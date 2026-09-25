#!/usr/bin/env bash
# deliver-probe_test.sh -- /deliver's three durable re-checks against a gh
# stand-in, a koto context stand-in, and real git with a local bare origin.
#
# Each case asserts what the probe wrote to context (the verdict, checked_pr,
# pr, pr_state), what it cleared, and that it wrote nothing to GitHub. Covered:
#
#   scoped    pass; the PLAN untracked, modified, or missing from HEAD; HEAD
#             not pushed; the PR body recording intent=stop; owned-pr.sh's
#             zero survivors, several (exit 3), and a failed read (exit 2)
#   executed  merged and open; the PLAN still present; no current DESIGN;
#             zero, several, and a failed read; stale pr_state cleared
#   merged    merged; not merged (the PR still OPEN) with its URL written;
#             the single-pr case where the merged PR's head is the /scope
#             topic branch and no impl/<slug> branch or PR exists; a closed
#             PR beside the merged one; zero, several, and a failed read, each
#             writing not-merged and no PR
#
# plus, in every mode, stale keys from an earlier tick cleared, and a stale
# leg-copied `pr` naming another PR replaced by the owned PR's URL (or left
# empty when the lookup fails), and the usage errors.
#
# Usage: bash skills/deliver/scripts/deliver-probe_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs bash, git and jq.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/deliver-probe.sh"
STUBS="$HERE/testdata"

for bin in git jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-probe-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
export MERGE_CONFIRM_WAIT_SECS=0

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

BIN="$T/bin"
mkdir -p "$BIN"
cp "$STUBS/gh" "$STUBS/koto" "$BIN/"
chmod +x "$BIN/gh" "$BIN/koto"
export KOTO_STORE="$T/store"
mkdir -p "$KOTO_STORE"

TOPIC=t1
BRANCH=docs/t1
URL=https://github.com/acme/widgets/pull/42
OTHER=https://github.com/acme/widgets/pull/99

# --- the repository -------------------------------------------------------------

G() { git -C "$R" -c user.email=t@example.invalid -c user.name=t "$@"; }
R="$T/repo"
O="$T/origin.git"
git init -q --bare -b main "$O"
git init -q -b main "$R"
printf '# t\n' >"$R/CLAUDE.md"
G add CLAUDE.md
G commit -q -m init
G remote add origin "$O"
G push -q origin main
G checkout -q -b "$BRANCH"
mkdir -p "$R/docs/plans" "$R/docs/designs/current"
printf -- '---\nstatus: Active\nexecution_mode: single-pr\n---\n# PLAN\n' >"$R/docs/plans/PLAN-$TOPIC.md"
G add docs
G commit -q -m "docs: plan"
G push -q origin "HEAD:refs/heads/$BRANCH"

# db <prs-json> [fail-json] -- a fresh gh database for one case.
N=0
db() {
    N=$((N + 1))
    export GH_DB="$T/db$N.json"
    local fail="${2:-}"
    [ -n "$fail" ] || fail="{}"
    jq -n --argjson prs "$1" --argjson fail "$fail" \
        '{login: "me", repo: "acme/widgets", default_branch: "main", prs: $prs, fail: $fail}' >"$GH_DB"
    : >"$GH_DB.calls"
}
pr() { # pr <url> <state> [author] [cross] [head] [body]
    jq -nc --arg u "$1" --arg s "$2" --arg a "${3:-me}" --argjson x "${4:-false}" \
        --arg h "${5:-$BRANCH}" --arg b "${6:-intent=continue}" \
        '{url: $u, number: ($u | split("/") | last | tonumber), state: $s, author: $a,
          isCrossRepository: $x, baseRefName: "main", headRefName: $h, body: ("# PR\n\n" + $b + "\n")}'
}

SESS=deliver-t1
key() { cat "$KOTO_STORE/$SESS/$1" 2>/dev/null; }
has() { [ -f "$KOTO_STORE/$SESS/$1" ]; }
seed() { mkdir -p "$KOTO_STORE/$SESS"; printf '%s' "$2" >"$KOTO_STORE/$SESS/$1"; }
reset_store() { rm -rf "${KOTO_STORE:?}/$SESS"; }

RC=0; OUT=""
run() { # run <mode> -- the probe from inside the repository
    OUT=$(cd "$R" && PATH="$BIN:$PATH" bash "$S" "$1" --topic "$TOPIC" --session "$SESS" 2>"$T/err")
    RC=$?
}
no_writes() {
    if grep -Eq '^pr (create|edit|merge|ready|close|review|comment)|^api .*(-X|--method)' "$GH_DB.calls"; then
        bad "$1: no GitHub write" "$(cat "$GH_DB.calls")"
    else
        ok "$1: no GitHub write"
    fi
}
# failed <label> <verdict> -- a failing verdict with no PR keys.
failed() {
    eq "$1: exit 0" 0 "$RC"
    eq "$1: verdict $2" "$2" "$(key "${MODE}_verdict")"
    if has checked_pr || has pr; then bad "$1: no checked_pr or pr written" "checked_pr=[$(key checked_pr)] pr=[$(key pr)]"; else ok "$1: no checked_pr or pr written"; fi
}

