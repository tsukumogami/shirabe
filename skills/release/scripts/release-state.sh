#!/usr/bin/env bash
# release-state.sh -- the session logic /release runs on the keys of
# release-<topic>.
#
# /release keeps what Phase 1 derives as keys in the koto session
# release-<topic> (references/skill-session-convention.md), because each phase
# runs in a new shell and a shell variable set in Phase 1 is gone by Phase 2.
# The rules that compute or read that state live here, so a test can run
# them on the real path; plain open, put, get and close calls stay in the prose
# as direct skill-session.sh calls. This script reaches the session through
# scripts/skill-session.sh (found relative to this file) and `koto context`,
# and never touches the staging folder.
#
# Usage:
#   release-state.sh topic
#   release-state.sh membership <topic>
#   release-state.sh read <topic> <range|prs|unattributed|notes|head|check-notes|assets>
#   release-state.sh version <value>
#   release-state.sh go <topic> [--unresolved]
#   release-state.sh mark <topic> dispatched <version>
#   release-state.sh mark <topic> concluded <success|failure|timeout>
#   release-state.sh check-notes <topic> <output-file>
#   release-state.sh carries <topic> <notes-file>
#   release-state.sh asset <topic> <output-file>
#   release-state.sh upload <topic> <version>
#
# Arguments (checked before any koto call):
#   <topic>   ^[a-z0-9][a-z0-9-]*$; `topic` prints one.
#   <value>   a version as the author typed it or chose it at the go.
#
# Subcommands and their output (stdout carries machine-readable lines or the
# key's content only; messages go to stderr):
#
#   topic        prints <owner>-<name> for the repository `gh repo view --json
#             owner,name` names: lowercased, each run of characters outside
#             [a-z0-9] turned into one -, leading and trailing - removed
#             (tsukumogami-shirabe). The owner keeps two same-named
#             repositories on one machine apart. An empty result is refused
#             (refused=empty_topic). Needs gh and jq; no koto call.
#
#   membership   in the live release-<topic>, from the git repository in the
#             current directory, computes what the release contains and writes
#             it as four keys, replacing any value an earlier run left:
#               work/range          the last v* tag's range <tag>..HEAD, or
#                                   HEAD when no v* tag exists (a first release)
#               work/prs            the pull request numbers named by "(#N)"
#                                   at the end of a subject in the range, one
#                                   per line, numerically sorted, unique
#               work/unattributed   "<short hash> <subject>" for each commit in
#                                   the range whose subject names no pull
#                                   request
#               work/head           the full hash of HEAD, the commit the
#                                   release is cut from; after-release.sh reads
#                                   the committed extension there
#             and writes work/check-notes and work/assets empty, for
#             check-notes and asset to add to.
#             A list with nothing in it is an empty key. It also removes the
#             keys a later phase writes (work/notes.md, work/dispatched,
#             work/concluded, work/after, work/after-go) when an earlier run
#             left them, so a crashed run's notes can't be published and its
#             dispatch can't start this run's installs. Prints
#               range=<range>
#               prs=<count>
#               unattributed=<count>
#
#   read         prints the key's content as stored (range -> work/range,
#             prs -> work/prs, unattributed -> work/unattributed, notes ->
#             work/notes.md, head -> work/head, check-notes -> work/check-notes,
#             assets -> work/assets), or exits 1 with "Phase 1 did not run" on stderr
#             when the key is absent. An empty key prints nothing and exits 0.
#
#   version      checks a version before it reaches any command line: one
#             leading v is dropped, and the rest must match, as a whole value,
#             ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ (a bash test, never a
#             line-based tool, so a second line can't ride along). Prints the
#             bare X.Y.Z[-pre], or refused=bad_version with exit 2 and a
#             message naming the value. No koto call.
#
#   go           decides whether this release's version-and-notes go can come
#             from the session's grant. Prints one line and exits 0:
#               go=grant dispatch=<dispatch id>
#               go=person reason=<token>
#             It asks a person, whatever the grant, only for
#               unresolved      the security check printed an UNRESOLVED line
#                               (--unresolved): a finding about what the
#                               release contains, not an approval of the cut
#             and otherwise prints release-grant.sh's line (its own reasons
#             when it says go=person), so a holder's run calls niwa once. A
#             first release, a major bump and a commit pushed straight to the
#             base branch are the grant's to answer, as any other cut is.
#
#   mark         records what Phase 5 and Phase 6 saw, for Phase 7 to read:
#               dispatched <version>   work/dispatched, the version this run
#                                      dispatched the release workflow for
#                                      (checked as `version` checks it, with
#                                      no leading v)
#               concluded <conclusion> work/concluded: success, failure or
#                                      timeout, as Phase 6's monitoring ended
#             Prints nothing. A session that isn't live is refused.
#
#   check-notes  takes the lines of a declared check's saved output that start
#             with "notes: ", drops that prefix, and appends the rest, as
#             printed, to work/check-notes (blank lines skipped, a trailing
#             carriage return dropped). Prints notes=<count>. A line holding a
#             control character is refused (refused=bad_notes_line); a session
#             that isn't live is refused.
#
#   carries      checks drafted notes against work/check-notes: every stored
#             line must appear in the notes file as a whole line, or as a
#             "- " list item. Prints carried=<count>, or a missing=<line> per
#             absent line and refused=notes_missing_check_lines with exit 2.
#
#   asset        reads a release-assets command's saved output. A last
#             non-blank line "asset: <path>" names a file to attach: <path>
#             must be absolute, a regular file (not a symlink), and hold no
#             quotes, $, backticks or control characters, and no earlier
#             asset may share its file name. It is appended to work/assets
#             and asset=<path> printed; any other last line prints asset=none.
#             A bad path is refused=bad_asset, a repeated name
#             refused=duplicate_asset, both exit 2.
#
#   upload       uploads each path in work/assets to the release v<version>
#             with `gh release upload --clobber`, then reads the release's
#             asset names back with `gh release view` and prints
#             uploaded=<name> for each one listed. A missing file
#             (failed=asset_missing), a failed upload (failed=upload), a failed
#             read-back (failed=read_back) or a name the release doesn't list
#             (failed=not_attached) exits 1. No assets prints uploaded=0.
#
# Exit codes:
#   0    success
#   1    a koto, gh or git operation failed; read, go, check-notes, carries,
#        asset, upload: the key is absent; upload: an asset file is gone, its
#        upload failed, or the release doesn't list it afterwards
#   2    refused: topic's empty result, membership's, mark's, check-notes' or
#        asset's session not live, membership's directory not a git work tree,
#        a version that fails the check, a notes line or asset path check-notes
#        or asset refuses, drafted notes that leave out a check's line (carries)
#   4    cannot tell: koto answered something other than a session's state
#   64   usage error; no koto call was made
#   127  koto, gh, git or jq is not on PATH (whichever the subcommand needs)
#
# Environment:
#   KOTO_BIN   the koto binary to run (default: `koto` from PATH); the nested
#              skill-session.sh reads it too.
#   TMPDIR     where the temporary files are made (a private 0700
#              directory, removed on every exit path).
#
# Requires: bash 3.2+, jq, git, gh (topic, upload), koto (every subcommand but
# topic and version). No eval,
# no associative arrays, no mapfile, no namerefs.

