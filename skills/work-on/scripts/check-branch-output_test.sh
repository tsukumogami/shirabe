#!/usr/bin/env bash
# check-branch-output_test.sh -- does check-branch-output.sh reach the right
# verdict on real repositories, name the right rule, and refuse to guess?
#
# Each case builds a throwaway repository with a bare origin and runs the
# script against it. --session reads impl_base through a koto stand-in on PATH
# that stores each context key as a file, so no engine is needed. The
# --docs-visibility cases run the real `shirabe validate`, since what they
# check is that the script counts the validator's visibility codes and no
# others; they SKIP with a notice where shirabe is not on PATH (the macOS floor
# leg), and the Linux CI job builds it so they run there.
#
# Every finding line the script prints is checked against koto's finding shape
# (`jq -e '.rule_id and .level and .message and .rule_ref'`).
#
# Usage: check-branch-output_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-branch-output.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-output-test.XXXXXX")
WORKDIR=$(cd -P "$WORKDIR" && pwd -P)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# --- the koto stand-in ----------------------------------------------------------

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add) mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
    get) [ -f "$f" ] || { echo "koto shim: no key $4" >&2; exit 1; }; cat "$f" ;;
    exists) [ -f "$f" ] ;;
    *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE
export PATH="$SHIM_BIN:$PATH"

set_impl_base() { # <session> <sha>
    mkdir -p "$SHIM_STORE/$1"
    printf '%s\n' "$2" > "$SHIM_STORE/$1/impl_base"
}

# --- fixtures -------------------------------------------------------------------
#
# fixture <name> [<claude-md line>]: a bare origin whose main holds one
# conventional commit (and a CLAUDE.md when a line is given), and a clone in
# $REPO on branch work/<name>.

REPO=""
N=0
fixture() {
    N=$((N + 1))
    local dir="$WORKDIR/fx-$N-$1"
    mkdir -p "$dir"
    git init -q --bare "$dir/origin.git"
    git clone -q "$dir/origin.git" "$dir/seed" 2>/dev/null
    (
        cd "$dir/seed" || exit 1
        printf 'readme\n' > README.md
        [ -z "${2-}" ] || printf '# repo\n\n%s\n' "$2" > CLAUDE.md
        git add -A && git commit -qm "chore: seed the repository"
        git push -q origin main 2>/dev/null
    )
    git clone -q "$dir/origin.git" "$dir/repo" 2>/dev/null
    REPO="$dir/repo"
    git -C "$REPO" checkout -q -b "work/$1"
}

commit_file() { # <path> <content> <message...>
    local path=$1 content=$2
    shift 2
    mkdir -p "$REPO/$(dirname "$path")"
    printf '%s\n' "$content" > "$REPO/$path"
    git -C "$REPO" add -A
    git -C "$REPO" commit -q "$@"
}

# advance_origin <message>: a new commit on origin's main, fetched into $REPO.
advance_origin() {
    local seed
    seed="$(dirname "$REPO")/seed"
    (
        cd "$seed" || exit 1
        git pull -q origin main 2>/dev/null
        printf '%s\n' "$1" >> main-only.txt
        git add -A && git commit -qm "$1"
        git push -q origin main 2>/dev/null
    )
    git -C "$REPO" fetch -q origin
}

OUT=""
ERR=""
RC=0
run() { # <args>... from $REPO
    OUT=$(cd "$REPO" && "$CHECK" "$@" 2>"$WORKDIR/stderr")
    RC=$?
    ERR=$(cat "$WORKDIR/stderr")
}

# Every finding line is koto's shape, and the run printed at least one when it
# exited 1 and none otherwise.
check_shape() { # <label>
    local line n=0 bad=0
    while IFS= read -r line; do
        case "$line" in
            ::koto-finding::*)
                n=$((n + 1))
                printf '%s' "${line#::koto-finding::}" \
                    | jq -e '.rule_id and .level and .message and .rule_ref' >/dev/null 2>&1 || bad=1
                ;;
        esac
    done <<EOF
$OUT
EOF
    if [ "$bad" -ne 0 ]; then
        fail "$1: a finding line does not parse as koto's finding shape: $OUT"
    elif [ "$RC" -eq 1 ] && [ "$n" -eq 0 ]; then
        fail "$1: exit 1 with no finding line"
    elif [ "$RC" -ne 1 ] && [ "$n" -ne 0 ]; then
        fail "$1: exit $RC printed $n finding line(s)"
    else
        pass "$1: finding lines parse as koto's finding shape ($n)"
    fi
}

