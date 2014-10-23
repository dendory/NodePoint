//
// Simple Node+Bootstrap (SNB)
//
// Author: Patrick Lambert - http://dendory.net
// Released under the MIT License
//
var http = require("http");
var url = require("url");
var query = require("querystring");
var crypto = require('crypto');
var fs = require('fs');
var readline = require('readline');

var config_file = "config.csv";
var version = "0.01";
var p, q, res, req, page_num, body;
var cookies = {};
var page = {};
var content = [];
var log = [];
var users = [];
var passwords = [];
var rexp = /^[\.0-9a-zA-Z_-]+$/;
var chartypes = [];
var config = {};
var pages = [];
var pages_url = [];
var pages_func = [];
var files = [];

//
// Pages
//
// Main page
page.main = function()
{
	headers(200, "text/html");
	res.write(read_content(0)); // main.html
	footers();
}

// Members page
page.members = function()
{
	headers(200, "text/html");
	var user = "";
	if(logged_in(cookies['n'], cookies['p'])) { user = cookies['n']; } // Check if user is logged in
	if(user)
	{
		res.write(read_content(1)); // admin.html
		if(user == "admin")   // functions available for admins only
		{
			if(q['save_file'] && q['data'] && files.indexOf(q['save_file']) != -1)  // edit one of the files in the files array
			{
				fs.writeFileSync(q['save_file'], q['data']);
				res.write("<div class='alert alert-success' role='alert'>File <b>" + q['save_file'] + "</b> saved.</div>");
				load_files();
			}
			if(q['edit_file'] && files.indexOf(q['edit_file']) != -1)  // edit one of the files in the files array
			{
				res.write("<form method='POST' action='.'>Raw content of entry <b>" + q['edit_file'].toString().split(',') + "</b>:<input type='hidden' name='save_file' value='" + q['edit_file'] + "'><br><textarea style='width:100%;height:300px' name='data'>" + fs.readFileSync(q['edit_file'], [encoding='utf8']) + "</textarea><br><input type='submit' value='Save changes' class='btn btn-lg btn-default'></form><br>");

			}
			if(q['save_change'] && config[q['save_change']] && q['data'])  // change a configuration value
			{
				read_config();
				config[q['save_change']] = q['data'];
				fs.writeFileSync(config_file, "");
				for(var key in config)
				{
					fs.appendFileSync(config_file, key + "," + config[key] + "\n");
				}
				files.forEach(function(s)
				{
					fs.appendFileSync(config_file, "file," + s + "\n");
				});
				pages.forEach(function(s)
				{
					fs.appendFileSync(config_file, "page," + s + "\n");
				});
				pages_url.forEach(function(s)
				{
					fs.appendFileSync(config_file, "page_url," + s + "\n");
				});
				pages_func.forEach(function(s)
				{
					fs.appendFileSync(config_file, "page_func," + s + "\n");
				});
				chartypes.forEach(function(s)
				{
					fs.appendFileSync(config_file, "chartype," + s + "\n");
				});
				res.write("<div class='alert alert-success' role='alert'>Configuration saved.</div>");
			}
			if(q['change'] && config[q['change']])  // change a configuration value
			{
				res.write("<form method='POST' action='.'><input type='hidden' name='save_change' value='" + q['change'] + "'><div class='alert alert-warning'>Enter the new value for key <b>" + q['change'] + "</b>: <input type='entry' name='data' value='" + config[q['change']] + "'></div><input type='submit' value='Save changes' class='btn btn-lg btn-default'></form><br>");
			}
			if(q['randomize'] && users.indexOf(q['randomize']) != -1) // reset a user password
			{
				var new_pass = rand_chars(10);
				var hashed_pass = crypto.createHash('sha256').update(new_pass).digest('hex');
				load_users();   // make sure the arrays have the latest info from file
				passwords[users.indexOf(q['randomize'])] = hashed_pass;
				fs.writeFileSync(config['user_file'], "");
				for(i=0; i<users.length; i++)
				{
					fs.appendFileSync(config['user_file'], users[i] + "," + passwords[i] + "\n");
				}
				res.write("<div class='alert alert-success' role='alert'>Randomized password for user " + q['randomize'] + ". New password: <b>" + new_pass + "</b></div>");
			}
			if(q['clear_log'])  // clear access log
			{
				log = [];
				res.write("<div class='alert alert-success' role='alert'>Log cleared.</div>");
			}
			if(q['reload_content']) // reload files and users from disk
			{
				read_config();
				load_users();
				load_files();
				res.write("<div class='alert alert-success' role='alert'>Configuration, users and files reloaded.</div>");
			}
			res.write("<h3>Server statistics</h3>");
			res.write("<p><table class='table table-striped'>");
			res.write("<tr><td>Framework version</td><td>" + version + "</td></tr>");
			res.write("<tr><td>Process ID</td><td>" + process.pid + "</td></tr>");
			res.write("<tr><td>Uptime</td><td>" + time_convert(process.uptime()) + "</td></tr>");
			res.write("</table></p>");
			res.write("<h3>Configuration values</h3>");
			res.write("<p><table class='table table-striped'>");
			res.write("<tr><th>Key</th><th>Value</th><th>Change value</th></tr>");
			res.write("<tr><td>Site name</td><td>" + config['project_name'] + "</td><td><a href='./?change=project_name'>Change</a></td></tr>");
			res.write("<tr><td>Logo file</td><td>" + config['project_icon'] + "</td><td><a href='./?change=project_icon'>Change</a></td></tr>");
			res.write("<tr><td>Favicon</td><td>" + config['favicon'] + "</td><td><a href='./?change=favicon'>Change</a></td></tr>");
			res.write("<tr><td>CSS template</td><td>" + config['css_file'] + "</td><td><a href='./?change=css_file'>Change</a></td></tr>");
			res.write("<tr><td>Users list</td><td>" + config['user_file'] + "</td><td><a href='./?change=user_file'>Change</a></td></tr>");
			res.write("<tr><td>Resource path</td><td>" + config['res_path'] + "</td><td><a href='./?change=res_path'>Change</a></td></tr>");
			res.write("<tr><td>Allow registrations</td><td>" + config['allow_registrations'] + "</td><td><a href='./?change=allow_registrations'>Change</a></td></tr>");
			res.write("</table></p>");
			res.write("<h3>Users list</h3>");
			res.write("<p><table class='table table-striped'>");
			res.write("<tr><th>User name</th><th>Hashed password</th><th>Reset password</th></tr>");
			for(i=0; i<users.length; i++)
			{
				res.write("<tr><td>" + users[i] + "</td><td>" + passwords[i] + "</td><td><a href='./?randomize=" + users[i] + "'>Reset</a></td></tr>");			
			}
			res.write("</table></p>");
			res.write("<h3>Files list</h3>");
			res.write("<p><table class='table table-striped'>");
			res.write("<tr><th>File name</th><th>Size</th><th>Edit file</th></tr>");
			for(i=0; i<files.length; i++)
			{
				res.write("<tr><td>" + files[i] + "</td><td>" + fs.statSync(files[i])['size'] + " bytes</td><td><a href='./?edit_file=" + files[i] + "'>Edit</a></td></tr>");
			}
			res.write("</table></p>");
			res.write("<p><a href='./?reload_content=1' class='btn btn-lg btn-default'>Reload content</a> &nbsp; <a href='./?upload_res=1' class='btn btn-lg btn-default'>Upload resource file</a></p>");
			res.write("<h3>Last 50 connections</h3>");
			res.write("<p><table class='table table-striped'>");
			res.write("<tr><th>Remote address</th><th>Time</th><th>Requested page</th></tr>");
			for(i=0; i<Math.min(log.length, 50); i++)
			{
				res.write("<tr><td>" + log[i][0] + "</td><td>" + log[i][1] + "</td><td>" + log[i][2] + "</td></tr>");
			}
			res.write("</table></p>");
			res.write("<p><a href='./?clear_log=1' class='btn btn-lg btn-default'>Clear log</a></p>");
		}
	}
	else
	{
		res.write("<div class='alert alert-danger' role='alert'>You are not logged in.</div>");
	}
	footers();
}

