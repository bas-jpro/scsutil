#!/usr/local/bin/perl -w
# Multicruise Test
#
# $Id$
#

use strict;

use lib '/packages/scs/current/lib';
use SCS;
use SCS::Compress;

my $scs = SCS::Compress->new({ debug => 1, path => '/data/cruise/jcr/20120426/scs/Compress',
							   cruises_dir => '/data/cruise/jcr', multi => 1 });

$scs->attach("oceanlogger");
my $rec = $scs->last_record();

print scalar(gmtime($rec->{timestamp})) . "\n";

$scs->next_cruise();
$rec = $scs->last_record();
print scalar(gmtime($rec->{timestamp})) . "\n";

0;

