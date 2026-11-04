# Passerelle nginx (non-root) : reverse-proxy, en-têtes de sécurité, rate-limit.
# La configuration est un template rendu au démarrage avec BACKEND_HOST / FRONTEND_HOST / LISTEN_PORT.
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY prod.conf.template /etc/nginx/templates/default.conf.template
ENV BACKEND_HOST=127.0.0.1 FRONTEND_HOST=127.0.0.1 LISTEN_PORT=8000
EXPOSE 8000
