#!/bin/bash

# terminate on errors
set -e

# Check if volume is empty
# Generate secrets
curl -f https://api.wordpress.org/secret-key/1.1/salt/ >> /usr/src/wordpress/wp-secrets.php
    
#Start mysql 
/etc/init.d/mysqld start
    
# Generate database passwords if does not exists in volume
MYSQL_WORDPRESS_USER="wordpress";
MYSQL_WORDPRESS_DATABASE="wordpress";
    
# A file in a docker volume to be persisted. This file also is used to know if backup must be restored or not.
MYSQL_PASSWORD_FILE="/var/lib/mysql/autogenerated"

if [ ! -f "$MYSQL_PASSWORD_FILE" ] ; 
then 
	echo 'Setting up wp-content volume'
	# Copy wp-content from Wordpress src to volume
	cp -r /usr/src/wordpress/wp-content /var/www/
	chown -R nobody.nobody /var/www


	MYSQL_RANDOM_ROOT_PASSWORD=`pwgen -s 40 1`;
	MYSQL_WORDPRESS_USER_PASSWORD=`pwgen -s 40 1`;
	
	#Create mysql user
	mysql -e "CREATE DATABASE ${MYSQL_WORDPRESS_DATABASE};"
	mysql -e "CREATE USER ${MYSQL_WORDPRESS_USER}@localhost IDENTIFIED BY '${MYSQL_WORDPRESS_USER_PASSWORD}';"
	mysql -e "GRANT ALL PRIVILEGES ON ${MYSQL_WORDPRESS_DATABASE}.* TO '${MYSQL_WORDPRESS_USER}'@'localhost';"
	mysql -e "FLUSH PRIVILEGES;"
    
	#Set root password
	mysqladmin -u root password $MYSQL_RANDOM_ROOT_PASSWORD
	echo "GENERATED ROOT PASSWORD AS '$MYSQL_RANDOM_ROOT_PASSWORD'"            
	echo "GENERATED WORDPRESS USER PASSWORD AS '$MYSQL_WORDPRESS_USER_PASSWORD'" 

	#Copy passwords for next deploy
	echo $MYSQL_RANDOM_ROOT_PASSWORD > $MYSQL_PASSWORD_FILE
	echo $MYSQL_WORDPRESS_USER_PASSWORD >> $MYSQL_PASSWORD_FILE
	
	#Update configuration files
	echo "define('DB_USER', '${MYSQL_WORDPRESS_USER}');" >> /usr/src/wordpress/wp-secrets.php
	echo "define('DB_PASSWORD', '${MYSQL_WORDPRESS_USER_PASSWORD}');" >> /usr/src/wordpress/wp-secrets.php
	echo "define('DB_HOST', 'localhost');" >> /usr/src/wordpress/wp-secrets.php
	echo "define('DB_NAME', '${MYSQL_WORDPRESS_DATABASE}');" >> /usr/src/wordpress/wp-secrets.php
	echo "define('DB_CHARSET', 'utf8');" >> /usr/src/wordpress/wp-secrets.php
	echo "define('DB_COLLATE', '');" >> /usr/src/wordpress/wp-secrets.php
    
	#Restore backup
	sed -i "1 s/^/USE ${MYSQL_WORDPRESS_DATABASE};\n/" /usr/src/wordpress/database_backup.sql
	sed -i -e "s|'siteurl', '.*', 'yes'|'siteurl', '${DOMAIN}', 'yes'|g" /usr/src/wordpress/database_backup.sql
	sed -i -e "s|'home', '.*', 'yes'|'home', '${DOMAIN}', 'yes'|g" /usr/src/wordpress/database_backup.sql
	mysql -uroot -p${MYSQL_RANDOM_ROOT_PASSWORD} < /usr/src/wordpress/database_backup.sql
	rm -f /usr/src/wordpress/database_backup.sql
	chown nobody:nobody -R /usr/src/wordpress/*
else    
	#Read password from file in volume
	MYSQL_RANDOM_ROOT_PASSWORD=`head -1 ${MYSQL_PASSWORD_FILE}`;
	MYSQL_WORDPRESS_USER_PASSWORD=`tail -1 ${MYSQL_PASSWORD_FILE}`;
fi
    
    #Get domain from variable set at docker run or use default value.
if [ -z ${DOMAIN} ]; 
then
	DOMAIN="localhost"
fi
    
#fi
exec "$@"
