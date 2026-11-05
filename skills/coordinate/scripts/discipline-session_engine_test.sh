#!/usr/bin/env bash
# discipline-session_engine_test.sh -- a discipline rotation on the session
# store, the shipped coordinate.md driven through real koto against the
# testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3).
#
# Proves, one line per case:
#   1. the discipline's first rotation: the find reads `first`, record_open
#      opens the rotation in the run's session with its window, and the next
#      find reaches reconcile;
#   2. a start inside the open rotation is a restart: a live run on the
#      shipped template is resumed (resumed=1, nothing opened or cancelled);
#      one that can't be resumed (here, a second live run of the discipline,
#      so the rotation's run isn't the only live one) is carried whole into
#      a new run, the live run cancelled, the same rotation and no second one;
#   3. a start on the rotation's end date is still a restart;
#   4. a start on the day after the end date opens the next rotation through
#      the predecessor path: the find reads `predecessor <session>`, the carry
#      lands and the next find reaches reconcile;
#   5. a start after an early close inside the window (the reasoning written)
#      opens the next rotation the same way, carrying the second rotation and
#      never the first, and its reconcile reads the reasoning as present;
#   6. the rotation ends at rotation_end: past its window, pick_facts and the
#      close-out route it there, the reasoning is written and the run ends
#      closed, naming its session as the record;
#   7. one scenario per rule an earlier session breaks (its name, provenance,
#      discipline, host, a predecessor another rotation names, two at one
#      stamp): each find reads `unreadable <session>`, the run stops at
#      record_conflict, and nothing is carried;
#   8. the run's role on a carried rotation
#      (docs/designs/DESIGN-coordinator-named-roles.md, Decision 1): the
#      opener reads the ended rotation's role, prints role= for the carry,
#      refuses both directions of mismatch and a failed read with nothing
#      opened, refuses a dispatcher change naming a session the record doesn't
#      report to, the ended rotation itself or its predecessor, and on an
#      accepted dispatcher or person change prints role_changed_from=,
#      role_change_by= and role_change_source=, which predecessor_carry passes
#      to state-open.sh --carry, the new rotation's row then holding the new
#      role with its set_by and entry; a role-less ended rotation is asked
#      before the carry and, given --role, the carry adds the row;
#   and across the whole suite no gh pr create, pr ready, contents write, ref
#   write or deletion, and no git push.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/discipline-session_engine_test.sh
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
# git is wrapped so a push anywhere in the suite is seen.
REAL_GIT=$(command -v git)
printf '#!/bin/sh\ncase "$1" in push) echo "git push $*" >> "%s/git.calls" ;; esac\nexec "%s" "$@"\n' "$T" "$REAL_GIT" > "$T/bin/git"
chmod +x "$T/bin/git"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"

WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(day -1)
WEEK_AGO=$(day -7)

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
agent() { local s=$1; shift; (cd "$WD" && bash "$PS/$s" --session "$S" "$@"); } # a script as the agent runs it
key() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
token() { (cd "$WD" && bash "$PS/coord-log.sh" capture --session "$S" --name RECORD_FIND 2>/dev/null) | sed 's/ sealed:.*//'; }
# open_run <discipline> [args json]: the opener's output in OPEN_OUT, its
# exit in OPEN_RC, its session in S; the args after the host are --role
# manager unless given.
open_run() {
    jq -nc --arg d "$1" --argjson a "${2:-[\"--role\",\"manager\"]}" '["--discipline", $d, "--host", "acme/widgets"] + $a' > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); OPEN_RC=$?
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
# oline <name>: a result line of the last open.
oline() { printf '%s\n' "$OPEN_OUT" | sed -n "s/^$1=//p"; }
# rotation_end_date <session> <date>: the rotation's window ends on <date>, as
# the agent writes it.
rotation_end_date() {
    key "$1" record/rotation | jq -c --arg e "$2" '.end = $e | if .start > $e then .start = $e else . end' > "$T/rot.json"
    (cd "$WD" && bash "$PS/state-stored-set.sh" --session "$1" --rotation "$T/rot.json") > /dev/null 2> "$T/w.err"
}
# to_reconcile: from a fresh run, through the find (and the open or the carry it
# names) to reconcile; prints the states it passed, space-separated. The open
# and the carry pass the role the opener printed (role=), and the carry the
# change it printed (role_change_by=, role_change_source=), as their
# directives say.
to_reconcile() {
    local st path role by src
    role=$(oline role) by=$(oline role_change_by) src=$(oline role_change_source)
    st=$(at); path=$st
    if [ "$st" = record_open ]; then
        agent state-open.sh --role "$role" --start "$TODAY" --end "$(day 6)" > "$T/open.out" 2> "$T/w.err" || { echo "$path open-failed"; return; }
        st=$(at --with-data '{"opened":"opened"}'); path="$path $st"
    elif [ "$st" = predecessor_carry ]; then
        if [ -n "$by" ]; then
            agent state-open.sh --carry --role "$role" --role-change-by "$by" --role-change-source "$src" > "$T/carry.out" 2> "$T/w.err" || { echo "$path carry-failed"; return; }
        else
            agent state-open.sh --carry --role "$role" > "$T/carry.out" 2> "$T/w.err" || { echo "$path carry-failed"; return; }
        fi
        st=$(at --with-data '{"carry":"carried"}'); path="$path $st"
    fi
    echo "$path"
}

