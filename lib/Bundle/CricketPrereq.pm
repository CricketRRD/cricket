package Bundle::CricketPrereq;

$VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);

1;

__END__

=head1 NAME

Bundle::CricketPrereq - A bundle to install all the modules Cricket needs.

=head1 SYNOPSIS

 perl -MCPAN -e 'install Bundle::CricketPrereq'

=head1 CONTENTS

Digest::MD5	2.09		- Message Digest 5

LWP	5.48				- library for WWW access in Perl

DB_File 1.73			- access to Berkeley DB 1.x

Date::Parse 2.11		- parses dates

Time::HiRes	01.20		- high resolution timing

=head1 DESCRIPTION

This bundle defines all reqreq modules for Cricket.

=head1 AUTHOR

Jeff R. Allen <jeff.allen@acm.org>

=cut

