#!/bin/bash

# Make sure you are root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi
echo "This script will copy NodePoint files, set permissions, and add Apache configuration options. Press CTRL-C to cancel."
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get default values
read -p "Software folder [/usr/share]: " installdir
installdir=${installdir:-/usr/share}
read -p "Apache document root [/var/www/html]: " wwwroot
wwwroot=${wwwroot:-/var/www/html}
read -p "Apache user [apache]: " wwwuser
wwwuser=${wwwuser:-apache}
read -p "Apache configuration file [/etc/httpd/conf/httpd.conf]: " conf
conf=${conf:-/etc/httpd/conf/httpd.conf}

# Copy files
echo "* Copying files..."
mkdir -p $installdir
cp -r $DIR $installdir

# Fix permissions
echo "* Setting permissions..."
chown -R $wwwuser.$wwwuser $installdir/nodepoint
chmod 600 $installdir/nodepoint/nodepoint.cfg
chmod 755 $installdir/nodepoint/www/nodepoint.cgi
chmod 755 $installdir/nodepoint/www/nodepoint-automate

# Add Apache config
echo "* Adding Apache config..."
ln -s $installdir/nodepoint/www $wwwroot/nodepoint
echo "<Directory />" >> $conf
echo " AllowOverride All" >> $conf
echo " Options FollowSymLinks" >> $conf
echo " Require all granted" >> $conf
echo "</Directory>" >> $conf
systemctl restart httpd

# Adding automation schedule
echo "* Adding automations schedule..."
crontab -l > /tmp/mycron
if grep -q nodepoint-automate /tmp/mycron; then
	echo "*/5 * * * * $installdir/nodepoint/www/nodepoint-automate" >> /tmp/mycron
	crontab /tmp/mycron
fi
rm -f /tmp/mycron

# Done
echo "Done. If no error occurred, NodePoint should be available from http://localhost/nodepoint"
echo "Please consult the manual for troubleshooting."
