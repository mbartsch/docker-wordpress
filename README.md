This is based on the official wordpress (wordpress:4.9.2)

Added:
mailx
zip
unzip
mysql client
imagemagick
pecl-redis

Increase the execution time of php to 301 seconds


Include two new variables
WORDPRESS_DB_ROOT_USER
WORDPRESS_DB_ROOT_PASS


if the variables are set, a connection with this user and password
will be done to the database, and the database will be created and the
user for WORDPRESS_DB_USER will be created on the database with host '%'
to allow connection

Please note this is what I use internally for my WP sites on Docker Containers
It may not work for your environment :(
