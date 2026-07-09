#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NAMESPACE:-customer-intent-demo}"
REGISTRY="${REGISTRY:-image-registry.openshift-image-registry.svc:5000/${NS}}"

echo "==> Build imagem de inferência"
podman build -t "${REGISTRY}/customer-intent-inference:latest" -f "${ROOT}/inference/Dockerfile" "${ROOT}"
podman push "${REGISTRY}/customer-intent-inference:latest" || true

echo "==> Build imagem Quarkus (requer Maven + JDK 17)"
pushd "${ROOT}/quarkus-backend" >/dev/null
./mvnw -q package -DskipTests || mvn -q package -DskipTests
podman build -t "${REGISTRY}/customer-intent-backend:latest" .
podman push "${REGISTRY}/customer-intent-backend:latest" || true
popd >/dev/null

echo "Imagens publicadas em ${REGISTRY}"
