# General SCS Module for SCS versions of RVS utilities
#
# $Id: SCSUtil.pm 567 2009-11-24 21:52:19Z jpro $
#

package SCSUtil;

use strict;
use File::Basename;
use IO::File;
use Time::Local;
use POSIX qw(strftime ceil floor);

my $SECS_PER_DAY = 60 * 60 * 24;

sub new {
	my $class = shift @_;
	
	my $scs = bless {
		path   => '/data/cruise/jcr/current/scs/Compress',
		delim  => ',',
		name   => undef,
		stream => undef, 
		record => {
			year      => undef,
			dayfract  => undef,
			timestamp => undef,
			vals      => undef,
		},
		vars => undef,
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
	
	$scs->{path} = $ENV{SCSPATH} if $ENV{SCSPATH};

	return $scs;
}

sub change_path {
	my ($scs, $path) = @_;
	
	$scs->{path} = $path;
}

sub attach {
	my ($scs, $stream) = @_;

	die basename($0) . ": Failed to attach $stream - no stream\n" if 
		!-e "$scs->{path}/$stream.ACO";

	$scs->{name} = $stream;
	$scs->{stream} = new IO::File "$scs->{path}/$stream.ACO", O_RDONLY ;

	if (!$scs->{stream}) {
		die basename($0). ": Failed to attach $stream\n";
	}

	$scs->{stream}->blocking(0);	
}

sub detach {
	my $scs = shift @_;

	return if !$scs->{stream};
	
	undef $scs->{stream};

	delete $scs->{record};
	$scs->{name} = undef;
	$scs->{vars} = undef;
}

sub list_streams {
	my $scs = shift @_;

	opendir(SD, $scs->{path});
	my @st_files = readdir(SD);
	closedir(SD);

	my @streams = ();
	foreach (@st_files) {
		push (@streams, $1) if /^([^ \.]+)\.ACO$/;
	}

	return @streams;
}

sub current_record {
	my $scs = shift @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};
	
	return $scs->{record};
}

sub next_record {
	my $scs = shift @_;

	my $rec = $scs->next_record_scs();	return undef unless $rec;

	$scs->_scs_to_time();
	
	return $scs->{record};
}

sub next_record_scs { 
	my $scs = shift @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	my $fh = $scs->{stream};
	my $str = <$fh>;

	return undef unless $str;

	chop($str);

	my ($year, $fract_time, $jday, $dayfract, @vals) = split(",", $str);
	
	$scs->{record}->{year} = $year;
	$scs->{record}->{dayfract} = $jday + $dayfract;
	$scs->{record}->{vals} = \@vals;

	return $scs->{record};
}

my $MAX_REC_LEN = 512;

sub prev_record {
	my $scs = shift @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	my $fh = $scs->{stream};
	
	my $pos = $fh->tell();
	return undef if $pos == 0;

	$fh->seek(-$MAX_REC_LEN, SEEK_CUR);
	
	my $prev_pos;
	my $last;
	while (<$fh>) {
		last if ($fh->tell() == $pos);
		$last = $_;
		$prev_pos = $fh->tell();
	}

	# Move file pointer to end of prev record
	$fh->seek($prev_pos, SEEK_SET);

	$scs->_convert($last);

	return $scs->{record};
}

sub last_record {
	my $scs = shift @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	my $fh = $scs->{stream};
	$fh->seek(-$MAX_REC_LEN, SEEK_END);

	my $last;
	$last = $_ while (<$fh>);

	$scs->_convert($last);

	return $scs->{record};
}

sub vars {
	my $scs = shift;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	return $scs->{vars} if $scs->{vars};
	
	my @vars = ();

	open(TP, "$scs->{path}/$scs->{name}.TPL");
	while (<TP>) {
		chomp;
		chop if /\r$/;
		my ($id, $name, $units) = split ",";
		
		push(@vars, { name => $name, units => $units } );
	}
	close(TP);

	$scs->{vars} = \@vars;

	return $scs->{vars};
}

# Return var position for a variable name that matches given re
sub get_re_var_pos {
	my ($scs, $re) = @_;

	# Make sure variables have been loaded
	$scs->vars();

	my $i = 0;
	foreach (@{ $scs->{vars} }) {
		return $i if $_->{name} =~ /$re/i;
		$i++;
	}

	return undef;
}

