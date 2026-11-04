#!/usr/bin/env bash
# Déploie (ou rollback vers) un tag d'image sur ECS Fargate. Utilisé par la CD ET par `make demo-up`.
#   1. vérifie que les 3 images existent dans ECR
#   2. enregistre de nouvelles révisions des définitions de tâche (app + migrate) avec ce tag
#   3. joue les migrations dans une tâche ponctuelle — si elles échouent, RIEN n'est déployé
#   4. met à jour le service ; le « circuit breaker » ECS revient seul en arrière si le déploiement échoue
#   5. attend la fin du déploiement et échoue si ECS a dû revenir en arrière
# Usage : ecs-deploy.sh <image_tag>
# Variables : AWS_REGION ECS_CLUSTER ECS_SERVICE ECS_APP_FAMILY ECS_MIGRATE_FAMILY ECS_SUBNETS ECS_SECURITY_GROUP
#             [DESIRED_COUNT=1] [ECR_PREFIX=taskflow] [LOG_GROUP=/taskflow/prod/ecs]
set -euo pipefail

TAG="${1:?usage: ecs-deploy.sh <image_tag>}"
: "${AWS_REGION:?}" "${ECS_CLUSTER:?}" "${ECS_SERVICE:?}" "${ECS_APP_FAMILY:?}" "${ECS_MIGRATE_FAMILY:?}" "${ECS_SUBNETS:?}" "${ECS_SECURITY_GROUP:?}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"
ECR_PREFIX="${ECR_PREFIX:-taskflow}"
LOG_GROUP="${LOG_GROUP:-/taskflow/prod/ecs}"
export AWS_DEFAULT_REGION="$AWS_REGION"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ [1/5] Vérification des images ($TAG)"
for svc in backend frontend nginx; do
  aws ecr describe-images --repository-name "${ECR_PREFIX}-${svc}" --image-ids imageTag="$TAG" >/dev/null \
    || { echo "✖ ${ECR_PREFIX}-${svc}:${TAG} introuvable dans ECR" >&2; exit 1; }
done

register() { # $1 = famille ; affiche l'ARN de la nouvelle révision
  aws ecs describe-task-definition --task-definition "$1" --query taskDefinition --output json \
    | jq --arg reg "$REGISTRY" --arg prefix "$ECR_PREFIX" --arg tag "$TAG" '
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
        | .containerDefinitions |= map(.image = ($reg + "/" + $prefix + "-" + .name + ":" + $tag))' > "$TMP/$1.json"
  aws ecs register-task-definition --cli-input-json "file://$TMP/$1.json" --query taskDefinition.taskDefinitionArn --output text
}

echo "▶ [2/5] Nouvelles définitions de tâche"
NEW_APP="$(register "$ECS_APP_FAMILY")"
NEW_MIGRATE="$(register "$ECS_MIGRATE_FAMILY")"
echo "  app     : $NEW_APP"
echo "  migrate : $NEW_MIGRATE"

echo "▶ [3/5] Migrations de la base"
TASK_ARN="$(aws ecs run-task --cluster "$ECS_CLUSTER" --launch-type FARGATE --task-definition "$NEW_MIGRATE" \
  --network-configuration "awsvpcConfiguration={subnets=[${ECS_SUBNETS}],securityGroups=[${ECS_SECURITY_GROUP}],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)"
[ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ] || { echo "✖ Impossible de lancer la tâche de migration" >&2; exit 1; }
aws ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$TASK_ARN"
EXIT_CODE="$(aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$TASK_ARN" --query 'tasks[0].containers[0].exitCode' --output text)"
echo "  ── journal de migration ──"
aws logs get-log-events --log-group-name "$LOG_GROUP" --log-stream-name "migrate/backend/${TASK_ARN##*/}" \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' || true
if [ "$EXIT_CODE" != "0" ]; then
  echo "✖ Migration en échec (code $EXIT_CODE) : le service n'a PAS été modifié." >&2
  exit 1
fi

echo "▶ [4/5] Mise à jour du service (desired=$DESIRED_COUNT)"
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$NEW_APP" \
  --desired-count "$DESIRED_COUNT" --query 'service.serviceName' --output text >/dev/null

echo "▶ [5/5] Attente du déploiement (circuit breaker actif)"
for i in $(seq 1 80); do
  sleep 15
  read -r STATE PRIMARY RUNNING < <(aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
    --query 'services[0].deployments[?status==`PRIMARY`] | [0].[rolloutState, taskDefinition, runningCount]' --output text)
  echo "  [$i] état=$STATE tâches=$RUNNING"
  if [ "$PRIMARY" != "$NEW_APP" ]; then
    echo "✖ ECS est revenu à la révision précédente (rollback automatique)." >&2
    aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].events[:8].message' --output text >&2 || true
    exit 1
  fi
  case "$STATE" in
    COMPLETED) echo "✔ Déploiement terminé : $TAG"; exit 0 ;;
    FAILED)
      echo "✖ Déploiement en échec (rollback automatique par ECS)." >&2
      aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].events[:8].message' --output text >&2 || true
      exit 1 ;;
  esac
done
echo "✖ Délai dépassé" >&2
exit 1
