package LeanODBC;

use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);

require Exporter;
require DynaLoader;
require AutoLoader;

@ISA = qw(Exporter DynaLoader);
@EXPORT_OK = qw(
	SQL_ERROR
	SQL_HANDLE_DBC
	SQL_HANDLE_DESC
	SQL_HANDLE_ENV
	SQL_HANDLE_STMT
	SQL_INVALID_HANDLE
	SQL_NO_DATA
	SQL_NO_DATA_FOUND
	SQL_NTS
        SQL_NULL_DATA
	SQL_NULL_HANDLE
	SQL_NULL_HDBC
	SQL_NULL_HDESC
	SQL_NULL_HENV
	SQL_NULL_HSTMT
	SQL_SUCCESS
	SQL_SUCCESS_WITH_INFO
        SQLAllocHandle
        SQLCloseCursor
        SQLConnect
        SQLDisconnect
        SQLDriverConnect
        SQLExecDirect
        SQLFetch
        SQLFreeHandle
        SQLGetData
        SQLGetDiagRec
        SQLNumResultCols
);
%EXPORT_TAGS = (ALL => [ qw(
	SQL_ERROR
	SQL_HANDLE_DBC
	SQL_HANDLE_DESC
	SQL_HANDLE_ENV
	SQL_HANDLE_STMT
	SQL_INVALID_HANDLE
	SQL_NO_DATA
	SQL_NO_DATA_FOUND
	SQL_NTS
        SQL_NULL_DATA
	SQL_NULL_HANDLE
	SQL_NULL_HDBC
	SQL_NULL_HDESC
	SQL_NULL_HENV
	SQL_NULL_HSTMT
	SQL_SUCCESS
	SQL_SUCCESS_WITH_INFO
        SQLAllocHandle
        SQLCloseCursor
        SQLConnect
        SQLDisconnect
        SQLDriverConnect
        SQLExecDirect
        SQLFetch
        SQLFreeHandle
        SQLGetData
        SQLGetDiagRec
        SQLNumResultCols
)]);

$VERSION = '0.90';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "& not defined" if $constname eq 'constant';
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
		croak "Your vendor has not defined LeanODBC macro $constname";
	}
    }
    no strict 'refs';
    *$AUTOLOAD = sub { $val };
    goto &$AUTOLOAD;
}

bootstrap LeanODBC $VERSION;

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

LeanODBC - This extension is a thin wrapper to a restricted subset of the ODBC 3.x API.

=head1 SYNOPSIS

  use LeanODBC (:ALL);

  @ret = SQLAllocHandle(SQL_HANDLE_HENV,SQL_NULL_HANDLE);
  $henv = $ret[1];
  @ret = SQLAllocHandle(SQL_HANDLE_DBC,$henv);
  $hdbc = $ret[1];
  @ret = SQLConnect($hdbc,'Sample DSN','MyUser','MyPwd');
  if ($ret[0] != SQL_SUCCESS) {
     @ret = SQLGetDiagRec(SQL_HANDLE_DBC,$hdbc,1);
     print join(' ',@ret) . "\n";
  } else { ... }

If this looks like raw ODBC API calls, that's intentional.

=head1 DESCRIPTION

This extension is a thin wrapper to a restricted subset of the ODBC 3.x API. It is not object-oriented and the functions share the same names as their ODBC 3.x counterparts. The restricted subset of the API only includes Core Interface functions for read-only operations.

The LeanODBC package exports no symbols by default. You can either import a specific list of symbols or use the tag 'ALL' to import everything.

To connect to an existing data source, LeanODBC exposes SQLConnect. Alternatively, you may specific a complete connect string and use SQLDriverConnect.

=head1 Constants

The following constants are exposed by the wrapper. Refer to the ODBC 3.x API documentation for their interpretation.

	SQL_ERROR
	SQL_HANDLE_DBC
	SQL_HANDLE_DESC
	SQL_HANDLE_ENV
	SQL_HANDLE_STMT
	SQL_INVALID_HANDLE
	SQL_NO_DATA
	SQL_NO_DATA_FOUND
	SQL_NTS
        SQL_NULL_DATA
	SQL_NULL_HANDLE
	SQL_NULL_HDBC
	SQL_NULL_HDESC
	SQL_NULL_HENV
	SQL_NULL_HSTMT
	SQL_SUCCESS
	SQL_SUCCESS_WITH_INFO

=head1 Functions

The functions are very similar to the ODBC C API. Parameters listed as [Output] in the ODBC 3.x API documentation are omitted when calling the wrapper versions. Functions with Output parameters return an array. The first value of the array is always the SQLRETURN value (SQL_SUCCESS, SQL_ERROR, etc). The remaining values in the array are the Output parameters in the order they appear in the ODBC API function call. Function without an Output parameter simply return the SQLRETURN value.

In some cases, [Input] parameters are also omitted. This is because the wrapper substitutes specific values for some parameters.

The list of functions exposed through the wrapper follows. The parameter names listed match those of the ODBC API documentation and have the same meaning.

=over 4

=item SQLAllocHandle(HandleType, InputHandle)

Returns an array: (SQLRETURN, OutputHandle). The wrapper will automatically set the ODBC environment to SQL_OV_ODBC3 when an environment handle is allocated.

=item SQLCloseCursor(StatementHandle)

=item SQLConnect(StatementHandle,ServerName,UserName,Authentication)

=item SQLDisconnect(ConnectionHandle)

=item SQLDriverConnect(ConnectionHandle,InConnectString,StringLength)

SQL_NTS constant may be substituted for StringLength. Returns an array: (SQLRETURN, OutConnectionString, StringLength). Note that the driver completion/ dialog window options are not available.

=item SQLExecDirect(StatementHandle, StatementText, TextLength)

SQL_NTS constant may be substituted for TextLength.

=item SQLFetch(StatementHandle)

=item SQLFreeHandle(HandleType, Handle)

=item SQLGetData(StatementHandle, ColumnNumber)

Returns an array: (SQLRETURN, TargetValue, StrLen_or_Ind). The wrapper always fetches data as SQL_C_CHAR, so TargetValue is a string and StrLen_or_Ind is the number of characters. Note that ODBC Drivers are required to support conversion from any data type to SQL_C_CHAR, so data  conversion issues should not be a problem. If the data value is NULL, TargetValue is the null string and StrLen_or_Ind is SQL_NULL_DATA.

=item SQLGetDiagRec(HandleType, Handle, RecNumber)

Returns an array: (SQLRETURN, sqlState, NativeError, MessageText, TextLength).

=item SQLNumResultCols(StatementHandle)

Returns an array: (SQLRETURN, ColumnCount).

=back

=head1 AUTHOR

Jake Brutlag, jakeb@corp.webtv.net

=head1 SEE ALSO

perl(1).

=cut
