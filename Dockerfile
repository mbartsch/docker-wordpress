FROM wordpress:4.8.1-php7.1-apache

RUN apt-get update && apt-get install -y mysql-client && apt-get clean
