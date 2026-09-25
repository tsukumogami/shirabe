#!/usr/bin/env bash
# drift-facts_test.sh -- the upstream drift facts, and the route they drive
# Part of the execute skill
#
# `drift_facts` computes, before the rebase, whether origin/main moved in a way
# the PLAN references, and `worktree_sync` routes on the answer. A run with no
# drift must reach `spawn_and_await` without the agent being asked anything,
# and a run with drift must stop at `worktree_discipline_check` with the facts
# the question needs.
#
# Two halves:
#
#   script cases -- drift-facts.sh against git fixtures with a bare `origin`,
#     writing through a koto stand-in on PATH that stores each key as a file
#     and logs the order keys arrive in. These need no engine, so they also
#     run on the macOS bash 3.2 floor leg, where koto is absent.
#
#   engine cases -- the shipped execute.md driven through real koto sessions:
#     no drift, overlap answered `informational`, and a deleted reference
#     answered `intent-changing`. Skipped with a note when koto is absent.
#
# Every run isolates HOME and builds its own fixtures under a temp directory.
#
# Usage: drift-facts_test.sh
#
# Exit codes:
#   0 -- all cases pass (engine cases may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/drift-facts.sh"
TEMPLATE="$SCRIPT_DIR/../koto-templates/execute.md"
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v jq  >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
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
# `koto context add <session> <key>` stores stdin at $SHIM_STORE/<session>/<key>
# and appends the key to $SHIM_STORE/order. A session named `fail-*` makes the
# write fail, which is how exit 66 is reached. `koto context remove` deletes
# the stored file and succeeds whether or not it was there, as koto's does.

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
if [ "$1 $2" = "context remove" ]; then
    rm -f "$SHIM_STORE/$3/$4"
    exit 0
fi
[ "$1 $2" = "context add" ] || { echo "koto shim: unsupported: $*" >&2; exit 2; }
case "$3" in fail-*) echo "koto shim: refusing session $3" >&2; exit 9 ;; esac
mkdir -p "$SHIM_STORE/$3"
cat > "$SHIM_STORE/$3/$4"
echo "$4" >> "$SHIM_STORE/order"
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE

# --- fixtures -----------------------------------------------------------------
#
# fixture <name>: a bare origin with a seeded main, a `seed` clone that plays
# upstream, and a `repo` clone on branch impl/<name> where the run happens.
# Main starts with src/a.go, src/b.go, docs/guide.md, README.md, and
# wip/notes.md (so wip/ exclusion is tested against a path that exists).

FX=""
fixture() {
    FX="$WORKDIR/fx-$1"
    mkdir -p "$FX"
    (
        cd "$FX" || exit 1
        git init -q --bare origin.git
        git clone -q origin.git seed 2>/dev/null
        cd seed || exit 1
        mkdir -p src docs wip
        printf 'a1\na2\na3\n' > src/a.go
        printf 'b1\n' > src/b.go
        printf 'guide\n' > docs/guide.md
        printf 'readme\n' > README.md
        printf 'notes\n' > wip/notes.md
        git add -A && git commit -q -m init && git push -q origin main
        cd .. && git clone -q origin.git repo 2>/dev/null
        cd repo && git checkout -q -b "impl/$1"
        # The run's origin names a GitHub repository, which is what the
        # template's initial state, write_set_record, records as the write set;
        # insteadOf sends every fetch to the bare repository above.
        git remote set-url origin https://github.com/o/r.git
        git config url."$FX/origin.git".insteadOf https://github.com/o/r.git
    ) >/dev/null 2>&1
}

# upstream <shell>: runs a change in the seed clone, commits, and pushes it.
upstream() {
    (cd "$FX/seed" && eval "$1" && git add -A && git commit -q -m "$2" && git push -q origin main) >/dev/null 2>&1
}

# plan <body>: writes and commits docs/plans/PLAN-t.md on the run's branch.
plan() {
    mkdir -p "$FX/repo/docs/plans"
    printf '%s\n' "$1" > "$FX/repo/docs/plans/PLAN-t.md"
    (cd "$FX/repo" && git add -A && git commit -q -m plan) >/dev/null 2>&1
}

