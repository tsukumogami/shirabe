#!/usr/bin/env bash
# record-scope-exit_test.sh -- the result facts /scope's record states write.
#
# Usage: bash skills/scope/scripts/record-scope-exit_test.sh
#
# A koto stand-in stores each context key as a file; a gh stub serves canned
# JSON per case and logs every call. Asserts the PLAN facts per mode (the next
# command R10 and R23 name), the startable list on multi-pr, the PR on intent
# runs through owned-pr.sh, no gh call at all on a no-intent run, exit_record
# error when the lookup cannot name exactly one owned PR, and stale keys
# cleared. Needs bash, git and jq.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/record-scope-exit.sh"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/scope-exit-test.XXXXXX")"
T="$(cd -P "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

SHIM="$T/shim"
STORE="$T/store"
mkdir -p "$SHIM" "$STORE"
export STORE
cat >"$SHIM/koto" <<'STUB'
#!/usr/bin/env bash
[ "$1" = context ] || exit 2
d="$STORE/$3"
case "$2" in
    add) mkdir -p "$d"; cat >"$d/$4" ;;
    remove) rm -f "$d/$4" ;;
    exists) [ -f "$d/$4" ] ;;
    get) cat "$d/$4" 2>/dev/null || exit 1 ;;
    *) exit 2 ;;
esac
STUB
cat >"$SHIM/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GHF/calls"
case "$1 $2" in
    "api user") key=user ;;
    "api repos/"*) key=repo ;;
    "repo view") key=repo-view ;;
    "pr list") key=pr-list ;;
    *) echo "gh stub: unexpected: $*" >&2; exit 9 ;;
esac
rc=0; [ -f "$GHF/$key.rc" ] && rc=$(cat "$GHF/$key.rc")
[ "$rc" = 0 ] || exit "$rc"
jqf=""; prev=""
for a in "$@"; do [ "$prev" = "--jq" ] && jqf="$a"; prev="$a"; done
if [ -n "$jqf" ]; then jq -r "$jqf" "$GHF/$key.json"; else cat "$GHF/$key.json"; fi
STUB
chmod +x "$SHIM/koto" "$SHIM/gh"

R="$T/repo"
git -C "$T" init -q repo
git -C "$R" checkout -q -b docs/topic
mkdir -p "$R/docs/plans"

