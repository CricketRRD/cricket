#!/usr/local/bin/perl -w
# -*- perl -*-

# Cricket: a configuration, polling and data display wrapper for RRD files
#
#    Copyright (C) 1998 Jeff R. Allen and WebTV Networks, Inc.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
BEGIN {
	my $programdir = (($0 =~ m:^(.*/):)[0] || "./") . "..";
	eval "require '$programdir/cricket-conf.pl'";
	eval "require '/usr/local/etc/cricket-conf.pl'"
					unless $Common::global::gInstallRoot;
	$Common::global::gInstallRoot ||= $programdir;

}

use lib "$Common::global::gInstallRoot/lib";
use strict;

use Win32::PerfLib;
use Getopt::Long;

my ($counter,$pr) = ({},{});
my $server;
my ($object,$cname,$ctype,$instance,$debug) = 0;
my %rcounter;

&GetOptions(
	"s|server=s" => \$server,
	"o|object=s" => \$object,
	"c|counter=s" => \$cname,
	"i|instance=s" => \$instance,
	"d|debug=i" => \$debug,
	"h|help" => \&Help,
	);

Win32::PerfLib::GetCounterNames($server, $counter);

if(!defined($server)) {
	$server = ".";
}

if(! $object || ! $counter) {
	warn "Error: -o|-c must be defined!\n";
	&Help;
}

print "* Setting server to $server\n";

foreach my $k (keys %{$counter}) {
	$rcounter{lc($counter->{$k})} = $k;
}


my $pl = new Win32::PerfLib($server);	
$pl->GetObjectList($rcounter{$object}, $pr) || die "Can't get counters from $server because of: $!\n";
$pl->Close();

print "* Getting counter type(s) for $cname\n";

foreach my $level2 (keys %{$pr->{'Objects'}}) {
	if($pr->{'Objects'}->{$level2}->{'NumInstances'} > 0) {
		if(defined($instance)) {
			print "\t* Traversing multiple counters for $cname\n";
		
			foreach my $level4 (keys %{$pr->{'Objects'}->{$level2}->{'Instances'}}) {
				my $ir = $pr->{'Objects'}->{$level2}->{'Instances'}->{$level4};
				foreach my $level5 (keys %{$ir->{'Counters'}}) {
					my $cr = $ir->{'Counters'}->{$level5};
					my $saneCounter = $counter->{$cr->{'CounterNameTitleIndex'}};
					my $saneInstance = $ir->{'Name'};
					print "\t\t\t* Debug: $saneCounter->$saneInstance\n" if($debug == 1);
					if(lc($saneCounter) eq lc($cname)) {
						if(lc($saneInstance) eq lc($instance)) {
							$ctype = Win32::PerfLib::GetCounterType($cr->{'CounterType'});
							print "\t\t* Found!\n";
							print "\t\t* $cname->$instance is counter: $ctype\n";
						}
					}
				}
			}
		} else {
			print "\t* Counter has multiple instances, ignoring because --instances not set\n";
		}
	}

	foreach my $level4 (keys %{$pr->{'Objects'}->{$level2}->{'Counters'}}) {
		my $cr = $pr->{'Objects'}->{$level2}->{'Counters'}->{$level4};
		my $saneCounter = $counter->{$cr->{'CounterNameTitleIndex'}};
		print "\t\t\t* Debug: $saneCounter\n" if ($debug == 1);

		if(lc($saneCounter) eq lc($cname)) {
			$ctype = Win32::PerfLib::GetCounterType($cr->{'CounterType'});
			print "\t\t* Found!\n";
			print "\t\t* $cname is counter type: $ctype\n";
			getFormula($ctype);
		}
	}
}

