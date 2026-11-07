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
# fresh: the run's Standing empty and no Run briefs row, so a case starts alike.
fresh() {
    printf '[]' > "$T/empty.json"; put "$G" record/standing "$T/empty.json"
    if ctx "$G" record/run | jq -e 'type == "array" and any(.[]; .key == "briefs")' > /dev/null 2>&1; then
        ctx "$G" record/run | jq -c '[.[] | select(.key != "briefs")]' > "$T/run.json"
        put "$G" record/run "$T/run.json"
    fi
}
standing() { ctx "$G" record/standing; }
briefs_rows() { ctx "$G" record/run | jq -s -c '[(.[0] // [])[] | select(.key == "briefs") | .value]'; }
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
    excluded_text "$GOLD/$f.txt" > "$T/excluded.txt"
    while IFS= read -r what; do
        case "$what" in "#"*) needf "$f: a heading came in: $what" ;; esac
        grep -qF -- "${what#- }" "$T/excluded.txt" && needf "$f: an excluded section's sentence came in: $what"
    done < <(standing | jq -r '.[].what')
    need "$f: brief-unread is cleared" "" "$(gaps)"
done
crit "R47. the first intake of each golden brief writes 7, 11 and 11 inferred brief rows and clears brief-unread"

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
grep -qF "  brief-unread lane: state-stored-set.sh --intake lane --by <you>; 1 of its lines can't be taken under the caps (60 inferred rule rows, 120 rule rows)" "$T/gate" \
    || needf "the gap's fix doesn't name 1 line: $(cat "$T/gate")"
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
need "  ... and the gap's fix names 2" "brief-unread lane: state-stored-set.sh --intake lane --by <you>; 2 of its lines can't be taken under the caps (60 inferred rule rows, 120 rule rows): ask a person which rule rows to confirm or end, then run it again" "$(gaps)"
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
printf '# Brief: out\n\n## Decisions already made\n\n- Never read acme/secret from here.\n- Keep notes in /Users/someone/x for later.\n- Pass the key %s along.\n- Keep one lane per feature.\n\n%s\n' "$TOKEN" "$LONG" > "$T/out.md"
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

# ---- the brief is never edited ---------------------------------------------------
while read -r p s; do
    [ -n "$p" ] || continue
    need "$p unchanged" "$s" "$(sha "$p")"
done < "$T/briefs.sums"
need "no intake changed a brief" "" "${EDITED#; }"
need "every intake of the suite was checked" true "$([ "$INTAKES" -ge 15 ] && echo true || echo false)"
crit "the brief file is unchanged by every intake"

done_tests brief-intake-engine