// Stream page
function show_stream_entry(entry)
{
	res.write("<h3><a href='./?entry=" + entry.split(',')[0] + "'>" + entry.split(',')[1] + "</a></h3>");
	res.write("<i>" + entry.split(',')[2] + "</i>");
	if(q['save_entry'] && q['data'])  // save an edited entry
	{
		if(logged_in(cookies['n'], cookies['p']) && cookies['n'] == "admin") // check logged in user is admin
		{
			fs.writeFileSync(q['entry'], q['data']);
			res.write("<div class='alert alert-success' role='alert'>Entry <b>" + q['entry'] + "</b> saved.</div>");
		}
		else
		{
			res.write("<div class='alert alert-danger' role='alert'>You cannot edit this page.</div>");
		}
	}
	else if(q['edit_entry'])  // editing an entry
	{
		if(logged_in(cookies['n'], cookies['p']) && cookies['n'] == "admin") // check logged in user is admin
		{
			res.write("<form method='POST' action='.'><br>Raw content of entry <b>" + entry.split(',')[0] + "</b>:<input type='hidden' name='entry' value='" + entry.split(',')[0] + "'><input type='hidden' name='save_entry' value='1'><textarea style='width:100%;height:300px' name='data'>" + fs.readFileSync(entry.split(',')[0], [encoding='utf8']) + "</textarea><br><input type='submit' value='Save changes' class='btn btn-lg btn-default'><br></form><br>");
		}
		else
		{
			res.write("<div class='alert alert-danger' role='alert'>You cannot edit this page.</div>");
		}
	}
	res.write("<div class='well'>" + fs.readFileSync(entry.split(',')[0], [encoding='utf8']) + "</div><hr>");
}

