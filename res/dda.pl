#!/usr/bin/perl
#
# NodePoint Direct Database Access - (C) 2015 Patrick Lambert - http://nodepoint.ca
#

use strict;
use DBI;

print "Enter the full path to your NodePoint database file (ENTER to exit): ";
my $dbname = <STDIN>;
chomp $dbname;
exit 0 if ($dbname eq "");
print "Accessing $dbname...\n\n";
my $db = DBI->connect("dbi:SQLite:dbname=" . $dbname, '', '', { RaiseError => 1, PrintError => 1 }) or do { exit 1; };
my @tables = $db->tables();
foreach my $table (@tables)
{
	print "Table found: $table\n";
}
