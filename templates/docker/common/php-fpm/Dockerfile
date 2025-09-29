# Stage 1: Build environment and Composer dependencies
FROM php:8.3-fpm-alpine AS builder

ARG SKIP_COMPOSER=false

RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        curl-dev \
        imagemagick-dev \
        libtool \
        libxml2-dev \
        postgresql-dev \
        sqlite-dev \
        libzip-dev \
        icu-dev \
    && apk add --no-cache \
        curl \
        git \
        postgresql-libs \
        imagemagick \
        libzip \
        icu \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        opcache \
        intl \
        zip \
        bcmath \
        soap \
        pcntl \
    && pecl install redis imagick \
    && docker-php-ext-enable redis imagick \
    && apk del .build-deps

WORKDIR /var/www
COPY . /var/www

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && if [ "$SKIP_COMPOSER" = "true" ]; then \
         echo "Skipping composer install in builder stage"; \
       else \
         composer install --no-dev --optimize-autoloader --no-interaction --no-progress --prefer-dist; \
       fi

# Stage 2: Production environment
FROM php:8.3-fpm-alpine AS production

RUN apk add --no-cache \
    postgresql-libs \
    imagemagick \
    libzip \
    icu \
    fcgi \
    procps \
    su-exec

RUN curl -o /usr/local/bin/php-fpm-healthcheck \
    https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

COPY ./docker/production/php-fpm/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh && chown www-data:www-data /usr/local/bin/entrypoint.sh

# Create an empty storage-init directory (storage may be excluded from build context)
RUN mkdir -p /var/www/storage-init
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/bin/docker-php-ext-* /usr/local/bin/

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN sed -i '/\[www\]/a pm.status_path = /status' /usr/local/etc/php-fpm.d/zz-docker.conf \
    && sed -i '/\[www\]/a catch_workers_output = yes' /usr/local/etc/php-fpm.d/zz-docker.conf \
    && sed -i '/\[www\]/a decorate_workers_output = no' /usr/local/etc/php-fpm.d/zz-docker.conf \
    && sed -i '/\[www\]/a clear_env = no' /usr/local/etc/php-fpm.d/zz-docker.conf

COPY --from=builder /var/www /var/www
WORKDIR /var/www
RUN chown -R www-data:www-data /var/www

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EXPOSE 9000
CMD ["php-fpm"]

# Stage 3: Development image
FROM production AS development

ARG XDEBUG_ENABLED=true
ARG XDEBUG_MODE=develop,coverage,debug,profile
ARG XDEBUG_HOST=host.docker.internal
ARG XDEBUG_IDE_KEY=DOCKER
ARG XDEBUG_LOG=/dev/stdout
ARG XDEBUG_LOG_LEVEL=0

USER root
RUN apk add --no-cache inotify-tools \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN if [ "${XDEBUG_ENABLED}" = "true" ]; then \
    pecl install xdebug && \
    docker-php-ext-enable xdebug && \
    echo "xdebug.mode=${XDEBUG_MODE}" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.idekey=${XDEBUG_IDE_KEY}" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.log=${XDEBUG_LOG}" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.log_level=${XDEBUG_LOG_LEVEL}" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.client_host=${XDEBUG_HOST}" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini ; \
    echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini ; \
fi

ARG UID=1000
ARG GID=1000
RUN addgroup -g ${GID} www || true \
    && adduser -D -u ${UID} -G www -s /bin/sh www || true
RUN sed -i "s/user = www-data/user = www/g" /usr/local/etc/php-fpm.d/www.conf \
   && sed -i "s/group = www-data/group = www/g" /usr/local/etc/php-fpm.d/www.conf

WORKDIR /var/www
COPY ./docker/development/php-fpm/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./docker/development/php/conf.d/opcache-dev.ini /usr/local/etc/php/conf.d/opcache-dev.ini
COPY ./docker/development/tools/watch-horizon.sh /usr/local/bin/watch-horizon.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/watch-horizon.sh \
    && chown www-data:www-data /usr/local/bin/entrypoint.sh /usr/local/bin/watch-horizon.sh
USER www-data
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EXPOSE 9000
CMD ["php-fpm"]
