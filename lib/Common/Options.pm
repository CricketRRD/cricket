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

package Common::Options;

use Getopt::Long;
use Common::Log;

sub commonOptions {
	# default to 'info' unless there's a environment variable
	# or a commandline arg
	my($logLevel) = $ENV{'CRICKET_LOG_LEVEL'};
	$logLevel = 'info' unless defined($logLevel);

	$ENV{'HOME'} = '' unless (defined($ENV{'HOME'})); 
	my($base) = "$ENV{'HOME'}/cricket-config";

	GetOptions( "loglevel:s" => \$logLevel, 
				"base:s" => \$base, @_);

	Common::Log::setLevel($logLevel);
	$Common::global::gConfigRoot = $base;
	if (!defined($Common::global::isCollector)) {
		$Common::global::isCollector = 0;
	}
}

1;

