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

	if(!defined($value)) {
		Warn("Skipping: Couldn't fetch last value from datafile.");
		return 1;
	}

	$min = shift(@Thresholds);
	$min = 'n' if (! defined($min));

	if(lc($min) eq 'n') {
		$minOK = 1;
	} else {
		$minOK = ($value > $min);
	}

	$max = shift(@Thresholds);
	$max = 'n' if (! defined($max));

	if(lc($max) eq 'n') {
		$maxOK = 1;
	} else {
		$maxOK = ($value < $max)
	}

	return ($maxOK && $minOK);
}

sub monHunt {
	my($self,$target,$ds,$type,$args) = @_;

	my($roll, $cmp_name, $cmp_ds) = split(/:/, $args);

	if(!defined($roll)) {
		Warn("Skipping: Missing rollover value in hunt threshold.");
		return 1;
	}

	# Fetch the current value from target's rrd file
	my($value) = $self->rrdFetch($target->{'rrd-datafile'},
					$self->getDSNum($target, $ds), 0);

	if(!defined($value)) {
		Warn("Skipping: Couldn't fetch last value from datafile.");
		return 1;
	}
	if($value == 0) {
		return 1; # no rollover, test succeeded.
	}

	my($cmp_target);
	if (defined($cmp_name)) {
		$cmp_name = join('/',$target->{'auto-target-path'},$cmp_name)
				if(!($cmp_name =~ /^\//));

		$cmp_target = $Common::global::gCT->configHash(lc($cmp_name), 'target');
		if(defined($cmp_target)) {
			ConfigTree::Cache::addAutoVariables(lc($cmp_name),
				$cmp_target, $Common::global::gConfigRoot);
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

	if(!defined($cmp_value)) {
		Warn("Skipping: Couldn't fetch current value from $cmp_name");
		return 1;
	}

	return ($cmp_value >= $roll);
}

sub monRelation {
	my($self, $target, $ds, $type, $args) = @_;

	my($thresh, $cmp_name, $cmp_ds, $cmp_time) = split(/:/, $args);
	my($pct) = ($thresh =~ s/\s*pct\s*//i);
	$cmp_time = 0 unless(defined($cmp_time));

	if(!defined($thresh) || !defined($cmp_time)) {
		Warn("Skipping: Improperly formatted relation monitor.");
		return 1;
	}

	my($gtlt);
	if(substr($thresh,0,1) eq '<' || substr($thresh,0,1) eq '>') {
		$gtlt = substr($thresh,0,1);
		$thresh = substr($thresh,1);
	} else {
		$gtlt = '>';
	}

	# Fetch the current value from target's rrd file
	my($value) = $self->rrdFetch($target->{'rrd-datafile'},
									$self->getDSNum($target,$ds), 0); 

	if(!defined($value)) {
		Warn("Skipping: Couldn't fetch last value from datafile.");
		return 1;
	}

	my($cmp_target);
	if(! $cmp_name) {
		$cmp_target = $target;
	} else {
		$cmp_name = join('/',$target->{'auto-target-path'}, $cmp_name)
			if (!($cmp_name =~ /^\//));

		$cmp_target = $Common::global::gCT->configHash(lc($cmp_name), 'target');
		if(defined($cmp_target)) {
			ConfigTree::Cache::addAutoVariables(lc($cmp_name),
							$cmp_target, $Common::global::gConfigRoot);
			ConfigTree::Cache::expandHash($cmp_target, $cmp_target, \&Warn);
		} else { 
			Warn("Skipping: No such target: $cmp_name");
			return 1;
		}
	}

	$cmp_ds = $ds unless ($cmp_ds);

	my($cmp_value) = $self->rrdFetch($cmp_target->{'rrd-datafile'},
							$self->getDSNum($cmp_target,$cmp_ds), $cmp_time);

	if(!defined($cmp_value)) {
		Warn("Skipping: Couldn't fetch value for $cmp_time ".
				"seconds ago from $cmp_name.");
		return 1;
	}

	if($cmp_value =~ /NaN/) {
		Info("Skipping: Data for $cmp_time seconds ago from " .
				"$cmp_name is NaN");
		return 1;
	}

	my($difference) = abs($cmp_value - $value);
	$thresh = abs($thresh); # differences are always positive

	if(defined($pct)) {
		# threshold is a percentage
		if($cmp_value == 0) {
			# avoid division by 0 
			if($difference == 0 && $gtlt eq '<') {
				return 1;
			} else {
				return 0; 
			}
		}
		$difference = $difference / abs($cmp_value) * 100;
	}
	return 0 if(!(eval "$difference $gtlt $thresh"));
	return 1;
}

# fetches any data you might need from an rrd file
# caching the open RRD::File object for later use
# if possible.
sub rrdFetch {
	my($self,$datafile,$dsNum,$sec) = @_;
	# check all of our arguments;
	return if(!defined($dsNum));
	return if(!defined($sec));
	return if(!defined($datafile));
	if(!defined($self->{currentfile}) || $datafile ne $self->{currentfile}) {
		my($rrd) = new RRD::File( -file => $datafile );
		return if(!$rrd->open() || !$rrd->loadHeader()); 
		$self->{currentfile} = $datafile;
		$self->{openrrd} = $rrd;
	}
	return unless ($dsNum < $self->{openrrd}->ds_cnt());

	my($rra,$lastrecord,$rraNum);
	for($rraNum = 0; $rraNum <= $#{$self->{openrrd}->{rra_def}}; $rraNum++) {
		$rra = $self->{openrrd}->rra_def($rraNum);
		$lastrecord = $rra->{row_cnt} * $rra->{pdp_cnt} *
						$self->{openrrd}->pdp_step();
		last if($lastrecord >= $sec);
	}

	if($lastrecord < $sec) { 
		Warn("Fetch Failed: RRD file does not have data going back " .
				"$sec seconds."); 
		return;
	}

	if($sec % ($lastrecord / $rra->{row_cnt})) {
		Warn("Fetch Failed: RRA required to find data $sec seconds ago " .
				"is too granular.");
		return;
	}

	my($rowNum) = $sec / ($self->{openrrd}->pdp_step() * $rra->{pdp_cnt});

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
			$target->{'target-type'}, 
			$target);
	my($Counter) = 0;
	my(%dsMap) = map { $_ => $Counter++ } split(/\s*,\s*/,$ttRef->{'ds'});
	return $dsMap{$dsName};
}

# Subroutines to handle alarms

# Action to send an alarm, you can change this to do whatever you need
# Default is to send a trap
sub Alarm {
	my($self,$target,$name,$ds,$type,$threshold) = @_;
	my($Specific_Trap_Type) = 4; # Violation Trap
	$self->sendMonitorTrap(
				$target->{'trap-address'},
				$Specific_Trap_Type,
				$type,
				$threshold,
				$name,
				$ds );
}

# Action to clear an alarm, you can change this to do whatever you need
# Default is to send a trap
sub Clear {
	my($self,$target,$name,$ds,$type,$threshold) = @_;
	my($Specific_Trap_Type) = 5; # Clear Trap
	$self->sendMonitorTrap(
				$target->{'trap-address'},
				$Specific_Trap_Type,
				$type,
				$threshold,
				$name,
				$ds );
}

# Attempt to send an alarm trap for a given target
sub sendMonitorTrap {
	my($self,$to,$spec,$type,$threshold,$target,$ds) = @_;

	if(!defined($to)) {
		Warn("No trap address defined for $target, couldn't send trap.");
		Info("Threshold Failed: $threshold for target $target");
		return;
	}

	my($OID_Prefix) = '.1.3.6.1.4.1.2595.1.3'; # OID for Cricket Violations

	my(@VarBinds);
	push(@VarBinds, "${OID_Prefix}.1", 'string', $type);
	push(@VarBinds, "${OID_Prefix}.2", 'string', $threshold);
	push(@VarBinds, "${OID_Prefix}.3", 'string', $target);
	push(@VarBinds, "${OID_Prefix}.4", 'string', $ds);

	Info("Trap Sent to $to:\n ". join(' -- ',@VarBinds));
	snmpUtils::trap2($to,$spec,@VarBinds);
}

1;
