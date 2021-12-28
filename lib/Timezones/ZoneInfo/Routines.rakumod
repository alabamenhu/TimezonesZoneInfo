unit module Routines;
# TODO check the overflow stuff carefully, and insure the correct native types are being used

# this just makes our life easier in reading c code
constant time = int64; # NOTE: different from Time (which is a struct)
constant false = 0;
constant true = 1;


# OTHER IMPORTANT CONSTANTS
my int64 $SECSPERMIN   =  60;
my int64 $MINSPERHOUR  =  60;
my int64 $HOURSPERDAY  =  24;
my int64 $DAYSPERWEEK  =   7;
my int64 $DAYSPERNYEAR = 365;
my int64 $DAYSPERLYEAR = 366;
my int64 $SECSPERHOUR  = $SECSPERMIN  * $MINSPERHOUR;
my int64 $SECSPERDAY   = $SECSPERHOUR * $HOURSPERDAY;
my int64 $MONSPERYEAR  =  12;

my int64 $YEARSPERREPEAT = 400; # years before a Gregorian repeat
my int64 $DAYSPERREPEAT  = 400 * 365 + 100 - 4 + 1;
my int64 $SECSPERREPEAT  = $DAYSPERREPEAT  *  $SECSPERDAY;
my int64 $AVGSECSPERYEAR = $SECSPERREPEAT div $YEARSPERREPEAT;

my int64 $TM_SUNDAY    = 0;
my int64 $TM_MONDAY    = 1;
my int64 $TM_TUESDAY   = 2;
my int64 $TM_WEDNESDAY = 3;
my int64 $TM_THURSDAY  = 4;
my int64 $TM_FRIDAY    = 5;
my int64 $TM_SATURDAY  = 6;

my int32 $EPOCH_YEAR   = 1970;
my int64 $TM_YEAR_BASE = 1900;
my int64 $TM_WDAY_BASE = $TM_MONDAY;

my int64 $NULL = 0;

# This is set to 64 bit (long) ints.  This may need to be smaller, though.
# Edit: appears to actually best be set to either 16 or 32.  Given separate 32 bit
# overflow functions, we will go with 16 unless there is a problem ultimately.
# This choice seems correct, because of a check akin to:
# 	INT_MIN ≤ $y ≤ INT_MAX
# where $y is explicitly defined as int32
my int16 $INT_MIN        = -2**15;
my int16 $INT_MAX        =  2**15 - 1;
my int32 $INT_FAST32_MIN = -2**31;
my int32 $INT_FAST32_MAX =  2**31 - 1;
my int64 $TIME_T_MIN     = -2**63;
my int64 $TIME_T_MAX     =  2**63 - 1;
my int64 $LONG_MIN       = -2**63;
my int64 $LONG_MAX       =  2**63 - 1;

