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

package Common::HandleTarget;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(handleTarget handleTargetInstance checkTargetInstance);

use Common::Log;
use Common::Util;
use Common::Map;
use RRD::File;

sub handleTarget {
	my($name, $instHandler, $cb) = @_;

	Debug("Processing $name...");

	my($target) = $Common::global::gCT->configHash($name, 'target');
	ConfigTree::Cache::addAutoVariables($name, $target,
		$Common::global::gConfigRoot);

	my($tname) = $target->{'auto-target-name'};

	Common::Map::mapPrepareInstance($target);

    # check for non-scalar instance
    # and handle as a special case with a loop
    my(@inst);
    if (defined($target->{'inst'})) {
        my($inst) = $target->{'inst'};
        $inst = ConfigTree::Cache::expandString($inst, $target, \&Warn);
 
        Debug("Evaling inst which is: $inst");
        $inst = quoteString($inst);
        @inst = Eval($inst);
    } else {
        @inst = ();
    }
 
    if ($#inst+1 > 1) {
        my($inst);
        foreach $inst (@inst) {
            # copy the current target to a temp target we can play
            # with -- i.e. set the inst to a scalar, then expand
 
            my($k, $v, $tmpTarg);
            $tmpTarg = {};
            foreach $k (keys(%{$target})) {
                $tmpTarg->{$k} = $target->{$k};
            }
 
            $tmpTarg->{'inst'} = $inst;
 
            Debug("Processing target $tname, instance $inst.");
			&{$instHandler}($name, $tmpTarg, $cb);
        }
    } else {
        # this is a scalar case, just continue into handleTargetInstance.
        $target->{'inst'} = (defined($inst[0]) ? $inst[0] : "");
 
        &{$instHandler}($name, $target, $cb);
    }
}

sub handleTargetInstance {
	my($name, $target, $cb) = @_;

	# expand it wrt itself
    ConfigTree::Cache::expandHash($target, $target, \&Warn);

	# this will do instance mapping, or leave the target untouched
	# if there's no work to do. (mapPrepareInstance has to have been
	# called first...)
	Common::Map::mapInstance($name, $target);

	# now, call the callback passed into us by the
	# parent
	&{$cb}($name, $target);
}

sub checkTargetInstance {
	my($name,$target) = @_;

	# expand it wrt itself
	ConfigTree::Cache::expandHash($target, $target, \&Warn);

	if(! $target->{'monitor-thresholds'}) {
		return;
	}

	my($m) = new Monitor;
	my($rrd) = new RRD::File( -file=>$target->{'rrd-datafile'} );
	if(!$rrd->open() || !$rrd->loadHeader()) {
		Info("Couldn't open RRD File for $name, skipping this target.");
		return;
	}

	# Convert backslashed commas to \0's ; 
	my $ThresholdString = $target->{'monitor-thresholds'};
	$ThresholdString =~ s/\\,/\0/g ;
	my(@ThresholdStrings) = split(/\s*,\s*/, $ThresholdString );
	 
	my($Threshold);
	foreach $Threshold (@ThresholdStrings) {
		$Threshold =~ s/\0/,/g ;
		my($ds,$type,$args) = split(/\s*:\s*/, $Threshold, 3);
		$args =~ s/\\:/\0/g ;
		my($alarmType) = 'SNMP' ;
		my($alarmArgs) ;
		if( $args =~ /^(.*)\s*:\s*(FUNC|EXEC)\s*:\s*([^:]*)\s*:\s*([^:]*)$/ ) {
			$args = $1 ;
			$alarmType = $2 ;
			my $alarmCommand = $3 ;
			my $clearCommand = $4 ;
			$args =~ s/\0/:/g ;
			$alarmCommand =~ s/\0/:/g ;
			$clearCommand =~ s/\0/:/g ;
			$alarmArgs->[0] = $alarmCommand ;
			$alarmArgs->[1] = $clearCommand ;
		} elsif( $args =~ /^(.*)\s*:\s*SNMP\s*$/ ) {
			$args = $1 ;
			$args =~ s/\0/:/g ;
		}				
		if(defined($Common::global::gMonitorTable{"$type"})) {
			if(&{$Common::global::gMonitorTable{"$type"}}
				($m, $target, $ds, $type, $args)) {
				# the test succeeded, check to see if we
				# should send a trap or not
				LogMonitor("$name - $Threshold passed.");

				my($metaRef) = $rrd->getMeta();
				if(defined($metaRef->{$Threshold})) {
					LogMonitor("Triggering recovery for $Threshold.");
					$m->Clear($target,$name,$ds,$type,$Threshold,$alarmType,$alarmArgs);
					delete($metaRef->{$Threshold});
					$rrd->setMeta($metaRef);
				}
			} else {
				my($metaRef) = $rrd->getMeta();
				LogMonitor("$name - $Threshold failed.");
				if(!defined($metaRef->{$Threshold})) {
					LogMonitor("Triggering alarm for $Threshold.");
					$m->Alarm($target,$name,$ds,$type,$Threshold,$alarmType,$alarmArgs);
					$metaRef->{$Threshold} = 'Failed';
					$rrd->setMeta($metaRef);
				}
			}
		} else {
			Warn("No monitor handler defined for monitor type $type");
		}
	}
	$rrd->close();
}

1;

