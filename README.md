Infraestructura de Alta Disponibilidad en AWS con ECS, ALB, EFS y Cloud Map (Lab 2)
===================================================================================

Descripción del Proyecto
------------------------

Implementación de una infraestructura en AWS para hostear una app con Frontend PHP y MySQL, ambos en Amazon ECS (EC2), expuesta mediante Application Load Balancer con TLS y dominio.\
Se utiliza EFS para persistencia de datos, AWS Cloud Map para descubrimiento de servicios interno y CodePipeline + CodeBuild para CI/CD (con docker buildx a linux/amd64).

Arquitectura (flujo)
--------------------

Usuarios → Route 53 (FQDN) → ALB (HTTPS) → Target Group (IP:80) → ECS Service (frontend, 2 tasks) → ECS Service (MySQL, 1 task) → EFS (/var/lib/mysql)\
Descubrimiento interno: Cloud Map (pepitoDB → mysql-service-dubai)\
Imágenes: ECR (frontend-lab2, db-lab2)\
CI/CD: CodePipeline → CodeBuild → Deploy to ECS

Servicios AWS Utilizados
------------------------

-   Amazon ECS (EC2) -- Orquestación de contenedores (frontend & MySQL)

-   Amazon ECR -- Registry privado de imágenes Docker

-   Elastic Load Balancing (ALB) -- Balanceo HTTP/HTTPS (redirect 80→443)

-   AWS Certificate Manager (ACM) -- Certificado TLS *.ecastelnuovo.ownboarding.teratest.net

-   Amazon Route 53 -- Hosted zone + A/ALIAS y CNAME

-   Amazon EFS -- Persistencia para MySQL (/var/lib/mysql)

-   AWS Cloud Map -- Service discovery DNS (MySQL)

-   VPC + Subnets + NAT + IGW -- Red multi-AZ

-   Amazon CloudWatch Logs -- Logs de contenedores

-   AWS CodePipeline + CodeBuild -- CI/CD (buildx)

* * * * *

Configuración Técnica
---------------------

### 1\. Networking (VPC)

-   VPC:  php-sample-vpc (vpc-0d0eed0237ec15bfc) -- CIDR 10.0.0.0/16 -- DNS hostnames/resolution: Enabled

-   Subnets

-   Públicas: 10.0.1.0/24 (1a), 10.0.2.0/24 (1b)

-   Privadas: 10.0.3.0/24 (1a), 10.0.4.0/24 (1b)

-   Route tables

-   Pública → 0.0.0.0/0 → igw-0f83d0bccf2145ab4

-   Privada → 0.0.0.0/0 → nat-0c5e14771a0068db1

-   IGW & NAT

### 2\. Security Groups (resumen efectivo)

-   php-sample-alb-sg

-   Inbound: 80/443 desde 0.0.0.0/0

-   Outbound: All

-   php-sample-ecs-tasks-sg (frontend)

-   Inbound: 80/TCP  desde  php-sample-alb-sg

-   Outbound: All (+ explícito 3306 → php-sample-mysql-sg)

-   php-sample-mysql-sg (db)

-   Inbound: 3306/TCP  desde  php-sample-ecs-tasks-sg

-   Outbound: All

-   mysql-efs-sg (EFS)

-   Inbound: 2049/TCP  desde  php-sample-mysql-sg

-   Outbound: All

### 3\. ECR (repos & build)

-   Repos:

-   frontend-lab2 → tags: latest, a5949eb (~1.46 GB)

-   db-lab2 → tag: latest (~183 MB)

-   Comandos (buildx, Mac ARM → linux/amd64)

docker buildx build --platform linux/amd64 -f Dockerfile

  -t 979244568430.dkr.ecr.us-east-1.amazonaws.com/frontend-lab2:latest --push .

docker buildx build --platform linux/amd64 -f db/Dockerfile

  -t 979244568430.dkr.ecr.us-east-1.amazonaws.com/db-lab2:latest --push .

### 4\. ECS --- Task Definitions

-   Frontend --- frontend-task-lab2:5

-   OS/Arch: Linux/x86_64, awsvpc

-   Imagen: .../frontend-lab2:a5949eb

-   Puerto: 80/TCP (App protocol HTTP)

-   Environment:  DB_HOST=mysql-service-dubai.pepitoDB (Cloud Map)

-   Logs: CloudWatch /ecs/frontend-task-lab2

-   MySQL --- mysql-task-dubai:2

-   OS/Arch: Linux/x86_64, awsvpc

-   Imagen: .../db-lab2@sha256:ecf76d...

-   Puerto: 3306/TCP

-   Volumen EFS:  fs-0e7798ddb9e1bb9f6 + Access Point  fsap-0f8967b33a18e1df6

-   Mount:  /var/lib/mysql

-   Logs: CloudWatch /ecs/mysql-task-dubai

### 5\. ECS --- Services & Placement

-   Frontend Service --- frontend-task-lab2

