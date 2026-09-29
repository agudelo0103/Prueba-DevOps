# -----------------------------------------------------------------------------
# Roles de DEPLOY, uno por ambiente. Solo los puede asumir un job que corre
# dentro del GitHub Environment correspondiente (sub = environment:<env>), y
# esos environments exigen rama main (+ aprobación manual en prod).
# -----------------------------------------------------------------------------

locals {
  # Servicios que Terraform administra en los stacks de ambiente.
  managed_services = [
    "ec2:*",
    "ecs:*",
    "elasticloadbalancing:*",
    "application-autoscaling:*",
    "cloudwatch:*",
    "logs:*",
    "wafv2:*",
    "sns:*",
  ]
}

data "aws_iam_policy_document" "deploy_trust" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_sub_prefix}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = var.environments

  name                 = "${var.project}-gha-deploy-${each.key}"
  description          = "GitHub Actions - terraform apply / deploy en ${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[each.key].json
  max_session_duration = 3600
}

# Lectura general: terraform necesita hacer refresh de todo lo que administra.
resource "aws_iam_role_policy_attachment" "deploy_readonly" {
  for_each = var.environments

  role       = aws_iam_role.deploy[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "deploy" {
  for_each = var.environments

  #checkov:skip=CKV_AWS_109:Acciones de servicio acotadas por región; ver README (ideal: cuentas separadas por ambiente).
  #checkov:skip=CKV_AWS_111:Acciones de servicio acotadas por región; ver README (ideal: cuentas separadas por ambiente).
  #checkov:skip=CKV_AWS_356:Varias acciones de ec2/ecs/elb no soportan restricción por ARN.
  #checkov:skip=CKV_AWS_290:Acciones de servicio acotadas por región; ver README.
  #checkov:skip=CKV_AWS_289:Acciones de servicio acotadas por región; ver README.
  #checkov:skip=CKV_AWS_355:Varias acciones de ec2/ecs/elb no soportan restricción por ARN.

  # 1. Servicios de infraestructura, solo en la región permitida.
  statement {
    sid       = "ManagedServicesInRegion"
    actions   = local.managed_services
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # 2. Parámetros SSM solo del propio ambiente (p. ej. el tag de imagen desplegado).
  statement {
    sid = "OwnSsmParameters"
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:GetParameter*",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project}/${each.key}/*"]
  }

  # 3. IAM: solo roles con el prefijo del ambiente y SIEMPRE con permissions
  #    boundary (evita escalamiento de privilegios desde el pipeline).
  statement {
    sid       = "CreateRolesOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:DeleteRolePolicy"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid = "ManageOwnRoles"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/${var.project}-${each.key}-*"]
  }

  statement {
    sid       = "PassOwnRolesToServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "ecs.application-autoscaling.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "NeverTouchBoundaries"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:PutRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:DeletePolicy"]
    resources = ["*"]
  }

  # 4. State remoto: solo la key de su propio ambiente.
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/envs/${each.key}/*"]
  }

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.terraform.arn]
  }

  # 5. ECR: login para todos; push solo desde dev (la imagen se construye una
  #    vez en dev y prod reutiliza exactamente el mismo digest).
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = each.key == "dev" ? [1] : []
    content {
      sid = "EcrPush"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      resources = [aws_ecr_repository.api.arn]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = var.environments

  name   = "terraform-deploy-${each.key}"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}

# -----------------------------------------------------------------------------
# Permissions boundary para los roles que crea el pipeline (task roles de ECS).
# Es el techo máximo de permisos: aunque alguien le agregue AdministratorAccess
# a un task role por código, el efecto real nunca supera esto.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "workload_boundary" {
  #checkov:skip=CKV_AWS_356:Boundary: define el techo; los permisos reales se acotan en cada rol.
  #checkov:skip=CKV_AWS_111:Boundary: define el techo; los permisos reales se acotan en cada rol.
  statement {
    sid = "AllowedWorkloadActions"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:PutMetricData",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "ssmmessages:*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadOwnSecrets"
    actions   = ["ssm:GetParameters", "ssm:GetParameter", "secretsmanager:GetSecretValue", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project]
    }
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${var.project}-workload-boundary"
  description = "Permissions boundary obligatorio para roles creados por el pipeline"
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
