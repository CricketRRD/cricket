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
use Common::Util;
use DBI;
use strict;

$main::gDSFetch{'sql'} = \&sqlFetch;

my %sqlFetches;

sub sqlFetch {
    my($dsList, $name, $target) = @_;
    my(@results);

    foreach my $line (@{$dsList}) {
        my @components = split(/:/, $line, 6);
        my ($index, $login, $password, $query, $col, $dbdriver);

        if($#components+1 < 6) {
            Error("Malformed datasource line: $line.");
            return();
        }

        $index      = shift(@components);
        $login      = shift(@components) || 'anonymous';
        $password   = shift(@components) || '';
        $query      = shift(@components) || missing("sql query", $line);
        $col        = shift(@components) || 1;
        $dbdriver   = shift(@components) || missing("db driver", $line);

        $sqlFetches{$index} = "$login:$password:$query:$col:$dbdriver";
    }

    DSLOOP: while(my ($index, $ilRef) = each %sqlFetches) {
        my($login, $password, $query, $col, $dbdriver) = split(/:/, $ilRef, 5);
        my $matches;
        my $value;

        my $dbh = DBI->connect($dbdriver, $login, $password) || Error();
        my $sth = $dbh->prepare($query);

        if($sth->errstr) {
            Error "Bad query: $sth->errstr";
        }

        $sth->execute;

        if($sth->errstr) {
            Error "Bad result: $sth->errstr";
        }

        my @row = $sth->fetchrow_array();
        $value = $row[$col-1];
        $matches++;

        if($sth->fetchrow_array()) {
            $matches++;
        }

        if($matches < 1) {
            push @results, "$index:U";
        } else {
            push @results, "$index:$value";
        }
    }

    return @results;
}

1;
