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

install_wp () {
	if ! [ -e index.php -a -e wp-includes/version.php ]; then
		echo >&2 "WordPress not found in $PWD - installing now..."
		chmod g+w /var/www/html
		if [ ! -e .htaccess ]; then
			echo -n "Creating HTACCESS File...."
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
			echo "Done."
		fi
		sudo -u wp-admin -i -- wp core download
		sudo -u wp-admin -i -- wp config create \
			--dbname=${WORDPRESS_DB_NAME:=wordpress} \
			--dbuser="${WORDPRESS_DB_USER:=root}" \
			--dbpass="${WORDPRESS_DB_PASSWORD:=}" \
			--dbhost="${WORDPRESS_DB_HOST:=mysql}" \
			--dbprefix="${WORDPRESS_TABLE_PREFIX:=wp_}" \
			--skip-check --extra-php <<PHP
// If we're behind a proxy server and using HTTPS, we need to alert Wordpress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
	\$_SERVER['HTTPS'] = 'on';
	define('WP_SITEURL', 'https://' . \$_SERVER['HTTP_HOST']);
	define('WP_HOME', 'https://' . \$_SERVER['HTTP_HOST']);
} else {
	define('WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST']);
	define('WP_HOME', 'http://' . \$_SERVER['HTTP_HOST']);
}
PHP
		echo "Checking for DB Access"
		#Using bang to permit to fail
		! sudo -u wp-admin -i -- wp db check
		if [ $? -ne 0 ] ; then
			echo "Db Error, Trying to Create DB"
			! sudo -u wp-admin -i -- wp db create
		fi
		sudo -u wp-admin -i -- wp core install \
			--url="${WORDPRESS_HTTP_HOST}" \
			--title="${WORDPRESS_SITE_TITLE}" \
			--admin_user="${WORDPRESS_ADMIN_USER}" \
			--admin_password="${WORDPRESS_ADMIN_PASS}" \
			--admin_email="${WORDPRESS_ADMIN_EMAIL}"
	fi


	# version 4.4.1 decided to switch to windows line endings, that breaks our seds and awks
	# https://github.com/docker-library/wordpress/issues/116
	# https://github.com/WordPress/WordPress/commit/1acedc542fba2482bab88ec70d4bea4b997a92e4

	sudo -u wp-admin -i -- wp config set DB_NAME ${WORDPRESS_DB_NAME:=wordpress}
	sudo -u wp-admin -i -- wp config set DB_USER "${WORDPRESS_DB_USER:=root}"
	sudo -u wp-admin -i -- wp config set DB_PASSWORD "${WORDPRESS_DB_PASSWORD:=}"
	sudo -u wp-admin -i -- wp config set DB_HOST "${WORDPRESS_DB_HOST:=mysql}"
	sudo -u wp-admin -i -- wp config set table_prefix "${WORDPRESS_TABLE_PREFIX:=wp_}" \

	if [ "$WORDPRESS_DEBUG" ]; then
		sudo -u wp-admin -i -- wp config set WP_DEBUG true --raw --type=constant
	else
		sudo -u wp-admin -i -- wp config set WP_DEBUG false --raw --type=constant
	fi

	if [ "$WORDPRESS_PLUGINS" ]; then
		sudo -u wp-admin -i -- wp plugin install --activate ${WORDPRESS_PLUGINS}
	fi

	if [ "$WORDPRESS_THEMES" ]; then 
 		sudo -u wp-admin -i -- wp theme install ${WORDPRESS_THEMES}
	fi
	# now that we're definitely done writing configuration, let's clear out the relevant envrionment variables (so that stray "phpinfo()" calls don't leak secrets from our code)

	echo -n "Reset permissions to the www-data user..."
	find . -user wp-admin -exec chown www-data {} \;
	echo "Done."
	echo -n "Reseting .wp-cli to wp-admin...."
	! chown -R wp-admin .wp-cli
	echo "Done."
	echo -n "Setting group write permissions..."
	find . \! -perm g+w -exec chmod g+w {} \;
	echo "Done."
	
}
if [ "$1" == apache2* ] || [ "$1" == php-fpm ] || [ "$1" == install ] ; then
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
		WORDPRESS_TABLE_PREFIX
		WORDPRESS_DEBUG
		WORDPRESS_PLUGINS
		WORDPRESS_THEMES
		WORDPRESS_SITE_TITLE
		WORDPRESS_ADMIN_USER
		WORDPRESS_ADMIN_PASS
		WORDPRESS_ADMIN_EMAIL
		WORDPRESS_HTTP_HOST
		"${uniqueEnvs[@]/#/WORDPRESS_}"

	)
	haveConfig=
	for e in "${envs[@]}"; do
		file_env "$e"
		if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
			haveConfig=1
		fi
	done

	if [ "$1" == install ] ; then
		install_wp
	fi

	for e in "${envs[@]}"; do
		unset "$e"
	done

fi

exec "$@"