set -uo pipefail

PROG="release-state"

SCRIPT_DIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
SS="$SCRIPT_DIR/../../../scripts/skill-session.sh"
BASH_BIN="${BASH:-bash}"
KOTO="${KOTO_BIN:-koto}"

RE_TOPIC='^[a-z0-9][a-z0-9-]*$'
RE_VERSION='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

say() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    printf 'error=usage\n'
    say "$1"
    say "usage: release-state.sh topic | membership <topic> | read <topic> <range|prs|unattributed|notes|head|check-notes|assets> | version <value> | go <topic> [--unresolved] | mark <topic> (dispatched <version> | concluded <success|failure|timeout>) | check-notes <topic> <output-file> | carries <topic> <notes-file> | asset <topic> <output-file> | upload <topic> <version> (see the header of this script)"
    exit 64
}

check_topic() { [[ "$1" =~ $RE_TOPIC ]] || usage "topic must match $RE_TOPIC"; }

need_tool() { # need_tool <command> <hint>
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'failed=%s_missing\n' "$1"
        say "$1 is not on PATH; $2"
        exit 127
    fi
}

need_koto() {
    need_tool "$KOTO" "/release needs koto (install it with \`tsuku install koto\`)"
    need_tool jq "install jq"
}

# session_live <session> -- exit 0 when the session is live. Exits the script
# when skill-session.sh cannot answer.
session_live() {
    local out rc
    out=$("$BASH_BIN" "$SS" status "$1" 2>/dev/null)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        say "cannot tell the state of $1 (skill-session.sh status exited $rc)"
        exit "$rc"
    fi
    [ "$out" = "live" ]
}

