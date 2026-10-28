#!/usr/bin/env bash
# publish-scoping-pr.sh -- /scope's one push and one pull request, on intent runs.
#
# With --intent set, /scope pushes its branch and opens one PR at exit, once the
# PLAN's mode is known (R9). This script is that step. The publish states in
# skills/scope/koto-templates/scope.md (publish_full_run, publish_re_evaluation,
# publish_abandonment) and `republish` have the agent run it, because a push and
# `gh pr create` are externally visible events and never a default action
# (references/default-action-conversion.md). Each of those states then gates on
# this script's --verify mode, which makes no GitHub or git write, so a run
# cannot claim a PR it did not open.
#
# Publish, in order; any failure stops with its step and no later write:
#
#   1. validate --topic against the slug pattern; read the mode from the PLAN's
#      frontmatter (never from evidence) -- required on a full-run exit
#   2. refuse a detached HEAD, a branch failing `git check-ref-format --branch`,
#      a missing `origin`, and the remote's default branch (or main/master)
#                                                            -> scope:push
#   3. push with `git push origin HEAD:refs/heads/<branch>` -- never a force
#      option, never a `+` refspec                           -> scope:push
#   4. look the PR up through skills/execute/scripts/owned-pr.sh, unchanged,
#      with --state open, --base <default>, and this run's identity:
#        one survivor   reused; with --session, its body is rewritten with
#                       `gh pr edit --body-file` unless the session's
#                       published_intent key already equals --intent,
#                       keeping the live body's Part 1 and the Part 2
#                       sections the template doesn't write (keep_live,
#                       below) and any run marker line it carries
#                       (`run-id.sh carry`)
#        zero           one `gh pr create --head <branch> --base <default>
#                       --title <title> --body-file <file>` (a foreign-only
#                       branch counts as zero), then looked up again
#        several (3), ambiguous (4), or another run's PR (5)
#                       scope:pr-create, no write
#        read fails (2) scope:pr-create, no write
#
# The run identity. Every lookup carries --run-id when the script has one:
# given as --run-id (/deliver's probe passes its own), or read from --session
# through skills/execute/scripts/run-id.sh get (scope-open.sh minted it). /scope
# stamps no marker on the PR it opens, so its own PR is matched on owned-pr.sh's
# login-and-branch fallback; the identity is what keeps a PR another run
# marked from being reused, edited, or verified. With neither flag (a hand
# run) the lookups match by login and branch alone.
#
# Draft or ready (R9): a draft for a single-pr or coordinated full-run and for
# the re-evaluation and abandonment-forced exits; ready for a multi-pr
# full-run, which is meant to merge and land the Active PLAN.
#
# The body is a fixed template over validated fields only: the slug, exit,
# outcome, `intent=`, mode, the docs/ artifact paths that exist, and the PLAN's
# work-item IDs. No free-text state field reaches it. The one text read from a
# document is a plan/v2 step plan's step headings, which the body lists as
# `### Step <N>: <title>` lines (a step has no ID beyond its number). They go
# inside a fenced code block, with every control character made a space and a
# fence longer than any backtick run in them, so a title stays literal text:
# no heading, link, mention or closing keyword in it is live. A coordinated
# body starts with the fixed coordination-PR declaration prefix and is checked
# with `shirabe validate --coordination-body` before it is posted.
#
# Which of those fields a body carries depends on the repository. The record
# lines (topic=, exit=, outcome=, intent=, mode=) and the PLAN's own path are
# the run's records, written only when scripts/pr-workflow-content.sh prints
# include for the repository. By default the body is one sentence naming the
# topic, the durable documents under `## Documents`, and the work items. A
# coordination body is written whole either way, since the merge gate reads
# its index.
#
# Every body has two parts (references/pr-body-conformance.md, PB2 and PB4):
# Part 1, one plain sentence naming the topic with no heading, then a bare
# `---` line, then everything else as Part 2. The squash message is the
# title and Part 1 (scripts/lib/squash-message.sh), so the record lines and
# sections never reach it. A rewrite of a reused PR whose live body has a
# top-level `---` keeps that body's Part 1 byte for byte in place of the
# sentence, and carries every `## ` section of its Part 2 whose heading the
# template never writes (KEEP_OWNED), unchanged, after the template's
# sections, naming each on stderr. A live Part 1 with no text is not kept.
#
# The intent last published. The body's `intent=` line is text for people; no
# step reads it back. With --session, a successful publish writes the intent
# it published to the session's context key published_intent, and that key is
# what both modes compare against:
#
#   publish   rewrites a reused PR's body when the key is absent or differs
#             from --intent. A session without the key (a new run
#             republishing, or one from before the key existed) always
#             rewrites: the body is a fixed template and the run marker is
#             carried, so a rewrite that changes nothing is harmless. With no
#             --session (a hand run) there is no run state to compare, so a
#             reused PR's body is left as it is.
#   verify    --expect-intent <v> passes only when the key equals <v>. It
#             needs --session; an absent key is "not verified" (exit 1).
#
# --verify exits 0 only when `git ls-remote origin refs/heads/<branch>` equals
# `git rev-parse HEAD`, exactly one owned open PR exists on the branch, and,
# with --expect-intent, the session's published_intent equals <value>. It
# makes no GitHub or git write, and no koto context write: given --session, it
# only reads the session's run identity (run-id.sh get) and published_intent.
#
# Usage:
#   publish-scoping-pr.sh --topic <slug> --exit <full-run|re-evaluation|abandonment-forced>
#                         --intent <continue|stop> [--session <name>]
#   publish-scoping-pr.sh --topic <slug> --verify [--session <name> [--expect-intent <continue|stop>]
#                         | --run-id <id>]
#
# With --session in publish mode, the script clears the context key
# publish_step when it starts and writes it (scope:push or scope:pr-create)
# with `koto context add` when it fails. The publish states route on
# publish_step through non-overridable context-matches gates. In either mode,
# --session is also where the run identity comes from (run_id, above).
#
# Output (stdout, key=value lines):
#   publish:  mode=<mode>, pr=<url> on success; step=<scope:push|scope:pr-create> on failure
#   verify:   pr=<url> on success
#
# Exit codes:
#   publish:  0 published; 10 scope:push; 11 scope:pr-create; 64 usage;
#             66 a koto context call failed
#   verify:   0 verified; 1 not verified; 2 could not read (published_intent
#             included); 64 usage; 66 the run identity could not be read
#
# Requires: bash 3.2+, git, gh, jq; shirabe for a coordinated body; koto with
# --session.
set -uo pipefail

