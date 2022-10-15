unit class Time is export;

has int16 $.second     is rw;      #=  0..61  (for leapseconds)
has int16 $.minute     is rw;      #=  0..59
has int16 $.hour       is rw;      #=  0..23
has int16 $.day        is rw;      #=  1..31
has int16 $.month      is rw;      #=  0..11  (months since January)
has int32 $.year       is rw;      #= -∞..∞   (years since 1900; 1910 = 10; 1899 = -1)
has int16 $.weekday    is rw =  0; #=  0..6   (days since Sunday; Monday = 1)
has int16 $.yearday    is rw =  0; #=  0..365 (Day index in year)
has int16 $.dst        is rw = -1; #= -1..1   (0 no dst, 1 dst, -1 unknown/automatic)
has int16 $.gmt-offset is rw =  0; #= -∞..∞   (offset of GMT, positive = east of GMT)
has str   $.tz-abbr    is rw = ""; #=         (Timezone abbreviation NULL AFTER localtime)

multi method gist(::?CLASS:D:) {
    ~ ($!year+1900)
    ~ "-"
    ~ ('0' if $!month < 9) ~ ($!month+1)
    ~ "-"
    ~ ('0' if $!day < 10) ~ $!day
    ~ " at "
    ~ ('0' if $!hour < 10) ~ $!hour
    ~ ':'
    ~ ('0' if $!minute < 10) ~ $!minute
    ~ ':'
    ~ ('0' if $!second < 10) ~ $!second
    ~ ', Z'
    ~ ($!gmt-offset < 0 ?? '-' !! '+' )
    ~ $!gmt-offset.abs.polymod(60,60).reverse.map({ ('0' if $^x < 10) ~ $^x}).join(':');
}
