# This is a simple wrapper for SNMP_utils. People who want to
# use other SNMP libraries can hook the calls here by replacing this
# copy of snmpUtils.pm with their own, which redirects the calls
# to their own library.

package snmpUtils;

use Common::Log;

use BER;
use SNMP_Session;
use SNMP_util;
use Sys::Hostname;

# snmp_utils 0.55 has a reference to main::DEBUG, so we instantiate
# it here, if necessary
if (! defined($main::DEBUG)) {
	$main::DEBUG = 0;
}

# this keeps BER from formatting timeticks, so that if someone
# want to put them into an RRD, it would work.
$BER::pretty_print_timeticks = 0; 

my($err) = '';

# this funky wrapper is because SNMP_Session throws exceptions with
# warn(), which we need to catch, instead of letting them run
# roughshod over Cricket's output.

sub _do {
	my($subref, @args) = @_;
	my(@res);

	$err = '';
	eval {
		local($SIG{'__WARN__'}) = sub { $err = $_[0]; die($err); };
		@res = &{$subref}(@args);
	};

	# do a little post processing on the overly wordy errors
	# that SNMP_Session gives us...

	if (defined($err) && $err ne '') {
		my(@err) = split(/\n\s*/, $err);
		if ($#err+1 > 2) {
			my($code) = (split(/: /, $err[2]))[1];
			$err = "$err[1] $code";
		} else {
			$err =~ s/\n//g;
		}

		Warn($err);
	}

	return @res;
}

sub get {
	_do(\&snmpget, @_);
}

sub getnext {
	_do(\&snmpgetnext, @_);
}

sub walk {
	_do(\&snmpwalk, @_);
}

sub trap2 {
	my($to, $spec, @data) = @_;

	# this is the OID for enterprises.webtv.wtvOps.wtvOpsTraps
	my($ent) = ".1.3.6.1.4.1.2595.1.1";

	_do(\&snmptrap, $to, $ent, hostname(), 6, $spec, @data);
}

sub trap {
	my($to, $spec, @data) = @_;

	# this is the OID for enterprises.webtv.wtvOps.wtvOpsTraps
	my($ent) = ".1.3.6.1.4.1.2595.1.1";

	# this makes a oid->value map for the trap. Note that
	# we just fake up simple one-level OID's... it suits our needs.
	my($item, @vars);
	my($ct) = 1;
	foreach $item (@data) {
		my($type) = "string";
		$type = "integer" if ($item =~ /^(\d+)$/);

		push @vars, $ct, $type, $item;
		$ct++;
	}
	_do(\&snmptrap, $to, $ent, hostname(), 6, $spec, @vars);
}

1;
