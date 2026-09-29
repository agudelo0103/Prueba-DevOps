# -----------------------------------------------------------------------------
# Application Load Balancer: única puerta de entrada pública. Opcionalmente
# HTTPS (ACM) y WAF con reglas administradas de AWS.
# -----------------------------------------------------------------------------

locals {
  https_enabled = var.certificate_arn != null
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Entrada publica al ALB"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:El ALB es público por diseño; HTTP redirige a HTTPS cuando hay certificado.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = local.https_enabled ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS desde internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# El ALB solo puede hablar con la VPC y en el puerto de la app.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Hacia los contenedores"
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
}

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_20:Sin certificado/dominio en la prueba; con certificate_arn HTTP redirige a HTTPS.
  #checkov:skip=CKV_AWS_91:Access logs del ALB fuera de alcance por costo (recomendado en producción real).
  #checkov:skip=CKV2_AWS_28:WAF controlado por variable enable_waf (activo en prod).
  #checkov:skip=CKV2_AWS_76:WAF opcional por variable; cuando está activo incluye KnownBadInputs (Log4j), ver CKV_AWS_192.
  #checkov:skip=CKV_AWS_150:Deletion protection controlada por variable (activa en prod).
  name                       = "${var.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS termina en el ALB; ALB->tarea viaja por red privada de la VPC restringida por SG.
  name                 = "${var.name}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip" # requerido por Fargate (awsvpc)
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Sin certificado: HTTP reenvía a la app. Con certificado: HTTP -> 301 HTTPS.
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:HTTP solo cuando no hay certificado; con certificate_arn redirige a HTTPS.
  #checkov:skip=CKV_AWS_103:TLS aplica en el listener HTTPS.
  #checkov:skip=CKV2_AWS_74:TLS aplica en el listener HTTPS.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------- WAF (opcional) ----------------------------------

resource "aws_wafv2_web_acl" "this" {
  #checkov:skip=CKV2_AWS_31:Logging del WAF fuera de alcance por costo.
  count = var.enable_waf ? 1 : 0

  name  = "${var.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # OWASP Top 10 genérico
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Entradas maliciosas conocidas (incluye Log4j / CVE-2021-44228)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # IPs con mala reputación según AWS
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
