#!/usr/bin/env bash
# dispatch-common_test.sh -- the dispatch helpers: topic validation, niwa's
# session-name slug and exact match, the guarded workspace-root lookup, and
# the entry-point table reader, a repository's visibility read, the
# invocation and mode builders with a review-level bound, and whether a
# Claude Code job is finished.
#
# The workspace-root cases build real directory layouts: a root, an instance
# under it, a clone inside the instance carrying its own .niwa/workspace.toml
# (a workspace's config clone does), the root itself (which carries
# .niwa/instance.json too), and a directory outside any workspace.
#
# Usage: bash skills/coordinate/scripts/dispatch-common_test.sh
# Exit codes: 0 all pass; 1 a failure. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-common-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */dispatch-common-test.*) rm -rf "$T" ;; esac' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
yes() { if "${@:2}"; then ok "$1"; else bad "$1" "expected success"; fi; }
no()  { if "${@:2}"; then bad "$1" "expected failure"; else ok "$1"; fi; }

# a_times <n>: n letter a's, without seq (not on run-tests.sh's PATH).
a_times() { local i=0 out=""; while [ "$i" -lt "$1" ]; do out="${out}a"; i=$((i + 1)); done; printf '%s' "$out"; }

# --- topics -----------------------------------------------------------------------

yes "topic: plain"               dc_valid_topic coordinate-dispatch-path
yes "topic: digits"              dc_valid_topic f3-2
no  "topic: empty"               dc_valid_topic ""
no  "topic: leading dash"        dc_valid_topic -x
no  "topic: uppercase"           dc_valid_topic Foo
no  "topic: underscore"          dc_valid_topic foo_bar
no  "topic: slash"               dc_valid_topic ../x
no  "topic: dot"                 dc_valid_topic a.b
no  "topic: 65 characters"       dc_valid_topic "$(a_times 65)"

# --- niwa's slug and the exact session match ---------------------------------------

eq  "slug: dashes to underscores" coordinate_dispatch_path "$(dc_niwa_slug coordinate-dispatch-path)"
eq  "slug: runs collapse"         a_b "$(dc_niwa_slug 'a--b')"
eq  "slug: capped at 40"          "$(a_times 40)" "$(dc_niwa_slug "$(a_times 45)")"
eq  "slug: cap re-trims _"        "$(a_times 39)" "$(dc_niwa_slug "$(a_times 39)-bbb")"

yes "match: slug and token"       dc_session_matches api api-1a2b3c4d
yes "match: dashed topic"         dc_session_matches api-v2 api_v2-1a2b3c4d
no  "match: never a prefix"       dc_session_matches api api_v2-1a2b3c4d
no  "match: token too short"      dc_session_matches api api-1a2b3c4
no  "match: token not hex"        dc_session_matches api api-1a2b3c4z
no  "match: token uppercase"      dc_session_matches api api-1A2B3C4D
no  "match: trailing text"        dc_session_matches api api-1a2b3c4d-x

# --- the workspace root -------------------------------------------------------------

W="$T/ws"
mkdir -p "$W/.niwa" "$W/inst/.niwa" "$W/inst/public/config/.niwa" "$W/inst/public/app/src" "$T/elsewhere"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
: >"$W/inst/.niwa/instance.json"
: >"$W/inst/public/config/.niwa/workspace.toml"

eq  "root: from inside an instance"     "$W" "$(dc_workspace_root "$W/inst/public/app/src")"
eq  "root: from the instance itself"    "$W" "$(dc_workspace_root "$W/inst")"
eq  "root: a clone's workspace.toml is never taken" "$W" "$(dc_workspace_root "$W/inst/public/config")"
eq  "root: at the root, which also has instance.json" "$W" "$(dc_workspace_root "$W")"
no  "root: outside any workspace"       dc_workspace_root "$T/elsewhere"

O="$T/orphan"
mkdir -p "$O/inst/.niwa"
: >"$O/inst/.niwa/instance.json"
no  "root: an instance whose parent isn't a root" dc_workspace_root "$O/inst"

N="$T/noinst"
mkdir -p "$N/.niwa" "$N/sub"
: >"$N/.niwa/workspace.toml"
eq  "root: a root with no instance marker, from itself" "$N" "$(dc_workspace_root "$N")"
no  "root: below a markerless root, no walk-up to a lone workspace.toml" dc_workspace_root "$N/sub"

