#!/usr/bin/env bash
set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

# Tests for rule-lifecycle.sh, the reference reader for the check lifecycle's
# figures.
#
# Every case runs against a small test registry and journal fixtures written
# here, in koto's flat line format, by awk loops into this suite's own scratch
# directory. Each threshold boundary has a fixture just below the bound and
# one exactly at it, and only the one at the bound meets its criterion. Every
# rule's stage_since is 2026-01-01, and a fixture sets its window's length
# with the date of its newest line.
#
# Needs bash, jq and awk. No network.
#
# Usage:
#   bash scripts/rule-lifecycle_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/rule-lifecycle.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/rule-lifecycle-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P)
cleanup() { chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; return 0; }
ktg_on_exit cleanup

REG="$T/registry.json"
cat >"$REG" <<'EOF'
{"schema":"shirabe-rule-registry/v1","rules":[
 {"id":"t/shadow","status":"active","summary":"Shadow","check":{"kind":"script","path":"scripts/x.sh"},"stage":"shadow","stage_since":"2026-01-01","gates":["demo:s_shadow:g"]},
 {"id":"t/warn","status":"active","summary":"Warn","check":{"kind":"script","path":"scripts/x.sh"},"stage":"warn","stage_since":"2026-01-01","gates":["demo:s_warn:g"]},
 {"id":"t/block","status":"active","summary":"Block","check":{"kind":"script","path":"scripts/x.sh"},"stage":"block","stage_since":"2026-01-01","gates":["demo:s_block:g"]},
 {"id":"t/other","status":"active","summary":"Other","check":{"kind":"script","path":"scripts/x.sh"},"stage":"block","stage_since":"2026-01-01","gates":["demo:s_other:g"]},
 {"id":"t/two","status":"active","summary":"Two gates","check":{"kind":"script","path":"scripts/x.sh"},"stage":"block","stage_since":"2026-01-01","gates":["demo:s_two:a","other:s_two:b"]},
 {"id":"t/gone","status":"retired","summary":"Gone","check":{"kind":"script","path":"scripts/x.sh"},"stage":"retired","stage_since":"2026-01-01","gates":["demo:s_gone:g"]},
 {"id":"t/nostage","status":"active","summary":"No stage","check":{"kind":"script","path":"scripts/x.sh"},"gates":["demo:s_nostage:g"]},
 {"id":"rs-1","status":"active","summary":"Review shadow","text":{"path":"r.md","first":"x"}}
]}
EOF

# Dates as offsets from stage_since (2026-01-01).
D0=2026-01-01
D3=2026-01-04
D6=2026-01-07
D7=2026-01-08
D13=2026-01-14
D14=2026-01-15
D55=2026-02-25
D56=2026-02-26
BEFORE=2025-12-31

# evals <state> <gate> <n> <fires> <level> <date> <session-prefix> [<rule> [<flags>]]
# n check_evaluated lines, each its own session at seq 1 and visit 1; the
# first <fires> of them fail with one check_finding for <rule> at <level>.
# <flags>: "trunc" marks every evaluation truncated, "nofc" leaves out
# koto.check.finding_count.
evals() {
    awk -v st="$1" -v g="$2" -v n="$3" -v k="$4" -v lv="$5" -v d="$6" -v sp="$7" \
        -v rule="${8:-}" -v flags="${9:-}" 'BEGIN {
        tr = (flags ~ /trunc/) ? "true" : "false"
        for (i = 1; i <= n; i++) {
            out = (i <= k) ? "failed" : "passed"
            fc = (flags ~ /nofc/) ? "" : sprintf(",\"koto.check.finding_count\":%d,\"koto.check.findings_truncated\":%s", (i <= k) ? 1 : 0, tr)
            printf "{\"kind\":\"check_evaluated\",\"v\":1,\"at\":\"%sT10:00:00.000Z\",\"koto.session.id\":\"%s-%d\",\"koto.seq\":1,\"koto.visit.seq\":1,\"koto.state\":\"%s\",\"koto.check\":\"%s\",\"koto.check.outcome\":\"%s\"%s}\n", d, sp, i, st, g, out, fc
            if (i <= k)
                printf "{\"kind\":\"check_finding\",\"v\":1,\"at\":\"%sT10:00:00.000Z\",\"koto.session.id\":\"%s-%d\",\"koto.seq\":1,\"koto.visit.seq\":1,\"koto.state\":\"%s\",\"koto.check.name\":\"%s\",\"koto.rule.id\":\"%s\",\"koto.finding.level\":\"%s\",\"koto.finding.count\":1,\"koto.attempt\":1,\"koto.visit_attempt\":1}\n", d, sp, i, st, g, rule, lv
        }
    }'
}

