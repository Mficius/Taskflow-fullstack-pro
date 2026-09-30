# TaskFlow Full Stack V6 Pro

Version intégrée du frontend TaskFlow V5 Pro et du backend Laravel V6 Pro.

## Architecture

- `frontend/code_frontend` — React 18 + MUI 7 + Axios
- `backend/backend` — Laravel 12 + Sanctum
- API REST sous `/api`

## Démarrage backend

```bash
cd backend/backend
cp .env.example .env
composer install
php artisan key:generate
php artisan migrate
php artisan serve --port=8000
```

## Démarrage frontend

```bash
cd frontend/code_frontend
npm ci
npm start
```

Le proxy React pointe par défaut vers `http://localhost:8000`.

Pour une autre API :

```bash
REACT_APP_API_URL=http://localhost:8000/api npm start
```

## Fonctionnalités connectées à l'API

- Authentification Sanctum
- Tasks + filtres
- Projects + members
- Dashboard
- Analytics 7/30/90 jours
- Global search
- Notifications persistantes
- Inbox
- Saved Views
- Activity / Audit Log
- Comments
- RBAC côté backend

## Vérifications effectuées

- Syntaxe PHP vérifiée avec `php -l` sur l'application, les routes et les migrations.
- Le build React n'a pas pu être exécuté dans l'environnement de génération car l'installation des dépendances npm n'a pas terminé dans le délai disponible.

## Sécurité

Le frontend ne doit pas être considéré comme une frontière de sécurité. Les accès aux projets, tâches, utilisateurs et ressources doivent rester contrôlés par Laravel. Sanctum protège les endpoints API avec des tokens Bearer.
