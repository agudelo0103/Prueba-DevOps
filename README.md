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
#    APPLY_ENABLED=true|false (por environment), ruleset en main con check "ci-ok".

# 3. Abrir un PR → CI. Merge → CD despliega dev y espera aprobación para prod.
```

## Probar localmente

```bash
cd app && pip install -r requirements-dev.txt && pytest -q
docker build -t api app && docker run --read-only -p 8080:8080 api
curl localhost:8080/health
```

## Destruir un ambiente (control de costos)

Desde el pipeline, sin credenciales locales:

1. **Actions → Destroy → Run workflow**
2. `environment`: `dev` o `prod` · `destroy`: ✅ (true) · `confirm`: escribir el nombre del ambiente
3. Etapas: **validate** (destroy=true, confirmación, rama main) → **plan -destroy** (rol de solo lectura; en el resumen se ve qué se borrará) → **destroy** (en el environment del ambiente; prod exige aprobación). Al final publica la lista de recursos eliminados y verifica en AWS, por tags, que no quede nada.
4. Poner `APPLY_ENABLED=false` en el environment para que el próximo merge no lo vuelva a crear:
   ```bash
   gh variable set APPLY_ENABLED -e dev -b false
   ```

Para volver a levantarlo: `APPLY_ENABLED=true` y ejecutar **CD → Run workflow**.

> Prod tiene `deletion_protection` en el ALB: antes de destruir prod hay que desactivarla con un PR (`enable_deletion_protection = false`). Esa fricción es intencional.

## Ver qué hay desplegado en cada ambiente

- **Resumen de cada run de CD** (job `apply (<env>)`): inventario por módulo y lista completa del state de Terraform, más los recursos reales en AWS con tags `Project`/`Environment`.
- **Comentario del plan en cada PR:** qué se va a crear, cambiar o destruir en dev y prod.
- **Localmente:** `terraform -chdir=terraform/envs/dev state list`.
