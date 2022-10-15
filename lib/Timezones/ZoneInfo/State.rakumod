#| The information on timezone and leapseconds for a timezone
unit class State is export;

use Timezones::ZoneInfo::TransTimeInfo:auth<zef:guifa>;
use Timezones::ZoneInfo::LeapSecInfo:auth<zef:guifa>;

my int64 $SECSPERDAY     =  86400;
my int64 $SECSPERREPEAT  =  12622780800;
my int32 $INT_FAST32_MIN = -2**31;
my int32 $INT_FAST32_MAX =  2**31 - 1;
my int64 $TIME_T_MIN     = -2**63;
my int64 $TIME_T_MAX     =  2**63 - 1;

my $TZ_MAX_TIMES = 2000;

has int32         $.leapcnt = 0;          #= Number of leap seconds (e.g. +@!lsis)
has int32         $.timecnt = 0;          #= Number of transition moments (e.g. +@!ats)
has int32         $.typecnt = 0;          #= Number of local time type objects (TimeInfo)
has int32         $.charcnt = 0;          #= Number of characters of timezone abbreviation strings (e.g. @!chars.join.chars)
has Bool          $.goback    = False;    #= Whether the time zone's rules loop in the future.
has Bool          $.goahead   = False;    #= Whether the time zone's rules loop in the past. (nearly always false)
has str           $.chars      = "";      #= Time zone abbreviation strings (null delimited)
#has int64         @.ats[$TZ_MAX_TIMES];  #= Moments when timezone information transitions
has               @.ats;                  #= ^^ but with a quickfix due to segmentation fault in Rakudo v2021.12-146-gde06617cc / MoarVM 2021.12-81-gf1101b95d
has int8          @.types[$TZ_MAX_TIMES]; #= The associated rule for each of the transition moments (to enable @!ats Z @!types)
has TransTimeInfo @.ttis;                 #= The rules for the transition time, indicating seconds of offset (Transition time information structure)
has LeapSecInfo   @.lsis;                 #= The leapseconds for this timezone.
has str           $.name;

# Human readable method names
method transition-times            { @!ats   } #= Moments (as time_t or POSIX time stamps) when the timezone will transition. Alias of .ats
method transition-info-association { @!types } #= The associated transition time info for a moment (hint: use Z with .transition-times )
method transition-info             { @!ttis  } #= The info for the transition time, indicating seconds of offset (Transition time information structure)
method leapseconds                 { @!lsis  } #= The leapseconds for this timezone. Alias of .lsis
method abbreviations               { $!chars.split: "\0" }
method leap-count                  { $!leapcnt }
method time-count                  { $!timecnt }
method type-count                  { $!typecnt }
method char-count                  { $!charcnt }
method go-ahead                    { $!goahead }
method go-back                     { $!goback  }

multi method gist (::?CLASS:D:) { "TZif:$!name"}
multi method gist (::?CLASS:U:) { "(TZif)" }

my &tzparse;
my &transtime;
my &leapcorr;
my &typesequiv;