rule_ids() {
    printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' | jq -r '.rule_id' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

expect() { # <label> <exit> [<rule ids, space separated, sorted>]
    if [ "$RC" -ne "$2" ]; then
        fail "$1: want exit $2, got $RC (stdout: $OUT; stderr: $ERR)"
        return
    fi
    if [ $# -ge 3 ] && [ "$(rule_ids)" != "$3" ]; then
        fail "$1: want rules [$3], got [$(rule_ids)]"
        return
    fi
    pass "$1"
    check_shape "$1"
}

# --- --commits ------------------------------------------------------------------

fixture subjects
BASE=$(git -C "$REPO" rev-parse origin/main)
commit_file a.txt a -m "feat: add a"
commit_file b.txt b -m "added b without a type"
commit_file c.txt c -m "fix: the tip is conventional"
run --commits --base-ref origin/main
expect "--commits: a non-conventional subject below a conventional tip" 1 "commit/conventional-subject"
BAD_SHA=$(git -C "$REPO" rev-parse HEAD~1 | cut -c1-12)
case "$OUT" in
    *"$BAD_SHA"*) pass "--commits: the finding names the offending commit" ;;
    *) fail "--commits: the finding does not name $BAD_SHA: $OUT" ;;
esac
BASE_REF_OUT=$OUT
BASE_REF_RC=$RC
set_impl_base s-subjects "$BASE"
run --commits --session s-subjects
if [ "$RC" = "$BASE_REF_RC" ] && [ "$OUT" = "$BASE_REF_OUT" ]; then
    pass "--base-ref origin/main selects the same commits as --session with impl_base at the branch point"
else
    fail "--base-ref and --session disagree: [$BASE_REF_RC] $BASE_REF_OUT vs [$RC] $OUT"
fi
check_shape "--commits --session"

fixture trailer
commit_file a.txt a -m "feat: add a" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
run --commits --base-ref origin/main
expect "--commits: a Co-Authored-By: Claude trailer" 1 "commit/no-ai-trailer"

fixture generated
commit_file a.txt a -m "feat: add a" -m "Generated with Claude Code"
run --commits --base-ref origin/main
expect "--commits: a Generated with Claude Code line" 1 "commit/no-ai-trailer"

fixture human-coauthor
commit_file a.txt a -m "feat: add a" -m "Co-Authored-By: Jane Doe <jane@example.invalid>"
run --commits --base-ref origin/main
expect "--commits: a human Co-Authored-By trailer is not attribution" 0

fixture merge
BASE=$(git -C "$REPO" rev-parse origin/main)
commit_file a.txt a -m "feat: add a"
advance_origin "docs: a change on main"
git -C "$REPO" merge -q --no-edit origin/main
SUBJECT=$(git -C "$REPO" log -1 --format=%s)
case "$SUBJECT" in
    Merge*) pass "fixture: the merge commit carries git's default subject ($SUBJECT)" ;;
    *) fail "fixture: the merge commit subject is [$SUBJECT]" ;;
esac
run --commits --base-ref origin/main
expect "--commits --base-ref: a merge commit with git's default subject" 0
set_impl_base s-merge "$BASE"
run --commits --session s-merge
expect "--commits --session: a merge commit with git's default subject" 0

# --- --wip ----------------------------------------------------------------------

fixture wip
# Split with "" so this file's own text never trips the public-content check,
# which refuses a committed wip/ file path.
WIP_FILE="wi""p/notes.md"
commit_file "$WIP_FILE" notes -m "chore: stage notes"
run --wip
expect "--wip: a staged file in HEAD's tree" 1 "branch/no-wip-files"
case "$OUT" in
    *"\"path\":\"$WIP_FILE\""*) pass "--wip: the finding names the path" ;;
    *) fail "--wip: the finding does not name $WIP_FILE: $OUT" ;;
esac

# --- --synced -------------------------------------------------------------------

