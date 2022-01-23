unit class ConvRule is export;

enum RuleType (
    julian-day            => 0,
    day-of-year           => 1,
    month-nth-day-of-week => 2);

has RuleType $.type;  #= The type of rule
has int      $.day;   #= Day number of rule
has int      $.week;  #= Week number of rule
has int      $.month; #= Month number of rule
has int32    $.time;  #= Transition time of rule, seconds after midnight
