#!/usr/bin/env bash
# legs-move_engine_test.sh -- every worker leg gets an end after the
# coordinator's session moves to another host (PRD R13, R15, R16;
# docs/designs/DESIGN-coordinator-session-record.md, Decision 7), against real
# koto on two simulated hosts sharing koto's cloud backend
# (testdata/cloud-hosts.sh over testdata/fake-s3.py), the shipped
# coordinate.md driven through its reconcile on the new host.
#
# Host A runs a roadmap coordinator on the session store with six leg-bound
# holdings, each a /deliver worker on a leg of A's request store:
#   moved     its worker's session is imported to B with the coordinator's
#   left      its worker's session stays on A
#   other     its worker's session is imported to B and bound there to another
#             leg before the coordinator reconciles
#   nochild   no worker ever attached, so no child is recorded
#   old       dispatched before leg keys existed: its leg has no key
#   held      (on B) a leg whose request B's own store holds
# The legs' keys are written as dispatch-worker.sh writes them, and
# wait-target.sh, run on A, records each bound child in its key.
#
# Proves:
#   1. on B, before the reconcile, the handover gate lists leg-unclassified for
#      every holding whose request B's store doesn't hold, and not for held;
#   2. the reconcile on B gives each leg its end: moved is re-legged, attached
#      to a new request on B that names its session, and the holding's return
#      path names the new leg; left, other, nochild and old move to the message
#      path, their keys (where they have one) unwatchable; held is watched as
#      before; the report says which under "Changed since then";
#   3. past it the gate lists no leg-unclassified;
#   4. moved's worker, finishing on B, resolves the new leg with its promoted
#      result;
#   5. a message from left, whose leg is now unwatchable, stands as a message
#      report (R16).
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/legs-move_engine_test.sh
set -uo pipefail

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
printf '#!/bin/sh\nGH_DB=${GH_DB:-%s} exec "%s" "$@"\n' "$GH_DB" "$HERE/testdata/gh" > "$T/bin/gh"
# The workspace manager lists no worker on either host: the pass's host read
# finds none, and the reads that matter here are the legs'.
printf '#!/bin/sh\n[ "$1" = list ] && { echo "[]"; exit 0; }\nexit 64\n' > "$T/bin/niwa"
chmod +x "$T/bin/gh" "$T/bin/niwa"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"

. "$HERE/testdata/cloud-hosts.sh"
trap 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac' EXIT
s3_start || { bad "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; done_tests legs-move-engine; exit 1; }
host_make a; host_make b
for h in a b; do
    W="$T/hosts/$h/work"
    mkdir -p "$W/.niwa" "$W/.claude"
    (cd "$W" && git init -q && git remote add origin https://github.com/acme/widgets.git && printf '.koto/\n' >> .git/info/exclude)
    echo '{}' > "$W/.niwa/instance.json"
    # The workspace root, where dispatch-worker.sh keeps its per-topic lock.
    : > "$W/.niwa/workspace.toml"
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
handover() { run state-handover.sh "$@"; }
# key <request>: the leg's key on host $ON, or nothing when there is none
# (koto prints its own refusal on stdout, so presence comes from a listing).
key() {
    host_on "$ON" koto context list "$S" --prefix "legs/$1/" | jq -e --arg k "legs/$1/deliver" 'index($k) != null' >/dev/null || return 0
    host_on "$ON" koto context get "$S" "legs/$1/deliver"
}
row() { run state-holding.sh --topic "$1" --read 2>/dev/null; }

# A stand-in /deliver: one state, then a terminal whose result the leg gets.
mkdir -p "$T/tpl"
cat > "$T/tpl/deliver.md" <<'EOF'
---
name: deliver
version: "1.0"
description: a stand-in /deliver for legs-move_engine_test.sh
initial_state: work
variables:
  TOPIC:
    required: true
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
    result:
      outcome: ready-awaiting-merge
      pr: https://github.com/acme/widgets/pull/21
---
## work
Stand-in.
## done
Done.
EOF
TPL="$T/tpl/deliver.md"

# ---- the fixture ---------------------------------------------------------------

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-legs.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: one\n\n**Dependencies:** None\n**Status:** In progress\n')"
pr_add() { # pr_add <number> <branch>
    db '.prs += [{repo: "acme/widgets", number: ($n | tonumber), title: "feat: x", body: "", state: "OPEN", isDraft: true, isCrossRepository: false,
        baseRefName: "main", headRefName: $b, headRefOid: $h, author: "alice", editor: null}]' --arg n "$1" --arg b "$2" --arg h "$SHA_HEAD"
}
for n in 21 22 23 24 25 26; do pr_add "$n" "feat/w$n"; done