RC=0
OUT=""
FACTS=""
INTENT=""
SESS=""
# run [session]: runs the script in the fixture through the shim.
run() {
    SESS=${1:-s-$$-$RANDOM}
    rm -f "$SHIM_STORE/order"
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$SESS" docs/plans/PLAN-t.md 2>"$WORKDIR/stderr")
    RC=$?
    FACTS=$(cat "$SHIM_STORE/$SESS/drift_facts.json" 2>/dev/null)
    INTENT=$(cat "$SHIM_STORE/$SESS/plan_intent.md" 2>/dev/null)
}

jf() { printf '%s' "$FACTS" | jq -c "$1" 2>/dev/null; }

PLAN_CODE='---
schema: plan/v1
---
# PLAN: t

## Scope Summary

Touches `src/a.go`.

## Issue Outlines

### Issue 1: feat: a

**Goal**: Change a.

**Files**: `src/a.go`'

# --- no advance ----------------------------------------------------------------

fixture no-advance
plan "$PLAN_CODE"
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"none"' ] && [ "$(jf .main_advanced)" = false ] \
    && [ "$(jf .commits_since_base)" = 0 ] && [ "$(jf .reasons)" = '["main_not_advanced"]' ]; then
    pass "main not advanced: route none, main_advanced false, commits_since_base 0"
else
    fail "main not advanced: rc $RC, facts $FACTS"
fi
if [ -z "$OUT" ]; then
    pass "a successful run writes nothing to stdout"
else
    fail "stdout should be empty, got [$OUT]"
fi
if [ "$(tr '\n' ' ' < "$SHIM_STORE/order")" = "plan_intent.md drift_facts.json " ]; then
    pass "plan_intent.md is written before drift_facts.json"
else
    fail "write order was [$(tr '\n' ' ' < "$SHIM_STORE/order" 2>/dev/null)]"
fi
if [ "$(jf .schema)" = '"drift-facts/v1"' ] && [ "$(jf .plan_doc)" = '"docs/plans/PLAN-t.md"' ] \
    && [ "$(jf '[.base, .main_head] | map(length)')" = '[40,40]' ] && [ "$(jf .truncated)" = false ]; then
    pass "schema drift-facts/v1 with plan_doc, base, main_head, truncated"
else
    fail "shape: $FACTS"
fi
if [ "$(jf 'keys_unsorted')" = '["route","schema","reasons","plan_doc","base","main_head","main_advanced","commits_since_base","referenced_paths","overlap","deleted_referenced_paths","truncated"]' ]; then
    pass "every drift-facts/v1 key is present, in order, route first"
else
    fail "keys were $(jf keys_unsorted)"
fi
case "$FACTS" in
    '{"route":"none",'*) pass "compact JSON starting {\"route\":\"none\"," ;;
    *) fail "facts should start with {\"route\":\"none\",; got ${FACTS:0:40}" ;;
esac
if printf '%s' "$INTENT" | grep -q '^# PLAN: t$' && printf '%s' "$INTENT" | grep -q 'Touches `src/a.go`' \
    && printf '%s' "$INTENT" | grep -q -- '- Issue 1: feat: a -- Change a.'; then
    pass "plan_intent.md carries the title, Scope Summary, and outline goals"
else
    fail "plan_intent.md: $INTENT"
fi

# --- an advance outside the referenced paths ------------------------------------

fixture outside
plan "$PLAN_CODE"
upstream 'printf more >> README.md; printf b2 >> src/b.go' 'SECRET-SUBJECT-outside'
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"none"' ] && [ "$(jf .main_advanced)" = true ] \
    && [ "$(jf .overlap)" = '[]' ] && [ "$(jf .reasons)" = '["no_overlap"]' ]; then
    pass "advance outside the referenced paths: route none, no overlap"
else
    fail "advance outside: rc $RC, facts $FACTS"
fi

# --- overlap --------------------------------------------------------------------

fixture overlap
plan "$PLAN_CODE"
upstream 'printf "a4\nUNIQUE-DIFF-TEXT\n" >> src/a.go' 'SECRET-SUBJECT-overlap'
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"judge"' ] \
    && [ "$(jf .overlap)" = '[{"path":"src/a.go","status":"modified","added":2,"removed":0}]' ] \
    && [ "$(jf .reasons)" = '["overlap"]' ]; then
    pass "overlap: route judge, overlap lists src/a.go with status and line counts"
