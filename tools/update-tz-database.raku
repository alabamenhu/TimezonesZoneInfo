#`(-------------------- TIMEZONE DATABASE UPDATER SCRIPT ------------------------

   SSSSSSSSSSSSSSS TTTTTTTTTTTTTTTTTTTTTTT     OOOOOOOOO     PPPPPPPPPPPPPPPPP
 SS:::::::::::::::ST:::::::::::::::::::::T   OO:::::::::OO   P::::::::::::::::P
S:::::SSSSSS::::::ST:::::::::::::::::::::T OO:::::::::::::OO P::::::PPPPPP:::::P
S:::::S     SSSSSSST:::::TT:::::::TT:::::TO:::::::OOO:::::::OPP:::::P     P:::::P
S:::::S            TTTTTT  T:::::T  TTTTTTO::::::O   O::::::O  P::::P     P:::::P
S:::::S                    T:::::T        O:::::O     O:::::O  P::::P     P:::::P
 S::::SSSS                 T:::::T        O:::::O     O:::::O  P::::PPPPPP:::::P
  SS::::::SSSSS            T:::::T        O:::::O     O:::::O  P:::::::::::::PP
    SSS::::::::SS          T:::::T        O:::::O     O:::::O  P::::PPPPPPPPP
       SSSSSS::::S         T:::::T        O:::::O     O:::::O  P::::P
            S:::::S        T:::::T        O:::::O     O:::::O  P::::P
            S:::::S        T:::::T        O::::::O   O::::::O  P::::P
SSSSSSS     S:::::S      TT:::::::TT      O:::::::OOO:::::::OPP::::::PP
S::::::SSSSSS:::::S      T:::::::::T       OO:::::::::::::OO P::::::::P
S:::::::::::::::SS       T:::::::::T         OO:::::::::OO   P::::::::P
 SSSSSSSSSSSSSSS         TTTTTTTTTTT           OOOOOOOOO     PPPPPPPPPP

                        Read the documentation, thanks ;-)

=begin pod
I have tried to account for the display of certain errors, but they might sometimes
be LTA.  The most important things is to have all of the base modules and command
line tools:

