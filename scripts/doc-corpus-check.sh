#!/usr/bin/env bash
# doc-corpus-check.sh -- run the document checks over BRIEFs and DESIGNs
# already merged to a repository's default branch, read from a named commit.
#
# The document checks hold new documents to the structural rules; this answers
# how the documents merged before them fare. It runs in one repository's
# checkout and reads only committed content: every document comes out of git at
# the named commit, so an uncommitted file or edit is never read.
#
# Usage:
#   doc-corpus-check.sh --since <YYYY-MM-DD> --until <YYYY-MM-DD> --commit <sha>
#
#   --since   first day of the window, inclusive (UTC)
#   --until   the day the window ends, exclusive (UTC); later than --since
#   --commit  the commit to read, 7 to 40 lowercase hex digits; it must be an
#             ancestor of origin's default branch (refs/remotes/origin/HEAD)
#
# Which documents: walking the first-parent history up to --commit with
#   git log --first-parent --diff-filter=AR --name-status -M -z
# a path is taken when it is first added by a commit whose committer date, in
# UTC, falls in the window. Only docs/briefs/BRIEF-*.md and
# docs/designs/**/DESIGN-*.md are taken. A later rename of a taken path, in the
# window or after it, moves it to its new path, so each document is read once,
# under its final path. A rename into one of those paths from anywhere else, in
# the window, counts as the document's first add, since that is where it first
# appears as a BRIEF or DESIGN; a rename of a document added before the window
# does not. A taken document later moved out of those paths keeps its last
# document path, so it is listed absent.
#
# Each final path is read from --commit through `git ls-tree` and
# `git cat-file`, never through the work tree: ls-tree gives the mode and the
# object id the type and size checks need, and reading the blob by its id
# never parses a path as part of a revision. A path with `..` or a control
# character in it is skipped without being printed (stderr counts them); a
# path that isn't a regular file there, or whose blob is over 1 MiB, is skipped
# and listed. Documents are written under generated names (BRIEF-<n>.md,
# DESIGN-<n>.md; the validator tells the format from the name) with mode 0600,
# in a private mktemp -d directory removed on every exit, an interrupt
# included.
#
# The checks come from scripts/lib/doc-validate.sh, the same library the /scope
# hop gate and doc-check.sh use: the validator is resolved and refused when it
# lies inside this repository, the plugin's writing-style rules are pinned, the
# canary must show the validator reports FC23 to FC25, and each document gets
# one `shirabe validate` run whose envelope must be a complete verdict (a
# schema-only skip of the document reads as SCHEMA at line 1). Each validator
# run, the canary's included, is stopped after DOC_CORPUS_TIMEOUT seconds.
#
# Standard output, printed only once every document has a verdict. A document
# the validator gives no verdict on stops the run with nothing printed: a
# report missing it would read as that document being clean.
#   <rule-id> <stage> <owner/repo> <path>:<line>
#                       one per FC23, FC24, FC25 or SCHEMA finding, under the
#                       registry entry that aliases the code and its stage
#   count <rule-id> <n> one per rule with at least one finding
#   absent <owner/repo> <path>
#                       a taken path that doesn't exist at --commit
#   skipped <owner/repo> <path> <reason>
#                       a taken path that isn't a regular file, or is over
#                       1 MiB, at --commit; <reason> is `not a regular file`
#                       or `over 1 MiB`
# A path can hold spaces, so a reader splits each line from the left: the
# first two fields of a finding, the first field of an absent or skipped line,
# then <owner/repo>, which never holds a space. A clean corpus prints nothing. No line carries document text: a finding
# prints only its rule, the path and the line number, so marker text in a
# document can't start a line. <owner/repo> comes from origin's URL.
#
# Records nothing in telemetry.
#
# Exit status:
#   0  the report above (findings or none)
#   2  usage, a refusal (not a git checkout, a shallow clone, no usable
#      origin remote or default branch, a commit that isn't an ancestor of the
#      default branch, git or jq missing), or no verdict (the validator missing, inside the repository,
#      failing its canary, timing out, or giving output this can't read);
#      nothing is printed on stdout
#
# Environment: DOC_CORPUS_TIMEOUT, seconds per validator run (default 120,
# 1 to 9999).
#
# Written for the bash 3.2 floor and without `set -e`.

