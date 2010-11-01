# SCS Parent module for Raw / Compress SCS Modules
#
# $Id$
#

package SCS;

use strict;
use File::Basename;

sub new {
	my $class = shift @_;

	my $scs = bless {
		path   => '',
		delim  => ',',
		name   => undef,
		stream => undef,
		record => {
			year      => undef,
			dayfract  => undef,
			timestamp => undef,
			vals      => undef,
		},
		vars    => undef,
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

	return $scs;
}

sub change_path {
	my ($self, $path) = @_;
	
	$self->{path} = $path;
}

sub current_record {
	my $self = shift @_;

	die basename($0) . ": Not attached\n" unless $self->{stream};
	
	return $self->{record};
}

sub check_status {
	my ($self, $status) = @_;

	$_ = $status;

	return $self->{NOTWRIT} if /^notwrit$/i;
	return $self->{TEST}    if /^test$/i;
	return $self->{REJECT}  if /^reject$/i;
	return $self->{SUSPECT} if /^suspect$/i;
	return $self->{RESTART} if /^restart$/i;
	return $self->{INTERP}  if /^interp$/i;
	return $self->{UNCORR}  if /^uncorr$/i;
	return $self->{GOOD}    if /^good$/i;
	return $self->{CORRECT} if /^correct$/i;
	return $self->{ACCEPT}  if /^accept$/i;

	die basename($0) . ": bad status $_\n";
}

sub get_instruments {
	my $self = shift;
	
	my @streams = $self->list_streams();
	my @instruments = ();
	my $namelen = 0;
	
	my $is = { };
	# Need to sort here to get substreams in order as well as instruments
	foreach my $s (sort @streams) {
		my ($inst, $str) = split('-', $s->{name}, 2);

		# Find longest name
		$namelen = length($inst) if length($inst) > $namelen;
		
		if ($is->{$inst}) {
			push(@{ $is->{$inst}->{streams} }, { name => $str, stream => $s->{name}, time => $s->{time} });
		} else {
			$is->{$inst} = { name => $inst, streams => [ { name => ($str || $inst), stream => $s->{name}, time => $s->{time} } ] };
		}
	}
	
	foreach my $i (sort keys %$is) {
		push(@instruments, $is->{$i});
	}
	
	return ($namelen, @instruments);
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
		die basename($0) . ": $self->{name} attach failure, mismatch\n" if
			!defined($var_lookup{$_});

		push(@ps, $var_lookup{$_});
	}

	return @ps;
}

1;
__END__