db_init
if ! koto_store_ready; then
    echo "koto lacks the session store's features; a session rotation needs a newer koto"
    done_tests discipline-session-engine
    exit $?
fi

echo "== 1. the first rotation =="
DISC=ops
open_run ops || { bad "the first rotation's run opens" "$(cat "$T/open.err")"; done_tests discipline-session-engine; exit 1; }
S1=$S
eq "the find reads first and the open leads to reconcile" "record_open reconcile" "$(to_reconcile)"
eq "  ... the find's token was first, then found" found "$(token)"
eq "  ... the rotation's window is in the session, with no predecessor" "$TODAY null" "$(key "$S1" record/rotation | jq -r '"\(.start) \(.predecessor)"')"

echo "== 2. a restart inside the open rotation =="
open_run ops
eq "a live run on the shipped template is resumed" "outcome=resumed resumed=1 session=$S1 role=manager" "$(printf '%s' "$OPEN_OUT" | tr '\n' ' ' | sed 's/ $//')"
# A second live run of the discipline, holding no record: the rotation's run is
# no longer the scope's only live run, so it can't be resumed.
EXTRA=coordinate-discipline-ops-$(date -u -d '+1 minute' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v+1M +%Y%m%dT%H%M%SZ)
jq -nc --arg p "$PR" '[["SCOPE", "discipline"], ["DISCIPLINE", "ops"], ["HOST_REPO", "acme/widgets"], ["PLUGIN_ROOT", $p]]' > "$T/extra-vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$EXTRA" "$TPL" "$T/extra-vars.json") > /dev/null 2> "$T/extra.err"
eq "a second live run of the discipline opens" 0 $?
ROT1=$(key "$S1" record/rotation)
open_run ops
S2=$S
# The live runs are cancelled only once the carry has landed (shirabe#1257).
case "$OPEN_OUT" in *"carried=$S1"*"cancelled="*) ok "a run that can't be resumed is carried" ;;
    *) bad "a run that can't be resumed is carried" "$OPEN_OUT $(cat "$T/open.err")" ;; esac
case "$OPEN_OUT" in *"cancelled=$S1"*) ok "  ... the live run cancelled" ;; *) bad "  ... the live run cancelled" "$OPEN_OUT" ;; esac
eq "  ... into a new run holding the same rotation" "$ROT1" "$(key "$S2" record/rotation)"
eq "  ... whose find reads its own rotation" "reconcile" "$(to_reconcile)"
eq "  ... with no second rotation" found "$(token)"

echo "== 3. a start on the end date =="
rotation_end_date "$S2" "$TODAY"; eq "the window now ends today" 0 $?
open_run ops
eq "a start on the end date is a restart" "outcome=resumed resumed=1 session=$S2 role=manager" "$(printf '%s' "$OPEN_OUT" | tr '\n' ' ' | sed 's/ $//')"

