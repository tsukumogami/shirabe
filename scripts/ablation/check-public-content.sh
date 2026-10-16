#!/usr/bin/env bash
#
# check-public-content.sh - refuse text a public repository must not carry
#
# shirabe is public. The ablation harness writes run records and a summary
# into the repository, and a pull request body goes with them, so this check
# refuses, in the text it is given:
#
#   - a home-directory path (/home/<user>/..., /Users/<user>/..., ~/.<dir>)
#   - a wip/ path that names a file (wip/<name>); the bare words "wip/ path"
#     in prose describing the rule are not a path and pass
#   - a UUID-shaped identifier (session ids have that shape)
#   - an instance or session name: <name>-<8 hex digits> after a '+', or a
#     snake_case <name>-<8 hex digits>; a jobs/<8 hex> path; a session_<id>
#   - a hosted-session URL
#   - common secret shapes: GitHub and cloud tokens, API keys, private keys
#   - any term in a denylist, when one is supplied
#
# One narrow exception exists, for files that must hold an old staging path
# to test the checks that police it: the allow file beside this script,
# check-public-content.allow, read by every invocation (the pre-push gate and
# the CI job run this same script, so the two cannot diverge). Each record is
# four tab-separated fields:
#
#   <class-id>  <file>  <issue>  <reason>
#
# where <class-id> names the finding class (only `wip-path` is allowlistable:
# a secret, an identifier or a home path is never carried on an allowlist),
# <file> is the one file the record covers, exactly as a finding prints it,
# <issue> is the owner/repo#N that tracks the deferral, and <reason> says why
# that file legitimately holds the literal. A finding matching a record is
# printed as an `allowed:` notice on stdout, with the issue, and does not
# fail the check. The allow file itself is scanned with the same pattern
# classes before it is trusted; a record whose text would itself be refused
# is a hard error, so no reason can smuggle a path, a name or a secret.
# $PUBLIC_CONTENT_ALLOWLIST overrides the location (the tests point it at
# their own scratch files; /dev/null reads as no records).
#
# The denylist is never part of this repository: a list of names that must
# not appear, kept in the repository in any form, would publish those names
# (a hash of a short name is recovered by hashing guesses). It is read at run
# time from --denylist <file> or $ABLATION_DENYLIST, and a path inside this
# checkout is refused. The file holds one term per line, matched
# case-insensitively; blank lines and lines starting with # are ignored. A
# term matches a token of the text (a run of [A-Za-z0-9._/-]) or any
# '/'-joined suffix of one, so "owner/name" is checked whole and "name" on its
# own. The terms stay in memory; nothing about them is printed or written.
#
# Without a list, the check says plainly that the denylisted-term check did
# not run and runs everything else. --require-denylist makes a missing list an
# error instead. A maintainer can supply the list in CI from a repository
# secret; the workflow does not assume one exists.
#
# Usage:
#   scripts/ablation/check-public-content.sh [--denylist <file>] [--require-denylist] <file>...
#   scripts/ablation/check-public-content.sh [--denylist <file>] [--require-denylist] --diff <base> [--head <commit>] [-- <pathspec>...]
#
# With --diff, only the lines <head> (default HEAD) adds relative to its merge
# base with <base> are checked, across the whole tree or only under the
# pathspecs given after --. With files, every line; "-" reads stdin.
#
# Exit codes:
#   0 - nothing refused
#   1 - at least one line refused; each is named on stderr as <source>:<line>: <class>
#   2 - usage error

set -euo pipefail

PROG=check-public-content
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
denylist="${ABLATION_DENYLIST:-}"
require_denylist=0
base=""
head="HEAD"
files=()
# Arguments after --: files to read, or with --diff the pathspecs to diff.
after_dashdash=()

die() {
    echo "$PROG: $*" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --denylist) [ "$#" -ge 2 ] || die "--denylist requires a file"; denylist="$2"; shift ;;
        --require-denylist) require_denylist=1 ;;
        --diff) [ "$#" -ge 2 ] || die "--diff requires a base"; base="$2"; shift ;;
        --head) [ "$#" -ge 2 ] || die "--head requires a commit"; head="$2"; shift ;;
        -h|--help) sed -n '2,66p' "$0"; exit 0 ;;
        --) shift; after_dashdash=("$@"); break ;;
        -) files+=("-") ;;
        -*) die "unknown option: $1" ;;
        *) files+=("$1") ;;
    esac
    shift