set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd -P)
MAX_BYTES=1048576
REGISTRY="$PLUGIN_ROOT/references/rule-registry.json"
CODES="FC23 FC24 FC25 SCHEMA"

usage() {
    cat >&2 <<'EOF'
Usage: doc-corpus-check.sh --since <YYYY-MM-DD> --until <YYYY-MM-DD> --commit <sha>

Runs the document checks over the BRIEFs and DESIGNs first added to the
repository's default branch in [since, until), read at <sha>.
Exit 0 the report on stdout, 2 refused or no verdict.
EOF
    exit 2
}

WORK=""
CHILD=""
stop_child() {
    [ -n "$CHILD" ] || return 0
    kill -TERM -- "-$CHILD" 2>/dev/null || kill -TERM "$CHILD" 2>/dev/null
    sleep 1
    kill -KILL -- "-$CHILD" 2>/dev/null || kill -KILL "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
    CHILD=""
    return 0
}
cleanup() {
    stop_child
    case "$WORK" in
        */doc-corpus-check.*) rm -rf "$WORK" ;;
    esac
    return 0
}
trap cleanup EXIT
trap 'cleanup; exit 2' INT TERM HUP

refuse() {
    echo "doc-corpus-check: refused: $*" >&2
    exit 2
}

# shellcheck source=lib/doc-validate.sh
. "$PLUGIN_ROOT/scripts/lib/doc-validate.sh" || refuse "cannot load scripts/lib/doc-validate.sh"

# --- arguments ----------------------------------------------------------------

SINCE="" UNTIL="" COMMIT=""
set_once() { # <current value> <name>
    [ -z "$1" ] || { echo "doc-corpus-check: $2 given twice" >&2; usage; }
}
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case "$1" in
        --since) set_once "$SINCE" --since; SINCE=$2 ;;
        --until) set_once "$UNTIL" --until; UNTIL=$2 ;;
        --commit) set_once "$COMMIT" --commit; COMMIT=$2 ;;
        *) usage ;;
    esac
    shift 2
done
[ -n "$SINCE" ] && [ -n "$UNTIL" ] && [ -n "$COMMIT" ] || usage

RE_DATE='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
RE_SHA='^[0-9a-f]{7,40}$'
RE_SECS='^[1-9][0-9]{0,3}$'
RE_SLUG_PART='^[A-Za-z0-9_.-]+$'
[[ $SINCE =~ $RE_DATE ]] || { echo "doc-corpus-check: --since is not a YYYY-MM-DD date" >&2; usage; }
[[ $UNTIL =~ $RE_DATE ]] || { echo "doc-corpus-check: --until is not a YYYY-MM-DD date" >&2; usage; }
[[ $SINCE < $UNTIL ]] || { echo "doc-corpus-check: --until must be later than --since" >&2; usage; }
[[ $COMMIT =~ $RE_SHA ]] || { echo "doc-corpus-check: --commit is not 7 to 40 lowercase hex digits" >&2; usage; }
LIMIT=${DOC_CORPUS_TIMEOUT:-120}
[[ $LIMIT =~ $RE_SECS ]] || refuse "DOC_CORPUS_TIMEOUT is not a whole number of seconds from 1 to 9999"

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH"
done

# --- the repository -----------------------------------------------------------

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "not inside a git working tree"
cd "$ROOT" || refuse "cannot enter the repository root"
ROOT_REAL=$(pwd -P)
# In a shallow clone the oldest commit shows every file as added, which would
# pull documents merged long before the window into it.
[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = false ] \
    || refuse "the repository is a shallow clone (git fetch --unshallow gives the full history)"

