output "state_bucket" {
  description = "Bucket del state remoto."
  value       = aws_s3_bucket.state.bucket
}

output "kms_key_arn" {
  description = "KMS usado para el state."
  value       = aws_kms_key.terraform.arn
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR de la API."
  value       = aws_ecr_repository.api.repository_url
}

output "plan_role_arn" {
  description = "Rol OIDC de solo lectura para terraform plan."
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arns" {
  description = "Rol OIDC de despliegue por ambiente."
  value       = { for env, role in aws_iam_role.deploy : env => role.arn }
}

output "workload_boundary_arn" {
  description = "Permissions boundary obligatorio para roles de workloads."
  value       = aws_iam_policy.workload_boundary.arn
}
