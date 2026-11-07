#!/usr/bin/env bash
# discipline-carry_engine_test.sh -- a discipline rotation that carried a
# predecessor recorded as manager, from the carry to its first report and the
# go-ahead, the shipped coordinate.md driven through real koto against the
# testdata/gh stand-in (docs/designs/DESIGN-coordinator-named-roles.md,
# Decision 6).
#
# Proves, one line per case:
#   1. the first rotation, which carried nothing: it opens as a manager and
#      its handover check lists no carry-unacknowledged; it sets a hold and a
#      go-ahead, and its window ends;
#   2. with an unacknowledged carry: the next start, given no --role, prints
#      role=manager from the ended rotation, and the carry reaches reconcile
#      with the role row manager. Once the other gaps are closed, --check
#      exits 1 listing carry-unacknowledged alone, though the carry brought
#      the first rotation's go-ahead, here dated after this run's start, so
#      only its being carried keeps it from clearing the gap; --md exits 0
#      while the gap is open, its line 3 the record line ending `Role:
#      manager.`; a `reconciled: reported` submit is refused and the run
#      stays in reconcile; once the go-ahead row is written, --check exits 0
#      and the submit moves on;
#   3. without one: a crash restart of that rotation (a second live run of
#      the discipline, so the opener carries it whole into a new run) reaches
#      reconcile in the same chain, the carried go-ahead dated back before
#      the chain started, so the go-ahead the rotation recorded is the one
#      that acknowledges the carry: --check exits 0 before --md, --md exits 0
#      naming the new run and manager, and the submit moves on, the order
#      Decision 3 states;
#   and across the whole suite no gh pr create, pr ready, contents write, ref
#   write or deletion.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/discipline-carry_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
. "$HERE/testdata/engine-session.sh"
mkdir -p "$T/bin"
ln -sf "$HERE/testdata/gh" "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"

# A clone-shaped workspace in a niwa instance that permits every finishing
# step, so the posture reads `readable`.
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(day -1)
DISC=carry

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
agent() { local s=$1; shift; (cd "$WD" && bash "$PS/$s" --session "$S" "$@"); } # a script as the agent runs it
key() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
# open_run [args json]: the opener's output in OPEN_OUT, its exit in OPEN_RC,
# its session in S; the args after the host are --role manager unless given.
open_run() {
    jq -nc --arg d "$DISC" --argjson a "${1:-[\"--role\",\"manager\"]}" '["--discipline", $d, "--host", "acme/widgets"] + $a' > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); OPEN_RC=$?
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
oline() { printf '%s\n' "$OPEN_OUT" | sed -n "s/^$1=//p"; }
# rotation_end_date <session> <date>: the rotation's window ends on <date>, as
# the agent writes it.
rotation_end_date() {
    key "$1" record/rotation | jq -c --arg e "$2" '.end = $e | if .start > $e then .start = $e else . end' > "$T/rot.json"
    (cd "$WD" && bash "$PS/state-stored-set.sh" --session "$1" --rotation "$T/rot.json") > /dev/null 2> "$T/w.err"
}
# to_reconcile: from a fresh run, through the find (and the open or the carry
# it names) to reconcile, passing the role= the opener printed as the
# directives say; prints the states it passed, space-separated.
to_reconcile() {
    local st path role
    role=$(oline role)
    st=$(at); path=$st
    if [ "$st" = record_open ]; then
        agent state-open.sh --role "$role" --start "$TODAY" --end "$(day 6)" > "$T/open.out" 2> "$T/w.err" || { echo "$path open-failed"; return; }
        st=$(at --with-data '{"opened":"opened"}'); path="$path $st"
    elif [ "$st" = predecessor_carry ]; then
        agent state-open.sh --carry --role "$role" > "$T/carry.out" 2> "$T/w.err" || { echo "$path carry-failed"; return; }
        st=$(at --with-data '{"carry":"carried"}'); path="$path $st"
    fi
    echo "$path"
}
# check: the handover gate's own call; the gaps it names, space-separated.
# Its exit is read by running the call again.
check() {
    agent state-handover.sh --check > /dev/null 2> "$T/check.err"
    sed -n 's/^  \([^:]*\): .*/\1/p' "$T/check.err" | tr '\n' ' ' | sed 's/ $//'
}
# md: the first report as the reconcile directive prints it; its exit in
# MD_RC, its output in $T/md.out.
md() { agent reconcile-report-get.sh --md > "$T/md.out" 2> "$T/md.err"; MD_RC=$?; }
role_row() { key "$1" record/run | jq -r '[.[] | select(.key == "role") | .value][0] // "none"'; }
w() { agent state-stored-set.sh "$@" > /dev/null 2> "$T/w.err"; }