else
    fail "overlap: rc $RC, facts $FACTS"
fi
if printf '%s' "$FACTS" | grep -q 'SECRET-SUBJECT\|UNIQUE-DIFF-TEXT'; then
    fail "facts carry a commit subject or diff text: $FACTS"
else
    pass "facts carry no commit subject and no diff text"
fi

# --- deletion -------------------------------------------------------------------

fixture deletion
plan "$PLAN_CODE"
upstream 'git rm -q src/a.go' 'drop a'
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"judge"' ] && [ "$(jf .deleted_referenced_paths)" = '["src/a.go"]' ] \
    && [ "$(jf '.overlap')" = '[{"path":"src/a.go","status":"deleted","added":0,"removed":3}]' ]; then
    pass "deletion: deleted_referenced_paths lists src/a.go, route judge"
else
    fail "deletion: rc $RC, facts $FACTS"
fi

# --- rename ---------------------------------------------------------------------

fixture rename
plan "$PLAN_CODE"
upstream 'git mv src/a.go src/renamed.go' 'move a'
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"judge"' ] \
    && [ "$(jf '.overlap[0] | [.path, .status, .renamed_to]')" = '["src/a.go","renamed","src/renamed.go"]' ] \
    && [ "$(jf .deleted_referenced_paths)" = '["src/a.go"]' ]; then
    pass "rename: overlap shows renamed with renamed_to, and the old path counts as deleted"
else
    fail "rename: rc $RC, facts $FACTS"
fi

# --- a prospective path maps to its nearest existing ancestor -----------------

fixture prospective
plan '# PLAN: t

Creates `src/new/deep/thing.go`.'
upstream 'printf b2 >> src/b.go' 'touch b'
run
if [ "$(jf .referenced_paths)" = '["docs/plans/PLAN-t.md","src/"]' ] && [ "$(jf .route)" = '"judge"' ] \
    && [ "$(jf '.overlap[0].path')" = '"src/b.go"' ]; then
    pass "a path that doesn't exist yet maps to its nearest existing ancestor (src/)"
else
    fail "prospective: facts $FACTS"
fi

# --- the root-ancestor drop -----------------------------------------------------

fixture rootdrop
plan '# PLAN: t

Adds `newtop/cmd/main.go` and `CHANGELOG.md`, and edits `src/a.go`.'
upstream 'printf more >> README.md' 'touch readme'
run
if [ "$(jf .referenced_paths)" = '["docs/plans/PLAN-t.md","src/a.go"]' ] && [ "$(jf .route)" = '"none"' ]; then
    pass "a path with no existing ancestor below the root is dropped, not mapped to the root"
else
    fail "root drop: facts $FACTS"
fi

# --- the no-references rule -----------------------------------------------------

fixture norefs
plan '---
schema: plan/v1
upstream: docs/guide.md
---
# PLAN: t

## Scope Summary

Prose only. Mentions `koto`, `status: override`, and `v0.12.2`.'
run
if [ "$(jf .route)" = '"judge"' ] && [ "$(jf .reasons)" = '["no_code_references"]' ] \
    && [ "$(jf .referenced_paths)" = '["docs/guide.md","docs/plans/PLAN-t.md"]' ] && [ "$(jf .main_advanced)" = false ]; then
    pass "a PLAN naming nothing beyond itself and its upstream routes judge, even with main unmoved"
else
    fail "no references: facts $FACTS"
fi

# --- truncation -----------------------------------------------------------------

fixture truncation
(
    cd "$FX/seed" || exit 1
    i=0
    while [ "$i" -lt 150 ]; do
        printf 'x\n' > "src/file-with-a-long-name-for-truncation-$i.go"
        i=$((i + 1))
    done
    git add -A && git commit -q -m many && git push -q origin main
    cd ../repo && git pull -q origin main
) >/dev/null 2>&1
long_scope=$(awk 'BEGIN { for (i = 0; i < 300; i++) print "Scope line " i " keeps the intent long enough to need a cut." }')
plan "# PLAN: t

## Scope Summary

