use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'LeanODBC',
    'VERSION_FROM' => 'LeanODBC.pm', # finds $VERSION
    'LIBS'	=> ['-lc:\vc98\lib\odbc32.lib -lc:\vc98\lib\kernel32.lib'],
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
    ($] ge '5.005') ? (
        'AUTHOR' => 'Jake Brutlag (jakeb@corp.webtv.net)',
        'ABSTRACT' => 'Thin wrapper around a restricted set of the ODBC 3.x API',
    ) : (),
);