PROG=publish-scoping-pr
HERE=$(cd "$(dirname "$0")" && pwd)
OWNED="$HERE/../../execute/scripts/owned-pr.sh"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RE_PR_URL='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$'
RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'
RE_RUN_ID='^[0-9a-f]{32}$'
RUNID="$HERE/../../execute/scripts/run-id.sh"
# cb_part1, the Part 1 reader squash-message.sh's separator rule is written once for.
. "$HERE/../../../scripts/lib/coordination-body.sh"
# The `## ` headings the template writes; a rewrite replaces these and keeps any other.
KEEP_OWNED='|## Documents|## Artifact Chain|## Work Items|## PR Index|## Merge Order|'
DECLARATION='> This is a **coordination PR** for a coordinated effort. It is docs-only and'

usage() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    printf 'usage: publish-scoping-pr.sh --topic <slug> --exit <exit> --intent <continue|stop> [--session <name>]\n' >&2
    printf '       publish-scoping-pr.sh --topic <slug> --verify [--session <name> [--expect-intent <continue|stop>] | --run-id <id>]\n' >&2
    exit 64
}

TOPIC=""; EXIT=""; INTENT=""; SESSION=""; VERIFY=0; EXPECT=""; RUN_ID=""
SEEN=" "
while [ "$#" -gt 0 ]; do
    case "$1" in
        --topic|--exit|--intent|--session|--expect-intent|--run-id)
            [ "$#" -ge 2 ] || usage "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --topic) TOPIC="$2" ;;
                --exit) EXIT="$2" ;;
                --intent) INTENT="$2" ;;
                --session) SESSION="$2" ;;
                --expect-intent) EXPECT="$2" ;;
                --run-id) RUN_ID="$2" ;;
            esac
            shift ;;
        --verify)
            case "$SEEN" in *" --verify "*) usage "--verify given more than once" ;; esac
            SEEN="$SEEN--verify "; VERIFY=1 ;;
        *) usage "unknown argument: $1" ;;
    esac
    shift
