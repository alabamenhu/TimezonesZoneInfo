# Timezones::ZoneInfo
A Raku module containing data (as well as some support routines) based on IANA's TZ database

Current IANA database version: **2021e** 

# Usage
```raku
   use Timezones::Data;
   get-timezone-data 'America/New_York'; # Obtain timezone data for the US's Eastern time
```

The timezone data is of type `Timezones::ZoneInfo::State` used with other methods. The identifier is the Olson ID for the zone.

There are two main functions (in `Timezones::ZoneInfo::Routines`) that work with timezones that you are likely to want to use:

  * **`sub localsub (State $tz-data, Int $posix-timestamp, :$leapadjusted = False --> Time)`**  
  Given a POSIX time stamp, provides the associated date/time (in a `Time` structure) for the timezone.  Passing `:leapadjusted` indicates that leapseconds are already included in the timestamp (this is not POSIX standard, but may be preferable for some applications)
  * **`sub mktime (State $tz-data, Time $tm-struct, :$leapadjust = False --> Time)`**  
  ***(NYI)*** Given a tm structure (`Timezones::ZoneInfo::Time`), provides the associated POSIX timestamp and GMT offsets.  Pay close attention to the `dst` attribute: use `1` or `0` if you know the time to be in daylight savings time or not, use `-1` if you are not sure.  Passing `:leapadjust` will include leap seconds in the timestamp (not POSIX standard, but may be preferable for some applications). 

These are more meant to be used by developers than end users, and convenience methods (or other modules) are intended to call these instead.
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