#!/usr/bin/env bash
# has-commits_test.sh -- the has_commits gate, counted from impl_base
# Part of the work-on skill
#
# `has_commits` guards the docs route out of issue_type_routing and the passed
# route out of scrutiny. It counts the commits in impl_base..HEAD, where
# impl_base is what `analysis` recorded, so it must answer the same way in
# every checkout shape a run happens in:
#
#   plain clone        -- origin plus a local `main`
#   no local main      -- a clone whose only `main` is origin/main (an isolated
#                         eval clone, a fresh clone of a feature branch)
#   linked worktree    -- `git worktree add` off a clone
#
# Two halves:
#
#   script cases -- has-commits.sh against real fixture repositories of each
#     shape, reading impl_base through a koto stand-in on PATH. No engine, so
#     they also run on the macOS bash 3.2 floor leg, where koto is absent.
#
#   engine cases -- the shipped work-on.md driven through real koto sessions in
#     each shape: the docs route and scrutiny's passed route, with and without
#     a commit, and with impl_base removed. Skipped with a note when koto is
#     absent, the way the other engine-backed suites skip.
#
# Every run isolates HOME and builds its own fixtures under a temp directory.
#
# Usage: has-commits_test.sh
#
# Exit codes:
#   0 -- all cases pass (engine cases may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/has-commits.sh"
TEMPLATE="$SCRIPT_DIR/../koto-templates/work-on.md"
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# --- the koto stand-in ---------------------------------------------------------
#
# `koto context add|get|exists|remove <session> <key>` against
# $SHIM_STORE/<session>/<key>; `get` and `exists` exit 1 for an absent key, as
# koto does.

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add)    mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
    get)    [ -f "$f" ] || { echo "koto shim: no key $4" >&2; exit 1; }; cat "$f" ;;
    exists) [ -f "$f" ] ;;
    remove) rm -f "$f" ;;
    *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE

# --- fixtures -----------------------------------------------------------------
#
# shape <name> <plain|nomain|worktree>: a bare origin with a seeded main, and a
# run directory $RUN on branch impl/<name> in the requested shape. For nomain
# the clone's local main is deleted, so only origin/main names it; for worktree
# $RUN is a linked worktree of a plain clone.

FX=""
RUN=""
shape() {
    FX="$WORKDIR/fx-$1"
    mkdir -p "$FX"
    (
        cd "$FX" || exit 1
        git init -q --bare origin.git
        git clone -q origin.git seed
        cd seed || exit 1
        printf 'readme\n' > README.md
        git add -A && git commit -q -m init && git push -q origin main
        cd .. && git clone -q origin.git repo
        cd repo || exit 1
        case "$2" in
            plain)    git checkout -q -b "impl/$1" ;;
            nomain)   git checkout -q -b "impl/$1" && git branch -q -D main ;;
            worktree) git worktree add -q -b "impl/$1" ../wt ;;
        esac
    ) >/dev/null 2>&1
    case "$2" in
        worktree) RUN="$FX/wt" ;;
        *)        RUN="$FX/repo" ;;
    esac
}

commit_file() {
    (cd "$RUN" && printf '%s\n' "${2:-x}" > "$1" && git add -A && git commit -q -m "feat: $1") >/dev/null 2>&1
}

head_sha() { (cd "$RUN" && git rev-parse HEAD); }

# record_base <session>: what analysis does -- impl_base is HEAD, now.
record_base() { head_sha | (PATH="$SHIM_BIN:$PATH" koto context add "$1" impl_base); }

