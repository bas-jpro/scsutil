# SCS Module to read RAW SCS Files
#
# $Id$
#

package SCSRaw;

use strict;
use File::Basename;
use IO::File;
use Time::Local;
use Fcntl qw(SEEK_SET);
use POSIX qw(strftime ceil floor);
use XML::Simple;

my $SECS_PER_DAY = 60 * 60 * 24;
my $RAW_SUFFIX = '.Raw';

sub new {
	my ($class, $xml_desc) = @_;
	
	my $raw = bless {
		path         => '/data/cruise/jcr/current/scs/Raw',
		xml_desc     => undef,
		delim        => ',',
		name         => undef,
		stream       => undef, 
		vars         => undef,
		vars_desc    => undef,
		files        => [ ],
		num_files    => 0,
		current_file => 0,
		
		record => {
			timestamp => undef,
			raw       => undef,
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
	
	$raw->{path} = $ENV{SCSRAWPATH} if $ENV{SCSRAWPATH};

	return $raw;
}

sub change_path {
	my ($raw, $path) = @_;
	
	$raw->{path} = $path;
}

# Extract vars description from give XML 
sub _load_desc {
	my ($raw, $xml_desc) = @_;
	return unless $xml_desc;

	# Save for _reattach
	$raw->{xml_desc} = $xml_desc;

	my $desc = XMLin($xml_desc, ForceArray => [ 'vars' ], KeyAttr => [ ]);
	$raw->{vars_desc} = $desc->{vars};
	$raw->{vars} = [];
	
	foreach my $v (@{ $raw->{vars_desc} }) {
		my $name = $v->{name};
		$name = $raw->{name} . $v->{name} if substr($v->{name}, 0, 1) eq '-';

		push(@{ $raw->{vars} }, { name => $name, units => $v->{units} });
	}
}

# XML desc is stream 
sub attach {
	my ($raw, $stream, $xml_desc) = @_;

	$raw->_find_files($stream);

	die basename($0) . ": Failed to attach $stream - no stream\n" if $raw->{num_files} == 0;

	$raw->{name} = $stream;
	$raw->{stream} = new IO::File "$raw->{path}/$raw->{files}->[$raw->{current_file}]->{name}", O_RDONLY;

	if (!$raw->{stream}) {
		die basename($0) . ": Failed to attach $stream - no stream\n";
	}

	$raw->{stream}->blocking(0);

	$raw->{record} = undef;

	$raw->_load_desc($xml_desc) if $xml_desc;
}

sub detach {
	my $raw = shift @_;

	if ($raw->{stream}) {
		undef $raw->{stream};
	}

	delete $raw->{record};
	$raw->{name} = undef;
	$raw->{files} = [ ];
	$raw->{num_files} = $raw->{current_file} = 0;

	$raw->{vars}      = undef;
	$raw->{vars_desc} = undef;
}

sub list_streams {
	my $raw = shift @_;

	opendir(SD, $raw->{path});
	my @st_files = readdir(SD);
	closedir(SD);

	my %uniq_streams = ();

	my @streams = ();
	foreach (@st_files) {
		if (/^([^_]+)_[0-9-]+$RAW_SUFFIX$/) {
			if (!exists($uniq_streams{$1})) {
				push(@streams, $1);
				
				$uniq_streams{$1} = 1;
			}
		}
	}

	return @streams;
}

sub current_record {
	my $raw = shift @_;

	die basename($0) . ": Not attached\n" unless $raw->{num_files};
	
	return $raw->{record};
}

sub next_record {
	my $raw = shift @_;

	my $rec = $raw->next_record_raw();	return undef unless $rec;

	$raw->_raw_to_time();
	
	return $raw->{record};
}

sub next_record_raw { 
	my $raw = shift @_;

	die basename($0) . ": Not attached\n" unless $raw->{num_files};

	my $fh = $raw->{stream};
	my $str = <$fh>;

	# Move to next file if there is one
	if (!$str) {
		# New files always are after the current file, so can reuse current_file
		my $next_file = $raw->{current_file} + 1;

		# Save where we are in case there are no more files and we want to wait and try again later
		my $fpos = $fh->tell();

		# Check for new files
		$raw->_reattach();
   
		# No more files found, so restore position
		# Need to seek (rather than go to end) in case file has grown since we last read it
		if ($next_file == $raw->{num_files}) {
			$raw->_load_file($next_file - 1);
			$fh = $raw->{stream};
			$fh->seek($fpos, SEEK_SET);

			return undef;
		}
		
		$raw->_load_file($next_file);

		# Read first record
		$fh = $raw->{stream};
		$str = <$fh>;
	}

	chop($str);

	$raw->_convert($str);

	return $raw->{record};
}

my $MAX_REC_LEN = 512;

sub prev_record {
	my $raw = shift @_;

	die basename($0) . ": Not attached\n" unless $raw->{num_files};

	my $fh = $raw->{stream};
	
	my $pos = $fh->tell();
	
	# Might have to move to previous file
	if ($pos == 0) {
		return undef if ($raw->{current_file} == 0);

		$raw->_load_file($raw->{current_file} - 1);
		
		$fh->seek(0, SEEK_END);
	}

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

	chop($last);

	$raw->_convert($last);

	return $raw->{record};
}

sub last_record {
	my $raw = shift @_;

	die basename($0) . ": Not attached\n" unless $raw->{num_files};
	
	# Need to reload in case more files have been created
	$raw->_reattach();
	$raw->_load_file($raw->{num_files} - 1);

	my $fh = $raw->{stream};
	$fh->seek(-$MAX_REC_LEN, SEEK_END);

	my $last;
	$last = $_ while (<$fh>);
	
	return undef unless $last;

	chop($last);

	$raw->_convert($last);

	return $raw->{record};
}

# Return var position for a variable name that matches given re
sub get_re_var_pos {
	my ($raw, $re) = @_;

	my $i = 0;
	foreach (@{ $raw->{vars} }) {
		return $i if $_->{name} =~ /$re/i;
		$i++;
	}

	return undef;
}

# Return list of positions in @vals for each variable given
sub get_vars_pos {
	my ($raw, @varnames) = @_;

	my %var_lookup;
	my $i = 0;
	foreach (@{ $raw->{vars} }) {
		$var_lookup{$_->{name}} = $i;
		$i++;
	}

	my @ps;
	foreach (@varnames) {
		die basename($0) . ": $raw->{name} attach failure, mismatch\n" if !defined($var_lookup{$_});

		push(@ps, $var_lookup{$_});
	}

	return @ps;
}

# Use a binary search to find a given start time and set filepos
# Based on version from book "Mastering Algorithms with Perl"
sub find_time { 
	my ($raw, $tstamp) = @_;
	return unless $tstamp;

	die basename($0) . ": Not attached\n" unless $raw->{num_files};

	my $found_file = -1;

	# Might be in this file 
	if ($raw->{files}->[$raw->{current_file}]->{start_time} <= $tstamp) {
		if ($raw->{files}->[$raw->{current_file}]->{end_time} && ($tstamp < $raw->{files}->[$raw->{current_file}]->{end_time})) {
			$found_file = $raw->{current_file};
		}
	}

	if ($found_file == -1) {
		# Check for new files
		$raw->_reattach();

		# First need to find file containing record
		for (my $i=0; $i<$raw->{num_files}; $i++) {
			if (($raw->{files}->[$i]->{start_time} <= $tstamp)) {
				if ($raw->{files}->[$i]->{end_time} && ($tstamp < $raw->{files}->[$i]->{end_time})) {
					# In this file
					$found_file = $i;
					last;
				}
			}
		}

		# Last file or nothing
		$found_file = $raw->{num_files} - 1;
	}

	# found_file is now the file number possibly containing the record we're after
	if ($found_file != $raw->{current_file}) {
		$raw->_load_file($found_file);
	}

	my $fh = $raw->{stream};
	
#	my ($year, $dayfract) = $raw->_time_to_raw($tstamp);

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
#				last if $raw->_time_compare($line, $year, $dayfract) >= 0;
				chop($line);
				$raw->_convert($line);

				last if $raw->{record}->{timestamp} >= $tstamp; 
				$low = tell($fh);

			}
			last;
		}
		
		last if !$line;

		chop($line);
		$raw->_convert($line);

#		if ($raw->_time_compare($line, $year, $dayfract) < 0) { 
		if ($raw->{record}->{timestamp} < $tstamp) {
			$low = $mid;
		} else {
			$high = $mid;
		}
	}

	# If we fall off end of file return undef
	if ($line) {
		$raw->_convert($line);
	} else {
		$raw->{record} = undef;
	}

	return $raw->{record};
}

