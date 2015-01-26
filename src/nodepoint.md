NodePoint Installation (Windows version)
======================

NodePoint is a ticket management platform based on the Bootstrap framework. It is meant to be simple to setup and use, yet still offers many features such as user management, access levels, commenting, release tracking, email notifications and a JSON API.

Requirements
------------

- A Windows host (7, 8, 10, Server 2008, Server 2012 should all work).

- IIS installed with *CGI* and *ISAPI Extensions* features.


Installation steps
------------------

- [Download NodePoint](http://nodepoint.ca) and unzip the folder where you need to, for example `C:\nodepoint`.

- Run `setup.bat`.

- Access the site and complete the first time configuration.


Troubleshooting
---------------
### If setup.bat fails: ###
Make sure you are running it as a local administrator. Make sure the file `%windir%\system32\inetsrv\appcmd.exe` exists, and that your web site is `Default Web Site`. Also run setup from the installation folder. Optionally, you may have to modify the script to suit your environment. 

### If you get the error `Could not access Registry`: ###

Make sure the virtual folder has credentials that has access to the Registry. Go to **Administrative Tools -> IIS Manager**, then select the *NodePoint* site under *Default Web Site* and go to **Advanced Settings**:

![](http://i.imgur.com/qk6pALz.jpg)

Once there, select a *Specific User* that has access to the Registry:

![](http://i.imgur.com/jMqJaEB.jpg)

This can be your own user name, or you can create a dedicated user in **Administrative Tools -> Computer Management -> Local Users and Groups**. Make sure that user is part of the *Administrators* local group, and that you restart the IIS server after.

### If you get the error `Could not access database file.`:###

Make sure that NodePoint has Read/Write access to the database file specified in the initial configuration. By default this is `C:\nodepoint\db\nodepoint.db`. This should be the user you configured in the initial setup. You can use *Windows Explorer* to right click on the file and check under the **Security** tab.

### If you get the error `The page you are requesting cannot be served because of the extension configuration.` or the server tries to download the file instead of executing it:###

Make sure you have the *CGI* and *ISAPI Extensions* IIS features installed and enable **Execute** under **IIS Manager -> Handler Mappings -> CGI-exe -> Edit Feature Permissions**:

![](http://i.imgur.com/2Wm0Pzp.jpg)

### If you get the error `The page you are requesting cannot be served because of the ISAPI and CGI Restriction list settings on the Web server.`:###

Go to **IIS Manager -> ISAPI and CGI Restrictions** and make sure *NodePoint* is listed. If not, click on **Edit Feature Settings** and enable unspecified CGI modules.

### If email notifications don't work ###

This is typically because of permission issues. Make sure that:

* The user that NodePoint runs under has permissions to make network connections.
* The firewall is allowing outgoing connections.
* The SMTP server is accepting connections from the NodePoint server and email address you set.

### If you forgot your admin password ###

You will need to remove the initial configuration settings and recreate them in order to recover access. This configuration is stored locally on the server inside the Windows Registry. Use `regedit.exe` and navigate to `HKLM/SOFTWARE/NodePoint`.

Configuration
-------------
These are the default configuration values for NodePoint. They have to be defined during first use, and can be modified by the NodePoint Administrator later from the Settings tab.

* Database file: This is the NodePoint database file. Make sure you routinely back this file up as it contains all of the information stored by NodePoint.
* Admin name: The NodePoint administrator.
* Admin password: The password for the administrator.
* Site name: The name shown at the top left of the interface.
* Public notice: This notice is shown on every page. Leave empty to remove the notice.
* Bootstrap template: This is a CSS file used by NodePoint. It should be a valid Bootstrap template, or could contain extra CSS elements you wish to use. The default file is `default.css` and contains a few such elements.
* Favicon: This is the icon shown by web browsers in the URL bar.
* Ticket visibility: When set to `Public`, all tickets will be visible by logged in and guest users. When set to `Private`, people need to log in to view tickets. `Restricted` prevents people without at least the Restricted View access level from viewing others' tickets. This is a good choice for IT/Helpdesk systems.
* Default access level: The access level for new users. Default is 1.
* Allow registrations: Allow guest users to register a new account. If set to no, the only way to add new accounts is if a user with Users Management access adds one.
* API read key: Used for some API operations.
* API write key: Used for some API operations.
* SMTP server: The hostname for email notifications. Leave empty to disable email notifications.
* SMTP port: The port number for SMTP connections, defaults to 25.
* SMTP username: User for SMTP connections, if your mail server requires authentication.
* SMTP password: Password for SMTP connections, if your mail server requires authentication. Warning: This will be stored in plain text on the NodePoint server. It is recommended that your SMTP server restricts connections based on IP addresses instead.
* Support email: The email from which email notifications come from.
* External notifications plugin: Call an application or script when a notification is sent. You can use the following variables here: *%user%*, *%title%* and *%message%*. For example: `echo %message% >> ..\%user%.log`
* Upload folder: Where product images and comment files are stored. Leave empty to disable uploads.
* Minimum upload level: The minimum access level a user must have to attach files to comments
* Items managed: The type of items NodePoint should manage. This is purely a UI customization.
* Custom ticket field: The name of the third ticket field (after 'title' and 'description'). This can be used to ask users who fill in tickets to list related tickets, or any other information relevant to your particular installation.
* Custom ticket type: The type of field. If `text`, then the entries will be shown as text. If `URL`, then links will be assumed. If `checkbox`, then users will have to select yes or no.
* Active Directory server: Enter your domain controller address to enable AD integration. Users will be created dynamically as they first log on, and passwords will be checked against AD.
* Active Directory domain: The domain to use for AD integration (in NT4 format).

Users management
----------------
NodePoint provides a simple way to manage users based on their access levels. Users have a specific level, which determines what shows up to them in the interface and what they can do. They can also enter an optional email address for notifications. Email addresses must be confirmed through the sending of an automated token when they first register, if email notifications are turned on. Users also have a password which can be changed by the user under the Settings tab, or reset by someone with the Users Management level.

These are the access levels used by NodePoint:

Level | Name | Description
------|------|----------------
6 | NodePoint Admin|Can change basic NodePoint settings
5 | Users management | Can create users, reset passwords, change access levels
4 | Products management | Can add, retire and edit products, view statistics
3 | Tickets management | Can create releases, update tickets, track time
2 | Restricted view | Can view restricted tickets and products
1 | Authorized users | Can create tickets and comments
0 | Unauthorized users | Can view private tickets

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

### Verify user password ###
* api=verify_password
* key=&lt;read key&gt;
* user=&lt;user name&gt;
* password=&lt;password&gt;

### Change user password ###
* api=change_password
* key=&lt;write key&gt;
* user=&lt;user name&gt;
* password=&lt;password&gt;

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

### Add release ###
* api=add_release
* key=&lt;write key&gt;
* product_id=&lt;product id&gt;
* release_id=&lt;release id&gt;
* notes=&lt;notes&gt;

Need support?
-------------

You can contact support at [support@nodepoint.ca](mailto:support@nodepoint.ca)
