# -*-perl-*-

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

#
# 	Ripped off lock, stock, and barrel from JRA's file.pm.
#	- ejt  08/08/1999

use Common::Log;

$main::gDSFetch{'field'} = \&fieldFetch;

sub fieldFetch {
	# This procedure is passed a REFERENCE to an array of file datasources.
	# Each line consists of "index:filename:key:valuef:keyf:delim"
	#
	# There can be spaces in the key, but there probably won't be.
	# "valuef" defaults to "2" if not specified
	# "keyf" defaults to "1" if not specified
	# "delim" defaults to ":" if not specified
	#
	# VERY IMPORTANT: The index MUST be returned with the corresponding value,
	# otherwise it'll get put back into the wrong spot in the RRD.

	my($dsList, $name, $target) = @_;

	my(@results, %files);

	my($line);
	foreach $line (@{$dsList}) {
		my(@components) = split(/:/, $line, 6);
		my ($index, $file, $key, $valuef, $keyf, $delim);

		if ($#components+1 < 3) {
			Error("Malformed datasource source: $line.");
			return ();
		}
			
		$index	= shift(@components);
		$file	= shift(@components);
		$key	= shift(@components);
		$valuef	= shift(@components) || 2;
		$keyf	= shift(@components) || 1;
		$delim	= shift(@components) || ":";

		push(@{ $files{$file} }, "$index:$file:$key:$valuef:$keyf:$delim");
	}

	my($file, $ilRef, $il);

	while (($file, $ilRef) = each %files) {
		Info("Reading data from $file for " .  $target->{'auto-target-name'});

		if (open(F, "<$file")) {
			my(@lines);
			chomp(@lines = <F>);
			close(F);

			while ($il = shift @{ $ilRef } ) {
				my($index, $file, $key, 
					$valuef, $keyf, $delim) = split(/:/, $il, 6);
				my $matches	= 0;
				my $match	= 0;

				foreach my $line (@lines) {
					my @bits = split($delim, $line);

					# just skip lines with too few fields
					next if (($#bits < $keyf - 1) || 
								($#bits < $valuef - 1));

					if ($bits[$keyf - 1] eq $key) {
						$matches++;
						$match = $bits[$valuef - 1];
					}
				}

				if ($matches > 1) {
					push @results, "$index:U";
					Error("Key $key matched $matches times for " .
							$target->{'auto-target-name'} .
							" from file $file.");
				} elsif ($matches == 0) {
					push @results, "$index:U";
				} else {
					push @results, "$index:$match";
				}
			}
		} else {
			Error("Could not fetch data for " . $target->{'auto-target-name'} .
					" from file $file: $!.");
		}
	}

	return @results;
}

1;

