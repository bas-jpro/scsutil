# General module for SCS Web Interface
#
# v1.0 JPRO JCR JR76 22/07/2002 Initial Release
#

package SCSWeb;

use strict;
use CGI::Pretty;

sub new {
	my $class = shift;

	my $web = bless {
		q       => new CGI,
		version => 'v1.0 JPRO 22/07/2002',
	}, $class;

	return $web;
}

sub content_header {
	my $web = shift;

	return "Content-type: text/html\n\n";
}

sub page_header {
	my $web = shift;

	my $q = $web->{q};

	my $hdr = $q->start_html({ -title => "JCR SCS Interface", 
							   -bgcolor => '#FFFFFF'});

	$hdr .= $q->table({-width => '100%', -bgcolor => '#000000'},
					  $q->Tr({-width => '100%', -align => 'center'},
							 $q->td($q->font({-size => '+2', 
											  -color => '#FFFFFF'},
											 "JCR SCS Interface"))));

	$hdr .= $q->br();

	return $hdr;
}

sub page_footer {
	my $web = shift;

	my $q = $web->{q};

	my $ftr = $q->br() . $q->hr({-shade => 1});
	$ftr .= $q->address($web->{version});
	$ftr .= $q->end_html();
	
	return $ftr;
}

1;
__END__
