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
# printed. Through --session, against a stand-in koto, it pins that a session
# koto removed at its terminal prints its block from the record koto answers
# with, and that a name that never existed exits 1. Needs bash and jq.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/print-scope-exit.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T="$(mktemp -d "${TMPDIR:-/tmp}/print-exit-test.XXXXXX")" || exit 1
ktg_on_exit 'rm -rf "$T"'

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2]
     got  [$3]"; fi; }

W="$T/work"
mkdir -p "$W/docs/decisions" "$W/docs/prds"
: >"$W/docs/decisions/DECISION-design-t-rejection-2026-06-01.md"
: >"$W/docs/decisions/DECISION-brief-t-rejection-2026-06-01.md"
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
render done_full_run '{"outcome":"scoped","exit":"full-run","intent":"none","next":"/execute docs/plans/PLAN-t.md","pr":"","plan_path":"docs/plans/PLAN-t.md","plan_execution_mode":"single-pr","startable":""}'
eq "single-pr, no intent" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=none
outcome=scoped
next=/execute docs/plans/PLAN-t.md" "$OUT"

render done_full_run "{\"outcome\":\"scoped\",\"exit\":\"full-run\",\"intent\":\"continue\",\"next\":\"/execute docs/plans/PLAN-t.md\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"coordinated\",\"startable\":\"\"}"
eq "coordinated, intent continue" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=continue
outcome=scoped
next=/execute docs/plans/PLAN-t.md
pr=$URL" "$OUT"

render done_full_run "{\"outcome\":\"handed-off-multi-pr\",\"exit\":\"full-run\",\"intent\":\"stop\",\"next\":\"/work-on #7\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"multi-pr\",\"startable\":\"#7 feat: first\\n#2 feat: second\"}"
eq "multi-pr, intent stop: the roots, then the closing line naming the PR" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=stop
outcome=handed-off-multi-pr
next=/work-on #7
pr=$URL
#7 feat: first
#2 feat: second
These items can start once the scoping PR $URL merges." "$OUT"

render done_full_run '{"outcome":"handed-off-multi-pr","exit":"full-run","intent":"none","next":"/work-on #7","pr":"","plan_path":"docs/plans/PLAN-t.md","plan_execution_mode":"multi-pr","startable":"#7 feat: first\n#2 feat: second"}'
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
render done_republished "{\"outcome\":\"scoped\",\"exit\":\"full-run\",\"intent\":\"continue\",\"next\":\"/execute docs/plans/PLAN-t.md\",\"pr\":\"$URL\",\"plan_path\":\"docs/plans/PLAN-t.md\",\"plan_execution_mode\":\"single-pr\",\"startable\":\"\"}"
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
render done_re_evaluation '{"outcome":"re-evaluation","exit":"re-evaluation","intent":"none","boundary":"design","pr":""}'
eq "re-evaluation: today's record, no outcome=" "/scope finished: exit=re-evaluation; artifact=docs/decisions/DECISION-design-t-rejection-2026-06-01.md
intent=none" "$OUT"
render done_re_evaluation '{"outcome":"re-evaluation","exit":"re-evaluation","intent":"none","boundary":"brief","pr":""}'
eq "re-evaluation at the brief boundary names the BRIEF rejection record" "/scope finished: exit=re-evaluation; artifact=docs/decisions/DECISION-brief-t-rejection-2026-06-01.md
intent=none" "$OUT"
render done_abandonment "{\"outcome\":\"abandonment\",\"exit\":\"abandonment-forced\",\"intent\":\"continue\",\"pr\":\"$URL\",\"forced_artifact\":\"docs/prds/PRD-t.md\"}"
eq "abandonment with intent: no outcome=, the draft PR" "/scope finished: exit=abandonment-forced; artifact=docs/prds/PRD-t.md
intent=continue
pr=$URL" "$OUT"
# The artifact comes from the result's forced_artifact, never from the tree:
# the marked PRD on disk names nothing when the result carries no key (a run
# force-materialized before the key existed), and a key naming a document that
# carries no marker is still the one printed.
render done_abandonment '{"outcome":"abandonment","exit":"abandonment-forced","intent":"none","pr":""}'
eq "abandonment without forced_artifact: artifact=none, the marked PRD is not read" "/scope finished: exit=abandonment-forced; artifact=none
intent=none" "$OUT"
render done_abandonment '{"outcome":"abandonment","exit":"abandonment-forced","intent":"none","pr":"","forced_artifact":"docs/designs/current/DESIGN-t.md"}'
eq "abandonment: the key's path, though no document there carries the marker" "/scope finished: exit=abandonment-forced; artifact=docs/designs/current/DESIGN-t.md
intent=none" "$OUT"
for p in docs/plans/PLAN-t.md docs/prds/PRD-other.md ../docs/prds/PRD-t.md "docs/prds/PRD-t.md
x"; do
    render done_abandonment "$(jq -nc --arg p "$p" '{outcome:"abandonment",exit:"abandonment-forced",intent:"none",pr:"",forced_artifact:$p}')"
    eq "abandonment: a forced_artifact outside the four paths is dropped (${p%%$'\n'*})" "/scope finished: exit=abandonment-forced; artifact=none
