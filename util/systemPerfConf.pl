#!/usr/local/bin/perl -w

# Host config file generator for Cricket, based on work by
# James Moore <jam@afn.org> and Grimshaw Stuart
# <stuart.grimshaw@blackburn.gov.uk>
# Hacked beyond recognition by Bert Driehuis to update the MIBs used and
# remove some dependancy on the presence of MIB files.
#
# Options are shown by running this script with the --help option.
# Use like you would use listInterfaces, i.e. make sure these directories
# and files exist:
#    cricket-config/Defaults [from sample-config/Defaults]
#    cricket-config/systemperf
#    cricket-config/systemperf/Defaults [from sample-config/systemperf/Defaults]
#    cricket-config/systemperf/fileserver.yourcompany.com
#    cricket-config/systemperf/mailserver.yourcompany.com
# and run this script at regular intervals (say, daily at midnight), like
#   % systemPerfConf.pl --host fileserver.yourcompany.com \
#            > cricket-config/systemperf/fileserver.yourcompany.com/Targets
#   % systemPerfConf.pl --host mailserver.yourcompany.com \
#            > cricket-config/systemperf/mailserver.yourcompany.com/Targets

use Getopt::Long;
use SNMP;

# Option values
my $help = 0;
my $community = "public";
my $auto = 0;
my $host;
my $include;
my $skip;

# Options accepted:
GetOptions('auto'=>\$auto, 'community:s'=>\$community, 'help'=>\$help,
    'host:s'=>\$host, 'include:s'=>\$include, 'skip:s'=>\$skip);

print_help() if $help;
print_help("--host is a required option") if !$host;
print_help("Specify either --auto or --include=...") if !$auto && !$include;

my $unavailable_ok = 1 if $auto;

my %include = ("system", 1, "storage", 1, "diskio", 1, "cpu", 1) if $auto;
if ($include) {
    foreach my $what (split(/\s*,\s*/, $include)) {
        $include{$what} = 1;
    }
}

my @skip = split(/\s*,\s*/, $skip) if $skip;

my $snmp = open_snmp($host, $community);
my $system_objectId = $snmp->get(".1.3.6.1.2.1.1.1.0");
die "Can't contact $host" unless $system_objectId;

my $order = 999;
print template_header($host, $community);
print get_systemtable($snmp) if defined($include{"system"});
print get_cputable($snmp) if defined($include{"cpu"});
print get_disktable($snmp) if defined($include{"storage"});
print get_diskiotable($snmp) if defined($include{"diskio"});

sub print_help {
    my $string = shift;

    print STDERR "$string\n\n" if $string;

print STDERR <<"EOF";
usage: $0 --host <unix host> [--community <community>] [options]

    --host:        name of host to be monitored
    --community:   community string for host (Default: public)
    --help:        prints this help
    --auto:        try to include all possible monitorable items
    --include=...  include only specific monitorable items (comma separated
                   list):
       system      system users and processes
       cpu         CPU usage
       storage     disk space
       diskio      disk I/O stats
    --skip=...     comma separated list of regular expressions to skip
                   devices you don't want monitored

An example:
    $0 --host mailserver --auto --skip='diskio_[mf]d,disk_dos'
       Autodetect all MIBs on mailserver, but skip diskio stats for
       md and fd devices, and skip any dos partitions
    $0 --host fileserver --include='cpu,storage'
       Only collect CPU usage and disk space on host "fileserver".

EOF

    exit(1);
}

sub template_header {
    my ($host, $community) = @_;
    my $tmpl = <<"EOF";

target --default--
    server          = $host
    snmp-community  = $community
EOF
    return $tmpl;
}

sub template_hr_sys {
    my $tmpl = <<"EOF";

target hr_sys
    target-type   = hr_System
    inst          = 0
    short-desc    = \"# of system processes and users\"
    order         = $order
EOF
    $order--;
    return $tmpl;
}

sub template_ucd_sys {
    my $tmpl = <<"EOF";

target ucd_sys
    target-type   = ucd_System
    short-desc    = \"CPU, Memory, and Load\"
    order         = $order
EOF
    $order--;
    return $tmpl;
}

sub template_hr_storage {
    my ($target, $index, $path, $size, $blocksize) = @_;
    return "" if isSkipTarget($target);
    my $tmpl = <<"EOF";

target $target
    target-type   = hr_Storage
    #inst          = $index
    inst          = map(hr-storage-name)
    hr-storage-name = "$path"
    short-desc    = \"Bytes used on $path\"
    max-size      = $size
    min-size      = $blocksize
    storage       = $target
    units         = $blocksize,*
    order         = $order
EOF
    $order--;
    return $tmpl;
}

sub template_ucd_diskio {
    my ($target) = @_;
    return "" if isSkipTarget("diskio_$target");
    my $tmpl = <<"EOF";

target diskio_$target
    target-type   = ucd_diskio
    inst          = map(ucd-diskio-device)
    ucd-diskio-device = "$target"
    short-desc    = \"disk I/O on $target\"
    order         = $order
EOF
    $order--;
    return $tmpl;
}


