#!/usr/local/bin/perl -w
#
# $Id$
#
# Generate Compress/.ACO & .TPL files for SCS v4
#

use strict;
use lib '/packages/scs/current/lib';
use SCS;
use SCS::Raw;
use SCS::Compress;
use XML::Simple;
use Parallel::ForkManager;
use IO::File;
use Fcntl qw(:DEFAULT :flock);
use POSIX qw(setsid);
use Getopt::Std;

my $TPL_EXT = '.TPL';
my $ACO_EXT = '.ACO';
my $SECS_PER_DAY = 60 * 60 * 24;

# Finish conversion if SIGTERM caught
my $FINISH = 0;
$SIG{TERM} = sub { $FINISH = 1; };

my %opts = ( k => 0, d => 0 );
getopts('kd', \%opts);

die "Usage: $0 [-k] [-d] <config file>\n" unless scalar(@ARGV) == 1;

# Do this here before we chdir since ARGV[0] might be relative
my $config = XMLin($ARGV[0], ForceArray => [ 'stream' ], KeyAttr => [ ] );

my $lockdir = $config->{lockdir};
if (!-d $lockdir) {
	die "$lockdir is not a directory\n";
}

# If -k given just kill existing processes and exit
if ($opts{k}) {
	opendir(DIR, $lockdir) or die "Can't read directory: $lockdir\n";
	my @ls = grep { -f "$lockdir/$_" } readdir(DIR);
	closedir(DIR);

	foreach my $l (@ls) {
		open(LF, "< $lockdir/$l") or die "Can't read lockfile: $l\n";
		my $pid = <LF>;
		next unless $pid;
		chomp($pid);
		close(LF);

		print "Killing: $l\n";
		kill 'TERM', $pid;
	}

	exit(0);
}

# Don't detach if -d is given
if (!$opts{d}) {
	# Change working directory to / fork a new server and return
	chdir("/") or die "FATAL Error: Can't chdir to / : $!\n";

	my $pid;
  FORK: {
	  if ($pid = fork) {
		  # We are the parent so end. Return the child pid
		  print "$pid\n";
		  exit(0);
	  } elsif (defined($pid)) {
		  # We are the child so continue
		  last;
	  } elsif ($! =~ /No more process/) {
		  # EAGAIN, supposedly recoverable fork error
		  sleep 5;
		  redo FORK;
	  } else {
		  # Weird fork error
		  die "Can't fork: $!\n";
	  }
	}

	# Start a new session to detach from tty group
	setsid or die "Can't start a new session\n";
}

my $num_streams = scalar(@{ $config->{stream} });

# if -d can only do one stream at once
if ($opts{d} && ($num_streams > 1)) {
	die "Debugging option -d only allows 1 stream to be converted\n";
}

my $pm = Parallel::ForkManager->new($num_streams);

# Loop through each raw stream, converting to compress format
foreach my $stream (@{ $config->{stream} }) {
	!$opts{d} and $pm->start and next; # fork child to handle conversion

	# Lock this stream so only 1 process/stream at any one time
	my $lockfile = $lockdir . "/" . $stream->{name};
	my $fl = new IO::File ">> $lockfile";
	if (!defined $fl) {
		die "Couldn't get lock ($lockfile) for $stream->{name}\n";
	}

	$fl->autoflush(1);
	if (flock($fl, LOCK_EX | LOCK_NB)) {
		if (!$fl->truncate(0)) {
			die "Couldn't truncate lock file for $stream->{name}\n";
		}
		print $fl $$, "\n";
		
		# Set name so we can see in ps
		$0 = 'raw2compress [' . $stream->{name} . ']';
	
		# Convert Stream
		# Catch errors so we can clean up logfiles
		eval { convert($stream); };

		if (!unlink($lockfile)) {
			die "Couldn't delete lock file ($lockfile)\n";
		}
	} else {
		print "$stream->{name} locked, exiting\n";
	}

	if (!$fl->close) {
		die "Couldn't close $stream->{name}\n";
	}

	!$opts{d} and $pm->finish;
}

!$opts{d} and $pm->wait_all_children;

0;

sub convert {
	my $stream = shift;
	die "No stream\n" unless $stream;

	my $raw = SCS::Raw->new();
	$raw->debug(1) if $opts{d};
	$raw->change_path($config->{rawdir}) if defined($config->{rawdir});
	$raw->attach($stream->{raw}, $config->{datadir} . '/' . $stream->{rawdesc});

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

		# Go to that time in raw file
		$rec = $raw->find_time($tstamp) if $tstamp;

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

	# Convert forever or until SIGTERM
	while (!$FINISH) {
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

		undef $rec;
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
