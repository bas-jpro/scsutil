# Main Handler for SCS Web Interface
#
# v1.0 JPRO JCR JR76  22/07/2002 Initial Release
# v1.1 JPRO JCR JR83  03/11/2002 Added track plotting capability
# v1.3 JPRO JCR JR134 16/11/2005 Added GTM download capability
# v1.4 JPRO JCR JR195 24/11/2009 Added JSON output of SCS
# 
# $Id: Main.pm 589 2009-12-05 16:47:35Z jpro $
#

package Apache::SCS::Main;

use strict;
use lib '/packages/scs/1.0/lib';
#use lib 'E:/scs/scs/lib';

use SCSUtil;
use Apache::SCS::Track;
use Apache::SCS::Constants;
use Apache::SCS::List;
use Apache::SCS::GTM;
use Apache::SCS::Download;

use CGI::Pretty qw( :all *table *Tr *form);
use Apache2::Const -compile => qw(:common :methods);
use Time::Local;
use POSIX qw(strftime INT_MAX);
use JSON::XS;

my $VERSION = "v1.4 JPRO 24/11/2009";
# Download module added by DACON 01/01/2011

sub handler : method {
	my ($class, $r) = @_;

	my @ps = split("/", $r->path_info);

	# Useful structure to pass to subroutines
	my $config = {
		request  => $r,
		scs      => SCSUtil->new(),
		location => (split("/", $r->uri))[1],
		path_info => \@ps,
	};

  CASE: {
	  $_ = $config->{path_info}->[1];

	  /^info$/         and do { stream_info($config);  last CASE; };
	  /^show$/         and do { show_streams($config); last CASE; };
	  /^track$/        and do { track_setup($config);  last CASE; };
	  /^plot$/         and do { track_plot($config);   last CASE; };
	  /^list$/         and do { list_vals($config);    last CASE; };
	  /^list-head$/    and do { list_head($config);    last CASE; };
	  /^list-body$/    and do { list_body($config);    last CASE; };
	  /^gtm$/          and do { gtm_setup($config);    last CASE; };
	  /^gtm-download$/ and do { gtm_download($config); last CASE; };
	  /^json$/         and do { json($config);         last CASE; };
	  /^download$/     and do { download_data($config);last CASE; };
	  
	  show_streams($config);
  }

	return Apache2::Const::OK;
}

sub show_streams {
	my $config = shift;

	my @streams = sort $config->{scs}->list_streams();

	my $refresh = $config->{path_info}->[2];

	if ($refresh) {
		print header({-refresh => "'$refresh'"}), "\n";
	} else {
		print header(), "\n";
	}

	&page_header;
	print start_table({-border => undef, -width => '95%', -align => 'center'});

	print Tr(
			 td({-width => '10%', -align => 'center'}, b("Name")),
			 td({-width => '20%', -align => 'center'}, b("Start")),
			 td({-width => '20%', -align => 'center'}, b("Last data")),
			 td({-width => '10%', -align => 'center'}, b("Name")),
			 td({-width => '20%', -align => 'center'}, b("Start")),
			 td({-width => '20%', -align => 'center'}, b("Last data"))
			 );

	print start_Tr();

	my $col = 0;
	foreach (@streams) {
		$config->{scs}->attach($_);
		
		my $rec = $config->{scs}->next_record();
		my $start = "-- No Data --";
		$start = $config->{scs}->time_str($rec->{timestamp}) if 
			$rec->{timestamp};
		
		$rec = $config->{scs}->last_record();
		my $end = "-- No Data --";
		$end = $config->{scs}->time_str($rec->{timestamp}) if 
			$rec->{timestamp};
		
		my $name = $config->{scs}->{name};

		print td({-width => '10%', -align => 'left'}, 
				 a({-href => "/$config->{location}/info/$name"}, $name));
		print td({-width => '20%', -align => 'center'}, $start);
		print td({-width => '20%', -align => 'center'}, $end);
		
		$col++;
		if ($col == 2) {
			$col = 0;
			print end_Tr(), start_Tr();
		}
		
		$config->{scs}->detach();
	}

	if ($col == 1) {
		print td({-width => '10%', -align => 'left'}, '&nbsp;');
		print td({-width => '20%', -align => 'center'}, '&nbsp;');
		print td({-width => '20%', -align => 'center'}, '&nbsp;');
	}
	
	print end_Tr();

	print end_table();

	print br(), br();

	if ($refresh) {
		print a({-href => "/$config->{location}/show"}, "No Refresh");
	} else {
		print a({-href => "/$config->{location}/show/1s"}, "Auto Refresh");
	}

	&page_footer;
}

sub json {
	my $config = shift;
	my ($stream, $tstamp) = (@{$config->{path_info}})[2,3];

	$config->{request}->content_type('application/json');
	#$config->{request}->send_http_header;

	# List all streams if none given
	if (!$stream) {
		my @streams = sort $config->{scs}->list_streams();

		my @ss = ();
		foreach my $s (@streams) {
			$config->{scs}->attach($s);
			my $rec = $config->{scs}->last_record();
			$config->{scs}->detach();

			push (@ss, { name => $s, time => ($rec ? $rec->{timestamp} : undef) });
		}

		print encode_json \@ss;
		return;
	}
	
	eval { $config->{scs}->attach($stream); };
	if ($@) {
		print encode_json { error => "Failed to attach $stream - no stream" };
		return;
	}

	my $vars = $config->{scs}->vars();
	my $rec = $config->{scs}->last_record();
	$rec = $config->{scs}->find_time($tstamp) if $tstamp;

	my $idx = 0;

	foreach my $v (@$vars) {
		$v->{value} = $rec->{vals}->[$idx++];
	}

    print encode_json { stream => $stream, timestamp => $rec->{timestamp}, vars => $vars };
}

