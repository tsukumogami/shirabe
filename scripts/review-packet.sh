#!/usr/bin/env bash
# review-packet.sh -- assemble the fixed input packet a review seat reads.
#
# A review seat that starts from a role name and nothing else explores: it
# reads skill references, the repository and design docs turn after turn, and
# every turn re-reads the growing context. The packet is the bounded input the
# seat starts from instead, assembled here by a script so the orchestrating
# agent never pastes documents into a prompt and never decides what a seat
# sees. The commissioning contract that tells each spawn site to use it is
# references/review-seat-commissioning.md.
#
# Three kinds:
#
#   code --session <koto-session>
#        [--issue <N> --issue-repo <owner/repo> | --criteria <file>]
#        [--panel <panel> --seat <seat>]
#       For /work-on's code seats (scrutiny, review, QA, the implementation
#       agent review). Sections, in order:
#         - acceptance criteria: from --criteria <file>, or from issue <N>'s
#           body via `gh issue view` (the `Acceptance Criteria` or `Done when`
#           section when the body has one, the whole body otherwise).
#           --issue is refused when the session is a plan-outline child
#           (created with ISSUE_SOURCE=plan_outline): its issue number is an
#           item in the PLAN, so its criteria come in through --criteria.
#           --issue needs --issue-repo, the run's ISSUE_REPO as the panel's
#           directive gives it: empty for an issue in this repository, and
#           owner/repo for one elsewhere, which is read from there with
#           `gh issue view <N> --repo <owner/repo>`. The value is never
#           looked up or guessed: reading this repository's issue N for an
#           issue elsewhere would hand the seats another issue's criteria
#         - design context: the session's `context.md`, which phase 0 wrote
#           from the design doc that names the issue, when present
#         - changed paths: `git diff --name-status -M <base> HEAD`
#         - test changes (`## Test changes`): the test files the change
#           touched, as scripts/lib/test-classify.sh's test_classify_unit
#           labels them over the same range, with the session's stored rules
#           copy (`review_level_rules.tsv`, else the shipped
#           review-level-rules.tsv) and, for a fix, the red's record
#           (`red_first.json`): added tests by path, edited tests by path,
#           then each edited test's hunks. "none" when the change touches no
#           test file. Every seat judges each edited test in its verdict's
#           `test_edits`, and panel-scope.sh --record refuses a round that
#           doesn't
#         - the diff: `git diff -M <base> HEAD`
#         - with --panel and --seat, the seat's unclosed findings: the
#           `findings` its decision in `<panel>_scope.json` carries, which
#           panel-scope.sh --plan hands a seat in a full round so it answers
#           each by id. "[none]" when the decision carries none
#       The base is the session's `impl_base` (record-changed-paths.sh --base
#       wrote it on entry to `analysis`), else the merge-base with origin's
#       default branch, else with local main -- the order
#       record-changed-paths.sh --write uses, so the packet and
#       changed_paths.txt describe the same range.
#
#   recheck --session <koto-session> --panel <panel> --seat <seat>
#       For the run panel-scope.sh --plan marked `recheck`: the panel's
#       re-verifier (seat `reverifier`), which answers each due finding by id
#       and, when its decision says so, reviews the fix diff. <panel> is
#       scrutiny, review, qa or light, as panel-scope.sh names them. The
#       packet is read from the session's `<panel>_scope.json`, from the
#       seat's own decision there. Its header says whether the decision
#       carries the fix-diff review (`fix review:`) and, when it does, where
#       that review's range starts (`review from:`). Sections:
#         - findings to re-verify: the decision's `findings`, every field
#           kept (id, summary, location, raiser, status, why it is due),
#           pretty-printed by jq
#         - with a fix-diff review, every panel's blocking criteria: the
#           scrutiny and review seats' questions and the QA tester's steps,
#           read from the shipped phase files, since this one review stands
#           in for every panel the retry re-enters
#         - with a fix-diff review, the review range's changed paths:
#           `git diff --name-status -M <review_from> HEAD`
#         - changed paths: `git diff --name-status -M <fix_diff_from> HEAD`
#         - the fix diff: `git diff -M <fix_diff_from> HEAD`
#       No acceptance criteria, design context or diff from impl_base: the
#       seats judged those already, and re-reading them is the cost a
#       re-verification exists to avoid. An empty fix diff still writes a
#       packet, saying the diff is empty, so the run can answer that nothing
#       fixed a finding. A `fix_diff_from` or `review_from` that is absent,
#       not a commit, or not an ancestor of HEAD can't bound the fix, so it
#       falls back to the code packet's base (below) and the packet's header
#       says so: wider than a re-verification needs, never narrower than the
#       fix.
#
#   doc --doc <path> --format <reference> [--extra <path>]...
#       For the jury seats. The document under review, its format reference,
#       and any supporting files the spawn site names (a scope file, an
#       upstream document). --doc and --extra resolve against the working
#       directory, which is the repository the document lives in. A relative
#       --format resolves against the plugin root, because format references
#       ship with shirabe, not with the repository under review. A missing
#       --extra is recorded as absent in the packet rather than failing: scope
#       files are wip/ artifacts that a resumed or child run may not have.
#
# Each section is capped (the *_CAP values below). A cut section ends with a
# `[truncated: kept K of T bytes ...]` line, so the seat knows there is more
# and can read the source if a finding needs it. The changed-path list has its
# own cap, separate from the diff's, so a truncated diff still names every
# file it touched.
#
# ## Output
#
# The packet is written to a fresh `mktemp` file outside the repository; its
# path is the only line on stdout. The caller passes that path to the seats
# and deletes the file once the round is aggregated, as with the seats'
# detail files. Diagnostics go to stderr.
#
# Exit codes:
#   0  -- packet written; its path is on stdout
#   64 -- an input the packet needs does not exist: --doc, --format or
#         --criteria is not a file, or no base resolves (not a git repository,
#         no commit at HEAD, no impl_base and no merge-base); for recheck,
#         `<panel>_scope.json` is absent or not JSON, or it does not mark
#         --seat `recheck` (commission that seat with the code packet); for
#         code with --seat, `<panel>_scope.json` is absent or not JSON, or has
#         no decision for --seat
#   66 -- a read or write failed: `gh issue view`, `git diff`, or the packet
#         file could not be created or written
#   67 -- usage: missing or unrecognised kind, flag, or flag value,
#         --issue without --issue-repo or the other way round, an
#         --issue-repo that is neither empty nor owner/repo, or --issue for
#         a plan-outline child's session
#   127 -- recheck, or code with --seat: jq is not on PATH
#
# On any non-zero exit no packet file is left behind.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

