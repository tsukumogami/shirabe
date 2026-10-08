#!/usr/bin/env bash
# pause_engine_test.sh -- the paused state, the shipped coordinate.md driven
# through real koto against the testdata/gh stand-in
# (docs/designs/DESIGN-coordinate-paused-state.md).
#
# A running fixture loop holds two units scoped ahead, each its own lane of
# work (Feature 1 and Feature 2), and a third unit nobody holds. Proves, one
# line per case:
#   1. a pause on each lane, set through the record: pick's facts mark both
#      units paused and the third free, and sending either lane its execution
#      is refused at dispatch_check as `paused`, with the pause named, back to
#      wait;
#   2. a resume by lane (its row ended through record-state.sh, then a
#      `resume` tick) releases that lane only: the other is still refused;
#   3. a pause on all holds every unit and every dispatch; a resume of the
#      whole ends it and nothing is paused;
#   4. a scheduled resume stored in the record (a `time` pause) is in force
#      before its minute and released at the first pick after it, brought by
#      a `resume` tick, with no session timer (the host clock stood in for by
#      BL_NOW, which reaches koto's actions);
#   5. a restarted coordinator, a new run opened on the record alone, finds a
#      pause standing at its first pick and refuses the dispatch; once that
#      pause ends, the dispatch goes ahead.
# The land step's refusal is board-land_engine_test.sh's, against the same
# record rows.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/pause_engine_test.sh
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
T=$(cd -P "$T" && pwd -P)
unset KOTO_STORE KOTO_COMPILED_HASH
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
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
state() { (cd "$WD" && bash "$PS/record-state.sh" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err"); }
pick_json() { (cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null); }
check_json() { (cd "$WD" && koto context get "$S" coord/dispatch_check.json 2>/dev/null); }
paused_of() { pick_json | jq -r --arg u "$1" '.units[] | select(.unit == $u) | .paused // "free"'; }
sid() { state --list; jq -r --arg k "$1" --arg o "$2" '[.standing[] | select(.kind == $k and .on == $o) | .standing][-1] // ""' "$T/w.out"; }
send() { at --with-data "$(jq -nc --arg u "$1" '{choice: "send_execution", unit: $u, rationale: "its blocker landed"}')"; }

RM=docs/roadmaps/ROADMAP-pause.md
db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-pause.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 2: second\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 3: third\n**Dependencies:** None\n**Status:** Not started\n')"
A=$(holding lane-a '{"unit": "Feature 1", "phase": "scoping-ahead", "dispatch_status": "dispatched", "branch": "feat/first", "pull_request": ""}')
B=$(holding lane-b '{"unit": "Feature 2", "phase": "scoping-ahead", "dispatch_status": "dispatched", "branch": "feat/second", "pull_request": ""}')
RECORD=$(record_json roadmap pause | jq -c --argjson a "$A" --argjson b "$B" '
    .holdings = [$a, $b]
    | .run = [{key: "arguments", value: "--roadmap docs/roadmaps/ROADMAP-pause.md", set_by: "the human", set: "2026-10-07T10:00Z"},
              {key: "cap", value: "5", set_by: "the human", set: "2026-10-07T10:00Z"},
              {key: "coordinator", value: "lane-coord", set_by: "lane-coord", set: "2026-10-07T10:00Z"},
              {key: "told", value: "lane-a", set_by: "lane-coord", set: "2026-10-07T10:00Z"},
              {key: "told", value: "lane-b", set_by: "lane-coord", set: "2026-10-07T10:00Z"}]
    | .work = [{item: "Feature 1", kind: "holding", who: "lane-a", next: "scoping, then its execution", updated: "2026-10-07T10:00Z"},
               {item: "Feature 2", kind: "holding", who: "lane-b", next: "scoping, then its execution", updated: "2026-10-07T10:00Z"}]')
db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-pause", body: $b, state: "open", author: "coord", editor: null}]' \
    --arg b "$(render "$RECORD" issue 2026-10-07T10:00:00Z)"

open_run() {
    printf '["%s"]' "$RM" > "$T/args.json"
    S=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
    [ -n "$S" ] || { bad "the run opens" "$(cat "$T/open.err")"; done_tests pause-engine; exit 1; }
}
open_run
eq "the run reaches reconcile" reconcile "$(at)"
eq "and pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"

echo "== 1. a pause on each lane =="
state --standing pause --on "Feature 1" --until lifted --what "hold the first lane" --owner "the human" --relayed-by "the process owner"
eq "a pause on Feature 1 is written through the record" 0 $?
state --standing pause --on "Feature 2" --until lifted --what "hold the second lane" --owner "the human"
eq "and one on Feature 2" 0 $?
P1=$(sid pause "Feature 1"); P2=$(sid pause "Feature 2")
eq "a resume tick brings pick" pick "$(at --with-data '{"event":"resume"}')"
eq "pick's facts mark both lanes paused and the third unit free" "$P1 $P2 free" "$(paused_of "Feature 1") $(paused_of "Feature 2") $(paused_of "Feature 3")"
eq "the holdings carry their pauses too" "lane-a:$P1 lane-b:$P2" "$(pick_json | jq -r '[.holdings[] | "\(.worker):\(.paused)"] | join(" ")')"
eq "sending the first lane its execution is refused, back to wait" wait "$(send lane-a)"
eq "  ... as paused, naming the pause" "paused $P1" "$(check_json | jq -r '"\(.verdict) \(.reason | capture("held by pause (?<s>s[0-9]+)").s)"')"
eq "and the second lane too" wait "$(at --with-data '{"event":"resume"}' >/dev/null; send lane-b)"
eq "  ... by its own pause" "paused $P2" "$(check_json | jq -r '"\(.verdict) \(.reason | capture("held by pause (?<s>s[0-9]+)").s)"')"

echo "== 2. a resume by lane =="
state --end "$P1" --by "the human"; eq "the first lane's pause is ended through record-state.sh" 0 $?
eq "a resume tick brings pick" pick "$(at --with-data '{"event":"resume"}')"
eq "the first lane is free, the second still paused" "free $P2" "$(paused_of "Feature 1") $(paused_of "Feature 2")"
eq "the second lane is still refused" wait "$(send lane-b)"
eq "  ... by its pause" paused "$(check_json | jq -r .verdict)"

echo "== 3. a pause on all, and a resume of the whole =="
state --standing pause --on all --until lifted --what "all lanes, until a resume" --owner "the human" --relayed-by "the process owner"
PA=$(sid pause all)
eq "pick sees the whole coordinator paused" "pick $PA" "$(at --with-data '{"event":"resume"}') $(pick_json | jq -r '.paused_all')"
eq "every unit is held, the lane with a pause of its own by that earlier one" "$PA $P2 $PA" "$(paused_of "Feature 1") $(paused_of "Feature 2") $(paused_of "Feature 3")"
eq "the first lane, free a moment ago, is refused" wait "$(send lane-a)"
eq "  ... by the pause on all" "paused" "$(check_json | jq -r .verdict)"
state --end "$PA" --by "the human"; eq "the whole is resumed" 0 $?
state --end "$P2" --by "the human"; eq "and the second lane" 0 $?
eq "a resume tick brings pick" pick "$(at --with-data '{"event":"resume"}')"
eq "nothing is paused" "null free free free" "$(pick_json | jq -r '.paused_all') $(paused_of "Feature 1") $(paused_of "Feature 2") $(paused_of "Feature 3")"
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"

echo "== 4. a scheduled resume in the record =="
state --standing pause --on all --until "time 2026-10-07T14:00Z" --what "all lanes, resume at 10:00 EDT" --owner "the human"
PT=$(sid pause all)
eq "before its minute a resume tick finds it in force" "pick $PT in-force" \
    "$(BL_NOW=2026-10-07T13:59Z at --with-data '{"event":"resume"}') $(pick_json | jq -r '.paused_all') $(pick_json | jq -r --arg s "$PT" '.pauses[] | select(.standing == $s) | .state')"
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"
eq "at its minute the next pick reads it met and holds nothing" "pick null met free" \
    "$(BL_NOW=2026-10-07T14:00Z at --with-data '{"event":"resume"}') $(pick_json | jq -r '.paused_all') $(pick_json | jq -r --arg s "$PT" '.pauses[] | select(.standing == $s) | .state') $(paused_of "Feature 1")"
state --end "$PT" --by "its condition, time 2026-10-07T14:00Z"; eq "the coordinator ends the met row" 0 $?
eq "it holds to wait" wait "$(at --with-data '{"choice":"hold"}')"

echo "== 5. a restart finds the pause standing =="
state --standing pause --on all --until lifted --what "all lanes, over the weekly limit" --owner "the human" --relayed-by "the process owner"
PR5=$(sid pause all)
OLD=$S
open_run
[ "$S" != "$OLD" ] && ok "a new run opens on the same record" || bad "a new run opens on the same record"
eq "it reaches reconcile" reconcile "$(at)"
eq "and pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "its first pick finds the pause standing, from the record alone" "$PR5 $PR5" "$(pick_json | jq -r '.paused_all') $(paused_of "Feature 1")"
eq "and the dispatch is refused" wait "$(send lane-a)"
eq "  ... as paused" paused "$(check_json | jq -r .verdict)"
state --end "$PR5" --by "the human"; eq "the pause ends" 0 $?
at --with-data '{"event":"resume"}' >/dev/null
eq "once it has, sending the first lane its execution goes ahead" dispatch "$(send lane-a)"
eq "  ... clear" ok "$(check_json | jq -r .verdict)"

echo "== the account =="
ENTRIES=$(cd "$WD" && bash "$PS/record-append.sh" --session "$S" --list)
eq "every pause and every end was told as an entry" "pause pause end pause end end pause end pause end" \
    "$(printf '%s' "$ENTRIES" | jq -r '[.[] | select(.kind == "pause" or .kind == "end") | .kind] | join(" ")')"

done_tests pause-engine
