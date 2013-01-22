#!/usr/local/bin/perl -w
# Multicruise Test
#
# $Id$
#

use strict;

use lib '/packages/scs/current/lib';
use SCS;
use SCS::Compress;

my $scs = SCS::Compress->new({ debug => 1, path => '/data/cruise/jcr/20120426', cruises_dir => '/data/cruise/jcr' });
$scs->next_cruise();

0;

