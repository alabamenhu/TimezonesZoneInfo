unit class LeapSecInfo is export;

has int64 $.transition; #= When the leap second occurs
has uint32 $.correction; #= How much time is added / subtracted

method new(blob8 $b) {
    if $b.elems == 8 {
        return self.bless:
                :transition($b.read-int32:  0, BigEndian),
                :correction($b.read-uint32: 4, BigEndian)
    } elsif $b.elems == 12 {
        return self.bless:
                :transition($b.read-int64:  0, BigEndian),
                :correction($b.read-uint32: 8, BigEndian)
    } else {
        die "Bad leap second information passed";
    }
}

multi method gist (::?CLASS:D:) {
    ~ "Ls["
    ~ ($!correction ≥ 0 ?? '+' !! '-')
    ~ ('0' if $!correction < 10)
    ~ $!correction
    ~ ' @ '
    ~ (DateTime.new: $!transition)
}