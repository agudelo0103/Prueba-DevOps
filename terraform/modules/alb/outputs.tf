output "dns_name" {
  description = "DNS público del ALB."
  value       = aws_lb.this.dns_name
}

output "arn_suffix" {
  description = "Sufijo del ARN del ALB (para métricas de CloudWatch)."
  value       = aws_lb.this.arn_suffix
}

output "security_group_id" {
  description = "SG del ALB (origen permitido hacia los contenedores)."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group de la aplicación."
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "Sufijo del ARN del target group (para métricas y autoscaling)."
  value       = aws_lb_target_group.app.arn_suffix
}

output "url" {
  description = "URL base de la aplicación."
  value       = "${local.https_enabled ? "https" : "http"}://${aws_lb.this.dns_name}"
}
