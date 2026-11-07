#!/usr/bin/env bash
# standing-rule-write_engine_test.sh -- state-stored-set.sh --standing rule on
# a real koto session of the shipped coordinate.md, against the testdata/gh
# stand-in (docs/designs/DESIGN-coordinator-standing-rule-provenance.md, the
# acceptance terms for the rule write). The host is acme/widgets, public
# unless a criterion says otherwise; the stand-in holds acme/gadgets public,
# acme/secret and other/hidden private, and no acme/ghost or other/absent.
# Forge reads are counted by the stand-in's call log. "Nothing written" means
# every record/ key but the entries byte-identical and no entry key added.
# Prints one line per criterion:
#   R23. a skill rule write exits 0 printing two lines, its row is the rule
#        row's shape, and its entry is kind rule, `s<n> (rule): <What>.
#        Source: <Source>.`;
#   R24. on a record with no standing_used, the next write after a rule write
#        takes the next id, read from the rule entry;
#   the inferred, inferred brief, pinned and doc forms each write the same
#        shape, and --rules --id reads each's class, status, confirm and
#        pointer as step 1's reader does;
#   R31. a decision Source is refused, 65, nothing written, and no koto
#        decisions command is run;
#   R6.  on a private host a skill row makes exactly the compare read and the
#        contents read for its repository, and no visibility read of it;
#   R7.  on each host, a commit the default branch doesn't hold (diverged,
#        behind) is refused, 65, with no contents read;
#   R8.  a What the file holds at the default branch's tip but not at the
#        cited commit is refused, 65;
#   R9.  a visibility, compare or contents read failing with HTTP 502 exits 2
#        naming that read, with no read after it;
#   R10. a compare read that doesn't answer within FORGE_READ_SECONDS exits 2
#        within 4 seconds, with no contents read;
#   R42. a compare status outside the four, and a visibility or contents read
#        answering a body that isn't JSON, exit 2 naming the read;
#   R11. on a public host, an absent, a private and a 404 repository give
#        byte-identical refusals, with no compare or contents read of it;
#   R12. on a private host, an absent repository, a 404 compare and a
#        notfound compare give byte-identical refusals;
#   R13. an HTTP 403 visibility read exits 2, not 65;
#   R43. on each host, a path the readable commit doesn't hold is refused, 65;
#   R26-R28. a host-cited doc write reads only the compare and the file more
#        than an inferred write, a skill write citing another repository its
#        visibility, the compare and the file, and an inferred write reads the
#        host twice (the writer's, which the core reuses, and the entry's);
#   R37-R39, R41. a What's bare repository names: refused when private or a
#        404 under the host's owner, passed for prose and another owner's
#        404, one read each, none on a private host, a 502 exiting 2;
#   R14-R17. the 120-rule and 60-inferred caps, a pause still written at both,
#        and no cap on a read or an unrelated write;
#   R34-R36. a stored row is never checked again: an unrelated write after its
#        repository turns private reads nothing of it and leaves Standing
#        byte for byte, while a new row citing it is refused.
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
# Usage: bash skills/coordinate/scripts/standing-rule-write_engine_test.sh
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
mkdir -p "$HOME" "$T/bin" "$T/fake" "$T/kotolog"
cat > "$T/fake/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
printf '%s\n' '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"no-mapping","grant":[]}'
EOF
chmod +x "$T/fake/niwa"
PATH="$T/fake:$T/bin:$ORIG_PATH"
export PATH
# A koto that logs its arguments, for R31, then runs the real one.
REAL_KOTO=$(command -v koto)
cat > "$T/kotolog/koto" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/koto.calls"
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/kotolog/koto"

