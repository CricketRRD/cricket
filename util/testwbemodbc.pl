
use lib "../lib";
use strict;
use Common::Log;
use wbemodbc;

Common::Log::setLevel('debug');

# substitue your own userid and hostname; for the local host, you can omit the hostname and the userid.
# note the '\\\\' to escape the \\ that precedes Windows hostnames
my @temp = (
	'0:<userid>:\\\\<hostname>:Root\CIMV2:WIN32_PerfRawData_PerfDisk_PhysicalDisk:DiskReadsPersec:Name=\'_Total\'',
	'1:<userid>:\\\\<hostname>:Root\CIMV2:CIM_Processor:LoadPercentage:DeviceID=\'CPU0\'',
	'2:<userid>:\\\\<hostname>:Root\CIMV2:WIN32_PerfRawData_PerfDisk_PhysicalDisk:DiskWritesPersec:Name=\'_Total\'');

my @results = &{$main::gDSFetch{'wbemodbc'}}(\@temp);

print join("\n",@results) . "\n";