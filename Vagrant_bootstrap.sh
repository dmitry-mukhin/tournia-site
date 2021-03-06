#!/usr/bin/env bash

apt-get update

#Install php repository
apt-get install -y language-pack-en-base
LC_ALL=en_US.UTF-8 add-apt-repository -y ppa:ondrej/php

apt-get update
apt-get install -y apache2 php7.1 git debconf-utils npm

# Install bower (for Ionic app)
#if command -v bower > /dev/null 2>&1; then
#  echo bower is installed
#else
#    ln -s /usr/bin/nodejs /usr/bin/node
#    npm install -g bower ionic cordova gulp
#fi

# Make symbolic link from /vagrant to /var/www (but only if that hasn't been done)
if [ ! -L "/var/www" ]; then
  rm -rf /var/www
  ln -fs /vagrant /var/www
fi

# Enable mod_rewrite
a2enmod rewrite

# in Apache settings, change /var/www/html to /var/www/public_html, and enable directory to enable mod_rewrite
sed -i 's/\/var\/www\/html/\/var\/www\/public_html\n\n<Directory \/var\/www>\nOrder allow,deny\nAllow from all\nAllowOverride All\n<\/Directory>/g' /etc/apache2/sites-enabled/000-default.conf

# Adding ServerName, but only if that hasn't been done yet
if [ $(grep -c "ServerName vagrantDev" "/etc/apache2/sites-enabled/000-default.conf") -lt 1 ]
then
    sed -i '1s/^/ServerName vagrantDev\n\n/' /etc/apache2/sites-enabled/000-default.conf
fi

# Setting date.timezone in php.ini
sed -i 's/;date.timezone =/date.timezone = Europe\/Amsterdam/g' /etc/php/7.1/apache2/php.ini
sed -i 's/;date.timezone =/date.timezone = Europe\/Amsterdam/g' /etc/php/7.1/cli/php.ini

# Change upload_max_filesize to 32MB
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 32M/g' /etc/php/7.1/apache2/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 32M/g' /etc/php/7.1/apache2/php.ini


# Show errors, because it's a development server
sed -i 's/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL & ~E_DEPRECATED/g' /etc/php/7.1/apache2/php.ini
sed -i 's/display_errors = Off/display_errors = On/g' /etc/php/7.1/apache2/php.ini
sed -i 's/display_startup_errors = Off/display_startup_errors = On/g' /etc/php/7.1/apache2/php.ini


# Run apache with user&group vagrant, to prevent problems with folder permissions
sed -i 's/APACHE_RUN_USER=www-data/APACHE_RUN_USER=vagrant/' /etc/apache2/envvars
sed -i 's/APACHE_RUN_GROUP=www-data/APACHE_RUN_GROUP=vagrant/' /etc/apache2/envvars

# Restart apache2
service apache2 restart

# Install MySQL server
echo mysql-server-5.7 mysql-server/root_password password vagrant | debconf-set-selections
echo mysql-server-5.7 mysql-server/root_password_again password vagrant | debconf-set-selections
apt-get install -y mysql-server php7.1-mysql

# Change the mysql bind-address
sed -i "s/^bind-address.*/bind-address=0.0.0.0/" /etc/mysql/my.cnf
echo "sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION" >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Restart mysql
service mysql restart

# Install phpmyadmin
echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | debconf-set-selections
echo 'phpmyadmin phpmyadmin/app-password-confirm password vagrant' | debconf-set-selections
echo 'phpmyadmin phpmyadmin/mysql/admin-pass password vagrant' | debconf-set-selections
echo 'phpmyadmin phpmyadmin/mysql/app-pass password vagrant' | debconf-set-selections
echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections
apt-get install -y phpmyadmin

# Autologin phpmyadmin
if [ ! -f "/etc/phpmyadmin/conf.d/autologin.php" ]; then
    cat >/etc/phpmyadmin/conf.d/autologin.php <<EOL
<?php
\$cfg['Servers'][\$i]['auth_type'] = 'config';
\$cfg['Servers'][\$i]['user'] = 'root';
\$cfg['Servers'][\$i]['password'] = 'vagrant';
EOL
fi