done

[[ "$TOPIC" =~ $RE_TOPIC ]] || usage "--topic [$TOPIC] does not match $RE_TOPIC"
if [ "$VERIFY" -eq 1 ]; then
    [ -z "$EXIT$INTENT" ] || usage "--verify takes only --topic, --expect-intent, and --session or --run-id"
    case "$SEEN" in
        *" --expect-intent "*)
            case "$EXPECT" in continue|stop) ;; *) usage "--expect-intent must be continue or stop" ;; esac
            case "$SEEN" in *" --session "*) ;; *) usage "--expect-intent reads the session's published_intent; give --session" ;; esac ;;
    esac
    case "$SEEN" in *" --session "*) case "$SEEN" in *" --run-id "*) usage "--session and --run-id are exclusive" ;; esac ;; esac
    if [ -n "$SESSION" ] && ! [[ "$SESSION" =~ $RE_SESSION ]]; then
        usage "--session [$SESSION] is not a koto session name"
    fi
    case "$SEEN" in
        *" --run-id "*) [[ "$RUN_ID" =~ $RE_RUN_ID ]] || usage "--run-id [$RUN_ID] is not a run id" ;;
    esac
else
    case "$SEEN" in *" --expect-intent "*) usage "--expect-intent goes with --verify" ;; esac
    case "$SEEN" in *" --run-id "*) usage "--run-id goes with --verify; publish reads it from --session" ;; esac
    case "$EXIT" in full-run|re-evaluation|abandonment-forced) ;; *) usage "--exit must be full-run, re-evaluation or abandonment-forced" ;; esac
    case "$INTENT" in continue|stop) ;; *) usage "--intent must be continue or stop" ;; esac
    if [ -n "$SESSION" ] && ! [[ "$SESSION" =~ $RE_SESSION ]]; then
        usage "--session [$SESSION] is not a koto session name"
    fi
fi

# resolve_run_id -- the run identity every lookup carries: --run-id as given,
# else the session's (run-id.sh get; never minted here), else none. Sets OWNED_RUN to the
# owned-pr.sh arguments.
OWNED_RUN=()
resolve_run_id() {
    if [ -z "$RUN_ID" ] && [ -n "$SESSION" ]; then
        RUN_ID=$(bash "$RUNID" get "${KOTO_TICK_SESSION:-$SESSION}" </dev/null) || {
            printf '%s: could not read this run'"'"'s identity\n' "$PROG" >&2
            exit 66
        }
    fi
    if [ -n "$RUN_ID" ]; then OWNED_RUN=(--run-id "$RUN_ID"); fi
    return 0
}

PLAN="docs/plans/PLAN-${TOPIC}.md"
SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && rm -rf -- "$SCRATCH"; return 0; }
trap cleanup EXIT

# --- shared reads -----------------------------------------------------------------

frontmatter_field() { # frontmatter_field <file> <key>
    awk -v k="$2" '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; inside = 1; next }
        inside && /^---[[:space:]]*$/ { exit }
        inside && index($0, k ":") == 1 {
            v = substr($0, length(k) + 2)
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v; exit
        }
    ' "$1"
}

# default_branch -- the remote's default branch: origin's HEAD symref, else
# what GitHub reports. Empty when neither can be read.
default_branch() {
    local d
    d=$(git ls-remote --symref origin HEAD | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }')
    if [ -z "$d" ]; then
        d=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name </dev/null) || d=""
    fi
    printf '%s' "$d"
}

repo_name() {
    local r
    r=$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null) || r=""
    [[ "$r" =~ $RE_REPO ]] || return 1
    printf '%s' "$r"
}

