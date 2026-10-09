#!/usr/bin/env bash
# check-branch-output.sh -- does what this branch carries pass the output rules?
# Part of the work-on skill
#
# A gate script: koto runs it as a command gate in the state that produced the
# output, and routes on its exit status. Each mode calls a check that already
# ships, unchanged, and translates its result:
#
#   --commits (--session <s> | --base-ref <ref>)
#       Every non-merge commit in the range: its subject must match the
#       Conventional Commits pattern the `commit_convention` gate in work-on.md
#       has always applied to the tip, and no line of its message may be an
#       AI-attribution line, by the predicate PB3 applies to a PR body
#       (`is_attribution_line` in crates/shirabe-validate/src/pr_body.rs): a
#       `Co-Authored-By:` line naming Claude or Anthropic, or a "Generated with
#       Claude Code" line. Merge commits are skipped: a branch catches up with
#       main by merging it in, and a merge commit's subject is git's.
#   --wip
#       `git ls-tree -r --name-only HEAD -- wip/`: no path under wip/ in the
#       committed tree.
#   --docs-visibility (--session <s> | --base-ref <ref>)
#       The `docs/**/*.md` files the range changed, through
#       `shirabe validate --visibility=<declared> --format json`. Only the
#       visibility-gated codes count (R7 VISION sections, R8 STRATEGY
#       sections, R9 a private-only type); every other code is left to the
#       validate-docs CI job. <declared> is the `## Repo Visibility:` header of
#       the repository root's CLAUDE.local.md, else its CLAUDE.md; with neither,
#       the flag is omitted and the validator detects visibility as it does in
#       CI.
#   --synced [--base-ref <ref>]
#       The test /execute's `worktree_sync` gates on: <ref> (default
#       origin/main) is an ancestor of HEAD and no merge is in progress.
#
# The range:
#   --session <s>    impl_base..HEAD, impl_base read from koto context, where
#                    /work-on's analysis state records it.
#   --base-ref <ref> <ref>..HEAD for --commits, and the diff from
#                    merge-base(<ref>, HEAD) for --docs-visibility.
#
# Exit status (the gate scripts' shared convention):
#   0  the output passes
#   1  at least one violation; one `::koto-finding::` line per violation on
#      stdout
#   2  the check could not decide: a usage error, a missing tool (git, jq,
#      koto, shirabe), a range or ref that does not resolve, a validator that
#      failed to run. No finding is printed; the reason goes to stderr.
#
# Each finding is koto's finding shape, built with jq:
#   ::koto-finding::{"rule_id":"<name>","level":"error","message":"<summary>: ...",
#                    "rule_ref":"<path>#L<a>-L<b>@<revision>"[,"path":"..."[,"line":N]]}
# The rules are entries of references/rule-registry.json; scripts/lib/rule-findings.sh
# resolves each one's reference and summary through scripts/rule-registry.sh.
#
# Runs from anywhere inside the repository's working tree. Written for the
# bash 3.2 floor and deliberately without `set -e`: an unexpected failure must
# not exit 1 and read as a violation.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
RULE_IDS="commit/conventional-subject commit/no-ai-trailer branch/no-wip-files docs/visibility-vision-sections docs/visibility-strategy-sections docs/private-only-type branch/current-with-main"

usage() {
    cat >&2 <<'EOF'
Usage: check-branch-output.sh --commits (--session <s> | --base-ref <ref>)
       check-branch-output.sh --wip
       check-branch-output.sh --docs-visibility (--session <s> | --base-ref <ref>)
       check-branch-output.sh --synced [--base-ref <ref>]

Exit 0 the output passes, 1 a violation (findings on stdout), 2 could not decide.
EOF
}

undecided() {
    echo "check-branch-output: $*" >&2
    exit 2
}

# shellcheck source=../../../scripts/lib/rule-findings.sh
. "$HERE/../../../scripts/lib/rule-findings.sh"

# require_rules <id>...: every rule this mode can report resolves before the
# check runs, so a violation is never reported without its reference.
require_rules() {
    rf_require "$@"
}

VIOLATIONS=0

# finding <rule_id> <detail> [<path> [<line>]]
finding() {
    VIOLATIONS=$((VIOLATIONS + 1))
    rf_finding "$@"
}

# --- arguments ----------------------------------------------------------------

[ $# -ge 1 ] || { usage; exit 2; }
MODE=$1
shift
case "$MODE" in
    --commits|--wip|--docs-visibility|--synced) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac

SESSION=""
BASE_REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session)
            [ $# -ge 2 ] && [ -z "$SESSION" ] || { usage; exit 2; }
            SESSION=$2; shift 2 ;;
        --base-ref)
            [ $# -ge 2 ] && [ -z "$BASE_REF" ] || { usage; exit 2; }
            BASE_REF=$2; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ -n "$SESSION" ]; then
    printf '%s' "$SESSION" | grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._-]*$' \
        || undecided "--session [$SESSION] is not a session name"
fi
if [ -n "$BASE_REF" ]; then
    printf '%s' "$BASE_REF" | grep -Eq '^[A-Za-z0-9._][A-Za-z0-9._/-]*$' \
        && ! printf '%s' "$BASE_REF" | grep -q '\.\.' \
        || undecided "--base-ref [$BASE_REF] is not a ref name"
