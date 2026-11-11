#!/usr/bin/env bash
# brief-intake_engine_test.sh -- state-stored-set.sh --intake, the brief
# intake, and the brief-unread gap state-handover.sh names, on a real koto
# session of the shipped coordinate.md, against the testdata/gh stand-in
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md, Decision 10
# and R47). The host is acme/widgets, public unless a criterion says
# otherwise; the stand-in holds acme/secret private. Each brief is copied
# into the scratch HOME and named with --host briefs:<label> <path>. "Nothing
# written" means every record/ key but the entries byte-identical and no
# entry key added. Prints one line per criterion:
#   R47. the first intake of each testdata/brief-golden brief, each on a
#        fresh record, writes 7, 11 and 11 inferred brief rows, the lines
#        testdata/standing-rules/brief-kept.json lists, each the rule row's
#        shape, and the Run briefs row, none a heading or a sentence of an
#        excluded section, and clears brief-unread;
#   a second intake of the same digest prints and writes nothing;
#   R47. a 61-sentence brief writes 60 rows, exits 1 naming 1 line, leaves
#        brief-unread open naming it, writes nothing when run again, and a
#        pause is still written;
#   a brief at the 120-rule cap stops at it and names the rest;
#   a brief sentence a Standing row already holds isn't written again, and a
#        paraphrase is;
#   a pause-shaped brief line comes in as an inferred rule row that holds and
#        grants nothing;
#   a new digest ends the earlier digest's rows the brief no longer states,
#        and its entries tell the rows, then the ends, then the briefs row;
#   a line that fails the text check or the 400 bytes is reported and left
#        out;
#   a failed visibility read exits 2 writing nothing;
#   the brief-intake-cap design's opt-in heading: the 90-line successor
#        brief testdata/standing-rules/successor-90.md, its rules under
#        `## Standing rules`, on a record holding three of them, writes only
#        the rest and the briefs row, counts the 59 sentences outside on
#        stderr and clears brief-unread; the same lines without the heading
#        cap as today and the gap names the same count; 61 rules under the
#        heading write 60 and exit 1; an empty `## Standing rules` writes no
#        rule row and the briefs row, counting every sentence outside; the
#        brief's path in no output, row or entry, in either mode;
#   the design's Decision 2, the Run briefs-read row: a capped intake writes
#        `<label> D c/n` with its run entry, and the next intake of D starts
#        at c (the 61-sentence brief after one end, a headingless brief of
#        130 lines over several rounds, the gap's count equal to the
#        intake's); a row for another digest or another n is ignored; a new
#        digest reads whole and keeps the earlier rows it states before c; a
#        capped run that only ends writes no row; a row breaking its grammar
#        refuses every write, and --run briefs-read exits 64; the rewrite
#        under `## Standing rules` clears a capped record; the restart carry
#        (core_carry) and the rotation carry (state-open.sh --carry) keep the
#        row and the rows it went past;
#   the brief file is unchanged by every intake.
#
# niwa is never the real one: a fake in the scratch directory, first on PATH,
# answers not-dispatched, and no session id is set, so --rules reads nothing.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there for the
# session before the first koto command, or the suite stops.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/brief-intake_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
ORIG_PATH=$PATH
# test-lib.sh makes the scratch directory T, the gh DB helpers and the ok/bad
# counters. It puts testdata/ (the koto stand-in) first on PATH; this suite
# needs the real koto, so PATH is rebuilt below.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH NIWA_BIN CLAUDE_CODE_SESSION_ID NIWA_LOOKUP_SECONDS FORGE_READ_SECONDS KOTO_BIN
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME/briefs" "$T/bin" "$T/fake" "$T/kotolog"
cat > "$T/fake/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
printf '%s\n' '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"no-mapping","grant":[]}'
EOF
chmod +x "$T/fake/niwa"
PATH="$T/fake:$T/bin:$ORIG_PATH"
export PATH
# A koto that logs its arguments, then runs the real one.
REAL_KOTO=$(command -v koto)
cat > "$T/kotolog/koto" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/koto.calls"
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/kotolog/koto"

# The session, named here and nowhere else.
G=coordinate-roadmap-intake-20261101T090000Z
d=$(koto session dir "$G" 2>&1) || { echo "FAIL: koto session dir $G failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory for $G is not under $T: [$d]; no case ran"; exit 1 ;;
esac

# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
# session_seed and koto_store_ready.
. "$HERE/testdata/engine-session.sh"
# `gh` is testdata/gh.
export COORD_TESTDATA="$HERE/testdata"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
. "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"

# koto refuses a --var value outside its allowlist (a `+` in a checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
SD="$HERE/testdata/standing-rules"
GOLD="$HERE/testdata/brief-golden"
WD="$T/work"
mkdir -p "$WD"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests brief-intake-engine; exit 1; }

