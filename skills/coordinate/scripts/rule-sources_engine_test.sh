#!/usr/bin/env bash
# rule-sources_engine_test.sh -- a Run value the coordinator worked out and its
# inferred rule row (state-stored-set.sh --run reports-to|cap --inferred), the
# handover read's reports-to-unsourced gap, and the Run `rules` rows read as
# sourced lines by --rules, on a real koto session of the shipped coordinate.md,
# against the testdata/gh stand-in
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md, Decision 5 and
# its acceptance terms). The host is acme/widgets, public; the stand-in holds
# acme/secret private and no other/absent. "Nothing written" means the
# record's key list and every record/ key but the entries byte-identical, so
# no entry key is added either. Prints one line per criterion:
#   1.  --run reports-to --inferred writes the Run row and a Standing rule row
#       {standing, kind rule, blank on, until, owner and relayed_by, what,
#       set, source inferred} in one write, both with the same Set, and tells
#       the run entry, then the rule entry `s<n> (rule): <What>. Source:
#       inferred.`;
#   2.  --run cap --inferred does the same for the cap;
#   3.  with 60 inferred rule rows held, either write exits 65 naming the
#       60-inferred cap, with no forge read and neither the value nor the row
#       written; with 120 rule rows (59 inferred) it names the 120 cap;
#   4.  a sentence over 400 bytes, one with a line break, one naming a private
#       repository (65), a token read failing with HTTP 502 (2), a cap
#       outside 1-99 and a malformed reports-to (65) each write nothing;
#   7.  the row reads inferred, unconfirmed, confirm true and not under the
#       session's grant through --rules --id, the handover read lists it
#       awaiting confirmation, and --rules --counts counts it inferred (beside
#       the record's `rules charter` Run row, whose label is neither skill-
#       nor workspace-);
#   8.  a reports-to naming a session with no dispatched-by link and no
#       Standing row naming it gives reports-to-unsourced, and --check exits 1
#       naming it;
#   9.  a dispatched-by link to another session, and an --inferred sentence
#       that doesn't name the session, leave the gap; the --inferred write, a
#       pinned rule row and a relayed event row naming the session each clear
#       it, and so does a real `koto session link <run> --dispatched-by
#       <session>`, tried last since koto refuses to remove a koto/ key;
#   10. with the --inferred row stripped from the record's Standing, the
#       handover read names reports-to-unsourced, and with it put back, not;
#   12. each --rules object for a Run rules row is {run, kind, label, digest,
#       class, said, pointer}, class skill-says, charter or inferred by its
#       label, said the row's Set, pointer {label, digest, host rules:<label>},
#       with no status, confirm or grant field; --rules --id prints none;
#   13. on a record holding the five event kinds and the four rows of
#       testdata/standing-rules/rule-rows.json, plus 8 skill-, 3 workspace-
#       and one notes Run rules rows, --rules --counts prints its seven lines
#       in order, skill-says 9, charter 4, inferred 2, relayed 5,
#       unreadable 1, adding up to the Standing rows plus the Run rules rows,
#       and each count is the --rules objects of that class;
#   14. the fake niwa's call log is the same with Run rules rows as without
#       (none on floor rows alone, one with a passing row), and the Standing
#       objects' under_session_grant and session_allows are unchanged;
#   16. no column, kind or key is added: the record's keys are the same
#       before and after the writes, every Standing row has the rule row's
#       columns, and the Run objects go with the Run rows they are read from.
#
# niwa is never the real one: a fake in the scratch directory, first on PATH,
# appends its arguments to a call log and answers a bound grant of merge-pr,
# as rule-grants_engine_test.sh's does.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there for the
# session before the first koto command, or the suite stops.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/rule-sources_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
ORIG_PATH=$PATH
# test-lib.sh makes the scratch directory T, the gh DB helpers, state_json and
# the ok/bad/eq counters. It puts testdata/ (the koto stand-in) first on PATH;
# this suite needs the real koto, so PATH is rebuilt below.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH NIWA_BIN CLAUDE_CODE_SESSION_ID NIWA_LOOKUP_SECONDS FORGE_READ_SECONDS KOTO_BIN
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin" "$T/fake"
cat > "$T/fake/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
cat "$T/niwa.answer"
EOF
chmod +x "$T/fake/niwa"
PATH="$T/fake:$T/bin:$ORIG_PATH"
export PATH

