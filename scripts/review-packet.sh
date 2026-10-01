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
# Two kinds:
#
#   code --session <koto-session> [--issue <N> | --criteria <file>]
#       For /work-on's code seats (scrutiny, review, QA, the implementation
#       agent review). Sections, in order:
#         - acceptance criteria: from --criteria <file>, or from issue <N>'s
#           body via `gh issue view` (the `Acceptance Criteria` or `Done when`
#           section when the body has one, the whole body otherwise)
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
#         no commit at HEAD, no impl_base and no merge-base)
#   66 -- a read or write failed: `gh issue view`, `git diff`, or the packet
#         file could not be created or written
#   67 -- usage: missing or unrecognised kind, flag, or flag value
#
# On any non-zero exit no packet file is left behind.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

AC_CAP=16384
DESIGN_CAP=24576
PATHS_CAP=16384
DIFF_CAP=98304
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

KIND="${1:-}"
case "$KIND" in
    code|doc) shift ;;
    "") usage "missing kind: expected code or doc" ;;
    *)  usage "unrecognised kind [$KIND]: expected code or doc" ;;
esac

SESSION=""
ISSUE=""
CRITERIA=""
DOC=""
FORMAT=""
# Newline-separated, read back line by line; bash 3.2 has arrays, but an
# empty one trips `set -u` there.
EXTRAS=""

while [ $# -gt 0 ]; do
    flag="$1"
    shift
    case "$KIND:$flag" in
        code:--session|code:--issue|code:--criteria|doc:--doc|doc:--format|doc:--extra)
            [ $# -ge 1 ] && [ -n "$1" ] || usage "$flag needs a value"
            ;;
        *) usage "unrecognised flag [$flag] for $KIND" ;;
    esac
    case "$flag" in
        --session)  SESSION="$1" ;;
        --issue)    ISSUE="$1" ;;
        --criteria) CRITERIA="$1" ;;
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
else
    [ -n "$SESSION" ] || usage "code needs --session"
    [ -z "$ISSUE" ] || [ -z "$CRITERIA" ] || usage "code takes --issue or --criteria, not both"
    case "$ISSUE" in
        *[!0-9]*) usage "--issue must be a number, got [$ISSUE]" ;;
    esac
    [ -z "$CRITERIA" ] || [ -f "$CRITERIA" ] || die 64 "criteria file [$CRITERIA] is not a file"
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

# ------------------------------------------------------------------ code ------

git rev-parse --git-dir >/dev/null 2>&1 || die 64 "not inside a git repository"
HEAD_SHA=$(git rev-parse --verify -q "HEAD^{commit}") || die 64 "HEAD does not name a commit"

BASE=""
BASE_SOURCE=""
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
[ -n "$BASE" ] || die 64 "no base resolves: impl_base is unset and HEAD shares no history with origin's default branch or local main"

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

section() {
    # $1 heading, $2 cap, $3 file, $4 text when the file is empty
    echo
    echo "## $1"
    echo
    if [ -s "$3" ]; then emit_capped "$2" "$3"; else echo "$4"; fi
}

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
