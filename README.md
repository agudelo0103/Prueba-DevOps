# Prueba DevOps

[![CI](https://github.com/agudelo0103/Prueba-DevOps/actions/workflows/ci.yml/badge.svg)](https://github.com/agudelo0103/Prueba-DevOps/actions/workflows/ci.yml)
[![CD](https://github.com/agudelo0103/Prueba-DevOps/actions/workflows/cd.yml/badge.svg)](https://github.com/agudelo0103/Prueba-DevOps/actions/workflows/cd.yml)

Plataforma de referencia: **GitHub Actions + Terraform + AWS (ECS Fargate)**, con aprobaciones, seguridad integrada, credenciales OIDC y principios Zero Trust.

| Entregable | Documento |
|-----------|-----------|
| Fase 1: preguntas conceptuales | [fase1-respuestas.md](fase1-respuestas.md) |
| Fase 2: propuesta de pipeline y arquitectura (+ casos prácticos) | [docs/fase2-propuesta.md](docs/fase2-propuesta.md) |
| Guion del video | [docs/guion-video.md](docs/guion-video.md) |

![Arquitectura](docs/diagram/arquitectura-aws.png)

## Cómo funciona (resumen)

```
feat/* ──PR──► CI: gitleaks · ruff/pytest · build+Trivy · fmt/validate/TFLint/Checkov · plan dev+prod (comentado)
                │  (ruleset: PR obligatorio + CODEOWNERS + check ci-ok)
                ▼
main ──► CD: build+Trivy → ECR :sha → apply dev → smoke test → plan prod → ⏸ aprobación → apply prod
```

- **Credenciales:** OIDC. No existe ninguna access key de AWS en GitHub.
- **State:** S3 + KMS + lock nativo, una key por ambiente.
- **Ambientes:** `terraform/envs/{dev,prod}`, con el mismo código, otros valores, otro rol y otro state.
- **Drift:** plan nocturno; si hay diferencias, se abre un issue.

## Puesta en marcha desde cero

```bash
# 1. Bootstrap (una sola vez, con credenciales de administrador)
cd terraform/bootstrap
# primera vez: comentar backend.tf, luego:
terraform init && terraform apply
terraform init -migrate-state        # mueve el state del bootstrap a S3

# 2. En GitHub: environments dev/prod (prod con revisores), variables
#    AWS_PLAN_ROLE_ARN (repo) y AWS_DEPLOY_ROLE_ARN (por environment),
#    PROD_APPLY_ENABLED=true|false, ruleset en main con check "ci-ok".

# 3. Abrir un PR → CI. Merge → CD despliega dev y espera aprobación para prod.
```

## Probar localmente

```bash
cd app && pip install -r requirements-dev.txt && pytest -q
docker build -t api app && docker run --read-only -p 8080:8080 api
curl localhost:8080/health
```

## Destruir (control de costos)

```bash
cd terraform/envs/dev
terraform destroy -var "image_tag=$(aws ssm get-parameter --name /prueba-devops/dev/image-tag --query Parameter.Value --output text)"
```
