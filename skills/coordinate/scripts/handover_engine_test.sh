#!/usr/bin/env bash
# handover_engine_test.sh -- a replacement coordinator started from the record
# alone, the shipped coordinate.md driven through real koto against the
# testdata/gh stand-in (docs/designs/current/DESIGN-coordinate-record-container.md,
# Decision 3).
#
# The fixture is the shape of the 2026-09-29 handover in which a coordinator
# was replaced by a second session: two workers in flight, one with a pull
# request; a fix a local agent was building that no holding covers; a standing
# answer the human gave through the process owner; a hold on a merge; the cap
# the human lowered to one; and the old coordinator's address, which both
# workers were told. The replacement is opened with no cap argument and no
# other file.
#
# Proves, one line per case:
#   1. the record alone carries every property the roadmap's acceptance test
#      names: the run's arguments and the cap, the worker ids, a next step per
#      holding, a row for the local agent's work, the standing answer with who
#      and when, the hold with who and when, and the coordinator's address
#      with who has been told it;
#   2. the replacement reaches reconcile, writes its own address, and the
#      handover gate then holds it there, naming each worker, until it has
#      told both (the third loss: reports going to the old session);
#   3. a person's unmarked comment on the record isn't an entry, and the
#      replacement relays it with the person as owner and itself as relayer;
#   4. past the gate the run reaches pick with the cap of one from the
#      record, not the default the session was opened with;
#   5. a holding with no next step holds the gate too, and a Work row clears it.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/handover_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh: the GitHub DB helpers, the record renderer and the counters. It
# puts testdata/ first on PATH, the koto stand-in included; this suite needs
# the real koto, so PATH is rebuilt with only the gh stand-in in front.
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

# A clone-shaped working directory in a niwa instance that permits every
# finishing step, so the posture reads `readable`.
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

