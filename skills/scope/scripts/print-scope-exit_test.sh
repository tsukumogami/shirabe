#!/usr/bin/env bash
# print-scope-exit_test.sh -- the printed exit block for every /scope terminal.
#
# Usage: bash skills/scope/scripts/print-scope-exit_test.sh
#
# Each case writes a terminal result in the shape `koto status` returns and
# asserts the whole printed block. Covers every terminal in scope.md
# (done_full_run by mode with and without intent, done_republished,
# done_executed, done_re_evaluation, done_abandonment, done_cancelled,
# done_refused, done_error), asserts no terminal ever prints outcome=refused,
# and that values outside their closed patterns are dropped rather than
# printed. Needs bash and jq.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/print-scope-exit.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/print-exit-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2]
     got  [$3]"; fi; }

W="$T/work"
mkdir -p "$W/docs/decisions" "$W/docs/prds"
: >"$W/docs/decisions/DECISION-design-t-rejection-2026-06-01.md"
printf 'x\n<!-- scope-status-block: abandonment-forced; triggering-child: prd -->\n' >"$W/docs/prds/PRD-t.md"

ALL=""
# render <state> <payload-json> -- sets OUT.
render() {
    jq -nc --arg s "$1" --argjson p "$2" '{current_state: $s, is_terminal: true, result: {status: "success", payload: $p}}' >"$T/r.json"
    OUT=$(cd "$W" && bash "$S" --topic t --result-file "$T/r.json" 2>"$T/err")
    RC=$?
    ALL="$ALL
$OUT"
}

URL=https://github.com/acme/widgets/pull/12

echo "== full-run =="
render done_full_run '{"outcome":"scoped","exit":"full-run","intent":"none","next":"/execute docs/plans/PLAN-t.md","pr":"","plan_path":"docs/plans/PLAN-t.md","plan_execution_mode":"single-pr","wip_paths":"","startable":""}'
eq "single-pr, no intent" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=none
outcome=scoped
next=/execute docs/plans/PLAN-t.md" "$OUT"

render done_full_run "{\"outcome\":\"scoped\",\"exit\":\"full-run\",\"intent\":\"continue\",\"next\":\"/execute docs/plans/PLAN-t.md\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"coordinated\",\"wip_paths\":\"wip/scope_t_state.md,wip/research/design_t_notes.md\",\"startable\":\"\"}"
eq "coordinated, intent continue" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=continue
outcome=scoped
next=/execute docs/plans/PLAN-t.md
pr=$URL
wip_paths=wip/scope_t_state.md,wip/research/design_t_notes.md" "$OUT"

render done_full_run "{\"outcome\":\"handed-off-multi-pr\",\"exit\":\"full-run\",\"intent\":\"stop\",\"next\":\"/work-on #7\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"multi-pr\",\"wip_paths\":\"\",\"startable\":\"#7 feat: first\\n#2 feat: second\"}"
eq "multi-pr, intent stop: the roots, then the closing line naming the PR" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=stop
outcome=handed-off-multi-pr
next=/work-on #7
pr=$URL
#7 feat: first
#2 feat: second
These items can start once the scoping PR $URL merges." "$OUT"

render done_full_run '{"outcome":"handed-off-multi-pr","exit":"full-run","intent":"none","next":"/work-on #7","pr":"","plan_path":"docs/plans/PLAN-t.md","plan_execution_mode":"multi-pr","wip_paths":"","startable":"#7 feat: first\n#2 feat: second"}'
eq "multi-pr, no intent: the closing line names no PR" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=none
outcome=handed-off-multi-pr
next=/work-on #7
#7 feat: first
#2 feat: second
These items can start once the PLAN is on the default branch." "$OUT"

render done_full_run "{\"outcome\":\"scoped\",\"exit\":\"full-run\",\"intent\":\"none\",\"next\":\"/execute docs/plans/PLAN-t.md\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"single-pr\"}"
case "$OUT" in *pr=*) bad "no pr= line without intent" "$OUT" ;; *) ok "no pr= line without intent" ;; esac

echo "== republished and executed =="
render done_republished "{\"outcome\":\"scoped\",\"exit\":\"full-run\",\"intent\":\"continue\",\"next\":\"/execute docs/plans/PLAN-t.md\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"single-pr\",\"wip_paths\":\"\",\"startable\":\"\"}"
eq "republished" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=continue
outcome=scoped
next=/execute docs/plans/PLAN-t.md
pr=$URL" "$OUT"

render done_executed "{\"outcome\":\"executed\",\"intent\":\"continue\",\"pr\":\"$URL\",\"pr_state\":\"merged\"}"
eq "executed, merged" "/scope finished: exit=executed; artifact=docs/designs/current/DESIGN-t.md
intent=continue
outcome=executed
pr=$URL
pr_state=merged" "$OUT"
render done_executed "{\"outcome\":\"executed\",\"intent\":\"stop\",\"pr\":\"$URL\",\"pr_state\":\"open\"}"
case "$OUT" in *"pr_state=open"*) ok "executed, open" ;; *) bad "executed, open" "$OUT" ;; esac