echo "== 4. a start on the day after the end date =="
rotation_end_date "$S2" "$YESTERDAY"; eq "the window ended yesterday" 0 $?
open_run ops
S3=$S
[ "$S3" != "$S2" ] && ok "a new run opens" || bad "a new run opens" "$OPEN_OUT"
case "$OPEN_OUT" in *carried=*) bad "  ... carrying nothing whole" "$OPEN_OUT" ;; *) ok "  ... carrying nothing whole" ;; esac
eq "the find reads the predecessor, the carry lands, and the next find reaches reconcile" "predecessor_carry reconcile" "$(to_reconcile)"
eq "  ... the rotation names the predecessor" "$S2" "$(key "$S3" record/rotation | jq -r .predecessor)"

echo "== 5. a start after an early close =="
printf 'The deploy job flakes on Mondays; watch it.\n' > "$T/why.txt"
(cd "$WD" && bash "$PS/state-stored-set.sh" --session "$S3" --reasoning-file "$T/why.txt") > /dev/null 2> "$T/w.err"
eq "the second rotation closes early with its reasoning" 0 $?
open_run ops
S4=$S
eq "the next start opens the third rotation through the predecessor path" "predecessor_carry reconcile" "$(to_reconcile)"
eq "  ... carrying the second rotation, never the first" "$S3" "$(key "$S4" record/rotation | jq -r .predecessor)"
eq "  ... and its reconcile reads the reasoning as present" present "$(key "$S4" reconcile/report.json | jq -r '.reasoning.status')"
eq "  ... verbatim" "The deploy job flakes on Mondays; watch it." "$(key "$S4" reconcile/reasoning.md)"

echo "== 6. the rotation ends at rotation_end =="
S=$S4
{ agent state-stored-set.sh --run arguments "--discipline ops --host acme/widgets" --by "the human" \
  && agent state-stored-set.sh --run cap 2 --by "the human" \
  && agent state-stored-set.sh --run coordinator ops-lead --by ops-lead \
  && agent state-stored-set.sh --run reports-to "the human" --by "the human" \
  && agent state-stored-set.sh --standing go-ahead --what "the carried state is acknowledged" --owner "the human"; } > /dev/null 2> "$T/w.err"
eq "the handover facts and the carry's go-ahead are written" 0 $?
rotation_end_date "$S4" "$YESTERDAY"
ST=$(at --with-data '{"reconciled":"reported"}')
eq "past its window the rotation reaches rotation_end" rotation_end "$ST"
eq "  ... and holds there until the reasoning is written" rotation_end "$(at --with-data '{"reasoning":"written"}')"
printf 'Nothing carried over that the tables miss.\n' > "$T/why.txt"
agent state-stored-set.sh --reasoning-file "$T/why.txt" > /dev/null 2> "$T/w.err"
OUT=$(tick --with-data '{"reasoning":"written"}')
eq "the run ends at done" done "$(printf '%s' "$OUT" | jq -r '.state // empty' 2>/dev/null)"
printf '%s\n' "$OUT" > "$T/done.json"; (cd "$WD" && koto status "$S4") > "$T/status.json" 2>&1
eq "  ... closed" closed "$(key "$S4" outcome)"
eq "  ... naming its session as the record" "$S4" "$(key "$S4" record_url)"

