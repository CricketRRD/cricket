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

package Common::Log;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(Debug Warn Info Die Error LogMonitor);

$kLogDebug	= 9;
$kLogMonitor = 8;
$kLogInfo	= 7;
$kLogWarn	= 5;
$kLogError	= 1;
$gCurLogLevel	= $kLogWarn;

%kLogNameMap = (
	'debug' => $kLogDebug,
	'monitor' => $kLogMonitor,
	'info' => $kLogInfo,
	'warn' => $kLogWarn,
	'error' => $kLogError
);

sub Log {
	my($level, @msg) = @_;
	my($msg) = join('', @msg);

	my($severity) = ' ';
	$severity = '*' if (($level == $kLogWarn) || ($level == $kLogError));

	if ($level <= $gCurLogLevel) {
		my($time) = timeStr(time());
		my($stuff) = $time . $severity;
		print STDERR "[$stuff] $msg\n";
	}
}

sub Die {
	Log($kLogError, @_);
	die("Exiting due to unrecoverble error.\n");
}

sub Error {
	Log($kLogError, @_);
}

sub Warn {
	Log($kLogWarn, @_);
}

sub Debug {
	Log($kLogDebug, @_);
}

sub Info {
	Log($kLogInfo, @_);
}

sub LogMonitor {
	Log($kLogMonitor, @_);
}

sub timeStr {
	my($t) = ($_[0] =~ /(\d*)/);
	my(@months) = ( "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
				"Aug", "Sep", "Oct", "Nov", "Dec");
	my($sec,$min,$hour,$mday,$mon,$year) = localtime($t);
	return sprintf("%02d-%s-%04d %02d:%02d:%02d", $mday, $months[$mon],
				$year + 1900, $hour, $min, $sec);
}

sub setLevel {
	my($level) = @_;

    if (defined($kLogNameMap{lc($level)})) {
        $gCurLogLevel = $kLogNameMap{lc($level)};
    } else {
        Common::Log::Warn("Log level name $level unknown. " .
                            "Defaulting to 'info.'");
        $gCurLogLevel = $kLogNameMap{lc('info')};
    }
}

1;

