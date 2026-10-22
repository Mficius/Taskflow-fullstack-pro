# TaskFlow Frontend

Frontend React 18 + Vite + Material UI pour l'API Laravel TaskFlow.

## Prérequis
- Node.js 20.19+ ou 22.12+ (Node.js 24 recommandé)
- npm
- API Laravel disponible sur `http://localhost:8000` en développement

## Développement local

```bash
npm ci
npm run dev
```

Vite démarre sur `http://localhost:3000`. Les requêtes `/api` sont transmises à `http://localhost:8000` par le proxy Vite.

Pour utiliser une autre URL d'API, créez un fichier `.env` à la racine du frontend :

```dotenv
VITE_API_URL=/api
VITE_API_PROXY_TARGET=http://localhost:8000
```

`VITE_API_URL` est l'URL utilisée par Axios dans le navigateur. `VITE_API_PROXY_TARGET` configure uniquement le proxy du serveur de développement Vite. Les variables `VITE_*` sont publiques : n'y placez aucun secret.

## Build et aperçu de production

```bash
npm run build
npm run preview
```

Vite génère le site statique dans `dist/`.

## Docker

```bash
docker build -t taskflow-frontend .
docker run --rm -p 8080:8080 taskflow-frontend
```

Ouvrez `http://localhost:8080`. Le conteneur sert les fichiers compilés par Nginx sur le port 8080.

> Important : le proxy configuré dans `vite.config.js` sert au développement uniquement. En production, configurez Nginx ou votre reverse proxy pour transmettre `/api` au backend Laravel, ou définissez `VITE_API_URL` au moment du build vers une URL d'API accessible depuis le navigateur.

## Fonctionnalités existantes

- Tableau de bord, tâches, projets et espaces de travail
- Kanban, filtres avancés, recherche et palette de commandes
- Analytics, boîte de réception, journal d'activité et audit
- Authentification et intégration Axios avec l'API Laravel
- Préférences locales pour le thème et le projet sélectionné

Les contrôles d'accès côté frontend sont uniquement ergonomiques. L'API doit appliquer les autorisations et l'isolation des données.