echo "== 7. an earlier session that breaks one rule =="
# craft <discipline> <name> <vars-json> [template]: an earlier rotation, ended,
# opened from the template (the shipped one unless given) with those variables.
craft() {
    local d=$1 n=$2 vars=$3 tpl=${4:-$TPL}
    printf '%s' "$vars" | jq -c 'to_entries | map([.key, .value])' > "$T/craft-vars.json"
    (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$n" "$tpl" "$T/craft-vars.json") > /dev/null 2> "$T/craft.err" || { echo "craft $n: $(cat "$T/craft.err")"; return 1; }
    jq -nc --arg n "$d" '{scope: {kind: "discipline", name: $n}, store: "session", written: "2026-10-01T10:00:00Z", pending: false}' > "$T/meta.json"
    for k in holdings deferrals side-effects reversals; do (cd "$WD" && printf '[]' | koto context add "$n" "record/$k"); done
    jq -nc --arg s "$WEEK_AGO" --arg e "$YESTERDAY" '{start: $s, end: $e, host_repo: "acme/widgets", predecessor: null}' > "$T/rot.json"
    (cd "$WD" && koto context add "$n" record/rotation --from-file "$T/rot.json" && koto context add "$n" record/meta --from-file "$T/meta.json" && koto cancel "$n") > /dev/null
}
vars_of() { jq -nc --arg d "$1" --arg h "${2:-acme/widgets}" --arg p "$PR" '{SCOPE: "discipline", DISCIPLINE: $d, HOST_REPO: $h, PLUGIN_ROOT: $p}'; }
stops() { # stops <label> <discipline> <expected-session>
    DISC=$2
    open_run "$2" || { bad "$1: the run opens" "$(cat "$T/open.err")"; return; }
    local st; st=$(at)
    eq "$1: the find reads unreadable <session>" "unreadable $3" "$(token)"
    eq "  ... and stops at record_conflict" record_conflict "$st"
    eq "  ... carrying nothing" "" "$(cd "$WD" && koto context list "$S" --prefix record/ | jq -r '.[]')"
}
craft badname coordinate-discipline-badname-20261001T100000Zx "$(vars_of badname)"
stops "a name that isn't coordinate-<slug>-<stamp>" badname coordinate-discipline-badname-20261001T100000Zx
# A structural change: a text-only one passes provenance through the compat
# table (coordinate.compat.json).
sed 's/^variables:$/variables:\n  PROVENANCE_PROBE:\n    description: A variable the shipped template does not declare.\n    default: ""/' "$TPL" > "$T/other-template.md"
craft prov coordinate-discipline-prov-20261001T100000Z "$(vars_of prov)" "$T/other-template.md"
stops "a session that fails provenance" prov coordinate-discipline-prov-20261001T100000Z
craft disc coordinate-discipline-disc-20261001T100000Z "$(vars_of other)"
stops "a session of another discipline" disc coordinate-discipline-disc-20261001T100000Z
craft host coordinate-discipline-host-20261001T100000Z "$(vars_of host acme/gadgets)"
stops "a session on another host" host coordinate-discipline-host-20261001T100000Z
craft named coordinate-discipline-named-20261001T100000Z "$(vars_of named)"
craft named coordinate-discipline-named-20261002T100000Zx "$(vars_of named)"
jq -nc --arg p coordinate-discipline-named-20261001T100000Z '{start: "2026-10-02", end: "2026-10-08", host_repo: "acme/widgets", predecessor: $p}' > "$T/rot.json"
(cd "$WD" && koto context add coordinate-discipline-named-20261002T100000Zx record/rotation --from-file "$T/rot.json" \
    && koto context remove coordinate-discipline-named-20261002T100000Zx record/meta) > /dev/null
stops "a predecessor another rotation already names" named coordinate-discipline-named-20261001T100000Z
craft twin coordinate-discipline-twin-20261001T100000Z "$(vars_of twin)"
craft twin coordinate-discipline-twin-20261001T100000Zb "$(vars_of twin)"
stops "two earlier rotations at one stamp" twin coordinate-discipline-twin-20261001T100000Z

echo "== 8. the role on a carried rotation =="
# The ended rotation is the candidate the opener reads the role of; the new
# run's find carries it, and predecessor_carry writes what the opener printed.
# A shim in front of the real koto fails every read of one run's record/run
# (RR_RUN).
REAL_KOTO=$(command -v koto)
cat > "$T/rrshim" <<EOF
#!/bin/sh
if [ -n "\$RR_RUN" ] && [ "\$3" = "\$RR_RUN" ]; then
    case "\$1 \$2 \$*" in "context list "*record/run*|"context get "*record/run*) echo "koto: the read of record/run failed" >&2; exit 1 ;; esac
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/rrshim"
sessions() { (cd "$WD" && koto session list 2>/dev/null) | jq -r '.[].id' | sort | tr '\n' ' '; }
# dsnap <run>: its record keys and values, its log's length and the session list.
dsnap() {
    local k
    { for k in $( (cd "$WD" && koto context list "$1" --prefix record/) | jq -r '.[]'); do printf '%s %s\n' "$k" "$(key "$1" "$k" | jq -cS .)"; done
      wc -l < "$( (cd "$WD" && koto session dir "$1"))/koto-$1.state.jsonl" | tr -d ' '; sessions; } | $SHA256
}
drow() { key "$1" record/run | jq -r '[.[] | select(.key == "role")] | if length == 0 then "none" else (.[0] | "\(.value)|\(.set_by)") end'; }
dentry() { (cd "$WD" && bash "$PS/state-entry.sh" --session "$1" --list 2>/dev/null) | jq -r '[.[] | select(.text | startswith("Run role"))] | last | .text // empty'; }
rmsg() { grep '^coordinate-open: ' "$T/open.err" | tail -1; }
RADDR=coordinate-roadmap-ops-director-20260926T080000Z
RRT="Ops lead at $RADDR"
DISC=rot
open_run rot || bad "8: the first rotation opens" "$(cat "$T/open.err")"
R1=$S
eq "8: the first rotation opens as a manager" "record_open reconcile manager|start --role" "$(to_reconcile) $(drow "$R1")"
agent state-stored-set.sh --run reports-to "$RRT" --by "the human" > /dev/null 2> "$T/w.err"
eq "8:   ... reporting to an address" 0 $?
rotation_end_date "$R1" "$YESTERDAY"
R1SNAP=$(dsnap "$R1")
open_run rot '["--role","director"]'
eq "8: a start naming director after a rotation recorded manager ended is refused role-mismatch" "2 refused role-mismatch" "$OPEN_RC $(oline outcome) $(oline reason)"
eq "8:   ... the whole message" "coordinate-open: $R1 is recorded as manager; this start names director. A continuation keeps its role unless an intervention from above changes it; nothing was written and $R1 goes on as it was. Start again naming manager, or no role, or start director as a new lineage." "$(rmsg)"
eq "8:   ... nothing opened, nothing written" "$R1SNAP" "$(dsnap "$R1")"
RR_RUN=$R1 KOTO_BIN="$T/rrshim" open_run rot
eq "8: a start whose read of the ended rotation's role fails is failed=role_read, exit 1" "1 role_read" "$OPEN_RC $(oline failed)"
eq "8:   ... nothing opened, nothing written" "$R1SNAP" "$(dsnap "$R1")"
for who in lane-other "$R1"; do
    open_run rot "[\"--role\",\"director\",\"--role-change-by\",\"$who\",\"--role-change-source\",\"dispatcher\"]"
    eq "8: a dispatcher change naming $who is refused" "2 role-change-refused" "$OPEN_RC $(oline reason)"
    case "$(rmsg)" in "coordinate-open: $R1 reports to $RRT"*"This start names director; nothing was written and $R1 goes on as manager.") pass "8:   ... naming the reports-to row and both roles" ;;
        *) fail "8:   ... naming the reports-to row and both roles" "$(rmsg)" ;; esac