# published_intent -- the session's published_intent key, empty when the key is
# absent or there is no --session. Only `exists` answering 1 means "absent";
# any other failure returns 1.
published_intent() {
    local sess rc
    [ -n "$SESSION" ] || return 0
    sess="${KOTO_TICK_SESSION:-$SESSION}"
    koto context exists "$sess" published_intent </dev/null >/dev/null
    rc=$?
    case "$rc" in
        0) koto context get "$sess" published_intent </dev/null || return 1 ;;
        1) return 0 ;;
        *) return 1 ;;
    esac
}

# --- verify ---------------------------------------------------------------------------

if [ "$VERIFY" -eq 1 ]; then
    not_verified() { printf '%s: not verified: %s\n' "$PROG" "$1" >&2; exit 1; }
    unreadable()   { printf '%s: cannot verify: %s\n' "$PROG" "$1" >&2; exit 2; }
    resolve_run_id

    BRANCH=$(git symbolic-ref --quiet --short HEAD) || not_verified "HEAD is detached"
    git remote get-url origin >/dev/null || not_verified "no origin remote"
    HEAD_SHA=$(git rev-parse HEAD) || unreadable "git rev-parse HEAD failed"
    REMOTE=$(git ls-remote origin "refs/heads/$BRANCH") || unreadable "git ls-remote origin failed"
    REMOTE_SHA=$(printf '%s\n' "$REMOTE" | awk 'NR == 1 { print $1 }')
    [ "$REMOTE_SHA" = "$HEAD_SHA" ] || not_verified "origin's $BRANCH is [$REMOTE_SHA], HEAD is $HEAD_SHA"

    DEFAULT=$(default_branch)
    [ -n "$DEFAULT" ] || unreadable "the default branch cannot be read"
    REPO=$(repo_name) || unreadable "the repository name cannot be read"
    URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state open --base "$DEFAULT" ${OWNED_RUN[@]+"${OWNED_RUN[@]}"} </dev/null)
    RC=$?
    case "$RC" in
        0) ;;
        3|4) not_verified "several owned open PRs on $BRANCH, or an ambiguous lookup (owned-pr.sh exit $RC)" ;;
        5) not_verified "the PR on $BRANCH was opened by another run" ;;
        *) unreadable "owned-pr.sh exited $RC" ;;
    esac
    [ -n "$URL" ] || not_verified "no owned open PR on $BRANCH"
    [[ "$URL" =~ $RE_PR_URL ]] || unreadable "owned-pr.sh printed a URL outside the pattern"
    if [ -n "$EXPECT" ]; then
        GOT=$(published_intent) || unreadable "the session's published_intent cannot be read"
        [ -n "$GOT" ] || not_verified "the session records no published_intent; no publish has succeeded in it"
        [ "$GOT" = "$EXPECT" ] || not_verified "the session's published_intent is [$GOT], expected $EXPECT"
    fi
    printf 'pr=%s\n' "$URL"
    exit 0
fi

# --- publish ----------------------------------------------------------------------------

ctx() { # ctx add|remove <key> [value]
    [ -n "$SESSION" ] || return 0
    local sess="${KOTO_TICK_SESSION:-$SESSION}"
    if [ "$1" = remove ]; then
        koto context remove "$sess" "$2" >/dev/null && return 0
    else
        printf '%s' "$3" | koto context add "$sess" "$2" >/dev/null && return 0
    fi
    printf '%s: koto context %s failed for %s\n' "$PROG" "$1" "$2" >&2
    exit 66
}

fail() { # fail <step> <message>
    printf '%s: %s\n' "$PROG" "$2" >&2
    ctx add publish_step "$1"
    printf 'step=%s\n' "$1"
    case "$1" in
        scope:push) exit 10 ;;
        *) exit 11 ;;
    esac
}

ctx remove publish_step
resolve_run_id

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/publish-scoping-pr.XXXXXX") || fail scope:push "could not make a scratch directory"