# disputes <state> <gate> <rule> <n> <source> <date> <session-prefix>
# n check_disputed lines, each from its own session.
disputes() {
    awk -v st="$1" -v g="$2" -v rule="$3" -v n="$4" -v src="$5" -v d="$6" -v sp="$7" 'BEGIN {
        for (i = 1; i <= n; i++)
            printf "{\"kind\":\"check_disputed\",\"v\":1,\"at\":\"%sT11:00:00.000Z\",\"koto.session.id\":\"%s-%d\",\"koto.state\":\"%s\",\"koto.check.name\":\"%s\",\"koto.rule.id\":\"%s\",\"koto.dispute.source\":\"%s\",\"koto.attempt\":1,\"koto.visit_attempt\":1}\n", d, sp, i, st, g, rule, src
    }'
}

# endline <date>: a line of another kind, for no rule, that sets the window's end.
endline() {
    printf '{"kind":"state_entered","v":1,"at":"%sT12:00:00.000Z","koto.session.id":"end","koto.state":"elsewhere"}\n' "$1"
}

# row <journal> <rule>: the rule's tab-separated line, read against $RREG
# (the test registry unless a section sets another).
RREG=$REG
row() {
    bash "$SUT" --registry "$RREG" figures "$1" 2>/dev/null | awk -F'\t' -v r="$2" '$1 == r'
}
TAB=$(printf '\t')
tsv() { local IFS="$TAB"; echo "$*"; }

expect_row() {
    local name=$1 file=$2 rule=$3 want got
    shift 3
    want=$(tsv "$@")
    got=$(row "$file" "$rule")
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name" "want [$want] got [$got]"; fi
}

expect_crit() {
    local name=$1 file=$2 rule=$3 want=$4 got
    got=$(row "$file" "$rule" | awk -F'\t' '{print $12}')
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name" "want $want got [$got]"; fi
}

J="$T/j"
mkdir "$J"

# -- one rule per criterion, and one meeting none, with every value --------

{ evals s_block g 100 10 error $D0 dem t/block
  disputes s_block g t/block 2 agent $D0 dema
  disputes s_block g t/block 1 person $D0 demp
  endline $D7; } >"$J/demote"
expect_row "demote: every figure" "$J/demote" t/block \
    t/block block 7 100 10 0 0 90 2 1 10 demote

{ evals s_shadow g 300 0 info $D0 ret t/shadow; endline $D56; } >"$J/retire"
expect_row "retire: every figure" "$J/retire" t/shadow \
    t/shadow shadow 56 300 0 0 0 300 0 0 0 retire

{ evals s_shadow g 100 25 info $D0 ptw t/shadow; endline $D14; } >"$J/p2w"
expect_row "promote to warn: every figure" "$J/p2w" t/shadow \
    t/shadow shadow 14 100 0 0 25 75 0 0 0 promote-to-warn

{ evals s_warn g 100 5 warning $D0 ptb t/warn
  disputes s_warn g t/warn 0 agent $D0 ptbd
  endline $D14; } >"$J/p2b"
expect_row "promote to block: every figure" "$J/p2b" t/warn \
    t/warn warn 14 100 0 5 0 95 0 0 0 promote-to-block

{ evals s_block g 50 2 error $D0 hold t/block; endline $D3; } >"$J/hold"
expect_row "a rule meeting none holds" "$J/hold" t/block \
    t/block block 3 50 2 0 0 48 0 0 2 hold

# -- promote to warn boundaries ---------------------------------------------

