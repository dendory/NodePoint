package Config::Win32;

use strict;
use Carp;
use Win32API::Registry qw (:ALL);
use vars qw($VERSION);

$VERSION = '1.01';

# Create new instance, assign vendor and app names, create Registry folders if they don't exist
sub new
{
	my $class = shift;
	my ($vendor, $app) = @_;
	if(!$vendor)
	{
		Carp::croak "Config: No vendor name provided.";
	}
	if(!$app)
	{
		$app = "Default";
	}
	RegCreateKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\" . $vendor . "\\" . $app, 0, "", REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, [], my $rh, []) or Carp::croak "Config: Can't access Registry. " . regLastError();
	RegCloseKey($rh);
	my $self = bless({ vendor_name => $vendor, app_name => $app}, $class);
	return $self;
}

# Read key/value pair
sub load
{
	my ($self, $key) = @_;
	my $value;
	if(!$key)
	{
		Carp::croak "Config: No key provided.";
	}	
	RegOpenKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\" . $self->{vendor_name} . "\\" . $self->{app_name}, 0, KEY_ALL_ACCESS, my $rh) or Carp::croak "Config: Can't access Registry. " . regLastError();
	RegQueryValueEx($rh, $key, [], my $type, $value, [] ) or $value = "";
	RegCloseKey($rh);
	if($value eq "NULL") { $value = ""; }
	return $value;
}

# Store key/value pair
sub save
{
	my ($self, $key, $value) = @_;
	if(!$key)
	{
		Carp::croak "Config: No key provided.";
	}	
	if(!$value)
	{
		$value = "NULL";
	}	
	RegOpenKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\" . $self->{vendor_name} . "\\" . $self->{app_name}, 0, KEY_ALL_ACCESS, my $rh) or Carp::croak "Config: Can't access Registry. " . regLastError();
	RegSetValueEx($rh, $key, 0, REG_SZ, $value, 0) or Carp::croak "Config: Can't save value for key " . $key . ". " . regLastError();
	RegCloseKey($rh);
	return 1;
}

# Read or set the application name
sub app
{
	my $self = shift;
	if(@_)
	{
		$self->{"app_name"} = shift;
		RegCreateKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\" . $self->{vendor_name}  . "\\" . $self->{app_name}, 0, "", REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, [], my $rh, []) or Carp::croak "Config: Can't access Registry. " . regLastError();
		RegCloseKey($rh);
	}
	return $self->{"app_name"};
}

# Read or set the vendor name
sub vendor
{
	my $self = shift;
	if(@_) { $self->{"vendor_name"} = shift; }
	return $self->{"vendor_name"};
}

sub type
{
	return "Registry";
}

sub sep
{
	return "\\";
}

1;

__END__

=pod

=head1 NAME

Config::Win32 - Load and save configuration values on Windows

=head1 SYNOPSIS

	 use Config::Win32;

	 my $cfg = Config::Win32->new("Vendor name", "Application name");

	 $cfg->save("key", "value");

	 print $cfg->load("key");

=head1 DESCRIPTION

This module is a simple way to save and load configuration options in the
Windows registry. While other Config modules exist, they mostly rely on
flat files, which is the norm on Unix systems but not as useful on Windows.

The registry provides an easy place to store values and this module takes
advantage of that. It uses the Win32API::Registry low-level API to access
the values.

=head1 ATTRIBUTES

=item $cfg = Config::Win32->new($vendor_name, $application_name)

Makes a configuration variable, and creates keys in the registry for the
vendor and application names under HKEY_LOCAL_USER/Software.

=item $cfg->app

=item $cfg->app($application_name)

Returns the current application name, or switches to a new application
name, and creates the proper keys in the registry.

=item $cfg->save($key, $value)

Saves a key/value pair to the registry under the current vendor and
application name. All values are assumed to be strings.

=item $cfg->load($key)

Returns the current value for $key.

=head1 COPYRIGHT

(C) 2014 Patrick Lambert - http://dendory.net

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
