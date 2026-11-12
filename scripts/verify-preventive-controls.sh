#!/usr/bin/env bash
###############################################################################
# Vérifie que l'infrastructure DÉPLOYÉE respecte bien les Preventive Controls.
# (Les scans CI vérifient le code ; ce script vérifie la RÉALITÉ du cloud/cluster.)
#
#   AWS_REGION=eu-west-3 CLUSTER=taskflow-prod NAMESPACE=taskflow \
#     ./scripts/verify-preventive-controls.sh
#
# Prérequis : aws cli v2, kubectl (contexte sur le cluster), jq.
# Code retour : 0 = tous les contrôles OK ; 1 = au moins un contrôle en échec.
# Lecture seule (les tests d'admission utilisent --dry-run=server : rien n'est créé).
###############################################################################
set -uo pipefail

REGION="${AWS_REGION:-eu-west-3}"
CLUSTER="${CLUSTER:-taskflow-prod}"
NS="${NAMESPACE:-taskflow}"
DB_ID="${DB_ID:-$CLUSTER}"
PROJECT="${PROJECT:-taskflow}"
SKIP_AWS="${SKIP_AWS:-false}"
SKIP_K8S="${SKIP_K8S:-false}"

PASS=0; FAIL=0; WARN=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  \033[31m✘\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
section() { printf '\n== %s\n' "$1"; }
# expect "description" <commande qui doit réussir>
expect() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }

if [ "$SKIP_AWS" != "true" ]; then
  section "AWS - Données (RDS)"
  RDS=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" --query 'DBInstances[0]' --output json 2>/dev/null || echo '{}')
  expect "RDS non accessible publiquement"      jq -e '.PubliclyAccessible == false' <<<"$RDS"
  expect "RDS chiffré (KMS)"                    jq -e '.StorageEncrypted == true' <<<"$RDS"
  expect "RDS sauvegardes >= 7 jours"           jq -e '.BackupRetentionPeriod >= 7' <<<"$RDS"
  expect "RDS protection contre la suppression" jq -e '.DeletionProtection == true' <<<"$RDS"
  expect "RDS authentification IAM activée"     jq -e '.IAMDatabaseAuthenticationEnabled == true' <<<"$RDS"
  jq -e '.MultiAZ == true' <<<"$RDS" >/dev/null 2>&1 && ok "RDS Multi-AZ" || warn "RDS mono-AZ (acceptable hors prod)"

  section "AWS - EKS"
  E=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster --output json 2>/dev/null || echo '{}')
  expect "EKS : secrets chiffrés avec KMS"   jq -e '[.encryptionConfig[]?.resources[]?] | index("secrets") != null' <<<"$E"
  expect "EKS : 5 types de logs activés"     jq -e '[.logging.clusterLogging[] | select(.enabled) | .types[]] | length >= 5' <<<"$E"
  expect "EKS : API non ouverte à 0.0.0.0/0" jq -e '(.resourcesVpcConfig.endpointPublicAccess == false) or ((.resourcesVpcConfig.publicAccessCidrs | index("0.0.0.0/0")) == null)' <<<"$E"
  expect "EKS : mode d'accès API (Access Entries)" jq -e '.accessConfig.authenticationMode == "API" or .accessConfig.authenticationMode == "API_AND_CONFIG_MAP"' <<<"$E"

  section "AWS - Point d'entrée (ALB + WAF)"
  LB=$(aws elbv2 describe-load-balancers --region "$REGION" --names "${CLUSTER}-alb" --query 'LoadBalancers[0]' --output json 2>/dev/null || echo '{}')
  LB_ARN=$(jq -r '.LoadBalancerArn // empty' <<<"$LB")
  if [ -n "$LB_ARN" ]; then
    expect "ALB : drop_invalid_header_fields" bash -c "aws elbv2 describe-load-balancer-attributes --region $REGION --load-balancer-arn $LB_ARN --query \"Attributes[?Key=='routing.http.drop_invalid_header_fields.enabled'].Value\" --output text | grep -qx true"
    expect "ALB : WAF associé"                bash -c "aws wafv2 get-web-acl-for-resource --region $REGION --resource-arn $LB_ARN --query WebACL.ARN --output text | grep -q arn:"
    LST=$(aws elbv2 describe-listeners --region "$REGION" --load-balancer-arn "$LB_ARN" --output json)
    expect "ALB : listener HTTP = redirection uniquement" jq -e '[.Listeners[] | select(.Port==80) | .DefaultActions[0].Type] | all(. == "redirect")' <<<"$LST"
    expect "ALB : listener HTTPS en TLS 1.3"  jq -e '[.Listeners[] | select(.Port==443) | .SslPolicy] | all(startswith("ELBSecurityPolicy-TLS13"))' <<<"$LST"
  else
    ko "ALB ${CLUSTER}-alb introuvable"
  fi

  section "AWS - Garde-fous du compte"
  ACCT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  expect "S3 : blocage d'accès public au niveau compte" bash -c "aws s3control get-public-access-block --account-id $ACCT --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' --output text | tr '\t' '\n' | grep -vqx False"
  expect "EBS : chiffrement par défaut"  bash -c "aws ec2 get-ebs-encryption-by-default --region $REGION --query EbsEncryptionByDefault --output text | grep -qx True"
  KEY=$(aws kms describe-key --region "$REGION" --key-id "alias/${CLUSTER}" --query KeyMetadata.KeyId --output text 2>/dev/null)
  expect "KMS : rotation de la clé activée" bash -c "aws kms get-key-rotation-status --region $REGION --key-id $KEY --query KeyRotationEnabled --output text | grep -qx True"
