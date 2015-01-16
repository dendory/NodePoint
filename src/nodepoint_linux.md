NodePoint Installation (Linux version)
======================

NodePoint is a ticket management platform based on the Bootstrap framework. It is meant to be simple to setup and use, yet still offers many features such as user management, access levels, commenting, release tracking, email notifications and a JSON API.

Requirements
------------

- A Linux host.

- Apache web server.


Installation steps
------------------

- [Download NodePoint](http://dendory.net/nodepoint) and unzip the folder where you need to, for example `~/nodepoint`.

- Make sure `www/nodepoint.cgi` can be executed by the web server, and it has write access to `nodepoint.cfg`, `db/` and `uploads/`. 

- Map a virtual host in your `httpd.conf`, or link the *www* folder, for example: `ln -s /var/www/nodepoint ~/nodepoint/www` (paths may differ based on your distro).

- Access the site at `http://localhost/nodepoint` and complete the first time configuration.


Troubleshooting
---------------
### If you get a 500 server error ###

Check in your server log what the likely error might be. Try to run `~/nodepoint/www/nodepoint.cgi` from a shell. If you get a `No such file or directory` you may be missing 32 bits binary support. In Debian you can enable 32bits support with these commands:

    dpkg --add-architecture i386
    apt-get install ia32-libs-i386

### You see a list of files in your browser instead of the proper interface ###

Make sure the `.htaccess` file is present, and that your Apache configuration allows overrides. Look for the line `AllowOverride All` in your default site configuration file.

### If you get the error `Could not access configuration file` ###

Make sure NodePoint has write access to `../nodepoint.cfg`. Make sure the file only contains one line with the text `dummy value`.

### If you get the error `Could not access database` ###

Make sure NodePoint has write access to the database, by default `../db/nodepoint.db`.

### If email notifications don't work ###

This is typically because of permission issues. Make sure that:

* The user that NodePoint runs under has permissions to make network connections.
* The firewall is allowing outgoing connections.
* The SMTP server is accepting connections from the NodePoint server and email address you set.

### If you forgot your admin password ###

Simply delete the `nodepoint.cfg` configuration file on the server and recreate it through the web interface from localhost.

API
---
NodePoint provides an API to add and show tickets in JSON format. You can use GET or POST arguments with the following values:

### Show ticket ###
* api=show_ticket
* key=&lt;read key&gt;
* id=&lt;ticket id&gt;

### List tickets by product ###
* api=list_tickets
* key=&lt;read key&gt;
* product_id=&lt;product id&gt;

### Add ticket ###
* api=add_ticket
* key=&lt;write key&gt;
* product_id=&lt;product id&gt;
* release_id=&lt;release id&gt;
* title=&lt;ticket title&gt;
* description=&lt;ticket description&gt;
* custom=&lt;custom field&gt;

### Add comment ###
* api=add_comment
* key=&lt;write key&gt;
* id=&lt;ticket id&gt;
* comment=&lt;comment&gt;

Need support?
-------------

You can contact the author at [dendory@live.ca](mailto:dendory@live.ca)
