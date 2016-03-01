#!/usr/bin/perl
#
# NodePoint - (C) 2014-2016 Patrick Lambert - http://nodepoint.ca
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
use Time::Piece;
use Mail::RFC822::Address qw(valid);
use File::Basename qw(dirname);
use File::Copy;
use Archive::Zip;
use Net::LDAP;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
use Net::SMTP;
use Crypt::RC4;
use Net::IMAP::Simple;
use Email::Simple;
use Email::MIME;
use Date::Parse;
use MIME::Base64;
use LWP::UserAgent;
use SOAP::Lite;
use utf8;

my ($cfg, $db, $sql, $sql2, $soap_user, $soap_pass);
my $m = localtime->strftime('%m');
my $y = localtime->strftime('%Y');
my $d = localtime->strftime('%d');

# SOAP creds
sub SOAP::Transport::HTTP::Client::get_basic_credentials {
    return $soap_user => $soap_pass;
}

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
				if($cfg->load('smtp_user') && $cfg->load('smtp_pass')) { $smtp->auth($cfg->load('smtp_user'), RC4($cfg->load("api_write"),  decode_base64($cfg->load('smtp_pass')))); }
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

$sql = $db->prepare("SELECT * FROM auto_log WHERE 0 = 1;") or quit(1);
$sql = $db->prepare("SELECT * FROM auto_modules WHERE 0 = 1;") or quit(1);
$sql = $db->prepare("SELECT * FROM auto WHERE 0 = 1;") or quit(1);
$sql = $db->prepare("SELECT * FROM auto_config WHERE 0 = 1;") or quit(1);

