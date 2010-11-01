#!/packages/perl/5.8.0/bin/perl -w
# SCS Graph Plotter
#
# v1.0 JPRO JCR 03/01/2004 Initial Release 
#

use Tcl;
use Tcl::Tk qw(:misc);
use lib '/packages/scs/current/lib';
use SCSUtil;
use strict;

# Create TCL interpreter
my $interp = new Tcl::Tk;

# Load BLT extension
$interp->Eval('package require BLT');

# Setup Main Window
$interp->Eval('wm title . "SCS Graph Control"');
$interp->Eval('wm geometry . 300x200');

my $new_time_btn = $interp->button('.time_btn', -text => 'New Time Series Graph', -command => \&new_time_graph_setup); 
$new_time_btn->pack(-side => 'top', -fill => 'x');
 
make_quit_btn($interp, '.', 'Quit');

$interp->MainLoop;

0;

sub make_quit_btn {
	my ($interp, $win, $txt) = @_;

	my $join = ($win eq '.') ? '' : '.';

	my $quit_f = $interp->frame($win . $join . 'quit_f', -relief => 'raised', -borderwidth => 1);
	$quit_f->pack(-side => 'bottom', -fill => 'x');

	my $quit_btn = $interp->button($win . $join . 'quit_f.quit', -text => $txt, -command => "destroy $win");
	$quit_btn->pack(-side => 'right');
}

sub make_text_entry {
	my ($interp, $win, $txt) = @_;

	my $join = ($win eq '.') ? '' : '.';
	my $cnt = 0;
	my $frame = $win . $join . "f_" . sprintf("%06d", $cnt);

	while ($interp->Eval("info commands $frame")) {
		$cnt++;
		$frame = $win . $join . "f_" . sprintf("%06d", $cnt);
	}

	my $f = $interp->frame($frame, -relief => 'raised', -borderwidth => 1);
	$f->pack(-side => 'top', -fill => 'x');

	my $f_t = $interp->label($frame . ".l", -text => $txt, -anchor => 'nw', -width => length($txt) + 5);
	$f_t->pack(-side => 'left');

	my $f_e = $interp->entry($frame . ".e", -relief => 'sunken', -background => 'white');
	$f_e->pack(-side => 'left', -fill => 'x', -expand => 1);
}

sub new_time_graph_setup {

	# Generate a unique name - should be a better way
	my $wcnt = 0;
	my $toplevel = '.graph_setup_' . sprintf("%06d", $wcnt);

	while ($interp->Eval("winfo exists $toplevel")) {
		$wcnt++;
		$toplevel = '.graph_setup_' . sprintf("%06d", $wcnt);
	}

	# Create window
	$interp->toplevel($toplevel);
	$interp->Eval('wm title ' . $toplevel . ' "Time Series Graph Setup"; wm geometry ' . $toplevel . ' 400x400');

	make_quit_btn($interp, $toplevel, 'Cancel');

	my $draw_btn = $interp->button($toplevel . '.quit_f.draw', -text => 'Draw', -command => \&draw_time_graph);
	$draw_btn->pack(-side => 'left');

	make_text_entry($interp, $toplevel, 'Graph Title');
}
