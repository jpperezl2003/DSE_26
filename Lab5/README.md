# Lab5 - Inventario RFID con ClickHouse OLAP y Grafana en EC2

Sensores Python -> Kinesis -> Lambda (VPC) -> ClickHouse -> consultas Grafana.
Una EC2 Amazon Linux 2023 t3.medium ejecuta ClickHouse y Grafana para este laboratorio.
Grafana se actualiza cada 30 segundos. No se utiliza Redshift ni se crean recursos IAM.

## Archivos
- main.tf: Kinesis existente, Lambda, logs y trigger por lotes.
- iam.tf: lee LabRole y LabInstanceProfile ya existentes, sin modificarlos.
- network.tf: VPC, subred privada de Lambda, subred publica EC2 y ruta Internet.
- database.tf: conexion privada por security groups, puerto 8123.
- grafana.tf: EC2, EIP, provisioning datasource y dashboard.
- grafana/user-data.sh.tftpl: instala ambos servicios, crea esquema y usuarios SQL.
- sql/schema.sql: tabla ReplacingMergeTree y vistas OLAP.
- lambda/handler.py: validacion y POST JSONEachRow a ClickHouse.
- scripts/simulate.py: generador RFID; tests/: pruebas sin AWS.

## Adaptacion al laboratorio
LabRole debe permitir Lambda, ENIs de Lambda en VPC, lectura de Kinesis y CloudWatch Logs.
LabInstanceProfile debe contener el rol y permitir Session Manager en EC2.
Que existan no demuestra que todos esos permisos esten habilitados; si falla una accion,
requiere habilitacion del docente. La identidad de Terraform necesita iam:PassRole y
permisos EC2/VPC/EIP, Lambda, Kinesis y lectura de los recursos IAM existentes.
El laboratorio no permitia Redshift Serverless ni iam:CreateRole: eliminamos ambos.
Kinesis se conserva con 1 shard, 24 horas y sin cifrado KMS. Terraform ignora cambios de
retencion para no invocar la operacion bloqueada. prevent_destroy protege el stream existente.
La Lambda no necesita NAT: AWS gestiona el polling de Kinesis y el codigo solo llama la
IP privada de ClickHouse. Ningun puerto de base de datos se abre a Internet.

## Preparacion
Conserva tu terraform.tfvars y las credenciales temporales AWS vigentes.
Elimina redshift_capacity si quedo en tfvars y usa grafana_instance_type="t3.medium".
Configura grafana_allowed_cidr con tu IP publica real y /32.
```powershell
aws sts get-caller-identity
terraform init
terraform validate
terraform plan -out=lab5.tfplan
terraform apply lab5.tfplan
```
No reutilices planes anteriores. No borres terraform.tfstate ni sus copias.
El plan puede eliminar security group/subredes sobrantes de Redshift; no debe reemplazar
Kinesis. Tras el fallo parcial, el stream aparecia tainted: se verifico su ID y se ejecuto
terraform untaint para conservar el stream ACTIVE confirmado por AWS.
Si trabajas con otra copia del estado y sigue tainted, confirma que el stream esta ACTIVE,
revisa terraform state list y ejecuta terraform untaint aws_kinesis_stream.inventory.
Si el stream existe pero no figura en ese estado, importalo en vez de crearlo nuevamente:
```powershell
terraform import aws_kinesis_stream.inventory lab5-inventario-events
```
Haz el import solo si ese recurso no esta ya registrado en tu estado.

## Despues del apply
1. Consola AWS > EC2 > lab5-inventario-grafana > Connect > Session Manager.
   El script instala ClickHouse y Grafana automaticamente; puede tardar varios minutos.
```bash
sudo cloud-init status --wait
sudo systemctl status clickhouse-server grafana-server --no-pager
sudo cat /etc/grafana/admin-password
sudo clickhouse-client --query "SHOW TABLES FROM inventory"
```
2. Desde PowerShell obtén la URL:
```powershell
terraform output -raw grafana_dashboard_url
```
Abrela e inicia sesion con admin y la contrasena generada. Datasource y nueve paneles
se cargan automaticamente. No hay SSO, script de importacion ni credenciales AWS en Grafana.
3. Genera lecturas desde PowerShell en Lab5:
```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r scripts/requirements.txt
$stream = terraform output -raw stream_name
$region = terraform output -raw aws_region
.\.venv\Scripts\python.exe scripts/simulate.py --stream $stream --region $region --events 100 --interval 2
```
El productor necesita kinesis:PutRecord; ya no requiere KMS. Cada ejecucion usa RFID nuevas.
4. Mantén Grafana en Last 6 hours y refresco 30s. Veras entradas, salidas, stock y retraso.

