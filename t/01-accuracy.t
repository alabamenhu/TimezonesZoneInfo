use Test;
# to be fleshed out later
#`<<<<<<
use Timezones::ZoneInfo;
use Timezones::ZoneInfo::Time;

my $tm;
given DateTime.now {
    $tm = Time.new:
       year => .year - 1900,
       month => .month - 1,
       day => .day,
       hour => .hour,
       minute => .minute,
       second => .whole-second,
       dst => -1,
       gmt-offset => 0;
}
say $tm;
my $atl = timezone-data 'US/Eastern';
say $atl;
my $foo = posix-from-calendar $tm, $atl;
say $foo;
say DateTime.new: $foo;
say calendar-from-posix $foo, $atl;
>>>>>>
ok True;

done-testing;