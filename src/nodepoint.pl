#!/usr/bin/perl -w
#
# NodePoint 1.0.4 - (C) 2015 Patrick Lambert - http://dendory.net/nodepoint
# Provided under the MIT License
#
# To use on Windows: Change all 'Linux' for 'Win32' in this file.
# To compile into a binary: Use PerlApp with the .perlapp file.
#

use strict;
use Config::Win32;
use Digest::SHA qw(sha1_hex);
use DBI;
use CGI;
use Net::SMTP;
use Mail::RFC822::Address qw(valid);
use Data::GUID;
use File::Type;
use Scalar::Util qw(looks_like_number);

my ($cfg, $db, $sql, $cn, $cp, $cgs, $last_login);
my $logged_user = "";
my $logged_lvl = -1;
my $q = new CGI;
my $VERSION = "1.0.4";
my %items = ("Product", "Product", "Release", "Release", "Model", "SKU/Model");

# Print headers
sub headers
{
	my ($page) = @_;
	if($cn && $cp || $cgs)
	{
		if($cn && $cp && $cgs) { print $q->header(-type => "text/html", -cookie => [$cn, $cp, $cgs]); }
		elsif($cgs) { print $q->header(-type => "text/html", -cookie => [$cgs]); }
		else { print $q->header(-type => "text/html", -cookie => [$cn, $cp]); }
	}
	else { print $q->header(-type => "text/html"); }
	print "<!DOCTYPE html>\n";
	print "<html>\n";
	print " <head>\n";
	if($cfg->load("site_name")) { print "  <title>" . $cfg->load("site_name") . " - " . $page . "</title>\n"; }
	else { print "  <title>NodePoint - " . $page . "</title>\n"; }
	print "  <meta charset='utf-8'>\n";
	print "  <meta http-equiv='X-UA-Compatible' content='IE=edge'>\n";
	print "  <meta name='viewport' content='width=device-width, initial-scale=1'>\n";
	print "  <link rel='stylesheet' href='bootstrap.css'>\n";
	if($cfg->load("css_template")) { print "  <link rel='stylesheet' href='" . $cfg->load("css_template") . "'>\n"; }
	if($cfg->load("favicon")) { print "  <link rel='shortcut icon' href='" . $cfg->load("favicon") . "'>\n"; }
	else { print "  <link rel='shortcut icon' href='favicon.gif'>\n"; }
	print " </head>\n";
	print " <body>\n";
	navbar();
	print "  <div class='container'>\n";
	if($cfg->load("motd")) { print "<div class='well'>" . $cfg->load("motd") . "</div>\n"; }
}

# Footers
sub footers
{
	print "  <div style='clear:both'></div><hr><div style='margin-top:-15px;font-size:9px;color:grey'><i>NodePoint v" . $VERSION . "</i></div></div>\n";
	print " <script src='jquery.js'></script>\n";
	print " <script src='bootstrap.js'></script>\n";
	print " </body>\n";
	print "</html>\n";
}

# Navigation bar
sub navbar
{
	print "	<div class='navbar navbar-default navbar-static-top' role='navigation'>\n";
	print "    <div class='container'>\n";
	print "	<div class='navbar-header'>\n";
	print "	 <button type='button' class='navbar-toggle collapsed' data-toggle='collapse' data-target='.navbar-collapse'>\n";
	print "	 <span class='sr-only'>Toggle navigation</span>\n";
	print "	 <span class='icon-bar'></span>\n";
	print "	 <span class='icon-bar'></span>\n";
	print "	 <span class='icon-bar'></span>\n";
	print "	 </button>\n";
	if($cfg->load("site_name")) { print "	 <a class='navbar-brand' href='.'>" . $cfg->load("site_name") . "</a>\n"; }
	else { print "	 <a class='navbar-brand' href='.'>NodePoint</a>\n"; }
	print "	</div>\n";
	print "	<div class='navbar-collapse collapse'>\n";
	print "	 <ul class='nav navbar-nav'>\n";
	if(!$cfg->load('db_address'))
	{
		print "	 <li class='active'><a href='.'>Initial configuration</a></li>\n";    
	}
	elsif($logged_user eq "")
	{
		if($q->param('m') && ($q->param('m') eq "products" || $q->param('m') eq "add_product" ||$q->param('m') eq "view_product" || $q->param('m') eq "edit_product" || $q->param('m') eq "add_release"))
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "tickets" || $q->param('m') eq "follow_ticket" || $q->param('m') eq "unfollow_ticket" || $q->param('m') eq "update_comment" || $q->param('m') eq "add_comment" || $q->param('m') eq "new_ticket" || $q->param('m') eq "add_ticket" || $q->param('m') eq "view_ticket" || $q->param('m') eq "update_ticket"))
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li class='active'><a href='./?m=tickets'>Tickets</a></li>\n";
		}
		else
		{
			print "	 <li class='active'><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n";
		}	    
	}
	else
	{
		if($q->param('m') && ($q->param('m') eq "tickets" || $q->param('m') eq "new_ticket" || $q->param('m') eq "follow_ticket" || $q->param('m') eq "unfollow_ticket" || $q->param('m') eq "update_comment" || $q->param('m') eq "add_comment" || $q->param('m') eq "add_ticket" || $q->param('m') eq "view_ticket" || $q->param('m') eq "update_ticket"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li class='active'><a href='./?m=tickets'>Tickets</a></li>\n";
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "products" || $q->param('m') eq "add_product" ||$q->param('m') eq "view_product" || $q->param('m') eq "edit_product" || $q->param('m') eq "add_release"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n";
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "settings" || $q->param('m') eq "clear_log" || $q->param('m') eq "stats" || $q->param('m') eq "change_lvl" || $q->param('m') eq "confirm_email" || $q->param('m') eq "reset_pass" || $q->param('m') eq "logout"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n";
			print "	 <li class='active'><a href='./?m=settings'>Settings</a></li>\n";
		}
		else
		{
			print "	 <li class='active'><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n";
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
	}
	print "	 </ul>\n";
	print "	 <ul class='nav navbar-nav navbar-right'>\n";
	if($logged_user ne "") { print "	  <li role='presentation'><a href='#'><b>" . $logged_user . " <span class='badge'>" . $logged_lvl . "</span></b></a></li>\n"; }
	else { print "	  <li role='presentation'><a href='#'>Guest</a></li>\n"; }
	print "	</ul>\n";
	print "	</div>\n";
	print "    </div>\n";
	print "   </div>\n";
}

# Convert to int so it doesnt throw up on invalid numbers
sub to_int
{
	my ($num) = @_;
	if(!$num) { return 0; }
	elsif(!looks_like_number($num)) { return 0; }
	else { return int($num); }
}

# Convert to float so it doesnt throw up on invalid numbers
sub to_float
{
	my ($num) = @_;
	if(!$num) { return 0; }
	elsif(!looks_like_number($num)) { return 0; }
	else { return sprintf("%.2f", ($num * 1)); }
}

# Print error messages
sub msg
{
	my ($text, $code) = @_;
	if($code == 0) { print "<div class='alert alert-danger' role='alert'><b>Error:</b> " . $text . "</div>\n"; }
	elsif($code == 2) { print "<div class='alert alert-info' role='alert'><b>Info:</b> " . $text . "</div>\n"; }
	elsif($code == 3) { print "<div class='alert alert-success' role='alert'><b>Success:</b> " . $text . "</div>\n"; }
	else { print "<div class='alert alert-warning' role='alert'><b>Warning:</b> " . $text . "</div>\n"; }    
}

# Login form
sub login
{
	print "<center>\n";
	if($cfg->load('allow_registrations') && $cfg->load('allow_registrations') ne 'off')
	{
		print "<div class='row'><div class='col-sm-6'>\n";
	}
	print "<h3>Login</h3><form method='POST' action='.'><br>\n";
	print "<p>User name: <input type='text' name='name'></p>\n";
	print "<p>Password: <input type='password' name='pass'></p>\n";
	print "<p><input class='btn btn-default' type='submit' value='Login'></p></form>\n";
	if($cfg->load('allow_registrations') && $cfg->load('allow_registrations') ne 'off')
	{
		print "</div><div class='col-sm-6'><h3>Register a new account</h3><form method='POST' action='.'><br>\n";
		print "<p>User name: <input type='text' name='new_name'></p>\n";
		print "<p>Password: <input type='password' name='new_pass1'></p>\n";
		print "<p>Confirm: <input type='password' name='new_pass2'></p>\n";
		print "<p>Email (optional): <input type='email' name='new_email'></p>\n";
		print "<p><input class='btn btn-default' type='submit' value='Register'></p></form></div></div>\n";
	}
	print "</center>\n";
}

# Sanitize functions
sub sanitize_html
{
	my ($text) = @_;
	if($text)
	{
		$text =~ s/</&lt;/g;
		$text =~ s/"/&quot;/g;
		return $text;
	}
	else { return ""; }
}

sub sanitize_alpha
{
	my ($text) = @_;
	if($text)
	{
		$text =~ s/[^A-Za-z0-9\-\_]//g;
		return $text;
	}
	else { return ""; }
}

sub sanitize_email
{
	my ($text) = @_;
	if($text)
	{
		if(valid($text)) { return $text; }
		else { return ""; }
	}
	else { return ""; }
}

# Check if tables exist for initial use and possibly corrupted db
sub db_check
{
	if(!defined($db)) # Can't even use headers() if this fails.
	{
		print "Content-type: text/html\n\nError: Could not access database file. Please ensure NodePoint has the proper permissions.";
		exit(0);
	};
	$sql = $db->prepare("SELECT * FROM users WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE users (name TEXT, pass TEXT, email TEXT, level INT, loggedin TEXT, confirm TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM products WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE products (name TEXT, model TEXT, description TEXT, screenshot BLOB, vis TEXT, created TEXT, modified TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM releases WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE releases (productid INT, releasedby TEXT, version TEXT, notes TEXT, created TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM tickets WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE tickets (productid INT, releaseid TEXT, createdby TEXT, assignedto TEXT, title TEXT, description TEXT, link TEXT, status TEXT, resolution TEXT, subscribers TEXT, created TEXT, modified TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM comments WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE comments (ticketid INT, name TEXT, comment TEXT, created TEXT, modified TEXT, file TEXT, filename TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM log WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE log (ip TEXT, by TEXT, op TEXT, time TEXT, key INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM timetracking WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE timetracking (ticketid INT, name TEXT, spent REAL, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
}

# Log an event
sub logevent
{
	my ($op) = @_;
	eval
	{
		$sql = $db->prepare("INSERT INTO log VALUES (?, ?, ?, ?, ?);");
		$sql->execute($q->remote_addr, $logged_user, $op, now(), time);
	};
}

# Basic configuration
sub save_config
{
	$cfg->save("db_address", $q->param('db_address'));
	$cfg->save("admin_name", sanitize_alpha($q->param('admin_name')));
	if($q->param("admin_pass")) { $cfg->save("admin_pass", sha1_hex($q->param('admin_pass'))); }
	$cfg->save("site_name", sanitize_html($q->param('site_name')));
	$cfg->save("motd", $q->param('motd'));
	$cfg->save("css_template", $q->param('css_template'));
	$cfg->save("favicon", $q->param('favicon'));
	$cfg->save("default_vis", $q->param('default_vis'));
	$cfg->save("default_lvl", to_int($q->param('default_lvl')));
	$cfg->save("allow_registrations", $q->param('allow_registrations'));    
	$cfg->save("smtp_server", $q->param('smtp_server'));    
	$cfg->save("smtp_port", $q->param('smtp_port'));    
	$cfg->save("smtp_from", $q->param('smtp_from'));
	$cfg->save("api_read", $q->param('api_read'));
	$cfg->save("api_write", $q->param('api_write'));
	$cfg->save("upload_folder", $q->param('upload_folder'));
	$cfg->save("items_managed", $q->param('items_managed'));
	$cfg->save("custom_name", $q->param('custom_name'));
	$cfg->save("custom_type", $q->param('custom_type'));
}

# Check login credentials
sub check_user
{
	my ($n, $p) = @_;
	if($p eq $cfg->load("admin_pass") && $n eq $cfg->load("admin_name"))
	{
		$logged_user = $cfg->load("admin_name");
		$logged_lvl = 6;
		$cn = $q->cookie(-name => "np_name", -value => $logged_user);
		$cp = $q->cookie(-name => "np_key", -value => $cfg->load("admin_pass"));
	}
	eval
	{
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if(rtrim($p) eq $res[1] && $n eq $res[0])
			{
				$logged_user = $res[0];
				$logged_lvl = to_int($res[3]);
				$last_login = $res[4];
				$sql = $db->prepare("UPDATE users SET loggedin = ? WHERE name = ?;");
				$sql->execute(now(), $res[0]);
				$cn = $q->cookie(-name => "np_name", -value => $logged_user);
				$cp = $q->cookie(-name => "np_key", -value => $res[1]);
				last;
			}
		}
	}; # check silently since headers may not be set
}

# Trimming right spaces
sub rtrim
{
	my $s = shift;
	if($s)
	{
		$s =~ s/\s+$//g;
		return $s
	}
	else { return ""; }
}

# Trim all spaces
sub trim 
{
	my $s = shift; 
	if($s)
	{
		$s =~ s/\s+//g;       
		return $s;
	}
	else { return ""; }
}

# Trim left spaces
sub ltrim 
{
	my $s = shift; 
	if($s)
	{
		$s =~ s/^\s+//g;       
		return $s;
	}
	else { return ""; }
}

# Return current time
sub now
{
	return "" . localtime;
}

# Send email
sub notify
{
	my ($u, $title, $mesg) = @_;
	if($cfg->load('smtp_server') && $cfg->load('smtp_port') && $cfg->load('smtp_from') && $u && $title && $mesg)
	{
		my $lsql = $db->prepare("SELECT * FROM users;");
		$lsql->execute();
		while(my @res = $lsql->fetchrow_array())
		{
			if($res[0] eq $u && $res[2] ne "" && ($res[5] eq "" || $title eq "Email confirmation")) # user is good, email is not null, confirm is empty or this is confirm email
			{
				eval
				{
					my $smtp = Net::SMTP->new('korriban.sithempire.local', Port => 25, Timeout => 10, Debug => 1);
					#$smtp->auth($smtpuser, $smtppassword);
					$smtp->mail($cfg->load('smtp_from'));
					if($smtp->to($res[2]))
					{
						$smtp->data();
						$smtp->datasend("From: " . $cfg->load('smtp_from') . "\n");
						$smtp->datasend("To: " . $res[2] . "\n");
						$smtp->datasend("Subject: NodePoint - " . $title . "\n\n");
						$smtp->datasend($mesg . "\n");
						$smtp->datasend();
						$smtp->quit;
					}
					else
					{
						msg("Could not send notification email to " . $u . ", target email was rejected.", 1);
					}
				} or do {
					msg("Could not send notification email to " . $u . ", connection to SMTP server failed.", 1);
				};
			}
		}
	}
}

# Home page
sub home
{
	my @products;
	$sql = $db->prepare("SELECT ROWID,* FROM products;");
	$sql->execute();
	while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }

	if(!$q->cookie('np_gs'))
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Getting started</h3></div><div class='panel-body'>\n";
		print "<p>Use the " . $items{"Product"} . "s tab to browse available " . lc($items{"Product"}) . "s along with their " . lc($items{"Release"}) . "s. You can view basic information about them and see their description. Use the Tickets tab to browse current tickets and comments. You can also change your email address and password under the Settings tab.</p>\n";
		if($logged_lvl > 0) { print "<p>As an <span class='label label-success'>Authorised User</span>, you can also add new tickets to specific " . lc($items{"Product"}) . "s and " . lc($items{"Release"}) . "s, or comment on existing ones.</p>\n"; }
		if($logged_lvl > 1) { print "<p>Since you have <span class='label label-success'>Restricted View</span> permission, you can also view restricted products and tickets, those not typically visible to normal users.</p>\n"; }
		if($logged_lvl > 2) { print "<p>With <span class='label label-success'>Tickets Management</span> access, you can modify existing tickets entered by other users, such as change the status, add a resolution, or edit title and description. You can assign yourself to tickets, and you can also add new " . lc($items{"Release"}) . "s under the " . $items{"Product"} . "s tab.</p>\n"; }
		if($logged_lvl > 3) { print "<p>As a <span class='label label-success'>" . $items{"Product"} . "s Management</span> user, you can add new " . lc($items{"Product"}) . "s, edit existing ones, or change their visibility, view statistics. Archiving a product will prevent users from adding new tickets for it.</p>\n" }
		if($logged_lvl > 4) { print "<p>With the <span class='label label-success'>Users Managemenet</span> access level, you have the ability to edit users under the Settings tab. You can reset passwords and change access levels, along with adding new users. You can also delete comments under the Tickets tab.</p>\n"; }
		if($logged_lvl > 5) { print "<p>Since you are logged in as <span class='label label-success'>NodePoint Administrator</span>, you can edit initial settings under the Settings tab. Note that it is good practice to use a lower access user to do your daily tasks.</p>\n" }
		print "</div></div>\n";
	}

	if($logged_lvl > 0)
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets you created</h3></div><div class='panel-body'><table class='table table-striped'>\n";
		print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>" . $items{"Release"} . "</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
		$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($products[$res[1]] && $res[3] eq $logged_user) { print "<tr><td>" . $res[0] . "</td><td>" . $products[$res[1]] . "</td><td>" . $res[2] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
		}
		print "</table></div></div>";
	}
	
	print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets you follow</h3></div><div class='panel-body'><table class='table table-striped'>\n";
	print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>User</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
	$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC;");
	$sql->execute();
	while(my @res = $sql->fetchrow_array())
	{
		if($products[$res[1]] && $res[10] =~ /\b$logged_user\b/) { print "<tr><td>" . $res[0] . "</td><td>" . $products[$res[1]] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
	}
	print "</table></div></div>";

	if($logged_lvl > 2)
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets assigned to you</h3></div><div class='panel-body'><table class='table table-striped'>\n";
		print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>User</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
		$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($products[$res[1]] && $res[4] =~ /\b$logged_user\b/) { print "<tr><td>" . $res[0] . "</td><td>" . $products[$res[1]] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
		}
		print "</table></div></div>";
	}
}

