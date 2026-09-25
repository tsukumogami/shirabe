#!/usr/bin/env bash
# scope-result_test.sh -- /scope's terminal results, driven through real koto
# sessions against the shipped scope.md.
#
# Usage: bash skills/scope/scripts/scope-result_test.sh
#
# Each case builds a repository with a local bare `origin`, puts
# testdata/gh-stateful-stub.sh first on PATH as `gh` (koto hands its PATH to the
# gates and default actions it runs), opens a `scope-<topic>` session, and walks
# it to a terminal. The recorded result is asserted with `koto status`, and on
# the executed path under --koto-leg with `koto request get`, then rendered with
# print-scope-exit.sh. Cases:
#
#   - an executed topic with a merged, then an open, owned PR: done_executed with
#     non-empty pr and pr_state matching the owned PR; the same through a leg;
#     a cross-repository-only PR ends done_error scope:pr-create with no URL
#   - an Active PLAN without intent: done_refused plan-active, next by mode
#   - a republish over a PR recording intent=stop: done_republished, the body
#     rewritten, no second PR
#   - a full-run exit, with and without intent: intent_declared sends the intent
#     run through publish_full_run and the no-intent run straight to cleanup,
#     with no gh call at all
#   - a publish that fails at pr create: done_error scope:pr-create with the exit
#     recorded; after the scenario is fixed, the next session routes through
#     resume_route back to publish_full_run and reaches done_full_run
#
# koto admits a --var value only inside ^[a-zA-Z0-9._/:@ \-]*$. When this
# checkout's path falls outside it, the cases run a copy of scope.md with the
# path written in for {{PLUGIN_ROOT}}. SKIPs (exit 0) without koto, jq, git or
# shirabe; the CI job installs all four.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
TEMPLATE="$REPO/skills/scope/koto-templates/scope.md"
STUB="$HERE/testdata/gh-stateful-stub.sh"
FIXTURES="$HERE/testdata"
PUBLISH="$HERE/publish-scoping-pr.sh"
PRINT="$HERE/print-scope-exit.sh"

for bin in koto jq git shirabe; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- no case ran"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/scope-result-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$2] not in [$3]" ;; esac; }

PLUGIN_ROOT_VAR="$REPO"
case "$REPO" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$REPO" "$T/plugin"
        PLUGIN_ROOT_VAR="$T/plugin"
        case "$PLUGIN_ROOT_VAR" in
            *[!a-zA-Z0-9._/:@\ -]*)
                sed "s#{{PLUGIN_ROOT}}#$REPO#g" "$TEMPLATE" >"$T/scope.md"
                TEMPLATE="$T/scope.md"
                PLUGIN_ROOT_VAR=/koto-probe
                echo "note: this checkout's path is outside koto's --var allowlist, so these cases run a"
                echo "      copy of scope.md with the path written in for {{PLUGIN_ROOT}}" ;;
        esac ;;
esac

BIN="$T/bin"
mkdir -p "$BIN"
cp "$STUB" "$BIN/gh"
chmod +x "$BIN/gh"
KH="$T/koto-home"
mkdir -p "$KH"

N=0
R=""; GHF=""
# repo <topic> -- a bare origin with main, a clone on docs/<topic>. Sets R, GHF.
repo() {
    N=$((N + 1))
    R="$T/work$N"; GHF="$T/gh$N"
    mkdir -p "$GHF"; : >"$GHF/calls"; printf '[]' >"$GHF/prs.json"
    git init -q --bare -b main "$T/origin$N.git"
    git init -q -b main "$R"
    printf '# repo\n' >"$R/README.md"
    git -C "$R" add README.md && git -C "$R" commit -q -m init
    git -C "$R" remote add origin "$T/origin$N.git"
    git -C "$R" push -q -u origin main
    git -C "$R" checkout -q -b "docs/$1"
    mkdir -p "$R/docs" "$R/wip"
}

seed_pr() { # seed_pr <url> <state> <cross> <head> <intent>
    jq --arg u "$1" --arg s "$2" --argjson c "$3" --arg h "$4" --arg i "$5" \
       '. + [{url: $u, state: $s, isCrossRepository: $c, author: {login: "me"},
              baseRefName: "main", headRefName: $h, body: ("intent=" + $i + "\n"), isDraft: true}]' \
       "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
}