# key_exists <session> <key> -- exit 0 present, 1 absent; exits the script on
# any other answer.
key_exists() {
    local rc=0
    "$KOTO" context exists "$1" "$2" >/dev/null || rc=$?
    case "$rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) say "koto context exists $2 failed (exit $rc)"; exit 4 ;;
    esac
}

# --- topic ------------------------------------------------------------------------------

cmd_topic() {
    local json owner name joined topic
    [ "$#" -eq 0 ] || usage "topic takes no arguments"
    need_tool gh "/release reads the repository's owner and name with gh"
    need_tool jq "install jq"
    json=$(gh repo view --json owner,name) || { say "gh repo view failed"; exit 1; }
    owner=$(printf '%s' "$json" | jq -r '(.owner | if type == "object" then (.login // "") else (. // "") end)') || { say "gh repo view answered something that is not the repository's owner and name"; exit 1; }
    name=$(printf '%s' "$json" | jq -r '(.name // "")') || { say "gh repo view answered something that is not the repository's owner and name"; exit 1; }
    joined="${owner}-${name}"
    topic=$(printf '%s' "$joined" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    if [ -z "$owner" ] || [ -z "$name" ] || [ -z "$topic" ]; then
        printf 'refused=empty_topic\n'
        say "gh repo view named no owner or no name; there is no topic to key the session on"
        exit 2
    fi
    printf '%s\n' "$topic"
}

# --- membership -------------------------------------------------------------------------

TMPD=""
cleanup() { [ -n "$TMPD" ] && rm -rf "$TMPD"; return 0; }

# put_file <session> <key> <file> -- store the file's bytes under the key,
# replacing a value an earlier run left; exits the script on failure.
put_file() {
    if ! "$KOTO" context add "$1" "$2" --from-file "$3" >/dev/null; then
        say "koto context add $2 failed"
        printf 'failed=%s\n' "$2"
        exit 1
    fi
}

cmd_membership() {
    local topic s last_tag range count_prs count_un
    [ "$#" -eq 1 ] || usage "membership takes <topic>"
    topic="$1"
    check_topic "$topic"
    need_koto
    need_tool git "install git"
    s="release-$topic"
    if ! git rev-parse --is-inside-work-tree >/dev/null; then
        printf 'refused=not_a_repository\n'
        say "the current directory is not in a git work tree"
        exit 2
    fi
    if ! session_live "$s"; then
        printf 'refused=session_not_live\n'
        say "$s is not live; open it first with skill-session.sh open release $topic"
        exit 2
    fi

    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT

    last_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
    # An empty last tag is the first release. The guard is load-bearing:
    # "..HEAD" is a range git accepts, and it resolves to zero commits, so
    # without it a first release derives an empty set silently.
    if [ -n "$last_tag" ]; then
        range="$last_tag..HEAD"
    else
        range="HEAD"
    fi
    printf '%s\n' "$range" >"$TMPD/range"

    # The pull requests the release contains: GitHub's squash merge appends
    # "(#N)" to the commit subject. grep exits 1 when nothing matches, which is
    # a legal outcome (an empty list), so it is guarded.
    git log --format='%s' "$range" >"$TMPD/subjects" || { say "git log $range failed"; exit 1; }
    { grep -oE '\(#[0-9]+\)$' "$TMPD/subjects" || true; } | tr -d '(#)' | sort -n -u >"$TMPD/prs"

    # Commits in the range that name no pull request: the release chore
    # commits, and anything pushed straight to the base branch.
    git log --format='%h %s' "$range" >"$TMPD/log" || { say "git log $range failed"; exit 1; }
    { grep -vE '\(#[0-9]+\)$' "$TMPD/log" || true; } >"$TMPD/unattributed"

    git rev-parse --verify HEAD >"$TMPD/head" || { say "git rev-parse HEAD failed"; exit 1; }

    # Nothing an earlier run wrote survives into this one: its notes, its
    # dispatch and installs, and its membership keys, which go before any new
    # one is written so a write that fails part-way leaves keys missing (read
    # stops on them) rather than a mix of this run's and the last one's.
    for k in work/notes.md work/dispatched work/concluded work/after work/after-go \
        work/range work/prs work/unattributed work/head work/check-notes work/assets; do
        key_exists "$s" "$k" || continue
        if ! "$KOTO" context remove "$s" "$k" >/dev/null; then
            printf 'failed=%s\n' "$k"
            say "could not remove $k"
            exit 1
        fi
    done

    put_file "$s" work/range "$TMPD/range"
    put_file "$s" work/prs "$TMPD/prs"
    put_file "$s" work/unattributed "$TMPD/unattributed"
    put_file "$s" work/head "$TMPD/head"
    : >"$TMPD/empty"
    put_file "$s" work/check-notes "$TMPD/empty"
    put_file "$s" work/assets "$TMPD/empty"

    count_prs=$(grep -c . "$TMPD/prs" || true)
    count_un=$(grep -c . "$TMPD/unattributed" || true)
    printf 'range=%s\n' "$range"
    printf 'prs=%s\n' "${count_prs:-0}"
    printf 'unattributed=%s\n' "${count_un:-0}"
}

# --- read -------------------------------------------------------------------------------

cmd_read() {
    local topic which s key
    [ "$#" -eq 2 ] || usage "read takes <topic> <range|prs|unattributed|notes|head|check-notes|assets>"
    topic="$1"
    which="$2"
    check_topic "$topic"
    case "$which" in
        range) key="work/range" ;;
        prs) key="work/prs" ;;
        unattributed) key="work/unattributed" ;;
        notes) key="work/notes.md" ;;
        head) key="work/head" ;;
        check-notes) key="work/check-notes" ;;
        assets) key="work/assets" ;;
        *) usage "read's key must be range, prs, unattributed, notes, head, check-notes or assets" ;;
    esac
    need_koto
    s="release-$topic"
    if ! key_exists "$s" "$key"; then
        say "Phase 1 did not run: $key is absent from $s (run Phase 1 first; its membership step writes it)"
        exit 1
    fi
    "$KOTO" context get "$s" "$key" || { say "cannot read $key"; exit 1; }
}

