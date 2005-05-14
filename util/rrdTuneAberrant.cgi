#!/usr/bin/perl -wT
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
    # this script lives in the util subdirectory
    my $programdir = (($0 =~ m:^(.*/)util:)[0] || "./") . ".";
    eval "require '$programdir/cricket-conf.pl'";
    eval "require '$programdir/../cricket-conf.pl'"
                    unless $Common::global::gInstallRoot;
    $Common::global::gInstallRoot ||= $programdir;
}

use lib "$Common::global::gInstallRoot/lib";

use CGI qw(carpout fatalsToBrowser);
use RRDs 1.000101;
use ConfigTree::Cache;
use Common::Version;
use Common::global;
use Common::HandleTarget;
use Common::Util;
use Common::Log;

$log = 'debug';
Common::Log::setLevel($log);

$gQ = new CGI;
fixHome($gQ);

$Common::global::gCT = new ConfigTree::Cache;
$gCT = $Common::global::gCT;
$gCT->Base($Common::global::gConfigRoot);
$gCT->Warn(\&Warn);

print $gQ -> header('text/plain');
 
if (! $gCT->init()) {
    print "Failed to open compiled config tree from " .
        "$Common::global::gConfigRoot/config.db: $!";
    exit(0);
}

my($recomp, $why) = $gCT->needsRecompile();
if ($recomp) {
    print "Config tree needs to be recompiled: $why";
    exit;
}

# validate target name
my($name) = $gQ->param("target");

my($targetRef) =  $gCT->configHash($name,'target');
if (!defined($targetRef)) {
    print "Specified target missing or invalid";
    exit;
}
ConfigTree::Cache::addAutoVariables($name, $targetRef, $Common::global::gConfigRoot);

my($ttRef) = $gCT->configHash($name, 'targettype',
                              lc($targetRef->{'target-type'}));

if (! defined($ttRef)) {
    print "Invalid or missing target-type for $name";
    exit;
}

# validate data source
my($ds) = $gQ -> param('ds');
if (!defined($ds)) {
    print "Missing data source name";
    exit;
}

my($dslist) = $ttRef->{'ds'};
my($dsnum) = 0;
my($bFound) = 0;
foreach $dsname (split(/\s*,\s*/, $dslist))
{
    if ($dsname eq $ds) {
        $bFound = 1;
        last;
    }
    $dsnum++
}
if (!$bFound) {
    print "Specified data source $ds does not exist for target $name";
    exit;
}

my($rrd) = $targetRef->{'rrd-datafile'};

# is this a vector-instance target?
# borrowed from HandleTarget
my(@inst);
if (defined($targetRef->{'inst'})) {
    my($inst) = $targetRef->{'inst'};
    $inst = ConfigTree::Cache::expandString($inst, $targetRef, \&Warn);
# assume $inst is something like (1..8) or (50,51,52)  
    $inst =~ s/^\s*\(//;
    $inst =~ s/\)\s*$//;
    if ($inst =~ /([0-9]+)\.\.([0-9]+)/) {
        if ($2 > $1) {
            my ($start,$end) = ($1, $2);
            for ( ;$start <= $end; ++$start) { push @inst, $start; } 
        }
    } else {
        @inst = split(/\s*,\s*/,$inst);
    }
} else {
    @inst = ();
}
if (scalar(@inst) > 1) {
    if (!defined($gQ->param('inst'))) {
        print "Target is a vector instance, but no instance specified";
        exit;
    }
    # is the inst valid?
    $bFound = 0;
    foreach $inst (@inst) {
        if ($inst eq $gQ->param('inst')) {
            $bFound = 1;
            last;
        }
    }
    if (!$bFound) {
        print "Instance specified " . $gQ->param('inst') 
        . " is not valid for target $name";
        exit;
    }
    # because inst appears in rrd-datafile, we need to remap inst to a scalar
    my($inst_save) = $targetRef->{'inst'};
    $targetRef->{'inst'} = $gQ->param('inst');
    $rrd = ConfigTree::Cache::expandString($rrd, $targetRef, \&Warn); 
    # not strictly necessary because at the moment this value won't be used
    # down stream... however, that may change in the future
    $targetRef->{'inst'} = $inst_save;
} else {
    $rrd = ConfigTree::Cache::expandString($rrd, $targetRef, \&Warn); 
}

# at this point, we have:
# a rrd data file pathname
my @arg; 
if ($Common::global::gLongDSName) {
    @arg = ('--aberrant-reset',"$dsname");
} else {
# a data source number (to compute the Cricket ds# name)
    @arg = ('--aberrant-reset',"ds$dsnum");
}
RRDs::tune $rrd, @arg;
my($err) = RRDs::error(); 
if ($err) {
    print "Failed:\ntune $rrd " . join(" ",@arg);
    print "\nRRDtool: $err\n";
} else {
    print "Success:\ntune $rrd " . join(" ",@arg) . "\n";
}

1; 

# borrowed from grapher.cgi
sub fixHome {
    return if (defined($Common::global::gCricketHome) &&
           $Common::global::gCricketHome =~ /\//);

    my($sname) = $gQ->script_name();
    if ($sname =~ /\/~([^\/]*)\//) {
        my($username) = $1;
        my($home) = (getpwnam($username))[7];
        if ($home) {
            $Common::global::gCricketHome = $home;
            return;
        } else {
            Info("Could not find a home directory for user $username." .
                "gCricketHome is probably not set right.");
        }
    } else {
        Info("Could not find a username in SCRIPT_NAME. " .
            "gCricketHome is probably not set right.");
    }
    $Common::global::gCricketHome ||= $Common::global::gInstallRoot . "/..";
}
