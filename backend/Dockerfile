# syntax=docker/dockerfile:1.7
###############################################################################
# Image PRODUCTION Laravel (php-fpm) - durcie
#  - multi-stage : aucun outil de build (git, composer, PHPIZE) dans l'image finale
#  - exécution en non-root (www-data), compatible readOnlyRootFilesystem
#  - pas de pcov/xdebug, opcache activé, expose_php désactivé
#  - bundle CA RDS embarqué (TLS obligatoire vers MySQL)
###############################################################################

# ---- 1. Dépendances Composer (sans dev) --------------------------------------
FROM composer:2.10 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
      --no-dev --no-interaction --no-progress --no-scripts --no-autoloader --prefer-dist
COPY . .
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative \
 && rm -rf tests .env .env.* storage/logs/* node_modules

# ---- 2. Bundle CA RDS -------------------------------------------------------------
FROM alpine:3.23 AS certs
RUN apk add --no-cache curl \
 && curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /rds-global-bundle.pem \
 && test -s /rds-global-bundle.pem

# ---- 3. Image finale ------------------------------------------------------------
FROM php:8.4-fpm-alpine3.23

RUN apk add --no-cache oniguruma \
 && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS oniguruma-dev \
 && docker-php-ext-install -j"$(nproc)" pdo_mysql mbstring bcmath pcntl exif opcache \
 && apk del .build-deps \
 && rm -rf /tmp/* /var/cache/apk/* \
 && apk upgrade --no-cache

COPY docker/php-prod.ini "$PHP_INI_DIR/conf.d/zz-taskflow.ini"
COPY --from=certs /rds-global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem

WORKDIR /var/www/html
COPY --from=vendor --chown=root:root /app .

# Répertoires inscriptibles (montés en emptyDir sous Kubernetes)
RUN mkdir -p storage/app storage/framework/cache/data storage/framework/sessions \
             storage/framework/views storage/logs bootstrap/cache \
 && chown -R www-data:www-data storage bootstrap/cache \
 && chmod -R u+rwX,g-w,o-rwx storage bootstrap/cache

COPY --chmod=0755 docker/entrypoint-prod.sh /usr/local/bin/entrypoint
ENV APP_ENV=production APP_DEBUG=false \
    MYSQL_ATTR_SSL_CA=/etc/ssl/certs/rds-global-bundle.pem

USER www-data
EXPOSE 9000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD php-fpm -t >/dev/null 2>&1 || exit 1

ENTRYPOINT ["entrypoint"]
CMD ["php-fpm"]
