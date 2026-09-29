locals {
  name = "${var.project}-${var.environment}"
}

# Recursos compartidos creados por el stack bootstrap.
data "aws_ecr_repository" "api" {
  name = "${var.project}-api"
}

data "aws_iam_policy" "workload_boundary" {
  name = "${var.project}-workload-boundary"
}

module "network" {
  source = "../../modules/network"

  name                     = local.name
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  single_nat_gateway       = var.single_nat_gateway
  flow_logs_retention_days = var.log_retention_days
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
}

module "alb" {
  source = "../../modules/alb"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  vpc_cidr                   = module.network.vpc_cidr
  public_subnet_ids          = module.network.public_subnet_ids
  certificate_arn            = var.certificate_arn
  enable_waf                 = var.enable_waf
  enable_deletion_protection = var.enable_deletion_protection
}

module "api" {
  source = "../../modules/ecs-service"

  name                     = local.name
  environment              = var.environment
  vpc_id                   = module.network.vpc_id
  private_subnet_ids       = module.network.private_subnet_ids
  alb_security_group_id    = module.alb.security_group_id
  target_group_arn         = module.alb.target_group_arn
  alb_arn_suffix           = module.alb.arn_suffix
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  container_image          = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
  app_version              = var.image_tag
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  min_capacity             = var.min_capacity
  max_capacity             = var.max_capacity
  use_fargate_spot         = var.use_fargate_spot
  container_insights       = var.container_insights
  log_retention_days       = var.log_retention_days
  permissions_boundary_arn = data.aws_iam_policy.workload_boundary.arn
  alarm_actions            = [aws_sns_topic.alarms.arn]
}

# ---------------------------- Alarmas -----------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------- Registro de versión -----------------------------
# Deja constancia de qué imagen está desplegada. El pipeline lo lee cuando un
# cambio es solo de infraestructura, para no cambiar la versión de la app.

resource "aws_ssm_parameter" "image_tag" {
  #checkov:skip=CKV2_AWS_34:No es un secreto; es el tag de la imagen desplegada.
  name        = "/${var.project}/${var.environment}/image-tag"
  description = "Tag de imagen desplegado actualmente en ${var.environment}"
  type        = "String"
  value       = var.image_tag

  depends_on = [module.api]
}
