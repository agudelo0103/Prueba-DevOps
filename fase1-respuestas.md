# Prueba DevOps — Fase 1: Preguntas conceptuales

**Candidato:** Cristian Agudelo

> Respuestas cortas, con mis propias palabras y explicando el porqué.

---

## Bloque 1 — Experiencia práctica (CI/CD, AWS, Terraform, GitHub)

### 1. Cuéntame un pipeline real que hayas construido de punta a punta.

Construí un pipeline en GitHub Actions para una API en contenedores desplegada en AWS ECS Fargate:

1. **Pull Request:** lint, pruebas unitarias, análisis estático (SAST) y escaneo de dependencias. Si algo falla, el PR no se puede fusionar (branch protection).
2. **Build:** construcción de la imagen Docker, escaneo de la imagen con Trivy y push a Amazon ECR con el tag del SHA del commit (nunca `latest`, para tener trazabilidad y rollback).
3. **Deploy a dev:** al hacer merge a `main`, el workflow asume un rol de AWS por OIDC, registra una nueva *task definition* con la imagen nueva y actualiza el *service* de ECS. Espera a que el servicio quede estable (`wait services-stable`).
4. **Smoke tests** contra el endpoint de health del ALB.
5. **Deploy a prod:** el mismo artefacto (misma imagen, mismo SHA) se promueve a prod, protegido con un *GitHub Environment* que exige aprobación manual.
6. **Rollback:** ECS con *deployment circuit breaker* activado; si las tareas nuevas no pasan health checks, vuelve solo a la versión anterior.
7. **Notificación** del resultado a Slack/Teams.

La clave del diseño: **se construye una vez y se promueve el mismo artefacto** entre ambientes.

### 2. ¿Qué has desplegado en AWS con Terraform?

- **Red:** VPC con subredes públicas y privadas en varias AZ, NAT Gateway, route tables, Security Groups y VPC Endpoints (ECR, S3, CloudWatch, Secrets Manager) para que el tráfico no salga a internet.
- **Cómputo:** clústeres ECS Fargate (cluster, task definitions, services, autoscaling), ALB con target groups y listeners HTTPS con certificado de ACM.
- **Datos:** RDS (PostgreSQL) en subredes privadas, buckets S3 con cifrado, versionado y bloqueo de acceso público.
- **Seguridad e identidad:** roles y políticas IAM de mínimo privilegio, el *OIDC provider* de GitHub, KMS keys, Secrets Manager.
- **Observabilidad:** log groups de CloudWatch, alarmas y dashboards.
- **Backend de Terraform:** bucket S3 para el state (cifrado + versionado) con bloqueo.

Todo organizado en **módulos reutilizables** y un directorio de configuración por ambiente.

### 3. ¿Cómo integrabas GitHub con AWS?

Con **OIDC (OpenID Connect)**, sin access keys:

1. En AWS se crea un *Identity Provider* que confía en `token.actions.githubusercontent.com`.
2. Se crea un rol IAM cuya *trust policy* solo permite asumirlo a un repositorio, rama o environment específico (condición sobre el claim `sub`, por ejemplo `repo:org/repo:environment:prod`).
3. En el workflow se da el permiso `id-token: write` y se usa la acción `aws-actions/configure-aws-credentials` con el ARN del rol.
4. GitHub emite un token JWT de corta vida, AWS STS lo valida y devuelve **credenciales temporales** (expiran en minutos/1 hora).

Resultado: no hay secretos guardados en GitHub, y cada ambiente tiene su propio rol con permisos distintos.

### 4. ¿Qué controles de seguridad metías en el pipeline?

- **Secret scanning** (Gitleaks / GitHub secret scanning) para que no se suban credenciales.
- **SAST** (CodeQL / Semgrep) sobre el código de la aplicación.
- **SCA / dependencias** (Dependabot, Trivy) para librerías con CVEs conocidos.
- **Escaneo de IaC** (Checkov / tfsec / Trivy config) para detectar malas configuraciones en Terraform: buckets públicos, SG abiertos a `0.0.0.0/0`, recursos sin cifrar.
- **Escaneo de imágenes** de contenedor antes de publicarlas en ECR (y *scan on push* en ECR).
- **OIDC** con roles de mínimo privilegio en lugar de llaves estáticas.
- **Aprobaciones obligatorias** y branch protection (revisión por pares, checks obligatorios, CODEOWNERS).
- **Acciones de terceros fijadas por SHA** para evitar ataques de cadena de suministro.