echo "== host A: the run and its legs =="
# A koto without the session store's features refuses every start, so there
# is no run to move.
if ! koto_store_ready; then
    echo "koto lacks the session store's features; the move needs a newer koto"
    done_tests legs-move-engine
    exit $?
fi
printf '["docs/roadmaps/ROADMAP-legs.md"]' > "$T/args.json"
S=$(host_on a bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$S" ] || { bad "host A's run opens" "$(cat "$T/open.err")"; done_tests legs-move-engine; exit 1; }
ok "host A's run opens"
eq "with no record it stops at record_open" record_open "$(at)"
run state-open.sh >/dev/null 2>"$T/w.err"; eq "the record opens in the run's session" 0 $?
eq "the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"

# leg <topic>: a request on A's store with one deliver leg pinning TOPIC, as
# dispatch-worker.sh opens it; prints the request id.
leg() {
    host_on a koto request create --role deliver --template deliver.md --inputs "{\"TOPIC\":\"$1\"}" \
        --requested-by "$S" --coordinator-of-record "coordinate-$1" | jq -r .request_id
}
# holding <topic> <pr> <request>: the holding on that leg.
holding_on() {
    holding "$1" "{\"unit\": \"Feature 1\", \"entry_point\": \"deliver\", \"mode\": \"--auto\", \"branch\": \"\",
        \"return_path\": \"leg $3:deliver\", \"pull_request\": \"[#$2](https://github.com/acme/widgets/pull/$2)\"}" > "$T/row.json"
    run state-holding.sh --topic "$1" --row-file "$T/row.json" >/dev/null 2>"$T/w.err" || bad "the holding $1 is written" "$(cat "$T/w.err")"
}
# legkey <request> <topic>: the leg's key, as dispatch-worker.sh writes it.
legkey() {
    jq -nc --arg r "$1" --arg t "$2" '{request: $r, leg: "deliver", topic: $t, state: "open", templates: ["deliver.md"], inputs: {TOPIC: $t}}' \
        | host_on "$ON" koto context add "$S" "legs/$1/deliver" >/dev/null
}
R_MOVED=$(leg moved); R_LEFT=$(leg left); R_OTHER=$(leg other); R_NOCHILD=$(leg nochild); R_OLD=$(leg old)
holding_on moved 21 "$R_MOVED"; holding_on left 22 "$R_LEFT"; holding_on other 23 "$R_OTHER"
holding_on nochild 24 "$R_NOCHILD"; holding_on old 25 "$R_OLD"
legkey "$R_MOVED" moved; legkey "$R_LEFT" left; legkey "$R_OTHER" other; legkey "$R_NOCHILD" nochild
attach_on_a() { # attach_on_a <topic> <request>: the worker's own session, bound to its leg on A
    host_on a koto init "deliver-$1" --template "$TPL" --var TOPIC="$1" --koto-leg "$2:deliver" >/dev/null 2>"$T/child.err" \
        || bad "worker $1 attaches on A" "$(cat "$T/child.err")"
}
attach_on_a moved "$R_MOVED"; attach_on_a left "$R_LEFT"; attach_on_a other "$R_OTHER"
host_on a bash "$PS/wait-target.sh" select --session "$S" >/dev/null 2>"$T/wt.err"; eq "the wait's leg pick runs on A" 0 $?
eq "  ... recording each bound child in its leg's key" "deliver-moved deliver-left deliver-other null" \
    "$(for r in "$R_MOVED" "$R_LEFT" "$R_OTHER" "$R_NOCHILD"; do key "$r" | jq -r '.child // "null"'; done | tr '\n' ' ' | sed 's/ $//')"

echo "== host B: the import =="
ON=b
host_on b koto template compile "$TPL" >/dev/null 2>"$T/c.err" || bad "the worker's template compiles on B" "$(cat "$T/c.err")"
for t in moved other; do
    host_on b koto session import "deliver-$t" --from "$WS_A" >/dev/null 2>"$T/imp.err" || bad "worker $t's session imports to B" "$(cat "$T/imp.err")"
done
printf '["docs/roadmaps/ROADMAP-legs.md", "--import", "%s", "--from", "%s"]' "$S" "$WS_A" > "$T/args.json"
host_on b bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" >"$T/open.out" 2>"$T/open.err"
eq "the coordinator imports to B" 0 $?
# other is bound to another leg on B before the reconcile.
R_ELSE=$(host_on b koto request create --role deliver --template deliver.md --inputs '{"TOPIC":"other"}' \
    --requested-by someone-else --coordinator-of-record coordinate-elsewhere | jq -r .request_id)
host_on b koto request attach --session deliver-other "$R_ELSE" deliver >/dev/null 2>"$T/att.err" \
    || bad "worker other attaches to another leg on B" "$(cat "$T/att.err")"
# held: a leg whose request B's own store holds.
R_HELD=$(host_on b koto request create --role deliver --template deliver.md --inputs '{"TOPIC":"held"}' \
    --requested-by "$S" --coordinator-of-record coordinate-held | jq -r .request_id)
holding_on held 26 "$R_HELD"
legkey "$R_HELD" held

echo "== 1. the gate before the reconcile =="
eq "every holding whose request B's store doesn't hold is leg-unclassified, and held isn't" \
    "leg-unclassified left leg-unclassified moved leg-unclassified nochild leg-unclassified old leg-unclassified other" \
    "$(handover | jq -r '[.gaps[].gap | select(startswith("leg-"))] | sort | join(" ")')"

echo "== 2. the reconcile on B gives each leg its end =="
STATE=$(at)
i=0
while [ "$STATE" = reconcile_pass ] && [ "$i" -lt 20 ]; do STATE=$(at); i=$((i + 1)); done
eq "the reconcile seals on B" reconcile "$STATE"
NEW_RP=$(row moved | jq -r .return_path)
NEW=${NEW_RP#leg }; NEW=${NEW%%:*}
case "$NEW_RP" in "leg "*":deliver") [ "$NEW" != "$R_MOVED" ] && ok "moved: the holding names a new leg" || bad "moved: the holding names a new leg" "$NEW_RP" ;;
    *) bad "moved: the holding names a new leg" "$NEW_RP $(host_on b koto context get "$S" reconcile/report.md 2>&1 | grep -i -A3 'not verified')" ;; esac