page.stream = function()
{
	headers(200, "text/html");
	var user = "";
	if(logged_in(cookies['n'], cookies['p'])) { user = cookies['n']; }
	if(!q['entry']) // entries listing
	{
		res.write(read_content(2)); // stream_intro.html
		var page = parseInt(q['page']) || 0;
		var entries = read_content(4).toString().split('\n'); // stream_pages.csv
		if(logged_in(cookies['n'], cookies['p']) && cookies['n'] == "admin")
		{
			res.write("<a href='./?new_stream_entry=1' class='btn btn-lg btn-default pull-right'>New entry</a>"); 
		}
		res.write("<h3>Entries " + ((page * 10) == 0 ? 1 : (page * 10)) + "-" + Math.min(((page * 10) + 10), entries.length) + " of " + entries.length + "</h3>");
		for(i=(page * 10); i<Math.min(entries.length, ((page * 10) + 10)); i++)
		{
			if(entries[i].toString().split(',')[2])
			{
				show_stream_entry(entries[i]);
			}
		}
		res.write("<p>");
		if(entries.length > ((page * 10) + 10)) res.write("<a href='./?page=" + (page + 1) + "' class='btn btn-lg btn-default'>Previous</a>");
		if(page > 0) res.write(" <a href='./?page=" + (page - 1) + "' class='btn btn-lg btn-default'>Next</a>");
		res.write("</p>");
	}
	else // specific entry
	{
		var entries = read_content(4).toString().split('\n'); // stream_pages.csv
		entries.forEach(function(entry)
		{
			if(entry.split(',')[2])
			{
				if(entry.split(',')[0] == q['entry'])
				{
					show_stream_entry(entry);
					res.write("<p><a href='.' class='btn btn-lg btn-default'>Index</a>");
					if(user)
					{
						res.write(" &nbsp; <a class='btn btn-lg btn-default' href='./?add_comment=1&entry=" + entry.split(',')[0] + "'>Comment</a>");
						if(user == "admin") { res.write(" &nbsp; <a class='btn btn-lg btn-default' href='./?edit_entry=1&entry=" + entry.split(',')[0] + "'>Edit</a>") }
					}
				}
			}
		});
	}
	res.write(read_content(3)); // stream_footer.html
	footers();
}

