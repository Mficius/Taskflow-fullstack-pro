#!/bin/sh
# Entrypoint production : les caches Laravel sont construits AU DÉMARRAGE
# (et non au build) pour prendre en compte les variables d'environnement
# injectées par Kubernetes (ConfigMap / ExternalSecret).
set -eu

if [ "${1:-}" = "php-fpm" ] || [ "${1:-}" = "php" ]; then
  php artisan config:cache
  php artisan route:cache
  php artisan event:cache
fi

exec "$@"
