use Timezones::ZoneInfo::State:auth<zef:guifa>;
use Timezones::ZoneInfo::Time:auth<zef:guifa>;

BEGIN my Map $links = %?RESOURCES{"links"}.lines.Map;
BEGIN my Set $zones = %?RESOURCES{"zones"}.lines.Set;

sub timezone-data (Str() $olson-id --> State) is export(:MANDATORY) {
    # Here we load the timezone data based on the Olson ID
    # and return it as a State object, caching as best we can.
    state %cache;
    .return with %cache{$olson-id};

    if $zones{$olson-id}:exists {
        return %cache{$olson-id} := State.new:
            %?RESOURCES{"TZif/$olson-id"}.IO.slurp(:bin),
            :name($olson-id);
    } orwith $links{$olson-id} {
        return %cache{$olson-id} := samewith $_;
    } else {
        use CX::Warn::Timezones::UnknownID;
        UnknownID.new(requested => $olson-id).throw;
        samewith 'Etc/GMT'
    }
}

# These routines just pass data along, but their names
# simply make more sense.  TODO: better document leapseconds

sub calendar-from-posix(int64 $time, State $state --> Time) is export(:MANDATORY) {
    use Timezones::ZoneInfo::Routines;
    localsub $state, $time
}

sub posix-from-calendar(Time $time, State $state --> int64) is export(:MANDATORY) {
    use Timezones::ZoneInfo::Routines;
    mktime $time, $state;
}

sub timezones-as-set(Bool() :$standard = True; Bool() :$aliases = False, Bool() :$historical = False --> Set) is export(:MANDATORY) {
    die X::NYI if $historical;

    return $zones ∪ $links.keys if $standard == True  && $aliases == True;
    return $links.keys.Set      if $standard == False && $aliases == True;
    return $zones               if $standard == True  && $aliases == False;
    return Set.new; # I mean, no one should reach this point, but it's consistent
}


# Officially, Instant (which is used to compare DateTime values)
# has no epoch.  Internally, Rakudo stores it in an int128 as a
# leapsecond-adjusted POSIX value (as an int128). For this reason
# the current practical max is 2⁶³-28 (as of 2022, there are 27
# leapseconds.  Since this will be Rakudo and/or architecture
# specific, we figure out the true safe values
# Realistically, these "safe" values (year = ±146×10⁹)
# should be more than sufficient until things stabilize for now.
constant max-time = BEGIN %?RESOURCES<posix-max>.slurp.Int;
constant min-time = BEGIN %?RESOURCES<posix-min>.slurp.Int;
sub max-posix-time is export(:constants) { max-time }
sub min-posix-time is export(:constants) { min-time }


my class InfFutureDateTime {
    method new     { nextwith max-time }
    method defined { False             }
    method Bool    { False             }
}
my class InfPastDateTime {
    method new     { nextwith min-time }
    method defined { False             }
    method Bool    { False             }
}

