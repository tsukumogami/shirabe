#!/usr/bin/env bash
# terminal-retention_test.sh -- the orchestrator's terminal tick keeps its record
# Part of the execute skill
#
# koto deletes a session on the tick that reaches a terminal state, and the
# deletion takes the session's `ctx/` with it. `/execute` ends at `done_blocked`
# when the chain cannot proceed and at `paused_for_review` when an interactive
# run hands a DRAFT PR back for review; both lose their context without
# `koto next --no-cleanup` (#360). The second is the worse loss -- a pause is
# solicited, and what dies with it is what a resume reads.
#
# `/execute` passes the flag unconditionally, where `/work-on` has to decide per
# run. That is sound only while an orchestrator session is always a root, so this
# harness checks the premise rather than trusting it. Case groups, in execution
# order -- deliberately not numbered, because a numbered map goes stale the first
# time a case is inserted and then misdirects the reader it was written for:
#
#   engine-free, so they also run on the bash 3.2 floor where koto is absent:
#     nothing in the corpus names execute.md as a child template (the tripwire)
#     SKILL.md and the template frontmatter both state the rule
#     every koto next command line in the template carries the flag
#     escalate still has the shape that chains
#
#   engine-backed, against the SHIPPED execute.md (or, in a checkout whose path
#   koto's --var allowlist refuses, a copy with that path written in):
#     the blocked terminal keeps its context, and a control without the flag
#     the PAUSE terminal keeps its context, and a control
#     retention does not block the resume it exists to protect: a plain init
#       is refused, and koto-open.sh --replace-terminal replaces the session
#     each terminal's result payload (outcome, step, reason), walked along
#       declared edges to merged, ready_awaiting_merge, the DIRTY done_blocked,
#       a verdict-error done_blocked, and paused_for_review, each with a
#       no-flag control
#     the merge step on the engine: a PR still OPEN after the merge call ends
#       merge-not-observed; a run resumed at merge_attempt without --merge ends
#       merge-not-requested with no pr merge; overrides on merge_route's and
#       merge_confirm's gates are refused and the run doesn't reach merged
#     the chain itself, driven in both directions on a minimal template
#
#   The engine-backed cases drive the real verdict scripts: a `gh` stub on PATH
#   serves the PR, its checks, and its base's rules, and koto hands that PATH to
#   the actions it runs.
#
# The tripwire matters most: if a future change makes `/execute` spawnable as a
# child, the unconditional flag would withhold its result from its parent, as
# references/koto-session-retention.md documents, and that case says so before
# it ships.
#
# The pause cases walk the declared edges with `koto next --to`, because reaching
# pr_finalization by evidence alone would mean satisfying the children-complete
# gate with real children -- a great deal of machinery to assert something about
# the tick that LEAVES the state, not about how it was entered. Every hop is a
# declared transition; koto refuses an undeclared one, so the walk cannot drift
# from the template's own graph without failing.
#
# Usage: terminal-retention_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the run skipped
#   1 -- one or more cases failed
#
# A missing koto exits 0 with a loud SKIP, matching settled-branch-record_test.sh:
# the Linux leg of check-execute-scripts.yml installs koto through the project
# tool manifest so the assertions genuinely run, and the macOS leg is the bash
# 3.2 floor check, where failing on absence would red the leg for a reason that
# has nothing to do with what it checks.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILLS_DIR=$(cd "$SKILL_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

REPO_ROOT=$(cd "$SKILLS_DIR/.." && pwd)
WORK_ON_TPL="skills/work-on/koto-templates/work-on.md"