fi

case "$MODE" in
    --commits|--docs-visibility)
        if [ -n "$SESSION" ] && [ -n "$BASE_REF" ]; then usage; exit 2; fi
        if [ -z "$SESSION" ] && [ -z "$BASE_REF" ]; then usage; exit 2; fi
        ;;
    --wip)
        if [ -n "$SESSION" ] || [ -n "$BASE_REF" ]; then usage; exit 2; fi
        ;;
    --synced)
        [ -z "$SESSION" ] || { usage; exit 2; }
        [ -n "$BASE_REF" ] || BASE_REF=origin/main
        ;;
esac

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || undecided "$tool is not on PATH"
done

ROOT=$(git rev-parse --show-toplevel) || undecided "not inside a git working tree"
cd "$ROOT" || undecided "cannot enter $ROOT"
git rev-parse --verify -q "HEAD^{commit}" >/dev/null || undecided "HEAD does not name a commit"

# resolve_base: sets BASE to the commit the range starts from.
resolve_base() {
    if [ -n "$SESSION" ]; then
        command -v koto >/dev/null || undecided "koto is not on PATH"
        stored=$(koto context get "$SESSION" impl_base | tr -d '[:space:]')
        [ -n "$stored" ] || undecided "session [$SESSION] has no impl_base in koto context"
        BASE=$(git rev-parse --verify -q "${stored}^{commit}") \
            || undecided "impl_base [$stored] is not a commit in this repository"
    else
        git rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null \
            || undecided "--base-ref [$BASE_REF] does not resolve to a commit"
        BASE=$(git merge-base "$BASE_REF" HEAD) \
            || undecided "HEAD shares no history with [$BASE_REF]"
    fi
}

# --- --commits ----------------------------------------------------------------

CONVENTIONAL='^(feat|fix|docs|chore|refactor|test|perf|build|ci|style|revert)(\([^)]+\))?!?: .+'
# U+1F916 (robot face), spelled as bytes so the source stays plain text. PB3
# matches it followed by " generated with".
ROBOT=$(printf '\360\237\244\226')

# is_attributed: reads a commit message on stdin; true when a line of it is an
# AI-attribution line, by PB3's predicate.
is_attributed() {
    LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C awk -v robot="$ROBOT" '
        {
            line = $0
            trimmed = line
            sub(/^[ \t]+/, "", trimmed)
            if (index(trimmed, "co-authored-by:") == 1 && (index(line, "claude") || index(line, "anthropic"))) { hit = 1 }
            if (index(line, "generated with claude code")) { hit = 1 }
            if (index(line, robot " generated with")) { hit = 1 }
        }
        END { exit hit ? 0 : 1 }'
}

check_commits() {
    require_rules commit/conventional-subject commit/no-ai-trailer
    if [ -n "$SESSION" ]; then
        resolve_base
        RANGE="$BASE..HEAD"
    else
        git rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null \
            || undecided "--base-ref [$BASE_REF] does not resolve to a commit"
        RANGE="$BASE_REF..HEAD"
    fi
    list=$(git rev-list --no-merges "$RANGE") \
        || undecided "cannot list the commits in $RANGE"
    count=0
    for sha in $list; do
        count=$((count + 1))
        short=$(printf '%s' "$sha" | cut -c1-12)
        subject=$(git log -1 --format=%s "$sha") \
            || undecided "cannot read commit $sha"
        if ! printf '%s\n' "$subject" | grep -Eq "$CONVENTIONAL"; then
            finding commit/conventional-subject \
                "commit $short subject \"$subject\" is not a Conventional Commits subject: use <type>[optional scope][!]: <description>, with <type> one of feat|fix|docs|chore|refactor|test|perf|build|ci|style|revert"
        fi
        message=$(git log -1 --format=%B "$sha") \
            || undecided "cannot read commit $sha"
        if printf '%s\n' "$message" | is_attributed; then
            finding commit/no-ai-trailer \
                "commit $short carries an AI-attribution line (a Co-Authored-By: trailer naming Claude or Anthropic, or a \"Generated with Claude Code\" line); reword the commit without it"
        fi
    done
    if [ "$VIOLATIONS" -gt 0 ]; then
        echo "check-branch-output: $VIOLATIONS commit violation(s) in $RANGE" >&2
        exit 1
    fi
    echo "check-branch-output: $count commit(s) in $RANGE pass" >&2
    exit 0
}

# --- --wip --------------------------------------------------------------------

check_wip() {
    require_rules branch/no-wip-files
    paths=$(git ls-tree -r --name-only HEAD -- wip/) \
        || undecided "cannot list HEAD's tree"
    if [ -z "$paths" ]; then
        echo "check-branch-output: no wip/ path in HEAD's tree" >&2
        exit 0
    fi
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        finding branch/no-wip-files \
            "$p is under wip/ in HEAD's tree; wip/ files must be removed from the branch before a pull request" "$p"
    done <<EOF
$paths
EOF
    echo "check-branch-output: $VIOLATIONS wip/ path(s) in HEAD's tree" >&2
    exit 1
}