# The session, named here and nowhere else.
G=coordinate-roadmap-rulewrite-20261020T090000Z
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
# `gh` is testdata/gh, but for the mode $GH_MODE_FILE names: sleep 5 seconds
# on a compare read, or answer acme/gadgets' visibility read, or a contents
# read, with a body that isn't JSON, which gh's --jq then fails on.
export COORD_TESTDATA="$HERE/testdata" GH_MODE_FILE="$T/gh.mode"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$(cat "$GH_MODE_FILE" 2>/dev/null):$*" in
    sleep-compare:*/compare/*) sleep 5 ;;
    nonjson-visibility:*"repos/acme/gadgets --jq .private"*|nonjson-contents:*/contents/*)
        printf '%s\n' "$*" >> "$GH_DB.calls"
        printf '<html>busy</html>\n' | jq -r "${@: -1}" 2> /dev/null
        exit 1 ;;
esac
. "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"

# koto refuses a --var value outside its allowlist (a `+` in a checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
WD="$T/work"
mkdir -p "$WD"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests standing-rule-write-engine; exit 1; }

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
# refused <label> <exit> <stderr text>: the last try exited so, its stderr
# holding the text, and wrote nothing.
refused() {
    need "$1: exit" "$2" "$RC"
    grep -qF -- "$3" "$T/err" || needf "$1: stderr lacks [$3]: $(cat "$T/err")"
    need "$1: nothing written" yes "$NOTHING"
}
written() { need "$1: exit" 0 "$RC$(cat "$T/err")"; need "$1: written" no "$NOTHING"; }
# reads <pattern>: how many of the last try's forge reads match the ERE.
reads() { grep -cE -- "$1" "$T/calls"; }
host_private() { db '.repos["acme/widgets"].private = $p' --argjson p "$1"; }
no_fail() { db '.fail = []'; }
fail_on() { db '.fail = [{match: $m, rc: 1, stderr: $e}]' --arg m "$1" --arg e "$2"; }
mode() { printf '%s' "$1" > "$GH_MODE_FILE"; }
# empty_standing: the run's Standing holds no row, so the next case starts alike.
empty_standing() { printf '[]' > "$T/empty.json"; put "$G" record/standing "$T/empty.json"; }
last_row() { ctx "$G" record/standing | jq -c '.[-1]'; }
last_entry() { local k; k=$( (cd "$WD" && koto context list "$G" --prefix record/entries/) | jq -r 'sort | .[-1]'); ctx "$G" "$k"; }

C=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
D=dddddddddddddddddddddddddddddddddddddddd
E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
F=ffffffffffffffffffffffffffffffffffffffff
PA=sha256:1111111111111111111111111111111111111111111111111111111111111111
PB=sha256:2222222222222222222222222222222222222222222222222222222222222222
SKILL=skills/x/SKILL.md
DOC=docs/charter.md
WHAT="The coordinator reads a CI run's status at most once a minute."
TIP_ONLY="It answers every review the same day."
CITED="$(printf '# The rules\n\nThe coordinator reads a CI run'"'"'s status at most once a\nminute. It never polls faster.\n')"
SRC_SKILL="skill acme/gadgets $SKILL $C"
SRC_DOC="doc acme/widgets $DOC $C"

# ---- the host and the run ----------------------------------------------------
db_init
db '.repos["other/hidden"] = {private: true, default_branch: "main"}
    | .files["acme/widgets"]["main:docs/roadmaps/ROADMAP-rulewrite.md"] = $r
    | .files["acme/gadgets"][$c + ":" + $s] = $t | .files["acme/gadgets"]["main:" + $s] = $t + "\n" + $tip
    | .files["acme/widgets"][$c + ":" + $d] = $t
    | .history = {"acme/gadgets": [$c], "acme/widgets": [$c], "acme/tools": [$c]}
    | .compare = {"acme/gadgets": {($e + "...HEAD"): "behind"}, "acme/widgets": {($f + "...HEAD"): "bogus"}}' \
    --arg r "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n')" \
    --arg c "$C" --arg e "$E" --arg f "$F" --arg s "$SKILL" --arg d "$DOC" --arg t "$CITED" --arg tip "$TIP_ONLY"
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"
jq -nc --arg p "$PR" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-rulewrite.md"], ["HOST_REPO", "acme/widgets"],
    ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$G" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err" \
    || stop "the run opens" "$(cat "$T/open.out" "$T/open.err")"
RECORD=$(record_json roadmap rulewrite | jq -c --arg v "charter $PA" '.run = [{key: "rules", value: $v, set_by: "the human", set: "2026-10-20T08:00Z"}]')
(cd "$WD" && session_seed "$G" "$RECORD" 2026-10-20T08:00:00Z) || stop "the run's record is seeded" ""
[ "$(at "$G")" = reconcile ] || stop "the run finds its record" "$(cat "$T/tick.err")"
mode none

# ---- R23 ------------------------------------------------------------------------
try --standing rule --what "$WHAT" --source "$SRC_SKILL"
written "the skill write"
need "  ... it prints two lines, the record's and the entry's" 2 "$(grep -c . "$T/out")"
ROW=$(last_row); N=$(printf '%s' "$ROW" | jq -r .standing)
need "  ... the row is the rule row's shape" \
    "$(jq -cnS --arg n "$N" --arg w "$WHAT" --arg s "$SRC_SKILL" --arg t "$(printf '%s' "$ROW" | jq -r .set)" \
        '{standing: $n, kind: "rule", on: "", until: "", what: $w, owner: "", relayed_by: "", set: $t, source: $s}')" \
    "$(printf '%s' "$ROW" | jq -cS .)"
need "  ... its Set a minute" true "$(printf '%s' "$ROW" | jq '.set | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$")')"
need "  ... and its entry" "rule|$N (rule): $WHAT. Source: $SRC_SKILL." "$(last_entry | jq -r '"\(.kind)|\(.text)"')"
crit "R23. a skill rule write exits 0 printing the record and its entry, the row {standing, kind rule, blank on, until, owner and relayed_by, what, set, source}, the entry kind rule reading s<n> (rule): <What>. Source: <Source>."

# ---- R24 ------------------------------------------------------------------------
empty_standing
try --standing rule --what "Keep one lane per feature." --source inferred
written "the inferred write"
N=$(last_row | jq -r '.standing[1:] | tonumber')
ctx "$G" record/meta | jq -c 'del(.standing_used)' > "$T/meta.json"
put "$G" record/meta "$T/meta.json"
empty_standing
need "  ... record/meta keeps no standing_used" null "$(ctx "$G" record/meta | jq -c '.standing_used')"
try --standing approval --what "the release notes as drafted" --owner "the human"
written "the next write"
need "  ... takes the next id, read from the rule row's entry" "s$((N + 1))" "$(last_row | jq -r .standing)"
crit "R24. on a record with no standing_used, the write after a rule write takes s<n+1>, the rule entry counted"

# ---- the four uncited forms --------------------------------------------------
empty_standing
for f in "inferred|[\"inferred\",\"unconfirmed\",true,{\"row\":\"$G record/standing @\"}]" \
    "inferred brief worker $PB|[\"inferred\",\"unconfirmed\",true,{\"brief\":\"worker\",\"digest\":\"$PB\"}]" \
    "pinned charter $PA|[\"charter\",\"in-force\",false,{\"pinned\":\"charter\",\"digest\":\"$PA\"}]" \
    "$SRC_DOC|[\"charter\",\"in-force\",false,{\"repo\":\"acme/widgets\",\"path\":\"$DOC\",\"commit\":\"$C\"}]"; do
    src=${f%%|*}
    try --standing rule --what "$WHAT" --source "$src"
    written "the ${src%% *} write"
    ROW=$(last_row); N=$(printf '%s' "$ROW" | jq -r .standing)
    need "  ... the ${src%% *} row's shape" '["standing","kind","on","until","what","owner","relayed_by","set","source"]||||' \
        "$(printf '%s' "$ROW" | jq -r '"\(keys_unsorted | tojson)|\(.on)|\(.until)|\(.owner)|\(.relayed_by)"')"
    need "  ... its Source" "$src" "$(printf '%s' "$ROW" | jq -r .source)"
    w --rules --id "$N" > "$T/view.json" 2> "$T/err"
    need "  ... --rules reads its class, status, confirm and pointer" "$(printf '%s' "${f#*|}" | sed "s/@/$N/")" \
        "$(jq -c '[.class, .status, .confirm, .pointer]' "$T/view.json")"
done
crit "the inferred, inferred brief, pinned and doc forms each write the rule row's shape, and --rules reads them inferred, inferred, charter and charter, unconfirmed for the two inferred, with step 1's pointers"

# ---- R31 ------------------------------------------------------------------------
rm -f "$T/koto.calls"
before=$(snap); reset_calls
(cd "$WD" && KOTO_BIN="$T/kotolog/koto" bash "$PS/state-stored-set.sh" --session "$G" --standing rule --what "$WHAT" \
    --source "decision example 000000000007") > "$T/out" 2> "$T/err"; RC=$?
if [ "$before" = "$(snap)" ]; then NOTHING=yes; else NOTHING=no; fi
refused "the decision form" 65 "refused: standing.s"
grep -qF ": the Source's decision form isn't written before koto's decision commands; write the row as inferred" "$T/err" \
    || needf "the refusal reads otherwise: $(cat "$T/err")"
[ -s "$T/koto.calls" ] || needf "the logging koto was never run"
grep -qE '(^| )decisions?( |$)' "$T/koto.calls" && needf "a koto decision command ran: $(grep -E '(^| )decisions?( |$)' "$T/koto.calls")"
crit "R31. a decision Source is refused, 65, telling the writer to write it inferred, nothing written, and no koto decisions command runs"

# ---- R6 -------------------------------------------------------------------------
host_private true
try --standing rule --what "$WHAT" --source "$SRC_SKILL"
written "the skill write on a private host"
need "  ... its reads of acme/gadgets are the compare, then the contents" \
    "api --method GET repos/acme/gadgets/compare/$C...HEAD --jq .status|api --method GET repos/acme/gadgets/contents/$SKILL?ref=$C --jq .content" \
    "$(grep 'acme/gadgets' "$T/calls" | tr '\n' '|' | sed 's/|$//')"
host_private false
crit "R6. on a private host, a skill row reads acme/gadgets' ancestry, then the file, and never its visibility"

# ---- R7, R8 ---------------------------------------------------------------------
for h in false true; do
    host_private "$h"
    for c in "$D:diverged" "$E:behind"; do
        try --standing rule --what "$WHAT" --source "skill acme/gadgets $SKILL ${c%%:*}"
        refused "a ${c#*:} commit (private host $h)" 65 ": the Source names a commit acme/gadgets's default branch doesn't hold, or a repository that can't be read"
        need "  ... no contents read (private host $h, ${c#*:})" 0 "$(reads '/contents/')"
    done
done
host_private false
crit "R7. on each host, a commit the default branch doesn't hold (diverged, behind) is refused, 65, with no contents read"
try --standing rule --what "$TIP_ONLY" --source "$SRC_SKILL"
refused "a sentence the tip holds" 65 ": the What isn't a sentence of $SKILL at $C"
crit "R8. a What the file holds at the default branch's tip but not at the cited commit is refused, 65"

# ---- R9 -------------------------------------------------------------------------
for c in "repos/acme/gadgets --jq|cannot read acme/gadgets's visibility" \
    "/compare/|cannot read whether acme/gadgets's default branch holds $C" \
    "/contents/$SKILL|cannot read $SKILL at $C in acme/gadgets"; do
    fail_on "${c%%|*}" "gh: Server Error (HTTP 502)"
    try --standing rule --what "$WHAT" --source "$SRC_SKILL"
    refused "a 502 on ${c%%|*}" 2 "${c#*|}"
    tail -1 "$T/calls" | grep -qF -- "${c%%|*}" || needf "a read follows the failed one (${c%%|*}): $(tail -1 "$T/calls")"
done
no_fail
crit "R9. a visibility, compare or contents read failing with HTTP 502 exits 2 naming it, with no read after it and nothing written"

# ---- R10 ------------------------------------------------------------------------
mode sleep-compare
t0=$(date +%s)
FORGE_READ_SECONDS=1 try --standing rule --what "$WHAT" --source "$SRC_SKILL"
t1=$(date +%s)
mode none
refused "a compare past its bound" 2 "cannot read whether acme/gadgets's default branch holds $C"
[ $((t1 - t0)) -le 4 ] || needf "the write took $((t1 - t0)) seconds"
need "  ... no contents read" 0 "$(reads '/contents/')"
crit "R10. a compare read that sleeps past FORGE_READ_SECONDS=1 exits 2 within 4 seconds, with no contents read and nothing written"

# ---- R42 ------------------------------------------------------------------------
try --standing rule --what "$WHAT" --source "doc acme/widgets $DOC $F"
refused "a compare status of bogus" 2 "cannot read whether acme/widgets's default branch holds $F"
need "  ... no contents read" 0 "$(reads '/contents/')"
for c in "nonjson-visibility|cannot read acme/gadgets's visibility|repos/acme/gadgets --jq" \
    "nonjson-contents|cannot read $SKILL at $C in acme/gadgets|/contents/"; do
    m=${c%%|*}; rest=${c#*|}
    mode "$m"
    try --standing rule --what "$WHAT" --source "$SRC_SKILL"
    mode none
    refused "a body that isn't JSON ($m)" 2 "${rest%%|*}"
    tail -1 "$T/calls" | grep -qF -- "${rest#*|}" || needf "a read follows the unparsable one ($m): $(tail -1 "$T/calls")"
done
crit "R42. a compare status of bogus, and a visibility or contents read answering a body that isn't JSON, exit 2 naming the read, with no later read and nothing written"

# ---- R11, R12, R13 --------------------------------------------------------------
db 'del(.repos["acme/tools"])'
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
refused "an absent repository on a public host" 65 ": the Source names acme/tools, a repository that isn't public"
cp "$T/err" "$T/r11.absent"; need "  ... no compare or contents read of it (absent)" 0 "$(reads 'acme/tools/')"
db '.repos["acme/tools"] = {private: true, default_branch: "main"}'
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
refused "a private repository on a public host" 65 ": the Source names acme/tools, a repository that isn't public"
cp "$T/err" "$T/r11.private"; need "  ... no compare or contents read of it (private)" 0 "$(reads 'acme/tools/')"
db '.repos["acme/tools"].private = false'
fail_on "repos/acme/tools --jq" "gh: Not Found (HTTP 404)"
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
no_fail
refused "a 404 repository on a public host" 65 ": the Source names acme/tools, a repository that isn't public"
cp "$T/err" "$T/r11.404"; need "  ... no compare or contents read of it (404)" 0 "$(reads 'acme/tools/')"
grep -qF "private, or unreadable from the public host acme/widgets: acme/tools" "$T/r11.absent" || needf "the core's line is missing: $(cat "$T/r11.absent")"
cmp -s "$T/r11.absent" "$T/r11.private" && cmp -s "$T/r11.absent" "$T/r11.404" || needf "the three refusals differ"
crit "R11. on a public host, an absent, a private and a 404 repository each give byte-identical refusals, 65, with no compare or contents read of it"

host_private true
db 'del(.repos["acme/tools"])'
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
refused "an absent repository on a private host" 65 ": the Source names a commit acme/tools's default branch doesn't hold, or a repository that can't be read"
cp "$T/err" "$T/r12.absent"
db '.repos["acme/tools"] = {private: false, default_branch: "main"}'
fail_on "acme/tools/compare/" "gh: Not Found (HTTP 404)"
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
no_fail
cp "$T/err" "$T/r12.404"; refused "a 404 compare on a private host" 65 "can't be read"
db '.compare["acme/tools"] = {($c + "...HEAD"): "notfound"}' --arg c "$C"
try --standing rule --what "$WHAT" --source "skill acme/tools $SKILL $C"
cp "$T/err" "$T/r12.notfound"; refused "a notfound compare on a private host" 65 "can't be read"
cmp -s "$T/r12.absent" "$T/r12.404" && cmp -s "$T/r12.absent" "$T/r12.notfound" || needf "the three refusals differ"
host_private false
crit "R12. on a private host, an absent repository, a 404 compare and a notfound compare each give byte-identical refusals, 65"

fail_on "repos/acme/gadgets --jq" "gh: Forbidden (HTTP 403)"
try --standing rule --what "$WHAT" --source "$SRC_SKILL"
no_fail
refused "a 403 visibility read" 2 "cannot read acme/gadgets's visibility"
crit "R13. an HTTP 403 on the visibility read exits 2, not 65, writing nothing"

for h in false true; do
    host_private "$h"
    fail_on "/contents/docs/missing.md" "gh: Not Found (HTTP 404)"
    try --standing rule --what "$WHAT" --source "doc acme/widgets docs/missing.md $C"
    no_fail
    refused "a path missing at a readable commit (private host $h)" 65 ": the Source names docs/missing.md, which acme/widgets doesn't hold at $C"
done
host_private false
crit "R43. on each host, a path the readable commit doesn't hold is refused, 65, naming the path, the repository and the commit"

# ---- R26, R27, R28 --------------------------------------------------------------
empty_standing
try --standing rule --what "$WHAT" --source inferred; written "the inferred write"; cp "$T/calls" "$T/log.inferred"
need "R28: the inferred write reads the host twice" 2 "$(grep -cxF 'api --method GET repos/acme/widgets --jq .private' "$T/log.inferred")"
need "  ... and nothing else" 2 "$(grep -c . "$T/log.inferred")"
empty_standing
try --standing rule --what "$WHAT" --source "$SRC_DOC"; written "the doc write"; cp "$T/calls" "$T/log.doc"
empty_standing
try --standing rule --what "$WHAT" --source "$SRC_SKILL"; written "the skill write"; cp "$T/calls" "$T/log.skill"
need "R26: the doc write's extra reads are the compare, then the contents" \
    "> api --method GET repos/acme/widgets/compare/$C...HEAD --jq .status|> api --method GET repos/acme/widgets/contents/$DOC?ref=$C --jq .content" \
    "$(diff "$T/log.inferred" "$T/log.doc" | grep '^[<>]' | tr '\n' '|' | sed 's/|$//')"
need "R27: the skill write's extra reads are the visibility, the compare, then the contents" \
    "> api --method GET repos/acme/gadgets --jq .private|> api --method GET repos/acme/gadgets/compare/$C...HEAD --jq .status|> api --method GET repos/acme/gadgets/contents/$SKILL?ref=$C --jq .content" \
    "$(diff "$T/log.inferred" "$T/log.skill" | grep '^[<>]' | tr '\n' '|' | sed 's/|$//')"
crit "R26-R28. a host-cited doc write adds only the compare and the file to an inferred write's reads, a skill write citing acme/gadgets its visibility, the compare and the file, and an inferred write reads the host twice, the writer's (which the core reuses) and the entry's"

# ---- R37, R38, R39, R41 ---------------------------------------------------------
for r in acme/secret '`acme/secret`' other/hidden acme/ghost; do
    try --standing rule --what "Never read $r from here." --source inferred
    rr=${r//\`/}
    refused "a What naming $r" 65 "names $rr, a repository that isn't public"
done
crit "R37. an inferred row whose What names acme/secret, \`acme/secret\`, other/hidden or acme/ghost is refused, 65, naming it, with nothing written"
for x in "and/or|Use one and/or the other." "CI/CD|Wait for the CI/CD checks." "other/absent|Ask other/absent first." "-|Read skills/coordinate/SKILL.md first."; do
    tok=${x%%|*}
    try --standing rule --what "${x#*|}" --source inferred
    written "a What holding $tok"
    if [ "$tok" = - ]; then
        need "  ... no read of the three-part path" 0 "$(reads 'repos/skills')"
    else
        need "  ... one visibility read of $tok" 1 "$(grep -cxF "api --method GET repos/$tok --jq .private" "$T/calls")"
    fi
done
crit "R38. Whats holding and/or, CI/CD, other/absent and skills/coordinate/SKILL.md are written, with one visibility read per two-part token and none for the three-part path"
host_private true
for r in acme/secret '`acme/secret`' other/hidden acme/ghost; do
    try --standing rule --what "Never read $r from here." --source inferred
    written "a What naming $r on a private host"
    need "  ... no read naming it" 0 "$(reads "repos/${r//\`/}")"
done
host_private false
crit "R39. on a private host, R37's Whats are written, with no read naming any token"
fail_on "repos/other/absent" "gh: Server Error (HTTP 502)"
try --standing rule --what "Ask other/absent first." --source inferred
no_fail
refused "a 502 on a token's read" 2 "cannot read other/absent's visibility"
crit "R41. a What token whose visibility read fails with HTTP 502 exits 2, not 65, writing nothing"

# ---- R14, R15, R16, R17 ---------------------------------------------------------
# standing_fixture <rule rows> <inferred among them> <kinds|event row count>:
# a Standing value, the rule rows inferred and then pinned, then the event rows.
standing_fixture() {
    jq -nc --argjson r "$1" --argjson i "$2" --arg ev "$3" --arg pin "pinned charter $PA" '
        def row($n; $k): {standing: "s\($n)", kind: $k, on: "", until: "", what: "row \($n)", owner: "", relayed_by: "", set: "2026-10-20T08:00Z"};
        [range($r) | row(. + 1; "rule") + {source: (if . < $i then "inferred" else $pin end)}]
        + (if $ev == "kinds" then
             [row($r + 1; "pause") + {on: "all", until: "lifted", owner: "the human"},
              row($r + 2; "go-ahead") + {on: "Feature 1", owner: "the human"},
              row($r + 3; "approval") + {owner: "the human"}, row($r + 4; "answer") + {owner: "the human"},
              row($r + 5; "assignment") + {on: "#7", owner: "the human"}]
           else [range($ev | tonumber) | row($r + 1 + .; "approval") + {owner: "the human"}] end)' > "$T/fixture.json"
    put "$G" record/standing "$T/fixture.json"
}
CAP60="refused: standing: the record holds 60 inferred rule rows, the most it keeps; confirm or end one first"
CAP120="refused: standing: the record holds 120 rule rows, the most it keeps; end one first"
standing_fixture 120 60 kinds
for c in "inferred|$CAP60" "inferred brief worker $PB|$CAP60" "pinned charter $PA|$CAP120" "$SRC_SKILL|$CAP120" \
    "$SRC_DOC|$CAP120" "decision example 000000000007|$CAP120"; do
    try --standing rule --what "$WHAT" --source "${c%%|*}"
    refused "a ${c%% *} row at both caps" 65 "${c#*|}"
done
try --standing pause --on all --until lifted --what "hold everything" --owner "the human"
written "a pause at both caps"
crit "R14. with 120 rule rows (60 inferred) and one row of each event kind, a rule row of each Source form is refused naming its cap, 65, nothing written, while a pause is written"
standing_fixture 100 60 0
for s in inferred "inferred brief worker $PB"; do
    try --standing rule --what "$WHAT" --source "$s"
    refused "a ${s%% *} row at 60 inferred of 100" 65 "$CAP60"
done
try --standing rule --what "$WHAT" --source "pinned charter $PA"
written "a pinned row at 60 inferred of 100"
crit "R15. with 60 inferred among 100 rule rows, an inferred or inferred brief row is refused naming 60, and a pinned row is written"
standing_fixture 119 59 30
try --standing rule --what "$WHAT" --source inferred
written "the 60th inferred row"
# --counts also counts each Run rules row in its class, and the record's
# `rules charter` row, a label neither skill- nor workspace-, reads inferred:
# the 60 inferred Standing rows and that row.
need "  ... --rules --counts prints inferred 61, the 60 rows and the charter Run row" "inferred 61" "$(w --rules --counts 2>/dev/null | grep '^inferred ')"
crit "R16. with 119 rule rows (59 inferred) and 30 event rows, one more inferred row is written and --rules --counts counts the 60 inferred rows (inferred 61 beside the record's charter Run row)"
standing_fixture 121 0 0
try --run friction rules-friction --by x
written "an unrelated write over 121 rule rows"
w --rules > /dev/null 2> "$T/err"
need "  ... and --rules" 0 "$?$(cat "$T/err")"
crit "R17. with 121 rule rows stored, --run friction and --rules each exit 0: no read checks the caps"

# ---- R34, R35, R36 --------------------------------------------------------------
empty_standing
try --standing rule --what "$WHAT" --source "$SRC_SKILL"
written "the skill write"
N=$(last_row | jq -r .standing)
db '.repos["acme/gadgets"].private = true'
ctx "$G" record/standing > "$T/st.before"
try --run friction rules-later --by x
written "an unrelated write after acme/gadgets turns private"
need "  ... reading nothing of acme/gadgets" 0 "$(reads 'acme/gadgets')"
ctx "$G" record/standing > "$T/st.after"
cmp -s "$T/st.before" "$T/st.after" || needf "record/standing changed: $(cat "$T/st.after")"
w --rules --id "$N" > "$T/view.json" 2> "$T/err"
need "  ... and --rules still reads the row skill-says" "0 skill-says" "$? $(jq -r .class "$T/view.json")"
crit "R34, R36. after acme/gadgets turns private, an unrelated write exits 0 reading nothing of it and leaves record/standing byte for byte, and --rules still reads the row skill-says"
try --standing rule --what "$WHAT" --source "$SRC_SKILL"
refused "a new row citing acme/gadgets" 65 "names acme/gadgets, a repository that isn't public"
db '.repos["acme/gadgets"].private = false'
crit "R35. on that record, a new rule row citing acme/gadgets is refused, 65, naming it, with nothing written"

done_tests standing-rule-write-engine