{ evals s_shadow g 99 1 info $D0 a t/shadow; endline $D14; } >"$J/p2w-e99"
{ evals s_shadow g 100 1 info $D0 a t/shadow; endline $D14; } >"$J/p2w-e100"
expect_crit "promote to warn: 99 evaluations hold" "$J/p2w-e99" t/shadow hold
expect_crit "promote to warn: 100 evaluations meet it" "$J/p2w-e100" t/shadow promote-to-warn

{ evals s_shadow g 100 1 info $D0 a t/shadow; endline $D13; } >"$J/p2w-d13"
expect_crit "promote to warn: 13 days hold" "$J/p2w-d13" t/shadow hold
expect_crit "promote to warn: 14 days meet it" "$J/p2w-e100" t/shadow promote-to-warn

{ evals s_shadow g 100 26 info $D0 a t/shadow; endline $D14; } >"$J/p2w-f26"
expect_crit "promote to warn: 26% fires hold" "$J/p2w-f26" t/shadow hold
expect_crit "promote to warn: 25% fires meet it" "$J/p2w" t/shadow promote-to-warn

{ evals s_shadow g 100 0 info $D0 a t/shadow; endline $D14; } >"$J/p2w-f0"
expect_crit "promote to warn: no fire holds" "$J/p2w-f0" t/shadow hold

# -- promote to block boundaries --------------------------------------------

{ evals s_warn g 99 5 warning $D0 a t/warn; endline $D14; } >"$J/p2b-e99"
{ evals s_warn g 100 5 warning $D0 a t/warn; endline $D14; } >"$J/p2b-e100"
expect_crit "promote to block: 99 evaluations hold" "$J/p2b-e99" t/warn hold
expect_crit "promote to block: 100 evaluations meet it" "$J/p2b-e100" t/warn promote-to-block

{ evals s_warn g 100 5 warning $D0 a t/warn; endline $D13; } >"$J/p2b-d13"
expect_crit "promote to block: 13 days hold" "$J/p2b-d13" t/warn hold
expect_crit "promote to block: 14 days meet it" "$J/p2b-e100" t/warn promote-to-block

{ evals s_warn g 100 4 warning $D0 a t/warn; endline $D14; } >"$J/p2b-f4"
expect_crit "promote to block: 4 fires hold" "$J/p2b-f4" t/warn hold
expect_crit "promote to block: 5 fires meet it" "$J/p2b-e100" t/warn promote-to-block

{ evals s_warn g 100 100 warning $D0 a t/warn
  disputes s_warn g t/warn 6 agent $D0 d; endline $D14; } >"$J/p2b-x6"
{ evals s_warn g 100 100 warning $D0 a t/warn
  disputes s_warn g t/warn 5 person $D0 d; endline $D14; } >"$J/p2b-x5"
expect_crit "promote to block: disputes at 6% of fires hold" "$J/p2b-x6" t/warn hold
expect_crit "promote to block: disputes at 5% of fires meet it" "$J/p2b-x5" t/warn promote-to-block

# -- demote boundaries ------------------------------------------------------

{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 2 agent $D0 d; endline $D7; } >"$J/dem-x2"
{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 3 agent $D0 d; endline $D7; } >"$J/dem-x3"
expect_crit "demote: 2 disputes hold" "$J/dem-x2" t/block hold
expect_crit "demote: 3 disputes meet it" "$J/dem-x3" t/block demote

{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 3 agent $D0 d; endline $D6; } >"$J/dem-d6"
expect_crit "demote: 6 days hold" "$J/dem-d6" t/block hold
expect_crit "demote: 7 days meet it" "$J/dem-x3" t/block demote

{ evals s_block g 100 100 error $D0 a t/block
  disputes s_block g t/block 20 agent $D0 d; endline $D7; } >"$J/dem-p20"
{ evals s_block g 100 100 error $D0 a t/block
  disputes s_block g t/block 21 agent $D0 d; endline $D7; } >"$J/dem-p21"
expect_crit "demote: disputes at 20% of fires hold" "$J/dem-p20" t/block hold
expect_crit "demote: disputes at 21% of fires meet it" "$J/dem-p21" t/block demote

# Disputes and no fires: a zero denominator meets nothing.
{ evals s_block g 10 0 error $D0 a t/block
  disputes s_block g t/block 5 agent $D0 d; endline $D7; } >"$J/dem-f0"