done
eq "8:   ... nothing opened, nothing written" "$R1SNAP" "$(dsnap "$R1")"
T0=$(date -u +%Y-%m-%dT%H:%MZ)
open_run rot "[\"--role\",\"director\",\"--role-change-by\",\"$RADDR\",\"--role-change-source\",\"dispatcher\"]"
R2=$S
eq "8: an accepted dispatcher change opens the next rotation, printing the change for the carry" \
    "0 director manager $RADDR dispatcher" "$OPEN_RC $(oline role) $(oline role_changed_from) $(oline role_change_by) $(oline role_change_source)"
eq "8:   ... predecessor_carry writes it" "predecessor_carry reconcile" "$(to_reconcile)"
T1=$(date -u +%Y-%m-%dT%H:%MZ)
eq "8:   ... the new rotation's row the new role, set by the address" "director|$RADDR" "$(drow "$R2")"
DSET=$(key "$R2" record/run | jq -r '.[] | select(.key == "role") | .set')
[[ ! $DSET < $T0 ]] && [[ ! $DSET > $T1 ]] && ok "8:   ... at the write's time" || bad "8:   ... at the write's time" "$T0 <= $DSET <= $T1"
eq "8:   ... with its entry" "Run role changed from manager to director by $RADDR, an intervention from above; source: dispatcher." "$(dentry "$R2")"
eq "8:   ... the ended rotation still holding manager" "manager|start --role" "$(drow "$R1")"
# R2 ends: R1 is its predecessor, named in its rotation.
rotation_end_date "$R2" "$YESTERDAY"
R2SNAP=$(dsnap "$R2")
open_run rot "[\"--role\",\"manager\",\"--role-change-by\",\"$R1\",\"--role-change-source\",\"dispatcher\"]"
eq "8: a dispatcher change naming the ended rotation's predecessor is refused" "2 role-change-refused" "$OPEN_RC $(oline reason)"
case "$(rmsg)" in "coordinate-open: $R2 reports to $RRT, and $R1 is $R2 itself or the run it continues"*) pass "8:   ... as role_change_self, naming the row" ;; *) fail "8:   ... as role_change_self, naming the row" "$(rmsg)" ;; esac
open_run rot
eq "8: a start naming manager after a rotation recorded director ended is refused role-mismatch" "2 refused role-mismatch" "$OPEN_RC $(oline outcome) $(oline reason)"
eq "8:   ... nothing opened, nothing written" "$R2SNAP" "$(dsnap "$R2")"
open_run rot '["--role","manager","--role-change-by","the human","--role-change-source","person"]'
R3=$S
eq "8: an accepted person change opens the next rotation" "0 manager director the human person" \
    "$OPEN_RC $(oline role) $(oline role_changed_from) $(oline role_change_by) $(oline role_change_source)"