// API page
page.api = function()
{
	res.writeHead(200, {"Content-Type": "application/json"});
	var json =
	{
		"app": config['project_name'],
		"version": version,
		"status": "",
		"message": "",
	}
	if(q['list_users'])
	{
		json["status"] = "Success";
		json["command"] = "list_users";
		var tmpusers = [];
		for(i=0; i<users.length; i++)
		{
			tmpusers.push({"user": users[i], "password": "<hidden>"});
		}
		json["users"] = tmpusers;
	}
	else if(q['list_pages'])
	{
		json["status"] = "Success";
		json["command"] = "list_pages";
		var tmppages = [];
		for(i=0; i<pages.length; i++)
		{
			tmppages.push({"page": pages[i], "url": pages_url[i], "function": pages_func[i]});
		}
		json["pages"] = tmppages;
	}
	else
	{
		json["status"] = "Error";
		json["message"] = "This is an API example. It will respond to GET or POST commands";
		json["available_commands"] = [{"command": "list_users", "description": "List the current users"}, {"command": "list_pages", "description": "List the current pages"}];
	}
	res.write(JSON.stringify(json, null, 4));
}

// Login page
page.login = function()
{
	var form_html = "<h3>Login</h3><form method='POST' action='.'><div class='row'><div class='col-sm-4'>User name: <input type='entry' name='name'></div><div class='col-sm-4'>Password: <input type='password' name='pass'></div><div class='col-sm-4'><input class='btn btn-lg btn-default pull-right' type='submit' value='Login'></div></div></form><hr>";
	
	var register_html = "<h3>Register</h3><form method='POST' action='.'><div class='row'><div class='col-sm-3'>User name: <input type='entry' name='new_name'></div><div class='col-sm-3'>Password: <input type='password' name='new_pass1'></div><div class='col-sm-3'>Confirm: <input type='password' name='new_pass2'></div><div class='col-sm-3'><input class='btn btn-lg btn-default pull-right' type='submit' value='Register'></div></div></form><hr>";
	if(config['allow_registrations'].toLowerCase() != "true") { register_html = ""; }
	
	if(config['allow_registrations'].toLowerCase() == "true" && q['new_name'] && q['new_pass1'] && q['new_pass2']) // User filled the registration form
	{
		headers(200, "text/html");
		if(q['new_pass1'] != q['new_pass2'])
		{
			res.write("<div class='alert alert-danger' role='alert'>Your passwords don't match.</div><p>" + register_html + "</p>");
		}
		else if(users.indexOf(q['new_name']) != -1)
		{
			res.write("<div class='alert alert-danger' role='alert'>User already exists.</div><p>" + register_html + "</p>");
		}
		else if(q['new_name'].length < 3)
		{
			res.write("<div class='alert alert-danger' role='alert'>Please enter a longer user name.</div><p>" + register_html + "</p>");
		}
		else if(q['new_pass1'].length < 8)
		{
			res.write("<div class='alert alert-danger' role='alert'>Please enter a longer password.</div><p>" + register_html + "</p>");
		}
		else if(!rexp.test(q['new_name']))
		{
			res.write("<div class='alert alert-danger' role='alert'>Please user only letters or numbers.</div><p>" + register_html + "</p>");
		}
		else
		{
			var hashed_pass = crypto.createHash('sha256').update(q['new_pass1']).digest('hex');
			users.push(q['new_name']);
			passwords.push(hashed_pass);
			fs.appendFile(config['user_file'], q['new_name'] + "," + hashed_pass, function (err)
			{
				console.log(err);
			});
			res.write("<div class='alert alert-success' role='alert'>New user created. You can now log in.</div><p>" + form_html + "</p>");		
		}
	}
	else if(q['name'] && q['pass']) // User filled the login form
	{
		var hashed_pass = crypto.createHash('sha256').update(q['pass']).digest('hex');
		if(logged_in(q['name'], hashed_pass))
		{
			headers(200, "text/html", [ "n=" + q['name'] + "; path=/" , "p=" + hashed_pass + "; path=/"]);
			res.write("<div class='alert alert-success' role='alert'>Logged in as " + q['name'] + ".</div><p><a href='/login/?logout=1'>Logout</a></p>");
		}
		else
		{
			headers(200, "text/html");
			res.write("<div class='alert alert-danger' role='alert'>Invalid user name or password.</div><p>" + form_html + "</p>");
		}		
	}
	else if(cookies['n'] && cookies['p'] != "" && !q['logout'])  // Cookies are already set
	{
		if(logged_in(cookies['n'], cookies['p']))
		{
			headers(200, "text/html");
			res.write("<div class='alert alert-success' role='alert'>Welcome back, " + cookies['n'] + ".</div><p><a href='/login/?logout=1'>Logout</a></p>");
		}
		else
		{
			headers(200, "text/html");
			res.write("<div class='alert alert-danger' role='alert'>Invalid login credentials. Please log in again.</div><p>" + form_html + "</p>");
		}
	}
	else  // display the form
	{
		if(q['logout'])
		{
			headers(200, "text/html", [ "n=;path=/", "p=;path=/" ]); 
			res.write("<div class='alert alert-success' role='alert'>Logged you out.</div>");
		}
		else
		{
			headers(200, "text/html");
			res.write("<div class='alert alert-danger' role='alert'>You must first log in.</div>");
		}
		res.write(form_html);
		res.write(register_html);
	}
	footers();
}

