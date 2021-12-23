use Timezones::ZoneInfo;
use Test;
#`<<<
use Timezones::ZoneInfo::Routines;
my $atl = get-timezone-data 'America/New_York';
my $mad = get-timezone-data 'Europe/Madrid';
my $dt = DateTime.now;

say $dt.posix;
my $dt2;
my $*TZDEBUG = True;
given my $atl2 = localsub $atl, $dt.posix {
    $dt2 = DateTime.new:
        year => .year + 1900,
        month => .month,
        day => .day,
        hour => .hour,
        minute => .minute,
        second => .second,
        timezone => .gmt-offset
}
#say localsub $mad, $dt.posix;

say "---------";
say $dt;
say $atl2;
say $dt2;
say floor $dt.posix - $dt2.posix;>>>

done-testing;
