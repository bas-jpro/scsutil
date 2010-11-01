#!/packages/perl/5.8.0/bin/perl -w
# SCS Commands for Tcl/Tk
#
# v1.0 JPRO JCR 03/02/2004 Initial Release
#

use Tcl;
use Tcl::Tk;
use lib '/packages/scs/current/lib';
use SCSUtil;
use Data::Dumper;

use strict;

my @SCSs = ();

my $interp = new Tcl::Tk;

# Create SCS commands
$interp->CreateCommand("scs", \&scs_cmd, "", \&delete_scs);

foreach (@ARGV) {
	$interp->EvalFile($_);
}

$interp->MainLoop;

0;

sub scs_cmd {
	my ($clientData, $interp, @args) = @_;

	my ($cmd_name, $sub_cmd, @cmd_args) = @args;

	my $res = '';

	my $cmd = '$res = scs_' . $sub_cmd . '($interp, @cmd_args)';

	eval $cmd;

	if ($@) {
		die "Error: invalid command scs $sub_cmd ($@)\n";
	}

	return undef;
}

sub delete_scs {
	my $clientData = shift;
}

sub scs_streams { 
	my ($interp, @args) = @_;

	my $scs = SCSUtil->new();

	$interp->ResetResult();
	foreach ($scs->list_streams()) {
		$interp->AppendElement($_);
	}
}

sub scs_vars {
	my ($interp, @args) = @_;

	my $scs = SCSUtil->new();
	$scs->attach($args[0]);

	$interp->ResetResult();
	foreach (@{ $scs->vars() }) {
		$interp->AppendElement($_->{name});
	}

	$scs->detach;
}

# Attach to a stream 
# Return SCS index
sub scs_new {
	my ($interp, @args) = @_;

	my $idx = 0;

	while ($SCSs[$idx]) {
		$idx++;
	}

	$SCSs[$idx] = SCSUtil->new();

	$SCSs[$idx]->attach($args[0]);

	$interp->SetResult($idx);
}

sub scs_next_record {
	my ($interp, @args) = @_;

	my $scs = $SCSs[$args[0]];

	my $tcl_list = $args[1];

	my @vars = $scs->get_vars_pos(@args[2..$#args]);

	my $rec = $scs->next_record();

	# Return 0 if no record, 1 otherwise
	# $tcl_list set to a list - timestamp var1 var2 ....
	if ($rec) {
		$interp->Eval("set $tcl_list $rec->{timestamp}");

		foreach (@vars) {
			$interp->Eval("lappend $tcl_list " . ($rec->{vals}->[$_] + 0));
		}

		$interp->SetResult(1);
	} else {
		$interp->SetResult(0);
	}

}

sub scs_find_time {
	my ($interp, @args) = @_;

	my $scs = $SCSs[$args[0]];

	$scs->find_time($args[1]);

	$interp->SetResult(1);
}

sub scs_start_time {
	my ($interp, @args) = @_;

	my $scs = SCSUtil->new();

	$scs->attach($args[0]);

	my $rec = $scs->next_record();

	$interp->SetResult($rec->{timestamp});

	$scs->detach;
}

sub scs_end_time {
	my ($interp, @args) = @_;

	my $scs = SCSUtil->new();

	$scs->attach($args[0]);

	my $rec = $scs->last_record();

	$interp->SetResult($rec->{timestamp});

	$scs->detach;
}
