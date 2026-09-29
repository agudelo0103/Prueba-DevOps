## ¿Qué cambia y por qué?

<!-- Contexto del cambio y enlace al ticket -->

## Tipo de cambio

- [ ] Aplicación
- [ ] Infraestructura (Terraform)
- [ ] Pipeline / CI-CD

## Checklist

- [ ] Revisé el **plan de Terraform** comentado en este PR (dev y prod)
- [ ] El plan **no destruye ni reemplaza** recursos críticos (o está justificado abajo)
- [ ] No hay secretos en el código (los valores sensibles van en Secrets Manager / SSM)
- [ ] Los checks de seguridad (Gitleaks, Trivy, Checkov) pasan o las excepciones están justificadas
- [ ] Tengo un plan de rollback

## Plan de rollback

<!-- ¿Cómo se revierte si algo sale mal? (revert del PR, tag anterior, etc.) -->
