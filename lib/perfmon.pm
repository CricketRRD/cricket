# -*-perl-*-

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

#    This is still very early in development. It's designed to collect Perfmon
#    counters from Windows NT systems. Perfmon is similiar in many respects to
#    the way Cricket does things. It keeps a config file resident in memory 
#    with all sorts of definitions from counter scaling, to what type of
#    counter it is. While it makes things convenient, it also requires a whole
#    bunch of disassembly of it's scheme to effectively put it into Cricket.
#
#    The math seems to be very wrong for some counters, which seems odd as all
#    the formulas were ripped straight from Microsoft's documentation on the
#    perflib SDK at: 
#    http://msdn.microsoft.com/library/en-us/perfmon/hh/pdh/perfdata_6di9.asp
#
#    I'm continually developing this as we need a good solution in-house for
#    flexible historical trending of perfmon counters.
#
#    I realize how god-awful slow this is, and it's really Perfmon's fault. 
#    Most counters are durational and require some sort of wait-time to get
#    two instances loaded to to comparisons/time based calculations. Also,
#    every time Perfmon is initiated on a system, you're required to get a 
#    list of every counter on the system which is very time consuming. Blame
#    my employer, not me! I'm considering making this application threaded to
#    boost performance.
#
#    Bugs I'm currently aware of:
#       * Yes there are many missing counter types. This is being worked on.
#         I'd like to think the ones which are missing right now wouldn't be
#         commonly used anyway (PERF_AVERAGE_BULK) or wouldn't be relevant
#         to Cricket anyway (PERF_COUNTER_TEXT).
#       * I know PERF_RAW_FRACTION and PERF_RAW_BASE are supremely messed up
#         right now and I'm not sure why. I'm using the formulas Microsoft
#         defined on their web site (100*x/b) and it returns screwy results.
#       * That's all I can think of right now. After spending over a week
#         working on this I think for the most part it works pretty well!
#
#    If you find any glaring bugs, omissions, or errors please feel free to 
#    email me so I can fix it.
#
#    Thanks - Adam Meltzer <ameltzer@microsoft.com>

#    Minidoc:
#
#    Perfmon counters use the following syntax for input:
#    perfmon:hostname:object:counter:instance:duration
#
#    object is the top-level class such as "Processor" or "Memory". This is a
#    required entry.
#    counter is the "% Processor Time" or "% Committed Bytes in Use". This is
#    also a required entry.
#    instance is optional, but many counters have instances such as "_Total"
#    duration is optional, it defaults to 1 second. For many perfmon counters,
#    there is a required duration to get a time-based calculation.

use Common::Log;
use Win32::PerfLib;
use strict;

$main::gDSFetch{'perfmon'} = \&perfmonFetch;
my %specialMath;

# stop
sub perfmonFetch {
	my($dsList, $name, $target) = @_;
	my %pmonFetches;
	my(@results);

	foreach my $line (@{$dsList}) {
		my @components = split(/:/, $line);
		my ($index, $server, $myobject, $mycounter, $myinstance,$myduration);
		
		if($#components+1 < 3) {
			Error("Malformed datasource line: $line.");
			return();
		}

		$index      = shift(@components);
		$server     = shift(@components);
		$myobject   = shift(@components) || missing("object");
		$mycounter  = shift(@components) || missing("counter");
		$myinstance = shift(@components) || '';
		$myduration = shift(@components) || 1;
		
		$pmonFetches{$index} = "$server:$myobject:$mycounter:$myinstance:$myduration";
	}

	while(my ($index, $ilRef) = each %pmonFetches) {
		my $counter = {};
		my $pr1      = {};
		my $pr2      = {};
		my $critical;

		my($server, $myobject, $mycounter, $myinstance,$myduration) = split(/:/, $ilRef);
		Win32::PerfLib::GetCounterNames($server, $counter) or $critical = $!;
		my $matches = 0;
		my $value;
		my %rcounter;

		
		Error("Counters can't be retrieved from $server because of $critical") if $critical;
		next if $critical;

		foreach my $k (sort keys %{$counter}) {
			$rcounter{lc($counter->{$k})} = $k;
		}

		$myobject = lc($myobject);
		my $perflib = new Win32::PerfLib($server);
		$perflib->GetObjectList($rcounter{$myobject}, $pr1);

		sleep $myduration;

		$perflib->GetObjectList($rcounter{$myobject}, $pr2);

		$perflib->Close();

		foreach my $level2 (sort keys %{$pr1->{'Objects'}}) {
			my $gDen1n = $pr1->{'PerfTime100nSec'};
			my $gDen2n = $pr2->{'PerfTime100nSec'};
			my $gDen1 = $pr1->{'PerfTime'};
			my $gDen2 = $pr2->{'PerfTime'};
			my $gTb  = $pr1->{'PerfFreq'};
			my $base;
			my $fract;

			if($pr1->{'Objects'}->{$level2}->{'NumInstances'} > 0) {
				foreach my $level4 (sort keys %{$pr1->{'Objects'}->{$level2}->{'Instances'}}) {
					my $ir1 = $pr1->{'Objects'}->{$level2}->{'Instances'}->{$level4};
					my $ir2 = $pr2->{'Objects'}->{$level2}->{'Instances'}->{$level4};
					foreach my $level5 (sort keys %{$ir1->{'Counters'}}) {
						my $cr1 = $ir1->{'Counters'}->{$level5};
						my $cr2 = $ir2->{'Counters'}->{$level5};
						my $saneCounterName = $counter->{$cr1->{'CounterNameTitleIndex'}};
						my $saneInstanceName = $ir1->{'Name'};
						if(lc($saneCounterName) eq lc($mycounter)) {
							if(lc($saneInstanceName) eq lc($myinstance) || !defined $myinstance) {
								$specialMath{lc($saneCounterName)}{Win32::PerfLib::GetCounterType($cr1->{'CounterType'})} = $cr1->{'Counter'};
								$value = getCounter($cr1,$cr2,$gDen1,$gDen2,$gDen1n,$gDen2n,$gTb,$ilRef);
								$matches++;
							}
						}
					}
				}
			}
			foreach my $level4 (sort keys %{$pr1->{'Objects'}->{$level2}->{'Counters'}}) {
				my $cr1 = $pr1->{'Objects'}->{$level2}->{'Counters'}->{$level4};
				my $cr2 = $pr2->{'Objects'}->{$level2}->{'Counters'}->{$level4};
				my $saneCounterName = $counter->{$cr1->{'CounterNameTitleIndex'}};
				if(lc($saneCounterName) eq lc($mycounter)) {
					$specialMath{lc($saneCounterName)}{Win32::PerfLib::GetCounterType($cr1->{'CounterType'})} = $cr1->{'Counter'};
					$value = getCounter($cr1,$cr2,$gDen1,$gDen2,$gDen1n,$gDen2n,$gTb,$ilRef);
					$matches++;
				}
			}
		}

		if($matches > 1) {
		Debug("More than one matches for datasource line: $ilRef. Only last instance will be used!");
		}
	
		if($matches < 1) {
			Error("No matches for datasource line: $ilRef");
			push @results, "$index:U";
		} else {
			push @results, "$index:$value";
		}
	} # end perfmon fetch

	return @results;

} # end sub perfmonFetch
	
