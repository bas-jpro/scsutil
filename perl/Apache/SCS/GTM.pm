# SCS GTM Download
# 
# v1.0 JPRO JR134 16/11/2005 Initial Release
#

package Apache::SCS::GTM;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(gtm_setup gtm_download);

use strict;
use lib '/nerc/packages/src/1.0/lib';
use SCSUtil;
use CGI::Pretty qw( :all *table *Tr *form *frameset);
use POSIX qw(strftime);
use Time::Local;

my @INTERVALS = qw(1 2 5 10 30 60 120 180 240 300);
my $STREAM = 'Seatex';

sub gtm_setup {
	my $config = shift;

	print header(), "\n";
	&Apache::SCS::Main::page_header;
	
	print br(), "\n";
	print h3(font({ -color => 'blue' }, "SCS GTM Download"));
   
	print start_form({-action => "/$config->{location}/gtm-download/ship-gtm.txt", -method => "post"});

	# This is Y2K compliant - gmtime returns year-1900
	my @ds = gmtime();

	my $year  = $ds[5]+1900;              
	my $month = sprintf("%02d", $ds[4]+1);
	my $day   = sprintf("%02d", $ds[3]);
	my $hour  = sprintf("%02d", $ds[2]);
	my $min   = sprintf("%02d", $ds[1]);
	my $sec   = sprintf("%02d", $ds[0]);

	print table({-align => 'left', -width => '100%'},
				Tr(
				   td({-align => "left", -width => "10%"}, "Start Time"),
				   td({-align => "left"},
					  popup_menu({-name => "start_day", -values  => $Apache::SCS::Constants::SCS_DAYS,
								  -default => $day})),
				   td({-align => "left"},
					  popup_menu({-name => "start_month", -values  => $Apache::SCS::Constants::SCS_MONTH_NUMS,
								  -labels  => $Apache::SCS::Constants::SCS_MONTH_NAMES,
								  -default => $month})),
				   td({-align => "left"},
					  popup_menu({-name => "start_year", -values => $Apache::SCS::Constants::SCS_YEARS,
								  -default => $year})),
				   td({-align => "left"},
					  popup_menu({-name => "start_hour", -values => $Apache::SCS::Constants::SCS_HOURS,
								  -default => $hour})),
				   td({-align => "left"},
					  popup_menu({-name => "start_min", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $min})),
				   td({-align => "left"},
					  popup_menu({-name => "start_sec", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $sec})),
				   td({-align => "left", -width => '60%'}, '&nbsp;'),
				   ),
				Tr(
				   td({-align => "left", -width => "10%"}, "End Time"),
				   td({-align => "left"},
					  popup_menu({-name => "end_day", -values  => $Apache::SCS::Constants::SCS_DAYS,
								  -default => $day})),
				   td({-align => "left"},
					  popup_menu({-name => "end_month", -values  => $Apache::SCS::Constants::SCS_MONTH_NUMS,
								  -labels  => $Apache::SCS::Constants::SCS_MONTH_NAMES,
								  -default => $month})),
				   td({-align => "left"},
					  popup_menu({-name => "end_year", -values => $Apache::SCS::Constants::SCS_YEARS,
								  -default => $year})),
				   td({-align => "left"},
					  popup_menu({-name => "end_hour", -values => $Apache::SCS::Constants::SCS_HOURS,
								  -default => $hour})),
				   td({-align => "left"},
					  popup_menu({-name => "end_min", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $min})),
				   td({-align => "left"},
					  popup_menu({-name => "end_sec", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $sec})),
				   td({-align => "left", -width => '60%'}, '&nbsp;'),
				   ),
				Tr(
				   td({-align => "left", -width => "10%"}, "Interval (s)"),
				   td({-align => "left", -width =>"90%", -colspan => "7"}, 
					  popup_menu({-name => "interval", -values => \@INTERVALS, -default => "2"})
					  ),
				   ),
				Tr(
				   td({-align => "left", -width => "100%", -colspan => "8"},
					  submit({-name => 'gtm_download', -value => 'Download Track'})),
				   ),
				);

	print end_form(), "\n";

	print br(), br(), br(), br(), br(), br(), hr(), "\n";
	&Apache::SCS::Main::page_footer;
}

sub gtm_download {
	my $config = shift;

	if (!param()) {
		die "Invalid input\n";
	} 

	my $start_time = timegm(param("start_sec"), param("start_min"), param("start_hour"),
							param("start_day"), param("start_month") - 1, 
							param("start_year") - 1900);

	my $end_time = timegm(param("end_sec"), param("end_min"), param("end_hour"),
						  param("end_day"), param("end_month") - 1, 
						  param("end_year") - 1900);

	my $interval = param("interval");
	
	my $filename = param("start_year") . param("start_month") . param("start_day") . param("start_hour") . 
		param("start_min") . param("start_sec");

	print header({ -type => "octet/gtm", -content_disposition => "attachment; filename=ship-gtm-$filename.txt"});
	
	#Connect to SCS Stream
	my $scs = SCSUtil->new();
	$scs->attach($STREAM);

	my ($lat_p, $lon_p) = ($scs->get_re_var_pos('lat'), $scs->get_re_var_pos('lon'));
	$scs->find_time($start_time);

	# Output GTM Header
	print "Version,212\n\r\n\r";
	print "WGS 1984 (GPS),217, 6378137, 298.257223563, 0, 0, 0\n\r\r";
	print "USER GRID,0,0,0,0,0\n\r\n\r";

	# Output tracklogs
	my $rec = $scs->current_record();
	$| = 1;

	my $first = 1;
	
	while ($rec && ($rec->{timestamp} <= $end_time)) {
        if (($rec->{timestamp} - $start_time) % $interval) {
			$rec = $scs->next_record();
			next;
        }
		
        my ($lat, $lon) = ($rec->{vals}->[$lat_p], $rec->{vals}->[$lon_p]);
		
        my $datetime = strftime("%m/%d/%Y,%H:%M:%S", gmtime($rec->{timestamp}));
        print "t,d,$lat,$lon,$datetime,0.00,$first\n\r";

        $first = 0;

        $rec = $scs->next_record();
	}

	# Tracklog color/style
	print "\n\rn,$STREAM,16711680,1\n\r";

	$scs->detach();
}

1;
__END__
