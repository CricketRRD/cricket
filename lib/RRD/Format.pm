# -- perl --

# RRD::Format: constants useful when digging around in an RRD file
# from Perl
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

# PORTING:
#
# Because RRD datafiles are defined in terms of C structures,
# different C compilers will pad them differently. Thus, this
# file needs to be updated to understand the various file
# layouts. To add support for an unsupported architecture,
# add a section to setArch that matches your architecture.
 
# The simple C program getFormat.c (which is in the util directory)
# can probably be trusted to find the correct format strings
# for your architecture. Instructions on how to use it are in
# the comments at the beginning of the program.
# Please send patches in, as you find
# formats for your specific architecture.

package RRD::Format;
require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(sizeof);

sub new {
	my($class) = @_;
	my($self) = {};
	bless($self, $class);
	return $self;
}

sub format {
	my($self, $fmt) = @_;
	return $self->{$fmt};
}

sub isOld {
	my($str) = @_;
	return ($str eq "mrtg");
}

sub setArch {
	my($self, $archname) = @_;

	$self->{'cookie'}       = "RRD";
	$self->{'version'}      = "0001";
	$self->{'float_cookie'} = 8.642135e130;

	$self->{'DST_COUNTER'}	= 0;
	$self->{'DST_ABSOLUTE'} = 1;
	$self->{'DST_GAUGE'}	= 2;
	$self->{'DST_DERIVE'}	= 3;

	$self->{'CF_AVERAGE'} = 0;
	$self->{'CF_MINIMUM'} = 1;
	$self->{'CF_MAXIMUM'} = 2;

	$self->{'LAST_DS_LEN'} = 30;    # Tobias says, "DO NOT CHANGE THIS" :)

	$archname =~ s/-thread//g;

	if ($archname eq "sun4-solaris" ||
		 $archname eq "MSWin32-x86" || $archname eq "MSWin32-x86-object" ||
		 $archname eq "irix-o32") {

		$self->{'newOld'} = "A4";
		$self->{'statHead'} = "a4 a5 x7 d L L L x4 x80";
		$self->{'dsDef'} = "a20 a20 L x4 d d x56";
		$self->{'rraDef'} = "a20 L L x4 d x72";
		$self->{'pdpDef'} = "a30 x2 L x4 d x64";
		$self->{'cdpDef'} = "d L x4 x64";

		$self->{'liveHead'} = "L";
		$self->{'rraPtr'} = "L";
		$self->{'element'} = "d";

		return 1;

     } elsif ($archname =~ /^aix|i.?86/i) {
        # Matija.Grabnar@arnes.si says that these formats           
        # work for Solaris x86 too. And Patrick Myers <pjm@mcc.ac.uk>
		# says it works for i386-freebsd. Cool. And John Banner
		# <jbanner@UVic.Ca> says it works on AIX. And Dave Mangot
		# <dave@epylon.com> says it works on i386-openbsd.

		# So, let's simplify and just say, 'if it has i.86 in the name,
		# use this format.
 
        $self->{'newOld'} = "A4";                
        $self->{'statHead'} = "a4 a5 x3 d L L L x80";    
        $self->{'dsDef'} = "a20 a20 L x4 d d x56";       
        $self->{'rraDef'} = "a20 L L d x72";         
        $self->{'pdpDef'} = "a30 x2 L x4 d x64";      
        $self->{'cdpDef'} = "d L x4 x64";             
 
        $self->{'liveHead'} = "L";                      
        $self->{'rraPtr'} = "L";                            
        $self->{'element'} = "d";       
 
        return 1;         
    } elsif ( $archname eq 'alpha-dec_osf') {
		# Thanks to Melissa D. Binde <binde@amazon.com> for
		# finding this (and a major foobar in getFormat.c)

       	$self->{'statHead'} = "a4 a5 x7 d L L L x80";
       	$self->{'dsDef'} = "a20 a20 L d d x56";
       	$self->{'rraDef'} = "a20 L L d x72";
       	$self->{'pdpDef'} = "a30 x2 L d x64";
       	$self->{'cdpDef'} = "d L x64";

		$self->{'liveHead'} = "L";
		$self->{'rraPtr'} = "L";
		$self->{'element'} = "d";

	} elsif ( $archname =~ 'PA-RISC' or $archname eq 'powerpc-linux') {
		$self->{'statHead'} = "a4 a5 x7 d L L L x4 x80"; 
		$self->{'dsDef'} = "a20 a20 L x4 d d x56"; 
		$self->{'rraDef'} = "a20 L L x4 d x72"; 
		$self->{'pdpDef'} = "a30 x2 L x4 d x64"; 
		$self->{'cdpDef'} = "d L x4 x64"; 
		$self->{'liveHead'} = "L"; 
		$self->{'rraPtr'} = "L"; 
		$self->{'element'} = "d"; 
	} else {                                   
        return;                                     
    }                                                
}

# a utility subroutine to imitate C's sizeof() built-in
sub sizeof {
	my($template) = @_;
	return (length(pack($template)));
}
