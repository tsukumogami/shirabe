#!/usr/bin/env bash
# record-changed-paths_test.sh -- the changed-paths record, and the one place
# /work-on asks for the issue's type
# Part of the work-on skill
#
# `analysis` records `impl_base` once, a finished implementation goes through
# the mechanical `changed_paths_record` state, and the issue's type is asked
# exactly once, at the single-field `issue_type_routing` state. This suite pins
# both halves of that.
#
#   script cases -- record-changed-paths.sh against git fixtures, writing
#     through a koto stand-in on PATH that stores each key as a file. They need
#     no engine, so they also run on the macOS bash 3.2 floor leg, where koto is
#     absent.
#
#   engine cases -- the shipped work-on.md driven through real koto sessions:
#     the gate-free pass through changed_paths_record, each issue-type route
#     with and without commits, the commit check at scrutiny, the override and
#     blocked exits when the record can't be written, and a full plan-backed run
#     that must ask for issue_type exactly once. Skipped with a note when koto
#     is absent, the way the other engine-backed suites skip.
#
# Every run isolates HOME and builds its own git fixtures under a temp
# directory.
#
# Usage: record-changed-paths_test.sh
#
# Exit codes:
#   0 -- all cases pass (engine cases may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/record-changed-paths.sh"
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
# $SHIM_STORE/<session>/<key>. `get` and `exists` exit 1 for an absent key, as
# koto does. A session named `fail-*`
# refuses writes, which is how exit 66 is reached.

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = context ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
f="$SHIM_STORE/$3/$4"
case "$2" in
    add)
        case "$3" in fail-*) echo "koto shim: refusing session $3" >&2; exit 9 ;; esac
        mkdir -p "$SHIM_STORE/$3"
        cat > "$f"
        ;;
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
# fixture <name>: a bare origin with a seeded main (README.md, src/a.go), and a
# `repo` clone on branch impl/<name>. origin/HEAD is set by the clone.
# local_fixture <name>: a repository with no remote at all, main plus impl/<name>.

FX=""
fixture() {
    FX="$WORKDIR/fx-$1"
    mkdir -p "$FX"
    (
        cd "$FX" || exit 1
        git init -q --bare origin.git
        git clone -q origin.git seed 2>/dev/null
        cd seed || exit 1
        mkdir -p src
        printf 'readme\n' > README.md
        printf 'a1\na2\na3\na4\na5\na6\na7\na8\n' > src/a.go
        git add -A && git commit -q -m init && git push -q origin main
        cd .. && git clone -q origin.git repo 2>/dev/null
        cd repo && git checkout -q -b "impl/$1"
    ) >/dev/null 2>&1
}

local_fixture() {
    FX="$WORKDIR/fx-$1"
    mkdir -p "$FX/repo"
    (
        cd "$FX/repo" || exit 1
        git init -q -b main .
        printf 'readme\n' > README.md
        git add -A && git commit -q -m init
        git checkout -q -b "impl/$1"
    ) >/dev/null 2>&1
}

# commit_file <path> [content]: writes and commits one file in the run's repo.
commit_file() {
    (cd "$FX/repo" && mkdir -p "$(dirname "$1")" && printf '%s\n' "${2:-x}" > "$1" \
        && git add -A && git commit -q -m "feat: $1") >/dev/null 2>&1
}

RC=0
OUT=""
PATHS=""
# run <mode> <session>: runs the script in the fixture through the shim.
run() {
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@" 2>"$WORKDIR/stderr")
    RC=$?
    PATHS=$(cat "$SHIM_STORE/${2:-none}/changed_paths.txt" 2>/dev/null)
}

stored() { cat "$SHIM_STORE/$1/$2" 2>/dev/null; }
head_sha() { (cd "$FX/repo" && git rev-parse "${1:-HEAD}"); }
path_lines() { printf '%s\n' "$PATHS" | sed '1,2d'; }

# --- impl_base is recorded once -------------------------------------------------

fixture base-fixed
run --base s-base
first=$(head_sha)
if [ "$RC" -eq 0 ] && [ "$(stored s-base impl_base)" = "$first" ]; then
    pass "--base writes impl_base as git rev-parse HEAD"
