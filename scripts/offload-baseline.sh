#!/usr/bin/env bash
#
# offload-baseline.sh - check the template pin and re-run the token count
#
# The instruction-offload baseline in docs/measurement/offload-baseline/ fixes
# a starting point before anything changes what the koto-templated skills
# (work-on, execute, scope, deliver) load. This script is the only tooling it
# needs: one subcommand proves the template pin still describes the commit it
# names, the other re-runs the per-skill instruction-token count at any commit.
# The method, the figures and the provisional definitions are in that
# directory's README.md.
#
# Both subcommands read the measured files from git objects at the commit, not
# from the working tree, so they give the same answer at the same commit from
# any checkout and leave the tree as they found it. The pin and the manifest
# themselves are ordinary files: by default the ones committed beside this
# script (resolved from the script's own location), so `count <old commit>`
# applies today's manifest to that commit's files. git runs in the repository
# of the current directory, which is normally the same one; the tests rely on
# the split to point the script at a throwaway repository. The only files
# written are under a mktemp -d directory removed on exit, plus koto's own
# compile cache when verify-pin compiles a template.
#
# Usage:
#   scripts/offload-baseline.sh verify-pin [--pin <file>]
#   scripts/offload-baseline.sh count <commit> [--manifest <file>]
#
# verify-pin
#   Checks every entry of the template pin against its pinned commit: the set
#   of templates, each entry's skill, git blob, declared name and version, and,
#   when the installed koto is the pinned koto version, the koto template hash.
#   With a different koto, or none, the hash comparison is reported as skipped
#   and does not fail the check.
#
# count
#   Prints, per profile in manifest order, a tab-separated line:
#     <profile> <raw tokens> <weighted tokens>
#   Tokens are bytes divided by 4. Raw counts each distinct (path, selector) of
#   a profile once; weighted multiplies each row's bytes by its weight. Each
#   total is divided by 4 and rounded to the nearest integer once, at the end.
#
# Manifest format (tab-separated; blank lines and lines starting with # are
# ignored; the first non-comment line is a header and is skipped):
#   profile  path  selector  weight  note
# Selectors:
#   file          the whole file
#   body          the file after its leading YAML frontmatter block
#   state:<name>  in a koto template, the `## <name>` section after the
#                 frontmatter, up to the next `## ` heading. Trailing blank
#                 lines of the section are not counted (the section is read
#                 through a command substitution); file and body count every
#                 byte. Changing either rule changes every recorded figure.
#
# Exit codes:
#   0 - verify-pin found no mismatch; count printed its figures
#   1 - verify-pin found a problem with the pin: a mismatch, a pin that does
#       not parse or lacks a field, or a pinned commit that is not a commit
#       here (each printed on stderr)
#   2 - usage error, or count could not complete (nothing printed on stdout)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_DIR="$REPO_ROOT/docs/measurement/offload-baseline"

# The skills whose koto templates the pin covers.
PINNED_SKILLS="work-on execute scope deliver"

PROG=offload-baseline
TMP_DIR=""

cleanup() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    return 0
}
trap cleanup EXIT

die() {
    echo "$PROG: $*" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Usage:
  scripts/offload-baseline.sh verify-pin [--pin <file>]
  scripts/offload-baseline.sh count <commit> [--manifest <file>]
EOF
    exit 0
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

# Resolves a commit argument to a full sha, refusing anything git could read
# as an option.
resolve_commit() {
    local arg="$1" sha
    case "$arg" in
        "") die "a commit is required" ;;
        -*) die "refusing commit argument that starts with '-': $arg" ;;
    esac
    sha=$(git rev-parse --verify --quiet --end-of-options "${arg}^{commit}") \
        || die "no such commit: $arg"
    printf '%s\n' "$sha"
}

# Prints the file at <sha>:<path> on stdout.
blob() {
    git cat-file blob "$1:$2"
}

# Strips a leading YAML frontmatter block (--- ... ---) from stdin.
strip_frontmatter() {
    awk '
        NR == 1 && $0 == "---" { infm = 1; next }
        infm && $0 == "---" { infm = 0; next }
        infm { next }
        { print }
    '
}