# Compare the current record time to an raw year, dayfract time
sub rec_time_compare {
	my ($raw, $year, $dayfract) = @_;

	return -1 if $raw->{record}->{year} < $year;
	return 1  if $raw->{record}->{year} > $year;

	return ($raw->{record}->{dayfract} <=> $dayfract);
}

# Convert raw year/dayfract to unixtimestamp
sub raw_to_time {
	my ($raw, $year, $dayfract) = @_;

	return timegm(0, 0, 0, 1, 0, $year - 1900) + $raw->_rint($SECS_PER_DAY * ($dayfract - 1));
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

# INTERNAL FUNCTIONS
# Convert date/time in filename to unix time
sub _convert_rawfile_time {
	my ($raw, $date, $time) = @_;

	my ($year, $month, $day, $hour, $minute, $second);

	if ($date =~ /^([0-9]{4})([0-9]{2})([0-9]{2})/) {
		($year, $month, $day) = ($1, $2, $3);
	} else {
		die basename($0) .": invalid file date\n";
	}
	
	if ($time =~ /^([0-9]{2})([0-9]{2})([0-9]{2})/) {
		($hour, $minute, $second) = ($1, $2, $3);
	} else {
		die basename($0) . ": invalid file time\n";
	}

	return timegm($second, $minute, $hour, $day, $month - 1, $year - 1900);
}

sub _convert_raw_time {
	my ($raw, $date, $tstamp) = @_;

	if ($date =~ /^([0-9]{2})\/([0-9]{2})\/([0-9]{4})/) {
		$date = join("", $3, $1, $2);
	}

	if ($tstamp =~ /^([0-9]{2}):([0-9]{2}):([0-9]{2})/) {
		$tstamp = join("", $1, $2, $3);
	}

	return $raw->_convert_rawfile_time($date, $tstamp);
}

# Convert record to timestamp / raw value
# Updated for SCS4 Raw files which have MM/DD/YYYY,HH:MM:SS.SSS time format
sub _convert {
	my ($raw, $str) = @_;

	my ($date, $tstamp) = undef;
	($date, $tstamp, $raw->{record}->{raw}) = split(",", $str, 3);

	$raw->{record}->{timestamp} = $raw->_convert_raw_time($date, $tstamp);

	# Extract variables from raw string if we have a description
	if ($raw->{vars_desc}) {
		$raw->{record}->{vals} = [];
		
		my @infs = split($raw->{delim}, $raw->{record}->{raw});
		foreach my $v (@{ $raw->{vars_desc} }) {
			my $val = undef;
			my $cmd = '$val = $raw->_convert_' . $v->{type} . '($v, \@infs)';
			
			eval $cmd;

			if ($@ || !defined($val)) {
				die basename($0) . ": $raw->{name}, Failed to convert variable $v->{name} of type $v->{type}: $@\n";
			}

			push(@{ $raw->{record}->{vals} }, $val);
		}
	}
}

# Convert string variable
sub _convert_string {
	my ($raw, $var, $infs) = @_;

	return (defined($infs->[$var->{field}]) ? $infs->[$var->{field}] : '');
}

# Convert a string variable just before a checksum field
sub _convert_prechecksum_string {
	my ($raw, $var, $infs) = @_;

	return (((split('\*', ($infs->[$var->{field}] || '')))[0]) || '');
}

# Convert GPS (D)DDMM.MMMM pos, dir (N,E,S,W) pair
sub _convert_latlon {
	my ($raw, $var, $infs) = @_;

	my ($gpspos, $dir) = ($infs->[$var->{field}], $infs->[$var->{field}+1]);
	# Make sure gpspos is a real - regex from perlretut
	$gpspos = 99999 unless defined($gpspos) && ($gpspos =~ /^[+-]?\ *(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/); 
	$dir    = 'N'   unless $dir;

	my $deg = int($gpspos / 100);
	my $min = $gpspos - ($deg * 100);

	return sprintf("%.5f", (($deg + ($min / 60)) * ((($dir eq 'S') || ($dir eq 'W')) ? -1 : 1)));
}

sub _reattach {
	my $raw = shift;

	my $name    = $raw->{name};
	my $xml_desc = $raw->{xml_desc};

	$raw->detach();
	$raw->attach($name, $xml_desc);
}

sub _find_files {
	my ($raw, $stream) = @_;

	$raw->{files} = [ ];
	$raw->{num_files} = 0;

	opendir(SR, $raw->{path}) or return;
	my @files = grep { /^${stream}_[0-9-]+$RAW_SUFFIX$/ } readdir(SR); 
	closedir(SR) or die basename($0) . ": Failed to close dir $raw->{path}\n";

	foreach my $f (sort @files) {
		if ($f =~ /([0-9]+)-([0-9]+)/) {
			push(@{ $raw->{files} }, { 
				name       => $f, 
				start_time => $raw->_convert_rawfile_time($1, $2),
				end_time   => undef,
			});

			$raw->{num_files}++;

			if ($raw->{num_files} > 1) {
				$raw->{files}->[$raw->{num_files}-2]->{end_time} = $raw->{files}->[$raw->{num_files}-1]->{start_time};
			}				
		}
	}
}


sub _load_file {
	my ($raw, $file) = @_;

	die basename($0) . ": invalid file\n" unless (($file >= 0) && ($file < $raw->{num_files}));

	$raw->{current_file} = $file;

	delete $raw->{stream};

	$raw->{stream} = new IO::File "< $raw->{path}/$raw->{files}->[$raw->{current_file}]->{name}";
	$raw->{stream}->blocking(0);
	
	$raw->{record} = undef;
}


# Round to nearest integer
sub _rint {
	my ($raw, $dval) = @_;

	if (abs(ceil($dval) - $dval) < abs(floor($dval) - $dval)) {
		return ceil($dval);
	}

	return floor($dval);
}

# Compare an raw line against and raw time
sub _time_compare { 
	my ($raw, $line, $year, $dayfract) = @_;

	my ($stream_year, $stream_dayfract) = (split($raw->{delim}, $line))[0, 1];

	return -1 if $stream_year < $year;

	return  1 if $stream_year > $year;

	# Years are equal
	return ($stream_dayfract <=> $dayfract); 
}

# Convert a unix timestamp to an raw year, dayfract
sub _time_to_raw { 
	my ($raw, $tstamp) = @_;

	my @ts = gmtime($tstamp);
	
	return ($ts[5] + 1900, 1 + $ts[7] + ($ts[2] * 3600 + $ts[1] * 60 + 
										 $ts[0]) / $SECS_PER_DAY);
}

# Convert an raw year, dayfract to unix timestamp
sub _raw_to_time {
	my $raw = shift;

	$raw->{record}->{timestamp} = timegm(0, 0, 0, 1, 0, $raw->{record}->{year} - 1900) +
		$raw->_rint($SECS_PER_DAY * ($raw->{record}->{dayfract} - 1)) if $raw->{record}->{year};
}

1;
__END__
