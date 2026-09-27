#!/usr/bin/env bash
# board-verdict_test.sh -- board-verdict.sh against a stand-in gh, one fixture
# per board criterion (testdata/board/cases/*.jq, each a change to the one
# passing board in base.jq).
#
# Each case's header says what it expects: `# expect: <verdict> [codes...]`
# (every code listed must appear among the reasons, and a verified board must
# have none), optional `# args:` (--repo acme/widgets always, and --pr 12
# unless the case names --pr or --sha),
# `# env:` and `# check:` (a jq expression the output must satisfy). Every
# output is also held to the contract: one JSON line, a verdict from the
# closed list, codes from the closed set, and verified only with no reasons
# and a 40-hex head. Beyond the cases: usage errors read nothing, the stand-in
# refuses a search form or a non-GET call, and the jobs reads run at most six
# at once.
#
# Needs bash and jq. Usage: bash skills/coordinate/scripts/board-verdict_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/board-verdict-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$HERE/testdata/board/helpers.sh"
bt_setup
BV="$PS/board-verdict.sh"

VERDICTS=" verified pending unverified error:board-read error:pr-state error:deadline head error:head-moved "
CODES=" board-empty run-pending run-startup-failure run-conclusion job-pending job-conclusion job-no-runner job-no-succeeded-step required-missing required-pending required-conclusion merge-state-dirty merge-state-unknown head-moved read-failed required-set-unreadable deadline "

contract() { # contract <label> <output file>
    local f=$2 v c
    [ "$(wc -l < "$f" | tr -d ' ')" = 1 ] || { bad "$1: one line" "$(cat "$f")"; return 1; }
    v=$(jq -r .verdict "$f" 2>/dev/null) || { bad "$1: JSON" "$(cat "$f")"; return 1; }
    case "$VERDICTS" in *" $v "*) ;; *) bad "$1: verdict in the closed list" "$v"; return 1 ;; esac
    for c in $(jq -r '.reasons[]?.code' "$f"); do
        case "$CODES" in *" $c "*) ;; *) bad "$1: code in the closed set" "$c"; return 1 ;; esac
    done
    if [ "$v" = verified ]; then
        jq -e '.reasons == [] and (.head | test("^[0-9a-f]{40}$"))' "$f" >/dev/null || { bad "$1: verified has no reasons and a head" "$(cat "$f")"; return 1; }
    fi
    if [ "$v" != head ] && [ "$v" != error:head-moved ]; then
        jq -e 'has("reasons") and has("skipped") and has("superseded") and has("required") and has("counts") and has("notes") and has("merge_state")' "$f" >/dev/null \
            || { bad "$1: every contract field" "$(cat "$f")"; return 1; }
    fi
    return 0
}