Edits \`src/\`.
$long_scope"
upstream 'for f in src/file-with-a-long-name-for-truncation-*.go; do printf y >> "$f"; done' 'touch many'
run
fbytes=$(printf '%s' "$FACTS" | wc -c | tr -d ' ')
ibytes=$(wc -c < "$SHIM_STORE/$SESS/plan_intent.md" | tr -d ' ')
if [ "$RC" -eq 0 ] && [ "$fbytes" -le 8192 ] && [ "$(jf .truncated)" = true ] && [ "$(jf .route)" = '"judge"' ] \
    && [ "$(jf '.reasons | index("truncated") != null')" = true ]; then
    pass "a payload over 8192 bytes is cut to $fbytes bytes, marked truncated, and routes judge"
else
    fail "truncation: rc $RC, $fbytes bytes, truncated $(jf .truncated), route $(jf .route)"
fi
if [ "$ibytes" -le 8192 ] && printf '%s' "$INTENT" | grep -q 'plan intent truncated'; then
    pass "plan_intent.md is cut to $ibytes bytes and marked"
else
    fail "plan_intent.md is $ibytes bytes"
fi

# --- wip/ exclusion -------------------------------------------------------------

fixture wip
plan '# PLAN: t

Reads `wip/notes.md` and edits `src/a.go`.

**Files**: `wip/notes.md`'
upstream 'printf more >> wip/notes.md' 'touch wip'
run
if [ "$(jf .referenced_paths)" = '["docs/plans/PLAN-t.md","src/a.go"]' ] && [ "$(jf .route)" = '"none"' ]; then
    pass "wip/ paths are never references, so a wip/ change is not drift"
else
    fail "wip exclusion: facts $FACTS"
fi

# --- line and anchor suffixes -----------------------------------------------------
#
# `src/b.go` is a second code reference, so without the suffix fix the run
# would route none: the deletion of src/a.go would go unseen.

fixture linesuffix
plan '# PLAN: t

Edits `src/a.go:1` and `src/b.go`.'
upstream 'git rm -q src/a.go' 'drop a'
run
if [ "$RC" -eq 0 ] && [ "$(jf .route)" = '"judge"' ] && [ "$(jf .deleted_referenced_paths)" = '["src/a.go"]' ]; then
    pass "a token with a :line suffix keeps its base path, so deleting it routes judge"
else
    fail "line suffix: rc $RC, facts $FACTS"
fi

fixture suffixshapes
plan '# PLAN: t

Tokens: `src/a.go:10-20`, `src/b.go#L10`, `docs/guide.md:3,4`, `README.md#L1-L9`.'
run
if [ "$(jf ".referenced_paths | sort")" = '["README.md","docs/guide.md","docs/plans/PLAN-t.md","src/a.go","src/b.go"]' ]; then
    pass "the :a-b, :a,b, #La, and #La-Lb suffixes are stripped to the base path"
else
    fail "suffix shapes: facts $FACTS"
fi

# --- rejected token shapes ------------------------------------------------------

fixture rejected
plan '# PLAN: t

Tokens: `src/{{NAME}}.go`, `$HOME/src/a.go`, `src/*.go`, `https://example.com/src/a.go`, `docs/guide.md`.'
upstream 'printf a4 >> src/a.go' 'touch a'
run
if [ "$(jf .referenced_paths)" = '["docs/guide.md","docs/plans/PLAN-t.md"]' ] && [ "$(jf .overlap)" = '[]' ]; then
    pass "tokens containing {{, \$, *, or :// are rejected"
else
    fail "rejected shapes: facts $FACTS"
fi

# --- cross-repo upstream skipping ----------------------------------------------

fixture crossrepo
plan '---
schema: plan/v1
upstream:
  - owner/other:src/a.go
  - docs/guide.md
---
# PLAN: t

Edits `src/b.go`.'
upstream 'printf a4 >> src/a.go' 'touch a'
run
if [ "$(jf .referenced_paths)" = '["docs/guide.md","docs/plans/PLAN-t.md","src/b.go"]' ] && [ "$(jf .route)" = '"none"' ] \
    && printf '%s' "$INTENT" | grep -q -- '- owner/other:src/a.go'; then
    pass "a cross-repo upstream is skipped as a reference and still listed in the intent"
else
    fail "cross-repo: facts $FACTS"
fi

