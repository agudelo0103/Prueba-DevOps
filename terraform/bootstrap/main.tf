# -----------------------------------------------------------------------------
# Bootstrap: recursos base que se crean UNA sola vez (desde local, con un
# administrador) y que luego permiten que todo lo demás se haga por pipeline:
#   - Bucket S3 + KMS para el state remoto de Terraform.
#   - Proveedor OIDC de GitHub y roles IAM (plan y deploy por ambiente).
#   - Repositorio ECR compartido (build once, promote everywhere).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}"
}

# ---------------------------- KMS ---------------------------------------------

resource "aws_kms_key" "terraform" {
  description             = "Cifrado del state de Terraform y de ECR (${var.project})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "terraform" {
  name          = "alias/${var.project}-terraform"
  target_key_id = aws_kms_key.terraform.key_id
}

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Política de llave: la raíz de la cuenta delega en IAM (patrón estándar de AWS).
  #checkov:skip=CKV_AWS_111:Política de llave: la raíz de la cuenta delega en IAM (patrón estándar de AWS).
  #checkov:skip=CKV_AWS_356:En una key policy "*" se refiere a la propia llave.
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }
}

# ---------------------------- State bucket -------------------------------------

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Replicación entre regiones fuera de alcance para la prueba (recomendada en producción real).
  #checkov:skip=CKV_AWS_18:Access logging del bucket de state fuera de alcance; CloudTrail registra los accesos.
  #checkov:skip=CKV2_AWS_62:No se requieren notificaciones de eventos en el bucket de state.
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

# ---------------------------- ECR ----------------------------------------------

resource "aws_ecr_repository" "api" {
  name                 = "${var.project}-api"
  image_tag_mutability = "IMMUTABLE" # un tag = un build; no se puede sobrescribir

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.terraform.arn
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar solo las ultimas 30 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}
