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

$main::gDSFetch{'exec'} = \&execFetch;

sub execFetch {
    # This procedure is passed a REFERENCE to an array of exec datasources.
    # The line consists of "index:line-num:shell command"
    #
    # There can and will be spaces in the shell command. If line-num
    # is missing it is assumed to be the first output line.
    #
    # VERY IMPORTANT: The index MUST be returned with the corresponding value,
    # otherwise it'll get put back into the wrong spot in the RRD.

    my($dsList, $name, $target) = @_;

    my(@results, %shellCmds);

    my($line);
    foreach $line (@{$dsList}) {
        my(@components) = split(/:/, $line, 3);
        my($index, $outputIndex, $cmd);

        if ($#components+1 == 3) {
            ($index, $outputIndex, $cmd) = @components;
        } elsif ($#components == 1) {
            ($index, $cmd) = @components;
            $outputIndex = 0;
        } else {
            Error("Malformed datasource source: $line.");
            return ();
        }
        push(@{ $shellCmds{$cmd} }, "$index:$outputIndex");
    }

    my($cmd, $execDSRef);

    while (($cmd, $execDSRef) = each %shellCmds) {
        Info("Retrieving data (EXEC: $cmd) for " .
         $target->{'auto-target-name'});

        if ( open(COMMAND, "$cmd|") ) {
            my(@output);
            chomp(@output = <COMMAND>);
            Debug("EXEC: $cmd results = " . join(",", @output));

            while ( $line = shift @{ $execDSRef } ) {
                my($index, $outputIndex) = split(/:/, $line, 2);
                if (defined $output[$outputIndex]) {
                    push(@results, "$index:$output[$outputIndex]");
                } else {
                    push(@results, "$index:U");
                }
            }
        } else {
            Error("Could not retrieve data for $target->{'tname'} " .
          "(EXEC: $cmd): $!.");
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