AC_CAP=16384
DESIGN_CAP=24576
PATHS_CAP=16384
DIFF_CAP=98304
TESTS_CAP=49152
FINDINGS_CAP=16384
DOC_CAP=65536
FORMAT_CAP=49152
EXTRA_CAP=32768

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=lib/test-classify.sh
. "$SCRIPT_DIR/lib/test-classify.sh" || { echo "review-packet: cannot load lib/test-classify.sh" >&2; exit 66; }

PACKET=""
WORK=""
cleanup() {
    [ -z "$WORK" ] || rm -rf "$WORK"
}
trap cleanup EXIT

die() {
    # $1 exit code, $2 message. A failure never leaves a half-written packet.
    [ -z "$PACKET" ] || rm -f "$PACKET"
    echo "review-packet: $2" >&2
    exit "$1"
}

usage() {
    die 67 "$1
usage: review-packet.sh code --session <koto-session> [--issue <N> --issue-repo <owner/repo> | --criteria <file>] [--panel <panel> --seat <seat>]
       review-packet.sh recheck --session <koto-session> --panel <panel> --seat <seat>
       review-packet.sh doc --doc <path> --format <reference> [--extra <path>]..."
}

# emit_capped <cap> <file>: print the file cut at <cap> bytes on a line
# boundary, with a trailer when anything was cut. LC_ALL=C makes awk count
# bytes, not characters.
emit_capped() {
    local cap="$1" file="$2" total kept
    total=$(wc -c < "$file" | tr -d '[:space:]')
    if [ "$total" -le "$cap" ]; then
        cat "$file"
        # A section always ends on a newline, so the next heading starts a line.
        if [ "$total" -gt 0 ] && [ -n "$(tail -c 1 "$file")" ]; then
            echo
        fi
        return 0
    fi
    LC_ALL=C awk -v cap="$cap" '
        { n = length($0) + 1; if (used + n > cap) exit; used += n; print }
    ' "$file"
    kept=$(LC_ALL=C awk -v cap="$cap" '
        { n = length($0) + 1; if (used + n > cap) exit; used += n }
        END { print used + 0 }
    ' "$file")
    echo "[truncated: kept $kept of $total bytes; read the source directly if a finding needs the rest]"
}

# session_source: print the ISSUE_SOURCE variable the session was created
# with, read from the workflow_initialized event in its koto state log.
# Prints nothing when the session has none, the log can't be found or read,
# or jq is absent: the caller then treats --issue as it always has, a GitHub
# issue, since an issue-backed run must not lose its packet to a failed
# lookup.
session_source() {
    local dir log v
    command -v jq >/dev/null 2>&1 || return 0
    dir=$(koto session dir "$SESSION" 2>/dev/null) || return 0
    log="$dir/koto-$SESSION.state.jsonl"
    [ -r "$log" ] || return 0
    v=$(head -n 1 "$log" | jq -c '.schema_version' 2>/dev/null)
    if [ "$v" != 1 ]; then
        # Loud, because the plan-outline check goes quiet with it.
        echo "review-packet: $SESSION's log header has schema_version ${v:-none}; this reader knows 1, so --issue is not checked against ISSUE_SOURCE" >&2
        return 0
    fi
    jq -r 'select(.type? == "workflow_initialized") | .payload.variables.ISSUE_SOURCE // ""' \
        "$log" 2>/dev/null | head -n 1
}

KIND="${1:-}"
case "$KIND" in
    code|recheck|doc) shift ;;
    "") usage "missing kind: expected code, recheck or doc" ;;
    *)  usage "unrecognised kind [$KIND]: expected code, recheck or doc" ;;