# Every `koto next` inside a fenced code block, at any indentation and inside
# `$(...)`, excluding shell-comment lines. Prints "line: text". This is the one
# definition of "a tick" in this suite; both the template count and the
# orchestrator walk use it, so they cannot disagree about what they are counting.
fenced_ticks() {
    awk '
        /^[[:space:]]*```/ { inblk = !inblk; next }
        inblk && /koto next / {
            t = $0; sub(/^[[:space:]]+/, "", t)
            if (t ~ /^#/) next
            printf "%d: %s\n", NR, $0
        }' "$1"
}
raw_cites() { grep -oE '(skills|references)/[A-Za-z0-9_/.-]*\.md' "$1" 2>/dev/null | sort -u; }
resolve() { # $1 citation, $2 citing file (repo-relative) -> repo-relative path, or nothing
    [ -f "$REPO_ROOT/$1" ] && { echo "$1"; return; }
    case "$2" in
        skills/*) sd=$(printf '%s' "$2" | cut -d/ -f1-2)
                  [ -f "$REPO_ROOT/$sd/$1" ] && echo "$sd/$1" ;;
    esac
}

# --- the engine-free cases, which run before the koto skip -------------------
#
# The premise behind /execute's unconditional flag: nothing materializes
# execute.md as a child.
#
# Three routes, not one. `default_template` is what /execute uses for its own
# children; a per-task `template:` field overrides it per child; and a session
# started under an explicit parent makes a child of any template at all.
#
# The scan covers every markdown file under skills/, not just templates and
# SKILL.md: this repo puts `koto init` in references/phases too (see
# skills/scope/references/phases/phase-0-setup.md), so a narrower scan would
# report a guarantee it had not checked. It still cannot see a `koto init
# --parent` issued from outside this repo, which is the residual blind spot --
# the premise this case asserts is "nothing in the shirabe corpus spawns
# execute.md as a child", not "koto could not be made to".
#
# The awk drops the `path:line:` prefix before matching, or every hit inside
# execute.md would match on its own filename.
CHILD_DECLS=$(grep -rn 'default_template:\|template:\|--parent' \
        --include='*.md' "$SKILLS_DIR" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*: *#' \
    | grep -v '/evals/' \
    | awk -F: '{ line = $0; sub(/^[^:]*:[0-9]*:/, "", line); if (line ~ /execute\.md/) print $0 }')
if [ -z "$CHILD_DECLS" ]; then
    pass "nothing names execute.md as a child template, so an orchestrator session is always a root"
else
    fail "execute.md is named as a child template, so /execute can now run as a child and its unconditional --no-cleanup would block the parent's converge:
$CHILD_DECLS"
fi

if grep -q -- '--no-cleanup' "$SKILL_MD"; then
    pass "SKILL.md states the terminal-tick retention rule"
else
    fail "SKILL.md must state that the orchestrator's koto next carries --no-cleanup"
fi

# execute.md's own note. Unlike work-on.md the flag is not forbidden here, but a
# terminal-reaching `koto next` added to this template must carry it, and the
# only thing that will tell a future editor so is the note. This is the template
# half of the issue's "say why the flag is there" criterion.
if grep -q '^# *Terminal-tick retention' "$TEMPLATE"; then
    pass "execute.md's frontmatter records why the flag rides every tick and what a new terminal-reaching tick must do"
else
    fail "execute.md has no frontmatter note explaining the retention rule to a template editor"
fi

# Every koto next command line in this template must carry the flag. An earlier
# version of this suite asserted the opposite for spawn_and_await's two ticks, on
# the false premise that a state declaring `accepts` cannot be chained through.
# Counted with the same shape-aware matcher as the walk below -- fenced, any
# indentation, inside $(...) -- not a column-0 grep, which would miss an indented
# tick and report a smaller denominator than the template really has.
TEMPLATE_TICKS=$(fenced_ticks "$TEMPLATE" | grep -c .)
TEMPLATE_TICKS_FLAGGED=$(fenced_ticks "$TEMPLATE" | grep -c -- '--no-cleanup')
if [ "$TEMPLATE_TICKS" -gt 0 ] && [ "$TEMPLATE_TICKS" -eq "$TEMPLATE_TICKS_FLAGGED" ]; then
    pass "every koto next command line in execute.md carries --no-cleanup ($TEMPLATE_TICKS of $TEMPLATE_TICKS)"
else
    fail "execute.md has $TEMPLATE_TICKS koto next command lines but only $TEMPLATE_TICKS_FLAGGED carry --no-cleanup. A tick keeps advancing while the next transition needs no evidence, so a tick that looks non-terminal can still chain into one."
fi

# The orchestrator's ticks are not all in execute.md. A state directive can send
# the agent to another file for the command to run, and that command is an
# orchestrator tick exactly as much as one written inline. Counting only
# execute.md's own lines is how phase-2.5's bare intent-changing tick -- which
# chains through escalate_upstream_drift into done_blocked -- went unflagged.
#
# What this scan covers, stated exactly so nothing relies on more:
#
#   the ticks  every `koto next` inside a fenced code block, at any indentation
#              and inside `$(...)`, excluding shell-comment lines. A tick written
#              only as inline code in prose is not treated as one.
#   the files  execute.md and skills/execute/SKILL.md, then every file reachable
#              from them by citation, transitively. Citations are resolved as
#              repo-rooted first, then relative to the citing skill.
#   bounded to the files /execute's orchestrator can be sent to: /execute's own
#              tree, repo-root references/, and /work-on's reference files --
#              but NOT /work-on's phase files that work-on.md itself cites. Those
#              are the child's instructions, and their ticks are correctly bare.
#              Other skills' trees are not entered: shared references cite them
#              as examples, not as commands the orchestrator runs.
#
# A citation that resolves to nothing is not followed, and is reported.

# The child's own phase files: the /work-on phase files work-on.md sends a child to.
CHILD_PHASES=" "
for c in $(raw_cites "$REPO_ROOT/$WORK_ON_TPL"); do
    r=$(resolve "$c" "$WORK_ON_TPL")
    case "$r" in skills/work-on/references/phases/*) CHILD_PHASES="$CHILD_PHASES$r " ;; esac
done

orchestrator_reachable() { # $1 candidate -> 0 if the walk may enter it
    case "$CHILD_PHASES" in *" $1 "*) return 1 ;; esac
    case "$1" in
        references/*.md)                 return 0 ;;
        skills/execute/*)                return 0 ;;
        skills/work-on/references/*)     return 0 ;;
        *)                               return 1 ;;
    esac
}

WALK_QUEUE="skills/execute/koto-templates/execute.md skills/execute/SKILL.md"
WALK_SEEN=""
WALK_UNRESOLVED=""
WALK_SHARED=" "
while [ -n "$WALK_QUEUE" ]; do
    set -- $WALK_QUEUE; cur="$1"; shift; WALK_QUEUE="$*"
    case " $WALK_SEEN " in *" $cur "*) continue ;; esac
    WALK_SEEN="$WALK_SEEN $cur"
    for c in $(raw_cites "$REPO_ROOT/$cur"); do
        r=$(resolve "$c" "$cur")
        if [ -z "$r" ]; then WALK_UNRESOLVED="$WALK_UNRESOLVED
  $cur -> $c"; continue; fi
        # A file the orchestrator is sent to that is ALSO one of the child's phase
        # files has two readers with opposite needs. Record it; it is checked below.
        case "$CHILD_PHASES" in *" $r "*) WALK_SHARED="$WALK_SHARED$r " ;; esac
        orchestrator_reachable "$r" && WALK_QUEUE="$WALK_QUEUE $r"
    done
done

WALK_BARE=""
for f in $WALK_SEEN; do
    bare=$(fenced_ticks "$REPO_ROOT/$f" | grep -v -- '--no-cleanup')
    [ -n "$bare" ] && WALK_BARE="$WALK_BARE
$f:
$bare"
done
WALK_COUNT=$(echo $WALK_SEEN | wc -w | tr -d ' ')
if [ -z "$WALK_BARE" ]; then
    pass "every fenced koto next in the $WALK_COUNT files the orchestrator can be sent to carries --no-cleanup"
else
    fail "a file the orchestrator can be sent to carries a bare koto next -- a bare tick that chains into a terminal destroys its record:$WALK_BARE"
fi

# Sanity on the walk itself: it has to have reached the file whose miss started
# this, or a change to how citations are written has quietly shrunk it.
case " $WALK_SEEN " in
    *" skills/work-on/references/phases/phase-2.5-worktree-discipline.md "*)
        pass "the walk reaches phase-2.5, the orchestrator-only /work-on file" ;;
    *)  fail "the walk no longer reaches phase-2.5 -- citation resolution changed and the scan has shrunk" ;;
esac
# An unresolved citation fails rather than being noted. A file the orchestrator
# is told to read that the walk cannot find is a file it cannot scan -- exactly
# the hole this whole scan exists to close. The case that proved it: execute.md
# cited /work-on's phase-6-pr.md by a path relative to /work-on, inherited when
# the orchestrator was lifted out of it, so the orchestrator was sent to a file
# nothing checked.
if [ -z "$WALK_UNRESOLVED" ]; then
    pass "every citation in the orchestrator's files resolves, so nothing it is sent to escapes the scan"
else
    fail "a file the orchestrator reads cites a path that resolves to no file, so the scan cannot see it (write it repo-rooted):$WALK_UNRESOLVED"
fi

# A file read by BOTH the orchestrator and a child cannot carry a tick at all:
# the orchestrator would need it flagged and a child needs it bare, and no one
# line can be both. Resolving that by judgement fails the next person to add a
# tick there, who will not know the file has two readers -- so it is a check.
SHARED_TICKS=""
for f in $WALK_SHARED; do
    t=$(fenced_ticks "$REPO_ROOT/$f")
    [ -n "$t" ] && SHARED_TICKS="$SHARED_TICKS
$f:
$t"
done
SHARED_COUNT=$(echo $WALK_SHARED | wc -w | tr -d ' ')
if [ -z "$SHARED_TICKS" ]; then
    pass "the $SHARED_COUNT file(s) read by both the orchestrator and a child carry no koto next tick"
else
    fail "a file read by both the orchestrator and a child carries a koto next tick, which cannot be right for both (flagged for the orchestrator, bare for a child). Move the command into a file only one of them reads:$SHARED_TICKS"
fi

# The mechanism behind that rule, pinned so nobody reinstates the carve-out on
# the reasoning that was wrong the first time: a state halts an auto-advance
# chain only if it declares at least one CONDITIONAL transition. Declaring
# `accepts` halts nothing, so a state can require evidence and still be chained
# straight through to a terminal.
ESCALATE_BLOCK=$(sed -n '/^  escalate:/,/^  [a-z_]*:$/p' "$TEMPLATE")
if printf '%s' "$ESCALATE_BLOCK" | grep -q 'accepts:' \
   && printf '%s' "$ESCALATE_BLOCK" | grep -q 'target: done_blocked' \
   && ! printf '%s' "$ESCALATE_BLOCK" | grep -q 'when:'; then
    pass "escalate still declares accepts and reaches done_blocked unconditionally -- the shape that chains, which is why spawn_and_await's ticks are flagged"
else
    fail "escalate's shape changed. Re-derive whether spawn_and_await's ticks can still chain into a terminal before trusting the flag count above; do NOT conclude from 'it accepts evidence' that it cannot."
fi


skip_engine_cases() {
    echo
    echo "SKIP: $1 -- the engine-backed cases did not run"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}

command -v koto >/dev/null 2>&1 || skip_engine_cases "koto not on PATH"
# jq skips rather than failing, matching koto. A runner with koto but no jq is
# an environment gap, not a defect in what this suite tests, and the Linux leg
# installs both so the cases genuinely run where it matters.
command -v jq >/dev/null 2>&1 || skip_engine_cases "jq not on PATH"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/terminal-retention.XXXXXX")
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Keep every session this harness creates out of the developer's real ~/.koto.
# This suite retains sessions on purpose, so it would leave more behind than most.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# The merge confirm read polls for up to 20 s by default; no case here needs to
# wait for a merge to land.
export MERGE_CONFIRM_WAIT_SECS=0

# --- the fixture the sessions run in ------------------------------------------
#
# koto binds a session to the directory `koto init` ran in and runs every action
# there, so each session opens in a small fixture repository. Its origin names a
# GitHub repository (never fetched), which is what write_set_record, the
# template's initial state, reads to record the write set `o/r`.
FIXREPO="$WORKDIR/repo"
mkdir -p "$FIXREPO"
(
    cd "$FIXREPO" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git commit -q --allow-empty -m init
    git checkout -q -b impl/probe
    git remote add origin https://github.com/o/r.git
) >/dev/null 2>&1
k() { (cd "$FIXREPO" && koto "$@"); }

# --- the plugin root ------------------------------------------------------------
#
# koto validates a variable's value against ^[a-zA-Z0-9._/:@ \-]*$, and a
# checkout under a directory with a `+` in it fails that. The actions these cases
# run (the write set, the verdict, the confirm read) live in the plugin, so the
# plugin root has to be real: this checkout's path when it is clean, a symlink in
# the temp tree when that is clean, and otherwise -- a temp tree that is itself
# under such a directory -- a copy of the template with this checkout's path
# written where {{PLUGIN_ROOT}} stood, under a stand-in PLUGIN_ROOT. The copy is
# the one departure from "the shipped template", and the note says so.
KOTO_ALLOW='^[a-zA-Z0-9._/:@ -]*$'
TPL="$TEMPLATE"
if [[ $REPO_ROOT =~ $KOTO_ALLOW ]]; then
    PLUGIN_ROOT_VAR="$REPO_ROOT"
else
    ln -s "$REPO_ROOT" "$WORKDIR/plugin"
    if [[ $WORKDIR/plugin =~ $KOTO_ALLOW ]]; then
        PLUGIN_ROOT_VAR="$WORKDIR/plugin"
    else
        mkdir -p "$WORKDIR/derived/skills/execute/koto-templates"
        ln -s "$REPO_ROOT/skills/work-on" "$WORKDIR/derived/skills/work-on"
        TPL="$WORKDIR/derived/skills/execute/koto-templates/execute.md"
        sed "s#{{PLUGIN_ROOT}}#$REPO_ROOT#g" "$TEMPLATE" > "$TPL"
        PLUGIN_ROOT_VAR=/koto-probe
        echo "  note: this checkout's path is outside koto's --var allowlist, so these cases run a"
        echo "        copy of execute.md with the path written in for {{PLUGIN_ROOT}}"
    fi
fi

# --- a gh stub, for the verdict and confirm reads -----------------------------
#
# Serves $GH_FIX/<key>.out / .rc, a numbered file (<key>.out.N, <key>.rc.N)
# answering the Nth call to a key, and logs every call. koto hands its PATH to
# the actions it runs, so the verdict scripts reach this stub, never GitHub.
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
fix="${GH_FIX:?}"
printf '%s\n' "$*" >> "$fix/gh.log"
key=unknown
case "$1 ${2:-}" in
    "api user") key=user ;;
    "pr list") key=list ;;
    "pr merge") key=merge ;;
    "pr view")
        case " $* " in *" --json state "*) key=confirm ;; *) key=view ;; esac ;;
    "pr checks") key=checks ;;
    "api "*)
        case "$2" in
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*) key=commit ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*) key=repo ;;
        esac ;;
esac
n=0; [ -f "$fix/$key.count" ] && n=$(cat "$fix/$key.count"); n=$((n + 1)); echo "$n" > "$fix/$key.count"
out="$fix/$key.out"; [ -f "$fix/$key.out.$n" ] && out="$fix/$key.out.$n"
rcf="$fix/$key.rc"; [ -f "$fix/$key.rc.$n" ] && rcf="$fix/$key.rc.$n"
[ -f "$out" ] || [ -f "$rcf" ] || { echo "gh stub: no fixture for [$key]" >&2; exit 1; }
[ -f "$out" ] && cat "$out"
rc=0; [ -f "$rcf" ] && rc=$(cat "$rcf")
exit "$rc"
STUB
chmod +x "$WORKDIR/bin/gh"
export PATH="$WORKDIR/bin:$PATH"

HEAD_SHA=1111111111111111111111111111111111111111
PR_URL="https://github.com/o/r/pull/7"

# gh_fixture <name> — a fresh fixture set for one session: an owned PR on
# impl/probe that is mergeable by squash at HEAD_SHA, and a confirm read that
# reports MERGED. Cases edit the files they are about.
gh_fixture() {
    GH_FIX="$WORKDIR/gh/$1"
    export GH_FIX
    rm -rf "$GH_FIX"; mkdir -p "$GH_FIX"; : > "$GH_FIX/gh.log"
    echo '{"login":"octo"}' > "$GH_FIX/user.out"
    echo '{"default_branch":"main","allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true}' > "$GH_FIX/repo.out"
    jq -nc --arg url "$PR_URL" '[{url: $url, state: "OPEN", isCrossRepository: false,
        author: {login: "octo"}, baseRefName: "main", headRefName: "impl/probe"}]' > "$GH_FIX/list.out"
    jq -nc --arg head "$HEAD_SHA" '{state: "OPEN", isDraft: false, mergeStateStatus: "CLEAN",
        reviewDecision: "", headRefOid: $head, baseRefName: "main", changedFiles: 1,
        commits: [{oid: $head, committedDate: ((now - 600) | todate)}]}' > "$GH_FIX/view.out"
    echo '[{"name":"build","bucket":"pass"}]' > "$GH_FIX/checks.out"
    echo '{"name":"main","protected":false}' > "$GH_FIX/branch.out"
    echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"build"}]}}]' > "$GH_FIX/rules.out"
    echo '[{"filename":"src/main.go"}]' > "$GH_FIX/files.out"
    echo '{"state":"MERGED"}' > "$GH_FIX/confirm.out"
}
gh_fixture default

# init_orchestrator <slug> [MERGE] — open execute-<slug> the way the session is
# named in production (the actions rebuild the name as execute-{{PLAN_SLUG}}),
# and take the first tick, which runs write_set_record and lands on
# orchestrator_setup. A session that did not get there fails the suite rather
# than letting later assertions prove nothing.
init_orchestrator() {
    local s="execute-$1" merge="${2:-false}" st
    k init "$s" --template "$TPL" \
        --var PLAN_DOC="docs/plans/PLAN-$1.md" \
        --var PLAN_SLUG="$1" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" \
        --var PAUSE_BEFORE_FINALIZE=false \
        --var MERGE="$merge" >/dev/null 2>&1
    if ! k status "$s" >/dev/null 2>&1; then
        echo "FAIL: koto init did not produce session '$s' -- the engine-backed cases cannot run" >&2
        k init "$s" --template "$TPL" --var PLAN_DOC="docs/plans/PLAN-$1.md" --var PLAN_SLUG="$1" \
            --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var PAUSE_BEFORE_FINALIZE=false --var MERGE="$merge" 2>&1 | tail -2 >&2
        exit 1
    fi
    printf 'the orchestrator record\n' | k context add "$s" summary.md >/dev/null 2>&1
    k next "$s" --no-cleanup >/dev/null 2>&1
    st=$(k status "$s" 2>/dev/null | jq -r '.current_state // "gone"')
    if [ "$st" != "orchestrator_setup" ]; then
        echo "FAIL: the first tick of '$s' stopped at '$st', not orchestrator_setup -- write_set_record did not record the write set" >&2
        k next "$s" --no-cleanup 2>&1 | head -c 1500 >&2
        exit 1
    fi
}

# walk <session> <state>... — directed hops along declared edges, flag on each.
walk() {
    local s="$1" t
    shift
    for t in "$@"; do
        k next "$s" --to "$t" --rationale "terminal-retention probe" --no-cleanup >/dev/null 2>&1
    done
}

state_of() { k status "$1" 2>/dev/null | jq -r '.current_state // "gone"'; }

# --- the blocked terminal keeps its context ----------------------------------

init_orchestrator block-keep
k next execute-block-keep --with-data '{"status":"blocked","detail":"probe"}' --no-cleanup >/dev/null 2>&1
if [ "$(k context get execute-block-keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "an orchestrator run reaching done_blocked with the flag keeps its context"
else
    fail "an orchestrator run reaching done_blocked with the flag lost its context"
fi

# Without the control this suite would pass on a koto that had stopped cleaning
# up at all, and the flag would look load-bearing while doing nothing.
init_orchestrator block-drop
k next execute-block-drop --with-data '{"status":"blocked","detail":"probe"}' >/dev/null 2>&1
if k context get execute-block-drop summary.md >/dev/null 2>&1; then
    fail "an orchestrator run reaching done_blocked without the flag kept its context -- the control did not fire"
else
    pass "an orchestrator run reaching done_blocked without the flag loses its context (control)"
fi

# --- the pause terminal keeps its context ------------------------------------
#
# paused_for_review is a suspension, not a termination: the operator is expected
# to come back, and what a resume reads is exactly the context koto disposes of
# on arrival, because the state is still terminal: true. #360's written
# acceptance criteria cover only the blocked terminal; this is the widening, and
# it is measured here rather than inferred from koto's source.

# The declared edges from orchestrator_setup to the pause terminal. koto refuses
# a hop it cannot find in the template, so this list is checked against the real
# graph on every run -- if a future edit reroutes the pause path, the walk stops
# short and the assertions below fail rather than silently testing nothing.
PAUSE_PATH="settled_branch_record drift_facts worktree_sync worktree_discipline_check spawn_and_await pr_finalization paused_for_review"

walk_to_pause() {
    # $1 session name, $2 extra flag for every hop ("" or --no-cleanup)
    local target
    for target in $PAUSE_PATH; do
        if [ -n "$2" ]; then
            k next "$1" --to "$target" --rationale "terminal-retention probe" "$2" >/dev/null 2>&1
        else
            k next "$1" --to "$target" --rationale "terminal-retention probe" >/dev/null 2>&1
        fi
    done
}

init_orchestrator pause-keep
walk_to_pause execute-pause-keep --no-cleanup
PAUSE_STATE=$(state_of execute-pause-keep)
if [ "$PAUSE_STATE" != "paused_for_review" ]; then
    fail "the walk did not reach paused_for_review (stopped at '$PAUSE_STATE') -- the pause path in execute.md has changed and this case is no longer testing it"
elif [ "$(k context get execute-pause-keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "an orchestrator run reaching paused_for_review with the flag keeps its context"
else
    fail "an orchestrator run reaching paused_for_review with the flag lost its context"
fi

init_orchestrator pause-drop
walk_to_pause execute-pause-drop ""
if k context get execute-pause-drop summary.md >/dev/null 2>&1; then
    fail "an orchestrator run reaching paused_for_review without the flag kept its context -- the control did not fire"
else
    pass "an orchestrator run reaching paused_for_review without the flag loses its context (control)"
fi

# --- retention must not block the resume it exists to protect ----------------
#
# The pause terminal is retained so a resume can read its record. A retained
# session keeps its name, and a plain `koto init` refuses a name already in use,
# so /execute enters through koto-open.sh with --replace-terminal: a finished
# session is replaced, and its old result comes back for the caller to print.
# These pin the signal, the refusal a plain init would still hit, and the
# replacement.

if [ "$(k status execute-pause-keep 2>/dev/null | jq -r '.is_terminal')" = "true" ]; then
    pass "the retained pause session reports is_terminal: true"
else
    fail "koto status no longer reports is_terminal: true for the retained pause session"
fi

if k init execute-pause-keep --template "$TPL" \
        --var PLAN_DOC=docs/plans/PLAN-pause-keep.md --var PLAN_SLUG=pause-keep \
        --var PLUGIN_ROOT="$PLUGIN_ROOT_VAR" --var PAUSE_BEFORE_FINALIZE=false >/dev/null 2>&1; then
    fail "a plain koto init accepted a name still held by the retained session -- re-check whether --replace-terminal is still needed"
else
    pass "a plain koto init refuses the retained session's name, which is why /execute enters with --replace-terminal"
fi

if [ "$(k context get execute-pause-keep summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "koto status and the refused init left the record intact"
else
    fail "inspecting the retained session destroyed or altered its record"
fi

ARGS_DIR="$WORKDIR/args"
mkdir -p "$ARGS_DIR"
jq -nc --arg root "$PLUGIN_ROOT_VAR" '[["PLAN_DOC","docs/plans/PLAN-pause-keep.md"],["PLAN_SLUG","pause-keep"],
    ["PLUGIN_ROOT",$root],["PAUSE_BEFORE_FINALIZE","false"],["MERGE","false"]]' > "$ARGS_DIR/vars.json"
OPEN_OUT=$(cd "$FIXREPO" && bash "$REPO_ROOT/scripts/koto-open.sh" execute-pause-keep "$TPL" "$ARGS_DIR/vars.json" \
    --attach-live --replace-terminal 2>/dev/null)
if printf '%s\n' "$OPEN_OUT" | grep -qx 'opened=replaced' \
    && printf '%s\n' "$OPEN_OUT" | grep -qx 'replaced_state=paused_for_review' \
    && [ "$(state_of execute-pause-keep)" = "write_set_record" ]; then
    pass "koto-open.sh --replace-terminal replaces the retained pause session and reports its old state"
else
    fail "--replace-terminal did not replace the retained session: [$OPEN_OUT], state [$(state_of execute-pause-keep)]"
fi

if grep -q -- '--replace-terminal' "$SKILL_MD" \
    && ! grep -n 'session cleanup' "$SKILL_MD" | grep -qi 'resume\|terminal\|clear\|recover'; then
    pass "SKILL.md's Resume enters with --replace-terminal, with no clean-up-before-init recovery"
else
    fail "SKILL.md's Resume must enter with --replace-terminal and must not clean a terminal before init"
fi

# --- each terminal's result payload -------------------------------------------
#
# Every edge into a terminal assigns `outcome` (and `step` or `reason` when the
# edge fixes it), and every terminal's result map reads those keys. These walk
# the declared edges -- directed hops up to the state that decides, then the
# real evidence or the real verdict -- and read the payload back. Each has a
# control without --no-cleanup on the deciding tick: the tick's own response
# still carries the result, and the session is gone, which is what the flag
# exists to prevent.

TO_CI="settled_branch_record drift_facts worktree_sync spawn_and_await pr_finalization plan_completion ci_monitor"

# at_ci_monitor <slug> [MERGE] — a session standing at ci_monitor with the
# settled branch and the expected head recorded, as the skipped states and the
# push would have left them.
at_ci_monitor() {
    init_orchestrator "$1" "${2:-false}"
    walk "execute-$1" $TO_CI
    printf 'impl/probe' | k context add "execute-$1" settled_branch >/dev/null 2>&1
    printf '%s' "$HEAD_SHA" | k context add "execute-$1" expected_head >/dev/null 2>&1
    if [ "$(state_of "execute-$1")" != "ci_monitor" ]; then
        echo "FAIL: the walk to ci_monitor stopped at $(state_of "execute-$1")" >&2
        exit 1
    fi
}

# decide <session> <json> <flag|""> — the deciding tick; sets RESP.
decide() {
    if [ -n "$3" ]; then
        RESP=$(k next "$1" --with-data "$2" "$3" 2>/dev/null)
    else
        RESP=$(k next "$1" --with-data "$2" 2>/dev/null)
    fi
}

# expect_payload <label> <session> <final state> <outcome> <step> <reason>
# — with the flag: the retained session's `koto status` result.
expect_payload() {
    local label="$1" s="$2" st="$3" want="$4|$5|$6" got
    got=$(k status "$s" 2>/dev/null | jq -r '.result.payload | "\(.outcome)|\(.step)|\(.reason)"')
    if [ "$(state_of "$s")" = "$st" ] && [ "$got" = "$want" ]; then
        pass "$label: $st, payload outcome|step|reason = $want"
    else
        fail "$label: state [$(state_of "$s")], payload [$got], want $st with [$want]"
    fi
}

# expect_control <label> <outcome> — without the flag: the response carries the
# result and the session is gone.
expect_control() {
    local s="$2" got
    got=$(printf '%s' "$RESP" | jq -r '.result.payload.outcome // "none"' 2>/dev/null)
    if [ "$got" = "$3" ] && ! k status "$s" >/dev/null 2>&1; then
        pass "$1 without the flag: the tick's response carries outcome=$3 and the session is gone (control)"
    else
        fail "$1 without the flag: response outcome [$got], session still present: $(k status "$s" >/dev/null 2>&1 && echo yes || echo no)"
    fi
}

# paused_for_review, by pr_finalization's pause edge.
init_orchestrator payload-pause
walk execute-payload-pause settled_branch_record drift_facts worktree_sync spawn_and_await pr_finalization
decide execute-payload-pause '{"finalization_status":"updated","pause_decision":"pause"}' --no-cleanup
expect_payload "paused_for_review" execute-payload-pause paused_for_review paused-for-review "" ""
if [ "$(k status execute-payload-pause | jq -r .result.payload.resume)" = "/execute docs/plans/PLAN-payload-pause.md" ]; then
    pass "paused_for_review carries the resume command"
else
    fail "paused_for_review resume: [$(k status execute-payload-pause | jq -r .result.payload.resume)]"
fi
init_orchestrator payload-pause-ctl
walk execute-payload-pause-ctl settled_branch_record drift_facts worktree_sync spawn_and_await pr_finalization
decide execute-payload-pause-ctl '{"finalization_status":"updated","pause_decision":"pause"}' ""
expect_control "paused_for_review" execute-payload-pause-ctl paused-for-review

# The DIRTY route: ci_monitor -> escalate_dirty_merge_state -> done_blocked.
at_ci_monitor payload-dirty
decide execute-payload-dirty '{"ci_outcome":"dirty_merge_state","rationale":"src/a.go conflicts"}' --no-cleanup
expect_payload "the DIRTY done_blocked" execute-payload-dirty done_blocked ready-awaiting-merge "" "merge-state:DIRTY"
if k status execute-payload-dirty | jq -e '.result.status == "failure"' >/dev/null; then
    pass "the DIRTY route still ends at the failure terminal (abandonment-forced)"
else
    fail "the DIRTY route's result status is not failure"
fi
at_ci_monitor payload-dirty-ctl
decide execute-payload-dirty-ctl '{"ci_outcome":"dirty_merge_state","rationale":"src/a.go conflicts"}' ""
expect_control "the DIRTY done_blocked" execute-payload-dirty-ctl ready-awaiting-merge

# A verdict error: a failed check makes the verdict error:execute:ci, and the
# step reaches the result through the key the record script wrote.
gh_fixture verdict-error
echo '[{"name":"build","bucket":"fail"}]' > "$GH_FIX/checks.out"
at_ci_monitor payload-error
decide execute-payload-error '{"ci_outcome":"failing_fixed"}' --no-cleanup
expect_payload "a verdict-error done_blocked" execute-payload-error done_blocked error "execute:ci" ""
if [ "$(k context get execute-payload-error merge_verdict)" = "error:execute:ci" ]; then
    pass "the verdict-error run routed on the recorded verdict error:execute:ci"
else
    fail "verdict-error: merge_verdict [$(k context get execute-payload-error merge_verdict 2>/dev/null)]"
fi
gh_fixture verdict-error-ctl
echo '[{"name":"build","bucket":"fail"}]' > "$GH_FIX/checks.out"
at_ci_monitor payload-error-ctl
decide execute-payload-error-ctl '{"ci_outcome":"failing_fixed"}' ""
expect_control "a verdict-error done_blocked" execute-payload-error-ctl error

# ready_awaiting_merge: no --merge, so the verdict is awaiting:merge-not-requested.
gh_fixture no-merge
at_ci_monitor payload-ready false
decide execute-payload-ready '{"ci_outcome":"pending"}' --no-cleanup
expect_payload "ready_awaiting_merge" execute-payload-ready ready_awaiting_merge ready-awaiting-merge "" "merge-not-requested"
if [ "$(k status execute-payload-ready | jq -r '.result.payload | "\(.pr) \(.repos)"')" = "$PR_URL o/r" ]; then
    pass "ready_awaiting_merge carries the owned PR and the write set"
else
    fail "ready_awaiting_merge pr/repos: [$(k status execute-payload-ready | jq -r '.result.payload | "\(.pr) \(.repos)"')]"
fi
gh_fixture no-merge-ctl
at_ci_monitor payload-ready-ctl false
decide execute-payload-ready-ctl '{"ci_outcome":"pending"}' ""
expect_control "ready_awaiting_merge" execute-payload-ready-ctl ready-awaiting-merge

# merged: --merge, a mergeable verdict, merge_attempt, and a confirm read of
# MERGED. The merge call itself is not made here (merge-exec.sh has its own
# suite); what is under test is that merge_confirm alone leads to merged.
gh_fixture merged
at_ci_monitor payload-merged true
k next execute-payload-merged --with-data '{"ci_outcome":"failing_fixed"}' --no-cleanup >/dev/null 2>&1
if [ "$(state_of execute-payload-merged)" = "merge_attempt" ]; then
    pass "a mergeable verdict with MERGE=true presents merge_attempt and asks for evidence"
else
    fail "mergeable with MERGE=true stopped at [$(state_of execute-payload-merged)]"
fi
decide execute-payload-merged '{"merge_exec":"called","merge_line":"merge-called:squash:'"$HEAD_SHA"'"}' --no-cleanup
expect_payload "merged" execute-payload-merged merged merged "" ""
if [ "$(k status execute-payload-merged | jq -r '.result.payload.pr')" = "$PR_URL" ]; then
    pass "merged carries the owned PR"
else
    fail "merged pr: [$(k status execute-payload-merged | jq -r '.result.payload.pr')]"
fi
gh_fixture merged-ctl
at_ci_monitor payload-merged-ctl true
k next execute-payload-merged-ctl --with-data '{"ci_outcome":"failing_fixed"}' --no-cleanup >/dev/null 2>&1
decide execute-payload-merged-ctl '{"merge_exec":"called","merge_line":"merge-called:squash:'"$HEAD_SHA"'"}' ""
expect_control "merged" execute-payload-merged-ctl merged

# --- the merge step's guarantees, on the engine --------------------------------

# A merge call that exits 0 while GitHub keeps reporting OPEN never reads as
# merged: merge_confirm's recorded read decides.
gh_fixture stays-open
echo '{"state":"OPEN"}' > "$GH_FIX/confirm.out"
at_ci_monitor stays-open true
k next execute-stays-open --with-data '{"ci_outcome":"failing_fixed"}' --no-cleanup >/dev/null 2>&1
k next execute-stays-open --with-data '{"merge_exec":"called"}' --no-cleanup >/dev/null 2>&1
expect_payload "merge called, PR still OPEN" execute-stays-open ready_awaiting_merge ready-awaiting-merge "" "merge-not-observed"

# A run stopped at merge_attempt with a recorded mergeable verdict, resumed
# without --merge: the rebind puts MERGE back to false, the merge_intent gate
# fails before any evidence is asked for, and nothing merges.
gh_fixture resume-without-merge
at_ci_monitor resume-no-merge true
k next execute-resume-no-merge --with-data '{"ci_outcome":"failing_fixed"}' --no-cleanup >/dev/null 2>&1
jq -nc --arg root "$PLUGIN_ROOT_VAR" '[["PLAN_DOC","docs/plans/PLAN-resume-no-merge.md"],["PLAN_SLUG","resume-no-merge"],
    ["PLUGIN_ROOT",$root],["PAUSE_BEFORE_FINALIZE","false"],["MERGE","false"]]' > "$ARGS_DIR/vars.json"
OPEN_OUT=$(cd "$FIXREPO" && bash "$REPO_ROOT/scripts/koto-open.sh" execute-resume-no-merge "$TPL" "$ARGS_DIR/vars.json" \
    --attach-live --replace-terminal 2>/dev/null)
k next execute-resume-no-merge --no-cleanup >/dev/null 2>&1
if printf '%s\n' "$OPEN_OUT" | grep -qx 'opened=attached' && ! grep -q '^pr merge' "$GH_FIX/gh.log"; then
    pass "resumed at merge_attempt without --merge: the attach rebinds MERGE and no pr merge is made"
else
    fail "resume without --merge: [$OPEN_OUT], gh: $(grep '^pr merge' "$GH_FIX/gh.log")"
fi
expect_payload "resumed at merge_attempt without --merge" execute-resume-no-merge ready_awaiting_merge ready-awaiting-merge "" "merge-not-requested"

# Overrides on the gates that decide the merge are refused, with and without
# --with-data. A session held at merge_route by a pending verdict:
gh_fixture pending
echo '[{"name":"build","bucket":"pending"}]' > "$GH_FIX/checks.out"
at_ci_monitor override-route true
k next execute-override-route --with-data '{"ci_outcome":"pending"}' --no-cleanup >/dev/null 2>&1
if [ "$(state_of execute-override-route)" = "merge_route" ]; then
    pass "a pending verdict holds the run at merge_route, asking for recheck"
else
    fail "pending verdict: state [$(state_of execute-override-route)]"
fi
for g in verdict_merged verdict_mergeable verdict_awaiting verdict_error verdict_pending verdict_present; do
    out=$(k overrides record execute-override-route --gate "$g" --rationale probe --with-data '{"matches":true,"exists":true}' 2>&1)
    rc=$?
    out2=$(k overrides record execute-override-route --gate "$g" --rationale probe 2>&1)
    rc2=$?
    if [ "$rc" -ne 0 ] && [ "$rc2" -ne 0 ] && printf '%s' "$out" | grep -q gate_not_overridable; then
        pass "merge_route's $g refuses an override, with and without --with-data"
    else
        fail "merge_route's $g accepted an override: [$out] [$out2]"
    fi
done
k next execute-override-route --no-cleanup >/dev/null 2>&1
if [ "$(state_of execute-override-route)" = "merge_route" ] && ! grep -q '^pr merge' "$GH_FIX/gh.log"; then
    pass "after the refused overrides the run is still at merge_route and nothing merged"
else
    fail "after refused overrides: state [$(state_of execute-override-route)]"
fi

# A session held at merge_confirm by a confirm read that cannot find the PR:
# the lookup serves the verdict, then starts failing before the confirm read.
gh_fixture confirm-held
at_ci_monitor override-confirm true
k next execute-override-confirm --with-data '{"ci_outcome":"failing_fixed"}' --no-cleanup >/dev/null 2>&1
rm -f "$GH_FIX/list.out"
echo 1 > "$GH_FIX/list.rc"
k next execute-override-confirm --with-data '{"merge_exec":"called"}' --no-cleanup >/dev/null 2>&1
if [ "$(state_of execute-override-confirm)" = "merge_confirm" ]; then
    pass "a confirm read that fails holds the run at merge_confirm"
else
    fail "confirm held: state [$(state_of execute-override-confirm)]"
fi
out=$(k overrides record execute-override-confirm --gate confirmed_merged --rationale probe --with-data '{"matches":true}' 2>&1)
rc=$?
out2=$(k overrides record execute-override-confirm --gate confirmed_merged --rationale probe 2>&1)
rc2=$?
if [ "$rc" -ne 0 ] && [ "$rc2" -ne 0 ] && printf '%s' "$out" | grep -q gate_not_overridable; then
    pass "merge_confirm's gate refuses an override, with and without --with-data"
else
    fail "merge_confirm's gate accepted an override: [$out] [$out2]"
fi
k next execute-override-confirm --no-cleanup >/dev/null 2>&1
if [ "$(state_of execute-override-confirm)" != "merged" ]; then
    pass "after the refused override the run does not reach merged"
else
    fail "the run reached merged after an override attempt"
fi
k next execute-override-confirm --with-data '{"confirm_status":"unreadable"}' --no-cleanup >/dev/null 2>&1
expect_payload "an unreadable confirm read" execute-override-confirm ready_awaiting_merge ready-awaiting-merge "" "merge-not-observed"

# --- the chain is real, not just a shape in the template --------------------
#
# escalate's shape asserted above is only worth asserting if that shape actually
# chains. This drives koto with a minimal template of exactly that shape -- a
# state declaring required evidence whose single transition to a failure
# terminal carries no `when` -- and shows one bare tick two states upstream
# landing on the terminal and taking the record with it. A stand-in rather than
# execute.md because reaching spawn_and_await for real means satisfying the
# settled-branch capture and materializing children, none of which is what this
# case is about.

cat > "$WORKDIR/chain.md" <<'CHAIN_EOF'
---
name: retention-chain-probe
version: "1.0"
description: A state with required evidence and one unconditional edge to a terminal.
initial_state: start
states:
  start:
    accepts:
      outcome:
        type: enum
        values: [ok, bad]
        required: true
    transitions:
      - target: middle
        when:
          outcome: bad
      - target: finished_ok
        when:
          outcome: ok
  middle:
    accepts:
      reason:
        type: string
        required: true
    transitions:
      - target: dead_end
  dead_end:
    terminal: true
    failure: true
  finished_ok:
    terminal: true
---

## start
Submit outcome.

## middle
Submit reason.

## dead_end
Terminal.

## finished_ok
Terminal.
CHAIN_EOF

koto init chain_bare --template "$WORKDIR/chain.md" >/dev/null 2>&1
printf 'the orchestrator record\n' | koto context add chain_bare summary.md >/dev/null 2>&1
koto next chain_bare --with-data '{"outcome":"bad"}' >/dev/null 2>&1
if koto context get chain_bare summary.md >/dev/null 2>&1; then
    fail "a bare tick did not chain through the accepts-declaring state -- re-check whether spawn_and_await's ticks still need the flag"
else
    pass "a bare tick chains through a state that declares required evidence and destroys the record (the defect the flag closes)"
fi

koto init chain_flagged --template "$WORKDIR/chain.md" >/dev/null 2>&1
printf 'the orchestrator record\n' | koto context add chain_flagged summary.md >/dev/null 2>&1
koto next chain_flagged --with-data '{"outcome":"bad"}' --no-cleanup >/dev/null 2>&1
if [ "$(koto context get chain_flagged summary.md 2>/dev/null)" = "the orchestrator record" ]; then
    pass "the same chained tick carrying --no-cleanup keeps the record"
else
    fail "the chained tick lost the record even with --no-cleanup"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
