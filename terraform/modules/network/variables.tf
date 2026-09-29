variable "name" {
  description = "Prefijo de nombres (proyecto-ambiente)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs explícitas (conjunto cerrado y determinístico)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "Usa entre 2 y 3 AZs para alta disponibilidad."
  }
}

variable "single_nat_gateway" {
  description = "true = un solo NAT (más barato, para dev). false = un NAT por AZ (alta disponibilidad, para prod)."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retención de los VPC Flow Logs."
  type        = number
  default     = 30
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary obligatorio para los roles IAM creados."
  type        = string
}
