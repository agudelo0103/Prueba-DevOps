"""API de demostración para la prueba DevOps.

Expone endpoints mínimos para validar el despliegue: health check para el
balanceador y metadatos de la versión desplegada (ambiente e imagen).
"""

import os
import socket

from fastapi import FastAPI

APP_ENV = os.getenv("APP_ENV", "local")
APP_VERSION = os.getenv("APP_VERSION", "dev-build")

app = FastAPI(title="Prueba DevOps API", version=APP_VERSION)


@app.get("/")
def root() -> dict:
    return {"message": "Hola desde la Prueba DevOps", "environment": APP_ENV}


@app.get("/health")
def health() -> dict:
    # Usado por el health check del target group del ALB.
    return {"status": "ok"}


@app.get("/version")
def version() -> dict:
    # Permite verificar qué imagen está corriendo en cada ambiente y en qué tarea.
    return {
        "environment": APP_ENV,
        "version": APP_VERSION,
        "host": socket.gethostname(),
    }
