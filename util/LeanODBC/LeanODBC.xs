#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "stripsql.h"

static int
not_here(char *s)
{
    croak("%s not implemented on this architecture", s);
    return -1;
}

static double
constant(char *name, int arg)
{
    errno = 0;
    switch (*name) {
    case 'A':
	break;
    case 'B':
	break;
    case 'C':
	break;
    case 'D':
	break;
    case 'E':
	break;
    case 'F':
	break;
    case 'G':
	break;
    case 'H':
	break;
    case 'I':
	break;
    case 'J':
	break;
    case 'K':
	break;
    case 'L':
	break;
    case 'M':
	break;
    case 'N':
	break;
    case 'O':
	break;
    case 'P':
	break;
    case 'Q':
	break;
    case 'R':
	break;
    case 'S':
	if (strEQ(name, "SQL_ERROR"))
#ifdef SQL_ERROR
	    return SQL_ERROR;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_HANDLE_DBC"))
#ifdef SQL_HANDLE_DBC
	    return SQL_HANDLE_DBC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_HANDLE_DESC"))
#ifdef SQL_HANDLE_DESC
	    return SQL_HANDLE_DESC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_HANDLE_ENV"))
#ifdef SQL_HANDLE_ENV
	    return SQL_HANDLE_ENV;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_HANDLE_STMT"))
#ifdef SQL_HANDLE_STMT
	    return SQL_HANDLE_STMT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_INVALID_HANDLE"))
#ifdef SQL_INVALID_HANDLE
	    return SQL_INVALID_HANDLE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NO_DATA"))
#ifdef SQL_NO_DATA
	    return SQL_NO_DATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NO_DATA_FOUND"))
#ifdef SQL_NO_DATA_FOUND
	    return SQL_NO_DATA_FOUND;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NTS"))
#ifdef SQL_NTS
	    return SQL_NTS;
#else
	    goto not_there;
#endif
if (strEQ(name, "SQL_NULL_DATA"))
#ifdef SQL_NULL_DATA
	    return SQL_NULL_DATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NULL_HANDLE"))
#ifdef SQL_NULL_HANDLE
	    return SQL_NULL_HANDLE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NULL_HDBC"))
#ifdef SQL_NULL_HDBC
	    return SQL_NULL_HDBC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NULL_HDESC"))
#ifdef SQL_NULL_HDESC
	    return SQL_NULL_HDESC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NULL_HENV"))
#ifdef SQL_NULL_HENV
	    return SQL_NULL_HENV;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_NULL_HSTMT"))
#ifdef SQL_NULL_HSTMT
	    return SQL_NULL_HSTMT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_SUCCESS"))
#ifdef SQL_SUCCESS
	    return SQL_SUCCESS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQL_SUCCESS_WITH_INFO"))
#ifdef SQL_SUCCESS_WITH_INFO
	    return SQL_SUCCESS_WITH_INFO;
#else
	    goto not_there;
#endif
	break;
    case 'T':
	break;
    case 'U':
	break;
    case 'V':
	break;
    case 'W':
	break;
    case 'X':
	break;
    case 'Y':
	break;
    case 'Z':
	break;
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}


MODULE = LeanODBC		PACKAGE = LeanODBC		


double
constant(name,arg)
	char *		name
	int		arg

short   
SQLAllocHandle(HandleType, InputHandle)
	short HandleType
	void* InputHandle
	PREINIT:
	void* OutputHandle;
	short rc;
	PPCODE:
	rc = SQLAllocHandle(HandleType,InputHandle,&OutputHandle);
	if (rc == SQL_SUCCESS && HandleType == SQL_HANDLE_ENV) {
	   SQLSetEnvAttr(OutputHandle,SQL_ATTR_ODBC_VERSION,(void*)SQL_OV_ODBC3,NULL);
	}
	EXTEND(SP, 2);
	PUSHs(sv_2mortal(newSViv(rc)));
	PUSHs(sv_2mortal(newSViv((long) OutputHandle)));

short    
SQLFreeHandle(HandleType, Handle)
	short	HandleType
	void*	Handle

short
SQLDisconnect(ConnectionHandle)
        void* ConnectionHandle

short
SQLGetDiagRec(HandleType, Handle, RecNumber)
	short HandleType 
	void* Handle
	short RecNumber 
	PREINIT:
	char sqlState[6];
        long NativeError;
	char MessageText[1024];
	short TextLength, rc;
	PPCODE:
	rc = SQLGetDiagRec(HandleType,Handle,RecNumber,
                (unsigned char*)sqlState,&NativeError,
		(unsigned char*)MessageText,1024,&TextLength);
	EXTEND(SP,5);
	PUSHs(sv_2mortal(newSViv(rc)));
	PUSHs(sv_2mortal(newSVpv(sqlState,5)));
	PUSHs(sv_2mortal(newSViv(NativeError)));
	PUSHs(sv_2mortal(newSVpv(MessageText,TextLength)));
	PUSHs(sv_2mortal(newSViv(TextLength)));

short
SQLDriverConnect(hdbc,szConnectStrIn,cbConnectStrIn)
	void*         hdbc
	char*	      szConnectStrIn
	short         cbConnectStrIn
	PREINIT:
	short cbConnStrOut;
	char szConnectStrOut[1024];
	short rc;
	PPCODE:
	rc = SQLDriverConnect(hdbc,NULL,
           (unsigned char*)szConnectStrIn, cbConnectStrIn,
	   (unsigned char*)szConnectStrOut,
           1024,&cbConnStrOut,SQL_DRIVER_NOPROMPT);
	EXTEND(SP,3);
	PUSHs(sv_2mortal(newSViv(rc)));
	PUSHs(sv_2mortal(newSVpv(szConnectStrOut,cbConnStrOut)));
	PUSHs(sv_2mortal(newSViv(cbConnStrOut)));           

short
SQLExecDirect(StatementHandle, StatementText, TextLength)
	void* StatementHandle
	unsigned char* StatementText 
	long TextLength

short   
SQLFetch(StatementHandle)
	void* StatementHandle

short   
SQLNumResultCols(StatementHandle)
	void* StatementHandle
	PREINIT:
	short ColumnCount, rc;
	PPCODE:
	rc = SQLNumResultCols(StatementHandle, &ColumnCount);
	EXTEND(SP,2);
	PUSHs(sv_2mortal(newSViv(rc)));
	PUSHs(sv_2mortal(newSViv(ColumnCount)));

short    
SQLGetData(StatementHandle, ColumnNumber)
	void* StatementHandle
	unsigned short ColumnNumber
	PREINIT:
	char TargetValue[1024] = "dummy";
	long StrLen_or_Ind, rc;
	PPCODE:
	rc = SQLGetData(StatementHandle,ColumnNumber,SQL_C_CHAR,
           (SQLPOINTER) TargetValue,1024,&StrLen_or_Ind);
	EXTEND(SP,3);
	PUSHs(sv_2mortal(newSViv(rc)));
	if (StrLen_or_Ind > 0) {
	   PUSHs(sv_2mortal(newSVpv(TargetValue,StrLen_or_Ind)));
	} else {
           TargetValue[0] = '\0';       
	   PUSHs(sv_2mortal(newSVpv(TargetValue,0)));
	}
	PUSHs(sv_2mortal(newSViv(StrLen_or_Ind)));

short   
SQLCloseCursor(StatementHandle)
	void* StatementHandle

short
SQLConnect(StatementHandle,ServerName,UserName,Authentication)
        void* StatementHandle
        unsigned char* ServerName
        unsigned char* UserName
        unsigned char* Authentication
        CODE:
        RETVAL = SQLConnect(StatementHandle, ServerName, SQL_NTS,
                 UserName, SQL_NTS, Authentication, SQL_NTS);
        OUTPUT:
        RETVAL
