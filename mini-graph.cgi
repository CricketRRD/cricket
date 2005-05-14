#!/usr/bin/perl -w
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
    # This magic attempts to guess the install directory based
    # on how the script was called. If it fails for you, just
    # hardcode it.
    my $programdir = (($0 =~ m:^(.*/):)[0] || "./") . ".";
    eval "require '$programdir/cricket-conf.pl'";
    eval "require '/usr/local/etc/cricket-conf.pl'"
        unless $Common::global::gInstallRoot;
    $Common::global::gInstallRoot ||= $programdir;
}

use lib "$Common::global::gInstallRoot/lib";

use CGI qw(fatalsToBrowser);
use Digest::MD5;
use HTTP::Date;

use Common::global;
use Common::Log;
use Common::Util;
Common::Log::setLevel('warn');

# Set a safe path. Necessary for set[ug]id operation.
$ENV{PATH} = "/bin:/usr/bin";

# cache cleaning params
#
$gPollingInterval = 5 * 60;     # defaults to 5 minutes

$Common::global::gUrlStyle ||= "classic";
my $gUsePathInfo = 0;
if ($Common::global::gUrlStyle eq "pathinfo") {
    $gUsePathInfo = 1;
}

$main::gQ = new CGI;

doGraph();

sub doGraph {
    my($imageName) = generateImageName($main::gQ);

    # check the image's existance (i.e. no error from stat()) and age

    my($mtime);
    if (defined($imageName)) {
        $mtime = (stat($imageName))[9];
    }

    if (!defined($mtime) || ((time() - $mtime) > $main::gPollingInterval)) {
        # this request is actually going to need work... pass it on
        if (Common::Util::isWin32()) {
            exec("perl $Common::global::gInstallRoot/grapher.cgi");
        } else {
            exec("$Common::global::gInstallRoot/grapher.cgi");
        }
    } else {
        Debug("Cached image exists: $imageName. Using that.");
        sprayPng($imageName);
    }
}

sub tryPng {
    my($png) = @_;

    # we need to make certain there are no buffering problems here.
    local($|) = 1;

    if (! open(PNG, "<$png")) {
        return;
    } else {
        my($stuff, $len);
        binmode(PNG);
        while ($len = read(PNG, $stuff, 8192)) {
            print $stuff;
        }
        close(PNG);
    }
    return 1;
}

sub sprayPng {
    my($png) = @_;

    my $mtime   = (stat($png))[9];
    my $expires = $mtime + $gPollingInterval;
 
    print $main::gQ->header(
                            -type           => 'image/png',
                            'Last-Modified' => time2str($mtime),
                            -expires        => time2str($expires),
                           );

    if (! tryPng($png)) {
        Warn("Could not open $png: $!");
        if (! tryPng("images/failed.png")) {
            Warn("Could not send failure png: $!");
            return;
        }
    }

    return 1;
}

sub generateImageName {
    my($q) = @_;
    my($param, $md5);

    $md5 = new Digest::MD5;

    # make sure to munge $target correctly if $gUrlStyle = pathinfo
    $md5->add(urlTarget($q));

    foreach $param ($q->param()) {
        next if ($param eq 'target');
        if ($param eq 'cache') {
            if (lc($q->param($param)) eq 'no') {
                return;
            }
        }
        $md5->add($param, $q->param($param));
    }
    my($hash) = unpack("H8", $md5->digest());

    return "$Common::global::gCacheDir/cricket-$hash.png";
}

# Get or set the target from the $cgi object.
sub urlTarget {
    my $cgi = shift;
    my $target = shift;
    return $cgi->param('target', $target) if !$gUsePathInfo;
    if (!defined($target)) {
        $target = $cgi->path_info();
        $target =~ s/\/+$//;  # Zonk any trailing slashes
        $target ||= "/";      # but we name the root explicitly
        return $target;
    }
    $cgi->path_info($target);
}


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
