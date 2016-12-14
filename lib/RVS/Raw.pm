# RVS::Raw Module to read RAW RVS Files
#
# $Id$
#

package RVS::Raw;
@ISA = qw(RVS);

use strict;
use Carp;

use File::Basename;
use File::Map qw(map_file unmap);

use constant {
	OHEAD_SIZE      => 512,
	NHEAD_SIZE      => 6144,
	MAGIC_OFST      => 14,
	DAMAGIC         => 0x5256530A, # Old RVS data file format
	PSVMAGIC        => 0x502A5256, # File stores data by variable
	PSDMAGIC        => 0x502A5244, # File stores data by cycle
	VNAMESIZ        => 8,
	COMNT_NUM       => 12, # Number of comment cards
	COMNT_SIZ       => 72, # Size of comment card
	MAXVARS         => 128,
	PACSIZE         => 6, # Size of packed data structure
	NHEAD_NAME_OFST => 0,
	NHEAD_VERS_OFST => 8,
	NHEAD_WRIT_OFST => 10,
	NHEAD_RAW__OFST => 11,
	NHEAD_PIPE_OFST => 12,
	NHEAD_ARCH_OFST => 13,
	NHEAD_MAG2_OFST => 14,
	NHEAD_CYCL_OFST => 18,
	NHEAD_MAX__OFST => 20,
	NHEAD_PRFL_OFST => 24,
	NHEAD_PSFL_OFST => 32,
	NHEAD_VARS_OFST => 40,
	NHEAD_NREC_OFST => 44,
	NHEAD_NROW_OFST => 48,
	NHEAD_PLAN_OFST => 52,
	NHEAD_BCEN_OFST => 56,
	NHEAD_BDAT_OFST => 60,
	NHEAD_BTIM_OFST => 64,
	NHEAD_PNAM_OFST => 68,
	NHEAD_PTYP_OFST => 80,
	NHEAD_PNUM_OFST => 88,
	NHEAD_INST_OFST => 96,
	NHEAD_FREQ_OFST => 108,
	NHEAD_IVNM_OFST => 112,
	NHEAD_IVUN_OFST => 120,
	NHEAD_LAT__OFST => 128,
	NHEAD_LON__OFST => 136,
	NHEAD_IDEP_OFST => 144,
	NHEAD_WDEP_OFST => 152,
	NHEAD_CMNT_OFST => 160,
};

use constant NHEAD_VNAM_OFST => (NHEAD_CMNT_OFST + (COMNT_NUM * COMNT_SIZ));
use constant NHEAD_UNAM_OFST => (NHEAD_VNAM_OFST + (MAXVARS * VNAMESIZ));

sub new {
	my $class = shift;

	my $self = $class->SUPER::new();
	$self->{pos}    = 0;
	$self->{len}    = 0;
	$self->{stream} = undef;
	$self->{recnum} = undef;
	$self->{header} = {
		magic    => undef,
		nvars    => undef,
		max_recs => undef,
	};

	return $self;
}

# Convert a given 4 byte position into a signed 32 bit value
sub _L32VAL {
	my ($self, $pos, $unsigned) = @_;
	$pos = $self->{pos} unless defined($pos);

	my $val = unpack("N", substr($self->{stream}, $pos, 4)); 
	
	return $val if $unsigned;

	# Convert to signed
	if ($val & 0x80000000) {
		$val = -($val & 0x7FFFFFFF + 1);
	}

	return $val;
}

# Convert a given 4 byte position into an unsigned 32 bit value 
sub _U32VAL {
	my ($self, $pos) = @_;
	return $self->_L32VAL($pos, 1);
}

# Convert a given 5 byte position into a floating point value
# Very small values go to 0
my $EPSILON = 5.0e-323;

sub _dblConv {
	my ($self, $pos) = @_;
	$pos = $self->{pos} unless defined($pos);

	my @bs = split('', substr($self->{stream}, $pos, 5));
	my $dbl_str = '000' . $bs[4] . $bs[3] . $bs[2] . $bs[1] . $bs[0];

	my $d = sprintf("%0.5f", unpack("d", $dbl_str));

	if (abs($d) < $EPSILON) {
		$d = 0;
	}

	return $d;
}