# slug_from_url <url>: owner/repo from an https, ssh, git or scp-style URL.
slug_from_url() {
    local p owner repo
    case "$1" in
        https://*|http://*|ssh://*|git://*) p=${1#*://}; p=${p#*/} ;;
        *@*:*) p=${1#*:} ;;
        *) return 1 ;;
    esac
    p=${p%/}
    p=${p%.git}
    case "$p" in
        */*/*|"") return 1 ;;
        */*) ;;
        *) return 1 ;;
    esac
    owner=${p%%/*}
    repo=${p#*/}
    [[ $owner =~ $RE_SLUG_PART ]] && [[ $repo =~ $RE_SLUG_PART ]] || return 1
    case "$owner" in .|..) return 1 ;; esac
    case "$repo" in .|..) return 1 ;; esac
    printf '%s/%s\n' "$owner" "$repo"
}
URL=$(git config --get remote.origin.url 2>/dev/null) || refuse "the repository has no origin remote"
SLUG=$(slug_from_url "$URL") || refuse "origin's URL names no owner/repo"

DEFAULT_REF=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) \
    || refuse "origin's default branch is unknown (git remote set-head origin --auto sets it)"
case "$DEFAULT_REF" in
    refs/remotes/origin/?*) ;;
    *) refuse "origin's default branch is unknown" ;;
esac
git rev-parse --verify --quiet --end-of-options "$DEFAULT_REF^{commit}" >/dev/null \
    || refuse "${DEFAULT_REF#refs/remotes/} does not resolve to a commit"
SHA=$(git rev-parse --verify --quiet --end-of-options "$COMMIT^{commit}") \
    || refuse "--commit $COMMIT is not a commit in this repository"
git merge-base --is-ancestor "$SHA" "$DEFAULT_REF" 2>/dev/null
case $? in
    0) ;;
    1) refuse "--commit $COMMIT is not an ancestor of ${DEFAULT_REF#refs/remotes/}" ;;
    *) refuse "cannot tell whether $COMMIT is an ancestor of ${DEFAULT_REF#refs/remotes/}" ;;
esac

# Each code's registered rule and stage, read once. A code the registry
# doesn't alias is a refusal: the report would print a rule it can't name.
RULE_FC23="" RULE_FC24="" RULE_FC25="" RULE_SCHEMA=""
STAGE_FC23="" STAGE_FC24="" STAGE_FC25="" STAGE_SCHEMA=""
[ -r "$REGISTRY" ] || refuse "cannot read $REGISTRY"
for code in $CODES; do
    id=$(dv_registry_id "$REGISTRY" "$code")
    [ -n "$id" ] || refuse "no active registry entry aliases $code"
    stage=$(jq -r --arg id "$id" '[.rules[] | select(.id == $id) | .stage] | first // ""' "$REGISTRY" 2>/dev/null)
    case "$stage" in
        block|warn|shadow) ;;
        *) refuse "the registry entry $id has no stage" ;;
    esac
    eval "RULE_$code=\$id STAGE_$code=\$stage"
done

# --- the validator ------------------------------------------------------------

umask 077
WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-corpus-check.XXXXXX") || refuse "cannot create a private scratch directory"
chmod 700 "$WORK" || refuse "cannot make the scratch directory private"
mkdir "$WORK/canary" "$WORK/docs" || refuse "cannot create the scratch directories"

# bounded <function> [<arg>...]: runs the function in a background process
# group of its own and stops the whole group, the validator with it, once
# LIMIT seconds pass. macOS has no timeout(1), so the parent polls. The
# function's DV_REASON comes back through a file.
bounded() {
    local ticks=0 max=$((LIMIT * 5)) rc
    rm -f "$WORK/reason"
    set -m
    (
        "$@"
        rc=$?
        printf '%s' "$DV_REASON" > "$WORK/reason"
        exit "$rc"
    ) </dev/null &
    CHILD=$!
    set +m
    while kill -0 "$CHILD" 2>/dev/null; do
        if [ "$ticks" -ge "$max" ]; then
            stop_child
            DV_REASON="the validator did not finish within $LIMIT seconds"
            return 1
        fi
        sleep 0.2
        ticks=$((ticks + 1))
    done
    wait "$CHILD" 2>/dev/null
    rc=$?
    CHILD=""
    DV_REASON=$(cat "$WORK/reason" 2>/dev/null)
    return "$rc"
}

