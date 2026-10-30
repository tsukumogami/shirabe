#!/usr/bin/env bash
# handover_engine_test.sh -- a coordinator moved to another host by importing
# its session, the shipped coordinate.md driven through real koto against the
# testdata/gh stand-in, on two simulated hosts sharing koto's cloud backend
# (testdata/cloud-hosts.sh over testdata/fake-s3.py)
# (docs/designs/archive/DESIGN-coordinate-record-container.md, Decision 3;
# docs/designs/DESIGN-coordinator-session-record.md; PRD R14, R17, R9, R22).
#
# The fixture is the shape of a real handover, on 2026-09-29, in which a
# replacement coordinator took over a run from a second session to cut its
# context cost: two workers in flight, one with a pull request; a fix a local
# agent was building that no holding covers; a standing answer the human gave
# through the process owner; a hold on a merge; the cap the human lowered to
# one; and the old coordinator's address, which both workers were told. Host A
# opens the run, its record in the run's session, and writes all of that
# through the record's writers, with the crash set (rules, briefs, friction,
# reports-to and where their files live) and a holding's pushed head. Host B
# imports the session through coordinate-open.sh --import, given no cap and no
# other file.
#
# Proves, one line per case:
#   0. the import: B prints imported=, resumed=1 and A's session name, which
#      keeps A's stamp; every record/ and legs/ key on B is the same as on A,
#      record/host keeps A's host facts and adds the source workspace, session
#      and template hash; A's copy then refuses a write as session_migrated
#      (and, before koto 0.32.0, a read too; from 0.32.0 a read answers with
#      A's last pushed copy), and on A it is neither a live run of the scope
#      nor a session holding the scope's record; B's next
#      entry is numbered after A's last (R9); B's reconcile report and closing
#      lines name the source;
#   1. the imported session alone carries every property the roadmap's
#      acceptance test names: the run's arguments and the cap, the worker ids,
#      a next step per holding, a row for the local agent's work, the standing
#      answer with who and when, the hold with who and when, the coordinator's
#      address with who has been told it, and the crash set and pushed head;
#   2. the replacement writes its own address, and the handover gate then
#      holds it at reconcile, naming each worker, until it has told both (the
#      third loss: reports going to the old session);
#   3. the replacement relays a person's word as a Standing row, the person
#      as owner and itself as relayer, and the entry it appends tells it;
#   4. past the gate the run reaches pick with the cap of one from the
#      record, not the default the session was opened with;
#   5. a holding with no next step holds the gate too, and a Work row clears it;
#   6. a run imported while it waits at the hub (on a third host) is printed
#      as `state=wait` with `tick=moved`; the check the hub's directive asks
#      on every visit says a reconcile is owed, and says it again when read
#      again; the moved tick takes it through a full reconcile whose report is
#      read on the new host and names its source, and the check is clear;
#   7. a discipline rotation on the session store
#      (docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3):
#      a second rotation carries the first's hold and go-ahead and reports
#      them, its handover gate lists carry-unacknowledged until a person's
#      go-ahead set after its start (the carried go-ahead doesn't clear it),
#      and host B imports it into a fresh workspace, resuming it there with
#      record/rotation as on A.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/handover_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh: the GitHub DB helpers, state_json and the counters. It
# puts testdata/ first on PATH, the koto stand-in included; this suite needs
# the real koto, so PATH is rebuilt with only the gh stand-in in front.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
. "$HERE/testdata/engine-session.sh"
mkdir -p "$T/bin"
# The gh stand-in finds its DB through GH_DB. koto's import gives the session
# the importing host's fixed command environment, which doesn't pass GH_DB (the
# source's legacy environment isn't carried), so gh on PATH names the DB itself.
printf '#!/bin/sh\nGH_DB=${GH_DB:-%s} exec "%s" "$@"\n' "$GH_DB" "$HERE/testdata/gh" > "$T/bin/gh"
chmod +x "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"