expect_crit "demote: disputes with no fires hold" "$J/dem-f0" t/block hold

# -- retire boundaries ------------------------------------------------------

{ evals s_shadow g 299 0 info $D0 a t/shadow; endline $D56; } >"$J/ret-e299"
expect_crit "retire: 299 evaluations hold" "$J/ret-e299" t/shadow hold
expect_crit "retire: 300 evaluations meet it" "$J/retire" t/shadow retire

{ evals s_shadow g 300 0 info $D0 a t/shadow; endline $D55; } >"$J/ret-d55"
expect_crit "retire: 55 days hold" "$J/ret-d55" t/shadow hold
expect_crit "retire: 56 days meet it" "$J/retire" t/shadow retire

{ evals s_block g 300 0 error $D0 a t/block; endline $D56; } >"$J/ret-block"
expect_crit "retire applies at block" "$J/ret-block" t/block retire
{ evals s_warn g 300 0 warning $D0 a t/warn; endline $D56; } >"$J/ret-warn"
expect_crit "retire applies at warn" "$J/ret-warn" t/warn retire
{ evals s_shadow g 300 1 info $D0 a t/shadow; endline $D56; } >"$J/ret-f1"
expect_crit "retire: one fire holds it back" "$J/ret-f1" t/shadow promote-to-warn

# -- zero evaluations -------------------------------------------------------

endline $D56 >"$J/zero"
expect_row "zero evaluations hold" "$J/zero" t/shadow \
    t/shadow shadow 56 0 0 0 0 0 0 0 0 hold