# ---- helpers ---------------------------------------------------------------
at() { (cd "$WD" && koto next "$1" "${@:2}" --no-cleanup 2>"$T/tick.err") | jq -r '.state // empty'; }
ctx() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
put() { (cd "$WD" && koto context add "$1" "$2" --from-file "$3"); }
# snap: the record's key list, and every key but an entry as hex bytes.
snap() {
    local k
    (cd "$WD" && koto context list "$G" --prefix record/) > "$T/snap.keys" 2>/dev/null || { echo unreadable; return; }
    cat "$T/snap.keys"
    for k in $(jq -r '.[] | select(startswith("record/entries/") | not)' "$T/snap.keys"); do
        printf '%s %s\n' "$k" "$(ctx "$G" "$k" | od -An -tx1 | tr -d ' \n')"
    done
}
# w <args...>: one state-stored-set.sh call as the run, from the repository.
w() { (cd "$WD" && bash "$PS/state-stored-set.sh" --session "$G" "$@"); }
# try <args...>: w, its exit in RC, stdout in $T/out, stderr in $T/err, and
# the forge reads it made in $T/calls (the log cleared first); NOTHING is yes
# when nothing was written.
try() {
    local before sums
    before=$(snap)
    sums=$(brief_sums)
    reset_calls
    w "$@" > "$T/out" 2> "$T/err"; RC=$?
    cp "$GH_DB.calls" "$T/calls"
    if [ "$before" = "$(snap)" ]; then NOTHING=yes; else NOTHING=no; fi
    [ "$sums" = "$(brief_sums)" ] || EDITED="$EDITED; $*"
    case "$*" in --intake*) INTAKES=$((INTAKES + 1)) ;; esac
}
# brief_sums: every brief file's path and digest; EDITED names each call
# after which one differed, and INTAKES counts the intakes made.
brief_sums() { local f; for f in "$HOME"/briefs/*; do [ -f "$f" ] && printf '%s %s\n' "$f" "$(sha "$f")"; done; }
EDITED= INTAKES=0
written() { need "$1: exit" 0 "$RC$(cat "$T/err")"; need "$1: written" no "$NOTHING"; }
reads() { grep -cE -- "$1" "$T/calls"; }
host_private() { db '.repos["acme/widgets"].private = $p' --argjson p "$1"; }
no_fail() { db '.fail = []'; }
fail_on() { db '.fail = [{match: $m, rc: 1, stderr: $e}]' --arg m "$1" --arg e "$2"; }
sha() { if command -v sha256sum > /dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1; else shasum -a 256 < "$1" | cut -d' ' -f1; fi; }
# brief_put <label> <source file>: the brief copied into the scratch HOME and
# named in record/host; its digest is kept in $T/briefs.sums, the last one
# this suite wrote for that path, for the check that no intake edits it.
brief_put() {
    local p="$HOME/briefs/$1.md"
    cp "$2" "$p"
    w --host "briefs:$1" "$p" > /dev/null 2> "$T/host.err" || needf "--host briefs:$1 failed: $(cat "$T/host.err")"
    { grep -vF "$p " "$T/briefs.sums" 2>/dev/null; printf '%s %s\n' "$p" "$(sha "$p")"; } > "$T/briefs.sums.next"
    mv "$T/briefs.sums.next" "$T/briefs.sums"
    DIG="sha256:$(sha "$p")"
}
# fresh: the run's Standing empty and no Run briefs or briefs-read row, so a
# case starts alike.
fresh() {
    printf '[]' > "$T/empty.json"; put "$G" record/standing "$T/empty.json"
    if ctx "$G" record/run | jq -e 'type == "array" and any(.[]; .key == "briefs" or .key == "briefs-read")' > /dev/null 2>&1; then
        ctx "$G" record/run | jq -c '[.[] | select(.key != "briefs" and .key != "briefs-read")]' > "$T/run.json"
        put "$G" record/run "$T/run.json"
    fi
}
standing() { ctx "$G" record/standing; }
briefs_rows() { ctx "$G" record/run | jq -s -c '[(.[0] // [])[] | select(.key == "briefs") | .value]'; }
# read_rows: the Run briefs-read rows' values.
read_rows() { ctx "$G" record/run | jq -s -c '[(.[0] // [])[] | select(.key == "briefs-read") | .value]'; }
# capfix <label> <n>: the brief-unread gap's capped fix text.
capfix() {
    printf 'state-stored-set.sh --intake %s --by <you>; %s of its lines can'"'"'t be taken under the caps (60 inferred rule rows, 120 rule rows): when they aren'"'"'t standing rules, have the brief rewritten with its rules under ## Standing rules and record it under the same label (state-stored-set.sh --host briefs:%s <absolute path>); otherwise ask a person which rule rows to confirm or end; then run it again, and it goes on after the lines it already took' "$1" "$2" "$1"
}
# gaps: the handover gate's brief-unread lines, `<gap>: <fix>`.
gaps() { (cd "$WD" && bash "$PS/state-handover.sh" --session "$G" --check) 2>&1 >/dev/null | sed -n 's/^  \(brief-unread [^:]*: .*\)$/\1/p'; }
entry_tail() {
    local k
    for k in $( (cd "$WD" && koto context list "$G" --prefix record/entries/) | jq -r --argjson n "$1" 'sort | .[-$n:][]'); do
        ctx "$G" "$k" | jq -r '"\(.kind)|\(.text)"'
    done
}
# excluded_text <file>: the text of the brief's six excluded sections, one line each.
excluded_text() {
    awk '/^#{1,2}( |$)/ { ex = ($0 == "## Goal" || $0 == "## Checkpoints" || $0 == "## Read first" || $0 == "## Acceptance criteria" || $0 == "## Reporting" || $0 == "## Keep-alive"); next }
         ex { print }' "$1"
}

# ---- the host and the run ----------------------------------------------------
db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-intake.md"] = $r' \
    --arg r "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n')"
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"
jq -nc --arg p "$PR" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-intake.md"], ["HOST_REPO", "acme/widgets"],
    ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$G" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err" \
    || stop "the run opens" "$(cat "$T/open.out" "$T/open.err")"
RECORD=$(record_json roadmap intake)
(cd "$WD" && session_seed "$G" "$RECORD" 2026-11-01T08:00:00Z) || stop "the run's record is seeded" ""
[ "$(at "$G")" = reconcile ] || stop "the run finds its record" "$(cat "$T/tick.err")"
: > "$T/briefs.sums"

# ---- R47: the golden briefs' first intake ------------------------------------
for f in min leg base; do
    fresh
    brief_put lane "$GOLD/$f.txt"
    need "$f: brief-unread is listed before" "brief-unread lane: state-stored-set.sh --intake lane --by <you>" "$(gaps)"
    rm -f "$T/koto.calls"
    KOTO_BIN="$T/kotolog/koto" try --intake lane --by coord
    written "$f: the intake"
    [ -s "$T/koto.calls" ] || needf "$f: the logging koto was never run"
    grep -qE '(^| )decisions?( |$)' "$T/koto.calls" 2>/dev/null && needf "$f: a decision command ran: $(grep -E '(^| )decisions?( |$)' "$T/koto.calls")"
    need "$f: the rows' Whats are brief-kept.json's" "$(jq -c --arg f "$f" '.[$f]' "$SD/brief-kept.json")" "$(standing | jq -c 'map(.what)')"
    need "$f: each row the rule row's shape, Source inferred brief lane $DIG" \
        "$(jq -r --arg f "$f" '.[$f] | length' "$SD/brief-kept.json")" \
        "$(standing | jq --arg s "inferred brief lane $DIG" '[.[] | select((keys_unsorted == ["standing","kind","on","until","what","owner","relayed_by","set","source"])
            and .kind == "rule" and .on == "" and .until == "" and .owner == "" and .relayed_by == "" and .source == $s)] | length')"
    need "$f: the Run briefs row" "[\"lane $DIG\"]" "$(briefs_rows)"
    need "$f: no briefs-read row" "[]" "$(read_rows)"
    entry_tail "$(( $(standing | jq length) + 1 ))" > "$T/entries.txt"
    need "$f: the last entry is the briefs row's" "run|Run briefs lane $DIG set by coord." "$(tail -1 "$T/entries.txt")"
    grep -qF "briefs-read" "$T/entries.txt" && needf "$f: a briefs-read entry: $(grep -F briefs-read "$T/entries.txt")"
    excluded_text "$GOLD/$f.txt" > "$T/excluded.txt"
    while IFS= read -r what; do
        case "$what" in "#"*) needf "$f: a heading came in: $what" ;; esac
        grep -qF -- "${what#- }" "$T/excluded.txt" && needf "$f: an excluded section's sentence came in: $what"
    done < <(standing | jq -r '.[].what')
    need "$f: brief-unread is cleared" "" "$(gaps)"
done
crit "R47. the first intake of each golden brief writes 7, 11 and 11 inferred brief rows and clears brief-unread, with no briefs-read row or entry"

# ---- idempotent on one digest -----------------------------------------------
fresh
brief_put lane "$GOLD/min.txt"
try --intake lane --by coord
written "the first intake"
try --intake lane --by coord
need "the second intake: exit" 0 "$RC"
need "  ... prints nothing" "" "$(cat "$T/out" "$T/err")"
need "  ... writes nothing" yes "$NOTHING"
need "  ... and reads nothing on GitHub" 0 "$(grep -c . "$T/calls")"
crit "a second intake of the same digest writes nothing"

# ---- R47: the 61-sentence brief ------------------------------------------------
fresh
brief_put lane "$SD/brief-61.md"
try --intake lane --by coord
need "the 61-sentence intake: exit" 1 "$RC"
need "  ... 60 rows written" 60 "$(standing | jq length)"
need "  ... the first 60 of its lines, in order" "- Decision 1 holds for every lane.|- Decision 60 holds for every lane." \
    "$(standing | jq -r '"\(.[0].what)|\(.[-1].what)"')"
need "  ... no briefs row" "[]" "$(briefs_rows)"
grep -qF "state-stored-set: took 60 of the brief's lines; 1 of its lines can't be taken under the caps: the record holds 60 inferred rule rows" "$T/err" \
    || needf "stderr doesn't name 1 line: $(cat "$T/err")"
(cd "$WD" && bash "$PS/state-handover.sh" --session "$G" --check) > /dev/null 2> "$T/gate"
need "  ... the gate exits 1" 1 "$?"
grep -qxF "  brief-unread lane: $(capfix lane 1)" "$T/gate" \
    || needf "the gap's fix isn't the capped text naming 1 line: $(cat "$T/gate")"
case "$(cat "$T/err")" in *"confirm or end one first") ;; *) needf "stderr doesn't end confirm or end one first: $(cat "$T/err")" ;; esac
try --intake lane --by coord
need "the intake again: exit" 1 "$RC"
need "  ... writes nothing" yes "$NOTHING"
grep -qF "took 0 of the brief's lines; 1 of its lines can't be taken under the caps" "$T/err" || needf "the second run's stderr: $(cat "$T/err")"
try --standing pause --on all --until lifted --what x --owner y
written "a pause at the cap"
crit "R47. a 61-sentence brief writes 60 rows, leaves brief-unread open naming 1 line, and a pause is still written"

# ---- the 120-rule cap --------------------------------------------------------
fresh
jq -nc --arg p "pinned workspace-charter sha256:$(printf '%064d' 1)" '[range(115) | {standing: "s\(. + 1)", kind: "rule", on: "", until: "",
    what: "Seeded row \(. + 1).", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: (if . < 10 then "inferred" else $p end)}]' > "$T/seed.json"
put "$G" record/standing "$T/seed.json"
brief_put lane "$GOLD/min.txt"
try --intake lane --by coord
need "the intake at 115 rule rows: exit" 1 "$RC"
need "  ... 5 rows written" 5 "$(standing | jq '[.[] | select(.source | startswith("inferred brief"))] | length')"
grep -qF "took 5 of the brief's lines; 2 of its lines can't be taken under the caps: the record holds 120 rule rows" "$T/err" \
    || needf "stderr: $(cat "$T/err")"
case "$(cat "$T/err")" in *"; end one first") ;; *) needf "stderr doesn't end end one first: $(cat "$T/err")" ;; esac
need "  ... and the gap's fix names 2, counted from its briefs-read row" "brief-unread lane: $(capfix lane 2)" "$(gaps)"
need "  ... which is lane at the 6th line" "[\"lane $DIG 5/7\"]" "$(read_rows)"
crit "a brief at the 120-rule cap stops at it and names the rest"

# ---- the match is against every row ------------------------------------------
fresh
jq -nc --arg c "skill acme/widgets docs/rules.md $(printf '%040d' 3)" '[
    {standing: "s1", kind: "pause", on: "all", until: "lifted", what: "Hold the lanes until the release.", owner: "the human", relayed_by: "", set: "2026-11-01T08:00Z"},
    {standing: "s2", kind: "rule", on: "", until: "", what: "Read the CI log before a retry.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $c}]' > "$T/seed.json"
put "$G" record/standing "$T/seed.json"
printf '# Brief: match\n\n## Decisions already made\n\n- hold the lanes until the release\n- READ the CI log before a retry.\n- Read the CI log before any retry.\n- Keep one lane per feature.\n- Keep one lane per feature.\n' > "$T/match.md"
brief_put lane "$T/match.md"
try --intake lane --by coord
written "the intake"
need "  ... only the paraphrase and one copy of the duplicate come in" '["- Read the CI log before any retry.","- Keep one lane per feature."]' \
    "$(standing | jq -c '[.[] | select((.source // "") | startswith("inferred brief")) | .what]')"
need "  ... the held rows untouched" "$(jq -c . "$T/seed.json")" "$(standing | jq -c '.[0:2]')"
crit "a brief sentence a Standing row already holds isn't written again; a paraphrase is"

# ---- a pause-shaped line -------------------------------------------------------
fresh
printf '# Brief: pause\n\n## Decisions already made\n\nPause all dispatches until the owner says go.\n\n- Ask Dana Reyes before a release.\n' > "$T/pause.md"
brief_put lane "$T/pause.md"
try --intake lane --by coord
written "the intake"
ROW=$(standing | jq -c '.[] | select(.what == "Pause all dispatches until the owner says go.")')
N=$(printf '%s' "$ROW" | jq -r .standing)
need "  ... the line is a rule row, Source inferred brief" "rule|inferred brief lane $DIG|" "$(printf '%s' "$ROW" | jq -r '"\(.kind)|\(.source)|\(.owner)"')"
w --rules --id "$N" > "$T/view.json" 2> "$T/err"
need "  ... --rules reads it inferred, unconfirmed, to confirm, granting nothing" '["inferred","unconfirmed",true,false,[]]' \
    "$(jq -c '[.class, .status, .confirm, .under_session_grant, .session_allows]' "$T/view.json")"
w --list > "$T/list.json" 2> "$T/err"
bash "$PS/pause-read.sh" --standing "$T/list.json" > "$T/pauses.json" 2> "$T/err"
need "  ... pause-read.sh lists no pause and nothing on all" '[[],null]' "$(jq -c '[.pauses, .all]' "$T/pauses.json")"
(cd "$WD" && bash "$PS/state-handover.sh" --session "$G") > "$T/handover.json" 2> "$T/err"
need "  ... the handover's standing holds no row for it" 0 "$(jq --arg n "$N" '[.standing[] | select(.standing == $n)] | length' "$T/handover.json")"
need "  ... while its awaiting-confirmation list does" 1 "$(jq --arg n "$N" '[.rule_lists[] | select(.list == "awaiting-confirmation") | .rows[] | select(.standing == $n)] | length' "$T/handover.json")"
need "  ... and the person a line names stays in What, Owner blank" "|- Ask Dana Reyes before a release." \
    "$(standing | jq -r '.[] | select(.what | test("Dana")) | "\(.owner)|\(.what)"')"
crit "a pause-shaped brief line comes in as an inferred rule row that holds and grants nothing"

# ---- a new digest ----------------------------------------------------------------
fresh
printf '# Brief: v1\n\n## Out of scope\n\n- Line A stays.\n- Line B reads one way.\n- Line C goes.\n' > "$T/v1.md"
brief_put lane "$T/v1.md"
V1=$DIG
try --intake lane --by coord
written "the v1 intake"
ROW_A=$(standing | jq -c '.[] | select(.what == "- Line A stays.")')
standing | jq -c --arg s "inferred brief other $V1" '. + [{standing: "s90", kind: "rule", on: "", until: "", what: "- Line C goes.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $s}]' > "$T/seed.json"
put "$G" record/standing "$T/seed.json"
B_ID=$(standing | jq -r '.[] | select(.what == "- Line B reads one way.") | .standing')
C_ID=$(standing | jq -r '.[] | select(.what == "- Line C goes." and (.source | test(" lane "))) | .standing')
printf '# Brief: v2\n\n## Out of scope\n\n- Line A stays.\n- Line B reads another way.\n- Line D comes.\n' > "$T/v2.md"
brief_put lane "$T/v2.md"
V2=$DIG
need "the rewritten brief: brief-unread is listed again" "brief-unread lane: state-stored-set.sh --intake lane --by <you>" "$(gaps)"
try --intake lane --by coord
written "the v2 intake"
need "  ... A's row byte-identical, with v1's Source" "$ROW_A" "$(standing | jq -c '.[] | select(.what == "- Line A stays.")')"
need "  ... B's and C's rows ended" "" "$(standing | jq -r --arg b "$B_ID" --arg c "$C_ID" '.[] | select(.standing == $b or .standing == $c) | .standing')"
need "  ... B' and D written with v2's digest" "- Line B reads another way.|inferred brief lane $V2 - Line D comes.|inferred brief lane $V2" \
    "$(standing | jq -r '[.[] | select(.what == "- Line B reads another way." or .what == "- Line D comes.") | "\(.what)|\(.source)"] | join(" ")')"
need "  ... the other label's row stays" "inferred brief other $V1" "$(standing | jq -r '.[] | select(.standing == "s90") | .source')"
need "  ... one briefs lane row, v2's" "[\"lane $V2\"]" "$(briefs_rows)"
need "  ... and brief-unread is cleared" "" "$(gaps)"
crit "a new digest ends the earlier digest's rows the brief no longer states"
B2=$(standing | jq -r '.[] | select(.what == "- Line B reads another way.") | .standing')
D2=$(standing | jq -r '.[] | select(.what == "- Line D comes.") | .standing')
need "the v2 entries, in order" \
    "rule|$B2 (rule): - Line B reads another way.. Source: inferred brief lane $V2.
rule|$D2 (rule): - Line D comes.. Source: inferred brief lane $V2.
end|$B_ID (rule: - Line B reads one way.) ended by coord.
end|$C_ID (rule: - Line C goes.) ended by coord.
run|Run briefs lane $V2 set by coord." "$(entry_tail 5)"
crit "the intake tells a rule entry per row, an end entry per ended row, then the briefs row"

# ---- lines left out ----------------------------------------------------------------
TOKEN="gh""p_$(printf '%036d' 7)"
LONG="Keep $(printf '%395s' '' | tr ' ' a)."
printf '# Brief: out\n\n## Decisions already made\n\n- Never read acme/secret from here.\n- Keep notes in /Us''ers/someone/x for later.\n- Pass the key %s along.\n- Keep one lane per feature.\n\n%s\n' "$TOKEN" "$LONG" > "$T/out.md"
need "the long line is 401 bytes" 401 "$(jq -rn --arg l "$LONG" '$l | utf8bytelength')"
for h in false true; do
    host_private "$h"
    fresh
    brief_put lane "$T/out.md"
    try --intake lane --by coord
    need "the intake (private host $h): exit" 0 "$RC"
    need "  ... written (private host $h)" no "$NOTHING"
    for m in "left out: a home-directory path: - Keep notes in /Users/[redacted]/x" "left out: a token-shaped string: - Pass the key gh""p_[redacted]" \
        "left out: a rule row's What is at most 400 bytes; this one is 401: Keep aaa"; do
        grep -qF -- "$m" "$T/err" || needf "stderr lacks [$m] (private host $h): $(cat "$T/err")"
    done
    grep -qF -- "$TOKEN" "$T/err" && needf "the token is printed (private host $h)"
    need "  ... the briefs row written (private host $h)" "[\"lane $DIG\"]" "$(briefs_rows)"
    if [ "$h" = false ]; then
        grep -qF "left out: names acme/secret, a repository that isn't public: - Never read acme/secret from here." "$T/err" || needf "stderr lacks acme/secret: $(cat "$T/err")"
        need "  ... the other line written" '["- Keep one lane per feature."]' "$(standing | jq -c 'map(.what)')"
    else
        need "  ... the acme/secret line written on a private host" '["- Never read acme/secret from here.","- Keep one lane per feature."]' "$(standing | jq -c 'map(.what)')"
        need "  ... with no read of it" 0 "$(reads 'repos/acme/secret')"
    fi
done
host_private false
crit "a line that fails the text check or the 400 bytes is reported and left out"

# ---- a failed read ---------------------------------------------------------------
fresh
brief_put lane "$GOLD/min.txt"
fail_on "repos/acme/widgets" "gh: Server Error (HTTP 502)"
try --intake lane --by coord
no_fail
need "the intake with the host's read failing: exit" 2 "$RC"
need "  ... nothing written" yes "$NOTHING"
grep -qF "cannot read acme/widgets's visibility" "$T/err" || needf "stderr: $(cat "$T/err")"
crit "a failed visibility read exits 2 writing nothing"

# ---- the opt-in heading: a successor brief ---------------------------------------
# The brief-intake-cap design's Decision 1. The record already holds three of
# the successor brief's rules word for word, under other Sources.
# seed_carried: those three rows, as a successor's record holds them.
seed_carried() {
    jq -nc --arg p "inferred brief predecessor sha256:$(printf '%064d' 5)" --arg c "skill acme/widgets docs/rules.md $(printf '%040d' 3)" '[
        {standing: "s1", kind: "rule", on: "", until: "", what: "Keep one worker per feature.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $p},
        {standing: "s2", kind: "rule", on: "", until: "", what: "Never merge a pull request whose checks are not green.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $c},
        {standing: "s3", kind: "rule", on: "", until: "", what: "Ask the owner before cutting a release.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $p}]' > "$T/seed.json"
    put "$G" record/standing "$T/seed.json"
}
# no_path <case> <file>...: the brief's path is in none of the files.
no_path() {
    local f
    for f in "${@:2}"; do grep -qF -- "briefs/lane.md" "$f" && needf "$1: the brief's path is in $(basename "$f"): $(cat "$f")"; done
    return 0
}
# gate_all: the handover check's whole output, both streams, in $T/gate.all.
gate_all() { (cd "$WD" && bash "$PS/state-handover.sh" --session "$G" --check) > "$T/gate.all" 2>&1; }
OUTSIDE_LINE="sentences sit outside its rule sections (## Standing rules, ## Decisions already made, ## Out of scope, ## Workspace rules) and weren't read as rules"
fresh
seed_carried
brief_put lane "$SD/successor-90.md"
need "the 90-line successor fixture is 90 lines" 90 "$(wc -l < "$SD/successor-90.md" | tr -d ' ')"
need "  ... brief-unread is listed before, uncapped" "brief-unread lane: state-stored-set.sh --intake lane --by <you>" "$(gaps)"
try --intake lane --by coord
need "the successor intake: exit" 0 "$RC"
need "  ... written" no "$NOTHING"
need "  ... only the rules no row holds, in order, Source inferred brief lane" \
    "$(jq -nc --arg s "inferred brief lane $DIG" '["- Hold every dispatch while a release is being tagged.",
        "- Read a failing check'"'"'s log before asking for a retry.", "- Report progress every two hours while workers are active.",
        "- Never reassign a held feature without telling its worker first.",
        "- Treat a reviewer'"'"'s changes-requested as blocking until it is resolved.", "- The plugin lane ships features in roadmap order.",
        "- Feature 27 waits for the release after next.", "- The website redesign belongs to another lane."] | map({what: ., source: $s})')" \
    "$(standing | jq -c '[.[3:][] | {what, source}]')"
need "  ... the carried rows untouched" "$(jq -c . "$T/seed.json")" "$(standing | jq -c '.[0:3]')"
need "  ... no holdings or takeover-step sentence came in" 0 \
    "$(standing | jq '[.[].what | select(test("^- Worker |^[0-9]+\\. |^- Features [0-9]|^- The (review|release|flaky|pull|last|rotation)"))] | length')"
grep -qF "state-stored-set: 59 of the brief's $OUTSIDE_LINE" "$T/err" || needf "stderr doesn't count the 59 sentences outside: $(cat "$T/err")"
need "  ... the Run briefs row" "[\"lane $DIG\"]" "$(briefs_rows)"
need "  ... brief-unread is cleared" "" "$(gaps)"
need "  ... the brief's digest is unchanged" "$DIG" "sha256:$(sha "$HOME/briefs/lane.md")"
standing > "$T/rows.json"
entry_tail 9 > "$T/entries.txt"
need "  ... its last entry is the briefs row's" "run|Run briefs lane $DIG set by coord." "$(tail -1 "$T/entries.txt")"
gate_all
no_path "the opt-in intake" "$T/out" "$T/err" "$T/gate.all" "$T/rows.json" "$T/entries.txt"
crit "a 90-line successor brief with its rules under ## Standing rules clears brief-unread in one intake"

fresh
seed_carried
grep -vx '## Standing rules' "$SD/successor-90.md" > "$T/plain.md"
brief_put lane "$T/plain.md"
try --intake lane --by coord
need "the same lines without the heading: exit" 1 "$RC"
need "  ... 58 rows written, to the inferred cap" 58 "$(standing | jq '[.[] | select(.source | startswith("inferred brief lane"))] | length')"
need "  ... a holdings sentence among them" 1 "$(standing | jq '[.[] | select(.what == "- Worker alder holds Feature 3 on branch impl-feature-3.")] | length')"
grep -qF "state-stored-set: took 58 of the brief's lines; 9 of its lines can't be taken under the caps: the record holds 60 inferred rule rows" "$T/err" \
    || needf "stderr doesn't name 9 lines: $(cat "$T/err")"
grep -qF "$OUTSIDE_LINE" "$T/err" && needf "a brief without the heading printed the outside count: $(cat "$T/err")"
need "  ... no briefs row" "[]" "$(briefs_rows)"
case "$(gaps)" in
    "brief-unread lane: state-stored-set.sh --intake lane --by <you>; 9 of its lines can't be taken under the caps"*) ;;
    *) needf "the gap doesn't name the same 9 lines: $(gaps)" ;;
esac
standing > "$T/rows.json"
entry_tail 58 > "$T/entries.txt"
gate_all
no_path "the headingless intake" "$T/out" "$T/err" "$T/gate.all" "$T/rows.json" "$T/entries.txt"
crit "the same lines without the heading cap as today, and the gap names the same count"

fresh
{
    printf '# Brief: many rules\n\nThe preamble is no rule.\n\n## Holdings\n\n- One holding.\n\n## Standing rules\n\n'
    for i in {1..61}; do printf -- '- Standing rule %s holds for every lane.\n' "$i"; done
} > "$T/rules61.md"
brief_put lane "$T/rules61.md"
try --intake lane --by coord
need "61 rules under the heading on an empty record: exit" 1 "$RC"
need "  ... 60 rows, the first 60 in order" "60|- Standing rule 1 holds for every lane.|- Standing rule 60 holds for every lane." \
    "$(standing | jq -r '"\(length)|\(.[0].what)|\(.[-1].what)"')"
grep -qF "state-stored-set: took 60 of the brief's lines; 1 of its lines can't be taken under the caps" "$T/err" || needf "stderr doesn't name 1 line: $(cat "$T/err")"
grep -qF "state-stored-set: 2 of the brief's $OUTSIDE_LINE" "$T/err" || needf "stderr doesn't count 2 outside: $(cat "$T/err")"
need "  ... no briefs row" "[]" "$(briefs_rows)"
case "$(gaps)" in
    "brief-unread lane: state-stored-set.sh --intake lane --by <you>; 1 of its lines can't be taken under the caps"*) ;;
    *) needf "the gap doesn't name 1 line: $(gaps)" ;;
esac
crit "61 rules under ## Standing rules write 60 and exit 1, the gap naming 1 line"

fresh
printf '# Brief: empty rules\n\nThe preamble is no rule. Nor is this.\n\n## Holdings\n\n- One holding.\n\n## Standing rules\n\n## Goal\n\nShip the lane.\n' > "$T/emptyrules.md"
brief_put lane "$T/emptyrules.md"
try --intake lane --by coord
need "an empty ## Standing rules section: exit" 0 "$RC"
need "  ... written" no "$NOTHING"
need "  ... no rule row" "[]" "$(standing | jq -c .)"
need "  ... the briefs row" "[\"lane $DIG\"]" "$(briefs_rows)"
grep -qF "state-stored-set: 4 of the brief's $OUTSIDE_LINE" "$T/err" || needf "stderr doesn't count all 4 sentences: $(cat "$T/err")"
need "  ... brief-unread is cleared" "" "$(gaps)"
gate_all
no_path "the empty-section intake" "$T/out" "$T/err" "$T/gate.all"
crit "an empty ## Standing rules section writes no rule row, the briefs row, and counts every sentence outside"

# ---- a capped intake goes on from its briefs-read row ------------------------------
# The brief-intake-cap design's Decision 2: a capped intake records how far it
# got in a Run briefs-read row, and the next intake of the same digest starts
# there.
# std_whats <source>: the Whats of the rows with that Source, in order.
std_whats() { standing | jq -c --arg s "$1" '[.[] | select(.source == $s) | .what]'; }
# gap_n: the count of untaken lines brief-unread lane names, or none.
gap_n() { gaps | sed -n 's/^brief-unread lane: .*; \([0-9]*\) of its lines can.t be taken.*/\1/p'; }
# err_n: the count of untaken lines the last intake's stderr names, or none.
err_n() { sed -n 's/^state-stored-set: took [0-9]* of the brief.s lines; \([0-9]*\) of its lines can.t be taken.*/\1/p' "$T/err"; }
# run_put <jq>: record/run rewritten by the filter.
run_put() { ctx "$G" record/run | jq -s -c "(.[0] // []) | $1" > "$T/run.json" && put "$G" record/run "$T/run.json"; }

fresh
brief_put lane "$SD/brief-61.md"
try --intake lane --by coord
need "the 61-sentence intake: exit" 1 "$RC"
need "  ... 60 rows" 60 "$(standing | jq length)"
need "  ... the briefs-read row lane D 60/61" "[\"lane $DIG 60/61\"]" "$(read_rows)"
need "  ... no briefs row" "[]" "$(briefs_rows)"
entry_tail 61 > "$T/entries.txt"
need "  ... 60 rule entries, then the briefs-read run entry" "60|run|Run briefs-read lane $DIG 60/61 set by coord." \
    "$(head -60 "$T/entries.txt" | grep -c '^rule|')|$(tail -1 "$T/entries.txt")"
gate_all
no_path "the capped intake" "$T/err" "$T/gate.all" "$T/entries.txt"
try --intake lane --by coord
need "the intake again, nothing to take or end: exit" 1 "$RC"
need "  ... the record unchanged, briefs-read row included" yes "$NOTHING"
need "  ... the row still lane D 60/61" "[\"lane $DIG 60/61\"]" "$(read_rows)"
ENDED=$(standing | jq -r '.[] | select(.what == "- Decision 7 holds for every lane.") | .standing')
w --end "$ENDED" --by coord > /dev/null 2> "$T/end.err" || needf "--end $ENDED failed: $(cat "$T/end.err")"
need "  ... the gap, counted from the row, is uncapped after the end" "brief-unread lane: state-stored-set.sh --intake lane --by <you>" "$(gaps)"
standing | jq -c '[.[].standing]' > "$T/ids.json"
try --intake lane --by coord
need "the intake after one end: exit" 0 "$RC$(cat "$T/err")"
need "  ... writes only the 61st sentence, not the ended one" '["- Decision 61 holds for every lane."]' \
    "$(standing | jq -c --slurpfile b "$T/ids.json" '[.[] | select(.standing as $s | $b[0] | index($s) | not) | .what]')"
need "  ... the ended sentence is not back" 0 "$(standing | jq '[.[] | select(.what == "- Decision 7 holds for every lane.")] | length')"
need "  ... the briefs row" "[\"lane $DIG\"]" "$(briefs_rows)"
need "  ... no briefs-read row" "[]" "$(read_rows)"
entry_tail 2 > "$T/entries.txt"
need "  ... a rule entry, then only the briefs run entry" "rule|run|Run briefs lane $DIG set by coord." \
    "$(head -1 "$T/entries.txt" | cut -d'|' -f1)|$(tail -1 "$T/entries.txt")"
need "  ... and brief-unread is cleared" "" "$(gaps)"
no_path "the completing intake" "$T/err" "$T/entries.txt"
crit "a capped 61-sentence brief leaves briefs-read lane D 60/61 and, after one end, writes only the 61st sentence and the briefs row"

# A headingless brief well over 60 lines, most rows removed between rounds
# (record/standing rewritten without them, a stand-in for a person's ends).
fresh
{ printf '# Brief: long\n\n'; for i in {1..130}; do printf -- '- Long rule %s holds for the lane.\n' "$i"; done; } > "$T/long.md"
brief_put lane "$T/long.md"
LONG_D=$DIG
try --intake lane --by coord
need "the 130-line headingless brief: exit" 1 "$RC"
need "  ... briefs-read lane D 60/130" "[\"lane $DIG 60/130\"]" "$(read_rows)"
REMOVED=
ROUND=1
while [ "$RC" = 1 ] && [ "$ROUND" -le 4 ]; do
    standing | jq -c '[.[] | select(.what | test("^- Long rule [0-9]+ ")) ] | .[5:] | map(.what)' > "$T/removed.json"
    REMOVED="$REMOVED $(jq -r '.[] | capture("rule (?<n>[0-9]+) ").n' "$T/removed.json" | tr '\n' ' ')"
    standing | jq -c '[.[] | select((.what | test("^- Long rule [0-9]+ ")) | not)] + ([.[] | select(.what | test("^- Long rule [0-9]+ "))] | .[0:5])' > "$T/seed.json"
    put "$G" record/standing "$T/seed.json"
    GAPN=$(gap_n)
    C=$(read_rows | jq -r '.[0] | split(" ")[2] | split("/")[0]')
    try --intake lane --by coord
    if [ "$RC" = 1 ]; then
        need "  ... round $ROUND: the gap's count is the intake's" "$GAPN" "$(err_n)"
    fi
    FIRST=$(standing | jq -r '[.[] | select(.what | test("^- Long rule [0-9]+ "))] | .[5].what')
    need "  ... round $ROUND writes from candidate $C on" "- Long rule $((C + 1)) holds for the lane." "$FIRST"
    ROUND=$((ROUND + 1))
done
need "  ... the rounds end with exit 0" 0 "$RC$(cat "$T/err")"
need "  ... the briefs row" "[\"lane $LONG_D\"]" "$(briefs_rows)"
need "  ... no briefs-read row" "[]" "$(read_rows)"
BACK=$(for n in $REMOVED; do standing | jq -r --arg w "- Long rule $n holds for the lane." '.[] | select(.what == $w) | .what'; done)
need "  ... no removed sentence back in Standing" "" "$BACK"
crit "a headingless brief well over 60 lines converges: each re-run writes from its briefs-read row and none of the removed rows comes back"

# A seeded briefs-read row naming another digest, or another n, is ignored.
for seeded in "lane sha256:$(printf '%064d' 9) 30/61" "lane @D 30/99"; do
    fresh
    brief_put lane "$SD/brief-61.md"
    run_put ". + [{key: \"briefs-read\", value: \"${seeded/@D/$DIG}\", set_by: \"coord\", set: \"2026-11-01T08:00Z\"}]"
    try --intake lane --by coord
    need "seeded ${seeded/@D/D}: exit" 1 "$RC"
    need "  ... the first 60 rows, from candidate 0" "60|- Decision 1 holds for every lane.|- Decision 60 holds for every lane." \
        "$(standing | jq -r '"\(length)|\(.[0].what)|\(.[-1].what)"')"
    need "  ... its own row in place of the seeded one" "[\"lane $DIG 60/61\"]" "$(read_rows)"
done
crit "a briefs-read row for another digest or another n is ignored, the intake reading from candidate 0"

# A new digest under the same label after a capped one.
fresh
brief_put lane "$SD/brief-61.md"
V1=$DIG
try --intake lane --by coord
{ printf '# Brief: v2\n\n## Decisions already made\n\n'
  for i in {1..10}; do printf -- '- Decision %s holds for every lane.\n' "$i"; done
  for i in {1..60}; do printf -- '- New rule %s holds for every lane.\n' "$i"; done; } > "$T/v2-70.md"
brief_put lane "$T/v2-70.md"
V2=$DIG
standing | jq -c '.[0:10]' > "$T/kept10.json"
try --intake lane --by coord
need "the new digest after V1's 60/61: exit" 1 "$RC"
need "  ... V1's rows for Decision 1-10 kept as they were" "$(jq -c . "$T/kept10.json")" "$(standing | jq -c '.[0:10]')"
need "  ... V1's other 50 rows ended" 0 "$(standing | jq --arg s "inferred brief lane $V1" '[.[] | select(.source == $s and (.what | test("Decision ([1-9]|10) ") | not))] | length')"
need "  ... 50 new rows, New rule 1 to 50" "50|- New rule 1 holds for every lane.|- New rule 50 holds for every lane." \
    "$(std_whats "inferred brief lane $V2" | jq -r '"\(length)|\(.[0])|\(.[-1])"')"
need "  ... one briefs-read row, V2 60/70" "[\"lane $V2 60/70\"]" "$(read_rows)"
ENDED=$(standing | jq -r '.[] | select(.what == "- New rule 3 holds for every lane.") | .standing')
w --end "$ENDED" --by coord > /dev/null 2> "$T/end.err" || needf "--end $ENDED failed: $(cat "$T/end.err")"
try --intake lane --by coord
need "  ... its re-run from 60: exit" 1 "$RC"
need "  ... writes New rule 51 only" "- New rule 51 holds for every lane." "$(std_whats "inferred brief lane $V2" | jq -r '.[-1]')"
need "  ... V1's rows for Decision 1-10 still in Standing" "$(jq -c . "$T/kept10.json")" "$(standing | jq -c '.[0:10]')"
need "  ... briefs-read V2 61/70" "[\"lane $V2 61/70\"]" "$(read_rows)"
crit "a new digest reads whole, ends only the earlier rows it states nowhere, and its re-run from c keeps the rows it states before c"

# A capped run whose ends leave no room: it ends, takes none, writes no row.
fresh
brief_put lane "$GOLD/min.txt"
jq -nc --arg o "inferred brief lane sha256:$(printf '%064d' 8)" '[range(60) | {standing: "s\(. + 1)", kind: "rule", on: "", until: "",
    what: "Bare row \(. + 1).", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: "inferred"}]
    + [{standing: "s61", kind: "rule", on: "", until: "", what: "Old line one.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $o},
       {standing: "s62", kind: "rule", on: "", until: "", what: "Old line two.", owner: "", relayed_by: "", set: "2026-11-01T08:00Z", source: $o}]' > "$T/seed.json"
put "$G" record/standing "$T/seed.json"
try --intake lane --by coord
need "60 bare inferred rows and two earlier-digest rows: exit" 1 "$RC"
need "  ... the two ended, no row taken" "60|0" \
    "$(standing | jq -r '"\(length)|\([.[] | select(.what | startswith("Old line"))] | length)"')"
need "  ... no briefs-read row" "[]" "$(read_rows)"
entry_tail 2 > "$T/entries.txt"
need "  ... its entries the two ends" "end|end" "$(cut -d'|' -f1 "$T/entries.txt" | tr '\n' '|' | sed 's/|$//')"
need "  ... the gap counts from candidate 0" 7 "$(gap_n)"
w --end s1 --by coord > /dev/null 2> "$T/end.err" || needf "--end s1 failed: $(cat "$T/end.err")"
try --intake lane --by coord
need "  ... the next run takes candidate 0" "$(jq -c '.min[0]' "$SD/brief-kept.json")" "$(standing | jq -c '.[-1].what')"
crit "a capped run whose ends leave no room ends them, writes no briefs-read row, and the next run starts at candidate 0"

# A briefs-read row that breaks its grammar: every write is refused.
fresh
SEEDR=$(ctx "$G" record/run | jq -s -c ".[0] // []")
BAD_D=sha256:$(printf '%064d' 4)
for bad in "lane $BAD_D 0/61" "lane $BAD_D 61/61" "lane $BAD_D 62/61" "lane sha256:abc 30/61" "two"; do
    if [ "$bad" = two ]; then
        jq -c --arg d "$BAD_D" '. + [{key: "briefs-read", value: "lane \($d) 30/61", set_by: "coord", set: "2026-11-01T08:00Z"},
            {key: "briefs-read", value: "lane \($d) 31/61", set_by: "coord", set: "2026-11-01T08:00Z"}]' <<< "$SEEDR" > "$T/run.json"
    else
        jq -c --arg v "$bad" '. + [{key: "briefs-read", value: $v, set_by: "coord", set: "2026-11-01T08:00Z"}]' <<< "$SEEDR" > "$T/run.json"
    fi
    put "$G" record/run "$T/run.json"
    try --standing pause --on all --until lifted --what x --owner y
    [ "$RC" != 0 ] || needf "a write over [$bad] exited 0"
    need "  ... [$bad]: nothing written" yes "$NOTHING"
