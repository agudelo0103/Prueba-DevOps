"""Diagramas de la solución (diagrams-as-code).

Genera:
  - arquitectura-aws.png : infraestructura en AWS (runtime) por ambiente.
  - pipeline-cicd.png    : flujo CI/CD de GitHub Actions hacia AWS.

Uso: ./generate.sh  (corre en Docker con Graphviz, sin instalar nada local)
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, ElasticContainerServiceService, Fargate
from diagrams.aws.general import Users
from diagrams.aws.management import Cloudwatch, CloudwatchAlarm, SystemsManagerParameterStore
from diagrams.aws.network import ALB, InternetGateway, NATGateway, Endpoint
from diagrams.aws.security import IAMRole, KMS, WAF, IAMPermissions
from diagrams.aws.storage import S3
from diagrams.aws.integration import SNS
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.vcs import Github
from diagrams.programming.language import Python
from diagrams.aws.devtools import CommandLineInterface
from diagrams.generic.blank import Blank

GRAPH = {"fontsize": "20", "pad": "0.6", "nodesep": "0.7", "ranksep": "1.0", "splines": "spline"}
NODE = {"fontsize": "12"}

# ---------------------------------------------------------------------------
# 1) Arquitectura AWS
# ---------------------------------------------------------------------------
with Diagram(
    "Prueba DevOps - Arquitectura AWS (us-east-1)",
    filename="arquitectura-aws",
    show=False,
    direction="LR",
    graph_attr=GRAPH,
    node_attr=NODE,
):
    users = Users("Usuarios\n(internet)")

    with Cluster("GitHub"):
        gha = GithubActions("GitHub Actions\n(OIDC, sin access keys)")

    with Cluster("Cuenta AWS"):
        with Cluster("Compartido (stack bootstrap)"):
            state = S3("State Terraform\n(versionado + lock)")
            kms = KMS("KMS")
            ecr = ECR("ECR\n(tags inmutables,\nscan on push)")
            with Cluster("IAM (OIDC)"):
                plan_role = IAMRole("gha-plan\n(solo lectura)")
                deploy_role = IAMRole("gha-deploy-<env>\n(por environment)")
                boundary = IAMPermissions("permissions\nboundary")

        with Cluster("VPC por ambiente  (dev 10.10/16 · prod 10.20/16)"):
            igw = InternetGateway("Internet GW")
            waf = WAF("WAF (prod)\nOWASP, Log4j,\nIP reputation, rate limit")

            with Cluster("Subredes públicas (AZ a / AZ b)"):
                alb = ALB("ALB\n(HTTP->HTTPS con ACM)")
                nat = NATGateway("NAT GW\n(1 en dev, 1 por AZ en prod)")

            with Cluster("Subredes privadas (AZ a / AZ b)"):
                with Cluster("ECS Cluster - Fargate"):
                    svc = ElasticContainerServiceService("ECS Service\n(circuit breaker\n+ rollback)")
                    tasks = [Fargate("Task AZ a"), Fargate("Task AZ b")]
                s3ep = Endpoint("S3 Gateway\nEndpoint")

            with Cluster("Operación"):
                logs = Cloudwatch("CloudWatch\nlogs, métricas,\nflow logs")
                alarms = CloudwatchAlarm("Alarmas\n5xx, unhealthy,\nCPU alta")
                sns = SNS("SNS\nnotificaciones")
                ssm = SystemsManagerParameterStore("SSM\nimage-tag desplegado")

    users >> Edge(label="HTTPS") >> igw >> waf >> alb
    alb >> Edge(label="solo SG del ALB\npuerto 8080") >> svc >> tasks
    tasks[0] >> Edge(style="dashed", label="pull imagen") >> nat
    nat >> Edge(style="dashed") >> ecr
    tasks[1] >> Edge(style="dashed") >> s3ep
    svc >> Edge(style="dotted") >> logs >> alarms >> sns

    gha >> Edge(label="AssumeRoleWithWebIdentity", color="darkgreen") >> plan_role
    gha >> Edge(color="darkgreen") >> deploy_role
    deploy_role >> Edge(label="terraform apply", color="darkgreen") >> svc
    deploy_role >> Edge(label="docker push (dev)", color="darkgreen") >> ecr
    deploy_role >> Edge(style="dotted") >> ssm
    plan_role >> Edge(style="dotted") >> state
    state - Edge(style="dotted") - kms
    boundary - Edge(style="dotted", label="techo de permisos\nde task roles") - svc


# ---------------------------------------------------------------------------
# 2) Pipeline CI/CD
# ---------------------------------------------------------------------------
with Diagram(
    "Prueba DevOps - Pipeline CI/CD (GitHub Actions)",
    filename="pipeline-cicd",
    show=False,
    direction="LR",
    graph_attr={**GRAPH, "ranksep": "0.8"},
    node_attr=NODE,
):
    dev = CommandLineInterface("Developer\nrama feature/*")

    with Cluster("CI - Pull Request a main  (check requerido: ci-ok)"):
        pr = Github("Pull Request\n+ CODEOWNERS")
        with Cluster("Seguridad y calidad"):
            gl = GithubActions("Gitleaks\n(secretos)")
            app = Python("ruff + pytest")
            trivy = GithubActions("Build + Trivy\n(imagen)")
            tfs = GithubActions("fmt · validate\nTFLint · Checkov")
        plan = GithubActions("terraform plan\ndev + prod\n(rol solo lectura)\ncomentado en el PR")

    with Cluster("CD - merge a main"):
        build = GithubActions("Build + Trivy\npush ECR :SHA")
        with Cluster("Environment: dev"):
            dplan = GithubActions("plan dev")
            dapply = GithubActions("apply dev\n(automático)")
            smoke = GithubActions("smoke test\n/health + /version")
        with Cluster("Environment: prod"):
            pplan = GithubActions("plan prod\n(mismo SHA)")
            gate = Users("Aprobación\nmanual")
            papply = GithubActions("apply prod\n(plan aprobado)")

    with Cluster("AWS"):
        aws_dev = ElasticContainerServiceService("ECS dev")
        aws_prod = ElasticContainerServiceService("ECS prod")

    drift = GithubActions("Drift detection\n(cron diario)\n-> issue")

    dev >> pr >> [gl, app, tfs]
    app >> trivy
    tfs >> plan
    pr >> Edge(label="squash merge") >> build
    build >> dplan >> dapply >> smoke >> pplan >> gate >> papply
    dapply >> Edge(color="darkgreen", label="OIDC") >> aws_dev
    papply >> Edge(color="darkgreen", label="OIDC") >> aws_prod
    drift >> Edge(style="dotted") >> [aws_dev, aws_prod]