# The session, named here and nowhere else.
G=coordinate-roadmap-rulesources-20261021T090000Z
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
# The instance the coordinator runs in, so --rules can make its grant read.
INST="$HOME/ws/inst"
WD="$INST/repo"
mkdir -p "$INST/.niwa" "$WD"
echo '{}' > "$INST/.niwa/instance.json"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
SID=$(printf "%s-%s-%s-%s-%s" 4f1c2b9e 7d3a 4e6b 9a8c 0d1e2f3a4b5c)

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests rule-sources-engine; exit 1; }

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
    local before
    before=$(snap)
    reset_calls
    w "$@" > "$T/out" 2> "$T/err"; RC=$?
    cp "$GH_DB.calls" "$T/calls"
    if [ "$before" = "$(snap)" ]; then NOTHING=yes; else NOTHING=no; fi
}
refused() {
    need "$1: exit" "$2" "$RC"
    grep -qF -- "$3" "$T/err" || needf "$1: stderr lacks [$3]: $(cat "$T/err")"
    need "$1: nothing written" yes "$NOTHING"
}
written() { need "$1: exit" 0 "$RC$(cat "$T/err")"; need "$1: written" no "$NOTHING"; }
fail_on() { db '.fail = [{match: $m, rc: 1, stderr: $e}]' --arg m "$1" --arg e "$2"; }
no_fail() { db '.fail = []'; }
handover() { (cd "$WD" && bash "$PS/state-handover.sh" --session "$G" "$@"); }
gaps() { handover 2>/dev/null | jq -r '[.gaps[].gap] | join(" ")'; }
has_gap() { case " $(gaps) " in *" reports-to-unsourced "*) echo yes ;; *) echo no ;; esac; }
standing_put() { printf '%s' "$1" > "$T/standing.json"; put "$G" record/standing "$T/standing.json"; }
run_put() { printf '%s' "$1" > "$T/run.json"; put "$G" record/run "$T/run.json"; }
last_row() { ctx "$G" record/standing | jq -c '.[-1]'; }
entry_keys() { (cd "$WD" && koto context list "$G" --prefix record/entries/) | jq -r 'sort | .[]'; }
run_row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "the human", set: "2026-10-21T08:00Z"}'; }
calls_n() { if [ -e "$T/niwa.calls" ]; then wc -l < "$T/niwa.calls" | tr -d ' '; else echo 0; fi; }
rules() { (cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID bash "$PS/state-stored-set.sh" --session "$G" --rules "$@"); }

PA=sha256:1111111111111111111111111111111111111111111111111111111111111111
PB=sha256:2222222222222222222222222222222222222222222222222222222222222222
ADDR=coord-lead
RT="director at $ADDR"
SENT="Report to $ADDR: worked out from the session that opened this run, not given in the brief"
CAP_SENT="Hold the cap at 3: worked out from the three lanes the roadmap opens at once"
CAP60="refused: standing: the record holds 60 inferred rule rows, the most it keeps; confirm or end one first"
CAP120="refused: standing: the record holds 120 rule rows, the most it keeps; end one first"
printf '%s\n' '{"schema":"niwa.authority.check/v1","state":"bound","binding":"mapping","dispatch_id":"dispatch-under-test","grant":[{"authority":"merge-pr","sources":["dispatch"]}],"level":"supervised","level_source":"workspace","grant_ceiling_source":"workspace"}' \
    > "$T/niwa.answer"

# ---- the host and the run ----------------------------------------------------
db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-rulesources.md"] = $r' \
    --arg r "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n')"
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"
jq -nc --arg p "$PR" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-rulesources.md"], ["HOST_REPO", "acme/widgets"],
    ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$G" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err" \
    || stop "the run opens" "$(cat "$T/open.out" "$T/open.err")"
