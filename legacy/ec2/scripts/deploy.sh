#!/usr/bin/env bash
# Déploie (ou rollback vers) un tag d'image sur l'instance. Lancé via AWS SSM par la CD.
# Usage : deploy.sh <image_tag>
# En cas d'échec du healthcheck, restaure automatiquement la version précédente.
set -euo pipefail

TAG="${1:?usage: deploy.sh <image_tag>}"
APP_DIR=/opt/taskflow
cd "$APP_DIR"

# shellcheck disable=SC1091
source /etc/taskflow/instance.env
export AWS_REGION AWS_DEFAULT_REGION

COMPOSE=(docker compose -f docker-compose.prod.yml)
PREV_TAG="$(cat .current_tag 2>/dev/null || true)"

write_env() { # $1 = tag
  local tag="$1" seed="false"
  [ -f .seeded ] || seed="true"
  umask 077
  {
    echo "ECR_REGISTRY=$ECR_REGISTRY"
    echo "IMAGE_TAG=$tag"
    echo "APP_URL=$APP_URL"
    echo "DB_DATABASE=taskflow"
    echo "DB_USERNAME=taskflow"
    echo "RUN_SEEDER=$seed"
    # Secrets : /taskflow/<env>/<nom> → NOM en majuscules
    aws ssm get-parameters-by-path --path "$SSM_PREFIX" --with-decryption \
      --query 'Parameters[].[Name,Value]' --output text |
      while IFS=$'\t' read -r name value; do
        printf '%s=%s\n' "$(basename "$name" | tr '[:lower:]' '[:upper:]')" "$value"
      done
  } > .env.new
  mv .env.new .env
}

healthy() {
  for _ in $(seq 1 40); do
    if curl -fsS -o /dev/null http://127.0.0.1/up && curl -fsS -o /dev/null http://127.0.0.1/; then
      return 0
    fi
    sleep 3
  done
  return 1
}

up() { # $1 = tag
  write_env "$1"
  aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null
  "${COMPOSE[@]}" pull
  "${COMPOSE[@]}" up -d --remove-orphans
}

echo "▶ Déploiement du tag $TAG (précédent : ${PREV_TAG:-aucun})"
up "$TAG"

if healthy; then
  echo "$TAG" > .current_tag
  touch .seeded
  docker image prune -f >/dev/null
  echo "✔ $TAG déployé et sain"
  exit 0
fi

echo "✖ Healthcheck KO pour $TAG" >&2
"${COMPOSE[@]}" logs --tail=60 backend nginx >&2 || true
if [ -n "$PREV_TAG" ] && [ "$PREV_TAG" != "$TAG" ]; then
  echo "↩ Rollback vers $PREV_TAG" >&2
  up "$PREV_TAG"
  healthy && echo "↩ Rollback réussi ($PREV_TAG)" >&2 || echo "⚠ Rollback KO : intervention manuelle" >&2
fi
exit 1