echo "== scoped =="
MODE=scoped

reset_store; seed pr "$OTHER"; seed scoped_verdict pass; seed checked_pr "$OTHER"
db "[$(pr "$URL" OPEN)]"
run scoped
eq "pass: exit 0" 0 "$RC"
eq "pass: verdict" pass "$(key scoped_verdict)"
eq "pass: checked_pr is the owned PR" "$URL" "$(key checked_pr)"
eq "pass: the leg-copied pr naming another PR is replaced by the owned PR" "$URL" "$(key pr)"
no_writes "pass"
if grep -q -- "--state open" "$GH_DB.calls"; then ok "pass: the lookup is owned-pr.sh --state open"; else bad "pass: --state open" "$(cat "$GH_DB.calls")"; fi

reset_store; seed pr "$OTHER"; seed scoped_verdict pass; seed checked_pr "$OTHER"
db "[]"
run scoped
failed "zero survivors (no PR)" fail
no_writes "zero survivors"

reset_store; seed pr "$OTHER"
db "[$(pr "https://github.com/fork/widgets/pull/7" OPEN me true),$(pr "https://github.com/acme/widgets/pull/8" OPEN someone-else)]"
run scoped
failed "zero survivors (only a fork's and another author's PRs)" fail

reset_store
db "[$(pr "$URL" OPEN),$(pr "https://github.com/acme/widgets/pull/43" OPEN)]"
run scoped
failed "several owned PRs (exit 3)" fail

reset_store; seed pr "$OTHER"
db "[$(pr "$URL" OPEN)]" '{"pr list": 1}'
run scoped
failed "a failed read (exit 2)" fail

reset_store
db "[$(pr "$URL" OPEN me false "$BRANCH" "intent=stop")]"
run scoped
failed "the PR body records intent=stop" fail

reset_store
db "[$(pr "$URL" OPEN)]"
printf 'more\n' >>"$R/docs/plans/PLAN-$TOPIC.md"
run scoped
failed "the PLAN modified against HEAD" fail
G checkout -q -- "docs/plans/PLAN-$TOPIC.md"

reset_store
G rm -q --cached "docs/plans/PLAN-$TOPIC.md"
run scoped
failed "the PLAN not tracked" fail
G reset -q -- "docs/plans/PLAN-$TOPIC.md"

reset_store
G commit -q --allow-empty -m "local only"
run scoped
failed "HEAD not pushed" fail
G reset -q --hard HEAD~1

reset_store
db "[$(pr "$URL" OPEN)]"
run scoped
eq "control: pass again after the fixtures are restored" pass "$(key scoped_verdict)"

echo "== executed =="
MODE=executed
G rm -q "docs/plans/PLAN-$TOPIC.md"
printf '# DESIGN\n' >"$R/docs/designs/current/DESIGN-$TOPIC.md"
G add docs
G commit -q -m "chore: cascade"

for st in MERGED:merged OPEN:open; do
    ghs="${st%%:*}"; want="${st#*:}"
    reset_store; seed pr "$OTHER"; seed pr_state open; seed executed_verdict merged
    db "[$(pr "$URL" "$ghs")]"
    run executed
    eq "$want: exit 0" 0 "$RC"
    eq "$want: verdict" "$want" "$(key executed_verdict)"
    eq "$want: checked_pr" "$URL" "$(key checked_pr)"
    eq "$want: pr replaces the leg's" "$URL" "$(key pr)"
    eq "$want: pr_state" "$want" "$(key pr_state)"
    no_writes "$want"
done
if grep -q -- "--state all" "$GH_DB.calls"; then ok "executed: the lookup is owned-pr.sh --state all"; else bad "executed: --state all" "$(cat "$GH_DB.calls")"; fi

reset_store; seed pr "$OTHER"; seed pr_state merged
db "[]"
run executed
failed "executed: zero survivors" fail
if has pr_state; then bad "executed: a stale pr_state is cleared"; else ok "executed: a stale pr_state is cleared"; fi

reset_store
db "[$(pr "$URL" MERGED),$(pr "https://github.com/acme/widgets/pull/43" OPEN)]"
run executed
failed "executed: several (exit 3)" fail

reset_store
db "[$(pr "$URL" MERGED)]" '{"api user": 1}'
run executed
failed "executed: a failed read (exit 2)" fail

reset_store
db "[$(pr "$URL" MERGED)]"
mkdir -p "$R/docs/plans"; printf -- '---\nexecution_mode: single-pr\n---\n' >"$R/docs/plans/PLAN-$TOPIC.md"
run executed
failed "executed: the PLAN still on disk" fail
rm -f "$R/docs/plans/PLAN-$TOPIC.md"

