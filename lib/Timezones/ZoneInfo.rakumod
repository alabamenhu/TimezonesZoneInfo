use Timezones::ZoneInfo::State;
use Timezones::ZoneInfo::Time;
sub next-tz-rule-change     { !!! }
sub previous-tz-rule-change { !!! }

BEGIN my Map $links = %?RESOURCES{"links"}.lines.Map;
BEGIN my Set $zones = %?RESOURCES{"zones"}.lines.Set;

sub timezone-data (Str() $olson-id --> State) is export {
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

sub calendar-from-posix(int64 $time, State $state --> Time) is export {
    use Timezones::ZoneInfo::Routines;
    localsub $state, $time
}

sub posix-from-calendar(Time $time, State $state --> int64) is export {
    use Timezones::ZoneInfo::Routines;
    mktime $time, $state;
}

sub timezones-as-set(Bool() :$standard = True; Bool() :$aliases = False, Bool() :$historical = False --> Set) is export {
    die X::NYI if $historical;

    return $zones ∪ $links.keys if $standard == True  && $aliases == True;
    return $links.keys.Set      if $standard == False && $aliases == True;
    return $zones               if $standard == True  && $aliases == False;
    return Set.new; # I mean, no one should reach this point, but it's consistent
}