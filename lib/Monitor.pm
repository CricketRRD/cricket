# Cricket: a configuration, polling and data display wrapper for RRD files
#
#    Copyright (C) 1998 Javier Muniz and WebTV Networks, Inc.
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

package Monitor;

use strict;
use snmpUtils;
use RRD::File;
use Common::Log;

# Registered monitors
$Common::global::gMonitorTable{'value'} = \&monValue;
$Common::global::gMonitorTable{'hunt'} = \&monHunt;
$Common::global::gMonitorTable{'relation'} = \&monRelation;
$Common::global::gMonitorTable{'exact'} = \&monExact;
# Support for aberrant behavior detection
$Common::global::gMonitorTable{'failures'} = \&monFailures;
$Common::global::gMonitorTable{'quotient'} = \&monQuotient;

sub new {
    my($package) = @_;
    my $self = { };
    bless $self, $package;
    return $self;
}

sub monValue {
    my($self,$target,$ds,$type,$args) = @_;
    my($min,$max,$minOK,$maxOK);
    my(@Thresholds) = split(/\s*:\s*/, $args);

    my($value) = $self->rrdFetch(
                                 $target->{'rrd-datafile'},
                                 $self->getDSNum($target, $ds), 0
                                 );

    if (!defined($value)) {
        Warn("Skipping: Couldn't fetch last value from datafile.");
        return 1;
    }

    if (isNaN($value))  {
        Info("Skipping: Last value from datafile was $value.");
        return 1;
    }

    $min = shift(@Thresholds);
    $min = 'n' if (! defined($min));

    if (lc($min) eq 'n') {
        $minOK = 1;
    } else {
        $minOK = ($value > $min) ? 1 : 0;
    }

    $max = shift(@Thresholds);
    $max = 'n' if (! defined($max));

    if (lc($max) eq 'n') {
        $maxOK = 1;
    } else {
        $maxOK = ($value < $max) ? 1 : 0;
    }
    Debug ("Value is $value; min is $min; max is $max");
    return ($maxOK && $minOK,$value);
}