else
    fail "--base: rc $RC, impl_base [$(stored s-base impl_base)], HEAD $first"
fi
if [ -z "$OUT" ]; then
    pass "a successful --base writes nothing to stdout"
else
    fail "--base stdout should be empty, got [$OUT]"
fi
commit_file src/new.go
run --base s-base
if [ "$RC" -eq 0 ] && [ "$(stored s-base impl_base)" = "$first" ] && [ "$(head_sha)" != "$first" ]; then
    pass "a second --base after a new commit leaves the stored impl_base unchanged"
else
    fail "re-entry moved impl_base: rc $RC, stored [$(stored s-base impl_base)], first $first"
fi
run --write s-base
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$PATHS" | sed -n 1p)" = "base: $first" ] \
    && [ "$(printf '%s\n' "$PATHS" | sed -n 2p)" = "commits: 1" ] \
    && [ "$(path_lines)" = "$(printf 'A\tsrc/new.go')" ]; then
    pass "--write diffs from impl_base: base line, commits line, one name-status line"
else
    fail "--write after impl_base: rc $RC, paths [$PATHS]"
fi
if [ -z "$OUT" ]; then
    pass "a successful --write writes nothing to stdout"
else
    fail "--write stdout should be empty, got [$OUT]"
fi

# --- a shared branch: siblings' earlier commits stay out -------------------------

fixture shared
commit_file sibling/one.md "sibling one"
commit_file sibling/two.md "sibling two"
run --base s-shared
commit_file mine/work.go
run --write s-shared
if [ "$RC" -eq 0 ] && [ "$(path_lines)" = "$(printf 'A\tmine/work.go')" ] \
    && [ "$(printf '%s\n' "$PATHS" | sed -n 2p)" = "commits: 1" ]; then
    pass "SHARED_BRANCH: sibling commits made before --base do not appear"
else
    fail "SHARED_BRANCH: rc $RC, paths [$PATHS]"
fi
case "$PATHS" in
    *sibling*) fail "SHARED_BRANCH: a sibling path leaked into changed_paths.txt" ;;
    *) pass "SHARED_BRANCH: no sibling path anywhere in the record" ;;
esac

# --- impl_base unset: merge-base with origin's default branch -------------------

fixture mergebase
fork=$(head_sha)
commit_file src/b.go
# origin/main moves after the fork; its change must not appear.
(cd "$FX/seed" && printf 'up\n' > upstream.md && git add -A && git commit -q -m up \
    && git push -q origin main) >/dev/null 2>&1
(cd "$FX/repo" && git fetch -q origin) >/dev/null 2>&1
run --write s-mb
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$PATHS" | sed -n 1p)" = "base: $fork" ] \
    && [ "$(path_lines)" = "$(printf 'A\tsrc/b.go')" ]; then
    pass "impl_base unset: the base is merge-base HEAD origin/<default>, upstream changes excluded"
else
    fail "merge-base fallback: rc $RC, fork $fork, paths [$PATHS]"
fi

fixture no-origin-head
fork=$(head_sha)
(cd "$FX/repo" && git remote set-head origin -d) >/dev/null 2>&1
commit_file src/c.go
run --write s-noh
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$PATHS" | sed -n 1p)" = "base: $fork" ]; then
    pass "impl_base unset, origin/HEAD unset: origin/main is taken as origin's default"
else
    fail "origin/main fallback: rc $RC, paths [$PATHS]"
fi

local_fixture local-main
fork=$(head_sha)
commit_file src/d.go
run --write s-local
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$PATHS" | sed -n 1p)" = "base: $fork" ] \
    && [ "$(path_lines)" = "$(printf 'A\tsrc/d.go')" ]; then
    pass "no origin default resolves: the base falls back to merge-base HEAD main"
else
    fail "local main fallback: rc $RC, paths [$PATHS]"
fi

# --- renames -------------------------------------------------------------------

fixture rename
run --base s-ren
(cd "$FX/repo" && git mv src/a.go src/renamed.go && git commit -q -m "refactor: rename") >/dev/null 2>&1
run --write s-ren
lines=$(path_lines)
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" = 1 ] \
    && printf '%s\n' "$lines" | grep -qE "^R[0-9]*	src/a.go	src/renamed.go$"; then
    pass "a rename is one R line naming both paths, not a delete plus an add"
