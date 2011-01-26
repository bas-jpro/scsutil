# SCS Variable List
#
# v1.0 JPRO JR84 27/02/2003 Initial Release
# v1.2 JPRO JR84 01/03/2003 Added Configurable display rate
#

package Apache::SCS::Download;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(download_data);

use strict;
use lib '/nerc/packages/scs/1.0/lib';

use SCSUtil;
use CGI::Pretty qw( :all *table *Tr *form *frameset);
use POSIX qw(strftime INT_MAX);
use Data::Dumper;
use JSON::XS;

use lib '/packages/dps/current/perl';
use DPS::Engine;
use DPS::Log;
use DPS::Control::Chain;

sub download_data {
	my $config = shift;

	my $stime = param('stime') || undef; # Optional start time in Unix epoch
	my $period = param('period') || undef; # Optional period in seconds
	
	my $output_type = param('output') || "json"; # Optional output type - default is json
	
	# Additional request types
	
	# Interval - if the interval parameter is set then the query will be passed to the
	#  DPS engine
	my $interval = param('interval') || undef;
	
	# StreamStatus
	my $streamstatus = param('streamstatus') || undef;
	
	
	# Retrieve Post variables
	my @vars = param('vars'); # These store the specific stream request variables
	my $streams = {};
	foreach (@vars) {
		my ($stream, $var) = split(":", $_, 2);
		$streams->{$stream}->{vars} = () if (!exists($streams->{$stream}));
		push(@{ $streams->{$stream}->{vars} }, $var); 
	}
	
	
	if($output_type eq "json") {
		# Overall JSON header
		# Output JSON type via HTTP Header

		#$config->{request}->content_type('application/json');
		$config->{request}->content_type('application/json');
		$config->{request}->send_http_header;
	
		print '{"timestamp":'.time(); # Wrapper for multiple stream return
		
		if($interval) {
			output_interval_via_json($config, $stime, $period, $interval, $streams);
		} else {
			output_via_json($config, $stime, $period, $streams);	
		}
		
		if($streamstatus && $streamstatus eq "yes") {
			output_streamstatus_via_json($config);
		}
		
		print "}";
	}
}

sub output_streamstatus_via_json {
	my $config = shift;
	
	print ', "streamstatus": ';
	
	my @streams = sort $config->{scs}->list_streams();

	my @ss = ();
	foreach my $s (@streams) {
		$config->{scs}->attach($s);
		my $rec = $config->{scs}->last_record();
		$config->{scs}->detach();

		push (@ss, { name => $s, time => ($rec ? $rec->{timestamp} : undef) });
	}

	print encode_json \@ss;
		
	
	print "";
}

