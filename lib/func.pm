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

use Common::Log;

# Uncomment the following line if you want to enable 'FUNC' alarm triggers.
# $main::gMonFuncEnabled = 1 ;

$main::gDSFetch{'func'} = \&funcFetch;

#----------------------------------------
# functions must be specified in the Defaults file similar to the
# following:
#   "func:Package::function(arguments)"
#
# If a package is specified, it will be 'require'd.  Unlike, say, 'exec',
# this function will be called for each datasource, so if you have a function
# that you'd like to return multiple values, write it such that it returns
# each of the values in turn, or code the return values based on the arguments

sub funcFetch {
    my($dsList, $name, $target) = @_;
	warn "(dsList,name,target) ([$dsList],[$name],[$target])\n";
    my(@results);
    my($line);
    foreach $line (@{$dsList}) {
        if ( $line =~ /(\d*):(.*)/) {
            my ($res,$number,$call,$eval);
			($number,$call) = ($1,$2);

			# we're trying to retrieve just the sub name, with no arguments
			my $sub = $call;
			$sub =~ s/(\(|\s).+//;

			if ($sub =~ /::/) { # if the sub is package-qualified...
				my $package = $sub;
				$package =~ s/::[^:]+$//; # trim off the sub name
				$eval = qq(use $package; $call);
			} else {
				$eval = $call;
			}
            $result = eval $eval;
			if ($@) {
				# there was an error of some kind
				Warn("Failed to collect info from $call: $@");
			} else {
				push @results, "$number:$result";
			}
        }
    }
    return @results;
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
