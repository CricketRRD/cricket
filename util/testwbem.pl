
use lib "../lib";
use strict;
use Common::Log;
use wbem;

Common::Log::setLevel('debug');

# For 0,1, & 4 the consecutive colons (::) indicate poll the localhost
# 2 & 3 poll a remote host, substitute an appropriate hostname for <remote>
my @temp = (
	'0::Root/CIMV2:WIN32_PerfRawData_PerfDisk_PhysicalDisk:DiskReadsPersec:Name=\'_Total\'',
	'1::Root/CIMV2:CIM_Processor:LoadPercentage:DeviceID=\'CPU0\'',
	'2:<remote>:Root/CIMV2:WIN32_PerfRawData_PerfDisk_PhysicalDisk:DiskReadsPersec:Name=\'_Total\'',
        '3:<remote>:Root/CIMV2:CIM_Processor:LoadPercentage:DeviceID=\'CPU0\'',
        '4::Root/CIMV2:WIN32_PerfRawData_PerfDisk_PhysicalDisk:DiskWritesPersec:Name=\'_Total\'');

my @results = &{$main::gDSFetch{'wbem'}}(\@temp);

print join("\n",@results) . "\n";