RECORD=$(record_json roadmap rulesources | jq -c --argjson r "[$(run_row arguments "--roadmap docs/roadmaps/ROADMAP-rulesources.md"),$(run_row cap 2),$(run_row coordinator rulesources-coord),$(run_row role manager),$(run_row rules "charter $PA")]" \
    '.run = $r | .standing = []')
(cd "$WD" && session_seed "$G" "$RECORD" 2026-10-21T08:00:00Z) || stop "the run's record is seeded" ""
[ "$(at "$G")" = reconcile ] || stop "the run finds its record" "$(cat "$T/tick.err")"
ctx "$G" record/meta | jq -e '(.driver // "") == ""' > /dev/null || stop "the run's record/meta names no driver" "$(ctx "$G" record/meta)"
standing_put '[]'
KEYS_BEFORE=$( (cd "$WD" && koto context list "$G" --prefix record/) | jq -c '[.[] | select(startswith("record/entries/") | not)] | sort')

# ---- 1 ------------------------------------------------------------------------
N0=$(entry_keys | wc -l | tr -d ' ')
try --run reports-to "$RT" --inferred "$SENT" --by "$G"
written "the reports-to --inferred write"
need "  ... it prints three lines, the record's and the two entries'" 3 "$(grep -c . "$T/out")"
RUN_RT=$(ctx "$G" record/run | jq -c '[.[] | select(.key == "reports-to")]')
need "  ... the Run row" "[\"$RT\",\"$G\"]" "$(printf '%s' "$RUN_RT" | jq -c '[.[0].value, .[0].set_by]')"
ROW=$(last_row); N=$(printf '%s' "$ROW" | jq -r .standing)
need "  ... the rule row, Source exactly inferred, Owner blank" \
    "$(jq -cnS --arg n "$N" --arg w "$SENT" --arg t "$(printf '%s' "$RUN_RT" | jq -r '.[0].set')" \
        '{standing: $n, kind: "rule", on: "", until: "", what: $w, owner: "", relayed_by: "", set: $t, source: "inferred"}')" \
    "$(printf '%s' "$ROW" | jq -cS .)"
need "  ... one Standing row" 1 "$(ctx "$G" record/standing | jq length)"
need "  ... two entries" $((N0 + 2)) "$(entry_keys | wc -l | tr -d ' ')"
KEYS=$(entry_keys); E1=$(sed -n "$((N0 + 1))p" <<<"$KEYS"); E2=$(sed -n "$((N0 + 2))p" <<<"$KEYS")
need "  ... the run entry first" "run|Run reports-to set to $RT by $G." "$(ctx "$G" "$E1" | jq -r '"\(.kind)|\(.text)"')"
need "  ... then the rule entry" "rule|$N (rule): $SENT. Source: inferred." "$(ctx "$G" "$E2" | jq -r '"\(.kind)|\(.text)"')"
crit "1. --run reports-to --inferred writes the Run row and a rule row {standing, kind rule, blank on, until, owner, relayed_by, what, set, source inferred} with one Set, then the run entry and the rule entry"

# ---- 2 ------------------------------------------------------------------------
try --run cap 3 --inferred "$CAP_SENT" --by "$G"
written "the cap --inferred write"
CAP_SET=$(ctx "$G" record/run | jq -r '[.[] | select(.key == "cap")] | "\(length) \(.[0].value) \(.[0].set)"')
ROW=$(last_row); N2=$(printf '%s' "$ROW" | jq -r .standing)
need "  ... one cap row, the new value" "1 3" "${CAP_SET% *}"
need "  ... the next id" "s$(( ${N#s} + 1 ))" "$N2"
need "  ... the rule row" "rule|$CAP_SENT|inferred||${CAP_SET##* }" "$(printf '%s' "$ROW" | jq -r '"\(.kind)|\(.what)|\(.source)|\(.owner)|\(.set)"')"
need "  ... and the rule entry last" "rule|$N2 (rule): $CAP_SENT. Source: inferred." "$(ctx "$G" "$(entry_keys | tail -1)" | jq -r '"\(.kind)|\(.text)"')"
crit "2. --run cap --inferred writes the cap row and its inferred rule row the same way, with the next id"