else
    fail "rename: rc $RC, lines [$lines]"
fi

# --- the caps ------------------------------------------------------------------

# many_files <n> <prefix>: one commit adding n files named <prefix><i>.
many_files() {
    (cd "$FX/repo" && mkdir -p m && i=1 && while [ "$i" -le "$1" ]; do
        : > "m/$2$i"; i=$((i + 1)); done && git add -A && git commit -q -m "feat: many") >/dev/null 2>&1
}

fixture cap-lines
run --base s-cl
many_files 250 f
run --write s-cl
nlines=$(path_lines | grep -c '^A	')
last=$(printf '%s\n' "$PATHS" | tail -1)
if [ "$RC" -eq 0 ] && [ "$nlines" = 200 ] && [ "$last" = "... 50 more paths" ]; then
    pass "250 paths: 200 path lines, then '... 50 more paths'"
else
    fail "line cap: rc $RC, $nlines path lines, last [$last]"
fi

fixture cap-exact
run --base s-ce
many_files 200 f
run --write s-ce
if [ "$RC" -eq 0 ] && [ "$(path_lines | grep -c '^A	')" = 200 ] \
    && ! printf '%s\n' "$PATHS" | grep -q 'more paths'; then
    pass "exactly 200 paths: all kept, no trailer"
else
    fail "200 paths: rc $RC, last [$(printf '%s\n' "$PATHS" | tail -1)]"
fi

fixture cap-bytes
run --base s-cb
LONG=$(printf 'long-name-%080d-' 0)
many_files 150 "$LONG"
run --write s-cb
bytes=$(printf '%s\n' "$PATHS" | wc -c | tr -d ' ')
kept=$(path_lines | grep -c '^A	')
last=$(printf '%s\n' "$PATHS" | tail -1)
if [ "$RC" -eq 0 ] && [ "$bytes" -le 8192 ] && [ "$kept" -lt 150 ] && [ "$kept" -gt 0 ] \
    && [ "$last" = "... $((150 - kept)) more paths" ]; then
    pass "150 long paths: cut by the 8192-byte cap ($bytes bytes, $kept kept), '... $((150 - kept)) more paths'"
else
    fail "byte cap: rc $RC, $bytes bytes, $kept kept, last [$last]"
fi
# Nothing classifies: every line is a header, a name-status line, or the trailer.
stray=$(printf '%s\n' "$PATHS" | grep -vE '^(base: [0-9a-f]{40}|commits: [0-9]+|[ACDMRTUX][0-9]*	.+|\.\.\. [0-9]+ more paths)$')
if [ -z "$stray" ]; then
    pass "the record holds only base, commits, name-status lines and the trailer -- no classification"
else
    fail "unexpected lines in changed_paths.txt: [$stray]"
fi

# --- exit codes ----------------------------------------------------------------

fixture exits
run
if [ "$RC" -eq 67 ]; then pass "no arguments: exit 67"; else fail "no arguments: rc $RC"; fi
run --write
if [ "$RC" -eq 67 ] && [ ! -e "$SHIM_STORE/none/changed_paths.txt" ]; then
    pass "--write with no session: exit 67, nothing written"
else
    fail "--write with no session: rc $RC"
fi
run --classify s-x
if [ "$RC" -eq 67 ] && [ ! -e "$SHIM_STORE/s-x/changed_paths.txt" ]; then
    pass "an unrecognised mode: exit 67, nothing written"
else
    fail "unrecognised mode: rc $RC"
fi
run --base
if [ "$RC" -eq 67 ]; then pass "--base with no session: exit 67"; else fail "--base with no session: rc $RC"; fi

# No base resolves: no impl_base, no remote, no local main.
FX="$WORKDIR/fx-orphan"
mkdir -p "$FX/repo"
(cd "$FX/repo" && git init -q -b trunk . && : > x && git add x && git commit -q -m init) >/dev/null 2>&1
run --write s-orphan
if [ "$RC" -eq 64 ] && [ ! -e "$SHIM_STORE/s-orphan/changed_paths.txt" ]; then
    pass "no base resolves: exit 64, no changed_paths.txt"
