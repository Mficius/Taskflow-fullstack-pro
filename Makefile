.PHONY: init up down logs test-backend test-frontend test-infra lint-infra localstack-up localstack-test localstack-down demo-up demo-deploy demo-down

TF := infrastructure/terraform

init: ## Crée .env avec des secrets aléatoires (dev)
	@test -f .env || { cp .env.example .env; \
	  sed -i "s|^APP_KEY=.*|APP_KEY=base64:$$(openssl rand -base64 32)|" .env; \
	  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$$(openssl rand -hex 16)|" .env; \
	  sed -i "s|^DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=$$(openssl rand -hex 16)|" .env; \
	  echo ".env créé"; }

up: init ## Démarre l'application en local (http://localhost:8080)
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=100

test-backend:
	cd backend && composer install && cp -n .env.example .env && php artisan key:generate && php artisan test

test-frontend:
	cd frontend && npm ci && npm test

# ── Infrastructure : tests sans compte AWS ─────────────────
lint-infra: ## fmt + validate
	terraform -chdir=$(TF) fmt -check -recursive
	terraform -chdir=$(TF) init -backend=false -input=false && terraform -chdir=$(TF) validate

test-infra: lint-infra ## Tests unitaires (mock_provider) + politiques OPA
	terraform -chdir=$(TF) test
	conftest verify -p infrastructure/policy

# ── LocalStack : applique réellement l'infra sur un AWS simulé ─
localstack-up:
	docker compose -f infrastructure/localstack/docker-compose.yml up -d --wait

localstack-test: localstack-up ## Applique + teste sur LocalStack (nécessite LOCALSTACK_AUTH_TOKEN pour ECS/RDS/ELB)
	./infrastructure/localstack/run-tests.sh

localstack-down:
	docker compose -f infrastructure/localstack/docker-compose.yml down -v

# ── Démonstration sur un vrai compte AWS (portfolio) ───────
demo-up: ## Crée l'infra, pousse les images, déploie (≈ 15 min, ~3 $/jour)
	@printf 'terraform {\n  backend "local" {}\n}\n' > $(TF)/backend_override.tf
	terraform -chdir=$(TF) init -input=false
	terraform -chdir=$(TF) apply -auto-approve -input=false
	./scripts/demo-deploy.sh

demo-deploy: ## Redéploie l'application (infra déjà créée)
	./scripts/demo-deploy.sh

demo-down: ## DÉTRUIT toute l'infra de démonstration (coût → 0)
	@printf 'terraform {\n  backend "local" {}\n}\n' > $(TF)/backend_override.tf
	terraform -chdir=$(TF) init -input=false
	terraform -chdir=$(TF) destroy -auto-approve -input=false
