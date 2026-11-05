#!/usr/bin/env bash

# TaskFlow - ECS Fargate deployment
#
# Usage:
#   ./scripts/ecs-deploy.sh <image_tag>
#
# Required variables:
#   AWS_REGION
#   ECS_CLUSTER
#   ECS_SERVICE
#   ECS_APP_FAMILY
#   ECS_MIGRATE_FAMILY
#   ECS_SUBNETS
#   ECS_SECURITY_GROUP
#
# Optional:
#   DESIRED_COUNT=1
#   ECR_PREFIX=taskflow
#   LOG_GROUP=/taskflow/prod/ecs
#   MIGRATION_CONTAINER_NAME=backend
#   MIGRATION_LOG_PREFIX=migrate
#   ASSIGN_PUBLIC_IP=ENABLED

set -Eeuo pipefail

# ==========================================
# 1. CONFIGURATION
# ==========================================

TAG="${1:?Usage: ecs-deploy.sh <image_tag>}"

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECS_CLUSTER:?ECS_CLUSTER is required}"
: "${ECS_SERVICE:?ECS_SERVICE is required}"
: "${ECS_APP_FAMILY:?ECS_APP_FAMILY is required}"
: "${ECS_MIGRATE_FAMILY:?ECS_MIGRATE_FAMILY is required}"
: "${ECS_SUBNETS:?ECS_SUBNETS is required}"
: "${ECS_SECURITY_GROUP:?ECS_SECURITY_GROUP is required}"

DESIRED_COUNT="${DESIRED_COUNT:-1}"
ECR_PREFIX="${ECR_PREFIX:-taskflow}"
LOG_GROUP="${LOG_GROUP:-/taskflow/prod/ecs}"

MIGRATION_CONTAINER_NAME="${MIGRATION_CONTAINER_NAME:-backend}"
MIGRATION_LOG_PREFIX="${MIGRATION_LOG_PREFIX:-migrate}"

ASSIGN_PUBLIC_IP="${ASSIGN_PUBLIC_IP:-ENABLED}"

export AWS_DEFAULT_REGION="$AWS_REGION"

# Dependencies
for cmd in aws jq; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: $cmd is required."
        exit 1
    }
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=========================================="
echo " TaskFlow - ECS Deployment"
echo "=========================================="
echo "Image tag : $TAG"
echo "Cluster   : $ECS_CLUSTER"
echo "Service   : $ECS_SERVICE"
echo "Region    : $AWS_REGION"
echo "=========================================="


# ==========================================
# 2. VERIFY ECR IMAGES
# ==========================================

echo ""
echo "[1/5] Checking ECR images..."

for SERVICE in backend frontend nginx; do

    REPOSITORY="${ECR_PREFIX}-${SERVICE}"

    if ! aws ecr describe-images \
        --repository-name "$REPOSITORY" \
        --image-ids imageTag="$TAG" \
        >/dev/null 2>&1; then

        echo "ERROR: Image not found:"
        echo "${REPOSITORY}:${TAG}"
        exit 1
    fi

    echo "  OK: ${REPOSITORY}:${TAG}"

done


# ==========================================
# 3. REGISTER TASK DEFINITIONS
# ==========================================

register_task_definition() {

    local FAMILY="$1"
    local OUTPUT_FILE="$TMP/${FAMILY}.json"

    echo "  Registering $FAMILY..." >&2

    aws ecs describe-task-definition \
        --task-definition "$FAMILY" \
        --query taskDefinition \
        --output json |
    jq \
        --arg registry "$REGISTRY" \
        --arg prefix "$ECR_PREFIX" \
        --arg tag "$TAG" '

        del(
            .taskDefinitionArn,
            .revision,
            .status,
            .requiresAttributes,
            .compatibilities,
            .registeredAt,
            .registeredBy,
            .deregisteredAt
        )

        | .containerDefinitions |= map(

            .image = (
                $registry + "/" + $prefix + "-" +

                (
                    if .name == "frontend" then
                        "frontend"

                    elif (
                        .name == "backend" or
                        .name == "php-fpm" or
                        .name == "laravel" or
                        .name == "migrate"
                    ) then
                        "backend"

                    elif .name == "nginx" then
                        "nginx"

                    else
                        error("Unknown application container: " + .name)
                    end
                )

                + ":" + $tag
            )
        )
    ' > "$OUTPUT_FILE"

    aws ecs register-task-definition \
        --cli-input-json "file://${OUTPUT_FILE}" \
        --query taskDefinition.taskDefinitionArn \
        --output text
}


