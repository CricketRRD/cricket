#!/usr/bin/perl -w
# -*- perl -*-
##############################################################################
#
# metaQuery.pl - Template to use cricket meta data for communicating with
#                external network monitoring tools.
#
#    Copyright (C) 2000 Mike Fisher and Tech Data Corporation
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
#
# Created: 04/03/2004 - Francois Mikus ( fmikus _AT_ acktomic dot com) 
#

BEGIN {
	my $programdir = (($0 =~ m:^(.*/):)[0] || "./") . "..";
	eval "require '$programdir/cricket-conf.pl'";
	eval "require '/usr/local/etc/cricket-conf.pl'"
					unless $Common::global::gInstallRoot;
	$Common::global::gInstallRoot ||= $programdir;
}

use lib "$Common::global::gInstallRoot/lib";
use strict;
use Common::Options;
use Common::Log;
use ConfigTree::Cache;
use RRD::File;

Common::Log::setFormat('minimal');

$Common::global::gCT = new ConfigTree::Cache;
my ($gCT) = $Common::global::gCT;
$gCT->Base($Common::global::gConfigRoot);
$gCT->Warn(\&Warn);

if (! $gCT->init()) {
    Die("Failed to open compiled config tree from " .
		"$Common::global::gConfigRoot/config.db: $!");
}


my $VERSION = '0.9';

my ($loglevel) = 'info';
my ($devicename);
my (@trees);

# Set the default logging level
Common::Log::setLevel($loglevel);

usage() if (!$ARGV[0]);

while ($ARGV[0] && $ARGV[0] =~ /^-/) {
    my $arg = shift;

    if ($arg eq '-h' || $arg eq '--help') {
        usage();
    } elsif ($arg eq '--loglevel') {
        my $x = shift;
        Die ("Missing a value for argument --loglevel\nUse --help") if (!$x);
        $loglevel = $x;
    } elsif ($arg eq '--all') {
        push @trees, '/';
    } elsif ($arg eq '--subtree') {
        my $x = shift;
        Die ("Missing a value for argument --subtree\nUse --help") if (!$x);
        push @trees, $x;
    } elsif ($arg eq '--version') {
       version(); 
    } else {
        Die ("Unknown flag: $arg\nUse --help.");
    }
}

Common::Log::setLevel($loglevel);

sub usage {
#'
    print STDERR <<EOD;
VERSION: $VERSION
USAGE: $0 [options] hostname

   --all                 - Process all of the config-tree
   --help                - Display this information.
   --loglevel            - Change the logging level. (Default info)
                            debug, logmonitor, info, warn, error
   --subtree             - Process a specific subtree /subtreename/
                           This option can be used multiple times
   --version             - Display version number

EXAMPLE:  $0 --all --loglevel debug

EOD
#'
    exit(1);
}

sub version {

    print STDOUT "VERSION: $VERSION\n";
    exit(0);
}

# This is a sample listing of error types that can be
# returned by users of genRtrConfig and it's successors.
# These error codes should be categorized as required
# Example: if you want all errors/thresholds crosses
# to be bundled together, assign the same group to them.
#                        #error type in meta file  #group
my %mapErrorToModule = ( 'errors-carrier-trans' => 'if_err',
                         'errors-in'            => 'if_err',
                         'errors-out'           => 'if_err',
                         'errors-resets'        => 'if_err',
                         'errors-crc'           => 'if_err',
                         'congestion-FECN-in'   => 'if_err',
                         'congestion-BECN-in'   => 'if_err',
                         'bandwidth-in'         => 'if_util',
                         'bandwidth-out'        => 'if_util',
                         'congestion-in'        => 'if_util',
                         'congestion-out'       => 'if_util',
                         'rate-limit'           => 'if_util',
                         'rtt-generic-exceed'   => 'rtt',
                         'rtt-ftp-exceed'       => 'rtt-ftp',
                         'rtt-ftp-warn'         => 'rtt-ftp',
                         'rtt-http-exceed'      => 'rtt-http',
                         'rtt-generic-fail'     => 'rtt',
                         'rtt-ftp-fail'         => 'rtt-ftp',
                         'rtt-http-fail'        => 'rtt-http',
                         'memory-warn'          => 'memory',
                         'memory-alert'         => 'memory',
                         'cpu-warn'             => 'cpu',
                         'cpu-alert'            => 'cpu',
                         'anomalie-in'          => 'if_ano',
                         'anomalie-out'         => 'if_ano',
                         'cpu'                  => 'cpu',
                         'memory'               => 'memory',
                         'unclassified'         => 'unclassified',
                      );

