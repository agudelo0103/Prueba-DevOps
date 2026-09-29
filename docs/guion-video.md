# Guion del video (≈ 15–20 min)

> Consejo: ten abiertas de antemano estas pestañas: el repo, un PR con el plan
> comentado, un run de CD completo, la consola de AWS (ECS, ALB, IAM) y el
> diagrama.

## 0. Introducción (1 min)
- Qué resuelve la propuesta: validar, aprobar, desplegar dev → prod, con seguridad, credenciales seguras, escalado y Zero Trust.
- Stack: GitHub Actions + Terraform + AWS ECS Fargate. **Todo está funcionando**, no es solo una presentación.

## 1. Diagrama de arquitectura (3 min) — `docs/diagram/arquitectura-aws.png`
- Recorrido de una solicitud: usuario → WAF → ALB (subred pública) → tareas Fargate (subred privada, 2 AZ).
- Las tareas **no tienen IP pública**; salen por NAT. Endpoint de S3 para ECR.
- Recursos compartidos: state S3 + KMS, ECR inmutable, roles OIDC.
- Mencionar que el diagrama es **código** (`arquitectura.py`) y se versiona.
- Mostrar también `pipeline-cicd.png`.

## 2. Código Terraform y aprobación (4 min)
- Estructura: `bootstrap/`, `modules/`, `envs/dev|prod` → mismo código, otros `tfvars` (mostrar la tabla dev vs prod).
- Mostrar `backend.tf` (state por ambiente, lock nativo) y un módulo (`ecs-service`: circuit breaker, autoscaling).
- **Demo:** abrir un PR con un cambio pequeño (por ejemplo, `max_capacity` de dev de 3 a 4):
  - checks: Gitleaks, TFLint, Checkov, validate;
  - **comentario del plan de dev y prod** en el PR;
  - CODEOWNERS pide revisión; el ruleset bloquea el merge sin `ci-ok`.
- Explicar: se aplica **el plan guardado**, no uno nuevo.

## 3. Despliegue DEV → PROD (3 min)
- Hacer merge y mostrar el run de CD: build + Trivy → push ECR `:sha` → apply dev → smoke test.
- Abrir la URL de dev: `/version` muestra el SHA del commit.
- Job de prod: **"Waiting for review"** → aprobar. Explicar que el environment `prod` es el único que puede asumir el rol de prod.
- Nota: en esta prueba el apply de prod está apagado por costos (`PROD_APPLY_ENABLED=false`); la aprobación y el plan sí corren.

## 4. Ramas, secretos y credenciales (2 min)
- Trunk-based: `main` + ramas cortas; los ambientes son etapas, no ramas.
- Mostrar en GitHub: **Settings → Secrets and variables**: no hay secretos de AWS, solo ARNs.
- Mostrar en IAM la **trust policy** del rol de prod (`sub = repo:...:environment:prod`).
- Permissions boundary; secretos de la app en Secrets Manager inyectados por ECS.

## 5. EC2 vs ECS vs EKS (1.5 min)
- Tabla comparativa; por qué ECS Fargate aquí; cuándo EKS o EC2.
- El módulo `ecs-service` es la pieza intercambiable.

## 6. Escalado (1.5 min)
- Target tracking doble (requests por tarea + CPU); cooldowns; min/max por ambiente; multi-AZ.
- Mostrar en la consola: ECS → service → Auto Scaling.

## 7. Seguridad (2 min)
- Tabla de controles por etapa. Mostrar la pestaña **Security** de GitHub (SARIF de Trivy y Checkov).
- Dockerfile endurecido, acciones fijadas por SHA, drift detection.

## 8. Casos prácticos (2 min)
- Caso 1: primero contener (rollback), luego buscar `replace`/`destroy` en el plan aplicado y CloudTrail.
- Caso 2: diferencias entre ambientes (rol/SCP, tfvars que solo usa prod, state, cuotas).
- Caso 3: ¿el cuello de botella es CPU? ¿la política está conectada? ¿max alcanzado? ¿tareas que no quedan sanas?

## Cierre (30 s)
- Siguientes pasos: una cuenta por ambiente, GuardDuty/Security Hub, firma de imágenes, HTTPS con dominio propio.