echo ""
echo "[2/5] Registering new task definitions..."

NEW_APP="$(register_task_definition "$ECS_APP_FAMILY")"

NEW_MIGRATE="$(register_task_definition "$ECS_MIGRATE_FAMILY")"

echo "  Application : $NEW_APP"
echo "  Migration   : $NEW_MIGRATE"


# ==========================================
# 4. RUN DATABASE MIGRATIONS
# ==========================================

echo ""
echo "[3/5] Running Laravel migrations..."

NETWORK_CONFIGURATION="awsvpcConfiguration={subnets=[${ECS_SUBNETS}],securityGroups=[${ECS_SECURITY_GROUP}],assignPublicIp=${ASSIGN_PUBLIC_IP}}"

aws ecs run-task \
    --cluster "$ECS_CLUSTER" \
    --launch-type FARGATE \
    --task-definition "$NEW_MIGRATE" \
    --network-configuration "$NETWORK_CONFIGURATION" \
    --output json > "$TMP/migration-task.json"

TASK_ARN="$(jq -r '.tasks[0].taskArn // empty' "$TMP/migration-task.json")"

if [[ -z "$TASK_ARN" ]]; then

    echo "ERROR: Unable to start migration task."

    jq '.failures' "$TMP/migration-task.json"

    exit 1

fi

echo "Migration task: $TASK_ARN"

echo "Waiting for migration task to stop..."

aws ecs wait tasks-stopped \
    --cluster "$ECS_CLUSTER" \
    --tasks "$TASK_ARN"


# ==========================================
# 5. CHECK MIGRATION RESULT
# ==========================================

TASK_DETAILS="$(
    aws ecs describe-tasks \
        --cluster "$ECS_CLUSTER" \
        --tasks "$TASK_ARN" \
        --output json
)"

EXIT_CODE="$(
    jq -r \
        --arg name "$MIGRATION_CONTAINER_NAME" \
        '.tasks[0].containers[]
         | select(.name == $name)
         | .exitCode // empty' \
        <<< "$TASK_DETAILS"
)"

echo ""
echo "Migration logs:"

TASK_ID="${TASK_ARN##*/}"

LOG_STREAM="${MIGRATION_LOG_PREFIX}/${MIGRATION_CONTAINER_NAME}/${TASK_ID}"

aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LOG_STREAM" \
    --query 'events[].message' \
    --output text 2>/dev/null |
    tr '\t' '\n' || true

if [[ "$EXIT_CODE" != "0" ]]; then

    echo ""
    echo "ERROR: Laravel migration failed."
    echo "Exit code: ${EXIT_CODE:-unknown}"

    jq -r '.tasks[0].stoppedReason // "No stopped reason available"' \
        <<< "$TASK_DETAILS"

    echo "ECS service was NOT updated."

    exit 1

fi

echo "Migration completed successfully."


# ==========================================
# 6. UPDATE ECS SERVICE
# ==========================================

echo ""
echo "[4/5] Updating ECS service..."

aws ecs update-service \
    --cluster "$ECS_CLUSTER" \
    --service "$ECS_SERVICE" \
    --task-definition "$NEW_APP" \
    --desired-count "$DESIRED_COUNT" \
    >/dev/null

echo "Service updated."
echo "Waiting for ECS deployment stability..."


# ==========================================
# 7. WAIT FOR STABLE DEPLOYMENT
# ==========================================

echo ""
echo "[5/5] Waiting for deployment..."

if ! aws ecs wait services-stable \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE"; then

    echo "ERROR: ECS deployment did not become stable."

    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --query 'services[0].events[:10].message' \
        --output text || true

    exit 1

fi


# ==========================================
# 8. VERIFY ACTIVE TASK DEFINITION
# ==========================================

ACTIVE_TASK_DEFINITION="$(
    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --query 'services[0].taskDefinition' \
        --output text
)"

if [[ "$ACTIVE_TASK_DEFINITION" != "$NEW_APP" ]]; then

    echo "ERROR: ECS is stable but the expected revision is not active."

    echo "Expected: $NEW_APP"
    echo "Active  : $ACTIVE_TASK_DEFINITION"

    echo "ECS may have rolled back to the previous revision."

    exit 1

fi


# ==========================================
# 9. SUCCESS
# ==========================================

echo ""
echo "=========================================="
echo " TaskFlow deployment successful!"
echo "=========================================="
echo "Image tag : $TAG"
echo "Task      : $NEW_APP"
echo "Service   : $ECS_SERVICE"
echo "=========================================="