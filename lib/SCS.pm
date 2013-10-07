# SCS Parent module for Raw / Compress SCS Modules
#
# $Id$
#

package SCS;

use strict;
use File::Basename;

my @PARAMS = qw(cruises_dir path delim debug multi);

sub new {
	my ($class, $params) = @_;

	my $scs = bless {
		multi       => 0,
		debug       => 0,
		cruises_dir => undef,
		path        => '',
		delim       => ',',
		name        => undef,
		stream      => undef,
		data_prefix => undef,
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

	# Load from paramaters if supplied
	if ($params) {
		foreach my $p (@PARAMS) {
			$scs->{$p} = $params->{$p} if $params->{$p};
		}
	}

	# If cruises_dir set path to first cruise
	if ($scs->{cruises_dir} && !$scs->{path}) {
		$scs->next_cruise();
	}

	return $scs;
}

sub log {
	my ($self, @msgs) = @_;
	return unless $self->{debug};

	print STDERR "$0: [" . scalar(localtime) . "] " . join(' ', @msgs) . "\n";
}

sub next_cruise {
	my $self = shift;
	return unless $self->{cruises_dir};

	# Assume cruises are alphanumerically sortable (e.g leg nos)
	if ($self->{path}) {
		my $id = (reverse(split('/', $self->{path})))[2];
		$self->log("Current cruise id $id");

		my $cs = $self->_get_cruise_dirs();
		my ($i, $num_cs) = (0, scalar(@$cs));
		
		while (($i < $num_cs) && ($cs->[$i] ne $id)) {
			$i++;
		}

		if ($cs->[$i] eq $id) {
			if ($i < $num_cs) {
				$self->log("Next cruise is", $cs->[$i+1]);

				$self->{path} = $self->{cruises_dir} . '/' . $cs->[$i+1] . '/scs/Compress';
			} else {
				$self->{path} = undef;
				$self->log("No more cruises");
			}
		} else {
			$self->{path} = undef;
			$self->log("Couldn't find current cruise");
		}
	} else {
		$self->log("looking for first cruise");
		my $dir = shift @{$self->_get_cruise_dirs()};
		$self->log("first cruise is $dir");

		$self->{path} = "$dir/scs/Compress";
	}

	# Reattach stream
	if ($self->{path}) {
		$self->_reattach();
	}

	return $self->{path};
}

# Cruises are sorted alphanumerically
sub _get_cruise_dirs {
	my $self = shift;
	return unless $self->{cruises_dir};

	opendir(my $dh, $self->{cruises_dir}) || die "Can't open directory [$self->{cruises_dir}]\n";
	my @cs = sort grep { -d "$self->{cruises_dir}/$_/scs" } readdir($dh);
	closedir($dh);

	$self->log("Read", scalar(@cs), "dirs");

	return \@cs;
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
		die basename($0) . ": $self->{name} attach failure, mismatch\n" if
			!defined($var_lookup{$_});

		push(@ps, $var_lookup{$_});
	}

	return @ps;
}

1;
__END__
