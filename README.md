# NodePoint #
## Introduction ##

NodePoint (NP) is a simple Web Application Framework (WAF) project based on the Node.js and Bootstrap library. The idea behind NodePoint is to have an entire web site living in one lightweight package, with no external dependencies than these two libraries, yet still offer all the usual features such as content processing, user management, blogs, an API, and more.

In order to run this web app, all you need is Node.js installed. The Bootstrap library is loaded dynamically at runtime. The goal is to have a very simple framework to build and customize, perfect for small projects that do not require a full-featured web server and CMS installed. Feel free to build upon this project to suit your needs.

The text on this page is contained in main.html and can be edited from the Members area. The default admin credential is username: `admin` password: `admin`.

## Configuration ##

Configuration values are saved in a single config file in CSV format. Here are the values you should configure:

\# |Variable name      |Description
--|-------------------|-----------------------
1 |project_name       |The title of your site
2 |project_icon       |The site logo
3 |port               |The port on which the server should listen for requests
4 |css_file           |A valid Bootstrap template, or any extra CSS file
5 |page               |List of pages
6 |page_url           |List of URLs for these pages
7 |page_func          |List of functions for these pages
8 |user_file          |File containing users information
9 |file               |List of files to load content from
10|res_path           |Path to resource files
11|allow_registrations|Allow users to register on the login page

Then, functions dynamically display pages based on the path in the URL requested by users. Each function corresponds to one page. These functions have access to the following additional variables created by NP:

\#|	Variable name |Description
--|---------------|---------------
1|	req|	The user request object
2|	res|	The response object
3|	p|	The URI path requested
4|	q|	An array containing GET or POST variables
9|	users|	Array containing the list of users
10|	passwords|	Array containing SHA-256 passwords for these users

## User management ##

User management is done through the previous variables users and passwords. You can use the function logged_in(user, hashed_password) to verify if a user is valid. This is what the login page does.

The arrays are filled from the content of the file user_file. In it, you should have each user on its own line, with each line having the user name and SHA-256 password, separated with a comma.

## Content management ##

NodePoint includes two functions to output header and footer information for users. The first is headers(status, chartype, cookies). The status should be set to 200 for success, and some other number for errors such as file not found or unauthorized. The chartype value is a valid value for the type of content you will display, whether that's html, plain text, and so on. Finally, the optional cookies variable is an array containing cookies to be set for the user. This is mostly used for logging in.

Each page can output content to the user via res.write(string), but you can also load content from files. Simply place a list of files in the files variable, and the content will be loaded into memory at startup. Then, you can access it with read_content(index) where index is the file number from the previous array.

Content may also refer to resource files. This is mostly useful to store images and other assets, and should be placed inside the path referred to in res_path. Then, these files can be accessed by appending the path /res/. For example, if you have image1.jpg then you can refer to it with the following code: `<img src='/res/image1.jpg'>`.

## Console ##

All logging information is displayed to the console. The console also allows you to enter some commands to manage a running server:

\#|	Console command|	Description
--|----------------|-
1|	version|	Display version information
2|	uptime|	Display how long the server has been running
3|	pid|	Display the Process ID
4|	reload|	Reload all files into memory
5|	hash|	Hash a string, useful to edit the passwords variable
6|	exit|	Kill the server

## Author ##

NodePoint was created by [Patrick Lambert](http://dendory.net) and released under the MIT License.