//
// Inline content injection functions
//
// Output headers to each page
function headers(status, chartype, cookies)
{
	if(cookies) { res.setHeader("Set-Cookie", cookies); }
	res.writeHead(status, {"Content-Type": chartype});
	res.write("<!DOCTYPE html>\n");
	res.write("<html>\n");
	res.write(" <head>\n");
	if(pages[page_num]) { res.write("  <title>" + pages[page_num] + "</title>\n"); }
	else { res.write("  <title>" + config['project_name'] + "</title>\n"); }
    res.write("  <meta charset='utf-8'>\n");
	res.write("  <meta http-equiv='X-UA-Compatible' content='IE=edge'>\n");
	res.write("  <meta name='viewport' content='width=device-width, initial-scale=1'>\n");
	res.write("  <link rel='icon' type='image/png' href='/res/" + config['favicon'] + "'>\n");
	res.write("  <link rel='stylesheet' href='https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css'>\n");
	res.write("  <link rel='stylesheet' href='" + config['css_file'] + "'>\n");
	res.write("  <style>body { padding-bottom: 50px; }</style>\n");
	res.write(" </head>\n");
	res.write(" <body>\n");
	navbar();
	res.write("  <div class='container'>\n\n");
}

// Top navigation bar
function navbar()
{
	res.write("  <div class='navbar navbar-default navbar-static-top' role='navigation'>\n");
	res.write("   <div class='container'>\n");
	res.write("    <div class='navbar-header'>\n");
	res.write("     <button type='button' class='navbar-toggle collapsed' data-toggle='collapse' data-target='.navbar-collapse'>\n");
	res.write("      <span class='sr-only'>Toggle navigation</span>\n");
	res.write("      <span class='icon-bar'></span>\n");
	res.write("      <span class='icon-bar'></span>\n");
	res.write("      <span class='icon-bar'></span>\n");
	res.write("     </button>\n");
	res.write("     <a class='navbar-brand' href='/'><img alt='Brand' src='/res/" + config["project_icon"] + "'> " + config["project_name"] + "</a>\n");
	res.write("    </div>\n");
	res.write("    <div class='navbar-collapse collapse'>\n");
	res.write("     <ul class='nav navbar-nav'>\n");
	for(i = 0; i < pages.length; i++)
	{
		if(pages[page_num] && pages[page_num] == pages[i]) { res.write("      <li class='active'><a href='" + pages_url[i] + "'>" + pages[i] + "</a></li>\n"); }
		else { res.write("      <li><a href='" + pages_url[i] + "'>" + pages[i] + "</a></li>\n"); }
	}
	res.write("     </ul>\n");
	res.write("    </div>\n");
	res.write("   </div>\n");
	res.write("  </div>\n");
}