# --- version ----------------------------------------------------------------------------

cmd_version() {
    local v
    [ "$#" -eq 1 ] || usage "version takes <value>"
    v="${1#v}"
    if [[ "$v" =~ $RE_VERSION ]]; then
        printf '%s\n' "$v"
        return 0
    fi
    printf 'refused=bad_version\n'
    say "the version $(printf '%q' "$1") is not X.Y.Z or X.Y.Z-<pre> (letters, digits and dots); the release stops here"
    exit 2
}

# --- go ---------------------------------------------------------------------------------

cmd_go() {
    local topic unresolved=0 s line
    [ "$#" -ge 1 ] || usage "go takes <topic>"
    topic="$1"
    shift
    check_topic "$topic"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --unresolved) unresolved=1 ;;
            *) usage "unknown go argument: $1" ;;
        esac
        shift
    done
    need_koto
    s="release-$topic"
    # Only a guard that Phase 1 ran; the range's value no longer decides the go.
    if ! key_exists "$s" work/range; then
        say "Phase 1 did not run: work/range is absent from $s (run Phase 1 first; its membership step writes it)"
        exit 1
    fi

    if [ "$unresolved" -eq 1 ]; then
        printf 'go=person reason=unresolved\n'
        return 0
    fi

    line=$("$BASH_BIN" "$SCRIPT_DIR/release-grant.sh")
    case "$line" in
        "go=grant dispatch="* | "go=person reason="*) printf '%s\n' "$line" ;;
        *) printf 'go=person reason=unreadable-answer\n' ;;
    esac
}

# --- mark -------------------------------------------------------------------------------

