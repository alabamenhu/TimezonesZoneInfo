# Timezones::ZoneInfo
A Raku module containing data (as well as some support routines) based on IANA's TZ database

Current IANA database version: **2021e** 

# Usage
```raku
   use Timezones::Data;
   get-timezone-data 'America/New_York'; # Obtain timezone data for the US's Eastern time
```

The timezone data is of type `Timezones::ZoneInfo::State` used with other methods.

Given a `DateTime` object from Raku, to interpret it in a given timezone, run it through the `localsub` \*ahem* sub:

```raku
my $us-east  = get-timezone-data 'America/New_York';
my $datetime = DateTime.now;
my $time     = localsub $us-east, $datetime.posix;
```

The `localsub` method takes a `State` value and a POSIX timestamp.  POSIX timestamps do *not* include leapstamps (they actually repeat for leapseconds).  If you have received a timestamp that does have leapseconds already taken into account, use `:leapadjusted` to avoid time calculation errors.
See documentation below for the format of `$time`.  Convenience methods may be written down the road, but in general, these methods are expected to be used by module authors.

# Class reference

### Timezones::ZoneInfo::Time

A Raku version of the POSIX `tm` struct.  Attributes include 

  * `.year` (**-∞..∞**, *years since 1900, 1910 = 10*)
  * `.month` (**0..11**, *months since January*)
  * `.day` (**1..31**)
  * `.hour` (**0..23**)
  * `.minute` (**0..59**)
  * `.second` (**0..61**, *values of 60-61 for leapseconds*)
  * `.weekday` (**0..6**, *days since Sunday; Monday = 1*)
  * `.yearday` (**0..365**, *day index in year, 0 = January 1st*)
  * `.dst` (**-1..1**; *0 standard time, 1 summer time, -1 unknown/automatic*)
  * `.gmt-offset` (**-∞..∞**, *offset of GMT, positive = east of GMT*)
  * `.tz-abbr` (*three or four letter abbreviation, non-unique*)
  
The infinite ranged elements aren't actually that as they're stored as `int32`.

### Timezones::ZoneInfo::State

A Raku version of `tz`'s `state` struct.  It will be made more easily introspectable in the future.

# Data
The data comes from IANA's [**tz** database](https://www.iana.org/time-zones).  

## Usage notes
If you request an unknown timezone via `get-timezone-data`, the data will be returned for `Etc/GMT`.
Using the `.posix` method of a DateTime object will strip any fractional seconds from it.

## Development notes
The names for the routines come from 