# --- the entry-point table -----------------------------------------------------------

eq  "entry: scope's leg"            scope "$(dc_entry_field scope 2)"
eq  "entry: execute's templates"    execute.md,execute-coordinated.md "$(dc_entry_field execute 3)"
eq  "entry: deliver answers its leg" deliver "$(dc_entry_field deliver 2)"
eq  "entry: work-on pins nothing" - "$(dc_entry_field work-on 4)"
eq  "entry: explore has no leg" - "$(dc_entry_field explore 2)"
no  "entry: unknown skill"          dc_entry_row nope
yes "flag: exact"                   dc_flag_allowed deliver --no-merge
yes "flag: wildcard value"          dc_flag_allowed scope --max-rounds=3
no  "flag: wildcard needs a value"  dc_flag_allowed scope --max-rounds=
no  "flag: not listed"              dc_flag_allowed deliver --merge
no  "flag: --koto-leg never listed" dc_flag_allowed scope --koto-leg=r:scope
no  "flag: --upstream never listed" dc_flag_allowed scope --upstream
no  "flag: coordinate allows none"  dc_flag_allowed coordinate --auto
no  "flag: with whitespace"         dc_flag_allowed deliver '--auto x'

# The target visibility an entry point requires, from a stand-in table: a
# row without the field reads as any, and a value outside the three is an
# error rather than a pass.
VT="$T/vis-entry-points.tsv"
printf 'a\t-\t-\t-\t-\n' >"$VT"
printf 'b\t-\t-\t-\t-\tpublic\twork-on\n' >>"$VT"
printf 'c\t-\t-\t-\t-\tsecret\t-\n' >>"$VT"
SAVED="$DC_ENTRY_POINTS"
DC_ENTRY_POINTS="$VT"
eq  "visibility: a row without the field is any" any "$(dc_entry_target_visibility a)"
eq  "visibility: a restricted row reads its value" public "$(dc_entry_target_visibility b)"
eq  "visibility: the alternative is field 7" work-on "$(dc_entry_field b "$DC_F_INSTEAD")"
dc_entry_target_visibility c >/dev/null; eq "visibility: an unknown value is an error (2)" 2 "$?"
dc_entry_target_visibility nope >/dev/null; eq "visibility: no row is 1" 1 "$?"
DC_ENTRY_POINTS="$SAVED"

# dc_repo_visibility reads gh api repos/<r>, through a gh stand-in.
GHB="$T/ghvis"
mkdir -p "$GHB"
cat >"$GHB/gh" <<'EOF'
#!/usr/bin/env bash
case "${@: -1}" in
    repos/o/pub) printf '{"visibility":"public"}\n' ;;
    repos/o/priv) printf '{"visibility":"private"}\n' ;;
    repos/o/int) printf '{"visibility":"internal"}\n' ;;
    repos/o/none) printf '{}\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$GHB/gh"
eq  "repo visibility: public" public "$(PATH="$GHB:$PATH" dc_repo_visibility o/pub)"
eq  "repo visibility: private" private "$(PATH="$GHB:$PATH" dc_repo_visibility o/priv)"
eq  "repo visibility: internal reads as private" private "$(PATH="$GHB:$PATH" dc_repo_visibility o/int)"
OUT=$(PATH="$GHB:$PATH" dc_repo_visibility o/none); RC=$?
eq  "repo visibility: no visibility field is 2, nothing printed" "2:" "$RC:$OUT"
OUT=$(PATH="$GHB:$PATH" dc_repo_visibility o/gone); RC=$?
eq  "repo visibility: a failed read is 2, nothing printed" "2:" "$RC:$OUT"

# --- the deadline ----------------------------------------------------------------------

