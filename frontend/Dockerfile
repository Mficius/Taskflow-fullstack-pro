
# premiere etape : builder l'application react
FROM node:24-alpine as builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --ignore-scripts

COPY . .

RUN npm run build


# deuxieme etape : servir l'application avec nginx
FROM nginxinc/nginx-unprivileged:stable-alpine


COPY --from=builder /app/build /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]