intent=none" "$OUT"
done
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
render done_error '{"outcome":"error","step":"scope:pr-create","exit":"abandonment-forced","intent":"continue","forced_artifact":"docs/prds/PRD-t.md"}'
eq "an abandonment publish failure: the artifact from forced_artifact" "/scope finished: exit=abandonment-forced; artifact=docs/prds/PRD-t.md
intent=continue
outcome=error
step=scope:pr-create" "$OUT"
render done_error '{"outcome":"error","step":"scope:pr-create","exit":"abandonment-forced","intent":"continue"}'
case "$OUT" in "/scope finished: exit=abandonment-forced; artifact=none"*) ok "an abandonment publish failure without the key: artifact=none" ;; *) bad "an abandonment publish failure without the key: artifact=none" "$OUT" ;; esac
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
case "$OUT" in *"wip_paths="*) bad "a leftover wip_paths in a payload is never printed" "$OUT" ;; *) ok "a leftover wip_paths in a payload is never printed" ;; esac
if grep -q '^outcome=merged' <<<"$OUT"; then bad "a startable line that is not #<N> <title> is dropped" "$OUT"; else ok "a startable line that is not #<N> <title> is dropped"; fi

render hop_plan '{}'
eq "a non-terminal state exits 1" "1" "$RC"

echo "== --session against a stand-in koto =="
# A koto that keeps finished records (tsukumogami/koto#355) answers `koto status`
# for a scope session it removed at its terminal: exit 0, "removed": true, and
# the same current_state and result a kept session reports. The exit block is
# read from that answer, deliberately: it carries everything the block needs.
# A name that never existed still answers "not found" (exit 2), and the script
# exits 1. The stand-in answers from $STATUS_ANSWERS/<name>; a real koto is
# never asked, since the one on PATH may predate the record.
STUBBIN="$T/stubbin"
mkdir -p "$STUBBIN" "$T/answers"
cat >"$STUBBIN/koto" <<'STUB'
#!/bin/bash
if [ "${1:-}" = status ] && [ -f "$STATUS_ANSWERS/${2:-}" ]; then
    cat "$STATUS_ANSWERS/$2"
    exit 0
fi
[ "${1:-}" = status ] && { printf '{"command":"status","error":"workflow '"'"'%s'"'"' not found"}\n' "${2:-}"; exit 2; }
exit 1
STUB
chmod +x "$STUBBIN/koto"
# session <name> -- run against the stand-in; sets OUT and RC.
session() {
    OUT=$(cd "$W" && STATUS_ANSWERS="$T/answers" PATH="$STUBBIN:$PATH" bash "$S" --topic t --session "$1" 2>"$T/err")
    RC=$?
}
jq -nc '{name: "scope-t", current_state: "done_full_run", is_terminal: true,
    result: {status: "success", payload: {outcome: "scoped", exit: "full-run", intent: "none",
        next: "/execute docs/plans/PLAN-t.md", pr: "", plan_path: "docs/plans/PLAN-t.md",
        plan_execution_mode: "single-pr", startable: ""}},
    removed: true, finished_at: "2026-10-12T14:00:00Z", session_id: "0123456789abcdef",
    execution_dir: "/work/repo"}' >"$T/answers/scope-t"
session scope-t
eq "a removed session's exit is read from its record: exit 0" "0" "$RC"
eq "a removed session prints the block a kept one does" "/scope finished: exit=full-run; artifact=docs/plans/PLAN-t.md
intent=none
outcome=scoped
next=/execute docs/plans/PLAN-t.md" "$OUT"
session scope-never
eq "a session that never existed exits 1" "1" "$RC"
eq "a session that never existed prints no block" "" "$OUT"

if grep -q '^outcome=refused' <<<"$ALL"; then
    bad "no terminal prints outcome=refused" "$(printf '%s\n' "$ALL" | grep '^outcome=refused')"
else
    ok "no terminal prints outcome=refused"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