dc_with_deadline 5 true; eq "deadline: a quick command's status" 0 "$?"
dc_with_deadline 5 false; eq "deadline: a failing command's status" 1 "$?"
# A caller's EXIT and TERM traps run in the caller alone. bash 5 ran them in
# the watcher when the TERM that stops it landed before the watcher had run
# its first command, which a quick command makes likely: in about one call in
# a hundred, the caller's EXIT trap ran in the watcher. Each trap appends a
# line, so over 1000 quick calls the file must end up with the caller's one
# EXIT line and nothing else; at that rate the old code fails the case nearly
# every run. bash 3.2 never showed it, so on the macOS floor the case passes
# either way; Linux CI's bash 5 is what checks it.
TRAPS="$T/caller-traps"
: >"$TRAPS"
(
    trap 'echo exit >>"$TRAPS"' EXIT
    trap 'echo term >>"$TRAPS"; exit 143' TERM
    i=0
    while [ "$i" -lt 1000 ]; do
        dc_with_deadline 30 true
        i=$((i + 1))
    done
)
eq "deadline: a caller's EXIT and TERM traps never run in the watcher" "exit" "$(cat "$TRAPS")"
START=$(date +%s)
dc_with_deadline 1 sleep 20; RC=$?
eq  "deadline: a command past it is 124" 124 "$RC"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "deadline: returns at the deadline"; else bad "deadline: returns at the deadline" ""; fi
# No watcher sleep outlives a quick command: its sleep length is unique to
# this run, so any process still running it afterwards is this run's leak.
# The check runs the moment the call returns, with no pause: the watcher
# waits on its sleep before it exits, so a sleep still listed here is a leak,
# not a slow exit. A zombie lists as <defunct> or [sleep] <defunct>, and
# this grep's own line has grep after its pid, so neither matches.
LEN=$(( 40000 + $$ % 10000 ))
# no_watcher_left <case>: the check, run right after a call. grep reads all
# of ps's output: with grep -q and pipefail, a ps longer than the pipe buffer
# dies of SIGPIPE at the first match and the match would read as none.
no_watcher_left() {
    local left
    left=$(ps -eo pid,args | grep -E "^ *[0-9]+ sleep $LEN\$")
    if [ -n "$left" ]; then bad "$1" "$left"; else ok "$1"; fi
}
if ! command -v ps >/dev/null 2>&1; then
    ok "deadline: no watcher left behind (not checked: ps isn't on this PATH)"
else
    dc_with_deadline "$LEN" true
    no_watcher_left "deadline: no watcher left behind"
    # bash drops a TERM that reaches the watcher's sleep before it execs (the
    # forked child still runs the watcher's trap). A sleep that ignores TERM
    # stands in for that one, and the command ends only once the sleep is
    # running, so the watcher has to stop it from its trap. The command fails
    # if it never sees the sleep, so the case can't pass without testing it.
    sleep() { if [ "$1" = "$LEN" ]; then trap '' TERM; exec sleep "$@"; fi; command sleep "$@"; }
    dc_with_deadline "$LEN" sh -c 'i=0; until ps -eo args | grep -q "^sleep $1\$"; do [ "$i" -ge 50 ] && exit 1; sleep 0.1; i=$((i + 1)); done' _ "$LEN"
    RC=$?
    unset -f sleep
    if [ "$RC" -ne 0 ]; then
        bad "deadline: no watcher left behind when its sleep ignores TERM" "the watcher's sleep was never seen running (status $RC)"
    else
        no_watcher_left "deadline: no watcher left behind when its sleep ignores TERM"
    fi
fi
# bash also drops a TERM that reaches the watcher while `trap` installs its
# handler. A watcher that ignores TERM for a second before its trap goes in
# stands in for that; the command ends once the watcher is inside that
# second, so the caller's first TERM is the one dropped, and the call still
# returns well before its deadline. As in the case above, the command fails
# if the watcher never gets there.
trap() { builtin trap '' TERM; : >"$T/ignoring"; command sleep 1; builtin trap "$@"; }
START=$(date +%s)
dc_with_deadline 20 sh -c 'i=0; until [ -e "$1" ]; do [ "$i" -ge 50 ] && exit 1; sleep 0.1; i=$((i + 1)); done' _ "$T/ignoring"
RC=$?
unset -f trap
if [ "$RC" -eq 0 ] && [ $(( $(date +%s) - START )) -lt 10 ]; then
    ok "deadline: a TERM the watcher drops as its trap goes in still stops it"
else
    bad "deadline: a TERM the watcher drops as its trap goes in still stops it" "status $RC after $(( $(date +%s) - START ))s"