my @year_lengths = 365, 366;
my @mon_lengths = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
                  [ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

#| Determines whether a given year is a leap year
sub isleap(\year) {
    year % 4 == 0
        &&
    (year % 100 != 0 || year % 400 == 0)
}


# This handles the parsing of tzparse in localtime.c
grammar Posix-TZ {
    token TOP {
        :my $*match = '';
        \n?                              # may be parsed an initial new line
                                         #  EST+5EDT+6,M3.2.0/2,M11.1.0/2
        ['<' $<std-name>=<.qname> '>'    # <EST>                           # for non-alpha names
        |    $<std-name>=<.name>     ]   #  EST
             $<std-off> =<.offset>       #     +5
       [['<' $<dst-name>=<.qname> '>'    #      <EDT>                      # for non-alpha names
        |    $<dst-name>=<.name>     ]   #       EDT
             $<dst-off> =<.offset>?   ]? #          +6
        [
            ','                          #            ,
            $<std-trans> = <change>      #             M3.2.0/2
            ','                          #                     ,
            $<dst-trans> = <change>      #                      M11.1.0/2
        |   $<default-trans> = $      ]? #
        \n?                              # may have final return
    }

    token name   { <[a..zA..Z]>+          } # alpha only
    token qname  { <[a..zA..Z0..9+-]>+    } # more permissive in angle quotes
    token number { <[0..9]>+              } # ASCII digits only
    token offset { $<sign>=<[-+]>? <time> }

    token time {
        '-'?
	         $<hour>   = <.number>
	    [':' $<minute> = <.number>]?
        [':' $<second> = <.number>]?
        <?{ # check the valid range (yes, it's really ±167 for hours, 60 is for leapseconds)
            my $valid = True;
                              $valid = False unless +$/<hour>   ~~ -167..167 ;
            with $/<minute> { $valid = False unless +$/<minute> ~~    0..59 };
            with $/<second> { $valid = False unless +$/<second> ~~    0..60 };
            $valid
        }>
    }

    proto token change  { * }
    token change:month  { $<type>='M' $<month>=<.number> '.' $<week>=<.number> '.' $<day>=<.number> ['/' <time>]? }
    token change:noleap { $<type>='J' $<day>  =<.number>                                            ['/' <time>]? }
    token change:leap   { $<type>=''  $<day>  =<.number>                                            ['/' <time>]? }
}

sub seconds-from-time($time) {
    $time ~~ /
        $<sign>=(<[+-]>?)
        $<hour>=<[0..9]> ** 1..2
        [':'$<minute>=<[0..9]> ** 1..2
        [':'$<second>=<[0..9]> ** 1..2]?]?
        /;
    my $result = +$<hour> * 3600;
    $result += +$<minute> * 60 with $<minute>;
    $result += +$<second>      with $<second>;
    with $<sign> { $result *= -1 if $<sign> eq '-' }
    return $result;
}
#| Creates a new TZ State object from a tzfile blob.
#| (this is our own version of IANA's tzdb's tzloadbody (from localtime.c)
method new (blob8 $tz, :$name) {
    say "Loading the state file '$name'" if $*TZDEBUG;
    my $VERSION;

    # Check initial header to determine version
    #                 Header:     T    Z    i    f  [v.#][0 xx 15]
    $VERSION = 1 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    $VERSION = 2 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,0x32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    $VERSION = 3 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,0x33,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    $VERSION = 4 if $tz[^20] ~~ [0x54,0x5A,0x69,0x66,0x34,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

    die "TZ file for $name does not begin with correct header (must begin with 'TZif'),\nBegan with ", $tz[^20]
        unless $VERSION;

    say "  1. Header is OK. Version '$VERSION' detected" if $*TZDEBUG;

    my int64 $pos;

    # Determine the initial position for parsing.
    if $VERSION == 1 {
        # Version 1 files begin immediately after the header.
        $pos = 20
    } else {
        # Version 2+ files include a version 1 file for backwards
        # compatibility, but then have a second copy with larger
        # integer sizes, so we scan the file to find that header.
        # The header's value is TZif followed by the version number
        # in ASCII, or $VERSION + 48
        my $head-version = $VERSION + 48;
        for 1..^$tz.elems -> $i {
            next unless $tz[$i    ] == 0x54           # T
                     && $tz[$i + 1] == 0x5A           # Z
                     && $tz[$i + 2] == 0x69           # i
                     && $tz[$i + 3] == 0x66           # f
                     && $tz[$i + 4] == $head-version; # 2/3/4
            $pos = $i + 20;
            last;
        }
    }

    # First the file contains the counts for different items
    # so we know how long to read each type for.
    # (AFAICT, $ttisgmtcnt == $ttisstdcnt == $typecnt)
    my int32 $ttisgmtcnt = $tz.read-int32: $pos     , BigEndian;
    my int32 $ttisstdcnt = $tz.read-int32: $pos +  4, BigEndian;
    my int32 $leapcnt    = $tz.read-int32: $pos +  8, BigEndian;
    my int32 $timecnt    = $tz.read-int32: $pos + 12, BigEndian;
    my int32 $typecnt    = $tz.read-int32: $pos + 16, BigEndian;
    my int32 $charcnt    = $tz.read-int32: $pos + 20, BigEndian;
    $pos += 24;

    if $*TZDEBUG {
        say "  2. Found the following elements:";
        say "     - $ttisgmtcnt TTIS GMT";
        say "     - $ttisstdcnt TTIS GMT";
        say "     - $leapcnt leapseconds";
        say "     - $timecnt times";
        say "     - $typecnt types";
        say "     - $charcnt characters";
    }

    # First we read the transition times (moments when a timezone changes
    # from one ruleset to another, e.g. daylight savings time, or changing
    # nominal zones, e.g. eastern to central).  These represent seconds
    # from the epoch.
    # ATS = AtTime(Stuct) (a transition time)
    say "  3. Reading Transition times" if $*TZDEBUG;
    my int64 @ats[$TZ_MAX_TIMES];
    for ^$timecnt {
        @ats[$_] =
                $VERSION == 1
                ?? $tz.read-int32($pos, BigEndian)
                !! $tz.read-int64($pos, BigEndian);
        $pos += 4 * ($VERSION == 1 ?? 1 !! 2); # 4 or 8
        say "     - ", DateTime.new(@ats[$_], :0timezone), "({@ats[$_]})" if $*TZDEBUG;
    }

    # Next, each one of these moments has an associated rule that
    # dictates, e.g., whether it's daylight savings time or how much
    # it is offset from GMT.
    # TYPES = tranisition time meta data (
    say "  4. Reading associated rules" if $*TZDEBUG;
    my int8 @types;
    for ^$timecnt {
        @types.push($tz.read-int8: $pos);
        $pos += 1;
    }
    if $*TZDEBUG {
        for @ats Z @types
            -> ($time, $type) {
            say "     - " ~ DateTime.new($time) ~ " > $type";
        };
    }


    die "Invalid local time type referenced in transition time index."
        if @types.any > $typecnt;

    # The following class will be used temporarily, as we'll add to it
    # later the information regarding standard/wall, universal/wall
    # and an actual string for the abbreviation.
    class TransTimeInfoTemp {
        has int32 $.gmtoffset;
        has int8  $.is-dst;
        has uint8 $.abbr-index; # this is offset of the chars, sadly.
        method new(blob8 $b) {
            self.bless:
                    :gmtoffset($b.read-int32: 0, BigEndian),
                    :is-dst($b.read-int8:  4),
                    :abbr-index($b.read-uint8: 5)
        }
    }

    # Now we read in each of the ttinfos, or "Time Transition Information"
    # storing them temporarily until we can fully compose it.
    my @ttinfo-temp;
    for ^$typecnt {
        @ttinfo-temp.push: TransTimeInfoTemp.new($tz.subbuf: $pos, 6);
        $pos += 6;
    }


    # Now we reach the timezone abbreviations, stored as the very annoying
    # C-style strings (\0 is the terminator/delimiter).
    # The hash will relate the index (see above) to the actual abbreviation
    # to aide final composition.
    say "  6. Reading TZ abbreviations" if $*TZDEBUG;
    my @tzabbr; # ignore this for now
    my %tz-abbr-temp;
    my $anchor = 0;
    my $chars = $tz.subbuf($pos, $charcnt).decode;
    while $anchor < $charcnt {
        my $tmp = 0;
        $tmp++ while $tz[$pos + $anchor + $tmp] != 0; # scan to the next null terminator
        %tz-abbr-temp{$anchor} := $tz.subbuf($pos + $anchor, $tmp).decode; # ASCII-encoded, so default UTF-8 is identical
        say "     - " ~ $tz.subbuf($pos + $anchor, $tmp).decode if $*TZDEBUG;
        $anchor += $tmp + 1;
    }

    $pos += $anchor;

    # Collect leapseconds

    say "  7. Reading leapseconds" if $*TZDEBUG;
    my LeapSecInfo @lsis;
    my $leap-length = $VERSION == 1 ?? 8 !! 12;
    for ^$leapcnt {
        @lsis.push:
                LeapSecInfo.new($tz.subbuf: $pos, $leap-length);
        $pos += $leap-length;
        say "     - " ~ @lsis.tail.gist if $*TZDEBUG;
    }

    say "  8. Collecting std v wall indicators" if $*TZDEBUG;
    #Collect standard vs wall indicator indices, 1 = true";
    my Bool @ttisstd;
    for ^$ttisstdcnt {
        @ttisstd.push: so ( $tz[$pos] == 1);
        $pos++;
    }
    say "     - " ~ @ttisstd.map({ (so $_) ?? "1" !! "0"}).join ~ ('none' unless @ttisstd) if $*TZDEBUG;

    say "  9. Collecting gmt v local indicators" if $*TZDEBUG;
    # Collect Universal/GMT vs local indicator indices, 1 = true";
    my Bool @ttisgmt;
    for ^$ttisgmtcnt {
        @ttisgmt.push: so ($tz[$pos] == 1);
        $pos++;
    }
    say "     - " ~ @ttisgmt.map({ (so $_) ?? "1" !! "0"}).join ~ ('none' unless @ttisgmt) if $*TZDEBUG;

    # Now that the standard/wall, universal/local, and rulesets
    # have been collected, we can compose the actual transition time
    # informations (found in Classes.pm6)

    say "  10.Loading transition time meta info" if $*TZDEBUG;
    my TransTimeInfo @ttis;
    for ^$typecnt -> $i {
        @ttis.push:
            TransTimeInfo.new:
                utoffset   => @ttinfo-temp[$i].gmtoffset,
                is-dst     => @ttinfo-temp[$i].is-dst == 1,
                abbr-index => @ttinfo-temp[$i].abbr-index,
                is-std     => @ttisstd[$i] // False,
                is-ut      => @ttisgmt[$i] // False,
                abbr       => (%tz-abbr-temp{@ttinfo-temp[$i].abbr-index} // ''); # <-- TODO: this is a quick fix for America/Adak which isn't reading the strings properly
        with @ttis.tail {
            say "     - $_" if $*TZDEBUG;
        }
    }

    # Lastly, we determine the goback/goahead information
    # which lets it know if the time information wraps/repeats for
    # the gregorian calendar.
    my $goback  = False;
    my $goahead = False;

    # BEGIN NEW LOOPING EXTENSION CODE
    if $pos < $tz.elems {
        my %ts := Hash.new: ttis => Array.new, ats => Array.new, types => Array.new;
        my %basep = :$timecnt, :@ats, :@lsis, :$leapcnt;

        say "  11.Processing extended tz code (via posix string)" if $*TZDEBUG;
        tzparse(
            $tz.subbuf($pos + 1).decode,  # TZ string to parse
            %ts,                          # this will get populated and read later
            %basep
        );
        if $*TZDEBUG {
            say "     - parse complete ";
            say "     - New transition times:";
            say "       - ", DateTime.new($_,:0timezone), " ({$_})" for %ts<ats>[^100];
            say "     - New transition times infos:";
            say "       - ", $_ for %ts<ttis><>;
        }
        # At this point, @ats[$timecnt - 1] is the final explicit transition time
        # %ts<ats>[0..*] represent the continuation

        my int32 $gotabbr = 0; # probably unnecessary because of Raku string handling
        # my int32 charcnt # unneeded for Raku version
        loop (my $i = 0; $i < %ts<typecnt>; $i++) {
            # this should only be one or two type counts
            my $tsabbr = %ts<ttis>[$i].abbr;
            with $chars.index($tsabbr) {
                # The abbreviation was in the old one, so rewrite the index
                %ts<ttis>[$i].abbr-index = $_;
                $gotabbr++;
            } else {
                # The abbreviation wasn't, so set index accordingly and append
                %ts<ttis>[$i].abbr-index = $chars.chars;
                $chars ~= $tsabbr ~ "\0";
                $gotabbr++;
            }
            if $gotabbr == %ts<typecnt> {
                $charcnt = $chars.chars;

                # If the two types are the same, they're a noop (i.e. pointless) so we "delete" them by
                # reducing the index
                while (1 < $timecnt && @types[$timecnt - 1] == @types[$timecnt - 2]) {
                    $timecnt--;
                }

                # Now we loop through the generated transition times and append them to
                # the end of the explicit ones
                loop (my $i = 0; $i < %ts<timecnt> && $timecnt < $TZ_MAX_TIMES; $i++) {
                    my int64 $t = %ts<ats>[$i];
                    WORKAROUND_increment_overflow_time_A: {
                        my ($tp, $j) = $t, leapcorr(@lsis, $t);
                        if !($j < 0 ?? $TIME_T_MIN - $j ≤ $tp !! $tp ≤ $TIME_T_MAX - $j) {
                            next;
                        } else {
                            $t += $j;
                            next if 0 < $timecnt && $t <= @ats[$timecnt - 1];
                        }
                    }
                    @ats[$timecnt] = $t;
                    @types[$timecnt] = $typecnt + %ts<types>[$i];
                    $timecnt++
                }
                loop ($i = 0; $i < %ts<typecnt>; $i++) {
                    @ttis[$typecnt++] = %ts<ttis>[$i];
                }
            }
        }
    }

    say "  12.Checking for forward/backward looping" if $*TZDEBUG;
    # check for go ahead and go back here
    die if $typecnt == 0;
    if $timecnt > 1 {
        if @ats[0] <= $TIME_T_MAX - $SECSPERREPEAT {
            my int64 $repeatat = @ats[0] + $SECSPERREPEAT;
            my int32 $repeattype = @types[0];
            loop (my $i = 1; $i < $timecnt; ++$i) {
                if @ats[$i] == $repeatat
                && typesequiv(@ttis, $typecnt, @types[$i], $repeattype) {
                    $goback = True;
                    last;
                }
            }
        }
        if $TIME_T_MIN + $SECSPERREPEAT ≤ @ats[$timecnt - 1] {
            my int64 $repeatat = @ats[$timecnt - 1] - $SECSPERREPEAT;
            my int32 $repeattype = @types[$timecnt - 1];
            loop (my $i = $timecnt - 2; $i ≥ 0; --$i) {
                if @ats[$i] == $repeatat
                && typesequiv(@ttis, $typecnt, @types[$i], $repeattype) {
                    $goahead = True;
                    last;
                }
            }
        }
    }

    say "  13. Successful load, now blessing" if $*TZDEBUG;
    self.bless:
        :$leapcnt,
        :$timecnt,
        :$typecnt,
        :$charcnt,
        :$goback,
        :$goahead,
        :@ats,
        :@types,
        :@ttis,
        :$chars,
        :@lsis,
        :$name
}


method equiv-to {
    die "NYI, see static bool typesequiv in localtime.c"
}

&tzparse = sub (str $name, $sp is raw, $basep is raw) {
    # The $basep in C appears to be used mainly to set up the leapseconds
    # but these are included in all of our files that would be loaded, so
    # can be ignored AFAICT.
    my str $stdname;      # const char * stdname;
    my str $dstname;      # size_t       stdlen;
    my int16 $stdlen;     # size_t       dstlen;
    my int16 $dstlen;     # size_t       charcnt;
    my int16 $charcnt;    # int_fast32_t stdoffset;
    my int32 $stdoffset;  # int_fast32_t dstoffset;
    my int32 $dstoffset;  # register char * cp;
    my int8 $load_ok;     # register bool load_ok;

    $sp<types> = Array.new;
	my int64 ($atlo, $leaplo) = - 2 ** 63, - 2 ** 63; # 	time_t atlo = TIME_T_MIN, leaplo = TIME_T_MIN;

	$stdname = $name; # stdname = name;
	my \match = Posix-TZ.parse($name.chomp);
    say "     - {$name.chomp}"  if $*TZDEBUG;
    say "     - {match ?? 'parsed' !! 'not parsed'}" if $*TZDEBUG;

	$stdname = ~match<std-name>;
    # NEGATIVE?
	$stdoffset = -seconds-from-time ~match<std-off>; # negative because it's hours behind GMT
    say "     - Standard offset is {match<std-off>} ({$stdoffset / 3600}h)" if $*TZDEBUG;
    if ($basep) {
        if (0 < $basep<timecnt>) {
            $atlo = $basep<ats>[$basep<timecnt> - 1]
        }
        $load_ok = 0; # false
        $sp<leapcnt> = $basep<leapcnt>;
        $sp<lsis> = $basep<lsis>;
    } else {
        die "No leapseconds available"; # this code normally would load the default zone which holds leapseconds data
        $sp<leapcnt> = 0;
    }
    if (0 < $sp<leapcnt>) {
        $leaplo = $sp<lsis>[$sp<leapcnt> - 1].transition;
    }
    # $leaplo is the moment of the last leapsecond
    # $atlo should be the time of the last fixed timezone (or dst) transition

	#$dstname = ~(match<dst-name> // '');
	if $dstname = ~(match<dst-name> // '') { # otherwise, no daylight savings time
	#`<<< get dst name
	if (*name != '\0') {
		if (*name == '<') {
			dstname = ++name;
			name = getqzname(name, '>');
			if (*name != '>')
			  return false;
			dstlen = name - dstname;
			name++;
		} else {
			dstname = name;
			name = getzname(name);
			dstlen = name - dstname; /* length of DST abbr. */
		}
		>>>

        with match<dst-offset> {
            $dstoffset = -seconds-from-time ~match<dst-offset> # negative because it's hours behind GMT
        } else {
            $dstoffset = $stdoffset + 3600; # one hour by default
        }
        say "     - Daylight offset is {match<dst-offset> // '…'} ({$dstoffset / 3600}h)" if $*TZDEBUG;

        with match<default-trans> {
            #`<<< Default rule string is ',M3.2.0,M11.1.0'
		    if (*name == '\0' && !load_ok)
			name = TZDEFRULESTRING;
		    >>>
        }

        use Timezones::ZoneInfo::ConvRule;

        my ConvRule $start;
        my ConvRule $end;
        my int32 $year;
        my int32 $timecnt;
        my int64 $janfirst;
        my int32 $janoffset = 0;
        my int32 ($yearbeg, $yearlim);

        $start = ConvRule.new:
            type  => ConvRule::RuleType(%('J'=>0, 'M' => 2, '' => 1){match<std-trans><type>}),
            day   => +match<std-trans><day>,
            week  => +(match<std-trans><week> // 0),
            month => +(match<std-trans><month> // 0),
            time  => seconds-from-time (match<std-trans><time> // '2:00');
        $end = ConvRule.new:
            type  => ConvRule::RuleType(%('J'=>0, 'M' => 2, '' => 1){match<dst-trans><type>}),
            day   => +match<dst-trans><day>,
            week  => +(match<dst-trans><week> // 0),
            month => +(match<dst-trans><month> // 0),
            time  => seconds-from-time (match<dst-trans><time> // '2:00');
        $sp<typecnt> = 2;
        $sp<ttis>[0] = TransTimeInfo.new: utoffset => $stdoffset, is-dst => False, abbr-index => 0, abbr => $stdname;
        $sp<ttis>[1] = TransTimeInfo.new: utoffset => $dstoffset, is-dst => True,  abbr-index => 1, abbr => $dstname;
        $sp<defaulttype> = 0;
        $timecnt = 0;
        $janfirst = 0;
        $yearbeg = 1970; # EPOCH_YEAR;

            #`<<<
			++name;
			if ((name = getrule(name, &start)) == NULL)
			  return false;
			if (*name++ != ',')
			  return false;
			if ((name = getrule(name, &end)) == NULL)
			  return false;
			if (*name != '\0')
			  return false;
			sp->typecnt = 2;	/* standard time and DST */
			/*
			** Two transitions per year, from EPOCH_YEAR forward.
			*/
			init_ttinfo(&sp->ttis[0], -stdoffset, false, 0);
			init_ttinfo(&sp->ttis[1], -dstoffset, true, stdlen + 1);
			sp->defaulttype = 0;
			timecnt = 0;
			janfirst = 0;
			yearbeg = EPOCH_YEAR;
			>>>


        repeat {
            my int32 $yearsecs = @year_lengths[isleap($yearbeg - 1)] * $SECSPERDAY;
            $yearbeg--;

            WORKAROUND_increment_overflow_time_A: {
                my ($tp,$j) = ($janfirst, -$yearsecs);
                if (! ($j < 0
                    ?? True #`[time_t signed] ?? $TIME_T_MIN - $j ≤ $tp !! -1 - $j < $tp
                    !! $tp ≤ $TIME_T_MAX - $j)) {
                    $janoffset -= $yearsecs; # would occur with the true return
                    last;                    # would occur with the true return
                }
                $janfirst += $j; # mutable
            }
            #if increment_overflow_time($janfirst, -$yearsecs) {
            #    $janoffset -= $yearsecs;
            #    last;
            #}
        } while $atlo < $janfirst && 1970 - 400 div 2 < $yearbeg;

        # Atlo remains unchanged, and is the time_t of the most recent fixed dst or timezone transition
        # yearbeg is a year after 1770
        # janfirst is the time_t of Jan 1 @ 0:00 for yearbeg

        loop {
            my int32 $yearsecs = @year_lengths[isleap($yearbeg)] * $SECSPERDAY;
            my int32 $yearbeg1 = $yearbeg;
            my int64 $janfirst1 = $janfirst;
            WORKAROUND_double_increment_overflows: {
                last if (! ($yearsecs < 0 ?? ($TIME_T_MIN - $yearsecs ≤ $janfirst1) !! ($janfirst1 ≤ $TIME_T_MAX - $yearsecs)));
                $janfirst1 += $yearsecs;
                last if ($yearbeg1 ≥ 0) ?? (1 > $INT_FAST32_MAX - $yearbeg1) !! (1 < $INT_FAST32_MIN - $yearbeg1);
                $yearbeg1 += 1;
                last if $atlo ≤ $janfirst1
            }
            #if increment_overflow_time($janfirst1, $yearsecs)
            #|| increment_overflow($yearbeg1, 1)
            #|| $atlo ≤ $janfirst1 {
            #    last;
            #}
            $yearbeg = $yearbeg1;
            $janfirst = $janfirst1;
        }

        # atlo is still the most recent transition
        # janfirst *should be* january first of the atlo's year
        # year beg should be atlo's year

		#`<<<
			while (true) {
			  int_fast32_t yearsecs
			    = year_lengths[isleap(yearbeg)] * SECSPERDAY;
			  int yearbeg1 = yearbeg;
			  time_t janfirst1 = janfirst;
			  if (increment_overflow_time(&janfirst1, yearsecs)
			      || increment_overflow(&yearbeg1, 1)
			      || atlo <= janfirst1)
			    break;
			  yearbeg = yearbeg1;
			  janfirst = janfirst1;
			}
		>>>
        $yearlim = $yearbeg;
        WORKAROUND_increment_overflow_B: {
            my ($i, $j) = $yearlim, 401 #`[YEARSPERREPEAT + 1];
            if (($i ≥ 0) ?? ($j > $INT_FAST32_MAX - $i) !! ($j < $INT_FAST32_MIN - $i)) {
                $yearlim = $INT_FAST32_MAX; # would happen with true
            }else{
                $yearlim += $j; # mutable bit
            }
        }

        # yearbeg should be the year of atlo
        # yearlim should be atlo's year + 401

        loop ($year = $yearbeg; $year < $yearlim; $year++) {
            # for (year = yearbeg; year < yearlim; year++) {
            my int32 $starttime = transtime($year, $start, -$stdoffset);
            my int32 $endtime   = transtime($year, $end, -$dstoffset);
            my int32 $yearsecs  = @year_lengths[isleap($year)] * $SECSPERDAY;
            my int8  $reversed  = $endtime < $starttime;

            if $reversed {
                my int32 $swap = $starttime;
                $starttime     = $endtime;
                $endtime       = $swap;
            }
            #`<<<
            	if (reversed) {
					int_fast32_t swap = starttime;
					starttime = endtime;
					endtime = swap;
				}
            >>>
            if  $reversed
            || ($starttime < $endtime
            &&  $endtime - $starttime < $yearsecs) {
                if ($TZ_MAX_TIMES - 2 < $timecnt) {
                    last
                }
                $sp<ats>[$timecnt] = $janfirst;

                # TODO double and triple check this work around logic here
                WORKAROUND_increment_overflow_C: {
                    my ($tp, $j) = $sp<ats>[$timecnt], $janoffset + $starttime;
                    if ($j < 0 ?? ($TIME_T_MIN - $j ≤ $tp) !! ($tp ≤ $TIME_T_MAX - $j)) {
                        $sp<ats>[$timecnt] = $tp + $j;
                        if $atlo ≤ $sp<ats>[$timecnt] {
                            $sp<types>[$timecnt++] = +!$reversed;
                        }
                    }
                }
                $sp<ats>[$timecnt] = $janfirst;
                WORKAROUND_increment_overflow_D: {
                    my ($tp, $j) = $sp<ats>[$timecnt], $janoffset + $endtime;
                    if ($j < 0 ?? $TIME_T_MIN - $j ≤ $tp !! $tp ≤ $TIME_T_MAX - $j) {
                        $sp<ats>[$timecnt] = $tp + $j;
                        if $atlo ≤ $sp<ats>[$timecnt] {
                            $sp<types>[$timecnt++] = +$reversed;
                        }
                    }
                }
            }
            # not sure how this would ever not be true...
            # I wonder if this is a bug that should be $endtime + $janoffset
            if ($endtime < $leaplo) {
                $yearlim = $year;
                WORKAROUND_increment_overflow_E: {
                    my ($i, $j) = $yearlim, 401 #`[YEARSPERREPEAT + 1];
                    if (($i ≥ 0) ?? ($j > $INT_FAST32_MAX - $i) !! ($j < $INT_FAST32_MIN - $i)) {
                        $yearlim = $INT_FAST32_MAX; # would happen with true
                    }else{
                        $yearlim += $j; # mutable bit
                    }
                }
                #if (increment_overflow($yearlim, YEARSPERREPEAT + 1)) {
                #    $yearlim = INT_MAX;
                #}
            }
            WORKAROUND_increment_overflow_time_F: {
                my int32 $j = $janoffset + $yearsecs;
                last if ! ($j < 0 ?? ($TIME_T_MIN - $j ≤ $janfirst) !! ($janfirst ≤ $TIME_T_MAX - $j));
                $janfirst += $j;
            }
            $janoffset = 0;
        }

        #`<<<
				if (endtime < leaplo) {
				  yearlim = year;
				  if (increment_overflow(&yearlim,
							 YEARSPERREPEAT + 1))
				    yearlim = INT_MAX;
				}
				if (increment_overflow_time
				    (&janfirst, janoffset + yearsecs))
					break;
				janoffset = 0;
			}
		>>>
		$sp<timecnt> = $timecnt;
		if (!$timecnt) {
		    $sp<ttis>[0] = $sp<ttis>[1];
		    $sp<typecnt> = 1; # perpetual DST
		} elsif (400 #`[$YEARSPERREPEAT] < $year - $yearbeg) {
		    $sp<goback> = $sp<goahead> = 1; # aka true
        } else {
            my int32 $theirstdoffset;
            my int32 $theirdstoffset;
            my int32 $theiroffset;
            my int8 $isdst;
            my int32 $i;
            my int32 $j;
            # if ($name ne '') {return 0 } TODO do we need this line?
            # Initial values of theirstdoffset and theirdstoffset
            loop ($i = 0; $i < $sp<timecnt>; ++$i) {
                $j = $sp<types>[$i];
                if (!$sp<ttis>[$j].is-dst) {
                    $theirstdoffset = - $sp<ttis>[$j].utoffset;
                    last;
                }
            }
            $theirdstoffset = 0;
            loop ($i = 0; $i < $sp<timecnt>; ++$i) {
                $j = $sp<types>[$i];
                if ($sp<ttis>[$j].is-dst) {
                    $theirdstoffset = - $sp<ttis>[$j].utoffset;
                    last;
                }
            }

            $isdst = 0; # false

            loop ($i = 0; $i < $sp<timcnt>; $i++) {
                $j = $sp<types>[$i];
                if $sp<types>[$i]<tt_ttisut> {
                    # no adjustment
                } else {
                    if ($isdst && !$sp<ttis>[$j].is-std) {
                        $sp<ats>[$i] += $dstoffset - $theirdstoffset;
                    } else {
                        $sp<ats>[$i] += $stdoffset - $theiroffset;
                    }
                }
                $theiroffset = - $sp<ttis>[$j].utoffset;
                if $sp<ttis>[$j].is-dst {
                    $theirdstoffset = $theiroffset;
                } else { $theirstdoffset = $theiroffset }
            }
            $sp<ttis>[0] = TransTimeInfo.new: :ufoffset(-$stdoffset), :is-dst  #`[0, false], :abbr-index(0);
            $sp<ttis>[1] = TransTimeInfo.new: :ufoffset(-$dstoffset), :!is-dst #`[1, true],  :abbr-index($stdlen + 1); # final value may need to be just "1"
            $sp<typecnt> = 2;
            $sp<defaulttype> = 0;
        }
    } else {
        $dstlen = 0;
        $sp<typecnt> = 1; # only standard time
        $sp<timecnt> = 0;
        $sp<ttis>[0] = TransTimeInfo.new: :utoffset(-$stdoffset), :!is-dst #`[0, false], :abbr-index(0);
        $sp<defaulttype> = 0;
    }


	# This code adds the two abbreviations
	#     to the State.  This can be done in Raku
	#     with a simple concat operation
	#sp->charcnt = charcnt;
	#cp = sp->chars;
	#memcpy(cp, stdname, stdlen);
	#cp += stdlen;
	#*cp++ = '\0';
	#if (dstlen != 0) {
	#	memcpy(cp, dstname, dstlen);
	#	*(cp + dstlen) = '\0';
	#}
	$sp<chars> = $sp<ttis>.map(*.abbr).join("\0");

	return True; # this activates the newer loop code
	# return true
}

use Timezones::ZoneInfo::ConvRule;
&transtime = sub (int32 $year, ConvRule $rulep, int32 $offset) {
    my int8  $leapyear;  #bool
    my int32 $value;
    my int32 $i;
    my int32 ($d, $m1, $yy0, $yy1, $yy2, $dow);

    $leapyear = isleap($year);
    given ($rulep.type) {
        when ConvRule::RuleType::julian-day {
            $value = ($rulep.day - 1) * $SECSPERDAY;
            if ($leapyear && $rulep.day ≥ 60) {
                $value += $SECSPERDAY;
            }
        }
        when ConvRule::RuleType::day-of-year {
            $value = $rulep.day * $SECSPERDAY;
        }
        when ConvRule::RuleType::month-nth-day-of-week {
            $m1  = ($rulep.month + 9) mod 12 + 1;
            $yy0 = ($rulep.month ≤ 2) ?? ($year - 1) !! $year;
            $yy1 = $yy0 div 100;
            $yy2 = $yy0 mod 100;
            $dow = ((26 * $m1 - 2) div 10 +
                     1 + $yy2 +
                     $yy2 div 4 +
                     $yy1 div 4 -
                     2 * $yy1)
                    mod 7;
            if $dow < 0 {
                $dow += 7; # days per week
            }

            $d = $rulep.day - $dow;
            if ($d < 0) {
                $d += 7; # days per week
            }
            loop ($i = 1; $i < $rulep.week; ++$i) {
                if ($d + 7 #`[daysperweek] ≥ @mon_lengths[$leapyear][$rulep.month - 1]) {
                    last;
                }
                $d += 7;
            }
            $value = $d * $SECSPERDAY;
            loop ($i = 0; $i < $rulep.month - 1; ++$i) {
                $value += @mon_lengths[$leapyear][$i] * $SECSPERDAY;
            }
        }
        default { die 'Unreachable code reached' }
    }
    return $value + $rulep.time + $offset
}

# modified slightly from the original to account for not having a full State constructed yet
&leapcorr = sub (@lsis, int64 $t) {
	my LeapSecInfo $lp;
	my int16 $i;

	$i = +@lsis;
	while (--$i ≥ 0) {
		$lp = @lsis[$i];
		if ($t ≥ $lp.transition) {
			return $lp.correction;
		}
	}
	return 0;
}

# modified slightly from the original to account for not having a full State constructed yet
&typesequiv = sub (TransTimeInfo @ttis, $timecnt, $a, $b ) {
    return False
        if $a < 0
        || $b < 0
        || $a > $timecnt
        || $b > $timecnt;

    my TransTimeInfo $ap = @ttis[$a];
    my TransTimeInfo $bp = @ttis[$a];
    return $ap.utoffset == $bp.utoffset
        && $ap.is-dst   == $bp.is-dst
        && $ap.is-std   == $bp.is-std
        && $ap.is-ut    == $bp.is-ut
        && $ap.abbr     eq $bp.abbr
}