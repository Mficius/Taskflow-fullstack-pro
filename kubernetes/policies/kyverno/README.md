# Kyverno : contrôles préventifs à l'admission

Installer Kyverno (Helm) puis appliquer : `kubectl apply -f kubernetes/policies/kyverno/`

Toutes les politiques sont en `validationFailureAction: Enforce` : une ressource non
conforme est **refusée par l'API server** (rien ne démarre). C'est la 2e ligne de défense
après les scans CI (Checkov / Conftest) et en plus de Pod Security Admission
(`namespace.yaml`, profil *restricted*).

Les mêmes règles sont testées en CI par `policy/kubernetes/*.rego` (Conftest) avant déploiement
et vérifiées après déploiement par `scripts/verify-preventive-controls.sh`.
