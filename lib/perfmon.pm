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
#       * On the same vein, this breaks the instance checker which Warn()s if
#         there are more than one matches for a selected counter.
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
#    perfmon:hostname:object:counter:instance:special options
#
#    object is the top-level class such as "Processor" or "Memory". This is a
#    required entry.
#    counter is the "% Processor Time" or "% Committed Bytes in Use". This is
#    also a required entry.
#    instance is optional, but many counters have instances such as "_Total"
#    duration is optional, it defaults to 1 second. For many perfmon counters,
#    there is a required duration to get a time-based calculation.
#    special options is optional. Currently it accepts 'noscale' which turns
#    off scaling if perfmon so demands it.

use Common::Log;
use Common::Util;
use Win32::PerfLib;
use strict;

$main::gDSFetch{'perfmon'} = \&perfmonFetch;

sub perfmonFetch {
    my($dsList, $name, $target) = @_;
    my %pmonFetches;
    my $counter = {};
    my $rcounter = {};
    my(@results);

    foreach my $line (@{$dsList}) {
        my @components = split(/:/, $line);
        my ($index, $server, $myobject, $mycounter, $myinstance,$myduration,$myoptions);

        if($#components+1 < 3) {
            Error("Malformed datasource line: $line.");
            return();
        }

        $index      = shift(@components);
        $server     = shift(@components) || missing("host",$line);
        $myobject   = shift(@components) || 'System';
        $mycounter  = shift(@components) || 'System Up Time';
        $myinstance = shift(@components) || '';
        $myoptions  = shift(@components) || '';

        $pmonFetches{$index} = "$server:$myobject:$mycounter:$myinstance:$myoptions";
    }

    DSLOOP: while(my ($index, $ilRef) = each %pmonFetches) {
        my $pr1 = {};
        my $critical;
        my ($matches,$noscale) = int(0);
        my $value;
        my $fractop;
        my ($perfTimeOnly,$perfFreqOnly);

        my($server, $myobject, $mycounter, $myinstance, $myoptions) = split(/:/, $ilRef);

        $myobject =~ s/=/:/g;

        my @options = split(/,/, $myoptions);

        foreach my $op (@options) {
            if($op =~ /^noscale$/i) {
                $noscale = 1;
            }

            if($op =~ /^perftime$/i) {
                $perfTimeOnly = 'normal';
            }

            if($op =~ /^perftime100ns$/i) {
                $perfTimeOnly = '100ns';
            }
            if($op =~ /^perffreq$/i) {
                $perfFreqOnly = 1;
            }
            if($op =~ /^base$/i) {
                $fractop = 'base';
            }
            if($op =~ /^fraction$/i) {
                $fractop = 'fraction';
            }
        }

        if(!($counter->{$server})) {

            my $tempref = {};
            Win32::PerfLib::GetCounterNames($server, $tempref) or $critical = $!;
            $counter->{$server} = $tempref;
        }

        if( (!$counter->{$server}) || $counter->{$server} == 0) {
            Error("No counters were retrieved from $server! Not wasting any more time on this ds: $ilRef");
            push @results, "$index:U";
            next DSLOOP;
        }

        # Get a list of mappings from CounterName -> id
        if (! $rcounter->{$server}) {
            foreach my $k (sort keys %{$counter->{$server}}) {
                $rcounter->{$server}->{lc($counter->{$server}->{$k})} = $k;
            }
        }

        $myobject = lc($myobject);

        my $perflib = new Win32::PerfLib($server);
        $perflib->GetObjectList($rcounter->{$server}->{$myobject}, $pr1);
        $perflib->Close();

        if($perfTimeOnly) {
            if($perfTimeOnly eq 'normal') {
                Debug("perfTimeOnly is $perfTimeOnly $pr1->{'PerfTime'}");
                my $value = Common::Util::fixNum($pr1->{'PerfTime'});

                push @results, "$index:$value";
                next DSLOOP;
            } elsif ($perfTimeOnly eq '100ns') {
                Debug("perfTimeOnly is $perfTimeOnly $pr1->{'PerfTime100nSec'}");
                my $value = Common::Util::fixNum($pr1->{'PerfTime100nSec'});
                push @results, "$index:$value";
                next DSLOOP;
            }
        }

        if($perfFreqOnly) {
            Debug("perfFreqOnly is $perfFreqOnly $pr1->{'PerfFreq'}");
            my $value = sprintf("%0.20g", $pr1->{'PerfFreq'});
            push @results, "$index:$value";
            next DSLOOP;
        }

        foreach my $level2 (sort keys %{$pr1->{'Objects'}}) {
            my $gDenn = $pr1->{'PerfTime100nSec'};
            my $gDen  = $pr1->{'PerfTime'};
            my $gTb   = $pr1->{'PerfFreq'};
            my $oldvalue;

            if($pr1->{'Objects'}->{$level2}->{'NumInstances'} > 0) {
                foreach my $level4 (sort keys %{$pr1->{'Objects'}->{$level2}->{'Instances'}}) {
                    my $oldvalue;
                    my $ir1 = $pr1->{'Objects'}->{$level2}->{'Instances'}->{$level4};
                    foreach my $level5 (sort keys %{$ir1->{'Counters'}}) {
                        my $cr1 = $ir1->{'Counters'}->{$level5};
                        my $saneCounterName = $counter->{$server}->{$cr1->{'CounterNameTitleIndex'}};
                        my $saneInstanceName = $ir1->{'Name'};
                        if(lc($saneCounterName) eq lc($mycounter)) {
                            if(lc($saneInstanceName) eq lc($myinstance) || !defined $myinstance) {
                                $value = getCounter($cr1,$index,$ilRef,$noscale,$fractop);
                                if($value ne "skip") {
                                    $oldvalue = $value;
                                    $matches++;
                                } else {
                                    $value = $oldvalue;
                                }
                            }
                        }
                    }
                }
            }
            foreach my $level4 (sort keys %{$pr1->{'Objects'}->{$level2}->{'Counters'}}) {
                my $cr1 = $pr1->{'Objects'}->{$level2}->{'Counters'}->{$level4};
                my $saneCounterName = $counter->{$server}->{$cr1->{'CounterNameTitleIndex'}};

                if(lc($saneCounterName) eq lc($mycounter)) {
                    $value = getCounter($cr1,$index,$ilRef,$noscale,$fractop);
                    if($value ne "skip") {
                        $oldvalue = $value;
                        $matches++;
                    } else {
                        $value = $oldvalue;
                    }
                }
            }
        }

        if($matches > 1) {
            Warn("More than one matches for datasource line: $ilRef. Only last instance will be used!");
        }

        if($matches < 1) {
            Error("No matches for datasource line: $ilRef");
            push @results, "$index:U";
        } else {
            push @results, "$index:$value";
        }
    }
    return @results;
}

sub getCounter {
    my ($cr1,$index,$ilRef,$noscale,$fractop) = @_;
    my ($crap,$junk,$cn) = split(/:/, $ilRef);
    my $scaler = $cr1->{'DefaultScale'};
    my $ctype = Win32::PerfLib::GetCounterType($cr1->{'CounterType'});

    if(defined($fractop)) {
        return "skip" if($fractop eq "base" && $ctype =~ /FRACTION/);
        return "skip" if($fractop eq "fraction" && $ctype =~ /BASE/);
    }

    Debug("ds$index COUNTER_TYPE is $ctype");

    if(defined $fractop) {
        Debug("FractOp is set to: $fractop");
    }
    my $value = $cr1->{'Counter'};

    if(defined($noscale) && $noscale < 1) {
        $value = $value * (10**$scaler);
    }

    $value = Common::Util::fixNum($value);

    return $value;
}

sub missing {
    my ($missing,$line) = @_;
    Error("Missing perfmon $missing in datasource: $line");
    return();
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