sub open_snmp {
    my ($host, $community, $port) = @_;
    $port ||= 161;
    my $timeout = 2;
    my $retries = 5;
    my $version = 1;

    $SNMP::auto_init_mib = 0;

    my %session_opts = (Community    => $community,
                        DestHost     => $host,
                        RemotePort   => $port,
                        Timeout      => $timeout * 1000000,
                        Retries      => $retries,
                        Version      => $version,
                        UseNumeric   => 1,
                        UseLongNames => 1);

    my $session = new SNMP::Session(%session_opts);
    die "Couldn't establish an SNMP session with $host" unless $session;
    return $session;
}

sub snmp_walk {
    my ($snmp, $oidbase) = @_;

    my %return = ();
    my $var = new SNMP::Varbind([$oidbase]);
    while ($snmp->getnext($var)) {
        last if substr($var->tag, 0, length($oidbase)) ne $oidbase;
        if (length($var->tag) > length($oidbase)) {
            my $index = substr($var->tag, length($oidbase) + 1);
            if (length($index) > 0) {
                $index .= "." . $var->iid;
            } else {
                $index = $var->iid;
            }
            $return{$index} = $var->val;
        } else {
            $return{$var->iid} = $var->val;
        }
    }
    return %return;
}

sub get_cputable {
    my $snmp = shift;
    my $rawcpu = $snmp->get(".1.3.6.1.4.1.2021.11.50.0");
    print STDERR "Could not fetch ucd_rawcpu table\n" unless $auto;
    return template_ucd_sys();
}

sub get_diskiotable {
    my $snmp = shift;
    my $tmpl = "";
    my %disknames = snmp_walk($snmp, ".1.3.6.1.4.1.2021.13.15.1.1.2");
    foreach my $idx (sort {$a <=> $b} keys %disknames) {
        $tmpl .= template_ucd_diskio($disknames{$idx});
    }
    return $tmpl;
}

sub get_disktable {
    my $snmp = shift;
    my $tmpl = "";

    my @disknames = snmp_walk($snmp, ".1.3.6.1.2.1.25.2.3.1.3");
    if ($#disknames < 0) {
        print STDERR "Could not fetch hr_storage table\n" unless $auto;
        return "";
    }
    my %disknames = @disknames;
    my %disktypes = snmp_walk($snmp, ".1.3.6.1.2.1.25.2.3.1.2");
    my %diskunits = snmp_walk($snmp, ".1.3.6.1.2.1.25.2.3.1.4");
    my %disksizes = snmp_walk($snmp, ".1.3.6.1.2.1.25.2.3.1.5");
    my %diskbytes;
    my $disktype_fixeddisk = ".1.3.6.1.2.1.25.2.1.4";
    foreach my $idx (keys %disknames) {
        my $targetname = $disknames{$idx};
        if (    ($disktypes{$idx} ne $disktype_fixeddisk) ||
                ($idx > 100) ||
                ($targetname =~ /\/proc\b/)) {
            delete $disknames{$idx};
            next;
        }
        $targetname =~ s/^\///;
        $targetname = "root" if $targetname eq "";
        $targetname =~ s/\//_/g;
        $disktargets{$idx} = "disk_" . $targetname;
        $diskbytes{$idx} = $diskunits{$idx} * $disksizes{$idx};
    }
    my $saved_order = $order--;
    my $saved_order2 = $order--;
    my @alltargets = ();
    foreach my $idx (sort {$a <=> $b} keys %disknames) {
        printf STDERR "%s: %s (%.0f)\n", $idx, $disknames{$idx}, $diskbytes{$idx};
        $tmpl .= template_hr_storage($disktargets{$idx}, $idx, $disknames{$idx},
                                     $diskbytes{$idx}, $diskunits{$idx});
        push @alltargets, $disktargets{$idx};
    }
    my $alltargets = join(';', @alltargets);
    my $mtargets_tmpl =<<"EOF";
target disks_all
    target-type   = hr_Storage
    mtargets      = $alltargets
    short-desc    = \"Disk usage (all disks)\"
    order         = $saved_order

#target disks_pct
#    target-type   = hr_StoragePct
#    mtargets      = $alltargets
#    short-desc    = \"Disk usage percentage (all disks)\"
#    order         = $saved_order2

EOF
    return $mtargets_tmpl . $tmpl;
}

sub get_systemtable {
    my $snmp = shift;
    my $system_numusers = $snmp->get(".1.3.6.1.2.1.25.1.5.0");
    if (!defined($system_numusers)) {
        return "" if $unavailable_ok;
        die "Cannot get number of users logged on";
    }
    return template_hr_sys();
}

sub isSkipTarget {
    my $target = shift;
    foreach my $skip (@skip) {
        return 1 if ($target =~ /^$skip/);
    }
    return 0;
}
