#!/usr/bin/env bash
# Crée (une seule fois) le bucket S3 de l'état Terraform : privé, versionné, chiffré.
# Usage : scripts/bootstrap-tfstate.sh [region]
set -euo pipefail
REGION="${1:-eu-west-3}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="taskflow-tfstate-${ACCOUNT}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET déjà présent."
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION"
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Bucket d'état : $BUCKET"
echo "Étape suivante :"
echo "  cd infrastructure/terraform"
echo "  terraform init -backend-config=bucket=$BUCKET -backend-config=key=prod/terraform.tfstate \\"
echo "                 -backend-config=region=$REGION -backend-config=use_lockfile=true -backend-config=encrypt=true"
echo "  terraform apply -var tf_state_bucket=$BUCKET     # crée aussi les rôles OIDC du pipeline infra"
