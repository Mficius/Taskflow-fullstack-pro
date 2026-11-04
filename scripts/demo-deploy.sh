#!/usr/bin/env bash
# Construit, pousse et déploie l'application sur l'infrastructure déjà créée (utilisé par `make demo-up`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/infrastructure/terraform"

OUT="$(terraform -chdir="$TF" output -json github_actions_variables)"
for k in $(echo "$OUT" | jq -r 'keys[]'); do
  export "$k=$(echo "$OUT" | jq -r --arg k "$k" '.[$k]')"
done
PREFIX="$(terraform -chdir="$TF" output -raw secrets_ssm_prefix)"
export LOG_GROUP="${PREFIX}/ecs"

TAG="demo-$(date +%Y%m%d%H%M%S)"
"$ROOT/scripts/push-images.sh" "$TAG"
"$ROOT/scripts/ecs-deploy.sh" "$TAG"

echo
echo "════════════════════════════════════════════"
echo " Application : $APP_URL"
echo " Dashboard   : $(terraform -chdir="$TF" output -raw dashboard_url)"
echo " Admin       : $(aws ssm get-parameter --name "${PREFIX}/seed_admin_email" --with-decryption --query Parameter.Value --output text)"
echo " Mot de passe: aws ssm get-parameter --name ${PREFIX}/seed_admin_password --with-decryption --query Parameter.Value --output text"
echo " Pensez à    : make demo-down   (évite ~3 $/jour)"
echo "════════════════════════════════════════════"
