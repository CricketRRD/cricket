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

package Common::global;

BEGIN {
	# Set defaults for things not picked up from cricket-config.pl
	$gCricketHome ||= $ENV{'HOME'}; 
	$gConfigRoot ||= $gCricketHome . "/cricket-config";
	if ($gConfigRoot !~ m#^/#) {
		$gConfigRoot = "$gCricketHome/$gConfigRoot";
	}
	if ($^O eq 'MSWin32') {
		$gCacheDir ||= "$ENV{'TEMP'}\\cricket-cache"
			if (defined($ENV{'TEMP'}));
		$gCacheDir ||= "c:\temp\cricket-cache";
	} else {
		$gCacheDir ||= "$ENV{'TMPDIR'}/cricket-cache"
			if (defined($ENV{'TMPDIR'}));
		$gCacheDir ||= "/tmp/cricket-cache";
	}

	if (!defined($isCollector)) {
		$isCollector = 0;
	}
}

1;
