# Timezones::ZoneInfo
A Raku module containing data (as well as some support routines) based on IANA's TZ database

Current IANA database version: **2021e** 

# Usage
There are three exported subs that will be the most commonly used.  Advanced users may wish to view the `Routines` submodule for more options.

  * **`timezone-data (Str() $olson-id --> State)`**  
Obtains the data for the given timezone.   The identifier is the Olson ID for the zone.  Backlinks for legacy IDs are followed.  If the zone does not exist, a warning is issued and the data for `Etc/GMT` is provided as a fallback.  See below for details on the `State` class.
  * **`sub calendar-from-posix (int64 $time, State $tz-data, :$leapadjusted = False --> Time)`**  
Given a [POSIX `time_t` stamp](https://www.gnu.org/software/libc/manual/html_node/Time-Types.html), provides the associated date/time (in a `Time` structure) for the timezone.  Passing `:leapadjusted` indicates that leapseconds are already included in the timestamp (this is not POSIX standard, but may be preferable for some applications).
  * **`sub posix-from-calendar (Time $tm-struct, State $tz-data, :$leapadjust = False --> int64)`**
Given a `Time` object (only ymdHMS values are used), provides the associated POSIX `time_t` timestamp and GMT offsets.  Pay close attention to the `dst` attribute: use `1` or `0` if you know the time to be in daylight savings time or not, use `-1` if you are not sure.  Passing `:leapadjust` will include leap seconds in the timestamp (not POSIX standard, but may be preferable for some applications). 

All methods work on times with integral seconds. It is left to the end user to handle any fractional seconds.

# Class reference

### Timezones::ZoneInfo::Time

A Raku version of the [POSIX `tm` struct](https://www.gnu.org/software/libc/manual/html_node/Broken_002ddown-Time.html) (with BSD/GNU extension).  Attributes include 

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

A Raku version of `tz`'s `state` struct.  It will be made more easily introspectable in the future.  For now, these are the attributes:
  * `.leap-count` (*number of leap seconds*)
  * `.lsis` (*array of `LeapSecInfo`, describing when they occur and by how much*)
  * `.time-count` (*number of moments when time shifts*)
  * `.ats` (*array of moments, as `time_t` when time shifts*)
  * `.type-count` (*number of transition types*)
  * `.ttis` (*array of `TransTimeInfo`, providing meta data for time shifts*)
  * `.types` (*array of indexes pointing to meta data for time shifts*)
  * `.char-count` (*number of abbreviation strings types*)
  * `.chars` (*c-style string data indicating timezone abbreviations*)
  * `.name` (*the Olson ID for the zone*)

# Data
The data comes from IANA's [**tz** database](https://www.iana.org/time-zones).  

# Version history

  * 0.1.0
    * First public release
  
# Copyright and license
The `tz` database and the code in it is public domain.  Therefore, the author module would find it unconscionable to release this module under any license, even for his own additions.  Consequently, this module is similarly expressly released into the public domain.  For jurisdictions where that is not possible, this module may be considered licensed under CC0 v1.0 (see accompanying license file).