# ---- 7 ------------------------------------------------------------------------
rules --id "$N" > "$T/view.json" 2> "$T/err"
need "--rules --id reads the row" "0 inferred unconfirmed true false []" \
    "$? $(jq -r '"\(.class) \(.status) \(.confirm) \(.under_session_grant) \(.session_allows | tojson)"' "$T/view.json")"
need "  ... pointing at its own row" "{\"row\":\"$G record/standing $N\"}" "$(jq -c .pointer "$T/view.json")"
need "  ... the handover read lists it awaiting confirmation" "$N $N2" \
    "$(handover | jq -r '[.rule_lists[] | select(.list == "awaiting-confirmation") | .rows[].standing] | join(" ")')"
# The two --inferred rows, and the seeded `rules charter` Run row, whose
# label is neither skill- nor workspace-.
need "  ... and --rules --counts counts both inferred" "inferred 3" "$(w --rules --counts | grep '^inferred ')"
crit "7. the --inferred row reads inferred, unconfirmed, confirm true and not under the grant; the handover read lists it awaiting confirmation; --counts counts it inferred"

# ---- 10 -----------------------------------------------------------------------
ctx "$G" record/standing > "$T/standing.saved"
need "the record that cleared the gap with --inferred lists no reports-to-unsourced" no "$(has_gap)"
jq -c --arg n "$N" 'map(select(.standing != $n))' "$T/standing.saved" > "$T/standing.stripped"
put "$G" record/standing "$T/standing.stripped"
need "  ... with that row stripped, the handover read names reports-to-unsourced" yes "$(has_gap)"
put "$G" record/standing "$T/standing.saved"
need "  ... and with it back, not" no "$(has_gap)"
crit "10. stripping the reports-to row's inferred Standing row makes the handover read name reports-to-unsourced"

# ---- 8 ------------------------------------------------------------------------
standing_put '[]'
try --run reports-to "$RT" --by "$G"
written "a plain reports-to write"
need "  ... with no rule row" 0 "$(ctx "$G" record/standing | jq length)"
need "the handover read names reports-to-unsourced" yes "$(has_gap)"
handover --check > /dev/null 2> "$T/check.err"
need "  ... --check exits 1" 1 "$?"
grep -qF "  reports-to-unsourced: state-stored-set.sh --run reports-to \"$RT\" --inferred " "$T/check.err" \
    || needf "--check doesn't name it with the --inferred fix: $(cat "$T/check.err")"
crit "8. a reports-to naming a session with no dispatched-by link and no Standing row naming it gives reports-to-unsourced, and --check exits 1 naming it"

# ---- 9 ------------------------------------------------------------------------
# koto keeps koto/ keys its own (context remove refuses them), so the real
# dispatched-by link to the session is the last clearing tried.
(cd "$WD" && koto session link "$G" --dispatched-by coord-other) > "$T/link.err" 2>&1 || needf "koto session link failed: $(cat "$T/link.err")"
need "a dispatched-by link to another session doesn't clear the gap" yes "$(has_gap)"
try --run reports-to "$RT" --inferred "Report to the lead coordinator: worked out from the session that opened this run" --by "$G"
written "an --inferred write whose sentence doesn't name the session"
need "  ... leaves the gap" yes "$(has_gap)"
standing_put '[]'
try --run reports-to "$RT" --inferred "$SENT" --by "$G"
written "the --inferred write"
need "  ... clears it" no "$(has_gap)"
standing_put '[]'
try --standing rule --what "Report to $ADDR each morning." --source "pinned charter $PA"
written "a pinned rule row naming the session"
need "  ... clears it" no "$(has_gap)"
standing_put '[]'
try --standing approval --what "the release notes as drafted" --owner "the human" --relayed-by "$ADDR"
written "a relayed event row naming the session"
need "  ... clears it" no "$(has_gap)"
standing_put '[]'
need "with none of them the gap is back" yes "$(has_gap)"
(cd "$WD" && koto session link "$G" --dispatched-by "$ADDR") > "$T/link.err" 2>&1 || needf "koto session link failed: $(cat "$T/link.err")"
need "the dispatched-by link to the session is in the run's session" "[\"koto/links/dispatched-by/$ADDR\",\"koto/links/dispatched-by/coord-other\"]" \
    "$( (cd "$WD" && koto context list "$G" --prefix koto/links/dispatched-by/) | jq -c 'sort')"
