#!/usr/bin/env bash
# Étape ADMIN (une seule fois, après terraform apply) : installation des opérateurs
# de plateforme et du contrôleur GitOps. GitHub Actions ne déploie jamais directement sur EKS.
set -euo pipefail
CLUSTER="${CLUSTER:-taskflow-prod}"; REGION="${AWS_REGION:-eu-west-3}"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

# 1. Namespace avec Pod Security Admission "restricted"
kubectl apply -f kubernetes/namespace.yaml

# 2. Opérateurs de plateforme. Pour une installation réglementée, fixer les versions Helm validées.
helm repo add external-secrets https://charts.external-secrets.io
helm repo add eks https://aws.github.io/eks-charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform -chdir=infrastructure/terraform output -json irsa_role_arns | jq -r '.["external-secrets"]')" --wait --timeout 5m
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName="$CLUSTER" --set region="$REGION" \
  --set vpcId="$(terraform -chdir=infrastructure/terraform output -raw vpc_id)" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform -chdir=infrastructure/terraform output -json irsa_role_arns | jq -r '.["lb-controller"]')" \
  --set enableShield=false --set enableWaf=false --set enableWafv2=false --wait --timeout 5m
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --timeout 5m
helm upgrade --install reloader stakater/reloader -n reloader --create-namespace --wait --timeout 5m
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --wait --timeout 5m
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --wait --timeout 10m

# Attendre que les CRD des opérateurs soient enregistrées avant de créer leurs ressources.
kubectl wait --for=condition=Established crd/externalsecrets.external-secrets.io --timeout=120s
kubectl wait --for=condition=Established crd/targetgroupbindings.elbv2.k8s.aws --timeout=120s
kubectl wait --for=condition=Established crd/clusterpolicies.kyverno.io --timeout=120s
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=120s

# 3. Contrôles préventifs à l'admission + garde-fous réseau
kubectl apply -f kubernetes/policies/kyverno/
kubectl apply -f kubernetes/policies/resourcequota.yaml

# 4. Déclarer l'application GitOps (repo public ou credentials Argo CD préconfigurés)
kubectl apply -f gitops/applications/taskflow-production.yaml
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/taskflow-production -n argocd --timeout=600s
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/taskflow-production -n argocd --timeout=600s

# 5. Vérification
./scripts/verify-preventive-controls.sh