# --- a branch-only PLAN whose fork point is behind origin/main -----------------
#
# The PLAN exists only on the branch, and main moved after the fork. The base
# must be the fork point, so the change to src/a.go shows up.

fixture branchonly
fork=$(cd "$FX/repo" && git rev-parse HEAD)
plan "$PLAN_CODE"
upstream 'printf a4 >> src/a.go' 'touch a'
run
if [ "$(jf .base)" = "\"$fork\"" ] && [ "$(jf .route)" = '"judge"' ] && [ "$(jf '.overlap[0].path')" = '"src/a.go"' ] \
    && [ "$(jf .commits_since_base)" = 1 ]; then
    pass "branch-only PLAN: the base is the fork point, so main's change after it is seen"
else
    fail "branch-only: fork $fork, facts $FACTS"
fi

# The same PLAN untracked: the base falls back to merge-base(HEAD, origin/main).
fixture untracked
fork=$(cd "$FX/repo" && git rev-parse HEAD)
mkdir -p "$FX/repo/docs/plans"
printf '%s\n' "$PLAN_CODE" > "$FX/repo/docs/plans/PLAN-t.md"
upstream 'printf a4 >> src/a.go' 'touch a'
run
if [ "$RC" -eq 0 ] && [ "$(jf .base)" = "\"$fork\"" ] && [ "$(jf .route)" = '"judge"' ]; then
    pass "untracked PLAN: the base is merge-base(HEAD, origin/main)"
else
    fail "untracked: rc $RC, facts $FACTS"
fi

# --- exit codes -----------------------------------------------------------------

fixture exits
plan "$PLAN_CODE"

o=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" 2>/dev/null); rc=$?
o2=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" only-session 2>/dev/null); rc2=$?
if [ "$rc" -eq 67 ] && [ "$rc2" -eq 67 ] && [ -z "$o$o2" ]; then
    pass "a missing argument exits 67"
else
    fail "missing argument: exits $rc and $rc2"
fi

o=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" s65 docs/plans/PLAN-absent.md 2>/dev/null); rc=$?
printf 'x\n' > "$WORKDIR/PLAN-outside.md"
o2=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" s65b "$WORKDIR/PLAN-outside.md" 2>/dev/null); rc2=$?
if [ "$rc" -eq 65 ] && [ "$rc2" -eq 65 ] && [ -z "$o$o2" ] && [ ! -d "$SHIM_STORE/s65" ]; then
    pass "a missing PLAN, or one outside the repository, exits 65 and writes nothing"
else
    fail "PLAN errors: exits $rc and $rc2"
fi

(cd "$FX/repo" && git remote set-url origin "$WORKDIR/no-such-origin.git") >/dev/null 2>&1
o=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" s64 docs/plans/PLAN-t.md 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ -z "$o" ] && [ ! -d "$SHIM_STORE/s64" ]; then
    pass "a failed fetch (no base) exits 64 and writes nothing"
else
    fail "failed fetch: exit $rc"
fi

# A rewind back into drift_facts: keys from the earlier run must not survive a
# failed recompute, or the stale route:none would satisfy the gates.
mkdir -p "$SHIM_STORE/s-stale"
printf '{"route":"none","schema":"drift-facts/v1"}' > "$SHIM_STORE/s-stale/drift_facts.json"
printf '# PLAN: stale\n' > "$SHIM_STORE/s-stale/plan_intent.md"
o=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" s-stale docs/plans/PLAN-t.md 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ ! -e "$SHIM_STORE/s-stale/drift_facts.json" ] && [ ! -e "$SHIM_STORE/s-stale/plan_intent.md" ]; then
    pass "a failed recompute removes drift_facts.json and plan_intent.md left by an earlier run"
else
    fail "stale keys: exit $rc, left [$(ls "$SHIM_STORE/s-stale" 2>/dev/null | tr '\n' ' ')]"
fi
(cd "$FX/repo" && git remote set-url origin "$FX/origin.git") >/dev/null 2>&1

