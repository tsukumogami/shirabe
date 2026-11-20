#!/usr/bin/env bash
# start-commit_test.sh — orchestrator_setup's start commit: a shared branch
# whose PLAN is already on the default branch still has a commit to open its
# draft PR on
# Part of the execute skill
#
# When an earlier pull request already merged the PLAN, impl/<slug> is cut at
# the default branch's head and has nothing of its own. GitHub refuses a pull
# request whose head has no commit its base lacks ("No commits between main and
# impl/<slug>"), so orchestrator_setup's draft PR could never be opened.
# start-commit.sh gives such a branch one empty commit before the push. The
# cases run real git against a local bare origin and a `koto` stub on PATH, so
# they need no network and no workflow engine:
#
#   step 2 as shipped     execute.md's start-commit and push lines, run in
#                         order on a branch cut at main with the PLAN merged:
#                         the pushed branch is one commit ahead of main, and
#                         expected_head is that commit
#   the commit            empty (main's tree), main's head its parent, a
#                         Conventional Commits subject, no trailer
#   a second run          makes no commit
#   a branch ahead        makes no commit
#   a branch behind main  the fetched default branch counts, not a stale local
#                         one: the branch still gets its commit
#   already pushed        the stuck state (impl/<slug> on origin at main's
#                         head, no PR): the start commit, then the push
#                         fast-forwards it
#   a staged file         stays staged and is not in the commit
#   refusals              a detached HEAD (65), a branch other than
#                         impl/<slug> (66), the default branch (67), a default
#                         branch that can't be read (68), a bad slug or
#                         remote (64); none of them moves HEAD
#   static                no push, no `git commit`, no force option
#
# Usage: start-commit_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)
SC="$SCRIPT_DIR/start-commit.sh"
PAR="$SCRIPT_DIR/push-and-record.sh"
EXECUTE_MD="$PLUGIN_ROOT/skills/execute/koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$PAR" ] || { echo "FAIL: $PAR not found" >&2; exit 1; }
[ -f "$EXECUTE_MD" ] || { echo "FAIL: $EXECUTE_MD not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/start-commit-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$WORK"'
BIN="$WORK/bin"
mkdir -p "$BIN"

# koto stub: logs "<args>|<stdin>" per call.
cat > "$BIN/koto" <<'STUB'
#!/usr/bin/env bash
data=""
[ -t 0 ] || data=$(cat)
printf '%s|%s\n' "$*" "$data" >> "${KOTO_LOG:?}"
exit 0
STUB
chmod +x "$BIN/koto"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

SESSION=execute-topic
SUBJECT="chore: start the topic implementation"

# fixture <name> — a bare origin whose main already carries the PLAN (the
# scoping PR merged it), and a clone of it on impl/topic cut at main's head.
fixture() {
    FX="$WORK/$1"
    ORIGIN="$FX/origin.git"
    CLONE="$FX/clone"
    KOTO_LOG="$FX/koto.log"
    mkdir -p "$FX"
    : > "$KOTO_LOG"
    git init -q --bare -b main "$ORIGIN"
    git init -q -b main "$FX/seed"
    (cd "$FX/seed" && echo base > README.md && git add README.md \
        && git commit -q -m "chore: init" \
        && mkdir -p docs/plans && echo plan > docs/plans/PLAN-topic.md \
        && git add docs/plans && git commit -q -m "docs: add the topic PLAN" \
        && git push -q "$ORIGIN" main) >/dev/null 2>&1
    git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
    git -C "$CLONE" checkout -q -b impl/topic
}

run_sc() {
    OUT=$(cd "$CLONE" && env PATH="$BIN:$PATH" bash "$SC" "$@" 2>"$FX/stderr")
    RC=$?
}
head_of() { git -C "$CLONE" rev-parse HEAD; }
main_of() { git -C "$ORIGIN" rev-parse refs/heads/main; }

# --- step 2 as execute.md ships it ---------------------------------------------

# The lines of orchestrator_setup's step 2 that run before the draft PR is
# created: the start commit and the push, in the directive's order, with the
# template's variables filled in as koto fills them.
step2_lines() {
    awk '/^\*\*2\. The shared branch\.\*\*/ {f = 1; next}
         /^\*\*Another run.s PR/ {f = 0}
         f' "$EXECUTE_MD" \
        | grep -E '^\{\{PLUGIN_ROOT\}\}/skills/execute/scripts/(start-commit|push-and-record)\.sh( |$)'
}

fixture reported
LINES=$(step2_lines)
STEP_RC=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in *'\') fail "step 2 line continues onto the next: [$line]"; STEP_RC=1; continue ;; esac
    line=${line//'{{PLUGIN_ROOT}}'/$PLUGIN_ROOT}
    line=${line//'{{SESSION_NAME}}'/$SESSION}
    line=${line//'{{PLAN_SLUG}}'/topic}
    read -r -a argv <<<"$line"
    (cd "$CLONE" && env PATH="$BIN:$PATH" KOTO_LOG="$KOTO_LOG" bash "${argv[@]}") >/dev/null 2>>"$FX/stderr" \
        || STEP_RC=$?
done <<EOF
$LINES
EOF
PUSHED=$(git -C "$ORIGIN" rev-parse --verify -q refs/heads/impl/topic)
if [ -z "$PUSHED" ]; then
    fail "step 2 pushed no impl/topic (exit $STEP_RC): $(tail -3 "$FX/stderr")"
else
    AHEAD=$(git -C "$ORIGIN" rev-list --count refs/heads/main..refs/heads/impl/topic)
    if [ "$AHEAD" -eq 0 ]; then
        # What GitHub answers the draft PR's create with on this branch.
        fail "step 2: No commits between main and impl/topic: the pushed branch is main's head, so the draft PR can't be opened"
    elif [ "$AHEAD" -eq 1 ] && [ "$(cat "$KOTO_LOG")" = "context add $SESSION expected_head|$PUSHED" ]; then
        pass "step 2 as shipped: impl/topic is pushed one commit ahead of main, and expected_head is that commit"
    else
        fail "step 2: $AHEAD commits ahead, koto log [$(cat "$KOTO_LOG")], pushed $PUSHED"
    fi
fi

# --- the commit -----------------------------------------------------------------

fixture commit
MAIN=$(main_of)
run_sc --plan-slug topic
NEW=$(head_of)
if [ "$RC" -eq 0 ] && [ "$NEW" != "$MAIN" ] && [ "$OUT" = "created $NEW" ] \
    && [ "$(git -C "$CLONE" rev-parse "$NEW^")" = "$MAIN" ] \
    && [ "$(git -C "$CLONE" rev-parse "$NEW^{tree}")" = "$(git -C "$CLONE" rev-parse "$MAIN^{tree}")" ] \
    && [ "$(git -C "$CLONE" log -1 --format=%s "$NEW")" = "$SUBJECT" ] \
    && [ "$(git -C "$CLONE" symbolic-ref --short HEAD)" = impl/topic ]; then
    pass "one empty commit on main's head, subject [$SUBJECT], still on impl/topic"
else
    fail "commit: exit $RC, out [$OUT], head $NEW, main $MAIN, subject [$(git -C "$CLONE" log -1 --format=%s 2>/dev/null)]"
fi
if [ "$(git -C "$CLONE" log -1 --format=%b "$NEW" | grep -ciE 'co-authored-by|generated with')" -eq 0 ] \
    && [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
    pass "the commit has no attribution trailer, and the work tree is clean"
else
    fail "commit body [$(git -C "$CLONE" log -1 --format=%b "$NEW")], status [$(git -C "$CLONE" status --porcelain)]"
fi

# --- a second run ---------------------------------------------------------------

run_sc --plan-slug topic
if [ "$RC" -eq 0 ] && [ "$(head_of)" = "$NEW" ] && [ "$OUT" = "unchanged $NEW" ]; then
    pass "a second run makes no commit"
else
    fail "second run: exit $RC, out [$OUT], head $(head_of), want $NEW"
fi

# --- a branch already ahead -------------------------------------------------------

fixture ahead
(cd "$CLONE" && echo work > work.txt && git add work.txt && git commit -q -m "feat: work")
BEFORE=$(head_of)
run_sc --plan-slug topic
if [ "$RC" -eq 0 ] && [ "$(head_of)" = "$BEFORE" ] && [ "$OUT" = "unchanged $BEFORE" ]; then
    pass "a branch with a commit of its own gets no start commit"
else
    fail "ahead: exit $RC, out [$OUT], head $(head_of), want $BEFORE"
fi

# --- a branch behind the default branch ----------------------------------------------

# The clone was cut before the PLAN merged: its main and impl/topic stop at the
# init commit. The fetched default branch is what counts.
FX="$WORK/behind"; ORIGIN="$FX/origin.git"; CLONE="$FX/clone"; KOTO_LOG="$FX/koto.log"
mkdir -p "$FX"; : > "$KOTO_LOG"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$FX/seed"
(cd "$FX/seed" && echo base > README.md && git add README.md && git commit -q -m "chore: init" \
    && git push -q "$ORIGIN" main) >/dev/null 2>&1
git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
git -C "$CLONE" checkout -q -b impl/topic
(cd "$FX/seed" && mkdir -p docs/plans && echo plan > docs/plans/PLAN-topic.md && git add docs/plans \
    && git commit -q -m "docs: add the topic PLAN" && git push -q "$ORIGIN" main) >/dev/null 2>&1
BEFORE=$(head_of)
run_sc --plan-slug topic
if [ "$RC" -eq 0 ] && [ "$(head_of)" != "$BEFORE" ] && [ "$(git -C "$CLONE" rev-parse HEAD^)" = "$BEFORE" ]; then
    pass "a branch behind the fetched default branch still gets its start commit"
else
    fail "behind: exit $RC, out [$OUT], head $(head_of), before $BEFORE: $(cat "$FX/stderr")"
fi

# --- already pushed: the stuck state --------------------------------------------------

fixture stuck
git -C "$CLONE" push -q origin impl/topic 2>/dev/null
run_sc --plan-slug topic
SHA=$(head_of)
PUSH_OUT=$(cd "$CLONE" && env PATH="$BIN:$PATH" KOTO_LOG="$KOTO_LOG" bash "$PAR" "$SESSION" 2>>"$FX/stderr")
PUSH_RC=$?
if [ "$RC" -eq 0 ] && [ "$PUSH_RC" -eq 0 ] && [ "$PUSH_OUT" = "$SHA" ] \
    && [ "$(git -C "$ORIGIN" rev-parse refs/heads/impl/topic)" = "$SHA" ] \
    && [ "$(git -C "$ORIGIN" rev-list --count refs/heads/main..refs/heads/impl/topic)" -eq 1 ]; then
    pass "impl/topic already pushed at main's head: the start commit, then a fast-forward push"
else
    fail "stuck: start exit $RC, push exit $PUSH_RC, pushed [$PUSH_OUT], head $SHA: $(tail -3 "$FX/stderr")"
fi

# --- a staged file ------------------------------------------------------------------

fixture staged
(cd "$CLONE" && echo staged > staged.txt && git add staged.txt)
MAIN=$(main_of)
run_sc --plan-slug topic
NEW=$(head_of)
if [ "$RC" -eq 0 ] && [ "$NEW" != "$MAIN" ] \
    && [ "$(git -C "$CLONE" rev-parse "$NEW^{tree}")" = "$(git -C "$CLONE" rev-parse "$MAIN^{tree}")" ] \
    && [ "$(git -C "$CLONE" diff --cached --name-only)" = staged.txt ]; then
    pass "a staged file is not in the start commit and stays staged"
else
    fail "staged: exit $RC, head $NEW, cached [$(git -C "$CLONE" diff --cached --name-only)]"
fi

# --- refusals -------------------------------------------------------------------------

fixture refusals
git -C "$CLONE" checkout -q --detach
BEFORE=$(head_of)
run_sc --plan-slug topic
if [ "$RC" -eq 65 ] && [ "$(head_of)" = "$BEFORE" ]; then
    pass "a detached HEAD is refused (65)"
else
    fail "detached: exit $RC, head $(head_of)"
fi

git -C "$CLONE" checkout -q -b feature/x
run_sc --plan-slug topic
if [ "$RC" -eq 66 ] && [ "$(head_of)" = "$BEFORE" ]; then
    pass "a branch other than impl/<slug> is refused (66)"
else
    fail "other branch: exit $RC"
fi

git -C "$CLONE" checkout -q impl/topic
run_sc --plan-slug other
if [ "$RC" -eq 66 ] && [ "$(head_of)" = "$BEFORE" ]; then
    pass "another PLAN's impl/<slug> is refused (66)"
else
    fail "another slug: exit $RC"
fi

for bad in "Bad_Slug" "" "../x"; do
    run_sc --plan-slug "$bad"
    if [ "$RC" -eq 64 ]; then pass "slug [$bad] is a usage error (64)"; else fail "slug [$bad]: exit $RC"; fi
done
run_sc --plan-slug topic --remote -x
if [ "$RC" -eq 64 ]; then pass "a remote starting with - is a usage error (64)"; else fail "remote -x: exit $RC"; fi
run_sc --plan-slug topic --plan-slug topic
if [ "$RC" -eq 64 ]; then pass "a repeated flag is a usage error (64)"; else fail "repeated flag: exit $RC"; fi

# The remote's default branch named impl/topic: refused, never committed on.
git -C "$ORIGIN" branch -q impl/topic main
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/impl/topic
run_sc --plan-slug topic
if [ "$RC" -eq 67 ] && [ "$(head_of)" = "$BEFORE" ]; then
    pass "the remote's default branch is refused (67)"
else
    fail "default branch: exit $RC"
fi
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# A remote that can't be read, and no local symref: nothing to count against.
git -C "$CLONE" remote add nowhere "$FX/missing.git"
run_sc --plan-slug topic --remote nowhere
if [ "$RC" -eq 68 ] && [ "$(head_of)" = "$BEFORE" ]; then
    pass "a default branch that can't be read stops before any commit (68)"
else
    fail "unreadable default: exit $RC, head $(head_of)"
fi

# --- static ---------------------------------------------------------------------------

if [ -f "$SC" ]; then
    CODE=$(grep -vE '^[[:space:]]*#' "$SC")
    if printf '%s\n' "$CODE" | grep -qE 'git[^|;&]*[[:space:]](push|commit)([[:space:]]|$)|--force'; then
        fail "start-commit.sh pushes, runs git commit, or passes a force option"
    else
        pass "start-commit.sh never pushes, never runs git commit, and passes no force option"
    fi
else
    fail "$SC not found"
fi

echo ""
echo "start-commit_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