sub output_via_json {
	my $config = shift;
	my $stime = shift;
	my $period = shift;
	my $streams = shift;

	# Output JSON type via HTTP Header
		
	# Get Records
	# The json_encode function is used for individual line elements. The streams and stream wrappers are
	# being added manually to avoid the case when there is a lot of a data and we don't want to combine
	# it into a giant array in memory. This script spits out each json entry line by line. This means
	# if the script terminates early it'll output malformed json.
	
	print ', "streams":['; # Wrapper for multiple stream return
	
	my @keys = sort keys %{$streams};
	
	# Process each stream one at a time
	foreach my $s (@keys) {
		eval { $config->{scs}->attach($s); };
		if ($@) {
			print encode_json { stream => $s, error => "Failed to attach $s - no stream" };
		} else {
		
			print '{"stream":"'.$s.'",';
			
			# Retrieve list of stream variable indexes. This is used to limit the results
			# to the selected variables
			my @ps = $config->{scs}->get_vars_pos(@{ $streams->{$s}->{vars} });
			my $vars = $config->{scs}->vars();
			
			# Include units in JSON
			my $units = {};
			foreach my $v (@$vars) {
				$units->{$v->{name}} = $v->{units};
			}

			print '"units":';
			print encode_json($units);
			print ',';
			
			# Begin JSON section for data
			print '"data":[';
			
			# Process return for a single time entry
			if(!$period) {
				
				my $rec;
				if(!$stime) {
					$stime = time();
				}
				
				# Get the record for the specified timestamp 
				# Special value 0 means give me the latest timestamp available
				if($stime eq "last") {
					$rec = $config->{scs}->last_record();
				} else {
					$config->{scs}->find_time($stime);
					$rec = $config->{scs}->next_record();				
				}
				
				my $smallrec = {};
				
				my $j = 0;
				foreach my $p (@ps) {
					$smallrec->{$streams->{$s}->{vars}->[$j]} = $rec->{vals}->[$p];
					$j++;
				}
				print encode_json { timestamp => $rec->{timestamp}, vars => $smallrec };
				
			} 
			# Process return for a time range
			else {
				
				# Limit period to one day of results
				if($period > 24*60*60) {
					$period = 24*60*60;
				}
				
				# Set the start time to $period seconds in the past if it's not
				# been provided
				if(!$stime) {
					#my $rec = $config->{scs}->last_record();
					$stime = time() - $period; # $rec->{timestamp} - $period;
				}
				
				# Set end time
				my $etime = INT_MAX; # End of Unix EPOCH		
				$etime = $stime + $period;
				
				# Set initial time
				$config->{scs}->find_time($stime);
				
				#print "<hr/>Time: ".$stime." ".$etime." ".$period."<hr/>";
				
				# Get first record
				my $rec = $config->{scs}->current_record();	
				while ($rec->{timestamp} <= $etime) {

					my $smallrec = {};
				
					my $j = 0;
					foreach my $p (@ps) {
						$smallrec->{$streams->{$s}->{vars}->[$j]} = $rec->{vals}->[$p];
						$j++;
					}
					
					print encode_json { timestamp => $rec->{timestamp}, vars => $smallrec };
					
					$rec = $config->{scs}->next_record();
					last if !$rec;	
					print "," if $rec->{timestamp} <= $etime;
				}	
			}
			
			$config->{scs}->detach();
			
			print "]}"; # Close wrapper for current stream
		}
		
		
		print "," unless $keys[@keys-1] eq $s; # adds a seperator between streams
	}
	
	print "]"; # Close wrapper for multiple streams.
}

sub output_interval_via_json {

	my ($config, $stime, $period, $interval, $streams) = @_;
	
	
	# Limit period to one day of results
	if($period > 24*60*60) {
		$period = 24*60*60;
	}
	
	# Set the start time to $period seconds in the past if it's not
	# been provided
	if(!$stime) {
		$stime = time() - $period;
	}
	
	# Set end time
	my $etime = INT_MAX; # End of Unix EPOCH		
	$etime = $stime + $period;
				
	# DPS Activation. Go!	
		
	# Get Records
	# The json_encode function is used for individual line elements. The streams and stream wrappers are
	# being added manually to avoid the case when there is a lot of a data and we don't want to combine
	# it into a giant array in memory. This script spits out each json entry line by line. This means
	# if the script terminates early it'll output malformed json.
	
	print ', "streams":['; # Wrapper for multiple stream return
	
	my @keys = sort keys %{$streams};
	
	# Process each stream one at a time
	foreach my $stream (@keys) {
		my $chain = DPS::Control::Chain->new(); 

		# Input
		my $input_params = {};
		$input_params->{'var'} = [];
		foreach my $var(@{$streams->{$stream}->{vars}}) {
			push @{$input_params->{'var'}}, {'out' => $var, 'in' => $var};
		}
		$input_params->{'stream'} = $stream;
		$chain->add_input('SCSIn', 'inputstream', $input_params);

		# Filter
		my $filter_params = {};
		$filter_params->{'interval'} = $interval;
		$chain->add_filter('Interval', 'main', $filter_params);

		# Output
		$chain->set_output('JSON', 'final', {'stream' => $stream});

		# Set chaining
		$chain->chain_module_onto_from('main', 'inputstream');
		$chain->chain_module_onto_from('final', 'main');
		
		###########################################################################################################

		my $dps = DPS::Engine->new();
		
		DPS::Log::set_level(0);
		$dps->initialize_from_chain($chain->get_chain());

		my $vars = $dps->{output}->get_vars();
		
		$dps->set_main($stime, $etime);
		$dps->run(''); # This will output in JSON for an individual stream
	}
	
	print "}"; # Close wrapper for multiple streams.
}

1;
__END__