else
    fail "no base: rc $RC, paths [$PATHS]"
fi
# A record left by an earlier lap is removed, so the gate cannot pass on it.
mkdir -p "$SHIM_STORE/s-stale"
printf 'base: stale\n' > "$SHIM_STORE/s-stale/changed_paths.txt"
run --write s-stale
if [ "$RC" -eq 64 ] && [ ! -e "$SHIM_STORE/s-stale/changed_paths.txt" ]; then
    pass "exit 64 removes a changed_paths.txt from an earlier lap"
else
    fail "stale record: rc $RC, file present: $([ -e "$SHIM_STORE/s-stale/changed_paths.txt" ] && echo yes || echo no)"
fi
FX="$WORKDIR/fx-notgit"
mkdir -p "$FX/repo"
run --base s-notgit
if [ "$RC" -eq 64 ] && [ ! -e "$SHIM_STORE/s-notgit/impl_base" ]; then
    pass "--base outside a git repository: exit 64, nothing written"
else
    fail "--base outside git: rc $RC"
fi
run --write s-notgit
if [ "$RC" -eq 64 ] && [ ! -e "$SHIM_STORE/s-notgit/changed_paths.txt" ]; then
    pass "--write outside a git repository: exit 64, no changed_paths.txt"
else
    fail "--write outside git: rc $RC"
fi

fixture write-fails
commit_file src/e.go
run --write fail-session
if [ "$RC" -eq 66 ]; then
    pass "a failed koto context add: exit 66"
else
    fail "context add failure: rc $RC"
fi

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

# A plugin root whose record-changed-paths.sh records the base and then fails
# every --write, for the cases where the record cannot be written.
FAKE_ROOT="$WORKDIR/fake-plugin"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts"
cat > "$FAKE_ROOT/skills/work-on/scripts/record-changed-paths.sh" <<STUB
#!/usr/bin/env bash
[ "\$1" = --base ] && exec "$PLUGIN_ROOT/skills/work-on/scripts/record-changed-paths.sh" "\$@"
echo "stub: refusing \$1" >&2
exit 64
STUB
chmod +x "$FAKE_ROOT/skills/work-on/scripts/record-changed-paths.sh"

