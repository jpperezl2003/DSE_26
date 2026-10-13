# Lab4: ALB, Lambda, ElastiCache y RDS con Terraform

Configurado para AWS Academy Learner Lab, perfil `academy`, region `us-east-1`.
Conserva la organizacion de Lab2/Lab3 y su backend S3 `juanpablo.perez`, con una
clave independiente `lab4/terraform.tfstate`. No modifica los recursos anteriores.

## Arquitectura

Cliente -> ALB publico -> Lambda en VPC -> ElastiCache Redis (HIT)
                                      -> RDS PostgreSQL (MISS / BYPASS)

VPC propia con dos subredes publicas para ALB y dos privadas para Lambda/RDS/cache.
RDS y Redis solo aceptan conexiones del security group de Lambda. El ALB invoca
Lambda mediante permisos IAM; no establece una conexion TCP a su security group.
No hace falta NAT: el codigo consulta servicios dentro de la VPC. `LabRole` debe
permitir administracion de ENI y escritura de logs, y el perfil debe poder pasarlo.
Las restricciones concretas de Academy deben verificarse con `plan` y `apply`.

Usa una RDS db.t3.micro y un nodo cache.t3.micro para el laboratorio. Tener subredes
en dos AZ no hace redundantes estos nodos: esta configuracion no tiene alta
disponibilidad de datos. Para produccion se evaluarian RDS Multi-AZ, replica Redis
con failover, RDS Proxy y HTTPS. Aqui HTTP sirve solo datos sinteticos y el ALB
acepta HTTP desde cualquier IPv4 (`allowed_cidr = "0.0.0.0/0"`).

## Estrategia: cache-aside / lazy loading + TTL

1. Lambda busca `lab4:report:v1:<id>` en Redis.
2. **HIT**: devuelve el reporte sin abrir conexion con PostgreSQL.
3. **MISS**: consulta PostgreSQL, guarda el reporte y lo devuelve.
4. La clave expira en 300 segundos mas un jitter aleatorio de 0 a 30 segundos.
   La siguiente lectura vuelve a cargarla: eso es **lazy loading**, cargar bajo demanda.

Se eligio porque los reportes se leen repetidamente y los datos del lab son estaticos.
Solo se almacenan datos solicitados, con menor trabajo para RDS. El primer acceso
paga el costo de RDS y Redis; lazy loading no acelera ese primer acceso.

Write-through actualiza la cache al escribir: mejora lecturas posteriores, pero
agrega trabajo a cada escritura y puede cachear datos que nadie consultara.
Write-behind difiere la escritura a RDS y complica durabilidad; no conviene aqui.
Si se agregan escrituras, confirmar primero en RDS e invalidar la clave afectada;
las carreras entre lecturas y escrituras requieren versionado o coordinacion si
se exige consistencia estricta. TTL limita obsolescencia, no garantiza consistencia.

El lock Redis `SET NX EX` agrupa MISS concurrentes del mismo producto. El ganador
carga el reporte; los demas esperan y responden **COALESCED**. El lock usa token
unico y borrado condicional para no borrar el de otro proceso. TTL con jitter
reduce expiraciones simultaneas. Si Redis falla o la espera se agota, responde 503
para no sobrecargar la pequena RDS; es una decision de proteccion con costo de
disponibilidad. BYPASS existe explicitamente para la prueba comparativa.

## Preparacion y despliegue (PowerShell desde Lab4)

No pegues credenciales en archivos Terraform. El perfil temporal de Academy
debe incluir access key, secret key y session token, y renovarse cuando expire.

```powershell
aws sts get-caller-identity --profile academy --region us-east-1
Copy-Item terraform.tfvars.example terraform.tfvars
# allowed_cidr permite por defecto HTTP desde cualquier IPv4.
python build.py
terraform fmt -check
terraform init
terraform validate
terraform plan -out=lab4.tfplan
terraform apply lab4.tfplan
```

