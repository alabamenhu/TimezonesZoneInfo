use Timezones::ZoneInfo::State;
use Timezones::ZoneInfo::Time;
sub next-tz-rule-change     { ... }
sub previous-tz-rule-change { ... }

BEGIN my %links = %?RESOURCES{"links"}.lines;

sub timezone-data (Str() $olson-id --> State) is export {
    # Here we load the timezone data based on the Olson ID
    # and return it as a State object;

    state %cache;
    .return with %cache{$olson-id};

    with %?RESOURCES{"TZif/$olson-id"}.IO.?slurp(:bin) {
        return %cache{$olson-id} := State.new: $_, :name($olson-id)
    } orwith %links{$olson-id} {
        return %cache{$olson-id} := samewith $_;
    } else {
        use CX::Warn::Timezones::UnknownID;
        warn UnknownID.new(requested => $olson-id);
        samewith 'Etc/GMT'
    }
}

sub calendar-from-posix(int64 $time, State $state --> Time) is export {
    use Timezones::ZoneInfo::Routines;
    localsub $state, $time
}


sub posix-from-calendar(Time $time, State $state --> int64) is export {
    use Timezones::ZoneInfo::Routines;
    mktime $time, $state;
}