db_init
if ! koto_store_ready; then
    echo "koto lacks the session store's features; a session rotation needs a newer koto"
    done_tests discipline-carry-engine
    exit $?
fi

echo "== 1. the first rotation, which carried nothing =="
open_run || { bad "the first rotation's run opens" "$(cat "$T/open.err")"; done_tests discipline-carry-engine; exit 1; }
R1=$S
eq "the find reads first and the open leads to reconcile" "record_open reconcile" "$(to_reconcile)"
eq "  ... with the role row manager" manager "$(role_row "$R1")"
case " $(check) " in *" carry-unacknowledged "*) bad "  ... its handover check lists no carry-unacknowledged" "$(cat "$T/check.err")" ;;
    *) ok "  ... its handover check lists no carry-unacknowledged" ;; esac
w --run arguments "--discipline carry --host acme/widgets" --by "the human" \
    && w --run cap 2 --by "the human" && w --run coordinator "$R1" --by "$R1"
eq "it writes the run's arguments, the cap and its address" 0 $?
jq -n '{hold: "after-cutover", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-10-01T10:00Z", lifted: ""}' > "$T/hold.json"
agent state-hold.sh --add --row-file "$T/hold.json" > /dev/null 2> "$T/w.err" \
    && w --standing go-ahead --what "ship the cutover" --owner "the human"
eq "  ... and sets a hold and a go-ahead" 0 $?
# The go-ahead dated after the next rotation's start, so only its being carried
# keeps it from acknowledging that rotation's carry.
key "$R1" record/standing | jq -c --arg s "$(day 1)T00:00Z" 'map(if .kind == "go-ahead" then .set = $s else . end)' > "$T/standing.json"
(cd "$WD" && koto context add "$R1" record/standing --from-file "$T/standing.json") > /dev/null 2>&1
eq "  ... dated tomorrow" "$(day 1)T00:00Z" "$(key "$R1" record/standing | jq -r '.[] | select(.kind == "go-ahead") | .set')"
rotation_end_date "$R1" "$YESTERDAY"; eq "  ... and its window ended yesterday" 0 $?

echo "== 2. the next rotation, with an unacknowledged carry =="
open_run '[]' || { bad "the next rotation's run opens" "$(cat "$T/open.err")"; done_tests discipline-carry-engine; exit 1; }
R2=$S
[ "$R2" != "$R1" ] && ok "a start with no --role opens the next rotation" || bad "a start with no --role opens the next rotation" "$OPEN_OUT"
eq "  ... printing role=manager, the ended rotation's" "0 manager" "$OPEN_RC $(oline role)"
eq "  ... and the carry reaches reconcile" "predecessor_carry reconcile" "$(to_reconcile)"
eq "  ... with the role row manager" manager "$(role_row "$R2")"
eq "  ... and the predecessor named" "$R1" "$(key "$R2" record/rotation | jq -r .predecessor)"
eq "the carry reports the hold and the go-ahead" "after-cutover|go-ahead:the human" \
    "$(key "$R2" coord/predecessor_carry.json | jq -r '"\([.holds[].hold] | join(" "))|\([.standing[] | "\(.kind):\(.owner)"] | join(" "))"')"
G=$(check)
case " $G " in *" carry-unacknowledged "*) ok "its handover check lists carry-unacknowledged" ;; *) bad "its handover check lists carry-unacknowledged" "$G" ;; esac
case " $G " in *" no-reports-to "*) ok "  ... and another gap, no-reports-to" ;; *) bad "  ... and another gap, no-reports-to" "$G" ;; esac
# The reconcile directive: every gap but carry-unacknowledged closes first.
w --run reports-to "the human" --by "the human" && w --run coordinator "$R2" --by "$R2"
eq "the other gaps are closed, and this run's address written" 0 $?
eq "  ... --check then lists carry-unacknowledged alone" "carry-unacknowledged" "$(check)"
agent state-handover.sh --check > /dev/null 2>&1; eq "  ... and exits 1" 1 $?
eq "  ... though the carry brought a go-ahead dated after this run's start" "go-ahead $(day 1)T00:00Z" \
    "$(key "$R2" record/standing | jq -r '.[] | select(.kind == "go-ahead") | "\(.kind) \(.set)"')"
eq "  ... which the handover read counts as carried, not acknowledged" "true false" \
    "$(agent state-handover.sh | jq -r '"\(.carry.carried) \(.carry.acknowledged)"')"