// Output footers to each page
function footers()
{
	res.write("\n\n  </div>\n");
	res.write("  <script src='https://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js'></script>\n");
	res.write("  <script src='https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js'></script>\n");
	res.write(" </body>\n");
	res.write("</html>\n");
}

//
// Utility functions
//
// Load resource files
function load_resource()
{
	var file = p.split('/res/')[1];
	if(rexp.test(file)) return 0;
	if(file.length < 5 || file.length > 30) return 0;
	var chartype;
	file = file.substr(0, (file.length-1));
	chartypes.forEach(function(type)
	{
		if(file.substr(-(type.split(':')[0].length)) == type.split(':')[0]) { chartype = type.split(':')[1]; }
	});
	if(!chartype) return 0;
	if(!fs.existsSync(config['res_path'] + file))	return 0;
	res.writeHead(200, {"Content-Type": chartype});
	res.write(fs.readFileSync(config['res_path'] + file, [encoding='utf8']));
	return 1;
}

// Return loaded file content
function read_content(i)
{
	return content[i];
}

// Check if a user is logged in
function logged_in(name, hashed_pass)
{
	if(!name || !hashed_pass) { return 0; }
	for(i = 0; i < users.length; i++)
	{
		if(users[i] == name && passwords[i] == hashed_pass) return 1;
	}
	return 0;
}

// Load pages
function change_page()
{
	for(i = 0; i < pages.length; i++) // iterate between pages to see if that's the requested URL
	{
		if(p == pages_url[i])
		{
			page_num = i;
			page[pages_func[i]]();
			return;
		}
	}
	if(p.substr(0, 5) == "/res/") // Special case, loading resource files
	{
		if(load_resource()) return;
	}
	headers(req, res, "Not found", 404, "text/html");  // URL not found
	res.write("<h2>Not Found</h2>");
	res.write("<p>The resource <tt>" + p + "</tt> was not found on this server.</p>");
	res.write("<hr><i>SNB " + version + "</i>");
	footers(req, res);
}

// Load files into memory
function load_files()
{
	content = [];
	for(i=0; i < files.length; i++)
	{
		content[i] = fs.readFileSync(files[i], [encoding='utf8']);
		console.log("Imported file [" + i + "]: " + files[i]);
	}
}

// Load users into memory
function load_users()
{
	users = [];
	passwords = [];
	var tmpusers = fs.readFileSync(config['user_file'], [encoding='utf8']);
	tmpusers = tmpusers.toString().split('\n');
	for(i=0; i<tmpusers.length; i++)
	{
		if(tmpusers[i].toString().split(',')[1])
		{
			console.log("Imported user [" + i + "]: " + tmpusers[i].toString().split(',')[0]);
			users.push(tmpusers[i].toString().split(',')[0]);
			passwords.push(tmpusers[i].toString().split(',')[1].toString().trim('\n'));
		}
	}
}

// Create random characters
function rand_chars(length)
{
	var chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
	var result = '';
	for (var i = length; i > 0; --i) result += chars[Math.round(Math.random() * (chars.length - 1))];
	return result;
}

