# SCS Variable List
#
# v1.0 JPRO JR84 27/02/2003 Initial Release
# v1.2 JPRO JR84 01/03/2003 Added Configurable display rate
#

package Apache::SCS::List;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(list_vals list_head list_body);

use strict;
use lib '/nerc/packages/scs/1.0/lib';
use SCSUtil;
use CGI::Pretty qw( :all *table *Tr *form *frameset);
use POSIX qw(strftime);

sub list_vals {
	my $config = shift;

	if (param('list_conf')) {
#		my @vars = param('vars');
#		list($config, \@vars);
		
		list_frames($config);
	} else {
		# Configure list display
		config_list($config);
	}
}

sub config_list {
	my $config = shift;

	print header(), "\n";
	&Apache::SCS::Main::page_header;

	my @streams = $config->{scs}->list_streams();

	print h3("Configure List Display");

	print start_form({-action => join("/", undef, $config->{location}, 'list'), -method => 'post'});

	foreach (@streams) {
		$config->{scs}->attach($_);

		print font({-color => 'blue', -size => '+1'}, b($config->{scs}->{name}));
		
		# Display Stream Variables
		my $vars = $config->{scs}->vars();
		my @vals = ();
		my %labels = ();

		foreach my $v (@$vars) {
			push(@vals, $config->{scs}->{name} . ":" . $v->{name});
			$labels{$config->{scs}->{name} . ":" . $v->{name}} = $v->{name};
		}
		print checkbox_group(-name => 'vars', -values => \@vals, -columns => '5', -labels => \%labels);

		$config->{scs}->detach();
	}

	print submit({-name => 'list_conf', -value => 'Display'});

	print end_form();

	&Apache::SCS::Main::page_footer;
}

sub list_frames {
	my $config = shift;

	my $qstr = query_string();

	print header(), "\n";
	print "<HTML><HEAD><TITLE>JCR SCS Interface</TITLE></HEAD>";
	
	print start_frameset({-rows => "140,*", -border => 0});
	print frame({-src => join("/", undef, $config->{location}, "list-head?$qstr"), -name => 'list-head', 
				 -marginheight => 0, -hspace => 0, -vspace => 0, -scrolling => 'yes'});
	print frame({-src => join("/", undef, $config->{location}, "list-body?$qstr"), -name => 'list-body', 
				 -marginheight => 0, -hspace => 0, -vspace => 0, -scrolling => 'yes'});
	print end_frameset();

	print "</HTML>";
}

sub list_head {
	my $config = shift;

	my @vars = param('vars');

	print header(), "\n";
	&Apache::SCS::Main::page_header;

	print h3("List Display");

	print start_table({-border => '1', -width => '95%', -align => 'center'});

	# @$vars is list of Stream:var - so count streams
	my $Streams = {};
	foreach (@vars) {
		my ($stream, $var) = split(":", $_, 2);

		$Streams->{$stream}->{vars} = () if (!exists($Streams->{$stream}));

		push(@{ $Streams->{$stream}->{vars} }, $var); 
	}

	# Compute columns sizes
	my $width = int((100 / (scalar(@vars) + 1)) + 0.5);

	# Display table header line 1
	print start_Tr({-width => '100%'});
	print td({-width => "$width%"}, '&nbsp;');

	foreach (sort keys %$Streams) {
		print td({-colspan => scalar(@{ $Streams->{$_}->{vars} }), -align => 'center'}, b($_));
	}

	print end_Tr();

	# Display table header line 2
	print start_Tr({-width => '100%'});
	print td({-align => 'center', -width => "$width%"}, b("Time"));

	foreach my $s (sort keys %$Streams) {
		foreach my $v (@{ $Streams->{$s}->{vars} }) {
			print td({-align => 'center', -width => "$width%"}, b($v));
		}
	}

	print end_Tr();

	print end_table();

	print end_html();
}

sub list_body {
	my $config = shift;
	
	my @vars = param('vars');

	# Display records for the last hour at minute boundaries
	my $current_time = 60 * (int(time() / 60));

	# @$vars is list of Stream:var - so count streams
	my $Streams = {};
	foreach (@vars) {
		my ($stream, $var) = split(":", $_, 2);

		$Streams->{$stream}->{vars} = () if (!exists($Streams->{$stream}));

		push(@{ $Streams->{$stream}->{vars} }, $var); 
	}

	# Compute columns sizes
	my $width = int((100 / (scalar(@vars) + 1)) + 0.5);

	print header({-refresh => '60'});

	print start_html({-bgcolor => '#FFFFFF'});
	print start_table({-border => '1', -width => '95%', -align => 'center'});

	for (my $t=0; $t<=3600; $t += 60) {

		# Get Records
		foreach my $s (sort keys %$Streams) {
			$config->{scs}->attach($s);
			
			# Work backwards
			$config->{scs}->find_time($current_time - $t);

			$Streams->{$s}->{record} = $config->{scs}->next_record();
			
			$config->{scs}->detach();
		}

		# Display Data
		print start_Tr({-width => '100%'});
		print td({-align => 'left', -width => "$width%"}, strftime("%d/%m/%Y %T", gmtime($current_time - $t)));
		
		foreach my $s (sort keys %$Streams) {
			$config->{scs}->attach($s);
			
			my @ps = $config->{scs}->get_vars_pos(@{ $Streams->{$s}->{vars} });
			
			# Check data age
			my $color = "#FFFFFF";
			# More than 5 minutes out
			if (abs($Streams->{$s}->{record}->{timestamp} - ($current_time - $t)) > 300) {
				$color = "#FF0000";
			}
 
			foreach my $p (@ps) {
				print td({-align => 'left', -width => "$width%", -bgcolor => $color}, $Streams->{$s}->{record}->{vals}->[$p]);
			}
			
			$config->{scs}->detach();
		}

		print end_Tr();
	}

	print end_table();

	&Apache::SCS::Main::page_footer;
}

1;
__END__