echo "== one fixture per criterion =="
for cf in "$TD"/board/cases/*.jq; do
    name=$(basename "$cf" .jq)
    expect=$(sed -n 's/^# expect: //p' "$cf")
    args=$(sed -n 's/^# args: //p' "$cf")
    envs=$(sed -n 's/^# env: //p' "$cf")
    check=$(sed -n 's/^# check: //p' "$cf")
    case " $args " in *" --pr "*|*" --sha "*) ;; *) args="--pr 12 $args" ;; esac
    bt_board "$name" || { bad "$name: fixture builds"; continue; }
    rm -f "$GH_BOARD_DIR/calls"
    # shellcheck disable=SC2086
    env $envs bash "$BV" --repo acme/widgets $args > "$T/out" 2> "$T/err"
    rc=$?
    [ $rc -eq 0 ] || { bad "$name: exit 0" "rc=$rc $(cat "$T/err")"; continue; }
    contract "$name" "$T/out" || continue
    set -- $expect
    want=$1; shift
    got=$(jq -r .verdict "$T/out")
    [ "$got" = "$want" ] || { bad "$name: verdict" "want $want, got $got: $(cat "$T/out") $(cat "$T/err")"; continue; }
    missing=
    for c in "$@"; do
        jq -e --arg c "$c" 'any(.reasons[]; .code == $c)' "$T/out" >/dev/null || missing="$missing $c"
    done
    [ -z "$missing" ] || { bad "$name: reason codes" "missing$missing in $(cat "$T/out")"; continue; }
    if [ -n "$check" ]; then
        jq -e -L "$TD/board" "include \"lib\"; $check" "$T/out" >/dev/null || { bad "$name: check" "$check on $(cat "$T/out")"; continue; }
    fi
    if grep -Ev '^(api --method GET |api graphql |pr view )' "$GH_BOARD_DIR/calls" | grep -q .; then
        bad "$name: every read is GET or GraphQL" "$(cat "$GH_BOARD_DIR/calls")"; continue
    fi
    ok "$name: $got${1:+ ($*)}"
done

echo "== read order and scope =="
bt_board complete-board
rm -f "$GH_BOARD_DIR/calls"
bash "$BV" --repo acme/widgets --pr 12 > "$T/out" 2>/dev/null
eq "the ref is read last" "api --method GET repos/acme/widgets/git/ref/heads/feat/x" "$(tail -1 "$GH_BOARD_DIR/calls")"
grep -q 'actions/runs?head_sha=0123456789abcdef0123456789abcdef01234567&per_page=100 --paginate' "$GH_BOARD_DIR/calls" && ok "runs are read by head_sha with --paginate" || bad "runs are read by head_sha with --paginate" "$(cat "$GH_BOARD_DIR/calls")"
grep -q 'filter=all' "$GH_BOARD_DIR/calls" && bad "jobs never use filter=all" || ok "jobs never use filter=all"
grep 'api graphql' "$GH_BOARD_DIR/calls" | grep -q 'mutation' && bad "the snapshot is a query" || ok "the snapshot is a query"

bt_board queued-run
rm -f "$GH_BOARD_DIR/calls"
bash "$BV" --repo acme/widgets --pr 12 > /dev/null 2>&1
grep -q 'runs/102/jobs' "$GH_BOARD_DIR/calls" && bad "a pending run's jobs aren't read" || ok "a pending run's jobs aren't read"

echo "== at most six job reads at once =="
jq -n -L "$TD/board" 'include "lib";
    [range(201; 214)] as $ids
    | {snapshot: snapshot("CLEAN"; []), runs: runs([$ids[] | run(.; "completed"; "success"; 1)]),
       branch: {protected: false}, rules: [], files: [], ref: {object: {sha: H}},
       __sleep: ([$ids[] | {key: "jobs-\(.)", value: 1}] | from_entries)}
    + ([$ids[] | {key: "jobs-\(.)", value: jobs([job(. * 10; "j\(.)"; "success"; "r"; [step("success")])])}] | from_entries)' > "$T/par.json"
bt_materialize "$T/par.json" "$GH_BOARD_DIR"
: > "$GH_BOARD_DIR/conc"
bash "$BV" --repo acme/widgets --pr 12 > "$T/out" 2>"$T/err"
eq "thirteen runs verify" verified "$(jq -r .verdict "$T/out")"
MAX=$(awk '/^\+/ { n++; if (n > m) m = n } /^-/ { n-- } END { print m + 0 }' "$GH_BOARD_DIR/conc")
if [ "$MAX" -le 6 ] && [ "$MAX" -ge 2 ]; then ok "job reads ran in parallel, at most six at once ($MAX)"; else bad "job reads ran in parallel, at most six at once" "max $MAX"; fi

echo "== usage reads nothing =="
rm -f "$GH_BOARD_DIR/calls"
for a in "--repo acme/widgets" "--repo acme --pr 12" "--repo acme/widgets --pr 0" "--repo acme/widgets --pr 12 --sha $H --base main" \
         "--repo acme/widgets --sha abc --base main" "--repo acme/widgets --sha $H" "--repo acme/widgets --sha $H --base main --head-only" \
         "--repo ../x --pr 1" "--repo acme/widgets --pr 12 --bogus" "--repo acme/widgets --sha $H --base ../main"; do
    bash "$BV" $a > "$T/out" 2>/dev/null
    rc=$?
    if [ $rc -eq 2 ] && [ ! -s "$T/out" ]; then ok "usage: $a"; else bad "usage: $a" "rc=$rc out=$(cat "$T/out")"; fi
done
[ ! -s "$GH_BOARD_DIR/calls" ] && ok "no usage error reached gh" || bad "no usage error reached gh" "$(cat "$GH_BOARD_DIR/calls")"

echo "== the stand-in refuses what a check must never do =="
GH_BOARD_DIR="$GH_BOARD_DIR" gh search prs x >/dev/null 2>&1; eq "a search command exits 9" 9 $?
GH_BOARD_DIR="$GH_BOARD_DIR" gh api repos/acme/widgets/pulls/12/merge >/dev/null 2>&1; eq "a REST call without --method GET exits 9" 9 $?
GH_BOARD_DIR="$GH_BOARD_DIR" gh api graphql -f 'query=mutation { x }' >/dev/null 2>&1; eq "a GraphQL mutation exits 9" 9 $?

echo "== the scripts' own reads =="
for f in board-verdict.sh board-lib.sh record-common.sh board-record.sh land-check.sh merge-confirm.sh merged-facts.sh land-merge.sh; do
    if grep -n 'gh api' "$HERE/$f" | grep -v '^[0-9]*:#' | grep -v -- '--method GET' | grep -v 'api graphql' | grep -q .; then
        bad "$f: every gh api call is --method GET or GraphQL" "$(grep -n 'gh api' "$HERE/$f" | grep -v -- '--method GET')"
    else ok "$f: every gh api call is --method GET or GraphQL"; fi
    if grep -v '^ *#' "$HERE/$f" | grep -Eq 'gh pr merge|--method (POST|PATCH|PUT|DELETE)|mutation'; then
        bad "$f: no write and no mutation"
    else ok "$f: no write and no mutation"; fi
done

echo
echo "board-verdict: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
