package sqlUtils;

use Common::Log;

sub sendto {
    my ($args, @data) = @_;
    my ($driver, $login, $password, $sybhome) = split(/,/, $args);
    my $dbh = DBI->connect($driver, $login, $password) ||
        Error("DBH connect failed because of: $DBI::errstr");
    my $ds = 0;
    foreach my $val (@data) {
        my @time = localtime();
        my $timestamp = ($time[4] + 1) . "-" . ($time[3]) . "-" .
            ($time[5] + 1900) . " $time[2]:$time[1]";

        $dbh->do("use cricket; " .
                 "insert into CricketData (targetPath, targetName, ds, " .
                 "value, timestamp) " .
                 "values ('$tpath', '$tname', '$ds', '$val', '$timestamp')");
        $ds++;
    }
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
