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

sub funcFetch { 
    my($dsList, $name, $target) = @_; 
    my(@results); 
    my($line); 
    foreach $line (@{$dsList}) { 
        if ( $line =~ /(\d*):(.*)/) { 
            my ($res);  
            $res = eval $2; 
            push @results, "$1:$res"; 
        } 
    } 
    return @results; 
} 
 
1; 

