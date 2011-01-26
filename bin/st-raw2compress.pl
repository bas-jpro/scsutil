#!/usr/local/bin/perl -w
#
# $Id$
#
# Generate Compress/.ACO & .TPL files for SCS v4
#

use strict;
use lib '/packages/scs/current/lib';
#use lib 'E:/scs/scs/lib';

use SCS;
use SCS::Raw;
use SCS::Compress;
use XML::Simple;
#use Parallel::ForkManager;
use Data::Dumper;
use IO::File;
use Fcntl qw(:DEFAULT :flock);
use POSIX qw(setsid);
use Getopt::Std;

#use lib 'E:/scs/dps/perl';
use lib '/users/dacon/projects/dps/perl';
use DPS::Log;
DPS::Log::set_level(100);

my $TPL_EXT = '.TPL';
my $ACO_EXT = '.ACO';
my $SECS_PER_DAY = 60 * 60 * 24;

# Finish conversion if SIGTERM caught
my $FINISH = 0;
$SIG{TERM} = sub { $FINISH = 1; };

my %opts = ( k => 0 );
getopts('k', \%opts);

die "Usage: $0 [-k] <config file> <stream>\n" unless scalar(@ARGV) == 2;

# Do this here before we chdir since ARGV[0] might be relative
my $config = XMLin($ARGV[0], ForceArray => [ 'stream' ], KeyAttr => [ ] );

my $lockdir = $config->{lockdir};
if (!-d $lockdir) {
	die "$lockdir is not a directory\n";
}

# Check for stream we want to convert
my $process_stream = $ARGV[1] || undef;

DPS::Log::msg(__PACKAGE__, "Ready to convert for stream=$process_stream");


foreach my $stream (@{ $config->{stream} }) {
	print  $stream->{name}."\n";
	if($stream->{name} eq $process_stream) {
	
		# Convert Stream
		convert($stream);
	}
}

0;

sub convert {
	my $stream = shift;
	die "No stream\n" unless $stream;

	DPS::Log::msg(__PACKAGE__, "convert :: stream=$stream->{name}");
	
	my $raw = SCS::Raw->new();
	$raw->change_path($config->{rawdir}) if defined($config->{rawdir});
	$raw->attach($stream->{raw}, $config->{datadir} . '/' . $stream->{rawdesc});

	DPS::Log::msg(__PACKAGE__, "convert :: raw attached");
	
	create_tpl($stream, $raw);

	# Create or open existing file
	my $aco_name = $config->{compressdir} . '/' . $stream->{name} . $ACO_EXT;
	my $ah = new IO::File;
	if (-e $aco_name) {
	

		# Find last timestamp in aco file
		my $scs = SCS::Compress->new();
		$scs->change_path($config->{compressdir});
		
		$scs->attach($stream->{name});
		my $rec = $scs->last_record();
		my $tstamp = $rec->{timestamp};
		$scs->detach();

		DPS::Log::msg(__PACKAGE__, "last ACO record: ".DPS::Log::date($rec->{timestamp}));
		
		# Go to that time in raw file
		$rec = $raw->find_time($tstamp) if $tstamp;

		DPS::Log::msg(__PACKAGE__, "matching RAW timestapm: ".DPS::Log::date($rec->{timestamp}));

		
		# If we found the time append to aco file
		if ($rec && $rec->{timestamp} && ($rec->{timestamp} == $tstamp)) {
			$ah->open(">> $aco_name");
		}
	}
	
	

	if (!$ah->opened) {
		$ah->open("> $aco_name");
	}

	die "Cannot write to $aco_name\n" unless $ah->opened;

	# Turn on Autoflush
	$ah->autoflush(1);

	# Convert Records - update program name every so often so ps can see progress
	my $ps_time = 0;

	DPS::Log::msg(__PACKAGE__, "Entering main watch loop");

	# Convert forever or until SIGTERM
	while (!$FINISH) {
		DPS::Log::msg(__PACKAGE__,"watch");
		my $rec = $raw->next_record();
		if (!$rec) {
			sleep(1);
			next;
		}
		
		# Detect if time goes backward and display so operator can see problems
		if (($rec->{timestamp} > $ps_time + $config->{psupdate}) || ($rec->{timestamp} < $ps_time)) {
			$ps_time = $rec->{timestamp};
			$0 = 'raw2compress [' . $ps_time . ' - ' . $stream->{name} . ']';
		}
		
		# Get SCS timestamp
		my ($year, $jday, $dayfract) = tstamp_to_scs($rec->{timestamp});

		print $ah join($stream->{delim}, $year, sprintf("%.6f", $jday+$dayfract), $jday, sprintf("%.8f", $dayfract),
					   @{ $rec->{vals} }), "\r\n";
	}

	$ah->close;
	$raw->detach();
}

sub create_tpl {
	my ($stream, $raw) = @_;

	my $tpl_name = $config->{compressdir} . '/' . $stream->{name} . $TPL_EXT;
	return if -e $tpl_name;
	
	open(TH, "> $tpl_name") or die "Cannot write to $tpl_name\n";

	my $varnum = $stream->{scsnum} || 0;
	foreach my $v (@{ $raw->{vars} }) {
		# Need to convert name to Compress form, rather than raw
		my $varname = $v->{name};

		if ($varname =~ /-/) {
			my $raw_varname = (reverse(split('-', $v->{name})))[0];
			
			$varname = $stream->{name} . '-' . $raw_varname;
		}

		print TH join(",", $varnum++, $varname, $v->{units}), "\r\n";
	}

	close(TH);	
}

# Convert unix timestamp to scs year, jday, dayfract
sub tstamp_to_scs {
	my $tstamp = shift;
	return (0, 0, 0) unless $tstamp;

	my @ts = gmtime($tstamp);
	return ($ts[5] + 1900, 1 + $ts[7], ($ts[2] * 3600 + $ts[1] * 60 + $ts[0]) / $SECS_PER_DAY);
}
