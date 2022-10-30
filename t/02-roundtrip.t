use Timezones::ZoneInfo:auth<zef:guifa>;
use Test;
my @timezones = <Etc/GMT America/New_York America/Los_Angeles Europe/Madrid
                 Asia/Tokyo Africa/Kinshasa Africa/Mogadishu Asia/Qatar Asia/Singapore>;
for ^100 {
    my $timezone = timezone-data @timezones.roll;
    my $in = (^1700000000).roll;
    my $mid = calendar-from-posix $in,  $timezone;
    my $out = posix-from-calendar $mid, $timezone;

    is $in, $out, "Random test ($in)";
}
done-testing;