esac

SESSION=""
ISSUE=""
# The issue's repository, from --issue-repo; empty for an issue in this
# repository. An empty value is a real answer, so whether the flag came at
# all is kept apart from it.
ISSUE_REPO=""
ISSUE_REPO_GIVEN=0
CRITERIA=""
DOC=""
FORMAT=""
PANEL=""
SEAT=""
# Newline-separated, read back line by line; bash 3.2 has arrays, but an
# empty one trips `set -u` there.
EXTRAS=""

while [ $# -gt 0 ]; do
    flag="$1"
    shift
    case "$KIND:$flag" in
        code:--session|code:--issue|code:--criteria|code:--panel|code:--seat|recheck:--session|recheck:--panel|recheck:--seat|doc:--doc|doc:--format|doc:--extra)
            [ $# -ge 1 ] && [ -n "$1" ] || usage "$flag needs a value"
            ;;
        code:--issue-repo)
            [ $# -ge 1 ] || usage "$flag needs a value, empty for an issue in this repository"
            ;;
        *) usage "unrecognised flag [$flag] for $KIND" ;;
    esac
    case "$flag" in
        --session)  SESSION="$1" ;;
        --issue)    ISSUE="$1" ;;
        --issue-repo) ISSUE_REPO="$1"; ISSUE_REPO_GIVEN=1 ;;
        --criteria) CRITERIA="$1" ;;
        --panel)    PANEL="$1" ;;
        --seat)     SEAT="$1" ;;
        --doc)      DOC="$1" ;;
        --format)   FORMAT="$1" ;;
        --extra)    EXTRAS="$EXTRAS$1
" ;;
    esac
    shift
done

# check_panel_seat: --panel and --seat name a panel and a seat as
# panel-scope.sh names them, before either reaches jq or a context key name.
check_panel_seat() {
    case "$PANEL" in
        scrutiny|review|qa|light) ;;
        *) usage "unrecognised --panel [$PANEL]: expected scrutiny, review, qa or light" ;;
    esac
    case "$SEAT" in
        *[!a-z]*) usage "--seat must be a seat name in lower case, got [$SEAT]" ;;
    esac
}

