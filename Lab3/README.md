# Lab3: EC2 Auto Scaling con ALB

Adaptación de Lab2: conserva Nginx, Amazon Linux 2023, la VPC y subredes predeterminadas, el perfil `academy`, la llave SSH generada y la organización de archivos.

## Escenario

Internet → ALB HTTP → Auto Scaling Group → entre 1 y 3 EC2.

- Capacidad inicial y mínima: 1; máxima: 3.
- CPU promedio objetivo: 50 %, configurable mediante `cpu_target`.
- Carga alta sostenida: AWS agrega capacidad hasta 3 instancias.
- Carga suficientemente baja y sostenida: AWS termina las adicionales hasta quedar en 1. Puede terminar la instancia original.
- Scale-in habilitado. AWS administra las alarmas y sus evaluaciones; la reducción no es inmediata al bajar de 50 %.
- Monitoreo detallado, calentamiento de 180 segundos y gracia de salud de 300 segundos.
- El ASG registra y elimina automáticamente los destinos del ALB.
- `ignore_changes` evita que Terraform restablezca la capacidad deseada después del escalado.

## Diferencias con Lab2

`main.tf` sustituye las dos EC2 fijas por un Launch Template, ASG y política de CPU. `backend.tf` usa la clave independiente `lab3/terraform.tfstate`, en el mismo bucket. La página Nginx muestra la IP y hostname del servidor que respondió. Las IP dinámicas se consultan en AWS, en lugar de usar outputs de instancias fijas.

Lab2 no se modifica. Se requieren la VPC predeterminada y sus subredes en las zonas `a` y `b` de la región elegida. Cambiar la región del proveedor no cambia la región del bucket en el backend.

## Desplegar

El ALB acepta HTTP desde cualquier IPv4 (`0.0.0.0/0`). Usa la URL del output para abrir la página o ejecutar k6 contra `/compute`; no necesitas configurar tu IP pública.

SSH está deshabilitado por defecto y no se utiliza para la prueba. Solo si deseas habilitarlo, agrega tu IPv4 pública real en `terraform.tfvars`:

```hcl
ssh_cidr = "TU_IP_PUBLICA/32"
```

HTTP a las EC2 solo se permite desde el ALB. Tanto la página como `/compute` son accesibles públicamente a través del ALB.

Desde PowerShell, dentro de Lab3:

```powershell
aws sts get-caller-identity --profile academy
terraform init
terraform fmt -check
terraform validate
terraform plan -out=lab3.tfplan
terraform apply lab3.tfplan
terraform output -raw load_balancer_url
```

Requiere credenciales `academy` vigentes, acceso al bucket existente y permisos para EC2, ELB, Auto Scaling y sus roles vinculados al servicio. AWS Academy puede restringir permisos o cuotas. No se ejecutaron plan ni apply al preparar estos archivos.

La llave `lab3-key.pem` se genera durante apply. La llave privada también se guarda en el estado: protege el bucket y no subas archivos PEM al repositorio.

## Aplicación y carga HTTP con k6

Flujo: k6 en tu computadora → ALB → Nginx → `/compute` → servicio Python en `127.0.0.1:8000`.

`/` sigue sirviendo la página estática y el health check. `/compute` calcula PBKDF2 SHA-256 con 200 000 iteraciones fijas y devuelve JSON con hostname, duración y resultado. No admite parámetros para aumentar el trabajo. El servicio usa un worker, adecuado para la t2.micro de 1 vCPU; cambiar a instancias con varias CPU requeriría adaptar los workers para utilizar toda su capacidad.

`app.py` se incluye en el user data del Launch Template mediante base64. El arranque instala Python y Nginx, crea el servicio systemd con usuario sin privilegios y verifica una respuesta del backend antes de iniciar Nginx. Las nuevas EC2 reciben automáticamente la aplicación. El servidor Python es para este laboratorio, no un servidor de aplicación de producción.