: >"$J/empty"
out=$(bash "$SUT" --registry "$REG" figures "$J/empty" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "t/shadow"')" = "$(tsv t/shadow shadow 0 0 0 0 0 0 0 0 0 hold)" ]; then
    pass "an empty journal exits 0 and holds"
else
    fail "an empty journal exits 0 and holds" "rc=$rc out=[$out]"
fi

# -- order, window end ------------------------------------------------------

# At warn, 100 evaluations over 14 days, 10 fires and 3 disputes: promote to
# block's evaluation and day minimums hold, and demote comes first. No figures
# meet two criteria outright (the reader's header says why), so this pins the
# answer where demote and promote to block's minimums overlap; it can't tell
# a reversed order from the table's.
{ evals s_warn g 100 10 warning $D0 a t/warn
  disputes s_warn g t/warn 3 agent $D0 d; endline $D14; } >"$J/order"
expect_crit "demote is reported before promote to block" "$J/order" t/warn demote

# The window ends at the newest line, even one for another rule.
{ evals s_shadow g 100 1 info $D0 a t/shadow
  evals s_other g 1 0 error $D14 o t/other; } >"$J/end-other"
expect_crit "the window ends at another rule's newest line" "$J/end-other" t/shadow promote-to-warn
expect_row "the other rule's own figures" "$J/end-other" t/other \
    t/other block 14 1 0 0 0 1 0 0 0 hold

# -- what counts ------------------------------------------------------------

# Records before stage_since: 50 evaluations, all firing, would make it 34%.
{ evals s_shadow g 50 50 info $BEFORE b t/shadow
  disputes s_shadow g t/shadow 4 agent $BEFORE bd
  evals s_shadow g 100 1 info $D0 a t/shadow; endline $D14; } >"$J/since"
expect_row "records before stage_since don't count" "$J/since" t/shadow \
    t/shadow shadow 14 100 0 0 1 99 0 0 0 promote-to-warn

# Evaluations without koto.check.finding_count (an older koto).
{ evals s_shadow g 100 1 info $D0 a t/shadow
  evals s_shadow g 50 50 info $D0 old t/shadow nofc; endline $D14; } >"$J/nofc"
expect_row "evaluations without a finding count don't count" "$J/nofc" t/shadow \
    t/shadow shadow 14 100 0 0 1 99 0 0 0 promote-to-warn

# Truncated evaluations leave the retire count, not the evaluation count.
{ evals s_shadow g 299 0 info $D0 a t/shadow
  evals s_shadow g 1 0 info $D0 cut t/shadow trunc; endline $D56; } >"$J/trunc"
expect_row "a truncated evaluation leaves the retire count" "$J/trunc" t/shadow \
    t/shadow shadow 56 300 0 0 0 300 0 0 0 hold
{ evals s_shadow g 300 0 info $D0 a t/shadow
  evals s_shadow g 1 0 info $D0 cut t/shadow trunc; endline $D56; } >"$J/trunc-301"
expect_crit "300 untruncated evaluations retire" "$J/trunc-301" t/shadow retire

# A finding at a gate not among the rule's gates: an evaluation of another
# rule's gate with a finding citing t/shadow, and a finding at the same
# session and seq as a t/shadow evaluation but naming another gate.
{ evals s_shadow g 300 0 info $D0 a t/shadow
  evals s_other g 1 1 error $D0 x t/shadow
  printf '{"kind":"check_finding","v":1,"at":"%sT10:00:00.000Z","koto.session.id":"a-1","koto.seq":1,"koto.visit.seq":1,"koto.state":"s_shadow","koto.check.name":"h","koto.rule.id":"t/shadow","koto.finding.level":"info","koto.finding.count":1,"koto.attempt":1,"koto.visit_attempt":1}\n' $D0
  endline $D56; } >"$J/foreign"
expect_row "a finding at another gate doesn't count" "$J/foreign" t/shadow \
    t/shadow shadow 56 300 0 0 0 300 0 0 0 retire
expect_row "nor for the gate's own rule" "$J/foreign" t/other \
    t/other block 56 1 0 0 0 1 0 0 0 hold

# A dispute at another gate doesn't count either.
{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 2 agent $D0 d
  disputes s_other g t/block 1 agent $D0 e; endline $D7; } >"$J/disp-foreign"
expect_crit "a dispute at another gate doesn't count" "$J/disp-foreign" t/block hold

# One session disputing twice counts once.
{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 2 agent $D0 d
  disputes s_block g t/block 1 person $D0 d; endline $D7; } >"$J/disp-twice"
expect_row "one session disputing twice counts once" "$J/disp-twice" t/block \
    t/block block 7 100 5 0 0 95 2 0 5 hold
{ cat "$J/disp-twice"; disputes s_block g t/block 1 person $D0 p; } >"$J/disp-third"
expect_row "a third session's dispute demotes" "$J/disp-third" t/block \
    t/block block 7 100 5 0 0 95 2 1 5 demote

# The session's earliest dispute is the one kept, whatever the line order:
# the agent's line comes first in the file and is three days later.
{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 1 agent $D3 q
  disputes s_block g t/block 1 person $D0 q; endline $D7; } >"$J/disp-earliest"
expect_row "a session's earliest dispute is the one kept" "$J/disp-earliest" t/block \
    t/block block 7 100 5 0 0 95 0 1 5 hold

# Only agent and person count, and a dispute with no session id is skipped.
{ evals s_block g 100 5 error $D0 a t/block
  disputes s_block g t/block 3 bot $D0 b
  disputes s_block g t/block 2 agent $D0 d
  printf '{"kind":"check_disputed","v":1,"at":"%sT11:00:00.000Z","koto.state":"s_block","koto.check.name":"g","koto.rule.id":"t/block","koto.dispute.source":"agent"}\n' $D0
  endline $D7; } >"$J/disp-source"
expect_row "another source and a dispute with no session don't count" "$J/disp-source" t/block \
    t/block block 7 100 5 0 0 95 2 0 5 hold

# A visit with two error fires and no passing evaluation is one unconverged
# visit; a visit whose gate passed after an error fire is none; a second
# check_finding level on one evaluation is one fire.
e_line() { # session seq visit state gate outcome
    printf '{"kind":"check_evaluated","v":1,"at":"%sT10:00:00.000Z","koto.session.id":"%s","koto.seq":%s,"koto.visit.seq":%s,"koto.state":"%s","koto.check":"%s","koto.check.outcome":"%s","koto.check.finding_count":1,"koto.check.findings_truncated":false}\n' $D0 "$1" "$2" "$3" "$4" "$5" "$6"
}
f_line() { # session seq visit state gate level
    printf '{"kind":"check_finding","v":1,"at":"%sT10:00:00.000Z","koto.session.id":"%s","koto.seq":%s,"koto.visit.seq":%s,"koto.state":"%s","koto.check.name":"%s","koto.rule.id":"t/two","koto.finding.level":"%s","koto.finding.count":1,"koto.attempt":1,"koto.visit_attempt":1}\n' $D0 "$1" "$2" "$3" "$4" "$5" "$6"
}
{ e_line S 1 1 s_two a failed; f_line S 1 1 s_two a error
  e_line S 2 1 s_two a failed; f_line S 2 1 s_two a error
  e_line S 3 2 s_two b failed; f_line S 3 2 s_two b error; f_line S 3 2 s_two b warning
  e_line S 4 2 s_two b passed
  e_line S 4 2 s_two b passed
  endline $D3; } >"$J/unconverged"
expect_row "two error fires in a visit that never passed: one unconverged visit" \
    "$J/unconverged" t/two t/two block 3 4 3 1 0 1 0 0 1 hold

# A pass of the rule's other gate in the same visit doesn't converge it, and a
# level other than error, warning or info counts as a fire in no column.
{ e_line V 1 1 s_two a failed; f_line V 1 1 s_two a error
  e_line V 2 1 s_two b passed
  e_line V 3 2 s_two b failed; f_line V 3 2 s_two b notice
  endline $D3; } >"$J/other-gate"
expect_row "another gate's pass leaves the visit unconverged; an odd level is a fire" \
    "$J/other-gate" t/two t/two block 3 3 1 0 0 1 0 0 1 hold

# -- each criterion applies only at its stages ------------------------------

# Copies of the criterion fixtures, moved to a stage the criterion skips.
for pair in "p2w:s_shadow:s_warn:t/shadow:t/warn" "p2w:s_shadow:s_block:t/shadow:t/block" \
            "p2b:s_warn:s_shadow:t/warn:t/shadow" "p2b:s_warn:s_block:t/warn:t/block" \
            "demote:s_block:s_shadow:t/block:t/shadow"; do
    IFS=: read -r src from to old new <<EOF
$pair
EOF
    sed -e "s/\"$from\"/\"$to\"/g" -e "s#\"$old\"#\"$new\"#g" "$J/$src" >"$J/stage-$src-$to"
done
# At warn the same figures meet promote to block, which comes after it.
expect_crit "promote to warn doesn't apply at warn" "$J/stage-p2w-s_warn" t/warn promote-to-block
expect_crit "promote to warn doesn't apply at block" "$J/stage-p2w-s_block" t/block hold
expect_crit "promote to block doesn't apply at shadow" "$J/stage-p2b-s_shadow" t/shadow promote-to-warn
expect_crit "promote to block doesn't apply at block" "$J/stage-p2b-s_block" t/block hold
expect_crit "demote doesn't apply at shadow" "$J/stage-demote-s_shadow" t/shadow hold
# t/two has two gates; retire's figures at one of them retire it.
{ evals s_two a 300 0 error $D0 a t/two; endline $D56; } >"$J/ret-two"
expect_crit "retire's figures at one of two gates" "$J/ret-two" t/two retire
{ evals s_gone g 300 0 error $D0 a t/gone; endline $D56; } >"$J/ret-gone"
expect_crit "nothing applies at retired" "$J/ret-gone" t/gone hold

# A rule with no stage_since counts nothing, even with data at its gate.
{ evals s_nostage g 300 0 error $D0 a t/nostage; endline $D56; } >"$J/nosince"
expect_row "no stage_since: no window, even with data" "$J/nosince" t/nostage \
    t/nostage block 0 0 0 0 0 0 0 0 0 hold

# An object with no dated `at` is skipped, and doesn't move the window's end.
{ cat "$J/p2w-d13"
  printf '{"kind":"state_entered","at":"yesterday","koto.session.id":"x"}\n'
  printf '{"kind":"state_entered","koto.session.id":"x"}\n'; } >"$J/undated"
expect_crit "an undated line is skipped" "$J/undated" t/shadow hold

# -- panel/open-finding counts every finding at the panel gates --------------

# panel-scope.sh --verdict prints a reviewer finding that cites an active rule
# under the cited rule's id, at a panel gate and at panel/open-finding's stage,
# and an agent disputes it with the cited id. At panel/open-finding's gates a
# finding or a dispute counts for it whatever rule id it carries, and never
# for the rule it cites, whose own findings at its own gate still count.
PREG="$T/panel-registry.json"
cat >"$PREG" <<'EOF'
{"schema":"shirabe-rule-registry/v1","rules":[
 {"id":"panel/open-finding","status":"active","summary":"Open finding","check":{"kind":"script","path":"scripts/p.sh"},"stage":"block","stage_since":"2026-01-01","gates":["demo:s_panel:v"]},
 {"id":"t/cited","status":"active","summary":"Cited","check":{"kind":"script","path":"scripts/x.sh"},"stage":"block","stage_since":"2026-01-01","gates":["demo:s_cited:g"]}
]}
EOF
RREG=$PREG

{ evals s_panel v 10 3 error $D0 p t/cited
  evals s_panel v 2 2 error $D0 q panel/open-finding
  evals s_cited g 5 1 error $D0 c t/cited
  endline $D3; } >"$J/panel-cites"
expect_row "a panel finding citing another rule fires for panel/open-finding" \
    "$J/panel-cites" panel/open-finding panel/open-finding block 3 12 5 0 0 7 0 0 5 hold
expect_row "a panel finding doesn't fire for the rule it cites" \
    "$J/panel-cites" t/cited t/cited block 3 5 1 0 0 4 0 0 1 hold

{ evals s_panel v 10 3 error $D0 p t/cited
  disputes s_panel v t/cited 2 agent $D0 pd
  disputes s_panel v panel/open-finding 1 person $D0 pp
  evals s_cited g 5 1 error $D0 c t/cited
  endline $D3; } >"$J/panel-disputes"
expect_row "a panel dispute citing another rule counts for panel/open-finding" \
    "$J/panel-disputes" panel/open-finding panel/open-finding block 3 10 3 0 0 7 2 1 3 hold
expect_row "a panel dispute doesn't count for the rule it cites" \
    "$J/panel-disputes" t/cited t/cited block 3 5 1 0 0 4 0 0 1 hold

RREG=$REG

# -- registry shapes --------------------------------------------------------

out=$(bash "$SUT" --registry "$REG" figures "$J/zero")
ids=$(printf '%s\n' "$out" | awk -F'\t' '{print $1}' | tr '\n' ' ')
if [ "$ids" = "t/shadow t/warn t/block t/other t/two t/gone t/nostage " ]; then
    pass "one line per script-checked rule, in registry order"
else
    fail "one line per script-checked rule, in registry order" "got [$ids]"
fi
expect_row "a retired entry holds" "$J/zero" t/gone t/gone retired 56 0 0 0 0 0 0 0 0 hold
expect_row "an entry with no stage shows block" "$J/zero" t/nostage t/nostage block 0 0 0 0 0 0 0 0 0 hold

# -- --json, standard input and several files --------------------------------

{ cat "$J/demote" "$J/unconverged" "$J/p2w"; } >"$J/all"
tsv_out=$(bash "$SUT" --registry "$REG" figures "$J/all")
json_out=$(bash "$SUT" --registry "$REG" figures --json "$J/all")
from_json=$(printf '%s\n' "$json_out" | jq -r '[.id, .stage, .days, .evaluations, .fires_error, .fires_warning, .fires_info, .passes, .disputes_agent, .disputes_person, .unconverged, .criterion] | @tsv')
nobj=$(printf '%s\n' "$json_out" | jq -s 'length')
if [ "$tsv_out" = "$from_json" ] && [ "$nobj" = 7 ]; then
    pass "--json prints one object per rule with the same values"
else
    fail "--json prints one object per rule with the same values" "tsv=[$tsv_out] json=[$json_out]"
fi
first_json=${json_out%%$'\n'*}
keys=$(jq -c 'keys_unsorted' <<<"$first_json")
if [ "$keys" = '["id","stage","days","evaluations","fires_error","fires_warning","fires_info","passes","disputes_agent","disputes_person","unconverged","criterion"]' ]; then
    pass "--json keys match the columns"
else
    fail "--json keys match the columns" "got $keys"
fi
if printf '%s\n' "$json_out" | jq -s -e 'all(.[];
        ([.id, .stage, .criterion] | all(type == "string"))
        and ([.days, .evaluations, .fires_error, .fires_warning, .fires_info, .passes,
              .disputes_agent, .disputes_person, .unconverged] | all(type == "number")))' >/dev/null; then
    pass "--json counts are numbers, names are strings"
