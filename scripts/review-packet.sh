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
#   code --session <koto-session> [--issue <N> | --criteria <file>]
#       For /work-on's code seats (scrutiny, review, QA, the implementation
#       agent review). Sections, in order:
#         - acceptance criteria: from --criteria <file>, or from issue <N>'s
#           body via `gh issue view` (the `Acceptance Criteria` or `Done when`
#           section when the body has one, the whole body otherwise).
#           --issue is refused when the session is a plan-outline child
#           (created with ISSUE_SOURCE=plan_outline): its issue number is an
#           item in the PLAN, so its criteria come in through --criteria
#         - design context: the session's `context.md`, which phase 0 wrote
#           from the design doc that names the issue, when present
#         - changed paths: `git diff --name-status -M <base> HEAD`
#         - the diff: `git diff -M <base> HEAD`
#       The base is the session's `impl_base` (record-changed-paths.sh --base
#       wrote it on entry to `analysis`), else the merge-base with origin's
#       default branch, else with local main -- the order
#       record-changed-paths.sh --write uses, so the packet and
#       changed_paths.txt describe the same range.
#
#   recheck --session <koto-session> --panel <panel> --seat <seat>
#       For a /work-on seat that panel-scope.sh --plan marked `recheck`: it
#       raised a blocking finding last round and now checks only whether that
#       finding is fixed. <panel> is scrutiny, review, qa or light, as
#       panel-scope.sh names them. The packet is read from the session's
#       `<panel>_scope.json`, from the seat's own decision there. Sections:
#         - findings to re-check: the seat's `findings` as the scope recorded
#           them, every field kept, pretty-printed by jq
#         - changed paths: `git diff --name-status -M <fix_diff_from> HEAD`
#         - the fix diff: `git diff -M <fix_diff_from> HEAD`
#       No acceptance criteria, design context or diff from impl_base: the
#       seat judged those last round, and re-reading them is the cost a
#       re-check exists to avoid. An empty fix diff still writes a packet,
#       saying the diff is empty, so the seat can answer that nothing fixed
#       the finding. A `fix_diff_from` that is absent, not a commit, or not an
#       ancestor of HEAD can't bound the fix, so the diff falls back to the
#       code packet's base (below) and the packet's header says so: wider than
#       a re-check needs, never narrower than the fix.
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
#         --seat `recheck` (commission that seat with the code packet)
#   66 -- a read or write failed: `gh issue view`, `git diff`, or the packet
#         file could not be created or written
#   67 -- usage: missing or unrecognised kind, flag, or flag value, or
#         --issue for a plan-outline child's session
#   127 -- recheck only: jq is not on PATH
#
# On any non-zero exit no packet file is left behind.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

AC_CAP=16384
DESIGN_CAP=24576
PATHS_CAP=16384
DIFF_CAP=98304
FINDINGS_CAP=16384
DOC_CAP=65536
FORMAT_CAP=49152
EXTRA_CAP=32768

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

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
usage: review-packet.sh code --session <koto-session> [--issue <N> | --criteria <file>]
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

# session_issue_source: print the ISSUE_SOURCE variable the session was
# created with (`github`, `plan_outline`, or nothing), read from the
# workflow_initialized event in its koto state log. Prints nothing when the
# log can't be found or read, or jq is absent: the caller then treats --issue
# as it always has, since an issue-backed run must not lose its packet to a
# failed lookup.
session_issue_source() {
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
    jq -r 'select(.type? == "workflow_initialized") | .payload.variables.ISSUE_SOURCE // empty' \
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
        code:--session|code:--issue|code:--criteria|recheck:--session|recheck:--panel|recheck:--seat|doc:--doc|doc:--format|doc:--extra)
            [ $# -ge 1 ] && [ -n "$1" ] || usage "$flag needs a value"
            ;;
        *) usage "unrecognised flag [$flag] for $KIND" ;;
    esac
    case "$flag" in
        --session)  SESSION="$1" ;;
        --issue)    ISSUE="$1" ;;
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
    case "$PANEL" in
        scrutiny|review|qa|light) ;;
        *) usage "unrecognised --panel [$PANEL]: expected scrutiny, review, qa or light" ;;
    esac
    case "$SEAT" in
        *[!a-z]*) usage "--seat must be a seat name in lower case, got [$SEAT]" ;;
    esac
    command -v jq >/dev/null || die 127 "jq not on PATH"
else
    [ -n "$SESSION" ] || usage "code needs --session"
    [ -z "$ISSUE" ] || [ -z "$CRITERIA" ] || usage "code takes --issue or --criteria, not both"
    case "$ISSUE" in
        *[!0-9]*) usage "--issue must be a number, got [$ISSUE]" ;;
    esac
    [ -z "$CRITERIA" ] || [ -f "$CRITERIA" ] || die 64 "criteria file [$CRITERIA] is not a file"
    # A plan-outline child's ISSUE_NUMBER is the item's number in its PLAN,
    # not a GitHub issue, so `gh issue view` on it reads whatever unrelated
    # issue or pull request the repository has under that number.
    if [ -n "$ISSUE" ] && [ "$(session_issue_source)" = plan_outline ]; then
        usage "session [$SESSION] is a plan-outline child: its issue number [$ISSUE] names an item in the PLAN, not a GitHub issue. Write the outline's acceptance criteria to a file and pass --criteria <file> instead of --issue"
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

