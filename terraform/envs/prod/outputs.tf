output "app_url" {
  description = "URL pública de la API."
  value       = module.alb.url
}

output "ecs_cluster" {
  description = "Cluster ECS."
  value       = module.api.cluster_name
}

output "ecs_service" {
  description = "Service ECS."
  value       = module.api.service_name
}

output "deployed_image_tag" {
  description = "Tag de imagen desplegado."
  value       = var.image_tag
}