URL="https://github.com/acme/widgets/pull/5"
N=0
GHF=""
fixture() { # fixture <pr-list-json>
    N=$((N + 1)); GHF="$T/gh$N"; mkdir -p "$GHF"
    printf '{"login":"me"}' >"$GHF/user.json"
    printf '{"default_branch":"main"}' >"$GHF/repo.json"
    printf '{"nameWithOwner":"acme/widgets"}' >"$GHF/repo-view.json"
    printf '%s' "$1" >"$GHF/pr-list.json"
    : >"$GHF/calls"
}
pr() { # pr <url> <cross> <author>
    printf '{"url":"%s","state":"OPEN","isCrossRepository":%s,"author":{"login":"%s"},"baseRefName":"main","headRefName":"docs/topic"}' "$1" "$2" "$3"
}
plan() { # plan <mode>
    cat >"$R/docs/plans/PLAN-topic.md" <<EOF
---
schema: plan/v1
status: Active
execution_mode: $1
---

# PLAN: topic

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#21: feat: b](#issue-21) | [#20](#issue-20) | simple |
| [#20: feat: a](#issue-20) | None | simple |
| [#22: feat: c](#issue-22) | None | simple |
EOF
}
run() { # run <session> <intent> <stage>
    (cd "$R" && PATH="$SHIM:$PATH" GHF="$GHF" bash "$S" --session "$1" --topic topic --intent "$2" --stage "$3" >/dev/null 2>"$T/err")
    RC=$?
}
key() { cat "$STORE/$1/$2" 2>/dev/null; }
has() { [ -f "$STORE/$1/$2" ]; }

echo "== the PLAN facts, by mode =="
for mode in single-pr coordinated; do
    plan "$mode"; fixture "[]"
    run "r-$mode" none resume
    eq "$mode: exit 0" "0" "$RC"
    eq "$mode: plan_path" "docs/plans/PLAN-topic.md" "$(key "r-$mode" plan_path)"
    eq "$mode: plan_execution_mode" "$mode" "$(key "r-$mode" plan_execution_mode)"
    eq "$mode: next is /execute on the PLAN" "/execute docs/plans/PLAN-topic.md" "$(key "r-$mode" next)"
    eq "$mode: no startable list" "" "$(key "r-$mode" startable)"
done
plan multi-pr; fixture "[]"
run r-multi none resume
eq "multi-pr: next is /work-on the first startable item" "/work-on #20" "$(key r-multi next)"
eq "multi-pr: startable lists the roots in PLAN order" "#20 feat: a
#22 feat: c" "$(key r-multi startable)"
if has r-multi pr || has r-multi exit_record; then bad "the resume stage writes no pr or exit_record"; else ok "the resume stage writes no pr or exit_record"; fi
eq "the resume stage makes no gh call" "" "$(cat "$GHF/calls")"

rm -f "$R/docs/plans/PLAN-topic.md"; fixture "[]"
run r-noplan none resume
eq "no PLAN: plan_path empty but present" "yes|" "$(has r-noplan plan_path && echo yes)|$(key r-noplan plan_path)"
eq "no PLAN: next empty" "" "$(key r-noplan next)"

echo "== exit stage, no intent =="
plan single-pr; fixture "[$(pr "$URL" false me)]"
run x-none none exit
eq "no intent: exit_record ok" "ok" "$(key x-none exit_record)"
eq "no intent: pr empty" "yes|" "$(has x-none pr && echo yes)|$(key x-none pr)"
eq "no intent: wip_paths written empty" "yes|" "$(has x-none wip_paths && echo yes)|$(key x-none wip_paths)"
eq "no intent: no gh call" "" "$(cat "$GHF/calls")"

echo "== exit stage, intent =="
fixture "[$(pr "$URL" false me)]"
mkdir -p "$STORE/x-one"; printf 'wip/scope_topic_state.md' >"$STORE/x-one/wip_paths"
run x-one continue exit
eq "one owned PR: pr" "$URL" "$(key x-one pr)"
eq "one owned PR: exit_record ok" "ok" "$(key x-one exit_record)"
eq "a publish's wip_paths is kept" "wip/scope_topic_state.md" "$(key x-one wip_paths)"
if grep -q -- '--state open' "$GHF/calls"; then ok "the lookup is owned-pr.sh --state open"; else bad "the lookup is owned-pr.sh --state open" "$(cat "$GHF/calls")"; fi
if grep -E '^pr (create|edit|merge)' "$GHF/calls" >/dev/null; then bad "no GitHub write"; else ok "no GitHub write"; fi

fixture "[$(pr "https://github.com/fork/widgets/pull/9" true me)]"
run x-foreign stop exit
eq "a foreign-only branch: exit_record error" "error" "$(key x-foreign exit_record)"
eq "a foreign-only branch: no foreign URL" "" "$(key x-foreign pr)"

fixture "[$(pr "$URL" false me),$(pr "https://github.com/acme/widgets/pull/6" false me)]"
run x-several continue exit
eq "several owned PRs: exit_record error" "error" "$(key x-several exit_record)"

fixture "[]"; echo 1 >"$GHF/pr-list.rc"
run x-fail continue exit
eq "a failed read: exit_record error" "error" "$(key x-fail exit_record)"
eq "a failed read still exits 0" "0" "$RC"

echo "== stale keys are cleared =="
rm -f "$R/docs/plans/PLAN-topic.md"
mkdir -p "$STORE/x-stale"
printf '/execute docs/plans/PLAN-old.md' >"$STORE/x-stale/next"
printf 'coordinated' >"$STORE/x-stale/plan_execution_mode"
printf '%s' "$URL" >"$STORE/x-stale/pr"
fixture "[]"
run x-stale none exit
eq "a stale next is cleared" "" "$(key x-stale next)"
eq "a stale mode is cleared" "" "$(key x-stale plan_execution_mode)"
eq "a stale pr is cleared" "" "$(key x-stale pr)"

echo "== usage =="
(cd "$R" && PATH="$SHIM:$PATH" GHF="$GHF" bash "$S" --session u --topic topic --intent maybe --stage exit >/dev/null 2>&1); RC=$?
eq "an intent outside the set is a usage error" "64" "$RC"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