RC=0
check() { (cd "$RUN" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@" 2>"$WORKDIR/stderr"); RC=$?; }

# --- the shapes are what they claim ------------------------------------------

shape s-probe nomain
if ! (cd "$RUN" && git rev-parse --verify -q refs/heads/main >/dev/null) \
    && (cd "$RUN" && git rev-parse --verify -q refs/remotes/origin/main >/dev/null) \
    && ! (cd "$RUN" && git log --oneline main..HEAD >/dev/null 2>&1); then
    pass "no-local-main fixture: only origin/main exists, and the old main..HEAD count fails there"
else
    fail "no-local-main fixture is not what it claims"
fi
shape s-wtprobe worktree
if [ "$(cd "$RUN" && git rev-parse --git-common-dir)" != "$(cd "$RUN" && git rev-parse --git-dir)" ]; then
    pass "worktree fixture: the run directory is a linked worktree"
else
    fail "worktree fixture is not a linked worktree"
fi

# --- each shape, with and without a commit --------------------------------------

for sh in plain nomain worktree; do
    shape "s-$sh" "$sh"
    record_base "s-$sh"
    check "s-$sh"
    [ "$RC" -eq 1 ] && pass "$sh: no commits since impl_base -> exit 1" \
        || fail "$sh: no commits exited $RC ($(cat "$WORKDIR/stderr"))"
    commit_file work.txt
    check "s-$sh"
    [ "$RC" -eq 0 ] && pass "$sh: a commit since impl_base -> exit 0" \
        || fail "$sh: with a commit exited $RC ($(cat "$WORKDIR/stderr"))"
done

# Commits the run didn't make don't count: the branch already carried one when
# the base was recorded.
shape s-prior nomain
commit_file prior.txt
record_base s-prior
check s-prior
[ "$RC" -eq 1 ] && pass "a commit before impl_base is not counted" \
    || fail "a commit before impl_base counted: exit $RC"

# --- no answer fails, never passes ---------------------------------------------

shape s-missing nomain
commit_file work.txt
check s-missing
if [ "$RC" -eq 64 ] && grep -q 'impl_base is not recorded' "$WORKDIR/stderr" \
    && grep -qF 'git rev-parse <commit> | koto context add s-missing impl_base' "$WORKDIR/stderr"; then
    pass "impl_base unset -> exit 64, even with commits on the branch, and the message says how to record it"
else
    fail "impl_base unset exited $RC ($(cat "$WORKDIR/stderr"))"
fi

printf '\n' | (PATH="$SHIM_BIN:$PATH" koto context add s-empty impl_base)
check s-empty
[ "$RC" -eq 64 ] && pass "impl_base empty -> exit 64" || fail "impl_base empty exited $RC"

printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' | (PATH="$SHIM_BIN:$PATH" koto context add s-bogus impl_base)
check s-bogus
if [ "$RC" -eq 64 ] && grep -q 'is not a commit' "$WORKDIR/stderr"; then
    pass "impl_base naming no commit -> exit 64"
else
    fail "impl_base naming no commit exited $RC"
fi

check
[ "$RC" -eq 67 ] && pass "missing session argument -> exit 67" || fail "missing argument exited $RC"

mkdir -p "$WORKDIR/not-git"
(cd "$WORKDIR/not-git" && PATH="$SHIM_BIN:$PATH" GIT_CEILING_DIRECTORIES="$WORKDIR" "$SCRIPT" s-plain 2>/dev/null)
[ $? -eq 64 ] && pass "outside a git repository -> exit 64" || fail "outside a git repository did not exit 64"

# --- engine cases ---------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: koto or jq not on PATH -- the engine cases did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

# koto validates --var values against ^[a-zA-Z0-9._/:@ \-]*$; a checkout path
# may not be inside that set, so the plugin root is reached through a clean
# symlink when it isn't.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac

STATE=""
tick() {
    # $1 session, $2 data (optional)
    local resp
    if [ -n "${2:-}" ]; then
        resp=$(cd "$RUN" && koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        resp=$(cd "$RUN" && koto next "$1" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$resp" | jq -r '.state // empty' 2>/dev/null)
}

ctx() { (cd "$RUN" && koto context "$@") 2>/dev/null; }

# at_verification <session>: the run reached the verification state. koto runs
# that state itself on entry, and these fixtures commit no verification map,
# so the run either waits there (a launcher that can't resolve a merge-base)
# or has already failed closed at done_blocked with verification's reason.
at_verification() {
    [ "$STATE" = verification ] && return 0
    [ "$STATE" = done_blocked ] && ctx get "$1" failure_reason | grep -q '^verification'
}

# to_routing <session>: issue-backed through analysis (which records impl_base
# as it enters) and a complete implementation, to issue_type_routing.
to_routing() {
    (cd "$RUN" && koto init "$1" --template "$TEMPLATE" \
        --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1)
    tick "$1" '{"mode":"issue_backed","issue_number":"7"}'
    tick "$1" '{"status":"override"}'
    # staleness_check routes on its own gate; with no GitHub remote the check
    # is unavailable (exit 3) and the run is already at analysis.
    tick "$1" '{"status":"override"}'
    printf 'plan\n' | ctx add "$1" plan.md
    tick "$1" '{"plan_outcome":"plan_ready"}'
    # The review level, chosen before implementation; full keeps scrutiny on
    # the code route.
    (cd "$RUN" && "$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh" set "$1" full) >/dev/null 2>&1
    tick "$1"
}

for sh in plain nomain worktree; do
    # docs: held without a commit, released by one.
    shape "e-docs-$sh" "$sh"
    to_routing "e-docs-$sh"
    if [ "$(ctx get "e-docs-$sh" impl_base)" = "$(head_sha)" ]; then
        pass "$sh: analysis recorded impl_base as HEAD"
    else
        fail "$sh: impl_base [$(ctx get "e-docs-$sh" impl_base)] is not HEAD"
    fi
    tick "e-docs-$sh" '{"implementation_status":"complete"}'
    tick "e-docs-$sh" '{"issue_type":"docs"}'
    [ "$STATE" = issue_type_routing ] && pass "$sh: docs with no commits holds at issue_type_routing" \
        || fail "$sh: docs with no commits reached [$STATE]"
    commit_file guide.md
    tick "e-docs-$sh" '{"issue_type":"docs"}'
    at_verification "e-docs-$sh" && pass "$sh: docs with a commit reaches verification" \
        || fail "$sh: docs with a commit reached [$STATE]"

    # code: scrutiny's passed route, held without a commit, released by one.
    shape "e-code-$sh" "$sh"
    to_routing "e-code-$sh"
    tick "e-code-$sh" '{"implementation_status":"complete"}'
    tick "e-code-$sh" '{"issue_type":"code"}'
    printf '{}\n' | ctx add "e-code-$sh" scrutiny_results.json
    tick "e-code-$sh" '{"scrutiny_outcome":"passed"}'
    [ "$STATE" = scrutiny ] && pass "$sh: scrutiny passed with no commits holds" \
        || fail "$sh: scrutiny with no commits reached [$STATE]"
    commit_file fix.txt
    tick "e-code-$sh" '{"scrutiny_outcome":"passed"}'
    [ "$STATE" = review ] && pass "$sh: scrutiny passed with a commit reaches review" \
        || fail "$sh: scrutiny with a commit reached [$STATE]"
done

# impl_base gone: the gate fails even though the branch has a commit.
shape e-nobase nomain
to_routing e-nobase
commit_file guide.md
tick e-nobase '{"implementation_status":"complete"}'
ctx remove e-nobase impl_base >/dev/null
tick e-nobase '{"issue_type":"docs"}'
[ "$STATE" = issue_type_routing ] && pass "impl_base removed: docs with a commit still holds" \
    || fail "impl_base removed: docs reached [$STATE]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