cmd_mark() {
    local topic what value s
    [ "$#" -eq 3 ] || usage "mark takes <topic> (dispatched <version> | concluded <success|failure|timeout>)"
    topic="$1"
    what="$2"
    value="$3"
    check_topic "$topic"
    case "$what" in
        dispatched)
            [[ "$value" =~ $RE_VERSION ]] || usage "mark dispatched takes a bare X.Y.Z or X.Y.Z-<pre> version"
            ;;
        concluded)
            case "$value" in success | failure | timeout) ;; *) usage "mark concluded takes success, failure or timeout" ;; esac
            ;;
        *) usage "mark records dispatched or concluded" ;;
    esac
    need_koto
    s="release-$topic"
    if ! session_live "$s"; then
        printf 'refused=session_not_live\n'
        say "$s is not live; Phase 1 opens it"
        exit 2
    fi
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT
    printf '%s\n' "$value" >"$TMPD/value"
    put_file "$s" "work/$what" "$TMPD/value"
}

# --- check-notes and carries ------------------------------------------------------------

# need_phase1_key <session> <key> -- exit 1 when Phase 1's membership didn't write it.
need_phase1_key() {
    if ! key_exists "$1" "$2"; then
        say "Phase 1 did not run: $2 is absent from $1 (run Phase 1 first; its membership step writes it)"
        exit 1
    fi
}

# need_live <session> -- refuse a session that isn't live.
need_live() {
    if ! session_live "$1"; then
        printf 'refused=session_not_live\n'
        say "$1 is not live; Phase 1 opens it"
        exit 2
    fi
}

# get_key <session> <key> <file> -- the key's content into the file, ending in
# a newline when it holds anything.
get_key() {
    "$KOTO" context get "$1" "$2" >"$3" || { say "cannot read $2"; exit 1; }
    if [ -s "$3" ] && [ -n "$(tail -c 1 "$3")" ]; then printf '\n' >>"$3"; fi
}

cmd_check_notes() {
    local topic file s count
    [ "$#" -eq 2 ] || usage "check-notes takes <topic> <output-file>"
    topic="$1"
    file="$2"
    check_topic "$topic"
    [ -f "$file" ] || usage "check-notes reads a check's output from a file, and $file is not one"
    need_koto
    s="release-$topic"
    need_live "$s"
    need_phase1_key "$s" work/check-notes
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT

    # A notes line is one the check started with "notes: ". The prefix goes;
    # the rest is copied as printed. A carriage return ending a line is dropped.
    LC_ALL=C sed -n 's/^notes: //p' "$file" | LC_ALL=C sed 's/\r$//' | { grep -v '^[[:space:]]*$' || true; } >"$TMPD/new"
    if LC_ALL=C grep -q '[[:cntrl:]]' "$TMPD/new"; then
        printf 'refused=bad_notes_line\n'
        say "a notes line in $file holds a control character; the check's output can't go into the notes as printed"
        exit 2
    fi
    get_key "$s" work/check-notes "$TMPD/notes"
    cat "$TMPD/new" >>"$TMPD/notes"
    put_file "$s" work/check-notes "$TMPD/notes"
    count=$(grep -c . "$TMPD/new" || true)
    printf 'notes=%s\n' "${count:-0}"
}

cmd_carries() {
    local topic notes s line carried=0 missing=0
    [ "$#" -eq 2 ] || usage "carries takes <topic> <notes-file>"
    topic="$1"
    notes="$2"
    check_topic "$topic"
    [ -f "$notes" ] || usage "carries reads drafted notes from a file, and $notes is not one"
    need_koto
    s="release-$topic"
    need_phase1_key "$s" work/check-notes
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT
    get_key "$s" work/check-notes "$TMPD/lines"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if grep -qxF -- "$line" "$notes" || grep -qxF -- "- $line" "$notes"; then
            carried=$((carried + 1))
        else
            printf 'missing=%s\n' "$line"
            missing=$((missing + 1))
        fi
    done <"$TMPD/lines"
    if [ "$missing" -gt 0 ]; then
        printf 'refused=notes_missing_check_lines\n'
        say "the notes leave out $missing line(s) a release check printed for them; add each as written, a line of its own or a '- ' list item"
        exit 2
    fi
    printf 'carried=%s\n' "$carried"
}

# --- asset and upload --------------------------------------------------------------------

