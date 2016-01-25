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
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(time);
use Mail::RFC822::Address qw(valid);
use File::Basename qw(dirname);
use File::Copy;
use Archive::Zip;
use Net::LDAP;
use Net::SMTP;
use Crypt::RC4;
use Net::IMAP::Simple;
use Email::Simple;

my ($cfg, $db, $sql, $sql2);

# Convert to int so it doesnt throw up on invalid numbers
sub to_int
{
	my ($num) = @_;
	if(!$num) { return 0; }
	elsif(!looks_like_number($num)) { return 0; }
	else { return int($num); }
}

# Return current time
sub now
{
	return "" . localtime;
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
				my $smtp = Net::SMTP->new($cfg->load('smtp_server'), Port => to_int($cfg->load('smtp_port')), Timeout => 5);
				if($cfg->load('smtp_user') && $cfg->load('smtp_pass')) { $smtp->auth($cfg->load('smtp_user'), $cfg->load('smtp_pass')); }
				$smtp->mail($cfg->load('smtp_from'));
				if($smtp->to($res[2]))
				{
					$smtp->data();
					$smtp->datasend("From: " . $cfg->load('smtp_from') . "\n");
					$smtp->datasend("To: " . $res[2] . "\n");
					$smtp->datasend("Subject: " . $cfg->load('site_name') . " - " . $title . "\n\n");
					$smtp->datasend($mesg . "\n\nThis is an automated message from " . $cfg->load('site_name') . ". To disable notifications, log into your account and remove the email under Settings.\n");
					$smtp->datasend();
					$smtp->quit;
				}
			}
		}
	}
}

# Log an event
sub logevent
{
	my ($module, $text) = @_;
	$sql2 = $db->prepare("INSERT INTO auto_log VALUES (?, ?, ?);");
	$sql2->execute($module, $text, now());
}

# Initial config
chdir dirname($0);
$cfg = Config::Win32->new("NodePoint", "settings");

if($cfg->load("db_address"))
{
	$db = DBI->connect("dbi:SQLite:dbname=" . $cfg->load("db_address"), '', '', { RaiseError => 0, PrintError => 0 })
}

if(!defined($db))
{
	print "Error: Could not access database file. Please ensure NodePoint has the proper permissions.";
	exit(1);
};

$sql = $db->prepare("SELECT * FROM auto_log WHERE 0 = 1;") or do
{
	$sql = $db->prepare("CREATE TABLE auto_log (module TEXT, event TEXT, time TEXT);");
	$sql->execute();
};
$sql->finish();
$sql = $db->prepare("SELECT * FROM auto_modules WHERE 0 = 1;") or do
{
	$sql = $db->prepare("CREATE TABLE auto_modules (name TEXT, enabled INT, lastrun TEXT, timestamp INT, result TEXT, description TEXT, schedule INT);");
};
$sql->finish();
$sql = $db->prepare("SELECT * FROM auto WHERE 0 = 1;") or do
{
	$sql = $db->prepare("CREATE TABLE auto (timestamp INT, result TEXT);");
	$sql->execute();
};
$sql->finish();
$sql = $db->prepare("SELECT * FROM auto_config WHERE 0 = 1;") or do
{
	$sql = $db->prepare("CREATE TABLE auto_config (module TEXT, key TEXT, value TEXT);");
	$sql->execute();
};
$sql->finish();

