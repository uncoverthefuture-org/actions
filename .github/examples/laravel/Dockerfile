# syntax=docker/dockerfile:1
FROM php:8.2-cli AS base
WORKDIR /app
COPY . /app
RUN apt-get update && apt-get install -y git unzip libzip-dev \
    && docker-php-ext-install zip pdo pdo_mysql \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer install --no-dev --optimize-autoloader --no-interaction
EXPOSE 8000
ENV TARGET_PORT=8000
CMD php artisan serve --host=0.0.0.0 --port=${TARGET_PORT:-8000}
