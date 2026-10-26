#!/usr/bin/env bash
# deliver-probe_test.sh -- /deliver's three durable re-checks against a gh
# stand-in, a koto context stand-in, and real git with a local bare origin.
#
# Each case asserts what the probe wrote to context (the verdict, checked_pr,
# pr, pr_state), what it cleared, and that it wrote nothing to GitHub. Covered:
#
#   scoped    pass; /scope's result (scope_intent and pr, as scope_run copies
#             them from the leg) recording intent stop, no intent, a forged
#             one, no PR, or a PR other than the owned one; a body with no
#             intent= line, or one recording intent=stop, beside a result of
#             continue still passes; the PLAN untracked, modified, or missing
#             from HEAD; HEAD not pushed; owned-pr.sh's zero survivors,
#             several (exit 3), and a failed read (exit 2)
#   executed  merged and open; the PLAN still present; no current DESIGN;
#             zero, several, and a failed read; stale pr_state cleared
#   merged    merged; not merged (the PR still OPEN) with its URL written;
#             the single-pr case where the merged PR's head is the /scope
#             topic branch and no impl/<slug> branch or PR exists; a closed
#             PR beside the merged one; zero, several, and a failed read, each
#             writing not-merged and no PR
#
# plus, in every mode, stale keys from an earlier tick cleared; in executed
# and merged a stale leg-copied `pr` naming another PR replaced by the owned
# PR's URL (or left empty when the lookup fails), and in scoped such a `pr`
# failing the check; and the usage errors.
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

