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

package Common::Util;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(Eval isNonNull isTrue isFalse mapOid runTime quoteString);

use Common::Log;

# This is used to help not-strictly-numeric instances sneak through
# the eval. This is a hack and should probably be solved better
# someday.

sub quoteInstance {
    my($targRef) = @_;
    my($inst) = $targRef->{'inst'};
    if (defined($inst)) {
        $targRef->{'inst'} = quoteString($targRef->{'inst'});
    }
}

sub quoteString {
    my($str) = @_;
    if ($str =~ /^[A-Za-z]/) {
        if ($str !~ /^qw\(/) {
            $str = "qw($str)";
        }
    }
    return $str;
}

# sub quoteString {
#   my($str) = @_;
#   my($new) = $str;
#
#   if ($str =~ /^[\w\.-]+$/) {
#       $new = "\'$str\'";
#       Debug("Quoted string [$str] to be [$new]");
#   }
#   return $new;
#}

sub mapOid {
    my($oidRef, $oid) = @_;
    return $oid unless $oid;

    while (($oidName) = ($oid =~ /([a-z]\w*)/i)) {
        if (defined $oidRef->{lc($oidName)}) {
            $oid =~ s/$oidName/$oidRef->{lc($oidName)}/;
        } else {
            Warn("Could not resolve OID for $oid");
            $oid = undef;
        }
    }

    return $oid;
}

# os-independent MkDir

sub MkDir {
    my($dir) = @_;

    if (isWin32()) {
        my ($dd) = $dir;
        $dd =~ s/\//\\/g;
        `cmd /X /C mkdir $dd`;
    } else {
        system("/bin/mkdir -p $dir");
    }
}

sub isWin32 {
    return ($^O eq 'MSWin32');
}

sub runTime {
    my $starttime = shift;
    $starttime = $^T unless defined $starttime;
    my($time) = time() - $starttime;
    if ($time > 59) {
        my($min) = int($time / 60);
        my($sec) = $time - ($min * 60);
        $time = "$min minutes, $sec";
    }
    $time .= " seconds";

    return $time;
}

# Perl doesn't like numbers in scientific notation. It makes it very unhappy.
# Thanks to Steen Linden for helping with a fix for this.
sub fixNum {
    my($n) = @_;

    if (!defined($n)) {
        Error("Value not defined in Common::Util::fixNum()!");
    }

    $n = sprintf("%0.20g", $n) if ($n =~ /^\d\.\d+e\+\d+$/);
    return $n;
}

sub isFalse {
    my($v) = @_;
    $v = lc($v) if (defined($v));

    if ($v eq '0' or $v eq 'false' or $v eq 'no') {
        return 1;
    }
    return 0;
}

sub isTrue {
    return ! isFalse(@_);
}

sub Eval {
    my($exp) = @_;
    my(@res);
    my($warn);

    my($p, $f, $l) = caller();

    eval {
        local($SIG{'__WARN__'}) = sub { $warn = $_[0]; die($warn); };
        #Debug("evaling ($f, line $l): $exp");
        @res = eval($exp);
    };

    if (defined($warn)) {
        Warn("Warning while evaluating $exp: $warn");
        Debug("Called from $f, line $l.");
    }

    return @res;
}

sub isNonNull {
    return (defined($_[0]) && $_[0] ne '');
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
