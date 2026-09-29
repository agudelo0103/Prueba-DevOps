variable "project" {
  description = "Nombre del proyecto (prefijo de recursos)."
  type        = string
  default     = "prueba-devops"
}

variable "environment" {
  description = "Nombre del ambiente."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment debe ser dev, qa o prod."
  }
}

variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Tag de la imagen a desplegar (SHA del commit). Lo inyecta el pipeline."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag debe ser un SHA de git (nunca 'latest')."
  }
}

# ---------------------------- Red ---------------------------------------------

variable "vpc_cidr" {
  description = "CIDR de la VPC (no debe solaparse entre ambientes)."
  type        = string
}

variable "availability_zones" {
  description = "AZs a usar (2 o 3)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "single_nat_gateway" {
  description = "Un solo NAT (dev) o uno por AZ (prod)."
  type        = bool
}

# ---------------------------- Entrada -----------------------------------------

variable "certificate_arn" {
  description = "Certificado ACM para HTTPS (null = solo HTTP)."
  type        = string
  default     = null
}

variable "enable_waf" {
  description = "Activa WAF en el ALB."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Protección contra borrado del ALB."
  type        = bool
  default     = false
}

# ---------------------------- Cómputo y escalado ------------------------------

variable "task_cpu" {
  description = "CPU por tarea (256 = 0.25 vCPU)."
  type        = number
}

variable "task_memory" {
  description = "Memoria por tarea (MiB)."
  type        = number
}

variable "min_capacity" {
  description = "Mínimo de tareas."
  type        = number
}

variable "max_capacity" {
  description = "Máximo de tareas."
  type        = number
}

variable "use_fargate_spot" {
  description = "Usar Fargate Spot."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "disabled | enabled | enhanced."
  type        = string
  default     = "disabled"
}

# ---------------------------- Observabilidad ----------------------------------

variable "log_retention_days" {
  description = "Retención de logs."
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Correo que recibe las alarmas (opcional)."
  type        = string
  default     = null
}
