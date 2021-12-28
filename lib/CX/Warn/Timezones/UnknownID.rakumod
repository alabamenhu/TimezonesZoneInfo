unit class UnknownID is CX::Warn is export;

has $.requested;

method message {
    ~ "The requested timezone ‘$!requested’ is unknown.\n"
    ~ "Perhaps you mistyped it?\n"
    ~ "    (Note: data for ‘Etc/UTC’ was given as fallback)"
}