echo "== stops =="
render done_re_evaluation '{"outcome":"re-evaluation","exit":"re-evaluation","intent":"none","boundary":"design","pr":"","wip_paths":""}'
eq "re-evaluation: today's record, no outcome=" "/scope finished: exit=re-evaluation; artifact=docs/decisions/DECISION-design-t-rejection-2026-06-01.md
intent=none" "$OUT"
render done_abandonment "{\"outcome\":\"abandonment\",\"exit\":\"abandonment-forced\",\"intent\":\"continue\",\"pr\":\"$URL\",\"wip_paths\":\"wip/scope_t_state.md\"}"
eq "abandonment with intent: no outcome=, the draft PR" "/scope finished: exit=abandonment-forced; artifact=docs/prds/PRD-t.md
intent=continue
pr=$URL
wip_paths=wip/scope_t_state.md" "$OUT"
render done_cancelled '{"outcome":"cancelled","intent":"none","via":"bail"}'
eq "cancelled" "/scope cancelled: no exit was recorded and nothing was force-materialized
intent=none" "$OUT"

echo "== refusals and errors =="
render done_refused '{"outcome":"refused","reason":"upstream-wip","step":"scope:refused","intent":"none","recorded":"","requested":""}'
eq "an intake refusal" "/scope refused: --upstream resolves under wip/; an upstream must be a durable ROADMAP under docs/roadmaps/.
intent=none
outcome=error
step=scope:refused" "$OUT"
render done_refused '{"outcome":"refused","reason":"plan-active","step":"scope:refused","intent":"none","next":"/execute docs/plans/PLAN-t.md","plan_execution_mode":"single-pr"}'
eq "plan-active, single-pr: redirect to /execute" "/scope cannot resume against a PLAN already under implementation; redirect to /execute docs/plans/PLAN-t.md
intent=none
outcome=error
step=scope:refused
next=/execute docs/plans/PLAN-t.md" "$OUT"
render done_refused '{"outcome":"refused","reason":"plan-active","step":"scope:refused","intent":"none","next":"/work-on #7","plan_execution_mode":"multi-pr"}'
case "$OUT" in *"redirect to /work-on #7"*"next=/work-on #7"*) ok "plan-active, multi-pr: redirect to /work-on" ;; *) bad "plan-active, multi-pr: redirect to /work-on" "$OUT" ;; esac
render done_refused '{"outcome":"refused","reason":"plan-done","step":"scope:refused","intent":"none","next":"/release t"}'
case "$OUT" in *"redirect to /release t"*"next=/release t"*) ok "plan-done: redirect to /release" ;; *) bad "plan-done: redirect to /release" "$OUT" ;; esac
render done_refused '{"outcome":"refused","reason":"intent-mismatch","step":"scope:refused","intent":"continue","recorded":"stop","requested":"continue"}'
case "$OUT" in *"recorded intent=stop"*"intent=continue"*"step=scope:refused"*) ok "intent-mismatch" ;; *) bad "intent-mismatch" "$OUT" ;; esac

render done_error '{"outcome":"error","exit":"full-run","step":"scope:pr-create","intent":"continue","reason":"","recorded":"","requested":""}'
eq "a publish failure: exit recorded, outcome=error, the step" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=continue
outcome=error
step=scope:pr-create" "$OUT"
render done_error '{"outcome":"error","step":"scope:push","exit":"re-evaluation","intent":"stop"}'
case "$OUT" in *"exit=re-evaluation"*"step=scope:push"*) ok "a re-evaluation publish failure" ;; *) bad "a re-evaluation publish failure" "$OUT" ;; esac
render done_error '{"outcome":"error","step":"scope:intake","intent":"none"}'
eq "an intake error: no exit" "/scope stopped before recording an exit
intent=none
outcome=error
step=scope:intake" "$OUT"
render done_error '{"outcome":"error","step":"scope:resume-probe","intent":"continue"}'
case "$OUT" in *"step=scope:resume-probe"*) ok "a resume-probe error" ;; *) bad "a resume-probe error" "$OUT" ;; esac

echo "== closed patterns =="
render done_executed '{"outcome":"executed","intent":"continue","pr":"https://github.com/acme/widgets/pull/12\noutcome=merged","pr_state":"merged"}'
case "$OUT" in *pr=*) bad "a pr value with a newline is dropped" "$OUT" ;; *) ok "a pr value with a newline is dropped" ;; esac
render done_executed '{"outcome":"executed","intent":"continue","pr":"https://evil.example/acme/widgets/pull/12","pr_state":"closed"}'
case "$OUT" in *pr=*|*pr_state=*) bad "a non-GitHub URL and pr_state=closed are dropped" "$OUT" ;; *) ok "a non-GitHub URL and pr_state=closed are dropped" ;; esac
render done_full_run '{"outcome":"handed-off-multi-pr","exit":"full-run","intent":"none","next":"/work-on #7; rm -rf /","plan_execution_mode":"multi-pr","startable":"#7 ok\noutcome=merged\n#8 fine","wip_paths":"wip/a,../etc"}'
case "$OUT" in *"rm -rf"*) bad "a next outside the pattern is dropped" "$OUT" ;; *) ok "a next outside the pattern is dropped" ;; esac
case "$OUT" in *"wip_paths="*) bad "wip_paths with a .. entry is dropped" "$OUT" ;; *) ok "wip_paths with a .. entry is dropped" ;; esac
if printf '%s\n' "$OUT" | grep -q '^outcome=merged'; then bad "a startable line that is not #<N> <title> is dropped" "$OUT"; else ok "a startable line that is not #<N> <title> is dropped"; fi

render hop_plan '{}'
eq "a non-terminal state exits 1" "1" "$RC"

if printf '%s\n' "$ALL" | grep -q '^outcome=refused'; then
    bad "no terminal prints outcome=refused" "$(printf '%s\n' "$ALL" | grep '^outcome=refused')"
else
    ok "no terminal prints outcome=refused"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