Si ya desplegaste una versión anterior, aplicar el Launch Template no actualiza las instancias existentes. Antes de k6, inicia un Instance Refresh desde la consola del ASG y espera su finalización. Revisa sus porcentajes de capacidad: mantener disponibilidad puede requerir una instancia temporal adicional; reemplazar primero la única instancia causa una interrupción. No se inicia ningún refresh automáticamente con este cambio. Durante la prueba no ejecutes un refresh.

Instala k6 siguiendo la [guía oficial para Windows](https://grafana.com/docs/k6/latest/set-up/install-k6/), y confirma `k6 version`. Desde la carpeta Lab3, después de desplegar:

```powershell
$alb = terraform output -raw load_balancer_url
Invoke-RestMethod "$alb/compute"
k6 run -e "BASE_URL=$alb" -e RATE=30 .\load-test.js
```

El script sube de 1 a 30 peticiones por segundo durante 1 minuto, mantiene 30 durante 8 minutos y baja a cero durante 1 minuto. La carga programada dura 10 minutos, más la comprobación inicial y hasta 15 segundos para terminar peticiones en curso. El regreso del ASG a una instancia ocurre después y puede requerir varios minutos adicionales; no se garantiza completar el ciclo 1 → 3 → 1 dentro de esos 10 minutos. Cada iteración envía una petición; se usan hasta 200 usuarios virtuales para sostener la tasa, independientemente del tiempo de respuesta. Puedes cambiar RATE entre 1 y 200. Ctrl+C interrumpe la prueba.

No se garantiza llegar a tres EC2 con RATE=30: ajusta según CPUUtilization. Si el promedio sigue por debajo del objetivo, repite con RATE=45 o RATE=60. Si observas muchos errores o timeouts, baja la tasa y espera a que las instancias nuevas estén saludables. `dropped_iterations` significa que el generador no logró iniciar toda la carga programada; revisa tiempos de respuesta y recursos locales. Los umbrales de error se evalúan al terminar, no abortan anticipadamente el escalado; un código de salida distinto de cero puede indicar que hubo más de 5 % de errores durante la saturación.

## Comprobar 1 → 3 → 1

```powershell
$asg = terraform output -raw autoscaling_group_name
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg --profile academy --region us-east-1 --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}'
aws ec2 describe-instances --filters "Name=tag:aws:autoscaling:groupName,Values=$asg" "Name=instance-state-name,Values=running" --profile academy --region us-east-1 --query 'Reservations[].Instances[].{Id:InstanceId,IP:PublicIpAddress}'
aws autoscaling describe-scaling-activities --auto-scaling-group-name $asg --profile academy --region us-east-1 --max-items 10
```

1. Confirma una instancia InService y un destino healthy; abre la URL del ALB.
2. Ejecuta k6 contra `/compute` como se indica arriba; no necesitas entrar en las EC2.
3. Observa CPUUtilization, capacidad deseada y actividades en AWS. El ALB distribuye automáticamente las peticiones entre los destinos saludables, incluidos los nuevos.
4. Espera a alcanzar tres instancias y registra la evidencia. Ajusta la tasa si la carga es insuficiente.
5. Deja terminar k6. Espera las evaluaciones y la estabilización; confirma el regreso a una instancia y un destino saludable. Puede tardar varios minutos después de finalizar la prueba.

T2 usa créditos: su agotamiento puede limitar la prueba; revisa CPUCreditBalance. Adapta la región de los comandos si cambias la configuración. El health check ligero comprueba Nginx, no garantiza que `/compute` siga funcionando: comprueba también los errores de k6. Un health check ligero no garantiza inmunidad frente a la saturación total de la máquina.

## Eliminar Lab3

```powershell
terraform plan -destroy
terraform destroy
```

La VPC, subredes y bucket existentes no se eliminan. ALB, EC2, EBS, IPv4 y métricas detalladas pueden generar costos. Este ejemplo usa HTTP; una sola instancia mínima no proporciona redundancia simultánea de cómputo.

Referencia: [Target tracking en AWS](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html).

Referencia k6: [Ramping arrival rate](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/ramping-arrival-rate/).
