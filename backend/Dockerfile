# Etape composer

FROM composer:2 as vendorSave

WORKDIR /app

COPY composer.json composer.lock ./

# 2. Installer les dépendances (cette étape restera en cache si vos dépendances ne changent pas)
RUN composer install  \
    --no-dev  \
    --optimize-autoloader \
    --prefer-dist \ 
    --no-scripts \
    --no-autoloader

# 3. Copier le reste du code source de l'application
COPY . .

# 4. Générer l'autoloader final avec votre code
RUN composer dump-autoload --optimize --no-dev
# Etape php Etape finale

FROM php:8.4-fpm-alpine3.23

RUN apk add --no-cache \
    bash \
    curl \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    oniguruma-dev \
    libxml2-dev \
    zip \
    unzip \
    git \
    $PHPIZE_DEPS \
 && apk update && apk upgrade --no-cache


RUN pecl install pcov && docker-php-ext-enable pcov

RUN docker-php-ext-install pdo \
    pdo_mysql \
    mbstring \
    xml \
    pcntl \
    exif \
    bcmath


WORKDIR /var/www/html

# copier le dossier vendor
COPY --from=vendorSave /app . 

# Optimiser laravel

RUN php artisan package:discover --ansi && \
    php artisan config:cache || true && \
    php artisan route:cache || true && \
    php artisan view:cache || true


RUN chown -R www-data:www-data /var/www/html

USER www-data

EXPOSE 9000

CMD ["php-fpm"]