need "  ... and clears the gap with Standing empty" no "$(has_gap)"
crit "9. a dispatched-by link to another session or a sentence not naming the session leaves reports-to-unsourced; the --inferred write, a pinned rule row and a relayed event row naming it, and a real koto session link --dispatched-by to it each clear it"

# ---- 3 ------------------------------------------------------------------------
# rule_fixture <rule rows> <inferred among them>: a Standing value, the rule
# rows inferred and then pinned, seeded with koto context add.
rule_fixture() {
    jq -nc --argjson r "$1" --argjson i "$2" --arg pin "pinned charter $PA" '
        [range($r) | {standing: "s\(. + 1)", kind: "rule", on: "", until: "", what: "row \(. + 1)", owner: "", relayed_by: "",
                      set: "2026-10-21T08:00Z", source: (if . < $i then "inferred" else $pin end)}]' > "$T/fixture.json"
    put "$G" record/standing "$T/fixture.json"
}
rule_fixture 60 60
for c in "reports-to|$RT|$SENT" "cap|4|$CAP_SENT"; do
    IFS='|' read -r k v s <<< "$c"
    try --run "$k" "$v" --inferred "$s" --by "$G"
    refused "--run $k --inferred at the 60-inferred cap" 65 "$CAP60"
    need "  ... with no forge read" 0 "$(grep -c . "$T/calls")"
done
rule_fixture 120 59
try --run cap 4 --inferred "$CAP_SENT" --by "$G"
refused "--run cap --inferred at the 120-rule cap" 65 "$CAP120"
crit "3. with 60 inferred rule rows, --run reports-to and --run cap with --inferred exit 65 naming the 60-inferred cap, read nothing on the forge, and write neither the value nor the row; at 120 rule rows, the 120 cap"

# ---- 4 ------------------------------------------------------------------------
standing_put '[]'
A401=$(printf '%401s' '' | tr ' ' a)
try --run cap 4 --inferred "$A401" --by "$G"
refused "a 401-byte sentence" 65 "a rule row's What is at most 400 bytes; this one is 401"
try --run cap 4 --inferred "$(printf 'two\nlines')" --by "$G"
refused "a sentence with a line break" 65 "refused: "
try --run reports-to "$RT" --inferred "Report to $ADDR, never to acme/secret" --by "$G"
refused "a sentence naming a private repository" 65 "names acme/secret, a repository that isn't public"
fail_on "repos/other/absent" "gh: Server Error (HTTP 502)"
try --run reports-to "$RT" --inferred "Report to $ADDR, as other/absent does" --by "$G"
no_fail
refused "a token read failing" 2 "cannot read other/absent's visibility"
try --run cap 100 --inferred "$CAP_SENT" --by "$G"
refused "a cap outside 1-99" 65 "a cap is a number from 1 to 99"
need "  ... with no forge read" 0 "$(grep -c . "$T/calls")"
try --run reports-to "director at coord/lead" --inferred "$SENT" --by "$G"
refused "a malformed reports-to" 65 "the shape of a path"
crit "4. a sentence over 400 bytes, with a line break or naming a private repository (65), a token read failing (2), a cap outside 1-99 and a malformed reports-to (65) each write neither row"

# ---- 12 -----------------------------------------------------------------------
standing_put '[]'
for v in "skill-SKILL.md $PA" "workspace-0-CLAUDE.md $PB" "notes $PB"; do
    w --run rules "$v" --by "$G" > /dev/null 2> "$T/err" || needf "--run rules $v failed: $(cat "$T/err")"
