#!/bin/sh
set -e

# 1. Attend que la base de données soit prête à recevoir des connexions
echo "Attente de la base de données..."
until php artisan db:monitor > /dev/null 2>&1; do
  sleep 1
done

# 2. Exécute automatiquement les migrations sans demander de confirmation
echo "Exécution des migrations..."
php artisan migrate --force

# 3. Lance la commande principale d'Apache (nécessaire pour garder le conteneur actif)
echo "Démarrage d'Apache..."
exec apache2-foreground