reset_store
mv "$R/docs/designs/current/DESIGN-$TOPIC.md" "$T/design.bak"
run executed
failed "executed: no DESIGN under docs/designs/current/" fail
mv "$T/design.bak" "$R/docs/designs/current/DESIGN-$TOPIC.md"

echo "== merged =="
MODE=merged

reset_store; seed pr "$OTHER"; seed merged_verdict merged; seed checked_pr "$OTHER"
# The single-pr case on a /deliver run: the merged PR's head is the topic
# branch /scope published, and no impl/<slug> branch or PR exists.
db "[$(pr "$URL" MERGED)]"
run merged
eq "merged (topic branch): exit 0" 0 "$RC"
eq "merged (topic branch): verdict" merged "$(key merged_verdict)"
eq "merged (topic branch): checked_pr is the topic branch's PR" "$URL" "$(key checked_pr)"
eq "merged (topic branch): pr is the owned PR, not the leg's" "$URL" "$(key pr)"
if git -C "$R" show-ref --verify --quiet "refs/heads/impl/$TOPIC" || grep -q "impl/$TOPIC" "$GH_DB.calls"; then
    bad "merged (topic branch): no impl/<slug> branch or lookup"
else
    ok "merged (topic branch): no impl/<slug> branch or lookup"
fi
if grep -q -- "--head $BRANCH --state all" "$GH_DB.calls"; then ok "merged: the lookup is --state all on the topic branch"; else bad "merged: lookup" "$(cat "$GH_DB.calls")"; fi
if grep -q -- "pr view 42 --repo acme/widgets --json state" "$GH_DB.calls"; then ok "merged: the confirm read reads the owned PR"; else bad "merged: confirm read" "$(cat "$GH_DB.calls")"; fi
no_writes "merged"

reset_store; seed pr "$OTHER"
db "[$(pr "$URL" OPEN),$(pr "$OTHER" MERGED me false other/branch)]"
run merged
eq "not merged: verdict" not-merged "$(key merged_verdict)"
eq "not merged: checked_pr is still the owned PR" "$URL" "$(key checked_pr)"
eq "not merged: a leg pr naming some other merged PR is replaced" "$URL" "$(key pr)"

reset_store
db "[$(pr "https://github.com/acme/widgets/pull/41" CLOSED),$(pr "$URL" MERGED)]"
run merged
eq "a closed PR beside the merged one: merged" merged "$(key merged_verdict)"
eq "a closed PR beside the merged one: the merged PR" "$URL" "$(key checked_pr)"

reset_store; seed pr "$OTHER"; seed checked_pr "$OTHER"; seed merged_verdict merged
db "[]"
run merged
failed "merged: zero survivors" not-merged

reset_store; seed pr "$OTHER"
db "[$(pr "$URL" MERGED),$(pr "https://github.com/acme/widgets/pull/43" MERGED)]"
run merged
failed "merged: several (exit 3)" not-merged

reset_store; seed pr "$OTHER"
db "[$(pr "$URL" MERGED)]" '{"pr list": 1}'
run merged
failed "merged: a failed lookup leaves pr empty" not-merged

reset_store
db "[$(pr "$URL" MERGED)]" '{"pr view": 1}'
run merged
eq "merged: a failed confirm read is not-merged" not-merged "$(key merged_verdict)"
eq "merged: ... with the PR it found" "$URL" "$(key pr)"

echo "== failures and usage =="
reset_store
db "[$(pr "$URL" MERGED)]"
OUT=$(cd "$R" && PATH="$BIN:$PATH" KOTO_FAIL_ADD=1 bash "$S" merged --topic "$TOPIC" --session "$SESS" 2>/dev/null)
eq "a failed koto context add exits 66" 66 "$?"

for args in "bogus --topic t1 --session s" "merged --session s" "merged --topic -x --session s" \
    "merged --topic t1 --topic t1 --session s" "merged --topic t1 --session bad/name" "merged --topic t1 --extra"; do
    : >"$KOTO_STORE/calls"
    # shellcheck disable=SC2086
    (cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION= bash "$S" $args >/dev/null 2>&1)
    rc=$?
    if [ "$rc" -eq 64 ] && [ ! -s "$KOTO_STORE/calls" ]; then ok "usage error, no koto call: $args"; else bad "usage: $args" "rc=$rc calls=$(cat "$KOTO_STORE/calls")"; fi
done

reset_store
db "[$(pr "$URL" MERGED)]"
(cd "$R" && PATH="$BIN:$PATH" KOTO_TICK_SESSION=deliver-t1 bash "$S" merged --topic "$TOPIC" >/dev/null 2>&1)
eq "the session comes from KOTO_TICK_SESSION when koto set it" merged "$(key merged_verdict)"

G checkout -q --detach
reset_store; seed pr "$OTHER"
run merged
failed "a detached HEAD" not-merged
G checkout -q "$BRANCH"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
