output "cluster_name" {
  description = "Nombre del cluster ECS."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Nombre del service ECS."
  value       = aws_ecs_service.api.name
}

output "task_definition_arn" {
  description = "Revisión de task definition desplegada."
  value       = aws_ecs_task_definition.api.arn
}

output "log_group_name" {
  description = "Log group de la aplicación."
  value       = aws_cloudwatch_log_group.app.name
}
