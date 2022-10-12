#| Defines information related to a time element, used internally in calculations
unit class TransTimeInfo is export;

has int32 $.utoffset   is rw;         #= The offset from universal time in seconds
has Bool  $.is-dst     is rw;         #= Whether daylight savings time
has int   $.abbr-index is rw;         #= Index in the list of abbreviations
has Bool  $.is-std     is rw = False; #= If true, transition is in standard time, else wall clock)
has Bool  $.is-ut      is rw = False; #= If true, transition is in universal time, else local time).
has str   $.abbr       is rw = '';    #= The actual string abbreviation (not from C)

multi method Str (::?CLASS:D:) {
    "[$!abbr {$!utoffset / 3600}h, {$!is-ut ?? 'gmt' !! 'loc'}/{$!is-dst ?? 'dst' !! 'std'}]";
}

multi method gist (::?CLASS:D:) {
    self.Str
}