# Validate before creating anything on disk.
if [ "$KIND" = "doc" ]; then
    [ -n "$DOC" ] || usage "doc needs --doc"
    [ -n "$FORMAT" ] || usage "doc needs --format"
    [ -f "$DOC" ] || die 64 "document under review [$DOC] is not a file"
    case "$FORMAT" in
        /*) FORMAT_PATH="$FORMAT" ;;
        *)  FORMAT_PATH="$PLUGIN_ROOT/$FORMAT" ;;
    esac
    [ -f "$FORMAT_PATH" ] || die 64 "format reference [$FORMAT] is not a file (resolved to $FORMAT_PATH)"
elif [ "$KIND" = "recheck" ]; then
    [ -n "$SESSION" ] || usage "recheck needs --session"
    [ -n "$PANEL" ] || usage "recheck needs --panel"
    [ -n "$SEAT" ] || usage "recheck needs --seat"
    check_panel_seat
    command -v jq >/dev/null || die 127 "jq not on PATH"
else
    [ -n "$SESSION" ] || usage "code needs --session"
    if [ -n "$PANEL$SEAT" ]; then
        [ -n "$PANEL" ] && [ -n "$SEAT" ] || usage "code takes --panel and --seat together"
        check_panel_seat
        command -v jq >/dev/null || die 127 "jq not on PATH"
    fi
    [ -z "$ISSUE" ] || [ -z "$CRITERIA" ] || usage "code takes --issue or --criteria, not both"
    case "$ISSUE" in
        *[!0-9]*) usage "--issue must be a number, got [$ISSUE]" ;;
    esac
    [ -z "$CRITERIA" ] || [ -f "$CRITERIA" ] || die 64 "criteria file [$CRITERIA] is not a file"
    if [ -n "$ISSUE" ]; then
        [ "$ISSUE_REPO_GIVEN" = 1 ] \
            || usage "--issue needs --issue-repo: the run's ISSUE_REPO as the panel's directive gives it, empty for an issue in this repository"
        # koto checks ISSUE_REPO's pattern at init; checked again because the
        # value reaches a gh argument. [[ =~ ]] anchors on the whole string,
        # so a value with a newline can't pass on its first line alone.
        RE_REPO='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
        if [ -n "$ISSUE_REPO" ] && ! [[ $ISSUE_REPO =~ $RE_REPO ]]; then
            usage "--issue-repo [$ISSUE_REPO] is not owner/repo"
        fi
        # A plan-outline child's ISSUE_NUMBER is the item's number in its
        # PLAN, not a GitHub issue, so `gh issue view` on it reads whatever
        # unrelated issue or pull request the repository has under that
        # number.
        if [ "$(session_source)" = plan_outline ]; then
            usage "session [$SESSION] is a plan-outline child: its issue number [$ISSUE] names an item in the PLAN, not a GitHub issue. Write the outline's acceptance criteria to a file and pass --criteria <file> instead of --issue"
        fi
    elif [ "$ISSUE_REPO_GIVEN" = 1 ]; then
        usage "--issue-repo goes with --issue"
    fi
fi

WORK=$(mktemp -d) || die 66 "could not create a temporary directory"
PACKET=$(mktemp "${TMPDIR:-/tmp}/review-packet.XXXXXX") || { PACKET=""; die 66 "could not create the packet file"; }

# ------------------------------------------------------------------ doc -------

if [ "$KIND" = "doc" ]; then
    {
        echo "# Review packet: document"
        echo
        echo "## Document under review: $DOC"
        echo
        emit_capped "$DOC_CAP" "$DOC"
        echo
        echo "## Format reference: $FORMAT"
        echo
        emit_capped "$FORMAT_CAP" "$FORMAT_PATH"
        printf '%s' "$EXTRAS" | while IFS= read -r extra; do
            echo
            echo "## Supporting: $extra"
            echo
            if [ -f "$extra" ]; then
                emit_capped "$EXTRA_CAP" "$extra"
            else
                echo "[absent: $extra does not exist in this checkout]"
            fi
        done
    } > "$PACKET" || die 66 "could not write the packet file"
    echo "$PACKET"
    exit 0
fi

# ------------------------------------------------------- code and recheck ----

git rev-parse --git-dir >/dev/null 2>&1 || die 64 "not inside a git repository"
HEAD_SHA=$(git rev-parse --verify -q "HEAD^{commit}") || die 64 "HEAD does not name a commit"

# resolve_base: sets BASE and BASE_SOURCE to the code packet's base, or
# returns 1 when none resolves. A recheck packet calls it only when its own
# fix_diff_from can't bound the fix.
BASE=""
BASE_SOURCE=""
resolve_base() {
    local stored default_ref
    if koto context exists "$SESSION" impl_base >/dev/null 2>&1; then
        stored=$(koto context get "$SESSION" impl_base 2>/dev/null | tr -d '[:space:]')
        if [ -n "$stored" ] && BASE=$(git rev-parse --verify -q "${stored}^{commit}"); then
            BASE_SOURCE="impl_base"
        else
            BASE=""
            echo "review-packet: impl_base [$stored] is not a commit here; falling back to the merge-base" >&2
        fi
    fi
    if [ -z "$BASE" ]; then
        default_ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
        if [ -z "$default_ref" ] && git rev-parse --verify -q "refs/remotes/origin/main^{commit}" >/dev/null; then
            default_ref=origin/main
        fi
        if [ -n "$default_ref" ] && BASE=$(git merge-base HEAD "$default_ref" 2>/dev/null); then
            BASE_SOURCE="merge-base with $default_ref"
        fi
        if [ -z "$BASE" ] && git rev-parse --verify -q "refs/heads/main^{commit}" >/dev/null \
            && BASE=$(git merge-base HEAD main 2>/dev/null); then
            BASE_SOURCE="merge-base with main"
        fi
    fi
    [ -n "$BASE" ]
}

# test_changes: the code packet's `## Test changes` body on stdout, empty when
# the change touches no test file. Added tests by path, then edited tests by
# path, then each edited test's hunks. The lists come first so a cap cuts only
# hunks, never the names of the tests a seat must judge.
test_changes() {
    local rules="$WORK/rules" record="$WORK/red" tab label path digest old
    tab=$(printf '\t')
    : > "$rules"
    if koto context exists "$SESSION" review_level_rules.tsv >/dev/null 2>&1; then
        koto context get "$SESSION" review_level_rules.tsv > "$rules" 2>/dev/null || : > "$rules"
    fi
    [ -s "$rules" ] || cp "$PLUGIN_ROOT/skills/work-on/references/review-level-rules.tsv" "$rules" 2>/dev/null || : > "$rules"
    # A rules file with no test class has no test files to list.
    awk -F '\t' '$1 == "class" && $2 == "test" && $3 != "" { f = 1 } END { exit !f }' "$rules" || return 0
    : > "$record"
    if koto context exists "$SESSION" red_first.json >/dev/null 2>&1; then
        koto context get "$SESSION" red_first.json > "$record" 2>/dev/null || : > "$record"
    fi
    test_classify_unit "$BASE" "$HEAD_SHA" "$rules" "$record" > "$WORK/testrows" 2>"$WORK/classify.err" || return 1
    [ -s "$WORK/testrows" ] || return 0
    awk -F '\t' '$1 == "added" { print $2 }' "$WORK/testrows" > "$WORK/added"
    awk -F '\t' '$1 == "edited" { print $2 }' "$WORK/testrows" > "$WORK/edited"
    echo "Added (new tests, or tests that only gained lines):"
    echo
    if [ -s "$WORK/added" ]; then sed 's/^/- /' "$WORK/added"; else echo "- none"; fi
    echo
    echo "Edited (a line removed or changed, the file deleted or renamed with a change, or a"
    echo "fix's reproducing test changed after its red). Judge each one as corrects or weakens"
    echo "in your verdict's test_edits:"
    echo
    if [ -s "$WORK/edited" ]; then sed 's/^/- /' "$WORK/edited"; else echo "- none"; fi
    while IFS="$tab" read -r label path digest; do
        [ "$label" = edited ] || continue
        # A rename's hunks need its old path in the pathspec as well.
        old=$(awk -F '\t' -v p="$path" '$1 ~ /^R/ && $3 == p { print $2; exit }' "$WORK/paths")
        echo
        echo "### Edited: $path"
        echo
        echo '```diff'
        if [ -n "$old" ]; then
            git diff -M "$BASE" "$HEAD_SHA" -- "$old" "$path"
        else
            git diff -M "$BASE" "$HEAD_SHA" -- "$path"
        fi
        echo '```'
    done < "$WORK/testrows"
}

section() {
    # $1 heading, $2 cap, $3 file, $4 text when the file is empty
    echo
    echo "## $1"
    echo
    if [ -s "$3" ]; then emit_capped "$2" "$3"; else echo "$4"; fi
}

# scope_decision: the session's <panel>_scope.json in $WORK/scope and --seat's
# decision there in $WORK/decision, or exit 64 saying which is missing.
scope_decision() {
    SCOPE_KEY="${PANEL}_scope.json"
    koto context exists "$SESSION" "$SCOPE_KEY" >/dev/null 2>&1 \
        || die 64 "no $SCOPE_KEY in session [$SESSION]: panel-scope.sh --plan $PANEL has not run, so no seat has a decision"
    koto context get "$SESSION" "$SCOPE_KEY" > "$WORK/scope" 2>"$WORK/koto.err" \
        || die 66 "koto context get $SCOPE_KEY failed: $(cat "$WORK/koto.err")"
    jq -c --arg s "$SEAT" '[.decisions[]? | select(.seat == $s)][0] // empty' \
        "$WORK/scope" > "$WORK/decision" 2>/dev/null \
        || die 64 "$SCOPE_KEY is not readable JSON"
    [ -s "$WORK/decision" ] || die 64 "$SCOPE_KEY has no decision for seat [$SEAT]"
}

# bound <field>: the decision's <field> as the commit a diff to HEAD starts
# from, in BOUND, with BOUND_SOURCE naming where it came from. panel-scope.sh
# writes only ancestors of HEAD there, so each refusal below means the scope
# was written by hand or by an older script; the fallback to the code
# packet's base widens the diff rather than dropping the fix, and says so.
BOUND=""
BOUND_SOURCE=""
bound() {
    local field="$1" raw why=""
    raw=$(jq -r --arg f "$field" '.[$f] // ""' "$WORK/decision")
    BOUND=""
    case "$raw" in
        "") why="has no $field" ;;
        *[!0-9a-f]*) why="has a $field [$raw] that is not a commit id" ;;
        *)
            if ! BOUND=$(git rev-parse --verify -q "${raw}^{commit}"); then
                BOUND=""
                why="has a $field [$raw] that is not a commit here"
            elif ! git merge-base --is-ancestor "$BOUND" HEAD; then
                BOUND=""
                why="has a $field [$raw] that is not an ancestor of HEAD"
            fi
            ;;
    esac
    if [ -n "$BOUND" ]; then
        BOUND_SOURCE="$field"
        return 0
    fi
    echo "review-packet: seat [$SEAT] in $SCOPE_KEY $why; the diff falls back to the code packet's base" >&2
    resolve_base || die 64 "seat [$SEAT] in $SCOPE_KEY $why, and no base resolves to fall back to"
    BOUND="$BASE"
    BOUND_SOURCE="fallback: the scope $why; $BASE_SOURCE"
}

# panel_criteria: every panel's blocking criteria, as the shipped phase files
# state them -- the scrutiny and review seats' questions and the QA tester's
# steps -- for the fix-diff review, which stands in for every panel a retry
# re-enters. Read from the files so the packet never drifts from them.
panel_criteria() {
    local entry file title
    for entry in phase-4a-scrutiny.md:Scrutiny phase-4b-review.md:Review phase-4c-qa.md:QA; do
        file="$PLUGIN_ROOT/skills/work-on/references/phases/${entry%%:*}"
        title=${entry#*:}
        echo "### $title"
        echo
        if [ -r "$file" ]; then
            awk '/^## (Reviewers|Tester Agent)$/ { on = 1; next }
                 on && /^## / { exit }
                 on && (/^- \*\*/ || /^[0-9]+\. /) { print; n++ }
                 END { if (n == 0) print "[missing: no criteria found under ## Reviewers or ## Tester Agent in this phase file; judge the fix against the acceptance criteria instead]" }' "$file"
        else
            echo "[absent: ${entry%%:*} is not in this checkout]"
        fi
        echo
    done
}