eq "  ... on B's store, bound to the worker's own session" deliver-moved \
    "$(host_on b koto request get "$NEW" 2>/dev/null | jq -r '(.request // .) | .legs.deliver.bound_child // "none"')"
eq "  ... its old key relegged, naming the new request" "relegged $NEW" "$(key "$R_MOVED" | jq -r '"\(.state) \(.new_request)"')"
eq "  ... its new key open, from the old request" "open $R_MOVED deliver-moved" "$(key "$NEW" | jq -r '"\(.state) \(.from) \(.child)"')"
for t in left other nochild old; do
    eq "$t: the holding reports by message" message "$(row "$t" | jq -r .return_path)"
done
eq "  ... and the keys of those that had one read unwatchable" "unwatchable unwatchable unwatchable" \
    "$(for r in "$R_LEFT" "$R_OTHER" "$R_NOCHILD"; do key "$r" | jq -r .state; done | tr '\n' ' ' | sed 's/ $//')"
eq "old: still no key" "" "$(key "$R_OLD")"
eq "held: watched as before" "leg $R_HELD:deliver open" "$(row held | jq -r .return_path) $(key "$R_HELD" | jq -r .state)"
REPORT=$(host_on b koto context get "$S" reconcile/report.json 2>/dev/null)
eq "the report names each end under Changed since then" \
    "left leg unwatchable|moved leg relegged|nochild leg unwatchable|old leg unwatchable|other leg unwatchable" \
    "$(printf '%s' "$REPORT" | jq -r '[.changes[] | select(.what | startswith("leg ")) | "\(.topic) \(.what)"] | sort | join("|")')"

echo "== 3. past it, the gate =="
eq "no leg is unclassified" "" "$(handover | jq -r '[.gaps[].gap | select(startswith("leg-"))] | join(" ")')"

echo "== 4. the re-legged worker reports on its new leg =="
host_on b koto next deliver-moved --with-data '{"finish":"go"}' >/dev/null 2>&1
eq "its terminal result resolves the new leg, promoted" "resolved promoted ready-awaiting-merge" \
    "$(host_on b koto request get "$NEW" 2>/dev/null | jq -r '(.request // .) | .legs.deliver | "\(.disposition) \(.result_source) \(.result.payload.outcome)"')"

echo "== 5. a message from an unwatchable leg's worker stands (R16) =="
printf '%s' left | host_on b koto context add "$S" report_topic >/dev/null
printf '%s' message | host_on b koto context add "$S" report_source >/dev/null
run report-source.sh >/dev/null 2>"$T/rs.err"; eq "report-source.sh admits it" 0 $?

done_tests legs-move-engine