sub monHunt {
    my($self,$target,$ds,$type,$args) = @_;

    my($roll, $cmp_name, $cmp_ds) = split(/\s*:\s*/, $args);

    if (!defined($roll)) {
        Warn("Skipping: Missing rollover value in hunt threshold.");
        return 1;
    }

    # Fetch the current value from target's rrd file
    my($value) = $self->rrdFetch($target->{'rrd-datafile'},
                                 $self->getDSNum($target, $ds), 0);

    if (!defined($value)) {
        Warn("Skipping: Couldn't fetch last value from datafile.");
        return 1;
    }
    if ($value == 0) {
        return 1; # no rollover, test succeeded.
    }

    my($cmp_target);
    if (defined($cmp_name)) {
        $cmp_name = join('/',$target->{'auto-target-path'},$cmp_name)
            if (!($cmp_name =~ /^\//));

        $cmp_target = $Common::global::gCT->configHash(lc($cmp_name), 'target');
        if (defined($cmp_target)) {
            ConfigTree::Cache::addAutoVariables(lc($cmp_name), $cmp_target,
                                                $Common::global::gConfigRoot);
            ConfigTree::Cache::expandHash($cmp_target, $cmp_target, \&Warn);
        } else {
            Warn("Skipping: No such target: $cmp_name");
            return 1;
        }
    } else {
        $cmp_target = $target;
    }

    $cmp_ds = $ds unless ($cmp_ds);
    my($cmp_value) = $self->rrdFetch($cmp_target->{'rrd-datafile'},
                                     $self->getDSNum($cmp_target, $cmp_ds), 0);

    if (!defined($cmp_value)) {
        Warn("Skipping: Couldn't fetch current value from $cmp_name");
        return 1;
    }

    return ($cmp_value >= $roll);
}

# if X and Y are data sources (Y is possibly X shifted by some temporal offset)
# and Z is a threshold, then a relation monitor checks:
# abs(Y - X)/Y > Z for Z a percentage (marked pct)
# abs(Y - X) > Z for Z not a percentage
# Default > can be replaced with <
# return 1 if the check passes or error, 0 if fail
sub monRelation {
    my($self, $target, $ds, $type, $args) = @_;

    my($thresh, $cmp_name, $cmp_ds, $cmp_time) = split(/\s*:\s*/, $args);
    my($pct) = ($thresh =~ s/\s*pct\s*//i);
    $cmp_time = 0 unless(defined($cmp_time));

    if (!defined($thresh) || !defined($cmp_time)) {
        Warn("Skipping: Improperly formatted relation monitor.");
        return 1;
    }

    my($gtlt);
    if (substr($thresh,0,1) eq '<' || substr($thresh,0,1) eq '>') {
        $gtlt = substr($thresh,0,1);
        $thresh = substr($thresh,1);
    } else {
        $gtlt = '>';
    }

    # Fetch the current value from target's rrd file
    my($value) = $self->rrdFetch($target->{'rrd-datafile'},
                                 $self->getDSNum($target,$ds), 0);

    if (!defined($value)) {
        Warn("Skipping: Couldn't fetch last value from datafile.");
        return 1;
    }

    my($cmp_value) = $self -> FetchComparisonValue($target,$ds,$cmp_name,$cmp_ds,$cmp_time);
    return (1,'NaN') if isNaN($cmp_value);

    my($difference) = abs($cmp_value - $value);
    $thresh = abs($thresh); # differences are always positive

    if ($pct) {
        # threshold is a percentage
        if ($cmp_value == 0) {
            #avoid division by 0
            if ($difference == 0 && $gtlt eq '<') {
                return (1,$value);
            } else {
                return (0,$value);
            }
        }
        $difference = $difference / abs($cmp_value) * 100;
    }
    Debug("Values $value, $cmp_value; Difference is $difference; gtlt is $gtlt; thresh is $thresh.");
# see documentation: threshold fails if expression is false
    return (0,$value) if ((eval "$difference $gtlt $thresh") == 0);
    return (1,$value);
}

sub monExact {
    my($self,$target,$ds,$type,$args) = @_;
    my(@args) = split(/\s*:\s*/, $args);

    if (@args != 1) {
        Warn("Skipping: monitor type \"exact\" requires 1 argument.");
        return 1;
    }
    my $exact = shift @args;

    my($value) = $self->rrdFetch(
                                 $target->{'rrd-datafile'},
                                 $self->getDSNum($target, $ds), 0
                                 );

    if (!defined($value)) {
        Warn("Skipping: Couldn't fetch last value from datafile.");
        return 1;
    }

    return $exact eq $value ? 0 : 1;
}

# check the FAILURES array for failure recorded by the aberrant behavior
# detection algorithm in RRD
# Return values: 1 = success
#                0 = failure
# Returns 1 on default or unexpected error
sub monFailures {
    my($self, $target, $ds, $type, $args) = @_;

    # only check value range if specified, as this requires fetching from the RRD
    if ($args =~ /:/) {
        # monValue returns 0 if out of range, 1 otherwise
        my ($rc, $value) = $self->monValue($target,$ds,'value',$args);
        Debug("value is $value, in range $rc");
        # value is out of range, so ignore any failure alarm
        if ($rc == 0) { return 1 };
    }
    my $datafile = $target->{'rrd-datafile'};
    my $dsNum = $self->getDSNum($target, $ds);
    return 1 if (!defined($dsNum));
    return 1 if (!defined($datafile));
    # open the file if not already open
    if (!defined($self->{currentfile}) || $datafile ne $self->{currentfile}) {
        my($rrd) = new RRD::File( -file => $datafile );
        return 1 if (!$rrd->open() || !$rrd->loadHeader());
        $self->{currentfile} = $datafile;
        $self->{openrrd} = $rrd;
    }
    # check for a valid $dsNum
    return 1 unless ($dsNum < $self->{openrrd}->ds_cnt());
    # find the FAILURES RRA
    my $rra;
    my $rraNum;
    for($rraNum = 0; $rraNum <= $#{$self->{openrrd}->{rra_def}}; $rraNum++) {
        $rra = $self->{openrrd}->rra_def($rraNum);
        last if ($rra -> {rraName} eq 'FAILURES');
    }
    return 1 if ($rra -> {rraName} ne 'FAILURES');

    # retrieve the most recent value
    my $ret;
    $ret = $self->{openrrd}->getDSRowValue($rraNum,0,$dsNum);
    if (!defined($ret)) {
        Warn("Skipping: Couldn't fetch last value from datafile FAILURES RRA.");
        return 1;
    }
    # FAILURES array stores a 1 for a failure (so should return 0)
    return 1 if isNaN($ret);
    return !($ret);
}

# if X and Y are data sources (Y is possibly X shifted by some temporal offset)
# and Z is a threshold, then a quotient monitor checks:
# X/Y > Z for Z a percentage (marked pct)
# abs(Y - X) > Z for Z not a percentage (deprecated)
# Default > can be replaced with <
# return 1 if the check passes or error, 0 if fail
sub monQuotient {
    my($self, $target, $ds, $type, $args) = @_;

    my($thresh, $cmp_name, $cmp_ds, $cmp_time) = split(/\s*:\s*/, $args);
    my($pct) = ($thresh =~ s/\s*pct\s*//i);
    $cmp_time = 0 unless(defined($cmp_time));
    Info("Use of quotient monitors without percent threshold is deprecated")
        unless (defined($pct));

    if (!defined($thresh) || !defined($cmp_time)) {
        Warn("Skipping: Improperly formatted quotient monitor.");
        return 1;
    }

    my($gtlt);
    if (substr($thresh,0,1) eq '<' || substr($thresh,0,1) eq '>') {
        $gtlt = substr($thresh,0,1);
        $thresh = substr($thresh,1);
    } else {
        $gtlt = '>';
    }
    # Fetch the current value from target's rrd file
    my($value) = $self->rrdFetch($target->{'rrd-datafile'},
                                 $self->getDSNum($target,$ds), 0);

    if (!defined($value)) {
        Warn("Skipping: Couldn't fetch last value from datafile.");
        return 1;
    }

    my $cmp_value = $self -> FetchComparisonValue($target,$ds,$cmp_name,$cmp_ds,$cmp_time);
    return 1 if isNaN($cmp_value);

    my($difference) = abs($cmp_value - $value);
    $thresh = abs($thresh); # differences are always positive

    if ($pct) {
        # threshold is a percentage
        if ($cmp_value == 0) {
            # avoid division by 0
            if ($difference == 0 && $gtlt eq '>') {
                return 1;
            } else {
                return 0;
            }
        }
        $difference = abs($value/$cmp_value) * 100;
    }
    Debug("Difference is $difference; gtlt is $gtlt; thresh is $thresh.");
    return (0,$value) if (eval "$difference $gtlt $thresh");
    return (1,$value);
}

# shared code used by monRelation and monQuotient
sub FetchComparisonValue {
    my($self,$target,$ds,$cmp_name,$cmp_ds,$cmp_time) = @_;
    my($cmp_target);
    if (! $cmp_name) {
        $cmp_target = $target;
    } else {
        $cmp_name = join('/',$target->{'auto-target-path'}, $cmp_name)
            if (!($cmp_name =~ /^\//));

        $cmp_target = $Common::global::gCT->configHash(lc($cmp_name), 'target');
        if (defined($cmp_target)) {
            ConfigTree::Cache::addAutoVariables(lc($cmp_name), $cmp_target,
                                                $Common::global::gConfigRoot);
            ConfigTree::Cache::expandHash($cmp_target, $cmp_target, \&Warn);
        } else {
            Warn("Skipping: No such target: $cmp_name");
            return 'NaN';
        }
    }

    $cmp_ds = $ds unless ($cmp_ds);

    my($cmp_value) = $self->rrdFetch($cmp_target->{'rrd-datafile'},
                                     $self->getDSNum($cmp_target,$cmp_ds),
                                     $cmp_time);

    if (!defined($cmp_value)) {
        Warn("Skipping: Couldn't fetch value for $cmp_time ".
             "seconds ago from $cmp_name.");
        return 'NaN';
    }

    if (isNaN($cmp_value)) {
        Info("Skipping: Data for $cmp_time seconds ago from " .
             "$cmp_name is NaN");
        return 'NaN';
    }
    return $cmp_value;
}

# fetches any data you might need from a rrd file
# in a RRA with consolidation function AVERAGE
# caching the open RRD::File object for later use
# if possible.
sub rrdFetch {
    my($self,$datafile,$dsNum,$sec) = @_;
    # check all of our arguments;
    return if (!defined($dsNum));
    return if (!defined($sec));
    return if (!defined($datafile));
    Debug("in rrdFetch: file is $datafile");
    if (!defined($self->{currentfile}) || $datafile ne $self->{currentfile}) {
        my($rrd) = new RRD::File( -file => $datafile );
        return if (!$rrd->open() || !$rrd->loadHeader());
        $self->{currentfile} = $datafile;
        $self->{openrrd} = $rrd;
    }
    return unless ($dsNum < $self->{openrrd}->ds_cnt());

    my($rra,$lastrecord,$rraNum);
    for($rraNum = 0; $rraNum <= $#{$self->{openrrd}->{rra_def}}; $rraNum++) {
        $rra = $self->{openrrd}->rra_def($rraNum);
        # if the consolidation function is not AVERAGE, we can
        # skip this RRA
        Debug("in rrdFetch: skipping RRA");
        next if ($rra->{rraName} ne "AVERAGE");
        $lastrecord = $rra->{row_cnt} * $rra->{pdp_cnt} *
            $self->{openrrd}->pdp_step();
        last if ($lastrecord >= $sec);
    }

    if ($lastrecord < $sec) {
        Warn("Fetch Failed: RRD file does not have data going back " .
             "$sec seconds.");
        return;
    }

    if ($sec % ($lastrecord / $rra->{row_cnt})) {
        Warn("Fetch Failed: RRA required to find data $sec seconds ago " .
             "is too granular.");
        return;
    }

    my($rowNum) = $sec / ($self->{openrrd}->pdp_step() * $rra->{pdp_cnt});
    Debug("in rrdFetch: rraNum is $rraNum rowNum is $rowNum dsNum is $dsNum");

    my ($foo) = $self->{openrrd}->getDSRowValue($rraNum,$rowNum,$dsNum);
    Debug("in rrdFetch: return is $foo");
    return $self->{openrrd}->getDSRowValue($rraNum,$rowNum,$dsNum);
}

# Given a target reference and datasource name,
# returns the datasource number or undef if no
# datasource of that name can be found in target's
# target-type dictionary
sub getDSNum {
    my($self, $target, $dsName) = @_;
    my($ttRef) = $Common::global::gCT->configHash(
                                 join('/',$target->{'auto-target-path'},
                                      $target->{'auto-target-name'}),
                                                  'targettype',
                                                  lc($target->{'target-type'}),
                                                  $target);
    my($Counter) = 0;
    my(%dsMap) = map { $_ => $Counter++ } split(/\s*,\s*/,$ttRef->{'ds'});

    return $dsMap{$dsName};
}

# Subroutines to handle alarms

sub dispatchAlarm {
# order of arguments: $self, $target, $name, $ds, $type, $threshold,
#                     $alarmType, $alarmArgs, $val
    my ($args, $action) = @_;

    my ($target, $ds, $val) = ($$args[1], $$args[3], $$args[8]);

    if (defined($val) && isNaN($val)) {
        Info("NaN in last value for target: $target->{'auto-target-path'} $target->{'auto-target-name'} for $ds.");
        return (0,'NaN');
    }

    my $alarmType       = $$args[6];

    my %dispatch = (
        EXEC => \&alarmExec,
        FILE => \&alarmFile,
        FUNC => \&alarmFunc,
        MAIL => \&alarmMail,
        SNMP => \&alarmSnmp,
        META => \&alarmMeta,
    );

    my $alarm = $dispatch{$alarmType};

    unless (defined($alarm)) { Warn("Unknown alarm: $alarmType"); return; }

    my $return = $alarm->($args, $action);
    return;
};


# Process alarm action
sub Alarm {
# order of arguments: $self, $target, $name, $ds, $type, $threshold,
#                     $alarmType, $alarmArgs, $val
    my $action = 'ADD';

    my $return = \&dispatchAlarm(\@_, $action);
    return;
};

# Action to clear an alarm
sub Clear {
# order of arguments: $self, $target, $name, $ds, $type, $threshold,
#                     $alarmType, $alarmArgs, $val
    my $action = 'CLEAR';

    my $return = \&dispatchAlarm(\@_, $action);
    return;
};

sub alarmExec {
    my ($args, $action) = @_;
    my $alarmArgs       = $$args[7];
    system($alarmArgs->[0]);

    if ($action eq 'ADD') {
        Info("Triggered event with system command '".$alarmArgs->[0]."' .");
    }

    else {
        Info("Cleared event with shell command '".$alarmArgs->[1]."' .");
    }

    return;
};

sub alarmFile {
    my ($args, $action)  = @_;
    my ($self, $target)    = ($$args[0], $$args[1]);
    my ($name, $ds)        = ($$args[2], $$args[3]);
    my ($type, $threshold) = ($$args[4], $$args[5]);
    my ($alarmArgs, $val)  = ($$args[7], $$args[8]);

    $self->LogToFile($alarmArgs, $action, $name, $ds, $val);
    return;
};

sub alarmFunc {
    my ($args, $action) = @_;
    my $alarmArgs       = $$args[7];

    if (defined $main::gMonFuncEnabled) {

        if ($action eq 'ADD') {
            eval($alarmArgs->[0]);
            Info("Triggered event with FUNC '".$alarmArgs->[0]."' .");
        }

        elsif ($action eq 'CLEAR') {
            eval($alarmArgs->[1]);
            Info("Cleared event with FUNC '".$alarmArgs->[1]."' .");
        }

    }

    else {
        Warn("Exec triggered, but executable alarms are not enabled.");
    }

    return;
};

sub alarmMail {
    my ($args, $action)    = @_;
    my ($self, $target)    = ($$args[0], $$args[1]);
    my ($name, $ds)        = ($$args[2], $$args[3]);
    my ($type, $threshold) = ($$args[4], $$args[5]);
    my ($alarmArgs, $val)  = ($$args[7], $$args[8]);
    $self->sendEmail( $action, $alarmArgs, $type, $threshold,
                      $name, $ds, $val, $target->{'inst'} );
    return;
};

sub alarmSnmp {
    my ($args, $action)    = @_;
    my ($self, $target)    = ($$args[0], $$args[1]);
    my ($name, $ds)        = ($$args[2], $$args[3]);
    my ($type, $threshold) = ($$args[4], $$args[5]);
    my ($val)              = ($$args[8]);

    my $Specific_Trap_Type = $action eq 'ADD' ? 4 : 5;
    $self->sendMonitorTrap( $target, $Specific_Trap_Type, $type,
                            $threshold, $name, $ds, $val );
    return;
};

sub alarmMeta {
    my ($args, $action)    = @_;

    # No action is required.
    # Alarm data is already stored in the Cricket meta files by HandleTarget.pm
    # The meta data is stored in $CRICKET/cricket-data/ directories.
    return;
};

# Attempt to send an alarm trap for a given target
sub sendMonitorTrap {
    my($self,$target,$spec,$type,$threshold,$name,$ds,$val) = @_;

    my $to = $target -> {'trap-address'};
    if (!defined($to)) {
        Warn("No trap address defined for $target, couldn't send trap.");
        Info("Threshold Failed: $threshold for target $target");
        return;
    }

    my($OID_Prefix) = '.1.3.6.1.4.1.2595.1.3'; # OID for Cricket Violations

    my(@VarBinds);
    push(@VarBinds, "${OID_Prefix}.1", 'string', $type);
    push(@VarBinds, "${OID_Prefix}.2", 'string', $threshold);
    # name is the fully qualified target name
    push(@VarBinds, "${OID_Prefix}.3", 'string', $name);
    push(@VarBinds, "${OID_Prefix}.4", 'string', $ds);
    my($logName) = "cricket";
    if (!Common::Util::isWin32() && defined($ENV{'LOGNAME'})) {
        $logName = $ENV{'LOGNAME'};
    }
    push(@VarBinds, "${OID_Prefix}.5", 'string', $logName);
    # Common::HandleTarget overloads this tag
    # for scalar targets, it could be "" or 0
    # otherwise, it is set the instance number
    if ($target->{'inst'}) {
        push(@VarBinds, "${OID_Prefix}.6", 'string', $target->{'inst'});
    }
    if (defined($target->{'inst-name'})) {
        push(@VarBinds, "${OID_Prefix}.7", 'string', $target->{'inst-name'});
    }
    # send the html contact-name
    my $htmlRef = $Common::global::gCT -> configHash($name,'html');
    if (defined($htmlRef -> {'contact-name'})) {
        # parse the mailto tag
        my $tag = $htmlRef -> {'contact-name'};
        if ($tag =~ /mailto\:([A-Z,a-z,.,@]+)/) {
            push(@VarBinds, "${OID_Prefix}.8", 'string', $1);
        }
    }
    push(@VarBinds, "${OID_Prefix}.9", 'string', $val) unless (!defined($val));

    Info("Trap Sent to $to:\n ". join(' -- ',@VarBinds));
    snmpUtils::trap2($to,$spec,@VarBinds);
}

sub LogToFile {
    my ($self, $filePath, $action, $targetName, $dataSourceName) = @_;
    my @lines = ();
    my $targetLine;

    return unless ($action eq 'ADD' || $action eq 'CLEAR');

    # try to open for read first and hunt for duplicate lines
    my $bFound = 0;

    if (open(INFILE, "$filePath")) {
        $targetLine = $targetName . " " . $dataSourceName;
        while (<INFILE>) {
            chomp;
            if ($_ eq $targetLine) {
                $bFound = 1;
                # nothing to add
                last if ($action eq 'ADD');
            } else {
                push (@lines, $_) if ($action eq 'CLEAR');
            }
        }
    }

    unless (open(INFILE, "+>>$filePath")) {
        Info("Failed to open file $filePath");
        return;
    }


    # append the new line to the end of the file
    if ($action eq 'ADD' && $bFound == 0) {
        Info("Appending line $targetLine to $filePath");
        print INFILE $targetLine . "\n";
        close(INFILE);
        return;
    }

    # don't need INFILE anymore
    close(INFILE);

    if ($action eq 'ADD' && $bFound == 1) {
        Info("$targetName $dataSourceName already in file $filePath");
        return;
    }

    if ($action eq 'CLEAR' && $bFound == 0) {
        Info("$targetName $dataSourceName already deleted from file $filePath");
        return;
    }
    # need to print out @lines, which excludes the $targetLine
    # overwrite old file
    unless (open(OUTFILE, ">$filePath")) {
        Info("Failed to open file $filePath");
        return;
    }
    Info("Deleting $targetLine from $filePath");
    print OUTFILE join("\n", @lines);
    print OUTFILE "\n" unless (scalar(@lines) == 0);
    close(OUTFILE);
}

sub sendEmail {
    my($self, $spec, $alarmArgs, $type, $threshold, $target, $ds, $val, $inst) = @_;

    my $to = $alarmArgs -> [1];
    if (!defined($to)) {
        Warn("No destination address defined for $target, couldn't send email.");
        return;
    }

    my @Message;
    push @Message, "type:\t\t$type";
    push @Message, "threshold:\t$threshold";
    push @Message, "target:\t$target";
    push @Message, "ds:\t\t$ds";
    if (defined($val))  {
        push @Message, "val:\t\t$val";
    }
    # for scalar targets, inst is either "" or 0
    if ($inst) {
        push @Message, "inst:\t\t$inst";
    }

    my $mail_program = $alarmArgs -> [0];
    if (!defined($mail_program)) {
        Warn("No email-program defined. Not sending email");
        return;
    } elsif (!open(MAIL, "|$mail_program -s 'Cricket $spec: $target' $to\n")) {
        Warn("Failed to open pipe to mail program");
        return;
    }
    Debug("|$mail_program -s 'Cricket $spec: $target' $to\n");
    print (MAIL join ("\n", @Message));
    Info("Email sent to: $to\n" . join(' -- ', @Message));
    close(MAIL);
}
1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
