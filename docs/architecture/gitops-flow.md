# Flux CI/CD et GitOps

1. GitHub Actions exécute les tests, les scans et construit les images.
2. Le job de publication CI se connecte à Docker Hub avec `DOCKER_USERNAME` et `DOCKER_PASSWORD`; aucun rôle AWS ni accès EKS n’est nécessaire pour publier les images.
3. Les images sont taguées avec le SHA Git et les digests Docker Hub sont enregistrés dans Helm; le workflow ouvre une PR qui met
   à jour `helm/taskflow/values-eks.yaml`.
4. Après revue et merge, Argo CD détecte le changement sur `main` et synchronise Helm
   vers le namespace `taskflow` dans EKS.
5. GitHub Actions ne reçoit aucun droit d'accès Kubernetes et n'exécute ni `kubectl`
   ni `helm upgrade` contre le cluster de production.

Les fichiers sous `kubernetes/deployments`, `kubernetes/services`, `kubernetes/configmaps`,
`kubernetes/hpa`, `kubernetes/jobs` et `kubernetes/ingress` sont des anciens manifestes
standalone. Pour l'application, Helm est la source de vérité. Le dossier `kubernetes/`
reste réservé aux politiques et ressources de plateforme non gérées par le chart.

Le bucket S3 privé, son endpoint VPC et l'endpoint STS privé (pour IRSA) sont provisionnés pour les futures pièces jointes.
Le code actuel n'implémente pas encore de téléversement et utilise `FILESYSTEM_DISK=local`;
les volumes `emptyDir` ne doivent donc pas être présentés comme un stockage persistant.
Avant d'activer S3 dans Laravel, ajouter `league/flysystem-aws-s3-v3` au projet, mettre à
jour `composer.lock`, configurer `AWS_BUCKET` et tester le flux de téléversement.
