# SCS Graph Plotter
#
# v1.0 JPRO JCR 03/01/2004 Initial Release
# v2.0 JPRO JCR 06/01/2004 Added multiple vars/graph
#

# Import BLT commands 
package require BLT
namespace import blt::*

wm title . "SCS Graph Control"
wm geometry . 300x200

frame .quit_f -relief raised -borderwidth 1
pack .quit_f -side bottom -fill x 

button .quit_f.quit -text "Quit" -underline 0 -command { destroy "." }
pack .quit_f.quit -side right

button .new_time_graph -text "New Time Series Graph" -command "new_time_graph_setup"
pack .new_time_graph -side top -fill x

set COLORS [list blue red black brown orange green cyan] 
set STREAMS [scs streams]
set NUMPTS 3600

proc new_time_graph_setup { } {
	# Set defaults 

	set arrayvar [new_array "graph_cfg"]
		
	global $arrayvar

	set ${arrayvar}(title) "Default Title"
	set ${arrayvar}(num_vars) 1

	set name [generate_uniq_win ".graph_setup"]

	toplevel $name 
	wm title $name "SCS Time Series Graph Setup"
	wm geometry $name 500x600

	set f [frame $name.quit_f -relief raised -borderwidth 1]
	pack $f -side bottom -fill x

	button $f.quit -text "Cancel" -underline 0 -command "destroy $name"
	pack $f.quit -side right

	button $f.draw -text "Draw" -underline 1 -command "destroy $name; draw_time_graph $arrayvar"
	pack $f.draw -side left

	button $f.add_str -text "Add Variable" -underline 1 \
		-command "destroy $name.var; incr ${arrayvar}(num_vars); setup_variables $name $arrayvar"

	pack $f.add_str -side left

	setup_variables $name $arrayvar
}

proc setup_variables { win arrayvar } {
	global $arrayvar COLORS
	
	# Set default color for new variable
	set col_idx [expr [set ${arrayvar}(num_vars)] - 1]
	set num_col [llength $COLORS]
	set ${arrayvar}(color)($col_idx) [lindex $COLORS [expr $col_idx % $num_col]]

	# Create variable canvas
	set f [canvas $win.var -relief flat -borderwidth 1]
	pack $f -side top -fill both

	make_text_entry $f "Graph title" ${arrayvar}(title)

	make_str_entry $f "Stream 0" 0 $arrayvar
	make_yesno_entry $f "Invert Y axis" 0 ${arrayvar}(invert)

	make_start_time $f $arrayvar

	for { set i 1 } { $i < [set ${arrayvar}(num_vars)] } { incr i } {
		make_str_entry $f "Stream $i" $i $arrayvar
		make_yesno_entry $f "Invert Y axis" $i ${arrayvar}(invert)
	}
}