done
if [ -n "$denylist" ]; then
    [ -f "$denylist" ] || die "denylist not found: $denylist"
    real=$(cd "$(dirname "$denylist")" && pwd -P)/$(basename "$denylist")
    case "$real" in
        "$CHECKOUT"/*) die "refusing a denylist inside the checkout: the list must not live in the repository" ;;
    esac
elif [ "$require_denylist" -eq 1 ]; then
    die "--require-denylist: no denylist given (--denylist <file> or \$ABLATION_DENYLIST)"
fi
if [ -n "$base" ]; then
    [ "${#files[@]}" -eq 0 ] || die "--diff takes no files; give pathspecs after --"
    pathspecs=(.)
    [ "${#after_dashdash[@]}" -eq 0 ] || pathspecs=("${after_dashdash[@]}")
    for ref in "$base" "$head"; do
        case "$ref" in -*) die "refusing a ref that starts with '-': $ref" ;; esac
        git rev-parse --verify --quiet --end-of-options "${ref}^{commit}" >/dev/null \
            || die "not a commit: $ref"
    done
else
    [ "${#after_dashdash[@]}" -eq 0 ] || files+=("${after_dashdash[@]}")
    [ "${#files[@]}" -gt 0 ] || die "nothing to check: give files or --diff <base>"
fi


TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Collect "<source>\t<line number>\t<text>" rows.
rows="$TMP/rows"
: > "$rows"
if [ -n "$base" ]; then
    # Three dots: against the merge base, so commits that landed on the base
    # branch after this branch forked are never read as this branch's lines.
    git diff --unified=0 --no-color "$base"..."$head" -- "${pathspecs[@]}" | awk '
        # A "+++ " line is a file header only between "diff --git" and the
        # first hunk; inside a hunk it is an added line that starts with "++".
        # git ends a header name that holds a space with a tab; drop it.
        /^diff --git / { header = 1; next }
        header && /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); sub(/\t$/, "", file); next }
        /^@@ / { header = 0; match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
        !header && /^\+/ { printf "%s\t%d\t%s\n", file, n, substr($0, 2); n++ }
    ' > "$rows"
else
    for f in "${files[@]}"; do
        if [ "$f" = "-" ]; then
            awk '{ printf "stdin\t%d\t%s\n", NR, $0 }' >> "$rows"
        else
            [ -f "$f" ] || die "no such file: $f"
            awk -v src="$f" '{ printf "%s\t%d\t%s\n", src, NR, $0 }' "$f" >> "$rows"
        fi
    done
fi

found=0
report() {
    echo "$PROG: $1:$2: $3" >&2
    found=1
}

# Pattern classes: a stable id, the printed class, then the ERE, matched
# against the text column only. The id is what an allow record names; only
# the ids in ALLOWLISTABLE may appear there.
patterns=(
    'home-path|home-directory path|(/home|/Users)/[A-Za-z0-9._-]+/|~/\.[A-Za-z]'
    'wip-path|wip/ path|(^|[^A-Za-z0-9_])wip/[A-Za-z0-9_][A-Za-z0-9_.-]*'
    'uuid|uuid-shaped identifier|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    'instance-name|instance or job name|\+[a-z0-9_]+-[0-9a-f]{8}([^0-9a-f]|$)|(^|[^A-Za-z0-9_])[a-z0-9]+_[a-z0-9_]+-[0-9a-f]{8}([^0-9a-f]|$)|(^|/)jobs/[0-9a-f]{8}([^0-9a-f]|$)|(^|[^A-Za-z0-9])session_[0-9A-Z][A-Za-z0-9]{15,}'
    'hosted-url|hosted-session url|claude\.ai/code/session_'
    'secret|secret shape|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
ALLOWLISTABLE="wip-path"

# scan_line_classes <text> -- print the id of every pattern class <text>
# matches, one per line. Used on the allow file's own records, so a record
# cannot carry what the check exists to refuse.
scan_line_classes() {
    local entry id rest re
    for entry in "${patterns[@]}"; do
        id="${entry%%|*}"
        rest="${entry#*|}"
        re="${rest#*|}"
        printf '%s' "$1" | grep -qE -- "$re" && printf '%s\n' "$id"
    done
    return 0
}

# The allow file: <class-id>\t<file>\t<issue>\t<reason>, # and blanks ignored.
ALLOW_DEFAULT="$SCRIPT_DIR/check-public-content.allow"
allow_file="${PUBLIC_CONTENT_ALLOWLIST-$ALLOW_DEFAULT}"
allow="$TMP/allow"
: > "$allow"
if [ -n "$allow_file" ] && [ -f "$allow_file" ]; then
    lineno=0
    while IFS= read -r rec || [ -n "$rec" ]; do
        lineno=$((lineno + 1))
        case "$rec" in ''|'#'*) continue ;; esac
        IFS=$'\t' read -r a_id a_file a_issue a_reason <<< "$rec"
        [ -n "${a_reason:-}" ] || die "allow file line $lineno: expected 4 tab-separated fields: <class-id> <file> <issue> <reason>"
        case " $ALLOWLISTABLE " in
            *" $a_id "*) ;;
            *) die "allow file line $lineno: class '$a_id' is not allowlistable (only: $ALLOWLISTABLE)" ;;
        esac
        case "$a_file" in
            stdin|-) die "allow file line $lineno: a record never covers stdin; only a named file can carry a deferral" ;;
        esac
        printf '%s' "$a_issue" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*#[0-9]+$' \
            || die "allow file line $lineno: issue must be owner/repo#N, got '$a_issue'"
        hit=$(scan_line_classes "$rec")
        [ -z "$hit" ] || die "allow file line $lineno: the record itself matches class '$(printf '%s' "$hit" | head -1)'; an allow record may quote the rule, never the content"
        if grep -qF "$a_id	$a_file	" "$allow"; then
            die "allow file line $lineno: duplicate record for class '$a_id' and file '$a_file'"
        fi
        printf '%s\t%s\t%s\n' "$a_id" "$a_file" "$a_issue" >> "$allow"
    done < "$allow_file"
fi

# allowed_issue <id> <file> -- print the covering record's issue, or nothing.
allowed_issue() {
    awk -F '\t' -v id="$1" -v f="$2" '$1 == id && $2 == f { print $3; exit }' "$allow"
}

# One grep per class over the text column; its line numbers index the rows.
texts="$TMP/texts"
cut -f3- "$rows" > "$texts"
for entry in "${patterns[@]}"; do
    id="${entry%%|*}"
    rest="${entry#*|}"
    class="${rest%%|*}"
    re="${rest#*|}"
    while IFS= read -r idx; do
        where=$(awk -F '\t' -v i="$idx" 'NR == i { print $1 "\t" $2; exit }' "$rows")
        src="${where%%$'\t'*}"
        ln="${where#*$'\t'}"
        issue=$(allowed_issue "$id" "$src")
        if [ -n "$issue" ]; then
            echo "$PROG: allowed: $src:$ln: $class ($issue)"
        else
            report "$src" "$ln" "$class"
        fi
    done < <(grep -nE -- "$re" "$texts" | cut -d: -f1 || true)
done

# Denylisted terms: every token and every '/'-suffix of it, against the list.
if [ -z "$denylist" ]; then
    echo "$PROG: denylist not provided: denylisted-term check did not run;" \
        "checked home-directory paths, wip/ file paths, session and job identifiers," \
        "hosted-session URLs and secret shapes"
else
    command -v python3 >/dev/null 2>&1 || die "python3 is required for the denylist check"
    hits=$(python3 - "$rows" "$denylist" <<'PY'
import re, sys
rows_path, list_path = sys.argv[1], sys.argv[2]
terms = {l.strip().lower() for l in open(list_path, encoding="utf-8", errors="replace")
         if l.strip() and not l.strip().startswith("#")}
for line in open(rows_path, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) < 3:
        continue
    src, n, text = parts
    hit = False
    for tok in re.findall(r"[a-z0-9._/-]+", text.lower()):
        tok = tok.rstrip(".")
        while tok and not hit:
            if tok in terms:
                hit = True
            tok = tok.split("/", 1)[1] if "/" in tok else ""
        if hit:
            break
    if hit:
        print(f"{src}\t{n}")
PY
)
    if [ -n "$hits" ]; then
        while IFS=$'\t' read -r src n; do
            report "$src" "$n" "denylisted term"
        done <<< "$hits"
    fi
    echo "$PROG: denylisted-term check ran against the supplied list"
fi

exit "$found"
