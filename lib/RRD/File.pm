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
use RRD::Format;

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

	if(! $fh->open($mode . $file)) {
		$fh = undef;
	} else {
		binmode($fh);
	}

	$self->fh($fh);
	return $fh;
}

sub close {
	my($self) = @_;
	return unless $self->fh();
	$self->fh()->close();
	$self->fh(undef);
	return;
}

# Reading the RRD headers is quite efficient, since it's using stdio.
# we typically read a disk block starting at offset
# 0, then fetch all of the header stuff from there. On my Solaris
# machine truss shows that we make one 8k read for the header,
# then one 8k read per DS we want to dig into.

sub _readBlock {
	my($self, $off, $size) = @_;

	my($fh) = $self->fh();
	return undef unless $fh;

	$fh->seek($off, 0) unless (! defined($off));
	my($buf);
	if ($fh->read($buf, $size)) {
		return $buf;
	} else {
		return undef;
	}
}

sub _readNextBlock {
	my($self, $size) = @_;
	return $self->_readBlock(undef, $size);
}

sub loadHeader {
	my($self) = @_;
	my($fh) = $self->fh();

	my($fmt) = new RRD::Format;
	if (! $fmt->setArch($RRD::File::gArch)) {
		$RRD::File::gErr = "Architecture $RRD::File::gArch not supported yet.";
		return;
	};

	# save it for later use (esp by getDataOffset)
	$self->fmt($fmt);

	my($header) = $self->_readBlock(0, sizeof($fmt->format('statHead')));
	return undef unless (defined($header));

	# cdp_xff is only available with old format, but it's only
	# accessed byu callers when they know it's going to be set,
	# so it's OK if we set it tp undef here for new format RRD's.

	my($c, $v, $fc, $ds_cnt, $rra_cnt, $pdp_step, $cdp_xff) =
		unpack($fmt->format('statHead'), $header);

	$c = fixName($c);
	$v = fixName($v);

	if ($c ne $fmt->format('cookie') ||
		($v ne $fmt->format('version')) ||
		($fc != $fmt->format('float_cookie'))) {
		$RRD::File::gErr = "Something is wrong with the header of this file.";
		return;
	}

	# and save all the good stuff for later use
	$self->ds_cnt($ds_cnt);
	$self->rra_cnt($rra_cnt);
	$self->pdp_step($pdp_step);
	$self->cdp_xff($cdp_xff);

	my($i);
	foreach $i (0 .. $ds_cnt-1) {
		my(%def) = ();
		my($block) = $self->_readNextBlock(sizeof($fmt->format('dsDef')));
		croak("Could not read DS def $i") unless (defined($block));

		my($dsName, $dst, $ds_mrhb, $min_val, $max_val) =
				unpack($fmt->format('dsDef'), $block);

		$dsName = fixName($dsName);
		$dst = fixName($dst);
		
		%def = ( 'dsName' => $dsName,
				'dst' => $dst,
				'ds_mrhb' => $ds_mrhb,
				'min_val' => $min_val,
				'max_val' => $max_val );

		push @{$self->{'ds_def'}}, \%def;
	}

	foreach $i (0 .. $rra_cnt-1) {
		my(%def) = ();
		my($block) = $self->_readNextBlock(sizeof($fmt->format('rraDef')));
		croak("Could not read RRA def $i") unless (defined($block));

		my($rraName, $row_cnt, $pdp_cnt, $cf) =
			unpack($fmt->format('rraDef'), $block);

		$rraName = fixName($rraName);
		$cf = fixName($cf);

		%def = ( 'rraName' => $rraName,
				'cf' => $cf,
				'row_cnt' => $row_cnt,
				'pdp_cnt' => $pdp_cnt );

		push @{$self->{'rra_def'}}, \%def;
	}

	{
		my($block) = $self->_readNextBlock(sizeof($fmt->format('liveHead')));
		croak("Could not read live header") unless (defined($block));

		my($last_up) = unpack($fmt->format('liveHead'), $block);
		$self->last_up($last_up);
	}

	foreach $i (0 .. $ds_cnt-1) {
		my(%def) = ();
		my($block) = $self->_readNextBlock(sizeof($fmt->format('pdpDef')));
		croak("Could not read PDP $i") unless (defined($block));

		my($last_ds, $unkn_sec, $value) = 
			unpack($fmt->format('pdpDef'), $block);

		$last_ds = fixName($last_ds);

		%def = ('last_ds' => $last_ds, 
				'value' => $value,
				'unkn_sec' => $unkn_sec );

		push @{$self->{'pdps'}}, \%def;
	}

	foreach $i (0 .. (($ds_cnt * $rra_cnt)-1)) {
		my(%def) = ();
		my($block) = $self->_readNextBlock(sizeof($fmt->format('cdpDef')));
		croak("Could not read CDP $i") unless (defined($block));

		my($value, $unkn_pdp) = unpack($fmt->format('cdpDef'), $block);
		
		%def = ( 'value' => $value,
				'unkn_pdp' => $unkn_pdp );

		push @{$self->{'cdps'}}, \%def;
	}

	foreach $i (0 .. ($rra_cnt-1)) {
		my($block) = $self->_readNextBlock(sizeof($fmt->format('rraPtr')));
		croak("Could not read RRD cur $i") unless (defined($block));

		my($ptr) = unpack($fmt->format('rraPtr'), $block);
		push @{$self->{'rra_ptr'}}, $ptr;
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

sub rra_ptr {
	my($self, $i) = @_;
	return $self->{'rra_ptr'}->[$i];
}

sub getDSRowValue {
    my($self, $rra, $row, $ds) = @_;
    my($ds_cnt) = $self->ds_cnt();
    my($rra_cnt) = $self->rra_cnt();
    if(!defined($ds) || $ds >= $self->ds_cnt()
		|| !defined($rra) || $rra >= $self->rra_cnt()) {
        return;
    }
    my($fmt) = new RRD::Format;
    if(! $fmt->setArch($RRD::File::gArch)) {
        $RRD::File::gErr = "Architecture $RRD::File::gArch not supported yet.";
        return;
    }
    $self->fmt($fmt);
 
    # this gets us to the place in the file where the data starts.
 
    my($headerOffset) = $self->getDataOffset();
 
    # was there an error?
    return unless($headerOffset);
    # determine which row we want from the RRA
    my($numRows) = $self->rra_def($rra)->{row_cnt};
    my($wantedRow) = ($self->rra_ptr($rra) - $row);
    while($wantedRow < 0) {
        $wantedRow += $numRows;
    }
 
    my($elmSize) = sizeof($fmt->format('element'));
    my($rraOffset) = ($rra * $ds_cnt * $numRows * $elmSize);
    my($dataOffset) = $rraOffset +
                    $wantedRow * ($ds_cnt * $elmSize) + $ds * $elmSize;
    my($offset) = $headerOffset + $dataOffset;
 
    my($value) = $self->_readBlock($offset, $elmSize);
 
    if(defined($value)) {
        ($value) = unpack($fmt->format('element'), $value);
        return $value;
    } else {
        return;
    }
}

sub getDSCurrentValue {
	my($self, $ds) = @_;

	my($ds_cnt) = $self->ds_cnt();
	my($rra_cnt) = $self->rra_cnt();

	# check param, now that we have ds_cnt.
	if (!defined($ds) || $ds >= $self->ds_cnt()) {
		return;
	}

	my($fmt) = new RRD::Format;
	if (! $fmt->setArch($RRD::File::gArch)) {
		$RRD::File::gErr = "Architecture $RRD::File::gArch not supported yet.";
		return;
	};
	$self->fmt($fmt);

	# this gets us to the place in the file where the data starts. now
	# all we need to do is find our bit of data within the data area...
	
	my($headerOffset) = $self->getDataOffset();

	# was there an error?
	return unless ($headerOffset);

	# now, calculate the offset into the data area
	#	we want the current row in the first RRA.
	#	we want the column corresponding to the given ds.
	#	(see last bit of rrd_format.h
	# 	if you want to try to understand this...)

	my($wantedRow) = $self->rra_ptr(0);
	my($elmSize) = sizeof($fmt->format('element'));
	my($rraOffset) = 0;		# this is because we only want the first RRA.
							# eventually, we could compute this for an
							# arbitrarty RRA.
	my($dataOffset) = $rraOffset +
					$wantedRow * ($ds_cnt * $elmSize) + $ds * $elmSize;
	my($offset) = $headerOffset + $dataOffset;

	my($value) = $self->_readBlock($offset, $elmSize);

	if (defined($value)) {
		($value) = unpack($fmt->format('element'), $value);
		return $value;
	} else {
		return;
	}
}

sub getDataOffset {
	my($self) = @_;

	my($fmt) = $self->fmt();
	return unless (defined($fmt));

	my($ds_cnt) = $self->ds_cnt();
	my($rra_cnt) = $self->rra_cnt();

	return (sizeof($fmt->format('statHead')) +
				$ds_cnt * sizeof($fmt->format('dsDef')) +
				$rra_cnt * sizeof($fmt->format('rraDef')) +
				sizeof($fmt->format('liveHead')) +
				$ds_cnt * sizeof($fmt->format('pdpDef')) +
				($ds_cnt * $rra_cnt) * sizeof($fmt->format('cdpDef')) +
				$rra_cnt * sizeof($fmt->format('rraPtr')));
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