md
eq "--md exits 0 while carry-unacknowledged is open" 0 "$MD_RC"
eq "  ... its line 3 the record line, ending Role: manager." "Record: session \`$R2\` on \`acme/widgets\`. Role: manager." "$(sed -n 3p "$T/md.out")"
eq "  ... under the report's heading" "# Reconcile report" "$(sed -n 1p "$T/md.out")"
eq "a reconciled: reported submit is refused, the run staying in reconcile" reconcile "$(at --with-data '{"reconciled":"reported"}')"
eq "  ... and a tick with no evidence finds it there" reconcile "$(at)"
w --standing go-ahead --what "the carried state is acknowledged" --owner "the human"
eq "the person's go-ahead is written" 0 $?
GA=$(key "$R2" record/standing | jq -r '[.[] | select(.what == "the carried state is acknowledged") | .standing][0] // empty')
G=$(check)
agent state-handover.sh --check > /dev/null 2>&1; eq "  ... --check then exits 0" 0 $?
eq "  ... naming no gap" "" "$G"
ST=$(at --with-data '{"reconciled":"reported"}')
[ -n "$ST" ] && [ "$ST" != reconcile ] && ok "  ... and the submit moves on ($ST)" || bad "  ... and the submit moves on" "$ST $(cat "$T/tick.err")"

echo "== 3. a crash restart of that rotation, its go-ahead set in its chain =="
# The carried go-ahead dated back to when the first rotation set it, before
# this chain started, so only the go-ahead the rotation recorded can
# acknowledge the carry after the restart.
key "$R2" record/standing | jq -c --arg g "$GA" 'map(if .kind == "go-ahead" and .standing != $g then .set = "2026-10-01T10:00Z" else . end)' > "$T/standing.json"
(cd "$WD" && koto context add "$R2" record/standing --from-file "$T/standing.json") > /dev/null 2>&1
eq "the carried go-ahead is dated before the chain started" "2026-10-01T10:00Z" \
    "$(key "$R2" record/standing | jq -r --arg g "$GA" '.[] | select(.kind == "go-ahead" and .standing != $g) | .set')"
# A second live run of the discipline, holding no record: the rotation's run is
# no longer the scope's only live run, so it can't be resumed and the opener
# carries it whole into a new run.
EXTRA=coordinate-discipline-carry-$(date -u -d '+1 minute' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v+1M +%Y%m%dT%H%M%SZ)
jq -nc --arg p "$PR" '[["SCOPE", "discipline"], ["DISCIPLINE", "carry"], ["HOST_REPO", "acme/widgets"], ["PLUGIN_ROOT", $p]]' > "$T/extra-vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$EXTRA" "$TPL" "$T/extra-vars.json") > /dev/null 2> "$T/extra.err"
eq "a second live run of the discipline opens" 0 $?
open_run
R3=$S
case "$OPEN_OUT" in *"carried=$R2"*) ok "the restart carries the rotation whole into a new run" ;;
    *) bad "the restart carries the rotation whole into a new run" "$OPEN_OUT $(cat "$T/open.err")" ;; esac
[ "$R3" != "$R2" ] && ok "  ... a new run" || bad "  ... a new run" "$R3"
eq "  ... whose find reads its own rotation and reaches reconcile" reconcile "$(to_reconcile)"
eq "  ... with the role row manager" manager "$(role_row "$R3")"
w --run coordinator "$R3" --by "$R3"; eq "  ... the new run writes its own address" 0 $?
eq "  ... its chain starting where the rotation's did" "$(cd "$WD" && bash "$PS/coord-log.sh" chain-start --session "$R2")" \
    "$(cd "$WD" && bash "$PS/coord-log.sh" chain-start --session "$R3")"
eq "  ... so the one go-ahead set since it started is the one that rotation recorded" "$GA" \
    "$(agent state-handover.sh | jq -r '.carry.start as $s | [.standing[] | select(.kind == "go-ahead" and .set >= $s) | .standing] | join(" ")')"
G=$(check)
agent state-handover.sh --check > /dev/null 2>&1; eq "--check exits 0 before the report, the go-ahead set in the chain" 0 $?
eq "  ... naming no gap" "" "$G"
md
eq "--md then exits 0" 0 "$MD_RC"
eq "  ... its line 3 naming the new run and manager" "Record: session \`$R3\` on \`acme/widgets\`. Role: manager." "$(sed -n 3p "$T/md.out")"
ST=$(at --with-data '{"reconciled":"reported"}')
[ -n "$ST" ] && [ "$ST" != reconcile ] && ok "  ... and the submit moves on ($ST)" || bad "  ... and the submit moves on" "$ST $(cat "$T/tick.err")"

echo "== no GitHub write, the whole suite =="
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls" \
    && bad "no pull request, contents or ref write" "$(grep -E '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls")" \
    || ok "no pull request, contents or ref write"

done_tests discipline-carry-engine
