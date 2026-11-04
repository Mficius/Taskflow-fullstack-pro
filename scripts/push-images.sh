#!/usr/bin/env bash
# Construit et pousse les 3 images vers ECR (usage local / démonstration ; la CD fait la même chose avec scans).
# Usage : push-images.sh <image_tag>
set -euo pipefail
TAG="${1:?usage: push-images.sh <image_tag>}"
REGION="${AWS_REGION:?AWS_REGION requis}"
PREFIX="${ECR_PREFIX:-taskflow}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${REGION}.amazonaws.com"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in backend frontend nginx; do
  echo "▶ $svc"
  docker build --platform linux/amd64 -t "${REGISTRY}/${PREFIX}-${svc}:${TAG}" "$ROOT/$svc"
  docker push "${REGISTRY}/${PREFIX}-${svc}:${TAG}"
done
