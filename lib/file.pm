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
# External modules.
use Fcntl ':mode'; # stat() constants; check whether a file is a socket.
#@@@FIXME: This pollutes our namespace. We should use qw(func) here.
use Socket;        # Socket operations.
#@@@FIXME;

#
# Cricket internal modules.
use Common::Log;


$main::gDSFetch{'file'} = \&fileFetch;

sub fileFetch {
    # This procedure is passed a REFERENCE to an array of file datasources.
    # The line consists of "index:line-num:shell command"
    #
    # There can and will be spaces in the shell command. If line-num
    # is missing it is assumed to be the first output line.
    #
    # VERY IMPORTANT: The index MUST be returned with the corresponding value,
    # otherwise it'll get put back into the wrong spot in the RRD.

    my($dsList, $name, $target) = @_;

    my(@results, %files);

    my($line);
    foreach $line (@{$dsList}) {
        my(@components) = split(/:/, $line, 3);
        my($index, $lineno, $file);

        if ($#components+1 == 3) {
            ($index, $lineno, $file) = @components;
        } elsif ($#components == 1) {
            ($index, $file) = @components;
            $lineno = 0;
        } else {
            Error("Malformed datasource source: $line.");
            return ();
        }
        push(@{ $files{$file} }, "$index:$lineno");
    }

    my($file, $ilRef, $il);

    while (($file, $ilRef) = each %files) {
        Info("Reading data from $file for " .
             $target->{'auto-target-name'});

        stat $file; # Populate magic "_" structure (and $!).
        if (-S _) { # $file is connected to a UNIC domain socket.
            socket  F, PF_UNIX, SOCK_STREAM, 0;
            connect F, sockaddr_un($file)
                or Debug("connect($file) returned: $!");
        } elsif (-f _) { # $file is a plain file.
            open F, "<$file"
                or Debug("open($file) returned: $!");
        }

        unless (defined F) { # No F means open() or connect() failed...
            Error("Could not fetch data for " .
                  $target->{'auto-target-name'} .
                  " from $file: $!.");
            next; # ...so skip it.
        }

        my @lines;
        chomp(@lines = <F>);
        close F;

        while ($il = shift @{ $ilRef } ) {
            my($index, $lineno) = split(/:/, $il, 2);
            if (defined($lines[$lineno])) {
                push @results, "$index:$lines[$lineno]";
            } else {
                push @results, "$index:U";
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