---

## Bloque 2 — Conceptos de CI/CD y Terraform

### 5. ¿Cuál es la diferencia entre integración continua, entrega continua y despliegue continuo?

- **Integración continua (CI):** cada cambio que se integra al repositorio se compila y se prueba automáticamente. El objetivo es detectar errores temprano y que la rama principal siempre esté sana.
- **Entrega continua (Continuous Delivery):** además de CI, el software siempre queda **listo para desplegar** en producción, pero el paso a prod requiere una **decisión humana** (una aprobación, un botón).
- **Despliegue continuo (Continuous Deployment):** todo cambio que pasa las pruebas llega a producción **automáticamente**, sin intervención humana.

La diferencia entre las dos últimas es solo una: **quién aprieta el botón de producción**, una persona o el pipeline.

### 6. ¿Qué etapas mínimas tendría un pipeline serio para Terraform en GitHub? Explica la razón de cada paso.

| # | Etapa | Por qué |
|---|-------|---------|
| 1 | `terraform fmt -check` | Garantiza un estilo uniforme; facilita la revisión y evita diffs de ruido. |
| 2 | `terraform init` (backend remoto) | Descarga providers/módulos con versiones fijadas (lock file) y conecta al state remoto. |
| 3 | `terraform validate` | Detecta errores de sintaxis y referencias inválidas antes de tocar la nube. |
| 4 | **Linter** (TFLint) | Encuentra errores que validate no ve: tipos de instancia inexistentes, variables sin usar, malas prácticas del provider. |
| 5 | **Escaneo de seguridad** (Checkov / Trivy) | Bloquea configuraciones inseguras antes de que existan. |
| 6 | `terraform plan -out=tfplan` | Muestra exactamente qué se va a crear, cambiar o destruir. Se publica como comentario en el PR para que el revisor lo vea. |
| 7 | **Revisión y aprobación** | Una persona (CODEOWNER) valida el plan; en prod, aprobación por GitHub Environment. |
| 8 | `terraform apply tfplan` | Aplica **el plan aprobado**, no uno nuevo. Así se aplica exactamente lo que se revisó. |
| 9 | **Verificación post-deploy / detección de drift** | Confirma que el estado real coincide con el código (un `plan` que debe salir sin cambios). |

Adicional: **concurrencia controlada** (`concurrency` en el workflow + locking del state) para que dos applies no se pisen.

### 7. ¿Qué mejorarías en un proceso donde cualquier developer puede hacer merge a main y disparar apply directo a AWS?

Ese proceso tiene tres problemas: no hay revisión, no hay separación entre ambientes y cualquier error llega directo a la nube. Lo mejoraría así, paso a paso:

1. **Proteger `main`** (branch protection / rulesets): nada de push directo; todo entra por Pull Request. *Razón:* obliga a que cada cambio sea visible y revisable.
2. **Revisión obligatoria con CODEOWNERS:** al menos 1–2 aprobaciones y que el dueño del código de infraestructura apruebe. *Razón:* separación de funciones; quien escribe no es quien aprueba.
3. **Checks obligatorios en el PR:** fmt, validate, TFLint, Checkov y `plan`. Si fallan, no se puede fusionar. *Razón:* los errores se detectan antes del merge, no en AWS.
4. **Plan visible en el PR:** el resultado del `plan` se publica como comentario. *Razón:* el revisor aprueba el impacto real (qué se crea/destruye), no solo el código.
5. **Separar ambientes:** el merge a `main` despliega solo a **dev**; **prod** requiere un GitHub Environment con aprobadores definidos. *Razón:* se prueba primero en un ambiente sin impacto al cliente.
6. **Aplicar el plan guardado:** `apply` sobre el `tfplan` generado y aprobado. *Razón:* evita que entre la revisión y el apply cambie algo sin que nadie lo vea.
7. **Credenciales por OIDC con un rol por ambiente:** el rol de prod solo lo puede asumir el environment `prod`. *Razón:* aunque alguien modifique el workflow, no obtiene permisos de prod.
8. **Protección ante destrucción:** alertar o bloquear si el plan contiene `destroy` en recursos críticos, y usar `prevent_destroy` en recursos como bases de datos. *Razón:* un cambio pequeño no debe poder borrar datos.
9. **State remoto con bloqueo y versionado:** *Razón:* evita corrupciones por applies simultáneos y permite recuperar un state anterior.
10. **Auditoría:** CloudTrail + historial de despliegues en GitHub. *Razón:* saber quién cambió qué y cuándo.