done
printf '%s' "$SEEDR" > "$T/run.json"; put "$G" record/run "$T/run.json"
try --run briefs-read "lane $BAD_D 30/61" --by coord
need "--run briefs-read: exit" 64 "$RC"
need "  ... nothing written" yes "$NOTHING"
crit "a briefs-read row with c = 0, c = n, c > n, a bad digest or two for one label refuses the write, and --run briefs-read exits 64"

# The rewrite route: the headingless lines cap with a marker, then the
# version with its rules under ## Standing rules clears the gap.
fresh
seed_carried
grep -vx '## Standing rules' "$SD/successor-90.md" > "$T/plain.md"
brief_put lane "$T/plain.md"
PLAIN_D=$DIG
try --intake lane --by coord
need "the headingless successor lines: exit" 1 "$RC"
case "$(read_rows)" in "[\"lane $PLAIN_D "*) ;; *) needf "no briefs-read row for the headingless digest: $(read_rows)" ;; esac
need "  ... the gap's fix names the rewrite" "brief-unread lane: $(capfix lane 9)" "$(gaps)"
brief_put lane "$SD/successor-90.md"
try --intake lane --by coord
need "  ... the rewrite recorded under the same label and taken: exit" 0 "$RC$(cat "$T/err" | grep -v 'sit outside')"
jq -R -s -c -L "$PS" 'include "state-schema"; brief_candidates' "$SD/successor-90.md" > "$T/optin.json"
need "  ... the headingless rows it doesn't state ended" 0 \
    "$(standing | jq --arg s "inferred brief lane $PLAIN_D" --slurpfile c "$T/optin.json" '[.[] | select(.source == $s) | .what as $w | select([$c[0][] | . == $w] | any | not)] | length')"
