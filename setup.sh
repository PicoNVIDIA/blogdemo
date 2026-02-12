#!/usr/bin/env bash
# =============================================================================
# NVIDIA RAG Blueprint – Infrastructure Bootstrap Script
# =============================================================================
# Usage:
#   export NGC_API_KEY="nvapi-..."
#   bash setup.sh
#
# Prerequisites:
#   - Docker Engine (>= 24.x recommended)
#   - Docker Compose v2 (>= 2.29.1)
#   - NVIDIA Container Toolkit (nvidia-ctk)
#   - At least one NVIDIA GPU (A100, H100, L40S, or RTX Pro 6000)
#   - git, curl
# =============================================================================
set -euo pipefail

# ── Colours for output ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_DIR="${SCRIPT_DIR}/nvidia-rag-blueprint"
HEALTH_URL="http://localhost:8082/v1/health?check_dependencies=true"

# ── 1. Check prerequisites ──────────────────────────────────────────────────
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
command -v git    >/dev/null 2>&1 || fail "git is not installed."
command -v curl   >/dev/null 2>&1 || fail "curl is not installed."

# Docker Compose v2 check
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "0.0.0")
info "Docker Compose version: ${COMPOSE_VERSION}"

# nvidia-smi check (warn, don't block — user may be on a remote GPU node)
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
    info "GPU detected: ${GPU_INFO}"
else
    warn "nvidia-smi not found. NVIngest requires an NVIDIA GPU."
    warn "If your GPU is on a remote node, you can ignore this warning."
fi

# ── 2. NGC API Key ──────────────────────────────────────────────────────────
if [[ -z "${NGC_API_KEY:-}" ]]; then
    fail "NGC_API_KEY is not set. Export it first:\n  export NGC_API_KEY=\"nvapi-...\""
fi
info "NGC_API_KEY is set (starts with ${NGC_API_KEY:0:8}…)"

# ── 3. Docker login to nvcr.io ──────────────────────────────────────────────
info "Logging into nvcr.io..."
echo "${NGC_API_KEY}" | docker login nvcr.io -u '$oauthtoken' --password-stdin \
    || fail "Docker login to nvcr.io failed. Check your NGC_API_KEY."
info "Docker login successful."

# ── 4. Clone the official NVIDIA RAG Blueprint ──────────────────────────────
if [[ -d "${BLUEPRINT_DIR}" ]]; then
    info "Blueprint repo already exists at ${BLUEPRINT_DIR}. Pulling latest..."
    (cd "${BLUEPRINT_DIR}" && git pull --ff-only 2>/dev/null || true)
else
    info "Cloning NVIDIA-AI-Blueprints/rag..."
    git clone https://github.com/NVIDIA-AI-Blueprints/rag.git "${BLUEPRINT_DIR}"
fi

# ── 5. Configure .env for NVIDIA-hosted NIMs ────────────────────────────────
ENV_FILE="${BLUEPRINT_DIR}/deploy/compose/.env"

if [[ -f "${ENV_FILE}" ]]; then
    info "Patching .env with NGC_API_KEY..."

    # Set the NGC / NVIDIA API key in every variant the .env might use
    sed -i.bak \
        -e "s|^NGC_API_KEY=.*|NGC_API_KEY=${NGC_API_KEY}|" \
        -e "s|^NVIDIA_API_KEY=.*|NVIDIA_API_KEY=${NGC_API_KEY}|" \
        -e "s|^NGC_CLI_API_KEY=.*|NGC_CLI_API_KEY=${NGC_API_KEY}|" \
        "${ENV_FILE}"

    # If the keys weren't in the file at all, append them
    grep -q "^NGC_API_KEY=" "${ENV_FILE}" || echo "NGC_API_KEY=${NGC_API_KEY}" >> "${ENV_FILE}"
    grep -q "^NVIDIA_API_KEY=" "${ENV_FILE}" || echo "NVIDIA_API_KEY=${NGC_API_KEY}" >> "${ENV_FILE}"

    info ".env configured."
else
    warn ".env not found at expected path. Creating minimal .env..."
    mkdir -p "$(dirname "${ENV_FILE}")"
    cat > "${ENV_FILE}" <<EOF
