#!/usr/bin/env bash
# Build the 4 service images with Cloud Build (amd64, matches GKE nodes) and push
# them to candy-play's Artifact Registry with the :production tag the prod values
# expect. Run from anywhere; paths resolve to the monorepo root (parent of k8s/).
set -euo pipefail

PROJECT_ID="candy-play"
REGION="europe-west3"
REPO="cloud-run-source-deploy"
TAG="${1:-production}"

# repo root = two up from k8s/scripts/gcp
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

echo "==> Project: $PROJECT_ID  tag: $TAG  root: $ROOT"
gcloud config set project "$PROJECT_ID" >/dev/null

echo "==> Enabling Cloud Build API..."
gcloud services enable cloudbuild.googleapis.com --project="$PROJECT_ID"

echo "==> Ensuring Artifact Registry repo $REPO..."
gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1 \
  || gcloud artifacts repositories create "$REPO" \
       --repository-format=docker --location="$REGION" --project="$PROJECT_ID"

# build <svc> <context> [dockerfile-relative-to-context]
# Without a dockerfile arg, uses --tag (Dockerfile at context root). tpay copies
# pyproject.toml + app/ from the repo's tpay dir, so its context is tpay with
# Dockerfile app/Dockerfile -> needs an explicit cloudbuild config.
build() {
  local svc="$1" ctx="$2" dockerfile="${3:-}"
  local image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${svc}:${TAG}"
  echo ""
  echo "==> Building $svc -> $image (context: $ctx${dockerfile:+, dockerfile: $dockerfile})"
  if [ -z "$dockerfile" ]; then
    gcloud builds submit "$ctx" --tag "$image" --project="$PROJECT_ID"
  else
    local cfg; cfg="$(mktemp)"
    cat > "$cfg" <<EOF2
steps:
  - name: gcr.io/cloud-builders/docker
    args: ["build","-f","$dockerfile","-t","$image","."]
images: ["$image"]
EOF2
    gcloud builds submit "$ctx" --config="$cfg" --project="$PROJECT_ID"
    rm -f "$cfg"
  fi
}

build icore          "Icore"
build euro-virtuals  "euro-virtuals"
build 01-tech        "01-tech"
build tpay           "tpay"           "app/Dockerfile"

echo ""
echo "==> Done. Images pushed with tag :$TAG"
gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}" \
  --include-tags --project="$PROJECT_ID" 2>/dev/null | head