sub getFormula {
	my ($cdef) = @_;
	print <<EOF;

Formulas are from MSDN - subject to change. Author of this program takes no 
responsibilities for inaccurate information!

Symbols:
TB   Time base. If TB is not used in the calculation, then it indicates the 
     units of the raw data.
B    The base value used for calculating performance data types that require
     base.

EOF
	if($cdef eq "PERF_100NSEC_MULTI_TIMER") {

		extractFormula($cdef, "Timer sampling of multiple but similar items. Result is an average sampling among the items. The number of items it the base data.", "CounterData", "100NsTime", "100Ns", "8", "%", "100*((X1-X0)/(Y1-Y0))/B1");
	} elsif ($cdef eq "PERF_100NSEC_MULTI_TIMER_INV") {
		extractFormula($cdef, "The inverse of the timer for multiple but similar items. Used when the objects are not in use.", "CounterData", "100NsTime", "100Ns", "8", "%", "100*(B1-((X1-X0)/(Y1-Y0)))/B1");
	} elsif ($cdef eq "PERF_100NSEC_TIMER") {
		extractFormula($cdef, "Timer for when the object is in use.", "CounterData", "100NsTime", "100Ns", "8", "%", "100*(X1-X0)/(Y1-Y0)");
	} elsif ($cdef eq "PERF_100NSEC_TIMER_INV") {
		extractFormula($cdef, "Timer for when the object is not in use.", "CounterData", "100NsTime", "100Ns", "8", "%", "100*(1-(X1-X0)/(Y1-Y0))");
	} elsif ($cdef eq "PERF_AVERAGE_BASE") {
		extractFormula($cdef, "Use of the base data in the computation of time or count averages. See PERF_AVERAGE_TIMER and PERF_AVERAGE_BULK", "N/A", "N/A", "N/A", "4", "N/A", "N/A");
	} elsif ($cdef eq "PERF_AVERAGE_BULK") {
		extractFormula($cdef, "A count that usually gives the bytes per operation when divided by the number of operations.", "CounterData", "N/A", "N/A", "8", "No suffix", "(X1-X0)/(B1-B0)");
	} elsif ($cdef eq "PERF_AVERAGE_TIMER") {
		extractFormula($cdef, "A timer that usually gives the time per operation when divided by the number of operations.", "CounterData", "N/A", "PerfFreq", "4", "Sec", "((X1-X0)/TB)/(B1-B0)");
	} elsif ($cdef eq "PERF_COUNTER_100NS_QUEUELEN_TYPE") {
		extractFormula($cdef, "Queue-length space-time product using a 100-nanosecond time base.", "CounterData", "PerfTime", "PerfFreq", "8", "No suffix", "(TB(X1-X0))/(Y1-Y0)");
	} elsif ($cdef eq "PERF_COUNTER_BULK_COUNT") {
		extractFormula($cdef, "Used to count byte transmission rates.", "CounterData", "PerfTime", "PerfFreq", "8", "/Sec", "(X1-X0)/((Y1-Y0)/TB)");
	} elsif ($cdef eq "PERF_COUNTER_COUNTER") {
		extractFormula($cdef, "Rate of counts. This is the most common counter.", "CounterData", "PerfTime", "PerfFreq", "4", "/Sec", "(X1-X0)/((Y1-Y0/TB)");
	} elsif ($cdef =~ /^(PERF_COUNTER_DELTA|PERF_COUNTER_LARGE_DELTA)$/) {
		extractFormula($cdef, "Difference between two counters", "CounterData", "N/A", "N/A", "4", "No suffix", "X1-X0");
	} elsif ($cdef eq "PERF_COUNTER_LARGE_QUEUELEN_TYPE") {
		extractFormula($cdef, "Counter per time interval. Typically used to track number of items queued or waiting.", "CounterData", "PerfTime", "PerfFreq", "8", "No suffix", "(X1-X0)/(Y1-Y0)");
	} elsif ($cdef =~ /^(PERF_COUNTER_RAWCOUNT|PERF_COUNTER_LARGE_RAWCOUNT)$/) {
		extractFormula($cdef, "Intantaneous counter value.", "CounterData", "N/A", "N/A", "8", "No suffix", "X");
	} elsif ($cdef =~ /^(PERF_COUNTER_RAWCOUNT_HEX|PERF_COUNTER_LARGE_RAWCOUNT_HEX)$/) {
		extractFormula($cdef, "Intantaneous counter value intended to be displayed as a hexadecimal number.", "CounterData", "N/A", "N/A", "8", "No suffix", "X");
	} elsif ($cdef eq "PERF_COUNTER_MULTI_BASE") {
		extractFormula($cdef, "Used as the base data for the MULTI counters. It defines the number of similar items sampled. See PERF_COUNTER_MULTI_TIMER, PERF_COUNTER_MULTI_TIMER_INV, PERF_100NSEC_MULTI_TIMER, and PERF_100NSEC_MULTI_TIMER_INV.", "N/A", "N/A", "N/A", "8", "N/A", "N/A");
	} elsif ($cdef eq "PERF_COUNTER_MULTI_TIMER") {
		extractFormula($cdef, "Timer sampling of multiple but similar items. Result is an average sampling among the items. The number of items is in the base data.", "CounterData", "PerfTime", "PerfFreq", "8", "%", "100*((X1-X0/((Y1-Y0)/TB))/B1");
	} elsif ($cdef eq "PERF_COUNTER_MULTI_TIMER_INV") {
		extractFormula($cdef, "The inverse of the timer for multiple but similar items. Used when the objects are not in use.", "CounterData", "PerfTime", "PerfFreq", "8", "%", "100*(B1-((X1-X0/((Y1-Y0)/TB)))/B1");
	} elsif ($cdef eq "PERF_COUNTER_NODATA") {
		extractFormula($cdef, "There is no data for this counter.", "0", "N/A", "N/A", "0", "N/A", "0");
	} elsif ($cdef eq "PERF_COUNTER_OBJECT_TIME_QUEUELEN_TYPE") {
		extractFormula($cdef, "Queue-length space-time product using an object-speific time base.", "CounterData", "ObjectTime", "ObjectSpecific", "8", "No suffix", "(X1-X0)/(Y1-Y0)");
	} elsif ($cdef eq "PERF_COUNTER_QUEUELEN_TYPE") {
		extractFormula($cdef, "Count per time interval. Typically used to track number of items queued or waiting.", "CounterData", "PerfTime", "PerfFreq", "4", "No suffix", "(X1-X0)/(Y1-Y0)");
	} elsif ($cdef eq "PERF_COUNTER_TIMER") {
		extractFormula($cdef, "The most common timer.", "CounterData", "PerfTime", "PerfFreq", "8", "%", "100*(X1-X0)/(Y1-Y0)");
	} elsif ($cdef eq "PERF_COUNTER_TIMER_INV") {
		extractFormula($cdef, "The inverse of the timer. Used when the object is not in use.", "CounterData", "PerfTime", "PerfFreq", "8", "%", "100*(1-(X1-X0)/(Y1-Y0))");
	} elsif ($cdef eq "PERF_ELAPSED_TIME") {
		extractFormula($cdef, "The data is the start time of the item being measured. For display, subtract the start time from the snapshot time to yield the elapsed time. the PerfTime member of the PERF_OBJECT_TYPE structure contains the sample time. Use the PerfFreq member of the PERF_OBJECT_TYPE structure to convert the time into seconds.", "CounterData", "PerfTime", "PerfFreq", "8", "Sec", "(Y-X)/TB");
	} elsif ($cdef =~ /^(PERF_RAW_BASE|PERF_LARGE_RAW_BASE)$/) {
		extractFormula($cdef, "Used as a base data for PERF_RAW_FRACTION. The CounterData holds the denominator of the fraction value. Check that this value is greater than zero before dividing.", "N/A", "N/A", "N/A", "8", "N/A", "N/A");
	} elsif ($cdef eq "PERF_OBJ_TIME_TIMER") {
		extractFormula($cdef, "64-bit timer in object-spcific units.", "CounterData", "PerfTime", "ObjectSpecific", "8", "%", "(X1-X0)/(Y1-Y0)");
	} elsif ($cdef eq "PERF_RAW_FRACTION") {
		extractFormula($cdef, "Instantaneous value, to be divided by the base data. See PERF_RAW_BASE", "CounterData", "N/A", "N/A", "4", "%", "100*X/B");
	} else {
		print "$cdef is unsupported/undocumented in this release.\n";
	}
}

sub extractFormula {
	my ($cdef, $desc, $x, $y, $tb, $size, $suff, $calc) = @_;

	format STDOUT =

Platform SDK

@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$cdef

@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$desc

Element        Value
X              @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<	
$x
Y              @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$y
Time base      @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$tb
Data size      @<< bytes
$size
Display suffix @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$suff
Calculation    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$calc

=end
.
	write;
}


sub Help {
	print <<EOF;

$0 v1.0 by Adam Meltzer <ameltzer\@microsoft.com>

Syntax: $0 <-s|-o|-c> [-i|-d|-h]

Accepts the following options:

[opt]	-s|--server	Server name to fetch counters from (defaults to .>
[req]	-o|--object	Object to fetch counters from (ie: System, Processor)
[req]	-c|--counter	Name of counter (ie: % Processor Time)
[opt]	-i|--instance	Instance name (ie: _Total)
[opt]	-d|--debug	0 = off, 1 = on
[opt]	-h|--help	You are here.
EOF

	exit 1;
}