sub getCounter {
	my ($cr1,$cr2,$den1,$den2,$den1n,$den2n,$tb,$ilRef) = @_;
	my ($crap,$junk,$cn) = split(/:/, $ilRef);
	my $value;
	my ($d1,$d2);

	my $scaler = $cr1->{'DefaultScale'};
	my $ctype = Win32::PerfLib::GetCounterType($cr1->{'CounterType'});

	my $n1 = $cr1->{'Counter'};
	my $n2 = $cr2->{'Counter'} if($cr2);

	if($ctype =~ /100NSEC/) {
		$d1 = $den1n;
		$d2 = $den2n;
	} else {
		$d1 = $den1;
		$d2 = $den2;
	}

	Debug("CounterType for $ilRef is $ctype");

	# Formulas are all defined on MSDN at:
	# http://msdn.microsoft.com/library/en-us/perfmon/hh/pdh/perfdata_6di9.asp
	#
	# They have all been for the most part copy-and-paste jobs with some slight
	# modifications (which I don't believe ultimately affected the outcome of
	# the arithematic.
	if ($ctype eq 'PERF_100NSEC_TIMER' || $ctype eq 'PERF_PRECISION_100NS_TIMER' || $ctype eq 'PERF_PRECISION_SYSTEM_TIMER') {
		$value = (($n2 - $n1) / ($d2 - $d1)) * 100;
	} elsif ($ctype eq 'PERF_100NSEC_TIMER_INV') {
		$value = (1- (($n2 - $n1) / ($d2 - $d1))) * 100;
	} elsif ($ctype eq 'PERF_COUNTER_COUNTER') {
		$value = ($n2 - $n1) / (($d2 - $d1) / $tb);
	} elsif ($ctype eq 'PERF_COUNTER_DELTA' || $ctype eq 'PERF_COUNTER_LARGE_DELTA') {
		$value = $n2 - $n1;
	} elsif ($ctype eq 'PERF_COUNTER_QUEUELEN_TYPE' || $ctype eq 'PERF_COUNTER_LARGE_QUEUELEN_TYPE' || $ctype eq 'PERF_OBJ_TIME_TIMER') {
		$value = ($n2 - $n1) / ($d2 - $d1);
	} elsif ($ctype =~ /^(PERF_COUNTER_RAW|PERF_COUNTER_LARGE_RAW)/) {
		$value = $n1;
	} elsif ($ctype eq 'PERF_RAW_BASE' && $specialMath{$cn}{'PERF_RAW_FRACTION'}) {
		# Yes, I know how crufty this is. I plan on fixing it soon.
		$value = 100 * $n1 / $specialMath{$cn}{'PERF_RAW_FRACTION'}; 
	} elsif ($ctype eq 'PERF_RAW_FRACTION' && $specialMath{$cn}{'PERF_RAW_BASE'}) {
		# Yes, I know how crufty this is. I plan on fixing it soon.
		$value = 100 * $n1 / $specialMath{$cn}{'PERF_RAW_FRACTION'}; 
	} elsif ($ctype eq 'PERF_ELAPSED_TIME') {
		$value = ($d1 - $n1) / $tb;
	} elsif ($ctype eq 'PERF_COUNTER_NODATA') {
		$value = 0;
	} else {
		Error("Ack! Unsupported counter $ctype. Mail this to ameltzer\@microsoft.com: $ilRef") unless ($ctype eq 'PERF_RAW_FRACTION' || $ctype eq 'PERF_RAW_BASE');
	}

	if($scaler != 0) {
		Debug("Scaler for $ilRef is: $scaler -- old value is: $value");
	}
	$value = $value * (10**$scaler) if($value);
	Debug("Return value for $ilRef is: $value") unless (!$value);

	return $value;
}

sub missing {
	my ($missing) = @_;
	Error("Missing perfmon $missing in datasource line.");
	return();
}