every_hop() { # every_hop <topic> <mode> -- the four artifacts, committed
    mkdir -p "$R/docs/briefs" "$R/docs/prds" "$R/docs/designs" "$R/docs/plans"
    sed "s/scope-koto-adoption/$1/g" "$FIXTURES/brief.md.fixture"  >"$R/docs/briefs/BRIEF-$1.md"
    sed "s/scope-koto-adoption/$1/g" "$FIXTURES/prd.md.fixture"    >"$R/docs/prds/PRD-$1.md"
    sed "s/scope-koto-adoption/$1/g" "$FIXTURES/design.md.fixture" >"$R/docs/designs/DESIGN-$1.md"
    sed -e "s/scope-koto-adoption/$1/g" -e "s/^execution_mode: .*/execution_mode: $2/" \
        "$FIXTURES/plan.md.fixture" >"$R/docs/plans/PLAN-$1.md"
    git -C "$R" add docs && git -C "$R" commit -q -m "docs: $1"
}

k() { (cd "$R" && HOME="$KH" PATH="$BIN:$PATH" GHF="$GHF" koto "$@"); }

# open <topic> [--koto-leg <req>:scope] [--var ...] -- a fresh or replacing session.
open() {
    local topic="$1"; shift
    k init "scope-$topic" --template "$TEMPLATE" --var TOPIC="$topic" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var PLUGIN_ROOT_PLACEMENT=outside \
        --replace-terminal "$@" >"$T/init.out" 2>&1 \
        || bad "koto init scope-$topic" "$(cat "$T/init.out")"
}
tick() { k next "scope-$1" --no-cleanup ${2:+--with-data "$2"} 2>/dev/null; }
state_of() { k status "scope-$1" 2>/dev/null | jq -r '.current_state'; }
result() { k status "scope-$1" 2>/dev/null | jq -r --arg f "$2" '.result.payload[$f] // ""'; }
publish() { # publish <topic> <exit> <intent>
    (cd "$R" && HOME="$KH" PATH="$BIN:$PATH" GHF="$GHF" bash "$PUBLISH" --topic "$1" --exit "$2" \
        --intent "$3" --session "scope-$1" >"$T/publish.out" 2>&1)
}
printed() { (cd "$R" && HOME="$KH" PATH="$BIN:$PATH" bash "$PRINT" --topic "$1" --session "scope-$1" 2>&1); }

echo "== executed topics =="

URL=https://github.com/acme/widgets/pull/42
repo ex
mkdir -p "$R/docs/designs/current"
sed "s/scope-koto-adoption/ex/g" "$FIXTURES/design.md.fixture" >"$R/docs/designs/current/DESIGN-ex.md"
git -C "$R" add docs && git -C "$R" commit -q -m "executed"
seed_pr "$URL" MERGED false docs/ex continue
open ex --var INTENT_FLAG=continue
tick ex >/dev/null
eq "executed, merged: done_executed" "done_executed" "$(state_of ex)"
eq "executed, merged: the result's pr is the owned PR" "$URL" "$(result ex pr)"
eq "executed, merged: pr_state" "merged" "$(result ex pr_state)"
eq "executed, merged: outcome" "executed" "$(result ex outcome)"
OUT=$(printed ex)
has "executed: prints outcome=executed" "outcome=executed" "$OUT"
has "executed: prints pr_state=merged" "pr_state=merged" "$OUT"
has "executed: prints the URL" "pr=$URL" "$OUT"
if grep -E '^pr (create|edit)' "$GHF/calls" >/dev/null; then bad "executed: no GitHub write"; else ok "executed: no GitHub write"; fi

REQ=$(k request create --with-data '{"legs":[{"name":"scope","role":"scope","template":"scope.md","inputs":{}}]}' \
    --requested-by scope-result-test --coordinator-of-record scope-result-test 2>/dev/null | jq -r '.request_id')
jq '.[0].state = "OPEN"' "$GHF/prs.json" >"$GHF/prs.new" && mv "$GHF/prs.new" "$GHF/prs.json"
open ex --var INTENT_FLAG=continue --koto-leg "$REQ:scope"
tick ex >/dev/null
eq "executed, open, under --koto-leg: done_executed" "done_executed" "$(state_of ex)"
LEG=$(k request get "$REQ" 2>/dev/null)
eq "the leg's result carries the owned PR" "$URL" "$(printf '%s' "$LEG" | jq -r '.legs.scope.result.payload.pr // ""')"
eq "the leg's result carries pr_state=open" "open" "$(printf '%s' "$LEG" | jq -r '.legs.scope.result.payload.pr_state // ""')"
eq "the leg's result carries outcome=executed" "executed" "$(printf '%s' "$LEG" | jq -r '.legs.scope.result.payload.outcome // ""')"

