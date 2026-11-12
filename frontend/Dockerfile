# Stage 1: Build React/Vite frontend
FROM node:24-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci --ignore-scripts

COPY . .
RUN npm run build

# Stage 2: Serve static assets with hardened unprivileged Nginx
FROM nginxinc/nginx-unprivileged:stable-alpine

# Mise à jour de sécurité des paquets système Alpine
USER root
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/*

# Configuration Nginx et fichiers statiques
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

# Exécution stricte sans privilèges (uid 101)
USER 101

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0 || exit 1

CMD ["nginx", "-g", "daemon off;"]