NOREMOTE="$WORKDIR/noremote"
mkdir -p "$NOREMOTE/docs/plans"
(cd "$NOREMOTE" && git init -q . && printf '%s\n' "$PLAN_CODE" > docs/plans/PLAN-t.md && git add -A && git commit -q -m x) >/dev/null 2>&1
o=$(cd "$NOREMOTE" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" s64b docs/plans/PLAN-t.md 2>/dev/null); rc=$?
if [ "$rc" -eq 64 ] && [ -z "$o" ]; then
    pass "a repository with no origin exits 64"
else
    fail "no origin: exit $rc"
fi

run fail-write
if [ "$RC" -eq 66 ] && [ -z "$OUT" ] && grep -q 'koto context add failed' "$WORKDIR/stderr"; then
    pass "a failed context write exits 66, with the diagnostic on stderr"
else
    fail "failed write: exit $RC, stdout [$OUT]"
fi

# --- route first, so the template's gate patterns match -----------------------
#
# The patterns are read out of the shipped template rather than copied, so a
# change to either side breaks this case.

fixture patterns
plan "$PLAN_CODE"
run
none_facts=$FACTS
upstream 'printf a4 >> src/a.go' 'touch a'
run
judge_facts=$FACTS
recorded_pat=$(awk '/drift_facts_recorded:/ { f = 1 } f && /pattern:/ { sub(/^[^\047]*\047/, ""); sub(/\047[^\047]*$/, ""); print; exit }' "$TEMPLATE")
clear_pat=$(awk '/drift_clear:/ { f = 1 } f && /pattern:/ { sub(/^[^\047]*\047/, ""); sub(/\047[^\047]*$/, ""); print; exit }' "$TEMPLATE")
if [ -n "$recorded_pat" ] && [ -n "$clear_pat" ] \
    && printf '%s' "$none_facts" | grep -Eq "$recorded_pat" && printf '%s' "$judge_facts" | grep -Eq "$recorded_pat" \
    && printf '%s' "$none_facts" | grep -Eq "$clear_pat" && ! printf '%s' "$judge_facts" | grep -Eq "$clear_pat"; then
    pass "drift_facts_recorded matches both routes; drift_clear matches none and not judge"
else
    fail "gate patterns [$recorded_pat] [$clear_pat] against [${none_facts:0:30}] [${judge_facts:0:30}]"
fi

# --- engine cases ---------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

# koto validates --var values against ^[a-zA-Z0-9._/:@ \-]*$; a checkout path
# may not be inside that set, so the plugin root is reached through a clean
# symlink when it isn't, and, when the temp tree is not clean either, through a
# copy of the template with the real path written where {{PLUGIN_ROOT}} stood.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        case "$WORKDIR/plugin" in
            *[!a-zA-Z0-9._/:@\ -]*)
                mkdir -p "$WORKDIR/derived/skills/execute/koto-templates"
                ln -s "$PLUGIN_ROOT/skills/work-on" "$WORKDIR/derived/skills/work-on"
                sed "s#{{PLUGIN_ROOT}}#$PLUGIN_ROOT#g" "$TEMPLATE" \
                    > "$WORKDIR/derived/skills/execute/koto-templates/execute.md"
                TEMPLATE="$WORKDIR/derived/skills/execute/koto-templates/execute.md"
                PLUGIN_ROOT=/koto-probe
                echo "  note: running a copy of execute.md with the plugin path written in (no allowlist-clean path exists)"
                ;;
            *) PLUGIN_ROOT="$WORKDIR/plugin" ;;
        esac
        ;;
esac

STATE=""
tick() {
    # $1 session, $2 data (optional)
    local resp
    if [ -n "${2:-}" ]; then
        resp=$(cd "$FX/repo" && koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        resp=$(cd "$FX/repo" && koto next "$1" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$resp" | jq -r '.state // empty' 2>/dev/null)
}

start() {
    # $1 fixture/slug; the PLAN is committed on the branch only. The first bare
    # tick runs write_set_record, the initial state, and stops at
    # orchestrator_setup, where each case submits its evidence.
    (cd "$FX/repo" && koto init "execute-$1" --template "$TEMPLATE" \
        --var PLAN_DOC=docs/plans/PLAN-t.md --var PLAN_SLUG="$1" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1 \
        && koto next "execute-$1" --no-cleanup >/dev/null 2>&1)
}

# No drift: one override tick at orchestrator_setup reaches spawn_and_await.
fixture e-nodrift
plan "$PLAN_CODE"
upstream 'printf more >> README.md' 'touch readme'
start e-nodrift
tick execute-e-nodrift '{"status":"override"}'
facts=$(cd "$FX/repo" && koto context get execute-e-nodrift drift_facts.json 2>/dev/null)
if [ "$STATE" = "spawn_and_await" ]; then
    pass "no drift: one override tick at orchestrator_setup reaches spawn_and_await"
else
    fail "no drift: stopped at [$STATE]"
fi
case "$facts" in
    '{"route":"none",'*) pass "no drift: drift_facts.json starts with {\"route\":\"none\"," ;;
    *) fail "no drift: facts [${facts:0:60}]" ;;
