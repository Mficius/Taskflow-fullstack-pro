#!/usr/bin/env bash
# Applique l'infra sur LocalStack, lance les tests d'intégration, puis nettoie.
# Prérequis : `docker compose -f infrastructure/localstack/docker-compose.yml up -d --wait` (make localstack-up)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF="$ROOT/infrastructure/terraform"
OVERRIDE="$TF/localstack_override.tf"

cleanup() { rm -f "$OVERRIDE" "$TF/backend_override.tf"; }
trap cleanup EXIT

# 1) Rediriger le provider vers LocalStack (fichier d'override, supprimé en sortie)
cp "$ROOT/infrastructure/localstack/provider_override.tf" "$OVERRIDE"

terraform -chdir="$TF" init -input=false -reconfigure
terraform -chdir="$TF" validate
terraform -chdir="$TF" fmt -check -recursive

# 2) Tests d'intégration : apply réel sur LocalStack puis destroy automatique (terraform test)
terraform -chdir="$TF" test -test-directory=tests-localstack

# 3) Vérifications indépendantes avec awslocal/aws CLI (si disponible)
if command -v aws >/dev/null 2>&1; then
  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-3
  echo "▶ Services LocalStack disponibles :"
  curl -fsS http://localhost:4566/_localstack/health | python3 -c 'import json,sys; d=json.load(sys.stdin)["services"]; print({k:v for k,v in d.items() if v in ("available","running")})'
fi
echo "✔ Tests LocalStack terminés"
