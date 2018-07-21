FROM wordpress:4.9.7-apache as builder
RUN echo no | pecl install redis 

FROM wordpress:4.9.7-apache
RUN apt-get update && apt-get install -y mysql-client bsd-mailx zip unzip imagemagick && apt-get clean
COPY log.ini execution.ini /usr/local/etc/php/conf.d/
COPY remoteip.conf /etc/apache2/conf-available
COPY --from=builder /usr/local/lib/php/extensions/no-debug-non-zts-20170718/redis.so /usr/local/lib/php/extensions/no-debug-non-zts-20170718/redis.so
RUN docker-php-ext-enable redis
RUN a2enmod remoteip 
RUN a2enconf remoteip
RUN sed -i 's/^LogFormat "%h/LogFormat "%a/' /etc/apache2/apache2.conf
RUN sed -i 's/LogLevel warn/LogLevel info/' /etc/apache2/apache2.conf
RUN sed -i 's/LogLevel .*/LogLevel info/' /etc/apache2/sites-available/*

COPY docker-entrypoint.sh /usr/local/bin