# Return list of positions in @vals for each variable given
sub get_vars_pos {
	my ($scs, @varnames) = @_;

	# Make sure variables have been loaded
	$scs->vars();

	my %var_lookup;
	my $i = 0;
	foreach (@{ $scs->{vars} }) {
		$var_lookup{$_->{name}} = $i;
		$i++;
	}

	my @ps;
	foreach (@varnames) {
		die basename($0) . ": $scs->{name} attach failure, mismatch\n" if
			!defined($var_lookup{$_});

		push(@ps, $var_lookup{$_});
	}

	return @ps;
}

# Return a string of the given timestamp in standard format
sub time_str {
	my ($scs, $tstamp) = @_;

	return strftime("%y %j %T", gmtime($tstamp));
}

sub convert_rvs_time {
	my ($scs, $rvstime) = @_;

	my ($year, $jday, $hour, $minute, $second);
	if ($rvstime =~ /^([0-9]{2})([0-9]{3})([0-9]{2})([0-9]{2})([0-9]{0,2})$/) {
		($year, $jday, $hour, $minute, $second) = ($1, $2, $3, $4, $5);
		$second = 0 unless $second;
	} else {
		die basename($0) .": invalid time\n";
	}
	
	# Y2K Compliance
	if ($year < 69) {
		$year += 2000;
	} else {
		$year += 1900;
	}

	return timegm(0, 0, 0, 1, 0, $year - 1900) + 
		($SECS_PER_DAY * ($jday - 1)) + (3600 * $hour) + (60 * $minute) +
			$second;
}

# Go to record with timestamp at least $tstamp
sub goto_time {
	my ($scs, $tstamp) = @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};
	
	# Start at beginning of file
	my $fh = $scs->{stream};
	$fh->seek(0, SEEK_SET);
	$scs->next_record();
	my $start_tstamp = $scs->{record}->{timestamp};

	if ($tstamp > $start_tstamp) {
		$scs->next_record();
		
		# Estimate record size and interval
		my $recsize = ($fh->tell()) / 2;
		my $interval = $scs->{record}->{timestamp} - $start_tstamp;
		$interval = 0.5 if $interval == 0; # Avoid divide-by-zero errors

		# Jump to record before guessed position
		my $jump = $recsize * (($tstamp - $start_tstamp) / $interval - 1);
		$fh->seek($jump, SEEK_SET);

		# Through away this record - we could be in the middle of one
		my $dummy = <$fh>;

		my $rec = $scs->next_record();

		# Check to see if we fell of the end of the file
		if (!$rec) {
			# Yup, go to last record
			$scs->last_record();
		}

		# If we overshot move backwards
		while ($tstamp - $scs->{record}->{timestamp} < 0) {
			last if !$scs->prev_record();
		}

		# If we undershot move forwards
		while ($tstamp - $scs->{record}->{timestamp} > 0) {
			last if !$scs->next_record();
		}
	}
}

# Use a binary search to find a given start time and set filepos
# Based on version from book "Mastering Algorithms with Perl"
sub find_time { 
	my ($scs, $tstamp) = @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	my $fh = $scs->{stream};
	
#	my ($year, $dayfract) = $scs->_time_to_scs($tstamp);

	my ($low, $mid, $mid2, $high) = (0, 0, 0, (stat($fh))[7]);
	my $line = "";

	while ($high != $low) {
		$mid = int(($high + $low) / 2);

		seek($fh, $mid, SEEK_SET);
		
		# read rest of line in case in middle
		$line = <$fh>;
		$mid2 = tell($fh);

		if ($mid2 < $high) {
			# Not near end of file
			$mid = $mid2;
			$line = <$fh>;
		} else {
			# At last line so linear search
			seek($fh, $low, SEEK_SET);

			while (defined($line = <$fh>)) {
#				last if $scs->_time_compare($line, $year, $dayfract) >= 0;
				$scs->_convert($line);
				last if $scs->{record}->{timestamp} >= $tstamp; 
				$low = tell($fh);

			}
			last;
		}

		$scs->_convert($line);

#		if ($scs->_time_compare($line, $year, $dayfract) < 0) { 
		if ($scs->{record}->{timestamp} < $tstamp) {
			$low = $mid;
		} else {
			$high = $mid;
		}
	}

	# If we fall off end of file return undef
	if ($line) {
		$scs->_convert($line);
	} else {
		$scs->{record} = undef;
	}

	return $scs->{record};
}

