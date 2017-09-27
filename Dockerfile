FROM wordpress:4.8.1-php7.1-apache

RUN apt-get update && apt-get install -y mysql-client bsd-mailx zip unzip imagemagick && apt-get clean
COPY log.ini execution.ini /usr/local/etc/php/conf.d/
COPY remoteip.conf /etc/apache2/conf-available
RUN a2enmod remoteip 
RUN a2enconf remoteip