section() {
    # $1 heading, $2 cap, $3 file, $4 text when the file is empty
    echo
    echo "## $1"
    echo
    if [ -s "$3" ]; then emit_capped "$2" "$3"; else echo "$4"; fi
}

# --------------------------------------------------------------- recheck ------

if [ "$KIND" = "recheck" ]; then
    SCOPE_KEY="${PANEL}_scope.json"
    koto context exists "$SESSION" "$SCOPE_KEY" >/dev/null 2>&1 \
        || die 64 "no $SCOPE_KEY in session [$SESSION]: panel-scope.sh --plan $PANEL has not run, so no seat is marked recheck"
    koto context get "$SESSION" "$SCOPE_KEY" > "$WORK/scope" 2>"$WORK/koto.err" \
        || die 66 "koto context get $SCOPE_KEY failed: $(cat "$WORK/koto.err")"
    jq -c --arg s "$SEAT" '[.decisions[]? | select(.seat == $s)][0] // empty' \
        "$WORK/scope" > "$WORK/decision" 2>/dev/null \
        || die 64 "$SCOPE_KEY is not readable JSON"
    [ -s "$WORK/decision" ] || die 64 "$SCOPE_KEY has no decision for seat [$SEAT]"
    DECISION=$(jq -r '.decision // ""' "$WORK/decision")
    [ "$DECISION" = "recheck" ] \
        || die 64 "$SCOPE_KEY marks seat [$SEAT] [$DECISION], not recheck: commission it with the code packet"
    jq '.findings // []' "$WORK/decision" > "$WORK/findings" \
        || die 66 "could not read the findings for seat [$SEAT]"

    # The fix diff starts where the seat's verdict was given. panel-scope.sh
    # only marks a seat recheck when that commit is an ancestor of HEAD, so
    # each refusal below means the scope was written by hand or by an older
    # script; the fallback widens the diff rather than dropping the fix.
    FROM_RAW=$(jq -r '.fix_diff_from // ""' "$WORK/decision")
    FROM=""
    why=""
    case "$FROM_RAW" in
        "") why="has no fix_diff_from" ;;
        *[!0-9a-f]*) why="has a fix_diff_from [$FROM_RAW] that is not a commit id" ;;
        *)
            if ! FROM=$(git rev-parse --verify -q "${FROM_RAW}^{commit}"); then
                FROM=""
                why="has a fix_diff_from [$FROM_RAW] that is not a commit here"
            elif ! git merge-base --is-ancestor "$FROM" HEAD; then
                FROM=""
                why="has a fix_diff_from [$FROM_RAW] that is not an ancestor of HEAD"
            fi
            ;;
    esac
    if [ -n "$FROM" ]; then
        FROM_SOURCE="fix_diff_from"
    else
        echo "review-packet: seat [$SEAT] in $SCOPE_KEY $why; the fix diff falls back to the code packet's base" >&2
        resolve_base || die 64 "seat [$SEAT] in $SCOPE_KEY $why, and no base resolves to fall back to"
        FROM="$BASE"
        FROM_SOURCE="fallback: the scope $why; $BASE_SOURCE"
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
        echo "fix diff from: $FROM ($FROM_SOURCE)"
        echo "head: $HEAD_SHA"
        echo "changed paths: $PATH_COUNT"
        section "Findings to re-check ($SCOPE_KEY)" "$FINDINGS_CAP" "$WORK/findings" "[none recorded]"
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
    gh issue view "$ISSUE" --json body -q .body > "$WORK/body" 2>"$WORK/gh.err" \
        || die 66 "gh issue view $ISSUE failed: $(cat "$WORK/gh.err")"
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
        AC_SOURCE="issue #$ISSUE, acceptance-criteria section"
    else
        cp "$WORK/body" "$WORK/ac"
        AC_SOURCE="issue #$ISSUE, whole body (no acceptance-criteria heading)"
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

{
    echo "# Review packet: code"
    echo
    echo "base: $BASE ($BASE_SOURCE)"
    echo "head: $HEAD_SHA"
    echo "changed paths: $PATH_COUNT"
    section "Acceptance criteria ($AC_SOURCE)" "$AC_CAP" "$WORK/ac" "[none given]"
    section "Design context ($DESIGN_SOURCE)" "$DESIGN_CAP" "$WORK/design" "[none recorded]"
    section "Changed paths" "$PATHS_CAP" "$WORK/paths" "[no changes between base and HEAD]"
    section "Diff" "$DIFF_CAP" "$WORK/diff" "[empty]"
} > "$PACKET" || die 66 "could not write the packet file"

echo "$PACKET"
exit 0