sub attach {
	my ($self, $stream) = @_;

    die basename($0) . ": Already attached to " . $self->{name} . "\n" if $self->{stream};
	die basename($0) . ": Failed to attach - no stream\n" unless $stream;

	my $fname = $self->{path} . "/$stream";
	die basename($0) . ": Failed to attach to $stream [$fname]\n" unless -e $fname;

	$self->{name} = $stream;
	map_file($self->{stream}, $fname, '<');
	$self->{pos} = 0;
	$self->{len} = -s $fname;

	if ($self->{len} < NHEAD_SIZE) {
		die basename($0) . ": Corrupt RVS file - too small\n";
	}

	# Check magic 
	$self->{header}->{magic} = $self->_U32VAL(MAGIC_OFST);

	if ($self->{header}->{magic} == DAMAGIC) {
		die basename($0) . ": Old style RVS file found - not supported\n";
	}

	if (($self->{header}->{magic} != PSVMAGIC) && ($self->{header}->{magic} != PSDMAGIC)) {
		die basename($0) . ": Non RVS file found\n";
	}
	
	$self->{header}->{nvars}    = $self->_L32VAL(NHEAD_VARS_OFST);
	$self->{header}->{max_recs} = $self->_L32VAL(NHEAD_NREC_OFST);
	
	$self->{vars} = [];

	for (my $i=0; $i<$self->{header}->{nvars}; $i++) {
		push(@{ $self->{vars} }, {
			name  => unpack("Z*", substr($self->{stream}, NHEAD_VNAM_OFST + $i * VNAMESIZ, VNAMESIZ)),
			units => unpack("Z*", substr($self->{stream}, NHEAD_UNAM_OFST + $i * VNAMESIZ, VNAMESIZ)),
			 });
	}

	$self->{header}->{recsize} = 4 + $self->{header}->{nvars} * PACSIZE;
	$self->{header}->{nrecs}   = (($self->{len} - NHEAD_SIZE) / $self->{header}->{recsize});

	# Position at start of records
	$self->{pos}    = NHEAD_SIZE;
	$self->{recnum} = -1;
}

sub detach {
	my $self = shift;

	if ($self->{stream}) {
		unmap($self->{stream});
	}

	$self->{stream} = undef;
	$self->{pos}    = $self->{len} = 0;
	$self->{header} = {};
	$self->{vars}   = undef;
	$self->{recnum} = undef;
	$self->{record} = {
		timstamp => undef,
		vals     => undef,
	};
}

sub list_streams {
	my $self = shift;

	opendir(SD, $self->{path}) or die basename($0) . ": Cannot read [" . $self->{path} . "]\n";
	my @fs = readdir(SD);
	closedir(SD);

	my @streams = ();
	foreach my $f (@fs) {
		if (!-d $self->{path} . "/$f") {
			push(@streams, $f);
		}
	}

	return @streams;
}

sub next_record {
	my $self = shift;

	die basename($0) . " Not attached\n" unless $self->{stream};

	my $rec = substr($self->{stream}, $self->{pos}, $self->{header}->{recsize});
	return undef unless (length($rec) == $self->{header}->{recsize});

	# Read timestamp
	$self->{record} = {
		timestamp => $self->_L32VAL(), 
		vals      => [],
	};
	
	$self->{pos} += 4;

	for (my $i=0; $i<$self->{header}->{nvars}; $i++) {
		push(@{ $self->{record}->{vals} }, $self->_dblConv());

		# Go to next value, skipping status
		$self->{pos} += PACSIZE;
	}

	return $self->{record};
}

sub last_record {
	my $self = shift;
	
	die basename($0) . " Not attached\n" unless $self->{stream};

	$self->{pos} = $self->{len} - $self->{header}->{recsize};

	return $self->next_record();
}

# Binary search to find a given time
sub find_time {
	my ($self, $tstamp) = @_;

	die basename($0) . ": Invalid time\n" unless $tstamp && ($tstamp >= 0);
	die basename($0) . ": Not attached\n" unless $self->{stream};

	# Check time of first record
	$self->{pos} = NHEAD_SIZE;
	my $t = $self->_L32VAL();

	if ($tstamp < $t) {
		return $self->next_record();
	}

	# Check time of last record
	$self->{pos} = $self->{len} - $self->{header}->{recsize};
	$t = $self->_L32VAL();

	if ($t < $tstamp) {
		return undef;
	}

	# Now binary search to find given start time
	my ($low, $mid, $high) = (0, 0, $self->{header}->{nrecs} - 1);

	while (($high - $low) > 1) {
		$mid = int(($high + $low) / 2);

		$self->{pos} = NHEAD_SIZE + $mid * $self->{header}->{recsize};
		$t = $self->_L32VAL();

		if ($t < $tstamp) {
			$low = $mid;
		} else {
			$high = $mid;
		}
	}

	while ($t < $tstamp) {
		$self->{pos} += $self->{header}->{recsize};
		
		$t = $self->_L32VAL();
	}

	return $self->next_record();
}

1;
__END__
