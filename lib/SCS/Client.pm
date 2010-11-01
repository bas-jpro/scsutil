# SCS::Client Module
# 
# $Id: Client.pm 597 2009-12-07 22:58:17Z jpro $
#

package SCS::Client;
@ISA = qw(SCS);

use strict;
use LWP::RobotUA;
use JSON::XS;

my $UA      = 'scs::client/$Rev: 597 $';
my $ADDR    = 'jpro@bas.ac.uk';
my $SCS_URL = 'http://scs.jcr.nerc-bas.ac.uk/scs/json/';

my $SECS_PER_DAY = 60 * 60 * 24;

sub new {
	my $class = shift @_;

	my $self = $class->SUPER::new();
	$self->{url} = $ENV{SCS_URL} || $SCS_URL;
	$self->{ua} = LWP::UserAgent->new(agent => $UA, from => $ADDR);

	$self->{tstamp} = 0;

	bless $self, $class;

	return $self;
}

sub _get {
	my ($self, @args) = @_;
	my $path = (scalar(@args) ? join("/", @args) : '');
	
	my $url = $self->{url} . $path;

	my $response = $self->{ua}->get($url);
	if ($response->is_success) {
		return decode_json $response->content;
	} else {
		die "Getting [$url] failed: " . $response->status_line . "\n";
	}
}

sub attach {
	my ($self, $stream) = @_;

	$self->{name} = $stream;
	my $rec = $self->_get($stream);
	
	if ($rec->{error}) {
		die $rec->{error} . "\n";
	}

	return 1;
}

sub detach {
	my $self = shift;

	$self->{name} = undef;
	$self->{vars} = undef;
}

sub list_streams {
	my $self = shift;

	my $res = $self->_get();
	return @$res;
}

sub last_record {
	my $self = shift;

	die basename($0) . ": Not attached\n" unless $self->{name};

	$self->_convert($self->_get($self->{name}));
	return $self->{record};
}

# Current will go from last record if called before find_time
# vs other SCS:: modules which go from start
sub next_record {
	my $self = shift;

	my $tstamp = ($self->{record} && $self->{record}->{timestamp} ? $self->{record}->{timestamp} : 0) + 1;
	
	if ($self->{tstamp} < $tstamp) {
		return $self->find_time($tstamp);
	} 

	return undef;
}

sub find_time {
	my ($self, $tstamp) = @_;

	die basename($0) . ": Not attached\n" unless $self->{name};

	$self->_convert($self->_get($self->{name}, $tstamp));
	return $self->{record};
}

sub vars {
	my $self = shift;

	die basename($0) . ": Not attached\n" unless $self->{name};
	return $self->{vars} if $self->{vars};

	my $rec = $self->_get($self->{name});

	$self->{vars} = $rec->{vars};

	return $self->{vars};
}

# Convert web services style record to SCS system
sub _convert {
	my ($self, $json_rec) = @_;

	if (!$json_rec || (!defined($json_rec->{timestamp}))) {
		$self->{record} = { year => undef, dayfract => undef, timestamp => undef, vals => undef };
		return;
	}

	$self->{record} = { timestamp => $json_rec->{timestamp}, vals => [] };
	foreach my $v (@{ $json_rec->{vars} }) {
		push(@{ $self->{record}->{vals} }, $v->{value});
	}
   
	my $secs = 0;
	($secs, $self->{record}->{year}, $self->{record}->{dayfract}) = (gmtime($json_rec->{timestamp}))[0, 5, 7];
	$self->{record}->{dayfract} += $secs / $SECS_PER_DAY;

	$self->{tstamp} = $self->{record}->{timestamp};
}

1;
__END__
