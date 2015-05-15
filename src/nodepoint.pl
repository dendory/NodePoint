#!/usr/bin/perl -w
#
# NodePoint - (C) 2015 Patrick Lambert - http://nodepoint.ca
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
use Net::LDAP;
use Crypt::RC4;
use MIME::Base64;
use Time::HiRes qw(time);
use Time::Piece;

my ($cfg, $db, $sql, $cn, $cp, $cgs, $last_login, $perf);
my $logged_user = "";
my $logged_lvl = -1;
my $q = new CGI;
my $VERSION = "1.2.0";
my %items = ("Product", "Product", "Release", "Release", "Model", "SKU/Model");
my @itemtypes = ("None");

$perf = time/100;
$perf = int(($perf - int($perf)) * 100000);

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
	if($logged_lvl > 5 && $cfg->load('comp_tickets') ne "on" && $cfg->load('comp_articles') ne "on" && $cfg->load('comp_time') ne "on") { msg("All components are turned off. Enable the ones you need in Settings.", 1); }
}

# Footers
sub footers
{
	my $perf2 = time/100;
	$perf2 = int(($perf2 - int($perf2)) * 100000); # Store 2.3 digits of current unixtime, to avoid overloading a 32bits int
	my $perf3 = $perf2 - $perf;
	if($perf3 < 0) { $perf3 = ($perf2 + 100000) - $perf; }
	print "  <div style='clear:both'></div><hr><div style='margin-top:-15px;font-size:9px;color:grey'><span class='pull-right'>" . $perf3 . " ms</span><i>NodePoint v" . $VERSION . "</i></div></div>\n";
	print " <script src='jquery.js'></script>\n";
	print " <script src='bootstrap.js'></script>\n";
	print " <script src='validator.js'></script>\n";
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
		if($q->param('m') && $q->param('m') eq "products")
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
		}
		elsif($q->param('m') && $q->param('m') eq "tickets")
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li class='active'><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
		}
		elsif($q->param('kb') || ($q->param('m') && $q->param('m') eq "articles"))
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li class='active'><a href='./?m=articles'>Articles</a></li>\n"; }
		}
		elsif($q->param('m') && $q->param('m') eq "items")
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
		}
		else
		{
			print "	 <li class='active'><a href='.'>Login</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
		}	    
	}
	else
	{
		if($q->param('m') && ($q->param('m') eq "tickets" || $q->param('m') eq "new_ticket" || $q->param('m') eq "follow_ticket" || $q->param('m') eq "unfollow_ticket" || $q->param('m') eq "update_comment" || $q->param('m') eq "add_comment" || $q->param('m') eq "add_ticket" || $q->param('m') eq "view_ticket" || $q->param('m') eq "update_ticket"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li class='active'><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "products" || $q->param('m') eq "add_product" ||$q->param('m') eq "view_product" || $q->param('m') eq "edit_product" || $q->param('m') eq "add_release" || $q->param('m') eq "delete_release"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "settings" || $q->param('m') eq "confirm_delete" || $q->param('m') eq "clear_log" || $q->param('m') eq "stats" || $q->param('m') eq "change_lvl" || $q->param('m') eq "confirm_email" || $q->param('m') eq "reset_pass" || $q->param('m') eq "logout") || $q->param('create_form') || $q->param('edit_form') || $q->param('save_form'))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li class='active'><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('kb') || $q->param('m') && ($q->param('m') eq "articles" || $q->param('m') eq "add_article" || $q->param('m') eq "save_article" || $q->param('m') eq "link_article" || $q->param('m') eq "unlink_article"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li class='active'><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "items" || $q->param('m') eq "checkout" || $q->param('m') eq "checkin" || $q->param('m') eq "save_item" || $q->param('m') eq "create_item" || $q->param('m') eq "edit_item"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		else
		{
			print "	 <li class='active'><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			print "	 <li><a href='./?m=settings'>Settings</a></li>\n";
		}
		if($cfg->load('comp_tickets') eq "on") 
		{ 
			print "   <form class='navbar-form navbar-right' method='GET' action='./'>";
			print "    <div class='form-group'>";
			print "     <input type='number' placeholder='Ticket ID' style='-moz-appearance:textfield;-webkit-appearance:none;' name='t' class='form-control'><input type='hidden' name='m' value='view_ticket'>";
			print "    </div>";
			print "    <button type='submit' class='btn btn-primary'>Open</button>";
			print "   </form>";
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

# Compares 'month day, year' strings 
sub by_date
{
    my ($ta, $tb) = map Time::Piece->strptime($_, '%b %d, %Y'), $a, $b;
    $ta <=> $tb;
}

# Compares 'month year' strings 
sub by_month
{
    my ($ta, $tb) = map Time::Piece->strptime($_, '%b %Y'), $a, $b;
    $ta <=> $tb;
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
	print "<center><div class='row'>";
	if(!$cfg->load('allow_registrations') || $cfg->load('allow_registrations') eq 'off' || $cfg->load('ad_server'))
	{
		print "<div class='col-sm-3'>&nbsp;</div>\n";
	}
	print "<div class='col-sm-6'>\n";
	print "<h3>Login</h3><form data-toggle='validator' role='form' method='POST' action='.'><div class='form-group'>\n";
	if($cfg->load('ad_server') && $cfg->load('ad_domain')) { print "<p>Enter your " . $cfg->load('ad_domain') . " credentials.</p>"; }
	print "<p><input type='text' name='name' placeholder='User name' class='form-control' data-error='User name must be between 2 and 50 characters.' data-minlength='2' maxlength='50' required></p>\n";
	print "<p><input type='password' name='pass' placeholder='Password' class='form-control' required></p>\n";
	print "<div class='help-block with-errors'></div></div>";
	print "<p><input class='btn btn-primary' type='submit' value='Login'></p></form>\n";
	if($cfg->load('allow_registrations') && $cfg->load('allow_registrations') ne 'off' && !$cfg->load('ad_server'))
	{
		print "</div><div class='col-sm-6'><h3>Register a new account</h3><form data-toggle='validator' role='form' method='POST' action='.'><div class='form-group'>\n";
		print "<p><input type='text' name='new_name' placeholder='User name' class='form-control' data-error='User name must be between 2 and 50 letters or numbers.' data-minlength='2' maxlength='50' required></p>\n";
		print "<p><input type='password' name='new_pass1' placeholder='Password' data-minlength='6' class='form-control' id='new_pass1' required></p>\n";
		print "<p><input type='password' name='new_pass2' class='form-control' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm' required></p>\n";
		print "<p><input type='email' name='new_email' placeholder='Email (optional)' class='form-control' data-error='Must be a valid email.' maxlength='99'></p>\n";
		print "<div class='help-block with-errors'></div></div>";
		print "<p><input class='btn btn-primary' type='submit' value='Register'></p></form>\n";
	}
	print "</div></div></center>\n";
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
		$text =~ s/[^A-Za-z0-9\.\-\_]//g;
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
	$sql = $db->prepare("SELECT * FROM autoassign WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE autoassign (productid INT, user TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM forms WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE forms (productid INT, formname TEXT, field0 TEXT, field0type INT, field1 TEXT, field1type INT, field2 TEXT, field2type INT, field3 TEXT, field3type INT, field4 TEXT, field4type INT, field5 TEXT, field5type INT, field6 TEXT, field6type INT, field7 TEXT, field7type INT, field8 TEXT, field8type INT, field9 TEXT, field9type INT, modified TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM kb WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE kb (productid INT, title TEXT, article TEXT, published INT, createdby TEXT, created TEXT, modified TEXT);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO kb VALUES (0, 'Using articles', 'Support articles are meant to help users understand the items managed by NodePoint. They are linked to one or all " . lc($items{"Product"}) . "s, and appear on the relevant " . lc($items{"Product"}) . " pages. Draft articles are only shown to users with access level 4 or above, and only those users can create new articles. Articles can then be used as part of ticket resolutions.', 0, 'api', ?, 'Never');");
		$sql->execute(now());
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM kblink WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE kblink (ticketid INT, kb INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM escalate WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE escalate (ticketid INT, user TEXT);");
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
		$sql->execute($q->remote_addr, $logged_user, $op, now(), int(time));
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
	$cfg->save("upload_lvl", to_int($q->param('upload_lvl')));
	$cfg->save("allow_registrations", $q->param('allow_registrations'));    
	$cfg->save("smtp_server", $q->param('smtp_server'));    
	$cfg->save("smtp_port", $q->param('smtp_port'));    
	$cfg->save("smtp_from", $q->param('smtp_from'));
	$cfg->save("smtp_user", $q->param('smtp_user'));    
	$cfg->save("smtp_pass", $q->param('smtp_pass'));    
	$cfg->save("api_read", $q->param('api_read'));
	$cfg->save("api_write", $q->param('api_write'));
	$cfg->save("api_imp", $q->param('api_imp'));
	$cfg->save("upload_folder", $q->param('upload_folder'));
	$cfg->save("items_managed", $q->param('items_managed'));
	$cfg->save("custom_name", $q->param('custom_name'));
	$cfg->save("custom_type", $q->param('custom_type'));
	$cfg->save("ext_plugin", $q->param('ext_plugin'));
	$cfg->save("ad_server", $q->param('ad_server'));
	$cfg->save("ad_domain", $q->param('ad_domain'));
	$cfg->save("comp_tickets", $q->param('comp_tickets'));
	$cfg->save("comp_articles", $q->param('comp_articles'));
	$cfg->save("comp_time", $q->param('comp_time'));
}

# Check login credentials
sub check_user
{
	my ($n, $p) = @_;
	if(sha1_hex($p) eq $cfg->load("admin_pass") && $n eq $cfg->load("admin_name"))
	{
		$logged_user = $cfg->load("admin_name");
		$logged_lvl = 6;
		$cn = $q->cookie(-name => "np_name", -value => $logged_user);
		$cp = $q->cookie(-name => "np_key", -value => encode_base64(RC4($cfg->load("api_read"), $p), ""));
	}
	else
	{
		if($cfg->load("ad_domain") && $cfg->load("ad_server"))
		{
			eval
			{
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or do
				{
					logevent("LDAP: Could not connect to Active Directory server");
					return;
				};
				my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $n, password=>$p);
				if($mesg->code)
				{
					 logevent("LDAP: " . $mesg->error);
					 return;
				}
				$logged_user = $n;
				$logged_lvl = $cfg->load("default_lvl");
				$cn = $q->cookie(-name => "np_name", -value => $logged_user);
				$cp = $q->cookie(-name => "np_key", -value => encode_base64(RC4($cfg->load("api_read"), $p), ""));
				$sql = $db->prepare("SELECT * FROM users WHERE name = ?;");
				$sql->execute($n);
				my $found = 0;
				while(my @res = $sql->fetchrow_array())
				{ 
					$found = 1;
					$logged_lvl = to_int($res[3]);
					$last_login = $res[4];
				}
				if(!$found)
				{
					$sql = $db->prepare("INSERT INTO users VALUES(?, ?, ?, ?, ?, ?);");
					$sql->execute($n, "*********", "", to_int($cfg->load('default_lvl')), now(), "");
				}
			}; # check silently since headers may not be set			
		}
		else
		{
			eval
			{
				$sql = $db->prepare("SELECT * FROM users;");
				$sql->execute();
				while(my @res = $sql->fetchrow_array())
				{
					if(sha1_hex(rtrim($p)) eq $res[1] && $n eq $res[0])
					{
						$logged_user = $res[0];
						$logged_lvl = to_int($res[3]);
						$last_login = $res[4];
						$sql = $db->prepare("UPDATE users SET loggedin = ? WHERE name = ?;");
						$sql->execute(now(), $res[0]);
						$cn = $q->cookie(-name => "np_name", -value => $logged_user);
						$cp = $q->cookie(-name => "np_key", -value => encode_base64(RC4($cfg->load("api_read"), $p), ""));
						last;
					}
				}
			}; # check silently since headers may not be set
		}
	}
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
	if($cfg->load('ext_plugin'))
	{
		my $cmd = $cfg->load('ext_plugin');
		my $u2 = $u;
		$u2 =~ s/"/''/g;
		my $title2 = $title;
		$title2 =~ s/"/''/g;
		my $mesg2 = $mesg;
		$mesg2 =~ s/"/''/g;		
		$cmd =~ s/\%user\%/\"$u2\"/g;
		$cmd =~ s/\%title\%/\"$title2\"/g;
		$cmd =~ s/\%message\%/\"$mesg2\"/g;
		$cmd =~ s/\n/ /g;
		$cmd =~ s/\r/ /g;
		system($cmd);
	}
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
					my $smtp = Net::SMTP->new($cfg->load('smtp_server'), Port => to_int($cfg->load('smtp_port')), Timeout => 5);
					if($cfg->load('smtp_user') && $cfg->load('smtp_pass')) { $smtp->auth($cfg->load('smtp_user'), $cfg->load('smtp_pass')); }
					$smtp->mail($cfg->load('smtp_from'));
					if($smtp->to($res[2]))
					{
						$smtp->data();
						$smtp->datasend("From: " . $cfg->load('smtp_from') . "\n");
						$smtp->datasend("To: " . $res[2] . "\n");
						$smtp->datasend("Subject: NodePoint - " . $title . "\n\n");
						$smtp->datasend($mesg . "\n\nThis is an automated message from " . $cfg->load('site_name') . ". To disable notifications, log into your account and remove the email under Settings.\n");
						$smtp->datasend();
						$smtp->quit;
					}
					else
					{
						if($logged_user ne "api") { msg("Could not send notification email to " . $u . ", target email was rejected.", 1); }
						logevent("Email notification error: " . $smtp->message());
					}
				} or do {
					if($logged_user ne "api") { msg("Could not send notification email to " . $u . ", connection to SMTP server failed.", 1); }
					logevent("Email notification error: Connection to SMTP server failed.");
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

	if($q->param('delete_notify') && $logged_user ne "")
	{
		$sql = $db->prepare("DELETE FROM escalate WHERE user = ? AND ticketid = ?;");
		$sql->execute($logged_user, to_int($q->param('delete_notify')));
	}

	if($logged_user ne "")
	{
		$sql = $db->prepare("SELECT DISTINCT ticketid FROM escalate WHERE user = ?;");
		$sql->execute($logged_user);
		while(my @res = $sql->fetchrow_array()) { msg("<span class='pull-right'><a href='./?delete_notify=" . $res[0] . "'>Clear</a></span>Ticket <a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[0] . "</a> requires your attention.", 2); }
	}

	if(!$q->cookie('np_gs'))
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Getting started</h3></div><div class='panel-body'>\n";
		print "<p>Use the " . $items{"Product"} . "s tab to browse available " . lc($items{"Product"}) . "s along with their " . lc($items{"Release"}) . "s. You can view basic information about them and see their description. Use the Tickets tab to browse current tickets and comments. The Articles tab contains related support articles. You can also change your email address and password under the Settings tab.</p>\n";
		print "<p>Your current access level is <b>" . $logged_lvl . "</b>. This gives you the following permissions:</p>\n";
		if($logged_lvl > 0) { print "<p>As an <span class='label label-success'>Authorized User</span>, you can add new tickets to specific " . lc($items{"Product"}) . "s and " . lc($items{"Release"}) . "s, or comment on existing ones.</p>\n"; }
		if($logged_lvl > 1) { print "<p>Since you have <span class='label label-success'>Restricted View</span> permission, you can view statistics and view restricted products and tickets, those which may not be visible to normal users.</p>\n"; }
		if($logged_lvl > 2) { print "<p>With <span class='label label-success'>Tickets Management</span> access, you can modify existing tickets entered by other users, such as change the status, add a resolution, or edit title and description. You can assign yourself to tickets, auto-assign to " . lc($items{"Product"}) . "s, and you can also add new " . lc($items{"Release"}) . "s under the " . $items{"Product"} . "s tab.</p>\n"; }
		if($logged_lvl > 3) { print "<p>As a <span class='label label-success'>" . $items{"Product"} . "s Management</span> user, you can add new " . lc($items{"Product"}) . "s, edit existing ones, change their visibility, and edit articles. Archiving a product will prevent users from adding new tickets for it.</p>\n" }
		if($logged_lvl > 4) { print "<p>With the <span class='label label-success'>Users Managemenet</span> access level, you have the ability to edit users under the Settings tab. You can reset passwords and change access levels, along with adding new users. You can also delete comments under the Tickets tab.</p>\n"; }
		if($logged_lvl > 5) { print "<p>Since you are logged in as <span class='label label-success'>NodePoint Administrator</span>, you can edit initial settings under the Settings tab. Note that it is good practice to use a lower access user to do your daily tasks.</p>\n" }
		print "</div></div>\n";
	}

	if($logged_lvl > 0 && $cfg->load('comp_tickets') eq "on")
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
	
	if($cfg->load('comp_tickets') eq "on")
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets you follow</h3></div><div class='panel-body'><table class='table table-striped'>\n";
		print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>User</th><th>Title</th><th>Status</th><th>Date</th></tr>\n";
		$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($products[$res[1]] && $res[10] =~ /\b$logged_user\b/) { print "<tr><td>" . $res[0] . "</td><td>" . $products[$res[1]] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; }
		}
		print "</table></div></div>";
	}
	
	if($logged_lvl > 2 && $cfg->load('comp_tickets') eq "on")
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
if($q->cookie('np_name') && $q->cookie('np_key') && $cfg->load("api_read"))
{
	check_user($q->cookie('np_name'), RC4($cfg->load("api_read"), decode_base64($q->cookie('np_key'))));
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
	elsif($cfg->load("items_managed") eq "Applications with platforms and versions")
	{
		$items{"Product"} = "Application";
		$items{"Model"} = "Platform";
		$items{"Release"} = "Version";
	}
}
	
# Main loop
if($q->param('site_name') && $q->param('db_address') && $logged_user ne "" && $logged_user eq $cfg->load('admin_name')) # Save config by admin
{
	headers("Settings");
	if($q->param('site_name') && $q->param('db_address') && $q->param('admin_name') && $q->param('custom_name') && $q->param('default_lvl') && $q->param('default_vis') && $q->param('api_write') &&  $q->param('api_imp') && $q->param('api_read') && $q->param('comp_tickets') && $q->param('comp_articles') && $q->param('comp_time')) # All required values have been filled out
	{
		# Test database settings
		$db = DBI->connect("dbi:SQLite:dbname=" . $q->param('db_address'), '', '', { RaiseError => 0, PrintError => 0 }) or do { msg("Could not verify database settings. Please hit back and try again.<br><br>" . $DBI::errstr, 0); exit(0); };
		db_check();
		save_config();
		msg("Settings updated. Press <a href='./?m=settings'>here</a> to continue.", 3);
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
		if(!$q->param('api_imp')) { $text .= "<span class='label label-danger'>Allow user impersonation</span> "; }
		if(!$q->param('custom_name')) { $text .= "<span class='label label-danger'>Custom ticket field</span> "; }
		if(!$q->param('comp_tickets')) { $text .= "<span class='label label-danger'>Component: Tickets management</span> "; }
		if(!$q->param('comp_articles')) { $text .= "<span class='label label-danger'>Component: Support articles</span> "; }
		if(!$q->param('comp_time')) { $text .= "<span class='label label-danger'>Component: Time tracking</span> "; }
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
				print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can create users, reset passwords, change access levels</td></tr><tr><td>4</td><td>Products management</td><td>Can add, retire and edit products, edit articles</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create releases, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view statistics, restricted tickets and products</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
				my $key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API read key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_read' value='" . $key . "'></div></div></p>\n";
				$key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API write key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_write' value='" . $key . "'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Allow user impersonation:</div><div class='col-sm-4'><input type='checkbox' name='api_imp'></div></div></p>\n";
				print "<p>API keys can be used by external applications to read and write tickets using the JSON API.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP server:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_server' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP port:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_port' value='25'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP username:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_user' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP password:</div><div class='col-sm-4'><input type='password' style='width:300px' name='smtp_pass' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Support email:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_from' value='admin\@company.com'></div></div></p>\n";
				print "<p>If a SMTP server host name is entered, NodePoint will attempt to send an email when new tickets are created, or changes occur.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>External notifications plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ext_plugin' value=''></div></div></p>\n";
				print "<p>Notifications can be sent to an external system command. Variables accepted are: \%user\%, \%title\% and \%message\%.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin username:</div><div class='col-sm-4'><input type='text' style='width:300px' name='admin_name' value='admin'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin password:</div><div class='col-sm-4'><input style='width:300px' type='password' name='admin_pass'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Public notice:</div><div class='col-sm-4'><input type='text' style='width:300px' name='motd' value='Welcome to NodePoint. Remember to be courteous when writing tickets. Contact the help desk for any problem.'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Upload folder:</div><div class='col-sm-4'><input type='text' style='width:300px' name='upload_folder' value='.." . $cfg->sep . "uploads'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Minimum upload level:</div><div class='col-sm-4'><select name='upload_lvl' style='width:300px'><option value=5>5 - Users management</option><option value=4>4 - Products management</option><option value=3>3 - Tickets management</option><option value=2>2 - Restricted view</option><option value=1 selected=selected>1 - Authorized users</option><option value=0>0 - Unauthorized users</option></select></div></div></p>\n";
				print "<p>The upload folder should be a local folder with write access and is used for product images and comment attachments. If left empty, uploads will be disabled.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Items managed:</div><div class='col-sm-4'><select style='width:300px' name='items_managed'><option selected>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option></select></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Custom ticket field:</div><div class='col-sm-4'><input type='text' style='width:300px' name='custom_name' value='Related tickets'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Custom field type:</div><div class='col-sm-4'><select style='width:300px' name='custom_type'><option>Text</option><option>Link</option><option>Checkbox</option></select></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Active Directory server:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ad_server' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Active Directory domain:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ad_domain' value=''></div></div></p>\n";
				print "<p>To validate logins against an Active Directory domain, enter your domain controller address and domain name (NT4 format) here.</p>\n";
				print "<p>Select which major components of NodePoint you want to activate:</p>";
				print "<p><div class='row'><div class='col-sm-4'>Component: Tickets Management</div><div class='col-sm-4'><input type='checkbox' name='comp_tickets' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Support Articles</div><div class='col-sm-4'><input type='checkbox' name='comp_articles' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Time Tracking</div><div class='col-sm-4'><input type='checkbox' name='comp_time' checked></div></div></p>\n";
				print "<p><input class='btn btn-primary pull-right' type='submit' value='Save'></p></form>\n"; 
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
	$logged_user = "api";
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
	elsif($q->param('api') eq "list_tickets")
	{
		if(!$q->param('product_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'product_id' argument.\",\n";
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
			print "{\n";
			print " \"message\": \"Ticket list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"tickets\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[0] . "\",\n";
				print "   \"product_id\": \"" . $res[1] . "\",\n";
				print "   \"release_id\": \"" . $res[2] . "\",\n";
				print "   \"title\": \"" . $res[5] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_users")
	{
		if(!$q->param('key'))
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
			print "{\n";
			print " \"message\": \"Users list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"users\": [\n";
			$sql = $db->prepare("SELECT name,email FROM users;");
			$sql->execute();
			my $found = 0;
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"name\": \"" . $res[0] . "\",\n";
				print "   \"email\": \"" . $res[1] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "verify_password")
	{
		if(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('password'))
		{
			print "{\n";
			print " \"message\": \"Missing 'password' argument.\",\n";
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
			print "{\n";
			my $found = 0;
			if($cfg->load("ad_domain") && $cfg->load("ad_server"))
			{
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or do
				{
					logevent("LDAP: Could not connect to Active Directory server");
					print " \"message\": \"Could not connect to AD server.\",\n";
					print " \"status\": \"ERR_AD_CONNECTION\",\n";
					print "}\n";
					exit(0);
				};
				my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . sanitize_alpha($q->param('user')), password=>$q->param('password'));
				if(!$mesg->code) { $found = 1; }
				else { logevent("LDAP: " . $mesg->error); }
			}
			else
			{
				$sql = $db->prepare("SELECT * FROM users WHERE name = ? AND pass = ?;");
				$sql->execute(sanitize_alpha($q->param('user')), sha1_hex($q->param('password')));
				while(my @res = $sql->fetchrow_array()) { $found = 1; }
			}
			if($found)
			{
				print " \"message\": \"Credentials are valid.\",\n";
				print " \"status\": \"OK\",\n";
			}
			else
			{
				print " \"message\": \"Invalid credentials.\",\n";
				print " \"status\": \"ERR_INVALID_CRED\",\n";
			}
			print "}\n";
		}
	}
	elsif($q->param('api') eq "change_password")
	{
		if(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('password'))
		{
			print "{\n";
			print " \"message\": \"Missing 'password' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(length($q->param('password')) < 6)
		{
			print "{\n";
			print " \"message\": \"Bad length for 'password' argument (above 6 characters).\",\n";
			print " \"status\": \"ERR_ARGUMENT_LENGTH\"\n";
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
		elsif($cfg->load("ad_server"))
		{
			print "{\n";
			print " \"message\": \"Passwords are synchronized with Active Directory.\",\n";
			print " \"status\": \"ERR_AD_ENABLED\"\n";
			print "}\n";		
		}
		else
		{
			print "{\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM users WHERE name = ?;");
			$sql->execute(sanitize_alpha($q->param('user')));
			while(my @res = $sql->fetchrow_array()) { $found = 1; }
			if(!$found)
			{
				print " \"message\": \"Invalid user name.\",\n";
				print " \"status\": \"ERR_INVALID_CRED\",\n";
			}
			else
			{
				$sql = $db->prepare("UPDATE users SET pass = '" . sha1_hex($q->param('password')) . "' WHERE name = ?;");
				$sql->execute(sanitize_alpha($q->param('user')));
				logevent("Password change: " . sanitize_alpha($q->param('user')));
				print " \"message\": \"Password changed.\",\n";
				print " \"status\": \"OK\",\n";
			}
			print "}\n";
		}
	}
	elsif($q->param('api') eq "add_user")
	{
		if(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(length(sanitize_alpha($q->param('user'))) < 3 || length(sanitize_alpha($q->param('user'))) > 16)
		{
			print "{\n";
			print " \"message\": \"Bad length for 'user' argument (between 3 and 16 characters).\",\n";
			print " \"status\": \"ERR_ARGUMENT_LENGTH\"\n";
			print "}\n";
		}
		elsif(!$q->param('password'))
		{
			print "{\n";
			print " \"message\": \"Missing 'password' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(length($q->param('password')) < 6)
		{
			print "{\n";
			print " \"message\": \"Bad length for 'password' argument (above 6 characters).\",\n";
			print " \"status\": \"ERR_ARGUMENT_LENGTH\"\n";
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
		elsif($cfg->load("ad_server"))
		{
			print "{\n";
			print " \"message\": \"Users are synchronized with Active Directory.\",\n";
			print " \"status\": \"ERR_AD_ENABLED\"\n";
			print "}\n";		
		}
		else
		{
			print "{\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM users WHERE name = ?;");
			$sql->execute(sanitize_alpha($q->param('user')));
			while(my @res = $sql->fetchrow_array()) { $found = 1; }
			if($found)
			{
				print " \"message\": \"User already exist.\",\n";
				print " \"status\": \"ERR_INVALID_ARGUMENT\",\n";
			}
			else
			{
				my $confirm = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..16;
				$sql = $db->prepare("INSERT INTO users VALUES(?, ?, ?, ?, ?, ?);");
				print " \"message\": \"User added.\",\n";
				print " \"status\": \"OK\",\n";
				if($q->param('email'))
				{ 
					$sql->execute(sanitize_alpha($q->param('user')), sha1_hex($q->param('password')), sanitize_email($q->param('email')), to_int($cfg->load('default_lvl')), "Never", $confirm); 
					notify(sanitize_alpha($q->param('user')), "Email confirmation", "You are receiving this email because a new user was created with this email address. Please confirm your email by logging into the NodePoint interface, and entering the following confirmation code under Settings: " . $confirm);
					print " \"confirm\": \"" . $confirm . "\",\n";
				}
				else { $sql->execute(sanitize_alpha($q->param('user')), sha1_hex($q->param('password')), "", to_int($cfg->load('default_lvl')), "Never", ""); }
				print " \"user\": \"" . sanitize_alpha($q->param('user')) . "\",\n";
				logevent("Add new user: " . sanitize_alpha($q->param('user')));
			}
			print "}\n";
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
		elsif(lc($cfg->load('api_imp')) ne "on" && $q->param('from_user'))
		{
			print "{\n";
			print " \"message\": \"User impersonation is not on.\",\n";
			print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
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
				my $from_user = "api";
				if(lc($cfg->load('api_imp')) eq "on" && $q->param('from_user')) { $from_user = sanitize_alpha($q->param('from_user')); }
				if($q->param('custom')) { $custom = sanitize_html($q->param('custom')); }
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), $from_user, "", sanitize_html($q->param('title')), sanitize_html($q->param('description')), $custom, "New", "", "", now(), "Never");
				$sql = $db->prepare("SELECT last_insert_rowid();");
				$sql->execute();
				my $rowid = -1;
				while(my @res = $sql->fetchrow_array()) { $rowid = to_int($res[0]); }
				print "{\n";
				print " \"message\": \"Ticket " . $rowid . " added.\",\n";
				print " \"status\": \"OK\"\n";
				print "}\n";
				$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array())
				{
					notify($res[1], "New ticket created", "A new ticket was created for one of your products:\n\nUser: api\nTitle: " . sanitize_html($q->param('title')) . "\n" . $cfg->load('custom_name') . ": " . $custom . "\nDescription: " . $q->param('description'));
				}
			}
		}
	}
	elsif($q->param('api') eq "add_release")
	{
		if(!$q->param('release_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'release_id' argument.\",\n";
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
		elsif(!$q->param('notes'))
		{
			print "{\n";
			print " \"message\": \"Missing 'notes' argument.\",\n";
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
			$sql = $db->prepare("INSERT INTO releases VALUES (?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('product_id')), "api", sanitize_html($q->param('release_id')), sanitize_html($q->param('notes')), now());
			print "{\n";
			print " \"message\": \"Release added.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "add_comment")
	{
		if(!$q->param('comment'))
		{
			print "{\n";
			print " \"message\": \"Missing 'comment' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('id'))
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
		elsif($q->param('key') ne $cfg->load('api_write'))
		{
			print "{\n";
			print " \"message\": \"Invalid 'key' value.\",\n";
			print " \"status\": \"ERR_INVALID_KEY\"\n";
			print "}\n";
		}
		else
		{
			$sql = $db->prepare("INSERT INTO comments VALUES (?, ?, ?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('id')), "api", sanitize_html($q->param('comment')), now(), "Never", "", "");
			print "{\n";
			print " \"message\": \"Comment added.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('id')));
			while(my @res = $sql->fetchrow_array())
			{
				my @us = split(' ', $res[4]);
				foreach my $u (@us)
				{
					notify($u, "New comment to ticket (" . to_int($q->param('id')) . ") assigned to you", "A new comment was posted to a ticket assigned to you:\n\nUser: api\nComment: " . sanitize_html($q->param('comment')));
				}
				notify($res[3], "New comment to your ticket (" . to_int($q->param('id')) . ")", "A new comment was posted to your ticket:\n\nUser: api\nComment: " . sanitize_html($q->param('comment')));
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
		if($logged_lvl > 2 && $cfg->load('comp_time') eq "on")
		{
			$sql = $db->prepare("SELECT * FROM timetracking WHERE name = ?;");
			$sql->execute($logged_user);
			my $totaltime = 0;
			while(my @res = $sql->fetchrow_array()) { $totaltime = $totaltime + to_float($res[2]); }
			print "<p>You have spent a total of <b>" . $totaltime . "</b> hours on tickets.</p>\n";
		}
		if($logged_lvl > 5)
		{
			print "<div class='alert alert-info' role='alert'><b>Update:</b><iframe src='//nodepoint.ca/update/?v=" . $VERSION . "' frameborder='0' width='99%' height='55px'></iframe></div>";
		}
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($res[0] eq $logged_user && $res[2] ne "" && $res[5] ne "" && $cfg->load('smtp_server'))
			{
				msg("<nobr><form method='POST' action='.'><input type='hidden' name='m' value='confirm_email'></nobr>Your email is not yet confirmed. Please enter the confirmation code here: <input type='text' name='code'> <input class='btn btn-primary pull-right' type='submit' value='Confirm'></form>", 2);
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
			print "<div class='form-group'><p><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='change_email'><div class='row'><div class='col-sm-6'>To change your notification email address, enter a new address here. Leave empty to disable notifications:</div><div class='col-sm-6'><input type='email' name='new_email' class='form-control' data-error='Must be a valid email.' placeholder='Email address' maxlength='99' value='" . $email . "'></div></div></p><div class='help-block with-errors'></div></div><input class='btn btn-primary pull-right' type='submit' value='Change email'></form></div></div>";
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Change password</h3></div><div class='panel-body'>\n";
			if($cfg->load("ad_server")) { print "<p>Password management is synchronized with Active Directory.</p>"; }
			elsif($logged_user eq "demo") { print "<p>The demo account cannot change its password.</p>"; }
			else
			{
				print "<div class='form-group'><p><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='change_pass'><div class='row'><div class='col-sm-4'><input placeholder='Current password' class='form-control' type='password' name='current_pass'></div><div class='col-sm-4'><input placeholder='New password' type='password' class='form-control' name='new_pass1' data-minlength='6' id='new_pass1' required></div><div class='col-sm-4'><input class='form-control' type='password' name='new_pass2' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm' required></div></div></p><div class='help-block with-errors'></div><input class='btn btn-primary pull-right' type='submit' value='Change password'></form></div>";
			}
			print "</div></div>";
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
				if($cfg->load('ad_server')) { print "<tr><td>" . $res[0] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td><a href='./?m=change_lvl&u=" . $res[0] . "'>Change access level</a></td><td>Managed by AD</td><td>" . $res[4] . "</td></tr>\n"; }
				else { print "<tr><td>" . $res[0] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td><a href='./?m=change_lvl&u=" . $res[0] . "'>Change access level</a></td><td><a href='./?m=reset_pass&u=" . $res[0] . "'>Reset password</a></td><td>" . $res[4] . "</td></tr>\n"; }
			}
			print "</table>\n";
			if(!$cfg->load('ad_server'))
			{
				print "<div class='form-group'><h4>Manually add a new user:</h4><form method='POST' action='.' data-toggle='validator' role='form'>\n";
				print "<p><div class='row'><div class='col-sm-6'><input type='text' name='new_name' placeholder='User name' class='form-control' required></div><div class='col-sm-6'><input type='email' name='new_email' placeholder='Email address (optional)' class='form-control'></div></div></p><p><div class='row'><div class='col-sm-6'><input type='password' name='new_pass1' data-minlength='6' id='new_pass1' class='form-control' placeholder='Password' required></div><div class='col-sm-6'><input type='password' name='new_pass2' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm password' class='form-control' required></div></div></p><div class='help-block with-errors'></div><input class='btn btn-primary pull-right' type='submit' value='Add user'></form></div>\n";
			}
			print "</div></div>\n";
		}
		if($logged_lvl > 1)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Statistics</h3></div><div class='panel-body'>\n";
			if($cfg->load('comp_tickets') eq "on")
			{
				print "<p><div class='row'><div class='col-sm-6'><center><h4>Number of tickets created</h4></center><canvas id='graph0'></canvas></div><div class='col-sm-6'><center><h4>Overall status distribution</h4></center><canvas id='graph1'></canvas></div></div></p>\n";
				print "<script src='Chart.min.js'></script><script>Chart.defaults.global.responsive = true; var data0 = { ";
				$sql = $db->prepare("SELECT created FROM tickets ORDER BY ROWID DESC;");
				$sql->execute();
				my $i = -1;
				my @labels = ('', '', '', '', '', '', '');
				my @points = (0, 0, 0, 0, 0, 0, 0);
				my $curwd = "-1";
				while(my @res = $sql->fetchrow_array())
				{ 
					my ($weekday, $month, $day, $hms, $year) = split(' ', $res[0]);
					if($curwd ne $month . " " . $day)
					{
						$i++;
						$curwd = $month . " " . $day;
					} 
					$labels[$i] = $month . " " . $day;
					$points[$i]++;
					if($i > 6) { last; }
				}			
				print "labels: ['" . $labels[6] . "', '" . $labels[5] . "', '" . $labels[4] . "', '" . $labels[3] . "', '" . $labels[2] . "', '" . $labels[1] . "', '" . $labels[0] . "'], datasets: [{ label: 'Tickets created by day', fillColor: '#F2FBFC', strokeColor: '#97BBCC', pointColor: '#97BBCC', pointStrokeColor: '#A7CBDC', pointHighlightFill: '#A7CBDC', pointHighlightStroke: '#97BBCC', data: [" . $points[6] . "," . $points[5] . "," . $points[4] . "," . $points[3] . "," . $points[2] . "," . $points[1] . "," . $points[0] . "] }]}; var ctx0 = document.getElementById('graph0').getContext('2d'); new Chart(ctx0).Line(data0); var data1 = [{ value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'New';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#87ABBC', highlight: '#97BBCC', label: 'New' }, { value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Open';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#EFC193', highlight: '#FFD1A3', label: 'Open' }, { value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Invalid';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#CDA5EF', highlight: '#DDB5FF', label: 'Invalid' }, { value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Hold';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#EF8B9C', highlight: '#FF9BAC', label: 'Hold' }, { value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Duplicate';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#A3D589', highlight: '#B3E599', label: 'Duplicate' }, { value: ";
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Resolved';");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { print $res[0]; }
				print ", color:'#DDDFA0', highlight: '#EDEFB0', label: 'Resolved' }";
				print "]; var ctx1 = document.getElementById('graph1').getContext('2d'); new Chart(ctx1).Pie(data1);</script><hr>\n";
			}
			print "<p><form method='GET' action='.'><div class='row'><div class='col-sm-6'><input type='hidden' name='m' value='stats'>Report type: <select class='form-control' name='report'>";
			if($cfg->load('comp_time') eq "on") { print "<option value='1'>Time spent per user</option><option value='2'>All time spent per ticket</option><option value='11'>Your time spent per ticket</option>"; }
			if($cfg->load('comp_articles') eq "on") { print "<option value='13'>Tickets linked per article</option>"; }
			if($cfg->load('comp_tickets') eq "on") { print "<option value='3'>Tickets created per " . lc($items{"Product"}) . "</option><option value='10'>New and open tickets per " . lc($items{"Product"}) . "</option><option value='4'>Tickets created per user</option><option value='5'>Tickets created per day</option><option value='6'>Tickets created per month</option><option value='7'>Tickets per status</option><option value='9'>Tickets assigned per user</option><option value='12'>Comment file attachments</option>"; }
			print "<option value='8'>Users per access level</option></select></div><div class='col-sm-6'><span class='pull-right'><input class='btn btn-primary' type='submit' value='Show report'> &nbsp; <input class='btn btn-primary' type='submit' name='csv' value='Export as CSV'></span></div></div></form></p></div><div class='help-block with-errors'></div></div>\n";
		}
		if($logged_lvl > 3 && $cfg->load('comp_tickets') eq "on")
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Custom forms</h3></div><div class='panel-body'>\n";
			print "<p><table class='table table-striped'><tr><th>Assigned " . lc($items{"Product"}) . "</th><th>Form name</th><th>Last update</th></tr>";
			my @products;
			$sql = $db->prepare("SELECT ROWID,* FROM products;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
			$sql = $db->prepare("SELECT ROWID,* FROM forms;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>";
 				if($products[$res[1]]) { print $products[$res[1]]; }
				else { print "None"; }
				print "</td><td><a href='./?edit_form=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[23] . "</td></tr>\n";
			}
			print "</table><form method='GET' action='./'><input type='hidden' name='create_form' value='1'><input type='submit' value='Create new custom form' class='pull-right btn btn-primary'></form></p></div></div>\n";
		}
		if($logged_lvl > 5)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Initial settings</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.'><table class='table table-striped'><tr><th>Setting</th><th>Value</th></tr>\n";
			print "<tr><td>Database file</td><td><input class='form-control' type='text' name='db_address' value=\"" .  $cfg->load("db_address") . "\"></td></tr>\n";
			print "<tr><td>Admin name</td><td><input class='form-control' type='text' name='admin_name' value=\"" .  $cfg->load("admin_name") . "\" readonly></td></tr>\n";
			print "<tr><td>Admin password</td><td><input class='form-control' type='password' name='admin_pass' value=''></td></tr>\n";
			print "<tr><td>Site name</td><td><input class='form-control' type='text' name='site_name' value=\"" . $cfg->load("site_name") . "\"></td></tr>\n";
			print "<tr><td>Public notice</td><td><input class='form-control' type='text' name='motd' value=\"" . $cfg->load("motd") . "\"></td></tr>\n";
			print "<tr><td>Bootstrap template</td><td><input class='form-control' type='text' name='css_template' value=\"" . $cfg->load("css_template") . "\"></td></tr>\n";
			print "<tr><td>Favicon</td><td><input class='form-control' type='text' name='favicon' value=\"" . $cfg->load("favicon") . "\"></td></tr>\n";
			print "<tr><td>Ticket visibility</td><td><select class='form-control' name='default_vis'>";
			if($cfg->load("default_vis") eq "Restricted") { print "<option>Public</option><option>Private</option><option selected>Restricted</option>"; }
			elsif($cfg->load("default_vis") eq "Private") { print "<option>Public</option><option selected>Private</option><option>Restricted</option>"; }
			else { print "<option selected>Public</option><option>Private</option><option>Restricted</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>Default access level</td><td><input class='form-control' type='text' name='default_lvl' value=\"" . to_int($cfg->load("default_lvl")) . "\"></td></tr>\n";
			print "<tr><td>Allow registrations</td><td><select class='form-control' name='allow_registrations'>";
			if($cfg->load("allow_registrations") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>API read key</td><td><input class='form-control' type='text' name='api_read' value=\"" . $cfg->load("api_read") . "\"></td></tr>\n";
			print "<tr><td>API write key</td><td><input class='form-control' type='text' name='api_write' value=\"" . $cfg->load("api_write") . "\"></td></tr>\n";
			print "<tr><td>Allow user impersonation</td><td><select class='form-control' name='api_imp'>";
			if($cfg->load("api_imp") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>SMTP server</td><td><input class='form-control' type='text' name='smtp_server' value=\"" . $cfg->load("smtp_server") . "\"></td></tr>\n";
			print "<tr><td>SMTP port</td><td><input class='form-control' type='text' name='smtp_port' value=\"" . $cfg->load("smtp_port") . "\"></td></tr>\n";
			print "<tr><td>SMTP username</td><td><input class='form-control' type='text' name='smtp_user' value=\"" . $cfg->load("smtp_user") . "\"></td></tr>\n";
			print "<tr><td>SMTP password</td><td><input class='form-control' type='password' name='smtp_pass' value=\"" . $cfg->load("smtp_pass") . "\"></td></tr>\n";
			print "<tr><td>Support email</td><td><input class='form-control' type='text' name='smtp_from' value=\"" . $cfg->load("smtp_from") . "\"></td></tr>\n";
			print "<tr><td>External notifications plugin</td><td><input class='form-control' type='text' name='ext_plugin' value=\"" . $cfg->load("ext_plugin") . "\"></td></tr>\n";
			print "<tr><td>Upload folder</td><td><input class='form-control' type='text' name='upload_folder' value=\"" . $cfg->load("upload_folder") . "\"></td></tr>\n";
			print "<tr><td>Minimum upload level</td><td><input class='form-control' type='text' name='upload_lvl' value=\"" . to_int($cfg->load("upload_lvl")) . "\"></td></tr>\n";
			print "<tr><td>Items managed</td><td><select class='form-control' name='items_managed'>";
			if($cfg->load("items_managed") eq "Projects with goals and milestones") { print "<option>Products with models and releases</option><option selected>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option>"; }
			elsif($cfg->load("items_managed") eq "Resources with locations and updates") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option selected>Resources with locations and updates</option><option>Applications with platforms and versions</option>"; }
			elsif($cfg->load("items_managed") eq "Applications with platforms and versions") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option selected>Applications with platforms and versions</option>"; }
			else { print "<option selected>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option>"; }
			print "</select></td></tr>\n";			
			print "<tr><td>Custom ticket field</td><td><input class='form-control' type='text' name='custom_name' value=\"" . $cfg->load("custom_name") . "\"></td></tr>\n";
			print "<tr><td>Custom field type</td><td><select class='form-control' name='custom_type'>";
			if($cfg->load("custom_type") eq "Link") { print "<option>Text</option><option selected>Link</option><option>Checkbox</option>"; }
			elsif($cfg->load("custom_type") eq "Checkbox") { print "<option>Text</option><option>Link</option><option selected>Checkbox</option>"; }
			else { print "<option selected>Text</option><option>Link</option><option>Checkbox</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>Active Directory server</td><td><input class='form-control' type='text' name='ad_server' value=\"" . $cfg->load("ad_server") . "\"></td></tr>\n";
			print "<tr><td>Active Directory domain</td><td><input class='form-control' type='text' name='ad_domain' value=\"" . $cfg->load("ad_domain") . "\"></td></tr>\n";
			print "<tr><td>Component: Tickets Management</td><td><select class='form-control' name='comp_tickets'>";
			if($cfg->load("comp_tickets") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>Component: Support Articles</td><td><select class='form-control' name='comp_articles'>";
			if($cfg->load("comp_articles") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td>Component: Time Tracking</td><td><select class='form-control' name='comp_time'>";
			if($cfg->load("comp_time") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "</table>The admin password will be left unchanged if empty.<br>See the <a href='./README.html'>README</a> file for help.<input class='btn btn-primary pull-right' type='submit' value='Save settings'></form></div></div>\n";
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Log (last 200 events)</h3></div><div class='panel-body'>\n";
			print "<form style='display:inline' method='POST' action='.'><input type='hidden' name='m' value='clear_log'><input class='btn btn-danger pull-right' type='submit' value='Clear log'><br></form><a name='log'></a><p>Filter log by events:<br><a href='./?m=settings#log'>All</a> | <a href='./?m=settings&filter_log=Failed#log'>Failed logins</a> | <a href='./?m=settings&filter_log=Success#log'>Successful logins</a> | <a href='./?m=settings&filter_log=level#log'>Level changes</a> | <a href='./?m=settings&filter_log=password#log'>Password changes</a> | <a href='./?m=settings&filter_log=new#log'>New users</a> | <a href='./?m=settings&filter_log=setting#log'>Settings updated</a> | <a href='./?m=settings&filter_log=notification#log'>Email notifications</a> | <a href='./?m=settings&filter_log=LDAP:#log'>Active Directory</a> | <a href='./?m=settings&filter_log=deleted:#log'>Deletes</a></p>\n";
			print "<table class='table table-striped'><tr><th>IP address</th><th>User</th><th>Event</th><th>Time</th></tr>\n";
			if($q->param("filter_log"))
			{
				$sql = $db->prepare("SELECT * FROM log DESC WHERE op LIKE ? ORDER BY key DESC LIMIT 200;");
				$sql->execute("%" . sanitize_alpha($q->param("filter_log")) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT * FROM log ORDER BY key DESC LIMIT 200;");
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
		if(length(sanitize_email($q->param('new_email'))) > 99)
		{
			msg("Email address should be less than 99 characters. Please go back and try again.", 0);
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
					notify($logged_user, "Email confirmation", "You are receiving this email because a user was created with this email address. Please confirm your email by logging into the NodePoint interface, and entering the following confirmation code under Settings: " . $confirm);
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
		print "<p><form method='POST' action='.'><input type='hidden' name='m' value='change_lvl'><input type='hidden' name='u' value='" . sanitize_alpha($q->param('u')) . "'>Select a new access level for user <b>" . sanitize_alpha($q->param('u')) . "</b>: <select name='newlvl'><option>0</option><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select><br><input class='btn btn-primary' type='submit' value='Change level'></form></p><br>\n";
		print "<p>Here is a list of available NodePoint levels:</p>\n";
		print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can create users, reset passwords, change access levels</td></tr><tr><td>4</td><td>" . $items{"Product"} . "s management</td><td>Can add, retire and edit " . lc($items{"Product"}) . "s, edit articles</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create " . lc($items{"Release"}) . "s, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view statistics, restricted tickets and " . lc($items{"Product"}) . "s</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
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
	elsif($q->param('m') eq "auto_assign" && $q->param('p') && $q->param('a') && $logged_lvl > 2)
	{
		headers("Products");
		if($q->param('a') eq "Auto-assign yourself")
		{
			$sql = $db->prepare("INSERT INTO autoassign VALUES (?, ?);");
			$sql->execute(to_int($q->param('p')), $logged_user);
			msg("Added yourself to auto-assignment. Press <a href='./?m=view_product&p=" . to_int($q->param('p')) . "'>here</a> to continue.", 3);
		}
		else
		{
			$sql = $db->prepare("DELETE FROM autoassign WHERE productid = ? AND user = ?;");
			$sql->execute(to_int($q->param('p')), $logged_user);
			msg("Removed yourself from auto-assignment. Press <a href='./?m=view_product&p=" . to_int($q->param('p')) . "'>here</a> to continue.", 3);		
		}
	}
	elsif($q->param('m') eq "save_article" && defined($q->param('article')) && defined($q->param('productid')) && $q->param('id') && defined($q->param('title')) && defined($q->param('published')) && $logged_lvl > 3)
	{
		headers("Articles");
		if(length(sanitize_html($q->param('title'))) < 2 || length(sanitize_html($q->param('title'))) > 50)
		{
			msg("The title must be between 2 and 50 characters. Please go back and try again.", 0);
		}
		else
		{
			$sql = $db->prepare("UPDATE kb SET title = ?, article = ?, published = ?, modified = ?, productid = ? WHERE ROWID = ?;");
			$sql->execute(sanitize_html($q->param('title')), sanitize_html($q->param('article')), to_int($q->param('published')), now(), to_int($q->param('productid')), to_int($q->param('id')));
			msg("Article <b>" . to_int($q->param('id')) . "</b> saved. Press <a href='./?m=articles'>here</a> to continue.", 3);
		}		
	}
	elsif($q->param('m') eq "add_article" && $logged_lvl > 3 && defined($q->param('productid')) && defined($q->param('title')))
	{
		headers("Articles");
		if(length(sanitize_html($q->param('title'))) < 2 || length(sanitize_html($q->param('title'))) > 50)
		{
			msg("The title must be between 2 and 30 characters. Please go back and try again.", 0);
		}
		else
		{
			$sql = $db->prepare("INSERT INTO kb VALUES (?, ?, '', 0, ?, ?, 'Never');");
			$sql->execute(to_int($q->param('productid')), sanitize_html($q->param('title')), $logged_user, now());
			msg("New draft article <b>" . sanitize_html($q->param('title')) . "</b> added. Press <a href='./?m=articles'>here</a> to continue.", 3);
		}
	}
	elsif($q->param('m') eq "articles")
	{
		headers("Articles");
		my @products;
		my $product;
		my $status;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		if($logged_lvl > 3)
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Add a new article</h3></div><div class='panel-body'>\n";
			print "<form method='GET' action='.'><p><div class='row'><div class='col-sm-6'><input type='hidden' name='m' value='add_article'><input placeholder='Title' class='form-control' type='text' name='title' maxlength='50'></div><div class='col-sm-6'><select class='form-control' name='productid'><option value='0'>All " . lc($items{"Product"}) . "s</option>";
			for(my $i = 1; $i < scalar(@products); $i++)
			{
				if($products[$i]) { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; }
			}
			print "</select></div></div></p><p><input type='submit' class='btn btn-primary pull-right' value='Add article'></p></form></div></div>\n";
		}
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Support articles</h3></div><div class='panel-body'><table class='table table-striped'>\n";
		if($logged_lvl > 3) { print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Last update</th></tr>"; }
		else { print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Last update</th></tr>"; }
		if($logged_lvl > 3) { $sql = $db->prepare("SELECT ROWID,* FROM kb;"); }
		else { $sql = $db->prepare("SELECT ROWID,* FROM kb WHERE published = 1;"); }
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if(to_int($res[1]) == 0) { $product = "All"; }
			elsif(!$products[$res[1]]) { $product = "All"; }
			else { $product = $products[$res[1]]; }
			if(to_int($res[4]) == 0) { $status = "Draft"; }
			else { $status = "Published"; }			
			if($logged_lvl > 3)
			{
				
				if($res[7] eq "Never") { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $status . "</td><td>" . $res[6] . "</td></tr>\n"; }
				else { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $status . "</td><td>" . $res[7] . "</td></tr>\n"; }
			}
			else
			{
				if($res[7] eq "Never") { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[6] . "</td></tr>\n"; }
				else { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[7] . "</td></tr>\n"; }
			}			
		}
		print "</table></div></div>\n";
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
				if($logged_lvl > 3) { print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <input class='form-control' type='text' name='product_name' value='" . $res[1] . "'></div><div class='col-sm-6'>" . $items{"Model"} . ": <input class='form-control' type='text' name='product_model' value='" . $res[2] . "'></div></div></p>\n"; }
				else { print "<p><div class='row'><div class='col-sm-6'>Product name: <b>" . $res[1] . "</b></div><div class='col-sm-6'>" . $items{"Model"} . ": <b>" . $res[2] . "</b></div></div></p>\n"; }
				print "<p><div class='row'><div class='col-sm-6'>Created on: <b>" . $res[6] . "</b></div><div class='col-sm-6'>Last modified on: <b>" . $res[7] . "</b></div></div></p>\n";
				if($logged_lvl > 3)
				{
					print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <select class='form-control' name='product_vis'><option";
					if($res[5] eq "Public") { print " selected=selected"; }
					print ">Public</option><option";
					if($res[5] eq "Private") { print " selected=selected"; }
					print ">Private</option><option";
					if($res[5] eq "Restricted") { print " selected=selected"; }
					print ">Restricted</option><option";
					if($res[5] eq "Archived") { print " selected=selected"; }
					print ">Archived</option></select></div>\n";
				}
				else { print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <b>" . $res[5] . "</b></div>"; }
				print "<div class='col-sm-6'>Auto-assigned to:<b>";
				my $sql2 = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
				$sql2->execute(to_int($q->param('p')));
				while(my @res2 = $sql2->fetchrow_array()) { print " " . $res2[0]; }
				print "</b></div></div></p>\n";
				if($logged_lvl > 3) { print "<p>Description:<br><textarea rows='10' name='product_desc' class='form-control'>" . $res[3] . "</textarea></p>\n"; }
				else { print "<p>Description:<br><pre>" . $res[3] . "</pre></p>\n"; }
				if($res[4] ne "") { print "<p><img src='./?file=" . $res[4] . "' style='max-width:95%'></p>\n"; }
				if($logged_lvl > 3) { print "<input class='btn btn-primary pull-right' type='submit' value='Update " . lc($items{"Product"}) . "'>Change " . lc($items{"Product"}) . " image: <input type='file' name='product_screenshot'></form>\n"; }
				if($logged_user eq $cfg->load("admin_name")) { print "<form method='GET' action='.'><input type='hidden' name='m' value='confirm_delete'><input type='hidden' name='productid' value='" . to_int($q->param('p')) . "'><input type='submit' class='btn btn-danger pull-right' value='Permanently delete this " . lc($items{"Product"}) . "'></form>"; }
				if($logged_lvl > 2)
				{
					my $sql2 = $db->prepare("SELECT * FROM autoassign WHERE productid = ? AND user = ?;");
					$sql2->execute(to_int($q->param('p')), $logged_user);
					my $found = 0;
					while(my @res2 = $sql2->fetchrow_array()) { $found = 1; }
					print "<p><form method='GET' action='.'><input type='hidden' name='m' value='auto_assign'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input class='btn btn-primary' type='submit' name='a' value='";
					if($found == 0) { print "Auto-assign yourself"; }
					else { print "Remove auto-assignment"; }
					print "'></form></p>";
				}
				print "</div></div>\n";
			}
			if($logged_lvl > 2 && $vis ne "Archived")
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Add " . lc($items{"Release"}) . " to this " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><form method='POST' action='.'>\n";
				print "<input type='hidden' name='m' value='add_release'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'><div class='row'><div class='col-sm-4'>" . $items{"Release"} . ": <input type='text' class='form-control' name='release_version'></div><div class='col-sm-6'>Notes or link: <input type='text' name='release_notes' class='form-control'></div></div><input class='btn btn-primary pull-right' type='submit' value='Add " . lc($items{"Release"}) . "'></form></div></div>\n";    
			}
			if($vis eq "Public" || ($vis eq "Private" && $logged_user ne "") || ($vis eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3)
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Release"} . "s</h3></div><div class='panel-body'><table class='table table-striped'>\n";
				print "<tr><th>" . $items{"Release"} . "</th><th>User</th><th>Notes</th><th>Date</th></tr>\n";
				$sql = $db->prepare("SELECT ROWID,* FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('p')));
				while(my @res = $sql->fetchrow_array())
				{
					print "<tr><td>" . $res[3] . "</td><td>" . $res[2] . "</td><td>";
					if(lc(substr($res[4], 0, 4)) eq "http") { print "<a href='" . $res[4] . "'>" . $res[4] . "</a>"; }
					else { print $res[4]; }
					print "</td><td>" .  $res[5];
					if($logged_lvl > 2) { print "<span class='pull-right'><form method='GET' action='.'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'><input type='hidden' name='m' value='delete_release'><input type='hidden' name='release_id' value='" . $res[0] . "'><input class='btn btn-danger' type='submit' value='Delete'></form></span>"; } 
					print "</td></tr>\n";
				}
				print "</table></div></div>\n";
			}
		}
		if($cfg->load('comp_articles') eq "on")
		{
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Related articles</h3></div><div class='panel-body'><table class='table table-striped'>\n";
			if($logged_lvl > 3) { print "<tr><th>ID</th><th>Title</th><th>Status</th><th>Last update</th></tr>"; }
			else { print "<tr><th>ID</th><th>Title</th><th>Last update</th></tr>"; }
			if($logged_lvl > 3) { $sql = $db->prepare("SELECT ROWID,* FROM kb WHERE (productid = ? OR productid = 0);"); }
			else { $sql = $db->prepare("SELECT ROWID,* FROM kb WHERE published = 1 AND (productid = ? OR productid = 0);"); }
			$sql->execute(to_int($q->param('p')));
			my $status;
			while(my @res = $sql->fetchrow_array())
			{
				if(to_int($res[4]) == 0) { $status = "Draft"; }
				else { $status = "Published"; }			
				if($logged_lvl > 3)
				{
					
					if($res[7] eq "Never") { print "<tr><td>" . $res[0] . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $status . "</td><td>" . $res[6] . "</td></tr>\n"; }
					else { print "<tr><td>" . $res[0] . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $status . "</td><td>" . $res[7] . "</td></tr>\n"; }
				}
				else
				{
					if($res[7] eq "Never") { print "<tr><td>" . $res[0] . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[6] . "</td></tr>\n"; }
					else { print "<tr><td>" . $res[0] . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[7] . "</td></tr>\n"; }
				}			
			}
			print "</table></div></div>\n";
		}
	}
	elsif($logged_lvl > 2 && $q->param('m') eq "delete_release")
	{
		headers($items{"Product"} . "s");
		if(!$q->param('release_id') || !$q->param('product_id'))
		{
			my $text = "Required fields missing: ";
			if(!$q->param('product_id')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . " ID</span> "; }
			if(!$q->param('release_id')) { $text .= "<span class='label label-danger'>" . $items{"Release"} . " ID</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);	    
		}
		else
		{
			$sql = $db->prepare("DELETE FROM releases WHERE productid = ? AND ROWID = ?;");
			$sql->execute(to_int($q->param('product_id')), to_int($q->param('release_id')));
			msg($items{"Release"} . " deleted from " . lc($items{"Product"}) . " <b>" . to_int($q->param('product_id')) . "</b>. Press <a href='./?m=view_product&p=" . to_int($q->param('product_id')) . "'>here</a> to continue.", 3);
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
				msg($items{"Release"} . " added. Press <a href='./?m=view_product&p=" . to_int($q->param('product_id')) . "'>here</a> to continue.", 3);
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
				msg($items{"Product"} . " <b>" . sanitize_html($q->param('product_name')) . "</b> updated. Press <a href='./?m=view_product&p=" . to_int($q->param('product_id')) . "'>here</a> to continue.", 3);
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
			print "<p><div class='row'><div class='col-sm-6'><input placeholder='" . $items{"Product"} . " name' type='text' name='product_name' class='form-control'></div><div class='col-sm-6'><input type='text' placeholder='" . $items{"Model"} . "' name='product_model' class='form-control'></div></div></p>\n";
			print "<p><div class='row'><div class='col-sm-6'><input type='text' name='product_release' placeholder='Initial " . lc($items{"Release"}) . "' class='form-control'></div><div class='col-sm-6'><select class='form-control' name='product_vis'><option>Public</option><option>Private</option><option>Restricted</option></select></div></div></p>\n";
			print "<p><textarea placeholder='Description' class='form-control' name='product_desc' rows='10' style='width:99%'></textarea></p><input class='btn btn-primary pull-right' type='submit' value='Add " . lc($items{"Product"}) . "'>";
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
				if($q->param("notify_user")) { $changes .= "Notified user: " . sanitize_alpha($q->param('notify_user')) . "\n"; }
				@us = split(' ', $res[4]);
				$creator = $res[3];
			}
			$sql = $db->prepare("UPDATE tickets SET link = ?, resolution = ?, status = ?, title = ?, description = ?, assignedto = ?, releaseid = ?, modified = ? WHERE ROWID = ?;");
			$sql->execute($lnk, $resolution, sanitize_alpha($q->param('ticket_status')), sanitize_html($q->param('ticket_title')), sanitize_html($q->param('ticket_desc')) . "\n\n--- " . now() . " ---\nTicket modified by: " . $logged_user . "\n" . $changes, $assigned, sanitize_html($q->param('ticket_releases')), now(), to_int($q->param('t')));
			foreach my $u (@us)
			{
				notify($u, "Ticket (" . to_int($q->param('t')) . ") assigned to you has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes);
			}
			if($creator) { notify($creator, "Your ticket (" . to_int($q->param('t')) . ") has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes); }
			msg("Ticket updated. Press <a href='./?m=view_ticket&t=" . to_int($q->param('t')) . "'>here</a> to continue.", 3);
			if($q->param("time_spent") && to_float($q->param("time_spent")) != 0)
			{
				$sql = $db->prepare("INSERT INTO timetracking VALUES (?, ?, ?, ?);");
				$sql->execute(to_int($q->param('t')), $logged_user, to_float($q->param("time_spent")), now());
			}
			if($q->param("notify_user") && sanitize_alpha($q->param('notify_user')) ne "")
			{
				$sql = $db->prepare("INSERT INTO escalate VALUES (?, ?);");
				$sql->execute(to_int($q->param('t')), sanitize_alpha($q->param('notify_user')));
				notify(sanitize_alpha($q->param('notify_user')), "Ticket (" . to_int($q->param('t')) . ") requires your attention", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes);
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
	elsif($q->param('m') eq "link_article" && $logged_lvl > 1)
	{
		headers("Articles");
		if($q->param('articleid') && $q->param('ticketid'))
		{
			$sql = $db->prepare("INSERT INTO kblink VALUES (?, ?);");
			$sql->execute(to_int($q->param('ticketid')), to_int($q->param('articleid')));
			msg("Article linked to ticket <b>" . to_int($q->param('ticketid')) . "</b>. Press <a href='./?m=view_ticket&t=" . to_int($q->param('ticketid')) . "'>here</a> to continue.", 3);
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('ticketid')) { $text .= "<span class='label label-danger'>Ticket ID</span> "; }
			if(!$q->param('articleid')) { $text .= "<span class='label label-danger'>Article ID</span> "; }
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
			msg("Comment added. Press <a href='./?m=view_ticket&t=" . to_int($q->param('t')) . "'>here</a> to continue.", 3);
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
		msg("Ticket <b>" . to_int($q->param('t')) . "</b> added to your home page. Press <a href='./?m=view_ticket&t=" . to_int($q->param('t')) . "'>here</a> to continue.", 3);
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
		msg("Removed ticket <b>" . to_int($q->param('t')) . "</b> from your home page. Press <a href='./?m=view_ticket&t=" . to_int($q->param('t')) ."'>here</a> to continue.", 3);
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
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Ticket " . to_int($q->param('t')) . "</h3></div><div class='panel-body'>";
				if($logged_lvl > 2) { print "<form method='POST' action='.'><input type='hidden' name='m' value='update_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'>\n"; }
				print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . ": <b>" . $product . "</b></div>";
				if($cfg->load('comp_articles') eq "on")
				{
					print "<div class='col-sm-6'>Linked articles: ";
					$sql = $db->prepare("SELECT DISTINCT kb FROM kblink WHERE ticketid = ?;");
					$sql->execute(to_int($q->param('t')));
					while(my @res2 = $sql->fetchrow_array()) { print "<a href='./?kb=" . $res2[0] . "'>" . $res2[0] . "</a> "; }
					print "</div>";
				}
					print "</div></p>";
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
					print "<p><div class='row'><div class='col-sm-6'>Status: <select class='form-control' name='ticket_status'><option";
					if($res[8] eq "New") { print " selected"; }
					print ">New</option><option";
					if($res[8] eq "Open") { print " selected"; }
					print ">Open</option><option";
					if($res[8] eq "Invalid") { print " selected"; }
					print ">Invalid</option><option";
					if($res[8] eq "Hold") { print " selected"; }
					print ">Hold</option><option";
					if($res[8] eq "Duplicate") { print " selected"; }
					print ">Duplicate</option><option";
					if($res[8] eq "Resolved") { print " selected"; }
					print ">Resolved</option><option";
					if($res[8] eq "Closed") { print " selected"; }
					print ">Closed</option></select></div><div class='col-sm-6'>Resolution: <input type='text' name='ticket_resolution' class='form-control' value='" . $res[9] . "'></div></div></p>\n"; 
				}
				else {print "<p><div class='row'><div class='col-sm-6'>Status: <b>" . $res[8] . "</b></div><div class='col-sm-6'>Resolution: <b>" . $res[9] . "</b></div></div></p>\n"; }
				print "<p><div class='row'><div class='col-sm-6'>" . $items{"Release"} . "s: ";
				if($logged_lvl > 2) { print "<input type='text' class='form-control' name='ticket_releases' value='" . $res[2] . "'>"; }
				else { print "<b>" . $res[2] . "</b>"; }
				print "</div><div class='col-sm-6'>";
				if($logged_lvl > 2)	{ print $cfg->load('custom_name') . ": <input type='text' class='form-control' name='ticket_link' value='" . $res[7] . "'></div></div></p>\n"; }
				else
				{
					if($cfg->load('custom_type') eq "Link") { print $cfg->load('custom_name') . ": <a href='" . $res[7] . "'><b>" . $res[7] . "</b></a></div></div></p>\n"; }
					else { print $cfg->load('custom_name') . ": <b>" . $res[7] . "</b></div></div></p>\n"; }
				}
				if($logged_lvl > 2) { print "<p>Title: <input type='text' class='form-control' name='ticket_title' value='" . $res[5] . "'></p>"; }
				else { print "<p>Title: <b>" . $res[5] . "</b></p>"; }
				if($logged_lvl > 2) { print "<p>Description:<br><textarea class='form-control' name='ticket_desc' rows='20'>" . $res[6] . "</textarea></p>\n"; }
				else { print "<p>Description:<br><pre>" . $res[6] . "</pre></p>\n"; }
				if($logged_lvl > 2)
				{ 
					print "<p><div class='row'>";
					if($cfg->load('comp_time') eq "on") { print "<div class='col-sm-4'>Time spent (in <b>hours</b>): <input type='text' name='time_spent' class='form-control' value='0'></div>"; }
					print "<div class='col-sm-4'>Notify user: <input type='text' name='notify_user' class='form-control' value=''></div>";
					if($cfg->load('comp_time') ne "on") { print "<div class='col-sm-4'></div>"; }
					print "<div class='col-sm-4'><input class='btn btn-primary pull-right' type='submit' value='Update ticket'></div></div></p></form><hr>\n"; 
				}
				if($logged_lvl > 1 && $cfg->load('comp_articles') eq "on")
				{
					print "<div class='row'><div class='col-sm-8'><form method='GET' action='./'><input type='hidden' name='m' value='link_article'><input type='hidden' name='ticketid' value='" . to_int($q->param('t')) . "'><select class='form-control' name='articleid'>";
					$sql = $db->prepare("SELECT ROWID,title FROM kb WHERE published = 1 AND (productid = ? OR productid = 0);");
					$sql->execute(to_int($res[1]));
					while(my @res2 = $sql->fetchrow_array()) { print "<option value=" . $res2[0] . ">" . $res2[1] . "</option>"; }
					print "</select></div><div class='col-sm-4'><input class='btn btn-primary pull-right' type='submit' value='Link article to this ticket'></form></div></div><hr>";
				}
				if($logged_user ne "")
				{
					if($res[10] =~ /\b\Q$logged_user\E\b/) { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='unfollow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-primary' type='submit' value='Unfollow ticket'></form>"; }
					else { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='follow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-primary' type='submit' value='Follow ticket'></form>"; }
				}
				if($logged_user eq $cfg->load("admin_name")) { print "<span class='pull-right'><form method='GET' action='.'><input type='hidden' name='m' value='confirm_delete'><input type='hidden' name='ticketid' value='" . to_int($q->param('t')) . "'><input type='submit' class='btn btn-danger' value='Permanently delete this ticket'></form></span>"; }
				print "</div></div>\n";
				if($logged_lvl > 1 && $cfg->load('comp_time') eq "on")
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
					print "<p><textarea class='form-control' rows='4' name='comment'></textarea></p>";
					print "<p><input class='btn btn-primary pull-right' type='submit' value='Add comment'>";
					if($logged_lvl >= to_int($cfg->load('upload_lvl'))) { print "Attach file: <input type='file' name='attach_file'>"; }
					print "</p></form></div></div>\n";
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
					if($logged_user eq $res[2]) { print "<p><textarea name='comment' rows='5' class='form-control'>" . $res[3] . "</textarea></p>"; }
					else { print "<p><pre>" . $res[3] . "</pre></p>"; }
					if($res[6] ne "" && $res[7] ne "") { print "<p>Attached file: <a href='./?file=" . $res[6] . "'>" . $res[7] . "</a></p>\n"; }
					print "<p><span class='pull-right'>";
					if($logged_user eq $res[2]) { print "<input class='btn btn-primary' type='submit' name='action' value='Update comment'> \n"; }
					if($logged_lvl > 4) { print "<input class='btn btn-danger' type='submit' name='action' value='Delete comment'>\n"; }
					print "</span></p></form></div></div>\n";
				}
			}
		}
	}
	elsif($q->param('m') eq "add_ticket" && $logged_lvl > 0 && $q->param('product_id'))
	{
		headers("Tickets");
		my @customform;
		my $description = "";
		my $title;
		$sql = $db->prepare("SELECT * FROM forms WHERE productid = ?;");
		$sql->execute(to_int($q->param('product_id')));
		@customform = $sql->fetchrow_array();
		if(@customform)
		{
			if($q->param('field0')) { $title = $q->param('field0'); }
			for(my $i = 0; $i < 10; $i++)
			{
				if($customform[($i*2)+2])
				{
					$description .= $customform[($i*2)+2] . " \t ";
					if($q->param('field'.$i)) { $description .= $q->param('field'.$i); }
					$description .= "\n\n"; 
				}
			}
		}
		else
		{
			if($q->param('ticket_title')) {	$title = $q->param('ticket_title'); }
			if($q->param('ticket_desc')) { $description = $q->param('ticket_desc'); }
 		}
		if($title && $description && $q->param('release_id'))
		{
			if(length($title) > 99 || length($description) > 9999)
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
				my $assignedto = "";
				$sql = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array()) { $assignedto .= $res[0] . " "; }
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), $logged_user, $assignedto, sanitize_html($title), sanitize_html($description), $lnk, "New", "", "", now(), "Never");
				$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array())
				{
					notify($res[1], "New ticket created", "A new ticket was created for one of your products:\n\nUser: " . $logged_user . "\nTitle: " . sanitize_html($title) . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nDescription: " . sanitize_html($description));
				}
				foreach my $assign (split(' ', $assignedto))
				{
					notify($assign, "New ticket created", "A new ticket was created for a product assigned to you:\n\nUser: " . $logged_user . "\nTitle: " . sanitize_html($title) . "\n" . $cfg->load('custom_name') . ": " . $lnk . "\nDescription: " . sanitize_html($description));
				}
				msg("Ticket successfully added. Press <a href='./?m=tickets'>here</a> to continue.", 3);
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$title)
			{
				if(@customform) { $text .= "<span class='label label-danger'>" . $customform[2] . "</span> "; }
				else { $text .= "<span class='label label-danger'>Ticket title</span> "; }
			}
			if(!$description) { $text .= "<span class='label label-danger'>Ticket description</span> "; }
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
			my @customform;
			$sql = $db->prepare("SELECT * FROM forms WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			@customform = $sql->fetchrow_array();
			print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Create a new ticket</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'>\n";
			print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <b>" . $product . "</b><input type='hidden' name='product_id' value='" . to_int($q->param('product_id')) . "'></div><div class='col-sm-6' style='text-align:right'>" . $items{"Release"} . ": <select name='release_id'>";
			$sql = $db->prepare("SELECT ROWID,* FROM releases WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array()) { print "<option>" . $res[3] . "</option>"; }
			print "</select></div></div></p><hr>\n";
			if(@customform)
			{
				for(my $i = 0; $i < 10; $i++)
				{
					if($customform[($i*2)+2])
					{
						print "<p><div class='row'><div class='col-sm-5'>" . $customform[($i*2)+2] . "</div><div class='col-sm-7'>";
						if(to_int($customform[($i*2)+3]) == 1) { print "<textarea class='form-control' name='field" . $i . "' rows=4></textarea>"; }
						elsif(to_int($customform[($i*2)+3]) == 2) { print "<input type='number' class='form-control' name='field" . $i . "'>"; }
						elsif(to_int($customform[($i*2)+3]) == 3) { print "<input type='checkbox' name='field" . $i . "'>"; }
						elsif(to_int($customform[($i*2)+3]) == 4) { print "<input type='radio' name='field" . $i . "' id='field" . $i . "yes' value='Yes'><label for='field" . $i . "yes'>Yes</label> &nbsp; <input type='radio' name='field" . $i . "' id='field" . $i . "no' value='No'><label for='field" . $i . "no'>No</label>"; }
						elsif(to_int($customform[($i*2)+3]) == 5) { print "<input type='radio' name='field" . $i . "' id='field" . $i . "true' value='True'><label for='field" . $i . "true'>True</label> &nbsp; <input type='radio' name='field" . $i . "' id='field" . $i . "false' value='False'><label for='field" . $i . "false'>False</label>"; }
						elsif(to_int($customform[($i*2)+3]) == 6) { print "<input type='email' class='form-control' name='field" . $i . "'>"; }
						elsif(to_int($customform[($i*2)+3]) == 7) { print "<select class='form-control' name='field" . $i . "'><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option><option>6</option><option>7</option><option>8</option><option>9</option><option>10</option></select>"; }
						elsif(to_int($customform[($i*2)+3]) == 8) { print "<input type='text' class='form-control' name='field" . $i . "' value='" . $ENV{REMOTE_ADDR} . "' readonly>"; }
						elsif(to_int($customform[($i*2)+3]) == 9) { print "<select class='form-control' name='field" . $i . "'><option>Extremely</option><option>A lot</option><option>Moderately</option><option>Slightly</option><option>Not at all</option></select>"; }
						else { print "<input type='text' class='form-control' name='field" . $i . "'>"; }
						print "</div></div></p>";
					}
				}
			}
			else
			{
				print "<p><input class='form-control' placeholder='Ticket title' type='text' name='ticket_title' maxlength='99'></p>\n";
				print "<p><textarea placeholder='Description' class='form-control' name='ticket_desc' rows='5'></textarea></p>\n";
				if($cfg->load('custom_type') eq "Checkbox") { print "<p>" . $cfg->load('custom_name') . ": <input type='checkbox' name='ticket_link'></p>\n"; }
				else { print "<p><input placeholder=\"" . $cfg->load('custom_name') . "\" type='text' name='ticket_link' class='form-control'></p>\n"; }
			}
			print "<input type='hidden' name='m' value='add_ticket'><input class='btn btn-primary pull-right' type='submit' value='Create ticket'></form></div></div>\n";
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
		}
		else
		{
			msg($items{"Product"} . " not found. Please go back and try again.", 0);
		}
	}
	elsif($q->param('m') eq "confirm_delete" && $logged_user eq $cfg->load("admin_name") && ($q->param('productid') || $q->param('ticketid')))
	{
		headers("Confirm");
		if($q->param('yes'))
		{
			if($q->param('productid'))
			{
				$sql = $db->prepare("SELECT ROWID FROM tickets WHERE productid = ?;");
				$sql->execute(to_int($q->param('productid')));
				while(my @res = $sql->fetchrow_array())
				{
					my $sql2 = $db->prepare("DELETE FROM comments WHERE ticketid = ?;");
					$sql2->execute(to_int($res[0]));				
				}
				$sql = $db->prepare("DELETE FROM tickets WHERE productid = ?;");
				$sql->execute(to_int($q->param('productid')));
				$sql = $db->prepare("DELETE FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('productid')));
				$sql = $db->prepare("DELETE FROM autoassign WHERE productid = ?;");
				$sql->execute(to_int($q->param('productid')));
				$sql = $db->prepare("DELETE FROM products WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('productid')));
				logevent("Product deleted: " . to_int($q->param('productid')));
				msg($items{"Product"} . " " . to_int($q->param('productid')) . " and associated tickets deleted. Press <a href='./?m=products'>here</a> to continue.", 3);
			}
			else
			{
				$sql = $db->prepare("DELETE FROM tickets WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('ticketid')));
				$sql = $db->prepare("DELETE FROM comments WHERE ticketid = ?;");
				$sql->execute(to_int($q->param('ticketid')));
				logevent("Ticket deleted: " . to_int($q->param('ticketid')));
				msg("Ticket " . to_int($q->param('ticketid')) . " deleted. Press <a href='./?m=tickets'>here</a> to continue.", 3);
			}
		}
		else
		{
			msg("This operation cannot be undone.", 1);
			print "<p><form method='GET' action='.'><input type='hidden' name='m' value='confirm_delete'><input type='hidden' name='yes' value='1'>";
			if($q->param('productid'))
			{
				print "<input type='hidden' name='productid' value='" . to_int($q->param('productid')) . "'>Are you sure you want to delete product <b>" . to_int($q->param('productid')) . "</b> and all associated tickets?";
			}
			else
			{
				print "<input type='hidden' name='ticketid' value='" . to_int($q->param('ticketid')) . "'>Are you sure you want to delete ticket <b>" . to_int($q->param('ticketid')) . "</b>?";			
			}
			print "<input type='submit' class='btn btn-danger pull-right' value='Confirm'></form></p>";
		}
	}
	elsif($q->param('m') eq "stats" && $q->param('report') && $logged_lvl > 1)
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
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>All time spent per ticket</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Ticket ID</th><th>Hours spent</th></tr>"; }
			$sql = $db->prepare("SELECT * FROM timetracking ORDER BY ticketid;");		
		}
		elsif(to_int($q->param('report')) == 11)
		{
			if($q->param('csv')) { print "\"Ticket ID\",\"Hours spent\"\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Your time spent per ticket</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Ticket ID</th><th>Hours spent</th></tr>"; }
			$sql = $db->prepare("SELECT * FROM timetracking WHERE name == \"$logged_user\" ORDER BY ticketid;");		
		}
		elsif(to_int($q->param('report')) == 3)
		{
			if($q->param('csv')) { print $items{"Product"} . ",Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets created per " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>" . $items{"Product"} . "</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT productid FROM tickets ORDER BY productid;");
		}
		elsif(to_int($q->param('report')) == 13)
		{
			if($q->param('csv')) { print "Article,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets linked per article</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Article</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT DISTINCT kb,ticketid FROM kblink ORDER BY kb;");
		}
		elsif(to_int($q->param('report')) == 10)
		{
			if($q->param('csv')) { print $items{"Product"} . ",Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>New and open tickets per " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>" . $items{"Product"} . "</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT productid FROM tickets WHERE status == 'Open' OR status == 'New' ORDER BY productid;");
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
		elsif(to_int($q->param('report')) == 9)
		{
			if($q->param('csv')) { print "User,Tickets\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets assigned per user</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>User</th><th>Tickets</th></tr>"; }
			$sql = $db->prepare("SELECT name FROM users;");
		}
		elsif(to_int($q->param('report')) == 12)
		{
			if($q->param('csv')) { print "Filename,GUID\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Comment file attachments</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Filename</th><th>GUID</th></tr>"; }
			$sql = $db->prepare("SELECT file,filename FROM comments WHERE file != '';");
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
			elsif(to_int($q->param('report')) == 12)
			{
				$results{$res[1]} = $res[0];
			}
			elsif(to_int($q->param('report')) == 2 || to_int($q->param('report')) == 11)
			{
				if(!$results{$res[0]}) { $results{$res[0]} = 0; }
				$results{$res[0]} += to_float($res[2]);
			}
			elsif(to_int($q->param('report')) == 9)
			{
				my $sql2 = $db->prepare("SELECT COUNT(*) FROM tickets WHERE assignedto LIKE ?;");
				$sql2->execute("%" . $res[0] . "%");
				while(my @res2 = $sql2->fetchrow_array())
				{
					if(to_int($res2[0]) > 0) { $results{$res[0]} = $res2[0]; }
				}
			}
			elsif(to_int($q->param('report')) == 3 || to_int($q->param('report')) == 10)
			{
				if(!$results{$products[to_int($res[0])]}) { $results{$products[to_int($res[0])]} = 0; }
				$results{$products[to_int($res[0])]} ++;
			}
			elsif(to_int($q->param('report')) == 4 || to_int($q->param('report')) == 7 || to_int($q->param('report')) == 8 || to_int($q->param('report')) == 13)
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
		if(to_int($q->param('report')) == 2 || to_int($q->param('report')) == 8 || to_int($q->param('report')) == 11 || to_int($q->param('report')) == 13)
		{
			foreach my $k (sort {$a <=> $b} keys(%results)) # numeric sorting
			{
				if($q->param('csv')) { print "\"" . $k . "\"," . $results{$k} . "\n"; }
				else { print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; }
				$totalresults += to_float($results{$k});
			}
		}
		elsif(to_int($q->param('report')) == 5)
		{
			foreach my $k (sort by_date keys(%results)) # date sorting
			{
				if($q->param('csv')) { print "\"" . $k . "\"," . $results{$k} . "\n"; }
				else { print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; }
				$totalresults += to_float($results{$k});
			}		
		}
		elsif(to_int($q->param('report')) == 6)
		{
			foreach my $k (sort by_month keys(%results)) # month sorting
			{
				if($q->param('csv')) { print "\"" . $k . "\"," . $results{$k} . "\n"; }
				else { print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; }
				$totalresults += to_float($results{$k});
			}		
		}
		else
		{
			foreach my $k (sort(keys(%results))) # alphabetical sorting
			{
				if($q->param('csv')) { print "\"" . $k . "\"," . $results{$k} . "\n"; }
				else { print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; }
				$totalresults += to_float($results{$k});
			}
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
	elsif($q->param('m') eq "unlink_article" && $q->param('articleid') && $q->param('ticketid') && $logged_lvl > 3)
	{
		headers("Articles");
		$sql = $db->prepare("DELETE FROM kblink WHERE ticketid = ? AND kb = ?;");
		$sql->execute(to_int($q->param('ticketid')), to_int($q->param('articleid')));
		msg("Ticket <b>" . to_int($q->param('ticketid')) . "</b> unlinked. Press <a href='./?kb=" . to_int($q->param('articleid')) . "'>here</a> to continue.", 3);
	}
	elsif($q->param('m') eq "tickets" && $cfg->load('comp_tickets') eq "on")
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
			print "<p><div class='row'><div class='col-sm-8'>Select a " . lc($items{"Product"}) . " name: <select class='form-control' name='product_id'>";
			$sql = $db->prepare("SELECT ROWID,* FROM products WHERE vis != 'Archived';");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($logged_lvl > 1 || $res[5] ne "Restricted") { print "<option value=" . $res[0] . ">" . $res[1] . "</option>"; }
			}
			print "</select></div><div class='col-sm-4'><input type='hidden' name='m' value='new_ticket'><input class='btn btn-primary pull-right' type='submit' value='Next'></div></div></p></form></div></div>\n";
		}
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Tickets ";
		if($q->param('filter_product')) { print "(" . $items{"Product"} . ": " . sanitize_alpha($q->param('filter_product')) . ") "; }
		if($q->param('filter_status')) { print "(Status: " . sanitize_alpha($q->param('filter_status')) . ") "; }
		print "(Limit: " . $limit . ") ";
		print "</h3></div><div class='panel-body'>\n";
		print "<p><form method='GET' action='.'><input type='hidden' name='m' value='tickets'>Filter tickets:<div class='row'><div class='col-sm-2'>By status: <select name='filter_status' class='form-control'><option>All</option><option>New</option><option>Open</option><option>Invalid</option><option>Duplicate</option><option>Hold</option><option>Resolved</option><option>Closed</option></select></div><div class='col-sm-4'>By " . lc($items{"Product"}) . ": <select name='filter_product' class='form-control'><option>All</option>";
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { print "<option value=" . $res[0] . ">" . $res[1] . "</option>"; }
		print "</select></div><div class='col-sm-2'>Limit: <select name='filter_limit' class='form-control'><option value='50000'>50,000</option><option value='10000'>10,000</option><option value='5000'>5,000</option><option value='1000' selected>1,000</option><option value='500'>500</option><option value='100'>100</option></select></div><div class='col-sm-4'><span class='pull-right'><input class='btn btn-primary' type='submit' value='Filter'> &nbsp; <input class='btn btn-primary' name='csv' type='submit' value='Export as CSV'></span></div></div></form></p><hr>";
		my $search = "";
		if($q->param('search')) { $search = sanitize_html($q->param('search')); }
		print "<p><form method='GET' action='.'><div class='row'><div class='col-sm-8'>Custom search:<input type='hidden' name='m' value='tickets'><input placeholder='Search terms' class='form-control' type='text' name='search' value='" . $search . "'></div><div class='col-sm-4'> <input class='btn btn-primary pull-right' type='submit' value='Search'></div></div></p>";
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
elsif(($q->param('create_form') || $q->param('edit_form') || $q->param('save_form')) && $logged_lvl > 3)
{
	headers("Settings");
	if($q->param('save_form'))
	{
		if($q->param('form_name') && $q->param('field0') && defined($q->param('product_id')))
		{
			$sql = $db->prepare("UPDATE forms SET productid = 0 WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			if($q->param('save_form') == -1)
			{
				$sql = $db->prepare("INSERT INTO forms VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('form_name')), sanitize_html($q->param('field0')), sanitize_html($q->param('field0type')), sanitize_html($q->param('field1')), sanitize_html($q->param('field1type')), sanitize_html($q->param('field2')), sanitize_html($q->param('field2type')), sanitize_html($q->param('field3')), sanitize_html($q->param('field3type')), sanitize_html($q->param('field4')), sanitize_html($q->param('field4type')), sanitize_html($q->param('field5')), sanitize_html($q->param('field5type')), sanitize_html($q->param('field6')), sanitize_html($q->param('field6type')), sanitize_html($q->param('field7')), sanitize_html($q->param('field7type')), sanitize_html($q->param('field8')), sanitize_html($q->param('field8type')), sanitize_html($q->param('field9')), sanitize_html($q->param('field9type')), now());
			}
			else
			{
				$sql = $db->prepare("UPDATE forms SET productid = ?, formname = ?, field0 = ?, field0type = ?, field1 = ?, field1type = ?, field2 = ?, field2type = ?, field3 = ?, field3type = ?, field4 = ?, field4type = ?, field5 = ?, field5type = ?, field6 = ?, field6type = ?, field7 = ?, field7type = ?, field8 = ?, field8type = ?, field9 = ?, field9type = ?, modified = ? WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('form_name')), sanitize_html($q->param('field0')), sanitize_html($q->param('field0type')), sanitize_html($q->param('field1')), sanitize_html($q->param('field1type')), sanitize_html($q->param('field2')), sanitize_html($q->param('field2type')), sanitize_html($q->param('field3')), sanitize_html($q->param('field3type')), sanitize_html($q->param('field4')), sanitize_html($q->param('field4type')), sanitize_html($q->param('field5')), sanitize_html($q->param('field5type')), sanitize_html($q->param('field6')), sanitize_html($q->param('field6type')), sanitize_html($q->param('field7')), sanitize_html($q->param('field7type')), sanitize_html($q->param('field8')), sanitize_html($q->param('field8type')), sanitize_html($q->param('field9')), sanitize_html($q->param('field9type')), now(), to_int($q->param('save_form')));
			}
			msg("Custom form saved. Press <a href='./?m=settings'>here</a> to continue.", 3);
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('form_name')) { $text .= "<span class='label label-danger'>Form name</span> "; }
			if(!$q->param('field0')) { $text .= "<span class='label label-danger'>Title question</span> "; }
			if(!defined($q->param('product_id'))) { $text .= "<span class='label label-danger'>Product name</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
	}
	else
	{
		print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Custom form</h3></div><div class='panel-body'><form method='POST' action='.'>";
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		my @res;
		if(to_int($q->param('edit_form')) > 0)
		{
			$sql = $db->prepare("SELECT * FROM forms WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('edit_form')));
			@res = $sql->fetchrow_array();
			if(!$res[1]) { msg("Form does not exist.", 0); footers(); exit; }
		}
		print "<input type='hidden' name='save_form' value='";
		if(to_int($q->param('edit_form')) > 0) { print to_int($q->param('edit_form')); }
		else { print "-1"; }
		print "'><p><div class='row'><div class='col-sm-6'>Form name: <input type='text' name='form_name' class='form-control' value='";
		if(to_int($q->param('edit_form')) > 0) { print $res[1]; }
		print "'></div><div class='col-sm-6'>" . $items{"Product"} . " linked to this form: <select class='form-control' name='product_id'>";
		if(to_int($q->param('edit_form')) > 0 && $res[0] == 0) { print "<option value='0' selected>None</option>"; }
		else { print "<option value='0'>None</option>"; }
		for(my $i = 1; $i < scalar(@products); $i++)
		{
			if($products[$i])
			{
				if(to_int($q->param('edit_form')) > 0 && $res[0] == $i) { print "<option value='" . $i . "' selected>" . $products[$i] . "</option>"; }
				else { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; }
			}
		}
		print "</select></div></div></p><table class='table table-striped'><tr><th>Field</th><th>Question</th><th>Answer type</th></tr>";
		for(my $i = 0; $i < 10; $i++)
		{
			print "<tr><td>";
 			if($i == 0) { print "Title"; }
			else { print $i; }
			print "</td><td><input type='text' class='form-control' value='";
			if(to_int($q->param('edit_form')) > 0) { print $res[($i*2)+2] }
			print "' name='field" . $i . "'></td><td><select class='form-control' name='field" . $i . "type'><option value=0";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 0) { print " selected"; } }
			print ">Some text</option><option value=1";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 1) { print " selected"; } }
			print ">Lots of text</option><option value=2";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 2) { print " selected"; } }
			print ">Number</option><option value=3";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 3) { print " selected"; } }
			print ">Checkbox</option><option value=4";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 4) { print " selected"; } }
			print ">Yes / No</option><option value=5";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 5) { print " selected"; } }
			print ">True / False</option><option value=6";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 6) { print " selected"; } }
			print ">Email address</option><option value=7";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 7) { print " selected"; } }
			print ">1 to 10</option><option value=8";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 8) { print " selected"; } }
			print ">IP address</option><option value=9";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 9) { print " selected"; } }
			print ">Satisfaction scale</option></td></tr>";
		}
		print "</table><p><input type='submit' class='btn btn-primary pull-right' value='Save'></p></form></div></div>";
	}
	footers();
}
elsif($q->param('kb') && $cfg->load('comp_articles') eq "on")
{
	headers("Articles");
	my @products;
	$sql = $db->prepare("SELECT ROWID,* FROM products;");
	$sql->execute();
	while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
	$sql = $db->prepare("SELECT ROWID,* FROM kb WHERE ROWID = ?;");
	$sql->execute(to_int($q->param('kb')));
	while(my @res = $sql->fetchrow_array())
	{
		if($logged_lvl > 3 || $res[4] == 1)
		{
			if($res[7] eq "Never") { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'>Created: <i>" . $res[6] . "</i></span>Article " . to_int($q->param('kb')) . "</h3></div><div class='panel-body'>\n"; }
			else { print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'>Last modified: <i>" . $res[7] . "</i></span>Article " . to_int($q->param('kb')) . "</h3></div><div class='panel-body'>\n"; }
			if($logged_lvl > 3)
			{
				print "<form method='POST' action='.'><input type='hidden' name='m' value='save_article'><input type='hidden' name='id' value='" . to_int($q->param('kb')) . "'>\n";
				print "<p><div class='row'><div class='col-sm-6'>Title: <input type='text' maxlength='50' class='form-control' name='title' value='" . $res[2] . "'></div><div class='col-sm-6'>\n";
				if(to_int($res[4]) == 0) { print "Article status: <select name='published' class='form-control'><option value='0' selected>Draft</option><option value='1'>Published</option></select>\n"; }
				else { print "Article status: <select name='published' class='form-control'><option value='0'>Draft</option><option value='1' selected>Published</option></select>\n"; }
				print "</div></div></p><p><div class='row'><div class='col-sm-6'>Applies to: <select class='form-control' name='productid'>";
				if($res[1] == 0) { print "<option value='0' selected>All " . lc($items{"Product"}) . "s</option>"; }
				else { print "<option value='0'>All</option>"; }
				for(my $i = 1; $i < scalar(@products); $i++)
				{
					if($products[$i])
					{
						if($res[1] == $i) { print "<option value='" . $i . "' selected>" . $products[$i] . "</option>"; }
						else { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; }
					}
				}
				print "</select></div></div></p>";
				print "<p>Description:<br><textarea name='article' rows='20' class='form-control'>" . $res[3] . "</textarea></p>\n";
				print "<input type='submit' class='btn btn-primary pull-right' value='Save article'></form>";
			}
			else
			{
				print "<p>Title: <b>" . $res[2] . "</b></p>\n";
				if($res[1] == 0 || !$products[$res[1]]) { print "<p>Applies to: <b>All " . lc($items{"Product"}) . "s</b></p>\n"; }
				else { print "<p>Applies to: <b>" . $products[$res[1]] . "</b></p>\n"; }
				print "<p>Description:<br><pre>" . $res[3] . "</pre></p>\n";
			}
			print "</p></div></div>";
			if($cfg->load('comp_tickets') eq "on")
			{
				print "<div class='panel panel-default'><div class='panel-heading'><h3 class='panel-title'>Active tickets linked to this article</h3></div><div class='panel-body'>\n";
				print "<table class='table table-striped'><tr><th>ID</th><th>Title</th><th>Status</th>";
				if($logged_lvl > 3) { print "<th>Unlink</th>"; }
				print "</tr>\n";
				$sql = $db->prepare("SELECT DISTINCT ticketid FROM kblink WHERE kb = ? ORDER BY ticketid DESC;");
				$sql->execute(to_int($q->param('kb')));
				while(my @res2 = $sql->fetchrow_array())
				{
					my $sql2 = $db->prepare("SELECT title,status ticketid FROM tickets WHERE ROWID = ? AND status != 'Closed';");
					$sql2->execute(to_int($res2[0]));
					while(my @res3 = $sql2->fetchrow_array())
					{
						print "<tr><td>" . $res2[0] . "</td><td><a href='./?m=view_ticket&t=" . $res2[0] . "'>" . $res3[0] . "</a></td><td>" . $res3[1] . "</td>";
						if($logged_lvl > 3) { print "<td><a href='./?m=unlink_article&articleid=" . to_int($q->param('kb')) . "&ticketid=" . $res2[0] . "'>Unlink</a></td>"; }
						print "</tr>\n";
					} 
				}
				print "</table></div></div>\n";
			}
		}
		else
		{
			msg("This article is not available.", 0);
		}
	}
	footers();
}
elsif(!$cfg->load("ad_server") && $q->param('new_name') && $q->param('new_pass1') && $q->param('new_pass2') && ($logged_lvl > 4 || $cfg->load('allow_registrations'))) # Process registration
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
	elsif(length(sanitize_alpha($q->param('new_name'))) < 3 || length(sanitize_alpha($q->param('new_name'))) > 16 || ($q->param('new_email') && length(sanitize_alpha($q->param('new_email'))) > 99) || length($q->param('new_pass1')) < 6)
	{
		msg("User names should be between 3 and 16 characters, passwords should be at least 6 characters, emails less than 99 characters. Please go back and try again.", 0);    
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
			notify(sanitize_alpha($q->param('new_name')), "Email confirmation", "You are receiving this email because a new user was created with this email address. Please confirm your email by logging into the NodePoint interface, and entering the following confirmation code under Settings: " . $confirm);
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
	check_user($q->param('name'), $q->param('pass'));
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