### 8. ¿Qué entiendes por payload en integración entre herramientas?

El **payload** es el **contenido de datos** que una herramienta le envía a otra en una integración, normalmente en formato JSON dentro del cuerpo de una petición HTTP. Es "la carga útil": la información de negocio, sin contar encabezados ni metadatos del protocolo.

Ejemplo: cuando hago un push, GitHub envía un webhook cuyo payload incluye el repositorio, la rama, el SHA del commit, el autor y los archivos cambiados. La herramienta que lo recibe (un pipeline, Slack, Jenkins) lee ese payload para decidir qué hacer. Por seguridad, el receptor debe validar la **firma** del payload (`X-Hub-Signature-256`) para confirmar que realmente viene de GitHub.

### 9. Si un push a una rama debe disparar un despliegue en AWS, ¿cómo lo implementarías?

Con un workflow de GitHub Actions:

```yaml
on:
  push:
    branches: [main]          # solo esta rama despliega

permissions:
  id-token: write             # necesario para OIDC
  contents: read

concurrency: deploy-dev       # evita despliegues simultáneos

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev          # reglas y variables del ambiente
    steps:
      - uses: actions/checkout@<sha>
      - uses: aws-actions/configure-aws-credentials@<sha>
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - run: # build, push a ECR y actualización del servicio / terraform apply
```

Puntos clave: el disparador filtra por rama (y opcionalmente por `paths`), la autenticación es por OIDC con un rol limitado a esa rama/ambiente, hay control de concurrencia y el ambiente define las reglas (aprobación si es prod).

### 10. ¿Qué riesgos hay si GitHub Actions usa access keys estáticas para AWS?

- **No expiran:** si se filtran (en un log, en un fork, en una dependencia comprometida) sirven indefinidamente hasta que alguien las rote.
- **Rotación manual:** en la práctica casi nunca se rotan.
- **Suelen tener demasiados permisos:** se reutiliza una llave "que funciona" para todo.
- **Mayor superficie de exposición:** cualquier workflow o acción de terceros con acceso a los secretos puede exfiltrarlas.
- **Trazabilidad pobre:** en CloudTrail todo aparece como el mismo usuario IAM; es difícil saber qué pipeline o qué persona hizo el cambio.
- **Incumplimiento** de buenas prácticas y auditorías (CIS, Well-Architected).

La solución es **OIDC**: credenciales temporales, sin secretos guardados y limitadas por repo/rama/ambiente.

### 11. ¿Qué diferencia hay entre webhook, runner y workflow?

- **Webhook:** es el **aviso**. Una notificación HTTP que una herramienta envía a otra cuando pasa un evento ("hubo un push"). Es el mecanismo de comunicación.
- **Workflow:** es la **receta**. El archivo YAML en `.github/workflows/` que define qué eventos lo disparan y qué jobs y pasos ejecutar.
- **Runner:** es **quien cocina**. La máquina (hospedada por GitHub o propia/self-hosted) que ejecuta los jobs del workflow.

Flujo: evento → (webhook/evento interno) → se dispara el **workflow** → sus jobs se ejecutan en un **runner**.

### 12. ¿Qué diferencia hay entre terraform validate, terraform plan y terraform apply?

- **`terraform validate`:** revisa que el código sea **correcto internamente**: sintaxis HCL, tipos de variables, referencias a recursos y atributos que existan. **No se conecta a la nube ni lee el state.** Es rápido y barato. No detecta, por ejemplo, que un nombre de bucket ya existe o que falta un permiso.
- **`terraform plan`:** compara tres cosas: el **código**, el **state** y la **infraestructura real** (hace *refresh* consultando las APIs del proveedor). Con eso calcula un plan de ejecución: qué se **crea (+)**, **cambia (~)**, **destruye (-)** o **reemplaza (-/+)**. **No modifica nada.** Guardado con `-out` se convierte en el artefacto que se revisa y aprueba.
- **`terraform apply`:** **ejecuta los cambios** reales en la nube llamando a las APIs y actualiza el state. Si se ejecuta sin un plan guardado, calcula uno nuevo y pide confirmación; en pipelines se usa `apply tfplan` para aplicar exactamente lo aprobado.

