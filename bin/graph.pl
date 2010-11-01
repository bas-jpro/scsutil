#!/packages/perl/5.8.0/bin/perl -w
# SCS Graph Plotting 
#
# v1.0 JPRO JCR 02/01/2004 Initial Release
#

use strict;
use lib '/packages/scs/current/lib';
use SCSUtil;

use Tk;
use Tk::Graph;

# Setup main Window
my $main = MainWindow->new(-title => "SCS Graph Control");
my $new_time_btn = $main->Button(-text => "New Time Series Graph", -command => [\&new_time_graph_setup, $main]);

$new_time_btn->pack(-side => 'top', -fill => 'x');

my $quit_f = make_quit_btn($main, 'Quit');

$main->geometry('300x200');

MainLoop;

0;

sub destroy_window {
	my $win = shift;

	$win->destroy;
}

sub make_quit_btn {
	my ($win, $txt) = @_;

	my $quit_f = $win->Frame(-borderwidth => 1, -relief => 'raised');
	my $quit_btn = $quit_f->Button(-text => "Quit", -command => [\&destroy_window, $win]);
	
	$quit_f->pack(-side => 'bottom', -fill => 'x');
	$quit_btn->pack(-side => 'right'); 
	
	return $quit_f;
}

sub make_text_entry {
	my ($win, $label, $var_ref) = @_;

	my $f = $win->Frame(-borderwidth => 1, -relief => 'raised');
	$f->pack(-side => 'top', -fill => 'x');

	my $f_l = $f->Label(-text => $label, -justify => 'left', -foreground => 'blue', -anchor => 'nw', -width => length($label)+5);
	$f_l->pack(-side => 'left');

	my $f_e = $f->Entry(-textvariable => $var_ref, -relief => 'sunken', -background => 'white');
	$f_e->pack(-side => 'left', -fill => 'x', -expand => 1);

	return $f;
}

sub make_str_frame {
	my ($win, $label, $str_ref, $var_ref) = @_;

	my $scs = SCSUtil->new();
	my @streams = $scs->list_streams();

	my $f = $win->Frame(-borderwidth => 1, -relief => 'raised');
	$f->pack(-side => 'top', -fill => 'x');

	# Stream selection frame
	my $f_s = $f->Frame(-borderwidth => 0, -relief => 'flat');
	$f_s->pack(-side => 'top', -fill => 'x');

	my $f_s_l = $f_s->Label(-text => $label, -justify => 'left', -anchor => 'nw', -width => 15);
	$f_s_l->pack(-side => 'left');

	my $f_s_om = $f_s->Optionmenu(-options => \@streams, -relief => 'flat', -variable => $str_ref);
	$f_s_om->pack(-side => 'left', -fill => 'x', -expand => 1);

	# Variable selection frame
	my $f_v = $f->Frame(-borderwidth => 0, -relief => 'flat');
	$f_v->pack(-side => 'top', -fill => 'x');

	my $f_v_l = $f_v->Label(-text => 'Variable', -justify => 'left', -anchor => 'nw', -width => 15);
	$f_v_l->pack(-side => 'left');

	my $f_v_om = $f_v->Optionmenu(-options => [], -relief => 'flat', -variable => $var_ref);
	$f_v_om->pack(-side => 'left', -fill => 'x', -expand => 1);

	# Configure variable selection command
	$f_s_om->configure(-command => [\&set_vars, $f_v_om, $scs ]);

	# Setup initial variables
	set_vars($f_v_om, $scs, $streams[0]);

	return $f;
}

sub set_vars {
	my ($var_menu, $scs, $stream) = @_;

	$scs->attach($stream);

	my @names = ();
	foreach (@{ $scs->vars() }) {
		push(@names, $_->{name});
	}

	$var_menu->configure(-options => \@names);

	$scs->detach;
}

sub new_time_graph_setup {
	my $main = shift;

	my $graph_cfg = {
		title    => '',
		stream   => '',
		variable => '',
	};

	my $setup_win = $main->Toplevel(-title => 'Time Series Graph Setup');
	$setup_win->geometry('400x400');

	my $btn_f = make_quit_btn($setup_win, 'Cancel');

	my $draw_btn = $btn_f->Button(-text => "Draw", -command => [\&draw_time_graph, $main, $setup_win, $graph_cfg]);

	$draw_btn->pack(-side => 'left', -fill => 'x');

	make_text_entry($setup_win, 'Graph Title', \$graph_cfg->{title} );
	
	my $str_f = make_str_frame($setup_win, 'Stream 1', \$graph_cfg->{stream}, \$graph_cfg->{variable});
}

sub draw_time_graph {
	my ($main, $setup_win, $graph_cfg) = @_;

	# Get rid of setup window
	destroy_window($setup_win);

	my $graph_win = $main->Toplevel(-title => 'Time Series Graph');
	$graph_win->geometry('800x300');

	my $btn_f = make_quit_btn($graph_win, 'Quit');

	my $graph = $graph_win->Graph(
								  -type       => 'Line',
								  -title      => $graph_cfg->{title},
								  -background => 'white',
								  -look       => 60,
								  -padding    => [50, 20, -30, 50],
								  -wire           => "#d2e8e4",
								  );

	$graph->pack(-side => 'top', -fill => 'both', -expand => 1);

	my $scs = SCSUtil->new();
	$scs->attach($graph_cfg->{stream});
	
	my $var_pos = $scs->get_re_var_pos($graph_cfg->{variable});

	while (my $rec = $scs->next_record()) {
		$graph->set({
			$graph_cfg->{variable} => $rec->{vals}->[$var_pos],
		});
	}
}

