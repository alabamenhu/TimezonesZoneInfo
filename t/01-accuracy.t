use Test;
use Timezones::ZoneInfo::Time:auth<zef:guifa>;
use Timezones::ZoneInfo:auth<zef:guifa>;

#| Compares two separate Time objects, returning an Order enum value
sub time-cmp(Time \a, Time \b) {
    if    a.year   != b.year   { return a.year   < b.year   ?? Order::Less !! Order::More }
    elsif a.month  != b.month  { return a.month  < b.month  ?? Order::Less !! Order::More }
    elsif a.day    != b.day    { return a.day    < b.day    ?? Order::Less !! Order::More }
    elsif a.hour   != b.hour   { return a.hour   < b.hour   ?? Order::Less !! Order::More }
    elsif a.minute != b.minute { return a.minute < b.minute ?? Order::Less !! Order::More }
    elsif a.second != b.second { return a.second < b.second ?? Order::Less !! Order::More }
    else { return Order::Same }
}

#| Creates a time object in a more succinct/human readable manner
sub make-time(:$y, :$M, :$d, :$h, :$m, :$s, :$wd, :$yd, :$dst, :$off, :$abbr) {
    Time.new: :year($y - 1900), :month($M - 1), :day($d), :hour($h), :minute($m), :second($s),
        :weekday($wd), :yearday($yd), :$dst, :gmt-offset($off), :tz-abbr($abbr)
}

# These are the timezones to be tested against
my \gmt      = timezone-data 'Etc/GMT';
my \new-york = timezone-data 'America/New_York';

# Each subtest chooses a time.  In each timezone, we provide a known-correct Time structure.
# The posix time is then converted into a calendar and compared.  The reverse (the known calendar
# being converted to a posix time) is also done.  Bo
subtest {
    my \time = 1577934245;

    with make-time(:2020y, :1M, :2d, :3h, :4m, :5s, :4wd, :1yd, :0dst, :off(0), :abbr<GMT>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, gmt)),
            Order::Same,
            '→ GMT';
        is  posix-from-calendar(calendar, gmt),
            time,
            '← GMT'
    }
    with make-time(:2020y, :1M, :1d, :22h, :4m, :5s, :3wd, :0yd, :0dst, :off(-18000), :abbr<EST>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, new-york)),
            Order::Same,
            '→ America/New_York';
        is  posix-from-calendar(calendar, new-york),
            time,
            '← America/New_York'
    }
}, 'GMT 2020-01-02T03:04:05 / POSIX 1577934245';

subtest {
    my \time = 467372577;

    with make-time(:1984y, :10M, :23d, :9h, :42m, :57s, :2wd, :296yd, :0dst, :off(0), :abbr<GMT>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, gmt)),
            Order::Same,
            '→ GMT';
        is  posix-from-calendar(calendar, gmt),
            time,
            '← GMT'
    }
    with make-time(:1984y, :10M, :23d, :5h, :42m, :57s, :2wd, :296yd, :1dst, :off(-14400), :abbr<EDT>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, new-york)),
            Order::Same,
            '→ America/New_York';
        is  posix-from-calendar(calendar, new-york),
            time,
            '← America/New_York'
    }
}, 'GMT 1984-10-23T09:42:57 / POSIX 467372577';

subtest {
    my \time = 703723256;

    with make-time(:1992y, :4M, :19d, :22h, :40m, :56s, :0wd, :109yd, :0dst, :off(0), :abbr<GMT>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, gmt)),
            Order::Same,
            '→ GMT';
        is  posix-from-calendar(calendar, gmt),
            time,
            '← GMT'
    }
    with make-time(:1992y, :4M, :19d, :18h, :40m, :56s, :0wd, :109yd, :1dst, :off(-14400), :abbr<EDT>) -> \calendar {
        is  time-cmp(calendar, calendar-from-posix(time, new-york)),
            Order::Same,
            '→ America/New_York';
        is  posix-from-calendar(calendar, new-york),
            time,
            '← America/New_York'
    }
}, 'GMT 1992-04-19T22:40:56 / POSIX 703723256';
#`<<<
Sunday, April 19, 1992 10:40:56 PM # GMT
Sunday, April 19, 1992  6:40:56 PM # should be
Sunday, April 19, 1992 10:40:56 AM # off by EIGHT
>>>
done-testing;