sub stream_info { 
	my $config = shift;

	my ($stream, $refresh, $tstamp) = (@{$config->{path_info}})[2,3,4];

	$tstamp = process_request($config, $stream) if param();

	if ($refresh) {
		print header({-refresh => $refresh}), "\n";
	} else {
		print header(), "\n";
	}

	&page_header;
	
	$config->{scs}->attach($stream);

	my $vars = $config->{scs}->vars();

	my $rec = $config->{scs}->last_record();
	$rec = $config->{scs}->find_time($tstamp) if $tstamp;

	print h3("Stream: ", font({-color => 'blue'}, $stream) . 
			 font({-color => '#000000'}, " at ") . 
			 font({-color => 'blue'}, scalar gmtime($rec->{timestamp})));

	print start_table({-border => undef, -width => '95%', -align => 'center'});
	
	print Tr(
			 td({-width => '10%', -align => 'center'}, b("Variable")),
			 td({-width => '10%', -align => 'center'}, b("Units")),
			 td({-width => '30%', -align => 'center'}, b("Last value")),
			 td({-width => '10%', -align => 'center'}, b("Variable")),
			 td({-width => '10%', -align => 'center'}, b("Units")),
			 td({-width => '30%', -align => 'center'}, b("Last value"))
			 );

	my ($col, $idx) = 0;

	print start_Tr();

	foreach (@$vars) {
		my $val = "-- No Data --";
		$val = $rec->{vals}->[$idx] if $rec->{vals};

		print td({-width => '10%', -align => 'left'}, b($_->{name}));
		print td({-width => '10%', -align => 'left'}, $_->{units});
		print td({-width => '30%', -align => 'center'}, $val);

		$col++;
		if ($col == 2) {
			$col = 0;
			print end_Tr(), start_Tr();
		}
	
		$idx++;
	}

	if ($col == 1) {
		print td({-width => '10%', -align => 'left'}, '&nbsp;');
		print td({-width => '10%', -align => 'center'}, '&nbsp;');
		print td({-width => '30%', -align => 'center'}, '&nbsp;');
	}

	print end_Tr(), end_table(), br(), br();

	if ($refresh) {
		print a({-href => "/$config->{location}/info/$stream"}, "No Refresh");
	} else {
		print a({-href => "/$config->{location}/info/$stream/1s"}, 
				"Auto Refresh");
	}

	print h3("Jump to time");
	print start_form({-action => "/$config->{location}/info/$stream",
					  -method => "post"});

	# This is Y2K compliant - gmtime returns year-1900
	my @ds = gmtime($rec->{timestamp});

	my $year  = $ds[5]+1900;              
	my $month = sprintf("%02d", $ds[4]+1);
	my $day   = sprintf("%02d", $ds[3]);
	my $hour  = sprintf("%02d", $ds[2]);
	my $min   = sprintf("%02d", $ds[1]);
	my $sec   = sprintf("%02d", $ds[0]);

	print table({-align => 'left'},
				Tr(
				   td({-align => "left"},
					  popup_menu({-name => "day", -values  => $Apache::SCS::Constants::SCS_DAYS,
								  -default => $day})),
				   td({-align => "left"},
					  popup_menu({-name => "month", -values  => $Apache::SCS::Constants::SCS_MONTH_NUMS,
								  -labels  => $Apache::SCS::Constants::SCS_MONTH_NAMES,
								  -default => $month})),
				   td({-align => "left"},
					  popup_menu({-name => "year", -values => $Apache::SCS::Constants::SCS_YEARS,
								  -default => $year})),
				   td({-align => "left"},
					  popup_menu({-name => "hour", -values => $Apache::SCS::Constants::SCS_HOURS,
								  -default => $hour})),
				   td({-align => "left"},
					  popup_menu({-name => "min", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $min})),
				   td({-align => "left"},
					  popup_menu({-name => "sec", -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $sec}))
				   ),
				Tr(
				   td({-align => 'right', -colspan => '6'},
					  submit({-name => 'goto_time', -value => 'Goto Time'}))
				   )
				);

	print end_form(), "\n";

	print p(), br(), br();
	print div({-align => 'center'}, a({-href => "/$config->{location}/show"},
									  "Show all streams"));
	&page_footer;

}

sub process_request {
	my ($config, $stream) = @_;

	if (param("goto_time")) {
		my $tstamp = timegm(param("sec"), param("min"), param("hour"),
							param("day"), param("month") - 1, 
							param("year") - 1900);

		return $tstamp;
	}

	return undef;
}

sub page_header {
	print start_html({ -title => "JCR SCS Interface", -bgcolor => '#FFFFFF'});
	print table({-width => '100%', -bgcolor => '#000000'},
				Tr({-width => '100%', -align => 'center'},
				   td(font({-size => '+2', -color => '#FFFFFF'},
						   "JCR SCS Interface"))
				   )
				);
}

sub page_footer {
	print address($VERSION), end_html();
}

1;
__END__