esac
if (cd "$FX/repo" && git merge-base --is-ancestor origin/main HEAD); then
    pass "after drift_facts and worktree_sync, origin/main is an ancestor of HEAD"
else
    fail "origin/main is not an ancestor of HEAD after the run"
fi
if (cd "$FX/repo" && git log --format=%s -1 origin/main | grep -q 'touch readme'); then
    pass "the origin/main that was rebased onto is the one drift_facts fetched"
else
    fail "origin/main in the run's clone does not carry the upstream commit"
fi

# Overlap: the run stops at worktree_discipline_check, and informational goes on.
fixture e-overlap
plan "$PLAN_CODE"
upstream 'printf a4 >> src/a.go' 'touch a'
start e-overlap
tick execute-e-overlap '{"status":"override"}'
facts=$(cd "$FX/repo" && koto context get execute-e-overlap drift_facts.json 2>/dev/null)
if [ "$STATE" = "worktree_discipline_check" ] \
    && [ "$(printf '%s' "$facts" | jq -c '[.overlap[].path]')" = '["src/a.go"]' ]; then
    pass "overlap: the run stops at worktree_discipline_check with src/a.go in overlap"
else
    fail "overlap: state [$STATE], facts [$facts]"
fi
if (cd "$FX/repo" && koto context exists execute-e-overlap plan_intent.md) >/dev/null 2>&1; then
    pass "overlap: plan_intent.md exists when the question is asked"
else
    fail "overlap: plan_intent.md is missing at worktree_discipline_check"
fi
tick execute-e-overlap '{"impact":"informational"}'
if [ "$STATE" = "spawn_and_await" ]; then
    pass "overlap: impact informational reaches spawn_and_await"
else
    fail "overlap: informational reached [$STATE]"
fi

# Deletion: the run stops at the question, and intent-changing ends the run.
fixture e-deletion
plan "$PLAN_CODE"
upstream 'git rm -q src/a.go' 'drop a'
start e-deletion
tick execute-e-deletion '{"status":"override"}'
facts=$(cd "$FX/repo" && koto context get execute-e-deletion drift_facts.json 2>/dev/null)
if [ "$STATE" = "worktree_discipline_check" ] \
    && [ "$(printf '%s' "$facts" | jq -c .deleted_referenced_paths)" = '["src/a.go"]' ]; then
    pass "deletion: the run stops at worktree_discipline_check with src/a.go deleted"
else
    fail "deletion: state [$STATE], facts [$facts]"
fi
tick execute-e-deletion '{"impact":"intent-changing","rationale":"src/a.go is gone"}'
if [ "$STATE" = "done_blocked" ]; then
    pass "deletion: impact intent-changing with a rationale ends at done_blocked"
else
    fail "deletion: intent-changing reached [$STATE]"
fi

# The question offers exactly two answers.
fixture e-values
plan "$PLAN_CODE"
upstream 'printf a4 >> src/a.go' 'touch a'
start e-values
resp=$(cd "$FX/repo" && koto next execute-e-values --with-data '{"status":"override"}' --no-cleanup 2>/dev/null)
if [ "$(printf '%s' "$resp" | jq -c '.expects.fields.impact.values')" = '["informational","intent-changing"]' ]; then
    pass "worktree_discipline_check offers exactly informational and intent-changing"
else
    fail "impact values: $(printf '%s' "$resp" | jq -c '.expects.fields.impact' 2>/dev/null)"
fi
(cd "$FX/repo" && koto next execute-e-values --with-data '{"impact":"none"}' --no-cleanup >/dev/null 2>&1)
if [ $? -ne 0 ]; then
    pass "impact none is refused: the script owns that answer"
else
    fail "impact none was accepted"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