# Three hosts on one bucket. Each workspace is a clone-shaped directory in a
# niwa instance that permits every finishing step, so the posture reads
# `readable`.
. "$HERE/testdata/cloud-hosts.sh"
ktg_on_exit 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac'
s3_start || { bad "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; done_tests handover-engine; exit 1; }
host_make a; host_make b; host_make c
for h in a b c; do
    W="$T/hosts/$h/work"
    mkdir -p "$W/.niwa" "$W/.claude"
    (cd "$W" && git init -q && git remote add origin https://github.com/acme/widgets.git && printf '.koto/\n' >> .git/info/exclude)
    echo '{}' > "$W/.niwa/instance.json"
    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$W/.claude/settings.json"
done
WS_A=$(host_ws a)

ON=a
tick() { host_on "$ON" koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"; }
at() { tick "$@" | jq -r '.state // empty'; }
run() { # run <script> <args...>: a coordinate script on session $S, on host $ON
    local s=$1; shift
    host_on "$ON" bash "$PS/$s" --session "$S" "$@"
}
state() { run state-stored-set.sh "$@" >"$T/w.out" 2>"$T/w.err"; }
handover() { run state-handover.sh "$@"; }
entries() { run state-entry.sh --list; }
# keys <host>: every record/ and legs/ key of $S on the host but record/host,
# with its content (run-tests.sh's PATH has no cksum, so no digest).
keys() {
    local k
    for p in record/ legs/; do host_on "$1" koto context list "$S" --prefix "$p" 2>/dev/null | jq -r '.[]'; done \
        | grep -vx record/host | LC_ALL=C sort | while IFS= read -r k; do
        printf '%s %s\n' "$k" "$(host_on "$1" koto context get "$S" "$k")"
    done
}
last_entry() { host_on "$1" koto context list "$S" --prefix record/entries/ | jq -r 'map(ltrimstr("record/entries/")) | sort | last // ""'; }

# ---- the fixture ---------------------------------------------------------------

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-handover.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 2: second\n\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 3: third\n\n**Dependencies:** None\n**Status:** Planned\n')"
db '.prs += [{repo: "acme/widgets", number: 12, title: "feat: first", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
    baseRefName: "main", headRefName: "feat/first", headRefOid: $h, author: "alice", editor: null}]' --arg h "$SHA_HEAD"

# ---- host A: the run, its record on the session store, written by the writers --

echo "== host A writes the run =="
# A koto without the session store's features refuses every start, so the
# handover has nothing to move.
if ! koto_store_ready; then
    echo "koto lacks the session store's features; the handover needs a newer koto"
    done_tests handover-engine
    exit $?
fi
printf '["docs/roadmaps/ROADMAP-handover.md"]' > "$T/args.json"
S=$(host_on a bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$S" ] || { bad "host A's run opens" "$(cat "$T/open.err")"; done_tests handover-engine; exit 1; }
ok "host A's run opens"
eq "with no record it stops at record_open" record_open "$(at)"
run state-open.sh >/dev/null 2>"$T/w.err"; eq "state-open.sh opens the record in the run's session" 0 $?
grep -Eq '^(issue|pr) create' "$GH_DB.calls" && bad "  ... opening nothing on GitHub" "$(grep -E '^(issue|pr) create' "$GH_DB.calls")" \
    || ok "  ... opening nothing on GitHub"
eq "the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"

F1=$(holding worker-f1 '{"unit": "Feature 1", "dispatch_status": "dispatched", "branch": "feat/first"}')
F2=$(holding worker-f2 '{"unit": "Feature 2", "dispatch_status": "dispatched", "branch": "", "pull_request": ""}')
printf '%s' "$F1" > "$T/f1.json"; printf '%s' "$F2" > "$T/f2.json"
jq -n '{hold: "after-release", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-09-29T20:30Z", lifted: ""}' > "$T/hold.json"
# 64 hex characters each, written out: run-tests.sh's PATH has no seq.
RULES=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BRIEFS=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
{ run state-holding.sh --topic worker-f1 --row-file "$T/f1.json" \
  && run state-holding.sh --topic worker-f2 --row-file "$T/f2.json" \
  && run state-holding.sh --topic worker-f1 --pushed-head "$SHA_HEAD" \
  && run state-hold.sh --add --row-file "$T/hold.json"; } >/dev/null 2>"$T/w.err"
eq "the holdings, a pushed head and the hold are written" 0 $?
state --run arguments "--roadmap docs/roadmaps/ROADMAP-handover.md --cap 3" --by "the human" \
    && state --run cap 1 --by "the human, via the process owner" \
    && state --run coordinator lane-v1 --by lane-v1 \
    && state --told worker-f1 --by lane-v1 \
    && state --told worker-f2 --by lane-v1 \
    && state --standing answer --what "panels at the head are the cost to cut, not instruction length" --owner "the human" --relayed-by "the process owner" \
    && state --work "Feature 1" --kind holding --who worker-f1 --next "waiting on the panel at the head" \
    && state --work "Feature 2" --kind holding --who worker-f2 --next "fix round on the evals, then a ready report" \
    && state --work "fix for the ablation check" --kind local-agent --who "local agent" --next "ready report, then the merge"
eq "the stored set is written" 0 $?
state --run rules "coordinate sha256:$RULES" --by lane-v1 \
    && state --run briefs "lane sha256:$BRIEFS" --by lane-v1 \
    && state --run friction lane-friction --by lane-v1 \
    && state --run reports-to "the human" --by "the human" \
    && state --host rules:coordinate "$WS_A/rules.md" --host briefs:lane "$WS_A/brief.md" --host friction "$WS_A/friction.md"
eq "the crash set and where its files live are written" 0 $?
SNAP=$(keys a)
HOST_A=$(host_on a koto context get "$S" record/host)
LAST_A=$(last_entry a)
[ -n "$SNAP" ] && [ -n "$LAST_A" ] && ok "host A holds the record's keys and entries" || bad "host A holds the record's keys and entries" "$SNAP / $LAST_A"

# ---- host B: the import ----------------------------------------------------------

echo "== 0. host B imports the run =="
ON=b
printf '["docs/roadmaps/ROADMAP-handover.md", "--import", "%s", "--from", "%s"]' "$S" "$WS_A" > "$T/args.json"
OUT=$(host_on b bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
eq "the import succeeds" 0 $?
eq "  ... printing imported, resumed, the session and its state (at reconcile, no tick)" "imported=$S resumed=1 session=$S state=reconcile" "$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
[ -s "$T/open.err" ] && bad "  ... with nothing on stderr" "$(cat "$T/open.err")" || ok "  ... with nothing on stderr"
eq "the run keeps A's stamp" "$S" "$(host_on b koto session list | jq -r --arg s "$S" '.[] | select(.id == $s) | .id')"
eq "every record/ and legs/ key is the same on B" "$SNAP" "$(keys b)"
HASH=$(host_on b bash "$PS/coord-log.sh" template-hash --session "$S")
eq "record/host keeps A's facts and adds the source" \
    "$(printf '%s' "$HOST_A" | jq -cS --arg w "$WS_A" --arg s "$S" --arg h "$HASH" '. + {source_workspace: $w, source_session: $s, template_hash: $h}')" \
    "$(host_on b koto context get "$S" record/host | jq -cS .)"
# koto 0.32.0 keeps an import's source as a read-only predecessor
# (koto_keeps_source): A's copy answers a read and refuses a write; an older
# koto's refuses both.
host_on a koto context get "$S" record/meta > "$T/out" 2>"$T/err"; rc=$?
if koto_keeps_source; then
    eq "A's copy still answers a read with its last pushed copy" "0 $(printf '%s\n' "$SNAP" | sed -n 's|^record/meta ||p')" "$rc $(cat "$T/out")"
else
    eq "A's copy then refuses a read" 2 $rc
    grep -q session_migrated "$T/out" && ok "  ... as session_migrated" || bad "  ... as session_migrated" "$(cat "$T/out" "$T/err")"
fi
printf '{}' | host_on a koto context add "$S" coord/probe.json > "$T/out" 2>"$T/err"; eq "A's copy refuses a write" 2 $?
grep -q session_migrated "$T/out" && ok "  ... as session_migrated" || bad "  ... as session_migrated" "$(cat "$T/out" "$T/err")"
eq "  ... and isn't a live run of the scope on A" "" \
    "$(host_on a bash "$PS/coord-log.sh" live-session --scope-slug "$(bash "$PS/coord-log.sh" slug --scope roadmap --name handover)" --all 2>/dev/null)"
eq "  ... nor a session that holds the scope's record on A" '{"session":null,"action":"none"}' \
    "$(host_on a bash "$PS/state-read.sh" --candidate --scope roadmap --name handover --hash "$HASH" 2>/dev/null | jq -c '{session, action}')"

echo "== 1. the imported session alone carries the stored set =="
eq "it is at reconcile" reconcile "$(at)"
H=$(handover); eq "the handover read prints" 0 $?
eq "the run's arguments" "--roadmap docs/roadmaps/ROADMAP-handover.md --cap 3" "$(printf '%s' "$H" | jq -r .arguments)"
eq "the cap, as the human lowered it" "1" "$(printf '%s' "$H" | jq -r .cap)"
eq "the worker ids" "worker-f1 worker-f2" "$(printf '%s' "$H" | jq -r '[.workers[].worker] | join(" ")')"
eq "a next step per holding" "waiting on the panel at the head|fix round on the evals, then a ready report" \
    "$(printf '%s' "$H" | jq -r '[.workers[].next] | join("|")')"
eq "the local agent's work, which no holding covers" "fix for the ablation check: ready report, then the merge" \
    "$(printf '%s' "$H" | jq -r '.work[] | select(.kind == "local-agent") | "\(.item): \(.next)"')"
# The writer stamps a Standing row with the minute it is written, so the
# stored set read back carries that minute, not a date the fixture chose.
printf '%s' "$H" | jq -e '.standing[0] | .owner == "the human" and .relayed_by == "the process owner" and (.set | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$"))' >/dev/null \
    && ok "the standing answer, with who and when" || bad "the standing answer, with who and when" "$(printf '%s' "$H" | jq -c .standing)"
eq "the hold, with who and when" "after-release acme/widgets#12 the human 2026-09-29T20:30Z" \
    "$(printf '%s' "$H" | jq -r '.holds[0] | "\(.hold) \(.on) \(.set_by) \(.set)"')"
eq "the coordinator's address and who has been told it" "lane-v1: worker-f1 worker-f2" \
    "$(printf '%s' "$H" | jq -r '"\(.coordinator): \(.told | join(" "))"')"
eq "the crash set: rules, briefs, friction and reports-to" "coordinate sha256:$RULES|lane sha256:$BRIEFS|lane-friction|the human" \
    "$(printf '%s' "$H" | jq -r '[(.rules[0] // ""), (.briefs[0] // ""), .friction, .reports_to] | join("|")')"
eq "  ... and where the files live" "$WS_A/rules.md $WS_A/friction.md" "$(printf '%s' "$H" | jq -r '"\(.host["rules:coordinate"]) \(.host.friction)"')"
eq "worker-f1's pushed head" "$SHA_HEAD" "$(run state-holding.sh --topic worker-f1 --read | jq -r .pushed_head)"
eq "and, for the old coordinator, no gaps" "0" "$(printf '%s' "$H" | jq '.gaps | length')"

echo "== 2. a new address holds the gate until each worker is told =="
state --run coordinator lane-v2 --by lane-v2; eq "the replacement writes its own address" 0 $?
eq "  ... as the entry after A's last (R9)" "$(printf '%06d' $((10#$LAST_A + 1)))" "$(last_entry b)"
eq "the gate holds at reconcile" reconcile "$(at --with-data '{"reconciled":"reported"}')"
grep -qF "This run was imported from session \`$S\` in workspace \`$WS_A\`, compiled from template \`$HASH\`." <<< "$(host_on b koto context get "$S" reconcile/report.md 2>/dev/null)" \
    && ok "the reconcile report names the source" || bad "the reconcile report names the source" "$(host_on b koto context get "$S" reconcile/report.md 2>&1 | head -5)"
handover --check >/dev/null 2>"$T/gaps"; eq "the check fails" 1 $?
grep -q 'not-told worker-f1' "$T/gaps" && grep -q 'not-told worker-f2' "$T/gaps" \
    && ok "  ... naming each worker still reporting to the old address" || bad "  ... naming each worker still reporting to the old address" "$(cat "$T/gaps")"
state --told worker-f1 --by lane-v2; eq "worker-f1 is told" 0 $?
eq "one untold worker still holds the gate" reconcile "$(at --with-data '{"reconciled":"reported"}')"

echo "== 3. the relay duty =="
state --standing go-ahead --what "release shirabe v0.25.0 once Feature 1 lands" --owner alice --relayed-by lane-v2
eq "the replacement relays it" 0 $?
eq "  ... the person as owner and itself as relayer" "go-ahead alice lane-v2" \
    "$(handover | jq -r '.standing[] | select(.kind == "go-ahead") | "\(.kind) \(.owner) \(.relayed_by)"')"
# An entry's author is the address the record's coordinator row names.
entries | jq -e 'any(.[]; .kind == "go-ahead" and .author == "lane-v2" and (.text | test("Owner: alice\\. Relayed by lane-v2\\.")))' >/dev/null \
    && ok "  ... and the entry tells it, written by the replacement" || bad "  ... and the entry tells it, written by the replacement" "$(entries | jq -c 'map({kind, author, text})')"

echo "== 4. past the gate, the cap is the record's =="
state --told worker-f2 --by lane-v2; eq "worker-f2 is told" 0 $?
eq "the gate passes and the run reaches pick" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "pick's facts carry the cap of one from the record, not the default" 1 \
    "$(host_on b koto context get "$S" coord/pick.json 2>/dev/null | jq -r .cap)"

echo "== 5. a holding with no next step holds the gate =="
state --done "Feature 2"; eq "Feature 2's next step is removed" 0 $?
eq "  ... and the gaps name it" "no-next-step Feature 2" "$(handover | jq -r '[.gaps[].gap] | join(" ")')"
state --work "Feature 2" --kind holding --who worker-f2 --next "a ready report"; eq "a Work row clears it" "" "$(handover | jq -r '[.gaps[].gap] | join(" ")')"

echo "== the closing lines name the source =="
eq "coordinate-report.sh prints the import facts" "outcome=stopped|source_workspace=$WS_A|source_session=$S|template_hash=$HASH" \
    "$(printf '{"is_terminal":true,"result":{"payload":{"outcome":"stopped"}}}' | host_on b bash "$PS/coordinate-report.sh" --session "$S" | grep -v '^events=' | tr '\n' '|' | sed 's/|$//')"

echo "== 6. a run imported at the hub reconciles on its new host =="
eq "pick holds, and the run waits at the hub" wait "$(at --with-data '{"choice":"hold"}')"
WS_B=$(host_ws b)
ON=c
printf '["docs/roadmaps/ROADMAP-handover.md", "--import", "%s", "--from", "%s"]' "$S" "$WS_B" > "$T/args.json"
OUT=$(host_on c bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
eq "host C imports it" 0 $?
grep -qx 'state=wait' <<< "$OUT" && ok "  ... printing that it waits at the hub" || bad "  ... printing that it waits at the hub" "$OUT"
grep -qx 'tick=moved' <<< "$OUT" && ok "  ... and the tick that comes first" || bad "  ... and the tick that comes first" "$OUT"
# The hub's directive asks this check on every visit; it reads the run's own
# keys, so it still says a reconcile is owed when read again, as after a
# restart, until the reconcile on this host clears it.
run reconcile-report-get.sh --check >/dev/null 2>&1; eq "the hub's check says a reconcile is owed on C" 3 $?
run reconcile-report-get.sh --check >/dev/null 2>&1; eq "  ... and still says so when read again" 3 $?
eq "the moved tick takes it through a full reconcile on C" reconcile "$(at --with-data '{"event":"moved"}')"
run reconcile-report-get.sh --check >/dev/null 2>&1; eq "  ... after which the check is clear" 0 $?
grep -qF "This run was imported from session \`$S\` in workspace \`$WS_B\`" <<< "$(host_on c koto context get "$S" reconcile/report.md 2>/dev/null)" \
    && ok "  ... whose report was read on C, naming B as the source" \
    || bad "  ... whose report was read on C, naming B as the source" "$(host_on c koto context get "$S" reconcile/report.md 2>&1 | head -5)"
eq "  ... and the handover read still carries the cap" "1" "$(handover | jq -r .cap)"

echo "== 7. a discipline rotation on the session: the carry, its gate and the import =="
# docs/designs/current/DESIGN-coordinator-record-teardown.md, Decision 3: host A
# runs a first rotation that sets a hold and a go-ahead and closes; the second
# rotation carries them, and its handover gate holds until a person's go-ahead
# set after its start; host B then imports the second rotation.
ON=a
rota_open() { # rota_open: a run of the rota discipline on host A, its session in S
    printf '["--discipline", "rota", "--host", "acme/widgets"]' > "$T/args.json"
    S=$(host_on a bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
rota_open || bad "the first rotation's run opens" "$(cat "$T/open.err")"
R1=$S
eq "the first rotation stops at record_open" record_open "$(at)"
run state-open.sh --start "$(date -u +%Y-%m-%d)" --end "$(date -u +%Y-%m-%d)" > /dev/null 2> "$T/w.err"
eq "  ... opens in its session" 0 $?
eq "  ... and reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"
jq -n '{hold: "after-cutover", on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-10-01T10:00Z", lifted: ""}' > "$T/rhold.json"
{ run state-hold.sh --add --row-file "$T/rhold.json" \
  && state --standing go-ahead --what "ship the cutover" --owner "the human"; } > /dev/null 2> "$T/w.err"
eq "the first rotation sets a hold and a go-ahead" 0 $?
printf 'The cutover waits on the vendor.\n' > "$T/rwhy.txt"
state --reasoning-file "$T/rwhy.txt"; eq "  ... and closes with its reasoning" 0 $?
rota_open || bad "the second rotation's run opens" "$(cat "$T/open.err")"
R2=$S
[ "$R2" != "$R1" ] && ok "the next start opens the second rotation" || bad "the next start opens the second rotation" "$R2"
eq "  ... whose find reads the predecessor" predecessor_carry "$(at)"
run state-open.sh --carry > "$T/rcarry.out" 2> "$T/w.err"; eq "  ... and carries it" 0 $?
eq "  ... reporting the hold and the go-ahead" "after-cutover|go-ahead:the human" \
    "$(host_on a koto context get "$R2" coord/predecessor_carry.json | jq -r '"\([.holds[].hold] | join(" "))|\([.standing[] | "\(.kind):\(.owner)"] | join(" "))"')"
eq "  ... and reaches reconcile" reconcile "$(at --with-data '{"carry":"carried"}')"
rgaps() { handover | jq -r '[.gaps[].gap] | join(" ")'; }
case " $(rgaps) " in *" carry-unacknowledged "*) ok "the gate lists carry-unacknowledged" ;; *) bad "the gate lists carry-unacknowledged" "$(rgaps)" ;; esac
eq "  ... though the carry brought the first rotation's go-ahead" "go-ahead" "$(host_on a koto context get "$R2" record/standing | jq -r '.[0].kind')"
state --standing go-ahead --what "the carried hold and go-ahead are acknowledged" --owner "the human"
eq "a person's go-ahead is recorded" 0 $?
case " $(rgaps) " in *" carry-unacknowledged "*) bad "  ... and clears it" "$(rgaps)" ;; *) ok "  ... and clears it" ;; esac
RROT=$(host_on a koto context get "$R2" record/rotation)
ON=b
printf '["--discipline", "rota", "--host", "acme/widgets", "--import", "%s", "--from", "%s"]' "$R2" "$WS_A" > "$T/args.json"
OUT=$(host_on b bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
eq "host B imports the second rotation" 0 $?
grep -qx 'resumed=1' <<< "$OUT" && grep -qx "session=$R2" <<< "$OUT" && ok "  ... resuming it there" || bad "  ... resuming it there" "$OUT $(cat "$T/open.err")"
eq "  ... its record/rotation reading the same as on A" "$RROT" "$(host_on b koto context get "$R2" record/rotation)"

done_tests handover-engine
