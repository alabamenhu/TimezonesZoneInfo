use Test;
use Timezones::ZoneInfo;
use CX::Warn::Timezones::UnknownID;

timezone-data 'Atlantic/Atlantis';
CONTROL {
    when UnknownID { ok True,  'Unknown Olsen ID Warning'; .resume }
    default        { ok False, 'Unknown Olsen ID Warning'; .resume }
}

done-testing;
