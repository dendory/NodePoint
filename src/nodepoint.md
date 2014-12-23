NodePoint Installation (Windows version)
======================

NodePoint is a ticket management platform based on the Bootstrap framework. It is meant to be simple to setup and use, yet still offers many features such as user management, access levels, commenting, release tracking, email notifications and a JSON API.

Requirements
------------

- A Windows host (7, 8, 10, Server 2008, Server 2012 should all work).

- IIS installed with *CGI* and *ISAPI Extensions* features.


Installation steps
------------------

- [Download NodePoint](http://dendory.net/nodepoint) and unzip the folder where you need to, for example `C:\nodepoint`.

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

You will need to remove the initial configuration settings and recreate them in order to recover access. This configuration is stored locally on the server inside the Windows Registry. Use `regedit.exe` and navigate to `HKLM/SOFTWARE/Wow6432Node/NodePoint`.

API
---
NodePoint provides an API to add and show tickets in JSON format. You can use GET or POST arguments with the following values:

### Show ticket ###
* api=show_ticket
* key=&lt;read key&gt;
* id=&lt;ticket id&gt;

### Add ticket ###
* api=add_ticket
* key=&lt;write key&gt;
* product_id=&lt;product id&gt;
* release_id=&lt;release id&gt;
* title=&lt;ticket title&gt;
* description=&lt;ticket description&gt;
* custom=&lt;custom field&gt;

Need support?
-------------

You can contact the author at [dendory@live.ca](mailto:dendory@live.ca)