# --------------------------------------------------------------- recheck ------

if [ "$KIND" = "recheck" ]; then
    scope_decision
    DECISION=$(jq -r '.decision // ""' "$WORK/decision")
    [ "$DECISION" = "recheck" ] \
        || die 64 "$SCOPE_KEY marks seat [$SEAT] [$DECISION], not recheck: commission it with the code packet"
    jq '.findings // []' "$WORK/decision" > "$WORK/findings" \
        || die 66 "could not read the findings for seat [$SEAT]"
    [ "$(jq 'length' "$WORK/findings")" != 0 ] || : > "$WORK/findings"

    # The fix diff starts at the oldest commit the findings were last judged
    # at; the fix-diff review's range at the newest commit any panel recorded.
    bound fix_diff_from
    FROM="$BOUND"
    FROM_SOURCE="$BOUND_SOURCE"
    FIX_REVIEW=no
    if [ "$(jq -r '.fix_review // false' "$WORK/decision")" = true ]; then
        FIX_REVIEW=yes
        bound review_from
        REVIEW_FROM="$BOUND"
        REVIEW_SOURCE="$BOUND_SOURCE"
        git diff --name-status -M "$REVIEW_FROM" HEAD > "$WORK/rpaths" \
            || die 66 "git diff --name-status -M $REVIEW_FROM HEAD failed"
        panel_criteria > "$WORK/criteria"
    fi

    git diff --name-status -M "$FROM" HEAD > "$WORK/paths" \
        || die 66 "git diff --name-status -M $FROM HEAD failed"
    git diff -M "$FROM" HEAD > "$WORK/diff" \
        || die 66 "git diff -M $FROM HEAD failed"
    PATH_COUNT=$(wc -l < "$WORK/paths" | tr -d '[:space:]')

    {
        echo "# Review packet: recheck"
        echo
        echo "panel: $PANEL"
        echo "seat: $SEAT"
        echo "fix review: $FIX_REVIEW"
        [ "$FIX_REVIEW" = no ] || echo "review from: $REVIEW_FROM ($REVIEW_SOURCE)"
        echo "fix diff from: $FROM ($FROM_SOURCE)"
        echo "head: $HEAD_SHA"
        echo "changed paths: $PATH_COUNT"
        section "Findings to re-verify, by id ($SCOPE_KEY)" "$FINDINGS_CAP" "$WORK/findings" "[none due]"
        if [ "$FIX_REVIEW" = yes ]; then
            section "Every panel's blocking criteria (the fix-diff review)" "$AC_CAP" "$WORK/criteria" "[none found]"
            section "Changed paths (fix-diff review, from $REVIEW_FROM)" "$PATHS_CAP" "$WORK/rpaths" "[no changes between $REVIEW_FROM and HEAD]"
        fi
        section "Changed paths (fix diff)" "$PATHS_CAP" "$WORK/paths" "[no changes between $FROM and HEAD]"
        section "Fix diff" "$DIFF_CAP" "$WORK/diff" "[empty: no commit since $FROM changes anything]"
    } > "$PACKET" || die 66 "could not write the packet file"
    echo "$PACKET"
    exit 0
