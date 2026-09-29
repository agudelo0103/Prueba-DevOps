variable "name" {
  description = "Prefijo de nombres (proyecto-ambiente)."
  type        = string
}

variable "environment" {
  description = "Nombre del ambiente (dev, prod...)."
  type        = string
}

variable "vpc_id" {
  description = "VPC del servicio."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subredes privadas donde corren las tareas."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Único origen permitido hacia las tareas."
  type        = string
}

variable "target_group_arn" {
  description = "Target group del ALB."
  type        = string
}

variable "alb_arn_suffix" {
  description = "Sufijo ARN del ALB (métrica ALBRequestCountPerTarget)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Sufijo ARN del target group (métrica ALBRequestCountPerTarget)."
  type        = string
}

variable "container_image" {
  description = "Imagen completa (repo:tag) a desplegar."
  type        = string
}

variable "app_version" {
  description = "Versión/tag desplegado, expuesto a la app como APP_VERSION."
  type        = string
}

variable "container_port" {
  description = "Puerto del contenedor."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU de la tarea (unidades Fargate: 256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memoria de la tarea en MiB."
  type        = number
  default     = 512
}

variable "min_capacity" {
  description = "Mínimo de tareas (también el desired inicial)."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Máximo de tareas del autoscaling."
  type        = number
  default     = 3

  validation {
    condition     = var.max_capacity >= 1
    error_message = "max_capacity debe ser al menos 1."
  }
}

variable "cpu_target_percent" {
  description = "Objetivo de CPU promedio para target tracking."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Objetivo de solicitudes por tarea (ALBRequestCountPerTarget, por minuto)."
  type        = number
  default     = 500
}

variable "use_fargate_spot" {
  description = "Usa FARGATE_SPOT como capacidad principal (ahorro en ambientes no productivos)."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "Nivel de Container Insights: disabled, enabled o enhanced."
  type        = string
  default     = "disabled"
}

variable "log_retention_days" {
  description = "Retención de logs de la aplicación."
  type        = number
  default     = 30
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary obligatorio para los roles IAM creados."
  type        = string
}

variable "alarm_actions" {
  description = "ARNs (SNS) a notificar cuando una alarma se dispara."
  type        = list(string)
  default     = []
}