En resumen: validate = "¿está bien escrito?", plan = "¿qué va a pasar?", apply = "hazlo".

### 13. ¿Cómo manejarías state remoto en AWS?

- **Backend S3** con:
  - **Versionado** activado (poder volver a un state anterior si se corrompe).
  - **Cifrado** con KMS (el state puede contener datos sensibles).
  - **Bloqueo de acceso público** y política de bucket que solo permita a los roles de Terraform.
- **Locking** para evitar applies simultáneos: con Terraform ≥ 1.10 el bloqueo nativo de S3 (`use_lockfile = true`); en versiones anteriores, una tabla DynamoDB.
- **Un state por ambiente** (y por componente si el proyecto es grande), idealmente en cuentas AWS separadas o al menos con keys y permisos separados. Así un error en dev no toca el state de prod y se reduce el "radio de explosión".
- El bucket del state se crea una sola vez (bootstrap) y se protege con `prevent_destroy`.
- **Nadie edita el state a mano**; si es necesario, `terraform state mv/rm/import` con revisión.

```hcl
terraform {
  backend "s3" {
    bucket       = "org-tfstate-prod"
    key          = "app/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 14. ¿Cómo organizarías Terraform para varios ambientes: dev, qa, prod?

**Módulos reutilizables + un directorio por ambiente:**

```
terraform/
├── modules/            # lógica reutilizable (network, ecs-service, rds...)
│   ├── network/
│   └── ecs-service/
└── envs/
    ├── dev/            # main.tf llama a los módulos, backend y tfvars propios
    ├── qa/
    └── prod/