# validate_one <generated name>: one validator run on a written document, from
# its directory, so the envelope names the generated file.
validate_one() {
    cd "$WORK/docs" || { DV_REASON="cannot enter the scratch directory"; return 1; }
    dv_validate "$1" "$WORK/env.json" "$WORK/env.err"
}

command -v shirabe >/dev/null 2>&1 || refuse "shirabe is not on PATH"
dv_resolve_validator "$ROOT_REAL" || refuse "$DV_REASON"
dv_pin_rules "$PLUGIN_ROOT" || refuse "$DV_REASON"
bounded dv_canary "$WORK/canary" || refuse "$DV_REASON"

# --- the walk -----------------------------------------------------------------

# is_doc <path>: a BRIEF directly under docs/briefs/, or a DESIGN anywhere
# under docs/designs/.
is_doc() {
    case "$1" in
        docs/briefs/BRIEF-*.md)
            case "${1#docs/briefs/}" in */*) return 1 ;; esac
            return 0 ;;
        docs/designs/*/DESIGN-*.md|docs/designs/DESIGN-*.md)
            case "${1##*/}" in DESIGN-*.md) return 0 ;; esac
            return 1 ;;
    esac
    return 1
}

# The taken paths, in the order first added. Indexed arrays exist on bash 3.2
# and hold any byte but NUL, which git's -z output never puts in a path.
TAKEN=()
# taken_index <path>: the index of a taken path, or nothing.
taken_index() {
    local i=0
    while [ "$i" -lt "${#TAKEN[@]}" ]; do
        [ "${TAKEN[$i]}" = "$1" ] && { echo "$i"; return 0; }
        i=$((i + 1))
    done
    return 1
}
in_window() { # <YYYY-MM-DD>
    ! [[ $1 < $SINCE ]] && [[ $1 < $UNTIL ]]
}

# Committer dates in UTC, oldest commit first. The pathspecs are literal, and
# the walk starts from the resolved commit after --end-of-options.
TZ=UTC git --literal-pathspecs log --first-parent --diff-merges=first-parent --reverse \
    --diff-filter=AR --name-status -M -z --date=format-local:%Y-%m-%d --format='%x01%H %cd' \
    --end-of-options "$SHA" -- docs/briefs docs/designs > "$WORK/log" 2> "$WORK/log.err" \
    || refuse "git log failed: $(tail -n 1 "$WORK/log.err")"

