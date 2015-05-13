# RVS Parent module for RAW / PRO Modules
#
# $Id$
#

package RVS;

use strict;
use File::Basename;

my @PARAMS = qw(path debug);

sub new {
	my ($class, $params) = @_;

	my $self = bless {
		raw     => 0,
		path    => '',
		debug   => 0,
		name    => 0,
		stream  => 0,
		vars    => undef,
		record  => {
			timestamp => undef,
			vals      => undef,
		}, 
		NOTWRIT => 0,
		TEST    => 10,
		REJECT  => 20,
		SUSPECT => 30,
		RESTART => 35,
		INTERP  => 40,
		UNCORR  => 45,
		GOOD    => 50,
		CORRECT => 55,
		ACCEPT  => 60,		
	}, $class;

	# Load from paramaters if supplied
	if ($params) {
		foreach my $p (@PARAMS) {
			$self->{$p} = $params->{$p} if $params->{$p};
		}
	}

	if (!$self->{path}) {
		$self->{path} = $ENV{DARAWBASE} || '/rvs/raw_data';
	}

	return $self;
}

sub debug {
	my ($self, $debug) = @_;

	if (defined($debug)) {
		$self->{debug} = $debug;
	}

	return $self->{debug};
}

sub path {
	my ($self, $path) = @_;
	
	if (defined($path)) {
		$self->{path} = $path;
	}

	return $self->{path};
}

sub log {
	my ($self, @msgs) = @_;
	return unless $self->{debug};

	print STDERR "$0: [" . scalar(localtime) . "] " . join(' ', @msgs) . "\n";
}

sub vars {
	my $self = shift;

	die basename($0) . ": Not attached\n" unless $self->{stream};

	return $self->{vars};
}

1;
__END__