fi
# A watcher that never installs its trap ignores every TERM, and stands in for
# one that won't stop: after about five seconds of TERMs the caller kills it
# and returns the command's own status, well before the deadline. The
# watcher's sleep is left to run out its 30 seconds.
trap() { builtin trap '' TERM; : >"$T/deaf"; }
START=$(date +%s)
dc_with_deadline 30 sh -c 'i=0; until [ -e "$1" ]; do [ "$i" -ge 50 ] && exit 1; sleep 0.1; i=$((i + 1)); done' _ "$T/deaf"
RC=$?
unset -f trap
if [ "$RC" -eq 0 ] && [ $(( $(date +%s) - START )) -lt 20 ]; then
    ok "deadline: a watcher that won't stop is killed and the call returns"
else
    bad "deadline: a watcher that won't stop is killed and the call returns" "status $RC after $(( $(date +%s) - START ))s"
fi
OUT=$(dc_with_deadline 30 echo hi); eq "deadline: output passes through a \$(...) promptly" hi "$OUT"
# The deadline's TERM reaches only the command's own pid; under dc_tree it
# reaches the command's children too. The child's stdout goes nowhere, as a
# git remote helper's goes to git, so nothing holds the $(...) open.
cat >"$T/forks.sh" <<EOF
#!/usr/bin/env bash
sleep 30 >/dev/null & echo \$! >"$T/child"; wait
EOF
chmod +x "$T/forks.sh"
START=$(date +%s)
OUT=$(dc_with_deadline 1 dc_tree "$T/forks.sh"); RC=$?
eq  "deadline under dc_tree: a command past it is 124" 124 "$RC"
if [ $(( $(date +%s) - START )) -lt 10 ]; then ok "deadline under dc_tree: returns at the deadline"; else bad "deadline under dc_tree: returns at the deadline" ""; fi
CHILD=$(cat "$T/child" 2>/dev/null)
# A child the TERM reached may not be reaped yet; one that outlived the TERM
# runs its whole 30 seconds, so a second's grace still catches it.
i=0
while [ -n "$CHILD" ] && [ "$i" -lt 20 ] && kill -0 "$CHILD" 2>/dev/null; do sleep 0.05; i=$((i + 1)); done
if [ -z "$CHILD" ]; then
    bad "deadline under dc_tree: the command's child is stopped too" "the command never started its child"
elif kill -0 "$CHILD" 2>/dev/null; then
    kill -KILL "$CHILD" 2>/dev/null
    bad "deadline under dc_tree: the command's child is stopped too" "pid $CHILD still running"
else
    ok "deadline under dc_tree: the command's child is stopped too"
fi
( dc_tree sh -c 'exit 3' ); eq "dc_tree: the command's own status" 3 "$?"
# The watcher writes its mark before it kills the command. A kill that pauses
# after every TERM (the watcher's subshell inherits the function) holds the
# command's end and the caller's TERM to the watcher wide apart, so with the
# mark moved back after the kill, that TERM would always land first and a
# deadline that passed would read as the killed command's 143.
kill() { builtin kill "$@"; local rc=$?; [ "${1-}" = -TERM ] && sleep 0.5; return $rc; }
dc_with_deadline 1 sleep 20; eq "deadline: still 124 when the caller's TERM reaches the watcher right after its kill" 124 "$?"
# A command that exits 0 from its own TERM trap keeps its 0 (its trap stops
# the sleep it started, so nothing outlives the case).
dc_with_deadline 1 sh -c 'trap "kill \$!; exit 0" TERM; sleep 20 & wait'; eq "deadline: a command that exits 0 as the deadline stops it keeps 0" 0 "$?"
unset -f kill

# --- the invocation and the holding's mode ---------------------------------------------
#
# A review_level adds its flags after the entry flags and before --koto-leg;
# the mode cell leaves them out, so a re-brief that rebuilds run_mode from it
# and keeps review_level doesn't give them twice.

printf '%s' '{"entry_point":"work-on","entry_args":["#12"],"run_mode":"--auto"}' >"$T/inv.json"
eq  "invocation: without a review level" "/shirabe:work-on #12 --auto" "$(dc_invocation "$T/inv.json")"
eq  "invocation: with a leg" "/shirabe:work-on #12 --auto --koto-leg=r_1:work-on" "$(dc_invocation "$T/inv.json" r_1:work-on)"
jq -c '.review_level = {"ceiling": "standard", "floor": "light"}' "$T/inv.json" >"$T/inv-rl.json"
eq  "invocation: the bound, floor first, before the leg" \
    "/shirabe:work-on #12 --auto --review-floor=light --review-ceiling=standard --koto-leg=r_1:work-on" \
    "$(dc_invocation "$T/inv-rl.json" r_1:work-on)"