# Global hashes that will be used to store the values of the monitor-thresholds

my %gData;
my %gDevices;

# This URL pre supposes that you are using pathinfo urls
# $gUrlStyle="pathinfo";  # URL path for authentication
my $gCRICKET = "http://127.0.0.1/cricket/grapher.cgi";

# foreach subtree to do
#   find the base node of that subtree
#   foreach leaf node of this subtree
#       process it

my($subtree);
foreach $subtree (@trees) {
    if ($gCT->nodeExists($subtree)) {
        $gCT->visitLeafs($subtree, \&myHandleTarget);
    } else {
        Warn("Unknown subtree $subtree.");
    }
}

my (@modulelist) = createModuleList(%mapErrorToModule);

sendEvents();


# Advanced debug loop
#foreach my $refData (keys %gData) {
#
#    Debug("@{$gData{$refData}}");
#}

1;

sub myHandleTarget {
	my($name) = @_;
	my(@monitor_instances);
	
	# Consult the config tree cache to get the information on that
	# specific target.
	my($tpath, $tname) = ($name =~ /^(.*)\/(.*)$/);
	my($target) = $gCT->configHash($name, 'target', undef, 1);

    # Devices should use the snmp-host variable to indicate the name
    # the device should be referred to.
	my ($targetname) = $target->{'snmp-host'};

    # Skip targets that have the nostate variable set to true
    return if (defined $target->{'nostate'} && $target->{'nostate'} eq 'true');

	# We are only interested in targets that have monitor-thresholds
	# defined in the config-tree of the META type.
	return unless ($target->{'monitor-thresholds'} && $target->{'monitor-thresholds'} =~ /:META:/);

    Debug ("$target->{'monitor-thresholds'}");
    Debug ("### TargetName $tname ###"); 

    ### Start meta file processing

    # find out the location of the meta data file 
    my($rrd) = new RRD::File( -file=>$target->{'rrd-datafile'} );

    # Look for active meta data
    my($refMeta) = $rrd->getMeta();

    foreach my $key (keys %{$refMeta}) {
        Debug ("Thresholds key: $key data: $refMeta->{$key}");
    }

    ### End meta file processing

	my ($a, $subtree, @path)  = split (/\//, $tpath);

	# Creating a path that is unique up to the point of the targetname
	my ($shortpath)  = split (/$targetname/, $name);
	$shortpath .= $targetname;

	# Rename the devicename to the Config-Tree path which will be used to refer to all
	# the different hashes + the logical name of the network device, 
	# these will be used to build the HTTP path to the Cricket grapher.cgi and to reference the device
	my ($devicename) = $targetname;

	my ($instance) = mapinstance($targetname, @path);

	if (defined $instance) {
		$tname = $instance . "=" . $tname;
		Debug ("Found an instance, update TargetName: $tname");
	}

	# Take a note of all the distinct routers for which we found monitor-thresholds
	# This will make it easier to process the devices only once.
	if (!exists $gDevices{$devicename}) {
		$gDevices{$devicename} = $shortpath; 
	}

	# Process each monitor threshold and create an entry containing
    # the message, references to active alarms, the ds
    # and the device it belongs to.

	my (@monitors) = split (/,\s+/, $target->{'monitor-thresholds'});
    my (%monitors);
    my ($cnt) = 0;
	foreach my $monitor (@monitors) {
        $cnt += 1;
		next unless $monitor =~ /:META:/;
        
        # Seperate both sides, as they could have a variable number of arguments
		my ($thresh_args, $meta_args) = split(/:META:/,$monitor);
		my (@thresh_args) = split(/:/,$thresh_args);

        # Process optional META options contained in the monitor threshold
		my (@meta_args) = split(/:/,$meta_args);
        my ($errorname) = shift(@meta_args);
        my ($colour) = shift(@meta_args);
        $colour = 'green' if (!$refMeta->{$monitor});
        my ($ds) = $thresh_args[0]; # Do not unshift as we want to use the variable later

        # Convert floats with excessive precision to something more digestible
        my $value     = cleanupValue($refMeta->{$monitor}) if $refMeta->{$monitor};

        # Replace the colour from the monitor with purple if data could not be retrieved
        # by the monitor threshold engine, this is indicated by NaN.
        $colour = 'purple' if ($value && $value =~ /NaN/i);

        my $module    = $mapErrorToModule{$errorname};
        Warn("Invalid or unset monitor threshold errorname, $errorname, for $devicename\nExpected format: <thresold>:META:<errorname>:<colour>") if (!$module);
        #next if (!$module); # Uncomment this for strict processing of errornames
        $module = "unclassified" if (!$module);        
 
        my $html_path = getHtmlPath($tname, $devicename, $shortpath, $module, $ds);
        my ($message) = "$errorname, OK.";
        $message = "$errorname on value $value, for $thresh_args of $tname." if ($value);
        
        # Build a unique key with == seperator tokens, and store the data as an anonymous array
        $gData{$devicename ."==". $module ."==". $cnt} = [$html_path, $ds, $colour, $message];
        Info("key: " .  $devicename ."==". $module ."==". $cnt . "value: " . $html_path . " " . $ds . " " . $colour . " " . $message);
    }
}

sub  processKey {
	my ($path, $devicename) = @_;
	my ($division,$location,$rest) = split (/-/, $devicename);

	my (@path) = split (/\//,$path);
	my ($href) = "<A HREF=\"" . $gCRICKET; # . "target=";
	foreach my $e (@path) {
		if ($e eq $devicename) {
			$href .= "/$devicename\">$devicename</A>";
			last;
		}
		if ($e ne "") {
			$href .= "/$e";
		}
	}

	return ($division,$location,$devicename,$href);
}

sub  instanceToHREF {

	my ($path, $devicename, $instance, $view) = @_;
	my (@instance) = split(/=/, $instance);
	my (@path) = split (/\//,$path);

	my ($division,$location,$rest) = split (/-/, $devicename);


	my ($href_instance) = "<A HREF=\"" . $gCRICKET . "target=";

	foreach my $e (@path) {
		if ($e eq $devicename) {
			$href_instance .= "%2F$devicename";
			last;
		}
		if ($e ne "") {
			$href_instance .= "%2F$e";
		}
	}

	foreach my $piece (@instance) {
		$href_instance .= "%2F" . $piece;
	}
	
    # Warning: It may be necessary to escape some of the caracters used in the url
	$href_instance .= "&ranges=d%3Aw&view=" . $view . "\">$devicename @instance</A>";

	return ($href_instance);

}

sub mapinstance {

   my ($targetname) = shift;
   my (@path) = @_;
   my ($instance);

   # Instance name and slot number if applicable for Catalyst CatOS Switches and others
    foreach my $c (reverse (@path)) {
        if (($c eq $targetname) || (!defined $c)){
            chop $instance unless (!defined $instance);
            last;
        } else {
            $instance .= $c . "-";
        }
    }

    return ($instance);
}

sub cleanupValue {
    my ($value) = @_;
    return if (!$value);

    ($value) = $value =~ /\s*value (\S+)$/;
    return "undef" if (!$value);
    # Return the value if it is not a floating point
    return ($value) if ($value !~ /^\d+\.\d+$/);
    
    # Remove extraneous precision from floating point variables
    return (sprintf("%.0f ", $value))  if ($value > 100);    
    return (sprintf("%.2f ", $value))  if ($value > 1);    
    return (sprintf("%.3f ", $value));

}

sub createModuleList {

    my (%mapping) = @_;
    my (%uniqueModule);
    foreach my $error (keys %mapping) {
        $uniqueModule{$mapping{$error}} = 1 if (!exists $uniqueModule{$mapping{$error}});
    }
    my (@placeholder) = (keys %uniqueModule);
    return @placeholder;
}

sub getHtmlPath {

    my ($tname, $devicename, $shortpath, $module, $ds) = @_;

    return $devicename;
}

################################################################################
### This sub should process the events in whatever format is required
### and send to the event management system.
################################################################################

sub sendEvents {

    # Do something useful with the compilation of error messages, status and html links.
    # Send that useful compilation to an event management system.

}
