variable "name" {
  description = "Prefijo de nombres (proyecto-ambiente)."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se crea el ALB."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (destino permitido del tráfico del ALB)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subredes públicas para el ALB."
  type        = list(string)
}

variable "app_port" {
  description = "Puerto donde escucha el contenedor."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Ruta del health check del target group."
  type        = string
  default     = "/health"
}

variable "certificate_arn" {
  description = "Certificado ACM. Si se define, se habilita HTTPS y HTTP redirige a HTTPS."
  type        = string
  default     = null
}

variable "enable_deletion_protection" {
  description = "Protege el ALB contra borrado accidental (prod)."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Asocia un WAF con reglas administradas de AWS y rate limiting."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Máximo de solicitudes por IP en 5 minutos antes de bloquear."
  type        = number
  default     = 2000
}
