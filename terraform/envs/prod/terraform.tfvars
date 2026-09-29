# Prod: alta disponibilidad y seguridad reforzada.
# NAT por AZ, Fargate on-demand, mínimo 2 tareas (una por AZ), WAF y
# protección contra borrado.
environment        = "prod"
vpc_cidr           = "10.20.0.0/16"
single_nat_gateway = false

task_cpu         = 512
task_memory      = 1024
min_capacity     = 2
max_capacity     = 10
use_fargate_spot = false

enable_waf                 = true
enable_deletion_protection = true
container_insights         = "enhanced"
log_retention_days         = 90

# Con dominio propio se define el certificado ACM y el ALB pasa a HTTPS:
# certificate_arn = "arn:aws:acm:us-east-1:<account>:certificate/<id>"