Usa `py build.py` si ese es tu lanzador Python. El empaquetado incluye pg8000,
redis y la CA oficial de RDS para verificar TLS. No instala paquetes en Lambda
durante una solicitud. Terraform necesita `build/lambda.zip` antes del plan.
El backend requiere que siga existiendo el bucket de Lab3 y permisos para su
prefijo lab4 y su archivo de bloqueo. El estado contiene contrasenas generadas:
no subirlo a Git ni publicarlo. `terraform init -backend=false` permite preparar
validacion local sin conectar el backend, pero no sustituye el init de despliegue.

```powershell
$alb = terraform output -raw alb_url
$fn = terraform output -raw lambda_name
terraform output seed_result
Invoke-RestMethod "$alb/report?id=1&cache=on"  # MISS
Invoke-RestMethod "$alb/report?id=1&cache=on"  # HIT
Invoke-RestMethod "$alb/report?id=1&cache=off" # BYPASS
```

`seed.tf` invoca Lambda automaticamente durante `terraform apply`, despues de
crear RDS y Lambda. El perfil academy necesita `lambda:InvokeFunction`.
La salida `seed_result` confirma el conteo de ventas y productos. Un error de
invocacion o conteo insuficiente hace fallar el despliegue. Seed crea 100,000 ventas
para 100 productos y un indice. No agrega sleeps a SQL para fingir mejoras.
Toda la creacion de tabla y carga de datos esta en `seed.sql`, incluido por
`build.py` en el paquete Lambda. Reempaquetar antes de cada plan si cambia el SQL.
Lambda lee y ejecuta ese archivo dentro de la VPC. No se necesita seed-event.json.
Seed es idempotente y solo accesible con InvokeFunction autenticado por IAM.
Ejecutarlo antes de la carga; no hay endpoints HTTP administrativos.

La carga se repite si cambia el SQL, el paquete Lambda o la instancia RDS.
No se ejecuta en cada apply sin cambios ni durante destroy. Las ventas existentes
no se duplican ni se sobrescriben. Para repetirla manualmente despues de un fallo:

```powershell
terraform apply -replace=aws_lambda_invocation.seed
```

No se ha verificado todavia la ejecucion real en AWS.

## Pruebas con wrk2

Proyecto oficial: https://github.com/giltene/wrk2 . El binario se llama `wrk`,
pero debe ser wrk2, que admite `-R`. Compilar/ejecutar en Linux o WSL.

```bash
git clone https://github.com/giltene/wrk2.git
cd wrk2
make
export WRK="$PWD/wrk"
# Volver a la carpeta Lab4 montada en WSL antes del siguiente comando.
bash load-test.sh http://DNS-DEL-ALB
```

El script usa el mismo dataset y consulta SQL en ambos modos. Precalienta los 100
productos, luego compara 10, 25, 50 y 100 solicitudes/segundo, 20 conexiones y
60 segundos por corrida. Guarda salidas en `results/`. Detener o reducir carga
si aparecen throttles o errores persistentes. Repetir al menos tres veces y
alternar el orden on/off para controlar cambios temporales y calentamiento.
wrk2 genera tasa constante y corrige coordinated omission en sus mediciones;
verificar siempre la tasa efectivamente alcanzada y errores, no solo latencia.

Para mostrar cache fria real, sin carga concurrente activa:

```powershell
aws lambda invoke --profile academy --region us-east-1 --function-name $fn --cli-binary-format raw-in-base64-out --payload file://clear-event.json clear-result.json
Invoke-RestMethod "$alb/report?id=1&cache=on"
Invoke-RestMethod "$alb/report?id=1&cache=on"
```

Cache vacia es un estado transitorio: al repetir claves aparecen HIT. Una corrida
`cache=off` representa ausencia sostenida de cache, no una cache fria que se calienta.
Separar ambos experimentos. Los cold starts de Lambda tampoco son cache MISS:
pueden existir aun si Redis ya tiene el dato. Mantener la prueba fria separada
de las mediciones con cache precalentada.

Registrar por corrida: tasa objetivo y real, p50/p95/p99, errores HTTP/socket,
HIT/MISS/COALESCED/BYPASS. Revisar CloudWatch Lambda Duration, Errors, Throttles y
ConcurrentExecutions; RDS CPUUtilization y DatabaseConnections; Redis CacheHits,
CacheMisses, Evictions y CPU. Los contadores Redis incluyen operaciones internas
del lock: usar los logs de la aplicacion para el hit ratio de reportes.