T=$(mktemp -d "${TMPDIR:-/tmp}/deliver-probe-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */deliver-probe-test.*) rm -rf "$T" ;; esac' EXIT
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
# scoped_store -- reset_store plus /scope's result as scope_run copies it from
# the scope leg: intent continue, and the owned PR's URL as pr.
scoped_store() { reset_store; seed scope_intent continue; seed pr "$URL"; }
# reset_store -- an empty session store holding only the run identity
# deliver-open.sh mints at the session's birth; the probe only reads it.
reset_store() {
    rm -rf "${KOTO_STORE:?}/$SESS" "$KOTO_STORE"/pr.* "$SHIRABE_RUN_RECORD_TEST_ROOT"
    mkdir -p "$KOTO_STORE/$SESS"
    printf '%s' 00112233445566778899aabbccddeeff >"$KOTO_STORE/$SESS/run_id"
}
# The PRs' index sessions sit at a shared address of this suite's own.
export SHIRABE_RUN_RECORD_TEST_ROOT="$T/shared-record"
# index_entry <n> <run_id> -- an entry naming <run_id> in acme/widgets#<n>'s
# index session, as scripts/run-trail.sh index lays one out.
index_entry() {
    mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/acme" "$KOTO_STORE/pr.acme.widgets.$1/run"
    printf '{"workspace":"/w","session":"execute-t1","session_id":"sid-1","mode":"single-pr","topic":"t1","written_at":"2026-01-01T00:00:00Z"}' \
        >"$KOTO_STORE/pr.acme.widgets.$1/run/$2"
}

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

scoped_store; seed scoped_verdict fail; seed checked_pr "$OTHER"
db "[$(pr "$URL" OPEN)]"
run scoped
eq "pass: exit 0" 0 "$RC"
eq "pass: verdict" pass "$(key scoped_verdict)"
eq "pass: checked_pr is the owned PR" "$URL" "$(key checked_pr)"
eq "pass: pr is the owned PR, the one /scope's result names" "$URL" "$(key pr)"
eq "pass: /scope's intent is left as scope_run copied it" continue "$(key scope_intent)"
no_writes "pass"
if grep -q -- "--state open" "$GH_DB.calls"; then ok "pass: the lookup is owned-pr.sh --state open"; else bad "pass: --state open" "$(cat "$GH_DB.calls")"; fi

scoped_store; seed scoped_verdict pass; seed checked_pr "$OTHER"
db "[]"
run scoped
failed "zero survivors (no PR)" fail
no_writes "zero survivors"

scoped_store
db "[$(pr "https://github.com/fork/widgets/pull/7" OPEN me true),$(pr "https://github.com/acme/widgets/pull/8" OPEN someone-else)]"
run scoped
failed "zero survivors (only a fork's and another author's PRs)" fail

scoped_store
db "[$(pr "$URL" OPEN),$(pr "https://github.com/acme/widgets/pull/43" OPEN)]"
run scoped
failed "several owned PRs (exit 3)" fail

# The run marker: the lookups carry this session's run_id.
MINE=0123456789abcdef0123456789abcdef
FOREIGN=fedcba9876543210fedcba9876543210

scoped_store
db "[$(pr "$URL" OPEN)]"
run scoped
eq "an unmarked /scope PR, looked up with a run identity, still passes on the fallback" pass "$(key scoped_verdict)"

scoped_store; rm -f "$KOTO_STORE/$SESS/run_id"
db "[$(pr "$URL" OPEN)]"
run scoped
eq "a session with no run_id: exit 66" 66 "$RC"
if has run_id; then bad "the probe mints no run_id" "[$(key run_id)]"; else ok "the probe mints no run_id"; fi

scoped_store; seed run_id "$MINE"
db "[$(pr "$URL" OPEN me false "$BRANCH" "intent=continue")]"
index_entry "${URL##*/}" "$FOREIGN"
run scoped
failed "the topic branch's PR was recorded by another run (exit 5)" fail
no_writes "another run's PR"

scoped_store; seed run_id "$MINE"
db "[$(pr "$URL" OPEN me false "$BRANCH" "intent=continue"),$(pr "https://github.com/acme/widgets/pull/43" OPEN)]"
index_entry "${URL##*/}" "$MINE"
run scoped
failed "a PR this run recorded beside one with no entry are ambiguous (exit 4)" fail

scoped_store
db "[$(pr "$URL" OPEN)]" '{"pr list": 1}'
run scoped
failed "a failed read (exit 2)" fail

# /scope's intent is read from its result (the leg, copied by scope_run),
# never from the PR's body.
scoped_store; seed scope_intent stop
db "[$(pr "$URL" OPEN)]"
run scoped
failed "/scope's result records intent stop" fail

scoped_store; rm -f "$KOTO_STORE/$SESS/scope_intent"
db "[$(pr "$URL" OPEN)]"
run scoped
failed "/scope's result records no intent" fail

scoped_store; seed scope_intent 'continue; rm -rf /'
db "[$(pr "$URL" OPEN)]"
run scoped
failed "a forged intent outside continue|stop" fail

scoped_store
db "[$(pr "$URL" OPEN me false "$BRANCH" "no intent line here")]"
run scoped
eq "a body with no intent= line, /scope's result continue: pass" pass "$(key scoped_verdict)"
eq "... with the owned PR" "$URL" "$(key checked_pr)"

scoped_store
db "[$(pr "$URL" OPEN me false "$BRANCH" "intent=stop")]"
run scoped
eq "a body recording intent=stop, /scope's result continue: pass" pass "$(key scoped_verdict)"

scoped_store; seed pr "$OTHER"
db "[$(pr "$URL" OPEN)]"
run scoped
failed "/scope's result names a PR that is not the owned PR" fail

scoped_store; rm -f "$KOTO_STORE/$SESS/pr"
db "[$(pr "$URL" OPEN)]"
run scoped
failed "/scope's result names no PR" fail


scoped_store
db "[$(pr "$URL" OPEN)]"
printf 'more\n' >>"$R/docs/plans/PLAN-$TOPIC.md"
run scoped
failed "the PLAN modified against HEAD" fail
G checkout -q -- "docs/plans/PLAN-$TOPIC.md"

scoped_store
G rm -q --cached "docs/plans/PLAN-$TOPIC.md"
run scoped
failed "the PLAN not tracked" fail
G reset -q -- "docs/plans/PLAN-$TOPIC.md"

scoped_store
G commit -q --allow-empty -m "local only"
run scoped
failed "HEAD not pushed" fail
G reset -q --hard HEAD~1

scoped_store
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
