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

# A fetch routine for retrieving data from Windows Management 
# Instrumentation Counters, the Microsoft implementation of the Web-Based
# Enterprise Management (WBEM) standard. This implementation feeds WQL
# (similar to SQL) queries to the WBEM ODBC Adapter shipped with Win2K.

use Common::Log;
use LeanODBC qw(:ALL);

$main::gDSFetch{'wbemodbc'} = \&wbemodbcFetch;

sub wbemodbcFetch {
      # This procedure is passed a REFERENCE to an array of wbemodbc datasources.
      # Each line consists of "index:uid:host:namespace:table:field:predicate"
      # Predicate is optional.
      # uid is assumed to be the current user running Cricket, and this uid
      # is presumed to have sufficient authority on the remote host.
      # VERY IMPORTANT: The index MUST be returned with the corresponding value,
      # otherwise it'll get put back into the wrong spot in the RRD.

      my($dsList, $name, $target) = @_;

      my (@results, @lines, $line, $connectstr, @nextline);
      my ($henv, $hdbc, $hstmt, $rc) = (undef,undef,undef,0);
      my $query = undef;
      my ($data, $datalen);
      my ($index, $uid, $host, $namespace, $table, $field, $predicate);
      my (@fieldList, @indexList);
      my $isConnected = 0;

      # sort lines by uid/host, namespace, and table 
      # (default they are sorted by index)
      @lines = sort {
	 substr ($a, index($a, ':')) cmp substr ($b, index($b, ':'))
      } (@{$dsList});

      ($rc, $henv) = SQLAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE);
      if ($rc != SQL_SUCCESS) {
	 Error("ODBC not available, failed to alloc environment handle!");
            return;
      }

      $line = shift @lines;
      CONNECTLOOP: while (defined($line)) 
      {
         ($index, $uid, $host, $namespace, $table, $field, $predicate) =
            split(/:/,$line,7);
 	 # close any existing ODBC connection
         if (defined $hdbc) {
            SQLDisconnect($hdbc) if ($isConnected);
            SQLFreeHandle(SQL_HANDLE_DBC,$hdbc);
            $hdbc = undef;
            $isConnected = 0;
         }
         # establish a new ODBC connection
         $connectstr = "DSN=WBEM Source;UID=$uid;SERVER=$host;DBQ=$namespace;NAMESPACES={$namespace,shallow};UIDPWDDEFINED";
         ($rc, $hdbc) = SQLAllocHandle(SQL_HANDLE_DBC,$henv);
         if ($rc == SQL_SUCCESS)
         {
            ($rc, $data, $datalen) = SQLDriverConnect($hdbc,$connectstr,SQL_NTS);
            if ($rc != SQL_SUCCESS && $rc != SQL_SUCCESS_WITH_INFO) {
               Warn("DriverConnect to $connectstr failed:");
               Warn(join(' ', SQLGetDiagRec(SQL_HANDLE_DBC,$hdbc,1)));
            } else {
               $isConnected = 1;
            }
         } else {
            Warn("Alloc Connect failed: " . join(' ', 
            SQLGetDiagRec(SQL_HANDLE_ENV,$henv,1)));
         }
         TABLELOOP: while (1)
         {
            ($rc, $hstmt) = SQLAllocHandle(SQL_HANDLE_STMT,$hdbc) if ($isConnected);
            @fieldList = ();
            @indexList = ();
            FIELDLOOP: while (1) {
               push @fieldList, "\"$field\"";
               push @indexList, $index;
               # group together queries to the same table with the same predicate
               $line = shift @lines;
               @nextline = split(/:/,$line,7) if (defined($line));
               if (!defined($line) || $table ne $nextline[4] || 
                  ($predicate ? $predicate : "") ne ($nextline[6] ? $nextline[6] : "") ||
                   $host ne $nextline[2] || $uid ne $nextline[1] || $namespace ne $nextline[3])
               { last FIELDLOOP; }
               ($index, $field) = ($nextline[0], $nextline[5]);
            }
            # construct and run the query
            $query = "SELECT " . join(',',@fieldList) . " FROM \"$table\"";
            $query .= " WHERE $predicate" if ($predicate);
            if (!($isConnected) || SQLExecDirect($hstmt,$query,SQL_NTS) != SQL_SUCCESS) {
               Warn("Query {$query} against $host $namespace failed:");
               Warn(join(' ', SQLGetDiagRec(SQL_HANDLE_STMT,$hstmt,1))) if ($isConnected);
               push @results, map { $_ . ':U' } @indexList;
            } else {
               if (($rc = SQLFetch($hstmt)) == SQL_SUCCESS) {
                  for (my $i = 1; $i <= scalar(@fieldList); $i++) {
                     ($rc, $data, $datalen) = SQLGetData($hstmt,$i);
                     if ($rc == SQL_SUCCESS) { push @results, "$indexList[$i - 1]:$data"; }
                     else { push @results, "$indexList[$i - 1]:U"; } 
                  }
               } else {
                  Warn("No result from $query. ");
                  Warn(join(' ', SQLGetDiagRec(SQL_HANDLE_STMT,$hstmt,1))) unless ($rc == SQL_NO_DATA_FOUND);
                  push @results, map { $_ . ':U' } @indexList;
               }
            }
            SQLFreeHandle(SQL_HANDLE_STMT,$hstmt) if ($isConnected);
            # @nextline is already set
            # check if a new connection is required
            # use an order designed to take advantage of shortcut evaluation
            if (!defined($line) || $host ne $nextline[2] || 
                $uid ne $nextline[1] || $namespace ne $nextline[3])
            { last TABLELOOP; }
            # continue with the next table/predicate
            ($index, $uid, $host, $namespace, $table, $field, $predicate) = @nextline;     
         }
      }
      if (defined $hdbc) {
         SQLDisconnect($hdbc) if ($isConnected);
         SQLFreeHandle(SQL_HANDLE_DBC,$hdbc);
      }
      SQLFreeHandle(SQL_HANDLE_ENV,$henv);
      return @results;
}

1;

