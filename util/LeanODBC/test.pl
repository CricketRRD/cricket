# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..15\n"; }
END {print "not ok 1\n" unless $loaded;}
use LeanODBC qw(:ALL);
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):
my @ret = SQLAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE);
print (($ret[0] == SQL_SUCCESS) ? "ok 2\n" : "not ok 2\n");
my $henv = $ret[1];
@ret = SQLAllocHandle(SQL_HANDLE_DBC,$henv);
print (($ret[0] == SQL_SUCCESS) ? "ok 3\n" : "not ok 3 $ret[0]\n");
my $hdbc = $ret[1];
my ($dsn, $user, $pwd) = ('NORTHWIND','','');
@ret = SQLConnect($hdbc,$dsn,$user,$pwd);
print (($ret[0] == SQL_SUCCESS) ? "ok 4\n" : "not ok 4\n");
if ($ret[0] != SQL_SUCCESS)
{
@ret = SQLGetDiagRec(SQL_HANDLE_DBC,$hdbc,1);
print join(' ',@ret) . "\n";
print "Troubleshooting: Did you create an ODBC Data Source" .
      " for the MS Access 2000 database fpnwind.mdb called NORTHWIND?\n";
die "Aborting test";
}
# test a basic SELECT and FETCH
@ret = SQLAllocHandle(SQL_HANDLE_STMT,$hdbc);
print (($ret[0] == SQL_SUCCESS) ? "ok 5\n" : "not ok 5\n");
my $hstmt = $ret[1];
# select bogus string in case the Northwind db changes records in the future
# remember, we are testing the API not the DB
@ret = SQLExecDirect($hstmt,
       'SELECT \'dummy1\' as "Last Name", NULL as "First Name"' .
       ' FROM Employees', SQL_NTS);
print (($ret[0] == SQL_SUCCESS) ? "ok 6\n" : "not ok 6\n");
if ($ret[0] != SQL_SUCCESS)
{
@ret = SQLGetDiagRec(SQL_HANDLE_STMT,$hstmt,1);
print join(' ',@ret) . "\n";
}
@ret = SQLNumResultCols($hstmt);
print (($ret[0] == SQL_SUCCESS && $ret[1] == 2) ? "ok 7\n" : "not ok 7\n");
@ret = SQLFetch($hstmt);
print (($ret[0] == SQL_SUCCESS) ? "ok 8\n" : "not ok 8\n");
if ($ret[0] != SQL_SUCCESS)
{
@ret = SQLGetDiagRec(SQL_HANDLE_STMT,$hstmt,1);
print join(' ',@ret) . "\n";
}
@ret = SQLGetData($hstmt,1);
print (($ret[0] == SQL_SUCCESS &&
        $ret[1] eq 'dummy1') ? "ok 9\n" : "not ok 9\n");
@ret = SQLGetData($hstmt,2);
print (($ret[0] == SQL_SUCCESS &&
        $ret[2] == SQL_NULL_DATA) ? "ok 10\n" : "not ok 10\n");
@ret = SQLCloseCursor($hstmt);
print (($ret[0] == SQL_SUCCESS) ? "ok 11\n" : "not ok 11\n");
@ret = SQLFreeHandle(SQL_HANDLE_STMT,$hstmt);
print (($ret[0] == SQL_SUCCESS) ? "ok 12\n" : "not ok 12\n");
@ret = SQLDisconnect($hdbc);
print (($ret[0] == SQL_SUCCESS) ? "ok 13\n" : "not ok 13\n");
@ret = SQLFreeHandle(SQL_HANDLE_DBC,$hdbc);
print (($ret[0] == SQL_SUCCESS) ? "ok 14\n" : "not ok 14\n");
@ret = SQLFreeHandle(SQL_HANDLE_ENV,$henv);
print (($ret[0] == SQL_SUCCESS) ? "ok 15\n" : "not ok 15\n");

