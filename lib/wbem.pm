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
# (similar to SQL) queries to the WMI COM Interface.

use Common::Log;
use Win32::OLE;
use Win32::OLE::Enum;
use Win32::OLE::Const 'Microsoft WMI Scripting V1.1 Library';

$main::gDSFetch{'wbem'} = \&wbemFetch;

sub wbemFetch {
      # This procedure is passed a REFERENCE to an array of wbemodbc datasources.
      # Each line consists of "index:uid:host:namespace:table:field:predicate"
      # Predicate is optional.
      # uid is assumed to be the current user running Cricket, and this uid
      # is presumed to have sufficient authority on the remote host.
      # VERY IMPORTANT: The index MUST be returned with the corresponding value,
      # otherwise it'll get put back into the wrong spot in the RRD.

      my($dsList, $name, $target) = @_;

      my (@results, @lines, $line, @nextline);
      my ($locator, $service, $objectSet, $object) = (undef, undef, undef, undef);
      my $query = undef;
      my ($index, $host, $namespace, $table, $field, $predicate);
      my (@fieldList, @indexList);
      my $isConnected = 0;

      # sort lines by host, namespace, and table 
      # (default they are sorted by index)
      @lines = sort {
	 substr ($a, index($a, ':')) cmp substr ($b, index($b, ':'))
      } (@{$dsList});

      # connect or load the WMI locator
      $locator = Win32::OLE->GetActiveObject("WbemScripting.SWbemLocator");
      $locator = Win32::OLE->new("WbemScripting.SWbemLocator") unless defined $locator;
      Error("failed to load WMI locator") unless defined $locator;
      $locator -> {Security_} -> {ImpersonationLevel} = wbemImpersonationLevelImpersonate;

      $line = shift @lines;
      CONNECTLOOP: while (defined($line)) 
      {
         ($index, $host, $namespace, $table, $field, $predicate) =
            split(/:/,$line,6);
         # obtain the WMI service interface for the namespace/host
         undef $service;
         $service = $locator -> ConnectServer($host,$namespace);
         if (defined $service) 
         {
            $isConnected = 1; 
         } else {
            Warn("ConnectServer to $host $namespace failed:");
            Warn(Win32::OLE->LastError());
            $isConnected = 0;
         }
 
         TABLELOOP: while (1)
         {
            @fieldList = ();
            @indexList = ();
            FIELDLOOP: while (1) {
               push @fieldList, "$field";
               push @indexList, $index;
               # group together queries to the same table with the same predicate
               $line = shift @lines;
               @nextline = split(/:/,$line,6) if (defined($line));
               if (!defined($line) || $table ne $nextline[3] || 
                  ($predicate ? $predicate : "") ne ($nextline[5] ? $nextline[5] : "") ||
                   $host ne $nextline[1] || $namespace ne $nextline[2])
               { last FIELDLOOP; }
               ($index, $field) = ($nextline[0], $nextline[4]);
            }
            # construct and run the query
            $query = "SELECT " . join(',',@fieldList) . " FROM $table";
            $query .= " WHERE $predicate" if ($predicate);
            undef $objectSet;
            $objectSet = $service -> ExecQuery($query,
		"WQL", wbemFlagReturnWhenComplete) if ($isConnected);
            if (!($isConnected) || !$objectSet) {
               Warn("Query {$query} against $host $namespace failed:");
               Warn(Win32::OLE->LastError()) if $isConnected;
               Warn("no connection") unless $isConnected;
               push @results, map { $_ . ':U' } @indexList;
            } else {
               $object = undef;
               my @temp = in $objectSet;
               # query should always be singleton select
               $object = shift @temp;
               if ($object) {
                 for (my $i = 1; $i <= scalar(@fieldList); $i++) {
                     my $data = $object -> {$fieldList[$i-1]};
                     push @results, "$indexList[$i - 1]:$data"
                 }
               } else {
                  Warn("No result from $query: " . Win32::OLE->LastError());
                  push @results, map { $_ . ':U' } @indexList;
               }
            }
            # @nextline is already set
            # check if a new connection is required
            # use an order designed to take advantage of shortcut evaluation
            if (!defined($line) || $host ne $nextline[1] || $namespace ne $nextline[2])
            { last TABLELOOP; }
            # continue with the next table/predicate
            ($index, $host, $namespace, $table, $field, $predicate) = @nextline;     
         }
      }
      # not certain is this required
      undef $object;
      undef $objectSet;
      undef $service;
      undef $locator;
      return @results;
}

1;
