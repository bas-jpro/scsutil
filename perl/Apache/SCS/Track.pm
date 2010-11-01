# SCS/GMT Track plotter
#
# v1.0 JPRO JR83 03/11/2002 Initial Release
#

package Apache::SCS::Track;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(track_setup track_plot);

use strict;
use CGI::Pretty qw(:all *form);
use lib '/nerc/packages/scs/1.0/perl';
use Apache::SCS::Constants;
use Time::Local;
use POSIX qw(strftime);

my $TRACKPLOT = '/nerc/packages/scs/1.0/bin/trackplot.pl';

my %DataSources = (
				   'Ashtec-ADU2' => 'Ashtech GPS',
				   'Trimble'     => 'Trimble DGPS',
				   'Glonass'     => 'Glonass',
				   );

my $DEFAULTSOURCE = 'Trimble';

# Autoflush output
$| = 1;

sub track_setup {
	my $config = shift;

	&Apache::SCS::Main::page_header;

	print h3('JCR Track Plot');

	print start_form({-method => 'post', -action => '/' . $config->{location} . '/plot'});
	
	my @DSvalues = sort keys %DataSources;
 
	print table({-width => '90%', -align => 'center'},
				Tr(
				   td({-width => '20%', -align => 'left'}, 'Data Source'),
				   td({-width => '80%', -align => 'left'},
					  popup_menu({-name => 'source', -values => \@DSvalues,
								  -labels => \%DataSources, -default => $DEFAULTSOURCE})),
				   ),
				Tr(
				   td({-width => '20%', -align => 'left'}, 'Start Time'),
				   td({-width => '80%', -align => 'left'}, time_select('start')),
				   ),
				Tr(
				   td({-width => '20%', -align => 'left'}, 'End Time'),
				   td({-width => '80%', -align => 'left'}, time_select('end')),
				   ),
				Tr(
				   td({-width => '100%', -align => 'center', -colspan => '2'}, '&nbsp;'),
				   ),
				Tr(
				   td({-width => '100%', -align => 'right', -colspan => '2'}, 
					  submit({-name => 'plot', -value => 'Plot Track'})),
				   ),
				);

	print end_form();

	&Apache::SCS::Main::page_footer;
}

sub time_select {
	my $prefix = shift @_;

	# This is Y2K compliant - gmtime returns year-1900
	my @ds = gmtime();

	my $year  = $ds[5]+1900;              
	my $month = sprintf("%02d", $ds[4]+1);
	my $day   = sprintf("%02d", $ds[3]);
	my $hour  = '00'; #sprintf("%02d", $ds[2]);
	my $min   = '00'; #sprintf("%02d", $ds[1]);
	my $sec   = '00'; #sprintf("%02d", $ds[0]);

	return table({-align => 'left'},
				Tr(
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_day', -values  => $Apache::SCS::Constants::SCS_DAYS,
								  -default => $day})),
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_month', -values  => $Apache::SCS::Constants::SCS_MONTH_NUMS,
								  -labels  => $Apache::SCS::Constants::SCS_MONTH_NAMES,
								  -default => $month})),
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_year', -values => $Apache::SCS::Constants::SCS_YEARS,
								  -default => $year})),
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_hour', -values => $Apache::SCS::Constants::SCS_HOURS,
								  -default => $hour})),
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_min', -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $min})),
				   td({-align => "left"},
					  popup_menu({-name => $prefix . '_sec', -values => $Apache::SCS::Constants::SCS_MINSEC,
								  -default => $sec}))
				   )
				);
}

sub track_plot {
	my $config = shift;

	&Apache::SCS::Main::page_header;
	
	print h3("Plotting Track");

	if (!param()) {
		print div({-align => 'center'}, font({-color => 'red', -size => '+3'}, 'SYSTEM ERROR'));
		
		&Apache::SCS::Main::page_footer;
		
		return;
	}
   
	my $source = param('source');

	my %times = ();

	foreach my $prefix (qw(start end)) {
		$times{$prefix} = timegm(param($prefix . '_sec'), param($prefix . '_min'), param($prefix . '_hour'),
								 param($prefix . '_day'), param($prefix . '_month') - 1, param($prefix .'_year') - 1900);
	}

	print br(), 'Starting plot ... ' . scalar(localtime) . "\n";

	my $cmd = "$TRACKPLOT $times{start} $times{end} $source /nerc/packages/scs/plots/track.$source.$times{start}.$times{end}.ps";

	`$cmd`;

	print br(), 'Plot finished ... ' . scalar(localtime) . "\n";

	&Apache::SCS::Main::page_footer;
}

1;
__END__