constant gregorian-cycle = 146_097 * 24 * 60 * 60; # 146097 days = 400 year gregorian cycle
proto sub next-tz-shift (|) is export(:tz-shift) {*}
multi sub next-tz-shift (int64 $time, State $state) {
    # To calculate, first adjust for leapseconds
    # Then, if it's beyond the last transition time, two things can happen
    #   (1) No loop, return a psuedo-infinite datetime
    #   (2) Loops, go back 400-year increments to calculate (then jump back afterwards)
    # Otherwise, calculation is a basic binary search
    my $leapseconds = leapseconds-at-time $time, $state;
    my $adj-time = $time + $leapseconds;
    my $jump     = 0;

    if $adj-time > $state.ats.tail {
        return max-time unless $state.go-ahead;
        my $secs-since-last   = $adj-time - $state.ats.tail;
        my $cycles-since-last = $secs-since-last div gregorian-cycle + 1; # add one to do effective ceiling
        $jump = gregorian-cycle * $cycles-since-last;
    } elsif $adj-time < $state.ats[1] { # 0 is generally an "absolute min" value
        unless $state.go-back {
            my $trans = $state.ats[1] - leapseconds-at-time($state.ats[1],$state);
            return $trans == 0 ?? max-time !! $trans;
        }
        my $secs-until-first   = $state.ats[0] - $adj-time;
        my $cycles-until-first = $secs-until-first div gregorian-cycle + 1; # add one to do effective ceiling
        $jump = - gregorian-cycle * $cycles-until-first;
    }
    $adj-time -= $jump;

    my int64 $lo = 1;
    my int64 $hi = $state.time-count;

    while $lo < $hi {
        my int64 $mid = ($lo + $hi) div 2;
        if $adj-time < $state.ats[$mid] { $hi = $mid    }
        else                            { $lo = $mid + 1};
    }

    # 0 is the Unix epoch.  This value doesn't coincide with any real-world transition time
    # so we treat it as a magical number.  The ZIC compiler uses 0 for zones with no transition
    # times to maximize compatibility with other systems.
    my $trans     = $state.ats[$lo] + $jump;
    my $adj-trans = $trans - leapseconds-at-time $trans, $state;
    $adj-trans == 0
        ?? max-time
        !! $adj-trans;
}
multi sub next-tz-shift (Int $time, State $state) {
    my int64 $t = $time;
    next-tz-shift $t, $state;
}
multi sub next-tz-shift (Time $time, State $state) {
    my $posix = posix-from-calendar $time,  $state;
    my $next  = next-tz-shift $posix, $state;
    calendar-from-posix $next, $state;
}


proto sub prev-tz-shift (|) is export(:tz-shift) {*}
multi sub prev-tz-shift (Time $time, State $state) {
    my $posix = posix-from-calendar $time,  $state;
    my $next  = prev-tz-shift $posix, $state;
    calendar-from-posix $next, $state;
}
multi sub prev-tz-shift (int64 $time, State $state) {
    # To calculate, first adjust for leapseconds
    # Then, if it's beyond the first transition time, two things can happen
    #   (1) No loop, return a psuedo-infinite datetime
    #   (2) Loops, go forward 400-year increments to calculate (then jump back afterwards)
    # Otherwise, calculation is a basic binary search
    my $leapseconds = leapseconds-at-time $time, $state;
    my $adj-time = $time + $leapseconds;
    my $jump     = 0;

    if $adj-time < $state.ats[1] { # .[0] is always INT_MIN (which may be 0 or actual INT_MIN by zone), so not a useful compare value here
        return min-time unless $state.go-back;
        my $secs-until-first = $state.ats[1] - $adj-time;
        my $cycles-until-first = $secs-until-first div gregorian-cycle + 1; # add one to do effective ceiling
        $jump = gregorian-cycle * $cycles-until-first;
    } elsif $adj-time > $state.ats.tail {
        unless $state.go-ahead {
            # TODO, are these subtracted values accurate?
            # TODO, That is are we calculating leapseconds at an already shifted value?
            my $trans = $state.ats.head - leapseconds-at-time($state.ats.head,$state);
            return $trans == 0 ?? min-time !! $trans;
        }
        my $secs-since-last   = $adj-time - $state.ats.tail;
        my $cycles-since-last = $secs-since-last div gregorian-cycle + 1; # add one to do effective ceiling
        $jump = - gregorian-cycle * $cycles-since-last;
    }

    $adj-time += $jump;

    my int64 $lo = 1;
    my int64 $hi = $state.time-count;

    while $lo < $hi {
        my int64 $mid = ($lo + $hi) div 2;
        if $adj-time < $state.ats[$mid] { $hi = $mid    }
        else                            { $lo = $mid + 1};
    }

    my $trans     = $state.ats[$lo - 1] - $jump;
    my $adj-trans = $trans - leapseconds-at-time $trans, $state;
    $adj-trans == 0
        ?? min-time
        !! $adj-trans;
}
multi sub prev-tz-shift (Int $time, State $state) {
    my int64 $t = $time;
    prev-tz-shift $t, $state;
}


sub leapseconds-at-time (int64 $time, State $state) is export(:leapseconds) {
    return 0 if $time < $state.leapseconds.head.transition;
    return $state.leapseconds[$_ - 1].correction
        if $time < $state.leapseconds[$_].transition
            for 1 ..^ $state.leapseconds.elems;
    return $state.leapseconds.tail.correction;
}