tick() { (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
state() { (cd "$WD" && bash "$PS/record-state.sh" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err"); }
handover() { (cd "$WD" && bash "$PS/record-handover.sh" --session "$S" "$@"); }
entries() { (cd "$WD" && bash "$PS/record-append.sh" --session "$S" --list); }

# ---- the fixture ---------------------------------------------------------------

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-handover.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 2: second\n\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 3: third\n\n**Dependencies:** None\n**Status:** Planned\n')"
db '.prs += [{repo: "acme/widgets", number: 12, title: "feat: first", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
    baseRefName: "main", headRefName: "feat/first", headRefOid: $h, author: "alice", editor: null}]' --arg h "$SHA_HEAD"
F1=$(holding worker-f1 '{"unit": "Feature 1", "dispatch_status": "dispatched", "branch": "feat/first"}')
F2=$(holding worker-f2 '{"unit": "Feature 2", "dispatch_status": "dispatched", "branch": "", "pull_request": ""}')
RECORD=$(record_json roadmap handover | jq -c --argjson a "$F1" --argjson b "$F2" '
    .holdings = [$a, $b]
    | .holds = [{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}]
    | .run = [{key: "arguments", value: "--roadmap docs/roadmaps/ROADMAP-handover.md --cap 3", set_by: "the human", set: "2026-09-28T11:27Z"},
              {key: "cap", value: "1", set_by: "the human, via the process owner", set: "2026-09-29T22:53Z"},
              {key: "coordinator", value: "lane-v1", set_by: "lane-v1", set: "2026-09-28T11:27Z"},
              {key: "told", value: "worker-f1", set_by: "lane-v1", set: "2026-09-29T10:00Z"},
              {key: "told", value: "worker-f2", set_by: "lane-v1", set: "2026-09-29T11:00Z"}]
    | .standing = [{standing: "s1", kind: "answer", what: "panels at the head are the cost to cut, not instruction length",
                    owner: "the human", relayed_by: "the process owner", set: "2026-09-29T17:40Z"}]
    | .work = [{item: "Feature 1", kind: "holding", who: "worker-f1", next: "waiting on the panel at the head", updated: "2026-09-29T21:40Z"},
               {item: "Feature 2", kind: "holding", who: "worker-f2", next: "fix round on the evals, then a ready report", updated: "2026-09-29T21:41Z"},
               {item: "fix for the ablation check", kind: "local-agent", who: "local agent", next: "ready report, then the merge", updated: "2026-09-29T21:42Z"}]')
db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-handover", body: $b, state: "open", author: "coord", editor: null}]' \
    --arg b "$(render "$RECORD" issue 2026-09-29T21:45:00Z)"
# A person's own comment on the record, carrying no entry marker.
db '.comments = [{repo: "acme/widgets", number: 7, id: 3001, body: "Go ahead with the shirabe v0.25.0 release once Feature 1 lands.",
    user: "alice", created_at: "2026-09-29T21:50:00Z", updated_at: "2026-09-29T21:50:00Z"}]'

# ---- the replacement, opened from the record alone -------------------------------

echo "== the replacement opens =="
printf '["docs/roadmaps/ROADMAP-handover.md"]' > "$T/args.json"
S=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$S" ] || { bad "the replacement session opens" "$(cat "$T/open.err")"; done_tests handover-engine; exit 1; }
ok "the replacement session opens with no cap argument"
eq "it reaches reconcile" reconcile "$(at)"

echo "== 1. the record alone carries the stored set =="
H=$(handover); eq "the handover read prints" 0 $?
eq "the run's arguments" "--roadmap docs/roadmaps/ROADMAP-handover.md --cap 3" "$(printf '%s' "$H" | jq -r .arguments)"
eq "the cap, as the human lowered it" "1" "$(printf '%s' "$H" | jq -r .cap)"
eq "the worker ids" "worker-f1 worker-f2" "$(printf '%s' "$H" | jq -r '[.workers[].worker] | join(" ")')"
eq "a next step per holding" "waiting on the panel at the head|fix round on the evals, then a ready report" \
    "$(printf '%s' "$H" | jq -r '[.workers[].next] | join("|")')"
eq "the local agent's work, which no holding covers" "fix for the ablation check: ready report, then the merge" \
    "$(printf '%s' "$H" | jq -r '.work[] | select(.kind == "local-agent") | "\(.item): \(.next)"')"
eq "the standing answer, with who and when" "the human the process owner 2026-09-29T17:40Z" \
    "$(printf '%s' "$H" | jq -r '.standing[0] | "\(.owner) \(.relayed_by) \(.set)"')"
eq "the hold, with who and when" "after-release acme/widgets#12 the human 2026-09-29T20:30Z" \
    "$(printf '%s' "$H" | jq -r '.holds[0] | "\(.hold) \(.on) \(.set_by) \(.set)"')"
eq "the coordinator's address and who has been told it" "lane-v1: worker-f1 worker-f2" \
    "$(printf '%s' "$H" | jq -r '"\(.coordinator): \(.told | join(" "))"')"
eq "and, for the old coordinator, no gaps" "0" "$(printf '%s' "$H" | jq '.gaps | length')"

echo "== 2. a new address holds the gate until each worker is told =="
state --run coordinator lane-v2 --by lane-v2; eq "the replacement writes its own address" 0 $?
eq "the gate holds at reconcile" reconcile "$(at --with-data '{"reconciled":"reported"}')"
handover --check >/dev/null 2>"$T/gaps"; eq "the check fails" 1 $?
grep -q 'not-told worker-f1' "$T/gaps" && grep -q 'not-told worker-f2' "$T/gaps" \
    && ok "  ... naming each worker still reporting to the old address" || bad "  ... naming each worker still reporting to the old address" "$(cat "$T/gaps")"
state --told worker-f1 --by lane-v2; eq "worker-f1 is told" 0 $?
eq "one untold worker still holds the gate" reconcile "$(at --with-data '{"reconciled":"reported"}')"

echo "== 3. the relay duty =="
entries | jq -e 'all(.[]; .id != 3001)' >/dev/null && ok "a person's unmarked comment isn't an entry" || bad "a person's unmarked comment isn't an entry" "$(entries)"
state --standing go-ahead --what "release shirabe v0.25.0 once Feature 1 lands" --owner alice --relayed-by lane-v2
eq "the replacement relays it" 0 $?
eq "  ... the person as owner and itself as relayer" "go-ahead alice lane-v2" \
    "$(handover | jq -r '.standing[] | select(.kind == "go-ahead") | "\(.kind) \(.owner) \(.relayed_by)"')"
entries | jq -e 'any(.[]; .kind == "go-ahead" and .author == "coord" and (.text | test("Owner: alice\\. Relayed by lane-v2\\.")))' >/dev/null \
    && ok "  ... and the entry tells it" || bad "  ... and the entry tells it" "$(entries | jq -c 'map({kind, text})')"

echo "== 4. past the gate, the cap is the record's =="
state --told worker-f2 --by lane-v2; eq "worker-f2 is told" 0 $?
eq "the gate passes and the run reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "pick's facts carry the cap of one from the record, not the default" 1 \
    "$(cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null | jq -r .cap)"

echo "== 5. a holding with no next step holds the gate =="
state --done "Feature 2"; eq "Feature 2's next step is removed" 0 $?
eq "  ... and the gaps name it" "no-next-step Feature 2" "$(handover | jq -r '[.gaps[].gap] | join(" ")')"
state --work "Feature 2" --kind holding --who worker-f2 --next "a ready report"; eq "a Work row clears it" "" "$(handover | jq -r '[.gaps[].gap] | join(" ")')"

done_tests handover-engine