# Fix upload problem
chown -R vagrant /var/lib/phpmyadmin/tmp
chgrp -R vagrant /var/lib/phpmyadmin/tmp

# Fix session problem phpmyadmin
sed -i 's/;session.save_path = "\/var\/lib\/php\/sessions"/session.save_path = "\/tmp"/g' /etc/php/7.1/apache2/php.ini

# Install additional PHP modules
apt-get install -y php7.1-intl php7.1-mcrypt php7.1-curl memcached php7.1-memcached

# Enable php7.1-mcrypt extension
phpenmod mcrypt

# Create parameters.yml if file does not exist
if [ ! -f /var/www/app/config/parameters.yml ]; then
    cp /var/www/app/config/parameters.yml.dist /var/www/app/config/parameters.yml
fi

# Install Xdebug, but disable by default because of performance
apt-get install -y php7.1-xdebug
if [ $(grep -c ";zend_extension=xdebug.so" "/etc/php/7.1/apache2/conf.d/20-xdebug.ini") -lt 1 ]
then
	sed -i 's/zend_extension=xdebug.so/;zend_extension=xdebug.so/g' /etc/php/7.1/apache2/conf.d/20-xdebug.ini
fi

# Write script to enable/disable phpdebug by phpdebug on/off
if [ ! -f /usr/bin/phpdebug ]; then
    cat >/usr/bin/phpdebug <<EOL
#!/bin/bash
if [ "\$1" == "on" ]; then
        echo "Enabling PHP debug"
        sed -i 's/;//g' /etc/php/7.1/apache2/conf.d/20-xdebug.ini
        service apache2 restart
else
        echo "Disabling PHP debug"
        sed -i 's/zend_extension=xdebug.so/;zend_extension=xdebug.so/g' /etc/php/7.1/apache2/conf.d/20-xdebug.ini
        service apache2 restart
fi
EOL
    chmod 775 /usr/bin/phpdebug
fi

# Set settings for Xdebug in php.ini, but only if that hasn't been done yet
if [ $(grep -c "xdebug.remote_connect_back" "/etc/php/7.1/apache2/php.ini") -lt 1 ]
then
    sed -i '$s/$/\n\nxdebug.remote_connect_back = 1\nxdebug.remote_enable = 1/' /etc/php/7.1/apache2/php.ini
fi
service apache2 restart

# Install GitHub token
#if [ ! -f /home/vagrant/.composer/auth.json ]; then
#    mkdir -p /home/vagrant/.composer
#    cat >/home/vagrant/.composer/auth.json <<EOL
#{
#    "github-oauth": {
#        "github.com": "1234567890"
#    }
#}
#
#EOL
#fi

# Install Java for Assetic
sudo add-apt-repository -y ppa:openjdk-r/ppa
apt-get update
apt-get install -y openjdk-7-jre

# Install sass and Compass
apt-get install -y ruby-dev #bug in compass needs this
gem install compass
gem install sass

# Update composer
cd /var/www
php composer.phar update

# Create MySQL user and database if it hasn't been created before
if [ ! -f /var/log/databasesetup ];
then
    QUERY="CREATE DATABASE IF NOT EXISTS \`tournament\`; GRANT ALL ON \`tournament\`.* to 'tournament'@'%' identified by 'tournament';FLUSH PRIVILEGES;"
    mysql -uroot -pvagrant -e "$QUERY"
    php /var/www/app/console doctrine:migrations:migrate -n
    mysql -utournament -ptournament tournament < /vagrant/testDump.sql

    echo "sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION" >> /etc/mysql/mysql.conf.d/mysqld.cnf

    touch /var/log/databasesetup
fi
# Run migrations (again) when redoing provisioning
php /var/www/app/console doctrine:migrations:migrate -n

# Create symlink to assets
php app/console assets:install public_html --symlink

# Useful for Docker
rm -rfd /var/tournia -R
mkdir /var/tournia
mkdir /var/tournia/cache
mkdir /var/tournia/logs
chown www-data:www-data /var/tournia -R