proc draw_time_graph { arrayvar } {
	global $arrayvar NUMPTS

	set name [generate_uniq_win ".graph"]
	
	toplevel $name
	wm title $name "SCS Time Series Graph"
	wm geometry $name 800x400

	set f [frame $name.quit_f -relief raised -borderwidth 1]
	pack $f -side bottom -fill x

	button $f.quit -text "Quit" -underline 0 -command "cancel_job $arrayvar $name"
	pack $f.quit -side right

#	button $f.print -text "Print Graph" -underline 0 -command "Blt_PostScriptDialog $name.graph"
#	pack $f.print -side right

	label $f.s -textvariable ${arrayvar}(tstamp) -width 30 -relief sunken
	label $f.v -textvariable ${arrayvar}(val) -width 10 -relief sunken
	pack $f.s $f.v -side left

	# Set start time (American)
	set time_str [join [list [set ${arrayvar}(hour)]  [set ${arrayvar}(minute)] [set ${arrayvar}(second)]] ":"]
	set date_str [join [list [set ${arrayvar}(month)] [set ${arrayvar}(day)]    [set ${arrayvar}(year)]] "/"]

	set start_time [clock scan [join [list $time_str $date_str] " "]]

	blt::stripchart $name.graph -title [set ${arrayvar}(title)] -bufferelements 0
	pack $name.graph -side top -fill both -expand 1

	set yAxes y
	set y2Axes { }

	for { set i 0 } { $i < [set ${arrayvar}(num_vars)] } { incr i } {
		set ${arrayvar}(xVec$i) [blt::vector create \#auto]
		set ${arrayvar}(yVec$i) [blt::vector create \#auto]
		
		global [set ${arrayvar}(xVec$i)]
		global [set ${arrayvar}(yVec$i)]

		# Create Axis
		if { $i > 0 } {
			set ${arrayvar}(axis)($i) "var_y$i"

			$name.graph axis create [set ${arrayvar}(axis)($i)] -title [set ${arrayvar}(var)($i)] \
				-titlecolor [set ${arrayvar}(color)($i)] -limitscolor [set ${arrayvar}(color)($i)]
 
			# alternate left & right
			if { $i & 1 } {
				lappend y2Axes [set ${arrayvar}(axis)($i)] 
			} else {
				lappend yAxes [set ${arrayvar}(axis)($i)]
			}

		} else { 
			set ${arrayvar}(axis)($i) "y"
			$name.graph axis configure y -title [set ${arrayvar}(var)($i)] -titlecolor [set ${arrayvar}(color)($i)] \
				-limitscolor [set ${arrayvar}(color)($i)]
		}
		
		set ${arrayvar}(scs_idx)($i) [scs new [set ${arrayvar}(stream)($i)]]

		scs find_time [set ${arrayvar}(scs_idx)($i)] $start_time

		$name.graph element create line$i -xdata [set ${arrayvar}(xVec$i)] -ydata [set ${arrayvar}(yVec$i)] \
			-label [set ${arrayvar}(var)($i)] -color [set ${arrayvar}(color)($i)] -pixel 1 \
			-mapy [set ${arrayvar}(axis)($i)]

		$name.graph xaxis configure -autorange $NUMPTS -shiftby 240 -stepsize 240  -subdivisions 0 \
			-command FormatMajorTick -title "Time"
		
		if { [set ${arrayvar}(invert)($i)] eq "yes" } {
			$name.graph axis configure [set ${arrayvar}(axis)($i)] -descending true
		}

		set ${arrayvar}(point$i) 0
	}

	if { [llength $y2Axes] } {
		$name.graph y2axis use $y2Axes
	}
	$name.graph yaxis use $yAxes
	
	$name.graph grid configure -hide false

	# Setup Zoom
	Blt_ZoomStack $name.graph
	
	# Keep going until finish set
	set ${arrayvar}(finish) 0

	# Update Graph 
	set ${arrayvar}(after_id) [after 10 update_graph $arrayvar]
}

proc cancel_job { arrayvar win } {
	global $arrayvar $win

	puts -nonewline "Cancelling update"

	set ${arrayvar}(finish) 1

	destroy $win
}

proc update_graph { arrayvar } {
	global $arrayvar

	if { [set ${arrayvar}(finish) ] } {
		return
	}

	for { set i 0 } { $i < [set ${arrayvar}(num_vars)] } { incr i } {
		global [set ${arrayvar}(xVec$i)]
		global [set ${arrayvar}(yVec$i)]
		
		set scs_idx [set ${arrayvar}(scs_idx)($i)]
		
		if { [scs next_record $scs_idx vals [set ${arrayvar}(var)($i)]] } {
			
			set secs                [lindex $vals 0] 
			set ${arrayvar}(val)    [lindex $vals 1]
			set ${arrayvar}(tstamp) [clock format $secs -format "%H:%M:%S %d/%m/%Y"]
			
			set point [set ${arrayvar}(point$i)]
			set xVec  [set ${arrayvar}(xVec$i)]
			set yVec  [set ${arrayvar}(yVec$i)]
			
			set ${xVec}(++end) 0
			set ${yVec}(++end) 0
			
			set ${xVec}($point) $secs
			set ${yVec}($point) [set ${arrayvar}(val)]
			
			# Only need to keep NUMPTS
			#	if { $point > $NUMPTS } { 
			#		unset xVec(0)
			#		unset yVec(0)
			
			#		incr point -1
			#	}
			
			incr ${arrayvar}(point$i)
			
			update	
		}
	} 

	# Redo command
	set ${arrayvar}(after_id) [after 10 update_graph $arrayvar]
}

proc new_array { prefix } {
	set cnt 0
	set name [join [list $prefix "_" [format "%06d" $cnt]] ""]
	global $name

	while { [array exists $name] } {
		incr cnt
		set name [join [list $prefix "_" [format "%06d" $cnt]] ""]		
		global $name
	}

	return $name
}

proc FormatMajorTick { widget secs } {
	return [clock format $secs -format "%H:%M"]
}
					   
proc generate_uniq_win { prefix } {
	set cnt 0
	set name [join [list $prefix "_" [format "%06d" $cnt]] ""]

	while { [winfo exists $name] } {
		incr cnt
		set name [join [list $prefix "_" [format "%06d" $cnt]] ""]		
	}

	return $name
}

proc generate_uniq_path { win prefix } {
	set cnt 0
	set name [join [list $win "." $prefix "_" [format "%06d" $cnt]] ""]

	while { [info commands $name] != "" } {
		incr cnt
		set name [join [list $win "." $prefix "_" [format "%06d" $cnt]] ""]		
	}

	return $name
}

proc make_text_entry { win txt var } {
	set f [generate_uniq_path $win "f"]

	frame $f -relief raised -borderwidth 1
	pack $f -side top -fill x

	label $f.l -text $txt -width [expr [string length $txt] + 3] -anchor nw
	pack $f.l -side left

	entry $f.e -relief sunken -background white -textvariable $var
	pack $f.e -side left -fill x -expand 1
}

proc make_yesno_entry { win txt idx var } {
	set f [generate_uniq_path $win "f"]

	frame $f -relief raised -borderwidth 1
	pack $f -side top -fill x

	checkbutton $f.c -offvalue no -onvalue yes -variable ${var}($idx) -text $txt
	pack $f.c -side left
}

proc make_str_entry { win txt idx arrayvar } {
	global $arrayvar

	set f [generate_uniq_path $win "str"]

	frame $f -relief raised -borderwidth 1
	pack $f -side top -fill x
	
	set width 15

	# Variables list
	frame $f.v -relief flat -borderwidth 1
	label $f.v.l -text "Variable" -width $width -anchor nw
	pack $f.v.l -side left

	set var_menu [make_var_menu $f.v ${arrayvar}(var)($idx)]

	# Streams list
	frame $f.s -relief flat -borderwidth 1
	label $f.s.l -text $txt -width $width -anchor nw
	pack $f.s.l -side left

	make_str_menu $f.s ${arrayvar}(stream)($idx) $var_menu ${arrayvar}(var)($idx)

	# Color chooser
	frame $f.c -relief flat -borderwidth 1
	label $f.c.l -text "Line colour" -width $width -anchor nw
	label $f.c.cl -text " " -width $width -background [set ${arrayvar}(color)($idx)]
	pack $f.c.l $f.c.cl -side left

	button $f.c.cb -text "Choose Colour" -underline 0 -command "choose_color $f.c.cl $idx $arrayvar"
	pack $f.c.cb -side right
	
	# Pack stream, variable frames
	pack $f.s $f.v $f.c -side top -fill x
}

proc choose_color { win idx arrayvar } {
	global $arrayvar

	set ${arrayvar}(color)($idx) [tk_chooseColor -initialcolor blue -title "Colour Chooser"]

	$win configure -background [set ${arrayvar}(color)($idx)]
}

proc make_str_menu { parent varname var_menu var_varname } {
	global STREAMS $varname $var_varname

	menubutton $parent.mb -textvariable $varname -menu $parent.mb.menu -relief raised
	pack $parent.mb -side left -fill x -expand 1

	menu $parent.mb.menu -tearoff false

	foreach s $STREAMS {
		$parent.mb.menu add command -label $s -command "global $varname; set $varname $s; set_vars $var_menu $var_varname $s"
	}
}

proc make_var_menu { parent varname } {
	global $varname

	menubutton $parent.mb -textvariable $varname -menu $parent.mb.menu -relief raised
	pack $parent.mb -side left -fill x -expand 1

	menu $parent.mb.menu -tearoff false

	return $parent.mb.menu
}

proc set_vars { menu varname stream} {
	global $varname

	set vars [scs vars $stream]

	# Remove current variables
	$menu delete 0 last

	foreach v $vars {
		$menu add command -label $v -command "global $varname; set $varname $v"
	}

	set $varname [lindex $vars 0]
}

proc make_start_time { win arrayvar } {
	global $arrayvar

	set f [frame $win.start_time -relief raised -borderwidth 1]
	pack $f -side top -fill x

	set fs [split [clock format [clock seconds] -format "%Y %m %d %H %M %S"]]
	set ${arrayvar}(year)   [lindex $fs 0]
	set ${arrayvar}(month)  [lindex $fs 1]
	set ${arrayvar}(day)    [lindex $fs 2]
	set ${arrayvar}(hour)   [lindex $fs 3]
	set ${arrayvar}(minute) [lindex $fs 4]
	set ${arrayvar}(second) [lindex $fs 5]

	label $f.l -text "Start Time" -anchor n -foreground blue
	pack $f.l -side top -fill x

	frame $f.year -relief flat -borderwidth 1
	label $f.year.l -text "Year" -width 8 -anchor nw
	entry $f.year.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(year)
	pack  $f.year.l -side left
	pack  $f.year.e -side right

	frame $f.month -relief flat -borderwidth 1
	label $f.month.l -text "Month" -width 8 -anchor nw	
	entry $f.month.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(month)
	pack  $f.month.l -side left
	pack  $f.month.e -side right

	frame $f.day -relief flat -borderwidth 1
	label $f.day.l -text "Day" -width 8 -anchor nw
	entry $f.day.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(day)
	pack  $f.day.l -side left
	pack  $f.day.e -side right

	frame $f.hour -relief flat -borderwidth 1
	label $f.hour.l -text "Hour" -width 8 -anchor nw
	entry $f.hour.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(hour)
	pack  $f.hour.l -side left
	pack  $f.hour.e -side right
	
	frame $f.minute -relief flat -borderwidth 1
	label $f.minute.l -text "Minute" -width 8 -anchor nw
	entry $f.minute.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(minute)
	pack  $f.minute.l -side left
	pack  $f.minute.e -side right
	
	frame $f.second -relief flat -borderwidth 1
	label $f.second.l -text "Second" -width 8 -anchor nw
	entry $f.second.e -relief sunken -borderwidth 1 -bg white -width 8 -textvariable ${arrayvar}(second)
	pack  $f.second.l -side left
	pack  $f.second.e -side right

	pack $f.year $f.month $f.day $f.hour $f.minute $f.second -side top -fill x

	frame  $f.buttons -relief flat -borderwidth 1
	button $f.buttons.start -borderwidth 1 -text "Start of Stream"  -underline 0 -command "SetStartTime $arrayvar"
	button $f.buttons.end   -borderwidth 1 -text "End of Stream" -underline 0 -command "SetEndTime $arrayvar"
	label $f.buttons.padding -text " " -width 20

	pack $f.buttons.start $f.buttons.padding -side left
	pack $f.buttons.end -side right
	pack $f.buttons -side top -fill x
}

proc SetStartTime { arrayvar } {
	global $arrayvar

	set stream [set ${arrayvar}(stream)(0)]
	set var [set ${arrayvar}(var)(0)]

	if { (($stream eq "") || ($var eq "")) } {
		return
	}
	
	set start_time [scs start_time $stream]

	set fs [split [clock format $start_time -format "%Y %m %d %H %M %S"]]
	set ${arrayvar}(year)   [lindex $fs 0]
	set ${arrayvar}(month)  [lindex $fs 1]
	set ${arrayvar}(day)    [lindex $fs 2]
	set ${arrayvar}(hour)   [lindex $fs 3]
	set ${arrayvar}(minute) [lindex $fs 4]
	set ${arrayvar}(second) [lindex $fs 5]

}

proc SetEndTime { arrayvar } { 
	global $arrayvar

	set stream [set ${arrayvar}(stream)(0)]
	set var [set ${arrayvar}(var)(0)]

	if { (($stream eq "") || ($var eq "")) } {
		return
	}
	
	set end_time [scs end_time $stream]

	set fs [split [clock format $end_time -format "%Y %m %d %H %M %S"]]
	set ${arrayvar}(year)   [lindex $fs 0]
	set ${arrayvar}(month)  [lindex $fs 1]
	set ${arrayvar}(day)    [lindex $fs 2]
	set ${arrayvar}(hour)   [lindex $fs 3]
	set ${arrayvar}(minute) [lindex $fs 4]
	set ${arrayvar}(second) [lindex $fs 5]
}