#
# Processing connection from here
#

# Connect to config
eval
{
	$cfg = Config::Win32->new("NodePoint", "settings");
};
if(!defined($cfg)) # Can't even use headers() if this fails.
{
	print "Content-type: text/html\n\nError: Could not access " . Config::Win32->type . ". Please ensure NodePoint has the proper permissions.";
	exit(0);
};

# Connect to DB
if($cfg->load("db_address"))
{
	$db = DBI->connect("dbi:SQLite:dbname=" . $cfg->load("db_address"), '', '', { RaiseError => 0, PrintError => 0 }) or do { }; # Silently connect to check cookies
	db_check();
}

# Check cookies
if($q->cookie('np_name') && $q->cookie('np_key'))
{
	check_user($q->cookie('np_name'), $q->cookie('np_key'));
}

# Check items tracked
if($cfg->load("items_managed"))
{
	if($cfg->load("items_managed") eq "Projects with goals and milestones")
	{
		$items{"Product"} = "Project";
		$items{"Model"} = "Goal";
		$items{"Release"} = "Milestone";
	}
	elsif($cfg->load("items_managed") eq "Resources with locations and updates")
	{
		$items{"Product"} = "Resource";
		$items{"Model"} = "Location";
		$items{"Release"} = "Update";
	}
}
	
