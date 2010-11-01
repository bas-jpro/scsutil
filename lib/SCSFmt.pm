# SCS '[m]fmt' file Module for SCS versions of RVS utilities
# 
# v1.0 JPRO JCR JR51 10/08/2000 Initial release
#
# NB [m]fmt files have a defined keyword order which must be followed
# this is the behaviour of mutli / anylist etc
#

package SCSFmt;
use strict;

use File::Basename;

sub new {
	my $class = shift @_;

	my $scsfmt = bless {
		path => '/nerc/packages/scs/1.0/fmt',
	}, $class;

	return $scsfmt;
}

sub changepath {
	my ($scsfmt, $path) = @_;

	return unless $path;

	$scsfmt->{path} = $path;
}

# Read a [m]fmt type file 
# checking the idstr against the first line
sub read {
	my ($scsfmt, $file, $idstr) = @_;

	my $fname = "$scsfmt->{path}/$file";
	$fname = $file if $file =~ /^\//;

	open(FF, "< $fname") or die basename($0) . ": unable to read $fname\n";

	my $line = <FF>;
	chomp($line);

	if ($line !~ /^$idstr$/) {
		die basename($0) . ": list description file has wrong format " .
			"expecting 'MUTLI FILE'\n";
	}

	my %config;

	# Always start with TITLE
	$line = <FF>;
	if ($line =~ /^TITLE:\s*([0-9]+)/) {
		$config{TITLE} = "";
		for (my $i=0; $i<$1; $i++) {
			$config{TITLE} .= <FF>;
			chomp($config{TITLE});
		}
	} else {
		die basename($0) . ": invalid number of title lines (TITLE)\n"; 
	}

	# Next is INTERVAL
	$line = <FF>;
	if ($line =~ /^INTERVAL:\s*([0-9]+)([smh]?)/) {
		$config{INTERVAL} = $1;
		$config{interval_units} = $2 || 's';
	} else {
		die basename($0) . ": invalid print interval (INTERVAL)\n";
	}

	# Next is FILES
	$line = <FF>;
	if ($line =~ /^FILES:\s*([1-9]+)/) {
		$config{FILES} = $1;
		$config{STREAM} = ();
	} else {
		die basename($0) . ": invalid number of files (FILES)\n";
	}
	
	# Now each STREAM
	for (my $s=0; $s<$config{FILES}; $s++) {
		$line = <FF>;
		my %stream;
		if ($line =~ /^STREAM:\s*([^ \n]+)/) {
			$stream{name} = $1;
			
			# First VARS
			$line = <FF>;
			if ($line =~ /^VARS:\s*([1-9][0-9]*)/) {
				$stream{num_vars} = $1;
				$stream{VARS} = ();

				for (my $v=0; $v<$stream{num_vars}; $v++) {
					$line = <FF>;
					chomp($line);
					my @fs = split(":", $line);

					# Error check input
					if ($fs[1] !~ /[ifne]/) {
						die basename($0) . ": bad treatment qualifier\n";
					}

					if ($fs[2] !~ /[1-9][0-9]*/) {
						die basename($0) . ": bad format line\n";
					}

					push(@{ $stream{VARS} }, \@fs);

					if ((scalar(@fs) != 4) && (scalar(@fs) != 6)) {
						die basename($0) . ": bad format line\n";
					}
				}
			} else {
				die basename($0) . ": bad data file name or wrong no. of " .
					"variables (STREAM/VARS)\n";
			}
		} else {
			die basename($0) . ": bad data file name or wrong no. of " .
				"variables (STREAM/VARS)\n";
		}

		push(@{ $config{STREAM} }, \%stream);
	}

	close(FF);

	return \%config;
}

sub interval {
	my ($scsfmt, $config) = @_;

	my $int = $config->{INTERVAL};

	$int *= 60    if $config->{interval_units} eq 'm'; # Minutes
	$int *= 3600  if $config->{interval_units} eq 'h'; # Hours
	$int *= 86400 if $config->{interval_units} eq 'd'; # Days

	return $int;
}

1;
__END__
