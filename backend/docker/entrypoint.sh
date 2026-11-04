#!/bin/sh
# Entrypoint production : prépare Laravel puis lance php-fpm.
set -eu

cd /var/www/html

if [ -z "${APP_KEY:-}" ]; then
  echo "[entrypoint] APP_KEY manquant : arrêt." >&2
  exit 1
fi

# Migrations optionnelles (activées sur l'unique instance applicative).
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  echo "[entrypoint] Attente de la base puis migrations..."
  i=0
  until php artisan migrate --force --no-interaction; do
    i=$((i+1))
    [ "$i" -ge 30 ] && { echo "[entrypoint] Migrations impossibles après 30 essais." >&2; exit 1; }
    sleep 2
  done
  if [ "${RUN_SEEDER:-false}" = "true" ]; then
    php artisan db:seed --force --no-interaction
  fi
fi

# Caches générés avec l'environnement RÉEL du conteneur.
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

exec "$@"
