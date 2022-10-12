use Test;
#`<<<
# This test is currently disabled pending warning system overhaul

use Timezones::ZoneInfo;
use CX::Warn::Timezones::UnknownID;
use Timezones::ZoneInfo::TransTimeInfo;
use Timezones::ZoneInfo::LeapSecInfo;

class Foo {
    my $TZ_MAX_TIMES = 2000;
    has int32         $.leapcnt = 0;     #= Number of leap seconds (e.g. +@!lsis)
    has int32         $.timecnt = 0;     #= Number of transition moments (e.g. +@!ats)
    has int32         $.typecnt = 0;     #= Number of local time type objects (TimeInfo)
    has int32         $.charcnt = 0;     #= Number of characters of timezone abbreviation strings (e.g. @!chars.join.chars)
    has Bool          $.goback    = False; #= Whether the time zone's rules loop in the future.
    has Bool          $.goahead   = False; #= Whether the time zone's rules loop in the past. (nearly always false)
    has str           $.chars      = "";    #= Time zone abbreviation strings (null delimited)
    has int64         @.ats[$TZ_MAX_TIMES];                #= Moments when timezone information transitions
    has int8          @.types[$TZ_MAX_TIMES]; #= The associated rule for each of the transition moments (to enable @!ats Z @!types)
    has TransTimeInfo @.ttis;                 #= The rules for the transition time, indicating seconds of offset (Transition time information structure)
    has LeapSecInfo   @.lsis;                 #= The leapseconds for this timezone.
    has str           $.name;

    method new {
        my int64 @ats[$TZ_MAX_TIMES];
        my int8  @types[$TZ_MAX_TIMES];
        self.bless:
            :0leapcnt,
            :0timecnt,
            :0typecnt,
            :0charcnt,
            :!goback,
            :!goahead,
            :@ats,
            :@types,
            :ttis[],
            :lsis[],
            :name<foo>



    }
}


#timezone-data 'Atlantic/Atlantis';
#CONTROL {
#    when UnknownID { ok True,  'Unknown Olsen ID Warning'; .resume }
#    default        { ok False, 'Unknown Olsen ID Warning'; .resume }
#}
>>>
ok True;

done-testing;
