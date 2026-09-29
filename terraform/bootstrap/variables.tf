variable "project" {
  description = "Prefijo de nombres para todos los recursos."
  type        = string
  default     = "prueba-devops"
}

variable "aws_region" {
  description = "Región principal."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "Repositorio de GitHub (owner/repo) autorizado a asumir los roles vía OIDC."
  type        = string
  default     = "agudelo0103/Prueba-DevOps"
}

variable "environments" {
  description = "Ambientes que tendrán un rol de despliegue propio."
  type        = set(string)
  default     = ["dev", "prod"]
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub (false si ya existe en la cuenta)."
  type        = bool
  default     = true
}