git rev-parse --is-inside-work-tree >/dev/null || fail scope:push "not inside a git work tree"
TOP=$(git rev-parse --show-toplevel) || fail scope:push "the work tree root cannot be read"
cd "$TOP" || fail scope:push "cannot enter $TOP"

# 1. the mode, from the PLAN
MODE=""
if [ -f "$PLAN" ]; then
    MODE=$(frontmatter_field "$PLAN" execution_mode)
    case "$MODE" in single-pr|multi-pr|coordinated) ;; *) MODE="" ;; esac
fi
if [ "$EXIT" = full-run ] && [ -z "$MODE" ]; then
    fail scope:push "a full-run exit needs $PLAN with an execution_mode in {single-pr, multi-pr, coordinated}"
fi
printf 'mode=%s\n' "${MODE:-none}"

# 2. the branch
BRANCH=$(git symbolic-ref --quiet --short HEAD) || fail scope:push "HEAD is detached; nothing is pushed from a detached HEAD"
git check-ref-format --branch "$BRANCH" >/dev/null || fail scope:push "[$BRANCH] fails git check-ref-format --branch"
case "$BRANCH" in -*) fail scope:push "[$BRANCH] starts with -" ;; esac
git remote get-url origin >/dev/null || fail scope:push "there is no origin remote"
DEFAULT=$(default_branch)
[ -n "$DEFAULT" ] || fail scope:push "origin's default branch cannot be read"
case "$BRANCH" in
    "$DEFAULT"|main|master) fail scope:push "[$BRANCH] is the default branch; /scope never pushes to it" ;;
esac

# 3. the push, skipped when origin already holds HEAD (a re-run after success)
HEAD_SHA=$(git rev-parse HEAD) || fail scope:push "git rev-parse HEAD failed"
REMOTE_SHA=$(git ls-remote origin "refs/heads/$BRANCH" | awk 'NR == 1 { print $1 }')
if [ "$REMOTE_SHA" != "$HEAD_SHA" ]; then
    git push -q origin "HEAD:refs/heads/$BRANCH" </dev/null >&2 \
        || fail scope:push "the push of HEAD to origin's $BRANCH failed"
fi

# 4. the PR
REPO=$(repo_name) || fail scope:pr-create "the repository name cannot be read"

OUTCOME=""
case "$EXIT" in
    full-run) if [ "$MODE" = multi-pr ]; then OUTCOME=handed-off-multi-pr; else OUTCOME=scoped; fi ;;
    re-evaluation) OUTCOME=re-evaluation ;;
    abandonment-forced) OUTCOME=abandonment ;;
esac

DRAFT=1
[ "$EXIT" = full-run ] && [ "$MODE" = multi-pr ] && DRAFT=0

# Whether the repository opts in to workflow content in its PR bodies.
CONTENT=$(bash "$HERE/../../../scripts/pr-workflow-content.sh" </dev/null) \
    || fail scope:pr-create "scripts/pr-workflow-content.sh could not read the repository's setting"

# The title becomes the squash commit's subject. The skill's name and the
# run's exit value are workflow records, kept for a repository that opts in
# and for a coordination PR, which stays as it was with its body.
if [ "$CONTENT" = include ] || { [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; }; then
    TITLE="docs(scope): ${TOPIC} (${EXIT})"
else
    case "$EXIT" in
        full-run) TITLE="docs: add the ${TOPIC} scoping documents" ;;
        re-evaluation) TITLE="docs: ${TOPIC} scoping documents, for re-evaluation" ;;
        *) TITLE="docs: ${TOPIC} scoping documents, abandoned" ;;
    esac
fi