done
try --standing rule --what "Keep one lane per feature" --source inferred
written "an inferred Standing row"
NS=$(last_row | jq -r .standing)
rules > "$T/rules.out" 2> "$T/err" || needf "--rules failed: $(cat "$T/err")"
ctx "$G" record/run > "$T/run.now"
jq -c '.[] | select(.key == "rules") | (.value | split(" ")) as $p
    | {run: "rules", kind: (if ($p[0] | startswith("skill-")) then "skill" elif ($p[0] | startswith("workspace-")) then "workspace" else "other" end),
       label: $p[0], digest: $p[1],
       class: (if ($p[0] | startswith("skill-")) then "skill-says" elif ($p[0] | startswith("workspace-")) then "charter" else "inferred" end),
       said: .set, pointer: {label: $p[0], digest: $p[1], host: "rules:\($p[0])"}}' "$T/run.now" > "$T/run.want"
need "each Run rules row's object, in record order, keys in order" "$(cat "$T/run.want")" "$(jq -c 'select(has("run"))' "$T/rules.out")"
need "  ... inferred (the seeded charter label), skill-says, charter, inferred" "inferred skill-says charter inferred" "$(jq -r 'select(has("run")) | .class' "$T/rules.out" | tr '\n' ' ' | sed 's/ $//')"
need "  ... none with status, confirm or a grant field" 0 \
    "$(jq -s '[.[] | select(has("run")) | select(has("status") or has("confirm") or has("under_session_grant") or has("session_allows"))] | length' "$T/rules.out")"
need "  ... after the Standing object" "$NS" "$(head -1 "$T/rules.out" | jq -r '.standing // "run"')"
rules --id "$NS" > "$T/rules.one" 2> "$T/err"
need "--rules --id prints that Standing object alone" "0 1 $NS" "$? $(jq -s length "$T/rules.one") $(jq -r .standing "$T/rules.one")"
crit "12. each Run rules row's --rules object is {run, kind, label, digest, class, said, pointer}: class by its label, said its Set, pointer {label, digest, host rules:<label>}, with no status, confirm or grant field; --rules --id prints Standing objects only"

