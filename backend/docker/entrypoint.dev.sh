#!/bin/sh
# Entrypoint développement : attend MySQL, migre, seed (démo) puis lance Apache.
set -e
cd /var/www/html

[ -d vendor ] || composer install --no-interaction

i=0
until php artisan migrate --force --no-interaction; do
  i=$((i+1)); [ "$i" -ge 30 ] && { echo "Base de données injoignable." >&2; exit 1; }
  echo "Attente de la base de données..."; sleep 2
done

[ "${RUN_SEEDER:-true}" = "true" ] && php artisan db:seed --force --no-interaction || true

exec apache2-foreground