eq "8:   ... predecessor_carry writes it" "predecessor_carry reconcile manager|the human" "$(to_reconcile) $(drow "$R3")"
eq "8:   ... with its entry" "Run role changed from director to manager by the human, an intervention from above; source: person." "$(dentry "$R3")"
rotation_end_date "$R3" "$YESTERDAY"
open_run rot
R4=$S
eq "8: a start naming the recorded role (manager) opens the next rotation" "0 manager " "$OPEN_RC $(oline role) $(oline role_changed_from)"
eq "8:   ... the carry keeping the row" "predecessor_carry reconcile manager|the human" "$(to_reconcile) $(drow "$R4")"
# A role-less ended rotation (a lineage from before the row): asked before the
# carry, and given --role the carry adds the row.
DISC=rotless
open_run rotless || bad "8: a role-less lineage's first rotation opens" "$(cat "$T/open.err")"
L1=$S
to_reconcile > /dev/null
key "$L1" record/run | jq -c '[.[] | select(.key != "role")]' > "$T/run.json"
(cd "$WD" && koto context add "$L1" record/run --from-file "$T/run.json")
eq "8: its record holds no role row" none "$(drow "$L1")"
rotation_end_date "$L1" "$YESTERDAY"
L1SNAP=$(dsnap "$L1")
open_run rotless '[]'
eq "8: a start with no --role after a role-less rotation ended is asked, exit 10" "10 ask=role" "$OPEN_RC $OPEN_OUT"
eq "8:   ... before the carry: nothing opened, nothing written" "$L1SNAP" "$(dsnap "$L1")"
open_run rotless '["--role","director"]'
L2=$S
eq "8: given --role director it opens the next rotation, printing role=director" "0 director" "$OPEN_RC $(oline role)"
eq "8:   ... the carry adding the row, set by the start's --role" "predecessor_carry reconcile director|start --role" "$(to_reconcile) $(drow "$L2")"

echo "== no GitHub write and no push, the whole suite =="
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls" \
    && bad "no pull request, contents or ref write" "$(grep -E '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls")" \
    || ok "no pull request, contents or ref write"
[ -s "$T/git.calls" ] && bad "no git push" "$(cat "$T/git.calls")" || ok "no git push"

done_tests discipline-session-engine