# With -z each commit is a header token ("\001<sha> <date>"), then per change
# a status token and one path (A) or two (R<score>): NUL-separated, with a
# newline before the first status. A path is never read as a header or a
# status: the state says which token comes next.
NL=$'\n'
SOH=$'\001'
TAB=$'\t'
state=head date="" old=""
while IFS= read -r -d '' tok; do
    case "$state" in
        head)
            tok=${tok#"$NL"}
            case "$tok" in
                "$SOH"*) date=${tok##* } ;;
                A) state=add ;;
                R[0-9]*) state=old ;;
                *) refuse "cannot read git log's output" ;;
            esac ;;
        add)
            if in_window "$date" && is_doc "$tok" && ! taken_index "$tok" >/dev/null; then
                TAKEN[${#TAKEN[@]}]=$tok
            fi
            state=head ;;
        old)
            old=$tok
            state=new ;;
        new)
            if i=$(taken_index "$old"); then
                # A move out of the document paths keeps the old path, which
                # is then listed absent.
                is_doc "$tok" && TAKEN[$i]=$tok
            elif in_window "$date" && is_doc "$tok" && ! is_doc "$old" && ! taken_index "$tok" >/dev/null; then
                TAKEN[${#TAKEN[@]}]=$tok
            fi
            state=head ;;
    esac
done < "$WORK/log"
[ "$state" = head ] || refuse "git log's output ended in the middle of a change"

# --- the documents ------------------------------------------------------------

: > "$WORK/findings"
: > "$WORK/absent"
: > "$WORK/skipped"
: > "$WORK/seen"
BAD_NAMES=0
N=0
i=0
while [ "$i" -lt "${#TAKEN[@]}" ]; do
    p=${TAKEN[$i]}
    i=$((i + 1))
    # Two taken paths can end at one name; the later one is the same document.
    j=0 dup=0
    while [ "$j" -lt "$((i - 1))" ]; do
        [ "${TAKEN[$j]}" = "$p" ] && dup=1
        j=$((j + 1))
    done
    [ "$dup" -eq 0 ] || continue
    case "$p" in
        *[[:cntrl:]]*) BAD_NAMES=$((BAD_NAMES + 1)); continue ;;
    esac
    # Git stores no `..` segment, so any `..` in a name is refused outright.
    case "$p" in
        *..*) BAD_NAMES=$((BAD_NAMES + 1)); continue ;;
    esac
    entry=""
    git --literal-pathspecs ls-tree -z --full-tree "$SHA" -- "$p" > "$WORK/tree" 2>/dev/null \
        || refuse "git ls-tree failed at $SHA"
    IFS= read -r -d '' entry < "$WORK/tree"
    if [ -z "$entry" ]; then
        printf 'absent %s %s\n' "$SLUG" "$p" >> "$WORK/absent"
        continue
    fi
    meta=${entry%%"$TAB"*}
    mode=${meta%% *}
    rest=${meta#* }
    type=${rest%% *}
    oid=${rest#* }
    if [ "$type" != blob ] || { [ "$mode" != 100644 ] && [ "$mode" != 100755 ]; }; then
        printf 'skipped %s %s not a regular file\n' "$SLUG" "$p" >> "$WORK/skipped"
        continue
    fi
    size=$(git cat-file -s "$oid" 2>/dev/null) || refuse "cannot read the size of $p at $SHA"
    if [ "$size" -gt "$MAX_BYTES" ]; then
        printf 'skipped %s %s over 1 MiB\n' "$SLUG" "$p" >> "$WORK/skipped"
        continue
    fi

    N=$((N + 1))
    case "$p" in
        docs/briefs/*) name="BRIEF-$N.md" ;;
        *) name="DESIGN-$N.md" ;;
    esac
    git cat-file blob "$oid" > "$WORK/docs/$name" 2>/dev/null || refuse "cannot read $p at $SHA"
    chmod 600 "$WORK/docs/$name" || refuse "cannot make a scratch document private"

    bounded validate_one "$name" || refuse "no verdict on $p: $DV_REASON"
    dv_select_violations "$WORK/env.json" > "$WORK/hits" 2>/dev/null \
        || refuse "cannot read the validator's output on $p"
    rm -f "$WORK/docs/$name"

    jq -r --arg codes " $CODES " '
        .code as $c
        | select(($c | type) == "string" and ($codes | contains(" " + $c + " ")))
        | "\(.code) \(if (.line | type) == "number" then .line else "" end)"' "$WORK/hits" > "$WORK/coded" 2>/dev/null \
        || refuse "cannot read the validator's output on $p"
    while read -r code line; do
        case " $CODES " in
            *" $code "*) ;;
            *) continue ;;
        esac
        [[ $line =~ ^[0-9]+$ ]] || refuse "the validator reported $code on $p with no line"
        eval "id=\$RULE_$code stage=\$STAGE_$code"
        printf '%s %s %s %s:%s\n' "$id" "$stage" "$SLUG" "$p" "$line" >> "$WORK/findings"
    done < "$WORK/coded"
done

if [ "$BAD_NAMES" -gt 0 ]; then
    echo "doc-corpus-check: skipped $BAD_NAMES path(s) with a .. or a control character in the name" >&2
fi

# --- the report ---------------------------------------------------------------

cat "$WORK/findings"
for code in $CODES; do
    eval "id=\$RULE_$code"
    n=$(awk -v id="$id" '$1 == id { n++ } END { print n + 0 }' "$WORK/findings")
    [ "$n" -gt 0 ] && printf 'count %s %s\n' "$id" "$n"
done
cat "$WORK/absent" "$WORK/skipped"
exit 0
