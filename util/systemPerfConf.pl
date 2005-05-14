#!/usr/bin/perl -w

# Host config file generator for Cricket, based on work by
# James Moore <jam@afn.org> and Grimshaw Stuart
# <stuart.grimshaw@blackburn.gov.uk>
# Hacked beyond recognition by Bert Driehuis to update the MIBs used and
# remove some dependancy on the presence of MIB files.
# Michael Han added the handling of network interface and sanitized the
# SNMP interface.
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

BEGIN {
    my $programdir = (($0 =~ m:^(.*/):)[0] || "./") . "..";
    eval "require '$programdir/cricket-conf.pl'";
    eval "require '/usr/local/etc/cricket-conf.pl'"
        unless $Common::global::gInstallRoot;
    $Common::global::gInstallRoot ||= $programdir;
}

use lib "$Common::global::gInstallRoot/lib";

use Getopt::Long;
use snmpUtils;

# Option values
my $help = 0;
my $community = "public";
my $auto = 0;
my $host;
my $include;
my $skip;

# OID dictionary
my %oid = ("sysDescr" =>	               "1.3.6.1.2.1.1.1",
           "ifDescr" =>                    "1.3.6.1.2.1.2.2.1.2",
           "ssCpuRawUser" =>               "1.3.6.1.4.1.2021.11.50.0",
           "diskIODevice" =>               "1.3.6.1.4.1.2021.13.15.1.1.2",
           "hrStorageFixedDisk" =>         "1.3.6.1.2.1.25.2.1.4",
           "hrStorageType" =>              "1.3.6.1.2.1.25.2.3.1.2",
           "hrStorageDescr" =>             "1.3.6.1.2.1.25.2.3.1.3",
           "hrStorageAllocationUnits" =>   "1.3.6.1.2.1.25.2.3.1.4",
           "hrStorageSize" =>              "1.3.6.1.2.1.25.2.3.1.5",
           "hrSystemNumUsers" =>           "1.3.6.1.2.1.25.1.5.0");

# Options accepted:
GetOptions('auto'=>\$auto, 'community:s'=>\$community, 'help'=>\$help,
           'host:s'=>\$host, 'include:s'=>\$include, 'skip:s'=>\$skip);

print_help() if $help;
print_help("--host is a required option") if !$host;
print_help("Specify either --auto or --include=...") if !$auto && !$include;

my $unavailable_ok = 1 if $auto;

my %include = ("system" => 1,
               "storage" => 1,
               "diskio" => 1,
               "cpu" => 1,
               "interface" => 1) if $auto;
if ($include) {
    foreach my $what (split(/\s*,\s*/, $include)) {
        $include{$what} = 1;
    }
}

my @skip = split(/\s*,\s*/, $skip) if $skip;

my $snmp = "$community\@$host";
my $system_objectId = snmpUtils::get($snmp, "$oid{sysDescr}.0");
die "Can't contact $host" unless $system_objectId;

my $order = 999;
print template_header($host, $community);
print get_systemtable($snmp) if defined($include{"system"});
print get_cputable($snmp) if defined($include{"cpu"});
print get_iftable($snmp) if defined($include{"interface"});
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

sub template_interface {
    my ($target) = @_;
    return "" if isSkipTarget("if_$target");
    my $tmpl = <<"EOF";

target if_$target
    target-type   = standard-interface
    inst          = map(interface-name)
    interface-name= "$target"
    short-desc    = \"network activity on $target\"
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

sub get_cputable {
    my $snmp = shift;
    my $rawcpu = snmpUtils::get($snmp, $oid{"ssCpuRawUser"});
    print STDERR "Could not fetch ucd_rawcpu table\n" unless $auto;
    return template_ucd_sys();
}

sub get_iftable {
    my $snmp = shift;
    my $tmpl = "";
    my $junk;

    my @interfaces = snmpUtils::walk($snmp, $oid{"ifDescr"});
    map { ($junk, $_)= split /:/, $_ } @interfaces;
    foreach (@interfaces) {
        $tmpl .= template_interface($_);
    }
    return $tmpl;
}

sub get_diskiotable {
    my $snmp = shift;
    my $tmpl = "";
    my $junk;

    my @disknames = snmpUtils::walk($snmp, $oid{"diskIODevice"});
    map { ($junk, $_)= split /:/, $_ } @disknames;
    foreach (@disknames) {
        $tmpl .= template_ucd_diskio($_);
    }
    return $tmpl;
}

sub get_disktable {
    my $snmp = shift;
    my $tmpl = "";
    my ($junk, $key, $val, @list);

    @list = snmpUtils::walk($snmp, $oid{"hrStorageDescr"});
    if ($#list < 0) {
        print STDERR "Could not fetch hr_storage table\n" unless $auto;
        return "";
    }
    map { ($key, $val) = split /:/, $_; $disknames{$key} = $val; } @list;
    @list = snmpUtils::walk($snmp, $oid{"hrStorageType"});
    map { ($key, $val) = split /:/, $_; $disktypes{$key} = $val; } @list;
    @list = snmpUtils::walk($snmp, $oid{"hrStorageAllocationUnits"});
    map { ($key, $val) = split /:/, $_; $diskunits{$key} = $val; } @list;
    @list = snmpUtils::walk($snmp, $oid{"hrStorageSize"});
    map { ($key, $val) = split /:/, $_; $disksizes{$key} = $val; } @list;
    my (%diskbytes, %disktargets);
    foreach my $idx (sort { $a<=>$b } keys %disknames) {
        my $targetname = $disknames{$idx};
        if (    ($disktypes{$idx} ne $oid{"hrStorageFixedDisk"}) ||
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
    foreach $idx (sort { $a<=>$b } keys %disknames) {
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
    my $system_numusers = snmpUtils::get($snmp, $oid{"hrSystemNumUsers"});
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

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
