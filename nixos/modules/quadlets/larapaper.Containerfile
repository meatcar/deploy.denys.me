FROM ghcr.io/usetrmnl/larapaper:0.37.1@sha256:6807254a810025c847ba363653daf879af6ab0079a3eb0b23f9adb90e227bd8d AS app
FROM bnussbau/serversideup-php:8.4-fpm-nginx-alpine-imagick-chromium@sha256:0d40b63c8500d6c334bb0ec7b7e30be21f181046046acf9f8af8cabd3e2bfe33

COPY --from=app --chown=www-data:www-data /var/www/html /var/www/html
COPY --from=app /usr/local/bin/trmnl-liquid-cli /usr/local/bin/trmnl-liquid-cli

ENV APP_VERSION=0.37.1 AUTORUN_ENABLED=true TRMNL_LIQUID_ENABLED=1

RUN php -r 'exit(PHP_VERSION_ID >= 80427 && PHP_VERSION_ID < 80500 ? 0 : 1);' \
    && composer check-platform-reqs --no-dev
