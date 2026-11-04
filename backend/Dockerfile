# syntax=docker/dockerfile:1.7
# ─────────────────────────────────────────────────────────────
# TaskFlow API — image de production (PHP-FPM, Alpine, non-root)
# ─────────────────────────────────────────────────────────────

# 1) Dépendances Composer (sans dev)
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
      --no-dev --no-interaction --no-progress --no-scripts \
      --prefer-dist --optimize-autoloader --no-autoloader
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative --no-dev

# 2) Image finale : uniquement le runtime (pas de compilateur, git, pcov…)
FROM php:8.5-fpm-alpine AS runtime
COPY --from=ghcr.io/mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_mysql bcmath opcache pcntl \
 && apk add --no-cache curl fcgi \
 && rm -rf /var/cache/apk/* /usr/local/bin/install-php-extensions

COPY docker/php.ini /usr/local/etc/php/conf.d/zz-taskflow.ini
COPY docker/php-fpm-status.conf /usr/local/etc/php-fpm.d/zz-status.conf

WORKDIR /var/www/html
COPY --from=vendor --chown=www-data:www-data /app .
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# Le cache de config/routes est généré AU DÉMARRAGE (entrypoint), pas au build :
# sinon les variables d'environnement du serveur seraient ignorées.
RUN mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
 && chown -R www-data:www-data storage bootstrap/cache \
 && chmod -R ug+rwX storage bootstrap/cache

USER www-data
EXPOSE 9000
HEALTHCHECK --interval=15s --timeout=3s --start-period=30s --retries=5 \
  CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q pong || exit 1
ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm"]
