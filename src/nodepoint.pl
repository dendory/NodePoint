#!/usr/bin/perl
#
# NodePoint - (C) 2014-2016 Patrick Lambert - http://nodepoint.ca
# Provided under the MIT License
#
# To use on Windows: Change all 'Linux' for 'Win32' in this file.
# To compile into a binary: Use PerlApp with the .perlapp file.
#

use strict;
use Config::Linux;
use Digest::SHA qw(sha1_hex);
use DBI;
use CGI '-utf8';;
use Net::SMTP;
use Mail::RFC822::Address qw(valid);
use Data::GUID;
use File::Type;
use Scalar::Util qw(looks_like_number);
use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_CONTROL_PAGED);
use MIME::Base64;
use Time::HiRes qw(time);
use Time::Piece;
use Text::Markdown 'markdown';
use Crypt::RC4;
use utf8;

my ($cfg, $db, $sql, $cn, $cp, $cgs, $last_login, $perf);
my $logged_user = "";
my $logged_lvl = -1;
my $q = new CGI;
my $VERSION = "1.7.4";
my %items = ("Product", "Product", "Release", "Release", "Model", "SKU/Model");
my @itemtypes = ("None");
my @themes = ("primary", "default", "success", "info", "warning", "danger");

$perf = time/100;
$perf = int(($perf - int($perf)) * 100000);

# Print headers
sub headers
{
	my ($page) = @_;
	if($cn && $cp || $cgs)
	{
		if($cn && $cp && $cgs) { print $q->header(-charset => 'UTF-8', -type => "text/html", -cookie => [$cn, $cp, $cgs]); }
		elsif($cgs) { print $q->header(-charset => 'UTF-8', -type => "text/html", -cookie => [$cgs]); }
		else { print $q->header(-charset => 'UTF-8', -type => "text/html", -cookie => [$cn, $cp]); }
	}
	else { print $q->header(-charset => 'UTF-8', -type => "text/html"); }
	print "<!DOCTYPE html>\n";
	print "<html>\n";
	print " <head>\n";
	if($cfg->load("site_name")) { print "  <title>" . $cfg->load("site_name") . " - " . $page . "</title>\n"; }
	else { print "  <title>NodePoint - " . $page . "</title>\n"; }
	print "  <meta charset='utf-8'>\n";
	print "  <meta http-equiv='X-UA-Compatible' content='IE=edge'>\n";
	print "  <meta name='viewport' content='width=device-width, initial-scale=1'>\n";
	print "  <link rel='stylesheet' href='bootstrap.css'>\n";
	print "  <link rel='stylesheet' href='datepicker.css'>\n";
	print "  <link rel='stylesheet' href='fullcalendar.css'>\n";
	print "  <link rel='stylesheet' href='datatables.css'>\n";
	print "  <script src='jquery.js'></script>\n";
	print "  <script src='bootstrap.js'></script>\n";
	print "  <script src='datatables.js'></script>\n";
	if($cfg->load("css_template")) { print "  <link rel='stylesheet' href='" . $cfg->load("css_template") . "'>\n"; }
	if($cfg->load("favicon")) { print "  <link rel='shortcut icon' href='" . $cfg->load("favicon") . "'>\n"; }
	else { print "  <link rel='shortcut icon' href='favicon.gif'>\n"; }
	print " </head>\n";
	print " <body>\n";
	navbar();
	print "  <div class='container'>\n";
	if($cfg->load("motd")) { print "<div class='well'>" . $cfg->load("motd") . "</div>\n"; }
	if($logged_lvl > 5 && $cfg->load('comp_tickets') ne "on" && $cfg->load('comp_articles') ne "on" && $cfg->load('comp_time') ne "on" && $cfg->load('comp_shoutbox') ne "on" && $cfg->load('comp_clients') ne "on" && $cfg->load('comp_items') ne "on" && $cfg->load('comp_steps') ne "on" && $cfg->load('comp_secrets') ne "on" && $cfg->load('comp_files') ne "on") { msg("All components are turned off. Enable the ones you need in Settings.", 1); }
}

# Footers
sub footers
{
	my $perf2 = time/100;
	$perf2 = int(($perf2 - int($perf2)) * 100000); # Store 2.3 digits of current unixtime, to avoid overloading a 32bits int
	my $perf3 = $perf2 - $perf;
	if($perf3 < 0) { $perf3 = ($perf2 + 100000) - $perf; }
	print "  <div style='clear:both'></div><hr><div style='margin-top:-15px;font-size:9px;color:grey'><span class='pull-right'>" . $perf3 . " ms</span><i>NodePoint v" . $VERSION . "</i></div></div>\n";
	print " <script src='validator.js'></script>\n";
	print " <script src='markdown.js'></script>\n";
	print " <script src='datepicker.js'></script>\n";
	print " <script>\$('.datepicker').datepicker();</script>\n";
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
		if($q->param('m') && ($q->param('m') eq "products" || $q->param('m') eq "view_product"))
		{
			print "	 <li><a href='.'>Login</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
		}
		elsif($q->param('m') && ($q->param('m') eq "tickets" || $q->param('m') eq "view_ticket" || $q->param('m') eq "add_ticket" || $q->param('m') eq "new_ticket"))
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
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "products" || $q->param('m') eq "add_product" || $q->param('m') eq "view_product" || $q->param('m') eq "edit_product" || $q->param('m') eq "add_release" || $q->param('m') eq "add_step" || $q->param('m') eq "delete_step" || $q->param('m') eq "delete_release"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li class='active'><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "settings" || $q->param('m') eq "stats" || $q->param('m') eq "auto" || $q->param('m') eq "show_report" || $q->param('m') eq "triggers" || $q->param('m') eq "customforms" || $q->param('m') eq "users" || $q->param('m') eq "log" || $q->param('m') eq "confirm_delete" || $q->param('m') eq "clear_log" || $q->param('m') eq "stats" || $q->param('m') eq "change_lvl" || $q->param('m') eq "files" || $q->param('m') eq "confirm_email" || $q->param('m') eq "reset_pass" || $q->param('m') eq "logout" || $q->param('m') eq "summary" || $q->param('m') eq "routing" || $q->param('m') eq "edit_route") || $q->param('create_form') || $q->param('edit_form') || $q->param('save_form'))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown active'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		elsif($q->param('m') && ($q->param('m') eq "clients" || $q->param('m') eq "add_client" || $q->param('m') eq  "view_client" || $q->param('m') eq  "view_event" || $q->param('m') eq "save_client" || $q->param('m') eq "set_defaults"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li class='active'><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		elsif($q->param('kb') || $q->param('m') && ($q->param('m') eq "articles" || $q->param('m') eq "add_article" || $q->param('m') eq "save_article" || $q->param('m') eq "unlink_article" || $q->param('m') eq "subscribe" || $q->param('m') eq "unsubscribe"))
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li class='active'><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		elsif($q->param('m') && $q->param('m') eq "items")
		{
			print "	 <li><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li class='active'><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		else
		{
			print "	 <li class='active'><a href='.'>Home</a></li>\n";
			print "	 <li><a href='./?m=products'>" . $items{"Product"} . "s</a></li>\n";
			if($cfg->load('comp_tickets') eq "on") { print "	 <li><a href='./?m=tickets'>Tickets</a></li>\n"; }
			if($cfg->load('comp_articles') eq "on") { print "	 <li><a href='./?m=articles'>Articles</a></li>\n"; }
			if($cfg->load('comp_items') eq "on") { print "	 <li><a href='./?m=items'>Items</a></li>\n"; }
			if($cfg->load('comp_clients') eq "on") { print "	 <li><a href='./?m=clients'>Clients</a></li>\n"; }
			print "  <li class='dropdown'><a href='#' class='dropdown-toggle' data-toggle='dropdown' role='button' aria-haspopup='true' aria-expanded='false'>Tools <span class='caret'></span></a><ul class='dropdown-menu'>\n";
			print "   <li><a href='./?m=settings'>Settings</a></li>\n";
			if($logged_lvl >= to_int($cfg->load("report_lvl"))) { print "   <li><a href='./?m=stats'>Statistics</a></li>\n"; }
			if($cfg->load('comp_files') eq "on") { print "   <li><a href='./?m=files'>Files</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("auto_lvl"))) { print "   <li><a href='./?m=auto'>Automation</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=customforms'>Custom forms</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")	{ print "   <li><a href='./?m=routing'>Ticket routing</a></li>\n"; }
			if($logged_lvl >= to_int($cfg->load("summary_lvl"))) { print "   <li><a href='./?m=users'>Users management</a></li>\n"; }
			if($logged_lvl > 5) { print "   <li><a href='./?m=log'>System log</a></li>\n"; }
			print "  <li role='separator' class='divider'></li><li><a href='./?m=logout'>Logout</a></li></ul></li>\n";
		}
		if($logged_lvl > 0 && ($cfg->load('comp_tickets') eq "on" || $cfg->load('comp_articles') eq "on" || $cfg->load('comp_items') eq "on" || $cfg->load('comp_clients') eq "on")) 
		{
			print "   <form class='navbar-form navbar-right' method='GET' action='./' data-toggle='validator' role='form'>";
			print "    <div class='form-group'>";
			print "     <input type='text' placeholder='Search query' style='-moz-appearance:textfield;-webkit-appearance:none;' name='q' class='form-control' data-minlength='2' maxlength='20' required><input type='hidden' name='m' value='search'>";
			print "    </div>";
			print "    <button type='submit' class='btn btn-primary'>Go</button>";
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
	if($code == 0) { print "<div class='alert alert-danger' role='alert'><span class='glyphicon glyphicon-remove' aria-hidden='true'></span> <span class='sr-only'>Error:</span> " . $text . "</div>\n"; }
	elsif($code == 2) { print "<div class='alert alert-info' role='alert'><span class='glyphicon glyphicon-info-sign' aria-hidden='true'></span> <span class='sr-only'>Info:</span> " . $text . "</div>\n"; }
	elsif($code == 3) { print "<div class='alert alert-success' role='alert'><span class='glyphicon glyphicon-ok' aria-hidden='true'></span> <span class='sr-only'>Success:</span> " . $text . "</div>\n"; }
	else { print "<div class='alert alert-warning' role='alert'><span class='glyphicon glyphicon-warning-sign' aria-hidden='true'></span> <span class='sr-only'>Warning:</span> " . $text . "</div>\n"; }
}

# Login form
sub login
{
	print "<center><div class='row'>";
	if($cfg->load("logo") ne "") { print "<p><img style='max-width:99%' src=\"" . $cfg->load("logo") . "\"></p>"; }
	if(!$cfg->load('allow_registrations') || $cfg->load('allow_registrations') eq 'off' || $cfg->load('ad_domain'))
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
	if($cfg->load('allow_registrations') && $cfg->load('allow_registrations') ne 'off' && !$cfg->load('ad_domain'))
	{
		print "</div><div class='col-sm-6'><h3>Register a new account</h3><form data-toggle='validator' role='form' method='POST' action='.'><div class='form-group'>\n";
		print "<p><input type='text' name='new_name' placeholder='User name' class='form-control' data-error='User name must be between 3 and 50 letters or numbers.' data-minlength='3' maxlength='50' required></p>\n";
		print "<p><input type='password' name='new_pass1' placeholder='Password' data-minlength='6' class='form-control' id='new_pass1' required></p>\n";
		print "<p><input type='password' name='new_pass2' class='form-control' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm' required></p>\n";
		print "<p><input type='email' name='new_email' placeholder='Email (optional)' class='form-control' data-error='Must be a valid email.' maxlength='99'></p>\n";
		print "<div class='help-block with-errors'></div></div>";
		print "<p><input class='btn btn-primary' type='submit' value='Register'></p></form>\n";
	}
	print "</div></div>";
	if($cfg->load("smtp_server") && !$cfg->load("ad_domain") && !$cfg->load("auth_plugin"))
	{
		print "<p style='font-size:12px'><a href='./?m=lostpass'>Forgot your password?</a></p>";
	}
	print "</center>\n";
}

# Sanitize functions
sub sanitize_html
{
	my ($text) = @_;
	if(defined($text))
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
	if(defined($text))
	{
		$text =~ s/[^A-Za-z0-9\.\-\_\@]//g;
		return $text;
	}
	else { return ""; }
}

sub sanitize_email
{
	my ($text) = @_;
	if(defined($text))
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
	$sql = $db->prepare("SELECT * FROM subscribe WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE subscribe (user TEXT, articleid INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM shoutbox WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE shoutbox (user TEXT, msg TEXT, created TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM steps WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE steps (productid INT, name TEXT, user TEXT, completion INT, due TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM steps_log WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE steps_log (productid INT, user TEXT, event TEXT, date TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM clients WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE clients (name TEXT, status TEXT, contact TEXT, notes TEXT, modified TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM items WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE items (name TEXT, type TEXT, serial TEXT, productid INT, clientid INT, approval INT, status INT, user TEXT, info TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM checkouts WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE checkouts (itemid INT, user TEXT, event TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM billing WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE billing (ticketid INT, client TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM billing_defaults WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE billing_defaults (client TEXT, type INT, currency TEXT, cost REAL);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM lostpass WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE lostpass (user TEXT, code TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM disabled WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE disabled (user TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM default_form WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE default_form (form INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM sessions WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE sessions (user TEXT, session TEXT, ip TEXT, expire INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM item_expiration WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE item_expiration (itemid INT, date TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM files WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE files (user TEXT, file TEXT, filename TEXT, time TEXT, size INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM files_product WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE files_product (productid INT, file TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM file_access WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE file_access (ip TEXT, file TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM events WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE events (clientid INT, user TEXT, type TEXT, summary TEXT, notes TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM auto WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE auto (timestamp INT, result TEXT);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto VALUES (0, '');");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM auto_modules WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE auto_modules (name TEXT, enabled INT, lastrun TEXT, timestamp INT, result TEXT, description TEXT, schedule INT);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Backup', 0, 'Never', 0, '', \"This module allows you to backup the database along with the uploads folder to another location for safe keeping. The folder must be a local or network path, and the type of backup can be a single archive file or a series of time stamped files.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Email to Ticket', 0, 'Never', 0, '', \"This module can fetch emails from an IMAP account and turn them into tickets automatically. The mail server and inbox information must be provided in order to log in, along with information about the ticket to create, and whether to delete the email afterward.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Bulk export', 0, 'Never', 0, '', \"This module will export a specific table to a file location automatically in CSV format. Specify the full path of a local file and the table to export.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Users sync', 0, 'Never', 0, '', \"This module can keep the internal users list in sync with your Active Directory server. This requires credentials of a user with object listing rights. The Base DN should be the OU where your users are kept, and the filter can be used to filter specific object types. Emails can optionally be updated for all users as well.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Computers sync', 0, 'Never', 0, '', \"This module will list computer objects from your Active Directory server and create entries in the Inventory Control component. The Base DN should be the OU where your computers are kept. The serial will be set to the machine's hostname. This requires credentials of a user with object listing rights.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Ticket expiration', 0, 'Never', 0, '', \"This module interacts with active tickets that were modified more than x days ago. It can notify assigned users, and close the ticket.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('File expiration', 0, 'Never', 0, '', \"This module can remove files uploaded using the Files component after a set amount of days.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Reminder notifications', 0, 'Never', 0, '', \"This module will notify users about expired items checked out, overdue tasks and tickets requiring attention.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('ServiceNow CMDB', 0, 'Never', 0, '', \"This module can import CMDB data from a ServiceNow instance and import the data into the Inventory Control component. You need to enter valid credentials and the name of the table to read, along with the table header mappings.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Update MOTD', 0, 'Never', 0, '', \"This module will dynamically update the MOTD from a text file.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('Log export', 0, 'Never', 0, '', \"This module will export the system log, access log and automation log to a CSV file, and optionally clear the logs afterward.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('CSV inventory', 0, 'Never', 0, '', \"This module will import items from a CSV file. You must specify the file name and the column mappings.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('CSV projects', 0, 'Never', 0, '', \"This module fetches projects, releases and auto-assignments from a CSV file. You must specific column mappings and whether current assignments should be overwritten. The CSV should contain one line per release. Assignments must be comma separated usernames. Non-existent projects or releases will be created.\", 0);");
		$sql->execute();
		$sql = $db->prepare("INSERT INTO auto_modules VALUES ('ODBC inventory', 0, 'Never', 0, '', \"This module will connect to an ODBC database using the specified DSN or connection string and the credentials provided. You also need to supply the column numbers (in order retrieved by a SELECT statement, starting at 0) to map against the inventory component.\", 0);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM auto_log WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE auto_log (module TEXT, event TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM auto_config WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE auto_config (module TEXT, key TEXT, value TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM secrets WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE secrets (productid INT, user TEXT, note TEXT, account TEXT, secret TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM secrets_log WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE secrets_log (productid INT, user TEXT, account TEXT, event TEXT, time TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM routing WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE routing (name TEXT, priority INT, hits INT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM routing_conditions WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE routing_conditions (route INT, key TEXT, value TEXT);");
		$sql->execute();
	};
	$sql->finish();
	$sql = $db->prepare("SELECT * FROM routing_actions WHERE 0 = 1;") or do
	{
		$sql = $db->prepare("CREATE TABLE routing_actions (route INT, key TEXT, value TEXT);");
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
	$cfg->save("enc_key", sanitize_html($q->param('enc_key')));
	$cfg->save("db_address", sanitize_html($q->param('db_address')));
	$cfg->save("admin_name", sanitize_alpha($q->param('admin_name')));
	if($q->param("admin_pass")) { $cfg->save("admin_pass", sha1_hex($q->param('admin_pass'))); }
	$cfg->save("site_name", sanitize_html($q->param('site_name')));
	$cfg->save("motd", sanitize_html($q->param('motd')));
	$cfg->save("email_sig", sanitize_html($q->param('email_sig')));
	$cfg->save("css_template", sanitize_html($q->param('css_template')));
	$cfg->save("favicon", sanitize_html($q->param('favicon')));
	$cfg->save("logo", sanitize_html($q->param('logo')));
	$cfg->save("default_vis", $q->param('default_vis'));
	$cfg->save("hide_close", $q->param('hide_close'));
	$cfg->save("disable_gs", $q->param('disable_gs'));
	$cfg->save("article_html", $q->param('article_html'));
	$cfg->save("default_lvl", to_int($q->param('default_lvl')));
	$cfg->save("tasks_lvl", to_int($q->param('tasks_lvl')));
	$cfg->save("summary_lvl", to_int($q->param('summary_lvl')));
	$cfg->save("auto_lvl", to_int($q->param('auto_lvl')));
	$cfg->save("add_secrets", to_int($q->param('add_secrets')));
	$cfg->save("view_secrets", to_int($q->param('view_secrets')));
	$cfg->save("upload_lvl", to_int($q->param('upload_lvl')));
	$cfg->save("upload_exts", sanitize_html($q->param('upload_exts')));
	$cfg->save("page_len", to_int($q->param('page_len')));
	$cfg->save("max_size", to_int($q->param('max_size')));
	$cfg->save("session_expiry", to_int($q->param('session_expiry')));
	$cfg->save("past_lvl", to_int($q->param('past_lvl')));
	$cfg->save("customs_lvl", to_int($q->param('customs_lvl')));
	$cfg->save("client_lvl", to_int($q->param('client_lvl')));
	$cfg->save("events_lvl", to_int($q->param('events_lvl')));
	$cfg->save("report_lvl", to_int($q->param('report_lvl')));
	$cfg->save("allow_registrations", $q->param('allow_registrations'));
	$cfg->save("need_assign", $q->param('need_assign'));
	$cfg->save("guest_tickets", $q->param('guest_tickets'));
	$cfg->save("smtp_server", sanitize_html($q->param('smtp_server')));
	$cfg->save("smtp_port", to_int($q->param('smtp_port')));
	$cfg->save("smtp_from", sanitize_html($q->param('smtp_from')));
	$cfg->save("smtp_user", sanitize_html($q->param('smtp_user')));
	$cfg->save("api_write", sanitize_html($q->param('api_write')));
	$cfg->save("smtp_pass", encode_base64(RC4($cfg->load("enc_key"), $q->param('smtp_pass'))));
	$cfg->save("api_read", sanitize_html($q->param('api_read')));
	$cfg->save("api_imp", $q->param('api_imp'));
	$cfg->save("theme_color", $q->param('theme_color'));
	$cfg->save("upload_folder", sanitize_html($q->param('upload_folder')));
	$cfg->save("items_managed", $q->param('items_managed'));
	$cfg->save("ext_plugin", sanitize_html($q->param('ext_plugin')));
	$cfg->save("auth_plugin", sanitize_html($q->param('auth_plugin')));
	$cfg->save("checkout_plugin", sanitize_html($q->param('checkout_plugin')));
	$cfg->save("task_plugin", sanitize_html($q->param('task_plugin')));
	$cfg->save("ticket_plugin", sanitize_html($q->param('ticket_plugin')));
	$cfg->save("newticket_plugin", sanitize_html($q->param('newticket_plugin')));
	$cfg->save("ad_server", sanitize_html($q->param('ad_server')));
	$cfg->save("ad_domain", sanitize_html($q->param('ad_domain')));
	$cfg->save("comp_tickets", $q->param('comp_tickets'));
	$cfg->save("comp_articles", $q->param('comp_articles'));
	$cfg->save("comp_time", $q->param('comp_time'));
	$cfg->save("comp_shoutbox", $q->param('comp_shoutbox'));
	$cfg->save("pinned_article", to_int($q->param('pinned_article')));
	$cfg->save("comp_billing", $q->param('comp_billing'));
	$cfg->save("comp_steps", $q->param('comp_steps'));
	$cfg->save("comp_secrets", $q->param('comp_secrets'));
	$cfg->save("comp_clients", $q->param('comp_clients'));
	$cfg->save("comp_items", $q->param('comp_items'));
	$cfg->save("comp_files", $q->param('comp_files'));
}

# Check login credentials
sub check_user
{
	my ($n, $p) = @_;
	my $session = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
	if(sha1_hex($p) eq $cfg->load("admin_pass") && lc($n) eq lc($cfg->load("admin_name")))
	{
		$logged_user = $cfg->load("admin_name");
		$logged_lvl = 6;
		$cn = $q->cookie(-name => "np_name", -value => $logged_user);
		$cp = $q->cookie(-name => "np_key", -value => $session);
		$sql = $db->prepare("DELETE FROM sessions WHERE user = ?;");
		$sql->execute($logged_user);
		$sql = $db->prepare("INSERT INTO sessions VALUES (?, ?, ?, ?);");
		$sql->execute($logged_user, $session, $q->remote_addr, to_int(time+to_int($cfg->load('session_expiry'))*3600));
	}
	else
	{
		$sql = $db->prepare("SELECT * FROM disabled WHERE user = ? COLLATE NOCASE;");
		$sql->execute(sanitize_alpha($n));
		while(my @res = $sql->fetchrow_array())
		{
			return;
		}
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
				$logged_user = lc($n);
				$logged_lvl = $cfg->load("default_lvl");
				$cn = $q->cookie(-name => "np_name", -value => $logged_user);
				$cp = $q->cookie(-name => "np_key", -value => $session);
				$sql = $db->prepare("DELETE FROM sessions WHERE user = ?;");
				$sql->execute($logged_user);
				$sql = $db->prepare("INSERT INTO sessions VALUES (?, ?, ?, ?);");
				$sql->execute($logged_user, $session, $q->remote_addr, to_int(time+to_int($cfg->load('session_expiry'))*3600));
				$sql = $db->prepare("SELECT * FROM users WHERE name = ? COLLATE NOCASE;");
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
					$sql->execute($logged_user, "*********", "", to_int($cfg->load('default_lvl')), now(), "");
				}
				else
				{
					$sql = $db->prepare("UPDATE users SET loggedin = ? WHERE name = ?;");
					$sql->execute(now(), $logged_user);
				}
			}; # check silently since headers may not be set			
		}
		elsif($cfg->load('auth_plugin'))
		{
			eval
			{
				my $cmd = $cfg->load('auth_plugin');
				$cmd =~ s/\%user\%/\"$n\"/g;
				$cmd =~ s/\%pass\%/\"$p\"/g;
				$cmd =~ s/\n/ /g;
				$cmd =~ s/\r/ /g;
				system($cmd);
				if ($? != 0)
				{
					logevent("AUTH: [" . $? . "] " . $!);
					return; 
				}
				$logged_user = lc($n);
				$logged_lvl = $cfg->load("default_lvl");
				$cn = $q->cookie(-name => "np_name", -value => $logged_user);
				$cp = $q->cookie(-name => "np_key", -value => $session);
				$sql = $db->prepare("DELETE FROM sessions WHERE user = ?;");
				$sql->execute($logged_user);
				$sql = $db->prepare("INSERT INTO sessions VALUES (?, ?, ?, ?);");
				$sql->execute($logged_user, $session, $q->remote_addr, to_int(time+to_int($cfg->load('session_expiry'))*3600));
				$sql = $db->prepare("SELECT * FROM users WHERE name = ? COLLATE NOCASE;");
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
					$sql->execute($logged_user, "*********", "", to_int($cfg->load('default_lvl')), now(), "");
				}
				else
				{
					$sql = $db->prepare("UPDATE users SET loggedin = ? WHERE name = ?;");
					$sql->execute(now(), $logged_user);
				}
			};
		}
		else
		{
			eval
			{
				$sql = $db->prepare("SELECT * FROM users;");
				$sql->execute();
				while(my @res = $sql->fetchrow_array())
				{
					if(sha1_hex(rtrim($p)) eq $res[1] && lc($n) eq lc($res[0]))
					{
						$logged_user = $res[0];
						$logged_lvl = to_int($res[3]);
						$last_login = $res[4];
						$sql = $db->prepare("UPDATE users SET loggedin = ? WHERE name = ?;");
						$sql->execute(now(), $res[0]);
						$cn = $q->cookie(-name => "np_name", -value => $logged_user);
						$cp = $q->cookie(-name => "np_key", -value => $session);
						$sql = $db->prepare("DELETE FROM sessions WHERE user = ?;");
						$sql->execute($logged_user);
						$sql = $db->prepare("INSERT INTO sessions VALUES (?, ?, ?, ?);");
						$sql->execute($logged_user, $session, $q->remote_addr, to_int(time+to_int($cfg->load('session_expiry'))*3600));
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
					if($cfg->load('smtp_user') && $cfg->load('smtp_pass')) { $smtp->auth($cfg->load('smtp_user'), RC4($cfg->load("enc_key"), decode_base64($cfg->load('smtp_pass')))); }
					$smtp->mail($cfg->load('smtp_from'));
					if($smtp->to($res[2]))
					{
						$smtp->data();
						$smtp->datasend("From: " . $cfg->load('smtp_from') . "\n");
						$smtp->datasend("To: " . $res[2] . "\n");
						$smtp->datasend("Subject: " . $cfg->load('site_name') . " - " . $title . "\n");
						$smtp->datasend("Content-Transfer-Encoding: 8bit\n");
						$smtp->datasend("Content-type: text/plain; charset=UTF-8\n\n");
						if($cfg->load('email_sig')) { $smtp->datasend($mesg . "\n\n" . $cfg->load('email_sig') . "\n"); }
						else { $smtp->datasend($mesg . "\n\nThis is an automated message from " . $cfg->load('site_name') . ". To disable notifications, log into your account and remove the email under Settings.\n"); }
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
		$sql->execute(lc($logged_user), to_int($q->param('delete_notify')));
	}

	if($logged_lvl > 3 && $cfg->load('comp_items') eq "on")
	{
		my $apprcount = 0;
		$sql = $db->prepare("SELECT COUNT(*) FROM items WHERE status = 2;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $apprcount = int($res[0]); }
		if($apprcount > 0) { msg("There are <b>" . $apprcount . "</b> items awaiting checkout approval. Press <a href='./?m=items'>here</a> to view the list.", 2); }
	}

	if($logged_user ne "")
	{
		$sql = $db->prepare("SELECT DISTINCT ticketid FROM escalate WHERE user = ?;");
		$sql->execute(lc($logged_user));
		while(my @res = $sql->fetchrow_array()) { msg("<span class='pull-right'><a href='./?delete_notify=" . $res[0] . "'>Clear</a></span>Ticket <a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[0] . "</a> requires your attention.", 2); }
	}

	if(!$q->cookie('np_gs') && $cfg->load('disable_gs') ne "on")
	{
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Getting started</h3></div><div class='panel-body'>\n";
		print "<p>Use the <b>" . $items{"Product"} . "s</b> tab to browse available " . lc($items{"Product"}) . "s along with their " . lc($items{"Release"}) . "s. You can view basic information about them and see their description.";
		if($cfg->load('comp_tickets') eq "on") { print " Use the <b>Tickets</b> tab to browse current tickets and comments."; }
		if($cfg->load('comp_articles') eq "on") { print " The <b>Articles</b> tab contains related support articles."; }
		if($cfg->load('comp_items') eq "on") { print " The <b>Items</b> tab contains inventory items you can checkout."; }
		if($cfg->load('comp_clients') eq "on") { print " The <b>Clients</b> tab contains a list of contacts."; }
		print " You can also change your email address and password under the <b>Settings</b> tab.</p>\n";
		print "<p>Your current access level is <b>" . $logged_lvl . "</b>.</p>\n";
		$sql = $db->prepare("SELECT * FROM users;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($res[0] eq $logged_user && $res[2] ne "" && $res[5] ne "" && $cfg->load('smtp_server'))
			{
				print "<p>Your email address is not currently confirmed. Make sure you go to the Settings tab to enter your confirmation code. You can also change your email address if you did not receive your confirmation email.</p>\n";
			}
		}
		print "</div></div>\n";
	}

	if($logged_user ne "" && $cfg->load('comp_shoutbox') eq "on")
	{
		if($q->param('shoutbox_post'))
		{
			$sql = $db->prepare("INSERT INTO shoutbox VALUES (?, ?, ?);");
			$sql->execute($logged_user, sanitize_html($q->param('shoutbox_post')), now());
		}
		if($q->param('shoutbox_delete') && $logged_lvl > 4)
		{
			$sql = $db->prepare("DELETE FROM shoutbox WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('shoutbox_delete')));		
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Shoutbox</h3></div><div class='panel-body'><div style='max-height:200px;overflow-y:scroll'><table class='table table-striped'>\n";
		$sql = $db->prepare("SELECT ROWID,* FROM shoutbox ORDER BY ROWID DESC LIMIT 30");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><th>" . $res[1] . "</th><td style='width:99%'>";
			if($logged_lvl > 4) { print "<span class='pull-right'><form method='POST' action='.'><input type='hidden' name='shoutbox_delete' value='" . $res[0] . "'><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Really remove this entry?\");' value='X'></form></span>"; }
			print $res[2] . "</td></tr>";
		}
		print "</table></div><form method='POST' action='.'><div class='row'><div class='col-sm-10'><input maxlength='999' class='form-control' name='shoutbox_post' placeholder='Type your message here'></div><div class='col-sm-2'><input type='submit' value='Post' class='btn btn-primary pull-right'></div></div></form></div></div>\n";
	}

	if($logged_user ne "" && $cfg->load('pinned_article'))
	{
		$sql = $db->prepare("SELECT ROWID,* FROM kb WHERE ROWID = ?;");
		$sql->execute(to_int($cfg->load('pinned_article')));
		while(my @res = $sql->fetchrow_array())
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $res[2] . "</h3></div><div class='panel-body'>\n";
			print "<p>" . markdown($res[3]) . "</p>";
			print "</div></div>\n";		
		}
	}

	if($logged_lvl > 0 && $cfg->load('comp_tickets') eq "on")
	{
		$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status != 'Closed' AND createdby = ?");
		$sql->execute($logged_user);
		my $count1 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count1 = to_int($res[0]); }
		if($count1 > 0)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets you created</h3></div><div class='panel-body'><table class='table table-striped' id='home1_table'>\n";
			print "<thead><tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Last modified</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC LIMIT 5000");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($products[$res[1]] && $res[3] eq $logged_user) 
				{ 
					print "<tr><td><nobr>";
					if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
					elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
					else { print "<img src='icons/normal.png' title='Normal'> "; }
					print $res[0] . "</nobr></td><td>" . $products[$res[1]] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[12] . "</td></tr>\n"; 
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home1_table').DataTable({'order':[[0,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}
	
	if($cfg->load('comp_tickets') eq "on")
	{
		$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status != 'Closed' AND subscribers LIKE ?");
		$sql->execute("%" . $logged_user . "%");
		my $count2 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count2 = to_int($res[0]); }
		if($count2 > 0)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Favorite tickets</h3></div><div class='panel-body'><table class='table table-striped' id='home2_table'>\n";
			print "<thead><tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Last modified</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC LIMIT 5000;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($products[$res[1]] && $res[10] =~ /\b$logged_user\b/) 
				{ 
					print "<tr><td><nobr>";
					if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
					elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
					else { print "<img src='icons/normal.png' title='Normal'> "; }
					print $res[0] . "</nobr></td><td>" . $products[$res[1]] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[12] . "</td></tr>\n"; 
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home2_table').DataTable({'order':[[0,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}
	
	if($logged_lvl > 2 && $cfg->load('comp_tickets') eq "on")
	{
		$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status != 'Closed' AND assignedto LIKE ?");
		$sql->execute("%" . $logged_user . "%");
		my $count3 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count3 = to_int($res[0]); }
		if($count3 > 0)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets assigned to you</h3></div><div class='panel-body'><table class='table table-striped' id='home3_table'>\n";
			print "<thead><tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Last modified</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC LIMIT 5000;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($products[$res[1]] && $res[4] =~ /\b$logged_user\b/) 
				{ 
					print "<tr><td><nobr>";
					if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
					elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
					else { print "<img src='icons/normal.png' title='Normal'> "; }
					print $res[0] . "</nobr></td><td>" . $products[$res[1]] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[12] . "</td></tr>\n"; 
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home3_table').DataTable({'order':[[0,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}

	if($cfg->load('comp_steps') eq "on")
	{
		if(defined($q->param('set_step')) && defined($q->param('completion')))
		{
			$sql = $db->prepare("UPDATE steps SET completion = ? WHERE user = ? AND ROWID = ?;");
			$sql->execute(to_int($q->param('completion')), $logged_user, to_int($q->param('set_step')));	
			if($cfg->load('task_plugin') && to_int($q->param('completion')) == 100)
			{
				$sql = $db->prepare("SELECT productid,name,due FROM steps WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('set_step')));
				while(my @res = $sql->fetchrow_array())
				{
					my $cmd = $cfg->load('task_plugin');
					my $s0 = $res[0];
					my $s1 = $res[1];
					my $s2 = $res[2];
					$cmd =~ s/\%product\%/\"$s0\"/g;
					$cmd =~ s/\%task\%/\"$s1\"/g;
					$cmd =~ s/\%due\%/\"$s2\"/g;
					$cmd =~ s/\%user\%/\"$logged_user\"/g;
					$cmd =~ s/\n/ /g;
					$cmd =~ s/\r/ /g;
					system($cmd);
				}
			}
			my $p = 0;
			my $stepname = "";
			$sql = $db->prepare("SELECT productid,name FROM steps WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('set_step')));
			while(my @res = $sql->fetchrow_array()) { $p = to_int($res[0]); $stepname = $res[1]; }
			$sql = $db->prepare("INSERT INTO steps_log VALUES (?, ?, ?, ?)");
			$sql->execute($p, $logged_user, "Set completion rate to <i>" . to_int($q->param('completion')) . "%</i> on task <i>" . $stepname . "</i>", now());
		}

		$sql = $db->prepare("SELECT COUNT(*) FROM steps WHERE user = ? AND completion < 100");
		$sql->execute($logged_user);
		my $count4 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count4 = to_int($res[0]); }
		if($count4 > 0)
		{
			my @products;
			$sql = $db->prepare("SELECT ROWID,* FROM products;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tasks assigned to you</h3></div><div class='panel-body'><table class='table table-striped' id='home4_table'>\n";
			print "<thead><tr><th>" . $items{"Product"} . "</th><th>Task</th><th>Due by</th><th>Completion</th><th></th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM steps WHERE user = ? AND completion < 100");
			$sql->execute($logged_user);
			my $m = localtime->strftime('%m');
			my $y = localtime->strftime('%Y');
			my $d = localtime->strftime('%d');
			while(my @res = $sql->fetchrow_array())
			{
				if($products[$res[1]])
				{
					print "<tr><td>" . $products[$res[1]] . "</td><td>" . $res[2] . "</td><td>";
					my @dueby = split(/\//, $res[5]);
					if(to_int($res[4]) == 100) { print "<font color='green'>Completed</font>"; }
					elsif($dueby[2] < $y || ($dueby[2] == $y && $dueby[0] < $m) || ($dueby[2] == $y && $dueby[0] == $m && $dueby[1] < $d)) { print "<font color='red'>Overdue</font>"; }
					else { print $res[5]; }
					print "</td><td><form method='POST' action='.'><input type='hidden' name='set_step' value='" . $res[0] . "'><select name='completion' class='form-control'>";
					if(to_int($res[4]) == 0) { print "<option value='0' selected>0%</option>"; }
					else { print "<option value='0'>0%</option>"; }
					if(to_int($res[4]) == 10) { print "<option value='10' selected>10%</option>"; }
					else { print "<option value='10'>10%</option>"; }
					if(to_int($res[4]) == 20) { print "<option value='20' selected>20%</option>"; }
					else { print "<option value='20'>20%</option>"; }
					if(to_int($res[4]) == 30) { print "<option value='30' selected>30%</option>"; }
					else { print "<option value='30'>30%</option>"; }
					if(to_int($res[4]) == 40) { print "<option value='40' selected>40%</option>"; }
					else { print "<option value='40'>40%</option>"; }
					if(to_int($res[4]) == 50) { print "<option value='50' selected>50%</option>"; }
					else { print "<option value='50'>50%</option>"; }
					if(to_int($res[4]) == 60) { print "<option value='60' selected>60%</option>"; }
					else { print "<option value='60'>60%</option>"; }
					if(to_int($res[4]) == 70) { print "<option value='70' selected>70%</option>"; }
					else { print "<option value='70'>70%</option>"; }
					if(to_int($res[4]) == 80) { print "<option value='80' selected>80%</option>"; }
					else { print "<option value='80'>80%</option>"; }
					if(to_int($res[4]) == 90) { print "<option value='90' selected>90%</option>"; }
					else { print "<option value='90'>90%</option>"; }
					if(to_int($res[4]) == 100) { print "<option value='100' selected>100%</option>"; }
					else { print "<option value='100'>100%</option>"; }
					print "</select></td><td><input type='submit' class='btn btn-primary pull-right' value='Save'></form></td></tr>";
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home4_table').DataTable({'order':[[2,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}

	if($cfg->load('comp_articles') eq "on")
	{
		$sql = $db->prepare("SELECT COUNT(*) FROM subscribe WHERE user = ?");
		$sql->execute($logged_user);
		my $count5 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count5 = to_int($res[0]); }
		if($count5 > 0)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Favorite articles</h3></div><div class='panel-body'><table class='table table-striped' id='home5_table'>\n";
			print "<thead><tr><th>ID</th><th>Title</th><th>Last modified</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT articleid FROM subscribe WHERE user = ?");
			$sql->execute($logged_user);
			while(my @res = $sql->fetchrow_array())
			{
				my $sql2;
				if($logged_lvl > 3) { $sql2 = $db->prepare("SELECT title,modified FROM kb WHERE ROWID = ?"); }
				else { $sql2 = $db->prepare("SELECT title,modified FROM kb WHERE published = 1 AND ROWID = ?"); }
				$sql2->execute($res[0]);
				while(my @res2 = $sql2->fetchrow_array())
				{
					print "<tr><td>" . $res[0] . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res2[0] . "</a></td><td>" . $res2[1] . "</td></tr>\n";
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home5_table').DataTable({'order':[[1,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}

	if($cfg->load('comp_items') eq "on")
	{
		$sql = $db->prepare("SELECT COUNT(*) FROM items WHERE user = ?");
		$sql->execute($logged_user);
		my $count6 = 0;
		while(my @res = $sql->fetchrow_array())	{ $count6 = to_int($res[0]); }
		if($count6 > 0)
		{	
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Checked out items</h3></div><div class='panel-body'><table class='table table-striped' id='home6_table'>\n";
			print "<thead><tr><th>Type</th><th>Name</th><th>Serial</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM items WHERE user = ?;");
			$sql->execute($logged_user);
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[2] . "</td><td><a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . "</a></td><td>";
				if($res[7] == 2) { print "<input type='submit' name='checkin' class='btn btn-default pull-right' value='Waiting approval' disabled>" . $res[3]; }
				else { print "<form method='POST' action='.'><input type='hidden' name='m' value='items'><input type='hidden' name='i' value='" . $res[0] . "'><input type='submit' name='checkin' value='Return' class='btn btn-primary pull-right'>" . $res[3] . "</form>"; }
				print "</td></tr>\n";
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#home6_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
		}
	}
}

#
# Processing connection from here
#

# Connect to config
eval
{
	$cfg = Config::Linux->new("NodePoint", "settings");
};
if(!defined($cfg)) # Can't even use headers() if this fails.
{
	print "Content-type: text/html\n\nError: Could not access " . Config::Linux->type . ". Please ensure NodePoint has the proper permissions.";
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
	eval
	{
		$sql = $db->prepare("SELECT * FROM sessions WHERE session = ? AND ip = ? AND user = ? AND expire > ?;");
		$sql->execute($q->cookie('np_key'), $q->remote_addr, sanitize_alpha($q->cookie('np_name')), to_int(time));
		while(my @res = $sql->fetchrow_array())
		{
			my $sql2 = $db->prepare("SELECT * FROM disabled WHERE user = ? COLLATE NOCASE;");
			$sql2->execute(sanitize_alpha($q->cookie('np_name')));
			while(my @res = $sql2->fetchrow_array())
			{
				return;
			}
			if($res[0] eq $cfg->load("admin_name"))
			{
				$logged_user = $cfg->load("admin_name");
				$logged_lvl = 6;
			}
			else
			{
				$sql2 = $db->prepare("SELECT * FROM users WHERE name = ? COLLATE NOCASE;");
				$sql2->execute($res[0]);
				while(my @res2 = $sql2->fetchrow_array())
				{
					$logged_user = $res2[0];
					$logged_lvl = to_int($res2[3]);
				}
			}
		}
	}; # check silently since headers may not be set
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
	elsif($cfg->load("items_managed") eq "Assets with types and instances")
	{
		$items{"Product"} = "Asset";
		$items{"Model"} = "Type";
		$items{"Release"} = "Instance";
	}
	elsif($cfg->load("items_managed") eq "Projects with types and phases")
	{
		$items{"Product"} = "Project";
		$items{"Model"} = "Type";
		$items{"Release"} = "Phase";
	}
}

# Sanity checks for levels config
if(to_int($cfg->load("past_lvl")) < 1 || to_int($cfg->load("past_lvl")) > 6) { $cfg->save("past_lvl", 5); }
if(to_int($cfg->load("upload_lvl")) < 1 || to_int($cfg->load("upload_lvl")) > 6) { $cfg->save("upload_lvl", 1); }
if(to_int($cfg->load("default_lvl")) < 0 || to_int($cfg->load("default_lvl")) > 5) { $cfg->save("default_lvl", 1); }
if(to_int($cfg->load("report_lvl")) < 1 || to_int($cfg->load("report_lvl")) > 6) { $cfg->save("report_lvl", 2); }
if(to_int($cfg->load("client_lvl")) < 1 || to_int($cfg->load("client_lvl")) > 6) { $cfg->save("client_lvl", 2); }
if(to_int($cfg->load("events_lvl")) < 1 || to_int($cfg->load("events_lvl")) > 6) { $cfg->save("events_lvl", 2); }
if(to_int($cfg->load("customs_lvl")) < 1 || to_int($cfg->load("customs_lvl")) > 6) { $cfg->save("customs_lvl", 4); }
if(to_int($cfg->load("tasks_lvl")) < 1 || to_int($cfg->load("tasks_lvl")) > 6) { $cfg->save("tasks_lvl", 4); }
if(to_int($cfg->load("summary_lvl")) < 1 || to_int($cfg->load("summary_lvl")) > 6) { $cfg->save("summary_lvl", 5); }
if(to_int($cfg->load("auto_lvl")) < 1 || to_int($cfg->load("auto_lvl")) > 6) { $cfg->save("auto_lvl", 5); }
if(to_int($cfg->load("add_secrets")) < 1 || to_int($cfg->load("add_secrets")) > 6) { $cfg->save("add_secrets", 4); }
if(to_int($cfg->load("view_secrets")) < 1 || to_int($cfg->load("view_secrets")) > 6) { $cfg->save("view_secrets", 2); }
if(to_int($cfg->load("page_len")) < 1) { $cfg->save("page_len", 50); }
if(to_int($cfg->load("session_expiry")) < 1) { $cfg->save("session_expiry", 12); }
if(to_int($cfg->load("max_size")) < 1) { $cfg->save("max_size", 999000); }
if(!$cfg->load("enc_key")) { $cfg->save("enc_key", $cfg->load("api_write")); }

# Main loop
if($q->param('site_name') && $q->param('db_address') && $logged_user ne "" && $logged_user eq $cfg->load('admin_name')) # Save config by admin
{
	headers("Settings");
	if($q->param('site_name') && $q->param('db_address') && $q->param('admin_name') && defined($q->param('default_lvl')) && $q->param('default_vis') && $q->param('hide_close') && $q->param('article_html') && $q->param('api_write') && defined($q->param('theme_color')) &&  $q->param('api_imp') && $q->param('api_read') && $q->param('comp_tickets') && $q->param('comp_articles') && $q->param('comp_time') && $q->param('comp_shoutbox') && $q->param('comp_billing') && $q->param('comp_clients') && $q->param('comp_items') && $q->param('comp_files') && $q->param('comp_steps') && $q->param('comp_secrets')) # All required values have been filled out
	{
		# Test database settings
		$db = DBI->connect("dbi:SQLite:dbname=" . $q->param('db_address'), '', '', { RaiseError => 0, PrintError => 0 }) or do { msg("Could not verify database settings. Please hit back and try again.<br><br>" . $DBI::errstr, 0); exit(0); };
		db_check();
		save_config();
		msg("<meta http-equiv='REFRESH' content='1;url=./?m=settings'>Settings updated.", 3);
		logevent("Settings updated");
	}
	else
	{
		my $text = "Some values are missing: ";
		if(!$q->param('admin_name')) { $text .= "<span class='label label-danger'>Admin name</span> "; }
		if(!defined($q->param('default_lvl'))) { $text .= "<span class='label label-danger'>New users access level</span> "; }
		if(!$q->param('default_vis')) { $text .= "<span class='label label-danger'>Ticket visibility</span> "; }
		if(!$q->param('hide_close')) { $text .= "<span class='label label-danger'>Hide closed tickets</span> "; }
		if(!$q->param('disable_gs')) { $text .= "<span class='label label-danger'>Disable Getting Started screen</span> "; }
		if(!$q->param('article_html')) { $text .= "<span class='label label-danger'>Allow HTML in articles</span> "; }
		if(!$q->param('api_read')) { $text .= "<span class='label label-danger'>API read key</span> "; }
		if(!$q->param('api_write')) { $text .= "<span class='label label-danger'>API write key</span> "; }
		if(!$q->param('enc_key')) { $text .= "<span class='label label-danger'>Encryption key</span> "; }
		if(!$q->param('api_imp')) { $text .= "<span class='label label-danger'>Allow user impersonation</span> "; }
		if(!defined($q->param('theme_color'))) { $text .= "<span class='label label-danger'>Interface theme color</span> "; }
		if(!$q->param('comp_tickets')) { $text .= "<span class='label label-danger'>Component: Tickets management</span> "; }
		if(!$q->param('comp_articles')) { $text .= "<span class='label label-danger'>Component: Support articles</span> "; }
		if(!$q->param('comp_time')) { $text .= "<span class='label label-danger'>Component: Time tracking</span> "; }
		if(!$q->param('comp_shoutbox')) { $text .= "<span class='label label-danger'>Component: Shoutbox</span> "; }
		if(!$q->param('comp_billing')) { $text .= "<span class='label label-danger'>Component: Billing</span> "; }
		if(!$q->param('comp_items')) { $text .= "<span class='label label-danger'>Component: Inventory Control</span> "; }
		if(!$q->param('comp_files')) { $text .= "<span class='label label-danger'>Component: Files Management</span> "; }
		if(!$q->param('comp_clients')) { $text .= "<span class='label label-danger'>Component: Clients Directory</span> "; }
		if(!$q->param('comp_steps')) { $text .= "<span class='label label-danger'>Component: Tasks Management</span> "; }
		if(!$q->param('comp_secrets')) { $text .= "<span class='label label-danger'>Component: Secrets Vault</span> "; }
		$text .= " Please go back and try again.";
		msg($text, 0);
	}
	footers();
}
elsif(!$cfg->load("db_address") || !$cfg->load("site_name")) # first use
{
	headers("Initial configuration");
	if($q->param('site_name') && $q->param('db_address') && $q->param('admin_name') && $q->param('admin_pass') && $q->param('default_lvl') && $q->param('default_vis') && $q->param('hide_close') && $q->param('api_write') && $q->param('api_read')) # All required values have been filled out
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
			if(!$q->param('default_lvl')) { $text .= "<span class='label label-danger'>New users access level</span> "; }
			if(!$q->param('default_vis')) { $text .= "<span class='label label-danger'>Ticket visibility</span> "; }
			if(!$q->param('hide_close')) { $text .= "<span class='label label-danger'>Hide closed tickets</span> "; }
			if(!$q->param('api_read')) { $text .= "<span class='label label-danger'>API read key</span> "; }
			if(!$q->param('api_write')) { $text .= "<span class='label label-danger'>API write key</span> "; }
			if(!$q->param('enc_key')) { $text .= "<span class='label label-danger'>Encryption key</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
		else
		{
#			if($q->remote_addr eq "127.0.0.1" || $q->remote_addr eq "::1")
#			{
				msg("Initial configuration not found! Create it now.", 2);
				print "<h3>Initial configuration</h3><p>These settings will be saved in the " . $cfg->type . ". It allows NodePoint to connect to the database and sets various default values.</p>\n";
				print "<form method='POST' action='.'>\n";
				print "<p><div class='row'><div class='col-sm-4'>Database file name:</div><div class='col-sm-4'><input type='text' style='width:300px' name='db_address' value='.." . $cfg->sep . "db" . $cfg->sep . "nodepoint.db'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Site name:</div><div class='col-sm-4'><input style='width:300px' type='text' name='site_name' value='NodePoint'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Favicon:</div><div class='col-sm-4'><input style='width:300px' type='text' name='favicon' value='favicon.gif'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Main page logo:</div><div class='col-sm-4'><input style='width:300px' type='text' name='logo' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Bootstrap template:</div><div class='col-sm-4'><input style='width:300px' type='text' name='css_template' value='default.css'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Interface theme color:</div><div class='col-sm-4'><select style='width:300px' name='theme_color'><option value='0'>Blue</option><option value='1'>Grey</option><option value='2'>Green</option><option value='3'>Cyan</option><option value='4'>Orange</option><option value='5'>Red</option></select></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Ticket visibility:</div><div class='col-sm-4'><select name='default_vis' style='width:300px'><option>Public</option><option>Private</option><option>Restricted</option></select></div></div></p>\n";
				print "<p>Tickets will have a default visibility when created. Public tickets can be seen by people not logged in, while private tickets require people to be logged in to view. Restricted ones can only be seen by authors and users with the <b>2 - Restricted view</b> level, ideal for helpdesk/support portals.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Allow user registrations:</div><div class='col-sm-4'><input type='checkbox' name='allow_registrations' checked=checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Hide closed tickets:</div><div class='col-sm-4'><input type='checkbox' name='hide_close' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Allow guest tickets:</div><div class='col-sm-4'><input type='checkbox' name='guest_tickets'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>New users access level:</div><div class='col-sm-4'><select name='default_lvl' style='width:300px'><option value=5>5 - Users management</option><option value=4>4 - Projects management</option><option value=3>3 - Tickets management</option><option value=2>2 - Restricted view</option><option value=1 selected=selected>1 - Authorized users</option><option value=0>0 - Unauthorized users</option></select></div></div></p>\n";
				print "<p>New registered users will be assigned a default access level, which can then be modified by users with the <b>5 - Users management</b> level. These are the access levels, with each rank having the lower permissions as well:</p>\n";
				print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can manage users, reset passwords, edit clients</td></tr><tr><td>4</td><td>Projects management</td><td>Can add, retire and edit projects, edit articles and items</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create releases, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view restricted tickets and projects</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
				my $key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API read key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_read' value='" . $key . "'></div></div></p>\n";
				$key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>API write key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='api_write' value='" . $key . "'></div></div></p>\n";
				$key = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..32;
				print "<p><div class='row'><div class='col-sm-4'>Encryption key:</div><div class='col-sm-4'><input type='text' style='width:300px' name='enc_key' value='" . $key . "'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Allow user impersonation:</div><div class='col-sm-4'><input type='checkbox' name='api_imp'></div></div></p>\n";
				print "<p>API keys can be used by external applications to read and write tickets using the JSON API.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP server:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_server' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP port:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_port' value='25'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP username:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_user' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>SMTP password:</div><div class='col-sm-4'><input type='password' style='width:300px' name='smtp_pass' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Support email:</div><div class='col-sm-4'><input type='text' style='width:300px' name='smtp_from' value='admin\@company.com'></div></div></p>\n";
				print "<p>If a SMTP server host name is entered, NodePoint will attempt to send an email when new tickets are created, or changes occur.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin username:</div><div class='col-sm-4'><input type='text' style='width:300px' name='admin_name' value='admin'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Admin password:</div><div class='col-sm-4'><input style='width:300px' type='password' name='admin_pass'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Public notice:</div><div class='col-sm-4'><input type='text' style='width:300px' name='motd' value='Welcome to NodePoint. Remember to be courteous when writing tickets. Contact the help desk for any problem.'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Upload folder:</div><div class='col-sm-4'><input type='text' style='width:300px' name='upload_folder' value='.." . $cfg->sep . "uploads'></div></div></p>\n";
				print "<p>The upload folder should be a local folder with write access and is used for product images and comment attachments. If left empty, uploads will be disabled.</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Type of portal:</div><div class='col-sm-4'><select style='width:300px' name='items_managed'><option selected>Products with models and releases</option><option selected>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option><option>Assets with types and instances</option><option>Projects with types and phases</option></select></div></div></p>\n";
				print "<p>To validate logins against an Active Directory domain, enter your domain controller address and domain name (NT4 format) here:</p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Active Directory server:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ad_server' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Active Directory domain:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ad_domain' value=''></div></div></p>\n";
				print "<p>These plugins allow you to extend NodePoint. See the manual for details:</p>";
				print "<p><div class='row'><div class='col-sm-4'>Authentication plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='auth_plugin' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Notifications plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ext_plugin' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Checkout plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='checkout_plugin' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Task completion plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='task_plugin' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>New ticket plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='newticket_plugin' value=''></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Ticket resolution plugin:</div><div class='col-sm-4'><input type='text' style='width:300px' name='ticket_plugin' value=''></div></div></p>\n";
				print "<p>Select which major components of NodePoint you want to activate:</p><p><b>Major components</b></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Tickets Management (Allow users to file tickets against projects and track work done on open issues)</div><div class='col-sm-4'><input type='checkbox' name='comp_tickets' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Support Articles (Create a knowledge base and provide documentation to your users)</div><div class='col-sm-4'><input type='checkbox' name='comp_articles' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Inventory Control (Track your assets, allow users to request item checkout with full approval process)</div><div class='col-sm-4'><input type='checkbox' name='comp_items' checked></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Clients Directory (Create a directory of contacts linked to items, billable tickets, and to track events)</div><div class='col-sm-4'><input type='checkbox' name='comp_clients' checked></div></div></p>\n";
				print "<p><b>Minor components</b></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Time Tracking (Track time spent on individual tickets)</div><div class='col-sm-4'><input type='checkbox' name='comp_time'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Shoutbox (Chat in real time between users)</div><div class='col-sm-4'><input type='checkbox' name='comp_shoutbox'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Tasks Management (Create and assign tasks to your users with completion rates and due dates)</div><div class='col-sm-4'><input type='checkbox' name='comp_steps'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Secrets Vault (Keep credentials or other project related secrets)</div><div class='col-sm-4'><input type='checkbox' name='comp_secrets'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Files Management (Allow users to upload files for clients or suppliers and track downloads)</div><div class='col-sm-4'><input type='checkbox' name='comp_files'></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-4'>Component: Billing (Track billable tickets for your clients and assign fixed or per hour rates)</div><div class='col-sm-4'><input type='checkbox' name='comp_billing'></div></div></p>\n";
				print "<p>See the <a href='./manual.pdf'>manual</a> file for detailed information.<input class='btn btn-primary pull-right' type='submit' value='Save'></p></form>\n"; 
#			}
#			else
#			{
#				msg("Initial configuration not found! It needs to be created from <b>localhost</b> only.", 0);
#			}
		}
		footers();
	}
}
elsif($q->param('api')) # API calls
{
	$logged_user = "api";
	print $q->header(-charset => 'UTF-8', -type => "text/plain");
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
				$res[6] =~ s/\r//g;
				$res[6] =~ s/\n/\\n/g;
				print " \"description\": \"" . $res[6] . "\",\n";
				print " \"priority\": \"" . $res[7] . "\",\n";
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
					$res2[3] =~ s/\r//g;
					$res2[3] =~ s/\n/\\n/g;
					print "   \"comment\": \"" . $res2[3] . "\",\n";
					print "   \"created_on\": \"" . $res2[4] . "\",\n";
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
			print " \"message\": \"Tickets list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"tickets\": [\n";
			my $found = 0;
			if($cfg->load("hide_close") eq "on") { $sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? AND status != 'Closed';"); }
			else { $sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ?;"); }
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
	elsif($q->param('api') eq "list_files")
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
			print " \"message\": \"Files list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"files\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM files;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[1] . "\",\n";
				print "   \"file_name\": \"" . $res[2] . "\",\n";
				print "   \"uploaded_by\": \"" . $res[0] . "\",\n";
				print "   \"uploaded_on\": \"" . $res[3] . "\",\n";
				print "   \"size\": \"" . $res[4] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_products")
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
			print " \"message\": \"Products list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"products\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT ROWID,* FROM products;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[0] . "\",\n";
				print "   \"name\": \"" . $res[1] . "\",\n";
				print "   \"model\": \"" . $res[2] . "\",\n";
				$res[3] =~ s/\r//g;
				$res[3] =~ s/\n/\\n/g;
				print "   \"description\": \"" . $res[3] . "\",\n";
				print "   \"visibility\": \"" . $res[5] . "\",\n";
				print "   \"created\": \"" . $res[6] . "\",\n";
				print "   \"modified\": \"" . $res[7] . "\",\n";
				print "   \"auto_assign\": [\n";
				my $sql2 = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
				$sql2->execute(to_int($res[0]));
				my $found2 = 0;
				while(my @res2 = $sql2->fetchrow_array())
				{
					if($found2) { print ",\n"; }
					$found2 = 1;
					print "    { \"user\": \"" . $res2[0] . "\" }";					
				}
				print "\n   ],\n";
				print "   \"releases\": [\n";
				my $sql2 = $db->prepare("SELECT releasedby,version,notes FROM releases WHERE productid = ?;");
				$sql2->execute(to_int($res[0]));
				my $found2 = 0;
				while(my @res2 = $sql2->fetchrow_array())
				{
					if($found2) { print ",\n"; }
					$found2 = 1;
					print "    {\n";
					print "      \"user\": \"" . $res2[0] . "\",\n";					
					print "      \"version\": \"" . $res2[1] . "\",\n";					
					print "      \"note\": \"" . $res2[2] . "\"\n";
					print "    }";
				}
				print "\n   ]\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "show_billing")
	{
		if(!$q->param('client'))
		{
			print "{\n";
			print " \"message\": \"Missing 'client' argument.\",\n";
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
			my $cost = 10.0;
			my $currency = "USD";
			my $type = 0;
			if($cfg->load('comp_time') eq "on") { $type = 1; }
			$sql = $db->prepare("SELECT type,currency,cost FROM billing_defaults WHERE client = ?;");
			$sql->execute(sanitize_html($q->param('client')));
			while(my @res = $sql->fetchrow_array())
			{
				$type = $res[0];
				$currency = $res[1];
				$cost = $res[2];
			}
			print "{\n";
			print " \"message\": \"Billing.\",\n";
			print " \"status\": \"OK\",\n";
			if($type == 0) { print " \"type\": \"Fixed\",\n"; }
			else { print " \"type\": \"Hourly\",\n"; }
			print " \"currency\": \"" . $currency . "\",\n";
			print " \"cost\": \"" . $cost . "\",\n";
			print " \"billable\": [\n";
			$sql = $db->prepare("SELECT ticketid FROM billing WHERE client = ?;");
			$sql->execute(sanitize_html($q->param('client')));
			my $total = 0;
			my $found = 0;
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"ticket_id\": \"" . $res[0] . "\",\n";
				my $curhours = 0;
				my $sql2 = $db->prepare("SELECT spent FROM timetracking WHERE ticketid = ?;");
				$sql2->execute($res[0]);
				while(my @res2 = $sql2->fetchrow_array())
				{
					$curhours += to_float($res2[0]);
				}
				print "   \"hours\": \"" . $curhours . "\",\n";
				if($cfg->load('comp_time') eq "on" && $type == 1)
				{
					print "   \"cost\": \"" . $curhours * to_float($cost) . "\",\n";
					$total += $curhours * to_float($cost);
				}
				else
				{
					print "   \"cost\": \"" . $cost . "\",\n";
					$total += $cost;
				}
				print "  }";
			}
			print "\n ],\n";
			print " \"total\": \"" . $total . "\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_tasks")
	{
		if(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
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
			print " \"message\": \"Tasks list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"tasks\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM steps WHERE user = ?;");
			$sql->execute(sanitize_alpha($q->param('user')));
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"product_id\": \"" . $res[0] . "\",\n";
				print "   \"description\": \"" . $res[1] . "\",\n";
				print "   \"completion\": \"" . $res[3] . "\",\n";
				print "   \"due\": \"" . $res[4] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "show_time")
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
			print "{\n";
			print " \"message\": \"Time tracking.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"time\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM timetracking WHERE ticketid = ?;");
			$sql->execute(to_int($q->param('id')));
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"name\": \"" . $res[1] . "\",\n";
				print "   \"hours\": \"" . $res[2] . "\",\n";
				print "   \"date\": \"" . $res[3] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_clients")
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
			print " \"message\": \"Clients list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"clients\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT ROWID,* FROM clients;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[0] . "\",\n";
				print "   \"name\": \"" . $res[1] . "\",\n";
				print "   \"status\": \"" . $res[2] . "\",\n";
				print "   \"contact\": \"" . $res[3] . "\",\n";
				print "   \"notes\": \"" . $res[4] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_events")
	{
		if(!$q->param('key'))
		{
			print "{\n";
			print " \"message\": \"Missing 'key' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('client_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'client_id' argument.\",\n";
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
			print " \"message\": \"Events list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"events\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT ROWID,* FROM events WHERE clientid = ?;");
			$sql->execute(to_int($q->param('client_id')));
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[0] . "\",\n";
				print "   \"user\": \"" . $res[2] . "\",\n";
				print "   \"type\": \"" . $res[3] . "\",\n";
				print "   \"summary\": \"" . $res[4] . "\",\n";
				print "   \"notes\": \"" . $res[5] . "\",\n";
				print "   \"date\": \"" . $res[6] . "\"\n";
				print "  }";
			}
			print "\n ]\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "list_items")
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
			print " \"message\": \"Items list.\",\n";
			print " \"status\": \"OK\",\n";
			print " \"items\": [\n";
			my $found = 0;
			$sql = $db->prepare("SELECT ROWID,* FROM items;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				my $expdate = "";
				my $sql3 = $db->prepare("SELECT date FROM item_expiration WHERE itemid = ?;");
				$sql3->execute(to_int($res[0]));
				while(my @res3 = $sql3->fetchrow_array())
				{
					$expdate = $res3[0];
				}
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"id\": \"" . $res[0] . "\",\n";
				print "   \"name\": \"" . $res[1] . "\",\n";
				print "   \"type\": \"" . $res[2] . "\",\n";
				print "   \"serial\": \"" . $res[3] . "\",\n";
				print "   \"product_id\": \"" . $res[4] . "\",\n";
				print "   \"client_id\": \"" . $res[5] . "\",\n";
				print "   \"approval\": \"" . $res[6] . "\",\n";
				print "   \"status\": \"" . $res[7] . "\",\n";
				print "   \"expiration\": \"" . $expdate . "\",\n";
				print "   \"user\": \"" . $res[8] . "\"\n";
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
			$sql = $db->prepare("SELECT name,email,level FROM users;");
			$sql->execute();
			my $found = 0;
			while(my @res = $sql->fetchrow_array())
			{
				if($found) { print ",\n"; }
				$found = 1;
				print "  {\n";
				print "   \"name\": \"" . $res[0] . "\",\n";
				print "   \"access_level\": \"" . $res[2] . "\",\n";
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
					print " \"status\": \"ERR_AD_CONNECTION\"\n";
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
				print " \"status\": \"OK\"\n";
			}
			else
			{
				print " \"message\": \"Invalid credentials.\",\n";
				print " \"status\": \"ERR_INVALID_CRED\"\n";
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
		elsif($cfg->load("ad_domain"))
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
				print " \"status\": \"ERR_INVALID_CRED\"\n";
			}
			else
			{
				$sql = $db->prepare("UPDATE users SET pass = '" . sha1_hex($q->param('password')) . "' WHERE name = ?;");
				$sql->execute(sanitize_alpha($q->param('user')));
				logevent("Password change: " . sanitize_alpha($q->param('user')));
				print " \"message\": \"Password changed.\",\n";
				print " \"status\": \"OK\"\n";
			}
			print "}\n";
		}
	}
	elsif($q->param('api') eq "assign_item")
	{
		if(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
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
			my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
			$sql2->execute(sanitize_alpha($q->param('user')), 3, to_int($q->param('id')));
			$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
			$sql2->execute(to_int($q->param('id')), "api", "Assigned to " . sanitize_alpha($q->param('user')), now());
			$sql2 = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
			$sql2->execute(to_int($q->param('id')));
			while(my @res2 = $sql2->fetchrow_array())
			{
				notify(sanitize_alpha($q->param('user')), "Item assigned to you", "An item has been assigned to you.\n\nItem name: " . $res2[1] . "\nItem type: " . $res2[2] . "\nSerial number: " . $res2[3] . "\nAdditional information: " . $res2[9]);
				if($cfg->load('checkout_plugin'))
				{
					my $cmd = $cfg->load('checkout_plugin');
					my $u = sanitize_alpha($q->param('user'));
					my $s = $res2[3];
					$cmd =~ s/\%user\%/\"$u\"/g;
					$cmd =~ s/\%serial\%/\"$s\"/g;
					$cmd =~ s/\n/ /g;
					$cmd =~ s/\r/ /g;
					system($cmd);
				}					
			}
			print "{\n";
			print " \"message\": \"Item assigned.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "update_ticket")
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
		elsif($q->param('status') && !($q->param('status') eq "New" || $q->param('status') eq "Open" || $q->param('status') eq "Invalid" || $q->param('status') eq "Duplicate" || $q->param('status') eq "Resolved" || $q->param('status') eq "Closed" || $q->param('status') eq "Hold"))
		{
			print "{\n";
			print " \"message\": \"Invalid 'status' value.\",\n";
			print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
			print "}\n";		
		}
		elsif($q->param('priority') && !($q->param('priority') eq "Low" || $q->param('priority') eq "Normal" || $q->param('priority') eq "High"))
		{
			print "{\n";
			print " \"message\": \"Invalid 'priority' value.\",\n";
			print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
			print "}\n";		
		}
		else
		{
			my $from_user = "api";
			if(lc($cfg->load('api_imp')) eq "on" && $q->param('from_user')) { $from_user = sanitize_alpha($q->param('from_user')); }
			my $desc = "";
			my $resolution = "";
			my $priority = "";
			my @us = ();
			my $status = "";
			my $creator = "";
			my $title = "";
			my $timespent = 0;
			$sql = $db->prepare("SELECT * FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('id')));
			while(my @res = $sql->fetchrow_array())
			{
				$desc = $res[5] . "\n\n--- " . now() . " ---\nTicket modified by: " . $from_user . "\n";
				$resolution = $res[8];
				$priority = $res[6];
				$status = $res[7];
				$creator = $res[2];
				$title = $res[4];
				@us = split(' ', $res[3]);
			}
			if($q->param('time_spent'))
			{ 
				$timespent = to_int($q->param('time_spent'));
				if($timespent > 99.99) { $timespent = 99.99; }
				if($timespent < -99.99) { $timespent = -99.99; }
			}
			if($q->param('resolution') && $q->param('resolution') ne $resolution)
			{
				$sql = $db->prepare("UPDATE tickets SET resolution = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_html($q->param('resolution')), to_int($q->param('id')));
				$desc .= "Resolution: \"" . $resolution . "\" => \"" . sanitize_html($q->param('resolution')) . "\"\n";
				$resolution = sanitize_html($q->param('resolution'));
			}
			if($q->param('status') && $q->param('status') ne $status)
			{
				$sql = $db->prepare("UPDATE tickets SET status = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_alpha($q->param('status')), to_int($q->param('id')));
				$desc .= "Status: " . $status . " => " . sanitize_alpha($q->param('status')) . "\n";
				$status = sanitize_alpha($q->param('status'));
			}
			if($q->param('priority') && $q->param('priority') ne $priority)
			{
				$sql = $db->prepare("UPDATE tickets SET link = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_alpha($q->param('priority')), to_int($q->param('id')));
				$desc .= "Priority: " . $priority . " => " . sanitize_alpha($q->param('priority')) . "\n";
				$priority = sanitize_alpha($q->param('priority'));
			}
			if($q->param('summary'))
			{
				if($cfg->load('comp_time') eq "on") {$desc .= "\n[" . $timespent . "] " . sanitize_html($q->param('summary')) . "\n";}
				else {$desc .= "\n" . sanitize_html($q->param('summary')) . "\n";}
			}
			if($cfg->load('comp_time') eq "on" && $timespent != 0)
			{
				$sql = $db->prepare("INSERT INTO timetracking VALUES (?, ?, ?, ?);");
				$sql->execute(to_int($q->param('id')), $from_user, $timespent, now());
			}
			$sql = $db->prepare("UPDATE tickets SET description = ? WHERE ROWID = ?;");
			$sql->execute($desc, to_int($q->param('id')));
			foreach my $u (@us)
			{
				notify($u, "Ticket (" . to_int($q->param('id')) . ") assigned to you has been modified", "The ticket \"" . $title . "\" has been modified:\n\nModified by: " . $from_user . "\nPriority: " . $priority . "\nStatus: " . $status . "\nResolution: " . $resolution . "\nDescription: " . $desc);
			}
			notify($creator, "Your ticket (" . to_int($q->param('id')) . ") has been modified", "The ticket \"" . $title . "\" has been modified:\n\nModified by: " . $from_user . "\nPriority: " . $priority . "\nStatus: " . $status . "\nResolution: " . $resolution . "\nDescription: " . $desc);
			print "{\n";
			print " \"message\": \"Ticket updated.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "assign_ticket")
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
		elsif(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' value.\",\n";
			print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
			print "}\n";		
		}
		else
		{
			my $from_user = "api";
			my $newassign = "";
			my $desc = "";
			my @us = ();
			my $creator = "";
			my $title = "";
			if(lc($cfg->load('api_imp')) eq "on" && $q->param('from_user')) { $from_user = sanitize_alpha($q->param('from_user')); }
			$sql = $db->prepare("SELECT assignedto,description,createdby,title FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('id')));
			while(my @res = $sql->fetchrow_array())
			{
				$newassign = $res[0] . " " . sanitize_alpha($q->param('user'));
				$desc = $res[1] . "\n\n--- " . now() . " ---\nTicket modified by: " . $from_user . "\nAssigned to: " . $res[0] . " => " . $newassign;
				@us = split(' ', $res[0]);
				$creator = $res[2];
				$title = $res[3];
			}
			if($desc ne "")
			{
				$sql = $db->prepare("UPDATE tickets SET assignedto = ?, description = ?, modified = ? WHERE ROWID = ?;");
				$sql->execute($newassign, $desc, now(), to_int($q->param('id')));
				foreach my $u (@us)
				{
					notify($u, "Ticket (" . to_int($q->param('id')) . ") assigned to you has been modified", "The ticket \"" . $title . "\" has been modified:" . $desc);
				}
				notify($creator, "Your ticket (" . to_int($q->param('id')) . ") has been modified", "The ticket \"" . $title . "\" has been modified:" . $desc);
			}
			print "{\n";
			print " \"message\": \"Ticket updated.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "return_item")
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
		elsif($q->param('key') ne $cfg->load('api_write'))
		{
			print "{\n";
			print " \"message\": \"Invalid 'key' value.\",\n";
			print " \"status\": \"ERR_INVALID_KEY\"\n";
			print "}\n";
		}
		else
		{
			my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
			$sql2->execute("", 1, to_int($q->param('id')));
			$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
			$sql2->execute(to_int($q->param('id')), "api", "Returned", now());
			print "{\n";
			print " \"message\": \"Item returned.\",\n";
			print " \"status\": \"OK\"\n";
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
		elsif(length(sanitize_alpha($q->param('user'))) < 3 || length(sanitize_alpha($q->param('user'))) > 50)
		{
			print "{\n";
			print " \"message\": \"Bad length for 'user' argument (between 3 and 50 characters).\",\n";
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
		elsif($cfg->load("ad_domain"))
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
				print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
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
				print " \"user\": \"" . sanitize_alpha($q->param('user')) . "\"\n";
				logevent("Add new user: " . sanitize_alpha($q->param('user')));
			}
			print "}\n";
		}
	}
	elsif($q->param('api') eq "add_event")
	{
		if(!$q->param('summary'))
		{
			print "{\n";
			print " \"message\": \"Missing 'summary' argument.\",\n";
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
		elsif(!$q->param('client_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'client_id' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('type'))
		{
			print "{\n";
			print " \"message\": \"Missing 'type' argument.\",\n";
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
			my $notes = "";
			if($q->param('notes')) { $notes = sanitize_html($q->param('notes')); }
			my $from_user = "api";
			if(lc($cfg->load('api_imp')) eq "on" && $q->param('from_user')) { $from_user = sanitize_alpha($q->param('from_user')); }
			$sql = $db->prepare("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('client_id')), $from_user, sanitize_html($q->param('type')), sanitize_html($q->param('summary')), $notes, now());
			$sql = $db->prepare("SELECT last_insert_rowid();");
			$sql->execute();
			my $rowid = -1;
			while(my @res = $sql->fetchrow_array()) { $rowid = to_int($res[0]); }
			print "{\n";
			print " \"message\": \"Event " . $rowid . " added.\",\n";
			print " \"status\": \"OK\"\n";
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
				my $lnk = "Normal";
				my $from_user = "api";
				if(lc($cfg->load('api_imp')) eq "on" && $q->param('from_user')) { $from_user = sanitize_alpha($q->param('from_user')); }
				if($q->param('priority')) { $lnk = sanitize_alpha($q->param('priority')); }
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), $from_user, "", sanitize_html($q->param('title')), sanitize_html($q->param('description')), $lnk, "New", "", "", now(), "Never");
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
					notify($res[1], "New ticket created", "A new ticket was created for one of your " . lc($items{"Product"}) . "s:\n\nUser: api\nTitle: " . sanitize_html($q->param('title')) . "\nDescription: " . sanitize_html($q->param('description')));
				}
				if($cfg->load('newticket_plugin'))
				{
					my $cmd = $cfg->load('newticket_plugin');
					my $s0 = to_int($q->param('product_id'));
					my $s1 = sanitize_html($q->param('release_id'));
					my $s2 = sanitize_html($q->param('title'));
					my $s3 = sanitize_html($q->param('description'));
					my $s4 = $rowid;
					$cmd =~ s/\%product\%/\"$s0\"/g;
					$cmd =~ s/\%release\%/\"$s1\"/g;
					$cmd =~ s/\%title\%/\"$s2\"/g;
					$cmd =~ s/\%description\%/\"$s3\"/g;
					$cmd =~ s/\%ticket\%/\"$s4\"/g;
					$cmd =~ s/\%user\%/\"$from_user\"/g;
					$cmd =~ s/\n/ /g;
					$cmd =~ s/\r/ /g;
					system($cmd);
				}
			}
		}
	}
	elsif($q->param('api') eq "add_client")
	{
		if(!$q->param('status'))
		{
			print "{\n";
			print " \"message\": \"Missing 'status' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(lc($q->param('status')) ne "contact" && lc($q->param('status')) ne "prospect" && lc($q->param('status')) ne "supplier" && lc($q->param('status')) ne "paid" && lc($q->param('status')) ne "unpaid")
		{
			print "{\n";
			print " \"message\": \"Invalid 'status' value. Must be one of: Prospect, Contact, Supplier, Paid, Unpaid.\",\n";
			print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('name'))
		{
			print "{\n";
			print " \"message\": \"Missing 'name' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('contact'))
		{
			print "{\n";
			print " \"message\": \"Missing 'contact' argument.\",\n";
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
			my $notes = "";
			if($q->param('notes')) { $notes = sanitize_html($q->param('notes')); }
			$sql = $db->prepare("INSERT INTO clients VALUES (?, ?, ?, ?, ?);");
			$sql->execute(sanitize_html($q->param('name')), ucfirst(lc(sanitize_html($q->param('status')))), sanitize_html($q->param('contact')), $notes, now());
			print "{\n";
			print " \"message\": \"Client added.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
		}
	}
	elsif($q->param('api') eq "add_item")
	{
		if(!$q->param('type'))
		{
			print "{\n";
			print " \"message\": \"Missing 'type' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('name'))
		{
			print "{\n";
			print " \"message\": \"Missing 'name' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!$q->param('serial'))
		{
			print "{\n";
			print " \"message\": \"Missing 'serial' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!defined($q->param('info')))
		{
			print "{\n";
			print " \"message\": \"Missing 'info' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!defined($q->param('approval')))
		{
			print "{\n";
			print " \"message\": \"Missing 'approval' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!defined($q->param('product_id')))
		{
			print "{\n";
			print " \"message\": \"Missing 'product_id' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif(!defined($q->param('client_id')))
		{
			print "{\n";
			print " \"message\": \"Missing 'client_id' argument.\",\n";
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
			print "{\n";
			my $found = 0;
			$sql = $db->prepare("SELECT * FROM items WHERE serial = ?;");
			$sql->execute(sanitize_html($q->param('serial')));
			while(my @res = $sql->fetchrow_array()) { $found = 1; }
			if($found)
			{
				print " \"message\": \"Serial number already exist.\",\n";
				print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
			}
			else
			{
				$sql = $db->prepare("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(sanitize_html($q->param('name')), ucfirst(lc(sanitize_alpha($q->param('type')))), sanitize_html($q->param('serial')), to_int($q->param('product_id')), to_int($q->param('client_id')), to_int($q->param('approval')), 1, "", sanitize_html($q->param('info')));
				print "{\n";
				print " \"message\": \"Item added.\",\n";
				print " \"status\": \"OK\"\n";
			}
			print "}\n";
		}
	}
	elsif($q->param('api') eq "update_item")
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
		elsif($q->param('key') ne $cfg->load('api_write'))
		{
			print "{\n";
			print " \"message\": \"Invalid 'key' value.\",\n";
			print " \"status\": \"ERR_INVALID_KEY\"\n";
			print "}\n";
		}
		else
		{
			if($q->param('expiration'))
			{
				if($q->param('expiration') !~ m/[0-9]{2}\/[0-9]{2}\/[0-9]{4}/)
				{
					print "{\n";
					print " \"message\": \"Expiration format must be mm/dd/yyyy.\",\n";
					print " \"status\": \"ERR_INVALID_ARGUMENT\"\n";
					print "}\n";
					quit(0);
				}
				else
				{
					$sql = $db->prepare("DELETE FROM item_expiration WHERE itemid = ?;");
					$sql->execute(to_int($q->param('id')));
					$sql = $db->prepare("INSERT INTO item_expiration VALUES (?, ?);");
					$sql->execute(to_int($q->param('id')), sanitize_html($q->param('expiration')));
				}
			}
			if($q->param('type'))
			{
				$sql = $db->prepare("UPDATE items SET type = ? WHERE ROWID = ?;");
				$sql->execute(ucfirst(lc(sanitize_html($q->param('type')))), to_int($q->param('id')));
			}
			if($q->param('serial'))
			{
				$sql = $db->prepare("UPDATE items SET serial = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_html($q->param('serial')), to_int($q->param('id')));
			}
			if($q->param('info'))
			{
				$sql = $db->prepare("UPDATE items SET info = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_html($q->param('info')), to_int($q->param('id')));
			}
			if($q->param('name'))
			{
				$sql = $db->prepare("UPDATE items SET name = ? WHERE ROWID = ?;");
				$sql->execute(sanitize_html($q->param('name')), to_int($q->param('id')));
			}
			if($q->param('product_id'))
			{
				$sql = $db->prepare("UPDATE items SET productid = ? WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('product_id')), to_int($q->param('id')));
			}
			if($q->param('client_id'))
			{
				$sql = $db->prepare("UPDATE items SET clientid = ? WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('client_id')), to_int($q->param('id')));
			}
			if($q->param('approval'))
			{
				$sql = $db->prepare("UPDATE items SET approval = ? WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('approval')), to_int($q->param('id')));
			}
			print "{\n";
			print " \"message\": \"Item updated.\",\n";
			print " \"status\": \"OK\"\n";
			print "}\n";
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
	elsif($q->param('api') eq "add_task")
	{
		if(!$q->param('product_id'))
		{
			print "{\n";
			print " \"message\": \"Missing 'product_id' argument.\",\n";
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
		elsif(!$q->param('due'))
		{
			print "{\n";
			print " \"message\": \"Missing 'due' argument.\",\n";
			print " \"status\": \"ERR_MISSING_ARGUMENT\"\n";
			print "}\n";
		}
		elsif($q->param('due') !~ m/[0-9]{2}\/[0-9]{2}\/[0-9]{4}/)
		{
			print "{\n";
			print " \"message\": \"Argument 'due' must be in format 'mm/dd/yyyy'.\",\n";
			print " \"status\": \"ERR_INVALID_FORMAT\"\n";
			print "}\n";
		}
		elsif(!$q->param('user'))
		{
			print "{\n";
			print " \"message\": \"Missing 'user' argument.\",\n";
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
			$sql = $db->prepare("INSERT INTO steps VALUES (?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('description')), sanitize_alpha($q->param('user')), 0, sanitize_html($q->param('due')));
			my $prod = "";
			$sql = $db->prepare("SELECT name FROM products WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array()) { $prod = $res[0]; }
			notify(sanitize_alpha($q->param('user')), "New task assigned to you", "A new task has been added for you on " . lc($items{"Product"}) . " \"" . $prod . "\":\n\nTask description: " . sanitize_html($q->param('description')) . "\nDue by: " . sanitize_html($q->param('due')));
			print "{\n";
			print " \"message\": \"Task added.\",\n";
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
		print " \"message\": \"Invalid 'api' value. See the manual for valid values.\",\n";
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
	my $actualfile = sanitize_alpha($q->param('file'));
	$sql = $db->prepare("SELECT filename FROM comments WHERE file = ?;");
	$sql->execute(sanitize_alpha($q->param('file')));
	while(my @res = $sql->fetchrow_array()) { $actualfile = $res[0]; }
	$sql = $db->prepare("SELECT filename FROM files WHERE file = ?;");
	$sql->execute(sanitize_alpha($q->param('file')));
	while(my @res = $sql->fetchrow_array()) { $actualfile = $res[0]; }
	open(my $fp, "<", $filename);
	print "Content-Disposition: inline; filename=" . $actualfile . "\n";
	if($type eq "application/octet-stream") { print "Content-type: text/plain\n\n"; }
	else { print "Content-type: " . $type . "\n\n"; }
	while(my $line = <$fp>)
	{
		print $line;
	}
	$sql = $db->prepare("INSERT INTO file_access VALUES (?, ?, ?)");
	$sql->execute($q->remote_addr, sanitize_alpha($q->param('file')), now());
	exit(0);
}
elsif($q->param('m')) # Modules
{
	if($q->param('m') eq "settings" && $logged_user ne "")
	{
		$cgs = $q->cookie(-name => "np_gs", -expires => '+3M', -value => "1");
		headers("Settings");
		print "<p>You are logged in as <b>" . $logged_user . "</b> and your access level is <b>" . $logged_lvl . "</b>.</p>\n";
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
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Change your email</h3></div><div class='panel-body'>\n";
			print "<div class='form-group'><p><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='change_email'><div class='row'><div class='col-sm-6'>To change your notification email address, enter a new address here. Leave empty to disable notifications:</div><div class='col-sm-6'><input type='email' name='new_email' class='form-control' data-error='Must be a valid email.' placeholder='Email address' maxlength='99' value=\"" . $email . "\"></div></div></p><div class='help-block with-errors'></div></div><input class='btn btn-primary pull-right' type='submit' value='Change email'></form></div></div>";
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Change your password</h3></div><div class='panel-body'>\n";
			if($cfg->load("ad_domain")) { print "<p>Password management is synchronized with Active Directory.</p>"; }
			elsif($cfg->load("auth_plugin")) { print "<p>Password management is handled by a plugin.</p>"; }
			elsif($logged_user eq "demo") { print "<p>The demo account cannot change its password.</p>"; }
			else
			{
				print "<div class='form-group'><p><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='change_pass'><div class='row'><div class='col-sm-4'><input placeholder='Current password' class='form-control' type='password' name='current_pass'></div><div class='col-sm-4'><input placeholder='New password' type='password' class='form-control' name='new_pass1' data-minlength='6' id='new_pass1' required></div><div class='col-sm-4'><input class='form-control' type='password' name='new_pass2' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm' required></div></div></p><div class='help-block with-errors'></div><input class='btn btn-primary pull-right' type='submit' value='Change password'></form></div>";
			}
			print "</div></div>";
		}
		if($logged_lvl > 5)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Initial settings</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.'><h4>User interface</h4><table class='table table-striped'>\n";
			print "<tr><td style='width:50%'>Database file</td><td><input class='form-control' type='text' name='db_address' value=\"" .  $cfg->load("db_address") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Upload folder</td><td><input class='form-control' type='text' name='upload_folder' value=\"" . $cfg->load("upload_folder") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Site name</td><td><input class='form-control' type='text' name='site_name' value=\"" . $cfg->load("site_name") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Public notice</td><td><input class='form-control' type='text' name='motd' value=\"" . $cfg->load("motd") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Email notifications signature</td><td><input class='form-control' type='text' name='email_sig' value=\"" . $cfg->load("email_sig") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Bootstrap template</td><td><input class='form-control' type='text' name='css_template' value=\"" . $cfg->load("css_template") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Interface theme color</td><td><select class='form-control' name='theme_color'><option value='0'";
			if($cfg->load("theme_color") eq "0") { print " selected"; }
			print ">Blue</option><option value='1'";
			if($cfg->load("theme_color") eq "1") { print " selected"; }
			print ">Grey</option><option value='2'";
			if($cfg->load("theme_color") eq "2") { print " selected"; }	
			print ">Green</option><option value='3'";
			if($cfg->load("theme_color") eq "3") { print " selected"; }
			print ">Cyan</option><option value='4'";
			if($cfg->load("theme_color") eq "4") { print " selected"; }
			print ">Orange</option><option value='5'";
			if($cfg->load("theme_color") eq "5") { print " selected"; }
			print ">Red</option></select>";
			print "<tr><td style='width:50%'>Favicon</td><td><input class='form-control' type='text' name='favicon' value=\"" . $cfg->load("favicon") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Main page logo</td><td><input class='form-control' type='text' name='logo' value=\"" . $cfg->load("logo") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Pinned article</td><td><input class='form-control' type='number' name='pinned_article' value=\"" . $cfg->load("pinned_article") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Type of portal</td><td><select class='form-control' name='items_managed'>";
			if($cfg->load("items_managed") eq "Projects with goals and milestones") { print "<option>Products with models and releases</option><option selected>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option><option>Assets with types and instances</option><option>Projects with types and phases</option>"; }
			elsif($cfg->load("items_managed") eq "Resources with locations and updates") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option selected>Resources with locations and updates</option><option>Applications with platforms and versions</option><option>Assets with types and instances</option><option>Projects with types and phases</option>"; }
			elsif($cfg->load("items_managed") eq "Applications with platforms and versions") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option selected>Applications with platforms and versions</option><option>Assets with types and instances</option><option>Projects with types and phases</option>"; }
			elsif($cfg->load("items_managed") eq "Assets with types and instances") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option><option selected>Assets with types and instances</option><option>Projects with types and phases</option>"; }
			elsif($cfg->load("items_managed") eq "Projects with types and phases") { print "<option>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option><option>Assets with types and instances</option><option selected>Projects with types and phases</option>"; }
			else { print "<option selected>Products with models and releases</option><option>Projects with goals and milestones</option><option>Resources with locations and updates</option><option>Applications with platforms and versions</option><option>Assets with types and instances</option><option>Projects with types and phases</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Number of rows per page</td><td><input class='form-control' type='number' name='page_len' value=\"" . $cfg->load("page_len") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Hide closed tickets</td><td><select class='form-control' name='hide_close'>";
			if($cfg->load("hide_close") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Disable Getting Started screen</td><td><select class='form-control' name='disable_gs'>";
			if($cfg->load("disable_gs") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Allow HTML in articles</td><td><select class='form-control' name='article_html'>";
			if($cfg->load("article_html") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "</table><h4>Security</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>Admin name</td><td><input class='form-control' type='text' name='admin_name' value=\"" .  $cfg->load("admin_name") . "\" readonly></td></tr>\n";
			print "<tr><td style='width:50%'>Admin password</td><td><input class='form-control' type='password' name='admin_pass' value=''></td></tr>\n";
			print "<tr><td style='width:50%'>Encryption key</td><td><input class='form-control' type='text' name='enc_key' value=\"" . $cfg->load("enc_key") . "\" readonly></td></tr>\n";
			print "<tr><td style='width:50%'>Allow guest tickets</td><td><select class='form-control' name='guest_tickets'>";
			if($cfg->load("guest_tickets") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Allow registrations</td><td><select class='form-control' name='allow_registrations'>";
			if($cfg->load("allow_registrations") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Ticket visibility</td><td><select class='form-control' name='default_vis'>";
			if($cfg->load("default_vis") eq "Restricted") { print "<option>Public</option><option>Private</option><option selected>Restricted</option>"; }
			elsif($cfg->load("default_vis") eq "Private") { print "<option>Public</option><option selected>Private</option><option>Restricted</option>"; }
			else { print "<option selected>Public</option><option>Private</option><option>Restricted</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Session expiry time (in hours)</td><td><input class='form-control' type='number' name='session_expiry' value=\"" . $cfg->load("session_expiry") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Maximum file upload size (in bytes)</td><td><input class='form-control' type='number' name='max_size' value=\"" . $cfg->load("max_size") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Must be assigned to " . lc($items{"Product"}) . "</td><td><select class='form-control' name='need_assign'>";
			if($cfg->load("need_assign") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Allowed upload extensions</td><td><input class='form-control' type='text' name='upload_exts' value=\"" . $cfg->load("upload_exts") . "\"></td></tr>\n";
			print "</table><h4>API access</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>API read key</td><td><input class='form-control' type='text' name='api_read' value=\"" . $cfg->load("api_read") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>API write key</td><td><input class='form-control' type='text' name='api_write' value=\"" . $cfg->load("api_write") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Allow user impersonation</td><td><select class='form-control' name='api_imp'>";
			if($cfg->load("api_imp") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "</table><h4>Active Directory integration</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>Active Directory server</td><td><input class='form-control' type='text' name='ad_server' value=\"" . $cfg->load("ad_server") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Active Directory domain</td><td><input class='form-control' type='text' name='ad_domain' value=\"" . $cfg->load("ad_domain") . "\"></td></tr>\n";
			print "</table><h4>Email configuration</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>SMTP server</td><td><input class='form-control' type='text' name='smtp_server' value=\"" . $cfg->load("smtp_server") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>SMTP port</td><td><input class='form-control' type='number' name='smtp_port' value=\"" . $cfg->load("smtp_port") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>SMTP username</td><td><input class='form-control' type='text' name='smtp_user' value=\"" . $cfg->load("smtp_user") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>SMTP password</td><td><input class='form-control' type='password' name='smtp_pass' value=\"" . RC4($cfg->load("enc_key"), decode_base64($cfg->load("smtp_pass"))) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Support email</td><td><input class='form-control' type='text' name='smtp_from' value=\"" . $cfg->load("smtp_from") . "\"></td></tr>\n";
			print "</table><h4>Access levels</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>New users access level</td><td><input class='form-control' type='number' name='default_lvl' value=\"" . to_int($cfg->load("default_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can upload files</td><td><input class='form-control' type='number' name='upload_lvl' value=\"" . to_int($cfg->load("upload_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can modify past ticket changes</td><td><input class='form-control' type='number' name='past_lvl' value=\"" . to_int($cfg->load("past_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can edit custom forms / routing</td><td><input class='form-control' type='number' name='customs_lvl' value=\"" . to_int($cfg->load("customs_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can view reports and statistics</td><td><input class='form-control' type='number' name='report_lvl' value=\"" . to_int($cfg->load("report_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can assign tasks to users</td><td><input class='form-control' type='number' name='tasks_lvl' value=\"" . to_int($cfg->load("tasks_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can view user details</td><td><input class='form-control' type='number' name='summary_lvl' value=\"" . to_int($cfg->load("summary_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can view client details</td><td><input class='form-control' type='number' name='client_lvl' value=\"" . to_int($cfg->load("client_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can add client events</td><td><input class='form-control' type='number' name='events_lvl' value=\"" . to_int($cfg->load("events_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can configure automation</td><td><input class='form-control' type='number' name='auto_lvl' value=\"" . to_int($cfg->load("auto_lvl")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can add secrets</td><td><input class='form-control' type='number' name='add_secrets' value=\"" . to_int($cfg->load("add_secrets")) . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Can view secrets</td><td><input class='form-control' type='number' name='view_secrets' value=\"" . to_int($cfg->load("view_secrets")) . "\"></td></tr>\n";
			print "</table><h4>Plugins</h4><table class='table table-striped'>";
			print "<tr><td style='width:50%'>Authentication</td><td><input class='form-control' type='text' name='auth_plugin' value=\"" . $cfg->load("auth_plugin") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Notifications</td><td><input class='form-control' type='text' name='ext_plugin' value=\"" . $cfg->load("ext_plugin") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Checkout</td><td><input class='form-control' type='text' name='checkout_plugin' value=\"" . $cfg->load("checkout_plugin") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Task completion</td><td><input class='form-control' type='text' name='task_plugin' value=\"" . $cfg->load("task_plugin") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>New tickets</td><td><input class='form-control' type='text' name='newticket_plugin' value=\"" . $cfg->load("newticket_plugin") . "\"></td></tr>\n";
			print "<tr><td style='width:50%'>Ticket resolution</td><td><input class='form-control' type='text' name='ticket_plugin' value=\"" . $cfg->load("ticket_plugin") . "\"></td></tr>\n";
			print "</table><h4>Components</h4><h5><b>Major components</b></h5><table class='table table-striped'>";
			print "<tr><td style='width:50%'>Tickets Management</td><td><select class='form-control' name='comp_tickets'>";
			if($cfg->load("comp_tickets") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Support Articles</td><td><select class='form-control' name='comp_articles'>";
			if($cfg->load("comp_articles") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Inventory Control</td><td><select class='form-control' name='comp_items'>";
			if($cfg->load("comp_items") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Clients Directory</td><td><select class='form-control' name='comp_clients'>";
			if($cfg->load("comp_clients") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "</table><h5><b>Minor components</b></h5><table class='table table-striped'>";
			print "<tr><td style='width:50%'>Time Tracking</td><td><select class='form-control' name='comp_time'>";
			if($cfg->load("comp_time") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Shoutbox</td><td><select class='form-control' name='comp_shoutbox'>";
			if($cfg->load("comp_shoutbox") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Tasks Management</td><td><select class='form-control' name='comp_steps'>";
			if($cfg->load("comp_steps") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Secrets Vault</td><td><select class='form-control' name='comp_secrets'>";
			if($cfg->load("comp_secrets") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Files Management</td><td><select class='form-control' name='comp_files'>";
			if($cfg->load("comp_files") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "<tr><td style='width:50%'>Billing</td><td><select class='form-control' name='comp_billing'>";
			if($cfg->load("comp_billing") eq "on") { print "<option selected>on</option><option>off</option>"; }
			else { print "<option>on</option><option selected>off</option>"; }
			print "</select></td></tr>\n";
			print "</table>The admin password will be left unchanged if empty.<br>See the <a href='./manual.pdf'>manual</a> file for detailed information.<input class='btn btn-primary pull-right' type='submit' value='Save settings'></form></div></div>\n";
		}
	}
	elsif($q->param('m') eq "users" && $logged_lvl >= to_int($cfg->load("summary_lvl")))
	{
		headers("Users management");
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Users management</h3></div><div class='panel-body'>\n";
		print "<table class='table table-stripped' id='users_table'><thead><tr><th>User name</th><th>Email</th><th>Level</th><th>Last login</th></tr></thead><tbody>\n";
		$sql = $db->prepare("SELECT * FROM users ORDER BY name;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td><a href='./?m=summary&u=" . $res[0] . "'>" . $res[0] . "</a></td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td>" . $res[4] . "</td></tr>\n";
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#users_table').DataTable({'order':[[0,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>\n";
		if(!$cfg->load('ad_domain') && $logged_lvl > 4)
		{
			print "<div class='form-group'><h4>Add a new user:</h4><form method='POST' action='.' data-toggle='validator' role='form'>\n";
			print "<p><div class='row'><div class='col-sm-6'><input type='text' name='new_name' placeholder='User name' class='form-control' maxlength='50' required></div><div class='col-sm-6'><input type='email' name='new_email' placeholder='Email address (optional)' class='form-control'></div></div></p><p><div class='row'><div class='col-sm-6'><input type='password' name='new_pass1' data-minlength='6' id='new_pass1' class='form-control' placeholder='Password' required></div><div class='col-sm-6'><input type='password' name='new_pass2' id='inputPasswordConfirm' data-match='#new_pass1' data-match-error='Passwords do not match.' placeholder='Confirm password' class='form-control' required></div></div></p><div class='help-block with-errors'></div><input class='btn btn-primary pull-right' type='submit' value='Add user'></form></div>\n";
		}
		print "</div></div>\n";
	}
	elsif($q->param('m') eq "stats" && $logged_lvl >= to_int($cfg->load("report_lvl")))
	{
		headers("Statistics");
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Statistics</h3></div><div class='panel-body'>\n";
		print "<form method='GET' action='.'><div class='row'><div class='col-sm-4'><input type='hidden' name='m' value='stats'><select name='u' class='form-control'><option value=''>All</option>";
		$sql = $db->prepare("SELECT name FROM users WHERE level > 0 ORDER BY name;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			 print "<option";
			 if($q->param('u') && sanitize_alpha($q->param('u')) eq $res[0]) { print " selected"; }
			 print ">" . $res[0] . "</option>"; 
		}
		print "</select></div><div class='col-sm-2'><input class='btn btn-primary' type='submit' value='Filter users'></div></div></form><hr>";
		if($cfg->load('comp_tickets') eq "on")
		{
			if($q->param('u'))
			{ print "<p><div class='row'><div class='col-sm-6'><center><h4>Number of tickets created by " . sanitize_alpha($q->param('u')) . ":</h4></center><canvas id='graph0'></canvas></div><div class='col-sm-6'><center><h4>Status distribution for tickets assigned to " . sanitize_alpha($q->param('u')) . ":</h4></center><canvas id='graph1'></canvas></div></div></p>\n"; }
			else { print "<p><div class='row'><div class='col-sm-6'><center><h4>Number of tickets created by all users:</h4></center><canvas id='graph0'></canvas></div><div class='col-sm-6'><center><h4>Overall status distribution:</h4></center><canvas id='graph1'></canvas></div></div></p>\n"; }
			print "<script src='Chart.min.js'></script><script>Chart.defaults.global.responsive = true; var data0 = { ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT created FROM tickets WHERE createdby = ? ORDER BY ROWID DESC;");
				$sql->execute(sanitize_alpha($q->param('u')));
			}
			else
			{
				$sql = $db->prepare("SELECT created FROM tickets ORDER BY ROWID DESC;");
				$sql->execute();
			}
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
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'New' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'New';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#87ABBC', highlight: '#97BBCC', label: 'New' }, { value: ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Open' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Open';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#EFC193', highlight: '#FFD1A3', label: 'Open' }, { value: ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Invalid' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Invalid';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#CDA5EF', highlight: '#DDB5FF', label: 'Invalid' }, { value: ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Hold' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Hold';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#EF8B9C', highlight: '#FF9BAC', label: 'Hold' }, { value: ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Duplicate' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Duplicate';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#A3D589', highlight: '#B3E599', label: 'Duplicate' }, { value: ";
			if($q->param('u'))
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Resolved' AND assignedto LIKE ?;");
				$sql->execute("%" . sanitize_alpha($q->param('u')) . "%");
			}
			else
			{
				$sql = $db->prepare("SELECT COUNT(*) FROM tickets WHERE status = 'Resolved';");
				$sql->execute();
			}
			while(my @res = $sql->fetchrow_array()) { print $res[0]; }
			print ", color:'#DDDFA0', highlight: '#EDEFB0', label: 'Resolved' }";
			print "]; var ctx1 = document.getElementById('graph1').getContext('2d'); new Chart(ctx1).Pie(data1);</script><hr>\n";
		}
		if($cfg->load('comp_steps') eq "on" || $cfg->load('comp_items') eq "on" || $cfg->load('comp_time') eq "on")
		{
			if($cfg->load('comp_time') ne "on")
			{
				if($cfg->load('comp_steps') ne "on") { print "<h4>Item expirations:</h4>"; }
				elsif($cfg->load('comp_items') ne "on") { print "<h4>Due tasks:</h4>"; }
				else { print "<h4>Due tasks and item expirations:</h4>"; }
			}
			else
			{
				if($cfg->load('comp_steps') ne "on" && $cfg->load('comp_items') ne "on") { print "<h4>Time spent on tickets:</h4>"; }
				elsif($cfg->load('comp_steps') ne "on") { print "<h4>Time spent on tickets and item expirations:</h4>"; }
				elsif($cfg->load('comp_items') ne "on") { print "<h4>Time spent on tickets and due tasks:</h4>"; }
				else { print "<h4>Time spent on tickets, due tasks and item expirations:</h4>"; }				
			}
			print "\n<script src='fullcalendar-moment.js'></script>\n<script src='fullcalendar.js'></script>\n<script>\n\$(document).ready(function(){\$('#calendar').fullCalendar({\nheader: {left: 'prev,next today', center: 'title', right: 'month,basicWeek,basicDay'}, editable: false, eventLimit: true,\nevents: [\n{title: 'Event start', start: '2000-11-01', allDay: true, url: './'}";
			if($cfg->load('comp_steps') eq "on")
			{
				if($q->param('u'))
				{
					$sql = $db->prepare("SELECT * FROM steps WHERE name = ?;");
					$sql->execute(sanitize_alpha($q->param('u')));
				}
				else
				{
					$sql = $db->prepare("SELECT * FROM steps;");
					$sql->execute();
				}
				while(my @res = $sql->fetchrow_array())
				{ print ",\n{title: 'Task due: " . $res[2] . "', description: \"<b>Task:</b> " . $res[1] . "<br><b>User:</b> " . $res[2] . "<br><b>Completion:</b> " . $res[3] . "%\", allDay: true, color: '#BF0721', start: '" . $res[4] . "', url: './?m=view_product&p=" . to_int($res[0]) . "'}"; }
			}
			if($cfg->load('comp_time') eq "on")
			{
				if($q->param('u'))
				{
					$sql = $db->prepare("SELECT * FROM timetracking WHERE name = ?;");
					$sql->execute(sanitize_alpha($q->param('u')));
				}
				else
				{
					$sql = $db->prepare("SELECT * FROM timetracking;");
					$sql->execute();
				}
				while(my @res = $sql->fetchrow_array())
				{ print ",\n{title: 'Time spent: " . $res[1] . "', description: \"<b>User:</b> " . $res[1] . "<br><b>Ticket:</b> " . $res[0] . "<br><b>Time spent:</b> " . $res[2] . "h\", allDay: true, color: '#8E7D7C', start: '" . $res[3] . "', url: './?m=view_ticket&t=" . to_int($res[0]) . "'}"; }
			}
			if($cfg->load('comp_items') eq "on")
			{
				$sql = $db->prepare("SELECT * FROM item_expiration;");
				$sql->execute();
				while(my @res = $sql->fetchrow_array())
				{
					my $sql2;
					if($q->param('u'))
					{
						$sql2 = $db->prepare("SELECT name,serial,status,user FROM items WHERE ROWID = ? AND user = ?;");
						$sql2->execute(to_int($res[0]), sanitize_alpha($q->param('u')));
					}
					else
					{
						$sql2 = $db->prepare("SELECT name,serial,status,user FROM items WHERE ROWID = ?;");
						$sql2->execute(to_int($res[0]));
					}
					while(my @res2 = $sql2->fetchrow_array())
					{
						print ",\n{title: \"Item expires: " . $res2[1] . "\", description: \"<b>Name:</b> " . $res2[0] . "<br><b>Serial:</b> " . $res2[1] . "<br><b>Status:</b> ";
						if(to_int($res2[2]) == 0) { print "<font color='red'>Unavailable</font>"; }
						elsif(to_int($res2[2]) == 1) { print "<font color='green'>Available</font>"; }
						elsif(to_int($res2[2]) == 2) { print "<font color='orange'>Waiting approval for: " . $res2[3] . "</font>"; }
						else { print "<font color='red'>Checked out by: " . $res2[3] . "</font>"; }
						print "\", allDay: true, color: '#0DAFAF', start: '" . $res[1] . "', url: './?m=items&i=" . to_int($res[0]) . "'}";
					} 
				}
			}
			print "\n], eventRender: function(event, element) {element.tooltip({html: true, container: 'body', title: event.description});} \n});});\n</script>\n";
			print "<div id='calendar'></div><hr>";
		}
		print "<p><h4>Reports:</h4><form method='GET' action='.'><div class='row'><div class='col-sm-6'><input type='hidden' name='m' value='show_report'><select class='form-control' name='report'>";
		if($cfg->load('comp_time') eq "on") { print "<option value='1'>Time spent per user</option><option value='2'>All time spent per ticket</option><option value='11'>Your time spent per ticket</option>"; }
		if($cfg->load('comp_articles') eq "on") { print "<option value='13'>Tickets linked per article</option>"; }
		if($cfg->load('comp_tickets') eq "on") { print "<option value='3'>Tickets created per " . lc($items{"Product"}) . "</option><option value='10'>New and open tickets per " . lc($items{"Product"}) . "</option><option value='4'>Tickets created per user</option><option value='5'>Tickets created per day</option><option value='6'>Tickets created per month</option><option value='7'>Tickets per status</option><option value='9'>Tickets assigned per user</option><option value='12'>Comment file attachments</option>"; }
		if($cfg->load('comp_shoutbox') eq "on") { print "<option value='14'>Full shoutbox history</option>"; }
		if($cfg->load('comp_clients') eq "on") { print "<option value='16'>Clients per status</option><option value='20'>Client events per user</option>"; }
		if($cfg->load('comp_items') eq "on") { print "<option value='15'>Items checked out per user</option><option value='18'>Item expiration dates</option>"; }
		print "<option value='8'>Users per access level</option><option value='17'>Active user sessions</option><option value='19'>Disabled users</option></select></div><div class='col-sm-6'><span class='pull-right'><input class='btn btn-primary' type='submit' value='Show report'></span></div></div></form></p></div><div class='help-block with-errors'></div></div>\n";
	}
	elsif($q->param('m') eq "edit_route" && $q->param('r') && $logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")
	{
		headers("Ticket routing");
		my %actions;
		my %conditions;
		$sql = $db->prepare("SELECT key,value FROM routing_conditions WHERE route = ?;");
		$sql->execute(to_int($q->param('r')));
		while(my @res = $sql->fetchrow_array())
		{ $conditions{$res[0]} = $res[1]; }
		$sql = $db->prepare("SELECT key,value FROM routing_actions WHERE route = ?;");
		$sql->execute(to_int($q->param('r')));
		while(my @res = $sql->fetchrow_array())
		{ $actions{$res[0]} = $res[1]; }
		$sql = $db->prepare("SELECT name,priority FROM routing WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('r')));
		while(my @res = $sql->fetchrow_array())
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Route " . to_int($q->param('r')) . "</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='./' data-toggle='validator' role='form'><input type='hidden' name='m' value='routing'><input type='hidden' name='r' value='" . to_int($q->param('r')) . "'><div class='row'><div class='col-sm-8'>Route name: <input type='text' name='name' class='form-control' value=\"" . $res[0] . "\" maxlength='99' required></div><div class='col-sm-4'>Priority: <input type='number' class='form-control' name='priority' value=\"" . $res[1] . "\" required></div></div>\n";
			print "<br><h4>Conditions:</h4><table class='table table-stripped'>\n";
			print "<tr><td>Ticket must be created by a user level <select name='lvl_or_higher'><option></option><option";
			if(exists($conditions{'lvl_or_higher'}) && $conditions{'lvl_or_higher'} eq "1") { print " selected"; }
			print ">1</option><option";
			if(exists($conditions{'lvl_or_higher'}) && $conditions{'lvl_or_higher'} eq "2") { print " selected"; }
			print ">2</option><option";
			if(exists($conditions{'lvl_or_higher'}) && $conditions{'lvl_or_higher'} eq "3") { print " selected"; }
			print ">3</option><option";
			if(exists($conditions{'lvl_or_higher'}) && $conditions{'lvl_or_higher'} eq "4") { print " selected"; }
			print ">4</option><option";
			if(exists($conditions{'lvl_or_higher'}) && $conditions{'lvl_or_higher'} eq "5") { print " selected"; }
			print ">5</option></select> and higher, or level <select name='lvl_or_lower'><option></option><option";
			if(exists($conditions{'lvl_or_lower'}) && $conditions{'lvl_or_lower'} eq "1") { print " selected"; }
			print ">1</option><option";
			if(exists($conditions{'lvl_or_lower'}) && $conditions{'lvl_or_lower'} eq "2") { print " selected"; }
			print ">2</option><option";
			if(exists($conditions{'lvl_or_lower'}) && $conditions{'lvl_or_lower'} eq "3") { print " selected"; }
			print ">3</option><option";
			if(exists($conditions{'lvl_or_lower'}) && $conditions{'lvl_or_lower'} eq "4") { print " selected"; }
			print ">4</option><option";
			if(exists($conditions{'lvl_or_lower'}) && $conditions{'lvl_or_lower'} eq "5") { print " selected"; }
			print ">5</option></select> and lower.</td></tr>\n";
			print "<tr><td>Ticket creator must have <input type='text' name='username_match' value=\"";
			if(exists($conditions{'username_match'})) { print $conditions{'username_match'}; }
			print "\"> in their user name.</td></tr>\n";
			print "<tr><td>Ticket must be filed against " . lc($items{"Product"}) . " <select name='project_match'><option></option>";
			my $sql3 = $db->prepare("SELECT ROWID,* FROM products;");
			$sql3->execute();
			while(my @res3 = $sql3->fetchrow_array())
			{
				print "<option value='" . $res3[0] . "'";
				if(exists($conditions{'project_match'}) && to_int($conditions{'project_match'}) == to_int($res3[0])) { print " selected"; }
				print ">" . $res3[1] . "</option>";
			}
			print "\">.</td></tr>\n";
			print "<tr><td>The ticket title must contain the text <input type='text' name='title_match' value=\"";
			if(exists($conditions{'title_match'})) { print $conditions{'title_match'}; }
			print "\">.</td></tr>\n";
			print "<tr><td>The ticket description must contain the text <input type='text' name='description_match' value=\"";
			if(exists($conditions{'description_match'})) { print $conditions{'description_match'}; }
			print "\">.</td></tr>\n";
			print "<tr><td>Custom form field <select name='field_match'><option></option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "1") { print " selected"; }
			print ">1</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "2") { print " selected"; }
			print ">2</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "3") { print " selected"; }
			print ">3</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "4") { print " selected"; }
			print ">4</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "5") { print " selected"; }
			print ">5</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "6") { print " selected"; }
			print ">6</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "7") { print " selected"; }
			print ">7</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "8") { print " selected"; }
			print ">8</option><option";
			if(exists($conditions{'field_match'}) && $conditions{'field_match'} eq "9") { print " selected"; }
			print ">9</option></select> must contain the text <input type='text' name='field_match_text' value=\"";
			if(exists($conditions{'field_match_text'})) { print $conditions{'field_match_text'}; }
			print "\">.</td></tr>\n";
			print "<tr><td>Ticket creator must be a member of the Active Directory security group <input type='text' name='group_memberof' value=\"";
			if(exists($conditions{'group_memberof'})) { print $conditions{'group_memberof'}; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> and the Base DN <input type='text' name='group_basedn' value=\"";
			if(exists($conditions{'group_basedn'})) { print $conditions{'group_basedn'}; }
			else { print "CN=Users,DC=" . $cfg->load("ad_domain") . ",DC=com"; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print ">. Use the username <input type='text' name='group_creds_username' value=\"";
			if(exists($conditions{'group_creds_username'})) { print $conditions{'group_creds_username'}; }
			else { print "Administrator"; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> and password <input type='password' name='group_creds_password' value=\"";
			if(exists($conditions{'group_creds_password'})) { print RC4($cfg->load("enc_key"),decode_base64($conditions{'group_creds_password'})); }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> to do the query in AD.</td></tr>\n";
			print "</table><br><h4>Actions:</h4><table class='table table-stripped'>\n";
			print "<tr><td>Set ticket status to <select name='status'><option></option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Open") { print " selected"; }
			print ">Open</option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Invalid") { print " selected"; }
			print ">Invalid</option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Hold") { print " selected"; }
			print ">Hold</option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Duplicate") { print " selected"; }
			print ">Duplicate</option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Resolved") { print " selected"; }
			print ">Resolved</option><option";
			if(exists($actions{'status'}) && $actions{'status'} eq "Closed") { print " selected"; }
			print ">Closed</option></select>.</td></tr>\n";
			print "<tr><td>Set ticket resolution to <input type='text' name='resolution' value=\"";
			if(exists($actions{'resolution'})) { print $actions{'resolution'}; }
			print "\">.</td></tr>\n";
			print "<tr><td>Append to the file <input type='text' name='output_file' value=\"";
			if(exists($actions{'output_file'})) { print $actions{'output_file'}; }
			print "\"> the following text:<br><textarea style='width:90%' rows=5 name='output_file_text'>";
			if(exists($actions{'output_file_text'})) { print $actions{'output_file_text'}; }			
			print "</textarea></td></tr>\n";
			print "<tr><td>Show a popup message with the text <input type='text' name='popup_message' value=\"";
			if(exists($actions{'popup_message'})) { print $actions{'popup_message'}; }
			print "\"> to the user.</td></tr>\n";
			print "<tr><td>Open a new window with the URL <input type='text' name='open_url' value=\"";
			if(exists($actions{'open_url'})) { print $actions{'open_url'}; }
			print "\">.</td></tr>\n";
			print "<tr><td>Redirect the user to the URL <input type='text' name='redirect_url' value=\"";
			if(exists($actions{'redirect_url'})) { print $actions{'redirect_url'}; }
			print "\"> after ticket submission.</td></tr>\n";
			print "<tr><td>Send a notification to user <select name='notify_user'><option></option><option";
			if(exists($actions{'notify_user'}) && $actions{'notify_user'} eq "\%user\%") { print " selected"; }
			print ">\%user\%</option>";
			my $sql3 = $db->prepare("SELECT name FROM users ORDER BY name;");
			$sql3->execute();
			while(my @res3 = $sql3->fetchrow_array())
			{
				print "<option";
				if(exists($actions{'notify_user'}) && $actions{'notify_user'} eq $res3[0]) { print " selected"; }			
				print ">" . $res3[0] . "</option>"; 
			}
			print "</select> with the title <input type='text' name='notify_user_title' value=\"";
			if(exists($actions{'notify_user_title'})) { print $actions{'notify_user_title'}; }
			print "\"> and the following text:<br><textarea style='width:90%' rows=5 name='notify_user_text'>";
			if(exists($actions{'notify_user_text'})) { print $actions{'notify_user_text'}; }
			print "</textarea></td></tr>\n";
			print "<tr><td>Assign user <select name='assign_user'><option></option>";
			my $sql3 = $db->prepare("SELECT name FROM users WHERE level > 2 ORDER BY name;");
			$sql3->execute();
			while(my @res3 = $sql3->fetchrow_array())
			{
				print "<option";
				if(exists($actions{'assign_user'}) && $actions{'assign_user'} eq $res3[0]) { print " selected"; }			
				print ">" . $res3[0] . "</option>"; 
			}
			print "</select> to the ticket.</td></tr>\n";
			print "<tr><td>Modify the Active Directory attribute <input type='text' name='attr_name' value=\"";
			if(exists($actions{'attr_name'})) { print $actions{'attr_name'}; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> of user <input type='text' name='attr_user' value=\"";
			if(exists($actions{'attr_user'})) { print $actions{'attr_user'}; }
			else { print "\%user\%"; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> of BaseDN <input type='text' name='attr_basedn' value=\"";
			if(exists($actions{'attr_basedn'})) { print $actions{'attr_basedn'}; }
			else { print "CN=Users,DC=" . $cfg->load("ad_domain") . ",DC=com"; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> to <input type='text' name='attr_value' value=\"";
			if(exists($actions{'attr_value'})) { print $actions{'attr_value'}; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print ">. Use the username <input type='text' name='attr_creds_username' value=\"";
			if(exists($actions{'attr_creds_username'})) { print $actions{'attr_creds_username'}; }
			else { print "Administrator"; }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> and password <input type='password' name='attr_creds_password' value=\"";
			if(exists($actions{'attr_creds_password'})) { print RC4($cfg->load("enc_key"),decode_base64($actions{'attr_creds_password'})); }
			print "\"";
			if($cfg->load("ad_domain") eq "") { print " disabled"; }
			print "> to connect to AD.</td></tr>\n";
			print "</table><br><div class='row'><div class='col-sm-12'><input name='delete_route' type='submit' onclick='return confirm(\"Are you sure?\");' value='Delete' class='btn btn-danger'> <input name='save_route' type='submit' value='Save' class='btn btn-primary pull-right'></div></div></form></div></div>\n";
		}
	}
	elsif($q->param('m') eq "routing" && $logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")
	{
		headers("Ticket routing");
		if($q->param('save_route') && $q->param('r') && $q->param('name') && $q->param('priority'))
		{
			$sql = $db->prepare("UPDATE routing SET name = ?, priority = ? WHERE ROWID = ?;");
			$sql->execute(sanitize_html($q->param('name')), to_int($q->param('priority')), to_int($q->param('r')));
			$sql = $db->prepare("DELETE FROM routing_conditions WHERE route = ?;");
			$sql->execute(to_int($q->param('r')));
			$sql = $db->prepare("DELETE FROM routing_actions WHERE route = ?;");
			$sql->execute(to_int($q->param('r')));
			$sql = $db->prepare("BEGIN");
			$sql->execute();
			if($q->param('lvl_or_higher'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "lvl_or_higher", to_int($q->param('lvl_or_higher')));	
			}
			if($q->param('lvl_or_lower'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "lvl_or_lower", to_int($q->param('lvl_or_lower')));	
			}
			if($q->param('project_match'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "project_match", to_int($q->param('project_match')));	
			}
			if($q->param('username_match'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "username_match", sanitize_html($q->param('username_match')));
			}
			if($q->param('group_memberof'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "group_memberof", sanitize_html($q->param('group_memberof')));
			}
			if($q->param('group_basedn'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "group_basedn", sanitize_html($q->param('group_basedn')));
			}
			if($q->param('group_creds_username'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "group_creds_username", sanitize_html($q->param('group_creds_username')));
			}
			if($q->param('group_creds_password'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "group_creds_password", encode_base64(RC4($cfg->load("enc_key"), $q->param('group_creds_password'))));
			}
			if($q->param('field_match'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "field_match", to_int($q->param('field_match')));				
			}
			if($q->param('field_match_text'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "field_match_text", sanitize_html($q->param('field_match_text')));				
			}
			if($q->param('title_match'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "title_match", sanitize_html($q->param('title_match')));				
			}
			if($q->param('description_match'))
			{
				$sql = $db->prepare("INSERT INTO routing_conditions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "description_match", sanitize_html($q->param('description_match')));				
			}
			if($q->param('status'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "status", sanitize_html($q->param('status')));				
			}
			if($q->param('resolution'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "resolution", sanitize_html($q->param('resolution')));				
			}
			if($q->param('open_url'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "open_url", sanitize_html($q->param('open_url')));				
			}
			if($q->param('popup_message'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "popup_message", sanitize_html($q->param('popup_message')));				
			}
			if($q->param('redirect_url'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "redirect_url", sanitize_html($q->param('redirect_url')));				
			}
			if($q->param('attr_name'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_name", sanitize_html($q->param('attr_name')));
			}
			if($q->param('attr_user'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_user", sanitize_html($q->param('attr_user')));
			}
			if($q->param('attr_basedn'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_basedn", sanitize_html($q->param('attr_basedn')));
			}
			if($q->param('attr_value'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_value", sanitize_html($q->param('attr_value')));
			}
			if($q->param('attr_creds_username'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_creds_username", sanitize_html($q->param('attr_creds_username')));
			}
			if($q->param('attr_creds_password'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "attr_creds_password", encode_base64(RC4($cfg->load("enc_key"), $q->param('attr_creds_password'))));
			}
			if($q->param('output_file'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "output_file", sanitize_html($q->param('output_file')));				
			}
			if($q->param('output_file_text'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "output_file_text", sanitize_html($q->param('output_file_text')));				
			}
			if($q->param('notify_user_title'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "notify_user_title", sanitize_html($q->param('notify_user_title')));				
			}
			if($q->param('notify_user'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "notify_user", sanitize_html($q->param('notify_user')));				
			}
			if($q->param('assign_user'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "assign_user", sanitize_alpha($q->param('assign_user')));				
			}
			if($q->param('notify_user_text'))
			{
				$sql = $db->prepare("INSERT INTO routing_actions VALUES (?, ?, ?);");
				$sql->execute(to_int($q->param('r')), "notify_user_text", sanitize_html($q->param('notify_user_text')));				
			}
			$sql = $db->prepare("END");
			$sql->execute();
			msg("Route saved.", 3)
		}
		if($q->param('create_route') && $q->param('name') && $q->param('priority'))
		{
			$sql = $db->prepare("INSERT INTO routing VALUES (?, ?, ?);");
			$sql->execute(sanitize_html($q->param('name')), to_int($q->param('priority')), 0);
			msg("New route added.", 3)
		}
		if($q->param('delete_route') && $q->param('r'))
		{
			$sql = $db->prepare("DELETE FROM routing WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('r')));
			$sql = $db->prepare("DELETE FROM routing_actions WHERE route = ?;");
			$sql->execute(to_int($q->param('r')));
			$sql = $db->prepare("DELETE FROM routing_conditions WHERE route = ?;");
			$sql->execute(to_int($q->param('r')));
			msg("Route removed.", 3)
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add route</h3></div><div class='panel-body'>\n";
		print "<form method='POST' action='./' data-toggle='validator' role='form'><input type='hidden' name='m' value='routing'><div class='row'><div class='col-sm-8'><input type='text' name='name' class='form-control' placeholder='Route name' maxlength='99' required></div><div class='col-sm-4'><input type='number' class='form-control' name='priority' placeholder='Priority' required></div></div><br><div class='row'><div class='col-sm-12'><input name='create_route' type='submit' value='Create' class='btn btn-primary pull-right'></div></div></form></div></div>\n";
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Ticket routing</h3></div><div class='panel-body'>\n";
		print "<p><table class='table table-stripped' id='routing_table'><thead><tr><th>ID</th><th>Route name</th><th>Priority</th><th>Hits</th></tr></thead><tbody>";
		$sql = $db->prepare("SELECT ROWID,* FROM routing;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td>" . $res[0] . "</td><td><a href='./?m=edit_route&r=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>\n";
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#routing_table').DataTable({'order':[[2,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></p></div></div>";
	}
	elsif($q->param('m') eq "customforms" && $logged_lvl >= to_int($cfg->load("customs_lvl")) && $cfg->load('comp_tickets') eq "on")
	{
		headers("Custom forms");
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Custom forms</h3></div><div class='panel-body'>\n";
		print "<form method='GET' action='./'><input type='hidden' name='create_form' value='1'><input type='submit' value='Create new custom form' class='btn btn-primary'></form><br>\n";
		print "<p><table class='table table-stripped' id='customs_table'><thead><tr><th>Assigned " . lc($items{"Product"}) . "</th><th>Form name</th><th>Last update</th></tr></thead><tbody>";
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		$sql = $db->prepare("SELECT * FROM default_form;");
		$sql->execute();
		my $defaultform = -1;
		while(my @res = $sql->fetchrow_array()) { $defaultform = to_int($res[0]); }
		$sql = $db->prepare("SELECT ROWID,* FROM forms;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td>";
			if($products[$res[1]]) { print $products[$res[1]]; }
			else { print "None"; }
			if($res[0] == $defaultform) { print " <b>(default form)</b>"; }
			print "</td><td><a href='./?edit_form=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[23] . "</td></tr>\n";
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#customs_table').DataTable({'order':[[1,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></p></div></div>";
	}
	elsif($q->param('m') eq "log" && $logged_lvl > 5)
	{
		headers("System log");
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>System log</h3></div><div class='panel-body'>\n";
		print "<form style='display:inline' method='POST' action='.'><input type='hidden' name='m' value='clear_log'><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Are you sure?\");' value='Clear log'><br></form><a name='log'></a><p>Filter log by events:<br><a href='./?m=log'>All</a> | <a href='./?m=log&filter_log=Failed'>Failed logins</a> | <a href='./?m=log&filter_log=Success'>Successful logins</a> | <a href='./?m=log&filter_log=level'>Level changes</a> | <a href='./?m=log&filter_log=password'>Password changes</a> | <a href='./?m=log&filter_log=new'>New users</a> | <a href='./?m=log&filter_log=setting'>Settings updated</a> | <a href='./?m=log&filter_log=notification'>Email notifications</a> | <a href='./?m=log&filter_log=LDAP:'>Active Directory</a> | <a href='./?m=log&filter_log=deleted:'>Deletes</a> | <a href='./?m=log&filter_log=secret:'>Secrets</a></p>\n";
		print "<table class='table table-stripped' id='log_table'><thead><tr><th>IP address</th><th>User</th><th>Event</th><th>Time</th></tr></thead><tbody>\n";
		if($q->param("filter_log"))
		{
			$sql = $db->prepare("SELECT * FROM log DESC WHERE op LIKE ? ORDER BY key DESC LIMIT 5000;");
			$sql->execute("%" . sanitize_alpha($q->param("filter_log")) . "%");
		}
		else
		{
			$sql = $db->prepare("SELECT * FROM log ORDER BY key DESC LIMIT 5000;");
			$sql->execute();
		}
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td>" . $res[0] . "</td><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>\n";
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#log_table').DataTable({'order':[[3,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
	}
	elsif($q->param('m') eq "clients" && $logged_user ne "" && $cfg->load('comp_clients') eq "on")
	{
		headers("Clients");
		if($logged_lvl > 4)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add a new client</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='add_client'><p><div class='row'><div class='col-sm-6'><input type='text' class='form-control' name='name' placeholder='Client name' maxlength='50' required></div><div class='col-sm-6'><select class='form-control' name='status'><option>Prospect</option><option>Contact</option><option>Supplier</option><option>Paid</option><option>Unpaid</option><option>Closed</option></select></div></div></p><p><input type='text' class='form-control' name='contact' placeholder='Contact' maxlength='99' required></p><p><textarea class='form-control' name='notes' placeholder='Notes'></textarea></p><p><input type='submit' value='Add client' class='btn btn-primary pull-right'></form>";
			print "</div></div>\n";
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Clients directory</h3></div><div class='panel-body'>";
		print "<table class='table table-stripped' id='clients_table'><thead><tr><th>ID</th><th>Name</th><th>Contact</th><th>Status</th></tr></thead><tbody>\n";
		$sql = $db->prepare("SELECT ROWID,* FROM clients;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td>" . $res[0] . "</td><td>";
			if($logged_lvl >= to_int($cfg->load('client_lvl'))) { print "<a href='./?m=view_client&c=" . $res[0] . "'>"; }
			print $res[1];
			if($logged_lvl >= to_int($cfg->load('client_lvl'))) { print "</a>"; }
			print "</td><td>" . $res[3] . "</td><td>" . $res[2] . "</td></tr>";
		}		
		print "</tbody></table><script>\$(document).ready(function(){\$('#clients_table').DataTable({'order':[[0,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','excel','pdf','print']});});</script>";
		print "</div></div>\n";
	}
	elsif($q->param('m') eq "save_client" && $q->param('c') && $logged_lvl > 4)
	{
		headers("Clients");
		if($q->param('delete'))
		{
			$sql = $db->prepare("DELETE FROM clients WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('c')));
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=clients'>Client removed.", 3);		
		}
		elsif(!$q->param('contact') || !$q->param('status'))
		{
			my $text = "Required fields missing: ";
			if(!$q->param('contact')) { $text .= "<span class='label label-danger'>Contact</span> "; }
			if(!$q->param('status')) { $text .= "<span class='label label-danger'>Status</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
		else
		{
			my $notes = "";
			if($q->param('notes')) { $notes = sanitize_html($q->param('notes')); }
			$sql = $db->prepare("UPDATE clients SET status = ?, contact = ?, notes = ?, modified = ? WHERE ROWID = ?;");
			$sql->execute(sanitize_html($q->param('status')), sanitize_html($q->param('contact')), $notes, now(), to_int($q->param('c')));
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=view_client&c=" . to_int($q->param('c')) . "'>Client updated.", 3);
		}
	}
	elsif($q->param('m') eq "summary" && $q->param('u') && $logged_lvl >= to_int($cfg->load('summary_lvl')))
	{
		headers("Summary");
		my $u = sanitize_alpha($q->param('u'));
		if($q->param('enable_user'))
		{
			$sql = $db->prepare("DELETE FROM disabled WHERE user = ?");
			$sql->execute($u);
			msg("User login enabled.", 3);
			logevent("Enabled: " . $u);
		}
		if($q->param('disable_user'))
		{
			if(lc($u) eq lc($cfg->load('admin_name')) || lc($u) eq lc("api") || lc($u) eq lc("guest") || lc($u) eq lc("system") || lc($u) eq lc("demo"))
			{
				msg("Cannot disable this user.", 1);
			}
			else
			{
				$sql = $db->prepare("INSERT INTO disabled VALUES (?)");
				$sql->execute($u);
				msg("User login disabled.", 3);
				logevent("Disabled: " . $u);
			}
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Summary for: " . $u . "</h3></div><div class='panel-body'><table class='table table-striped'><tr><th>Key</th><th>Value</th></tr>\n";
		$sql = $db->prepare("SELECT loggedin,level,email,confirm FROM users WHERE name = ?");
		$sql->execute($u);
		while(my @res = $sql->fetchrow_array())
		{
			print "<tr><td>Last login time</td><td>" . $res[0] . "</td></tr>";
			print "<tr><td>Access level</td><td>" . $res[1] . "</td></tr>";
			print "<tr><td>Email address</td><td>" . $res[2] . "</td></tr>";
			if($res[3] eq "") { print "<tr><td>Confirmed email</td><td>True</td></tr>"; }
			else { print "<tr><td>Confirmed email</td><td>False</td></tr>"; }
		}

		if($cfg->load('comp_steps') eq "on")
		{
			my $m = localtime->strftime('%m');
			my $y = localtime->strftime('%Y');
			my $d = localtime->strftime('%d');
			$sql = $db->prepare("SELECT due FROM steps WHERE user = ? AND completion < 100;");
			$sql->execute($u);
			my $overduetasks = 0;
			my $totaltasks = 0;
			while(my @res = $sql->fetchrow_array())
			{
				my @dueby = split(/\//, $res[0]);
				if($dueby[2] < $y || ($dueby[2] == $y && $dueby[0] < $m) || ($dueby[2] == $y && $dueby[0] == $m && $dueby[1] < $d)) { $overduetasks++; }
				$totaltasks++;
			}
			print "<tr><td>Active tasks</td><td>" . $totaltasks . "</td></tr>";
			print "<tr><td>Overdue tasks</td><td>" . $overduetasks . "</td></tr>";
		}

		if($cfg->load('comp_time') eq "on")
		{
			$sql = $db->prepare("SELECT spent FROM timetracking WHERE name = ?");
			$sql->execute($u);
			my $timespent = 0.0;
			while(my @res = $sql->fetchrow_array())
			{
				$timespent += to_float($res[0]);
			}		
			print "<tr><td>Hours spent on tickets</td><td>" . $timespent . "</td></tr>";
		}
	
		if($cfg->load('comp_tickets') eq "on")
		{
			$sql = $db->prepare("SELECT COUNT(*) FROM comments WHERE name = ?;");
			$sql->execute($u);
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>Comments created</td><td>" . $res[0] . "</td></tr>";
			}
			$sql = $db->prepare("SELECT COUNT(*) FROM escalate WHERE user = ?;");
			$sql->execute($u);
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>Pending notifications</td><td>" . $res[0] . "</td></tr>";
			}
			$sql = $db->prepare("SELECT ROWID,title FROM tickets WHERE createdby = ?");
			$sql->execute($u);
			print "<tr><td>Tickets created</td><td>";
			while(my @res = $sql->fetchrow_array())
			{
				print "<a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[1] . "</a><br>";
			}
			print "</td></tr>";
			$sql = $db->prepare("SELECT ROWID,title FROM tickets WHERE status != 'Closed' AND assignedto LIKE ?;");
			$sql->execute("%" . $u . "%");
			print "<tr><td>Active tickets assigned</td><td>";
			while(my @res = $sql->fetchrow_array())
			{
				 print "<a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[1] . "</a><br>";
			}
			print "</td></tr>";
		}

		if($cfg->load('comp_items') eq "on")
		{
			$sql = $db->prepare("SELECT ROWID,name,serial FROM items WHERE user = ?");
			$sql->execute($u);
			print "<tr><td>Checked out items</td><td>";
			while(my @res = $sql->fetchrow_array())
			{
				print "<a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . " (" . $res[2] . ")</a><br>";
			}
			print "</td></tr>";
		}

		print "</table>";
		
		if($logged_lvl > 4)
		{
			$sql = $db->prepare("SELECT * FROM disabled WHERE user = ?;");
			$sql->execute($u);
			my $userisbanned = 0;
			while(my @res = $sql->fetchrow_array())
			{
				$userisbanned = 1;
			}
			print "<form style='display:inline-block' method='GET' action='.'><input type='hidden' name='m' value='change_lvl'><input type='hidden' name='u' value='" . $u . "'><input type='submit' class='btn btn-primary pull-right' value='Change access level'></form>&nbsp;<form style='display:inline-block' method='GET' action='.'><input type='hidden' name='m' value='reset_pass'><input type='hidden' name='u' value='" . $u . "'>";
			if($cfg->load("ad_domain") && $cfg->load("ad_server"))
			{
				print "<input type='submit' class='btn btn-default pull-right' value='Password managed by AD' disabled>";
			}
			else
			{
				print "<input type='submit' class='btn btn-primary pull-right' value='Reset password'>";
			}
			print "</form><form style='display:inline-block' class='pull-right' method='GET' action='.'><input type='hidden' name='m' value='summary'><input type='hidden' name='u' value='" . $u . "'>";
			if($userisbanned == 0) { print "<input type='submit' class='btn btn-danger pull-right' name='disable_user' value='Disable login'>"; }
			else { print "<input type='submit' class='btn btn-success pull-right' name='enable_user' value='Enable login'>"; }
			print "</form>";
		}
		print "</div></div>";
	}
	elsif($q->param('m') eq "view_event" && $q->param('e') && $q->param('c') && $logged_lvl >= to_int($cfg->load('client_lvl')))
	{
		headers("Clients");
		my $clientname = "Unknown";
		$sql = $db->prepare("SELECT name FROM clients WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('c')));
		while(my @res = $sql->fetchrow_array())
		{ $clientname = $res[0]; }
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $clientname . "</h3></div><div class='panel-body'>";
		$sql = $db->prepare("SELECT * FROM events WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('e')));
		while(my @res = $sql->fetchrow_array())
		{
			if($logged_lvl >= to_int($cfg->load('events_lvl')))
			{ 
				print "<form method='POST' action='.'><input type='hidden' name='m' value='view_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><input type='hidden' name='update_event' value='" . to_int($q->param('e')) . "'>";
				print "<p><div class='row'><div class='col-sm-12'>Event type: <b>" . $res[2] . "</b></div></div><div class='row'><div class='col-sm-12'>Event summary: <input type='text' class='form-control' name='event_summary' value=\"" . $res[3] . "\">";
			}
			else
			{
				print "<p><div class='row'><div class='col-sm-6'>Event type: <b>" . $res[2] . "</b></div><div class='col-sm-6'>Event summary: <b>" . $res[3] . "</b>";
			}
			print "</div></div></p><p><div class='row'><div class='col-sm-12'>Notes:<br>";
			if($logged_lvl >= to_int($cfg->load('events_lvl')))
			{ 
				print "<textarea class='form-control' name='event_notes' rows=10>" . $res[4] . "</textarea>";
			}
			else
			{
				print "<pre>" . $res[4] . "</pre>";
			}
			print "</div></div></p>";
			if($logged_lvl >= to_int($cfg->load('events_lvl')))
			{ 
				print "<input type='submit' class='btn btn-primary pull-right' value='Update event'></form>";
				print "<form method='GET' action='.'><input type='hidden' name='m' value='view_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><input type='hidden' name='delete_event' value='" . to_int($q->param('e')) . "'><input type='submit' class='btn btn-danger' onclick='return confirm(\"Are you sure?\");' value='Delete'></form>";
			}
		}
		print "</div></div>\n";
	}
	elsif($q->param('m') eq "view_client" && $q->param('c') && $logged_lvl >= to_int($cfg->load('client_lvl')))
	{
		headers("Clients");
		if($logged_lvl >= to_int($cfg->load('events_lvl')) && $q->param('new_event') && $q->param('event_type'))
		{
			my $notes = "";
			if($q->param('event_notes')) { $notes = sanitize_html($q->param('event_notes')); }
			$sql = $db->prepare("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?);");
			$sql->execute(to_int($q->param('c')), $logged_user, sanitize_html($q->param('event_type')), sanitize_html($q->param('new_event')), $notes, now());
			msg("New event added.", 3);
		}
		if($logged_lvl >= to_int($cfg->load('events_lvl')) && $q->param('event_summary') && $q->param('update_event'))
		{
			my $notes = "";
			if($q->param('event_notes')) { $notes = sanitize_html($q->param('event_notes')); }
			$sql = $db->prepare("UPDATE events SET summary = ?, notes = ? WHERE ROWID = ?;");
			$sql->execute(sanitize_html($q->param('event_summary')), $notes . "\n\nUpdated by " . $logged_user . " on " . now() . "\n", to_int($q->param('update_event')));
			msg("Event updated.", 3);
		}
		if($logged_lvl >= to_int($cfg->load('events_lvl')) && $q->param('delete_event'))
		{
			$sql = $db->prepare("DELETE FROM events WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('delete_event')));
			msg("Event deleted.", 3);
		}
		if($q->param('set_defaults') && $q->param('c') && $logged_lvl > 4)
		{
			$sql = $db->prepare("DELETE FROM billing_defaults WHERE client = ?;");
			$sql->execute(sanitize_html($q->param('set_defaults')));
			$sql = $db->prepare("INSERT INTO billing_defaults VALUES (?, ?, ?, ?);");
			$sql->execute(sanitize_html($q->param('set_defaults')), to_int($q->param('type')), sanitize_alpha($q->param('currency')), to_float($q->param('cost')));
			msg("Client default values updated.", 3);
		}
		$sql = $db->prepare("SELECT * FROM clients WHERE ROWID = ?;");
		$sql->execute(to_int($q->param('c')));
		while(my @res = $sql->fetchrow_array())
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $res[0] . "<span class='pull-right'>Last modified: <i>" . $res[4] . "</i></span></h3></div><div class='panel-body'>";
			if($logged_lvl > 4 && $q->param('edit'))
			{
				print "<form method='POST' action='.'><input type='hidden' name='m' value='save_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><p><div class='row'><div class='col-sm-6'><input type='text' class='form-control' name='contact' placeholder='Contact' maxlength='99' value=\"" . $res[2] . "\"></div><div class='col-sm-6'><select class='form-control' name='status'><option";
				if($res[1] eq "Prospect") { print " selected"; }
				print ">Prospect</option><option";
				if($res[1] eq "Contact") { print " selected"; }
				print ">Contact</option><option";
				if($res[1] eq "Supplier") { print " selected"; }
				print ">Supplier</option><option";
				if($res[1] eq "Paid") { print " selected"; }
				print ">Paid</option><option";
				if($res[1] eq "Unpaid") { print " selected"; }
				print ">Unpaid</option><option";
				if($res[1] eq "Closed") { print " selected"; }
				print ">Closed</option></select></div></div></p><p><textarea class='form-control' name='notes' placeholder='Notes' rows='10'>" . $res[3] . "</textarea></p><p><input type='submit' value='Delete' name='delete' class='btn btn-danger'><input type='submit' value='Save client' class='btn btn-primary pull-right'></form>";
			}
			else
			{
				print "<p><div class='row'><div class='col-sm-6'>Contact: <b>" . $res[2] . "</b></div><div class='col-sm-6'>Status: <b>" . $res[1] . "</b></div></div></p><p>Notes:<br><pre>" . $res[3] . "</pre></p>";
				if($logged_lvl > 4) { print "<form method='POST' action='.' class='form-group'><input type='hidden' name='m' value='view_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><input type='submit' class='btn btn-primary pull-right' name='edit' value='Edit client'></form>"; }
			}
			print "</div></div>\n";
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Events</h3></div><div class='panel-body'>";
			if($logged_lvl >= to_int($cfg->load('events_lvl')))
			{
				print "<h4>Add new event</h4><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='view_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><p><div class='row'><div class='col-sm-2'><select class='form-control' name='event_type'><option>Email dialog</option><option>Phone call</option><option>Online meeting</option><option>In-person meeting</option><option>Other contact</option></select></div><div class='col-sm-8'><input type='text' class='form-control' name='new_event' value='' placeholder='Event summary'></div><div class='col-sm-2'><input type='submit' value='Add event' class='btn btn-primary pull-right'></div></div></p><p><div class='row'><div class='col-sm-12'><textarea name='event_notes' class='form-control' placeholder='Event notes'></textarea></div></div></p></form><h4>Events log</h4>\n";
			}
			print "<table class='table table-striped' id='events_table'><thead><tr><th>User</th><th>Type</th><th>Summary</th><th>Date</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM events WHERE clientid = ?;");
			$sql->execute(to_int($q->param('c')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td><a href='./?m=view_event&e=" . $res[0] . "&c=" . to_int($q->param('c')) . "'>" . $res[4] . "</a></td><td>" . $res[6] . "</td></tr>\n";
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#events_table').DataTable({'order':[[3,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>\n";
			print "</div></div>\n";
			if($cfg->load('comp_billing') eq "on" && $cfg->load('comp_tickets') eq "on")
			{
				my $cost = 10.0;
				my $currency = "USD";
				my $type = 0;
				if($cfg->load('comp_time') eq "on") { $type = 1; }
				my $sql2 = $db->prepare("SELECT type,currency,cost FROM billing_defaults WHERE client = ?;");
				$sql2->execute($res[0]);
				while(my @res2 = $sql2->fetchrow_array())
				{
					$type = $res2[0];
					$currency = $res2[1];
					$cost = $res2[2];
				}
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Billing</h3></div><div class='panel-body'>";
				if($logged_lvl > 4)
				{
					print "<form method='POST' action='.'><input type='hidden' name='m' value='view_client'><input type='hidden' name='c' value='" . to_int($q->param('c')) . "'><input type='hidden' name='set_defaults' value=\"" . $res[0] . "\"><div class='row'><div class='col-sm-3'>Type: <select class='form-control' name='type'><option value='0'";
					if($type == 0) { print " selected"; }
					print ">Fixed</option><option value='1'";
					if($type == 1) { print " selected"; }
					print ">Hourly</option></select></div><div class='col-sm-3'>Cost: <input type='number' class='form-control' name='cost' value='" . to_float($cost) . "'></div><div class='col-sm-3'>Currency: <input type='text' maxlength='4' class='form-control' name='currency' value=\"" . $currency . "\"></div><div class='col-sm-3'><span class='pull-right'><input type='submit' value='Set' class='btn btn-primary'></span></div></div></form>";
				}
				else
				{
					print "<div class='row'><div class='col-sm-4'>Type: <b>";
					if($type == 0) { print "Fixed"; }
					else { print "Hourly"; }
					print "</b></div><div class='col-sm-4'>Cost: <b>" . $cost . "</b></div><div class='col-sm-4'>Currency: <b>" . $currency . "</b></div></div>";
				}
				print "<p><table class='table table-striped' id='billing_table'><thead><tr><th>Ticket ID</th><th>Hours</th><th>Cost</th></tr></thead><tbody>";
				$sql2 = $db->prepare("SELECT ticketid FROM billing WHERE client = ?;");
				$sql2->execute($res[0]);
				my $total = 0;
				while(my @res2 = $sql2->fetchrow_array())
				{
					print "<tr><td><a href='./?m=view_ticket&t=" . $res2[0] . "'>" . $res2[0] . "</td><td>";
					my $curhours = 0;
					my $sql3 = $db->prepare("SELECT spent FROM timetracking WHERE ticketid = ?;");
					$sql3->execute($res2[0]);
					while(my @res3 = $sql3->fetchrow_array())
					{
						$curhours += to_float($res3[0]);
					}
					print $curhours . "</td><td>\$";
					if($cfg->load('comp_time') eq "on" && $type == 1)
					{
						print $curhours * to_float($cost);
						$total += $curhours * to_float($cost);
					}
					else
					{
						print $cost;
						$total += $cost;
					}
					print "</td></tr>\n";
				}
				print "</tbody><tfoot><tr><th>Total</th><th></th><th>\$" . $total . "</th></tr>\n";
				print "</tfoot></table><script>\$(document).ready(function(){\$('#billing_table').DataTable({'order':[[0,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></p></div></div>\n";
			}
		}
		if($cfg->load('comp_items') eq "on")
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Related items</h3></div><div class='panel-body'><table class='table table-striped' id='clientitems_table'><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>Status</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT ROWID,* FROM items WHERE clientid = ?;");
			$sql->execute(to_int($q->param('c')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[2] . "</td><td><a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[3] . "</td><td>";
				if(to_int($res[7]) == 0) { print "<font color='red'>Unavailable</font>"; }
				elsif(to_int($res[7]) == 1) { print "<font color='green'>Available</font>"; }
				elsif(to_int($res[7]) == 2) { print "<font color='orange'>Waiting approval for: " . $res[8] . "</font>"; }
				else { print "<font color='red'>Checked out by: " . $res[8] . "</font>"; }
				print "</td></tr>\n";
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#clientitems_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
		}
	}
	elsif($q->param('m') eq "add_client" && $logged_lvl > 4)
	{
		headers("Clients");
		if(!$q->param('name') || !$q->param('contact') || !$q->param('status'))
		{
			my $text = "Required fields missing: ";
			if(!$q->param('name')) { $text .= "<span class='label label-danger'>Client name</span> "; }
			if(!$q->param('contact')) { $text .= "<span class='label label-danger'>Contact</span> "; }
			if(!$q->param('status')) { $text .= "<span class='label label-danger'>Status</span> "; }
			$text .= " Please go back and try again.";
			msg($text, 0);
		}
		else
		{
			my $notes = "";
			if($q->param('notes')) { $notes = sanitize_html($q->param('notes')); }
			$sql = $db->prepare("INSERT INTO clients VALUES (?, ?, ?, ?, ?);");
			$sql->execute(sanitize_html($q->param('name')), sanitize_html($q->param('status')), sanitize_html($q->param('contact')), $notes, now());
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=clients'>Client added.", 3);
		}
	}
	elsif($q->param('m') eq "clear_log" && $logged_lvl > 5)
	{
		headers("System log");
		$sql = $db->prepare("DELETE FROM log;");
		$sql->execute();
		msg("Log cleared. Press <a href='./?m=log'>here</a> to continue.", 3);
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
					msg("<meta http-equiv='REFRESH' content='1;url=.'>Email address updated.", 3);
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
		$sql = $db->prepare("DELETE FROM sessions WHERE user = ?;");
		$sql->execute($logged_user);
		msg("You have now logged out. Press <a href='.'>here</a> to go back to the login page.", 3);
	}
	elsif($q->param('m') eq "change_lvl" && $logged_lvl > 4 && $q->param('u') && defined($q->param('newlvl')))
	{
		headers("Users management");
		if(to_int($q->param('newlvl')) < 0 || to_int($q->param('newlvl')) > 5)
		{
			msg("Invalid access level. Please go back and try again.", 0);
		}
		else
		{
			$sql = $db->prepare("UPDATE users SET level = ? WHERE name = ?;");
			$sql->execute(to_int($q->param('newlvl')), sanitize_alpha($q->param('u')));
			msg("Updated access level for user <b>" . sanitize_alpha($q->param('u')) . "</b>. Press <a href='./?m=users'>here</a> to continue.", 3);
			logevent("Level change: " . sanitize_alpha($q->param('u')));
		}
	}
	elsif($q->param('m') eq "change_lvl" && $logged_lvl > 4 && $q->param('u'))
	{
		headers("Users management");
		print "<p><form method='POST' action='.'><input type='hidden' name='m' value='change_lvl'><input type='hidden' name='u' value='" . sanitize_alpha($q->param('u')) . "'>Select a new access level for user <b>" . sanitize_alpha($q->param('u')) . "</b>: <select name='newlvl'><option>0</option><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select><br><input class='btn btn-primary' type='submit' value='Change level'></form></p><br>\n";
		print "<p>Here is a list of available NodePoint levels:</p>\n";
		print "<table class='table table-striped'><tr><th>Level</th><th>Name</th><th>Description</th></tr><tr><td>6</td><td>NodePoint Admin</td><td>Can change basic NodePoint settings</td></tr><td>5</td><td>Users management</td><td>Can manage users, reset passwords, edit clients</td></tr><tr><td>4</td><td>" . $items{"Product"} . "s management</td><td>Can add, retire and edit " . lc($items{"Product"}) . "s, edit articles and items</td></tr><tr><td>3</td><td>Tickets management</td><td>Can create " . lc($items{"Release"}) . "s, update tickets, track time</td></tr><tr><td>2</td><td>Restricted view</td><td>Can view restricted tickets and " . lc($items{"Product"}) . "s</td></tr><tr><td>1</td><td>Authorized users</td><td>Can create tickets and comments</td></tr><tr><td>0</td><td>Unauthorized users</td><td>Can view private tickets</td></tr></table>\n";
	}
	elsif($q->param('m') eq "reset_pass" && $logged_lvl > 4 && $q->param('u'))
	{
		headers("Users management");
		my $newpass = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..8;
		$sql = $db->prepare("UPDATE users SET pass = ? WHERE name = ?;");
		$sql->execute(sha1_hex($newpass), sanitize_alpha($q->param('u')));
		msg("Password reset for user <b>" . sanitize_alpha($q->param('u')) . "</b>. The new password is  <b>" . $newpass . "</b>  Press <a href='./?m=users'>here</a> to continue.", 3);
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
			if($cfg->load("article_html") eq "on") { $sql->execute(sanitize_html($q->param('title')), $q->param('article'), to_int($q->param('published')), now(), to_int($q->param('productid')), to_int($q->param('id'))); }
			else { $sql->execute(sanitize_html($q->param('title')), sanitize_html($q->param('article')), to_int($q->param('published')), now(), to_int($q->param('productid')), to_int($q->param('id'))); }
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=articles'>Article <b>" . to_int($q->param('id')) . "</b> saved.", 3);
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
			$sql = $db->prepare("SELECT last_insert_rowid();");
			$sql->execute();
			my $lastrowid = 0;
			while(my @res = $sql->fetchrow_array())
			{
				$lastrowid = to_int($res[0]);
			}
			msg("<meta http-equiv='REFRESH' content='1;url=./?kb=" . $lastrowid . "'>New draft article <b>" . sanitize_html($q->param('title')) . "</b> added.", 3);
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
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add a new article</h3></div><div class='panel-body'>\n";
			print "<form method='GET' action='.' data-toggle='validator' role='form'><p><div class='row'><div class='col-sm-6'><input type='hidden' name='m' value='add_article'><input placeholder='Title' class='form-control' type='text' name='title' maxlength='50' required></div><div class='col-sm-6'><select class='form-control' name='productid'><option value='0'>All " . lc($items{"Product"}) . "s</option>";
			for(my $i = 1; $i < scalar(@products); $i++)
			{
				if($products[$i]) { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; }
			}
			print "</select></div></div></p><p><input type='submit' class='btn btn-primary pull-right' value='Add article'></p></form></div></div>\n";
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Support articles</h3></div><div class='panel-body'><table class='table table-striped' id='articles_table'><thead>\n";
		if($logged_lvl > 3) { print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Last update</th></tr></thead><tbody>"; }
		else { print "<tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Last update</th></tr></thead><tbody>"; }
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
		print "</tbody></table><script>\$(document).ready(function(){\$('#articles_table').DataTable({'order':[[2,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
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
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Product"} . " information</h3></div><div class='panel-body'>\n";
				if($logged_lvl > 3 && $q->param('edit')) { print "<form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='edit_product'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'>\n"; }
				if($logged_lvl > 3 && $q->param('edit')) { print "<p><div class='row'><div class='col-sm-6'>" . $items{"Product"} . " name: <input class='form-control' type='text' name='product_name' value=\"" . $res[1] . "\"></div><div class='col-sm-6'>" . $items{"Model"} . ": <input class='form-control' type='text' name='product_model' value=\"" . $res[2] . "\"></div></div></p>\n"; }
				else { print "<p><div class='row'><div class='col-sm-6'>Product name: <b>" . $res[1] . "</b></div><div class='col-sm-6'>" . $items{"Model"} . ": <b>" . $res[2] . "</b></div></div></p>\n"; }
				print "<p><div class='row'><div class='col-sm-6'>Created on: <b>" . $res[6] . "</b></div><div class='col-sm-6'>Last modified on: <b>" . $res[7] . "</b></div></div></p>\n";
				if($logged_lvl > 3 && $q->param('edit'))
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
				my @remusers;
				while(my @res2 = $sql2->fetchrow_array())
				{
					print " " . $res2[0];
					push @remusers, $res2[0];
				}
				print "</b>";
				if($logged_lvl > 3 && $q->param('edit'))
				{ 
					print "<br>Add user: <select name='add_auto_assign'><option></option>";
					my $sql3 = $db->prepare("SELECT name FROM users WHERE level > 2 ORDER BY name;");
					$sql3->execute();
					while(my @res3 = $sql3->fetchrow_array()) { print "<option>" . $res3[0] . "</option>"; }
					print "</select> Remove: <select name='rem_auto_assign'><option></option>";
					foreach my $rem (@remusers) { print "<option>" . $rem . "</option>"; }
					print "</select>";
				}
				print "</b></div></div></p>\n";
				if($logged_lvl > 3 && $q->param('edit')) { print "<p>Description:<span class='pull-right'><img title='Header' src='icons/header.png' style='cursor:pointer' onclick='javascript:md_header()'> <img title='Bold' src='icons/bold.png' style='cursor:pointer' onclick='javascript:md_bold()'> <img title='Italic' src='icons/italic.png' style='cursor:pointer' onclick='javascript:md_italic()'> <img title='Code' src='icons/code.png' style='cursor:pointer' onclick='javascript:md_code()'> <img title='Image' src='icons/image.png' style='cursor:pointer' onclick='javascript:md_image()'> <img title='Link' src='icons/link.png' style='cursor:pointer' onclick='javascript:md_link()'> <img title='List' src='icons/list.png' style='cursor:pointer' onclick='javascript:md_list()'></span><br><textarea id='markdown' rows='10' name='product_desc' class='form-control'>" . $res[3] . "</textarea></p>\n"; }
				else { print "<hr>" . markdown($res[3]) . "\n"; }
				if($res[4] ne "") { print "<p><img src='./?file=" . $res[4] . "' style='max-width:95%'></p>\n"; }
				if($logged_lvl > 3 && $q->param('edit')) { print "<input class='btn btn-primary pull-right' type='submit' value='Update " . lc($items{"Product"}) . "'>Change " . lc($items{"Product"}) . " image: <input type='file' name='product_screenshot'></form>\n"; }
				if($logged_user eq $cfg->load("admin_name") && $q->param('edit')) { print "<form method='GET' action='.'><input type='hidden' name='m' value='confirm_delete'><input type='hidden' name='productid' value='" . to_int($q->param('p')) . "'><input type='submit' class='btn btn-danger pull-right' value='Permanently delete this " . lc($items{"Product"}) . "'></form>"; }
				if($logged_lvl > 3  && !$q->param('edit'))
				{
					print "<form method='GET' action='.'><input type='hidden' name='m' value='view_product'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input class='btn btn-primary pull-right' type='submit' name='edit' value='Edit " . lc($items{"Product"}) . "'></form>";
				}
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
			if($vis eq "Public" || ($vis eq "Private" && $logged_user ne "") || ($vis eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3)
			{
				print "<a name=productdata></a>";
				my $isassigned = 0;
				if($logged_user eq $cfg->load("admin_name")) { $isassigned = 1; }
				$sql = $db->prepare("SELECT * FROM autoassign WHERE productid = ? AND user = ?;");
				$sql->execute(to_int($q->param('p')), $logged_user);
				while(my @res = $sql->fetchrow_array()) { $isassigned = 1; }
				if($q->param('tab') eq "tasks")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>";
					if($logged_lvl >= to_int($cfg->load('tasks_lvl')) && $q->param('add_step') && $q->param('name') && $q->param('user') && $q->param('due'))
					{
						if($q->param('due') !~ m/[0-9]{2}\/[0-9]{2}\/[0-9]{4}/)
						{
							msg("Due date must be in the format: mm/dd/yyyy.", 0);
						}
						else
						{
							$sql = $db->prepare("INSERT INTO steps VALUES (?, ?, ?, ?, ?);");
							$sql->execute(to_int($q->param('p')), sanitize_html($q->param('name')), sanitize_alpha($q->param('user')), 0, sanitize_html($q->param('due')));
							my $prod = "";
							$sql = $db->prepare("SELECT name FROM products WHERE ROWID = ?;");
							$sql->execute(to_int($q->param('p')));
							while(my @res = $sql->fetchrow_array()) { $prod = $res[0]; }
							notify(sanitize_alpha($q->param('user')), "New task assigned to you", "A new task has been added for you on " . lc($items{"Product"}) . " \"" . $prod . "\":\n\nTask description: " . sanitize_html($q->param('name')) . "\nDue by: " . sanitize_html($q->param('due')));
							$sql = $db->prepare("INSERT INTO steps_log VALUES (?, ?, ?, ?)");
							$sql->execute(to_int($q->param('p')), $logged_user, "Added new task <i>" . sanitize_html($q->param('name')) . "</i> to user <i>" . sanitize_alpha($q->param('user')) . "</i> due by <i>" . sanitize_html($q->param('due')) . "</i>", now());
							msg("Task added.", 3);
						}
					}
					if($logged_lvl >= to_int($cfg->load('tasks_lvl')) && $q->param("delete_step"))
					{
						my $p = 0;
						my $stepname = "";
						$sql = $db->prepare("SELECT productid,name FROM steps WHERE ROWID = ?;");
						$sql->execute(to_int($q->param('delete_step')));
						while(my @res = $sql->fetchrow_array()) { $p = to_int($res[0]); $stepname = $res[1]; }
						$sql = $db->prepare("DELETE FROM steps WHERE ROWID = ?;");
						$sql->execute(to_int($q->param('delete_step')));
						$sql = $db->prepare("INSERT INTO steps_log VALUES (?, ?, ?, ?)");
						$sql->execute($p, $logged_user, "Deleted task <i>" . $stepname . "</i>", now());
						msg("Task removed.", 3);
					}
					if($q->param('clear_log') && $logged_lvl > 5)
					{
						$sql = $db->prepare("DELETE FROM steps_log WHERE productid = ?;");
						$sql->execute(to_int($q->param('p')));
					}
					if($logged_lvl >= to_int($cfg->load('tasks_lvl')) && $vis ne "Archived" && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='tasks'><h4>Add a new task</h4><p><div class='row'><div class='col-sm-12'><input placeholder='Description' class='form-control' name='name' maxlength='200' required></div></div></p><p><div class='row'><div class='col-sm-5'>Assign user:<br><select name='user' class='form-control'>";
						$sql = $db->prepare("SELECT name FROM users WHERE level > 0 ORDER BY name;");
						$sql->execute();
						while(my @res = $sql->fetchrow_array()) { print "<option>" . $res[0] . "</option>"; }
						print "</select></div><div class='col-sm-5'>Due by:<br><input type='text' class='form-control datepicker' name='due' placeholder='mm/dd/yyyy' required></div><div class='col-sm-2'><input class='btn btn-primary pull-right' name='add_step' type='submit' value='Add task'></div></div></p></form><hr><h4>Current tasks</h4>\n";
					}
					print "<table class='table table-stripped' id='tasks_table'><thead><tr><th>Task</th><th>Assigned to</th><th>Completion</th><th>Due by</th></tr></thead><tbody>";
					$sql = $db->prepare("SELECT ROWID,* FROM steps WHERE productid = ?;");
					$sql->execute(to_int($q->param('p')));
					my $m = localtime->strftime('%m');
					my $y = localtime->strftime('%Y');
					my $d = localtime->strftime('%d');
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td>" . $res[4] . "%</td><td>";
						my @dueby = split(/\//, $res[5]);
						if(to_int($res[4]) == 100) { print "<font color='green'>Completed</font>"; }
						elsif($dueby[2] < $y || ($dueby[2] == $y && $dueby[0] < $m) || ($dueby[2] == $y && $dueby[0] == $m && $dueby[1] < $d)) { print "<font color='red'>Overdue</font>"; }
						else { print $res[5]; }
						if($logged_lvl >= to_int($cfg->load('tasks_lvl')) && $vis ne "Archived") { print "<span class='pull-right'><form method='POST' action='.'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='tasks'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input type='hidden' name='m' value='delete_step'><input type='hidden' name='delete_step' value=\"" . $res[0] . "\"><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Really remove this task?\");' value='X'></form></span>"; }
						print "</td></tr>";
					}				
					print "</tbody></table><script>\$(document).ready(function(){\$('#tasks_table').DataTable({'order':[[3,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>";
					if($logged_lvl > 3 && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<hr><h4>Completion log</h4>";
						if($logged_lvl > 5) { print "<p><form style='display:inline' method='POST' action='./?m=auto'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='tasks'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input class='btn btn-danger pull-right' name='clear_log' onclick='return confirm(\"Are you sure?\");' type='submit' value='Clear log'><br></form></p>"; }
						print "<table class='table table-stripped' id='steps_log_table'><thead><tr><th>User</th><th>Event</th><th>Date</tr></thead><tbody>";
						$sql = $db->prepare("SELECT * FROM steps_log WHERE productid = ? ORDER BY ROWID DESC LIMIT 5000;");
						$sql->execute(to_int($q->param('p')));
						while(my @res = $sql->fetchrow_array())
						{
							print "<tr><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>";
						}
						print "</tbody></table><script>\$(document).ready(function(){\$('#steps_log_table').DataTable({'order':[[2,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>";
					}
					print "</div></div>\n";
				}
				elsif($q->param('tab') eq "secrets")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>";
					if($q->param('clear_log') && $logged_lvl > 5)
					{
						$sql = $db->prepare("DELETE FROM secrets_log WHERE productid = ?;");
						$sql->execute(to_int($q->param('p')));
					}
					if($q->param('view_secret') && $q->param('secret') && $logged_lvl >= to_int($cfg->load('view_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						$sql = $db->prepare("SELECT account,secret FROM secrets WHERE ROWID = ?;");
						$sql->execute(to_int($q->param('secret')));
						while(my @res = $sql->fetchrow_array())
						{
							msg($res[0] . " / " . RC4($cfg->load("enc_key"), decode_base64($res[1])), 2);
							my $sql2 = $db->prepare("INSERT INTO secrets_log VALUES (?, ?, ?, ?, ?)");
							$sql2->execute(to_int($q->param('p')), $logged_user, $res[0], "Viewed secret", now());
						}
					}
					if($q->param('change_secret') && $q->param('new_secret') && $q->param('secret') && $logged_lvl >= to_int($cfg->load('add_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						my $account = "Unknown";
						$sql = $db->prepare("SELECT account FROM secrets WHERE ROWID = ?;");
						$sql->execute(to_int($q->param('secret')));
						while(my @res = $sql->fetchrow_array()) { $account = $res[0]; }
						$sql = $db->prepare("UPDATE secrets SET secret = ? WHERE ROWID = ?");
						$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('new_secret'))), to_int($q->param('secret')));
						msg("Secret changed.", 3);
						$sql = $db->prepare("INSERT INTO secrets_log VALUES (?, ?, ?, ?, ?)");
						$sql->execute(to_int($q->param('p')), $logged_user, $account, "Changed secret", now());
					}
					if($q->param('delete_secret') && $q->param('secret') && $logged_lvl >= to_int($cfg->load('add_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						my $account = "Unknown";
						$sql = $db->prepare("SELECT account FROM secrets WHERE ROWID = ?;");
						$sql->execute(to_int($q->param('secret')));
						while(my @res = $sql->fetchrow_array()) { $account = $res[0]; }
						$sql = $db->prepare("DELETE FROM secrets WHERE ROWID = ?");
						$sql->execute(to_int($q->param('secret')));
						msg("Secret removed.", 3);
						$sql = $db->prepare("INSERT INTO secrets_log VALUES (?, ?, ?, ?, ?)");
						$sql->execute(to_int($q->param('p')), $logged_user, $account, "Deleted secret", now());
					}
					if($q->param('add_secret') && $q->param('account') && $q->param('secret') && $logged_lvl >= to_int($cfg->load('add_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						my $note = "";
						if($q->param('note')) { $note = sanitize_html($q->param('note')); }
						$sql = $db->prepare("INSERT INTO secrets VALUES (?, ?, ?, ?, ?, ?);");
						$sql->execute(to_int($q->param('p')), $logged_user, $note, sanitize_html($q->param('account')), encode_base64(RC4($cfg->load("enc_key"), $q->param('secret'))), now());
						msg("Secret added.", 3);
						$sql = $db->prepare("INSERT INTO secrets_log VALUES (?, ?, ?, ?, ?)");
						$sql->execute(to_int($q->param('p')), $logged_user, sanitize_html($q->param('account')), "Added secret", now());
					}
					if($logged_lvl >= to_int($cfg->load('add_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='secrets'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><h4>Add a new secret</h4><p><div class='row'><div class='col-sm-6'><input placeholder='Account name' class='form-control' name='account' maxlength='30' required></div><div class='col-sm-6'><input placeholder='Secret' class='form-control' name='secret' maxlength='200' required></div></div></p><p><div class='row'><div class='col-sm-12'><input placeholder='Note' class='form-control' name='note' maxlength='200'></div></div></p><p><input class='btn btn-primary pull-right' type='submit' name='add_secret' value='Add secret'></p></form><br><hr><h4>Known secrets</h4>\n";
					}
					print "<table class='table table-stripped' id='secrets_table'><thead><tr><th>Account</th><th>Note</th><th>Added by</th><th>Date</th></tr></thead><tbody>";
					$sql = $db->prepare("SELECT ROWID,* FROM secrets WHERE productid = ?;");
					$sql->execute(to_int($q->param('p')));
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[4] . "</td><td>" . $res[3] . "</td><td>" . $res[2] . "</td><td>" . $res[6] . "<span class='pull-right'><form method='POST' action='.'><input type='hidden' name='m' value='view_product'><input type='hidden' name='new_secret' value=''><input type='hidden' name='tab' value='secrets'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input type='hidden' name='secret' value=\"" . $res[0] . "\">";
						if($logged_lvl >= to_int($cfg->load('view_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on")) { print "<input class='btn btn-primary' name='view_secret' type='submit' value='View'>"; }
						if($logged_lvl >= to_int($cfg->load('add_secrets')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on")) { print " <input class='btn btn-primary' name='change_secret' type='submit' onclick='this.form.new_secret.value=window.prompt(\"Change secret to:\");' value='Change'> <input class='btn btn-danger' name='delete_secret' type='submit' onclick='return confirm(\"Really remove this secret?\");' value='X'>"; }
						print "</form></nobr></span></td></tr>";
					}				
					print "</tbody></table><script>\$(document).ready(function(){\$('#secrets_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>";
					if($logged_lvl > 3 && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<hr><h4>Transaction log</h4>";
						if($logged_lvl > 5) { print "<p><form style='display:inline' method='POST' action='./?m=auto'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='secrets'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input class='btn btn-danger pull-right' name='clear_log' onclick='return confirm(\"Are you sure?\");' type='submit' value='Clear log'><br></form></p>"; }
						print "<table class='table table-stripped' id='secrets_log_table'><thead><tr><th>User</th><th>Account</th><th>Event</th><th>Date</tr></thead><tbody>";
						$sql = $db->prepare("SELECT * FROM secrets_log WHERE productid = ? ORDER BY ROWID DESC LIMIT 5000;");
						$sql->execute(to_int($q->param('p')));
						while(my @res = $sql->fetchrow_array())
						{
							print "<tr><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td><td>" . $res[4] . "</td></tr>";
						}
						print "</tbody></table><script>\$(document).ready(function(){\$('#secrets_log_table').DataTable({'order':[[3,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>";
					}					
					print "</div></div>\n";
				}
				elsif($q->param('tab') eq "articles")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>";
					if($logged_lvl > 3)
					{
						print "<h4>Add a new " . lc($items{"Product"}) . " article</h4>\n";
						print "<p><form method='GET' action='.' data-toggle='validator' role='form'><div class='row'><div class='col-sm-8'><input type='hidden' name='m' value='add_article'><input placeholder='Title' class='form-control' type='text' name='title' maxlength='50' required><input type='hidden' value='" . to_int($q->param('p')) . "' name='productid'></div><div class='col-sm-4'><input type='submit' class='btn btn-primary pull-right' value='Add article'></div></div></form></p><hr><h4>" . $items{"Product"} . " articles</h4>\n";
					}
					print "<table class='table table-striped' id='relatedarticles_table'><thead>\n";
					if($logged_lvl > 3) { print "<tr><th>ID</th><th>Title</th><th>Status</th><th>Last update</th></tr></thead><tbody>"; }
					else { print "<tr><th>ID</th><th>Title</th><th>Last update</th></tr></thead><tbody>"; }
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
					print "</tbody></table><script>\$(document).ready(function(){\$('#relatedarticles_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
				}
				elsif($q->param('tab') eq "items")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>";
					if($logged_lvl > 3)
					{
						print "<h4>Add a new " . lc($items{"Product"}) . " item</h4>";
						print "<form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='items'>\n";
						print "<p><div class='row'><div class='col-sm-4'>Item type: <select name='type' class='form-control'><option>Desktop</option><option>Laptop</option><option>Server</option><option>Keyboard</option><option>Mouse</option><option>Display</option><option>Phone</option><option>Printer</option><option>Peripheral</option><option>Software</option><option>Furniture</option><option>Tool</option><option>Vehicle</option><option>Other</option></select></div><div class='col-sm-4'>Item name: <input type='text' maxlength='50' class='form-control' name='name' required></div><div class='col-sm-4'>Serial number: <input type='text' maxlength='30' class='form-control' name='serial' required></div></div></p><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'><input type='hidden' name='client_id' value='None'>\n";
						print "<p>Information provided on checkout: <textarea name='info' class='form-control'></textarea></p>";
						print "<p><input type='submit' name='new_item' class='btn btn-primary pull-right' value='Add item'><label><input type='checkbox' name='approval'> Require approval for checkout</label></p></form><hr>\n";
						print "<h4>" . $items{"Product"} . " items</h4>";
					}
					print "<table class='table table-striped' id='relateditems_table'><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>Status</th></tr></thead><tbody>";
					$sql = $db->prepare("SELECT ROWID,* FROM items WHERE productid = ?;");
					$sql->execute(to_int($q->param('p')));
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[2] . "</td><td><a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[3] . "</td><td>";
						if(to_int($res[7]) == 0) { print "<font color='red'>Unavailable</font>"; }
						elsif(to_int($res[7]) == 1) { print "<font color='green'>Available</font>"; }
						elsif(to_int($res[7]) == 2) { print "<font color='orange'>Waiting approval for: " . $res[8] . "</font>"; }
						else { print "<font color='red'>Checked out by: " . $res[8] . "</font>"; }
						print "</td></tr>\n";
					}
					print "</tbody></table><script>\$(document).ready(function(){\$('#relateditems_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
				}
				elsif($q->param('tab') eq "tickets")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>";
					if($logged_lvl > 0  || $cfg->load("guest_tickets") eq "on")
					{
						print "<p><form method='POST' action='.'><div class='row'><div class='col-sm-12'><input type='hidden' name='product_id' value='" . to_int($q->param('p')) . "'><input type='hidden' name='m' value='new_ticket'><input class='btn btn-primary' type='submit' value='Add a new " . lc($items{"Product"}) . " ticket'></div></div></form></p><hr>\n";
						if($cfg->load("hide_close") eq "on") { print "<h4>Active " . lc($items{"Product"}) . " tickets</h4>"; }
						else { print "<h4>" . $items{"Product"} . " tickets</h4>"; }
					}
					print "<table class='table table-stripped' id='tickets_table'><thead><tr><th>ID</th><th>User</th><th>Title</th><th>Status</th><th>Date</th></tr></thead><tbody>\n";
					if($cfg->load("hide_close") eq "on") { $sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? AND status != 'Closed' ORDER BY ROWID DESC;"); }
					else { $sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE productid = ? ORDER BY ROWID DESC;"); }
					$sql->execute(to_int($q->param('p')));
					while(my @res = $sql->fetchrow_array())
					{
						if(($cfg->load("default_vis") eq "Public" || ($cfg->load("default_vis") eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $logged_lvl > 1))
						{ 
							print "<tr><td><nobr>";
							if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
							elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
							else { print "<img src='icons/normal.png' title='Normal'> "; }
							print $res[0] . "</nobr></td><td>" . $res[3] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; 
						}
					}
					print "</tbody></table><script>\$(document).ready(function(){\$('#tickets_table').DataTable({'order':[[0,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
					print "</div></div>\n";
				}
				elsif($q->param('tab') eq "files" && $cfg->load('comp_files') eq "on")
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation' class='active'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>\n";
					my $filedata = "";
					my $filename = "";
					if($q->param('delete_file') && $logged_lvl >= to_int($cfg->load('upload_lvl')))
					{
						$filedata = sanitize_alpha($q->param('delete_file'));
						if(length($filedata) == 36)
						{
							open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
							print $OUTFILE "This file is no longer available.";
							close($OUTFILE);
							$sql = $db->prepare("DELETE FROM files WHERE file = ?;");
							$sql->execute($filedata);
							$sql = $db->prepare("DELETE FROM files_product WHERE file = ?;");
							$sql->execute($filedata);
							msg("File <b>" . $filedata . "</b> removed.", 3);				
						}
					}
					if($q->param('attach_file') && $logged_lvl >= to_int($cfg->load('upload_lvl')))
					{
						eval
						{
							my $lightweight_fh = $q->upload('attach_file');
							if(defined $lightweight_fh)
							{
								my $tmpfilename = $q->tmpFileName($lightweight_fh);
								$filedata = Data::GUID->new;
								$filename = substr(sanitize_html($q->param('attach_file')), 0, 40);
								my $file_size = (-s $tmpfilename);
								if($file_size > to_int($cfg->load('max_size')))
								{
									msg("File size is larger than accepted value.", 0);
								}
								elsif($cfg->load('upload_exts') ne "" && index($cfg->load('upload_exts'), (split /\./, $filename)[-1]) == -1)
								{
									msg("File type is not in the list of allowed extensions.", 0);
								}
								else
								{
									my $io_handle = $lightweight_fh->handle;
									binmode($io_handle);
									my ($buffer, $bytesread);
									open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
									while($bytesread = $io_handle->read($buffer,1024))
									{
										print $OUTFILE $buffer;
									}
									close($OUTFILE);
									$sql = $db->prepare("INSERT INTO files VALUES (?, ?, ?, ?, ?);");
									$sql->execute($logged_user, $filedata, $filename, now(), to_int($file_size));
									$sql = $db->prepare("INSERT INTO files_product VALUES (?, ?);");
									$sql->execute(to_int($q->param('p')), $filedata);
									msg("File <b>" . $filedata . "</b> uploaded.", 3);				
								}
							}
						};
						if($@)
						{
							msg("File uploading to <b>" . $cfg->load('upload_folder') . $cfg->sep . $filedata . "</b> failed.", 0); 
						}
					}
					if($logged_lvl >= to_int($cfg->load('upload_lvl')) && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<h4>Add a new " . lc($items{"Product"}) . " file</h4>\n";
						print "<form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='files'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><p>Add new file: <input type='file' name='attach_file'><input class='btn btn-primary pull-right' type='submit' value='Upload'></p></form>\n";
						print "<br><hr><h4>" . $items{"Product"} . " files</h4>\n";
					}
					$sql = $db->prepare("SELECT files.* FROM files INNER JOIN files_product ON files.file = files_product.file WHERE files_product.productid = ?;");
					$sql->execute(to_int($q->param('p')));
					print "<table class='table table-striped' id='files_table'><thead><tr><th>File name</th><th>File size</th><th>Uploaded by</th><th>Date</th><th>Hits</th><th>Download link</th></tr></thead><tbody>\n";
					while(my @res = $sql->fetchrow_array())
					{
						my $accesscount = 0;
						my $sql2 = $db->prepare("SELECT COUNT(*) FROM file_access WHERE file = ?;");
						$sql2->execute($res[1]);
						while(my @res2 = $sql2->fetchrow_array()) { $accesscount = to_int($res2[0]); }
						print "<tr><td>" . $res[2] . "</td><td>" . to_int($res[4]) . "</td><td>" . $res[0] . "</td><td>" . $res[3] . "</td><td>" . $accesscount . "</td><td><a href='./?file=" . $res[1] . "'>" . $res[1] . "</a>";
						if($logged_lvl >= to_int($cfg->load('upload_lvl'))) { print "<span class='pull-right'><form method='POST' action='.'><input type='hidden' name='m' value='view_product'><input type='hidden' name='tab' value='files'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input type='hidden' name='delete_file' value=\"" . $res[1] . "\"><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Really remove this file?\");' value='X'></form></span>"; }
						print "</td></tr>\n";
					}
					print "</tbody></table><script>\$(document).ready(function(){\$('#files_table').DataTable({'order':[[0,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>\n";
					print "</div></div>\n";
				}
				else
				{
					print "<ul class='nav nav-pills nav-tabs'><li role='presentation' class='active'><a href='./?m=view_product&p=" . to_int($q->param('p')) . "#productdata'>" . $items{"Release"} . "s</a></li>";
					if($cfg->load('comp_steps') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=tasks&p=" . to_int($q->param('p')) . "#productdata'>Tasks</a></li>"; }
					if($cfg->load('comp_secrets') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=secrets&p=" . to_int($q->param('p')) . "#productdata'>Secrets</a></li>"; }
					if($cfg->load('comp_tickets') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=tickets&p=" . to_int($q->param('p')) . "#productdata'>Tickets</a></li>"; }
					if($cfg->load('comp_articles') eq "on") { print "<li role='presentation'><a href='./?m=view_product&tab=articles&p=" . to_int($q->param('p')) . "#productdata'>Articles</a></li>"; }
					if($cfg->load('comp_items') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=items&p=" . to_int($q->param('p')) . "#productdata'>Items</a></li>"; }
					if($cfg->load('comp_files') eq "on" && $logged_user ne "") { print "<li role='presentation'><a href='./?m=view_product&tab=files&p=" . to_int($q->param('p')) . "#productdata'>Files</a></li>"; }
					print "</ul>\n";
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-body'>\n";
					if($logged_lvl > 2 && $q->param("delete_release"))
					{
						$sql = $db->prepare("DELETE FROM releases WHERE productid = ? AND ROWID = ?;");
						$sql->execute(to_int($q->param('p')), to_int($q->param('delete_release')));
						msg($items{"Release"} . " removed.", 3);
					}
					if($logged_lvl > 2 && $q->param("add_release") && $q->param('release_version') && $q->param('release_notes'))
					{
						if(length(sanitize_html($q->param('release_version'))) > 50 || length(sanitize_html($q->param('release_notes'))) > 999)
						{
							msg("Version should be less than 50 characters, notes should be less than 1,000 characters. Please go back and try again.", 0);
						}
						else
						{
							$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
							$sql->execute(to_int($q->param('p')));
							my $found;
							while(my @res = $sql->fetchrow_array())
							{
								if(lc($res[2]) eq lc(sanitize_html($q->param('release_version')))) { $found = 1; }
							}
							if($found)
							{
								msg("This " . lc($items{"Release"}) . " already exists.", 0);
							}
							else
							{
								$sql = $db->prepare("INSERT INTO releases VALUES (?, ?, ?, ?, ?);");
								$sql->execute(to_int($q->param('p')), $logged_user, sanitize_html($q->param('release_version')), sanitize_html($q->param('release_notes')), now());
								msg($items{"Release"} . " added.", 3);
							}
						}
					}
					if($logged_lvl > 2 && $vis ne "Archived" && ($isassigned == 1 || $cfg->load('need_assign') ne "on"))
					{
						print "<h4>Add a new " . lc($items{"Release"}) . "</h4><form method='POST' action='.' data-toggle='validator' role='form'>\n";
						print "<input type='hidden' name='m' value='view_product'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><div class='row'><div class='col-sm-4'>" . $items{"Release"} . ": <input type='text' class='form-control' name='release_version' required></div><div class='col-sm-6'>Notes or link: <input type='text' name='release_notes' class='form-control' required></div><div class='col-sm-2'><input class='btn btn-primary pull-right' type='submit' name='add_release' value='Add " . lc($items{"Release"}) . "'></div></div></form><hr><h4>Current " . lc($items{"Release"}) . "s</h4>\n";
					}
					print "<table class='table table-striped' id='releases_table'>\n";
					print "<thead><tr><th>" . $items{"Release"} . "</th><th>User</th><th>Notes</th><th>Date</th></tr></thead><tbody>\n";
					$sql = $db->prepare("SELECT ROWID,* FROM releases WHERE productid = ?;");
					$sql->execute(to_int($q->param('p')));
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[3] . "</td><td>" . $res[2] . "</td><td>";
						if(lc(substr($res[4], 0, 4)) eq "http") { print "<a href='" . $res[4] . "'>" . $res[4] . "</a>"; }
						else { print $res[4]; }
						print "</td><td>" .  $res[5];
						if($logged_lvl > 2) { print "<span class='pull-right'><form method='GET' action='.'><input type='hidden' name='m' value='view_product'><input type='hidden' name='p' value='" . to_int($q->param('p')) . "'><input type='hidden' name='m' value='delete_release'><input type='hidden' name='delete_release' value=\"" . $res[0] . "\"><input class='btn btn-danger' type='submit' onclick='return confirm(\"Really remove this entry?\");' value='X'></form></span>"; } 
						print "</td></tr>\n";
					}
					print "</tbody></table><script>\$(document).ready(function(){\$('#releases_table').DataTable({'order':[[3,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
				}
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
							if($file_size > to_int($cfg->load('max_size')))
							{
								msg("Image size is too large.", 1);
							}
							else
							{
								my $io_handle = $lightweight_fh->handle;
								binmode($io_handle);
								my ($buffer, $bytesread);
								$screenshot = Data::GUID->new;
								open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $screenshot) or die $@;
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
				msg("<meta http-equiv='REFRESH' content='1;url=./?m=products'>" . $items{"Product"} . " <b>" . sanitize_html($q->param('product_name')) . "</b> added.", 3);
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
							if($file_size > to_int($cfg->load('max_size')))
							{
								msg("Image size is too large.", 1);
							}
							else
							{
								my $io_handle = $lightweight_fh->handle;
								binmode($io_handle);
								my ($buffer, $bytesread);
								$screenshot = Data::GUID->new;
								open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $screenshot) or die $@;
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
				if($q->param('add_auto_assign'))
				{
					$sql = $db->prepare("INSERT INTO autoassign VALUES (?, ?);");
					$sql->execute(to_int($q->param('product_id')), sanitize_alpha($q->param('add_auto_assign')));
					notify(sanitize_alpha($q->param('add_auto_assign')), "Auto assigned to " . lc($items{"Product"}), "You have been auto-assigned to " . lc($items{"Product"}) . " " . to_int($q->param('product_id')). ".");
				}
				if($q->param('rem_auto_assign'))
				{
					$sql = $db->prepare("DELETE FROM autoassign WHERE productid = ? AND user = ?;");
					$sql->execute(to_int($q->param('product_id')), sanitize_alpha($q->param('rem_auto_assign')));					
					notify(sanitize_alpha($q->param('rem_auto_assign')), "Unassigned from " . lc($items{"Product"}), "You have been removed from auto assignment on " . lc($items{"Product"}) . " " . to_int($q->param('product_id')). ".");
				}
				msg("<meta http-equiv='REFRESH' content='1;url=./?m=view_product&p=" . to_int($q->param('product_id')) . "'>" . $items{"Product"} . " <b>" . sanitize_html($q->param('product_name')) . "</b> updated.", 3);
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
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add a new " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data' data-toggle='validator' role='form'>\n";
			print "<p><div class='row'><div class='col-sm-6'><input placeholder='" . $items{"Product"} . " name' type='text' name='product_name' class='form-control' required></div><div class='col-sm-6'><input type='text' placeholder='" . $items{"Model"} . "' name='product_model' class='form-control'></div></div></p>\n";
			print "<p><div class='row'><div class='col-sm-6'><input type='text' name='product_release' placeholder='Initial " . lc($items{"Release"}) . "' class='form-control' required></div><div class='col-sm-6'><select class='form-control' name='product_vis'><option>Public</option><option>Private</option><option>Restricted</option></select></div></div></p>\n";
			print "<span class='pull-right'><img title='Header' src='icons/header.png' style='cursor:pointer' onclick='javascript:md_header()'> <img title='Bold' src='icons/bold.png' style='cursor:pointer' onclick='javascript:md_bold()'> <img title='Italic' src='icons/italic.png' style='cursor:pointer' onclick='javascript:md_italic()'> <img title='Code' src='icons/code.png' style='cursor:pointer' onclick='javascript:md_code()'> <img title='Image' src='icons/image.png' style='cursor:pointer' onclick='javascript:md_image()'> <img title='Link' src='icons/link.png' style='cursor:pointer' onclick='javascript:md_link()'> <img title='List' src='icons/list.png' style='cursor:pointer' onclick='javascript:md_list()'></span><br>";
			print "<p><textarea placeholder='Description' id='markdown' class='form-control' name='product_desc' rows='10' required></textarea></p><input class='btn btn-primary pull-right' type='submit' value='Add " . lc($items{"Product"}) . "'>";
			if($cfg->load('upload_folder')) { print $items{"Product"} . " image: <input type='file' name='product_screenshot'>\n"; }
			print "<input type='hidden' name='m' value='add_product'></form></div></div>\n";
		}
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		my $found;
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>List of " . lc($items{"Product"}) . "s</h3></div><div class='panel-body'><table class='table table-striped' id='projects_table'>\n";
		print "<thead><tr><th>ID</th><th>Name</th><th>" . $items{"Model"} . "</th></tr></thead><tbody>\n";
		while(my @res = $sql->fetchrow_array())
		{
			if($res[5] eq "Public" || ($res[5] eq "Private" && $logged_user ne "") || ($res[5] eq "Restricted" && $logged_lvl > 1) || $logged_lvl > 3) { print "<tr><td>" . $res[0] . "</td><td><a href='./?m=view_product&p=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[2] . "</td></tr>\n"; }
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#projects_table').DataTable({'order':[[1,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
	}
	elsif($q->param('m') eq "update_ticket" && $logged_lvl > 2 && $q->param('t'))
	{
		headers("Tickets");
		if($q->param('ticket_status') && $q->param('work_done') && $q->param('ticket_title') && $q->param('ticket_desc') && ($q->param('ticket_resolution') || ($q->param('ticket_status') eq "Open" || $q->param('ticket_status') eq "New")))
		{
			my $resolution = "";
			my $timespent = 0.00;
			if($q->param("time_spent"))
			{
				$timespent = to_float($q->param("time_spent"));
				if($timespent > 99.99) { $timespent = 99.99; }
				if($timespent < -99.99) { $timespent = -99.99; }
			}
			if($q->param('ticket_resolution')) { $resolution = sanitize_html($q->param('ticket_resolution')); }
			my $lnk = "Normal";
			if($q->param('ticket_priority')) { $lnk = sanitize_html($q->param('ticket_priority')); }
			my $assigned = "";
			if($q->param('ticket_assigned')) { $assigned = sanitize_html($q->param('ticket_assigned')); }
			$assigned =~ s/\b$logged_user\b//g;
			if($q->param('ticket_assign_self')) { $assigned .= " " . $logged_user; }
			my $changes = "";
			if($cfg->load('comp_articles') eq "on" && $q->param('link_article') && $q->param('link_article') ne "")
			{ $changes .= "Linked article: " . to_int($q->param('link_article')) . "\n"; }
			if($q->param("notify_user")) { $changes .= "Notified user: " . sanitize_alpha($q->param('notify_user')) . "\n"; }
			$sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('t')));
			my (@us, $creator);
			while(my @res = $sql->fetchrow_array())
			{
				if($res[2] ne sanitize_html($q->param('ticket_releases'))) { $changes .= $items{"Release"} . "s: \"" . $res[2] . "\" => \"" . sanitize_html($q->param('ticket_releases')) . "\"\n"; }
				if(trim($res[4]) ne trim($assigned)) { $changes .= "Assigned to: " . $res[4] . " => " . $assigned . "\n"; }
				if($res[5] ne sanitize_html($q->param('ticket_title'))) { $changes .= "Title: \"" . $res[5] . "\" => \"" . sanitize_html($q->param('ticket_title')) . "\"\n"; }
				if($res[7] ne $lnk) { $changes .= "Priority: " . $res[7] . " => " . $lnk . "\n"; }
				if($res[8] ne sanitize_alpha($q->param('ticket_status'))) { $changes .= "Status: " . $res[8] . " => " . sanitize_alpha($q->param('ticket_status')) . "\n"; }
				if($res[9] ne $resolution) { $changes .= "Resolution: \"" . $res[9] . "\" => \"" . $resolution . "\"\n"; }
				@us = split(' ', $res[4]);
				$creator = $res[3];
			}
			$changes .= "\n";
			if($cfg->load('comp_time') eq "on") { $changes .= "[" . $timespent . "] "; }
			$changes .= sanitize_html($q->param('work_done')) . "\n";				
			$sql = $db->prepare("UPDATE tickets SET link = ?, resolution = ?, status = ?, title = ?, description = ?, assignedto = ?, releaseid = ?, modified = ? WHERE ROWID = ?;");
			$sql->execute($lnk, $resolution, sanitize_alpha($q->param('ticket_status')), sanitize_html($q->param('ticket_title')), sanitize_html($q->param('ticket_desc')) . "\n\n--- " . now() . " ---\nTicket modified by: " . $logged_user . "\n" . $changes, $assigned, sanitize_html($q->param('ticket_releases')), now(), to_int($q->param('t')));
			foreach my $u (@us)
			{
				notify($u, "Ticket (" . to_int($q->param('t')) . ") assigned to you has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\nPriority: " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes);
			}
			if($creator) { notify($creator, "Your ticket (" . to_int($q->param('t')) . ") has been modified", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\nPriority: " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes); }
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=view_ticket&t=" . to_int($q->param('t')) . "'>Ticket updated.", 3);
			if($timespent != 0)
			{
				$sql = $db->prepare("INSERT INTO timetracking VALUES (?, ?, ?, ?);");
				$sql->execute(to_int($q->param('t')), $logged_user, $timespent, now());
			}
			if($q->param("notify_user") && sanitize_alpha($q->param('notify_user')) ne "")
			{
				$sql = $db->prepare("INSERT INTO escalate VALUES (?, ?);");
				$sql->execute(to_int($q->param('t')), sanitize_alpha(lc($q->param('notify_user'))));
				notify(sanitize_alpha($q->param('notify_user')), "Ticket (" . to_int($q->param('t')) . ") requires your attention", "The ticket \"" . $q->param('ticket_title') . "\" has been modified:\n\nModified by: " . $logged_user . "\nPriority: " . $lnk . "\nStatus: " . sanitize_alpha($q->param('ticket_status')) . "\nResolution: " . $resolution . "\nAssigned to: " . $assigned . "\nDescription: " . $q->param('ticket_desc') . "\n\n" . $changes);
			}
			if($cfg->load('comp_billing') eq "on")
			{
				$sql = $db->prepare("DELETE FROM billing WHERE ticketid = ?");
				$sql->execute(to_int($q->param('t')));
				if($q->param('billable') && $q->param('billable') ne "")
				{
					$sql = $db->prepare("INSERT INTO billing VALUES (?, ?)");
					$sql->execute(to_int($q->param('t')), sanitize_html($q->param('billable')));
				}
			}
			if($cfg->load('comp_articles') eq "on" && $q->param('link_article') && $q->param('link_article') ne "")
			{
				$sql = $db->prepare("INSERT INTO kblink VALUES (?, ?);");
				$sql->execute(to_int($q->param('t')), to_int($q->param('link_article')));
			}
			if($cfg->load('ticket_plugin'))
			{
				my $cmd = $cfg->load('ticket_plugin');
				my $s0 = sanitize_alpha($q->param('ticket_status'));
				my $s1 = $resolution;
				my $s2 = to_int($q->param('t'));
				my $s3 = "";
				if($q->param('billable') && $q->param('billable') ne "")
				{
					$s3 = sanitize_html($q->param('billable'));
				}
				$cmd =~ s/\%status\%/\"$s0\"/g;
				$cmd =~ s/\%resolution\%/\"$s1\"/g;
				$cmd =~ s/\%ticket\%/\"$s2\"/g;
				$cmd =~ s/\%client\%/\"$s3\"/g;
				$cmd =~ s/\%user\%/\"$logged_user\"/g;
				$cmd =~ s/\n/ /g;
				$cmd =~ s/\r/ /g;
				system($cmd);
			}
		}
		else
		{
			my $text = "Required fields missing: ";
			if(!$q->param('ticket_status')) { $text .= "<span class='label label-danger'>Ticket status</span> "; }
			if(!$q->param('ticket_title')) { $text .= "<span class='label label-danger'>Ticket title</span> "; }
			if(!$q->param('ticket_releases')) { $text .= "<span class='label label-danger'>Ticket " . lc($items{"Release"}) . "s</span> "; }
			if(!$q->param('ticket_desc')) { $text .= "<span class='label label-danger'>Ticket description</span> "; }
			if(!$q->param('ticket_resolution') && ($q->param('ticket_status') ne "Open" && $q->param('ticket_status') ne "New")) { $text .= "<span class='label label-danger'>Ticket resolution</span> "; }
			if(!$q->param('work_done')) { $text .= "<span class='label label-danger'>Summary of work done</span> "; }
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
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=tickets'>Comment deleted.", 3);
		}
		elsif($q->param('comment') && length($q->param('comment')) < 9999)
		{
			$sql = $db->prepare("UPDATE comments SET comment = ?, modified = ? WHERE ROWID = ? AND name = ?;");
			$sql->execute(sanitize_html($q->param('comment')), now(), to_int($q->param('c')), $logged_user);
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=tickets'>Comment updated.", 3);
		}
		else
		{
			msg("Comment missing or too long. Please go back and try again.", 0);		
		}
	}
	elsif($q->param('m') eq "auto" && $logged_lvl >= to_int($cfg->load('auto_lvl')))
	{
		headers("Automation");
		if($q->param('config'))
		{
			$sql = $db->prepare("SELECT * FROM auto_modules WHERE name = ?;");
			$sql->execute(sanitize_html($q->param('config')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $res[0] . "</h3></div><div class='panel-body'><form method='POST' action='./?m=auto'>\n";
				print "<p><div class='row'><div class='col-sm-12'>" . $res[5] . "</div></div></p>";
				print "<p><div class='row'><div class='col-sm-6'>Last run: <b>" . $res[2] . "</b></div><div class='col-sm-6'>Last result: <b>" . $res[4] . "</b></div></div></p><hr>";
				print "<p><div class='row'><div class='col-sm-6'>Status: <select class='form-control' name='enabled'><option value='0'>Disabled</option><option value='1'";
				if(to_int($res[1]) == 1) { print " selected"; }
				print ">Enabled</option></select></div><div class='col-sm-6'>Schedule: <select class='form-control' name='schedule'><option value='0'";
				if($res[6] == 0) { print "selected"; }
				print ">5 minutes</option><option value='1'";
				if($res[6] == 1) { print "selected"; }
				print ">15 minutes</option><option value='2'";
				if($res[6] == 2) { print "selected"; }
				print ">Hourly</option><option value='3'";
				if($res[6] == 3) { print "selected"; }
				print ">Daily</option><option value='4'";
				if($res[6] == 4) { print "selected"; }
				print ">Weekly</option></select></div></div></p>";
				if($res[0] eq "Backup")
				{
					my $folder = $0 . "_backups";
					my $type = "Time stamped";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Backup';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'folder') { $folder = $res2[2]; }
						if($res2[1] eq 'type') { $type = $res2[2]; }
					}
					print "<p><div class='row'><div class='col-sm-4'>Backup folder:</div><div class='col-sm-8'><input class='form-control' type='text' name='folder' value=\"" . $folder . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Archive type:</div><div class='col-sm-8'><select class='form-control' name='type'><option>Time stamped</option><option";
					if($type eq "Overwrite") { print " selected"; }
					print ">Overwrite</option></select></div></div></p>";
				}
				elsif($res[0] eq "Bulk export")
				{
					my $filename = "export.csv";
					my $table = "Tickets";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Bulk export';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'filename') { $filename = $res2[2]; }
						if($res2[1] eq 'table') { $table = $res2[2]; }
					}
					print "<p><div class='row'><div class='col-sm-4'>Export file:</div><div class='col-sm-8'><input class='form-control' type='text' name='filename' value=\"" . $filename . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Table to export:</div><div class='col-sm-8'><select class='form-control' name='table'><option>Tickets</option><option";
					if($table eq "Items") { print " selected"; }
					print ">Items</option><option";
					if($table eq "Clients") { print " selected"; }
					print ">Clients</option><option";
					if($table eq "Users") { print " selected"; }
					print ">Users</option><option";
					if($table eq "Secrets") { print " selected"; }
					print ">Secrets</option><option";
					if($table eq "Tasks") { print " selected"; }
					print ">Tasks</option></select></div></div></p>";
				}
				elsif($res[0] eq "Log export")
				{
					my $filename = "log.csv";
					my $remlog = 0;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Log export';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'filename') { $filename = $res2[2]; }
						if($res2[1] eq 'remlog') { $remlog = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>Export file:</div><div class='col-sm-8'><input class='form-control' type='text' name='filename' value=\"" . $filename . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Delete logs afterward:</div><div class='col-sm-8'><select class='form-control' name='remlog'><option";
					if($remlog == 1) { print " selected"; }
					print ">Yes</option><option";
					if($remlog == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
				}
				elsif($res[0] eq "CSV projects")
				{
					my $filename = "projects.csv";
					my $productvis = "Public";
					my $ovrassign = 0;
					my $mapname = 0;
					my $mapgoal = 1;
					my $mapdesc = 2;
					my $maprel = 3;
					my $mapnote = 4;
					my $mapassign = 5;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'CSV projects';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'filename') { $filename = $res2[2]; }
						if($res2[1] eq 'productvis') { $productvis = $res2[2]; }
						if($res2[1] eq 'ovrassign') { $ovrassign = to_int($res2[2]); }
						if($res2[1] eq 'mapname') { $mapname = to_int($res2[2]); }
						if($res2[1] eq 'mapgoal') { $mapgoal = to_int($res2[2]); }
						if($res2[1] eq 'mapdesc') { $mapdesc = to_int($res2[2]); }
						if($res2[1] eq 'maprel') { $maprel = to_int($res2[2]); }
						if($res2[1] eq 'mapnote') { $mapnote = to_int($res2[2]); }
						if($res2[1] eq 'mapassign') { $mapassign = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>File name:</div><div class='col-sm-8'><input class='form-control' type='text' name='filename' value=\"" . $filename . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Create new " . lc($items{"Product"}) . "s as:</div><div class='col-sm-8'><select class='form-control' name='productvis'><option>Public</option><option";
					if($productvis eq "Private") { print " selected"; }
					print ">Private</option><option";
					if($productvis eq "Restricted") { print " selected"; }
					print ">Restricted</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Overwrite current assignments:</div><div class='col-sm-8'><select class='form-control' name='ovrassign'><option";
					if($ovrassign == 1) { print " selected"; }
					print ">Yes</option><option";
					if($ovrassign == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for '" . lc($items{"Product"}) . " name':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapname' value=\"" . $mapname . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for '" . lc($items{"Product"}) . " " . lc($items{"Model"}) . "':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapgoal' value=\"" . $mapgoal . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for '" . lc($items{"Product"}) . " description':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapdesc' value=\"" . $mapdesc . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for '" . lc($items{"Release"}) . " name':</div><div class='col-sm-8'><input class='form-control' type='number' name='maprel' value=\"" . $maprel . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for '" . lc($items{"Release"}) . " note':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapnote' value=\"" . $mapnote . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'auto-assignment':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapassign' value=\"" . $mapassign . "\"></div></div></p>";
				}
				elsif($res[0] eq "Update MOTD")
				{
					my $filename = "motd.txt";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Update MOTD';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'filename') { $filename = $res2[2]; }
					}
					print "<p><div class='row'><div class='col-sm-4'>Text file:</div><div class='col-sm-8'><input class='form-control' type='text' name='filename' value=\"" . $filename . "\"></div></div></p>";
				}
				elsif($res[0] eq "Users sync")
				{
					my $aduser = "Administrator";
					my $adpass = "";
					my $mapname = "sAMAccountName";
					my $searchfilter = "(&(objectCategory=person)(objectClass=user))";
					my $basedn = "CN=Users,DC=" . $cfg->load("ad_domain") . ",DC=com";
					my $importemail = 0;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Users sync';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
						if($res2[1] eq 'mapname') { $mapname = $res2[2]; }
						if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
						if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
						if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("enc_key"), decode_base64($res2[2])); }
						if($res2[1] eq 'importemail') { $importemail = to_int($res2[2]); }
					}
					if($cfg->load("ad_server") eq "") { msg("Active Directory integration is not configured.", 1); }
					print "<p><div class='row'><div class='col-sm-4'>Base DN:</div><div class='col-sm-8'><input class='form-control' type='text' name='basedn' value=\"" . $basedn . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Filter:</div><div class='col-sm-8'><input class='form-control' type='text' name='searchfilter' value=\"" . $searchfilter . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Username:</div><div class='col-sm-8'><input class='form-control' type='text' name='aduser' value=\"" . $aduser . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Password:</div><div class='col-sm-8'><input class='form-control' type='password' name='adpass' value=\"" . $adpass . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Mapping for 'username':</div><div class='col-sm-8'><select class='form-control' name='mapname'><option>sAMAccountName</option><option";
					if($mapname eq "cn") { print " selected"; }
					print ">cn</option><option";
					if($mapname eq "userPrincipalName") { print " selected"; }
					print ">userPrincipalName</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Import email addresses:</div><div class='col-sm-8'><select class='form-control' name='importemail'><option";
					if($importemail == 1) { print " selected"; }
					print ">Yes</option><option";
					if($importemail == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
				}
				elsif($res[0] eq "Email to Ticket")
				{
					my $imapuser = "";
					my $imappass = "";
					my $imapserver = "";
					my $imapport = 143;
					my $imapssl = 0;
					my $deleteemail = 0;
					my $productid = 1;
					my $releaseid = "1.0";
					my $priority = "Normal";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Email to Ticket';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'productid') { $productid = to_int($res2[2]); }
						if($res2[1] eq 'releaseid') { $releaseid = $res2[2]; }
						if($res2[1] eq 'priority') { $priority = $res2[2]; }
						if($res2[1] eq 'imapport') { $imapport = to_int($res2[2]); }
						if($res2[1] eq 'deleteemail') { $deleteemail = to_int($res2[2]); }
						if($res2[1] eq 'imapssl') { $imapssl = to_int($res2[2]); }
						if($res2[1] eq 'imapuser') { $imapuser = $res2[2]; }
						if($res2[1] eq 'imappass') { $imappass = RC4($cfg->load("enc_key"), decode_base64($res2[2])); }
						if($res2[1] eq 'imapserver') { $imapserver = $res2[2]; }
					}
					print "<p><div class='row'><div class='col-sm-4'>IMAP Server:</div><div class='col-sm-8'><input class='form-control' type='text' name='imapserver' value=\"" . $imapserver . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>IMAP Port:</div><div class='col-sm-8'><input class='form-control' type='number' name='imapport' value=\"" . $imapport . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Username:</div><div class='col-sm-8'><input class='form-control' type='text' name='imapuser' value=\"" . $imapuser . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Password:</div><div class='col-sm-8'><input class='form-control' type='password' name='imappass' value=\"" . $imappass . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Use SSL:</div><div class='col-sm-8'><select class='form-control' name='imapssl'><option";
					if($imapssl == 1) { print " selected"; }
					print ">Yes</option><option";
					if($imapssl == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Delete emails:</div><div class='col-sm-8'><select class='form-control' name='deleteemail'><option";
					if($deleteemail == 1) { print " selected"; }
					print ">Yes</option><option";
					if($deleteemail == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>" . $items{"Product"} . " ID:</div><div class='col-sm-8'><input class='form-control' type='number' name='productid' value=\"" . $productid . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>" . $items{"Release"} . ":</div><div class='col-sm-8'><input class='form-control' type='text' name='releaseid' value=\"" . $releaseid . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Priority:</div><div class='col-sm-8'><select class='form-control' name='priority'><option";
					if($priority eq "High") { print " selected"; }
					print ">High</option><option";
					if($priority eq "Normal") { print " selected"; }
					print ">Normal</option><option";
					if($priority eq "Low") { print " selected"; }
					print ">Low</option></select></div></div></p>";
				}
				elsif($res[0] eq "Computers sync")
				{
					my $aduser = "Administrator";
					my $adpass = "";
					my $type = "Desktop";
					my $mapinfo = "operatingSystem";
					my $approval = 0;
					my $searchfilter = "(&(objectCategory=computer))";
					my $basedn = "CN=Computers,DC=" . $cfg->load("ad_domain") . ",DC=com";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Computers sync';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
						if($res2[1] eq 'type') { $type = $res2[2]; }
						if($res2[1] eq 'mapinfo') { $mapinfo = $res2[2]; }
						if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
						if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
						if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("enc_key"), decode_base64($res2[2])); }
						if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
					}
					if($cfg->load("ad_server") eq "") { msg("Active Directory integration is not configured.", 1); }
					print "<p><div class='row'><div class='col-sm-4'>Base DN:</div><div class='col-sm-8'><input class='form-control' type='text' name='basedn' value=\"" . $basedn . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Filter:</div><div class='col-sm-8'><input class='form-control' type='text' name='searchfilter' value=\"" . $searchfilter . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Username:</div><div class='col-sm-8'><input class='form-control' type='text' name='aduser' value=\"" . $aduser . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Password:</div><div class='col-sm-8'><input class='form-control' type='password' name='adpass' value=\"" . $adpass . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Require checkout approval:</div><div class='col-sm-8'><select class='form-control' name='approval'><option";
					if($approval == 1) { print " selected"; }
					print ">Yes</option><option";
					if($approval == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Computer type:</div><div class='col-sm-8'><select class='form-control' name='type'><option";
					if($type eq "Desktop") { print " selected"; }
					print ">Desktop</option><option";
					if($type eq "Laptop") { print " selected"; }
					print ">Laptop</option><option";
					if($type eq "Server") { print " selected"; }
					print ">Server</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Mapping for 'info':</div><div class='col-sm-8'><input class='form-control' type='text' name='mapinfo' value=\"" . $mapinfo . "\"></div></div></p>";
				}
				elsif($res[0] eq "Ticket expiration")
				{
					my $numdays = 30;
					my $closeticket = 0;
					my $remindticket = 0;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Ticket expiration';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'numdays') { $numdays = to_int($res2[2]); }
						if($res2[1] eq 'closeticket') { $closeticket = to_int($res2[2]); }
						if($res2[1] eq 'remindticket') { $remindticket = to_int($res2[2]); }
					}
					if($cfg->load("smtp_server") eq "") { msg("Email server is not configured.", 1); }
					print "<p><div class='row'><div class='col-sm-4'>Number of days old:</div><div class='col-sm-8'><input class='form-control' type='number' name='numdays' value='" . $numdays . "'></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Notify assigned users:</div><div class='col-sm-8'><select class='form-control' name='remindticket'><option";
					if($remindticket == 1) { print " selected"; }
					print ">Yes</option><option";
					if($remindticket == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Close tickets:</div><div class='col-sm-8'><select class='form-control' name='closeticket'><option";
					if($closeticket == 1) { print " selected"; }
					print ">Yes</option><option";
					if($closeticket == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
				}
				elsif($res[0] eq "File expiration")
				{
					my $numdays = 30;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'File expiration';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'numdays') { $numdays = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>Number of days old:</div><div class='col-sm-8'><input class='form-control' type='number' name='numdays' value='" . $numdays . "'></div></div></p>";
				}
				elsif($res[0] eq "Reminder notifications")
				{
					my $reminditems = 0;
					my $remindtasks = 0;
					my $remindtickets = 0;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Reminder notifications';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'reminditems') { $reminditems = to_int($res2[2]); }
						if($res2[1] eq 'remindtasks') { $remindtasks = to_int($res2[2]); }
						if($res2[1] eq 'remindtickets') { $remindtickets = to_int($res2[2]); }
					}
					if($cfg->load("smtp_server") eq "") { msg("Email server is not configured.", 1); }
					print "<p><div class='row'><div class='col-sm-4'>Expired checkout items:</div><div class='col-sm-8'><select class='form-control' name='reminditems'><option";
					if($reminditems == 1) { print " selected"; }
					print ">Yes</option><option";
					if($reminditems == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Overdue tasks:</div><div class='col-sm-8'><select class='form-control' name='remindtasks'><option";
					if($remindtasks == 1) { print " selected"; }
					print ">Yes</option><option";
					if($remindtasks == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Tickets notifications:</div><div class='col-sm-8'><select class='form-control' name='remindtickets'><option";
					if($remindtickets == 1) { print " selected"; }
					print ">Yes</option><option";
					if($remindtickets == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
				}
				elsif($res[0] eq "ServiceNow CMDB")
				{
					my $type = "Server";
					my $cmdburl = "https://mycompany.service-now.com";
					my $cmdbtable = "cmdb_ci_server";
					my $mapname = "name";
					my $mapserial = "asset_tag";
					my $mapinfo = "os";
					my $approval = 0;
					my $cmdbuser = "admin";
					my $cmdbpass = "";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'ServiceNow CMDB';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'type') { $type = $res2[2]; }
						if($res2[1] eq 'cmdburl') { $cmdburl = $res2[2]; }
						if($res2[1] eq 'cmdbtable') { $cmdbtable = $res2[2]; }
						if($res2[1] eq 'mapname') { $mapname = $res2[2]; }
						if($res2[1] eq 'mapserial') { $mapserial = $res2[2]; }
						if($res2[1] eq 'mapinfo') { $mapinfo = $res2[2]; }
						if($res2[1] eq 'cmdbuser') { $cmdbuser = $res2[2]; }
						if($res2[1] eq 'cmdbpass') { $cmdbpass = RC4($cfg->load("enc_key"), decode_base64($res2[2])); }
						if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>ServiceNow URL:</div><div class='col-sm-8'><input class='form-control' type='text' name='cmdburl' value=\"" . $cmdburl . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>ServiceNow CMDB table:</div><div class='col-sm-8'><input class='form-control' type='text' name='cmdbtable' value=\"" . $cmdbtable . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Username:</div><div class='col-sm-8'><input class='form-control' type='text' name='cmdbuser' value=\"" . $cmdbuser . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Password:</div><div class='col-sm-8'><input class='form-control' type='password' name='cmdbpass' value=\"" . $cmdbpass . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Require checkout approval:</div><div class='col-sm-8'><select class='form-control' name='approval'><option";
					if($approval == 1) { print " selected"; }
					print ">Yes</option><option";
					if($approval == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Asset type:</div><div class='col-sm-8'><select class='form-control' name='type'><option";
					if($type eq "Desktop") { print " selected"; }
					print ">Desktop</option><option";
					if($type eq "Laptop") { print " selected"; }
					print ">Laptop</option><option";
					if($type eq "Server") { print " selected"; }
					print ">Server</option><option";
					if($type eq "Keyboard") { print " selected"; }
					print ">Keyboard</option><option";
					if($type eq "Mouse") { print " selected"; }
					print ">Mouse</option><option";
					if($type eq "Display") { print " selected"; }
					print ">Display</option><option";
					if($type eq "Phone") { print " selected"; }
					print ">Phone</option><option";
					if($type eq "Software") { print " selected"; }
					print ">Software</option><option";
					if($type eq "Printer") { print " selected"; }
					print ">Printer</option><option";
					if($type eq "Peripheral") { print " selected"; }
					print ">Peripheral</option><option";
					if($type eq "Furniture") { print " selected"; }
					print ">Furniture</option><option";
					if($type eq "Tool") { print " selected"; }
					print ">Tool</option><option";
					if($type eq "Other") { print " selected"; }
					print ">Other</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Mapping for 'name':</div><div class='col-sm-8'><input class='form-control' type='text' name='mapname' value=\"" . $mapname . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Mapping for 'serial':</div><div class='col-sm-8'><input class='form-control' type='text' name='mapserial' value=\"" . $mapserial . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Mapping for 'info':</div><div class='col-sm-8'><input class='form-control' type='text' name='mapinfo' value=\"" . $mapinfo . "\"></div></div></p>";
				}
				elsif($res[0] eq "ODBC inventory")
				{
					my $type = "Server";
					my $odbcdsn = "Driver={SQL Server};Server=127.0.0.1;Database=my_data;";
					my $odbctable = "dbo.my_items";
					my $mapname = "0";
					my $mapserial = "1";
					my $mapinfo = "2";
					my $approval = 0;
					my $odbcuser = "sa";
					my $odbcpass = "";
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'ODBC inventory';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'type') { $type = $res2[2]; }
						if($res2[1] eq 'odbcdsn') { $odbcdsn = $res2[2]; }
						if($res2[1] eq 'odbctable') { $odbctable = $res2[2]; }
						if($res2[1] eq 'mapname') { $mapname = to_int($res2[2]); }
						if($res2[1] eq 'mapserial') { $mapserial = to_int($res2[2]); }
						if($res2[1] eq 'mapinfo') { $mapinfo = to_int($res2[2]); }
						if($res2[1] eq 'odbcuser') { $odbcuser = $res2[2]; }
						if($res2[1] eq 'odbcpass') { $odbcpass = RC4($cfg->load("enc_key"), decode_base64($res2[2])); }
						if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>Connection string:</div><div class='col-sm-8'><input class='form-control' type='text' name='odbcdsn' value=\"" . $odbcdsn . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Table name:</div><div class='col-sm-8'><input class='form-control' type='text' name='odbctable' value=\"" . $odbctable . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Username:</div><div class='col-sm-8'><input class='form-control' type='text' name='odbcuser' value=\"" . $odbcuser . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Password:</div><div class='col-sm-8'><input class='form-control' type='password' name='odbcpass' value=\"" . $odbcpass . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Require checkout approval:</div><div class='col-sm-8'><select class='form-control' name='approval'><option";
					if($approval == 1) { print " selected"; }
					print ">Yes</option><option";
					if($approval == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Asset type:</div><div class='col-sm-8'><select class='form-control' name='type'><option";
					if($type eq "Desktop") { print " selected"; }
					print ">Desktop</option><option";
					if($type eq "Laptop") { print " selected"; }
					print ">Laptop</option><option";
					if($type eq "Server") { print " selected"; }
					print ">Server</option><option";
					if($type eq "Keyboard") { print " selected"; }
					print ">Keyboard</option><option";
					if($type eq "Mouse") { print " selected"; }
					print ">Mouse</option><option";
					if($type eq "Display") { print " selected"; }
					print ">Display</option><option";
					if($type eq "Phone") { print " selected"; }
					print ">Phone</option><option";
					if($type eq "Software") { print " selected"; }
					print ">Software</option><option";
					if($type eq "Printer") { print " selected"; }
					print ">Printer</option><option";
					if($type eq "Peripheral") { print " selected"; }
					print ">Peripheral</option><option";
					if($type eq "Furniture") { print " selected"; }
					print ">Furniture</option><option";
					if($type eq "Tool") { print " selected"; }
					print ">Tool</option><option";
					if($type eq "Other") { print " selected"; }
					print ">Other</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'name':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapname' value=\"" . $mapname . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'serial':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapserial' value=\"" . $mapserial . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'info':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapinfo' value=\"" . $mapinfo . "\"></div></div></p>";
				}
				elsif($res[0] eq "CSV inventory")
				{
					my $type = "Server";
					my $filename = "items.csv";
					my $mapname = 0;
					my $mapserial = 1;
					my $mapinfo = 2;
					my $approval = 0;
					my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'CSV inventory';");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						if($res2[1] eq 'type') { $type = $res2[2]; }
						if($res2[1] eq 'filename') { $filename = $res2[2]; }
						if($res2[1] eq 'mapname') { $mapname = to_int($res2[2]); }
						if($res2[1] eq 'mapserial') { $mapserial = to_int($res2[2]); }
						if($res2[1] eq 'mapinfo') { $mapinfo = to_int($res2[2]); }
						if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
					}
					print "<p><div class='row'><div class='col-sm-4'>File name:</div><div class='col-sm-8'><input class='form-control' type='text' name='filename' value=\"" . $filename . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Require checkout approval:</div><div class='col-sm-8'><select class='form-control' name='approval'><option";
					if($approval == 1) { print " selected"; }
					print ">Yes</option><option";
					if($approval == 0) { print " selected"; }
					print ">No</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Asset type:</div><div class='col-sm-8'><select class='form-control' name='type'><option";
					if($type eq "Desktop") { print " selected"; }
					print ">Desktop</option><option";
					if($type eq "Laptop") { print " selected"; }
					print ">Laptop</option><option";
					if($type eq "Server") { print " selected"; }
					print ">Server</option><option";
					if($type eq "Keyboard") { print " selected"; }
					print ">Keyboard</option><option";
					if($type eq "Mouse") { print " selected"; }
					print ">Mouse</option><option";
					if($type eq "Display") { print " selected"; }
					print ">Display</option><option";
					if($type eq "Phone") { print " selected"; }
					print ">Phone</option><option";
					if($type eq "Software") { print " selected"; }
					print ">Software</option><option";
					if($type eq "Printer") { print " selected"; }
					print ">Printer</option><option";
					if($type eq "Peripheral") { print " selected"; }
					print ">Peripheral</option><option";
					if($type eq "Furniture") { print " selected"; }
					print ">Furniture</option><option";
					if($type eq "Tool") { print " selected"; }
					print ">Tool</option><option";
					if($type eq "Other") { print " selected"; }
					print ">Other</option></select></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'name':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapname' value=\"" . $mapname . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'serial':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapserial' value=\"" . $mapserial . "\"></div></div></p>";
					print "<p><div class='row'><div class='col-sm-4'>Column mapping for 'info':</div><div class='col-sm-8'><input class='form-control' type='number' name='mapinfo' value=\"" . $mapinfo . "\"></div></div></p>";
				}
				print "<p><input type='hidden' name='m' value='auto'><input type='hidden' name='save' value='" . sanitize_html($q->param('config')) . "'><input class='btn btn-primary pull-right' type='submit' value='Save'></p>";
				print "</form></div></div>\n";
			}
		}
		else
		{
			if($q->param('run_all'))
			{
				$sql = $db->prepare("UPDATE auto_modules SET timestamp = 0;");
				$sql->execute();
				msg("All enabled modules will be executed on next run regardless of scheduling.", 3)
			}
			if($q->param('clear_all') && $logged_lvl > 5)
			{
				$sql = $db->prepare("DROP TABLE auto_modules;");
				$sql->execute();
				msg("<meta http-equiv='REFRESH' content='1;url=./?m=auto'>Modules reset.", 3);
				quit(0);
			}
			if($q->param('clear_log') && $logged_lvl > 5)
			{
				$sql = $db->prepare("DELETE FROM auto_log;");
				$sql->execute();
			}
			if($q->param('save') && defined($q->param('schedule')) && defined($q->param('enabled')))
			{
				$sql = $db->prepare("BEGIN");
				$sql->execute();
				$sql = $db->prepare("UPDATE auto_modules SET enabled = ?, schedule = ? WHERE name = ?;");
				$sql->execute(to_int($q->param('enabled')), to_int($q->param('schedule')), $q->param('save'));
				if($q->param('save') eq "Backup")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Backup';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Backup', 'folder', ?);");
					$sql->execute(sanitize_html($q->param('folder')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Backup', 'type', ?);");
					$sql->execute(sanitize_html($q->param('type')));
				}
				elsif($q->param('save') eq "Bulk export")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Bulk export';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Bulk export', 'filename', ?);");
					$sql->execute(sanitize_html($q->param('filename')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Bulk export', 'table', ?);");
					$sql->execute(sanitize_html($q->param('table')));
				}
				elsif($q->param('save') eq "Log export")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Log export';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Log export', 'filename', ?);");
					$sql->execute(sanitize_html($q->param('filename')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Log export', 'remlog', ?);");
					if($q->param('remlog') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "Update MOTD")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Update MOTD';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Update MOTD', 'filename', ?);");
					$sql->execute(sanitize_html($q->param('filename')));
				}
				elsif($q->param('save') eq "Users sync")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Users sync';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'basedn', ?);");
					$sql->execute(sanitize_html($q->param('basedn')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'searchfilter', ?);");
					$sql->execute(sanitize_html($q->param('searchfilter')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'aduser', ?);");
					$sql->execute(sanitize_html($q->param('aduser')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'mapname', ?);");
					$sql->execute(sanitize_alpha($q->param('mapname')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'adpass', ?);");
					$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('adpass'))));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Users sync', 'importemail', ?);");
					if($q->param('importemail') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "Computers sync")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Computers sync';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'basedn', ?);");
					$sql->execute(sanitize_html($q->param('basedn')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'searchfilter', ?);");
					$sql->execute(sanitize_html($q->param('searchfilter')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'aduser', ?);");
					$sql->execute(sanitize_html($q->param('aduser')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'type', ?);");
					$sql->execute(sanitize_html($q->param('type')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'mapinfo', ?);");
					$sql->execute(sanitize_html($q->param('mapinfo')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'adpass', ?);");
					$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('adpass'))));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Computers sync', 'approval', ?);");
					if($q->param('approval') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "ServiceNow CMDB")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'ServiceNow CMDB';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'cmdburl', ?);");
					$sql->execute(sanitize_html($q->param('cmdburl')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'cmdbtable', ?);");
					$sql->execute(sanitize_html($q->param('cmdbtable')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'mapname', ?);");
					$sql->execute(sanitize_html($q->param('mapname')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'mapserial', ?);");
					$sql->execute(sanitize_html($q->param('mapserial')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'mapinfo', ?);");
					$sql->execute(sanitize_html($q->param('mapinfo')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'cmdbuser', ?);");
					$sql->execute(sanitize_html($q->param('cmdbuser')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'type', ?);");
					$sql->execute(sanitize_html($q->param('type')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'cmdbpass', ?);");
					$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('cmdbpass'))));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ServiceNow CMDB', 'approval', ?);");
					if($q->param('approval') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "ODBC inventory")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'ODBC inventory';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'odbcdsn', ?);");
					$sql->execute(sanitize_html($q->param('odbcdsn')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'odbctable', ?);");
					$sql->execute(sanitize_html($q->param('odbctable')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'mapname', ?);");
					$sql->execute(to_int($q->param('mapname')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'mapserial', ?);");
					$sql->execute(to_int($q->param('mapserial')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'mapinfo', ?);");
					$sql->execute(to_int($q->param('mapinfo')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'odbcuser', ?);");
					$sql->execute(sanitize_html($q->param('odbcuser')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'type', ?);");
					$sql->execute(sanitize_html($q->param('type')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'odbcpass', ?);");
					$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('odbcpass'))));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('ODBC inventory', 'approval', ?);");
					if($q->param('approval') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "CSV inventory")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'CSV inventory';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'filename', ?);");
					$sql->execute(sanitize_html($q->param('filename')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'mapname', ?);");
					$sql->execute(to_int($q->param('mapname')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'mapserial', ?);");
					$sql->execute(to_int($q->param('mapserial')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'mapinfo', ?);");
					$sql->execute(to_int($q->param('mapinfo')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'type', ?);");
					$sql->execute(sanitize_html($q->param('type')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV inventory', 'approval', ?);");
					if($q->param('approval') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "CSV projects")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'CSV projects';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'filename', ?);");
					$sql->execute(sanitize_html($q->param('filename')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'productvis', ?);");
					$sql->execute(sanitize_alpha($q->param('productvis')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'mapname', ?);");
					$sql->execute(to_int($q->param('mapname')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'mapdesc', ?);");
					$sql->execute(to_int($q->param('mapdesc')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'mapgoal', ?);");
					$sql->execute(to_int($q->param('mapgoal')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'maprel', ?);");
					$sql->execute(to_int($q->param('maprel')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'mapnote', ?);");
					$sql->execute(to_int($q->param('mapnote')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'mapassign', ?);");
					$sql->execute(to_int($q->param('mapassign')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('CSV projects', 'ovrassign', ?);");
					if($q->param('ovrassign') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "Email to Ticket")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Email to Ticket';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'imapserver', ?);");
					$sql->execute(sanitize_html($q->param('imapserver')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'imapport', ?);");
					$sql->execute(to_int($q->param('imapport')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'productid', ?);");
					$sql->execute(to_int($q->param('productid')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'releaseid', ?);");
					$sql->execute(sanitize_html($q->param('releaseid')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'priority', ?);");
					$sql->execute(sanitize_alpha($q->param('priority')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'imapuser', ?);");
					$sql->execute(sanitize_html($q->param('imapuser')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'imappass', ?);");
					$sql->execute(encode_base64(RC4($cfg->load("enc_key"), $q->param('imappass'))));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'imapssl', ?);");
					if($q->param('imapssl') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Email to Ticket', 'deleteemail', ?);");
					if($q->param('deleteemail') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "Ticket expiration")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Ticket expiration';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Ticket expiration', 'numdays', ?);");
					$sql->execute(to_int($q->param('numdays')));
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Ticket expiration', 'remindticket', ?);");
					if($q->param('remindticket') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Ticket expiration', 'closeticket', ?);");
					if($q->param('closeticket') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				elsif($q->param('save') eq "File expiration")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'File expiration';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('File expiration', 'numdays', ?);");
					$sql->execute(to_int($q->param('numdays')));
				}
				elsif($q->param('save') eq "Reminder notifications")
				{
					$sql = $db->prepare("DELETE FROM auto_config WHERE module = 'Reminder notifications';");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Reminder notifications', 'remindtickets', ?);");
					if($q->param('remindtickets') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Reminder notifications', 'remindtasks', ?);");
					if($q->param('remindtasks') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
					$sql = $db->prepare("INSERT INTO auto_config VALUES ('Reminder notifications', 'reminditems', ?);");
					if($q->param('reminditems') eq "Yes") { $sql->execute(1); }
					else { $sql->execute(0); }
				}
				$sql = $db->prepare("END");
				$sql->execute();
				msg("Changes saved.", 3)
			}
			$sql = $db->prepare("SELECT * FROM auto;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if(to_int($res[0]) + 700 < time()) { msg("The scheduled task <b>nodepoint-automate</b> does not seem to be running. Please check your installation.", 1); }
			}
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Automation modules</h3></div><div class='panel-body'>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM auto_modules ORDER BY name ASC;");
			$sql->execute();
			print "<table class='table table-striped' id='auto_table'><thead><tr><th>Name</th><th>Status</th><th>Schedule</th><th>Last run time</th><th>Last result</th></tr></thead><tbody>\n";
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td><a href='./?m=auto&config=" . $res[1] . "'>" . $res[1] . "</a></td><td>";
				if(to_int($res[2]) == 1) { print "<font color='green'>Enabled</font>"; }
				else { print "<font color='red'>Disabled</font>"; }
				print "</td><td>";
				if(to_int($res[7]) == 0) { print "5 minutes"; }
				elsif(to_int($res[7]) == 1) { print "15 minutes"; }
				elsif(to_int($res[7]) == 2) { print "Hourly"; }
				elsif(to_int($res[7]) == 3) { print "Daily"; }
				elsif(to_int($res[7]) == 4) { print "Weekly"; }
				print "</td><td>" . $res[3] . "</td><td>";
				if($res[5] eq "Success") { print "<font color='green'>Success</font>"; }
				else { print "<font color='red'>" . $res[5] . "</font>"; }
				print "</td></tr>";
			}
			print "</tbody></table><p><form method='POST' action='./?m=auto'><input type='hidden' name='m' value='auto'><input class='btn btn-primary' type='submit' name='run_all' value='Process all modules on next run'>";
			if($logged_lvl > 5) { print "<input class='btn btn-danger pull-right' type='submit' name='clear_all' value='Reset modules'>"; }
			print "</form></p></div></div>\n";
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Automation log</h3></div><div class='panel-body'>\n";
			if($logged_lvl > 5) { print "<form style='display:inline' method='POST' action='./?m=auto'><input type='hidden' name='m' value='auto'><input type='hidden' name='clear_log' value='1'><input class='btn btn-danger pull-right' onclick='return confirm(\"Are you sure?\");' type='submit' value='Clear log'><br></form>"; }
			$sql = $db->prepare("SELECT * FROM auto;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				print "<p>Last automation result: <b>" . $res[1] . "</b></p>";
			}
			$sql = $db->prepare("SELECT * FROM auto_log ORDER BY ROWID DESC LIMIT 5000;");
			$sql->execute();
			print "<table class='table table-striped' id='autolog_table'><thead><tr><th>Module</th><th>Event</th><th>Date</th></tr></thead><tbody>\n";
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[0] . "</td><td>" . $res[1] . "</td><td>" . $res[2] . "</td></tr>";
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#autolog_table').DataTable({'order':[[2,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
		}
	}
	elsif($q->param('m') eq "files" && $cfg->load('comp_files') eq "on")
	{
		my $filedata = "";
		my $filename = "";
		headers("Files");
		if($q->param('delete_file') && $logged_lvl >= to_int($cfg->load('upload_lvl')))
		{
			$filedata = sanitize_alpha($q->param('delete_file'));
			if(length($filedata) == 36)
			{
				open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
				print $OUTFILE "This file is no longer available.";
				close($OUTFILE);
				$sql = $db->prepare("DELETE FROM files WHERE file = ?;");
				$sql->execute($filedata);
				$sql = $db->prepare("DELETE FROM files_product WHERE file = ?;");
				$sql->execute($filedata);
				msg("File <b>" . $filedata . "</b> removed.", 3);				
			}
		}
		if($q->param('attach_file') && $logged_lvl >= to_int($cfg->load('upload_lvl')))
		{
			eval
			{
				my $lightweight_fh = $q->upload('attach_file');
				if(defined $lightweight_fh)
				{
					my $tmpfilename = $q->tmpFileName($lightweight_fh);
					$filedata = Data::GUID->new;
					$filename = substr(sanitize_html($q->param('attach_file')), 0, 40);
					my $file_size = (-s $tmpfilename);
					if($file_size > to_int($cfg->load('max_size')))
					{
						msg("File size is larger than accepted value.", 0);
					}
					elsif($cfg->load('upload_exts') ne "" && index($cfg->load('upload_exts'), (split /\./, $filename)[-1]) == -1)
					{
						msg("File type is not in the list of allowed extensions.", 0);
					}
					else
					{
						my $io_handle = $lightweight_fh->handle;
						binmode($io_handle);
						my ($buffer, $bytesread);
						open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
						while($bytesread = $io_handle->read($buffer,1024))
						{
							print $OUTFILE $buffer;
						}
						close($OUTFILE);
						$sql = $db->prepare("INSERT INTO files VALUES (?, ?, ?, ?, ?);");
						$sql->execute($logged_user, $filedata, $filename, now(), to_int($file_size));
						msg("File <b>" . $filedata . "</b> uploaded.", 3);				
					}
				}
			};
			if($@)
			{
				msg("File uploading to <b>" . $cfg->load('upload_folder') . $cfg->sep . $filedata . "</b> failed.", 0); 
			}
		}
		if($logged_lvl >= to_int($cfg->load('upload_lvl')))
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add a new file</h3></div><div class='panel-body'>\n";
			print "<form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='files'><p>Add new file: <input type='file' name='attach_file'><input class='btn btn-primary pull-right' type='submit' value='Upload'></p></form>\n";
			print "</div></div>\n";
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Available files</h3></div><div class='panel-body'>\n";
		$sql = $db->prepare("SELECT * FROM files;");
		$sql->execute();
		print "<table class='table table-striped' id='files_table'><thead><tr><th>File name</th><th>File size</th><th>Uploaded by</th><th>Date</th><th>Hits</th><th>Download link</th></tr></thead><tbody>\n";
		while(my @res = $sql->fetchrow_array())
		{
			my $accesscount = 0;
			my $sql2 = $db->prepare("SELECT COUNT(*) FROM file_access WHERE file = ?;");
			$sql2->execute($res[1]);
			while(my @res2 = $sql2->fetchrow_array()) { $accesscount = to_int($res2[0]); }
			print "<tr><td>" . $res[2] . "</td><td>" . to_int($res[4]) . "</td><td>" . $res[0] . "</td><td>" . $res[3] . "</td><td>" . $accesscount . "</td><td><a href='./?file=" . $res[1] . "'>" . $res[1] . "</a>";
			if($logged_lvl >= to_int($cfg->load('upload_lvl'))) { print "<span class='pull-right'><form method='POST' action='.'><input type='hidden' name='m' value='files'><input type='hidden' name='delete_file' value=\"" . $res[1] . "\"><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Really remove this file?\");' value='X'></form></span>"; }
			print "</td></tr>\n";
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#files_table').DataTable({'order':[[0,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>\n";
		print "</div></div>\n";
		if($logged_lvl > 5)
		{
			if($q->param('clear_log'))
			{
				$sql = $db->prepare("DELETE FROM file_access;");
				$sql->execute();
			}			
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Access log</h3></div><div class='panel-body'>\n";
			$sql = $db->prepare("SELECT * FROM file_access ORDER BY ROWID DESC LIMIT 5000;");
			$sql->execute();
			print "<form style='display:inline' method='POST' action='./?m=files'><input type='hidden' name='m' value='files'><input type='hidden' name='clear_log' value='1'><input class='btn btn-danger pull-right' type='submit' onclick='return confirm(\"Are you sure?\");' value='Clear log'><br></form>";
			print "<table class='table table-striped' id='files_log'><thead><tr><th>IP address</th><th>File ID</th><th>Date</th></tr></thead><tbody>\n";
			while(my @res = $sql->fetchrow_array())
			{
				print "<tr><td>" . $res[0] . "</td><td>" . $res[1] . "</td><td>" . $res[2] . "</td></tr>\n";
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#files_log').DataTable({'order':[[2,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script>\n";
			print "</div></div>\n";
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
						$filedata = Data::GUID->new;
						$filename = substr(sanitize_html($q->param('attach_file')), 0, 40);
						my $file_size = (-s $tmpfilename);
						if($file_size > to_int($cfg->load('max_size')))
						{
							msg("File size is larger than accepted value. Please go back and try again.", 0);
							footers();
							exit(0);
						}
						elsif($cfg->load('upload_exts') ne "" && index($cfg->load('upload_exts'), (split /\./, $filename)[-1]) == -1)
						{
							msg("File type is not in the list of allowed extensions. Please go back and try again.", 0);
							footers();
							exit(0);
						}
						else
						{
							my $io_handle = $lightweight_fh->handle;
							binmode($io_handle);
							my ($buffer, $bytesread);
							open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
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
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=view_ticket&t=" . to_int($q->param('t')) . "'>Comment added.", 3);
		}
		else
		{
			msg("Comment must be more than 1 and less than 10,000 characters. Please go back and try again.", 0);
		}
	}
	elsif($q->param('m') eq "subscribe" && $q->param('articleid') && $logged_user ne "")
	{
		headers("Articles");
		$sql = $db->prepare("INSERT INTO subscribe VALUES (?, ?)");
		$sql->execute($logged_user, to_int($q->param('articleid')));
		msg("Article <b>" . to_int($q->param('articleid')) . "</b> added to your home page. Press <a href='./?kb=" . to_int($q->param('articleid')) . "'>here</a> to continue.", 3);
	}
	elsif($q->param('m') eq "unsubscribe" && $q->param('articleid') && $logged_user ne "")
	{
		headers("Articles");
		$sql = $db->prepare("DELETE FROM subscribe WHERE user = ? AND articleid = ?");
		$sql->execute($logged_user, to_int($q->param('articleid')));
		msg("Article <b>" . to_int($q->param('articleid')) . "</b> removed from your home page. Press <a href='./?kb=" . to_int($q->param('articleid')) . "'>here</a> to continue.", 3);
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
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Ticket " . to_int($q->param('t')) . "</h3></div><div class='panel-body'>";
				if($logged_lvl > 2 && $q->param('edit')) { print "<form method='POST' action='.'><input type='hidden' name='m' value='update_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'>\n"; }
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
				if($logged_lvl >= to_int($cfg->load('summary_lvl')))
				{
                    print "<p><div class='row'><div class='col-sm-6'>Created by: <b><a href='./?m=summary&u=" . $res[3] . "'>" . $res[3] . "</a></b></div><div class='col-sm-6'>Created on: <b>" . $res[11] . "</b></div></div></p>\n";
				}
				else
				{
					print "<p><div class='row'><div class='col-sm-6'>Created by: <b>" . $res[3] . "</b></div><div class='col-sm-6'>Created on: <b>" . $res[11] . "</b></div></div></p>\n";
				}
				print "<p><div class='row'><input type='hidden' name='ticket_assigned' value='" . $res[4] . "'><div class='col-sm-6'>Assigned to: <b>" . $res[4] . "</b>";
				if($logged_lvl > 2 && $q->param('edit'))
				{ 
					print " <input type='checkbox' name='ticket_assign_self'";
					if($res[4] =~ /\b\Q$logged_user\E\b/) { print " checked"; }
					print "><i> Assign yourself</i>"; 
				}
				print "</div><div class='col-sm-6'>Modified on: <b>" . $res[12] . "</b></div></div></p>\n";
				if($logged_lvl > 2 && $q->param('edit')) 
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
					print ">Closed</option></select></div><div class='col-sm-6'>Resolution: <input type='text' name='ticket_resolution' class='form-control' value=\"" . $res[9] . "\"></div></div></p>\n"; 
				}
				else {print "<p><div class='row'><div class='col-sm-6'>Status: <b>" . $res[8] . "</b></div><div class='col-sm-6'>Resolution: <b>" . $res[9] . "</b></div></div></p>\n"; }
				print "<p><div class='row'><div class='col-sm-6'>" . $items{"Release"} . "s: ";
				if($logged_lvl > 2 && $q->param('edit')) { print "<input type='text' class='form-control' name='ticket_releases' value=\"" . $res[2] . "\">"; }
				else { print "<b>" . $res[2] . "</b>"; }
				print "</div><div class='col-sm-6'>";
				if($logged_lvl > 2 && $q->param('edit'))
				{ 
					print "Priority: <select class='form-control' name='ticket_priority'>";
					if($res[7] eq "High") { print "<option selected>High</option><option>Normal</option><option>Low</option>"; }
					elsif($res[7] eq "Low") { print "<option>High</option><option>Normal</option><option selected>Low</option>"; }
					else { print "<option>High</option><option selected>Normal</option><option>Low</option>"; }
					print "</select></div></div></p>\n"; }
				else
				{
					print "Priority: <b>";
					if($res[7] eq "High") { print "<img src='icons/high.png'> High"; }
					elsif($res[7] eq "Low") { print "<img src='icons/low.png'> Low"; }
					else { print "<img src='icons/normal.png'> Normal"; }
					print "</b></div></div></p>\n";
				}
				if($logged_lvl > 2 && $q->param('edit')) { print "<p>Title: <input type='text' class='form-control' name='ticket_title' maxlength='50' value=\"" . $res[5] . "\"></p>"; }
				else
				{ 
					print ""; 
					if($cfg->load('comp_billing') eq "on" && $cfg->load('comp_clients') eq "on")
					{
						print "<p><div class='row'><div class='col-sm-6'>Title: <b>" . $res[5] . "</b></div><div class='col-sm-6'>Billable to: <b>";
						my $sql2 = $db->prepare("SELECT client FROM billing WHERE ticketid = ?;");
						$sql2->execute(to_int($q->param('t')));
						while(my @res2 = $sql2->fetchrow_array()) { print $res2[0]; }
						print "</b></div></div></p>";
					}
					else { print "<p>Title: <b>" . $res[5] . "</b></p>"; }
				}
				if($logged_lvl > 2 && $q->param('edit'))
				{ 
					print "<p>Previous description:<br><textarea class='form-control' name='ticket_desc' rows='10'";
					if($logged_lvl < to_int($cfg->load('past_lvl'))) { print " readonly"; }
					print ">" . $res[6] . "</textarea></p>\n";
					print "<p><div class='row'><div class='col-sm-12'>Summary of work done:<input type='text' class='form-control' name='work_done'></div></div></p>\n"; 
				}
				else { print "<p>Description:<br><pre>" . $res[6] . "</pre></p>"; }
				if($logged_lvl > 2 && $q->param('edit'))
				{ 
					print "<div class='row'>";
					if($cfg->load('comp_billing') eq "on" && $cfg->load('comp_clients') eq "on")
					{
						if($cfg->load('comp_articles') eq "on") { print "<div class='col-sm-4'>Billable to: "; }
						else { print "<div class='col-sm-8'>Billable to: "; }
						my $sql2 = $db->prepare("SELECT client FROM billing WHERE ticketid = ?;");
						$sql2->execute(to_int($q->param('t')));
						my $client = "";
						while(my @res2 = $sql2->fetchrow_array()) { $client = $res2[0]; }
						print "<select class='form-control' name='billable'><option></option>";
						$sql2 = $db->prepare("SELECT name FROM clients WHERE status != 'Closed' ORDER BY name;");
						$sql2->execute();
						while(my @res2 = $sql2->fetchrow_array())
						{
							if($client eq $res2[0]) { print "<option selected>" . $res2[0] . "</option>"; }
							else { print "<option>" . $res2[0] . "</option>"; } 
						}
						print "</select></div>";
					}
					if($cfg->load('comp_articles') eq "on")
					{
						if($cfg->load('comp_billing') eq "on" && $cfg->load('comp_clients') eq "on") { print "<div class='col-sm-4'>"; }
						else { print "<div class='col-sm-8'>"; }
						print "Link article: <select class='form-control' name='link_article'><option></option>";
						my $sql2 = $db->prepare("SELECT ROWID,title FROM kb WHERE published = 1 AND (productid = ? OR productid = 0);");
						$sql2->execute(to_int($res[1]));
						while(my @res2 = $sql2->fetchrow_array()) { print "<option value=" . $res2[0] . ">" . $res2[1] . "</option>"; }
						print "</select></div>";
					}
					print "</div><div class='row'>";
					if($cfg->load('comp_time') eq "on") { print "<div class='col-sm-4'>Time spent (in <b>hours</b>): <input type='text' name='time_spent' class='form-control' value='0'></div><div class='col-sm-4'>"; }
					else { print "<div class='col-sm-8'>"; }
					print "Notify user: <select name='notify_user' class='form-control'><option selected></option>";
					my $sql2 = $db->prepare("SELECT name FROM users WHERE level > 0 ORDER BY name;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
					print "</select></div>";
					if($cfg->load('comp_time') ne "on") { print "<div class='col-sm-4'></div>"; }
					print "<div class='col-sm-4'><input class='btn btn-primary pull-right' type='submit' value='Update ticket'></div></div></form><hr>\n"; 
				}
				if($logged_lvl > 2 && !$q->param('edit'))
				{
					print "<form method='GET' action='.'><input type='hidden' name='m' value='view_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-primary pull-right' type='submit' name='edit' value='Edit ticket'></form>";
				}
				if($logged_user ne "")
				{
					if($res[10] =~ /\b\Q$logged_user\E\b/) { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='unfollow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-primary' type='submit' value='Remove favorite'></form>"; }
					else { print "<form action='.' method='POST' style='display:inline'><input type='hidden' name='m' value='follow_ticket'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'><input class='btn btn-primary' type='submit' value='Add favorite'></form>"; }
				}
				if($logged_user eq $cfg->load("admin_name") && $q->param('edit')) { print "<span class='pull-right'><form method='GET' action='.'><input type='hidden' name='m' value='confirm_delete'><input type='hidden' name='ticketid' value='" . to_int($q->param('t')) . "'><input type='submit' class='btn btn-danger' value='Permanently delete this ticket'></form></span>"; }
				print "</div></div>\n";
				if($logged_lvl > 1 && $cfg->load('comp_time') eq "on")
				{
					$sql = $db->prepare("SELECT * FROM timetracking WHERE ticketid = ? ORDER BY ROWID DESC;");
					$sql->execute(to_int($q->param('t')));
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Time breakdown</h3></div><div class='panel-body'><table class='table table-striped' id='time_table'><thead><tr><th>User</th><th>Hours spent</th><th>Date</th></tr></thead><tbody>\n";
					my $totaltime = 0;
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[1] . "</td><td>" . $res[2] . "</td><td>" . $res[3] . "</td></tr>\n";
						$totaltime += to_float($res[2]);
					}
					print "</tbody><tfoot><tr><th>Total</th><th>" . $totaltime . "</th><th></th></tr></tfoot>\n";
					print "</table><script>\$(document).ready(function(){\$('#time_table').DataTable({'order':[[2,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
				}
				print "<h3>Comments</h3>";
				if($logged_lvl > 0 && $res[8] ne "Closed")
				{
					print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add comment</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'><input type='hidden' name='m' value='add_comment'><input type='hidden' name='t' value='" . to_int($q->param('t')) . "'>\n";
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
					{ print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'><i>" . $res[4] . "</i></span>" . $res[2] . "</h3></div><div class='panel-body'>"; }
					else
					{ print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'><i>" . $res[4] . "</i> (Edited: <i>" . $res[5] . "</i>)</span>" . $res[2] . "</h3></div><div class='panel-body'>"; }
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
	elsif($q->param('m') eq "search" && $logged_lvl > 0 && $q->param('q'))
	{
		headers("Search");
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Search results for: <i>" . sanitize_html($q->param('q')) . "</i></h3></div><div class='panel-body'>\n";
		if($cfg->load("comp_tickets") eq "on" && (($cfg->load('default_vis') eq "Restricted" && $logged_lvl > 1) || ($cfg->load('default_vis') eq "Private" && $logged_lvl > -1) || $cfg->load('default_vis') eq "Public"))
		{
			print "<h4>Tickets</h4>";
			print "<table class='table table-stripped' id='search1'><thead><tr><th>ID</th><th>User</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Date</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM tickets ORDER BY ROWID DESC LIMIT 1000;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] == to_int($q->param('q')) || index($res[5], sanitize_html($q->param('q'))) != -1 || index($res[6], sanitize_html($q->param('q'))) != -1)
				{ 
					print "<tr><td><nobr>";
					if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
					elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
					else { print "<img src='icons/normal.png' title='Normal'> "; }
					print $res[0] . "</nobr></td><td>" . $res[3] . "</td><td>" . $products[$res[1]] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; 
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#search1').DataTable({'order':[[0,'desc']],pageLength:10,dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script><br>\n";
		}
		if($cfg->load("comp_articles") eq "on")
		{
			print "<h4>Support articles</h4>";
			print "<table class='table table-striped' id='search2'><thead><tr><th>ID</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Last update</th></tr></thead><tbody>\n";
			if($logged_lvl > 3) { $sql = $db->prepare("SELECT ROWID,* FROM kb ORDER BY ROWID DESC LIMIT 1000;"); }
			else { $sql = $db->prepare("SELECT ROWID,* FROM kb WHERE published = 1 ORDER BY ROWID DESC LIMIT 1000;"); }
			$sql->execute();
			my $product = "";
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] == to_int($q->param('q')) || index($res[2], sanitize_html($q->param('q'))) != -1 || index($res[3], sanitize_html($q->param('q'))) != -1)
				{
					if(to_int($res[1]) == 0) { $product = "All"; }
					elsif(!$products[$res[1]]) { $product = "All"; }
					else { $product = $products[$res[1]]; }
					if($res[7] eq "Never") { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[6] . "</td></tr>\n"; }
					else { print "<tr><td>" . $res[0] . "</td><td>" . $product . "</td><td><a href='./?kb=" . $res[0] . "'>" . $res[2] . "</a></td><td>" . $res[7] . "</td></tr>\n"; }
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#search2').DataTable({'order':[[2,'asc']],pageLength:10,dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script><br>\n";
		}
		if($cfg->load("comp_items") eq "on")
		{
			my $expired = 0;
			my $expdate = "";
			my $m = localtime->strftime('%m');
			my $y = localtime->strftime('%Y');
			my $d = localtime->strftime('%d');
			print "<h4>Inventory items</h4>";
			print "<table class='table table-striped' id='search3'><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>Status</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM items ORDER BY ROWID DESC LIMIT 1000;"); 
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] == to_int($q->param('q')) || index($res[1], sanitize_html($q->param('q'))) != -1 || index($res[3], sanitize_html($q->param('q'))) != -1)
				{
					my $sql3 = $db->prepare("SELECT date FROM item_expiration WHERE itemid = ?;");
					$sql3->execute(to_int($res[0]));
					while(my @res3 = $sql3->fetchrow_array())
					{
						my @expby = split(/\//, $res3[0]);
						if($expby[2] < $y || ($expby[2] == $y && $expby[0] < $m) || ($expby[2] == $y && $expby[0] == $m && $expby[1] < $d)) { $expired = 1; }
					}
					print "<tr><td>" . $res[2] . "</td><td><a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[3] . "</td><td>";
					if(to_int($res[7]) == 0) { print "<font color='red'>Unavailable</font>"; }
					elsif(to_int($res[7]) == 1) 
					{
						if($expired == 1) { print "<font color='purple'>Expired</font>"; }
						else { print "<font color='green'>Available</font>"; } 
					}
					elsif(to_int($res[7]) == 2) { print "<font color='orange'>Waiting approval for: " . $res[8] . "</font>"; }
					else { print "<font color='red'>Checked out by: " . $res[8] . "</font>"; }
					print "</td></tr>\n";
					$expired = 0;
				}
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#search3').DataTable({'order':[[0,'asc']],pageLength:10,dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script><br>\n";
		}
		if($cfg->load("comp_clients") eq "on")
		{
			print "<h4>Clients directory</h4>";
			print "<table class='table table-stripped' id='search4'><thead><tr><th>ID</th><th>Name</th><th>Contact</th><th>Status</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM clients ORDER BY ROWID DESC LIMIT 1000;");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($res[0] == to_int($q->param('q')) || index($res[1], sanitize_html($q->param('q'))) != -1 || index($res[3], sanitize_html($q->param('q'))) != -1 || index($res[4], sanitize_html($q->param('q'))) != -1)
				{
					print "<tr><td>" . $res[0] . "</td><td>";
					if($logged_lvl >= to_int($cfg->load('client_lvl'))) { print "<a href='./?m=view_client&c=" . $res[0] . "'>"; }
					print $res[1];
					if($logged_lvl >= to_int($cfg->load('client_lvl'))) { print "</a>"; }
					print "</td><td>" . $res[3] . "</td><td>" . $res[2] . "</td></tr>";
				}
			}		
			print "</tbody></table><script>\$(document).ready(function(){\$('#search4').DataTable({'order':[[0,'asc']],pageLength:10,dom:'Bfrtip',buttons:['copy','csv','excel','pdf','print']});});</script>";
		}
		print "</div></div>\n";
	}
	elsif($q->param('m') eq "add_ticket" && ($logged_lvl > 0 || $cfg->load("guest_tickets") eq "on") && $q->param('product_id'))
	{
		if($logged_user eq "") { $logged_user = "Guest"; } 
		headers("Tickets");
		my @customform;
		my $description = "";
		my $title;
		my $assignedto = "";
		my $lnk = "Normal";
		my @field = ["", "", "", "", "", "", "", "", "", ""];
		$sql = $db->prepare("SELECT * FROM forms WHERE productid = ?;");
		$sql->execute(to_int($q->param('product_id')));
		@customform = $sql->fetchrow_array();
		if(!@customform) # Product doesn't have a custom form assigned, but is there a default form defined?
		{
			$sql = $db->prepare("SELECT * FROM default_form;");
			$sql->execute();
			my $formid = -1;
			while(my @res = $sql->fetchrow_array()) { $formid = to_int($res[0]); }
			if($formid != -1)
			{
				$sql = $db->prepare("SELECT * FROM forms WHERE ROWID = ?;");
				$sql->execute($formid);
				@customform = $sql->fetchrow_array();
			}
		}
		if(@customform) # A custom form is linked to this product, or there is a default form
		{
			if($q->param('field0')) { $title = $q->param('field0'); }
			for(my $i = 0; $i < 10; $i++)
			{
				if($customform[($i*2)+2])
				{
					$description .= $customform[($i*2)+2] . " \t ";
					if(defined($q->param('field'.$i))) { $description .= $q->param('field'.$i); $field[$i] = sanitize_html($q->param('field'.$i)); }
					elsif($q->param('upload'.$i)) { $description .= $q->param('upload'.$i); $field[$i] = sanitize_html($q->param('upload'.$i)); }
					elsif($q->param('priority'.$i)) { $description .= $q->param('priority'.$i); $lnk = sanitize_alpha($q->param('priority'.$i)); $field[$i] = $lnk; }
					elsif($q->param('assign'.$i)) { $description .= $q->param('assign'.$i); $assignedto .= sanitize_alpha($q->param('assign'.$i)) . " "; $field[$i] = sanitize_alpha($q->param('assign'.$i)); }
					$description .= "\n\n"; 
				}
			}
		}
		else # No custom form, parse title/description fields
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
				$sql = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array()) { $assignedto .= $res[0] . " "; }
				$sql = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('release_id')), $logged_user, $assignedto, sanitize_html($title), sanitize_html($description), $lnk, "New", "", "", now(), "Never");
				$sql = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
				$sql->execute(to_int($q->param('product_id')));
				while(my @res = $sql->fetchrow_array())
				{
					notify($res[1], "New ticket created", "A new ticket was created for one of your " . lc($items{"Product"}) . "s:\n\nUser: " . $logged_user . "\nTitle: " . sanitize_html($title) . "\nPriority: " . $lnk . "\nDescription: " . sanitize_html($description));
				}
				foreach my $assign (split(' ', $assignedto))
				{
					notify($assign, "New ticket created", "A new ticket was created for a " . lc($items{"Product"}) . " assigned to you:\n\nUser: " . $logged_user . "\nTitle: " . sanitize_html($title) . "\nPriority: " . $lnk . "\nDescription: " . sanitize_html($description));
				}
				$sql = $db->prepare("SELECT last_insert_rowid();");
				$sql->execute();
				my $lastrowid = 0;
				while(my @res = $sql->fetchrow_array())
				{
					$lastrowid = to_int($res[0]);
				}
				if($lastrowid != 0)
				{
					if($cfg->load('newticket_plugin'))
					{
						my $cmd = $cfg->load('newticket_plugin');
						my $s0 = to_int($q->param('product_id'));
						my $s1 = sanitize_html($q->param('release_id'));
						my $s2 = sanitize_html($title);
						my $s3 = sanitize_html($description);
						my $s4 = $lastrowid;
						$cmd =~ s/\%product\%/\"$s0\"/g;
						$cmd =~ s/\%release\%/\"$s1\"/g;
						$cmd =~ s/\%title\%/\"$s2\"/g;
						$cmd =~ s/\%description\%/\"$s3\"/g;
						$cmd =~ s/\%ticket\%/\"$s4\"/g;
						$cmd =~ s/\%user\%/\"$logged_user\"/g;
						$cmd =~ s/\n/ /g;
						$cmd =~ s/\r/ /g;
						system($cmd);
					}
					if($q->param('client'))
					{
						$sql = $db->prepare("INSERT INTO billing VALUES (?, ?);");
						$sql->execute($lastrowid, sanitize_html($q->param($q->param('client'))));
					}
					for(my $i = 0; $i < 10; $i++)
					{
						if($customform[($i*2)+2] && $q->param('upload'.$i) && $cfg->load('upload_folder'))
						{
							eval
							{
								my $lightweight_fh = $q->upload('upload'.$i);
								if(defined $lightweight_fh)
								{
									my $tmpfilename = $q->tmpFileName($lightweight_fh);
									my $filedata = Data::GUID->new;
									my $filename = substr(sanitize_html($q->param('upload'.$i)), 0, 40);
									my $file_size = (-s $tmpfilename);
									if($file_size > to_int($cfg->load('max_size')))
									{
										msg("File size is too large, upload aborted for: " . sanitize_html($q->param('upload'.$i)), 4);
									}
									elsif($cfg->load('upload_exts') ne "" && index($cfg->load('upload_exts'), (split /\./, $filename)[-1]) == -1)
									{
										msg("File type is not in the list of allowed extensions, upload aborted for: " . sanitize_html($q->param('upload'.$i)), 4);
									}
									else
									{
										my $io_handle = $lightweight_fh->handle;
										binmode($io_handle);
										my ($buffer, $bytesread);
										open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $filedata) or die $@;
										while($bytesread = $io_handle->read($buffer,1024))
										{
											print $OUTFILE $buffer;
										}
										$sql = $db->prepare("INSERT INTO comments VALUES (?, ?, ?, ?, ?, ?, ?);");
										$sql->execute($lastrowid, $logged_user, $customform[($i*2)+2], now(), "Never", $filedata, $filename);
									}
								}
							};
						}
					}
				}
				my $redirect_url = "./?m=view_ticket&t=" . $lastrowid;
				my $pj = to_int($q->param('product_id'));
				my $rj = sanitize_html($q->param('release_id'));
				my $field1 = $field[1];
				my $field2 = $field[2];
				my $field3 = $field[3];
				my $field4 = $field[4];
				my $field5 = $field[5];
				my $field6 = $field[6];
				my $field7 = $field[7];
				my $field8 = $field[8];
				my $field9 = $field[9];
				$description = sanitize_html($description);
				$title = sanitize_html($title);
				my $sql2 = $db->prepare("SELECT ROWID FROM routing ORDER BY priority;");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					my %actions;
					my %conditions;
					$sql = $db->prepare("SELECT key,value FROM routing_conditions WHERE route = ?;");
					$sql->execute(to_int($res2[0]));
					while(my @res = $sql->fetchrow_array())
					{ $conditions{$res[0]} = $res[1]; }
					my $processactions = 0;
					if(exists($conditions{'lvl_or_higher'}))
					{
						if($logged_lvl >= to_int($conditions{'lvl_or_higher'})) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'lvl_or_lower'}))
					{
						if($logged_lvl <= to_int($conditions{'lvl_or_lower'})) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'project_match'}))
					{
						if($pj == to_int($conditions{'project_match'})) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'username_match'}))
					{
						if(index($logged_user, $conditions{'username_match'}) != -1) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'title_match'}))
					{
						if(index($title, $conditions{'title_match'}) != -1) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'description_match'}))
					{
						if(index($description, $conditions{'description_match'}) != -1) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'field_match'}) && exists($conditions{'field_match_text'}))
					{
						if(index($field[$conditions{'field_match'}], $conditions{'field_match_text'}) != -1) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if(exists($conditions{'group_memberof'}) && exists($conditions{'group_basedn'}) && $cfg->load("ad_server") ne "")
					{
						my $found = 0;
						my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent("Could not connect to AD server to check group membership.");
						if($ldap)
						{
							my $mesg;
							if($conditions{'group_creds_username'} ne "" && $conditions{'group_creds_password'} ne "") { $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $conditions{'group_creds_username'}, password => RC4($cfg->load("enc_key"), decode_base64($conditions{'group_creds_password'}))); }
							else { $mesg = $ldap->bind; }
							$mesg = $ldap->search(base => $conditions{'group_basedn'}, filter => "(&(objectClass=user)(memberOf=" . $conditions{'group_memberof'} . "))");
							if($mesg->code)
							{
								logevent("LDAP: " . $mesg->error . " [" . $mesg->code . "]");
							}
							else
							{
								while (my $entry = $mesg->pop_entry())
								{
									if($entry->get_value('sAMAccountName') eq $logged_user)
									{ 
										$found = 1;
									}
								}
							}
							$mesg = $ldap->unbind;
						}
						if($found == 1) { $processactions += 1; }
						else { $processactions = -999; }
					}
					if($processactions > 0)
					{
						$sql = $db->prepare("SELECT key,value FROM routing_actions WHERE route = ?;");
						$sql->execute(to_int($res2[0]));
						while(my @res = $sql->fetchrow_array())
						{ $actions{$res[0]} = $res[1]; }
						if(exists($actions{'status'}))
						{
							$sql = $db->prepare("UPDATE tickets SET status = ? WHERE ROWID = ?;");
							$sql->execute($actions{'status'}, $lastrowid);
						}
						if(exists($actions{'resolution'}))
						{
							$sql = $db->prepare("UPDATE tickets SET resolution = ? WHERE ROWID = ?;");
							$sql->execute($actions{'resolution'}, $lastrowid);
						}
						if(exists($actions{'assign_user'}))
						{
							$assignedto .= " " . $actions{'assign_user'};
							$sql = $db->prepare("UPDATE tickets SET assignedto = ? WHERE ROWID = ?;");
							$sql->execute($assignedto, $lastrowid);
							notify($actions{'assign_user'}, "New ticket created", "A new ticket was created and routed to you:\n\nUser: " . $logged_user . "\nTitle: " . $title . "\nPriority: " . $lnk . "\nDescription: " . $description);
						}
						if(exists($actions{'output_file'}) && exists($actions{'output_file_text'}))
						{
							my $outf = $actions{'output_file'};
							$outf =~ s/\%user\%/$logged_user/g;
							$outf =~ s/\%ticket\%/$lastrowid/g;
							$outf =~ s/\%title\%/$title/g;
							$outf =~ s/\%description\%/$description/g;
							$outf =~ s/\%priority\%/$lnk/g;
							$outf =~ s/\%assigned\%/$assignedto/g;
							$outf =~ s/\%product\%/$pj/g;
							$outf =~ s/\%release\%/$rj/g;
							$outf =~ s/\%field1\%/$field1/g;
							$outf =~ s/\%field2\%/$field2/g;
							$outf =~ s/\%field3\%/$field3/g;
							$outf =~ s/\%field4\%/$field4/g;
							$outf =~ s/\%field5\%/$field5/g;
							$outf =~ s/\%field6\%/$field6/g;
							$outf =~ s/\%field7\%/$field7/g;
							$outf =~ s/\%field8\%/$field8/g;
							$outf =~ s/\%field9\%/$field9/g;
							my $out = $actions{'output_file_text'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							if(open(my $OUTFILE, ">>", $outf))
							{
								print $OUTFILE $out;
								close($OUTFILE);
							}
						}
						if(exists($actions{'notify_user'}) && exists($actions{'notify_user_text'}) && exists($actions{'notify_user_title'}))
						{
							my $out = $actions{'notify_user_text'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							my $outt = $actions{'notify_user_title'};
							$outt =~ s/\%user\%/$logged_user/g;
							$outt =~ s/\%ticket\%/$lastrowid/g;
							$outt =~ s/\%title\%/$title/g;
							$outt =~ s/\%description\%/$description/g;
							$outt =~ s/\%priority\%/$lnk/g;
							$outt =~ s/\%assigned\%/$assignedto/g;
							$outt =~ s/\%release\%/$rj/g;
							$outt =~ s/\%product\%/$pj/g;
							$outt =~ s/\%field1\%/$field1/g;
							$outt =~ s/\%field2\%/$field2/g;
							$outt =~ s/\%field3\%/$field3/g;
							$outt =~ s/\%field4\%/$field4/g;
							$outt =~ s/\%field5\%/$field5/g;
							$outt =~ s/\%field6\%/$field6/g;
							$outt =~ s/\%field7\%/$field7/g;
							$outt =~ s/\%field8\%/$field8/g;
							$outt =~ s/\%field9\%/$field9/g;
							my $outu = $actions{'notify_user'};
							$outu =~ s/\%user\%/$logged_user/g;
							notify($outu, $outt, $out);
						}
						if(exists($actions{'open_url'}))
						{
							my $out = $actions{'open_url'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							print "<script>window.open(\"" . $out . "\");</script>";
						}
						if($cfg->load("ad_domain") ne "" && exists($actions{'attr_basedn'}) && exists($actions{'attr_user'}) && exists($actions{'attr_name'}) && exists($actions{'attr_value'}) && exists($actions{'attr_creds_username'}) && exists($actions{'attr_creds_password'}))
						{
							my $out = $actions{'attr_value'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							my $uout = $actions{'attr_user'};
							$uout =~ s/\%user\%/$logged_user/g;
							$uout =~ s/\%ticket\%/$lastrowid/g;
							$uout =~ s/\%title\%/$title/g;
							$uout =~ s/\%description\%/$description/g;
							$uout =~ s/\%priority\%/$lnk/g;
							$uout =~ s/\%assigned\%/$assignedto/g;
							$uout =~ s/\%product\%/$pj/g;
							$uout =~ s/\%release\%/$rj/g;
							$uout =~ s/\%field1\%/$field1/g;
							$uout =~ s/\%field2\%/$field2/g;
							$uout =~ s/\%field3\%/$field3/g;
							$uout =~ s/\%field4\%/$field4/g;
							$uout =~ s/\%field5\%/$field5/g;
							$uout =~ s/\%field6\%/$field6/g;
							$uout =~ s/\%field7\%/$field7/g;
							$uout =~ s/\%field8\%/$field8/g;
							$uout =~ s/\%field9\%/$field9/g;
							my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent("Could not connect to AD server to check group membership.");
							if($ldap)
							{
								my $mesg;
								my $dn = "";
								$mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $actions{'attr_creds_username'}, password => RC4($cfg->load("enc_key"), decode_base64($actions{'attr_creds_password'})));
								$mesg = $ldap->search(base => $actions{'attr_basedn'}, filter => "(&(objectCategory=person)(objectClass=user))");
								if($mesg->code)
								{
									logevent("LDAP: " . $mesg->error . " [" . $mesg->code . "]");
								}
								else
								{
									while (my $entry = $mesg->pop_entry())
									{
										if($entry->get_value('sAMAccountName') eq $uout) { $dn = $entry->get_value('distinguishedName'); }
									}
									if($dn ne "")
									{
										logevent("LDAP: Updating attribute [" . $actions{'attr_name'} . "] of user [" . $dn . "]");
										$mesg = $ldap->modify($dn, replace => { $actions{'attr_name'} => $out });
										if($mesg->code)
										{
											logevent("LDAP: " . $mesg->error . " [" . $mesg->code . "]");
										}
									}
								}
								$mesg = $ldap->unbind;
							}
						}
						if(exists($actions{'popup_message'}))
						{
							my $out = $actions{'popup_message'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							print "<script>alert(\"" . $out . "\");</script>";
						}
						if(exists($actions{'redirect_url'}))
						{
							my $out = $actions{'redirect_url'};
							$out =~ s/\%user\%/$logged_user/g;
							$out =~ s/\%ticket\%/$lastrowid/g;
							$out =~ s/\%title\%/$title/g;
							$out =~ s/\%description\%/$description/g;
							$out =~ s/\%priority\%/$lnk/g;
							$out =~ s/\%assigned\%/$assignedto/g;
							$out =~ s/\%product\%/$pj/g;
							$out =~ s/\%release\%/$rj/g;
							$out =~ s/\%field1\%/$field1/g;
							$out =~ s/\%field2\%/$field2/g;
							$out =~ s/\%field3\%/$field3/g;
							$out =~ s/\%field4\%/$field4/g;
							$out =~ s/\%field5\%/$field5/g;
							$out =~ s/\%field6\%/$field6/g;
							$out =~ s/\%field7\%/$field7/g;
							$out =~ s/\%field8\%/$field8/g;
							$out =~ s/\%field9\%/$field9/g;
							$redirect_url = $out;
						}
						$sql = $db->prepare("UPDATE routing SET hits = hits + 1 WHERE ROWID = ?;");
						$sql->execute(to_int($res2[0]));						
					}
				}
				msg("<meta http-equiv='REFRESH' content='1;url=" . $redirect_url . "'>Ticket successfully added.", 3);
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
	elsif($q->param('m') eq "new_ticket" && ($logged_lvl > 0 || $cfg->load("guest_tickets") eq "on") && $q->param('product_id'))
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
			if(!@customform)
			{
				$sql = $db->prepare("SELECT * FROM default_form;");
				$sql->execute();
				my $formid = -1;
				while(my @res = $sql->fetchrow_array()) { $formid = to_int($res[0]); }
				if($formid != -1)
				{
					$sql = $db->prepare("SELECT * FROM forms WHERE ROWID = ?;");
					$sql->execute($formid);
					@customform = $sql->fetchrow_array();
				}
			}
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Create a new ticket</h3></div><div class='panel-body'><form method='POST' action='.' enctype='multipart/form-data'>\n";
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
						elsif(to_int($customform[($i*2)+3]) == 10) { print "<input type='text' class='form-control datepicker' name='field" . $i . "' placeholder='mm/dd/yyyy'>"; }
						elsif(to_int($customform[($i*2)+3]) == 13) { print "<input type='tel' class='form-control' name='field" . $i . "' placeholder='(nnn) nnn-nnnn'>"; }
						elsif(to_int($customform[($i*2)+3]) == 14) 
						{ 
							 if($logged_lvl >= to_int($cfg->load('upload_lvl'))) { print "<input type='file' name='upload" . $i . "'>"; }
							 else { print "<input type='text' value='File uploads not available for your access level.' class='form-control' disabled>"; }
						}
						elsif(to_int($customform[($i*2)+3]) == 11)
						{
							if($cfg->load("comp_billing") eq "on") { print "<input type='hidden' name='client' value='field" . $i . "'>"; }
							print "<select class='form-control' name='field" . $i . "'>";
							my $sql2 = $db->prepare("SELECT name FROM clients WHERE status != 'Closed' ORDER BY name;");
							$sql2->execute();
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
							print "</select>";
						}
						elsif(to_int($customform[($i*2)+3]) == 17)
						{
							print "<select class='form-control' name='priority" . $i . "'><option>High</option><option selected>Normal</option><option>Low</option></select>";
						}
						elsif(to_int($customform[($i*2)+3]) == 18)
						{
							print "<select class='form-control' name='field" . $i . "'>";
							my $sql2 = $db->prepare("SELECT name FROM users ORDER BY name;");
							$sql2->execute();
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
							print "</select>\n";
						}
						elsif(to_int($customform[($i*2)+3]) == 19)
						{
							print "<select class='form-control' name='assign" . $i . "'>";
							my $sql2 = $db->prepare("SELECT name FROM users WHERE level > 2 ORDER BY name;");
							$sql2->execute();
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
							print "</select>\n";
						}
						elsif(to_int($customform[($i*2)+3]) == 15)
						{
							print "<select class='form-control' name='field" . $i . "'>";
							my $sql2 = $db->prepare("SELECT title FROM kb WHERE published = 1 ORDER BY title;");
							$sql2->execute();
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
							print "</select>";
						}
						elsif(to_int($customform[($i*2)+3]) == 16)
						{
							print "<select class='form-control' name='field" . $i . "'>";
							my $sql2 = $db->prepare("SELECT name FROM steps WHERE productid = ? AND user = ? AND completion < 100 ORDER BY name;");
							$sql2->execute(to_int($q->param('product_id')), $logged_user);
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
							print "</select>";
						}
						elsif(to_int($customform[($i*2)+3]) == 12)
						{
							print "<select class='form-control' name='field" . $i . "'>";
							my $sql2 = $db->prepare("SELECT name,serial FROM items WHERE user = ?;");
							if($logged_user ne "") { $sql2->execute($logged_user); }
							else { $sql2->execute("Guest"); }
							while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . " (" . $res2[1] . ")</option>"; }
							print "</select>";
						}
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
			}
			print "<input type='hidden' name='m' value='add_ticket'><input class='btn btn-primary pull-right' type='submit' value='Create ticket'></form></div></div>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM products WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('product_id')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $items{"Product"} . " information</h3></div><div class='panel-body'>\n";
				print "<div class='row'><div class='col-sm-6'>Product name: <b>" . $res[1] . "</b></div><div class='col-sm-6'>" . $items{"Model"} . ": <b>" . $res[2] . "</b></div></div>\n";
				print "<div class='row'><div class='col-sm-6'>Created on: <b>" . $res[6] . "</b></div><div class='col-sm-6'>Last modified on: <b>" . $res[7] . "</b></div></div>\n";
				print "<div class='row'><div class='col-sm-6'>" . $items{"Product"} . " visibility: <b>" . $res[5] . "</b></div></div>\n";
				print "<hr>" . markdown($res[3]) . "\n";
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
		if($q->param('yes')) # Delete confirmed
		{
			if($q->param('productid')) # Delete a project
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
				$sql = $db->prepare("DELETE FROM steps WHERE productid = ?;");
				$sql->execute(to_int($q->param('productid')));
				$sql = $db->prepare("DELETE FROM products WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('productid')));
				logevent("Product deleted: " . to_int($q->param('productid')));
				msg($items{"Product"} . " " . to_int($q->param('productid')) . " and associated tickets deleted. Press <a href='./?m=products'>here</a> to continue.", 3);
			}
			else # Delete a ticket
			{
				$sql = $db->prepare("DELETE FROM tickets WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('ticketid')));
				$sql = $db->prepare("DELETE FROM comments WHERE ticketid = ?;");
				$sql->execute(to_int($q->param('ticketid')));
				logevent("Ticket deleted: " . to_int($q->param('ticketid')));
				msg("Ticket " . to_int($q->param('ticketid')) . " deleted. Press <a href='./?m=tickets'>here</a> to continue.", 3);
			}
		}
		else # Ask confirmation for deleting an item
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
	elsif($q->param('m') eq "lostpass") # Lost password component.. only available if email notifications are on and AD integration off
	{
		headers("Password reset");
		if($cfg->load("smtp_server") && !$cfg->load("ad_domain"))
		{
			if($q->param('user') && $q->param('code')) # Step 3
			{
				my $found = 0;
				my $newpass = "";
				$sql = $db->prepare("SELECT ROWID FROM lostpass WHERE user = ? AND code = ?;");
				$sql->execute(sanitize_alpha($q->param('user')), sanitize_alpha($q->param('code')));
				while(my @res = $sql->fetchrow_array())
				{
					$newpass = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..8;
					my $sql2 = $db->prepare("DELETE FROM lostpass WHERE user = ?");
					$sql2->execute(sanitize_alpha($q->param('user')));
					$sql2 = $db->prepare("UPDATE users SET pass = ? WHERE name = ?");
					$sql2->execute(sha1_hex($newpass), sanitize_alpha($q->param('user')));
					notify(sanitize_alpha($q->param('user')), "Password reset", "Your password has successfully been reset from the lost password form. If you believe this was done in error, please contact your system administrator.");
					logevent("Password change: " . sanitize_alpha($q->param('user')));
					$found = 1;
				}
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span class='pull-right'>Step 3/3</span>Password reset</h3></div><div class='panel-body'>";
				if($found == 1)
				{
					print "<p>Your password has successfully been reset. Your new password is: <b>" . $newpass . "</b></p><p>You can now login using this password. Once logged in, you can change your password from the <i>Settings</i> page.</p>";
				}
				else
				{
					print "<p>Invalid code. Please go back and try again.</p>";
				}
				print "</div></div>";
			
			}
			elsif($q->param('user')) # Step 2
			{
				my $found = 0;
				$sql = $db->prepare("SELECT confirm,email FROM users WHERE name = ?;");
				$sql->execute(sanitize_alpha($q->param('user')));
				while(my @res = $sql->fetchrow_array())
				{
					if($res[0] eq "" && $res[1] ne "")
					{
						my $code = join'', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..16;
						my $sql2 = $db->prepare("DELETE FROM lostpass WHERE user = ?");
						$sql2->execute(sanitize_alpha($q->param('user')));
						$sql2 = $db->prepare("INSERT INTO lostpass VALUES (?, ?)");
						$sql2->execute(sanitize_alpha($q->param('user')), $code);
						notify(sanitize_alpha($q->param('user')), "Password reset code", "A password reset was initiated from the lost password form for the account " . sanitize_alpha($q->param('user')) . ". To continue with this reset, please enter the following confirmation code:  " . $code);
						$found = 1; 
					}
				}
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span class='pull-right'>Step 2/3</span>Password reset</h3></div><div class='panel-body'>";
				if($found == 1)
				{
					print "<p>A confirmation code has been sent to your registered email address. Enter it here:</p>";
					print "<p><form method='GET' action='.'><input type='hidden' name='m' value='lostpass'><input type='hidden' name='user' value='" . sanitize_alpha($q->param('user')) . "'><input type='text' name='code' placeholder='Confirmation code' class='form-control'><br><input type='submit' class='btn btn-primary pull-right' value='Confirm'></form></p>";
				}
				else
				{
					print "<p>The specified user does not have a confirmed email address. The process cannot continue.</p>";
				}
				print "</div></div>";
			}
			else # Step 1
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span class='pull-right'>Step 1/3</span>Password reset</h3></div><div class='panel-body'>";
				print "<p>You can reset your password by using this form. Enter your user name:</p>";
				print "<p><form method='GET' action='.'><input type='hidden' name='m' value='lostpass'><input type='text' name='user' placeholder='User name' class='form-control'><br><input type='submit' class='btn btn-primary pull-right' value='Next'></form></p>";
				print "</div></div>";
			}
		}
	}
	elsif($q->param('m') eq "show_report" && $q->param('report') && $logged_lvl >= to_int($cfg->load("report_lvl")))
	{
		my %results;
		my $totalresults = 0;
		headers("Settings");
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		if(to_int($q->param('report')) == 1)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Time spent per user</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>User</th><th>Hours spent</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT * FROM timetracking ORDER BY name;");
		}
		elsif(to_int($q->param('report')) == 2)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>All time spent per ticket</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Ticket ID</th><th>Hours spent</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT * FROM timetracking ORDER BY ticketid;");
		}
		elsif(to_int($q->param('report')) == 16)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Clients per status</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Status</th><th>Clients</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT status FROM clients;");
		}
		elsif(to_int($q->param('report')) == 17)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Active user sessions</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Timestamp</th><th>User</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT user,expire FROM sessions;");
		}
		elsif(to_int($q->param('report')) == 18)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Item expiration dates</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Serial number</th><th>Date</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT item_expiration.date,items.serial FROM items INNER JOIN item_expiration ON items.ROWID = item_expiration.itemid;");
		}
		elsif(to_int($q->param('report')) == 19)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Disabled users</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>User</th><th>State</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT 'Disabled',user FROM disabled;");
		}
		elsif(to_int($q->param('report')) == 20)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Client events per user</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Event</th><th>User</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT user,summary FROM events;");
		}
		elsif(to_int($q->param('report')) == 11)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Your time spent per ticket</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Ticket ID</th><th>Hours spent</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT * FROM timetracking WHERE name == \"$logged_user\" ORDER BY ticketid;");		
		}
		elsif(to_int($q->param('report')) == 3)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets created per " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>" . $items{"Product"} . "</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT productid FROM tickets ORDER BY productid;");
		}
		elsif(to_int($q->param('report')) == 13)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets linked per article</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Article</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT DISTINCT kb,ticketid FROM kblink ORDER BY kb;");
		}
		elsif(to_int($q->param('report')) == 14)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Full shoutbox history</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Time</th><th>Message</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT created,user,msg FROM shoutbox;");
		}
		elsif(to_int($q->param('report')) == 15)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Items checked out per user</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Serial number</th><th>User</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT user,serial FROM items WHERE status = 3;");
		}
		elsif(to_int($q->param('report')) == 10)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>New and open tickets per " . lc($items{"Product"}) . "</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>" . $items{"Product"} . "</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT productid FROM tickets WHERE status == 'Open' OR status == 'New' ORDER BY productid;");
		}
		elsif(to_int($q->param('report')) == 4)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets created per user</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>User</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT createdby FROM tickets ORDER BY createdby;");
		}
		elsif(to_int($q->param('report')) == 5)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets created per day</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Day</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT created,ROWID FROM tickets ORDER BY ROWID;");
		}
		elsif(to_int($q->param('report')) == 6)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets created per month</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Month</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT created,ROWID FROM tickets ORDER BY ROWID;");
		}
		elsif(to_int($q->param('report')) == 7)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets per status</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Status</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT status FROM tickets ORDER BY status;");
		}
		elsif(to_int($q->param('report')) == 8)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Users per access level</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Access level</th><th>Users</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT level FROM users ORDER BY level;");
		}
		elsif(to_int($q->param('report')) == 9)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Tickets assigned per user</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>User</th><th>Tickets</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT name FROM users;");
		}
		elsif(to_int($q->param('report')) == 12)
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Comment file attachments</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Filename</th><th>GUID</th></tr></thead><tbody>";
			$sql = $db->prepare("SELECT file,filename FROM comments WHERE file != '';");
		}
		else
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Unknown report</h3></div><div class='panel-body'><table class='table table-striped' id='report_table'><thead><tr><th>Unknown</th><th>Unknown</th></tr></thead><tbody>";
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
			elsif(to_int($q->param('report')) == 12 || to_int($q->param('report')) == 15 || to_int($q->param('report')) == 17 || to_int($q->param('report')) == 18 || to_int($q->param('report')) == 19 || to_int($q->param('report')) == 20)
			{
				$results{$res[1]} = $res[0];
			}
			elsif(to_int($q->param('report')) == 14)
			{
				$results{$res[0]} = $res[1] . ": " . $res[2];			
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
			elsif(to_int($q->param('report')) == 4 || to_int($q->param('report')) == 7 || to_int($q->param('report')) == 8 || to_int($q->param('report')) == 13 || to_int($q->param('report')) == 16)
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
				print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; 
				$totalresults += to_float($results{$k});
			}
		}
		elsif(to_int($q->param('report')) == 5)
		{
			foreach my $k (sort by_date keys(%results)) # date sorting
			{
				print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>";
				$totalresults += to_float($results{$k});
			}		
		}
		elsif(to_int($q->param('report')) == 6)
		{
			foreach my $k (sort by_month keys(%results)) # month sorting
			{
				print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; 
				$totalresults += to_float($results{$k});
			}		
		}
		else
		{
			foreach my $k (sort(keys(%results))) # alphabetical sorting
			{
				print "<tr><td>" . $k . "</td><td>" . $results{$k} . "</td></tr>"; 
				$totalresults += to_float($results{$k});
			}
		}
		if(to_int($totalresults) == 0) { $totalresults = keys(%results); }
		print "</tbody><tfoot><tr><td><b>Total</b></td><td><b>" . $totalresults . "</b></td></tr>";
		print "</tfoot></table><script>\$(document).ready(function(){\$('#report_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>"; 
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
		my @products;
		$sql = $db->prepare("SELECT ROWID,* FROM products;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		headers("Tickets");
		if($logged_lvl > 0  || $cfg->load("guest_tickets") eq "on")  # add new ticket pane
		{
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Create a new ticket</h3></div><div class='panel-body'><form method='POST' action='.'>\n";
			print "<p><div class='row'><div class='col-sm-8'>Select a " . lc($items{"Product"}) . " name: <select class='form-control' name='product_id'>";
			$sql = $db->prepare("SELECT ROWID,* FROM products WHERE vis != 'Archived';");
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				if($logged_lvl > 1 || $res[5] ne "Restricted") { print "<option value=" . $res[0] . ">" . $res[1] . "</option>"; }
			}
			print "</select></div><div class='col-sm-4'><input type='hidden' name='m' value='new_ticket'><input class='btn btn-primary pull-right' type='submit' value='Next'></div></div></p></form></div></div>\n";
		}
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>";
		if($cfg->load("hide_close") eq "on") { print "Active tickets"; }
		else { print "Tickets"; }
		print "</h3></div><div class='panel-body'>\n";
		print "<table class='table table-stripped' id='tickets_table'><thead><tr><th>ID</th><th>User</th><th>" . $items{"Product"} . "</th><th>Title</th><th>Status</th><th>Date</th></tr></thead><tbody>\n";
		if($cfg->load("hide_close") eq "on") { $sql = $db->prepare("SELECT ROWID,* FROM tickets WHERE status != 'Closed' ORDER BY ROWID DESC;"); }
		else { $sql = $db->prepare("SELECT ROWID,* FROM tickets ORDER BY ROWID DESC;"); }
		$sql->execute();
		while(my @res = $sql->fetchrow_array())
		{
			if($products[$res[1]] && (($cfg->load("default_vis") eq "Public" || ($cfg->load("default_vis") eq "Private" && $logged_lvl > -1) || ($res[3] eq $logged_user) || $logged_lvl > 1)))
			{ 
				print "<tr><td><nobr>";
				if($res[7] eq "High") { print "<img src='icons/high.png' title='High'> "; }
				elsif($res[7] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
				else { print "<img src='icons/normal.png' title='Normal'> "; }
				print $res[0] . "</nobr></td><td>" . $res[3] . "</td><td>" . $products[$res[1]] . "</td><td><a href='./?m=view_ticket&t=" . $res[0] . "'>" . $res[5] . "</a></td><td>" . $res[8] . "</td><td>" . $res[11] . "</td></tr>\n"; 
			}
		}
		print "</tbody></table><script>\$(document).ready(function(){\$('#tickets_table').DataTable({'order':[[0,'desc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
	}
	elsif($q->param('m') eq "items" && $cfg->load('comp_items') eq "on" && $logged_user ne "")
	{
		my $expired = 0;
		my $expdate = "";
		my $m = localtime->strftime('%m');
		my $y = localtime->strftime('%Y');
		my $d = localtime->strftime('%d');
		my @products;
		$sql = $db->prepare("SELECT ROWID,name FROM products ORDER BY name;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $products[$res[0]] = $res[1]; }
		my @clients;
		$sql = $db->prepare("SELECT ROWID,name FROM clients ORDER BY name;");
		$sql->execute();
		while(my @res = $sql->fetchrow_array()) { $clients[$res[0]] = $res[1]; }
		headers("Items");
		if($q->param('new_item'))
		{
			if(!$q->param('name') || !$q->param('type') || !$q->param('product_id') || !$q->param('client_id') || !$q->param('serial')) 
			{
				my $text = "Required fields missing: ";
				if(!$q->param('name')) { $text .= "<span class='label label-danger'>Item name</span> "; }
				if(!$q->param('type')) { $text .= "<span class='label label-danger'>Item type</span> "; }
				if(!$q->param('serial')) { $text .= "<span class='label label-danger'>Serial number</span> "; }
				if(!$q->param('product_id')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . "</span> "; }
				if(!$q->param('client_id')) { $text .= "<span class='label label-danger'>Client</span> "; }
				$text .= " Please go back and try again.";
				msg($text, 0);
			}
			else
			{
				my $info = "";
				if($q->param('info')) { $info = sanitize_html($q->param('info')); }
				my $approval = 0;
				if($q->param('approval')) { $approval = 1; }
				my $found = 0;
				$sql = $db->prepare("SELECT * FROM items WHERE serial = ?;");
				$sql->execute(sanitize_html($q->param('serial')));
				while(my @res = $sql->fetchrow_array()) { $found = 1; }
				if($found)
				{
					msg("Serial number already exists. Please go back and try again.", 0)
				}
				else
				{
					$sql = $db->prepare("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
					$sql->execute(sanitize_html($q->param('name')), sanitize_html($q->param('type')), sanitize_html($q->param('serial')), to_int($q->param('product_id')), to_int($q->param('client_id')), $approval, 1, "", $info);
					$sql = $db->prepare("SELECT last_insert_rowid();");
					$sql->execute();
					my $lastrowid = 0;
					while(my @res = $sql->fetchrow_array())
					{
						$lastrowid = to_int($res[0]);
					}
					msg("<meta http-equiv='REFRESH' content='1;url=./?m=items&i=" . $lastrowid . "'>New item added.", 3);
				}
			}
		}
		elsif($q->param('i'))
		{
			if($q->param('save_item') && $logged_lvl > 3)
			{
				if(!$q->param('type') || !$q->param('product_id') || !$q->param('client_id') || !$q->param('serial')) 
				{
					my $text = "Required fields missing: ";
					if(!$q->param('type')) { $text .= "<span class='label label-danger'>Item type</span> "; }
					if(!$q->param('serial')) { $text .= "<span class='label label-danger'>Serial number</span> "; }
					if(!$q->param('product_id')) { $text .= "<span class='label label-danger'>" . $items{"Product"} . "</span> "; }
					if(!$q->param('client_id')) { $text .= "<span class='label label-danger'>Client</span> "; }
					$text .= " Please go back and try again.";
					msg($text, 0);
				}
				else
				{
					my $info = "";
					if($q->param('info')) { $info = sanitize_html($q->param('info')); }
					my $approval = 0;
					if($q->param('approval')) { $approval = 1; }
					my $found = 0;
					$sql = $db->prepare("SELECT * FROM items WHERE serial = ? AND ROWID != ?;");
					$sql->execute(sanitize_html($q->param('serial')), to_int($q->param('i')));
					while(my @res = $sql->fetchrow_array()) { $found = 1; }
					if($found)
					{
						msg("Serial number already exists. Please go back and try again.", 0)
					}
					else
					{
						$sql = $db->prepare("UPDATE items SET type = ?, productid = ?, clientid = ?, serial = ?, approval = ?, info = ? WHERE ROWID = ?;");
						$sql->execute(sanitize_html($q->param('type')), to_int($q->param('product_id')), to_int($q->param('client_id')), sanitize_html($q->param('serial')), $approval, $info, to_int($q->param('i')));
						msg("Item updated.", 3);
					}
				}
			}
			if($q->param('deny') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
				$sql2->execute(to_int($q->param('i')));
				while(my @res2 = $sql2->fetchrow_array())
				{
					notify($res2[8], "Checkout request denied", "Item name: " . $res2[1] . "\nItem type: " . $res2[2] . "\nSerial number: " . $res2[3]);
				}
				$sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
				$sql2->execute("", 1, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Approval denied", now());
				msg("Checkout request denied.", 3);
			}
			if($q->param('approve') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("UPDATE items SET status = ? WHERE ROWID = ?;");
				$sql2->execute(3, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Checkout approved", now());
				msg("Checkout request approved.", 3);
				$sql2 = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
				$sql2->execute(to_int($q->param('i')));
				while(my @res2 = $sql2->fetchrow_array())
				{
					notify($res2[8], "Checkout request approved", "Item name: " . $res2[1] . "\nItem type: " . $res2[2] . "\nSerial number: " . $res2[3] . "\nAdditional information: " . $res2[9]);
					if($cfg->load('checkout_plugin'))
					{
						my $cmd = $cfg->load('checkout_plugin');
						my $u = $res2[8];
						my $s = $res2[3];
						$cmd =~ s/\%user\%/\"$u\"/g;
						$cmd =~ s/\%serial\%/\"$s\"/g;
						$cmd =~ s/\n/ /g;
						$cmd =~ s/\r/ /g;
						system($cmd);
					}	
				}
			}
			if($q->param('assign') && $q->param('user') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
				$sql2->execute(sanitize_alpha($q->param('user')), 3, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Assigned to " . sanitize_alpha($q->param('user')), now());
				msg("Item assigned to user <b>" . sanitize_alpha($q->param('user')) . "</b>.", 3);
				$sql2 = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
				$sql2->execute(to_int($q->param('i')));
				while(my @res2 = $sql2->fetchrow_array())
				{
					notify(sanitize_alpha($q->param('user')), "Item assigned to you", "An item has been assigned to you.\n\nItem name: " . $res2[1] . "\nItem type: " . $res2[2] . "\nSerial number: " . $res2[3] . "\nAdditional information: " . $res2[9]);
					if($cfg->load('checkout_plugin'))
					{
						my $cmd = $cfg->load('checkout_plugin');
						my $u = sanitize_alpha($q->param('user'));
						my $s = $res2[3];
						$cmd =~ s/\%user\%/\"$u\"/g;
						$cmd =~ s/\%serial\%/\"$s\"/g;
						$cmd =~ s/\n/ /g;
						$cmd =~ s/\r/ /g;
						system($cmd);
					}					
				}
			}
			if($q->param('expiration') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("DELETE FROM item_expiration WHERE itemid = ?;");
				$sql2->execute(to_int($q->param('i')));
				if($q->param('exp_date'))
				{
					if($q->param('exp_date') !~ m/[0-9]{2}\/[0-9]{2}\/[0-9]{4}/)
					{
						msg("Expiration date must be in the format: mm/dd/yyyy. Please go back and try again.", 0);
					}
					else
					{
						$sql2 = $db->prepare("INSERT INTO item_expiration VALUES (?, ?);");
						$sql2->execute(to_int($q->param('i')), sanitize_html($q->param('exp_date')));
						msg("Item expiration date set to <b>" . sanitize_html($q->param('exp_date')) . "</b>.", 3);
						$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
						$sql2->execute(to_int($q->param('i')), $logged_user, "Expiration set to " . sanitize_html($q->param('exp_date')), now());
					}
				}
				else
				{
					msg("Item expiration date removed.", 3);
					$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
					$sql2->execute(to_int($q->param('i')), $logged_user, "Expiration date removed", now());				
				}
			}
			$expdate = "";
			$sql = $db->prepare("SELECT date FROM item_expiration WHERE itemid = ?;");
			$sql->execute(to_int($q->param('i')));
			while(my @res = $sql->fetchrow_array())
			{
				$expdate = $res[0];
				my @expby = split(/\//, $expdate);
				if($expby[2] < $y || ($expby[2] == $y && $expby[0] < $m) || ($expby[2] == $y && $expby[0] == $m && $expby[1] < $d)) { $expired = 1; }
			}
			if($q->param('unavailable') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
				$sql2->execute("", 0, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Made unavailable", now());
				msg("Item made unavailable.", 3);
			}
			if($q->param('delete') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("DELETE FROM items WHERE ROWID = ?;");
				$sql2->execute(to_int($q->param('i')));
				$sql2 = $db->prepare("DELETE FROM checkouts WHERE itemid = ?;");
				$sql2->execute(to_int($q->param('i')));
				msg("<meta http-equiv='REFRESH' content='1;url=./?m=items'>Item removed.", 3);
			}
			if($q->param('available') && $logged_lvl > 3)
			{
				my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
				$sql2->execute("", 1, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Made available", now());
				msg("Item made available.", 3);
			}
			if($q->param('checkin') && $logged_lvl > 0)
			{
				my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
				$sql2->execute("", 1, to_int($q->param('i')));
				$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
				$sql2->execute(to_int($q->param('i')), $logged_user, "Returned", now());
				msg("<meta http-equiv='REFRESH' content='1;url=./?m=items'>Item returned.", 3);
			}
			if($q->param('checkout') && $logged_lvl > 0)
			{
				$sql = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('i')));
				while(my @res = $sql->fetchrow_array())
				{
					if($res[6] == 1) # Approval needed
					{
						my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
						$sql2->execute($logged_user, 2, to_int($q->param('i')));
						$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
						$sql2->execute(to_int($q->param('i')), $logged_user, "Requested", now());
						msg("Request sent. You will be notified after it is approved or denied.", 3);
						notify($logged_user, "Item requested", "Your checkout request was sent. You will be notified after it is approved or denied.\n\nItem name: " . $res[1] . "\nItem type: " . $res[2] . "\nSerial number: " . $res[3]);
						$sql2 = $db->prepare("SELECT name FROM users WHERE level > 3 AND email != '';");
						$sql2->execute();
						while(my @res2 = $sql2->fetchrow_array())
						{
							notify($res2[0], "Checkout requested", "A checkout request was submitted by: " . $logged_user . "\n\nItem name: " . $res[1] . "\nItem type: " . $res[2] . "\nSerial number: " . $res[3]);
						}
					}
					else # Checkout
					{
						my $sql2 = $db->prepare("UPDATE items SET user = ?, status = ? WHERE ROWID = ?;");
						$sql2->execute($logged_user, 3, to_int($q->param('i')));
						$sql2 = $db->prepare("INSERT INTO checkouts VALUES (?, ?, ?, ?);");
						$sql2->execute(to_int($q->param('i')), $logged_user, "Checked out", now());
						msg("Item checked out.", 3);
						notify($logged_user, "Item checked out", "Item name: " . $res[1] . "\nItem type: " . $res[2] . "\nSerial number: " . $res[3] . "\nAdditional information: " . $res[9]);
						if($cfg->load('checkout_plugin'))
						{
							my $cmd = $cfg->load('checkout_plugin');
							my $u = $logged_user;
							my $s = $res[3];
							$cmd =~ s/\%user\%/\"$u\"/g;
							$cmd =~ s/\%serial\%/\"$s\"/g;
							$cmd =~ s/\n/ /g;
							$cmd =~ s/\r/ /g;
							system($cmd);
						}
					}
				}
			}
			$sql = $db->prepare("SELECT ROWID,* FROM items WHERE ROWID = ?;");
			$sql->execute(to_int($q->param('i')));
			while(my @res = $sql->fetchrow_array())
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>" . $res[1] . "</h3></div><div class='panel-body'>";
				if(!$q->param('edit'))
				{
					print "<p><div class='row'><div class='col-sm-6'>Type: <b>" . $res[2] . "</b></div><div class='col-sm-6'>Serial number: <b>" . $res[3] . "</b></div></div></p>";
					print "<p><div class='row'><div class='col-sm-6'>Related " . lc($items{'Product'}) . ": <b>";
					if($products[$res[4]]) { print $products[$res[4]]; }
					else { print "None"; }
					if($cfg->load('comp_clients') eq "on")
					{
						print "</b></div><div class='col-sm-6'>Related client: <b>";
						if($clients[$res[5]]) { print $clients[$res[5]]; }
						else { print "None"; }
					}			
					print "</b></div></div></p><p><div class='row'><div class='col-sm-6'>Checkout approval: <b>";
					if(to_int($res[6]) == 1) { print "Required"; }
					else { print "Not required"; } 	
					print "</b></div><div class='col-sm-6'>Expiration date: <b>" . $expdate . "</b></div></div></p>";
					if(($logged_user eq $res[8] && $res[7] == 3) || $logged_lvl > 3) { print "<p>Additional information:<br><pre>" . $res[9] . "</pre></p>"; }
					print "<p>Status: <b>";
					if(to_int($res[7]) == 0) { print "Unavailable"; }
					elsif(to_int($res[7]) == 1) 
					{
						if($expired == 1) { print "Expired"; } 
						else { print "Available"; } 
					}
					elsif(to_int($res[7]) == 2) 
					{
						if($logged_lvl >= to_int($cfg->load('summary_lvl'))) { print "Waiting approval for: <a href='./?m=summary&u=" . $res[8] . "'>" . $res[8] . "</a>"; }
						else { print "Waiting approval for: " . $res[8]; } 
					}
					else
					{
						if($logged_lvl >= to_int($cfg->load('summary_lvl'))) { print "Checked out by: <a href='./?m=summary&u=" . $res[8] . "'>" . $res[8] . "</a>"; }
						else { print "Checked out by: " . $res[8]; } 
					}
					print "</b></p>";
					if($logged_lvl > 3) 
					{
						print "<form style='display:inline' method='GET' action='.'><input type='hidden' name='m' value='items'><input type='hidden' name='i' value='" . to_int($q->param('i')) . "'><input type='submit' class='btn btn-primary pull-right' name='edit' value='Edit item'></form>"; 
					}
					if($logged_lvl > 0 && $res[7] == 1 && $expired == 0)
					{
						print "<form style='display:inline' method='GET' action='.'><input type='hidden' name='m' value='items'><input type='hidden' name='i' value='" . to_int($q->param('i')) . "'><input type='submit' class='btn btn-primary' name='checkout' value='";
						if(to_int($res[6]) == 1) { print "Request"; }
						else { print "Checkout"; }
						print "'></form>"; 
					}
					print " <form style='display:inline' method='GET' action='http://chart.apis.google.com/chart'><input type='hidden' name='cht' value='qr'><input type='hidden' name='chs' value='300x300'><input type='hidden' name='chld' value='H|0'><input type='hidden' name='chl' value='" . $res[3] . "'><input type='submit' class='btn btn-primary' value='QR'></form></p>";
				}
				elsif($logged_lvl > 3)
				{
					print "<form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='items'><input type='hidden' name='i' value='" . to_int($q->param('i')) . "'>\n";
					print "<p><div class='row'><div class='col-sm-6'>Item type: <select name='type' class='form-control'><option";
					if($res[2] eq "Desktop") { print " selected"; }
					print ">Desktop</option><option";
					if($res[2] eq "Laptop") { print " selected"; }
					print ">Laptop</option><option";
					if($res[2] eq "Server") { print " selected"; }
					print ">Server</option><option";
					if($res[2] eq "Keyboard") { print " selected"; }
					print ">Keyboard</option><option";
					if($res[2] eq "Mouse") { print " selected"; }
					print ">Mouse</option><option";
					if($res[2] eq "Display") { print " selected"; }
					print ">Display</option><option";
					if($res[2] eq "Phone") { print " selected"; }
					print ">Phone</option><option";
					if($res[2] eq "Printer") { print " selected"; }
					print ">Printer</option><option";
					if($res[2] eq "Peripheral") { print " selected"; }
					print ">Peripheral</option><option";
					if($res[2] eq "Software") { print " selected"; }
					print ">Software</option><option";
					if($res[2] eq "Furniture") { print " selected"; }
					print ">Furniture</option><option";
					if($res[2] eq "Tool") { print " selected"; }
					print ">Tool</option><option";
					if($res[2] eq "Vehicle") { print " selected"; }
					print ">Vehicle</option><option";
					if($res[2] eq "Other") { print " selected"; }
					print ">Other</option></select></div><div class='col-sm-6'>Serial number: <input type='text' maxlength='30' class='form-control' name='serial' value='" . $res[3] . "' required></div></div></p>\n";
					print "<p><div class='row'><div class='col-sm-6'>Related " . lc($items{"Product"}) . ": <select class='form-control' name='product_id'><option>None</option>";
					for(my $i = 1; $i < scalar(@products); $i++)
					{
						if($products[$i]) 
						{
							if(to_int($res[4]) == $i) { print "<option value='" . $i . "' selected>" . $products[$i] . "</option>"; }
							else { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; }
						} 
					}
					print "</select></div>";
					if($cfg->load('comp_clients') eq "on")
					{
						print "<div class='col-sm-6'>Related client: <select class='form-control' name='client_id'><option>None</option>";
						for(my $i = 1; $i < scalar(@clients); $i++)
						{
							if($clients[$i]) 
							{
								 if(to_int($res[5]) == $i) { print "<option value='" . $i . "' selected>" . $clients[$i] . "</option>"; }
								 else { print "<option value='" . $i . "'>" . $clients[$i] . "</option>"; }
							} 
						}
						print "</select></div>";
					}
					else { print "<input type='hidden' name='client_id' value='None'>"; }
					print "</div></p>";
					print "<p>Information provided on checkout: <textarea name='info' class='form-control'>" . $res[9] . "</textarea></p>";
					print "<p><label><input type='checkbox' name='approval'";
					if(to_int($res[6]) == 1) { print " checked"; }
					print "> Require approval for checkout</label></p>";
					print "<p><input type='submit' name='save_item' class='btn btn-primary pull-right' value='Save'>";
					if($res[7] == 0) { print "<input type='submit' name='available' class='btn btn-success' value='Make available'>"; }
					else { print "<input type='submit' name='unavailable' class='btn btn-danger' value='Make unavailable'>"; }
					print " <input type='submit' name='delete' class='btn btn-danger' value='Delete item'>";
					print "</p><hr><p><div class='row'><div class='col-sm-4'>Assign to user: <select name='user' class='form-control'>";
					my $sql2 = $db->prepare("SELECT name FROM users WHERE level > 0 ORDER BY name;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array()) { print "<option>" . $res2[0] . "</option>"; }
					print "</select></div><div class='col-sm-2'><br><input type='submit' name='assign' class='btn btn-primary' value='Assign'></div>";
					print "<div class='col-sm-4'>Set expiration date: <input name='exp_date' class='form-control datepicker' placeholder='mm/dd/yyyy' value ='";
					$sql2 = $db->prepare("SELECT date FROM item_expiration WHERE itemid = ?;");
					$sql2->execute(to_int($q->param('i')));
					while(my @res2 = $sql2->fetchrow_array()) { print $res2[0]; }
					print "'></div><div class='col-sm-2'><br><input type='submit' name='expiration' class='btn btn-primary' value='Set'></div></div></p></form>";
				}
				print "</div></div>\n";
			}
			if($logged_lvl > 0)
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Checkout history</h3></div><div class='panel-body'><table class='table table-striped' id='checkouts_table'><thead><tr><th>User</th><th>Event</th><th>Time</th></tr></thead><tbody>";		
				$sql = $db->prepare("SELECT user,event,time FROM checkouts WHERE itemid = ?;");
				$sql->execute(to_int($q->param('i')));
				while(my @res = $sql->fetchrow_array())
				{
					print "<tr><td>" . $res[0] . "</td><td>" . $res[1] . "</td><td>" . $res[2] . "</td></tr>";
				}
				print "</tbody></table><script>\$(document).ready(function(){\$('#checkouts_table').DataTable({'order':[[2,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>";
			}
		}
		else # Items list
		{
			if($logged_lvl > 3)
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Add a new item</h3></div><div class='panel-body'><form method='POST' action='.' data-toggle='validator' role='form'><input type='hidden' name='m' value='items'>\n";
				print "<p><div class='row'><div class='col-sm-4'>Item type: <select name='type' class='form-control'><option>Desktop</option><option>Laptop</option><option>Server</option><option>Keyboard</option><option>Mouse</option><option>Display</option><option>Phone</option><option>Printer</option><option>Peripheral</option><option>Software</option><option>Furniture</option><option>Tool</option><option>Vehicle</option><option>Other</option></select></div><div class='col-sm-4'>Item name: <input type='text' maxlength='50' class='form-control' name='name' required></div><div class='col-sm-4'>Serial number: <input type='text' maxlength='30' class='form-control' name='serial' required></div></div></p>\n";
				print "<p><div class='row'><div class='col-sm-6'>Related " . lc($items{"Product"}) . ": <select class='form-control' name='product_id'><option>None</option>";
				for(my $i = 1; $i < scalar(@products); $i++)
				{
					if($products[$i]) { print "<option value='" . $i . "'>" . $products[$i] . "</option>"; } 
				}
				print "</select></div>";
				if($cfg->load('comp_clients') eq "on")
				{
					print "<div class='col-sm-6'>Related client: <select class='form-control' name='client_id'><option>None</option>";
					for(my $i = 1; $i < scalar(@clients); $i++)
					{
						if($clients[$i]) { print "<option value='" . $i . "'>" . $clients[$i] . "</option>"; } 
					}
					print "</select></div>";
				}
				else { print "<input type='hidden' name='client_id' value='None'>"; }
				print "</div></p>";
				print "<p>Information provided on checkout: <textarea name='info' class='form-control'></textarea></p>";
				print "<p><input type='submit' name='new_item' class='btn btn-primary pull-right' value='Add item'><label><input type='checkbox' name='approval'> Require approval for checkout</label></p></form></div></div>\n";
			}
			print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Inventory items</h3></div><div class='panel-body'>";
			if($logged_lvl > 3)
			{
				my $apprcount = 0;
				$sql = $db->prepare("SELECT COUNT(*) FROM items WHERE status = 2;");
				$sql->execute();
				while(my @res = $sql->fetchrow_array()) { $apprcount = to_int($res[0]); }
				if($apprcount > 0)
				{
					print "<h4>Items awaiting approval</h4>";
					print "<table class='table table-striped' id='approval_table'><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>User</th><th>Action</th></tr></thead><tbody>\n";
					$sql = $db->prepare("SELECT ROWID,* FROM items WHERE status = 2;");
					$sql->execute();
					while(my @res = $sql->fetchrow_array())
					{
						print "<tr><td>" . $res[2] . "</td><td>" . $res[1] . "</td><td>" . $res[3] . "</td><td>" . $res[8] . "</td><td><form method='POST' action='.'><input type='hidden' name='m' value='items'><input type='hidden' name='i' value='" . $res[0] . "'><input class='btn btn-success' type='submit' name='approve' value='Approve'> <input type='submit' class='btn btn-danger' name='deny' value='Deny'></form></td></tr>\n";
					}
					print "</tbody></table><script>\$(document).ready(function(){\$('#approval_table').DataTable({'order':[[0,'asc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script><hr><h4>Items list</h4>\n";
				}
			}
			print "<table class='table table-striped' id='items_table'><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>Status</th></tr></thead><tbody>\n";
			$sql = $db->prepare("SELECT ROWID,* FROM items;"); 
			$sql->execute();
			while(my @res = $sql->fetchrow_array())
			{
				my $sql3 = $db->prepare("SELECT date FROM item_expiration WHERE itemid = ?;");
				$sql3->execute(to_int($res[0]));
				while(my @res3 = $sql3->fetchrow_array())
				{
					my @expby = split(/\//, $res3[0]);
					if($expby[2] < $y || ($expby[2] == $y && $expby[0] < $m) || ($expby[2] == $y && $expby[0] == $m && $expby[1] < $d)) { $expired = 1; }
				}
				print "<tr><td>" . $res[2] . "</td><td><a href='./?m=items&i=" . $res[0] . "'>" . $res[1] . "</a></td><td>" . $res[3] . "</td><td>";
				if(to_int($res[7]) == 0) { print "<font color='red'>Unavailable</font>"; }
				elsif(to_int($res[7]) == 1) 
				{
					if($expired == 1) { print "<font color='purple'>Expired</font>"; }
					else { print "<font color='green'>Available</font>"; } 
				}
				elsif(to_int($res[7]) == 2) { print "<font color='orange'>Waiting approval for: " . $res[8] . "</font>"; }
				else { print "<font color='red'>Checked out by: " . $res[8] . "</font>"; }
				print "</td></tr>\n";
				$expired = 0;
			}
			print "</tbody></table><script>\$(document).ready(function(){\$('#items_table').DataTable({'order':[[0,'asc']],pageLength:" . to_int($cfg->load('page_len')) . ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
		}
	}
	else # This happens if an invalid address was specified, or if the user's session ran out
	{
		headers("Error");
		msg("Unknown module or access denied. Please login first.", 0);
	}
	footers();
}
elsif(($q->param('create_form') || $q->param('edit_form') || $q->param('save_form')) && $logged_lvl >= to_int($cfg->load("customs_lvl")))
{
	headers("Custom forms");
	if($q->param('save_form'))
	{
		if($q->param('form_name') && $q->param('field0') && defined($q->param('product_id'))) # Save new form
		{
			$sql = $db->prepare("UPDATE forms SET productid = 0 WHERE productid = ?;");
			$sql->execute(to_int($q->param('product_id')));
			if($q->param('save_form') == -1)
			{
				$sql = $db->prepare("INSERT INTO forms VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('form_name')), sanitize_html($q->param('field0')), sanitize_html($q->param('field0type')), sanitize_html($q->param('field1')), sanitize_html($q->param('field1type')), sanitize_html($q->param('field2')), sanitize_html($q->param('field2type')), sanitize_html($q->param('field3')), sanitize_html($q->param('field3type')), sanitize_html($q->param('field4')), sanitize_html($q->param('field4type')), sanitize_html($q->param('field5')), sanitize_html($q->param('field5type')), sanitize_html($q->param('field6')), sanitize_html($q->param('field6type')), sanitize_html($q->param('field7')), sanitize_html($q->param('field7type')), sanitize_html($q->param('field8')), sanitize_html($q->param('field8type')), sanitize_html($q->param('field9')), sanitize_html($q->param('field9type')), now());
				if($q->param('make_default'))
				{
					$sql = $db->prepare("SELECT last_insert_rowid();");
					$sql->execute();
					my $rowid = -1;
					while(my @res = $sql->fetchrow_array()) { $rowid = to_int($res[0]); }
					if($rowid != -1)
					{
						$sql = $db->prepare("DELETE FROM default_form");
						$sql->execute();
						$sql = $db->prepare("INSERT INTO default_form VALUES (?)");
						$sql->execute($rowid);
					}
				}
			}
			else # Update existing form
			{
				$sql = $db->prepare("UPDATE forms SET productid = ?, formname = ?, field0 = ?, field0type = ?, field1 = ?, field1type = ?, field2 = ?, field2type = ?, field3 = ?, field3type = ?, field4 = ?, field4type = ?, field5 = ?, field5type = ?, field6 = ?, field6type = ?, field7 = ?, field7type = ?, field8 = ?, field8type = ?, field9 = ?, field9type = ?, modified = ? WHERE ROWID = ?;");
				$sql->execute(to_int($q->param('product_id')), sanitize_html($q->param('form_name')), sanitize_html($q->param('field0')), sanitize_html($q->param('field0type')), sanitize_html($q->param('field1')), sanitize_html($q->param('field1type')), sanitize_html($q->param('field2')), sanitize_html($q->param('field2type')), sanitize_html($q->param('field3')), sanitize_html($q->param('field3type')), sanitize_html($q->param('field4')), sanitize_html($q->param('field4type')), sanitize_html($q->param('field5')), sanitize_html($q->param('field5type')), sanitize_html($q->param('field6')), sanitize_html($q->param('field6type')), sanitize_html($q->param('field7')), sanitize_html($q->param('field7type')), sanitize_html($q->param('field8')), sanitize_html($q->param('field8type')), sanitize_html($q->param('field9')), sanitize_html($q->param('field9type')), now(), to_int($q->param('save_form')));
				if($q->param('make_default'))
				{
					$sql = $db->prepare("DELETE FROM default_form");
					$sql->execute();
					$sql = $db->prepare("INSERT INTO default_form VALUES (?)");
					$sql->execute(to_int($q->param('save_form')));
				}
				else
				{
					$sql = $db->prepare("DELETE FROM default_form WHERE form = ?");
					$sql->execute(to_int($q->param('save_form')));				
				}
			}
			msg("<meta http-equiv='REFRESH' content='1;url=./?m=customforms'>Custom form saved.", 3);
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
	else # Form creation page
	{
		print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Custom form</h3></div><div class='panel-body'><form method='POST' action='.'>";
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
			print ">Satisfaction scale</option><option value=14";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 14) { print " selected"; } }
			print ">File upload</option><option value=13";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 13) { print " selected"; } }
			print ">Phone number</option><option value=10";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 10) { print " selected"; } }
			print ">Date</option><option value=17";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 17) { print " selected"; } }
			print ">Ticket priority</option><option value=18";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 18) { print " selected"; } }
			print ">Users list</option><option value=19";
			if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 19) { print " selected"; } }
			print ">Assign to user</option>";
			if($cfg->load('comp_clients') eq "on")
			{
				print "<option value=11";
				if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 11) { print " selected"; } }
				print ">Client</option>";
			}
			if($cfg->load('comp_items') eq "on")
			{
				print "<option value=12";
				if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 12) { print " selected"; } }
				print ">Checked out item</option>";
			}
			if($cfg->load('comp_articles') eq "on")
			{
				print "<option value=15";
				if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 15) { print " selected"; } }
				print ">Published articles</option>";
			}
			if($cfg->load('comp_steps') eq "on")
			{
				print "<option value=16";
				if(to_int($q->param('edit_form')) > 0) { if(to_int($res[($i*2)+3]) == 16) { print " selected"; } }
				print ">Assigned tasks</option>";
			}
			print "</td></tr>";
		}
		print "</table><p><input type='submit' class='btn btn-primary pull-right' value='Save'><label><input name='make_default' type='checkbox'";
		if(to_int($q->param('edit_form')) > 0)
		{
			$sql = $db->prepare("SELECT * FROM default_form WHERE form = ?;");
			$sql->execute(to_int($q->param('edit_form')));
			while(my @res = $sql->fetchrow_array())
			{ print " checked"; }
		}
		print "> Make this the default form</label></p></form></div></div>";
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
			if($res[7] eq "Never") { print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'>Created: <i>" . $res[6] . "</i></span>Article " . to_int($q->param('kb')) . "</h3></div><div class='panel-body'>\n"; }
			else { print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'><span style='float:right'>Last modified: <i>" . $res[7] . "</i></span>Article " . to_int($q->param('kb')) . "</h3></div><div class='panel-body'>\n"; }
			if($logged_lvl > 3 && $q->param('edit'))
			{
				print "<form method='POST' action='.'><input type='hidden' name='m' value='save_article'><input type='hidden' name='id' value='" . to_int($q->param('kb')) . "'>\n";
				print "<p><div class='row'><div class='col-sm-6'>Title: <input type='text' maxlength='50' class='form-control' name='title' value=\"" . $res[2] . "\"></div><div class='col-sm-6'>\n";
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
				print "<p>Description:<span class='pull-right'><img title='Header' src='icons/header.png' style='cursor:pointer' onclick='javascript:md_header()'> <img title='Bold' src='icons/bold.png' style='cursor:pointer' onclick='javascript:md_bold()'> <img title='Italic' src='icons/italic.png' style='cursor:pointer' onclick='javascript:md_italic()'> <img title='Code' src='icons/code.png' style='cursor:pointer' onclick='javascript:md_code()'> <img title='Image' src='icons/image.png' style='cursor:pointer' onclick='javascript:md_image()'> <img title='Link' src='icons/link.png' style='cursor:pointer' onclick='javascript:md_link()'> <img title='List' src='icons/list.png' style='cursor:pointer' onclick='javascript:md_list()'></span><br><textarea id='markdown' name='article' rows='20' class='form-control'>" . $res[3] . "</textarea></p>\n";
				print "<input type='submit' class='btn btn-primary pull-right' value='Save article'></form>";
			}
			else
			{
				print "<div class='row'><div class='col-sm-6'>Title: <b>" . $res[2] . "</b></div>\n";
				if($res[1] == 0 || !$products[$res[1]]) { print "<div class='col-sm-6'>Applies to: <b>All " . lc($items{"Product"}) . "s</b></div></div>\n"; }
				else { print "<div class='col-sm-6'>Applies to: <b>" . $products[$res[1]] . "</b></div></div>\n"; }
				print "<hr>" . markdown($res[3]) . "\n";
			}
			if($logged_lvl > 3  && !$q->param('edit'))
			{
				print "<form method='GET' action='.'><input type='hidden' name='kb' value='" . to_int($q->param('kb')) . "'><input class='btn btn-primary pull-right' type='submit' name='edit' value='Edit article'></form>";
			} 
			if($logged_user ne "")
			{
				my $sql2 = $db->prepare("SELECT ROWID FROM subscribe WHERE user = ? AND articleid = ?;");
				$sql2->execute($logged_user, to_int($q->param('kb')));
				my $found = 0;
				while(my @res2 = $sql2->fetchrow_array()) { $found = 1;}
				if($found == 1) { print "<form method='GET' action='.'><input type='hidden' name='m' value='unsubscribe'><input type='hidden' name='articleid' value='" . to_int($q->param('kb')) . "'><input class='btn btn-primary' type='submit' value='Remove favorite'></form>"; }
				else { print "<form method='GET' action='.'><input type='hidden' name='m' value='subscribe'><input type='hidden' name='articleid' value='" . to_int($q->param('kb')) . "'><input class='btn btn-primary' type='submit' value='Add favorite'></form>"; }
			}
			print "</div></div>";
			if($cfg->load('comp_tickets') eq "on" && $logged_user ne "")
			{
				print "<div class='panel panel-" . $themes[to_int($cfg->load('theme_color'))] . "'><div class='panel-heading'><h3 class='panel-title'>Active tickets linked to this article</h3></div><div class='panel-body'>\n";
				print "<table class='table table-striped' id='linkedtickets_table'><thead><tr><th>ID</th><th>Title</th><th>Status</th>";
				if($logged_lvl > 3) { print "<th>Unlink</th>"; }
				print "</tr></thead><tbody>\n";
				$sql = $db->prepare("SELECT DISTINCT ticketid FROM kblink WHERE kb = ? ORDER BY ticketid DESC;");
				$sql->execute(to_int($q->param('kb')));
				while(my @res2 = $sql->fetchrow_array())
				{
					my $sql2 = $db->prepare("SELECT title,status,link ticketid FROM tickets WHERE ROWID = ? AND status != 'Closed';");
					$sql2->execute(to_int($res2[0]));
					while(my @res3 = $sql2->fetchrow_array())
					{
						print "<tr><td><nobr>";
						if($res3[2] eq "High") { print "<img src='icons/high.png' title='High'> "; }
						elsif($res3[2] eq "Low") { print "<img src='icons/low.png' title='Low'> "; }
						else { print "<img src='icons/normal.png' title='Normal'> "; }
						print $res2[0] . "</nobr></td><td><a href='./?m=view_ticket&t=" . $res2[0] . "'>" . $res3[0] . "</a></td><td>" . $res3[1] . "</td>";
						if($logged_lvl > 3) { print "<td><a href='./?m=unlink_article&articleid=" . to_int($q->param('kb')) . "&ticketid=" . $res2[0] . "'>Unlink</a></td>"; }
						print "</tr>\n";
					} 
				}
				print "</tbody></table><script>\$(document).ready(function(){\$('#linkedtickets_table').DataTable({'order':[[0,'desc']],pageLength:" .  to_int($cfg->load('page_len')). ",dom:'Bfrtip',buttons:['copy','csv','pdf','print']});});</script></div></div>\n";
			}
		}
		else
		{
			msg("This article is not available.", 0);
		}
	}
	footers();
}
elsif(!$cfg->load("ad_domain") && $q->param('new_name') && $q->param('new_pass1') && $q->param('new_pass2') && ($logged_lvl > 4 || $cfg->load('allow_registrations'))) # Process registration
{
	headers("Registration");
	if($q->param('new_pass1') ne $q->param('new_pass2'))
	{
		msg("Passwords do not match. Please go back and try again.", 0);
	}
	elsif(lc(sanitize_alpha($q->param('new_name'))) eq lc($cfg->load('admin_name')) || lc(sanitize_alpha($q->param('new_name'))) eq "system" || lc(sanitize_alpha($q->param('new_name'))) eq "guest" || lc(sanitize_alpha($q->param('new_name'))) eq "api")
	{
		msg("This user name is reserved. Please go back and try again.", 0);
	}
	elsif(length(sanitize_alpha($q->param('new_name'))) < 3 || length(sanitize_alpha($q->param('new_name'))) > 50 || ($q->param('new_email') && length(sanitize_alpha($q->param('new_email'))) > 99) || length($q->param('new_pass1')) < 6)
	{
		msg("User names should be between 3 and 50 characters, passwords should be at least 6 characters, emails less than 99 characters. Please go back and try again.", 0);
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
			else { msg("<meta http-equiv='REFRESH' content='1;url=./?m=users'>User <b>" . sanitize_alpha($q->param('new_name')) . "</b> added.", 3); }
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