cmd_asset() {
    local topic file s last path name
    [ "$#" -eq 2 ] || usage "asset takes <topic> <output-file>"
    topic="$1"
    file="$2"
    check_topic "$topic"
    [ -f "$file" ] || usage "asset reads an asset command's output from a file, and $file is not one"
    need_koto
    s="release-$topic"
    need_live "$s"
    need_phase1_key "$s" work/assets
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT

    last=$({ grep -v '^[[:space:]]*$' "$file" || true; } | tail -n 1)
    last="${last%$'\r'}"
    case "$last" in
        "asset: "*) path="${last#asset: }" ;;
        *)
            printf 'asset=none\n'
            return 0
            ;;
    esac
    case "$path" in
        /*) ;;
        *) path="" ;;
    esac
    case "$path" in
        *\'* | *\"* | *\$* | *\`* | *[[:cntrl:]]*) path="" ;;
    esac
    if [ -z "$path" ] || [ -L "$path" ] || [ ! -f "$path" ]; then
        printf 'refused=bad_asset\n'
        say "the asset line names $(printf '%q' "${last#asset: }"), which is not an absolute path to a regular file free of quotes, \$ and backticks; nothing is attached"
        exit 2
    fi
    name=$(basename -- "$path")
    get_key "$s" work/assets "$TMPD/assets"
    while IFS= read -r prior; do
        [ -n "$prior" ] || continue
        if [ "$(basename -- "$prior")" = "$name" ]; then
            printf 'refused=duplicate_asset\n'
            say "an earlier asset command already named a file called $name; one would replace the other on the release"
            exit 2
        fi
    done <"$TMPD/assets"
    printf '%s\n' "$path" >>"$TMPD/assets"
    put_file "$s" work/assets "$TMPD/assets"
    printf 'asset=%s\n' "$path"
}

cmd_upload() {
    local topic version s path name count=0
    [ "$#" -eq 2 ] || usage "upload takes <topic> <version>"
    topic="$1"
    version="$2"
    check_topic "$topic"
    [[ "$version" =~ $RE_VERSION ]] || usage "upload takes a bare X.Y.Z or X.Y.Z-<pre> version"
    need_koto
    need_tool gh "/release uploads release assets with gh"
    s="release-$topic"
    need_phase1_key "$s" work/assets
    TMPD=$(mktemp -d "${TMPDIR:-/tmp}/release-state.XXXXXX") || { say "cannot make a temporary directory"; exit 1; }
    trap cleanup EXIT
    get_key "$s" work/assets "$TMPD/assets"

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ ! -f "$path" ]; then
            printf 'failed=asset_missing\n'
            say "$path is gone; run its asset command again"
            exit 1
        fi
        if ! gh release upload "v$version" "$path" --clobber >&2; then
            printf 'failed=upload\n'
            say "gh release upload v$version $path failed"
            exit 1
        fi
        count=$((count + 1))
    done <"$TMPD/assets"
    if [ "$count" -eq 0 ]; then
        printf 'uploaded=0\n'
        return 0
    fi

    # Read the release back: an upload counts once GitHub lists the asset.
    if ! gh release view "v$version" --json assets --jq '.assets[].name' >"$TMPD/names"; then
        printf 'failed=read_back\n'
        say "gh release view v$version failed, so the upload can't be confirmed"
        exit 1
    fi
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        name=$(basename -- "$path")
        if ! grep -qxF -- "$name" "$TMPD/names"; then
            printf 'failed=not_attached\n'
            say "v$version doesn't list $name after its upload"
            exit 1
        fi
        printf 'uploaded=%s\n' "$name"
    done <"$TMPD/assets"
}

# --- dispatch ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a subcommand is required"
sub="$1"
shift
case "$sub" in
    topic) cmd_topic "$@" ;;
    membership) cmd_membership "$@" ;;
    read) cmd_read "$@" ;;
    version) cmd_version "$@" ;;
    go) cmd_go "$@" ;;
    mark) cmd_mark "$@" ;;
    check-notes) cmd_check_notes "$@" ;;
    carries) cmd_carries "$@" ;;
    asset) cmd_asset "$@" ;;
    upload) cmd_upload "$@" ;;
    *) usage "unknown subcommand: $sub" ;;
esac