fi

if [ "$SKIP_K8S" != "true" ]; then
  section "Kubernetes - Admission (Pod Security + Kyverno)"
  expect "Namespace : Pod Security 'restricted' en enforce" bash -c "kubectl get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -qx restricted"

  # Tests négatifs : l'API server DOIT refuser ces pods (le dry-run server évalue l'admission)
  deny() {
    local desc="$1" manifest="$2"
    if echo "$manifest" | kubectl apply -n "$NS" --dry-run=server -f - >/dev/null 2>&1; then
      ko "$desc : ACCEPTÉ alors qu'il devrait être refusé"
    else
      ok "$desc : refusé par l'admission"
    fi
  }
  deny "Pod privilégié"       '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"pc-privileged","labels":{"app.kubernetes.io/part-of":"taskflow"}},"spec":{"containers":[{"name":"x","image":"nginxinc/nginx-unprivileged:1.27-alpine","securityContext":{"privileged":true}}]}}'
  deny "Pod root"             '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"pc-root","labels":{"app.kubernetes.io/part-of":"taskflow"}},"spec":{"containers":[{"name":"x","image":"nginxinc/nginx-unprivileged:1.27-alpine","securityContext":{"runAsUser":0}}]}}'
  deny "Image :latest"        '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"pc-latest","labels":{"app.kubernetes.io/part-of":"taskflow"}},"spec":{"containers":[{"name":"x","image":"nginx:latest"}]}}'
  deny "hostNetwork"          '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"pc-hostnet","labels":{"app.kubernetes.io/part-of":"taskflow"}},"spec":{"hostNetwork":true,"containers":[{"name":"x","image":"nginxinc/nginx-unprivileged:1.27-alpine"}]}}'
  deny "Image hors registre autorisé" '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"pc-registry","labels":{"app.kubernetes.io/part-of":"taskflow"}},"spec":{"containers":[{"name":"x","image":"docker.io/evil/miner:1.0"}]}}'

  KY=$(kubectl get clusterpolicy -o json 2>&1)
  if jq -e '.items' <<<"$KY" >/dev/null 2>&1; then
    expect "Kyverno : politiques taskflow présentes et en Enforce" jq -e '[.items[] | select(.metadata.name|startswith("taskflow-")) | .spec.validationFailureAction] | length > 0 and all(. == "Enforce")' <<<"$KY"
  elif grep -qi "forbidden" <<<"$KY"; then
    warn "Kyverno : lecture des ClusterPolicy interdite pour ce rôle (vérifié indirectement par les refus d'admission ci-dessus)"
  else
    warn "Kyverno non installé (seul Pod Security Admission protège le cluster)"
  fi

  section "Kubernetes - Réseau et workloads"
  expect "NetworkPolicy default-deny présente" bash -c "kubectl get networkpolicy -n $NS -o name | grep -q default-deny"
  PODS=$(kubectl get pods -n "$NS" -o json 2>/dev/null || echo '{"items":[]}')
  expect "Tous les conteneurs : readOnlyRootFilesystem" jq -e '[.items[].spec.containers[] | .securityContext.readOnlyRootFilesystem == true] | all' <<<"$PODS"
  expect "Tous les conteneurs : allowPrivilegeEscalation=false" jq -e '[.items[].spec.containers[] | .securityContext.allowPrivilegeEscalation == false] | all' <<<"$PODS"
  expect "Tous les conteneurs : capabilities drop ALL" jq -e '[.items[].spec.containers[] | (.securityContext.capabilities.drop // []) | index("ALL") != null] | all' <<<"$PODS"
  expect "Aucun pod en root" jq -e '[.items[] | (.spec.securityContext.runAsNonRoot == true)] | all' <<<"$PODS"
  expect "Aucun pod en tag :latest" jq -e '[.items[].spec.containers[].image | endswith(":latest")] | any | not' <<<"$PODS"
  expect "Secret applicatif présent (ExternalSecret synchronisé)" kubectl get secret -n "$NS" taskflow-api-secrets
  expect "Secret de migration séparé présent" kubectl get secret -n "$NS" taskflow-migration-secrets
  expect "ServiceAccount API TaskFlow présent" kubectl get serviceaccount -n "$NS" taskflow-production-api
  expect "Aucun secret en clair dans les ConfigMaps" bash -c "kubectl get cm -n $NS -o json | jq -e '[.items[].data // {} | keys[] | test(\"(?i)(password|secret|api_?key|private_?key|_token\$)\")] | any | not'"
fi

printf '\n== Résultat : %d OK, %d échec(s), %d avertissement(s)\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ]
