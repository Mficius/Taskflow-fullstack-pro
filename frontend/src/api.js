import axios from "axios";

export const API = axios.create({
  baseURL: process.env.REACT_APP_API_URL || "/api",
  timeout: 15000,
  headers: { Accept: "application/json" },
});

API.interceptors.request.use(config => {
  try {
    const session = JSON.parse(localStorage.getItem("taskflow-session") || "null");
    if (session?.token) config.headers.Authorization = `Bearer ${session.token}`;
  } catch (_) {}
  return config;
});

export const loginApi = credentials => API.post("/auth/login", credentials);
export const meApi = () => API.get("/auth/me");
export const logoutApi = () => API.post("/auth/logout");
export const updateProfileApi = data => API.put("/auth/profile", data);
export const updatePasswordApi = data => API.put("/auth/password", data);

export const getTodos = params => API.get("/todos", { params });
export const createTodo = todo => API.post("/todos", todo);
export const updateTodo = (id, todo) => API.put(`/todos/${id}`, todo);
export const deleteTodo = id => API.delete(`/todos/${id}`);

export const getUsersApi = () => API.get("/users");
export const createUserApi = user => API.post("/users", user);
export const updateUserApi = (id, user) => API.put(`/users/${id}`, user);
export const deleteUserApi = id => API.delete(`/users/${id}`);

export const getProjectsApi = () => API.get("/projects");
export const getProjectApi = id => API.get(`/projects/${id}`);
export const createProject = project => API.post("/projects", project);
export const updateProject = (id, project) => API.put(`/projects/${id}`, project);
export const deleteProjectApi = id => API.delete(`/projects/${id}`);
export const addProjectMember = (projectId, userId) => API.post(`/projects/${projectId}/members`, { userId });
export const removeProjectMember = (projectId, userId) => API.delete(`/projects/${projectId}/members/${userId}`);

export const getTaskComments = taskId => API.get(`/todos/${taskId}/comments`);
export const createTaskComment = (taskId, comment) => API.post(`/todos/${taskId}/comments`, comment);
export const getActivityLog = params => API.get("/activity", { params });
export const getAuditLog = params => API.get("/audit-log", { params });

export const getDashboardApi = params => API.get("/dashboard", { params });
export const getAnalyticsApi = params => API.get("/analytics", { params });
export const searchApi = q => API.get("/search", { params: { q } });

export const getNotificationsApi = params => API.get("/notifications", { params });
export const getUnreadNotificationCountApi = () => API.get("/notifications/unread-count");
export const markNotificationReadApi = id => API.post(`/notifications/${id}/read`);
export const markAllNotificationsReadApi = () => API.post("/notifications/read-all");

export const getSavedViewsApi = resource => API.get("/saved-views", { params: resource ? { resource } : {} });
export const createSavedViewApi = data => API.post("/saved-views", data);
export const updateSavedViewApi = (id, data) => API.put(`/saved-views/${id}`, data);
export const deleteSavedViewApi = id => API.delete(`/saved-views/${id}`);

export const normalizeList = payload => {
  const value = payload?.data ?? payload;
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.data)) return value.data;
  if (Array.isArray(value?.items)) return value.items;
  if (Array.isArray(value?.results)) return value.results;
  return [];
};
export const normalizeTodos = normalizeList;

export const apiError = error => error?.response?.data?.message
  || Object.values(error?.response?.data?.errors || {})?.flat?.()?.[0]
  || error?.message
  || "Une erreur est survenue.";
