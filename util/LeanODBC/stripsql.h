
#ifdef __cplusplus
extern "C" { 			/* Assume C declarations for C++   */
#endif  /* __cplusplus */

/* ODBC function return values */
#define SQL_SUCCESS                0
#define SQL_SUCCESS_WITH_INFO      1
#define SQL_NO_DATA              100
#define SQL_ERROR                 (-1)
#define SQL_INVALID_HANDLE        (-2)
#define SQL_NO_DATA_FOUND	 100

/* null-terminated string code */
#define SQL_NTS                   (-3)

/* handle type identifiers */
#define SQL_HANDLE_ENV             1
#define SQL_HANDLE_DBC             2
#define SQL_HANDLE_STMT            3
#define SQL_HANDLE_DESC            4

/* null handles returned by SQLAllocHandle() */
#define SQL_NULL_HENV       0
#define SQL_NULL_HDBC       0
#define SQL_NULL_HSTMT      0
#define SQL_NULL_HDESC      0
#define SQL_NULL_HANDLE     0L

/* typedefs & defines not exported via Perl */
typedef unsigned char   SQLCHAR;
typedef long            SQLINTEGER;
typedef short           SQLSMALLINT;
typedef unsigned short  SQLUSMALLINT;
typedef void *		SQLPOINTER;
typedef SQLSMALLINT     SQLRETURN;
typedef void*		SQLHANDLE;
typedef SQLHANDLE	SQLHSTMT;
typedef SQLHANDLE	SQLHDBC;
#define SQL_C_CHAR    		1
#define SQL_ATTR_ODBC_VERSION	200
#define	SQL_OV_ODBC3		3UL
#define SQL_DRIVER_NOPROMPT     0
#define SQL_NULL_DATA          (-1)
#define SQL_API		__stdcall

SQLRETURN SQL_API    SQLAllocHandle(SQLSMALLINT HandleType,
           SQLHANDLE InputHandle, SQLHANDLE *OutputHandle);

SQLRETURN SQL_API    SQLCloseCursor(SQLHSTMT StatementHandle);

SQLRETURN SQL_API    SQLConnect(SQLHDBC ConnectionHandle,
           SQLCHAR *ServerName, SQLSMALLINT NameLength1,
           SQLCHAR *UserName, SQLSMALLINT NameLength2,
           SQLCHAR *Authentication, SQLSMALLINT NameLength3);

SQLRETURN SQL_API    SQLDisconnect(SQLHDBC ConnectionHandle);

SQLRETURN SQL_API    SQLDriverConnect(
    SQLHDBC            hdbc,
    SQLHANDLE          hwnd,
    SQLCHAR 	       *szConnStrIn,
    SQLSMALLINT        cbConnStrIn,
    SQLCHAR            *szConnStrOut,
    SQLSMALLINT        cbConnStrOutMax,
    SQLSMALLINT        *pcbConnStrOut,
    SQLUSMALLINT       fDriverCompletion);

SQLRETURN SQL_API    SQLExecDirect(SQLHSTMT StatementHandle,
           SQLCHAR *StatementText, SQLINTEGER TextLength);

SQLRETURN SQL_API    SQLFetch(SQLHSTMT StatementHandle);

SQLRETURN SQL_API    SQLFreeHandle(SQLSMALLINT HandleType, SQLHANDLE Handle);

SQLRETURN SQL_API    SQLGetData(SQLHSTMT StatementHandle,
           SQLUSMALLINT ColumnNumber, SQLSMALLINT TargetType,
           SQLPOINTER TargetValue, SQLINTEGER BufferLength,
           SQLINTEGER *StrLen_or_Ind);

SQLRETURN SQL_API    SQLGetDiagRec(SQLSMALLINT HandleType, SQLHANDLE Handle,
           SQLSMALLINT RecNumber, SQLCHAR *Sqlstate,
           SQLINTEGER *NativeError, SQLCHAR *MessageText,
           SQLSMALLINT BufferLength, SQLSMALLINT *TextLength);

SQLRETURN SQL_API    SQLNumResultCols(SQLHSTMT StatementHandle,
           SQLSMALLINT *ColumnCount);

SQLRETURN SQL_API    SQLSetEnvAttr(SQLHANDLE EnvironmentHandle,
	   SQLINTEGER Attribute,
	   SQLPOINTER ValuePtr,
	   SQLINTEGER StringLength);

#ifdef __cplusplus
} /* End of extern "C" { */
#endif  /* __cplusplus */