need "  ... the briefs row, the new digest" "[\"lane $DIG\"]" "$(briefs_rows)"
need "  ... no briefs-read row" "[]" "$(read_rows)"
need "  ... brief-unread is cleared" "" "$(gaps)"
crit "a headingless brief's capped record clears once its rewrite under ## Standing rules is recorded and taken"

# koto-open.sh takes its vars file away, so each open writes one.
dvars() { jq -nc --arg p "$PR" '[["SCOPE", "discipline"], ["DISCIPLINE", "brk"], ["HOST_REPO", "acme/widgets"], ["PLUGIN_ROOT", $p]]' > "$T/dvars.json"; }
vars_roadmap() { jq -nc --arg p "$PR" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-intake.md"], ["HOST_REPO", "acme/widgets"], ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"; }
# The carries copy the Run section whole: a successor of a record capped at
# lane D 60/61 holds that row and the 60 rows it went past, and goes on.
fresh
brief_put lane "$SD/brief-61.md"
C61_D=$DIG
try --intake lane --by coord
need "the record to carry: exit" 1 "$RC"
need "  ... capped at lane D 60/61" "[\"lane $C61_D 60/61\"]" "$(read_rows)"
# The restart carry: core_carry, sourced as state-stored-set_test.sh does,
# into a second run of the roadmap, written to by session as the tests do.
G2=coordinate-roadmap-intake-20261101T100000Z
vars_roadmap; (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$G2" "$TPL" "$T/vars.json") > "$T/open2.out" 2> "$T/open2.err" \
    || needf "the restart's run opens: $(cat "$T/open2.out" "$T/open2.err")"
(cd "$WD" && PROG=carry SCOPE=roadmap NAME=intake REPO=acme/widgets HERE="$PS"
    . "$PS/state-common.sh"; . "$PS/state-read.sh"; . "$PS/state-write-core.sh"; RS_RETRY_PAUSE=0
    core_carry "$G" "$G2") > /dev/null 2> "$T/carry.err" || needf "core_carry failed: $(cat "$T/carry.err")"
w2() { (cd "$WD" && RS_SESSION=$G2 bash "$PS/state-stored-set.sh" --scope roadmap --name intake --repo acme/widgets --skip-session-checks "$@"); }
need "the restart carry: its briefs-read row" "[\"lane $C61_D 60/61\"]" "$(ctx "$G2" record/run | jq -c '[.[] | select(.key == "briefs-read") | .value]')"
need "  ... and the 60 rows it went past" "$(standing | jq -c .)" "$(ctx "$G2" record/standing | jq -c .)"
w2 --end "$(ctx "$G2" record/standing | jq -r ".[0].standing")" --by coord > /dev/null 2> "$T/end.err" || needf "--end after the restart carry failed: $(cat "$T/end.err")"
w2 --intake lane --by coord > /dev/null 2> "$T/err"
need "  ... one end and a re-run: exit" 0 "$?$(cat "$T/err")"
need "  ... writes the 61st sentence" "- Decision 61 holds for every lane." "$(ctx "$G2" record/standing | jq -r '.[-1].what')"
need "  ... the briefs row and no briefs-read row" "[\"lane $C61_D\"]|[]" \
    "$(ctx "$G2" record/run | jq -c '[.[] | select(.key == "briefs") | .value]')|$(ctx "$G2" record/run | jq -c '[.[] | select(.key == "briefs-read") | .value]')"
crit "after a restart carry, the successor holds the briefs-read row and the 60 rows, and one end and a re-run finish the brief"

# The rotation carry: state-open.sh --carry, from one rotation of a
# discipline to the next.
DSLUG=coordinate-discipline-brk
dat() { (cd "$WD" && koto next "$1" "${@:2}" --no-cleanup 2>"$T/tick.err") | jq -r '.state // empty'; }
dw() { local s=$1; shift; (cd "$WD" && bash "$PS/state-stored-set.sh" --session "$s" "$@"); }
dday() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
R1=$DSLUG-20261101T090000Z
R2=$DSLUG-20261101T100000Z
dvars; (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$R1" "$TPL" "$T/dvars.json") > /dev/null 2> "$T/dopen.err" || needf "the first rotation opens: $(cat "$T/dopen.err")"
ST=$(dat "$R1")
[ "$ST" = record_open ] || needf "the first rotation's find: [$ST] $(cat "$T/tick.err")"
(cd "$WD" && bash "$PS/state-open.sh" --session "$R1" --role manager --start "$(dday 0)" --end "$(dday 6)") > /dev/null 2> "$T/dopen.err" \
    || needf "the first rotation's record opens: $(cat "$T/dopen.err")"
ST=$(dat "$R1" --with-data '{"opened":"opened"}')
[ "$ST" = reconcile ] || needf "the first rotation reaches reconcile: [$ST] $(cat "$T/tick.err")"
dw "$R1" --host briefs:lane "$HOME/briefs/lane.md" > /dev/null 2> "$T/w.err" || needf "--host on the first rotation: $(cat "$T/w.err")"
dw "$R1" --intake lane --by coord > /dev/null 2> "$T/err"
need "the first rotation's intake: exit" 1 "$?"
need "  ... capped at lane D 60/61" "[\"lane $C61_D 60/61\"]" "$(ctx "$R1" record/run | jq -c '[.[] | select(.key == "briefs-read") | .value]')"
ctx "$R1" record/rotation | jq -c --arg e "$(dday -1)" '.end = $e | if .start > $e then .start = $e else . end' > "$T/rot.json"
dw "$R1" --rotation "$T/rot.json" > /dev/null 2> "$T/w.err" || needf "the first rotation's window ends: $(cat "$T/w.err")"
dvars; (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$R2" "$TPL" "$T/dvars.json") > /dev/null 2> "$T/dopen.err" || needf "the next rotation opens: $(cat "$T/dopen.err")"
# The opener cancels every other live run of the scope as it opens the next one.
(cd "$WD" && koto cancel "$R1") > /dev/null 2> "$T/cancel.err" || needf "the first rotation is cancelled: $(cat "$T/cancel.err")"
ST=$(dat "$R2")
[ "$ST" = predecessor_carry ] || needf "the next rotation's find: [$ST] $(cat "$T/tick.err")"
(cd "$WD" && bash "$PS/state-open.sh" --session "$R2" --carry --role manager) > /dev/null 2> "$T/dopen.err" \
    || needf "state-open.sh --carry: $(cat "$T/dopen.err")"
ST=$(dat "$R2" --with-data '{"carry":"carried"}')
[ "$ST" = reconcile ] || needf "the next rotation reaches reconcile: [$ST] $(cat "$T/tick.err")"
need "the rotation carry: its briefs-read row" "[\"lane $C61_D 60/61\"]" "$(ctx "$R2" record/run | jq -c '[.[] | select(.key == "briefs-read") | .value]')"
need "  ... and the 60 rows it went past" "$(ctx "$R1" record/standing | jq -c .)" "$(ctx "$R2" record/standing | jq -c .)"
dw "$R2" --host briefs:lane "$HOME/briefs/lane.md" > /dev/null 2> "$T/w.err" || needf "--host on the next rotation: $(cat "$T/w.err")"
dw "$R2" --end "$(ctx "$R2" record/standing | jq -r ".[0].standing")" --by coord > /dev/null 2> "$T/end.err" || needf "--end after the rotation carry failed: $(cat "$T/end.err")"
dw "$R2" --intake lane --by coord > /dev/null 2> "$T/err"
need "  ... one end and a re-run: exit" 0 "$?$(cat "$T/err")"
need "  ... writes the 61st sentence" "- Decision 61 holds for every lane." "$(ctx "$R2" record/standing | jq -r '.[-1].what')"
need "  ... the briefs row and no briefs-read row" "[\"lane $C61_D\"]|[]" \
    "$(ctx "$R2" record/run | jq -c '[.[] | select(.key == "briefs") | .value]')|$(ctx "$R2" record/run | jq -c '[.[] | select(.key == "briefs-read") | .value]')"
crit "after a rotation carry, the next rotation holds the briefs-read row and the 60 rows, and one end and a re-run finish the brief"

# ---- the brief is never edited ---------------------------------------------------
while read -r p s; do
    [ -n "$p" ] || continue
    need "$p unchanged" "$s" "$(sha "$p")"
done < "$T/briefs.sums"
need "no intake changed a brief" "" "${EDITED#; }"
need "every intake of the suite was checked" true "$([ "$INTAKES" -ge 15 ] && echo true || echo false)"
crit "the brief file is unchanged by every intake"

done_tests brief-intake-engine
