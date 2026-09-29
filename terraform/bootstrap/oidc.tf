# -----------------------------------------------------------------------------
# Federación GitHub Actions -> AWS con OIDC. No existen access keys: cada job
# recibe credenciales temporales de STS limitadas por repo, rama o environment.
# -----------------------------------------------------------------------------

# El proveedor OIDC es único por cuenta. Si ya existe (otro proyecto lo creó),
# se reutiliza en lugar de crearlo, para no afectar a terceros.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  github_owner      = split("/", var.github_repository)[0]
  github_repo_name  = split("/", var.github_repository)[1]
  oidc_sub_prefix   = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repository_id}"
}

# ---------------- Rol de PLAN (solo lectura) ----------------------------------
# Lo usan los PR (para comentar el plan) y la detección de drift en main.

data "aws_iam_policy_document" "plan_trust" {
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
      values = [
        "${local.oidc_sub_prefix}:pull_request",
        "${local.oidc_sub_prefix}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  description          = "GitHub Actions - terraform plan (solo lectura)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_extra" {
  # Leer el state y crear/liberar el lock file (use_lockfile) durante el plan.
  statement {
    sid       = "StateLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.terraform.arn]
  }

  # Mínimo privilegio: aunque ReadOnlyAccess es amplio, el plan nunca debe
  # poder leer valores de secretos.
  statement {
    sid       = "DenySecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  statement {
    sid     = "DenySecretParameters"
    effect  = "Deny"
    actions = ["ssm:GetParameter*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:${local.account_id}:parameter/${var.project}/*/secrets/*",
    ]
  }
}

resource "aws_iam_role_policy" "plan_extra" {
  name   = "terraform-state-and-guardrails"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_extra.json
}