// Time conversion util
function time_convert(secs)
{
	var sec_num = parseInt(secs, 10);
	var hours = Math.floor(sec_num / 3600);
	var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
	var seconds = sec_num - (hours * 3600) - (minutes * 60);
	var time = hours + " hours, " + minutes + " mins, " + seconds + " secs";
	return time;
}

// Read config file
function read_config()
{
	config = [];
	pages = [];
	pages_url = [];
	pages_func = [];
	chartypes = [];
	files = [];
	var tmpconfig = fs.readFileSync(config_file, [encoding='utf8']);
	tmpconfig = tmpconfig.toString().split('\n');
	for(i=0; i<tmpconfig.length; i++)
	{
		tmpconfig[i] = tmpconfig[i].toString().trim()
		if(tmpconfig[i].toString().split(',')[1])
		{
			if(tmpconfig[i].toString().split(',')[0] == "file") files.push(tmpconfig[i].toString().split(',')[1]);
			else if(tmpconfig[i].toString().split(',')[0] == "chartype") chartypes.push(tmpconfig[i].toString().split(',')[1]);
			else if(tmpconfig[i].toString().split(',')[0] == "page") pages.push(tmpconfig[i].toString().split(',')[1]);
			else if(tmpconfig[i].toString().split(',')[0] == "page_url") pages_url.push(tmpconfig[i].toString().split(',')[1]);
			else if(tmpconfig[i].toString().split(',')[0] == "page_func") pages_func.push(tmpconfig[i].toString().split(',')[1]);
			else config[tmpconfig[i].toString().split(',')[0]] = tmpconfig[i].toString().split(',')[1]
		}
	}
	console.log("Loaded " + i + " configuration values.");
}

// Handle a request
function onreq(request, response)
{
	req = request;
	res = response;
	cookies = {};
	p = url.parse(req.url).pathname;
	if(p.slice(-1) != "/") { p = p + "/"; }
	console.log("Request received from [" + req.connection.remoteAddress + "] on [" + Date() + "] for [" + p + "]");
	log.push([req.connection.remoteAddress, Date(), p]);
	body = '';
	req.on('data', function (data) 
	{
		body += data;
		if (body.length > 1e6) { req.connection.destroy(); }
	});
	req.on('end', function () 
	{
		if(req.method == 'POST')
		{
			q = query.parse(body); // Load q from POST data
			change_page(req, res);
			res.end();
		}
	});
	var tmpcookies = req.headers.cookie;
	tmpcookies && tmpcookies.split(';').forEach(function( cookie )
	{
		var parts = cookie.split('=');
		cookies[parts.shift().trim()] = unescape(parts.join('='));
	});
	if(req.method != 'POST')
	{
		q = query.parse(req.url.split('?')[1]);  // Load q from GET data
		change_page(req, res);	
		res.end();
	}
}

// Initial loads
read_config();
load_users();
load_files();

// Create server
http.createServer(onreq).listen(config['port']);
console.log("Server started on port " + config['port'] + " [" + Date() + "]");
console.log("Available console commands: version, pid, uptime, reload, hash, exit");

// Console input
var rl = readline.createInterface(process.stdin, process.stdout);
rl.setPrompt('');
rl.prompt();
rl.on('line', function(line)
{
	if (line === "version")
	{
		console.log("SNB: " + version + ", Node.js: " + process.version + ", V8 engine: " + process.versions.v8);
	}
	else if (line === "pid")
	{
		console.log("PID: " + process.pid);
	}
	else if (line === "uptime")
	{
		console.log("Uptime: " + time_convert(process.uptime()));
	}
	else if (line === "reload")
	{
		load_files();
	}
    else if (line === "exit")
	{
		process.exit(0);
	}
    else if (line.split(' ')[0] === "hash")
	{
		if(line.split(' ')[1]) { console.log(crypto.createHash('sha256').update(line.split(' ')[1]).digest('hex')); }
	}
	else
	{
		console.log("Unknown command.");
	}
	rl.prompt();
});
  