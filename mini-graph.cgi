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
	# This magic attempts to guess the install directory based
	# on how the script was called. If it fails for you, just
	# hardcode it.

	$gInstallRoot = (($0 =~ m:^(.*/):)[0] || './') . '.';

	# cached images are stored here... there will be no more than
	# 5 minutes worth of images, so it won't take too much space.
	# If you leave it unset, the default (/tmp or c:\temp) will probably
	# be OK.
	# $gCacheDir = "/path/to/cache";
}

use lib "$gInstallRoot/lib";

use CGI qw(fatalsToBrowser);
use Digest::MD5;

use Common::Log;
use Common::Util;
Common::Log::setLevel('warn');

# cache cleaning params
#
$gPollingInterval = 5 * 60;     # defaults to 5 minutes

$main::gQ = new CGI;

initOS();
doGraph();

# set the cache dir if necessary, and fix up the ConfigRoot if
# we are not on Win32 (where home is undefined)

sub initOS {
	if ($^O eq 'MSWin32') {
		if (! defined($main::gCacheDir)) {
			$main::gCacheDir = 'c:\temp\cricket-cache';
			$main::gCacheDir = "$ENV{'TEMP'}\\cricket-cache"
				if (defined($ENV{'TEMP'}));
		}
	} else {
		if (! defined($main::gCacheDir)) {
			$main::gCacheDir = '/tmp/cricket-cache';
			$main::gCacheDir = "$ENV{'TMPDIR'}/cricket-cache"
				if (defined($ENV{'TMPDIR'}));
		}
	}
}

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
		   exec("perl $gInstallRoot/grapher.cgi");
		} else {
		   exec("$gInstallRoot/grapher.cgi");
		}
	} else {
		Debug("Cached image exists. Using that.");
		sprayGif($imageName);
	}
}

sub tryGif {
	my($gif) = @_;
	
	# we need to make certain there are no buffering problems here.
	local($|) = 1;
	
	if (! open(GIF, "<$gif")) { 
		return;
	} else { 
		my($stuff, $len); 
		binmode(GIF);
		while ($len = read(GIF, $stuff, 8192)) { 
			print $stuff; 
		} 
		close(GIF); 
	}
	return 1;
}

sub sprayGif {
	my($gif) = @_;

	print $main::gQ->header('image/gif');

	if (! tryGif($gif)) {
		Warn("Could not open $gif: $!");
		if (! tryGif("images/failed.gif")) {
			Warn("Could not send failure gif: $!");
			return;
		}
	}

	return 1;
}

sub generateImageName {
	my($q) = @_;
	my($param, $md5);

	$md5 = new Digest::MD5;

	foreach $param ($q->param()) {
		next if ($param eq 'rand');
        if ($param eq 'cache') {
            if (lc($q->param($param)) eq 'no') {
                return;
            }
        }
		$md5->add($param, $q->param($param));
	}
	my($hash) = unpack("H8", $md5->digest());

	return "$main::gCacheDir/cricket-$hash.gif";
}