sub check_status {
	my ($scs, $status) = @_;

	$_ = $status;

	return $scs->{NOTWRIT} if /^notwrit$/i;
	return $scs->{TEST}    if /^test$/i;
	return $scs->{REJECT}  if /^reject$/i;
	return $scs->{SUSPECT} if /^suspect$/i;
	return $scs->{RESTART} if /^restart$/i;
	return $scs->{INTERP}  if /^interp$/i;
	return $scs->{UNCORR}  if /^uncorr$/i;
	return $scs->{GOOD}    if /^good$/i;
	return $scs->{CORRECT} if /^correct$/i;
	return $scs->{ACCEPT}  if /^accept$/i;

	die basename($0) . ": bad status $_\n";
}

# Convert the value at a given position to degrees & minutes
# dir is "N" for lat and "E" for lon
sub conv_deg_min {
	my ($scs, $var_pos, $dir) = @_;

	die basename($0) . ": Not attached\n" unless $scs->{stream};

	die basename($0) . ": invalid dir\n" unless $dir && 
		(($dir eq "N") || ($dir eq "E"));

	my $val = $scs->{record}->{vals}->[$var_pos];

	die basename($0). ": no record\n" if !defined($val);

	if ($val < 0) {
		$val *= -1;
		$dir = "S" if $dir eq "N";
		$dir = "W" if $dir eq "E";
	}

	my $deg = int($val);
	my $min = ($val - $deg) * 60.0;

	return sprintf("%02d %0.2f$dir", $deg, $min);
}

# Compare the current record time to an scs year, dayfract time
sub rec_time_compare {
	my ($scs, $year, $dayfract) = @_;

	return -1 if $scs->{record}->{year} < $year;
	return 1  if $scs->{record}->{year} > $year;

	return ($scs->{record}->{dayfract} <=> $dayfract);
}

# Convert scs year/dayfract to unixtimestamp
sub scs_to_time {
	my ($scs, $year, $dayfract) = @_;

	return timegm(0, 0, 0, 1, 0, $year - 1900) + $scs->_rint($SECS_PER_DAY * ($dayfract - 1));
}

# INTERNAL FUNCTIONS
sub _convert {
	my ($scs, $str) = @_;

	$scs->_convert_scs($str);
	$scs->_scs_to_time();

}

sub _convert_scs {
	my ($scs, $str) = @_;

	if (!$str) {
		$scs->{record}->{year} = undef;
		$scs->{record}->{dayfract} = undef;
		$scs->{record}->{timestamp} = undef;
		$scs->{record}->{vals} = undef;
		return;
	}
	chomp($str);
	chop($str) if ($str =~ /\r$/);

	my ($year, $fract_time, $jday, $dayfract, @vals) = split(",", $str);
	
	$scs->{record}->{year} = $year;
	$scs->{record}->{dayfract} = $jday + $dayfract;
	$scs->{record}->{vals} = \@vals;
}

# Round to nearest integer
sub _rint {
	my ($scs, $dval) = @_;

	if (abs(ceil($dval) - $dval) < abs(floor($dval) - $dval)) {
		return ceil($dval);
	}

	return floor($dval);
}

# Compare an scs line against and scs time
sub _time_compare { 
	my ($scs, $line, $year, $dayfract) = @_;

	my ($stream_year, $stream_dayfract) = (split($scs->{delim}, $line))[0, 1];

	return -1 if $stream_year < $year;

	return  1 if $stream_year > $year;

	# Years are equal
	return ($stream_dayfract <=> $dayfract); 
}

# Convert a unix timestamp to an scs year, dayfract
sub _time_to_scs { 
	my ($scs, $tstamp) = @_;

	my @ts = gmtime($tstamp);
	
	return ($ts[5] + 1900, 1 + $ts[7] + ($ts[2] * 3600 + $ts[1] * 60 + 
										 $ts[0]) / $SECS_PER_DAY);
}

# Convert an scs year, dayfract to unix timestamp
sub _scs_to_time {
	my $scs = shift;

	$scs->{record}->{timestamp} = timegm(0, 0, 0, 1, 0, $scs->{record}->{year} - 1900) +
		$scs->_rint($SECS_PER_DAY * ($scs->{record}->{dayfract} - 1)) if $scs->{record}->{year};
}

1;
__END__