# from localtime.c, should be int32
my @year_lengths      = 365, 366;
my @mon_lengths    = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
							     [ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
my int64 $WRONG = -1;

# From tzfile.h
my int32 $TZ_MAX_TYPES = 256;


use Timezones::ZoneInfo::State;
use Timezones::ZoneInfo::TransTimeInfo;
use Timezones::ZoneInfo::Time;
use Timezones::ZoneInfo::LeapSecInfo;

#| These variables names match localtime's localsub's
sub localsub( State $sp, time $t is copy, #`[$setname, ←unused?] Time $tmp = Time.new, :$leapadjusted = False --> Time) is export {

    my TransTimeInfo $ttisp;
    my int64         $i;
    my Time          $result;

    $t = posix2time($sp, $t) unless $leapadjusted;

    if $sp.go-back  && $t < $sp.ats.head
    || $sp.go-ahead && $t > $sp.ats.tail {
        my time $newt;
        my time	$seconds;
        my time	$years;

        if   $t < $sp.ats.head { $seconds = $sp.ats.head - $t }
        else	               { $seconds = $t - $sp.ats.tail }
        --$seconds;

        $years   = $seconds div $SECSPERREPEAT * $YEARSPERREPEAT;
        $seconds = $years * $AVGSECSPERYEAR;
        $years  += $YEARSPERREPEAT;
        if   $t < $sp.ats.head { $newt = $t + $seconds + $SECSPERREPEAT }
        else                   { $newt = $t - $seconds - $SECSPERREPEAT }

        if $newt < $sp.ats.head
        || $newt > $sp.ats.tail {
            die "Impossible situation";
            return $NULL;	# "cannot happen" per C code, C code returns null
        }
        $result = localsub($sp, $newt, #`[$setname, ←unused?] $tmp);
        if $result {
            my int64 $newy;

            $newy = $result.year;
            if   $t < $sp.ats.head { $newy -= $years }
            else                   { $newy += $years }
            if !($INT_MIN ≤ $newy ≤ $INT_MAX) {
                die "Impossible situation at line {$?LINE}";
                return $NULL;
            }
            $result.year = $newy;
        }
        return $result;
    }

    if $sp.time-count == 0
    || $t < $sp.ats.head {
        # TODO HANDLE A 0 TIME COUNT
        # die "Highly unlikely situation at line {$?LINE}, sp has {$sp.type-count} types";
		$i = 0; # $sp.default-type; # this shouldn't happen often
	} else {
		my int64 $lo = 1;
		my int64 $hi = $sp.time-count;

		while $lo < $hi {
			my int64 $mid = ($lo + $hi) div 2;
			if   $t < $sp.ats[$mid] { $hi = $mid    }
			else	                { $lo = $mid + 1};
		}
		$i = $sp.types[$lo - 1];
	}
	$ttisp = $sp.ttis[$i];

	$result = timesub($t, $ttisp.utoffset, $sp, $tmp);
	if $result {
	  $result.dst = $ttisp.is-dst;
	  $result.tz-abbr = $ttisp.abbr; # shortcut for &sp->chars[ttisp->tt_desigidx] + parsing
    }
	return $result;
}

#| Determines whether a given year is a leap year
sub isleap(\year) {
    year % 4 == 0
        &&
    (year % 100 != 0 || year % 400 == 0)
}

sub leaps_thru_end_of(time \year) {
    sub leaps_thru_end_of_nonneg(time \year) { year div 4 - year div 100 + year div 400 }

    year < 0
	    ?? -1 - leaps_thru_end_of_nonneg(-1 - year)
	    !! leaps_thru_end_of_nonneg(year);
}


# I *think* $t is readwrite here
sub timesub(time $timep is rw, int32 $offset, State $sp, Time:D $tmp --> Time) {
	my LeapSecInfo	$lp;
	my time	        $tdays;
	my int32        $ip;
	my int32        $corr;
	my int32        $i;
	my int32        $idays;
	my int32        $rem;
	my int32        $dayoff;
	my int32        $dayrem;
	my time         $y;

	# If less than SECSPERMIN, the number of seconds since the
    # most recent positive leap second; otherwise, do not add 1
    # to localtime tm_sec because of leap seconds.

    my time $secs_since_posleap = $SECSPERMIN;

	$corr = 0;
	$i = $sp ?? $sp.leap-count !! 0;

	while (--$i ≥ 0) {
		$lp = $sp.lsis[$i];
		if $timep ≥ $lp.transition {
			$corr = $lp.correction;
			if ($i == 0 ?? 0 !! $sp.lsis[$i-1].correction) < $corr { # c code has lp[-1], which I *think* is short for $sp.lsis[$i-1]
			    $secs_since_posleap = $timep - $lp.transition;
            }
			last
		}
	}


    $tdays    = $timep  div $SECSPERDAY;
	$rem      = $timep  mod $SECSPERDAY;
	$rem     += $offset mod $SECSPERDAY - $corr mod $SECSPERDAY +  3    *  $SECSPERDAY;
	$dayoff   = $offset div $SECSPERDAY - $corr div $SECSPERDAY + $rem div $SECSPERDAY - 3;
	$rem   mod= $SECSPERDAY;

	$dayrem  = $tdays mod $DAYSPERREPEAT;
	$dayrem += $dayoff mod $DAYSPERREPEAT;
	$y = $EPOCH_YEAR - $YEARSPERREPEAT
	     + ((1 + $dayoff div $DAYSPERREPEAT + $dayrem div $DAYSPERREPEAT
		 - (($dayrem mod $DAYSPERREPEAT) < 0)
		 + $tdays div $DAYSPERREPEAT)
		 * $YEARSPERREPEAT);

	$idays  = $tdays mod $DAYSPERREPEAT;
	$idays += $dayoff mod $DAYSPERREPEAT + 2 * $DAYSPERREPEAT;
	$idays mod= $DAYSPERREPEAT;

	# Increase Y and decrease IDAYS until IDAYS is in range for Y. 1750
	while @year_lengths[isleap($y)] ≤ $idays {
		my int32 $tdelta = $idays div $DAYSPERLYEAR;
		my int32 $ydelta = $tdelta + !$tdelta; # !$tdelta  === $tdelta ?? 0 ! 1
		my time  $newy   = $y + $ydelta;
		my int32 $leapdays;
		$leapdays = leaps_thru_end_of($newy - 1) -
			leaps_thru_end_of($y - 1);
		$idays -= $ydelta * $DAYSPERNYEAR;
		$idays -= $leapdays;
		$y = $newy;
	}

    # At this point, the C code does a check for signedness of the time
    # unit, which we define here as int64.  The raw True/False here (always
    # skipping the first branch) represents that for future maintainers.
    # Effectively, though, we want to know if we can actually represent the year
    # and return a type object (a substitute for a null check) if we can't
	if (!True && $y < $TM_YEAR_BASE) {
	    #int signed_y = y;
	    #tmp->tm_year = signed_y - TM_YEAR_BASE;
	} elsif (!True || $INT_FAST32_MIN + $TM_YEAR_BASE ≤ $y) # use INT_FAST32_MIN because year is 32bit
		   && $y - $TM_YEAR_BASE ≤ $INT_FAST32_MAX {
		$tmp.year = $y - $TM_YEAR_BASE;

	} else {
	    return Time; # $NULL, here we use a type object which is falsy
	}
	$tmp.yearday = $idays;

	#The "extra" mods below avoid overflow problems.

	$tmp.weekday = $TM_WDAY_BASE
			+ (($tmp.year mod $DAYSPERWEEK)
			   * ($DAYSPERNYEAR mod $DAYSPERWEEK))
			+ leaps_thru_end_of($y - 1)
			- leaps_thru_end_of($TM_YEAR_BASE - 1)
			+ $idays;
	$tmp.weekday mod= $DAYSPERWEEK;
	if $tmp.weekday < 0 {
	    $tmp.weekday += $DAYSPERWEEK
	};

	$tmp.hour = $rem div $SECSPERHOUR;
	$rem mod= $SECSPERHOUR;
	$tmp.minute = $rem div $SECSPERMIN;
	$tmp.second = $rem mod $SECSPERMIN;

	# Use "... ??:??:60" at the end of the localtime minute containing
	#  the second just before the positive leap second.
	$tmp.second += $secs_since_posleap ≤ $tmp.second;

    # because we can't play pointer tricks
    #    ip = mon_lengths[isleap(y)]; ip[tmp->tm_mon]
    # becomes
    #    mon_lengths[isleap(y)][$tmp.month]
    # which looks hideous but ah well
	# $ip = @mon_lengths[isleap($y)]; # originally used for the pointer tricks
	loop (
	    $tmp.month = 0;
	    $idays ≥ @mon_lengths[isleap($y);$tmp.month];
	    $tmp.month++
	) {
		$idays -= @mon_lengths[isleap($y);$tmp.month]
    }
	$tmp.day = $idays + 1;
	$tmp.dst = false;
	$tmp.gmt-offset = $offset;
	return $tmp;
}


# This handles the parsing of tzparse in localtime.c
grammar Posix-TZ {
    token TOP {
       :my $match = '';
       ['<' {$match = '>'}]?     # <EST+5EDT+6,M3.2.0/2,M11.1.0/2>
       $<std-name> = <.name>      #  EST
       $<std-off>  = <.offset>    #     +5
       $<dst-name> = <.name>      #       EDT
       $<dst-off>  = <.offset>?   #          +6
       ','                        #            ,
       $<std-trans> = <change>    #             M3.2.0/2
       ','                        #                     ,
       $<dst-trans> = <change>    #                      M11.1.0/2
       $match                     # terminal if bound only
    }

    token name   { <[a..zA..Z]>+          }
    token number { <[0..9]>+              }
    token offset { $<sign>=<[-+]>? <time> }

    token time {
	         $<hour>   = <.number>
	    [':' $<minute> = <.number>]?
        [':' $<second> = <.number>]?
        <?{ # check the valid range (yes, it's really ±167 for hours, 60 is for leapseconds)
            my $valid = True;
                              $valid = False unless +$/<hour>   ~~ -167 .. 167 ;
            with $/<minute> { $valid = False unless +$/<minute> ~~    0 .. 59 };
            with $/<second> { $valid = False unless +$/<second> ~~    0 .. 60 };
            $valid
        }>
    }

    proto token change  { * }
    token change:month  { $<type>='M' $<month>=<.number> '.' <.number> '.' <.number> '/' <time> }
    token change:noleap { $<type>='J' $<day>  =<.number>                             '/' <time> }
    token change:leap   { $<type>=''  $<day>  =<.number>                             '/' <time> }
}

sub mktime(Time $tmp, State $sp) is export {
	my int32 $zero = 0;
	time1 $tmp, &localsub, $sp #`[, $zero ←unused?]; #<--false;
}
# This is just "time1" in localtime.c
sub time1 (
    Time  $tmp,
    Time  &funcp, # (State, time, [int32], Time)
    State $sp,
    #`[ int32 $offset ←unused? ]
    --> time
) {
    my time   $t;
    my int32 ($samei, $otheri);
    my int32 ($sameind, $otherind);
    my int32  $i;
    my int32  $nseen;
	my int8   @seen[$TZ_MAX_TYPES];
	my uint8  @types[$TZ_MAX_TYPES];
	my Bool   $okay;


	if !$tmp { # originally if $tmp = NULL
	    warn "value outside of range at {$?LINE}";
		return $WRONG;
	}
	if $tmp.dst > 1 { $tmp.dst = 1 }

	$t = time2($tmp, &funcp, $sp, #`[$offset, ←unused?] $okay);

	if $okay        { return $t }
	if $tmp.dst < 0 { return $t } # under POSIX Conf Test Suite, $tmp.dst = 0

	# We're supposed to assume that somebody took a time of one type
	# and did some math on it that yielded a "struct tm" that's bad.
	# We try to divine the type they started from and adjust to the
	# type they need.
	if !$sp {# originally if $sp == NULL
	    warn "bad state value at {$?LINE}";
		return $WRONG;
    }
	loop ($i = 0; $i < $sp.type-count; ++$i) {
		@seen[$i] = false;
    }
	$nseen = 0;
	loop ($i = $sp.time-count - 1; $i ≥ 0; --$i) {
		if !@seen[$sp.types[$i]] {
			@seen[$sp.types[$i]] = true;
			@types[$nseen++] = $sp.types[$i];
		}
    }

    loop ($sameind = 0; $sameind < $nseen; ++$sameind) {
        $samei = @types[$sameind];
		if $sp.ttis[$samei].is-dst != $tmp.dst {
			next;
        }
		loop ($otherind = 0; $otherind < $nseen; ++$otherind) {
			$otheri = @types[$otherind];
			if ($sp.ttis[$otheri].is-dst == $tmp.dst) {
				next
			}
			$tmp.second += ($sp.ttis[$otheri].utoffset
					- $sp.ttis[$samei].utoffset);
			$tmp.dst = !$tmp.dst;
			$t = time2($tmp, &funcp, $sp, #`[$offset, ←unused?] $okay);
			if ($okay) {
			    return $t
			}
			$tmp.second -= ($sp.ttis[$otheri].utoffset
					- $sp.ttis[$samei].utoffset);
			$tmp.dst = !$tmp.dst;
		}
	}
	return $WRONG;
}

sub time2 (
    Time $tmp,
         &funcp, # (State, time, int32, Time)
    State $sp,
    #`[ int32 $offset is rw, ←unused?]
    Bool $okay is rw # bool
    --> time
)  {
    my time $t = 0;
    #  First try without normalization of seconds
    #  (in case tm_sec contains a value associated with a leap second).
    #  If that fails, try with normalization of seconds.


	my int32 $FALSE = 0;
	my int32 $TRUE  = 1;
    $t = time2sub($tmp, &funcp, $sp, #`[$offset, ←unused?] $okay, $FALSE);
    return $t # if $okay;
    #return $okay
    #    ?? $t
    #    !! time2sub($tmp, &funcp, $sp, #`[$offset, ←unused?] $okay, $TRUE)
}

sub time2sub (
    Time   $tmp,
           &funcp, # (State, time, int32, Time) # time and Time should be RW!!!
    State  $sp,
    #`[ int32 $offset is rw, ←unused?]
    Bool  $okayp is rw, #bool
    int32  $do_norm_secs,
    --> time
) {
	my int32  $dir;
	my int32 ($i, $j);
	my int32  $saved_seconds;
	my int32  $li;
	my time   $lo;
	my time   $hi;
	my int32  $y;
	my time   $newt;
	my time   $t;
	my Time  ($yourtm, $mytm);

	$okayp = False;
	$yourtm = $tmp;
	$mytm = Time.new; # special for Raku, otherwise $mytime ends up a type object

	if $do_norm_secs {
		# if normalize_overflow($yourtm.minute, $yourtm.second, $SECSPERMIN) {
		#     return $WRONG
		# }
		NORMALIZE_OVERFLOW_WORKAROUND_α: {
			my int16 ($a, $b, $c) = $yourtm.minute, $yourtm.second, $SECSPERMIN;
			my int16 $d = ($b ≥ 0) ?? ($b div $c) !! (-1 - (-1 - $b) div $c);
			$yourtm.second -= $d * $c; # $b -= $d * $c; # rewrite
			if ($a ≥ 0
				?? ($d > $INT_MAX - $a)
				!! ($d < $INT_MIN - $a)) {
				return $WRONG # return true aka, trigger return
			}else{
				$yourtm.minute += $d; # $a += $d rewrite
				# return false (aka, do nothing)
			}
		}
	}
	# if normalize_overflow($yourtm.hour, $yourtm.minute, $MINSPERHOUR) {
	# 	return $WRONG
    # }
    NORMALIZE_OVERFLOW_WORKAROUND_β: {
		my int16 ($a, $b, $c) = $yourtm.hour, $yourtm.minute, $MINSPERHOUR;
		my int16 $d = ($b ≥ 0) ?? ($b div $c) !! (-1 - (-1 - $b) div $c);
		$yourtm.minute -= $d * $c; # $b -= $d * $c; # rewrite
		if ($a ≥ 0
			?? ($d > $INT_MAX - $a)
			!! ($d < $INT_MIN - $a)) {
			return $WRONG # return true aka, trigger return
		}else{
			$yourtm.hour += $d; # $a += $d rewrite
			# return false (aka, do nothing)
		}
	}

	# if normalize_overflow($yourtm.day, $yourtm.hour, $HOURSPERDAY) {
	# 	return $WRONG
    # }
	NORMALIZE_OVERFLOW_WORKAROUND_γ: {
		my int16 ($a, $b, $c) = $yourtm.day, $yourtm.hour, $HOURSPERDAY;
		my int16 $d = ($b ≥ 0) ?? ($b div $c) !! (-1 - (-1 - $b) div $c);
		$yourtm.hour -= $d * $c; # $b -= $d * $c; # rewrite
		if ($a ≥ 0
			?? ($d > $INT_MAX - $a)
			!! ($d < $INT_MIN - $a)) {
			return $WRONG # return true aka, trigger return
		}else{
			$yourtm.day += $d; # $a += $d rewrite
			# return false (aka, do nothing)
		}
	}

	$y = $yourtm.year;
	# if normalize_overflow32($y, $yourtm.month, $MONSPERYEAR) {
	#     return $WRONG
    # }
	NORMALIZE_OVERFLOW_WORKAROUND_δ: {
		my int16 ($a, $b, $c) = $y, $yourtm.month, $MONSPERYEAR;
		my int16 $d = ($b ≥ 0) ?? ($b div $c) !! (-1 - (-1 - $b) div $c);
		$yourtm.month -= $d * $c; # $b -= $d * $c; # rewrite
		if ($a ≥ 0
			?? ($d > $INT_MAX - $a)
			!! ($d < $INT_MIN - $a)) {
			return $WRONG # return true aka, trigger return
		}else{
			$y += $d; # $a += $d rewrite
			# return false (aka, do nothing)
		}
	}


	# Turn y into an actual year number for now.
	# It is converted back to an offset from TM_YEAR_BASE later.

	# if increment_overflow32($y, $TM_YEAR_BASE) {
    #     return $WRONG
    # }
    INCREMENT_OVERFLOW32_WORKAROUND_α: {
    	my (int32 $a, int16 $b) = $y, $TM_YEAR_BASE;
		if ($a ≥ 0)
			?? ($b > $INT_FAST32_MAX - $a)
			!! ($b < $INT_FAST32_MIN - $a) {
			return $WRONG; # originally 'return true'
		}
		$y += $b; # originally $a += $b, but is rw
    }

	while ($yourtm.day ≤ 0) {
		# if (increment_overflow32($y, -1)) {
		#     return $WRONG;
        # }
        INCREMENT_OVERFLOW32_WORKAROUND_β: {
			my (int32 $a, int16 $b) = $y, -1;
			if ($a ≥ 0)
				?? ($b > $INT_FAST32_MAX - $a)
				!! ($b < $INT_FAST32_MIN - $a) {
				return $WRONG; # originally 'return true'
			}
			$y += $b; # originally $a += $b, but is rw
        }
		$li = $y + (1 < $yourtm.month);
		$yourtm.day += @year_lengths[isleap($li)];
	}

	while ($yourtm.day > $DAYSPERLYEAR) {
		$li = $y + (1 < $yourtm.month);
		$yourtm.day -= @year_lengths[isleap($li)];
		# if (increment_overflow32($y, 1)) {
		#     return $WRONG;
        # }
        INCREMENT_OVERFLOW32_WORKAROUND_γ: {
			my (int32 $a, int16 $b) = $y, 1;
			if ($a ≥ 0)
				?? ($b > $INT_FAST32_MAX - $a)
				!! ($b < $INT_FAST32_MIN - $a) {
				return $WRONG; # originally 'return true'
			}
			$y += $b; # originally $a += $b, but is rw
        }
	}

	loop {
		$i = @mon_lengths[isleap($y)][$yourtm.month];
		if ($yourtm.day ≤ $i) {
			last
        }
		$yourtm.day -= $i;
		if (++$yourtm.month) ≥ $MONSPERYEAR {
			$yourtm.month = 0;
			# if (increment_overflow32($y, 1)) {
			#     return $WRONG
            # }
			INCREMENT_OVERFLOW32_WORKAROUND_δ: {
				my (int32 $a, int16 $b) = $y, 1;
				if ($a ≥ 0)
					?? ($b > $INT_FAST32_MAX - $a)
					!! ($b < $INT_FAST32_MIN - $a) {
					return $WRONG; # originally 'return true'
				}
				$y += $b; # originally $a += $b, but is rw
			}
		}
	}
	# if (increment_overflow32($y, -$TM_YEAR_BASE)) {
	#     return $WRONG;
    # }
	INCREMENT_OVERFLOW32_WORKAROUND_ε: {
		my (int32 $a, int16 $b) = $y, -$TM_YEAR_BASE;
		if ($a ≥ 0)
			?? ($b > $INT_FAST32_MAX - $a)
			!! ($b < $INT_FAST32_MIN - $a) {
			return $WRONG; # originally 'return true'
		}
		$y += $b; # originally $a += $b, but is rw
	}
	if (! ($INT_MIN ≤ $y ≤ $INT_MAX)) {
		return $WRONG;
    }
	$yourtm.year = $y;
	if ($yourtm.second >= 0 && $yourtm.second < $SECSPERMIN) {
		$saved_seconds = 0;
    }
	elsif ($y + $TM_YEAR_BASE < $EPOCH_YEAR) {
		# We can't set tm_sec to 0, because that might push the
		# time below the minimum representable time.
		# Set tm_sec to 59 instead.
		# This assumes that the minimum representable time is
		# not in the same minute that a leap second was deleted from,
		# which is a safer assumption than using 58 would be.

		# if (increment_overflow($yourtm.second, 1 - $SECSPERMIN)) {
		#     return $WRONG;
        # }
		INCREMENT_OVERFLOW_WORKAROUND_α: {
			my int16 ($a, $b) = $yourtm.second, 1 - $SECSPERMIN;
			if ($a ≥ 0)
				?? ($b > $INT_MAX - $a)
				!! ($b < $INT_MIN - $a) {
				return $WRONG; # originally 'return true'
			}
			$yourtm.second += $b; # originally $a += $b, but is rw
		}
		$saved_seconds = $yourtm.second;
		$yourtm.second = $SECSPERMIN - 1;
	} else {
		$saved_seconds = $yourtm.second;
		$yourtm.second = 0;
	}

	# Do a binary search (this works whatever time_t's type is).

	# Basically, this search picks (leapcorrected) POSIX time values
	# It then determines what the time would be in the given time zone
	# and then compares the resultant calendar time with the given one,
	# and then tries again.
	$lo = $TIME_T_MIN;
	$hi = $TIME_T_MAX;
	BINARY_SEARCH:
	loop {

		$t = $lo div 2 + $hi div 2;
		if    ($t < $lo) { $t = $lo }
		elsif ($t > $hi) { $t = $hi }
		if (! funcp($sp, $t,  #`[$offset, ←unused?] $mytm)) {
			# Assume that t is too extreme to be represented in
			# a struct tm; arrange things so that it is less
			# extreme on the next pass.
			$dir = ($t > 0) ?? 1 !! -1;
		} else { $dir = tmcomp($mytm, $yourtm) }
		if ($dir != 0) {
			if ($t == $lo) {
				if ($t == $TIME_T_MAX) {
					return $WRONG;
				}
				++$t;
				++$lo;
			} elsif ($t == $hi) {
				if ($t == $TIME_T_MIN) {
					return $WRONG;
				}
				--$t;
				--$hi;
			}
			if ($lo > $hi) {
				return $WRONG;
			}
			if ($dir > 0) {
				$hi = $t;
			} else { $lo = $t }
			next;
		}

		# This comes from a pragma in the c code that goes
		#     if defined TM_GMTOFF && ! UNINIT_TRAP
		# TM_GMTOFF is True, but I'm not sure whether UNINIT_TRAP should be or not for Raku
		# This flag allows for quick testing between the two
		my $UNINIT_TRAP = False;

        if $UNINIT_TRAP {
			if ($mytm.gmt-offset != $yourtm.gmt-offset
				&& ($yourtm.gmt-offset < 0
					?? (-$SECSPERDAY <= $yourtm.gmt-offset
						&& ($mytm.gmt-offset <=
							(min($INT_FAST32_MAX, $LONG_MAX)
								+ $yourtm.gmt-offset)))
					!! ($yourtm.gmt-offset <= $SECSPERDAY
						&& ((max($INT_FAST32_MIN, $LONG_MIN)
							+ $yourtm.gmt-offset)
								<= $mytm.gmt-offset)))) {
			  # MYTM matches YOURTM except with the wrong UT offset.
			  #   YOURTM.TM_GMTOFF is plausible, so try it instead.
			  #   It's OK if YOURTM.TM_GMTOFF contains uninitialized data,
			  #   since the guess gets checked.
			  my time $altt = $t;
			  my int32 $diff = $mytm.gmt-offset - $yourtm.gmt-offset;

			  # if (!increment_overflow_time($altt, $diff)) { # THIS LINE BEING WORKED AROUND
			  my Bool $IOT;
			  INCREMENT_OVERFLOW_TIME_WORKAROUND: {
			  	  my (time $a, int32 $b) = $altt, $diff;
			      if (! ($b < 0
						   ?? ($TIME_T_MIN - $b ≤ $a)
						   !! ($a ≤ $TIME_T_MAX - $b))) {
					  $IOT = True;
				  } else{
				      $altt += $b;
				      $IOT = False;
				  }
			  }
			  if !$IOT { # this is the final line of the
				my Time $alttm;
				if (funcp($sp, $altt, #`[$offset, ←unused?] $alttm)
				&& $alttm.tm_isdst == $mytm.tm_isdst
				&& $alttm.gmt-offset == $yourtm.gmt-offset
				&& tmcomp($alttm, $yourtm) == 0) {
				  $t    = $altt;
				  $mytm = $alttm;
				}
			  }
			}
		} # end UNINIT_TRAP pragma

		if ($yourtm.dst < 0 || $mytm.dst == $yourtm.dst) {
			last
		}
		# Right time, wrong type.
		# Hunt for right time, right type.
		# It's okay to guess wrong since the guess
		# gets checked.

		if !$sp { # originally  if (sp == NULL)
			return $WRONG;
		}
		loop ($i = $sp.type-count - 1; $i >= 0; --$i) {
			if ($sp-.ttis[$i].is-dst != $yourtm.dst) {
				next
			}
			loop ($j = $sp.type-count - 1; $j >= 0; --$j) {
				if ($sp.ttis[$j].is-dst == $yourtm.dst) {
					next;
				}
				$newt = ($t + $sp.ttis[$j].utoffset
					- $sp.ttis[$i].utoffset);
				if (! funcp($sp, $newt,  #`[$offset, ←unused?] $mytm)) {
					next;
				}
				if (tmcomp($mytm, $yourtm) != 0) {
					next;
				}
				if ($mytm.dst != $yourtm.dst) {
					next;
				}
				# We have a match.
				$t = $newt;
				last BINARY_SEARCH; # was a goto: label
			}
		}
		return $WRONG;
	}

	# label (for goto, replaced by labeling the loop for escape
	$newt = $t + $saved_seconds;
	if (($newt < $t) != ($saved_seconds < 0)) {
		return $WRONG;
	}
	$t = $newt;
	if (funcp($sp, $t,  #`[$offset, ←unused?] $tmp)) {
		$okayp = True;
	}
	return $t;
}


# ⚠︎ The following normalize_overflow and increment_overflow routines
# ⚠︎   rely upon passing read-writable native ints. As of 24 XII 2021,
# ⚠︎   this causes a bytecode validation error, for more info, see
# ⚠︎   https://github.com/MoarVM/MoarVM/issues/1626
# ⚠︎ Once fixed, please delete WORKAROUND: labeled blocks for the
# ⚠︎   original code (commented out immediately above).
sub normalize_overflow(int16 $tensptr is rw, int16 $unitsptr is rw, int16 $base)
{
	my int16 $tensdelta;

	$tensdelta = ($unitsptr ≥ 0)
		?? ($unitsptr div $base)
		!! (-1 - (-1 - $unitsptr) div $base);
	$unitsptr -= $tensdelta * $base;
	return increment_overflow($tensptr, $tensdelta);
}
sub normalize_overflow32(int32 $tensptr is rw, int16 $unitsptr is rw, int16 $base)
{
	my int16 $tensdelta;

	$tensdelta = ($unitsptr ≥ 0)
		?? ($unitsptr div $base)
		!! (-1 - (-1 - $unitsptr) div $base);
	$unitsptr -= $tensdelta * $base;
	return increment_overflow32($tensptr, $tensdelta);
}
sub increment_overflow(int16 $ip is rw, int16 $j)
{
	my int16 $i = $ip;

	# If i >= 0 there can only be overflow if i + j > INT_MAX
	# or if j > INT_MAX - i; given i >= 0, INT_MAX - i cannot overflow.
	# If i < 0 there can only be overflow if i + j < INT_MIN
	# or if j < INT_MIN - i; given i < 0, INT_MIN - i cannot overflow.
	if (($i ≥ 0)
	    ?? ($j > $INT_MAX - $i)
	    !! ($j < $INT_MIN - $i)) {
	    return true
	}
	$ip += $j;
	return false;
}

sub increment_overflow32(int32 $lp is rw, int16 $m)
{
	my int32 $l = $lp;

	if (($l ≥ 0)
	    ?? ($m > $INT_FAST32_MAX - $l)
	    !! ($m < $INT_FAST32_MIN - $l)) {
	    return true;
	}
	$lp += $m;
	return false;
}

sub increment_overflow_time(time $tp is rw, int32 $j)
{
	# This is like
	# 'if (! (TIME_T_MIN <= *tp + j && *tp + j <= TIME_T_MAX)) ...',
	# except that it does the right thing even if *tp + j would overflow.

	if (! ($j < 0
	       ?? (True #`«(TYPE_SIGNED(time_t)» ?? $TIME_T_MIN - $j <= $tp !! -1 - $j < $tp) # this line begins with TYPE_SIGNED(time_t), which is true for us
	       !! ($tp <= $TIME_T_MAX - $j))) {
		return true;
	}
	$tp += $j;
	return false;
}

sub tmcomp(Time $a, Time $b) {
	my $x;
	if $x = $a.year   <=> $b.year   { return $x }
	if $x = $a.month  <=> $b.month  { return $x }
	if $x = $a.day    <=> $b.day    { return $x }
	if $x = $a.hour   <=> $b.hour   { return $x }
	if $x = $a.minute <=> $b.minute { return $x }
	return  $a.second <=> $b.second
}


sub posix2time (State $sp, int64 $t){
	my int64 $x;
	my int64 $y;

	$x = $t + leapcorr($sp, $t);
	$y = $x - leapcorr($sp, $x);
	if ($y < $t) {
		repeat {
			$x++;
			$y = $x - leapcorr($sp, $x);
		} while ($y < $t);
		$x -= $y != $t;
	} elsif ($y > $t) {
		repeat {
			--$x;
			$y = $x - leapcorr($sp, $x);
		} while ($y > $t);
		$x += $y != $t;
	}
	return $x;
}

sub leapcorr(State $sp, int64 $t) {
	my LeapSecInfo $lp;
	my int16 $i;

	$i = $sp.leap-count;
	while (--$i ≥ 0) {
		$lp = $sp.lsis[$i];
		if ($t ≥ $lp.transition) {
			return $lp.correction;
		}
	}
	return 0;
}
