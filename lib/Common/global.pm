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

# define the ConfigRoot class
package ConfigRoot;

my $val;

sub TIESCALAR {
    my $class = shift;
    my $me;
    $val = shift;
    bless \$me, $class;
}

sub FETCH {
    my $self = shift;
    if (!defined($val)) {
        return $Common::global::gCricketHome . "/cricket-config";
        # check for relative path (both UNIX and DOS drive letter style)
    } elsif ($val !~ m#^/# && $val !~ m#^[a-z,A-Z]:/#) {
        return "$Common::global::gCricketHome/$val" unless
             ($^O eq 'MSWin32' && $Common::global::isGrapher);
    }
    return $val;
}

# this method will only be invoked if someone sets $gConfigRoot
# after Common::global is loaded
sub STORE {
    my $self = shift;
    $val = shift;
    return $self->FETCH();
}

package Common::global;

BEGIN {
    # Set defaults for things not picked up from cricket-config.pl
    $gCricketHome ||= $ENV{'HOME'};
    tie $gConfigRoot, 'ConfigRoot', $gConfigRoot;
    if ($^O eq 'MSWin32') {
        $gCacheDir ||= "$ENV{'TEMP'}\\cricket-cache"
            if (defined($ENV{'TEMP'}));
        $gCacheDir ||= "c:\\temp\\cricket-cache";
    } else {
        $gCacheDir ||= "$ENV{'TMPDIR'}/cricket-cache"
            if (defined($ENV{'TMPDIR'}));
        $gCacheDir ||= "/tmp/cricket-cache";
    }

    $hasPersistantGlobals ||= 0;
    $hasPersistantGlobals = 1 if $ENV{'MOD_PERL'};
    $hasPersistantGlobals = 1 if $CGI::SpeedyCGI::i_am_speedy;

    $gSkipMonitor ||= 0;
    $gUrlStyle ||= "classic";

    if (!defined($isGrapher)) {
        $isGrapher = 0;
    }
    if (!defined($isCollector)) {
        $isCollector = 0;
    }
    if (!defined($gLongDSName)) {
        $gLongDSName = 0;
    }
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
