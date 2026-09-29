# Dev: barato y desechable. Un NAT, Fargate Spot, 1-3 tareas, sin WAF.
environment        = "dev"
vpc_cidr           = "10.10.0.0/16"
single_nat_gateway = true

task_cpu         = 256
task_memory      = 512
min_capacity     = 1
max_capacity     = 3
use_fargate_spot = true

container_insights = "disabled"
log_retention_days = 14
