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
#   and across the whole suite no gh pr create, pr ready, contents write, ref
#   write or deletion, and no git push.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/discipline-session_engine_test.sh
set -uo pipefail

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
# open_run <discipline>: the opener's output in OPEN_OUT, its session in S.
open_run() {
    printf '["--discipline", "%s", "--host", "acme/widgets"]' "$1" > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
# rotation_end_date <session> <date>: the rotation's window ends on <date>, as
# the agent writes it.
rotation_end_date() {
    key "$1" record/rotation | jq -c --arg e "$2" '.end = $e | if .start > $e then .start = $e else . end' > "$T/rot.json"
    (cd "$WD" && bash "$PS/record-state.sh" --session "$1" --rotation "$T/rot.json") > /dev/null 2> "$T/w.err"
}
# to_reconcile: from a fresh run, through the find (and the open or the carry it
# names) to reconcile; prints the states it passed, space-separated.
to_reconcile() {
    local st path
    st=$(at); path=$st
    if [ "$st" = record_open ]; then
        agent record-open.sh --start "$TODAY" --end "$(day 6)" > "$T/open.out" 2> "$T/w.err" || { echo "$path open-failed"; return; }
        st=$(at --with-data '{"opened":"opened"}'); path="$path $st"
    elif [ "$st" = predecessor_carry ]; then
        agent record-open.sh --carry > "$T/carry.out" 2> "$T/w.err" || { echo "$path carry-failed"; return; }
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
eq "a live run on the shipped template is resumed" "resumed=1 session=$S1" "$(printf '%s' "$OPEN_OUT" | tr '\n' ' ' | sed 's/ $//')"
# A second live run of the discipline, holding no record: the rotation's run is
# no longer the scope's only live run, so it can't be resumed.
EXTRA=coordinate-discipline-ops-$(date -u -d '+1 minute' +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v+1M +%Y%m%dT%H%M%SZ)
jq -nc --arg p "$PR" '[["SCOPE", "discipline"], ["DISCIPLINE", "ops"], ["HOST_REPO", "acme/widgets"], ["PLUGIN_ROOT", $p]]' > "$T/extra-vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$EXTRA" "$TPL" "$T/extra-vars.json") > /dev/null 2> "$T/extra.err"
eq "a second live run of the discipline opens" 0 $?
ROT1=$(key "$S1" record/rotation)
open_run ops
S2=$S
case "$OPEN_OUT" in *"cancelled="*"carried=$S1"*) ok "a run that can't be resumed is carried" ;;
    *) bad "a run that can't be resumed is carried" "$OPEN_OUT $(cat "$T/open.err")" ;; esac
case "$OPEN_OUT" in *"cancelled=$S1"*) ok "  ... the live run cancelled" ;; *) bad "  ... the live run cancelled" "$OPEN_OUT" ;; esac
eq "  ... into a new run holding the same rotation" "$ROT1" "$(key "$S2" record/rotation)"
eq "  ... whose find reads its own rotation" "reconcile" "$(to_reconcile)"
eq "  ... with no second rotation" found "$(token)"

echo "== 3. a start on the end date =="
rotation_end_date "$S2" "$TODAY"; eq "the window now ends today" 0 $?
open_run ops
eq "a start on the end date is a restart" "resumed=1 session=$S2" "$(printf '%s' "$OPEN_OUT" | tr '\n' ' ' | sed 's/ $//')"

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
(cd "$WD" && bash "$PS/record-state.sh" --session "$S3" --reasoning-file "$T/why.txt") > /dev/null 2> "$T/w.err"
eq "the second rotation closes early with its reasoning" 0 $?
open_run ops
S4=$S
eq "the next start opens the third rotation through the predecessor path" "predecessor_carry reconcile" "$(to_reconcile)"
eq "  ... carrying the second rotation, never the first" "$S3" "$(key "$S4" record/rotation | jq -r .predecessor)"
eq "  ... and its reconcile reads the reasoning as present" present "$(key "$S4" reconcile/report.json | jq -r '.reasoning.status')"
eq "  ... verbatim" "The deploy job flakes on Mondays; watch it." "$(key "$S4" reconcile/reasoning.md)"

echo "== 6. the rotation ends at rotation_end =="
S=$S4
{ agent record-state.sh --run arguments "--discipline ops --host acme/widgets" --by "the human" \
  && agent record-state.sh --run cap 2 --by "the human" \
  && agent record-state.sh --run coordinator ops-lead --by ops-lead \
  && agent record-state.sh --run reports-to "the human" --by "the human" \
  && agent record-state.sh --standing go-ahead --what "the carried state is acknowledged" --owner "the human"; } > /dev/null 2> "$T/w.err"
eq "the handover facts and the carry's go-ahead are written" 0 $?
rotation_end_date "$S4" "$YESTERDAY"
ST=$(at --with-data '{"reconciled":"reported"}')
eq "past its window the rotation reaches rotation_end" rotation_end "$ST"
eq "  ... and holds there until the reasoning is written" rotation_end "$(at --with-data '{"reasoning":"written"}')"
printf 'Nothing carried over that the tables miss.\n' > "$T/why.txt"
agent record-state.sh --reasoning-file "$T/why.txt" > /dev/null 2> "$T/w.err"
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
sed 's/^## start$/## start\n\nA different template./' "$TPL" > "$T/other-template.md"
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

echo "== no GitHub write and no push, the whole suite =="
grep -Eq '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls" \
    && bad "no pull request, contents or ref write" "$(grep -E '^(pr create|pr ready|api --method (POST|DELETE|PUT|PATCH))' "$GH_DB.calls")" \
    || ok "no pull request, contents or ref write"
[ -s "$T/git.calls" ] && bad "no git push" "$(cat "$T/git.calls")" || ok "no git push"

done_tests discipline-session-engine