## Verificacion y diagnostico
En Session Manager puedes consultar directamente la base:
```bash
sudo clickhouse-client --query "SELECT * FROM inventory.inventory_stock"
sudo clickhouse-client --query "SELECT * FROM inventory.daily_movements ORDER BY day DESC LIMIT 20"
sudo tail -n 100 /var/log/cloud-init-output.log
sudo journalctl -u clickhouse-server -u grafana-server -n 100 --no-pager
```
En PowerShell:
```powershell
$function = terraform output -raw lambda_name
aws logs tail "/aws/lambda/$function" --since 10m --region $region
```
Si Grafana no abre, verifica tu IP /32 y la instalacion de cloud-init.
Si Lambda falla, revisa el permiso ENI/Kinesis/logs de LabRole y los logs del POST.
La EC2 puede existir antes de terminar bootstrap: errores iniciales de conexion se reintentan.
Si el laboratorio no permite Session Manager, requiere habilitacion; no se abre SSH.

## Modelo OLAP y reglas
raw_events usa ReplacingMergeTree(ingested_at), ordenado por event_id.
fact_movements consulta FINAL para deduplicar incluso antes de los merges de fondo.
Un event_id debe identificar siempre el mismo evento; se conserva su ultima copia.
inventory_stock usa el ultimo movimiento de cada RFID/almacen segun occurred_at y luego
agrupa por producto. daily_movements calcula entradas y salidas deduplicadas por dia.
La condicion stock bajo es stock < minimum_stock (3 por defecto), calculada en Grafana.
Lambda valida campos, longitudes, movimiento y fecha con zona horaria. Descarta lecturas
invalidas con logs. Los errores HTTP retornan el lote para reintento.
No es un sistema de reservas ni validacion transaccional de salidas; analiza lecturas observadas.
El reloj del sensor debe ser correcto. Un fallo persistente puede bloquear el shard hasta
expirar la retencion (24 horas); para produccion agregar alarmas y destino de fallos.

## Seguridad, persistencia y costos
El usuario ingestor no usa contrasena para este laboratorio; solo tiene INSERT sobre la
tabla y admite direcciones de la VPC. El security group solo admite 8123 desde el grupo
de Lambda. El usuario administrador queda restringido a localhost. Grafana usa un usuario
local de solo lectura; el plugin admite cambiar max_execution_time sin permitir escrituras.
HTTP interno sin TLS es una simplificacion de laboratorio; produccion requiere autenticacion
y TLS. La web de Grafana usa contrasena aleatoria y solo admite tu IP, por HTTP en puerto 3000.
IMDSv2 obligatorio, disco cifrado y EIP estable. No se instalan claves AWS en las aplicaciones.

ClickHouse y Grafana comparten una sola EC2 (sin alta disponibilidad). ClickHouse tiene
limite de memoria de 2 GiB; la instancia tiene al menos 4 GiB. Los datos y ajustes viven
en el disco raiz de 24 GiB: reemplazar o destruir la EC2 los elimina. Exporta datos antes
de hacerlo si los necesitas. Cambios en user-data/provisioning fuerzan reemplazo de EC2.
El JSON se provisiona como archivo; las ediciones manuales no son la fuente de verdad.
La EC2 instala versiones estables disponibles de los repositorios oficiales.
EC2/EBS, IPv4/EIP y Kinesis generan cargos aunque no haya simulacion.

Para destruir todo, primero cambia prevent_destroy=false en main.tf (proteccion de Kinesis),
revisa un plan de destruccion y ejecuta terraform destroy. Esto elimina historial y stream.
No borres .terraform.lock.hcl ni el estado para solucionar errores.

## Pruebas
```powershell
python -B -m unittest discover -s tests -v
```
Las pruebas verifican normalizacion, formato JSON e informacion de reintento.
Terraform validate no comprueba los permisos de LabRole ni ejecuta el SQL real:
la instalacion y consultas ClickHouse deben comprobarse tras el apply.

Referencias:
https://clickhouse.com/docs/install/redhat
https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/configure/