else
    fail "--json counts are numbers, names are strings" "got [$json_out]"
fi

stdin_out=$(bash "$SUT" --registry "$REG" figures <"$J/all")
files_out=$(bash "$SUT" --registry "$REG" figures "$J/demote" "$J/unconverged" "$J/p2w")
if [ "$stdin_out" = "$tsv_out" ] && [ "$files_out" = "$tsv_out" ]; then
    pass "standard input, several files and one concatenated file agree"
else
    fail "standard input, several files and one concatenated file agree" "stdin=[$stdin_out] files=[$files_out]"
fi

# A line that isn't JSON is skipped.
{ echo 'not json'; cat "$J/p2w"; echo '[1,2]'; } >"$J/noise"
expect_crit "a line that isn't a JSON object is skipped" "$J/noise" t/shadow promote-to-warn

# -- read-only inputs, unreadable inputs ------------------------------------

RO="$T/ro"
mkdir "$RO"
cp "$REG" "$RO/registry.json"
cp "$J/demote" "$RO/journal"
chmod 444 "$RO/registry.json" "$RO/journal"
chmod 555 "$RO"
snap() { (cd "$RO" && ls -la . && cksum registry.json journal); }
before=$(snap)
out=$(cd "$RO" && bash "$SUT" --registry registry.json figures journal 2>&1); rc=$?
after=$(snap)
if [ $rc -eq 0 ] && [ "$before" = "$after" ] && grep -q "^t/block${TAB}block${TAB}7${TAB}" <<<"$out"; then
    pass "a read-only directory: prints, creates and modifies nothing"
