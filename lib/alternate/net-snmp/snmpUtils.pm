#	$Id$
#	$Source$
#
# This is a simple wrapper for Net-SNMP. People who want to
# use other SNMP libraries can hook the calls here by replacing this
# copy of snmpUtils.pm with their own, which redirects the calls
# to their own library.
#
# To use this one, mv the original snmpUtils.pm out of the way and
# symlink this one in its place:
#	cd ~cricket/lib
#	mv snmpUtils.pm snmpUtils_SNMP_Session.pm
#	ln -s alternate/net-snmp/snmpUtils.pm snmpUtils.pm
#
# TODO:
#	Verify that traps are generated consistent with the main
#	implementation.
#	Provide an upper bound to the number of cached sessions,
#	by implementing an LRU cache.

package snmpUtils;

use Common::Log;
use SNMP;
use Sys::Hostname;

# this is the OID for enterprises.webtv.wtvOps.wtvOpsTraps
my($trapoid) = ".1.3.6.1.4.1.2595.1.1";

# Max number of times a device can fail to respond before we skip further
# requests.  Adjust as needed. (This should probably be made a target
# attribute in the config tree so it can be set on a per device basis.)
my $MAXTRIES = 2;

my %skipcnt;
my %sessions;
my @fifo;

my $hostname = undef;

sub init {
    %skipcnt = ();
    %sessions = ();
}

# Establish an SNMP session to the given host.

sub opensnmp {
    my($snmp) = @_;
    if (defined $sessions{$snmp}) {      # If we already have a session...
        if ($sessions{$snmp} != -1) {    # If it not blacklisted, return it.
            return $sessions{$snmp};
        } else {                         # Else blacklisted, return undef.
            return undef;
         }
    }

    my $snmp_url = $snmp;
    $snmp =~ s#snmp://##;
    my $istrap = 0;
    $istrap = 1 if ($snmp =~ s#trap://##);
    my ($comm, $rest) = split(/\@/, $snmp, 2);
    if (!defined($rest)) {
        $comm = undef;
        $rest = $snmp;
    }
    my ($host, $port, $timeout, $retries, $backoff, $version) =
                split(/\s*:\s*/, $rest);

    $comm ||= 'public';
    $port ||= 161 if !$istrap;
    $port ||= 162 if $istrap;
    $timeout ||= 2;
    $retries ||= 5;
    $backoff ||= 1;
    $version ||= 1;

    Info("Opening SNMP session to $host:$port/v$version");

    my %session_opts = (Community    => $comm,
                 DestHost     => $host,
                 RemotePort   => $port,
                 Timeout      => $timeout * 1000000,
                 Retries      => $retries,
                 Version      => $version,
                 AuthProto    => 'MD5',
                 PrivProto    => 'DES',
                 AuthPass     => '',
                 PrivPass     => '',
                 Context      => 'default',
                 SecName      => 'initial',
                 SecLevel     => 'authNoPriv',
                 UseNumeric   => 1,
                 UseLongNames => 1);

    my $session = new SNMP::Session(%session_opts) if !$istrap;
    $session = new SNMP::TrapSession(%session_opts) if $istrap;

    if (!defined($session)) {
        Warn("Can't set up session to $snmp");
        $sessions{$snmp} = -1;
        return undef;
    }

    $sessions{$snmp_url} = $session;    # Save the session for future reference.
    $skipcnt{$snmp_url} = $MAXTRIES;    # Init the blacklist counter.
    push @fifo, $snmp_url;
    if ($#fifo > 20) {
        my $old_url = shift @fifo;
        delete $sessions{$old_url};
        # We keep the blacklist entry
    }

    return $session;
}

sub count_error {
    my ($snmp, $session) = @_;
    # Strip community name from error
    my($ignore1, $ssnmp) = $snmp =~ /([^@]+@)?(.*)/;

    my $errstr = $session->{"ErrorStr"};
    Warn($errstr);

    if ($errstr =~ /timeout/i) {
        $skipcnt{$snmp}--;
        Warn("Skip count now $skipcnt{$snmp} for $ssnmp");

        if ($skipcnt{$snmp} <= 0) {
            Warn("Blacklisting $ssnmp");
            $sessions{$snmp} = -1;
         }
    }
}

sub get {
    my ($snmp, @oids) = @_;
    my $session = opensnmp($snmp);
    return () unless defined($session);

    my @vars;
    foreach my $oid (@oids) {
        my $var = new SNMP::Varbind([$oid]);
        push @vars, $var;
    }
    my $varlist = new SNMP::VarList(@vars);
    $session->get($varlist);
    if ($session->{"ErrorNum"}) {
        &count_error($snmp, $session);
        return ();
    }
    my @return;
    foreach my $var (@vars) {
        push @return, $var->val;
    }
    return @return;
}

sub walk {
    my ($snmp, $oid) = @_;
    my $session = opensnmp($snmp);
    return () unless defined($session);

    my @return = ();
    $oid = &SNMP::translateObj($oid) if $oid =~ /^[a-zA-Z]/;
    $oid = ".$oid" unless substr($oid, 0, 1) eq ".";
    my $var = new SNMP::Varbind([$oid]);
    while (defined $session->getnext($var)) {
        last if substr($var->tag, 0, length($oid)) ne $oid;
        if (length($var->tag) > length($oid)) {
            push @return, substr($var->tag, length($oid) + 1) . "." .
                 $var->iid . ":" .  $var->val;
        } else {
            push @return, $var->iid . ":" .  $var->val;
        }
    }
    return @return;
}

sub trap {
    my($to, $spec, @data) = @_;

    my @newdata = ();
    my($ct) = 1;
    foreach my $item (@data) {
        push @newdata, ".$ct", "", $item;
        $ct++;
    }
    &trap2($to, $spec, @newdata);
}

sub trap2 {
    my($to, $spec, @data) = @_;

    $to = "trap://$to" unless $to =~ /^trap/;
    my $session = opensnmp($to);
    return undef unless defined($session);

    # this makes a oid->value map for the trap. Note that
    # we just fake up simple one-level OID's... it suits our needs.
    my($type, $item, @vars);
    while (@data) {
        $oid = shift @data;
        shift @data;
        $item = shift @data;
        $type = OCTETSTR;
        $type = UINTEGER if ($item =~ /^(\d+)$/);
        $type = INTEGER if ($item =~ /^-(\d+)$/);

        my $var = new SNMP::Varbind([$oid, undef, $item, $type]);
        push @vars, $var;
    }
    my $varlist = new SNMP::VarList(@vars);
    $hostname ||= hostname();
    $session->trap(enterprise=>$trapoid, agent=>$hostname, specific=>$spec,
                   $varlist);
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