fixture behind
commit_file a.txt a -m "feat: add a"
advance_origin "docs: a change on main"
run --synced
expect "--synced: a branch missing origin/main" 1 "branch/current-with-main"
git -C "$REPO" merge -q --no-commit --no-ff origin/main >/dev/null 2>&1
if [ -e "$(git -C "$REPO" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; then
    pass "fixture: a merge is in progress"
else
    fail "fixture: MERGE_HEAD is absent"
fi
run --synced
expect "--synced: a merge in progress (MERGE_HEAD present)" 1 "branch/current-with-main"
git -C "$REPO" commit -q --no-edit
run --synced
expect "--synced: after the merge is committed" 0

# --- a clean fixture ------------------------------------------------------------

fixture clean "## Repo Visibility: Public"
BASE=$(git -C "$REPO" rev-parse origin/main)
commit_file src/a.sh 'echo a' -m "feat: add a"
commit_file src/b.sh 'echo b' -m "fix(src): correct b"
set_impl_base s-clean "$BASE"
run --commits --session s-clean
expect "clean: --commits --session" 0
run --commits --base-ref origin/main
expect "clean: --commits --base-ref" 0
run --wip
expect "clean: --wip" 0
run --synced
expect "clean: --synced" 0
run --docs-visibility --session s-clean
expect "clean: --docs-visibility with no changed document" 0

# --- could not decide -----------------------------------------------------------

run --commits --base-ref origin/no-such-branch
expect "--commits: a --base-ref that does not resolve" 2
set_impl_base s-bogus 0123456789abcdef0123456789abcdef01234567
run --commits --session s-bogus
expect "--commits: an impl_base that names no commit" 2
run --commits --session s-unset
expect "--commits: a session with no impl_base" 2
run --docs-visibility --base-ref origin/no-such-branch
expect "--docs-visibility: a --base-ref that does not resolve" 2
run --synced --base-ref origin/no-such-branch
expect "--synced: a ref that does not resolve" 2
run --commits
expect "usage: --commits with no range" 2
run --commits --session s-clean --base-ref origin/main
expect "usage: --commits with both ranges" 2
run --wip --session s-clean
expect "usage: --wip with a range" 2
run --nonsense
expect "usage: an unknown mode" 2

# --- --docs-visibility ------------------------------------------------------------

write_doc() { # <path> then the body on stdin
    mkdir -p "$REPO/$(dirname "$1")"
    cat > "$REPO/$1"
}

VISION='---
schema: vision/v1
status: Draft
thesis: x
scope: org
---

# VISION: x

## Status

Draft

## Thesis

x

## Competitive Positioning

y'

STRATEGY='---
schema: strategy/v1
status: Draft
---

# STRATEGY: x

## Status

Draft

## Competitive Considerations

y'

COMP='---
schema: comp/v1
status: Draft
---

# COMP: x'

PRD='---
schema: prd/v1
status: Draft
problem: x
goals: y
---

# PRD: x

## Status

Draft'

if command -v shirabe >/dev/null 2>&1; then
    fixture comp "## Repo Visibility: Public"
    printf '%s\n' "$COMP" | write_doc docs/competitive/COMP-x.md
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs: add a comparison"
    run --docs-visibility --base-ref origin/main
    expect "--docs-visibility: a COMP doc in a public repository" 1 "docs/private-only-type"

    fixture comp-private "## Repo Visibility: Private"
    printf '%s\n' "$COMP" | write_doc docs/competitive/COMP-x.md
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs: add a comparison"
    run --docs-visibility --base-ref origin/main
    expect "--docs-visibility: a COMP doc in a private repository" 0

    fixture vision "## Repo Visibility: Public"
    BASE=$(git -C "$REPO" rev-parse origin/main)
    printf '%s\n' "$VISION" | write_doc docs/visions/VISION-x.md
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs: add a vision"
    set_impl_base s-vision "$BASE"
    run --docs-visibility --session s-vision
    expect "--docs-visibility: a VISION with a prohibited section" 1 "docs/visibility-vision-sections"
    case "$OUT" in
        *'"path":"docs/visions/VISION-x.md"'*'"line":'*) pass "--docs-visibility: the finding names the file and line" ;;
        *) fail "--docs-visibility: the finding does not name the file and line: $OUT" ;;
    esac

    fixture strategy "## Repo Visibility: Public"
    printf '%s\n' "$STRATEGY" | write_doc docs/strategies/STRATEGY-x.md
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs: add a strategy"
    run --docs-visibility --base-ref origin/main
    expect "--docs-visibility: a STRATEGY with a prohibited section" 1 "docs/visibility-strategy-sections"

    fixture prd "## Repo Visibility: Public"
    printf '%s\n' "$PRD" | write_doc docs/prds/PRD-x.md
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "docs: add a prd"
    # The validator does fail this document, on a code the gate leaves to CI.
    VOUT=$(cd "$REPO" && shirabe validate --visibility=public --format json docs/prds/PRD-x.md 2>/dev/null)
    if printf '%s' "$VOUT" | jq -e '[.findings[].code] | length > 0 and all(. != "R7" and . != "R8" and . != "R9")' >/dev/null 2>&1; then
        pass "fixture: the PRD fails the validator on a non-visibility code only"
    else
        fail "fixture: the PRD does not carry a non-visibility finding: $VOUT"
    fi
    run --docs-visibility --base-ref origin/main
    expect "--docs-visibility: a PRD missing a required section (a non-visibility code)" 0

    fixture skill-file "## Repo Visibility: Public"
    commit_file skills/x/SKILL.md 'Never commit a private/ path or a wip/ reference.' -m "docs(x): describe the rule"
    run --docs-visibility --base-ref origin/main
    expect "--docs-visibility: a changed skill file containing private/" 0
else
    echo "SKIP: shirabe not on PATH -- the --docs-visibility validator cases did not run"
fi

echo
echo "check-branch-output_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
