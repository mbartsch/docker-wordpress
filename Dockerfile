FROM wordpress:4.8.1-php7.1-fpm-alpine

RUN apk --no-cache add mysql
