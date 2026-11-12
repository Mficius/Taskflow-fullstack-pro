# Manifestes Kubernetes historiques

Ces fichiers sont conservés à titre de référence et ne doivent pas être appliqués en production.
Les workloads TaskFlow, Services, HPA, PDB, ExternalSecrets et TargetGroupBindings sont
gérés par `helm/taskflow` et Argo CD. Les politiques de plateforme actives restent dans
`kubernetes/policies/kyverno/` et `kubernetes/policies/resourcequota.yaml`.
