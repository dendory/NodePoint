package Config::Linux;

use strict;
use Carp;
use Config::Simple;
use vars qw($VERSION);

$VERSION = '1.0';

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
	my $filename = "../nodepoint.cfg";
	if(!-e $filename)
	{
		open(F, ">" . $filename) or Carp::croak "Config: Could create configuration file " . $filename;
		print F "dummy value\n";
		close(F);
	}
	my $config = new Config::Simple($filename) or Carp::croak "Config: Could not access " . $filename;
	my $self = bless({ cfg => $config}, $class);
	return $self;
}

# Read key/value pair
sub load
{
	my ($self, $key) = @_;
	if(!$key)
	{
		Carp::croak "Config: No key provided.";
	}	
	my $value = $self->{cfg}->param($key);
	if(!$value || $value eq "NULL") { $value = ""; }
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
	if(!$value || $value eq "")
	{
		$value = "NULL";
	}
	$self->{cfg}->param($key, $value);
	$self->{cfg}->save();
	return 1;
}

sub type
{
	return "configuration file";
}

sub sep
{
	return "/";
}

1;

__END__
