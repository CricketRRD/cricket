# -*- perl -*-

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

# a simple little RPN calculator -- implements the same operations
# that RRDTool does.

package RPN;

sub new {
    my($type) = @_;
    my($self) = {};
    bless($self, $type);
    return $self;
}

sub op {
    my($self, $op) = @_;

    if ($op eq '+') {
        my($a) = $self->pop();
        my($b) = $self->pop();
        return unless (defined($a) && defined($b));

        $self->push($b + $a);
    } elsif ($op eq '-') {
        my($a) = $self->pop();
        my($b) = $self->pop();
        return unless (defined($a) && defined($b));

        $self->push($b - $a);
    } elsif ($op eq '*') {
        my($a) = $self->pop();
        my($b) = $self->pop();
        return unless (defined($a) && defined($b));

        $self->push($b * $a);
    } elsif ($op eq '/') {
        my($a) = $self->pop();
        my($b) = $self->pop();
        return unless (defined($a) && defined($b));

        if ($a != 0) {
            $self->push($b / $a);
        } else {
            $self->push(undef);
        }
    } elsif ($op =~ /^LOG$/i) {
        my($a) = $self->pop();
        return unless (defined($a));

        if ($a != 0) {
            $self->push(log($a));
        } else {
            $self->push(undef);
        }
    }
}

sub pop {
    my($self) = @_;
    my($res) = pop(@{$self->{'stack'}});
    warn("Stack underflow") if (! defined($res));
    return $res;
}

sub push {
    my($self, @items) = @_;
    push @{$self->{'stack'}}, @items;
}

sub run {
    my($self, $string) = @_;

    my($item);
    foreach $item (split(/,/, $string)) {
        if ($item !~ /\d/ && ($item =~ /^[\+\*\/\-]/ || $item =~ /^log$/i)) {
            $self->op($item);
        } else {
            $self->push($item);
        }
    }

    return ($self->pop());
}

1;