-   Desired: 2 (REPLICA)

-   Subnets: privadas 10.0.3.0/24 (1a) y 10.0.4.0/24 (1b)

-   SG:  php-sample-ecs-tasks-sg

-   Constraint:  distinctInstance

-   Target Group:  php-frontend-tg (IP, HTTP:80) --- 2 targets Healthy (1a/1b)

-   MySQL Service --- mysql-task-dubai

-   Desired: 1 (REPLICA)

-   Service discovery:  mysql-service-dubai @ pepitoDB (A, TTL 15s)

-   Instancia Healthy:  10.0.4.5

### 6\. EFS (persistencia)

-   FS:  fs-0e7798ddb9e1bb9f6 --- General Purpose, Throughput Elastic, Backups ON, Encrypted

-   Mount targets (estado actual):

-   us-east-1a → subnet privada 10.0.3.0/24

-   us-east-1b → subnet pública 10.0.2.0/24

-   SG en mounts:  php-sample-mysql-sg

Nota: Best practice: ambos mount targets en subnets privadas y SG propio de EFS (mysql-efs-sg con inbound 2049 desde php-sample-mysql-sg). Se deja documentado el estado actual por cercanía a la entrega.

### 7\. ALB / HTTPS

-   ALB:  php-sample-alb (internet-facing, IPv4) --- subnets públicas 1a/1b

-   Listeners

-   HTTP:80 → Redirect 301 a HTTPS:443

-   HTTPS:443 → Forward a php-frontend-tg --- Policy:  ELBSecurityPolicy-2016-08 --- Cert:  *.ecastelnuovo.ownboarding.teratest.net

### 8\. TLS / DNS

-   ACM: certificado Issued y In use

-   Route 53:

-   A (Alias)  ecastelnuovo.ownboarding.teratest.net → CloudFront

-   CNAME  alb.ecastelnuovo.ownboarding.teratest.net → <alb-dns>.elb.amazonaws.com

-   ALB DNS:  php-sample-alb-1219184588.us-east-1.elb.amazonaws.com

### 9\. CI/CD --- CodePipeline

-   Pipeline:  Source (GitHub via OAuth) → Build (CodeBuild) → Deploy (Amazon ECS) --- All actions succeeded

-   Build (buildx):

docker buildx build --platform linux/amd64 -f Dockerfile

  -t 979244568430.dkr.ecr.us-east-1.amazonaws.com/frontend-lab2:latest --push .

docker buildx build --platform linux/amd64 -f db/Dockerfile

  -t 979244568430.dkr.ecr.us-east-1.amazonaws.com/db-lab2:latest --push .

-   Deploy: acción de ECS actualizando el service frontend a la última task definition.

* * * * *

Pruebas de Validación
---------------------

-   Balanceo y salud: Target Group php-frontend-tg con 2 targets Healthy (IPs privadas en 1a/1b)

-   HTTPS:  HTTP:80 → 301 → HTTPS:443, certificado ACM válido

-   ECS Estado:  frontend 2/2 RUNNING, mysql 1/1 RUNNING

* * * * *

Consideraciones de Seguridad
----------------------------

-   TLS en el perímetro (ALB)

-   SGs en cadena: ALB → Frontend (80), Frontend → MySQL (3306), MySQL ↔ EFS (2049)

-   Outbound "All" (válido para el lab). Recomendación post-lab: restringir egress y mover EFS a subnets privadas con SG propio.

Monitoreo y Métricas
--------------------

-   CloudWatch Logs:  /ecs/frontend-task-lab2, /ecs/mysql-task-dubai

-   ALB:  RequestCount, HTTPCode_Target_2XX, TargetResponseTime

-   ECS:  CPUUtilization, MemoryUtilization, RunningTaskCount

Desvíos vs Requisitos
---------------------

-   Parameter Store (requisito):  No utilizado. Se usó Cloud Map para DB_HOST y variables de entorno para credenciales.

-   EFS (AZ 1b): mount target en subnet pública y SG de MySQL; se documenta como estado actual.

* * * * *

Entregables / URLs
------------------

-   ALB (DNS):  php-sample-alb-1219184588.us-east-1.elb.amazonaws.com

-   Dominio:  ecastelnuovo.ownboarding.teratest.net

-   Alias directo al ALB:  alb.ecastelnuovo.ownboarding.teratest.net

-   ECR:

-   979244568430.dkr.ecr.us-east-1.amazonaws.com/frontend-lab2

-   979244568430.dkr.ecr.us-east-1.amazonaws.com/db-lab2

-   ECS Cluster:  cluster-lab2 --- Services: frontend-task-lab2 (rev 5), mysql-task-dubai (rev 1)

-   EFS:  fs-0e7798ddb9e1bb9f6

Información del Proyecto
------------------------

-   Autor: Ezequiel Castelnuovo

-   Fecha de Implementación: Noviembre 2025

-   Repositorio:  https://github.com/ezequielcastelnuovo