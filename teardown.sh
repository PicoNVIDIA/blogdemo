#!/usr/bin/env bash
# =============================================================================
# NVIDIA RAG Blueprint – Teardown Script
# =============================================================================
# Stops and removes all Docker containers, networks, and volumes
# created by setup.sh.
#
# Usage:  bash teardown.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_DIR="${SCRIPT_DIR}/nvidia-rag-blueprint"
COMPOSE_DIR="${BLUEPRINT_DIR}/deploy/compose"
ENV_FILE="${COMPOSE_DIR}/.env"

echo "============================================================"
info "Tearing down NVIDIA RAG Blueprint infrastructure..."
echo "============================================================"
echo ""

# ── 1. Stop NVIngest ────────────────────────────────────────────────────────
info "Stopping NVIngest server..."
if [[ -f "${COMPOSE_DIR}/docker-compose-ingestor-server.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/docker-compose-ingestor-server.yaml" \
        --env-file "${ENV_FILE}" down -v 2>/dev/null || true
elif [[ -f "${COMPOSE_DIR}/ingestor.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/ingestor.yaml" \
        --env-file "${ENV_FILE}" down -v 2>/dev/null || true
fi

# Stop standalone container if it was used as fallback
docker rm -f blogdemo-nvingest 2>/dev/null || true

info "NVIngest stopped."

# ── 2. Stop Milvus ──────────────────────────────────────────────────────────
info "Stopping Milvus vector database..."
if [[ -f "${COMPOSE_DIR}/vectordb.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/vectordb.yaml" \
        --env-file "${ENV_FILE}" down -v 2>/dev/null || true
elif [[ -f "${COMPOSE_DIR}/docker-compose-vectordb.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/docker-compose-vectordb.yaml" \
        --env-file "${ENV_FILE}" down -v 2>/dev/null || true
fi

# Stop fallback Milvus if it was deployed inline
docker compose --project-name blogdemo-milvus down -v 2>/dev/null || true

info "Milvus stopped."

# ── 3. Clean up any remaining project containers ────────────────────────────
info "Cleaning up remaining containers..."
# Remove any containers with 'nvingest' or 'milvus' or 'etcd' or 'minio' in name
for pattern in nvingest milvus etcd minio; do
    containers=$(docker ps -aq --filter "name=${pattern}" 2>/dev/null || true)
    if [[ -n "${containers}" ]]; then
        docker rm -f ${containers} 2>/dev/null || true
        info "  Removed ${pattern} containers."
    fi
done

# ── 4. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
info "Teardown complete."
echo "============================================================"
echo ""
echo "  All Docker services have been stopped and volumes removed."
echo ""
echo "  To also remove the cloned blueprint repo:"
echo "    rm -rf ${BLUEPRINT_DIR}"
echo ""
echo "  To also remove the sample PDF:"
echo "    rm -rf ${SCRIPT_DIR}/data/"
echo ""
echo "============================================================"