jq -c '.review_level = {"ceiling": "standard"}' "$T/inv.json" >"$T/inv-c.json"
eq  "invocation: a ceiling alone" "/shirabe:work-on #12 --auto --review-ceiling=standard" "$(dc_invocation "$T/inv-c.json")"
eq  "mode: leaves the bound out" "--auto" "$(dc_mode "$T/inv-rl.json")"
jq -c --arg m "$(dc_mode "$T/inv-rl.json")" '.run_mode = $m | .entry_args = [.entry_args[0]]' "$T/inv-rl.json" >"$T/inv-re.json"
eq  "mode: a re-brief from the mode cell gives the bound once" \
    "/shirabe:work-on #12 --auto --review-floor=light --review-ceiling=standard" "$(dc_invocation "$T/inv-re.json")"

# The table against the skills it names: every skill exists, every template a
# leg admits exists and declares each pinned variable, and every flag's stem
# is one the skill's own SKILL.md mentions. A skill that renames a flag or a
# template shows up here, not at a worker's attach.
SKILLS="$HERE/../.."
while IFS='	' read -r skill leg tpls pinned flags vis instead; do
    case "$skill" in '' | '#'*) continue ;; esac
    [ -f "$SKILLS/$skill/SKILL.md" ] && ok "table: $skill exists" || bad "table: $skill exists" ""
    case "$vis" in
        any | public | private) [ -n "$instead" ] && ok "table: $skill's target visibility is any, public or private" ||
            bad "table: $skill's row has seven fields" "" ;;
        *) bad "table: $skill's target visibility is any, public or private" "[$vis]" ;;
    esac
    # Every shipped row carries all seven fields: a row cut short would read as
    # unrestricted, so the table itself is held to its full shape.
    if [ "$instead" = - ] || dc_entry_row "$instead" >/dev/null; then
        ok "table: $skill's alternative is - or an entry point"
    else
        bad "table: $skill's alternative is - or an entry point" "[$instead]"
    fi
    if [ "$tpls" != - ]; then
        IFS=, read -r -a TS <<EOF
$tpls
EOF
        for t in "${TS[@]}"; do
            f="$SKILLS/$skill/koto-templates/$t"
            [ -f "$f" ] && ok "table: $skill admits $t, which exists" || bad "table: $skill admits $t, which exists" "$f"
            if [ "$pinned" != - ]; then
                IFS=, read -r -a PS <<EOF
$pinned
EOF
                for p in "${PS[@]}"; do
                    grep -Eq "^  ${p%%=*}:" "$f" && ok "table: $t declares ${p%%=*}" || bad "table: $t declares ${p%%=*}" ""
                done
            fi
        done
    fi
    if [ "$flags" != - ]; then
        IFS=, read -r -a FS <<EOF
$flags
EOF
        for fl in "${FS[@]}"; do
            stem=${fl%%=*}
            grep -Fq -- "$stem" "$SKILLS/$skill/SKILL.md" && ok "table: $skill documents $stem" || bad "table: $skill documents $stem" ""
        done
    fi
done <"$DC_ENTRY_POINTS"

# --- unit matches past a pipe's capacity (shirabe#874) ---------------------------
# A pick.json whose units' forms run well past a pipe's buffer (6,000 issues,
# about 120 KiB of forms), with the unit asked for listed first. Piped into
# an early-exiting grep under pipefail, the writer was cut off once grep had
# matched and the match read as "not pick_facts' JSON" (exit 2); read without
# a pipe it matches every time.
jq -n '{scope: "discipline", host: "acme/widgets", units: [range(1; 6001) | {unit: "#\(.)", title: "t"}]}' > "$T/pick-big.json"
FORMS_BYTES=$(dc_unit_forms "$T/pick-big.json" | wc -c | tr -d ' ')
[ "$FORMS_BYTES" -gt 65536 ] && ok "unit matches: the forms run past a pipe's buffer ($FORMS_BYTES bytes)" \
    || bad "unit matches: the forms run past a pipe's buffer" "$FORMS_BYTES bytes"
