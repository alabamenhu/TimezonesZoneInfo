use v6.d;
=begin pod
=TITLE   Max/min POSIX time value finder
=AUTHOR  Matthew Stephen Stuckwisch
=VERSION 1.0
This script detects the minimum and maximum values for
POSIX times in a given Raku environment (this may vary
between OS/architecture/compiler).  This calculates it
once by way of trial and error, pinpointing it by
checking for validity of values in a binary search.
=end pod

sub MAIN {
    my \max-file = $*PROGRAM.parent.add('resources/posix-max');
    my \min-file = $*PROGRAM.parent.add('resources/posix-min');

    max-file.spurt: ~system-max-posix-time;
    min-file.spurt: ~system-min-posix-time;

    exit 0;
}

sub system-max-posix-time {
    my $lo = 0;
    my $hi = 2 ** 128;
    while $hi - $lo > 1 {
        my $mid = ($hi + $lo) div 2;
        try     { Instant.from-posix($mid).DateTime }
        with $! { $hi = $mid }
        else    { $lo = $mid }
    }
    try        { Instant.from-posix($hi).DateTime }
    do with $! { return $lo }
    else       { return $hi }
}

sub system-min-posix-time {
    my $lo = - (2 ** 128);
    my $hi = 0;
    while $hi - $lo > 1 {
        my $mid = ($hi + $lo) div 2;
        try     { Instant.from-posix($mid).DateTime }
        with $! { $lo = $mid }
        else    { $hi = $mid }
    }

    try     { Instant.from-posix($lo).DateTime }
    with $! { return $hi }
    else    { return $lo }
}