| Modo | RPS objetivo | RPS real | p50 | p95 | p99 | Errores | HIT % |
|---|---:|---:|---:|---:|---:|---:|---:|
| BYPASS | pendiente | | | | | | |
| Caliente | pendiente | | | | | | |

No prometer rendimiento ilimitado: definir antes de medir un criterio, por ejemplo
p95 < 200 ms, errores < 1% y tasa alcanzada >= 95% de la solicitada. Es un objetivo
de prueba, no un resultado observado. Reportar la mayor carga que lo cumple.
La latencia del cliente incluye internet y ALB; `elapsed_ms` solo mide el handler.
Para este dataset pequeno, la mejora puede ser modesta: reportar los datos reales.

Lambda escala concurrencia automaticamente, dentro de su cuota. El valor -1 usa
la cuota compartida; Academy puede impedir reservar concurrencia si su limite es
pequeno. Si se permite, fijar un limite acorde con conexiones de RDS. El lock
solo agrupa solicitudes del mismo producto y no protege BYPASS ni claves distintas.
Las conexiones SQL se cierran al terminar cada consulta, con timeout acotado;
para cargas mayores evaluar RDS Proxy y dimensionar la base.

## Alternativa: k6 desde PowerShell

`load-test.js` reemplaza el uso de los scripts wrk2 para estas pruebas. No requiere
WSL. k6 esta instalado localmente. Desde Lab4:

```powershell
New-Item -ItemType Directory -Force results | Out-Null
k6 run -e CACHE=off -e RPS=10 --summary-export results/k6-off-10.json load-test.js
k6 run -e CACHE=on -e RPS=10 --summary-export results/k6-on-10.json load-test.js
```

La URL HTTP del ALB actual viene como valor predeterminado. Si cambia, agregar
`-e BASE_URL=http://NUEVO-ALB` a cada comando. Cada corrida precalienta los 100
productos y luego mide 60 segundos, con 20 VUs preasignados y maximo 50. Cada
iteracion medida envia una solicitud. `CACHE=off` ignora Redis durante la medicion.
Para aumentar carga, repetir con RPS=25, 50 y 100, conservando el mismo valor en
los dos modos. Alternar orden y repetir para comparar resultados reproducibles.

Comparar `report_latency` (med=p50, p95, p99), `report_errors`, `report_requests`
y `cache_hit_ratio` (HIT / todas las solicitudes medidas). Los contadores
`cache_hits`, `cache_misses`, `cache_bypasses` y `cache_coalesced` excluyen respuestas
invalidas. Estas metricas personalizadas excluyen el precalentamiento; las metricas
HTTP globales de k6 tambien incluyen setup. Para tasa media de solicitudes
completadas usar report_requests.count / 60 si no hubo cola final; considerar
gracefulStop cuando la hubo. `dropped_iterations` indica solicitudes programadas
que no pudieron iniciarse: no afirmar que se sostuvo la carga si aparecen.

Los umbrales son objetivos de prueba (p95<200ms, errores<1%, cero iteraciones
descartadas). Un codigo de salida no cero por umbrales incumplidos es un resultado
de rendimiento fallido, no necesariamente un error del script. El precalentamiento
aborta si la API no devuelve los datos esperados. No mide la transicion fria:
esa prueba se realiza por separado con la accion clear.

Referencia: https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/

## Limpieza

```powershell
terraform plan -destroy
terraform destroy
```

Esto elimina los datos sinteticos: RDS no guarda snapshot final en esta configuracion.
Los recursos generan cargos contra el presupuesto de Academy mientras existen.

## Referencias

- https://aws.amazon.com/caching/best-practices/
- https://docs.aws.amazon.com/elasticloadbalancing/latest/application/lambda-functions.html
- https://docs.aws.amazon.com/lambda/latest/dg/python-package.html
- https://aws.amazon.com/lambda/faqs/
- https://github.com/giltene/wrk2

Estado de entrega: archivos preparados; despliegue y resultados de AWS pendientes
de verificar acceso al perfil academy y conectividad de herramientas.