RESP=""
STATE=""
ACTION=""
TRACE="$WORKDIR/trace"
: > "$TRACE"
tick() {
    # $1 session, $2 data (optional). Every response is appended to $TRACE.
    if [ -n "${2:-}" ]; then
        RESP=$(cd "$FX/repo" && koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        RESP=$(cd "$FX/repo" && koto next "$1" --no-cleanup 2>/dev/null)
    fi
    printf '%s\n' "$RESP" | jq -c --arg s "$1" '{session: $s, state, action, expects}' >> "$TRACE" 2>/dev/null
    STATE=$(printf '%s' "$RESP" | jq -r '.state // empty' 2>/dev/null)
    ACTION=$(printf '%s' "$RESP" | jq -r '.action // empty' 2>/dev/null)
}

ctx() { (cd "$FX/repo" && koto context "$@") 2>/dev/null; }

start() {
    # $1 session, $2 plugin root (optional)
    (cd "$FX/repo" && koto init "$1" --template "$TEMPLATE" \
        --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 \
        --var PLUGIN_ROOT="${2:-$PLUGIN_ROOT}" >/dev/null 2>&1)
}

# Issue-backed to analysis; the three overrides cross the states that read a
# real GitHub issue and a real baseline.
to_analysis() {
    start "$1" "${2:-}"
    tick "$1" '{"mode":"issue_backed","issue_number":"7"}'
    tick "$1" '{"status":"override"}'
    tick "$1" '{"status":"override"}'
    tick "$1" '{"staleness_signal":"override"}'
}

to_implementation() {
    to_analysis "$1" "${2:-}"
    printf 'plan\n' | ctx add "$1" plan.md
    tick "$1" '{"plan_outcome":"plan_ready"}'
}

# The routing question, reached through changed_paths_record with no evidence.
fixture e-route
to_implementation e-route
base=$(ctx get e-route impl_base)
if [ "$STATE" = implementation ] && [ "$base" = "$(head_sha)" ]; then
    pass "analysis records impl_base as HEAD on entry"
else
    fail "analysis: state [$STATE], impl_base [$base]"
fi
commit_file docs/guide.md
tick e-route '{"implementation_status":"complete"}'
if [ "$STATE" = issue_type_routing ] && [ "$ACTION" = evidence_required ] \
    && [ "$(printf '%s' "$RESP" | jq -c '.expects.fields | keys')" = '["issue_type"]' ]; then
    pass "complete with no issue_type crosses changed_paths_record and stops at issue_type_routing asking for issue_type"
else
    fail "complete: state [$STATE], action [$ACTION], expects $(printf '%s' "$RESP" | jq -c '.expects.fields' 2>/dev/null)"
fi
if ctx exists e-route changed_paths.txt >/dev/null && ctx get e-route changed_paths.txt | grep -q '^A	docs/guide.md$'; then
    pass "changed_paths.txt is in context when the question is asked"
else
    fail "changed_paths.txt missing or wrong: [$(ctx get e-route changed_paths.txt)]"
fi
if grep '"session":"e-route"' "$TRACE" | grep -q '"state":"changed_paths_record"'; then
    fail "changed_paths_record stopped for the agent on the passing path"
else
    pass "changed_paths_record never stopped for the agent: the gate passed with no evidence"
fi
if [ "$(printf '%s' "$RESP" | jq -c '.expects.fields.issue_type.values')" = '["code","docs","task"]' ]; then
    pass "issue_type offers exactly code, docs and task"
else
    fail "issue_type values: $(printf '%s' "$RESP" | jq -c '.expects.fields.issue_type' 2>/dev/null)"
fi
tick e-route '{"issue_type":"docs"}'
if [ "$STATE" = verification ]; then
    pass "docs with commits reaches verification"
else
    fail "docs with commits reached [$STATE]"
fi

# code with no commits over main still reaches scrutiny; scrutiny then holds
# passed until a commit exists.
fixture e-code
to_implementation e-code
tick e-code '{"implementation_status":"complete"}'
tick e-code '{"issue_type":"code"}'
if [ "$STATE" = scrutiny ]; then
    pass "code reaches scrutiny with no commits over main"
else
    fail "code with no commits reached [$STATE]"
fi
printf '{}\n' | ctx add e-code scrutiny_results.json
tick e-code '{"scrutiny_outcome":"passed"}'
if [ "$STATE" = scrutiny ]; then
    pass "scrutiny: passed with scrutiny_results.json but no commits does not reach review"
else
    fail "scrutiny with no commits reached [$STATE]"
fi
commit_file src/fix.go
tick e-code '{"scrutiny_outcome":"passed"}'
if [ "$STATE" = review ]; then
    pass "scrutiny: passed with commits reaches review"
else
    fail "scrutiny with commits reached [$STATE]"
fi

fixture e-task
to_implementation e-task
tick e-task '{"implementation_status":"complete"}'
tick e-task '{"issue_type":"task"}'
if [ "$STATE" = verification ]; then
    pass "task with no commits reaches verification"
else
    fail "task with no commits reached [$STATE]"
fi

fixture e-docs-empty
to_implementation e-docs-empty
tick e-docs-empty '{"implementation_status":"complete"}'
tick e-docs-empty '{"issue_type":"docs"}'
if [ "$STATE" = issue_type_routing ]; then
    pass "docs with no commits does not advance"
else
    fail "docs with no commits reached [$STATE]"
fi

# The record cannot be written: changed_paths_record stops, and both exits work.
fixture e-override
to_implementation e-override "$FAKE_ROOT"
tick e-override '{"implementation_status":"complete"}'
if [ "$STATE" = changed_paths_record ] && ! ctx exists e-override changed_paths.txt >/dev/null; then
    pass "script fails, changed_paths.txt absent: changed_paths_record stops for the agent ($ACTION)"
else
    fail "failed record: state [$STATE], action [$ACTION]"
fi
tick e-override '{"paths_status":"override"}'
if [ "$STATE" = issue_type_routing ]; then
    pass "paths_status override reaches issue_type_routing"
else
    fail "override reached [$STATE]"
fi

fixture e-blocked
to_implementation e-blocked "$FAKE_ROOT"
tick e-blocked '{"implementation_status":"complete"}'
tick e-blocked '{"paths_status":"blocked","detail":"no base"}'
if [ "$STATE" = done_blocked ]; then
    pass "paths_status blocked reaches done_blocked"
else
    fail "blocked reached [$STATE]"
fi

# A full plan-backed run on a shared branch: issue_type is asked exactly once,
# and the sibling's earlier commit stays out of the record.
fixture e-plan
commit_file sibling/earlier.md "a sibling's commit"
(cd "$FX/repo" && koto init e-plan --template "$TEMPLATE" \
    --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 --var ISSUE_SOURCE=plan_outline \
    --var PLAN_DOC=docs/plans/PLAN-t.md --var SHARED_BRANCH=impl/e-plan \
    --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1)
tick e-plan '{"mode":"plan_backed","issue_source":"plan_outline"}'
printf 'outline\n' | ctx add e-plan context.md
tick e-plan '{"status":"completed","issue_source":"plan_outline"}'
tick e-plan '{"verdict":"proceed"}'
# On a shared branch the orchestrator made the branch; setup_plan_backed takes
# override, as its directive says.
[ "$STATE" = setup_plan_backed ] && tick e-plan '{"status":"override"}'
if [ "$STATE" = analysis ]; then
    pass "plan-backed: plan_validation proceed, then setup, reaches analysis"
else
    fail "plan-backed: expected analysis, got [$STATE]"
fi
printf 'plan\n' | ctx add e-plan plan.md
tick e-plan '{"plan_outcome":"plan_ready"}'
commit_file src/mine.go
tick e-plan '{"implementation_status":"complete"}'
if ctx get e-plan changed_paths.txt | grep -q sibling; then
    fail "plan-backed: a sibling's earlier commit leaked into changed_paths.txt"
else
    pass "plan-backed: the sibling's earlier commit is not in changed_paths.txt"
fi
tick e-plan '{"issue_type":"code"}'
printf '{}\n' | ctx add e-plan scrutiny_results.json
tick e-plan '{"scrutiny_outcome":"passed"}'
printf '{}\n' | ctx add e-plan review_results.json
tick e-plan '{"review_outcome":"passed"}'
printf '{}\n' | ctx add e-plan qa_results.json
tick e-plan '{"qa_outcome":"passed"}'
tick e-plan '{"verification_outcome":"passed","commands_run":"none"}'
printf '## Changes Made\n' | ctx add e-plan summary.md
tick e-plan '{"finalization_status":"ready_for_pr"}'
if [ "$STATE" = pre_pr_evidence ]; then
    pass "plan-backed: the run reaches pre_pr_evidence"
else
    fail "plan-backed: expected pre_pr_evidence, got [$STATE]"
fi
# pr_creation and ci_monitor read GitHub; cross them to the terminal.
(cd "$FX/repo" && koto next e-plan --to done --rationale "no GitHub in this fixture" --no-cleanup >/dev/null 2>&1)
asked=$(grep '"session":"e-plan"' "$TRACE" | grep -c '"issue_type"')
if [ "$asked" = 1 ]; then
    pass "plan-backed: issue_type is requested exactly once across the run"
else
    fail "plan-backed: issue_type requested $asked times"
fi
asked_at=$(grep '"session":"e-plan"' "$TRACE" | grep '"issue_type"' | jq -r .state)
if [ "$asked_at" = issue_type_routing ]; then
    pass "plan-backed: the one request is at issue_type_routing"
else
    fail "plan-backed: issue_type requested at [$asked_at]"
fi

# The issue-backed run above asks exactly once too.
asked=$(grep '"session":"e-route"' "$TRACE" | grep -c '"issue_type"')
if [ "$asked" = 1 ]; then
    pass "issue-backed: issue_type is requested exactly once"
else
    fail "issue-backed: issue_type requested $asked times"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
