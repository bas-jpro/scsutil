#!/usr/local/bin/perl -w
# Monitor SCS Streams
#
# Usage: scs_monitor.pl [-r] [-d <n>] [-a <n>]
#        -r - use Raw streams
#        -d - update delay, seconds 
#        -a - old data age, seconds
#
# $Id$
#

use strict;
use Term::ScreenColor;
use POSIX qw(strftime);
use Getopt::Std;

use lib '/packages/scs/current/lib';
use SCSUtil;
use SCSRaw;

my $TIMEFMT  = '%y-%m-%d %T';
my $NODATA   = '---- No Data ----';
my $TIMELEN  = length($NODATA);
my $STRLEN   = 3; # 3 stream name length

my $DATA_OK  = 'green';
my $DATA_OLD = 'on red'; 
my $TOO_OLD  = 5; # in seconds

my $UPD_DELAY = 2; # update delay in seconds

# Parse Arguments
my %opts = ( a => $TOO_OLD, d => $UPD_DELAY, r => 0);
getopts('ra:d:', \%opts);

if ($opts{a} !~ /^\d+$/) {
	die "$0: -a must be a positive integer\n";
}

if ($opts{d} !~ /^\d+$/) {
	die "$0: -d must be a positive integer\n";
}

# Connect to SCS streams
my $scs = undef;
if ($opts{r}) {
	$scs = SCSRaw->new();
} else {
	$scs = SCSUtil->new();
}
die "Couldn't connect to scs\n" unless $scs;

# Setup Screen
my $scr = new Term::ScreenColor;
$scr->clrscr();
$scr->noecho();
$scr->colorizable(1);

# Loop until 'q' is pressed
my $r = 0;
while (1) {
	# FIXME: Term::Screen doesn't update when resizing
	my $width  = $scr->cols();
	my $height = $scr->rows();
	
	$scr->at($height-1, 0)->puts('Press q to quit');

	my $tsr = scalar(gmtime);
	$scr->at($height-1, $width - length($tsr))->puts($tsr);

	if ($scr->key_pressed()) {
		my $c = getc;

		exit(0) if $c eq 'q';
	}

	# Reload list of instruments each loop to look for new / removed files
	$r = 0;
	my ($namelen, @is) = get_instruments($scs);

	foreach my $inst (@is) {
		# Put spaces to overwrite any screen remnants
		$scr->at($r, 0)->puts($inst->{name} . '  ');

		my $c = $namelen + 2;

		foreach my $s (@{ $inst->{streams} }) {
			if ($c > ($width - $TIMELEN - ($STRLEN + 1) - 1)) {
				$c = $namelen + 2;
				$r++;
				# Clear any existing stream name
				$scr->at($r, 0)->puts(' ' x ($namelen + 2));
			}

			$scs->attach($s->{stream});
			my $rec = $scs->last_record();
	
			my $str = substr($s->{name}, 0, $STRLEN);

			if (!$rec || !$rec->{timestamp}) {
				$scr->at($r, $c)->puts($str . ' ' . $NODATA . ' ');
			} else {
				my $tstamp = $rec->{timestamp};
				my $color = $DATA_OK;
				
				if (time - $tstamp > $opts{a}) {
					$color = $DATA_OLD;
				}
				
				$scr->at($r, $c)->puts($str . ' ');
				$scr->at($r, $c + $STRLEN + 1)->putcolored($color, strftime($TIMEFMT, gmtime($tstamp)));
				$scr->at($r, $c + $STRLEN + 1 + $TIMELEN)->puts(' ');
			}
			$scs->detach();
			
			$c += $TIMELEN + $STRLEN + 1 + 1;
		}

		# Clear rest of line
		$scr->at($r, $c)->clreol();

		$r++;
	}

	# Clear rest of screen except status line at bottom in case list has changed
	for (; $r<$height-1; $r++) {
		$scr->at($r, 0)->clreol();
	}

	sleep($opts{d});
}

0;

sub get_instruments {
	my $scs = shift;

	my @streams = $scs->list_streams();
	my @instruments = ();
	my $namelen = 0;
	
	my $is = { };
	# Need to sort here to get substreams in order as well as instruments
	foreach my $s (sort @streams) {
		my ($inst, $str) = split('-', $s, 2);
		
		# Find longest name
		$namelen = length($inst) if length($inst) > $namelen;
		
		if ($is->{$inst}) {
			push(@{ $is->{$inst}->{streams} }, { name => $str, stream => $s });
		} else {
			$is->{$inst} = { name => $inst, streams => [ { name => ($str || $inst), stream => $s } ] };
		}
	}
	
	foreach my $i (sort keys %$is) {
		push(@instruments, $is->{$i});
	}

	return ($namelen, @instruments);
}

