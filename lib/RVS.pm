# RVS Parent module for RAW / PRO Modules
#
# $Id$
#

package RVS;

use strict;
use File::Basename;
use Data::Dumper;

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

# Return units for a given variable
sub get_units {
	my ($self, $var) = @_;

	# Make sure variables have been loaded
	$self->vars();

	foreach (@{ $self->{vars} }) {
		return $_->{units} if $_->{name} eq $var;
	}

	return undef;	
}

# Return var position for a variable name that matches given re
sub get_re_var_pos {
	my ($self, $re) = @_;

	# Make sure variables have been loaded
	$self->vars();

	my $i = 0;
	foreach (@{ $self->{vars} }) {
		return $i if $_->{name} =~ /$re/i;
		$i++;
	}

	return undef;
}

# Return position for a single exact variable name
sub get_var_pos {
	my ($self, $varname) = @_;

	my @ps = $self->get_vars_pos($varname);
	return $ps[0];
}

# Return list of positions in @vals for each variable given
sub get_vars_pos {
	my ($self, @varnames) = @_;

	# Make sure variables have been loaded
	$self->vars();

	my %var_lookup;
	my $i = 0;
	foreach (@{ $self->{vars} }) {
		$var_lookup{$_->{name}} = $i;
		$i++;
	}

	
	my @ps;
	foreach (@varnames) {
		die basename($0) . ": $self->{name} attach failure, mismatch\n" if !defined($var_lookup{$_});

		push(@ps, $var_lookup{$_});
	}

	return @ps;
}

sub current_record {
	my $self = shift @_;

	die basename($0) . ": Not attached\n" unless $self->{stream};
	
	return $self->{record};
}

1;
__END__