fi

# ------------------------------------------------------------------ code ------

resolve_base || die 64 "no base resolves: impl_base is unset and HEAD shares no history with origin's default branch or local main"

# Acceptance criteria.
if [ -n "$CRITERIA" ]; then
    cp "$CRITERIA" "$WORK/ac" || die 66 "could not read criteria file [$CRITERIA]"
    AC_SOURCE="$CRITERIA"
elif [ -n "$ISSUE" ]; then
    # An issue in another repository is read from there, and named with its
    # repository wherever the packet names it.
    if [ -n "$ISSUE_REPO" ]; then
        ISSUE_REF="$ISSUE_REPO#$ISSUE"
        gh issue view "$ISSUE" --repo "$ISSUE_REPO" --json body -q .body > "$WORK/body" 2>"$WORK/gh.err" \
            || die 66 "gh issue view $ISSUE --repo $ISSUE_REPO failed: $(cat "$WORK/gh.err")"
    else
        ISSUE_REF="#$ISSUE"
        gh issue view "$ISSUE" --json body -q .body > "$WORK/body" 2>"$WORK/gh.err" \
            || die 66 "gh issue view $ISSUE failed: $(cat "$WORK/gh.err")"
    fi
    # The section under an `Acceptance Criteria` or `Done when` heading, up to
    # the next heading at the same level or above. No such heading: the body.
    if awk '
        /^#+[ \t]/ {
            level = match($0, /[^#]/) - 1
            if (inside && level <= start) inside = 0
            if (!inside && tolower($0) ~ /^#+[ \t]+(acceptance criteria|done when)/) {
                inside = 1; start = level; found = 1
            }
        }
        inside { print }
        END { exit found ? 0 : 3 }
    ' "$WORK/body" > "$WORK/ac"; then
        AC_SOURCE="issue $ISSUE_REF, acceptance-criteria section"
    else
        cp "$WORK/body" "$WORK/ac"
        AC_SOURCE="issue $ISSUE_REF, whole body (no acceptance-criteria heading)"
    fi
else
    : > "$WORK/ac"
    AC_SOURCE="none given"
fi

# Design context: what phase 0 extracted, when it ran.
DESIGN_SOURCE="none recorded"
: > "$WORK/design"
if koto context exists "$SESSION" context.md >/dev/null 2>&1; then
    if koto context get "$SESSION" context.md > "$WORK/design" 2>/dev/null; then
        DESIGN_SOURCE="koto context.md"
    else
        : > "$WORK/design"
    fi
fi

git diff --name-status -M "$BASE" HEAD > "$WORK/paths" \
    || die 66 "git diff --name-status -M $BASE HEAD failed"
git diff -M "$BASE" HEAD > "$WORK/diff" \
    || die 66 "git diff -M $BASE HEAD failed"
PATH_COUNT=$(wc -l < "$WORK/paths" | tr -d '[:space:]')

# Test changes: the shared classifier's rows over the same range, with the
# session's rules copy (the shipped file when none is stored) and, for a fix,
# the red's record, so the packet names the same edited tests the review
# floor, the round's required judgments and the hold do.
test_changes > "$WORK/tests" || die 66 "could not classify the change's test files: $(head -c 300 "$WORK/classify.err")"

# A seat in a full round answers its own unclosed findings by id: the ones its
# decision carries.
: > "$WORK/own"
if [ -n "$SEAT" ]; then
    scope_decision
    jq '.findings // []' "$WORK/decision" > "$WORK/own" \
        || die 66 "could not read the findings for seat [$SEAT]"
    [ "$(jq 'length' "$WORK/own")" != 0 ] || : > "$WORK/own"
fi

{
    echo "# Review packet: code"
    echo
    echo "base: $BASE ($BASE_SOURCE)"
    echo "head: $HEAD_SHA"
    echo "changed paths: $PATH_COUNT"
    section "Acceptance criteria ($AC_SOURCE)" "$AC_CAP" "$WORK/ac" "[none given]"
    section "Design context ($DESIGN_SOURCE)" "$DESIGN_CAP" "$WORK/design" "[none recorded]"
    section "Changed paths" "$PATHS_CAP" "$WORK/paths" "[no changes between base and HEAD]"
    section "Test changes" "$TESTS_CAP" "$WORK/tests" "none"
    section "Diff" "$DIFF_CAP" "$WORK/diff" "[empty]"
    if [ -n "$SEAT" ]; then
        section "Your unclosed findings, by id ($SCOPE_KEY, seat $SEAT)" "$FINDINGS_CAP" "$WORK/own" "[none]"
    fi
} > "$PACKET" || die 66 "could not write the packet file"

echo "$PACKET"
exit 0
