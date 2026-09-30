# TaskFlow Frontend

React + Material UI frontend for the TaskFlow Laravel API.

## Local development

1. Start Laravel on `http://localhost:8000`.
2. Copy `.env.example` to `.env` only if you need a custom API URL.
3. Run `npm install`.
4. Run `npm start`.

The development proxy in `package.json` forwards `/api` to `http://localhost:8000`.

The frontend now uses the backend for authentication, users, projects, tasks, comments and activity logs. No demo users or task/project persistence are kept in localStorage. Only the UI theme and selected project are local preferences.

## TaskFlow V3 — SaaS Workspace Upgrade

This version keeps the existing TaskFlow visual identity while adding a more complete project-management workflow:

- Project workspace with Overview / Board / List / Timeline / Members / Activity tabs
- Shared advanced filters: search, status, priority, project, assignee and due date
- Saved filter views stored locally per workspace
- Board and List are two views of the same filtered task dataset
- Drag-and-drop task movement between Kanban columns
- WIP/load signals and compact decision-oriented task cards
- Global Analytics page with project performance and workload distribution
- Clear project context and persistent sidebar navigation
- Existing API integration, authentication, comments and offline cache preserved

The frontend remains compatible with the existing backend API used by the original project.

## TaskFlow V4 Pro

V4 adds a more product-oriented SaaS interaction layer on top of the V3 workspace:
- hash-based contextual navigation (`#/dashboard`, `#/tasks`, `#/projects/:id/:tab`, etc.)
- global search / command palette with `Ctrl+K` / `Cmd+K`
- searchable projects, tasks, members and navigation actions
- notification center for overdue tasks and recent activity
- persistent project tab context in the URL
- analytics period selection scoped to task activity dates
- saved task views remain available through local storage

## TaskFlow V5 Pro

This frontend iteration adds a SaaS-oriented workspace layer:
- Inbox with unread/read state and attention views
- Searchable audit log surface
- Workspace delivery overview and "My work" panel
- Expanded RBAC navigation (admin/manager/member)
- Existing project workspace, board/list/timeline, analytics and command palette retained

Production note: frontend permissions are for UX only. Real authorization, tenant isolation, audit immutability and workspace membership must be enforced by the backend/API.
