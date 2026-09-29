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

# GitHub emite el claim "sub" con formato inmutable: incluye los IDs numéricos
# del dueño y del repo. Si el repo se borra y alguien crea otro con el mismo
# nombre, sus tokens NO sirven para asumir estos roles.
variable "github_owner_id" {
  description = "ID numérico del dueño del repositorio (gh api users/<owner> --jq .id)."
  type        = string
  default     = "79058858"
}

variable "github_repository_id" {
  description = "ID numérico del repositorio (gh api repos/<owner>/<repo> --jq .id)."
  type        = string
  default     = "1394061195"
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
