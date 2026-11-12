#!/bin/sh
set -e

# Génère une APP_KEY uniquement pour le développement local si le fichier .env est vide.
if [ ! -f .env ]; then
    cp .env.example .env
fi
if ! grep -q '^APP_KEY=base64:' .env; then
    php artisan key:generate --force --no-interaction
fi

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