# render_steps -- a plan/v2 PLAN's work items: each `### Step <N>: <title>`
# heading of `## Steps`, in PLAN order, inside one fenced code block. Control
# characters become spaces, so a title cannot start a line of its own or carry
# a terminal escape, and the fence is one backtick longer than the longest run
# in the titles (three at least), so no title can close it.
render_steps() {
    local steps fence
    steps=$(LC_ALL=C awk '
        /^##[[:space:]]+Steps[[:space:]]*$/ { s = 1; next }
        s && /^##[[:space:]]/ { exit }
        s && /^###[[:space:]]+Step[[:space:]]+[1-9][0-9]*:/ {
            line = $0
            sub(/^###[[:space:]]+Step[[:space:]]+/, "", line)
            num = line; sub(/:.*$/, "", num)
            title = substr(line, length(num) + 2)
            gsub(/[[:cntrl:]]/, " ", title)
            gsub(/  +/, " ", title)
            sub(/^ /, "", title); sub(/ $/, "", title)
            printf "### Step %s: %s\n", num, title
        }
    ' "$PLAN")
    [ -n "$steps" ] || return 0
    fence=$(printf '%s\n' "$steps" | awk '
        { line = $0
          while (match(line, /`+/)) { if (RLENGTH > max) max = RLENGTH; line = substr(line, RSTART + RLENGTH) } }
        END { n = (max >= 3) ? max + 1 : 3; f = ""; for (i = 0; i < n; i++) f = f "`"; print f }')
    printf '\n## Work Items\n\n'
    printf '%stext\n%s\n%s\n' "$fence" "$steps" "$fence"
}

# The fixed template. Every value is an enum, the validated slug, or a path
# composed from it; work-item IDs are digits read from the PLAN, and a step
# plan's step headings are listed as literal text (render_steps).
render_body() {
    local f="$1" p ids records=1 coord=0
    [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ] && coord=1
    # The run's record (the topic=/exit=/outcome=/intent=/mode= lines and the
    # PLAN's path, a file deleted when the work completes) is written only for a
    # repository that opts in to workflow content. A coordination body keeps
    # its record whatever the switch says: the merge gate reads its index.
    [ "$coord" = 1 ] || [ "$CONTENT" = include ] || records=0
    {
        # Part 1, the squash message's body: one plain sentence, no heading.
        if [ "$coord" = 1 ]; then
            printf 'The coordination pull request for %s, which merges after every node pull request.\n\n' "$TOPIC"
        else
            case "$EXIT" in
                full-run) printf 'The scoping documents for %s.\n\n' "$TOPIC" ;;
                re-evaluation) printf 'The scoping documents for %s, sent back for re-evaluation.\n\n' "$TOPIC" ;;
                *) printf 'The scoping documents for %s, which was abandoned.\n\n' "$TOPIC" ;;
            esac
        fi
        printf -- '---\n\n'
        if [ "$coord" = 1 ]; then
            printf '# Coordination PR: %s\n\n' "$TOPIC"
            printf '%s\n' "$DECLARATION"
            printf '> merges **last**, once every indexed PR has merged and finalization is\n'
            printf '> complete. See `references/coordination-strategy.md`.\n\n'
        elif [ "$records" = 1 ]; then
            printf '# /scope: %s\n\n' "$TOPIC"
        fi
        if [ "$records" = 1 ]; then
            printf 'topic=%s\n' "$TOPIC"
            printf 'exit=%s\n' "$EXIT"
            printf 'outcome=%s\n' "$OUTCOME"
            printf 'intent=%s\n' "$INTENT"
            printf 'mode=%s\n\n' "${MODE:-none}"
            printf '## Artifact Chain\n\n'
        else
            printf '## Documents\n\n'
        fi
        for p in "docs/briefs/BRIEF-${TOPIC}.md" "docs/prds/PRD-${TOPIC}.md" \
                 "docs/designs/DESIGN-${TOPIC}.md" "docs/designs/current/DESIGN-${TOPIC}.md" \
                 "docs/plans/PLAN-${TOPIC}.md"; do
            # An abandoned run writes no PLAN; never list one it left behind.
            [ "$EXIT" = abandonment-forced ] && [ "$p" = "$PLAN" ] && continue
            [ "$records" = 0 ] && [ "$p" = "$PLAN" ] && continue
            [ -f "$p" ] && printf -- '- %s\n' "$p"
        done
        for p in docs/decisions/DECISION-*-"${TOPIC}"-*.md; do
            [ -f "$p" ] && printf -- '- %s\n' "$p"
        done
        if [ -f "$PLAN" ] && [ "$EXIT" != abandonment-forced ]; then
            # Issue numbers from the Implementation Issues table (the first
            # cell of each row), else the outline IDs.
            ids=$(awk '
                /^##[[:space:]]+Implementation[[:space:]]+Issues/ { t = 1; next }
                t && /^##[[:space:]]/ { t = 0 }
                t && /^\|/ {
                    split($0, cells, "|")
                    if (match(cells[2], /#[0-9]+/)) print substr(cells[2], RSTART, RLENGTH)
                }
            ' "$PLAN" | awk '!seen[$0]++')
            if [ -z "$ids" ]; then
                ids=$(awk '/^###[[:space:]]+Issue[[:space:]]+[0-9]+/ { o = $0; sub(/^###[[:space:]]+Issue[[:space:]]+/, "", o); sub(/[^0-9].*$/, "", o); print "Issue " o }' "$PLAN")
            fi
            if [ "$(frontmatter_field "$PLAN" schema)" = plan/v2 ]; then
                render_steps
            elif [ -n "$ids" ]; then
                printf '\n## Work Items\n\n'
                printf '%s\n' "$ids" | sed 's/^/- /'
            fi
        fi
        if [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; then
            printf '\n## PR Index\n\nNo node PR is open yet; /execute opens one per PR node.\n\n'
            printf '## Merge Order\n\n```merge-order\n'
            printf "# /execute renders the PLAN's merge order here (PR and gate nodes, one per line).\n"
            printf '```\n'
        fi
    } >"$f"
    check_coord_body "$f"
}

# check_coord_body <file> -- a coordination body is checked before it is posted.
check_coord_body() {
    if [ "$MODE" = coordinated ] && [ "$EXIT" = full-run ]; then
        command -v shirabe >/dev/null 2>&1 \
            || fail scope:pr-create "shirabe is not on PATH; a coordination body cannot be validated without it"
        shirabe validate --coordination-body "$1" >&2 \
            || fail scope:pr-create "the coordination body fails shirabe validate --coordination-body"
    fi
}

# keep_live <live> <new> -- when the live body has a top-level `---` (cb_part1:
# squash-message.sh's rule, outside a ``` fence), rewrite <new> as the live
# Part 1 byte for byte, the `---` line, the template's Part 2, then each `## `
# section of the live Part 2 whose heading is not in KEEP_OWNED, unchanged and
# in live order (a heading inside a fence starts nothing), after a blank line.
# A live Part 1 with no text gives way to the template's. Each carried heading
# is named on stderr. A live body with no top-level `---` leaves <new> as it is.
keep_live() {
    local live="$1" new="$2" p1="$2.part1" carried="$2.carried" names="$2.names" n
    cb_part1 "$live" >"$p1" || return 0
    if [ -z "$(tr -d '[:space:]' <"$p1")" ]; then
        cb_part1 "$new" >"$p1" || return 1
    fi
    LC_ALL=C awk -v owned="$KEEP_OWNED" -v names="$names" '
        function flush(   i, last, l) {
            if (keep) {
                last = 0
                for (i = 1; i <= n; i++) { l = buf[i]; if (l ~ /[^ \t\r]/) last = i }
                if (last) { printf "\n"; for (i = 1; i <= last; i++) print buf[i] }
            }
            n = 0
        }
        { line = $0; sub(/\r$/, "", line) }
        !sep {
            if (line ~ /^[ \t]*```/) fence = !fence
            else if (!fence && line ~ /^[ \t]*---[ \t]*$/) { sep = 1; fence = 0 }
            next
        }
        line ~ /^[ \t]*```/ { fence = !fence }
        !fence && line ~ /^## / {
            flush()
            h = line; sub(/[ \t]+$/, "", h)
            keep = (index(owned, "|" h "|") == 0)
            if (keep) print h > names
        }
        keep { buf[++n] = $0 }
        END { flush() }
    ' "$live" >"$carried" || return 1
    # The template's Part 2 starts on the line after its own separator.
    n=$(cb_part1 "$new" | wc -l) || return 1
    {
        cat "$p1"
        printf -- '---\n'
        tail -n "+$((n + 2))" "$new"
        cat "$carried"
    } >"$new.kept" || return 1
    mv -f "$new.kept" "$new" || return 1
    if [ -s "$names" ]; then
        while IFS= read -r n; do
            printf '%s: kept the live body'"'"'s section [%s], after the template'"'"'s sections\n' "$PROG" "$n" >&2
        done <"$names"
    fi
    return 0
}

BODY="$SCRATCH/body.md"
render_body "$BODY"

lookup() {
    URL=$(bash "$OWNED" --repo "$REPO" --head "$BRANCH" --state open --base "$DEFAULT" ${OWNED_RUN[@]+"${OWNED_RUN[@]}"} </dev/null)
    LRC=$?
}

lookup
case "$LRC" in
    0) ;;
    3|4) fail scope:pr-create "several owned open PRs on $BRANCH, or an ambiguous lookup (owned-pr.sh exit $LRC); refusing to pick one" ;;
    5) fail scope:pr-create "the PR on $BRANCH was opened by another run; not reusing it" ;;
    *) fail scope:pr-create "the owned-PR lookup failed (owned-pr.sh exit $LRC)" ;;
esac

if [ -n "$URL" ]; then
    [[ "$URL" =~ $RE_PR_URL ]] || fail scope:pr-create "owned-pr.sh printed a URL outside the pattern"
    LAST=$(published_intent) || fail scope:pr-create "the session's published_intent cannot be read"
    # No --session: no run state to compare against, so the PR is reused as is.
    if [ -n "$SESSION" ] && [ "$LAST" != "$INTENT" ]; then
        # A full-body rewrite keeps the live Part 1, the Part 2 sections the
        # template doesn't write, and whatever run marker the live body carries.
        gh pr view "$URL" --json body --jq .body </dev/null > "$SCRATCH/live-body.md" \
            || fail scope:pr-create "the owned PR's body cannot be read"
        keep_live "$SCRATCH/live-body.md" "$BODY" \
            || fail scope:pr-create "could not keep the PR's Part 1 and sections in the new body"
        check_coord_body "$BODY"
        bash "$RUNID" carry "$SCRATCH/live-body.md" "$BODY" </dev/null \
            || fail scope:pr-create "could not carry the PR's run marker into the new body"
        gh pr edit "$URL" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr edit --body-file failed"
    fi
else
    if [ "$DRAFT" -eq 1 ]; then
        gh pr create --repo "$REPO" --draft --head "$BRANCH" --base "$DEFAULT" \
            --title "$TITLE" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr create failed"
    else
        gh pr create --repo "$REPO" --head "$BRANCH" --base "$DEFAULT" \
            --title "$TITLE" --body-file "$BODY" </dev/null >&2 \
            || fail scope:pr-create "gh pr create failed"
    fi
    lookup
    [ "$LRC" -eq 0 ] && [ -n "$URL" ] \
        || fail scope:pr-create "the created PR is not found as the one owned open PR on $BRANCH"
    [[ "$URL" =~ $RE_PR_URL ]] || fail scope:pr-create "owned-pr.sh printed a URL outside the pattern"
fi

# The PR now carries this run's intent; record it as the intent last published.
# The publish gates' --verify --expect-intent reads it, so a failed write is
# reported (exit 66) rather than left for the gate to find.
ctx add published_intent "$INTENT"

# A successful publish consumes the prior-run facts: the retry they exist for
# has happened, and leaving the key would let it fire twice. Genuinely
# best-effort, unlike ctx, whose exit 66 would report failure for a publish
# that already succeeded -- the PR exists by this line, and the cleanup phase
# removes the key too.
if [ -n "$SESSION" ]; then
    koto context remove "${KOTO_TICK_SESSION:-$SESSION}" work/prior-run.md >/dev/null 2>&1 \
        || printf '%s: could not remove work/prior-run.md; the cleanup phase removes it too\n' "$PROG" >&2
fi

printf 'pr=%s\n' "$URL"
exit 0