```

- El **código** vive en los módulos (una sola vez); cada ambiente solo cambia **valores** (tamaños, número de réplicas, CIDRs).
- Cada ambiente tiene **su propio backend/state** y **su propio rol de AWS** (idealmente su propia cuenta con AWS Organizations).
- Los módulos se **versionan** (tags), así prod puede quedarse en `v1.2.0` mientras dev prueba `v1.3.0`.
- Prefiero directorios sobre `terraform workspace` para ambientes, porque los workspaces comparten backend y credenciales, y es fácil equivocarse de workspace y aplicar en prod.

### 15. ¿Qué harías para evitar drift o cambios manuales en AWS?

El *drift* es cuando la infraestructura real ya no coincide con el código. Lo combatiría en tres frentes:

1. **Prevenir:** quitar permisos de escritura en la consola a las personas (acceso de solo lectura en prod); los cambios solo los hace el rol del pipeline. SCPs en AWS Organizations para bloquear acciones peligrosas. Acceso de emergencia (*break-glass*) auditado.
2. **Detectar:** un workflow programado (por ejemplo, cada noche) que ejecute `terraform plan -detailed-exitcode` en cada ambiente; si el código de salida indica cambios, abre un issue o alerta. Complementar con **AWS Config** y alertas de CloudTrail sobre cambios hechos fuera del rol del pipeline.
3. **Corregir:** decidir si el cambio manual se incorpora al código (y se hace PR) o si se revierte con un `apply`. Nunca dejar el drift sin resolver.

La razón es que si se permiten cambios manuales, el código deja de ser la fuente de verdad y el siguiente `apply` puede borrar ese cambio o fallar en prod.

### 16. ¿Qué mala práctica ves en usar un solo repositorio con variables mezcladas de todos los ambientes y sin aprobación?

- **Riesgo de aplicar en el ambiente equivocado:** con variables mezcladas es fácil usar valores de dev en prod (o al revés).
- **Radio de explosión enorme:** un solo cambio puede afectar todos los ambientes a la vez.
- **Sin separación de permisos:** quien puede tocar dev puede tocar prod.
- **Secretos expuestos:** suelen terminar en archivos de variables en texto plano, visibles para todos.
- **Sin aprobación = sin control:** no hay revisión por pares ni trazabilidad de quién aprobó un cambio en prod; incumple auditorías.
- **No se puede promover:** no existe el flujo "probar en dev → luego prod", todo cae al mismo tiempo.

El problema no es tener un solo repositorio (un monorepo está bien); el problema es **no separar configuración, state, credenciales y aprobaciones por ambiente**.

---

## Bloque 3 — Cómputo en AWS: EC2, ECS, EKS y escalado

### 17. Diferencia entre ECS, EKS y EC2 para desplegar aplicaciones. Tu punto de vista.

- **EC2:** máquinas virtuales. Tengo control total (sistema operativo, parches, runtime), pero también toda la responsabilidad operativa. Escala por instancias.
- **ECS:** orquestador de contenedores **propio de AWS**. Simple, muy integrado con IAM, ALB, CloudWatch y Secrets Manager. Con **Fargate** no administro servidores.
- **EKS:** **Kubernetes administrado** por AWS. Estándar de la industria, portable entre nubes y con un ecosistema enorme (Helm, operators, service mesh), pero con mucha más complejidad operativa (upgrades del clúster, add-ons, networking, RBAC).

**Mi punto de vista:** para la mayoría de aplicaciones web y APIs en AWS, **ECS con Fargate** da el mejor equilibrio entre simplicidad, costo operativo y seguridad. Elegiría EKS solo cuando haya una razón concreta (ver 19), y EC2 para casos que no encajan en contenedores (ver 20). La herramienta debe elegirse por la capacidad del equipo para operarla, no por moda.

### 18. ¿Cuándo escogerías ECS en vez de EKS?

- El equipo es pequeño o no tiene experiencia en Kubernetes.
- Toda la solución vive en AWS y no hay requisito de multinube.
- Son pocos servicios (APIs, workers) sin necesidades avanzadas de orquestación.
- Se busca salir rápido a producción y bajar costo operativo (sin plano de control que pagar ni upgrades de clúster).
- Se quiere integración nativa sencilla: roles IAM por tarea, ALB, CloudWatch, Secrets Manager.

### 19. ¿Cuándo sí justificarías EKS?

- **Muchos microservicios** (decenas o cientos) y varios equipos compartiendo plataforma.
- Requisito de **portabilidad / multinube / híbrido** (on-premise + AWS).
- La organización **ya tiene conocimiento y herramientas de Kubernetes** (Helm, ArgoCD/GitOps).
- Necesidades avanzadas: service mesh, operators, CRDs, scheduling complejo, cargas de ML con GPU, jobs por lotes a gran escala.
- Se quiere construir una **plataforma interna** para developers con estándares comunes.

### 20. ¿Cuándo una carga debería quedarse en EC2 y no en contenedores?

- **Aplicaciones legadas o monolitos** difíciles de contenerizar (dependencias del sistema operativo, instaladores, estado en disco local).
- **Software con licencias atadas** al host, núcleos o sockets (algunas bases de datos, software comercial).
- **Necesidades de bajo nivel:** kernel específico, drivers, hardware especial, acceso directo a la red o almacenamiento de alto rendimiento.
- **Cargas con estado** que requieren discos locales persistentes (algunas bases de datos autogestionadas).
- Aplicaciones de **Windows** con dependencias difíciles de llevar a contenedores.
- Cuando migrar a contenedores cuesta más de lo que aporta.

### 21. ¿Qué es una task definition en ECS?

Es la **plantilla** (en JSON) que describe cómo ejecutar uno o varios contenedores: la imagen, CPU y memoria, puertos, variables de entorno, secretos (referencias a Secrets Manager/SSM), configuración de logs, health checks, volúmenes y los roles IAM (*task role* para lo que la app hace en AWS y *execution role* para descargar la imagen y leer secretos).

Es **inmutable y versionada**: cada cambio crea una revisión nueva (`app:1`, `app:2`...), lo que facilita el rollback.

### 22. ¿Qué hace un service en ECS?

El service **mantiene corriendo el número deseado de tareas** de una task definition, todo el tiempo:

- Si una tarea muere o falla su health check, la **reemplaza** automáticamente.
- La **registra en el balanceador** (ALB/target group).
- Gestiona los **despliegues** (rolling update, o blue/green con CodeDeploy) y el **circuit breaker** para hacer rollback si la versión nueva falla.
- Se integra con **Application Auto Scaling** para subir o bajar el número de tareas.

La task definition dice "qué" correr; el service asegura "cuántas y que sigan vivas".

### 23. ¿Qué diferencia hay entre escalar EC2 y escalar ECS?

- **Escalar EC2 (Auto Scaling Group):** se agregan o quitan **máquinas virtuales**. Es más lento (minutos: arrancar la instancia, bootstrap) y la unidad es más grande.
- **Escalar ECS:** tiene dos niveles:
  1. **Escalado del servicio:** agrega o quita **tareas (contenedores)**. Es rápido (segundos).
  2. **Escalado de la capacidad:** si ECS corre sobre EC2, un *Capacity Provider* con *managed scaling* ajusta el ASG para que haya espacio para las tareas. Con **Fargate este nivel desaparece**: AWS pone la capacidad.

En resumen: en EC2 escalo servidores; en ECS escalo la aplicación (tareas) y, solo si uso EC2 como capacidad, también los servidores.

### 24. ¿Qué es target tracking scaling?

Es una política de autoescalado donde **defino un valor objetivo para una métrica** y AWS ajusta la capacidad automáticamente para mantenerla cerca de ese valor, como un termostato.

Ejemplo: "mantener el CPU promedio del servicio en 60 %". Si sube a 85 %, agrega tareas; si baja a 20 %, las quita (más lento, para evitar oscilaciones). AWS crea y administra las alarmas de CloudWatch por mí. Es más simple que el *step scaling*, donde tengo que definir los umbrales y los pasos a mano.

### 25. En EKS, ¿cómo escala el clúster?

En dos niveles:

1. **Pods (aplicación):**
   - **HPA (Horizontal Pod Autoscaler):** agrega o quita réplicas de pods según CPU, memoria o métricas personalizadas.
   - **VPA:** ajusta los requests de CPU/memoria de los pods.
   - **KEDA:** escala por eventos (mensajes en cola SQS, Kafka, etc.), incluso a cero.
2. **Nodos (infraestructura):**
   - **Karpenter** (recomendado hoy): cuando hay pods pendientes que no caben, lanza el nodo más adecuado en segundos y consolida nodos subutilizados para ahorrar costos.
   - **Cluster Autoscaler:** ajusta los Auto Scaling Groups de los node groups.
   - O **Fargate** para EKS, donde cada pod corre sin administrar nodos.

El flujo: sube la carga → HPA crea pods → si no hay espacio, quedan *Pending* → Karpenter/Cluster Autoscaler agrega nodos.

### 26. ¿Qué métrica usarías para escalar una API?

Depende de dónde está el cuello de botella, pero para una API prefiero métricas que reflejen **la demanda real**:

- **Solicitudes por destino (`ALBRequestCountPerTarget`)**: mi primera opción. Es proporcional a la carga y reacciona antes que el CPU.
- **CPU** si la API es intensiva en cómputo (es simple y confiable).
- **Latencia (p95/p99)** como métrica de alerta o complementaria; no suele ser buena única métrica para escalar, porque puede subir por causas que no se arreglan agregando réplicas (una base de datos lenta).
- **Profundidad de cola** si la API delega trabajo a workers asíncronos.

Normalmente combino dos políticas (requests por target + CPU) y la que pida más capacidad gana.

---

## Bloque 4 — Seguridad: DevSecOps y Zero Trust

### 27. ¿Qué significa DevSecOps para ti? (explicado para alguien no técnico)

Imagina que construyes una casa. La forma antigua era construirla completa y al final llamar a un inspector de seguridad; si encontraba un problema en los cimientos, había que tumbar paredes y costaba muchísimo.

**DevSecOps** es tener la seguridad **presente desde el primer ladrillo**: revisiones automáticas en cada etapa, candados puestos desde el diseño y todo el equipo (constructores, arquitectos y el inspector) trabajando juntos, no uno después del otro.

En software significa que, cada vez que alguien cambia algo, hay revisiones automáticas que buscan vulnerabilidades, contraseñas expuestas o configuraciones inseguras, **antes** de que el cambio llegue a los clientes. Es más barato, más rápido y más seguro arreglar los problemas temprano.

### 28. ¿Qué controles de seguridad meterías en un pipeline de Terraform? (mínimo 4)

1. **Escaneo estático de IaC (Checkov / Trivy / tfsec):** analiza el código antes de desplegar y bloquea configuraciones inseguras, por ejemplo buckets S3 públicos, Security Groups con `0.0.0.0/0` en el puerto 22, bases de datos sin cifrar o sin backups.
2. **Detección de secretos (Gitleaks):** evita que se suban contraseñas o llaves dentro de `.tf` o `.tfvars`. Los secretos deben venir de Secrets Manager/SSM, nunca estar en el código.
3. **Autenticación por OIDC con mínimo privilegio:** el pipeline asume un rol temporal distinto por ambiente; el rol de plan (en PRs) es de solo lectura y el de apply solo puede usarse desde el environment aprobado.
4. **Revisión del plan y aprobación obligatoria:** el `plan` se publica en el PR, lo revisa un CODEOWNER, y en prod se requiere aprobación en el GitHub Environment. Se aplica solo el plan aprobado.
5. **Policy as Code (OPA/Conftest o Sentinel):** reglas propias de la organización sobre el plan en JSON: tags obligatorios, regiones permitidas, prohibir `destroy` en recursos críticos, tipos de instancia permitidos.
6. **Protección del state:** S3 cifrado con KMS, versionado, bloqueo, y acceso restringido solo a los roles de Terraform.
7. **Cadena de suministro:** versiones de providers y módulos fijadas (`.terraform.lock.hcl`) y acciones de GitHub fijadas por SHA.

### 29. ¿Qué es Zero Trust?

Es un modelo de seguridad basado en **"nunca confíes, siempre verifica"**. No se confía en nadie por el solo hecho de estar "dentro de la red"; **cada acceso se verifica** siempre, según la identidad, el dispositivo y el contexto.

Sus principios:
- **Verificar explícitamente** cada solicitud (identidad fuerte, MFA, estado del dispositivo).
- **Mínimo privilegio:** solo los permisos necesarios y por el tiempo necesario (acceso *just-in-time*).
- **Asumir que ya hubo una brecha:** segmentar para limitar el daño, cifrar todo y monitorear continuamente.

El perímetro ya no es la red; **el perímetro es la identidad**.

### 30. ¿Cómo aplicarías Zero Trust en AWS?

- **Identidad:** IAM Identity Center (SSO) con MFA; nada de usuarios IAM con llaves de larga duración. Roles temporales para personas, pipelines (OIDC) y aplicaciones (task roles/IRSA/Pod Identity).
- **Mínimo privilegio:** políticas IAM acotadas, permission boundaries, SCPs en AWS Organizations y revisión con IAM Access Analyzer.
- **Segmentación:** cuentas separadas por ambiente, VPC con subredes privadas, Security Groups que referencian otros SGs (no rangos amplios), VPC Endpoints para no salir a internet.
- **Acceso a servidores sin puertos abiertos:** SSM Session Manager en lugar de SSH/bastión; sesiones registradas.
- **Cifrado en todas partes:** TLS en tránsito (ACM) y KMS en reposo.
- **Verificación en la capa de aplicación:** AWS Verified Access para aplicaciones internas; WAF en el borde.
- **Monitoreo continuo:** CloudTrail, GuardDuty, Security Hub, AWS Config y VPC Flow Logs, con alertas.

### 31. ¿Abrir el puerto 22 a internet para administrar servidores encaja con Zero Trust?

**No.** Abrir el 22 a `0.0.0.0/0` es confiar en la red y expone el servidor a escaneos, fuerza bruta y exploits de SSH desde cualquier lugar del mundo. Además, las llaves SSH suelen compartirse, no expiran y no dejan buena trazabilidad de quién hizo qué.

La alternativa Zero Trust en AWS es **SSM Session Manager**: sin puertos de entrada abiertos, acceso basado en identidad IAM (con MFA), permisos por instancia o por tag, sesiones temporales y **registro completo** de la sesión en CloudWatch/S3. Si se requiere SSH por alguna razón, que sea a través de Session Manager o EC2 Instance Connect Endpoint, nunca expuesto a internet.

### 32. ¿Qué diferencia hay entre "estar autenticado" y "estar autorizado"?

- **Autenticación:** comprobar **quién eres**. Ejemplo: usuario, contraseña y MFA; o el token OIDC que demuestra que eres el pipeline del repositorio X.
- **Autorización:** decidir **qué puedes hacer** una vez que se sabe quién eres. Ejemplo: la política IAM que dice que ese rol puede leer un bucket pero no borrarlo.

Analogía: en un hotel, mostrar la cédula en la recepción es **autenticarte**; la tarjeta que te dan y que solo abre tu habitación (y no las demás) es tu **autorización**. Siempre va primero la autenticación y después la autorización.
