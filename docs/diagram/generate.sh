#!/usr/bin/env bash
# Genera los PNG de los diagramas en un contenedor con Graphviz + diagrams,
# sin instalar nada en la máquina local.
set -euo pipefail
cd "$(dirname "$0")"
docker run --rm --network host -v "$PWD:/work" -w /work python:3.12-slim bash -c '
  set -e
  apt-get update -qq >/dev/null && apt-get install -y -qq graphviz fonts-dejavu >/dev/null
  pip install --quiet --root-user-action=ignore --disable-pip-version-check diagrams==0.25.1
  python arquitectura.py
  chown '"$(id -u):$(id -g)"' *.png'
echo "Diagramas generados: $(ls ./*.png)"