# ---- 13 -----------------------------------------------------------------------
EVENTS=$(jq -nc '
    def ev($n; $k): {standing: "s\($n)", kind: $k, on: "", until: "", what: "event \($n)", owner: "the human", relayed_by: "", set: "2026-10-21T08:00Z"};
    [ev(1; "pause") + {on: "all", until: "lifted"}, ev(2; "go-ahead") + {on: "Feature 1"}, ev(3; "approval"), ev(4; "answer"),
     ev(5; "assignment") + {on: "#7"}]')
standing_put "$(jq -c --argjson e "$EVENTS" '$e + .' "$HERE/testdata/standing-rules/rule-rows.json")"
run_put "$(ctx "$G" record/run | jq -c --arg a "$PA" '[.[] | select(.key != "rules")]
    + [range(8) | {key: "rules", value: "skill-\(.)-x.md \($a)", set_by: "s", set: "2026-10-21T08:00Z"}]
    + [range(3) | {key: "rules", value: "workspace-\(.)-CLAUDE.md \($a)", set_by: "s", set: "2026-10-21T08:00Z"}]
    + [{key: "rules", value: "notes \($a)", set_by: "s", set: "2026-10-21T08:00Z"}]')"
w --rules --counts > "$T/counts" 2> "$T/err" || needf "--counts failed: $(cat "$T/err")"
need "the seven lines in rule_classes order" "relayed 5|owner-said 0|dispatcher-said 0|inferred 2|skill-says 9|charter 4|unreadable 1" \
    "$(tr '\n' '|' < "$T/counts" | sed 's/|$//')"
need "  ... adding up to the Standing rows plus the Run rules rows" "$(( $(ctx "$G" record/standing | jq length) + $(ctx "$G" record/run | jq '[.[] | select(.key == "rules")] | length') ))" \
    "$(awk '{ n += $2 } END { print n + 0 }' "$T/counts")"
w --rules > "$T/rules.all" 2> "$T/err" || needf "--rules failed: $(cat "$T/err")"
need "  ... each count the --rules objects of that class" "$(cat "$T/counts")" \
    "$(jq -r -s '. as $o | ["relayed", "owner-said", "dispatcher-said", "inferred", "skill-says", "charter", "unreadable"][]
        | . as $k | "\($k) \([$o[] | select(.class == $k)] | length)"' "$T/rules.all")"
crit "13. on the five event kinds and rule-rows.json's four rows plus 8 skill-, 3 workspace- and one notes Run rules rows, --counts prints its seven lines in order with skill-says 9, charter 4, inferred 2, adding up to the Standing rows plus the Run rules rows"

# ---- 14 -----------------------------------------------------------------------
verdicts() { jq -c 'select(has("standing")) | [.standing, .under_session_grant, .session_allows]' "$1" | tr '\n' ' '; }
RUN_WITH=$(ctx "$G" record/run)
RUN_WITHOUT=$(printf '%s' "$RUN_WITH" | jq -c '[.[] | select(.key != "rules")]')
# Floor rows alone (the inferred brief, pinned and decision rows): no read.
FLOOR=$(jq -c '[.[] | select((.source | split(" ")[0]) != "skill")]' "$HERE/testdata/standing-rules/rule-rows.json")
standing_put "$FLOOR"
for r in without with; do
    if [ "$r" = with ]; then run_put "$RUN_WITH"; else run_put "$RUN_WITHOUT"; fi
    rm -f "$T/niwa.calls"
    rules > "$T/floor.$r" 2> "$T/err" || needf "--rules failed: $(cat "$T/err")"
    need "floor rows $r Run rules rows: no niwa read" 0 "$(calls_n)"
done
need "  ... the Standing objects' grant fields the same" "$(verdicts "$T/floor.without")" "$(verdicts "$T/floor.with")"
# A relayed approval passes the floor and the anchor: one read, either way.
standing_put "$(jq -c --argjson e "$EVENTS" '$FLOOR + [$e[2]]' --argjson FLOOR "$FLOOR" -n)"
for r in without with; do
    if [ "$r" = with ]; then run_put "$RUN_WITH"; else run_put "$RUN_WITHOUT"; fi
    rm -f "$T/niwa.calls"
    rules > "$T/pass.$r" 2> "$T/err" || needf "--rules failed: $(cat "$T/err")"
    need "a passing row $r Run rules rows: one niwa read" 1 "$(calls_n)"
done
need "  ... the Standing objects' grant fields the same" "$(verdicts "$T/pass.without")" "$(verdicts "$T/pass.with")"
need "  ... the approval under the grant" '["s3",true,["merge-pr"]]' "$(jq -c 'select(.standing == "s3") | [.standing, .under_session_grant, .session_allows]' "$T/pass.with")"
need "  ... and 12 Run objects, none with a grant field" "12 0" \
    "$(jq -s '[.[] | select(has("run"))] | "\(length) \([.[] | select(has("under_session_grant") or has("session_allows"))] | length)"' -r "$T/pass.with")"
crit "14. Run rules rows change neither the fake niwa's call log (none on floor rows, one with a passing row) nor the Standing objects' under_session_grant and session_allows, and no Run object carries either"

# ---- 16 -----------------------------------------------------------------------
KEYS_AFTER=$( (cd "$WD" && koto context list "$G" --prefix record/) | jq -c '[.[] | select(startswith("record/entries/") | not)] | sort')
need "the record's keys, entries aside, are the same as before the writes" "$KEYS_BEFORE" "$KEYS_AFTER"
standing_put '[]'
run_put "$RUN_WITHOUT"
try --run reports-to "$RT" --inferred "$SENT" --by "$G"
written "one more --inferred write"
need "  ... every Standing row has the rule row's columns" '["standing","kind","on","until","what","owner","relayed_by","set","source"]' \
    "$(ctx "$G" record/standing | jq -c '[.[] | keys_unsorted] | unique | .[0]')"
need "  ... every Run row the Run columns" '["key","value","set_by","set"]' "$(ctx "$G" record/run | jq -c '[.[] | keys_unsorted] | unique | .[0]')"
w --rules > "$T/rules.none" 2> "$T/err"
need "  ... and with the Run rules rows gone, --rules prints no Run object" "0 0" "$? $(jq -s '[.[] | select(has("run"))] | length' "$T/rules.none")"
crit "16. no column, kind or key is added: the record's keys are unchanged, the rows keep their columns, and the Run objects are read from the Run rows alone"

done_tests rule-sources-engine