# Main loop
if($q->param('site_name') && $q->param('db_address') && $logged_user ne "" && $logged_user eq $cfg->load('admin_name')) # Save config by admin
{
	headers("Settings");
	if($q->param('site_name') && $q->param('db_address') && $q->param('admin_name') && $q->param('custom_name') && $q->param('default_lvl') && $q->param('default_vis') && $q->param('api_write') && $q->param('api_read')) # All required values have been filled out
	{
		# Test database settings
		$db = DBI->connect("dbi:SQLite:dbname=" . $q->param('db_address'), '', '', { RaiseError => 0, PrintError => 0 }) or do { msg("Could not verify database settings. Please hit back and try again.<br><br>" . $DBI::errstr, 0); exit(0); };
		db_check();
		save_config();
		msg("Settings updated. Press <a href='.'>here</a> to continue.", 3);
		logevent("Settings updated");
	}
	else
	{
		my $text = "Some values are missing: ";
		if(!$q->param('admin_name')) { $text .= "<span class='label label-danger'>Admin name</span> "; }
		if(!$q->param('default_lvl')) { $text .= "<span class='label label-danger'>Default access level</span> "; }
		if(!$q->param('default_vis')) { $text .= "<span class='label label-danger'>Ticket visibility</span> "; }
		if(!$q->param('api_read')) { $text .= "<span class='label label-danger'>API read key</span> "; }
		if(!$q->param('api_write')) { $text .= "<span class='label label-danger'>API write key</span> "; }
		if(!$q->param('custom_name')) { $text .= "<span class='label label-danger'>Custom ticket field</span> "; }
		$text .= " Please go back and try again.";
		msg($text, 0);
	}
	footers();
}
elsif(!$cfg->load("db_address") || !$cfg->load("site_name")) # first use
{
	headers("Initial configuration");
	if($q->param('site_name') && $q->param('db_address') && $q->param('custom_name') && $q->param('admin_name') && $q->param('admin_pass') && $q->param('default_lvl') && $q->param('default_vis') && $q->param('api_write') && $q->param('api_read')) # All required values have been filled out
	{
		# Test database settings
		$db = DBI->connect("dbi:SQLite:dbname=" . $q->param('db_address'), '', '', { RaiseError => 0, PrintError => 0 }) or do { msg("Could not verify database settings. Please hit back and try again.<br><br>" . $DBI::errstr, 0); exit(0); };
		save_config();
		msg("Initial settings saved to the " . $cfg->type . ". The NodePoint administrator name is <b>" . $cfg->load('admin_name') . "</b> with the password you provided. Be sure to memorize those as there is no way to recover them. Press <a href='.'>here</a> to go to the login page.", 3);
		db_check();
		footers();
	}
	else
	{
		if($q->param('site_name'))
		{
			my $text = "Some values are missing: ";
			if(!$q->param('admin_name')) { $text .= "<span class='label label-danger'>Admin name</span> "; }
			if(!$q->param('admin_pass')) { $text .= "<span class='label label-danger'>Admin password</span> "; }
			if(!$q->param('default_lvl')) { $text .= "<span class='label label-danger'>Default access level</span> "; }
			if(!$q->param('default_vis')) { $text .= "<span class='label label-danger'>Ticket visibility</span> "; }
			if(!$q->param('api_read')) { $text .= "<span class='label label-danger'>API read key</span> "; }
			if(!$q->param('api_write')) { $text .= "<span class='label label-danger'>API write key</span> "; }
			if(!$q->param('custom_name')) { $text .= "<span class='label label-danger'>Custom ticket field</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
		else
		{
			if($q->remote_addr eq "127.0.0.1" || $q->remote_addr eq "::1")
			{
				msg("Initial configuration not found! Create it now.", 2);
				print "<h3>Initial configuration</h3><p>These settings will be saved in the " . $cfg->type . ". It allows NodePoint to connect to the database server and sets various default values.</p>\n";
				print "<form method='POST' action='.'>\n";
				print "<p><div class='row'><div class='col-sm-4'>Database file name:</div><div class='col-sm-4'><input type='text' style='width:300px' name='db_address' value='.." . $cfg->sep . "db" . $cfg->sep . "nodepoint.db'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Site name:</div><div class='col-sm-4'><input style='width:300px' type='text' name='site_name' value='NodePoint'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Favicon:</div><div class='col-sm-4'><input style='width:300px' type='text' name='favicon' value='favicon.gif'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Bootstrap template:</div><div class='col-sm-4'><input style='width:300px' type='text' name='css_template' value='default.css'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Ticket visibility:</div><div class='col-sm-4'><select name='default_vis' style='width:300px'><option>Public</option><option>Private</option><option>Restricted</option></select></div></div></p>\n";
				print "<p>Tickets will have a default visibility when created. Public tickets can be seen by people not logged in, while private tickets require people to be logged in to view. Restricted ones can only be seen by authors and users with the <b>2 - Restricted view</b> level, ideal for helpdesk/support portals.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Allow user registrations:</div><div class='col-sm-4'><input type='checkbox' name='allow_registrations' checked=checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Default access level:</div><div class='col-sm-4'><select name='default_lvl' style='width:300px'><option value=5>5 - Users management</option><option value=4>4 - Products management</option><option value=3>3 - Tickets management</option><option value=2>2 - Restricted view</option><option value=1 selected=selected>1 - Authorized users</option><option value=0>0 - Unauthorized users</option></select></div></div></p>\n";
				print "<p>New registered users will be assigned a default access level, which can then be modified by users with the <b>5 - Users management</b> level. These are the access levels, with each rank having the lower permissions as well:</p>\n";
				print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can create users, reset passwords, change access levels</td></tr><tr><td>4</td><td>Products management</td><td>Can add, retire and edit products, view statistics</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create releases, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view restricted tickets and products</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
				my $key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API read key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_read' value='" . $key . "'></div></div></p>\n";
				$key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API write key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_write' value='" . $key . "'></div></div></p>\n";
				print "<p>API keys can be used by external applications to read and write tickets using the JSON API.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP server:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_server' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP port:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_port' value='25'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Support email:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_from' value='admin\@company.com'></div></div></p>\n";
				print "<p>If a SMTP server host name is entered, NodePoint will attempt to send an email when new tickets are created, or changes occur.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin username:</div><div class='col-sm-4'><input type='text' style='width:300px' name='admin_name' value='admin'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin password:</div><div class='col-sm-4'><input style='width:300px' type='password' name='admin_pass'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Public notice:</div><div class='col-sm-4'><input type='text' style='width:300px' name='motd' value='Welcome to NodePoint. Remember to be courteous when writing tickets. Contact the help desk for any problem.'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Upload folder:</div><div class='col-sm-4'><input type='text' style='width:300px' name='upload_folder' value='.." . $cfg->sep . "uploads'></div></div></p>\n";
				print "<p>The upload folder should be a local folder with write access and is used for product images. If left empty, image uploads will be disabled.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Items managed:</div><div class='col-sm-4'><select style='width:300px' name='items_managed'><option selected>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option></select></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Custom ticket field:</div><div class='col-sm-4'><input type='text' style='width:300px' name='custom_name' value='Related tickets'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Custom field type:</div><div class='col-sm-4'><select style='width:300px' name='custom_type'><option>Text</option><option>Link</option><option>Checkbox</option></select></div></div></p>\n";
				
				print "<p><input class='btn btn-default pull-right' type='submit' value='Save'></p></form>\n"; 
			}
			else
			{
				msg("Initial configuration not found! It needs to be created from <b>localhost</b> only.", 0);
			}
		}
		footers();
	}
}
elsif($q->param('api')) # API calls
{
	print $q->header(-type => "text/plain");
	if($q->param('api') eq "show_ticket")
	{
		if(!$q->param('id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'id' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('key'))
		{
			print "{\n";
			print " \"message\": \"Missing 'key' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif($q->param('key') ne $cfg->load('api_read'))
		{
			print "{\n";
			print " \"message\": \"Invalid 'key' value.\",\n";
			print " \"status\": \"ERR_INVALID_KEY\"\n";
			print "}\n";
		}
		else
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('id')));
			my $found = 0;
			while(my @res = $sql->fetchrow_array())
			{
				$found = 1;
				print "{\n";
				print " \"message\": \"Ticket showed.\",\n";
				print " \"status\": \"OK\",\n";
				print " \"id\": \"" . $res[0] . "\",\n";
				print " \"product_id\": \"" . $res[1] . "\",\n";
				print " \"release_id\": \"" . $res[2] . "\",\n";
				print " \"created_by\": \"" . $res[3] . "\",\n";
				print " \"assigned_to\": \"" . $res[4] . "\",\n";
				print " \"title\": \"" . $res[5] . "\",\n";
				print " \"description\": \"" . $res[6] . "\",\n";
				print " \"custom\": \"" . $res[7] . "\",\n";
				print " \"status\": \"" . $res[8] . "\",\n";
				print " \"resolution\": \"" . $res[9] . "\",\n";
				print " \"followers\": \"" . $res[10] . "\",\n";
				print " \"created_on\": \"" . $res[11] . "\",\n";
				print " \"modified_on\": \"" . $res[12] . "\",\n";
				print " \"comments\": [\n";
				my $sql2 = $db->prepare("SELECT ROWID,* FROM comments WHERE ticketid = ?;");
				$sql2->execute(to_int($q->param('id')));
				my $found = 0;
				while(my @res2 = $sql2->fetchrow_array())
				{
					if($found) { print ",\n"; }
					$found = 1;
					print "  {\n";
					print "   \"id\": \"" . $res2[0] . "\",\n";
					print "   \"name\": \"" . $res2[2] . "\",\n";
					print "   \"comment\": \"" . $res2[3] . "\",\n";
					print "   \"created_on\": \"" . $res2[4] . "\"\n";
					print "   \"modified_on\": \"" . $res2[5] . "\"\n";
					print "  }";
				}
				print "\n ]\n";
				print "}\n";
			}
			if(!$found)
			{
				print "{\n";
				print " \"message\": \"Ticket not found.\",\n";
				print " \"status\": \"ERR_INVALID_ID\"\n";
				print "}\n";
			}
		}
	}
	elsif($q->param('api') eq "add_ticket")
	{
		if(!$q->param('title'))
		{
			print "{\n";
			print " \"message\": \"Missing 'title' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('description'))
		{
			print "{\n";
			print " \"message\": \"Missing 'description' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('product_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'product_id' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('release_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'release_id' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('key'))
		{
			print "{\n";
			print " \"message\": \"Missing 'key' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif($q->param('key') ne $cfg->load('api_write'))
		{
			print "{\n";
			print " \"message\": \"Invalid 'key' value.\",\n";
			print " \"status\": \"ERR_INVALID_KEY\"\n";
			print "}\n";
		}
		else
		{
			my $found = 0;
			$sql = $db->prepare("SELECT name FROM products WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array()) { $found = 1; }
			if(!$found)
			{
				print "{\n";
				print " \"message\": \"Invalid 'product_id' value.\",\n";
				print " \"status\": \"ERR_INVALID_PRODUCT_ID\"\n";
				print "}\n";
			}
			else
			{
				my $custom = "";
				if($q->param('custom')) { $custom = sanitize_html($q->param('custom')); }
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), "api", "", sanitize_html($q->param('title')), sanitize_html($q->param('description')), $custom, "New", "", "", now(), "Never");
				$sql = $db->prepare("SELECT last_insert_rowid();");
				$sql->execute();
				my $rowid = -1;
				while(my @res = $sql->fetchrow_array()) { $rowid = to_int($res[0]); }
				print "{\n";
				print " \"message\": \"Ticket " . $rowid . " added.\",\n";
				print " \"status\": \"OK\"\n";
				print "}\n";
			}
		}
	}
	else
	{
		print "{\n";
		print " \"message\": \"Invalid 'api' value. Valid values are: 'show_ticket', 'add_ticket'.\",\n";
		print " \"status\": \"ERR_INVALID_API\"\n";
		print "}\n";
	}
	exit(0);
}
elsif($q->param('file') && $cfg->load('upload_folder')) # Show an image
{
	my $ft = File::Type->new();
	my $filename = $cfg->load('upload_folder') . $cfg->sep . sanitize_alpha($q->param('file'));
	my $type = $ft->checktype_filename($filename);
	if(!$type)
	{
		headers("Error");
		msg("File not found or corrupted.", 0);
		exit(0);
	}
	open(my $fp, $filename);
	if($type eq "application/octet-stream") { print "Content-type: text/plain\n\n"; }
	else { print "Content-type: " . $type . "\n\n"; }
	while(my $line = <$fp>)
	{
		print $line;
	}
	exit(0);
}
elsif($q->param('m')) # Modules
{
	if($q->param('m') eq "settings" && $logged_user ne "")
	{
		$cgs = $q->cookie(-name => "np_gs", -expires => '+3M', -value => "1");
		headers("Settings");
		print "<p>You are logged in as <b>" . $logged_user . "</b> and your access level is <b>" . $logged_lvl . "</b>. Press <a href='./?m=logout'>here</a> to log out.</p>\n";
		if($logged_lvl > 2)
		{
			$sql = $db->prepare("SELECT * FROM timetracking WHERE name = ?;");
			$sql->execute($logged_user);
			my $totaltime = 0;
			while(my @res = $sql->fetchrow_array()) { $totaltime = $totaltime + to_float($res[2]); }
			print "<p>You have spent a total of <b>" . $totaltime . "</b> hours on tickets.</p>\n";
		}
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($res[0] eq $logged_user && $res[2] ne "" && $res[5] ne "" && $cfg->load('smtp_server'))
			{
				msg("<nobr><form method='POST' action='.'><input type='hidden' name='m' value='confirm_email'></nobr>Your email is not yet confirmed. Please enter the confirmation code here: <input type='text' name='code'> <input class='btn btn-default pull-right' type='submit' value='Confirm'></form>", 2);
			}
		}
		if($logged_user ne $cfg->load('admin_name') && !$cfg->load('smtp_server')) { msg("Email notifications are disabled.", 1); }
		if($logged_lvl != 6)
		{
			my $email = "";
			$sql = $db->prepare("SELECT * FROM users;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] eq $logged_user)
				{
					$email = $res[2];
				}
			}		    
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Change email</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.'><input type='hidden' name='m' value='change_email'>To change your notification email address, enter a new address here. Leave empty to disable notifications:<br><input type='text' name='new_email' size='40' value='" . $email . "'> <input class='btn btn-default pull-right' type='submit' value='Change email'></form></div></div>";
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Change password</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.'><input type='hidden' name='m' value='change_pass'>Current password: <input type='password' name='current_pass'> New password: <input type='password' name='new_pass1'> Confirm: <input type='password' name='new_pass2'> <input class='btn btn-default pull-right' type='submit' value='Change password'></form></div></div>";
		}
		if($logged_lvl > 4)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Users management</h3></div><div class='panel-body'>\n";
			print "<p>Filter users by access level: <a href='./?m=settings'>All</a> | <a href='./?m=settings&filter_users=0'>0</a> | <a href='./?m=settings&filter_users=1'>1</a> | <a href='./?m=settings&filter_users=2'>2</a> | <a href='./?m=settings&filter_users=3'>3</a> | <a href='./?m=settings&filter_users=4'>4</a> | <a href='./?m=settings&filter_users=5'>5</a></p>";
			print "<table class='table table-striped'><tr><th>User name</th><th>Email</th><th>Level</th><th>Change access level</th><th>Reset password</th><th>Last login</th></tr>\n";
			if(defined($q->param("filter_users")))
			{
				$sql = $db->prepare("SELECT * FROM users WHERE level = ?;");
				$sql->execute(to_int($q->param("filter_users")));
			}
			else
			{
				$sql = $db->prepare("SELECT * FROM users;");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[0] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td><a href='./?m=change_lvl&u=" . $res[0] . "'>Change access level</a></td><td><a href='./?m=reset_pass&u=" . $res[0] . "'>Reset password</a></td><td>" . $res[4] . "</td></tr>\n";
			}
			print "</table>\n";
			print "<h4>Manually add a new user:</h4><form method='POST' action='.'>\n";
			print "<div class='row'><div class='col-sm-6'>User name: <input type='text' name='new_name'></div><div class='col-sm-6'>Email address (optional): <input type='email' name='new_email'></div></div><div class='row'><div class='col-sm-6'>Password: <input type='password' name='new_pass1'></div><div class='col-sm-6'>Confirm password: <input type='password' name='new_pass2'></div></div><input class='btn btn-default pull-right' type='submit' value='Add user'></p></form>\n";
			print "</div></div>\n";    
		}
		if($logged_lvl > 3)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Statistics</h3></div><div class='panel-body'>\n";
			print "<p><form method='GET' action='.'><input type='hidden' name='m' value='stats'>Report type: <select name='report'><option value='1'>Time spent per user</option><option value='2'>Time spent per ticket</option><option value='3'>Tickets created per " . lc($items{"Product"}) . "</option><option value='4'>Tickets created per user</option><option value='5'>Tickets created per day</option><option value='6'>Tickets created per month</option><option value='7'>Tickets per status</option><option value='8'>Users per access level</option></select><span class='pull-right'><input class='btn btn-default' type='submit' value='Show'> <input class='btn btn-default' type='submit' name='csv' value='Export as CSV'></span>\n";
			print "</form></p></div></div>\n";
		}
		if($logged_lvl > 5)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Initial settings</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.'><table class='table table-striped'><tr><th>Setting</th><th>Value</th></tr>\n";
			print "<tr><td>Database file</td><td><input style='width:300px' type='text' name='db_address' value=\"" .  $cfg->load("db_address") . "\"></td></tr>\n";
			print "<tr><td>Admin name</td><td><input style='width:300px' type='text' name='admin_name' value=\"" .  $cfg->load("admin_name") . "\"></td></tr>\n";
			print "<tr><td>Admin password</td><td><input style='width:300px' type='password' name='admin_pass' value=''></td></tr>\n";
			print "<tr><td>Site name</td><td><input style='width:300px' type='text' name='site_name' value=\"" . $cfg->load("site_name") . "\"></td></tr>\n";
			print "<tr><td>Public notice</td><td><input style='width:300px' type='text' name='motd' value=\"" . $cfg->load("motd") . "\"></td></tr>\n";
			print "<tr><td>Bootstrap template</td><td><input style='width:300px' type='text' name='css_template' value=\"" . $cfg->load("css_template") . "\"></td></tr>\n";
			print "<tr><td>Favicon</td><td><input style='width:300px' type='text' name='favicon' value=\"" . $cfg->load("favicon") . "\"></td></tr>\n";
			print "<tr><td>Ticket visibility</td><td><select style='width:300px' name='default_vis'>";
			if($cfg->load("default_vis") eq "Restricted") { print "<option>Public</option><option>Private</option><option selected>Restricted</option>"; }
			elsif($cfg->load("default_vis") eq "Private") { print "<option>Public</option><option selected>Private</option><option>Restricted</option>"; }
			else { print "<option selected>Public</option><option>Private</option><option>Restricted</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>Default access level</td><td><input style='width:300px' type='text' name='default_lvl' value=\"" . $cfg->load("default_lvl") . "\"></td></tr>\n";
			print "<tr><td>Allow registrations</td><td><select style='width:300px' name='allow_registrations'>";
			if($cfg->load("allow_registrations") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>API read key</td><td><input style='width:300px' type='text' name='api_read' value=\"" . $cfg->load("api_read") . "\"></td></tr>\n";
			print "<tr><td>API write key</td><td><input style='width:300px' type='text' name='api_write' value=\"" . $cfg->load("api_write") . "\"></td></tr>\n";
			print "<tr><td>SMTP server</td><td><input style='width:300px' type='text' name='smtp_server' value=\"" . $cfg->load("smtp_server") . "\"></td></tr>\n";
			print "<tr><td>SMTP port</td><td><input style='width:300px' type='text' name='smtp_port' value=\"" . $cfg->load("smtp_port") . "\"></td></tr>\n";
			print "<tr><td>Support email</td><td><input style='width:300px' type='text' name='smtp_from' value=\"" . $cfg->load("smtp_from") . "\"></td></tr>\n";
			print "<tr><td>Upload folder</td><td><input style='width:300px' type='text' name='upload_folder' value=\"" . $cfg->load("upload_folder") . "\"></td></tr>\n";
			print "<tr><td>Items managed</td><td><select style='width:300px' name='items_managed'>";
			if($cfg->load("items_managed") eq "Projects with goals and milestones") { print "<option>Products with models and releases</option><option selected>Projects with goals and milestones</option><option>Resources with locations and updates</option>"; }
			elsif($cfg->load("items_managed") eq "Resources with locations and updates") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option selected>Resources with locations and updates</option>"; }
			else { print "<option selected>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option>"; }
			print "</select></td></tr>\n";			
			print "<tr><td>Custom ticket field</td><td><input style='width:300px' type='text' name='custom_name' value=\"" . $cfg->load("custom_name") . "\"></td></tr>\n";
			print "<tr><td>Custom field type</td><td><select style='width:300px' name='custom_type'>";
			if($cfg->load("custom_type") eq "Link") { print "<option>Text</option><option selected>Link</option><option>Checkbox</option>"; }
			elsif($cfg->load("custom_type") eq "Checkbox") { print "<option>Text</option><option>Link</option><option selected>Checkbox</option>"; }
			else { print "<option selected>Text</option><option>Link</option><option>Checkbox</option>"; }
			print "</select></td></tr>\n";
			print "</table>The admin password will be left unchanged if empty.<input class='btn btn-default pull-right' type='submit' value='Save settings'></form></div></div>\n";
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Log (last 50 events)</h3></div><div class='panel-body'>\n";
			print "<form style='display:inline' method='POST' action='.'><input type='hidden' name='m' value='clear_log'><input class='btn btn-default pull-right' type='submit' value='Clear log'><br></form><a name='log'></a><p>Filter log by events: <a href='./?m=settings#log'>All</a> | <a href='./?m=settings&filter_log=Failed#log'>Failed logins</a> | <a href='./?m=settings&filter_log=Success#log'>Successful logins</a> | <a href='./?m=settings&filter_log=level#log'>Level changes</a> | <a href='./?m=settings&filter_log=password#log'>Password changes</a> | <a href='./?m=settings&filter_log=user#log'>New users</a> | <a href='./?m=settings&filter_log=setting#log'>Settings updated</a></p>\n";
			print "<table class='table table-striped'><tr><th>IP address</th><th>User</th><th>Event</th><th>Time</th></tr>\n";
			if($q->param("filter_log"))
			{
				$sql = $db->prepare("SELECT * FROM log DESC WHERE op LIKE ? ORDER BY key LIMIT 50;");
				$sql->execute("%" . sanitize_alpha($q->param("filter_log")) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT * FROM log ORDER BY key DESC LIMIT 50;");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[0] . "</td><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>\n";
			}
			print "</table></div></div>\n";
		}
	}
	elsif($q->param('m') eq "clear_log" && $logged_lvl > 5)
	{
		headers("Settings");
		$sql = $db->prepare("DELETE FROM log;");
		$sql->execute();
		msg("Log cleared. Press <a href='./?m=settings'>here</a> to continue.", 3);
	}
	elsif($q->param('m') eq "confirm_email" && $logged_user ne "" && defined($q->param('code')))
	{
		headers("Settings");
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		my $found = 0;
		while(my @res = $sql->fetchrow_array())
		{
			if($res[0] eq $logged_user && $res[5] eq sanitize_alpha($q->param('code')))
			{
				$sql = $db->prepare("UPDATE users SET confirm = '' WHERE name = ?;");
				$sql->execute($logged_user);
				$found = 1;
				msg("Email address confirmed. Press <a href='.'>here</a> to continue.", 3);
				last;
			}
		}
		if(!$found) { msg("Confirmation code not found. Please go back and try again.", 0); }
	}
	elsif($q->param('m') eq "change_pass" && $logged_user ne "" && defined($q->param('new_pass1')) && defined($q->param('new_pass2')) && defined($q->param('current_pass')))
	{
		my $found = 0;
		headers("Settings");
		if($q->param('new_pass1') ne $q->param('new_pass2'))
		{
			msg("Passwords do not match. Please go back and try again.", 0);
		}
		elsif(length($q->param('new_pass1')) < 6)
		{
			msg("Your password should be at least 6 characters. Please go back and try again.", 0);    
		}
		else
		{
			$sql = $db->prepare("SELECT * FROM users;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] eq $logged_user && $res[1] eq sha1_hex($q->param('current_pass')))
				{
					$sql = $db->prepare("UPDATE users SET pass = '" . sha1_hex($q->param('new_pass1')) . "' WHERE name = ?;");
					$sql->execute($logged_user);
					msg("Password changed. Press <a href='.'>here</a> to go back to the login page.", 3);
					logevent("Password change: " . $logged_user);
					$found = 1;
					last;
				}
			}	    
			if(!$found) { msg("Could not confirm your password. Please go back and try again.", 0); }
		}
	}
	elsif($q->param('m') eq "change_email" && $logged_user ne "" && defined($q->param('new_email')))
	{
		headers("Settings");
		if(length(sanitize_email($q->param('new_email'))) > 36)
		{
			msg("Email address should be less than 36 characters. Please go back and try again.", 0);
		}
		else
		{
			my $confirm = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..16;
			$sql = $db->prepare("SELECT * FROM users;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] eq $logged_user)
				{
					$sql = $db->prepare("UPDATE users SET confirm = '" . $confirm . "' WHERE name = ?;");
					$sql->execute($logged_user);
					$sql = $db->prepare("UPDATE users SET email = '" . sanitize_email($q->param('new_email')) . "' WHERE name = ?;");
					$sql->execute($logged_user);
					msg("Email address updated. Press <a href='.'>here</a> to continue.", 3);
					notify($logged_user, "Email confirmation", "Please confirm your email by logging into the NodePoint interface, and entering the following confirmation code under Settings: " . $confirm);
					last;
				}
			}
		}	    
	}
	elsif($q->param('m') eq "logout" && $logged_user ne "")
	{
		$cn = $q->cookie(-name => "np_name", -value => "");
		$cp = $q->cookie(-name => "np_key", -value => "");
		headers("Settings");
		msg("You have now logged out. Press <a href='.'>here</a> to go back to the login page.", 3);
	}
	elsif($q->param('m') eq "change_lvl" && $logged_lvl > 4 && $q->param('u') && defined($q->param('newlvl')))
	{
		headers("Settings");
		if(to_int($q->param('newlvl')) < 0 || to_int($q->param('newlvl')) > 5)
		{
			msg("Invalid access level. Please go back and try again.", 0);
		}
		else
		{
			$sql = $db->prepare("UPDATE users SET level = ? WHERE name = ?;");
			$sql->execute(to_int($q->param('newlvl')), sanitize_alpha($q->param('u')));
			msg("Updated access level for user <b>" . sanitize_alpha($q->param('u')) . "</b>. Press <a href='./?m=settings'>here</a> to continue.", 3);
			logevent("Level change: " . sanitize_alpha($q->param('u')));
		}
	}
	elsif($q->param('m') eq "change_lvl" && $logged_lvl > 4 && $q->param('u'))
	{
		headers("Settings");
		print "<p><form method='POST' action='.'><input type='hidden' name='m' value='change_lvl'><input type='hidden' name='u' value='" . sanitize_alpha($q->param('u')) . "'>Select a new access level for user <b>" . sanitize_alpha($q->param('u')) . "</b>: <select name='newlvl'><option>0</option><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select><br><input class='btn btn-default' type='submit' value='Change level'></form></p><br>\n";
		print "<p>Here is a list of available NodePoint levels:</p>\n";
		print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can create users, reset passwords, change access levels</td></tr><tr><td>4</td><td>" . $items{"Product"} . "s management</td><td>Can add, retire and edit " . lc($items{"Product"}) . "s, view statistics</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create " . lc($items{"Release"}) . "s, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view restricted tickets and " . lc($items{"Product"}) . "s</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
	}
	elsif($q->param('m') eq "reset_pass" && $logged_lvl > 4 && $q->param('u'))
	{
		headers("Settings");
		my $newpass = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..8;
		$sql = $db->prepare("UPDATE users SET pass = ? WHERE name = ?;");
		$sql->execute(sha1_hex($newpass), sanitize_alpha($q->param('u')));
		msg("Password reset for user <b>" . sanitize_alpha($q->param('u')) . "</b>. The new password is  <b>" . $newpass . "</b>  Press <a href='./?m=settings'>here</a> to continue.", 3);
		notify(sanitize_alpha($q->param('u')), "Password reset", "Your password has been reset by user: " . $logged_user);
		logevent("Password change: " . sanitize_alpha($q->param('u')));
	}
	elsif($q->param('m') eq "view_product" && $q->param('p'))
	{
		headers($items{"Product"} . "s");
		$sql = $db->prepare("SELECT ROWID,* FROM products WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('p')));
		my $vis = "";
		while(my @res = $sql->fetchrow_array())
		{
			$vis = $res[5];
			if($res[5] eq "Public" || ($res[5] eq "Private" && $logged_user ne "") || ($res[5] eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3)
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Product"} . " information</h3></div><div class='panel-body'>\n";
				if($logged_lvl > 3) { print "<form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='edit_product'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'>\n"; }
				if($logged_lvl > 3) { print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <input style='width:200px' type='text' name='product_name' value='" . $res[1] . "'></div><div class='col-sm-6'>" . $items{"Model"} . ": <input type='text' name='product_model' value='" . $res[2] . "'></div></div>\n"; }
				else { print "<div class='row'><div class='col-sm-6'>Product name: <b>" . $res[1] . "</b></div><div class='col-sm-6'>" . $items{"Model"} . ": <b>" . $res[2] . "</b></div></div>\n"; }
				print "<div class='row'><div class='col-sm-6'>Created on: <b>" . $res[6] . "</b></div><div class='col-sm-6'>Last modified on: <b>" . $res[7] . "</b></div></div>\n";
				if($logged_lvl > 3)
				{
					print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <select name='product_vis'><option";
					if($res[5] eq "Public") { print " selected=selected"; }
					print ">Public</option><option";
					if($res[5] eq "Private") { print " selected=selected"; }
					print ">Private</option><option";
					if($res[5] eq "Restricted") { print " selected=selected"; }
					print ">Restricted</option><option";
					if($res[5] eq "Archived") { print " selected=selected"; }
					print ">Archived</option></select></div></div>\n";
				}
				else { print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <b>" . $res[5] . "</b></div></div>\n"; }
				if($logged_lvl > 3) { print "Description:<br><textarea rows='10' name='product_desc' style='width:99%'>" . $res[3] . "</textarea>\n"; }
				else { print "Description:<br><pre>" . $res[3] . "</pre>\n"; }
				if($res[4] ne "") { print "<p><img src='./?file=" . $res[4] . "' style='max-width:95%'></p>\n"; }
				if($logged_lvl > 3) { print "<input class='btn btn-default pull-right' type='submit' value='Update " . lc($items{"Product"}) . "'>Change " . lc($items{"Product"}) . " image: <input type='file' name='product_screenshot'></form>\n"; }
				print "</div></div>\n";
			}
			if($logged_lvl > 2 && $vis ne "Archived")
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Add " . lc($items{"Release"}) . " to this " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><form method='POST' action='.'>\n";
				print "<input type='hidden' name='m' value='add_release'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'><div class='row'><div class='col-sm-4'>" . $items{"Release"} . ": <input type='text' name='release_version'></div><div class='col-sm-6'>Notes: <input type='text' name='release_notes' style='width:300px'></div></div><input class='btn btn-default pull-right' type='submit' value='Add " . lc($items{"Release"}) . "'>\n";
				print "</div></div>\n";    
			}
			if($vis eq "Public" || ($vis eq "Private" && $logged_user ne "") || ($vis eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3)
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Release"} . "s</h3></div><div class='panel-body'><table class='table table-striped'>\n";
				print "<tr><th>" . $items{"Release"} . "</th><th>User</th><th>Notes</th><th>Date</th></tr>\n";
				$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('p')));
				while(my @res = $sql->fetchrow_array())
				{
					print "<tr><td>" . $res[2] . "</td><td>" . $res[1] . "</td><td>" . $res[3] . "</td><td>" .  $res[4] . "</td></tr>\n";
				}
				print "</table></div></div>\n";
			}
		}
	}
	elsif($logged_lvl > 2 && $q->param('m') eq "add_release")
	{
		headers($items{"Product"} . "s");
		if(!$q->param('release_version') || !$q->param('release_notes') || !$q->param('product_id'))
		{
			my $text = "Required fields missing: ";
			if(!$q->param('release_notes')) { $text .= "<span class='label label-danger'>" . $items{"Release"} . " notes</span> "; }
			if(!$q->param('product_id')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " ID</span> "; }
			if(!$q->param('release_version')) { $text .= "<span class='label label-danger'>" . $items{"Release"} . "</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);	    
		}
		elsif(length(sanitize_html($q->param('release_version'))) > 50 || length(sanitize_html($q->param('release_notes'))) > 999)
		{
			msg("Version should be less than 50 characters, notes should be less than 1,000 characters. Please go back and try again.", 0);
		}
		else
		{
			$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			my $found;
			while(my @res = $sql->fetchrow_array())
			{
				if(lc($res[2]) eq lc(sanitize_html($q->param('release_version')))) { $found = 1; }
			}
			if($found)
			{
				msg("This " . lc($items{"Release"}) . " already exists. Please go back and try again.", 0);
			}
			else
			{
				$sql = $db->prepare("INSERT INTO releases VALUES (?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), $logged_user, sanitize_html($q->param('release_version')), sanitize_html($q->param('release_notes')), now());
				msg($items{"Release"} . " added. Press <a href='./?m=products'>here</a> to continue.", 3);
			}
		}
	}
	elsif($logged_lvl > 3 && $q->param('m') eq "add_product")
	{
		headers($items{"Product"} . "s");
		if($q->param('product_name') && $q->param('product_release') && $q->param('product_vis'))
		{
			my $product = sanitize_html($q->param('product_name'));
			my $desc = "";
			my $screenshot = "";
			my $model = "";
			my $release = sanitize_html($q->param('product_release'));
			my $vis = sanitize_html($q->param('product_vis'));
			if($q->param('product_desc')) { $desc = sanitize_html($q->param('product_desc')); }
			if($q->param('product_model')) { $model = sanitize_html($q->param('product_model')); }
			if($q->param('product_screenshot') && $cfg->load('upload_folder'))
			{
				if($q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/jpeg" || $q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/gif" || $q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/png")
				{
					eval
					{
						my $lightweight_fh = $q->upload('product_screenshot');
						if(defined $lightweight_fh)
						{
							my $tmpfilename = $q->tmpFileName($lightweight_fh);
							my $file_size = (-s $tmpfilename);
							if($file_size > 999000)
							{
								msg("Image size is too large.", 1);
							}
							else
							{
								my $io_handle = $lightweight_fh->handle;
								binmode($io_handle);
								my ($buffer, $bytesread);
								$screenshot = Data::GUID->new;
								open(my $OUTFILE, ">" . $cfg->load('upload_folder') . $cfg->sep . $screenshot) or die $@;
								while($bytesread = $io_handle->read($buffer,1024))
								{
									print $OUTFILE $buffer;
								}
							}
						}
					};
					if($@) { msg("Image uploading to <b>" . $cfg->load('upload_folder') . $cfg->sep . $screenshot . "</b> failed.", 1); }
				}
				else
				{
					msg("Image type is unknown, must be a PNG, GIF or JPG.", 1);
				}
			}
			$sql = $db->prepare("SELECT * FROM products;");
			$sql->execute();
			my $found;
			while(my @res = $sql->fetchrow_array())
			{
				if(lc($res[0]) eq lc($product)) { $found = 1; }
			}
			if($found)
			{
				msg($items{"Product"} . " name already exist. Please go back and try again.", 0);
			}
			elsif(length($product) > 50 || length($model) > 50 || length($desc) > 9999)
			{
				msg($items{"Product"} . " name and " . lc($items{"Model"}) . " must be less than 50 characters. Description must be less than 10,000 characters. Please go back and try again.", 0);
			}
			else
			{
				$sql = $db->prepare("INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?);");
				$sql->execute($product, $model, $desc, $screenshot, $vis, now(), "Never");
				my $rowid = -1;
				$sql = $db->prepare("SELECT ROWID FROM products WHERE name = ?;");
				$sql->execute($product);
				while(my @res = $sql->fetchrow_array())
				{
					$rowid = to_int($res[0]);
				}
				if($rowid > 0)
				{
					$sql = $db->prepare("INSERT INTO releases VALUES (?, ?, ?, ?, ?);");
					$sql->execute($rowid, $logged_user, $release, "Initial release", now());
				}
				msg($items{"Product"} . " <b>" . sanitize_html($q->param('product_name')) . "</b> added. Press <a href='./?m=products'>here</a> to continue.", 3);
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('product_name')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " name</span> "; }
			if(!$q->param('product_vis')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " visibility</span> "; }
			if(!$q->param('product_release')) { $text .= "<span class='label label-danger'>" . $items{"Release"} . "</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);	    
		}
	}
	elsif($logged_lvl > 3 && $q->param('m') eq "edit_product" && $q->param('product_id'))
	{
		headers($items{"Product"} . "s");
		if($q->param('product_name') && $q->param('product_vis'))
		{
			my $desc = "";
			my $model = "";
			my $screenshot = "";
			my $product = sanitize_html($q->param('product_name'));
			my $vis = sanitize_html($q->param('product_vis'));
			if($q->param('product_desc')) { $desc = sanitize_html($q->param('product_desc')); }
			if($q->param('product_model')) { $model = sanitize_html($q->param('product_model')); }
			if($q->param('product_screenshot') && $cfg->load('upload_folder'))
			{
				if($q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/jpeg" || $q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/gif" || $q->uploadInfo($q->param('product_screenshot'))->{'Content-Type'} eq "image/png")
				{
					eval
					{
						my $lightweight_fh = $q->upload('product_screenshot');
						if(defined $lightweight_fh)
						{
							my $tmpfilename = $q->tmpFileName($lightweight_fh);
							my $file_size = (-s $tmpfilename);
							if($file_size > 999000)
							{
								msg("Image size is too large.", 1);
							}
							else
							{
								my $io_handle = $lightweight_fh->handle;
								binmode($io_handle);
								my ($buffer, $bytesread);
								$screenshot = Data::GUID->new;
								open(my $OUTFILE, ">" . $cfg->load('upload_folder') . $cfg->sep . $screenshot) or die $@;
								while($bytesread = $io_handle->read($buffer,1024))
								{
									print $OUTFILE $buffer;
								}
							}
						}
					};
					if($@) { msg("Image uploading to <b>" . $cfg->load('upload_folder') . $cfg->sep . $screenshot . "</b> failed.", 1); }
				}
				else
				{
					msg("Image type is unknown, must be a PNG, GIF or JPG.", 1);
				}
			}
			if(length($product) > 50 || length($model) > 50 || length($desc) > 9999)
			{
				msg($items{"Product"} . " name and " . lc($items{"Model"}) . " must be less than 50 characters. Description must be less than 10,000 characters. Please go back and try again.", 0);
			}
			else
			{
				$sql = $db->prepare("UPDATE products SET name = ?, model = ?, description = ?, vis = ?, modified = ? WHERE ROWID = ?;");
				$sql->execute($product, $model, $desc, $vis, now(), to_int($q->param('product_id')));
				if($screenshot ne "")
				{
					$sql = $db->prepare("UPDATE products SET screenshot = ? WHERE ROWID = ?;");
					$sql->execute($screenshot, to_int($q->param('product_id')));
				}
				msg($items{"Product"} . " <b>" . sanitize_html($q->param('product_name')) . "</b> updated. Press <a href='./?m=products'>here</a> to continue.", 3);
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('product_name')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " name</span> "; }
			if(!$q->param('product_vis')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " visibility</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);	    
		}
	}
	elsif($q->param('m') eq "products")
	{
		headers($items{"Product"} . "s");
		if($logged_lvl > 3)  # add new product pane
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Add a new " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'>\n";
			print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <input type='text' name='product_name' style='width:200px'></div><div class='col-sm-6'>" . $items{"Model"} . ": <input type='text' name='product_model' style='width:200px'></div></div>\n";
			print "<div class='row'><div class='col-sm-6'>Initial " . lc($items{"Release"}) . ": <input type='text' name='product_release' style='width:200px' value='1.0'></div><div class='col-sm-6'>" . $items{"Product"} . " visibility: <select name='product_vis'><option>Public</option><option>Private</option><option>Restricted</option></select></div></div>\n";
			print "Description:<br><textarea name='product_desc' rows='10' style='width:99%'></textarea><br><input class='btn btn-default pull-right' type='submit' value='Add " . lc($items{"Product"}) . "'>";
			if($cfg->load('upload_folder')) { print $items{"Product"} . " image: <input type='file' name='product_screenshot'>\n"; }
			print "<input type='hidden' name='m' value='add_product'></form></div></div>\n";
		}
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		my $found;
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>List of " . lc($items{"Product"}) . "s</h3></div><div class='panel-body'><table class='table table-striped'>\n";
		print "<tr><th>ID</th><th>Name</th><th>" . $items{"Model"} . "</th></tr>\n";
		while(my @res = $sql->fetchrow_array())
		{
			if($res[5] eq "Public" || ($res[5] eq "Private" && $logged_user ne "") || ($res[5] eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3) { print "<tr><td>" . $res[0] . "</td><td><a href='./?m=view_product&p=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[2] . "</td></tr>\n"; }
		}
		print "</table></div></div>\n";
	}
	elsif($q->param('m') eq "update_ticket" && $logged_lvl > 2 && $q->param('t'))
	{
		headers("Tickets");
		if($q->param('ticket_status') && $q->param('ticket_title') && $q->param('ticket_desc') && ($q->param('ticket_resolution') || ($q->param('ticket_status') eq "Open" || $q->param('ticket_status') eq "New")))
		{
			my $resolution = "";
			if($q->param('ticket_resolution')) { $resolution = sanitize_html($q->param('ticket_resolution')); }
			my $lnk = "";
			if($q->param('ticket_link')) { $lnk = sanitize_html($q->param('ticket_link')); }
			my $assigned = "";
			if($q->param('ticket_assigned')) { $assigned = sanitize_html($q->param('ticket_assigned')); }
			$assigned =~ s/\b$logged_user\b//g;
			if($q->param('ticket_assign_self')) { $assigned .= " " . $logged_user; }
			my $changes = "";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('t')));
			my (@us, $creator);
			while(my @res = $sql->fetchrow_array())
			{
				if($res[2] ne sanitize_html($q->param('ticket_releases'))) { $changes .= $items{"Release"} . "s: \"" . $res[2] . "\" => \"" . sanitize_html($q->param('ticket_releases')) . "\"\n"; }
				if(trim($res[4]) ne trim($assigned)) { $changes .= "Assigned to: " . $res[4] . " => " . $assigned . "\n"; }
				if($res[5] ne sanitize_html($q->param('ticket_title'))) { $changes .= "Title: \"" . $res[5] . "\" => \"" . sanitize_html($q->param('ticket_title')) . "\"\n"; }
				if($res[7] ne $lnk) { $changes .= $cfg->load('custom_name') . ": \"" . $res[7] . "\" => \"" . $lnk . "\"\n"; }
				if($res[8] ne sanitize_alpha($q->param('ticket_status'))) { $changes .= "Status: " . $res[8] . " => " . sanitize_alpha($q->param('ticket_status')) . "\n"; }
				if($res[9] ne $resolution) { $changes .= "Resolution: \"" . $res[9] . "\" => \"" . $resolution . "\"\n"; }			
				@us = split(' ', $res[4]);
				$creator = $res[3];
			}
			$sql = $db->prepare("UPDATE tickets SET link = ?, resolution = ?, status = ?, title = ?, description = ?, assignedto = ?, releaseid = ?, modified = ? WHERE ROWID = ?;");
			$sql->execute($lnk, $resolution, sanitize_alpha($q->param('ticket_status')), sanitize_html($q->param('ticket_title')), sanitize_html($q->param('ticket_desc')) . "\n\n---\nTicket modified by: " . $logged_user . "\n" . $changes, $assigned, sanitize_html($q->param('ticket_releases')), now(), to_int($q->param('t')));
			foreach my $u (@us)
			{
				notify($u, "Ticket (" . to_int($q->param('t')) . ") assigned to you has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes);
			}
			if($creator) { notify($creator, "Your ticket (" . to_int($q->param('t')) . ") has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes); }
			msg("Ticket updated. Press <a href='./?m=tickets'>here</a> to continue.", 3);
			if($q->param("time_spent") && to_float($q->param("time_spent")) != 0)
			{
				$sql = $db->prepare("INSERT INTO timetracking VALUES (?, ?, ?, ?);");
				$sql->execute(to_int($q->param('t')), $logged_user, to_float($q->param("time_spent")), now());
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('ticket_status')) { $text .= "<span class='label label-danger'>Ticket status</span> "; }
			if(!$q->param('ticket_title')) { $text .= "<span class='label label-danger'>Ticket title</span> "; }
			if(!$q->param('ticket_releases')) { $text .= "<span class='label label-danger'>Ticket " . lc($items{"Release"}) . "s</span> "; }
			if(!$q->param('ticket_desc')) { $text .= "<span class='label label-danger'>Ticket description</span> "; }
			if(!$q->param('ticket_resolution')) { $text .= "<span class='label label-danger'>Ticket resolution</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
	}
	elsif($q->param('m') eq "update_comment" && $q->param('c') && $q->param('action'))
	{
		headers("Tickets");
		if($q->param('action') eq "Delete comment" && $logged_lvl > 4)
		{
			$sql = $db->prepare("DELETE FROM comments WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('c')));
			msg("Comment deleted. Press <a href='./?m=tickets'>here</a> to continue.", 3);
		}
		elsif($q->param('comment') && length($q->param('comment')) < 9999)
		{
			$sql = $db->prepare("UPDATE comments SET comment = ?, modified = ? WHERE ROWID = ? AND name = ?;");
			$sql->execute(sanitize_html($q->param('comment')), now(), to_int($q->param('c')), $logged_user);
			msg("Comment updated. Press <a href='./?m=tickets'>here</a> to continue.", 3);
		}
		else
		{
			msg("Comment missing or too long. Please go back and try again.", 0);		
		}
	}
	elsif($q->param('m') eq "add_comment" && $logged_lvl > 0 && $q->param('t'))
	{
		headers("Tickets");	
		if($q->param('comment') && length($q->param('comment')) < 9999)
		{
			my $filedata = "";
			my $filename = "";
			if($q->param('attach_file') && $cfg->load('upload_folder'))
			{
				eval
				{
					my $lightweight_fh = $q->upload('attach_file');
					if(defined $lightweight_fh)
					{
						my $tmpfilename = $q->tmpFileName($lightweight_fh);
						my $file_size = (-s $tmpfilename);
						if($file_size > 99000)
						{
							msg("File size is too large. Please go back and try again.", 0);
							footers();
							exit(0);
						}
						else
						{
							my $io_handle = $lightweight_fh->handle;
							binmode($io_handle);
							my ($buffer, $bytesread);
							$filedata = Data::GUID->new;
							$filename = substr(sanitize_html($q->param('attach_file')), 0, 40);
							open(my $OUTFILE, ">" . $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
							while($bytesread = $io_handle->read($buffer,1024))
							{
								print $OUTFILE $buffer;
							}
						}
					}
				};
				if($@)
				{
					msg("File uploading to <b>" . $cfg->load('upload_folder') . $cfg->sep . $filedata . "</b> failed.", 1); 
					footers();
					exit(0);
				}
			}
			$sql = $db->prepare("INSERT INTO comments VALUES (?, ?, ?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('t')), $logged_user, sanitize_html($q->param('comment')), now(), "Never", $filedata, $filename);
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('t')));
			while(my @res = $sql->fetchrow_array())
			{
				my @us = split(' ', $res[4]);
				foreach my $u (@us)
				{
					notify($u, "New comment to ticket (" . $res[0] . ") assigned to you", "A new comment was posted to a ticket assigned to you:\n\nUser: " . $logged_user . "\nComment: " . $q->param('comment') . "\nAttachment: " . $filename);
				}
				notify($res[3], "New comment posted to your ticket (" . $res[0] . ")", "A new comment was posted to your ticket:\n\nUser: " . $logged_user . "\nComment: " . $q->param('comment') . "\nAttachment: " . $filename);
			}			
			msg("Comment added. Press <a href='./?m=tickets'>here</a> to continue.", 3);
		}
		else
		{
			msg("Comment must be more than 1 and less than 10,000 characters. Please go back and try again.", 0);
		}
	}
	elsif($q->param('m') eq "follow_ticket" && $q->param('t') && $logged_user ne "")
	{
		headers("Tickets");
		$sql = $db->prepare("UPDATE tickets SET subscribers = subscribers || ? WHERE ROWID = ?");
		$sql->execute(" " . $logged_user, to_int($q->param('t')));
		msg("Added you as a follower. Press <a href='./?m=tickets'>here</a> to continue.", 3);
	}
	elsif($q->param('m') eq "unfollow_ticket" && $q->param('t') && $logged_user ne "")
	{
		headers("Tickets");
		my $subs = "";
		$sql = $db->prepare("SELECT subscribers FROM tickets WHERE ROWID = ?");
		$sql->execute(to_int($q->param('t')));
		while(my @res = $sql->fetchrow_array()) { $subs = $res[0]; }
		$subs =~ s/\b$logged_user\b//g;
		$sql = $db->prepare("UPDATE tickets SET subscribers = ? WHERE ROWID = ?");
		$sql->execute($subs, to_int($q->param('t')));
		msg("Removed you as a follower. Press <a href='./?m=tickets'>here</a> to continue.", 3);
	}
	elsif($q->param('m') eq "view_ticket" && $q->param('t'))
	{
		headers("Tickets");
		$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('t')));
		while(my @res = $sql->fetchrow_array())
		{
			if(($cfg->load('default_vis') eq "Restricted" && $logged_lvl > 1) || ($cfg->load('default_vis') eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $cfg->load('default_vis') eq "Public")
			{
				$sql = $db->prepare("SELECT ROWID,* FROM products WHERE ROWID = ?;");
				$sql->execute(to_int($res[1]));
				my $product = "";
				while(my @res2 = $sql->fetchrow_array()) { $product = $res2[1]; }
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Ticket " . to_int($q->param('t')) . "</h3></div><div class='panel-body'><form method='POST' action='.'><input type='hidden' name='m' value='update_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'>\n";
				print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . ": <b>" . $product . "</b></div><div class='col-sm-6'>" . $items{"Release"} . "s: ";
				if($logged_lvl > 2) { print "<input type='text' style='width:200px' name='ticket_releases' value='" . $res[2] . "'>"; }
				else { print "<b>" . $res[2] . "</b>"; }
				print "</div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-6'>Created by: <b>" . $res[3] . "</b></div><div class='col-sm-6'>Created on: <b>" . $res[11] . "</b></div></div></p>\n";
				print "<p><div class='row'><input type='hidden' name='ticket_assigned' value='" . $res[4] . "'><div class='col-sm-6'>Assigned to: <b>" . $res[4] . "</b>";
				if($logged_lvl > 2)
				{ 
					print " <input type='checkbox' name='ticket_assign_self'";
					if($res[4] =~ /\b\Q$logged_user\E\b/) { print " checked"; }
					print "><i> Assign yourself</i>"; 
				}
				print "</div><div class='col-sm-6'>Modified on: <b>" . $res[12] . "</b></div></div></p>\n";
				if($logged_lvl > 2) 
				{
					print "<p><div class='row'><div class='col-sm-6'>Status: <select name='ticket_status'><option";
					if($res[8] eq "New") { print " selected"; }
					print ">New</option><option";
					if($res[8] eq "Open") { print " selected"; }
					print ">Open</option><option";
					if($res[8] eq "Invalid") { print " selected"; }
					print ">Invalid</option><option";
					if($res[8] eq "Hold") { print " selected"; }
					print ">Hold</option><option";
					if($res[8] eq "Resolved") { print " selected"; }
					print ">Resolved</option><option";
					if($res[8] eq "Closed") { print " selected"; }
					print ">Closed</option></select></div><div class='col-sm-6'>Resolution: <input type='text' name='ticket_resolution' style='width:200px' value='" . $res[9] . "'></div></div></p>\n"; 
				}
				else {print "<p><div class='row'><div class='col-sm-6'>Status: <b>" . $res[8] . "</b></div><div class='col-sm-6'>Resolution: <b>" . $res[9] . "</b></div></div></p>\n"; }
				if($logged_lvl > 2) { print "<p><div class='row'><div class='col-sm-6'>Title: <input type='text' style='width:60%' name='ticket_title' value='" . $res[5] . "'></div>"; }
				else { print "<p><div class='row'><div class='col-sm-6'>Title: <b>" . $res[5] . "</b></div>"; }
				if($logged_lvl > 2)	{ print "<div class='col-sm-6'>" . $cfg->load('custom_name') . ": <input type='text' style='width:60%' name='ticket_link' value='" . $res[7] . "'></div></div></p>\n"; }
				else
				{
					if($cfg->load('custom_type') eq "Link") { print "<div class='col-sm-6'>" . $cfg->load('custom_name') . ": <a href='" . $res[7] . "'><b>" . $res[7] . "</b></a></div></div></p>\n"; }
					else { print "<div class='col-sm-6'>" . $cfg->load('custom_name') . ": <b>" . $res[7] . "</b></div></div></p>\n"; }
				
				}
				if($logged_lvl > 2) { print "<p>Description:<br><textarea name='ticket_desc' rows='20' style='width:95%'>" . $res[6] . "</textarea></p>\n"; }
				else { print "<p>Description:<br><pre>" . $res[6] . "</pre></p>\n"; }
				if($logged_lvl > 2) { print "<p>Time spent (in <b>hours</b>): <input type='text' name='time_spent' value='0'><input class='btn btn-default pull-right' type='submit' value='Update ticket'></p>\n"; }
				print "</form>";
				if($logged_user ne "")
				{
					if($res[10] =~ /\b\Q$logged_user\E\b/) { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='unfollow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-default' type='submit' value='Unfollow ticket'></form>"; }
					else { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='follow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-default' type='submit' value='Follow ticket'></form>"; }
				}
				print "</div></div>\n";
				if($logged_lvl > 2)
				{
					$sql = $db->prepare("SELECT * FROM timetracking WHERE ticketid = ? ORDER BY ROWID DESC;");
					$sql->execute(to_int($q->param('t')));
					print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Time breakdown</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>User</th><th>Hours spent</th><th>Date</th></tr>\n";
					my $totaltime = 0;
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>\n";
						$totaltime += to_float($res[2]);
					}
					print "<tr><td><b>Total</b></td><td><b>" . $totaltime . "</b></td><td></td></tr>\n";
					print "</table></div></div>\n";
				}
				print "<h3>Comments</h3>";
				if($logged_lvl > 0 && $res[8] ne "Closed")
				{
					print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Add comment</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='add_comment'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'>\n";
					print "<p><textarea rows='4' name='comment' style='width:95%'></textarea></p>";
					print "<p>Attach file: <input type='file' name='attach_file'><input class='btn btn-default pull-right' type='submit' value='Add comment'></p>\n";
					print "</form></div></div>\n";
				}
				$sql = $db->prepare("SELECT ROWID,* FROM comments WHERE ticketid = ? ORDER BY ROWID DESC;");
				$sql->execute(to_int($q->param('t')));
				while(my @res = $sql->fetchrow_array())
				{
					if($res[5] eq "" || $res[5] eq "Never")
					{ print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'><i>" . $res[4] . "</i></span>" . $res[2] . "</h3></div><div class='panel-body'>"; }
					else
					{ print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'><i>" . $res[4] . "</i> (Edited: <i>" . $res[5] . "</i>)</span>" . $res[2] . "</h3></div><div class='panel-body'>"; }
					print "<form method='POST' action='.'><input type='hidden' name='m' value='update_comment'><input type='hidden' name='c' value='" . $res[0] . "'>\n";
					if($logged_user eq $res[2]) { print "<p><textarea name='comment' rows='5' style='width:95%'>" . $res[3] . "</textarea></p>"; }
					else { print "<p><pre>" . $res[3] . "</pre></p>"; }
					if($res[6] ne "" && $res[7] ne "") { print "<p>Attached file: <a href='./?file=" . $res[6] . "'>" . $res[7] . "</a></p>\n"; }
					print "<p><span class='pull-right'>";
					if($logged_user eq $res[2]) { print "<input class='btn btn-default' type='submit' name='action' value='Update comment'> \n"; }
					if($logged_lvl > 4) { print "<input class='btn btn-default' type='submit' name='action' value='Delete comment'>\n"; }
					print "</span></p></form></div></div>\n";
				}
			}
		}
	}
	elsif($q->param('m') eq "add_ticket" && $logged_lvl > 0 && $q->param('product_id'))
	{
		headers("Tickets");
		if($q->param('ticket_title') && $q->param('ticket_desc') && $q->param('release_id'))
		{
			if(length($q->param('ticket_title')) > 99 || length($q->param('ticket_desc')) > 9999)
			{
				msg("Ticket title must be less than 100 characters, description less than 10,000 characters. Please go back and try again.", 0);
			}
			else
			{
				my $lnk = "";
				if($q->param('ticket_link')) { $lnk = sanitize_html($q->param('ticket_link')); }
				if($cfg->load('custom_type') eq "Checkbox")
				{
					if($lnk eq "on") { $lnk = "Yes"; }
					else { $lnk = "No"; }
				}
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), $logged_user, "", sanitize_html($q->param('ticket_title')), sanitize_html($q->param('ticket_desc')), $lnk, "New", "", "", now(), "Never");
				$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array())
				{
					notify($res[1], "New ticket created", "A new ticket was created for one of your products:\n\nUser: " . $logged_user . "\nTitle: " . sanitize_html($q->param('ticket_title')) . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nDescription: " . $q->param('ticket_desc'));
				}
				msg("Ticket successfully added. Press <a href='./?m=tickets'>here</a> to continue.", 3);
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('ticket_title')) { $text .= "<span class='label label-danger'>Ticket title</span> "; }
			if(!$q->param('ticket_desc')) { $text .= "<span class='label label-danger'>Ticket description</span> "; }
			if(!$q->param('release_id')) { $text .= "<span class='label label-danger'>" . $items{"Release"} . "</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
	}
	elsif($q->param('m') eq "new_ticket" && $logged_lvl > 0 && $q->param('product_id'))
	{
		headers("Tickets");
		$sql = $db->prepare("SELECT ROWID,* FROM products WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('product_id')));
		my $product = "";
		while(my @res = $sql->fetchrow_array()) { $product = $res[1]; }
		if($product ne "")
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Create a new ticket</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'>\n";
			print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <b>" . $product . "</b><input type='hidden' name='product_id' value='" . to_int($q->param('product_id')) . "'></div><div class='col-sm-6'>" . $items{"Release"} . ": <select name='release_id'>";
			$sql = $db->prepare("SELECT ROWID,* FROM releases WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array()) { print "<option>" . $res[3] . "</option>"; }
			print "</select></div></div></p>\n";
			print "<p>Ticket title: <input type='text' name='ticket_title' style='width:70%'></p>\n";
			print "<p>Description:<br><textarea name='ticket_desc' rows='5' style='width:95%'></textarea></p>\n";
			if($cfg->load('custom_type') eq "Checkbox") { print $cfg->load('custom_name') . ": <input type='checkbox' name='ticket_link'>\n"; }
			else { print $cfg->load('custom_name') . ": <input type='text' name='ticket_link' style='width:50%'>\n"; }
			print "<input type='hidden' name='m' value='add_ticket'><input class='btn btn-default pull-right' type='submit' value='Create ticket'></form></div></div>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM products WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Product"} . " information</h3></div><div class='panel-body'>\n";
				print "<div class='row'><div class='col-sm-6'>Product name: <b>" . $res[1] . "</b></div><div class='col-sm-6'>" . $items{"Model"} . ": <b>" . $res[2] . "</b></div></div>\n";
				print "<div class='row'><div class='col-sm-6'>Created on: <b>" . $res[6] . "</b></div><div class='col-sm-6'>Last modified on: <b>" . $res[7] . "</b></div></div>\n";
				print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <b>" . $res[5] . "</b></div></div>\n";
				print "Description:<br><pre>" . $res[3] . "</pre>\n";
				if($res[4] ne "") { print "<p><img src='./?file=" . $res[4] . "' style='max-width:95%'></p>\n"; }
				print "</div></div>\n";
			}
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? ORDER BY ROWID DESC LIMIT 50;");
			$sql->execute(to_int($q->param('product_id')));
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets for this " . lc($items{"Product"}) . " (last 50 entries)</h3></div><div class='panel-body'><table class='table table-striped'>\n";
			print "<tr><th>ID</th><th>" . $items{"Release"} . "<th>User</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
			while(my @res = $sql->fetchrow_array())
			{
				if(($cfg->load("default_vis") eq "Public" || ($cfg->load("default_vis") eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $logged_lvl > 1))
				{ print "<tr><td>" . $res[0] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
			}
			print "</table></div></div>\n";
		}
		else
		{
			msg("Product not found. Please go back and try again.", 0);
		}
	}
	elsif($q->param('m') eq "stats" && $q->param('report') && $logged_lvl > 3)
	{
		my %results;
		my $totalresults = 0;
		if($q->param('csv')) { print $q->header(-type => "text/csv", -attachment => "stats.csv"); }
		else { headers("Settings"); }
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		if(to_int($q->param('report')) == 1)
		{
			if($q->param('csv')) { print "User,\"Hours spent\"\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Time spent per user</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>User</th><th>Hours spent</th></tr>"; }
			$sql = $db->prepare("SELECT * FROM timetracking ORDER BY name;");
		}
		elsif(to_int($q->param('report')) == 2)
		{
			if($q->param('csv')) { print "\"Ticket ID\",\"Hours spent\"\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Time spent per ticket</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Ticket ID</th><th>Hours spent</th></tr>"; }
			$sql = $db->prepare("SELECT * FROM timetracking ORDER BY ticketid;");		
		}
		elsif(to_int($q->param('report')) == 3)
		{
			if($q->param('csv')) { print $items{"Product"} . ",Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets created per " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>" . $items{"Product"} . "</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT productid FROM tickets ORDER BY productid;");
		}
		elsif(to_int($q->param('report')) == 4)
		{
			if($q->param('csv')) { print "User,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets created per user</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>User</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT createdby FROM tickets ORDER BY createdby;");
		}
		elsif(to_int($q->param('report')) == 5)
		{
			if($q->param('csv')) { print "Day,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets created per day</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Day</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT created,ROWID FROM tickets ORDER BY ROWID;");
		}
		elsif(to_int($q->param('report')) == 6)
		{
			if($q->param('csv')) { print "Month,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets created per month</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Month</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT created,ROWID FROM tickets ORDER BY ROWID;");
		}
		elsif(to_int($q->param('report')) == 7)
		{
			if($q->param('csv')) { print "Status,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets per status</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Status</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT status FROM tickets ORDER BY status;");
		}
		elsif(to_int($q->param('report')) == 8)
		{
			if($q->param('csv')) { print "\"Access level\",Users\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Users per access level</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Access level</th><th>Users</th></tr>"; }
			$sql = $db->prepare("SELECT level FROM users ORDER BY level;");
		}
		else
		{
			if($q->param('csv')) { print "Unknown,Unknown\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Unknown report</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Unknown</th><th>Unknown</th></tr>"; }
			$sql = $db->prepare("SELECT ROWID FROM users;");
		}
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if(to_int($q->param('report')) == 1)
			{
				if(!$results{$res[1]}) { $results{$res[1]} = 0; }
				$results{$res[1]} += to_float($res[2]);
			}
			elsif(to_int($q->param('report')) == 2)
			{
				if(!$results{$res[0]}) { $results{$res[0]} = 0; }
				$results{$res[0]} += to_float($res[2]);
			}
			elsif(to_int($q->param('report')) == 3)
			{
				if(!$results{$products[to_int($res[0])]}) { $results{$products[to_int($res[0])]} = 0; }
				$results{$products[to_int($res[0])]} ++;
			}
			elsif(to_int($q->param('report')) == 4 || to_int($q->param('report')) == 7 || to_int($q->param('report')) == 8)
			{
				if(!$results{$res[0]}) { $results{$res[0]} = 0; }
				$results{$res[0]} ++;
			}
			elsif(to_int($q->param('report')) == 5)
			{
				my ($weekday, $month, $day, $hms, $year) = split(' ', $res[0]);
				my $r = $month . " " . $day . ", " . $year;
				if(!$results{$r}) { $results{$r} = 0; }
				$results{$r} ++;
			}
			elsif(to_int($q->param('report')) == 6)
			{
				my ($weekday, $month, $day, $hms, $year) = split(' ', $res[0]);
				my $r = $month . " " . $year;
				if(!$results{$r}) { $results{$r} = 0; }
				$results{$r} ++;
			}
		}
		while(my ($k, $v) = each(%results))
		{
			if($q->param('csv')) { print "\"" . $k . "\"," . $v . "\n"; }
			else { print "<tr><td>" . $k . "</td><td>" . $v . "</td></tr>"; }
			$totalresults += to_float($v);
		}
		if($q->param('csv'))
		{
			print "Total," . $totalresults . "\n";
			exit(0); 
		}
		else 
		{
			print "<tr><td><b>Total</b></td><td><b>" . $totalresults . "</b></td></tr>";
			print "</table></div></div>"; 
		}
	}
	elsif($q->param('m') eq "tickets")
	{
		my $limit = 1000;
		if($q->param('filter_limit')) { $limit = to_int($q->param('filter_limit')); }
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		if($q->param('csv'))
		{
			print $q->header(-type => "text/csv", -attachment => "tickets.csv");
			print "ID," . $items{"Product"} . ",User,Title,Description,\"" . $cfg->load('custom_name') . "\",Status,Resolution,Created,Modified\n";
			if($q->param('filter_status') && $q->param('filter_status') ne "All" && $q->param('filter_product') && $q->param('filter_product') ne "All")
			{
				$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status = ? AND productid = ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
				$sql->execute(sanitize_alpha($q->param('filter_status')), to_int($q->param('filter_product')));
			}
			elsif($q->param('filter_status') && $q->param('filter_status') ne "All")
			{
				$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status = ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
				$sql->execute(sanitize_alpha($q->param('filter_status')));
			}
			elsif($q->param('filter_product') && $q->param('filter_product') ne "All")
			{
				$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
				$sql->execute(to_int($q->param('filter_product')));
			}
			else
			{
				$sql = $db->prepare("SELECT ROWID,* FROM tickets ORDER BY ROWID DESC LIMIT " . $limit . ";");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array())
			{
				if($products[$res[1]] && (($cfg->load("default_vis") eq "Public" || ($cfg->load("default_vis") eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $logged_lvl > 1)))
				{
					my $desc = $res[6];
					$desc =~ s/&lt;/</g;
					$desc =~ s/&quot;/""/g;
					print "\"" . $res[0] . "\",\"" . $products[$res[1]] . "\",\"" . $res[3] . "\",\"" . $res[5] . "\",\"" . $desc . "\",\"" . $res[7] . "\",\"" . $res[8] . "\",\"" . $res[9] . "\",\"" . $res[11] . "\",\"" . $res[12] . "\"\n"; 
				}
			}
			exit(0);
		}
		headers("Tickets");
		if($logged_lvl > 0)  # add new ticket pane
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Create a new ticket</h3></div><div class='panel-body'><form method='POST' action='.'>\n";
			print "<p>Select a " . lc($items{"Product"}) . " name: <select name='product_id'>";
			$sql = $db->prepare("SELECT ROWID,* FROM products WHERE vis != 'Archived';");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($logged_lvl > 1 || $res[5] ne "Restricted") { print "<option value=" . $res[0] . ">" . $res[1] . "</option>"; }
			}
			print "</select></p><input type='hidden' name='m' value='new_ticket'><input class='btn btn-default pull-right' type='submit' value='Next'></form></div></div>\n";
		}
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets ";
		if($q->param('filter_product')) { print "(" . $items{"Product"} . ": " . sanitize_alpha($q->param('filter_product')) . ") "; }
		if($q->param('filter_status')) { print "(Status: " . sanitize_alpha($q->param('filter_status')) . ") "; }
		print "(Limit: " . $limit . ") ";
		print "</h3></div><div class='panel-body'>\n";
		print "<p><form method='GET' action='.'><input type='hidden' name='m' value='tickets'>Filter tickets: By status: <select name='filter_status'><option>All</option><option>New</option><option>Open</option><option>Invalid</option><option>Hold</option><option>Resolved</option><option>Closed</option></select> By " . lc($items{"Product"}) . ": <select name='filter_product'><option>All</option>";
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { print "<option value=" . $res[0] . ">" . $res[1] . "</option>"; }
		print "</select> Limit: <select name='filter_limit'><option value='50000'>50,000</option><option value='10000'>10,000</option><option value='5000'>5,000</option><option value='1000' selected>1,000</option><option value='500'>500</option><option value='100'>100</option></select><span class='pull-right'><input class='btn btn-default' type='submit' value='Filter'> <input class='btn btn-default' name='csv' type='submit' value='Export as CSV'></span></form></p>";
		my $search = "";
		if($q->param('search')) { $search = sanitize_html($q->param('search')); }
		print "<p><form method='GET' action='.'><input type='hidden' name='m' value='tickets'>Custom search: <input type='text' name='search' value='" . $search . "' style='width:300px'> <input class='btn btn-default' type='submit' value='Search'></p>";
		print "<table class='table table-striped'><tr><th>ID</th><th>" . $items{"Product"} . "</th><th>User</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
		if($q->param('filter_status') && $q->param('filter_status') ne "All" && $q->param('filter_product') && $q->param('filter_product') ne "All")
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status = ? AND productid = ? ORDER BY ROWID DESC LIMIT 1000;");
			$sql->execute(sanitize_alpha($q->param('filter_status')), to_int($q->param('filter_product')));
		}
		elsif($q->param('filter_status') && $q->param('filter_status') ne "All")
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status = ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
			$sql->execute(sanitize_alpha($q->param('filter_status')));
		}
		elsif($q->param('filter_product') && $q->param('filter_product') ne "All")
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
			$sql->execute(to_int($q->param('filter_product')));
		}
		elsif($q->param('search'))
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE title LIKE ? OR description LIKE ? ORDER BY ROWID DESC LIMIT " . $limit . ";");
			$sql->execute("%" . sanitize_html($q->param('search')) . "%", "%" . sanitize_html($q->param('search')) . "%");
		}
		else
		{
			$sql = $db->prepare("SELECT ROWID,* FROM tickets ORDER BY ROWID DESC LIMIT " . $limit . ";");
			$sql->execute();
		}
		while(my @res = $sql->fetchrow_array())
		{
			if($products[$res[1]] && (($cfg->load("default_vis") eq "Public" || ($cfg->load("default_vis") eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $logged_lvl > 1)))
			{ print "<tr><td>" . $res[0] . "</td><td>" . $products[$res[1]] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
		}
		print "</table></div></div>\n";
	}
	else
	{
		headers("Error");
		msg("Unknown module or access denied.", 0);
	}
	footers();
}
elsif($q->param('new_name') && $q->param('new_pass1') && $q->param('new_pass2') && ($logged_lvl > 4 || $cfg->load('allow_registrations'))) # Process registration
{
	headers("Registration");
	if($q->param('new_pass1') ne $q->param('new_pass2'))
	{
		msg("Passwords do not match. Please go back and try again.", 0);
	}
	elsif(lc(sanitize_alpha($q->param('new_name'))) eq lc($cfg->load('admin_name')) || lc(sanitize_alpha($q->param('new_name'))) eq "guest" || lc(sanitize_alpha($q->param('new_name'))) eq "api")
	{
		msg("This user name is reserved. Please go back and try again.", 0);
	}
	elsif(length(sanitize_alpha($q->param('new_name'))) < 3 || length(sanitize_alpha($q->param('new_name'))) > 16 || ($q->param('new_email') && length(sanitize_alpha($q->param('new_email'))) > 36) || length($q->param('new_pass1')) < 6)
	{
		msg("User names should be between 3 and 16 characters, passwords should be at least 6 characters. Please go back and try again.", 0);    
	}
	else
	{
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		my $found;
		while(my @res = $sql->fetchrow_array())
		{
			if(lc($res[0]) eq lc(sanitize_alpha($q->param('new_name')))) { $found = 1; }
		}
		if(!$found)
		{
			my $confirm = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..16;
			$sql = $db->prepare("INSERT INTO users VALUES(?, ?, ?, ?, ?, ?);");
			if($q->param('new_email')) { $sql->execute(sanitize_alpha($q->param('new_name')), sha1_hex($q->param('new_pass1')), sanitize_email($q->param('new_email')), to_int($cfg->load('default_lvl')), "Never", $confirm); }
			else { $sql->execute(sanitize_alpha($q->param('new_name')), sha1_hex($q->param('new_pass1')), "", to_int($cfg->load('default_lvl')), "Never", $confirm); }
			if($logged_user eq "") { msg("User <b>" . sanitize_alpha($q->param('new_name')) . "</b> added. Press <a href='.'>here</a> to go to the login page.", 3); }
			else { msg("User <b>" . sanitize_alpha($q->param('new_name')) . "</b> added. Press <a href='./?m=settings'>here</a> to continue.", 3); }
			logevent("Add new user: " . sanitize_alpha($q->param('new_name')));
			notify(sanitize_alpha($q->param('new_name')), "Email confirmation", "Please confirm your email by logging into the NodePoint interface, and entering the following confirmation code under Settings: " . $confirm);
		}
		else
		{
			msg("User already exists. Please go back and try again.", 0);	    
		}
	}
	footers();
}
elsif($q->param('name') && $q->param('pass')) # Process login
{
	check_user($q->param('name'), sha1_hex($q->param('pass')));
	if($logged_user ne "")
	{
		headers("Home");
		if($last_login) { msg("Logged in successfully. Your last login was on " . $last_login . ".", 3); }
		else { msg("Logged in successfully.", 3); }
		logevent("Successful login");
		home();
	}
	else
	{
		headers("Login");
		msg("Invalid login credentials.", 0);
		logevent("Failed login");
		login();
	}
	footers();
}
else # main page
{
	if($logged_user ne "")
	{
		headers("Home");
		home();
	}
	else
	{
		headers("Login");
		login();
	}
	footers();
}

if($db)
{
	if($sql) { $sql->finish(); }
	$db->disconnect;
}