# Prints one template state's section from stdin (after the frontmatter).
# Exits 3 when the state is not found.
state_section() {
    strip_frontmatter | awk -v want="## $1" '
        $0 == want { on = 1; found = 1; print; next }
        on && /^## / { on = 0 }
        on { print }
        END { if (!found) exit 3 }
    '
}

# Prints the byte count of one (commit, path, selector) span, or fails with a
# message naming what is missing.
span_bytes() {
    local sha="$1" path="$2" selector="$3" out status
    git cat-file -e "$sha:$path" 2>/dev/null \
        || { echo "$PROG: $path does not exist at ${sha}" >&2; return 1; }
    case "$selector" in
        file)
            blob "$sha" "$path" | wc -c | tr -d ' '
            ;;
        body)
            blob "$sha" "$path" | strip_frontmatter | wc -c | tr -d ' '
            ;;
        state:*)
            status=0
            out=$(blob "$sha" "$path" | state_section "${selector#state:}") || status=$?
            if [ "$status" -ne 0 ]; then
                echo "$PROG: state '${selector#state:}' not found in $path at ${sha}" >&2
                return 1
            fi
            printf '%s\n' "$out" | wc -c | tr -d ' '
            ;;
        *)
            echo "$PROG: unknown selector '$selector' for $path" >&2
            return 1
            ;;
    esac
}

cmd_count() {
    local commit="" manifest="$BASELINE_DIR/load-manifest.tsv"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --manifest)
                [ "$#" -ge 2 ] || die "--manifest requires a value"
                manifest="$2"; shift ;;
            -h|--help) usage ;;
            *)
                [ -z "$commit" ] || die "unexpected argument: $1"
                commit="$1" ;;
        esac
        shift
    done
    [ -n "$commit" ] || die "count requires a commit"
    [ -f "$manifest" ] || die "manifest not found: $manifest"

    local sha
    sha=$(resolve_commit "$commit")

    TMP_DIR=$(mktemp -d)
    local rows="$TMP_DIR/rows"
    : > "$rows"

    # One line per manifest row: profile, key, bytes, weight. Any missing span
    # fails the whole count before anything reaches stdout.
    local header_seen=0 line profile path selector weight note bytes failed=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|"#"*) continue ;;
        esac
        if [ "$header_seen" -eq 0 ]; then
            header_seen=1
            continue
        fi
        IFS='	' read -r profile path selector weight note <<EOF
$line
EOF
        if [ -z "$profile" ] || [ -z "$path" ] || [ -z "$selector" ] || [ -z "$weight" ]; then
            echo "$PROG: malformed manifest row: $line" >&2
            failed=1
            continue
        fi
        # A plain decimal: digits, optionally one point followed by digits.
        case "$weight" in
            ""|*[!0-9.]*|.*|*.|*.*.*)
                echo "$PROG: bad weight '$weight' for $path" >&2
                failed=1
                continue
                ;;
        esac
        if bytes=$(span_bytes "$sha" "$path" "$selector"); then
            printf '%s\t%s\t%s\t%s\n' "$profile" "$path|$selector" "$bytes" "$weight" >> "$rows"
        else
            failed=1
        fi
    done < "$manifest"

    [ "$failed" -eq 0 ] || die "count failed at ${sha}; no figures printed"
    [ -s "$rows" ] || die "manifest has no rows: $manifest"

    awk -F '\t' '
        {
            if (!($1 in seen_profile)) { seen_profile[$1] = 1; order[++n] = $1 }
            key = $1 SUBSEP $2
            if (!(key in seen_span)) { seen_span[key] = 1; raw[$1] += $3 }
            weighted[$1] += $3 * $4
        }
        END {
            for (i = 1; i <= n; i++) {
                p = order[i]
                printf "%s\t%d\t%d\n", p, int(raw[p] / 4 + 0.5), int(weighted[p] / 4 + 0.5)
            }
        }
    ' "$rows"
}

# Reads a top-level frontmatter scalar (name or version) from stdin.
#
# It reads its input to the end rather than exiting at the frontmatter's
# close: the writer is `git cat-file` on a template larger than a pipe buffer,
# and a reader that exits early sends it SIGPIPE, which pipefail turns into a
# silent exit 141 wherever SIGPIPE isn't ignored (it is on CI runners).
frontmatter_scalar() {
    awk -v key="$1" '
        done { next }
        NR == 1 && $0 != "---" { done = 1; next }
        NR == 1 { next }
        $0 == "---" { done = 1; next }
        index($0, key ":") == 1 {
            v = substr($0, length(key) + 2)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
            print v
            done = 1
        }
    '
}

# Lists the koto templates of the pinned skills at <sha>, one path per line.
templates_at() {
    local sha="$1" skill
    # --full-tree: paths are from the repository root even when the caller
    # runs from a subdirectory. The greps end with `|| true` so an empty
    # listing is an empty set, which the comparison below reports, rather
    # than a pipefail exit with nothing said.
    for skill in $PINNED_SKILLS; do
        git ls-tree --full-tree --name-only "$sha" -- "skills/$skill/koto-templates/" 2>/dev/null || true
    done | { grep -E '^skills/[^/]+/koto-templates/[^/]+\.md$' || true; } \
         | { grep -v '\.mermaid\.md$' || true; } | LC_ALL=C sort
}

cmd_verify_pin() {
    local pin="$BASELINE_DIR/template-pin.json"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --pin)
                [ "$#" -ge 2 ] || die "--pin requires a value"
                pin="$2"; shift ;;
            -h|--help) usage ;;
            *) die "unexpected argument: $1" ;;
        esac
        shift
    done
    [ -f "$pin" ] || die "pin not found: $pin"
    jq -e 'type == "object"' "$pin" >/dev/null 2>&1 || { echo "$PROG: $pin does not parse as a JSON object" >&2; exit 1; }

    local errors=0
    mismatch() {
        echo "$PROG: $*" >&2
        errors=$((errors + 1))
    }

    local commit koto_pinned
    commit=$(jq -r '.pinned_commit // empty | strings' "$pin")
    koto_pinned=$(jq -r '.koto_version // empty | strings' "$pin")
    [ -n "$commit" ] || { echo "$PROG: pin has no pinned_commit" >&2; exit 1; }
    [ -n "$koto_pinned" ] || { mismatch "pin has no koto_version"; koto_pinned="(none)"; }
    jq -e '.templates | type == "array"' "$pin" >/dev/null 2>&1 \
        || { echo "$PROG: pin has no templates array" >&2; exit 1; }

    # resolve_commit is not reused here: a bad pinned commit is a problem with
    # the pin (exit 1), not a usage error (exit 2).
    local sha
    case "$commit" in
        -*) echo "$PROG: pinned_commit starts with '-': $commit" >&2; exit 1 ;;
    esac
    sha=$(git rev-parse --verify --quiet --end-of-options "${commit}^{commit}") \
        || { echo "$PROG: pinned_commit $commit is not a commit here" >&2; exit 1; }

    # Whether the koto hash can be compared on this machine.
    local koto_installed="" compare_koto=0
    if command -v koto >/dev/null 2>&1; then
        koto_installed=$(koto version 2>/dev/null | awk 'NR == 1 { print $2 }')
    fi
    if [ -n "$koto_installed" ] && [ "$koto_installed" = "$koto_pinned" ]; then
        compare_koto=1
    elif [ -z "$koto_installed" ]; then
        echo "$PROG: koto hash comparison skipped: koto is not installed (pinned $koto_pinned)" >&2
    else
        echo "$PROG: koto hash comparison skipped: installed koto $koto_installed, pinned $koto_pinned" >&2
    fi

    TMP_DIR=$(mktemp -d)

    # koto compiles a template together with the child templates it names by
    # relative path (execute.md names ../../work-on/koto-templates/work-on.md),
    # so every pinned skill's koto-templates/ directory is extracted with its
    # layout intact. The compiled hash does not depend on where the tree sits.
    if [ "$compare_koto" -eq 1 ]; then
        mkdir -p "$TMP_DIR/tree"
        local kt
        for kt in $(templates_at "$sha"); do
            mkdir -p "$TMP_DIR/tree/$(dirname "$kt")"
            blob "$sha" "$kt" > "$TMP_DIR/tree/$kt"
        done
    fi

    # The set of paths must equal the set of templates at the commit.
    templates_at "$sha" > "$TMP_DIR/expected"
    jq -r '.templates[] | (.path // "") | strings' "$pin" | LC_ALL=C sort > "$TMP_DIR/actual"
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && mismatch "missing entry for $p"
    done <<EOF
$(LC_ALL=C comm -23 "$TMP_DIR/expected" "$TMP_DIR/actual")
EOF
    while IFS= read -r p; do
        [ -n "$p" ] && mismatch "entry $p: no such template at $commit"
    done <<EOF
$(LC_ALL=C comm -13 "$TMP_DIR/expected" "$TMP_DIR/actual")
EOF

    local count i entry path skill declared_name declared_version git_blob koto_hash
    local field actual_blob actual_name actual_version compiled actual_hash
    count=$(jq '.templates | length' "$pin")
    i=0
    while [ "$i" -lt "$count" ]; do
        entry=$(jq -c ".templates[$i]" "$pin")
        i=$((i + 1))
        path=$(printf '%s' "$entry" | jq -r '.path // empty | strings')
        [ -n "$path" ] || path="(entry $i)"

        local missing=0
        for field in skill path declared_name declared_version git_blob koto_template_hash; do
            if ! printf '%s' "$entry" | jq -e --arg f "$field" '.[$f] | type == "string" and length > 0' >/dev/null; then
                mismatch "entry $path: missing field $field"
                missing=1
            fi
        done
        [ "$missing" -eq 0 ] || continue

        skill=$(printf '%s' "$entry" | jq -r '.skill')
        declared_name=$(printf '%s' "$entry" | jq -r '.declared_name')
        declared_version=$(printf '%s' "$entry" | jq -r '.declared_version')
        git_blob=$(printf '%s' "$entry" | jq -r '.git_blob')
        koto_hash=$(printf '%s' "$entry" | jq -r '.koto_template_hash')

        case "$path" in
            "skills/$skill/koto-templates/"*) ;;
            *) mismatch "entry $path: skill '$skill' does not match its path" ;;
        esac

        # A path the commit lacks was already reported by the set comparison.
        git cat-file -e "$sha:$path" 2>/dev/null || continue

        actual_blob=$(git rev-parse "$sha:$path")
        [ "$actual_blob" = "$git_blob" ] \
            || mismatch "entry $path: git_blob $git_blob, but $commit has $actual_blob"

        actual_name=$(blob "$sha" "$path" | frontmatter_scalar name)
        actual_version=$(blob "$sha" "$path" | frontmatter_scalar version)
        [ "$actual_name" = "$declared_name" ] \
            || mismatch "entry $path: declared_name '$declared_name', but the template says '$actual_name'"
        [ "$actual_version" = "$declared_version" ] \
            || mismatch "entry $path: declared_version '$declared_version', but the template says '$actual_version'"

        if [ "$compare_koto" -eq 1 ]; then
            if compiled=$(koto template compile "$TMP_DIR/tree/$path" 2>/dev/null); then
                actual_hash=$(basename "$compiled" .json)
                [ "$actual_hash" = "$koto_hash" ] \
                    || mismatch "entry $path: koto_template_hash $koto_hash, but koto $koto_installed compiles $actual_hash"
            else
                mismatch "entry $path: koto template compile failed"
            fi
        fi
    done

    if [ "$errors" -gt 0 ]; then
        echo "$PROG: verify-pin found $errors mismatch(es) against $commit" >&2
        exit 1
    fi
    echo "$PROG: pin verified against $commit ($count templates)" >&2
}

need git
need jq

[ "$#" -ge 1 ] || die "a subcommand is required: verify-pin or count (--help for usage)"
sub="$1"
shift
case "$sub" in
    verify-pin) cmd_verify_pin "$@" ;;
    count) cmd_count "$@" ;;
    -h|--help) usage ;;
    *) die "unknown subcommand: $sub" ;;
esac