repo exf
mkdir -p "$R/docs/designs/current"
sed "s/scope-koto-adoption/exf/g" "$FIXTURES/design.md.fixture" >"$R/docs/designs/current/DESIGN-exf.md"
git -C "$R" add docs && git -C "$R" commit -q -m "executed"
seed_pr "https://github.com/fork/widgets/pull/9" MERGED true docs/exf continue
open exf --var INTENT_FLAG=continue
tick exf >/dev/null
eq "a cross-repository-only PR: done_error" "done_error" "$(state_of exf)"
eq "a cross-repository-only PR: step=scope:pr-create" "scope:pr-create" "$(result exf step)"
case "$(k status scope-exf)" in *pull/9*) bad "the foreign URL never reaches the result" ;; *) ok "the foreign URL never reaches the result" ;; esac

echo "== an Active PLAN without intent =="
for mode in single-pr multi-pr; do
    repo "pa-$mode"
    every_hop "pa-$mode" "$mode"
    open "pa-$mode"
    tick "pa-$mode" >/dev/null
    eq "$mode: done_refused" "done_refused" "$(state_of "pa-$mode")"
    eq "$mode: reason plan-active" "plan-active" "$(result "pa-$mode" reason)"
    case "$mode" in
        single-pr) eq "single-pr: next is /execute on the PLAN" "/execute docs/plans/PLAN-pa-single-pr.md" "$(result "pa-$mode" next)" ;;
        multi-pr) case "$(result "pa-$mode" next)" in /work-on*) ok "multi-pr: next is /work-on" ;; *) bad "multi-pr: next is /work-on" "$(result "pa-$mode" next)" ;; esac ;;
    esac
    eq "$mode: no gh call" "" "$(cat "$GHF/calls")"
done

echo "== republish over intent=stop =="
repo rp
every_hop rp single-pr
git -C "$R" push -q origin HEAD:refs/heads/docs/rp
seed_pr "https://github.com/acme/widgets/pull/7" OPEN false docs/rp stop
open rp --var INTENT_FLAG=continue
eq "an Active PLAN with intent goes to republish" "republish" "$(tick rp | jq -r '.state')"
publish rp full-run continue
tick rp '{"publish_result":"attempted"}' >/dev/null
eq "republish: done_republished" "done_republished" "$(state_of rp)"
eq "republish: outcome scoped" "scoped" "$(result rp outcome)"
eq "republish: the reused PR" "https://github.com/acme/widgets/pull/7" "$(result rp pr)"
eq "republish: no pr create" "0" "$(grep -c '^pr create' "$GHF/calls" | tr -d ' ')"
eq "republish: the body now records intent=continue" "1" "$(jq -r '.[0].body' "$GHF/prs.json" | grep -c '^intent=continue$')"

echo "== a full-run exit, with and without intent =="

# pointer 3 with a fresh state file resumes at finalize.
state3() { printf 'topic: %s\nlast_updated: %s\nphase_pointer: 3\nintent: %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >"$R/wip/scope_$1_state.md"; }

repo fn
every_hop fn single-pr
: >"$GHF/calls"
state3 fn none
open fn
eq "no intent, pointer 3: finalize" "finalize" "$(tick fn | jq -r '.state')"
tick fn '{"exit":"full-run"}' >/dev/null
tick fn '{"exit_artifacts":"docs/plans/PLAN-fn.md: Active","plan_execution_mode":"single-pr"}' >/dev/null
eq "no intent: straight to cleanup, past no publish state" "cleanup_full_run" "$(state_of fn)"
tick fn '{"cleanup_result":"done"}' >/dev/null
eq "no intent: done_full_run" "done_full_run" "$(state_of fn)"
eq "no intent: outcome scoped" "scoped" "$(result fn outcome)"
eq "no intent: next" "/execute docs/plans/PLAN-fn.md" "$(result fn next)"
eq "no intent: pr empty" "" "$(result fn pr)"
# The PLAN validator the chain gate runs (shirabe validate, FC09) probes
# `gh auth status` itself, read-only, as it did before intent existed; /scope
# makes no gh call of its own on a no-intent run.
eq "no intent: no gh call beyond the validator's auth probe" "" "$(grep -vx 'auth status' "$GHF/calls")"
eq "no intent: nothing pushed" "" "$(git -C "$R" ls-remote origin refs/heads/docs/fn)"
OUT=$(printed fn)
has "no intent: prints intent=none" "intent=none" "$OUT"
case "$OUT" in *pr=*) bad "no intent: prints no pr=" "$OUT" ;; *) ok "no intent: prints no pr=" ;; esac

