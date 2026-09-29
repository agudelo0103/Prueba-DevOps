# -----------------------------------------------------------------------------
# Servicio ECS Fargate: cluster, task definition endurecida, service con
# rollback automático y autoscaling por target tracking.
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

locals {
  container_name = "api"
}

resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_158:Cifrado por defecto de CloudWatch Logs; CMK opcional por costo.
  #checkov:skip=CKV_AWS_338:Retención configurable por ambiente.
  name              = "/ecs/${var.name}/api"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights configurable por ambiente (activo en prod, apagado en dev por costo).
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }
}

# ---------------------------- IAM ---------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: lo usa el agente de ECS para descargar la imagen y escribir logs.
resource "aws_iam_role" "execution" {
  name                 = "${var.name}-task-execution"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: identidad de la aplicación. Hoy no necesita permisos de AWS;
# cualquier permiso futuro se agrega aquí, acotado y bajo el boundary.
resource "aws_iam_role" "task" {
  name                 = "${var.name}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

# ---------------------------- Red ---------------------------------------------

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "Tareas ECS: solo aceptan trafico del ALB"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-tasks" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "Solo desde el ALB"
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS saliente (ECR, CloudWatch, APIs de AWS) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ---------------------------- Task definition ---------------------------------

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # Los valores por defecto que AWS agrega (hostPort, listas vacías) se declaran
  # explícitamente; si no, cada plan detecta una diferencia y recrea la task
  # definition (drift perpetuo y un despliegue innecesario en cada apply).
  container_definitions = jsonencode([{
    name                   = local.container_name
    image                  = var.container_image
    essential              = true
    readonlyRootFilesystem = true
    privileged             = false
    user                   = "10001"
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    mountPoints    = []
    volumesFrom    = []
    systemControls = []
    environment = [
      { name = "APP_ENV", value = var.environment },
      { name = "APP_VERSION", value = var.app_version },
    ]
    linuxParameters = {
      capabilities = { add = [], drop = ["ALL"] }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

# ---------------------------- Service -----------------------------------------

resource "aws_ecs_service" "api" {
  name                   = "${var.name}-api"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = var.min_capacity
  enable_execute_command = false # Zero Trust: sin shell a los contenedores
  propagate_tags         = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # Rolling update sin caída: primero sube las tareas nuevas y luego baja las viejas.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  # Si la versión nueva no queda sana, ECS vuelve solo a la anterior.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # terraform apply espera a que el despliegue termine (y falla si hubo rollback).
  wait_for_steady_state = true

  lifecycle {
    # El número de tareas lo gobierna el autoscaling, no Terraform.
    ignore_changes = [desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

# ---------------------------- Autoscaling -------------------------------------

resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

# Política 1: demanda real (solicitudes por tarea). Reacciona antes que el CPU.
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-requests-per-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${var.target_group_arn_suffix}"
    }
  }
}

# Política 2: protección por CPU. Gana la que pida más capacidad.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ---------------------------- Alarmas -----------------------------------------

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name}-api-5xx"
  alarm_description   = "La API está respondiendo errores 5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-api-unhealthy-hosts"
  alarm_description   = "Hay tareas que no pasan el health check del ALB"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

# CPU alta sostenida = el autoscaling no está alcanzando (¿max_capacity bajo?
# ¿cuello de botella fuera del contenedor?).
resource "aws_cloudwatch_metric_alarm" "cpu_sustained_high" {
  alarm_name          = "${var.name}-api-cpu-sustained-high"
  alarm_description   = "CPU > 85% por 15 minutos: el autoscaling no está absorbiendo la carga"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.api.name
  }
}