# --- --docs-visibility --------------------------------------------------------

# declared_visibility: the root CLAUDE.local.md / CLAUDE.md header, lowercased,
# parsed as the validator parses it (first well-formed header in a file wins,
# CLAUDE.local.md before CLAUDE.md). Prints nothing when neither declares one.
declared_visibility() {
    for f in CLAUDE.local.md CLAUDE.md; do
        [ -f "$f" ] || continue
        v=$(LC_ALL=C tr '[:upper:]' '[:lower:]' < "$f" | awk '
            {
                line = $0
                sub(/^[ \t]+/, "", line)
                if (index(line, "## repo visibility:") != 1) next
                value = substr(line, length("## repo visibility:") + 1)
                sub(/^[ \t]+/, "", value)
                if (index(value, "private") == 1) { print "private"; exit }
                if (index(value, "public") == 1) { print "public"; exit }
            }')
        if [ -n "$v" ]; then
            printf '%s\n' "$v"
            return 0
        fi
    done
    return 0
}

check_docs_visibility() {
    require_rules docs/visibility-vision-sections docs/visibility-strategy-sections docs/private-only-type
    resolve_base
    changed=$(git diff --name-only --diff-filter=d "$BASE" HEAD -- docs/) \
        || undecided "cannot diff $BASE..HEAD"
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-branch-output.XXXXXX") \
        || undecided "cannot create a temporary directory"
    trap 'rm -rf "$WORK"' EXIT
    : > "$WORK/files"
    n=0
    while IFS= read -r p; do
        case "$p" in
            docs/*.md) [ -f "$p" ] && { printf '%s\n' "$p" >> "$WORK/files"; n=$((n + 1)); } ;;
        esac
    done <<EOF
$changed
EOF
    if [ "$n" -eq 0 ]; then
        echo "check-branch-output: no changed document under docs/" >&2
        exit 0
    fi
    command -v shirabe >/dev/null || undecided "shirabe is not on PATH"

    vis=$(declared_visibility)
    set --
    [ -z "$vis" ] || set -- "--visibility=$vis"
    while IFS= read -r p; do
        set -- "$@" "$p"
    done < "$WORK/files"

    shirabe validate --format json "$@" > "$WORK/out" 2> "$WORK/err"
    rc=$?
    # 0 clean, 2 violations, 4 a schema-skipped document: each still prints the
    # JSON envelope this reads. 1 and 3 are the validator failing to run.
    case "$rc" in
        0|2|4) ;;
        *) undecided "shirabe validate exited $rc: $(tail -n 1 "$WORK/err")" ;;
    esac
    jq -c '.findings[] | select(.code == "R7" or .code == "R8" or .code == "R9")' \
        "$WORK/out" > "$WORK/hits" 2> "$WORK/jq.err" \
        || undecided "cannot read shirabe validate's JSON output: $(tail -n 3 "$WORK/jq.err")"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        code=$(printf '%s' "$hit" | jq -r '.code')
        case "$code" in
            R7) id=docs/visibility-vision-sections ;;
            R8) id=docs/visibility-strategy-sections ;;
            R9) id=docs/private-only-type ;;
        esac
        file=$(printf '%s' "$hit" | jq -r '.file // ""')
        line=$(printf '%s' "$hit" | jq -r '.line // ""')
        msg=$(printf '%s' "$hit" | jq -r '.message // ""')
        finding "$id" "$code: $msg" "$file" "$line"
    done < "$WORK/hits"
    if [ "$VIOLATIONS" -gt 0 ]; then
        echo "check-branch-output: $VIOLATIONS visibility violation(s) in changed documents (visibility: ${vis:-detected})" >&2
        exit 1
    fi
    echo "check-branch-output: $n changed document(s) pass the visibility checks (visibility: ${vis:-detected})" >&2
    exit 0
}

# --- --synced -----------------------------------------------------------------

check_synced() {
    require_rules branch/current-with-main
    git rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null \
        || undecided "[$BASE_REF] does not resolve to a commit"
    git merge-base --is-ancestor "$BASE_REF" HEAD
    rc=$?
    case "$rc" in
        0) ;;
        1)
            finding branch/current-with-main \
                "$BASE_REF is not an ancestor of HEAD: merge it into the branch (never rebase)"
            ;;
        *) undecided "git merge-base --is-ancestor exited $rc" ;;
    esac
    merge_head=$(git rev-parse --git-path MERGE_HEAD) \
        || undecided "cannot locate MERGE_HEAD"
    if [ -e "$merge_head" ]; then
        finding branch/current-with-main \
            "a merge is in progress (MERGE_HEAD exists): finish or abort it before going on"
    fi
    if [ "$VIOLATIONS" -gt 0 ]; then
        echo "check-branch-output: the branch is not current with $BASE_REF" >&2
        exit 1
    fi
    echo "check-branch-output: the branch is current with $BASE_REF" >&2
    exit 0
}

case "$MODE" in
    --commits) check_commits ;;
    --wip) check_wip ;;
    --docs-visibility) check_docs_visibility ;;
    --synced) check_synced ;;
esac
