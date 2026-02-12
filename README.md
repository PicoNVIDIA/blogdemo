# NVIDIA AI Data Platform: Enterprise RAG with NVIngest

A self-contained demo showing how **NVIDIA NVIngest** solves the problem of RAG failing on complex enterprise PDFs. Standard text extractors flatten tables into gibberish; NVIngest extracts tables, charts, and text as **separate structured objects**, so an LLM can actually read the data and give precise answers.

## What's in the repo

| File | Purpose |
|---|---|
| `notebooks/nvidia_rag_demo.ipynb` | The main demo — ingest, inspect, index, chat (4 parts, ~24 cells) |
| `generate_sample_pdf.py` | Creates a synthetic Acme Corp financial report PDF with a table and chart |
| `docker-compose-nvingest.yaml` | Starts the NVIngest runtime using NVIDIA cloud endpoints (no local NIMs needed) |
| `setup.sh` | Clones the NVIDIA RAG Blueprint repo and starts Milvus (vector DB) |
| `teardown.sh` | Stops and removes all Docker containers and volumes |
| `requirements.txt` | Python dependencies |

## Quick start

### Prerequisites

- Docker with Docker Compose v2+
- `nvidia-container-toolkit` installed
- An NVIDIA GPU (A100 / H100 / L40S)
- An NGC API key — get one at https://build.nvidia.com/

### Setup

```bash
git clone https://github.com/PicoNVIDIA/blogdemo.git && cd blogdemo

# Set your NGC API key
export NGC_API_KEY="nvapi-..."

# Log in to the NVIDIA container registry
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

# Start Milvus (vector database)
bash setup.sh   # NVIngest errors at the end are expected — we start it separately below

# Start NVIngest (document extraction service)
docker compose -f docker-compose-nvingest.yaml up -d

# Wait for NVIngest to be ready (~60s on first start)
until curl -sf http://localhost:7670/v1/health/ready; do sleep 5; echo "waiting..."; done

# Create a Python venv and install dependencies
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt && pip install "setuptools<72"

# Generate the sample PDF
python generate_sample_pdf.py

# Launch the notebook
jupyter lab notebooks/
```

### Run the demo

Open `nvidia_rag_demo.ipynb` and run all cells. The notebook walks through four parts:

1. **Ingest** — sends the PDF to NVIngest and gets back structured extractions
2. **Inspect** — shows how NVIngest separated text, tables, and charts into distinct chunks
3. **Index** — builds a LlamaIndex RAG pipeline with NVIDIA cloud LLM + embeddings + Milvus
4. **Chat** — asks 4 questions that require reading specific table rows

Expected results:

| Query | Expected answer |
|---|---|
| Q3 2024 revenue | **$2,847M** |
| Q2 → Q3 net income growth | **$389M → $456M (+$67M, ~17.2%)** |
| Q4 2024 EPS | **$2.61** |
| FY 2024 total revenue + Q1 2025 guidance | **$10,552M; $3,300–$3,500M** |

### Tear down

```bash
docker compose -f docker-compose-nvingest.yaml down -v
bash teardown.sh
```

## How it works

```
PDF Document
  │
  ▼
NVIngest (GPU-accelerated extraction)
  │  ├── text chunks      (narrative paragraphs)
  │  ├── table chunks     (structured rows & columns)
  │  └── image chunks     (chart descriptions)
  ▼
NVIDIA Embedding NIM  →  Milvus Vector DB
  │
  ▼
NVIDIA LLM NIM  →  Accurate, table-grounded answers
```

The key insight: NVIngest preserves the table's row-column structure instead of flattening it into an unreadable string. This is what makes the LLM able to answer "What was Q3 revenue?" with the exact number ($2,847M) instead of hallucinating.

## Architecture details

- **NVIngest** (`nvcr.io/nvidia/nemo-microservices/nv-ingest:26.1.2`) — document extraction orchestrator. Uses NVIDIA cloud endpoints for table detection (YOLOX), OCR, and chart captioning so no local NIM containers are needed.
- **Milvus** — vector database for storing and retrieving embeddings.
- **LlamaIndex** — RAG orchestration framework.
- **NVIDIA NIMs** (cloud) — `meta/llama-3.1-70b-instruct` for the LLM and `nvidia/nv-embedqa-e5-v5` for 1024-dim embeddings, both via `https://integrate.api.nvidia.com/v1`.

---

*Built with the [NVIDIA AI Blueprint for RAG](https://build.nvidia.com/nvidia/build-an-enterprise-rag-pipeline) and [NVIngest](https://github.com/NVIDIA-AI-Blueprints/multimodal-pdf-data-extraction).*
