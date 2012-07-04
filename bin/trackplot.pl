#!/usr/local/bin/perl -w
#
# Plot ship's track from SCS streams
#
# v1.0 JPRO JCR JR83 03/11/2002 Initial Release
#
# Arguments start_time end_time stream filename
#
# Times in unix timestamp format
#
# Note: Usually run as web user from JCR SCS Web interface
#

use strict;

# Directory with .gmtdefaults in
my $WORKINGDIR = '/packages/scs/plots';

# GMT Programs
my $GMTDIR  = '/packages/gmt/3.3.4/';
my $PSCOAST = $GMTDIR . 'bin/pscoast';
my $PSXY    = $GMTDIR . 'bin/psxy';
my $MINMAX  = $GMTDIR . 'bin/minmax';

# SCS Programs
my $SCSDIR  = '/packages/scs/current/';
my $EXTRACT = $SCSDIR . 'bin/extract_latlon';
		
# Printable width (CM) for different paper sizes
# Determined by trial & error
my $PAPER_WIDTHS = {
	'A0' => {
		'Portrait' => '79.1',
		'Landscape' => '72.0',
	},
	'A4' => {
		'Portrait'  => '16.65',
		'Landscape' => '13.80',
	},
};

if (scalar(@ARGV) != 4) {
	die "Usage: $0 <start time> <end time> <stream> <filename>\n";
}

my ($start_time, $end_time, $stream, $filename) = @ARGV;

# Change working directory 
chdir($WORKINGDIR);

# Generate Lat/Lons if necessary
my $latlon_file = "$stream.$start_time.$end_time.latlon";

# Only extract data if not previously done 
if (!-e $latlon_file) {
    # Extract Lat/Lon from SCS Stream
	my $cmd = "$EXTRACT $start_time $end_time $stream > $latlon_file"; 
	
	`$cmd`;
}

# Find min/max values
my $cmd = "$MINMAX -I5 -C $latlon_file";

my $minmax = `$cmd`;
chomp($minmax);

# Extract min / max values
my ($null, $ymin, $ymax, $xmin, $xmax) = split(/\s+/, $minmax);

my $bbox = "-R$xmin/$xmax/$ymin/$ymax";

# Calculate orientation and scaling factors
my ($xdegs, $ydegs) = ($xmax - $xmin, $ymax - $ymin);

my $paper_mode = "-P";
my $cmdeg = ($PAPER_WIDTHS->{A4}->{Landscape} / $ydegs) . 'c';

if ($xdegs < $ydegs) {
	$paper_mode = "-P";
	$cmdeg = ($PAPER_WIDTHS->{A4}->{Portrait} / $xdegs) . 'c';
}

print STDERR "Paper_mode: $paper_mode CMDEGS: $cmdeg\n";

#my $cmdeg = "1c";

# Draw Coasts
$cmd = "$PSCOAST $bbox -Jm$cmdeg $paper_mode -B1g1 -Df -G180/120/60 -K > $filename";
`$cmd`;

# Plot track
$cmd = "$PSXY $bbox -Jm$cmdeg $paper_mode -: -O -U < $latlon_file >> $filename";
`$cmd`;

0;