else
    fail "a read-only directory: prints, creates and modifies nothing" "rc=$rc out=[$out]"
fi
chmod 755 "$RO"

expect_exit() {
    local name=$1 want=$2 rc
    shift 2
    "$@" >/dev/null 2>&1; rc=$?
    if [ "$rc" = "$want" ]; then pass "$name"; else fail "$name" "want exit $want got $rc"; fi
}
expect_exit "a missing input exits 2" 2 bash "$SUT" --registry "$REG" figures "$J/nope"
expect_exit "a directory as input exits 2" 2 bash "$SUT" --registry "$REG" figures "$J"
expect_exit "a missing registry exits 2" 2 bash "$SUT" --registry "$T/nope.json" figures "$J/zero"
echo '{"rules": 3}' >"$T/bad.json"
expect_exit "a registry that doesn't parse exits 2" 2 bash "$SUT" --registry "$T/bad.json" figures "$J/zero"
expect_exit "no command exits 2" 2 bash "$SUT" --registry "$REG"
expect_exit "an unknown option exits 2" 2 bash "$SUT" --registry "$REG" figures --bogus "$J/zero"
if [ "$(id -u)" != 0 ]; then
    cp "$J/zero" "$T/locked"; chmod 000 "$T/locked"
    expect_exit "an unreadable input exits 2" 2 bash "$SUT" --registry "$REG" figures "$J/zero" "$T/locked"
    cp "$REG" "$T/locked.json"; chmod 000 "$T/locked.json"
    expect_exit "an unreadable registry exits 2" 2 bash "$SUT" --registry "$T/locked.json" figures "$J/zero"
fi

# -- the real registry ------------------------------------------------------

REAL_N=$(jq '[.rules[] | select(.check.kind? == "script")] | length' "$SCRIPT_DIR/../references/rule-registry.json")
out=$(bash "$SUT" figures </dev/null); rc=$?
n=$(printf '%s\n' "$out" | grep -c .)
if [ $rc -eq 0 ] && [ "$n" = "$REAL_N" ]; then
    pass "the registry beside the script: one line per script entry"
else
    fail "the registry beside the script: one line per script entry" "rc=$rc lines=$n want $REAL_N"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
