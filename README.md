# Timezones::ZoneInfo
A Raku module containing data (as well as some support routines) based on IANA's TZ database.
This module is not normally expected to be consumed on its own — it is designed to be as light weight as possible.
Its intended use is for authors of various time-related tools. 

Current IANA database version: **2022e** 

# Usage
The first four subs are exported by default.  All methods work on times with integral seconds. It is currently left to the end user to handle any fractional seconds.

  * **`sub timezones-as-set(:$standard = True, :$aliases = False, :$historical = False --> Set)`**  
This provides a list of all timezone identifiers as a set (if you need it as a list, `.keys`).  By default it does not include various aliases (generally, but not always, spell changes in identifiers like *Kiev*→*Kyiv*).  Historical zones are those that go back to the early part of the 20th century and farther back and rarely if ever needed.  They are currently NYI.
  * **`timezone-data (Str() $olson-id --> State)`**  
Obtains the data for the given timezone.   The identifier is the Olson ID for the zone.  Backlinks for legacy IDs are followed.  If the zone does not exist, a warning is issued and the data for `Etc/GMT` is provided as a fallback.  See below for details on the `State` class.
  * **`sub calendar-from-posix (int64 $time, State $tz-data, :$leapadjusted = False --> Time)`**  
Given a [POSIX `time_t` stamp](https://www.gnu.org/software/libc/manual/html_node/Time-Types.html), provides the associated date/time (in a `Time` structure) for the timezone.  Passing `:leapadjusted` indicates that leapseconds are already included in the timestamp (this is not POSIX standard, but may be preferable for some applications).
  * **`sub posix-from-calendar (Time $tm-struct, State $tz-data, :$leapadjust = False --> int64)`**  
Given a `Time` object (only ymdHMS values are used), provides the associated POSIX `time_t` timestamp and GMT offsets.  Pay close attention to the `dst` attribute: use `1` or `0` if you know the time to be in daylight savings time or not, use `-1` if you are not sure.  Passing `:leapadjust` will include leap seconds in the timestamp (not POSIX standard, but may be preferable for some applications). 

The final two methods are available by providing the `tz-shift` option in the `use` statement.  They will return a time in the same format provided.

  * **`sub next-tz-shift (Time|int64 $time, State $tz-data, :$leapadjust = False --> Time|int64)`**  
Given either a `Time` object (only ymdHMS values are used) or a POSIX `time_t` timestamp, indicates when the next shift in GMT offsets will occur. Generally, that's when daylight savings time will start or end, but it may also be when an area shifts timezones entirely (e.g. when Russia makes adjustments to its timezones at various periods throughout the year).  Passing `:leapadjust` will include leap seconds in the timestamp (not POSIX standard, but may be preferable for some applications).  This routine returns values in the same format provided.
  * **`sub prev-tz-shift (Time|int64 $time, State $tz-data, :$leapadjust = False --> Time|int64)`**  
Same as `next-tz-shift` but in reverse.  Finds the most recent previous shift in timezone data.

Both `next-tz-shift` and `prev-tz-shift` can potentially return a special extremely small or large integer value.  
Such values are intended to represent an “infinite” past or future, but may be different given compiler/architecture/system.
`Timezones::ZoneInfo` will detect your system's maximum and minimum time values upon installation and those
values can be obtained using the constants `max-posix-time` and `min-posix-time` (exported with `:constants` in the `use` statement).
On my system, for instance, these are **2<sup>63</sup> - 1 - 27**, and **0 - 2<sup>63</sup>**, where 27 is the current number of leapseconds.

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
  * `.leapcnt` (*number of leap seconds*)
  * `.lsis` (*array of `LeapSecInfo`, describing when they occur and by how much*)
  * `.timecnt` (*number of moments when time shifts*)
  * `.ats` (*array of moments, as `time_t` when time shifts*)
  * `.typecnt` (*number of transition types*)
  * `.ttis` (*array of `TransTimeInfo`, providing meta data for time shifts*)
  * `.types` (*array of indexes pointing to meta data for time shifts*)
  * `.chars` (*c-style string data indicating timezone abbreviations*)
  * `.charcnt` (*length of `chars`*)
  * `.name` (*the Olson ID for the zone*)

# Data
The data comes from IANA's [**tz** database](https://www.iana.org/time-zones).  

# Todo
  * Add support for fractional seconds
  * Tweak custom warning throwing
  
# Version history
  * 0.4.0
    * Add new feature to find previous/next shifts in timezone (`next-tz-rule-change` and `prev-tz-rule-change`)
    * Fixed a major calculation bug in interpreting POSIX tz strings
    * New tests to guard against future bugs
    * Moved maintenance tools out of `resources` and into `tools` (they aren't needed at runtime)
    * Updated to 2022e version of the database
      * Jordan and Syria will now observe DST year round
      * Minor fixes for historical data in Mexico
  * 0.3.1
    * Debug-mode–guarded some code that was spitting random hyphens
  * 0.3.0
    * Added new exported routine `timezones-as-set`
    * Updated to 2022d version of the database (2022c did not have new tz data)
      * Palestine will enter DST on Saturdays
      * Ukraine zones simplified
  * 0.2.2
    * Updated to 2022b version of the database
      * Urgent update for Chile
      * Iran will no longer use DST
  * 0.2.1
    * Updated to 2022a version of the database
      * Urgent update for Palestine
      * Improvements to historical data for Ukraine and Chile.
  * 0.2.0
    * Added support for version 3 files (these allow for full repeat into the future) 
  * 0.1.0
    * First public release
  
# Copyright and license
The `tz` database and the code in it is public domain.  Therefore, the author of this module (Matthew Stephen Stuckwisch) would find it unconscionable to release this module under any license, even for his own additions.  Consequently, this module is similarly expressly released into the public domain.  For jurisdictions where that is not possible, this module may be considered © 2021–2022 and licensed under CC0 v1.0 (see accompanying license file).
