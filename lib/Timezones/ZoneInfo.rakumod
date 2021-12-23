# This class mimics the functionality of
use Timezones::ZoneInfo::State;

sub next-tz-rule-change     { ... }
sub previous-tz-rule-change { ... }

sub get-timezone-data (Str() $olson-id --> State) is export {
    # Here we load the timezone data based on the Olson ID
    # and return it as a State object;

    state %cache;
    .return with %cache{$olson-id};

    # TODO more gracefully handle this
    with %?RESOURCES{"TZif/$olson-id"}.slurp(:bin) {
        return %cache{$olson-id} := State.new: $_, :name($olson-id)
    }else{
        warn 'Unknown / invalid time zone ID';
        %cache{$olson-id} := samewith 'Etc/GMT';
    }
}

sub apply-timezone-to-posix($time, State $state) is export {
    use Timezones::ZoneInfo::Routines;
    localsub $state, $time
}