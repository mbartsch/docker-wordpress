FROM wordpress:4.9.7-apache as builder
RUN echo no | pecl install redis 

FROM wordpress:4.9.7-apache
RUN apt update && apt upgrade -y && apt install -y mysql-client bsd-mailx zip unzip imagemagick && apt-get clean
RUN curl -o /usr/local/bin/wp  https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x /usr/local/bin/wp
RUN printf "\n\n\n\n\n\n\n\n\n" | openssl req -x509 -newkey rsa:4096 -keyout /etc/ssl/private/ssl-cert-snakeoil.key -out /etc/ssl/certs/ssl-cert-snakeoil.pem -days 365 -nodes
COPY log.ini execution.ini /usr/local/etc/php/conf.d/
COPY remoteip.conf /etc/apache2/conf-available
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20170718/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-20170718/redis.so
RUN a2enmod ssl 
RUN a2ensite default-ssl
RUN docker-php-ext-enable redis
RUN a2enmod remoteip 
RUN a2enconf remoteip
RUN sed -i 's/^LogFormat "%h/LogFormat "%a/' /etc/apache2/apache2.conf
RUN sed -i 's/LogLevel warn/LogLevel info/' /etc/apache2/apache2.conf
RUN sed -i 's/LogLevel .*/LogLevel info/' /etc/apache2/sites-available/*

COPY docker-entrypoint.sh /usr/local/bin