=item C<LibCurl> (requires L<curl|https://curl.haxx.se/>)
=item C<LibArchive> (requires L<libarchive|https://www.libarchive.org/>)
=item L<gcc|https://gcc.gnu.org/>

To run, just use the command

    raku update-tz-database.raku

There are currently no options, but eventually I will add options to skip certain
steps to be performed manually in case something is causing them problems.

First we have a few constants:
=end pod
constant $updater-version = '0.6.2';
constant $module-version  = '0.4.1';
constant TZ-DATA-URL      = 'ftp://ftp.iana.org/tz/tzdata-latest.tar.gz'; #= TZ data download URL
constant TZ-CODE-URL      = 'ftp://ftp.iana.org/tz/tzcode-latest.tar.gz'; #= TZ code download URL
constant TZ-ZONE-FILES    = <africa antarctica asia australasia etcetera
                            europe factory northamerica southamerica>;    #= Files with zone data (pacificnew removed in 2020b)
constant TZ-ZIC-FILES     = <zic.c private.h tzfile.h version>;           #= Files to be cleaned up

# Build paths ( .parent = tools/ )
my \TZ-BIN-DIR     = $*PROGRAM.parent.add('update/bin').resolve;                               #= TZ utility compile directory
my \TZ-DL-DIR      = $*PROGRAM.parent.add('update/download').resolve;                          #= TZ files download directory
my \TZ-DATA-DL     = $*PROGRAM.parent.add('update/download/tzdata-latest.tar.gz').resolve.Str; #= TZ data download file
my \TZ-CODE-DL     = $*PROGRAM.parent.add('update/download/tzcode-latest.tar.gz').resolve.Str; #= TZ code download file
my \TZ-DATA-DIR    = $*PROGRAM.parent.add('update/data/').resolve.Str;                         #= TZ data expansion directory
my \TZ-LEAPSECONDS = $*PROGRAM.parent.add('update/data/leapseconds').resolve.Str;              #= Leapseconds data file
my \VERSION-FILE   = $*PROGRAM.parent.add('update/tz-version').resolve.Str;                    #= Most recent TZ metadata file
my \TZ-ZIC-EXE     = $*PROGRAM.parent.add('update/bin/zic').resolve.Str;                       #= Executable zic utility file
my \TZ-BACK-FILE   = $*PROGRAM.parent.add('update/data/backward').resolve.Str;
# Product paths
my \META6-FILE     = $*PROGRAM.parent.parent.add('META6.json').resolve.Str;         #= Timezones::ZoneInfo's current META6 file
my \TZif-DIR       = $*PROGRAM.parent.parent.add('resources/TZif').resolve.Str;     #= Where compiled tz data files will go
my \TZ-LINK-FILE   = $*PROGRAM.parent.parent.add('resources/links').resolve.Str.IO; #= A file (newline delimited) with pairs of alias names to real names
my \TZ-ZONE-FILE   = $*PROGRAM.parent.parent.add('resources/zones').resolve.Str.IO; #= A file that lists each available timezone

# Because I like teh pretty
constant $g     = "\x001b[32m";
constant $r     = "\x001b[31m";
constant $b     = "\x001b[34m";
constant $x     = "\x001b[0m";
constant $tall1 = "\x001b#3";
constant $tall2 = "\x001b#4";
constant $wide  = "\x001b#6";


# Sometimes github doesn't work well with empty directories,
# but we need these to be present:
TZ-BIN-DIR.mkdir;
TZ-DL-DIR.mkdir;

# Gotta say hi and try to be fancy (yes I got bored)
my @header-choices = (1, 2 xx 10).flat;
say header @header-choices.pick;

=begin pod
First we download the files from the IANA website.
Thankfully these days it shouldn't take that long
=end pod
use LibCurl::Easy;
print "Downloading TZ data files (~400kB)... ";
LibCurl::Easy.new(URL => TZ-DATA-URL, download => TZ-DATA-DL).perform;
say $g, "OK", $x;
print "Downloading TZ code files (~250kB)... ";
LibCurl::Easy.new(URL => TZ-CODE-URL, download => TZ-CODE-DL).perform;
say $g, "OK", $x;


=begin pod
The archives contain a fair number of extra files that we do not need.
Out of the tzdata archive, we grab the files with mostly modern
information and avoid the historical ones because they are known to be
less accurate.  But maybe one day as an option...

From the code archive, we only need to compile the ZIC, and so we
grab only the files needed for its compilation. (Code for localtime
was ported directly to Raku.)
=end pod

use Libarchive::Simple;

print "Extracting TZ data files... ";
  my $data = archive-read TZ-DATA-DL;
  .extract(destpath => TZ-DATA-DIR)
    for $data.grep(*.pathname ∈ TZ-ZONE-FILES | 'leapseconds' | 'backward' );
say $g, "OK", $x;


print "Extracting TZ code files... ";
  my $code = archive-read TZ-CODE-DL;
  .extract(destpath => TZ-DATA-DIR)
    for $code.grep(*.pathname ∈ TZ-ZIC-FILES);
say $g, "OK", $x;


=begin pod
Compiling immediately after extraction would result in an error because
it requires a C<version.h> file.  That file is created via the Makefile,
but why waste our time?  The values it holds are only for printing out
usage/version information, which we don't care about.  Consequently, the
file has already been included (and should not be deleted in distributions
of this module) as the following:

    static char const PKGVERSION[]="";
    static char const TZVERSION[]="";
    static char const REPORT_BUGS_TO[]="";

GCC is required, but perhaps other compilers could be enabled in the
future.  We do a basic compile without optimization because the
processing is so fast anyways.
=end pod


print "Building zone info compiler (ZIC)... ";
# -DHAVE_GETTEXT=0 is because MacOS gives strange results for this, see
# documentation at <http://mm.icann.org/pipermail/tz/2022-October/032168.html>
unless my $proc = run(<gcc -Wall update/data/zic.c -o update/bin/zic -DHAVE_GETTEXT=0>, :cwd($*PROGRAM.parent.resolve), :err) {
    say $r, "ERROR", $x;
    say("   ", $r, "|", $x, " $_") for $proc.err.slurp(:close).lines;
    die "Please fix the above and try again.";
}
say $g, "OK", $x;

=begin pod
With ZIC compiled, we begin processing the data files.  Each of the
regional files (Europe, Asia, etc) contain dozens of different zones
with hundreds of rules, as well as a fair number of links.  Right now
we don't do anything special with the links -- ZIC outputs multiple
copies of the same zone under each name.  To be memory efficient, we
could eventually link them through binding at run time and remove
the excess to reduce download size.
=end pod

print "Processing zone files... ";
TZ-ZONE-FILE.spurt: ""; # clear old
for TZ-ZONE-FILES<> -> $zone {
    print "\rProcessing zone files... $b","($zone)$x \x001b[K";
    unless my $proc = run(
            TZ-ZIC-EXE, '-b','slim',
            '-d', TZif-DIR,
            '-L', TZ-LEAPSECONDS,
             "{TZ-DATA-DIR}/$zone", :err) {
        say $r, "ERROR", $x;
        say("   ", $r, "|", $x, " $_") for $proc.err.slurp(:close).lines;
        die "Please fix the above and try again.";
    }

    # get names of individual ones
    for TZ-DATA-DIR.IO.add($zone).lines.grep(*.starts-with: 'Zone')>>.match(/^Zone \h+ <( \S+ )>/) -> $id {
        TZ-ZONE-FILE.spurt: "$id\n", :append;
    }
    # And now the aliased versions
    for TZ-DATA-DIR.IO.add($zone).lines.grep(*.starts-with: 'Link')>>.match(/^Link \h+ <[a..zA..Z0..9/_-]>+ \h+ <(<[a..zA..Z0..9/_-]>+ )>/) -> $id {
        TZ-ZONE-FILE.spurt: "$id\n", :append;
    }

}
say "\rProcessing zone files... ", $g, "OK", $x, "\x001b[K";


=begin pod
Around 1993, a number of timezones were renamed.  These name changes
were included as links in a separate file.  We read them in here separately.
=end pod

print "Establishing back links... ";
TZ-LINK-FILE.spurt: ""; # clear old
for TZ-BACK-FILE.IO.lines -> $line {
    next unless $line ~~ /^Link \h+ $<new>=<[a..zA..Z0..9/_-]>+ \h+ $<old>=<[a..zA..Z0..9/_-]>+/;
    print "\rEstablishing back links... $b","($<old>)$x \x001b[K";
    TZ-LINK-FILE.spurt: "$<old>\n$<new>\n", :append;
}
say "\rEstablishing back links... ", $g, "OK", $x, "\x001b[K";



=begin pod
Each TZif file must be included in the C<META6.json> file, and since
the files aren't static, we just generate the entire document inside
of this script.  It isn't smart enough to properly adjust the version
information, but if it detects a situation wherein that's necessary,
it will alert the user at the end of execution.
=end pod

print "Creating new META6.json file... ";

use META6;
my @files;

sub get-contents(IO() $folder) {
    my @result;
    for $folder.dir.grep(none *.starts-with('.')) -> IO $item {
        if $item.d {
            for get-contents($item).grep(none *.starts-with('.')) -> $sub-item {
                push @result, ($item.basename ~ '/' ~ $sub-item);
            }
        }else{
            push @result, $item.basename
        }
    }
    @result;
}

my @resources = get-contents(TZif-DIR).map('TZif/' ~ *).grep(none /DS_Store/);
@resources.push('links');
@resources.push('zones');
@resources.push('posix-max');
@resources.push('posix-min');

my $meta6 = META6.new(
        name         => <Timezones::ZoneInfo>,
        description  => 'A module providing timezone data and routines, based on IANA’s tz database and code',
        version      => Version.new($module-version),
        perl-version => Version.new('6.*'),
        raku-version => Version.new('6.*'),
        test-depends => <Test>,
        depends      => [],
        resources    => @resources,
        tags         => <timezones olson tz tzdb>,
        authors      => ['Matthew Stephen STUCKWISCH <mateu@softastur.org>'],
        auth         => 'zef:guifa',
        source-url   => 'git://github.com/alabamenhu/TimezonesZoneInfo.git',
        support      => META6::Support.new(
            source => 'git://github.com/alabamenhu/TimezonesZoneInfo.git'
        ),
        provides => {
            'CX::Warn::Timezones::UnknownID' => 'lib/CX/Warn/Timezones/UnknownID.rakumod',
            'Timezones::ZoneInfo' => 'lib/Timezones/ZoneInfo.rakumod',
            'Timezones::ZoneInfo::ConvRule' => 'lib/Timezones/ZoneInfo/ConvRule.rakumod',
            'Timezones::ZoneInfo::LeapSecInfo' => 'lib/Timezones/ZoneInfo/LeapSecInfo.rakumod',
            'Timezones::ZoneInfo::Link' => 'lib/Timezones/ZoneInfo/Link.rakumod',
            'Timezones::ZoneInfo::Routines' => 'lib/Timezones/ZoneInfo/Routines.rakumod',
            'Timezones::ZoneInfo::State' => 'lib/Timezones/ZoneInfo/State.rakumod',
            'Timezones::ZoneInfo::Time' => 'lib/Timezones/ZoneInfo/Time.rakumod',
            'Timezones::ZoneInfo::TransTimeInfo' => 'lib/Timezones/ZoneInfo/TransTimeInfo.rakumod',
        },
        license     => 'CC0-1.0',
);

META6-FILE.IO.spurt: $meta6.to-json(:sorted-keys);
say $g, "OK", $x;

# Need to grab this before we clean up files.  No real logical place to put it flow wise.
my $new-version = TZ-DATA-DIR.IO.add("version").resolve.slurp.chomp;

=begin pod
Cleaning up after ourselves also means that no one will ever
pollute GitHub with all of our intermediate files (something I've
I<never> done, of course.
=end pod

print "Cleaning up files... ";
TZ-CODE-DL.IO.unlink;
TZ-DATA-DL.IO.unlink;
TZ-ZIC-EXE.IO.unlink;
.unlink for TZ-DATA-DIR.IO.dir.grep(*.basename ∈ TZ-ZIC-FILES | TZ-ZONE-FILES | 'leapseconds' | 'backward' );
say $g, "OK", $x, "\n";

=begin pod
The final step of the update is to compare the old and new versions.
If the just-installed version is newer, then it's imperative that an
incremental update be published.  Otherwise,
=end pod

my $old-version = VERSION-FILE.IO.slurp.chomp;
VERSION-FILE.IO.spurt: $new-version;

say "Please note the follow version update information:";
say $tall1, "  $old-version -> {$g if $old-version cmp $new-version == Less}$new-version$x";
say $tall2, "  $old-version -> {$g if $old-version cmp $new-version == Less}$new-version$x";
say $wide, "   old      new{"\x001b[5m?\x001b[0m" if $old-version cmp $new-version == More}";

say do given $old-version cmp $new-version {
    when Same {
              ~ "Because the version information is the same, \n"
              ~ "you do \x001b[1mnot\x001b[0m need to update the version unless \n"
              ~ "you have made additional changes to the module."
              }
    when Less {
              ~ "Because the TZ database has been updated, unless there\n"
              ~ "are blocking changes, you should increment the module\n"
              ~ "version number and release \x001b[1mas soon as possible\x001b[0m."
              }
    when More {
              ~ "So... this is weird.  Somehow you must have had exclusive \n"
              ~ "preview access to an upcoming TZ data release, because \n"
              ~ "the latest version number has \x001b[1mdowngraded\x001b[0m you.\n"
              ~ "Not really sure what I can do for you…  ¯\\_(ツ)_/¯";
              }
}
say "";
exit;

# need to create the file
# gcc -Wall zic.c -o ../bin/zic



CATCH {

  #when X::LibCurl {
  #    say "$_.Int() : $_";
  #    #say $curl.response-code;
  #    #say $curl.error;
  #}



  default {
    .say
  }
}


multi sub header(1) {
    my $text = q:to/END/
████████╗██╗███╗   ███╗███████╗███████╗ ██████╗ ███╗   ██╗███████╗
╚══██╔══╝██║████╗ ████║██╔════╝╚══███╔╝██╔═══██╗████╗  ██║██╔════╝
   ██║   ██║██╔████╔██║█████╗    ███╔╝ ██║   ██║██╔██╗ ██║█████╗
   ██║   ██║██║╚██╔╝██║██╔══╝   ███╔╝  ██║   ██║██║╚██╗██║██╔══╝
   ██║   ██║██║ ╚═╝ ██║███████╗███████╗╚██████╔╝██║ ╚████║███████╗
   ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
        ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗██████╗
        ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔══██╗
XXXXXXXX██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ██████╔╝
        ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ██╔══██╗
        ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗██║  ██║
         ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
END
;

    my $foreground = "\x001b[34;1m";
    my $background = "\x001b[36m";
    my $result = "";
    my $current = "\n\x001b[0;0f\x001b[0J";
    for $text.comb -> $letter {
        if $letter eq "█" {
            $result ~= $foreground if $current ne "fore";
            $current = "fore";
        }else{
            $result ~= $background if $current ne "back";
            $current = "back";
        }
        $result ~= $letter;
    }
    $result ~= $x;
    $result.subst:
        'XXXXXXXX',
        $x ~ do given $updater-version.chars {
            when 1 { "   v$updater-version   " }
            when 2 { "  v.$updater-version  " }
            when 3 { "  v$updater-version  " }
            when 4 { " v.$updater-version " }
            when 5 { " v$updater-version " }
            when 6 { "v.$updater-version" }
        }
}

multi sub header (2) {
    #~ "\x001b[2J"
    "\n"
    ~ "\x001b[0;0f\x001b[0J"
    ~ $tall1 ~ "\x001b[1mTimezone Updater\n"
    ~ $tall2 ~ "Timezone Updater\x001b[0m\n"
    ~ "  Version $updater-version\n"
}