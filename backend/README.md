# TaskFlow API — SaaS Backend V6

Laravel 12 REST API designed to back the TaskFlow V5 frontend and its SaaS-oriented workspace UX.

## What changed in V6

- Sanctum bearer-token authentication.
- Profile and password endpoints used by Settings.
- Role-based access: `admin`, `manager`, `member`.
- Project membership authorization.
- Tasks with status, priority, due date, description, assignee and project.
- Server-side task filtering for search, status, priority, assignee and due dates.
- Project detail endpoint with members and tasks.
- Comments with activity + notifications.
- Rich activity/audit feed with `taskId` and `projectId` exposed for the frontend.
- Dashboard aggregation endpoint.
- Analytics aggregation endpoint.
- Global search endpoint for Command Palette / global search.
- Persistent notifications with unread count and read state.
- Persistent saved views for advanced filters.
- CORS configuration for the React development server.
- Validation and authorization remain enforced server-side.

## Demo accounts

- `admin@taskflow.local` / `admin123`
- `manager@taskflow.local` / `manager123`
- `member@taskflow.local` / `member123`

Change these credentials before using the application outside a local demo environment.

## Setup

```bash
composer install
cp .env.example .env
php artisan key:generate
# For SQLite:
touch database/database.sqlite
php artisan migrate --seed
php artisan serve --host=0.0.0.0 --port=8000
```

The API is available under `/api`.

## Frontend connection

The React frontend can keep using:

```env
REACT_APP_API_URL=http://localhost:8000/api
```

When both applications run through Docker/reverse proxy, point `REACT_APP_API_URL` to the public API origin instead.

## Main endpoints

### Authentication

- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/logout`
- `PUT /api/auth/profile`
- `PUT /api/auth/password`

### Tasks

- `GET /api/todos`
- `POST /api/todos`
- `GET /api/todos/{todo}`
- `PUT /api/todos/{todo}`
- `DELETE /api/todos/{todo}`
- `GET /api/todos/{todo}/comments`
- `POST /api/todos/{todo}/comments`

Optional task filters on `GET /api/todos`:

```text
?projectId=1
?status=in_progress
?priority=high
?assigneeId=3
?q=deploy
?due=overdue|today|upcoming|none
```

### Projects

- `GET /api/projects`
- `GET /api/projects/{project}`
- `POST /api/projects`
- `PUT /api/projects/{project}`
- `DELETE /api/projects/{project}`
- `POST /api/projects/{project}/members`
- `DELETE /api/projects/{project}/members/{userId}`

### Workspace / SaaS

- `GET /api/dashboard?days=30`
- `GET /api/analytics?days=30&projectId=1`
- `GET /api/search?q=deploy`
- `GET /api/notifications`
- `GET /api/notifications/unread-count`
- `POST /api/notifications/{notification}/read`
- `POST /api/notifications/read-all`
- `GET /api/saved-views?resource=tasks`
- `POST /api/saved-views`
- `PUT /api/saved-views/{savedView}`
- `DELETE /api/saved-views/{savedView}`

### Activity / Audit

- `GET /api/activity`
- `GET /api/audit-log`

Both endpoints expose activity metadata such as `taskId` and `projectId`, which lets the frontend keep project activity contextual.

### Users

- `GET /api/users`
- `POST /api/users` — admin
- `PUT /api/users/{user}` — admin
- `DELETE /api/users/{user}` — admin

## API design notes

The backend remains the source of truth for authorization. The frontend role checks are only UX safeguards; they must not be treated as security boundaries.

Authentication uses Laravel Sanctum bearer tokens. This is compatible with the current Axios interceptor in the TaskFlow frontend. FastAPI's equivalent architecture would normally use OAuth2/JWT, but this backend is Laravel, so Sanctum is retained rather than introducing a second authentication stack.

## Tests

Run:

```bash
php artisan test
```

The environment used to prepare this archive did not contain Composer's generated `vendor/autoload.php`, so the test suite could not be executed here. PHP syntax validation was run across the application, routes and migrations.
