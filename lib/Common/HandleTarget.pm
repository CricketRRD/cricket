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
        $inst = ConfigTree::Cache::expandString($inst, $target, \&Warn)
                    if (length($inst) > 2 && index($inst, "%") >= 0);

        Debug("Evaling inst which is: $inst");
        $inst = quoteString($inst);
        @inst = Eval($inst);
    } else {
        @inst = ();
    }

    if ($#inst+1 > 1) {
        my $instnames;
        my(@instnames) = ();
        my $hasInstNames = 0;
        if (defined($target->{'inst-names'})) {
            $instnames = $target->{'inst-names'};
            $instnames = ConfigTree::Cache::expandString($instnames,$target,\&Warn);
            $instnames = quoteString($instnames);
            @instnames = Eval($instnames);
            $hasInstNames = 1;
        }

        my($inst);
        foreach $inst (@inst) {
            $instnames = shift @instnames if $hasInstNames;
            # copy the current target to a temp target we can play
            # with -- i.e. set the inst to a scalar, then expand

            my($k, $v, $tmpTarg);
            $tmpTarg = {};
            foreach $k (keys(%{$target})) {
                $tmpTarg->{$k} = $target->{$k};
            }

            $tmpTarg->{'inst'} = $inst;
            # use inst-name instead of inst-names here because
            # I have no idea if inst-names is used later in the code
            $tmpTarg->{'inst-name'} = $instnames if $hasInstNames;

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

    if (! $target->{'monitor-thresholds'}) {
        return;
    }

    my($m) = new Monitor;
    my($rrd) = new RRD::File( -file=>$target->{'rrd-datafile'} );
    if (!$rrd->open()) {
        Info("Couldn't open RRD File for $name, skipping this target.");
        return;
    }

    my $rrdpollinterval = $target->{'rrd-poll-interval'};
    my $time = time();
    # Convert backslashed commas to \0's ;
    my $ThresholdString = $target->{'monitor-thresholds'};
    $ThresholdString =~ s/\\,/\0/g ;
    my(@ThresholdStrings) = split(/\s*,\s*/, $ThresholdString );

    my($Threshold);
    # General monitor threshold format:
    # datasource:monitor type:monitor args:action:action args
    # Current supported actions: FUNC, EXEC, FILE, MAIL, SNMP, META
    # Action args are colon (:) delimited.
    # Monitor args are colon (:) delimited, but must not collide with
    # any of the action tags.
    # SNMP is the exception; it has no action args and instead uses
    # the target variable trap-address. This exception is maintained for
    # backwards compatibility.
    # META only stores an alarm in the *.meta files; It can have any number of
    # action arguments which can serve to group alarms
    # for classification or to identify a priority priority level. Arguments
    # are not interpreted or processed in any way by Monitor.pm.
    foreach $Threshold (@ThresholdStrings) {
        # restore escaped commas
        $Threshold =~ s/\0/,/g ;
        my($span) = 0;
        my($spanlength);

        my($ds,$type,$args) = split(/\s*:\s*/, $Threshold, 3);
        ($args, $spanlength) = split(/:SPAN:/, $args, 2) if ($args =~ /SPAN/);
        if (defined ($spanlength) && $spanlength =~ /\d+/ ){
            $span = 1;
        }

        # hide escaped colons
        $args =~ s/\\:/\0/g ;
        # default action type is SNMP
        my($actionType) = 'SNMP' ;
        my(@actionArgs);
        # search for an action tag
        if ( $args =~ /^(.*)\s*:\s*(FUNC|EXEC|FILE|MAIL|META)\s*:\s*(.*)$/ ) {
            $args = $1 ;
            $actionType = $2 ;
            # restore escaped colons in the monitor args field
            $args =~ s/\0/:/g ;
            my $action_args = $3;
            # action args are colon-delimited
            @actionArgs = split(/\s*:\s*/, $action_args);
            # restore escaped colons in the action args field
            map { $_ =~ s/\0/:/g } @actionArgs;
        } elsif ( $args =~ /^(.*)\s*:\s*(SNMP|META)\s*$/ ) {
            $args = $1 ;
            $actionType = $2 ;
            # restore escaped colons
            $args =~ s/\0/:/g ;
        }
        if (defined($Common::global::gMonitorTable{"$type"})) {
            my $persistent = $target->{'persistent-alarms'};
            $persistent = 'false' if (!defined($persistent));

            my ($rc, $val) =
                &{$Common::global::gMonitorTable{"$type"}}
                    ($m, $target, $ds, $type, $args);
            if ($rc) {
                # the test succeeded, check to see if we
                # should send a trap or not
                LogMonitor("$name - $Threshold passed.");

                my($metaRef) = $rrd->getMeta();
                if (defined($metaRef->{$Threshold})) {
                    LogMonitor("Triggering recovery for $Threshold.");
                    $m->Clear($target,$name,$ds,$type,$Threshold,$actionType,
                              \@actionArgs,$val);
                    delete($metaRef->{$Threshold});
                    $rrd->setMeta($metaRef);
                }
            } else {
                my($metaRef) = $rrd->getMeta();
                my ($x, $mt, $mevent, $rest);
                ($x,$mt, $mevent, $rest) = split (/\s+/, $metaRef->{$Threshold},4) 
                                                 unless (!defined($metaRef->{$Threshold}));
                $mt = $time if !defined($mt);
                LogMonitor("$name -  $mt - $Threshold failed.");
                my($spanfail) = 0;

                if ($span && $mt < ($time - ($spanlength * $rrdpollinterval) - 90)) {
                        $spanfail = 1;
                }
                if ((!$span || $span && $spanfail) && 
                    ($persistent eq "true" || !defined($metaRef->{$Threshold})) ) {

                    LogMonitor("Triggering alarm for $Threshold.");
                    $m->Alarm($target,$name,$ds,$type,$Threshold,$actionType,\@actionArgs,$val);
                    $metaRef->{$Threshold} = ' '. $mt .' failure value '. $val;
                    $rrd->setMeta($metaRef);
                } elsif ($span && (!defined($mevent)) || (($mevent ne 'failure') && $spanfail))  {
                    LogMonitor("Triggering a span event for $Threshold.");
                    my($event) = ($spanfail) ? 'failure' : 'spanevent';
                    $m->Alarm($target,$name,$ds,$type,$Threshold,$actionType,\@actionArgs,$val) if ($spanfail);
                    $metaRef->{$Threshold} = ' '. $mt . ' ' . $event . ' value '. $val;
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

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
