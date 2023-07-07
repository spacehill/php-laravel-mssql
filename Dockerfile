ARG MAJOR_PHP_VERSION=8.2.7

FROM php:${MAJOR_PHP_VERSION}-fpm-bookworm

ARG MAJOR_PHP_VERSION
ARG NGINX_VERSION=1.20~buster

LABEL maintainer="Tobias Hillen (tobias.hillen@spacehill.de)"

ENV TZ Australia/Sydney

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
    curl gcc make autoconf libc-dev zlib1g-dev libicu-dev g++ pkg-config gnupg2 dirmngr wget apt-transport-https lsb-release ca-certificates \
    python3-pip python3-setuptools git default-mysql-client libmemcached-dev libz-dev libpq-dev libjpeg-dev libpng-dev libfreetype6-dev \
    libssl-dev libwebp-dev libmcrypt-dev libonig-dev libxrender1 libxext6 librdkafka-dev openssh-server sudo nginx dialog && \
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

RUN set -eux; \
    # install php pdo_mysql extention
    docker-php-ext-install pdo_mysql; \
    # install php pdo_pgsql extention
    docker-php-ext-install pdo_pgsql; \
    # install php gd library
    docker-php-ext-configure gd \
    --prefix=/usr \
    --with-jpeg \
    --with-webp \
    --with-freetype; \
    docker-php-ext-install gd; \
    # install php pcntl lib
    docker-php-ext-install pcntl; \
    # install php opcache lib
    docker-php-ext-install opcache; \
    # install php sockets
    docker-php-ext-install sockets; \
    # install php bcmath
    docker-php-ext-install bcmath; \
    # install php intl
    docker-php-ext-configure intl; \
    docker-php-ext-install intl; \
    php -r 'var_dump(gd_info());'

RUN set -xe; \
    apt-get update -yqq && \
    pecl channel-update pecl.php.net && \
    apt-get install -yqq \
    apt-utils \
    libzip-dev zip unzip && \
    docker-php-ext-configure zip; \
    docker-php-ext-install zip && \
    php -m | grep -q 'zip'

# then install the drivers
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/debian/9/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install msodbcsql17 unixodbc-dev -y && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

# install pecl drivers
RUN pecl install sqlsrv-5.10.0 && \
    pecl install pdo_sqlsrv-5.10.0 && \
    docker-php-ext-enable sqlsrv && \
    docker-php-ext-enable pdo_sqlsrv

# install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# configure locale
ARG LOCALE=POSIX
ENV LC_ALL ${LOCALE}

# install nodejs 18
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN apt-get install -y nodejs
RUN npm install npm@latest -g 
RUN npm install yarn -g

# clean up
RUN apt-get autoremove -y && \
    apt-get autoclean -y && \
    apt-get clean -y

RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    rm /var/log/lastlog /var/log/faillog

# output the php version for verification
RUN set -xe; php -v | head -n 1 | grep -q "PHP ${PHP_VERSION}."

ARG PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

# copy over laravel specific php ini 
COPY ini/laravel.ini /usr/local/etc/php/conf.d
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
COPY ini/opcache.ini /usr/local/etc/php/conf.d

# the base image adds a bunch of pools that we dont want
RUN rm /usr/local/etc/php-fpm.d/*.conf

# copy over our laravel fpm pool config
COPY ini/laravel.pool.conf /usr/local/etc/php-fpm.d/

# copy over nginx.conf
COPY nginx.conf /etc/nginx/

WORKDIR /var/www

RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache && \
    chown -R www-data:www-data storage bootstrap/cache && \
    chmod -R 744 storage

RUN mkdir /var/run/php
RUN chown www-data:www-data /var/run/php storage bootstrap/cache