repo fi
every_hop fi single-pr
state3 fi continue
open fi --var INTENT_FLAG=continue
tick fi >/dev/null
tick fi '{"exit":"full-run"}' >/dev/null
tick fi '{"exit_artifacts":"docs/plans/PLAN-fi.md: Active","plan_execution_mode":"single-pr"}' >/dev/null
eq "intent: the exit goes to publish_full_run" "publish_full_run" "$(state_of fi)"
tick fi '{"publish_result":"attempted"}' >/dev/null
eq "intent: claiming a publish that never happened is refused by the gate" "done_error" "$(state_of fi)"

repo fi2
every_hop fi2 single-pr
state3 fi2 continue
open fi2 --var INTENT_FLAG=continue
tick fi2 >/dev/null
tick fi2 '{"exit":"full-run"}' >/dev/null
tick fi2 '{"exit_artifacts":"docs/plans/PLAN-fi2.md: Active","plan_execution_mode":"single-pr"}' >/dev/null
publish fi2 full-run continue
tick fi2 '{"publish_result":"attempted"}' >/dev/null
eq "intent: a verified publish reaches cleanup" "cleanup_full_run" "$(state_of fi2)"
tick fi2 '{"cleanup_result":"done"}' >/dev/null
eq "intent: done_full_run" "done_full_run" "$(state_of fi2)"
eq "intent: the result names the scoping PR" "https://github.com/acme/widgets/pull/100" "$(result fi2 pr)"
eq "intent: one pr create --draft" "1" "$(grep -c '^pr create .*--draft' "$GHF/calls" | tr -d ' ')"
OUT=$(printed fi2)
has "intent: prints intent=continue" "intent=continue" "$OUT"
has "intent: prints outcome=scoped" "outcome=scoped" "$OUT"
has "intent: prints the PR" "pr=https://github.com/acme/widgets/pull/100" "$OUT"

echo "== a failed publish, and its retry =="
repo pf
every_hop pf single-pr
state3 pf continue
echo 1 >"$GHF/pr-create.rc"
open pf --var INTENT_FLAG=continue
tick pf >/dev/null
tick pf '{"exit":"full-run"}' >/dev/null
tick pf '{"exit_artifacts":"docs/plans/PLAN-pf.md: Active","plan_execution_mode":"single-pr"}' >/dev/null
publish pf full-run continue
# The directive's own step: record the failed step in the state file.
STEP=$(sed -n 's/^step=//p' "$T/publish.out")
printf 'exit: full-run\nplan_execution_mode: single-pr\npublish_error: %s\n' "$STEP" >>"$R/wip/scope_pf_state.md"
tick pf '{"publish_result":"attempted"}' >/dev/null
eq "a failing pr create: done_error" "done_error" "$(state_of pf)"
eq "a failing pr create: step=scope:pr-create" "scope:pr-create" "$(result pf step)"
eq "a failing pr create: the exit is still recorded" "full-run" "$(result pf exit)"
has "the state file keeps publish_error" "publish_error: scope:pr-create" "$(cat "$R/wip/scope_pf_state.md")"
OUT=$(printed pf)
has "prints outcome=error" "outcome=error" "$OUT"
has "prints step=scope:pr-create" "step=scope:pr-create" "$OUT"

rm -f "$GHF/pr-create.rc"
open pf
eq "the retry routes through resume_route back to publish_full_run" "publish_full_run" "$(tick pf | jq -r '.state')"
publish pf full-run continue
sed -i.bak '/^publish_error:/d' "$R/wip/scope_pf_state.md" && rm -f "$R/wip/scope_pf_state.md.bak"
tick pf '{"publish_result":"attempted"}' >/dev/null
tick pf '{"cleanup_result":"done"}' >/dev/null
eq "the retry reaches done_full_run" "done_full_run" "$(state_of pf)"
eq "the retry: one PR, created on the retry" "1" "$(jq 'length' "$GHF/prs.json")"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