# Main loop
my $runcount = 0;
$sql = $db->prepare("SELECT * FROM auto_modules WHERE enabled = 1;");
$sql->execute();
while(my @res = $sql->fetchrow_array())
{
	if((to_int($res[6]) == 0 && to_int($res[3]) + 290 < time()) || (to_int($res[6]) == 1 && to_int($res[3]) + 890 < time()) || (to_int($res[6]) == 2 && to_int($res[3]) + 3590 < time()) || (to_int($res[6]) == 3 && to_int($res[3]) + 86390 < time()) || (to_int($res[6]) == 4 && to_int($res[3]) + 604790 < time()))
  	{
		$runcount += 1;
		my $result = "Failed";
		if($res[0] eq 'Backup')
		{
			my $folder = "";
			my $type = "Time stamped";
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Backup';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'folder') { $folder = $res2[2]; }
				if($res2[1] eq 'type') { $type = $res2[2]; }
			}
			if($folder eq "")
			{
				logevent($res[0], "Missing folder configuration value.");
			}
			elsif(!-d $folder) 
			{
				logevent($res[0], "Backup folder does not exist.");
			}
			else
			{
				my $zip = Archive::Zip->new();
				$zip->addFile($cfg->load('db_address'), "nodepoint.db");
				if($cfg->load('upload_folder'))
				{
					opendir(DIR, $cfg->load('upload_folder')) or logevent($res[0], "Error archiving uploads folder.");
					while(my $file = readdir(DIR))
					{
						next if ($file =~ m/^\./);
						$zip->addFile($cfg->load('upload_folder') . $cfg->sep . $file, $file);
					}
					closedir(DIR);
				}
				my $zipfile = $folder . $cfg->sep . "nodepoint.zip";
				if($type eq "Time stamped") { $zipfile = $folder . $cfg->sep . "nodepoint_" . to_int(time()) . ".zip"; }
				if($zip->writeToFileNamed($zipfile) == 0)
				{
					my $size = -s $zipfile;
					$result = "Success";
					logevent($res[0], $size . " bytes archive created.");
				}
				else
				{
					logevent($res[0], "Could not backup database.");						
				}
			}
		}
		elsif($res[0] eq 'Bulk export')
		{
			my $filename = "";
			my $table = "Tickets";
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Bulk export';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'filename') { $filename = $res2[2]; }
				if($res2[1] eq 'table') { $table = $res2[2]; }
			}
			if($filename eq "")
			{
				logevent($res[0], "Missing filename configuration value.");
			}
			else
			{
				my $rowcount = 0;
				open(my $OUTFILE, ">", $filename) or logevent($res[0], "Error writing content to export file.");
				if($table eq "Tickets")
				{
					print $OUTFILE "\"title\",\"product_id\",\"release_id\",\"created_by\",\"assigned_to\",\"priority\",\"status\",\"resolution\",\"created\",\"modified\"\n";
					$sql2 = $db->prepare("SELECT * FROM tickets;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						$rowcount += 1;
						print $OUTFILE "\"" . $res2[4] . "\",\"" . $res2[0] . "\",\"" .  $res2[1] . "\",\"" .  $res2[2] . "\",\"" .  $res2[3] . "\",\"" .  $res2[6] . "\",\"" .  $res2[7] . "\",\"" .  $res2[8] . "\",\"" .  $res2[10] . "\",\"" .  $res2[11] . "\"\n";  
					}
				}
				elsif($table eq "Items")
				{
					print $OUTFILE "\"name\",\"type\",\"serial\",\"product_id\",\"client_id\",\"approval\",\"status\",\"user\"\n";
					$sql2 = $db->prepare("SELECT * FROM items;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						$rowcount += 1;
						print $OUTFILE "\"" . $res2[0] . "\",\"" . $res2[1] . "\",\"" .  $res2[2] . "\",\"" .  $res2[3] . "\",\"" .  $res2[4] . "\",\"" .  $res2[5] . "\",\"" .  $res2[6] . "\",\"" .  $res2[7] . "\"\n";  
					}
				}
				elsif($table eq "Tasks")
				{
					print $OUTFILE "\"product_id\",\"name\",\"user\",\"completion\",\"due\"\n";
					$sql2 = $db->prepare("SELECT * FROM steps;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						$rowcount += 1;
						print $OUTFILE "\"" . $res2[0] . "\",\"" . $res2[1] . "\",\"" .  $res2[2] . "\",\"" .  $res2[3] . "\",\"" .  $res2[4] . "\"\n";  
					}
				}
				elsif($table eq "Clients")
				{
					print $OUTFILE "\"name\",\"status\",\"contact\"\n";
					$sql2 = $db->prepare("SELECT * FROM clients;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						$rowcount += 1;
						print $OUTFILE "\"" . $res2[0] . "\",\"" . $res2[1] . "\",\"" .  $res2[2] . "\"\n";  
					}
				}
				elsif($table eq "Users")
				{
					print $OUTFILE "\"name\",\"email\",\"level\",\"last_login\"\n";
					$sql2 = $db->prepare("SELECT * FROM users;");
					$sql2->execute();
					while(my @res2 = $sql2->fetchrow_array())
					{
						$rowcount += 1;
						print $OUTFILE "\"" . $res2[0] . "\",\"" . $res2[2] . "\",\"" .  $res2[3] . "\",\"" .  $res2[4] . "\"\n";  
					}
				}
				close($OUTFILE);
				$result = "Success";
				logevent($res[0], "Exported " . $rowcount . " rows.");
			}
		}
		elsif($res[0] eq 'Users sync')
		{
			my $aduser = "";
			my $adpass = "";
			my $basedn = "";
			my $searchfilter = "";
			my $importemail = 0;
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Users sync';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
				if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
				if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
				if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("api_write"), $res2[2]); }
				if($res2[1] eq 'importemail') { $importemail = to_int($res2[2]); }
			}
			if($basedn eq "")
			{
				logevent($res[0], "Missing Base DN configuration value.");
			}
			else
			{
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent($res[0], "Could not connect to AD server.");
				my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $aduser, password => $adpass);
				$mesg = $ldap->search(base => $basedn, filter => $searchfilter);
				if($mesg->code)
				{
					logevent($res[0], "LDAP: " . $mesg->error . " [" . $mesg->code . "]");
				}
				else
				{
					my $rowcount = 0;
					my $updcount = 0;
					my $newcount = 0;
					foreach my $entry ($mesg->entries)
					{
						my $name = $entry->get_value('sAMAccountName');
						my $mail = $entry->get_value('mail');
						my $existing = 0;
						$sql2 = $db->prepare("SELECT COUNT(*) FROM users WHERE name = ?;");
						$sql2->execute(sanitize_alpha($name));
						while(my @res2 = $sql2->fetchrow_array())
						{
							$existing = to_int($res2[0]);
						}
						if(lc(sanitize_alpha($name)) eq "guest" || lc(sanitize_alpha($name)) eq "system" || lc(sanitize_alpha($name)) eq "api" || lc(sanitize_alpha($name)) eq lc($cfg->load('admin_name')))
						{}
						elsif($existing > 0 && $importemail == 1)
						{
							$sql2 = $db->prepare("UPDATE users SET email = ? WHERE name = ?");
							$sql2->execute(sanitize_email($mail), sanitize_alpha($name));
							$updcount += 1;
						}
						elsif($existing == 0 && $importemail == 1)
						{
							$sql2 = $db->prepare("INSERT INTO users VALUES(?, ?, ?, ?, ?, ?);");
							$sql2->execute(sanitize_alpha($name), "*********", sanitize_email($mail), to_int($cfg->load('default_lvl')), now(), "");
							$newcount += 1;
						}
						elsif($existing == 0 && $importemail == 0)
						{
							$sql2 = $db->prepare("INSERT INTO users VALUES(?, ?, ?, ?, ?, ?);");
							$sql2->execute(sanitize_alpha($name), "*********", "", to_int($cfg->load('default_lvl')), now(), "");
							$newcount += 1;
						}
						$rowcount += 1; 
					}
					$mesg = $ldap->unbind; 
					$result = "Success";
					logevent($res[0], "Listed " . $rowcount . " accounts, updated " . $updcount . ", created " . $newcount . ".");
				}
			}
		}
		elsif($res[0] eq 'Computers sync')
		{
			my $aduser = "";
			my $adpass = "";
			my $type = "";
			my $basedn = "";
			my $approval = 0;
			my $searchfilter = "";
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Computers sync';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
				if($res2[1] eq 'type') { $type = $res2[2]; }
				if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
				if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
				if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("api_write"), $res2[2]); }
				if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
			}
			if($basedn eq "")
			{
				logevent($res[0], "Missing Base DN configuration value.");
			}
			else
			{
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent($res[0], "Could not connect to AD server.");
				my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $aduser, password => $adpass);
				$mesg = $ldap->search(base => $basedn, filter => $searchfilter);
				if($mesg->code)
				{
					logevent($res[0], "LDAP: " . $mesg->error . " [" . $mesg->code . "]");
				}
				else
				{
					my $rowcount = 0;
					my $updcount = 0;
					my $newcount = 0;
					foreach my $entry ($mesg->entries)
					{
						my $name = $entry->get_value('sAMAccountName');
						my $serial = $entry->get_value('dNSHostName');
						my $os = $entry->get_value('operatingSystem');
						my $existing = "";
						$sql2 = $db->prepare("SELECT serial FROM items WHERE name = ?;");
						$sql2->execute(sanitize_html($name));
						while(my @res2 = $sql2->fetchrow_array())
						{
							$existing = $res2[0];
						}
						if($existing ne sanitize_html($serial) && $existing ne "")
						{
							$sql2 = $db->prepare("UPDATE items SET serial = ? WHERE name = ?");
							$sql2->execute(sanitize_html($serial), sanitize_html($name));
							$updcount += 1;
						}
						elsif($existing eq "")
						{
							$sql2 = $db->prepare("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
							$sql2->execute(sanitize_html($name), $type, sanitize_html($serial), 0, 0, $approval, 1, "", sanitize_html($os));
							$newcount += 1;
						}
						$rowcount += 1; 
					}
					$mesg = $ldap->unbind; 
					$result = "Success";
					logevent($res[0], "Listed " . $rowcount . " computers, updated " . $updcount . ", created " . $newcount . ".");
				}
			}
		}
		elsif($res[0] eq 'Email to Ticket')
		{
			my $imapserver = "";
			my $imapuser = "";
			my $imappass = "";			
			my $imapport = 143;
			my $imapssl = 0;
			my $productid = 0;
			my $deleteemail = 0;
			my $releaseid = "";
			my $priority = "Normal";
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Email to Ticket';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'imapserver') { $imapserver = $res2[2]; }
				if($res2[1] eq 'imapport') { $imapport = to_int($res2[2]); }
				if($res2[1] eq 'imapssl') { $imapssl = to_int($res2[2]); }
				if($res2[1] eq 'productid') { $productid = to_int($res2[2]); }
				if($res2[1] eq 'deleteemail') { $deleteemail = to_int($res2[2]); }
				if($res2[1] eq 'releaseid') { $releaseid = $res2[2]; }
				if($res2[1] eq 'priority') { $priority = $res2[2]; }
				if($res2[1] eq 'imapuser') { $imapuser = $res2[2]; }
				if($res2[1] eq 'imappass') { $imappass = RC4($cfg->load("api_write"), $res2[2]); }
			}
			if($imapserver eq "")
			{
				logevent($res[0], "Missing server configuration value.");
			}
			else
			{
				my $rowcount = 0;
				my $newcount = 0;
				my $imap = Net::IMAP::Simple->new($imapserver, port => $imapport, use_ssl => $imapssl) or logevent($res[0], "Could not connect to IMAP server.");
				if(!$imap->login($imapuser, $imappass))
				{
					logevent($res[0], "Could not login to IMAP server. " . $imap->errstr)
				}
				else
				{
					my $nm = $imap->select('INBOX');
					for(my $i = 1; $i <= $nm; $i++)
					{
						if(!$imap->seen($i))
						{
							my $es = Email::Simple->new(join '', @{$imap->get($i)});
							my $fromaddr = sanitize_email($es->header('From') =~ /^.*<(.*)>.*/);
							my $from = "System";
							if($fromaddr ne "")
							{
								$sql2 = $db->prepare("SELECT name FROM users WHERE email = ?;");
								$sql2->execute($fromaddr);
								while(my @res2 = $sql2->fetchrow_array()) { $from = $res2[0]; }
							}
							$sql2 = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
							$sql2->execute($productid, $releaseid, $from, "", sanitize_html($es->header('Subject')), sanitize_html($es->body), $priority, "New", "", "", now(), "Never");
							$sql2 = $db->prepare("SELECT last_insert_rowid();");
							$sql2->execute();
							my $rowid = -1;
							while(my @res2 = $sql2->fetchrow_array()) { $rowid = to_int($res2[0]); }
							$sql2 = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
							$sql2->execute($productid);
							while(my @res2 = $sql2->fetchrow_array())
							{
								notify($res2[1], "New ticket created", "A new ticket was created for one of your projects:\n\nUser: " . $from . " <" . $fromaddr . ">\nTitle: " . sanitize_html($es->header('Subject')) . "\nPriority: " . $priority . "\nDescription: " . sanitize_html($es->body));
							}
							my $assignedto = "";
							$sql2 = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
							$sql2->execute($productid);
							while(my @res2 = $sql2->fetchrow_array()) { $assignedto .= $res2[0] . " "; }
							foreach my $assign (split(' ', $assignedto))
							{
								notify($assign, "New ticket created", "A new ticket was created for a project assigned to you:\n\nUser: " . $from . " <" . $fromaddr . ">\nTitle: " . sanitize_html($es->header('Subject')) . "\nPriority: " . $priority . "\nDescription: " . sanitize_html($es->body));
							}
							if($cfg->load('newticket_plugin'))
							{
								my $cmd = $cfg->load('newticket_plugin');
								my $s0 = $productid;
								my $s1 = $releaseid;
								my $s2 = sanitize_html($es->header('Subject'));
								my $s3 = sanitize_html($es->body);
								my $s4 = $rowid;
								my $s5 = $from . " <" . $fromaddr . ">";
								$cmd =~ s/\%product\%/\"$s0\"/g;
								$cmd =~ s/\%release\%/\"$s1\"/g;
								$cmd =~ s/\%title\%/\"$s2\"/g;
								$cmd =~ s/\%description\%/\"$s3\"/g;
								$cmd =~ s/\%ticket\%/\"$s4\"/g;
								$cmd =~ s/\%user\%/\"$s5\"/g;
								$cmd =~ s/\n/ /g;
								$cmd =~ s/\r/ /g;
								system($cmd);
							}
							$newcount += 1;
							if($deleteemail) { $imap->delete($i); }
						}
						$rowcount += 1;
					}
					$imap->quit;
					$result = "Success";
					logevent($res[0], "Listed " . $rowcount . " emails, " . $newcount . " tickets created.");
				}
			}
		}
		# TODO: Go module by module and read config, do stuff
		else { logevent($res[0], "Not implemented."); }
		$sql2 = $db->prepare("UPDATE auto_modules SET lastrun = ?, timestamp = ?, result = ? WHERE name = ?;");
		$sql2->execute(now(), time(), $result, $res[0]);

	}
}
# Finish
$sql = $db->prepare("DELETE FROM auto;");
$sql->execute();
$sql = $db->prepare("INSERT INTO auto VALUES (?, 'Ran " . $runcount . " modules at " . now() . ".');");
$sql->execute(time());
