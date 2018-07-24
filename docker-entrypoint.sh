#!/bin/bash -x
set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	if [ "$(id -u)" = '0' ]; then
		case "$1" in
			*) # php-fpm
				user='www-data'
				group='www-data'
				;;
		esac
	else
		user="$(id -u)"
		group="$(id -g)"
	fi

	if ! [ -e index.php -a -e wp-includes/version.php ]; then
		echo >&2 "WordPress not found in $PWD - installing now..."
		chmod g+w /var/www/html
		sudo -u wp-admin -i -- wp core download
		sudo -u wp-admin -i -- wp config create \
			--dbname=${WORDPRESS_DB_NAME:=wordpress} \
			--dbuser="${WORDPRESS_DB_USER:=root}" \
			--dbpass="${WORDPRESS_DB_PASSWORD:=}" \
			--dbhost="${WORDPRESS_DB_HOST:=mysql}" \
			--dbprefix="${WORDPRESS_TABLE_PREFIX:=wp_}" \
			--skip-check
		sudo -u wp-admin -i -- wp db check || EXIT_CODE=$? && true
		if [ $EXIT_CODE -ne 0 ] ; then
			sudo -u wp-admin -i -- wp db create --dbuser=${MYSQL_ENV_MYSQL_USER:-root} --dbpass=${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-}
		fi
		if [ ! -e .htaccess ]; then
			# NOTE: The "Indexes" option is disabled in the php:apache base image
			cat > .htaccess <<-'EOF'
				# BEGIN WordPress
				<IfModule mod_rewrite.c>
				RewriteEngine On
				RewriteBase /
				RewriteRule ^index\.php$ - [L]
				RewriteCond %{REQUEST_FILENAME} !-f
				RewriteCond %{REQUEST_FILENAME} !-d
				RewriteRule . /index.php [L]
				</IfModule>
				<IfModule mod_php.c>
				php_value upload_max_filesize 64M
				php_value post_max_size 64M
				php_value max_execution_time 300
				php_value max_input_time 300
				</IfModule>
				# END WordPress
			EOF
			chown "$user:$group" .htaccess
		fi
	fi

	# TODO handle WordPress upgrades magically in the same way, but only if wp-includes/version.php's $wp_version is less than /usr/src/wordpress/wp-includes/version.php's $wp_version

	# allow any of these "Authentication Unique Keys and Salts." to be specified via
	# environment variables with a "WORDPRESS_" prefix (ie, "WORDPRESS_AUTH_KEY")
	uniqueEnvs=(
		AUTH_KEY
		SECURE_AUTH_KEY
		LOGGED_IN_KEY
		NONCE_KEY
		AUTH_SALT
		SECURE_AUTH_SALT
		LOGGED_IN_SALT
		NONCE_SALT
	)
	envs=(
		WORDPRESS_DB_HOST
		WORDPRESS_DB_USER
		WORDPRESS_DB_PASSWORD
		WORDPRESS_DB_NAME
		"${uniqueEnvs[@]/#/WORDPRESS_}"
		WORDPRESS_TABLE_PREFIX
		WORDPRESS_DEBUG
	)
	haveConfig=
	for e in "${envs[@]}"; do
		file_env "$e"
		if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
			haveConfig=1
		fi
	done

	# version 4.4.1 decided to switch to windows line endings, that breaks our seds and awks
	# https://github.com/docker-library/wordpress/issues/116
	# https://github.com/WordPress/WordPress/commit/1acedc542fba2482bab88ec70d4bea4b997a92e4
	sed -ri -e 's/\r$//' wp-config*

	if [ ! -e wp-config.php ]; then
			awk '/^\/\*.*stop editing.*\*\/$/ && c == 0 { c = 1; system("cat") } { print }' wp-config-sample.php > wp-config.php <<'EOPHP'
// If we're behind a proxy server and using HTTPS, we need to alert Wordpress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
	$_SERVER['HTTPS'] = 'on';
	define('WP_SITEURL', 'https://' . $_SERVER['HTTP_HOST'] . '/');
	define('WP_HOME', 'https://' . $_SERVER['HTTP_HOST'] . '/');
} else {
	define('WP_SITEURL', 'http://' . $_SERVER['HTTP_HOST'] . '/');
	define('WP_HOME', 'http://' . $_SERVER['HTTP_HOST'] . '/');
}
EOPHP
		chown "$user:$group" wp-config.php
	fi

	sudo -u wp-admin -i -- wp config create \
		--dbname=${WORDPRESS_DB_NAME:=wordpress} \
		--dbuser="${WORDPRESS_DB_USER:=root}" \
		--dbpass="${WORDPRESS_DB_PASSWORD:=}" \
		--dbhost="${WORDPRESS_DB_HOST:=mysql}" \
		--dbprefix="${WORDPRESS_TABLE_PREFIX:=wp_}" \
		--skip-salts --force

	if [ "$WORDPRESS_DEBUG" ]; then
		sudo -u wp-admin -i -- wp config set WP_DEBUG true --raw --type=constant
	fi

	# now that we're definitely done writing configuration, let's clear out the relevant envrionment variables (so that stray "phpinfo()" calls don't leak secrets from our code)
	for e in "${envs[@]}"; do
		unset "$e"
	done
fi

exec "$@"
