# -*- perl -*-

# RRD::File: a package for digging around in RRD files from Perl
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

package RRD::File;

use strict;
use Carp;
use Config;
use FileHandle;
use RRDs;

$RRD::File::gErr = "";
$RRD::File::gArch = $Config{'archname'};

# field setters/getters (gets value if no args, sets value and
# returns old value if it does have an arg)

sub file { shift->_getAndSet('file', @_) };
sub fh { shift->_getAndSet('fh', @_) };
sub fmt { shift->_getAndSet('format', @_) };
sub ds_cnt { shift->_getAndSet('ds_cnt', @_) };
sub rra_cnt { shift->_getAndSet('rra_cnt', @_) };
sub pdp_step { shift->_getAndSet('pdp_step', @_) };
sub cdp_xff { shift->_getAndSet('cdp_xff', @_) };
sub last_up { shift->_getAndSet('last_up', @_) };
sub info { shift->_getAndSet('info', @_) };

sub _getAndSet {
    my($self, $field, $value) = @_;
    my($retval) = $self->{$field};
    $self->{$field} = $value if ($#_ >= 2);
    return $retval;
}

sub new {
    my($type) = shift;
    my(%p) = @_;
    my($self) = {};
    $self->{'file'} = $p{'-file'};
    $self->{'fh'} = undef;

    bless $self, $type;
    return $self;
}

sub open {
    my($self, $mode) = @_;
    $mode = "<" if (! defined($mode));

    my($file) = $self->file();
    return unless defined($file);

    my($fh) = new FileHandle;

    if (! $fh->open($mode . $file)) {
        $fh = undef;
    } else {
        binmode($fh);
    }

    close($fh) if $fh;

    return 1;
}

sub close {
    my($self) = @_;
    1;
}

sub loadHeader {
    my($self) = @_;
    my($file) = $self->file();

    my($info) = RRDs::info($file);

    if (!$info) {
        $RRD::File::gErr = "Error reading RRD header: " . RRDs::error;
        return;
    }

    $self->info($info);

    # cdp_xff is only available with old format, but it's only
    # accessed byu callers when they know it's going to be set,
    # so it's OK if we set it tp undef here for new format RRD's.

    my %DSdefs;
    my %RRAdefs;
    while (my ($key, $value) = each(%$info)) {
        if ($key =~ /^ds\[(.*)\]\.(.*)$/) {
            $value = fixName($value) if ($2 eq 'type');
            $DSdefs{fixName($1)}{$2} = $value;
#            warn "dsdefs{$1}{$2} = $value\n";
        } elsif ($key =~ /^rra\[(.*)\]\.(.*)$/) {
            $RRAdefs{fixName($1)}{$2} = $value;
#            warn "rradefs{$1}{$2} = $value\n";
        }
    }

    $self->ds_cnt( scalar(keys %DSdefs) );
    $self->rra_cnt( scalar(keys %RRAdefs) );
    $self->pdp_step( $$info{'step'} );

    foreach my $dsName (keys %DSdefs) {
        my $ds = $DSdefs{$dsName};
        my(%def) = ();
        my $dsNum = ($dsName =~ /^ds(\d+)$/)[0];

        my($dst, $ds_mrhb, $min_val, $max_val, $value) =
          ($$ds{type}, $$ds{minimal_heartbeat},
           $$ds{min}, $$ds{max}, $$ds{value});

        %def = ( 'dsName' => $dsName,
                 'dst' => $dst,
                 'ds_mrhb' => $ds_mrhb,
                 'min_val' => $min_val,
                 'max_val' => $max_val,
                 'value' => $value );

        $self->{'ds_def'}->[$dsNum] = \%def;
    }

    foreach my $rraName (keys %RRAdefs) {
        my $rra = $RRAdefs{$rraName};
        my(%def) = ();

        my($row_cnt, $pdp_cnt, $cf) =
          ($$rra{rows}, $$rra{pdp_per_row}, $$rra{cf});

        $rraName = fixName($rraName);
        $cf = fixName($cf);

        %def = ( 'rraName' => $rraName,
                 'cf' => $cf,
                 'row_cnt' => $row_cnt,
                 'pdp_cnt' => $pdp_cnt );

        push @{$self->{'rra_def'}}, \%def;
    }

    $self->last_up($$info{last_update});

    foreach my $dsName (keys %DSdefs) {
        my(%def) = ();

        my($last_ds, $unkn_sec, $value) =
          ($DSdefs{$dsName}{last_ds},
           $DSdefs{$dsName}{value},
           $DSdefs{$dsName}{unknown_sec});

        $last_ds = fixName($last_ds);

        %def = ('last_ds' => $last_ds,
                'value' => $value,
                'unkn_sec' => $unkn_sec );

        push @{$self->{'pdps'}}, \%def;
    }

    return 1;
}

sub ds_def {
    my($self, $i) = @_;
    return $self->{'ds_def'}->[$i];
}

sub rra_def {
    my($self, $i) = @_;
    return $self->{'rra_def'}->[$i];
}

sub pdp {
    my($self, $i) = @_;
    return $self->{'pdps'}->[$i];
}

sub cdp {
    my($self, $i) = @_;
    return $self->{'cdps'}->[$i];
}

sub getDSCurrentValue {
    my($self, $ds) = @_;

    my($ds_cnt) = $self->ds_cnt();

    # check param, now that we have ds_cnt.
    if (!defined($ds) || $ds >= $ds_cnt) {
        return undef;
    }

    my ($start, $step, $names, $data) = RRDs::fetch($self->file(),
                                                    'AVERAGE',
                                                    '--start',
                                                    "now",
                                                    '--end',
                                                    "now");
    if (my $error = RRDs::error) {
        Warn("getDSCurrentValue: fetch failed: $error");
        return undef;
    }
    my $ret = @{$data}[0]->[$ds];

    return 'NaN' unless defined($ret);
    return $ret;
}

sub getMeta {
    my($self) = @_;
    my($metaRef) = {};

    my($file) = $self->file();
    return $metaRef unless defined($file);

    # make the metafile name. Remove the .rrd (if there is one)
    # and append .meta
    $file =~ s/\.rrd$//;
    my($metaFile) = "$file.meta";

    if (CORE::open(META, "<$metaFile")) {
        while (<META>) {
            chomp;
            my($delim) = "\0";
            $delim = ":" if (! /\0/); # backwards compatiblity
            my($k, $v) = split(/$delim/, $_, 2);
            $metaRef->{$k} = $v;
        }
        CORE::close(META);
    }

    return $metaRef;
}

sub setMeta {
    my($self, $metaRef) = @_;

    my($file) = $self->file();
    return unless defined($file);

    # make the metafile name. Remove the .rrd (if there is one)
    # and append .meta
    $file =~ s/\.rrd$//;
    my($metaFile) = "$file.meta";

    if (CORE::open(META, ">$metaFile")) {
        my($k);
        foreach $k (keys(%{$metaRef})) {
            print META join("\0", $k, $metaRef->{$k}), "\n";
        }
        CORE::close(META);

        return 1;
    } else {
        return;
    }
}

sub fixName {
    my($str) = @_;

    # fix undefs (generated by old files) to be emtpy, so that
    # we don't get warnings in rrd-dump
    return "" unless defined ($str);

    # even though unpack gives us all the bytes, we only want the C
    # string.
    my($nul) = index($str, "\0");
    if ($nul != -1) {
        $str = substr($str, 0, $nul);
    }

    return $str;
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# cperl-indent-level: 4
# End:
