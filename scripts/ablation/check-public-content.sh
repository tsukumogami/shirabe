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
#   - any term whose sha256 appears in the denylist
#
# The denylist holds hashes, one lowercase hex sha256 per line, of terms that
# must not appear (private repository names, vendor names). Storing hashes
# means the list itself names nothing. A term matches when the sha256 of a
# lowercased token of the text equals a listed hash; tokens are runs of
# [A-Za-z0-9._/-], and every '/'-joined suffix of a token is tried too, so
# "owner/name" is checked whole and "name" on its own.
#
# Usage:
#   scripts/ablation/check-public-content.sh [--denylist <file>] <file>...
#   scripts/ablation/check-public-content.sh [--denylist <file>] --diff <base>
#
# With --diff, only the lines HEAD adds relative to its merge base with <base>
# are checked. With files, every line; "-" reads stdin.
#
# Exit codes:
#   0 - nothing refused
#   1 - at least one line refused; each is named on stderr as <source>:<line>: <class>
#   2 - usage error

set -euo pipefail

PROG=check-public-content
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
denylist="$SCRIPT_DIR/public-content-denylist.txt"
base=""
files=()

die() {
    echo "$PROG: $*" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --denylist) [ "$#" -ge 2 ] || die "--denylist requires a file"; denylist="$2"; shift ;;
        --diff) [ "$#" -ge 2 ] || die "--diff requires a base"; base="$2"; shift ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        --) shift; files+=("$@"); break ;;
        -) files+=("-") ;;
        -*) die "unknown option: $1" ;;
        *) files+=("$1") ;;
    esac
    shift
done
[ -f "$denylist" ] || die "denylist not found: $denylist"
if [ -n "$base" ]; then
    [ "${#files[@]}" -eq 0 ] || die "--diff takes no files"
    git rev-parse --verify --quiet --end-of-options "${base}^{commit}" >/dev/null \
        || die "not a commit: $base"
    case "$base" in -*) die "refusing base that starts with '-': $base" ;; esac
else
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
    git diff --unified=0 --no-color "$base"...HEAD -- . | awk '
        /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); next }
        /^@@ / { match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
        /^\+/ { printf "%s\t%d\t%s\n", file, n, substr($0, 2); n++ }
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

# Pattern classes. ERE, matched against the text column only.
patterns=(
    'home-directory path|(/home|/Users)/[A-Za-z0-9._-]+/|~/\.[A-Za-z]'
    'wip/ path|(^|[^A-Za-z0-9_])wip/[A-Za-z0-9_][A-Za-z0-9_.-]*'
    'uuid-shaped identifier|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    'instance or job name|\+[a-z0-9_]+-[0-9a-f]{8}([^0-9a-f]|$)|(^|[^A-Za-z0-9_])[a-z0-9]+_[a-z0-9_]+-[0-9a-f]{8}([^0-9a-f]|$)|(^|/)jobs/[0-9a-f]{8}([^0-9a-f]|$)|(^|[^A-Za-z0-9])session_[A-Za-z0-9]{8,}'
    'hosted-session url|claude\.ai/code/session_'
    'secret shape|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

# One grep per class over the text column; its line numbers index the rows.
texts="$TMP/texts"
cut -f3- "$rows" > "$texts"
for entry in "${patterns[@]}"; do
    class="${entry%%|*}"
    re="${entry#*|}"
    while IFS= read -r idx; do
        where=$(awk -F '\t' -v i="$idx" 'NR == i { print $1 "\t" $2; exit }' "$rows")
        report "${where%%$'\t'*}" "${where#*$'\t'}" "$class"
    done < <(grep -nE -- "$re" "$texts" | cut -d: -f1 || true)
done

# Denylisted terms: hash every token and every '/'-suffix of it.
hashes="$TMP/hashes"
grep -E '^[0-9a-f]{64}$' "$denylist" > "$hashes" || true
if [ -s "$hashes" ]; then
    command -v python3 >/dev/null 2>&1 || die "python3 is required for the denylist check"
    hits=$(python3 - "$rows" "$hashes" <<'PY'
import hashlib, re, sys
rows_path, hashes_path = sys.argv[1], sys.argv[2]
hashes = {l.strip() for l in open(hashes_path) if l.strip()}
for line in open(rows_path, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) < 3:
        continue
    src, n, text = parts
    hit = False
    for tok in re.findall(r"[a-z0-9._/-]+", text.lower()):
        tok = tok.rstrip(".")
        while tok and not hit:
            if hashlib.sha256(tok.encode()).hexdigest() in hashes:
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
fi

exit "$found"
