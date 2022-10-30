use Test;

use Timezones::ZoneInfo:auth<zef:guifa>;

my Set $standard = timezones-as-set;
my Set $all      = timezones-as-set :aliases;
my Set $aliases  = timezones-as-set :aliases, :!standard;

# Obviously, these are subject to change (see Ukraine in 2022.d update)
# and thus the test file here isn't foolproof.  That said, I've chosen
# a few that should be mostly stable.  If this test fails, please check
# to see that IANA hasn't shifted something around.

ok  $standard<America/New_York>;
ok  $all<     America/New_York>;
nok $aliases< America/New_York>;

sub check-unaliased($id) {
    subtest {
        ok  $standard{$id};
        ok  $all{$id};
        nok $aliases{$id};
    }, "$id (unaliased)";
}

sub check-alias-pair($old, $new) {
    subtest {
        ok  $all{$old};
        ok  $all{$new};
        ok  $aliases{$old};
        nok $aliases{$new};
        ok  $standard{$new};
        nok $standard{$old};
    }, "$old -> $new";
}

check-unaliased 'America/New_York';
check-unaliased 'Europe/Madrid';
check-unaliased 'Etc/GMT+5';

check-alias-pair 'Europe/Kiev',          'Europe/Kyiv';
check-alias-pair 'Asia/Chongqing',       'Asia/Shanghai';
check-alias-pair 'Africa/Asmera',        'Africa/Nairobi';
check-alias-pair 'America/Buenos_Aires', 'America/Argentina/Buenos_Aires';
check-alias-pair 'Pacific/Samoa',        'Pacific/Pago_Pago';
check-alias-pair 'Iran',                 'Asia/Tehran';

subtest {
    nok $standard<Foo/Bar>;
    nok $aliases<Foo/Bar>;
    nok $all<Foo/Bar>;
}, "Nonsensical IDs";

done-testing;
