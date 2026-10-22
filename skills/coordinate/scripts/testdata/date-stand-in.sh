# date-stand-in.sh -- a clock the coordinate engine suites can move forward,
# for coordinate-engine-lib.sh (the quiet case) and
# reconcile-pass_engine_test.sh (the listing re-read). Sourced by a suite after
# it sets T (its scratch directory). Not shipped behaviour.
#
#   set_clock <seconds>   write $T/bin/date, which reads <seconds> later than
#                         the real clock
#   clear_clock           remove it, putting the real clock back
#
# The suite puts $T/bin first on PATH itself, before koto starts, so the
# commands koto runs see the stand-in. It is there only while a clock is set,
# so every other `date` is the real one and starts no shell. REAL_DATE is the
# date on PATH when this file is sourced. GNU date reads an epoch as `-d @N`,
# BSD date (macOS) as `-r N`, so the stand-in is written with whichever this
# host's date takes, and a call that names its own time (-d, --date, -r,
# --reference) goes to the real date unchanged.
#
# Two things to know while a clock is set:
#   - every plain `date` call reads ahead, not only the script under test's,
#     so timestamps anything writes in that window are ahead too;
#   - on BSD a call that names its time with a flag other than -d or -r (a
#     `date -j -f` parse, say) gets the epoch flag added and breaks. None of
#     the scripts these suites run parses dates that way today.

REAL_DATE=$(command -v date)
if "$REAL_DATE" -d @0 +%s >/dev/null 2>&1; then AT_FLAG=-d AT_PREFIX=@; else AT_FLAG=-r AT_PREFIX=; fi
mkdir -p "$T/bin"
set_clock() { # set_clock <seconds>
    cat > "$T/bin/date" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in -d*|--date*|-r*|--reference*) exec "$REAL_DATE" "\$@" ;; esac; done
exec "$REAL_DATE" $AT_FLAG "$AT_PREFIX\$(( \$("$REAL_DATE" +%s) + $1 ))" "\$@"
EOF
    chmod +x "$T/bin/date"
    hash -r
}
clear_clock() { rm -f "$T/bin/date"; hash -r; }