# Main loop
$sql = $db->prepare("DELETE FROM auto;");
$sql->execute();
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
		elsif($res[0] eq 'Update MOTD')
		{
			my $filename = "";
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Update MOTD';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'filename') { $filename = $res2[2]; }
			}
			if($filename eq "")
			{
				logevent($res[0], "Missing filename configuration value.");
			}
			else
			{
				my $motd = "";
				if(open(my $F, $filename))
				{
					$motd = <$F>;
					close($F);
					$cfg->save("motd", sanitize_html($motd));
					$result = "Success";
					logevent($res[0], "Updated motd.");
				}
				else { logevent($res[0], "Error reading file."); }
			}
		}
		elsif($res[0] eq 'Users sync')
		{
			my $aduser = "";
			my $adpass = "";
			my $basedn = "";
			my $searchfilter = "";
			my $importemail = 0;
			my $page = Net::LDAP::Control::Paged->new(size => 999);
			my $cookie;
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Users sync';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
				if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
				if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
				if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("api_write"), decode_base64($res2[2])); }
				if($res2[1] eq 'importemail') { $importemail = to_int($res2[2]); }
			}
			if($basedn eq "")
			{
				logevent($res[0], "Missing Base DN configuration value.");
			}
			else
			{
				my $rowcount = 0;
				my $updcount = 0;
				my $newcount = 0;
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent($res[0], "Could not connect to AD server.");
				if($ldap)
				{
					my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $aduser, password => $adpass);
					$sql2 = $db->prepare("BEGIN");
					$sql2->execute();
					while(1) 
					{
						$mesg = $ldap->search(base => $basedn, filter => $searchfilter, control => [$page]);
						if($mesg->code)
						{
							logevent($res[0], "LDAP: " . $mesg->error . " [" . $mesg->code . "]");
						}
						else
						{
							while (my $entry = $mesg->pop_entry())
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
						}
						my ($resp) = $mesg->control(LDAP_CONTROL_PAGED) or last;
						$cookie = $resp->cookie or last;
						$page->cookie($cookie);
					}
					$sql2 = $db->prepare("END");
					$sql2->execute();
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
			my $page = Net::LDAP::Control::Paged->new(size => 999);
			my $cookie;
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Computers sync';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'basedn') { $basedn = $res2[2]; }
				if($res2[1] eq 'type') { $type = $res2[2]; }
				if($res2[1] eq 'searchfilter') { $searchfilter = $res2[2]; }
				if($res2[1] eq 'aduser') { $aduser = $res2[2]; }
				if($res2[1] eq 'adpass') { $adpass = RC4($cfg->load("api_write"), decode_base64($res2[2])); }
				if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
			}
			if($basedn eq "")
			{
				logevent($res[0], "Missing Base DN configuration value.");
			}
			else
			{
				my $rowcount = 0;
				my $updcount = 0;
				my $newcount = 0;
				my $ldap = Net::LDAP->new($cfg->load("ad_server")) or logevent($res[0], "Could not connect to AD server.");
				if($ldap)
				{
					my $mesg = $ldap->bind($cfg->load("ad_domain") . "\\" . $aduser, password => $adpass);
					$sql2 = $db->prepare("BEGIN");
					$sql2->execute();
					while(1) 
					{

						$mesg = $ldap->search(base => $basedn, filter => $searchfilter, control => [$page]);
						if($mesg->code)
						{
							logevent($res[0], "LDAP: " . $mesg->error . " [" . $mesg->code . "]");
						}
						else
						{
							while (my $entry = $mesg->pop_entry())
							{
								my $name = $entry->get_value('sAMAccountName');
								my $serial = $entry->get_value('dNSHostName');
								my $os = $entry->get_value('operatingSystem');
								my $existing = "";
								if($serial ne "" && $name ne "")
								{
									$sql2 = $db->prepare("SELECT name FROM items WHERE serial = ?;");
									$sql2->execute(sanitize_html($serial));
									while(my @res2 = $sql2->fetchrow_array()) { $existing = $res2[0]; }
									if($existing eq "")
									{
										$sql2 = $db->prepare("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
										$sql2->execute(sanitize_html($name), $type, sanitize_html($serial), 0, 0, $approval, 1, "", sanitize_html($os));
										$newcount += 1;
									}
									elsif($existing ne sanitize_html($name))
									{
										$sql2 = $db->prepare("UPDATE items SET name = ? WHERE serial = ?");
										$sql2->execute(sanitize_html($name), sanitize_html($serial));
										$updcount += 1;
									}
								}
								$rowcount += 1; 
							}
						}
						my ($resp) = $mesg->control(LDAP_CONTROL_PAGED) or last;
						$cookie = $resp->cookie or last;
						$page->cookie($cookie);
					}
					$sql2 = $db->prepare("END");
					$sql2->execute();
					$mesg = $ldap->unbind; 
					$result = "Success";
					logevent($res[0], "Listed " . $rowcount . " computers, updated " . $updcount . ", created " . $newcount . ".");
				}
			}
		}
		elsif($res[0] eq 'ServiceNow CMDB')
		{
			my $type = "";
			my $cmdburl = "";
			my $cmdbtable = "";
			my $mapname = "";
			my $mapserial = "";
			my $mapinfo = "";
			my $approval = 0;
			my $cmdbuser = "";
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
				if($res2[1] eq 'cmdbuser') { $soap_user = $res2[2]; }
				if($res2[1] eq 'cmdbpass') { $soap_pass = RC4($cfg->load("api_write"), decode_base64($res2[2])); }
				if($res2[1] eq 'approval') { $approval = to_int($res2[2]); }
			}
			if($cmdburl eq "" || $cmdbtable eq "")
			{
				logevent($res[0], "Missing ServiceNow URL or CMDB table configuration value.");
			}
			else
			{
				my $rowcount = 0;
				my $updcount = 0;
				my $crtcount = 0;
				my $url = $cmdburl . "/" . $cmdbtable . ".do?SOAP";
				my $som;
				my $soap = SOAP::Lite->proxy($url);
				eval
				{
					my $method = SOAP::Data->name("getRecords")->attr({xmlns => "http://www.service-now.com/"});
					my @params = (SOAP::Data->name());
					$som = $soap->call($method => @params);
				} or logevent($res[0], "Could not connect to SOAP endpoint: " . $url . " [" . $soap->transport->status . "]");
				if($som)
				{
					$sql2 = $db->prepare("BEGIN");
					$sql2->execute();
					my @data;
					eval { @data = @{$som->body->{getRecordsResponse}->{getRecordsResult}} } or logevent($res[0], "Invalid or empty response from server.");
					foreach my $rec (@data)
					{
						$rowcount += 1;
						if($rec->{$mapserial} ne "" && $rec->{$mapname} ne "")
						{
							$sql2 = $db->prepare("SELECT name FROM items WHERE serial = ?;");
							$sql2->execute(sanitize_html($rec->{$mapserial}));
							my $existing = "";
							while(my @res2 = $sql2->fetchrow_array()) { $existing = $res2[0]; }
							if($existing eq "")
							{
								$sql2 = $db->prepare("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
								$sql2->execute(sanitize_html($rec->{$mapname}), sanitize_alpha($type), sanitize_html($rec->{$mapserial}), 0, 0, $approval, 1, "", sanitize_html($rec->{$mapinfo}));
								$crtcount += 1;
							}
							elsif($existing ne sanitize_html($rec->{$mapname}))
							{
								$sql2 = $db->prepare("UPDATE items SET name = ? WHERE serial = ?");
								$sql2->execute(sanitize_html($rec->{$mapname}), sanitize_html($rec->{$mapserial}));
								$updcount += 1;
							}
						}
					}
					$sql2 = $db->prepare("END");
					$sql2->execute();
					$result = "Success";
					logevent($res[0], "Listed " . $rowcount . " items, updated " . $updcount . ", created " . $crtcount . ".");
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
				if($res2[1] eq 'imappass') { $imappass = RC4($cfg->load("api_write"), decode_base64($res2[2])); }
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
							if($fromaddr eq "") { $fromaddr = sanitize_email($es->header('From')); }
							my $sentfrom = "\n\nSent by email.";
							my $from = "System";
							if($fromaddr ne "")
							{
								$sql2 = $db->prepare("SELECT name FROM users WHERE email = ?;");
								$sql2->execute($fromaddr);
								while(my @res2 = $sql2->fetchrow_array()) { $from = $res2[0]; }
							}
							if($from eq "System") { $sentfrom = "\n\nSent by email from: " . $fromaddr; }
							my $body = $es->body;
							my $parts = Email::MIME->new($es->body);
							for my $part ($parts->parts) 
							{
								if(!$part->content_type)
								{
									$body = $part->body;
								}
								elsif($part->content_type =~ m!text/plain! or lc($part->content_type) eq 'text')
								{
									for my $subpart ($part->parts) { $body = $subpart->body; }
								}
							}
							$sql2 = $db->prepare("INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
							$sql2->execute($productid, $releaseid, $from, "", sanitize_html($es->header('Subject')), sanitize_html($body)  . $sentfrom, $priority, "New", "", "", now(), "Never");
							$sql2 = $db->prepare("SELECT last_insert_rowid();");
							$sql2->execute();
							my $rowid = -1;
							while(my @res2 = $sql2->fetchrow_array()) { $rowid = to_int($res2[0]); }
							$sql2 = $db->prepare("SELECT * FROM releases WHERE productid = ?;");
							$sql2->execute($productid);
							while(my @res2 = $sql2->fetchrow_array())
							{
								notify($res2[1], "New ticket created", "A new ticket was created for one of your projects:\n\nUser: " . $from . "\nTitle: " . sanitize_html($es->header('Subject')) . "\nPriority: " . $priority . "\nDescription: " . sanitize_html($body));
							}
							my $assignedto = "";
							$sql2 = $db->prepare("SELECT user FROM autoassign WHERE productid = ?;");
							$sql2->execute($productid);
							while(my @res2 = $sql2->fetchrow_array()) { $assignedto .= $res2[0] . " "; }
							foreach my $assign (split(' ', $assignedto))
							{
								notify($assign, "New ticket created", "A new ticket was created for a project assigned to you:\n\nUser: " . $from . "\nTitle: " . sanitize_html($es->header('Subject')) . "\nPriority: " . $priority . "\nDescription: " . sanitize_html($body));
							}
							if($cfg->load('newticket_plugin'))
							{
								my $cmd = $cfg->load('newticket_plugin');
								my $s0 = $productid;
								my $s1 = $releaseid;
								my $s2 = sanitize_html($es->header('Subject'));
								my $s3 = sanitize_html($body);
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
		elsif($res[0] eq 'Ticket expiration')
		{
			my $numdays = 0;
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
			if($numdays == 0)
			{
				logevent($res[0], "Invalid days amount.");
			}
			else
			{
				my $ticketcount = 0;
				my $actcount = 0;
				$sql2 = $db->prepare("SELECT ROWID,title,assignedto,modified,created FROM tickets WHERE status != 'Closed';");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					$ticketcount += 1;
					my $tickettime = $res2[3];
					if($tickettime eq "Never") { $tickettime = $res2[4]; }
					if((str2time($tickettime) + (86400 * $numdays)) < time())
					{
						$actcount += 1;
						if($closeticket == 1)
						{
							my $sql3 = $db->prepare("UPDATE tickets SET status = 'Closed', resolution = 'Closed by automation engine.', modified = ? WHERE ROWID = ?;");
							$sql3->execute(now(), $res2[0]);
						}
						if($remindticket == 1)
						{
							foreach my $assign (split(' ', $res2[2]))
							{
								notify($assign, "Ticket (" . $res2[0] . ") requires your attention", "Ticket " . $res2[1] . " assigned to you has reached its expiration threshold and requires your attention.");
							}
						}
					}
				}
				$result = "Success";
				logevent($res[0], "Found " . $ticketcount . " active tickets, acted on " . $actcount . ".");
			}
		}
		elsif($res[0] eq 'File expiration')
		{
			my $numdays = 0;
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'File expiration';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'numdays') { $numdays = to_int($res2[2]); }
			}
			if($numdays == 0)
			{
				logevent($res[0], "Invalid days amount.");
			}
			else
			{
				my $filecount = 0;
				my $delcount = 0;
				$sql2 = $db->prepare("SELECT ROWID,* FROM files;");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					$filecount += 1;
					my $filetime = $res2[4];
					if((str2time($filetime) + (86400 * $numdays)) < time())
					{
						$delcount += 1;
						open(my $OUTFILE, ">", $cfg->load('upload_folder') . $cfg->sep . $res2[2]);
						print $OUTFILE "This file is no longer available.";
						close($OUTFILE);
						my $sql3 = $db->prepare("DELETE FROM files WHERE file = ?;");
						$sql3->execute($res2[2]);
					}
				}
				$result = "Success";
				logevent($res[0], "Found " . $filecount . " files, removed " . $delcount . ".");
			}
		}
		elsif($res[0] eq 'Reminder notifications')
		{
			my $remindtickets = 0;
			my $remindtasks = 0;
			my $reminditems = 0;
			my $sql2 = $db->prepare("SELECT * FROM auto_config WHERE module = 'Reminder notifications';");
			$sql2->execute();
			while(my @res2 = $sql2->fetchrow_array())
			{
				if($res2[1] eq 'remindtickets') { $remindtickets = to_int($res2[2]); }
				if($res2[1] eq 'remindtasks') { $remindtasks = to_int($res2[2]); }
				if($res2[1] eq 'reminditems') { $reminditems = to_int($res2[2]); }
			}
			my $rowcount = 0;
			if($remindtickets == 1)
			{
				$sql2 = $db->prepare("SELECT * FROM escalate;");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					my $sql3 = $db->prepare("SELECT title FROM tickets WHERE ROWID = ?;");
					$sql3->execute(to_int($res2[0]));
					while(my @res3 = $sql3->fetchrow_array())
					{
						$rowcount += 1;
						notify($res2[1], "Ticket (" . $res2[0] . ") requires your attention", "The following ticket requires your attention:\n\n" . $res2[0] . " - " . $res3[0])
					}
				}
			}
			if($remindtasks == 1)
			{
				$sql2 = $db->prepare("SELECT ROWID,name,user,due FROM steps WHERE completion < 100;");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					my @dueby = split(/\//, $res2[3]);
					if($dueby[2] < $y || ($dueby[2] == $y && $dueby[0] < $m) || ($dueby[2] == $y && $dueby[0] == $m && $dueby[1] < $d))
					{
						$rowcount += 1;
						notify($res2[2], "Task (" . $res2[0] . ") is overdue", "The following task is overdue:\n\nTask: " . $res2[1] . "\nDue on: " . $res2[3])
					}
				}
			}
			if($reminditems == 1)
			{
				$sql2 = $db->prepare("SELECT * FROM item_expiration;");
				$sql2->execute();
				while(my @res2 = $sql2->fetchrow_array())
				{
					my $sql3 = $db->prepare("SELECT name,user FROM items WHERE status = 3 AND ROWID = ?;");
					$sql3->execute(to_int($res2[0]));
					while(my @res3 = $sql3->fetchrow_array())
					{
						my @dueby = split(/\//, $res2[1]);
						if($dueby[2] < $y || ($dueby[2] == $y && $dueby[0] < $m) || ($dueby[2] == $y && $dueby[0] == $m && $dueby[1] < $d))
						{
							$rowcount += 1;
							notify($res3[1], "Item (" . $res2[0] . ") has expired", "The following checked out item is expired:\n\nItem: " . $res3[0] . "\nExpiration date: " . $res2[1])
						}
					}
				}
			}
			$result = "Success";
			logevent($res[0], "Sent " . $rowcount . " notifications.");
		}
		else { logevent($res[0], "Not implemented."); }
		$sql2 = $db->prepare("UPDATE auto_modules SET lastrun = ?, timestamp = ?, result = ? WHERE name = ?;");
		$sql2->execute(now(), time(), $result, $res[0]);
	}
}
# Finish
$sql = $db->prepare("INSERT INTO auto VALUES (?, 'Ran " . $runcount . " modules at " . now() . ".');");
$sql->execute(time());
