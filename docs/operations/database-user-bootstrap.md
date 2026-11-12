# Création des comptes SQL applicatifs (une seule fois)

Le compte maître RDS n'est jamais injecté dans les pods. Terraform crée deux secrets
Secrets Manager : `taskflow/prod/database-app` (runtime) et
`taskflow/prod/database-migrator` (Job de migrations). External Secrets les synchronise
respectivement dans `taskflow-api-secrets` et `taskflow-migration-secrets`.

Depuis un poste d'administration autorisé (ou l'hôte SSM), récupérez les secrets via
AWS CLI sans les afficher dans le terminal ni les committer. Utilisez le secret maître
RDS (`terraform output -raw rds_master_secret_arn`) pour ouvrir une session MySQL.
Récupérez les deux autres valeurs JSON avec `aws secretsmanager get-secret-value`.

Créez ensuite les comptes avec les mots de passe correspondants :

```sql
CREATE USER 'taskflow_app'@'%' IDENTIFIED BY '<PASSWORD_FROM_DATABASE_APP_SECRET>' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE ON taskflow.* TO 'taskflow_app'@'%';

CREATE USER 'taskflow_migrator'@'%' IDENTIFIED BY '<PASSWORD_FROM_DATABASE_MIGRATOR_SECRET>' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES
ON taskflow.* TO 'taskflow_migrator'@'%';
FLUSH PRIVILEGES;
```

Ces noms correspondent au `project_name=taskflow` par défaut. Si tu changes ce nom,
adapte les identifiants SQL aux valeurs `username` des secrets Terraform.

Vérifie que les deux ExternalSecrets affichent `Ready=True` avant le déploiement. Le
compte runtime ne possède pas de droits DDL. Seul le Job `migrate` reçoit le compte
migrator. Supprime tout fichier temporaire contenant le secret maître dès la fin.