NGC_API_KEY=${NGC_API_KEY}
NVIDIA_API_KEY=${NGC_API_KEY}
NGC_CLI_API_KEY=${NGC_API_KEY}
EOF
    info "Minimal .env created."
fi

# ── 6. Start Milvus (Vector Database) ───────────────────────────────────────
COMPOSE_DIR="${BLUEPRINT_DIR}/deploy/compose"

info "Starting Milvus vector database..."
if [[ -f "${COMPOSE_DIR}/vectordb.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/vectordb.yaml" --env-file "${ENV_FILE}" up -d
elif [[ -f "${COMPOSE_DIR}/docker-compose-vectordb.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/docker-compose-vectordb.yaml" --env-file "${ENV_FILE}" up -d
else
    warn "No vectordb compose file found. Launching standalone Milvus..."
    docker compose -f - --project-name blogdemo-milvus up -d <<'MILVUS_YAML'
services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.18
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 30s
      timeout: 20s
      retries: 3

  minio:
    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
    environment:
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin
    ports:
      - "9001:9001"
      - "9000:9000"
    command: minio server /minio_data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  milvus:
    image: milvusdb/milvus:v2.4.17
    command: ["milvus", "run", "standalone"]
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    ports:
      - "19530:19530"
      - "9091:9091"
    depends_on:
      etcd:
        condition: service_healthy
      minio:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9091/healthz"]
      interval: 30s
      timeout: 20s
      retries: 3
MILVUS_YAML
fi

info "Waiting for Milvus to become healthy..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:9091/healthz" >/dev/null 2>&1 || \
       curl -sf "http://localhost:19530" >/dev/null 2>&1; then
        info "Milvus is healthy."
        break
    fi
    sleep 5
    echo -n "."
done
echo ""

# ── 7. Start NVIngest Server ────────────────────────────────────────────────
info "Starting NVIngest server..."
if [[ -f "${COMPOSE_DIR}/docker-compose-ingestor-server.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/docker-compose-ingestor-server.yaml" --env-file "${ENV_FILE}" up -d
elif [[ -f "${COMPOSE_DIR}/ingestor.yaml" ]]; then
    docker compose -f "${COMPOSE_DIR}/ingestor.yaml" --env-file "${ENV_FILE}" up -d
else
    warn "No ingestor compose file found in blueprint."
    warn "Attempting to use the nv-ingest standalone image..."
    docker run -d \
        --name blogdemo-nvingest \
        --gpus all \
        --network host \
        -e NGC_API_KEY="${NGC_API_KEY}" \
        -e NVIDIA_API_KEY="${NGC_API_KEY}" \
        -p 8082:8082 \
        nvcr.io/nvidia/nv-ingest:latest
fi

# ── 8. Wait for NVIngest health ─────────────────────────────────────────────
info "Waiting for NVIngest to become healthy (this may take a few minutes on first pull)..."
MAX_WAIT=120
for i in $(seq 1 ${MAX_WAIT}); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" == "200" ]]; then
        info "NVIngest is healthy!"
        break
    fi
    if (( i % 10 == 0 )); then
        info "  Still waiting... (${i}/${MAX_WAIT}s, last HTTP code: ${HTTP_CODE})"
    fi
    sleep 1
done

if [[ "${HTTP_CODE}" != "200" ]]; then
    warn "NVIngest did not report healthy within ${MAX_WAIT}s."
    warn "It may still be starting. Check: curl ${HEALTH_URL}"
fi

# ── 9. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
info "NVIDIA RAG Blueprint infrastructure is up!"
echo "============================================================"
echo ""
echo "  NVIngest API:   http://localhost:8082"
echo "  NVIngest Health: ${HEALTH_URL}"
echo "  Milvus gRPC:    localhost:19530"
echo "  MinIO Console:  http://localhost:9001  (minioadmin/minioadmin)"
echo ""
echo "Next steps:"
echo "  1. cd ${SCRIPT_DIR}"
echo "  2. pip install -r requirements.txt"
echo "  3. python generate_sample_pdf.py"
echo "  4. jupyter lab notebooks/"
echo ""
echo "To tear down:  bash teardown.sh"
echo "============================================================"