um_rc=
for i in 1 2 3; do dc_unit_matches "#1" "$T/pick-big.json"; um_rc="$um_rc$?"; done
eq "unit matches: the first unit of a large pick matches, 3 of 3" 000 "$um_rc"
dc_unit_matches "acme/widgets#1" "$T/pick-big.json"; eq "unit matches: its host form too" 0 $?
dc_unit_matches "#6001" "$T/pick-big.json"; eq "unit matches: a unit pick didn't list doesn't" 1 $?
printf 'not json\n' > "$T/pick-bad.json"
dc_unit_matches "#1" "$T/pick-bad.json"; eq "unit matches: a file that isn't pick_facts' JSON is 2" 2 $?

# --- a finished job (shirabe#1182) -------------------------------------------------
# Finished means the job's own state file reads done, stopped or failed and
# the listing shows no live pid. The listing's state is never read: Claude
# Code 2.1.309 lists every job as working, a stopped one included. A live pid
# is this shell's; a dead one is a reaped child's.
CH="$T/claude-home"
JF=4b3597d2
mkdir -p "$CH/jobs/$JF"
jstate() { printf '%s\n' "$1" >"$CH/jobs/$JF/state.json"; }
sleep 0 &
DEAD=$!
wait "$DEAD"
LIVE=$$
# The rows are built before any $(...) that passes one: bash 3.2 keeps the
# backslash of a \" inside a double-quoted command substitution.
ROW_DEAD=$(jq -nc --argjson p "$DEAD" '{state: "working", pid: $p}')
ROW_LIVE=$(jq -nc --argjson p "$LIVE" '{state: "done", pid: $p}')
for s in done stopped failed; do
    jstate "{\"state\":\"$s\"}"
    yes "job: state file $s, listed working with no pid" dc_job_finished "$CH" "$JF" '{"state":"working"}'
    yes "job: state file $s, a null pid" dc_job_finished "$CH" "$JF" '{"state":"working","pid":null}'
    yes "job: state file $s, a dead pid" dc_job_finished "$CH" "$JF" "$ROW_DEAD"
    eq  "job: state file $s, a live pid" "job $JF is still running (pid $LIVE)" "$(dc_job_finished "$CH" "$JF" "$ROW_LIVE")"
done
jstate '{"state":"done"}'
yes "job: the listing's state missing" dc_job_finished "$CH" "$JF" '{}'
yes "job: the listing's state unknown" dc_job_finished "$CH" "$JF" '{"state":"waiting"}'
eq  "job: a pid that isn't one" "job $JF lists pid [abc], which is not a pid" \
    "$(dc_job_finished "$CH" "$JF" '{"pid":"abc"}')"
no  "job: pid 0 isn't one" dc_job_finished "$CH" "$JF" '{"pid":0}'
no  "job: a negative pid isn't one" dc_job_finished "$CH" "$JF" '{"pid":-1}'
no  "job: a row that isn't an object" dc_job_finished "$CH" "$JF" '[]'
no  "job: a row that isn't JSON" dc_job_finished "$CH" "$JF" 'not json'
no  "job: a job id that isn't one" dc_job_finished "$CH" "../$JF" '{}'
for row in '{"state":"done"}' '{"state":"working"}' '{"state":"done","pid":null}'; do
    jstate '{"state":"working"}'
    eq  "job: state file working, listed $row" "the state file of job $JF reads working" "$(dc_job_finished "$CH" "$JF" "$row")"
done
jstate '{"state":"waiting"}'
eq  "job: state file in an unknown state" "the state file of job $JF reads [waiting], which isn't known to be finished" \
    "$(dc_job_finished "$CH" "$JF" '{}')"
jstate '{"createdAt":"2026-10-01T09:00:00.000Z"}'
no  "job: state file with no state" dc_job_finished "$CH" "$JF" '{}'
jstate 'not json'
eq  "job: state file that isn't JSON" "the state file of job $JF is not readable JSON" "$(dc_job_finished "$CH" "$JF" '{}')"
rm -f "$CH/jobs/$JF/state.json"
eq  "job: no state file" "job $JF has no state file at $CH/jobs/$JF/state.json" "$(dc_job_finished "$CH" "$JF" '{}')"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
