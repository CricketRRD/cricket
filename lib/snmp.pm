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

# This lets people replace our choice of snmp libraries by simply
# replacing snmpUtils.pm (Ed, this means you! <wink>)

use snmpUtils;

use Common::Log;

use strict;

# This tells the collector that we are open for business and
# happy to handle snmp:// datasources.
$main::gDSFetch{'snmp'} = \&snmpFetch;

sub snmpFetch {
    # This procedure is passed a REFERENCE to an array of SNMP datasources.
    #
    # Each element consists of a string like:
    #		index://community@host:port/oid
    # community and port are optional. If they are left out, they
    # will default to public and 161, respectively.
    #
    # VERY IMPORTANT: The index MUST be returned with the corresponding value,
    # otherwise it'll get put back into the wrong spot in the RRD.

    my($dsList, $name, $target) = @_;
	my(%oidsPerSnmp) = ();

	my($dsspec);
	my($oidMap) = $main::gCT->configHash($name, 'oid');
    foreach $dsspec (@{ $dsList }) {
		my($index);

		($index, $dsspec) = split(/:/, $dsspec, 2);
		$dsspec =~ s#^//##;
		
		# This little hack is for people who like to use slashes in their 
		# community strings.
		my($comm, $cinfo) = split(/@/, $dsspec, 2);
		my($snmp, $oid)   = split(/\//, $cinfo, 2);	
		$snmp = $comm . "@" . $snmp;

		$oid = mapOid($oidMap, $oid);
		if (! defined $oid) {
			Warn("Could not find an OID in $dsspec");
			return ();
		}
		
		# Debug("SNMP parser: snmp://$snmp/$oid");
		
		# we only try to process them if we didn't find a problem
		# above (hence the check for undef)
		push(@{ $oidsPerSnmp{$snmp} }, "$index:$oid")
			if (defined $oid);
    }
	
    my(@results) = ();
	
    while (my($snmp, $snmpDSRef) = each %oidsPerSnmp) {
		my(@oidsToQuery) = ();
		
		if ($#{ $snmpDSRef } >= 0) {
			my(@oidsToQuery) = my(@indices) = ();
			my($line);
			while ($line = shift @{ $snmpDSRef }) {
				my($index, $oid) = split(/:/, $line);
				push(@indices, $index); push(@oidsToQuery, $oid);
			}

			Debug("Getting from $snmp ", join(" ", @oidsToQuery));
			my(@hostResults) = snmpUtils::get($snmp, @oidsToQuery);
			Debug("Got: ", join(" ", @hostResults));
			
			# it tells us everything went to hell by returning
			# scalar -1. Unfortunately, we interpret that as the first
			# result. So, make it undef so that we fix it later.
			# hopefully, we don't need to fetch a -1 all the time...
			
			if (defined($hostResults[0]) && $hostResults[0] == -1) {
				$hostResults[0] = undef;
			}
			
			# turn undefs into "U"'s to make RRD happy
			my($ctr);
			for $ctr ( 0..$#indices ) {
				my($res) = $hostResults[$ctr];
				$res = "U" if (! defined($res));
				push(@results, "$indices[$ctr]:$res");
			}
		}
    }
	
    return @results;
}

1;

