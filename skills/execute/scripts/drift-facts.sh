#!/usr/bin/env bash
# drift-facts.sh -- for /execute: compute upstream drift facts before the rebase.
#
# `/execute` asks one judgment question before it dispatches children: did
# `origin/main` move in a way that changes what the PLAN means? Most runs don't
# need anyone to answer it. Either main hasn't moved, or it moved only in paths
# the PLAN never names. This script works out which case applies, from git
# alone, and writes the answer where koto can route on it. The `drift_facts`
# state runs it as its `default_action`, and `worktree_sync`'s `drift_clear`
# gate reads the result, so a run with no drift reaches `spawn_and_await`
# without the agent being asked anything.
#
# Usage: drift-facts.sh <koto-session-name> <plan-doc>
#
# Output: nothing on stdout. Two context keys on the session, written in this
# order so that if `drift_facts.json` exists, `plan_intent.md` does too:
#
#   plan_intent.md   -- the PLAN's title, upstreams, Scope Summary, and each
#                       outline's goal. At most 8192 bytes.
#   drift_facts.json -- compact JSON, `route` first, schema drift-facts/v1.
#                       At most 8192 bytes.
#
# Before anything else, once the arguments check out, both keys are removed,
# so a failed run never leaves an earlier run's facts behind for the gates.
#
# Diagnostics go to stderr.
#
# Exit codes:
#   0  -- both keys written
#   64 -- no base resolves: not a git repository, `git fetch origin` failed,
#         `origin/main` is absent, or it shares no history with the PLAN
#   65 -- the PLAN doc is missing, unreadable, or outside the repository
#   66 -- a `koto context add` or `koto context remove` failed; koto's own
#         stderr says why
#   67 -- an argument is missing
#
# ## What the script does
#
#   1. Checks its arguments (67), removes any earlier drift_facts.json and
#      plan_intent.md (66), and finds the PLAN inside the repository (65).
#   2. Fetches `origin` and resolves `origin/main` (64). The rebase in
#      `worktree_sync` doesn't fetch; it uses what this step fetched.
#   3. Resolves the base: `merge-base(<last commit touching the PLAN>,
#      origin/main)`, or `merge-base(HEAD, origin/main)` for a PLAN git doesn't
#      track yet (64 if neither resolves).
#   4. Collects reference tokens from the PLAN: the `upstream:` frontmatter
#      value(s), the entries on `**Files**:` lines, and every backticked token
#      outside fenced code blocks. Cross-repo upstreams (`owner/repo:path`) are
#      skipped, since they name another repository's tree. Tokens containing
#      `{{`, `$`, `*`, or `://` are rejected, as is anything under `wip/`.
#      A trailing line or anchor suffix (`:10`, `:10-20`, `:10,20`, `#L10`,
#      `#L10-L20`) is stripped, so the base path still counts.
#   5. Resolves each surviving token against the base tree, at file or
#      directory granularity. A path that doesn't exist at the base (a file the
#      PLAN will create) maps to its nearest existing ancestor directory; one
#      whose only existing ancestor is the repository root is dropped, because
#      the root would overlap with everything. The PLAN and its upstreams are
#      always in the set, as literal paths.
#   6. Diffs the base against `origin/main` with rename detection. A changed
#      path that equals a referenced file, or sits under a referenced
#      directory, is an overlap. A referenced path present at the base and
#      absent from `origin/main` is a deleted reference.
#   7. Picks the route and writes the two keys. The route is `judge` when there
#      is an overlap, a deleted reference, a truncated payload, or no reference
#      beyond the PLAN and its upstreams (a PLAN that names no code is always
#      asked about). Otherwise it's `none`.
#
# The facts deliberately carry no commit subjects and no diff text: paths,
# statuses, and line counts only. Whatever reads them never sees prose a third
# party wrote on main.
#
# ## Why this runs before the rebase
#
# For a PLAN that exists only on the branch, the fork point is the base, and a
# rebase moves the fork point to the tip of `origin/main`. Computed after the
# rebase, every run would look like "main hasn't advanced".
#
# That has one consequence worth knowing: a `koto rewind` into `drift_facts`
# after `worktree_sync` has run computes against the already rebased branch.
# The base comes out as `origin/main` itself, and the facts read as "main has
# not advanced" even when it had. To re-judge real drift after a rebase,
# compare against the pre-rebase commit by hand (`git reflog` has it).
#
# Bash 3.2: no associative arrays, no mapfile. Lists live in temp files.
set -uo pipefail

SESSION="${1:-}"
PLAN="${2:-}"
MAX_BYTES=8192

die() {
    # $1 exit code, rest the message
    local rc=$1
    shift
    echo "drift-facts: $*" >&2
    exit "$rc"
}

if [ -z "$SESSION" ] || [ -z "$PLAN" ]; then
    echo "usage: drift-facts.sh <koto-session-name> <plan-doc>" >&2
    die 67 "missing argument"
fi

# Facts from an earlier run (a `koto rewind` back into drift_facts) must not
# survive a failed recompute: the gates would find the old route and pass on
# it. drift_facts.json goes first, so plan_intent.md never outlives it.
# `koto context remove` succeeds when the key is already absent.
for key in drift_facts.json plan_intent.md; do
    koto context remove "$SESSION" "$key" >/dev/null \
        || die 66 "koto context remove failed for $key on session [$SESSION]"
done

command -v jq >/dev/null || die 64 "jq is required and not on PATH"

TOP=$(git rev-parse --show-toplevel) || die 64 "not inside a git repository"
TOP=$(cd "$TOP" && pwd -P)

# --- 1. the PLAN, as a repository-relative path ------------------------------

[ -f "$PLAN" ] && [ -r "$PLAN" ] || die 65 "PLAN doc [$PLAN] is missing or unreadable"
case "$PLAN" in
    /*) PLAN_ABS=$PLAN ;;
    *)  PLAN_ABS="$PWD/$PLAN" ;;
esac
PLAN_ABS="$(cd "$(dirname "$PLAN_ABS")" && pwd -P)/$(basename "$PLAN_ABS")"
PLAN_REL=${PLAN_ABS#"$TOP"/}
[ "$PLAN_REL" != "$PLAN_ABS" ] || die 65 "PLAN doc [$PLAN] is outside the repository at [$TOP]"

cd "$TOP" || die 64 "cannot enter the repository root [$TOP]"

WORK=$(mktemp -d) || die 64 "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# --- 2. fetch, and resolve origin/main ----------------------------------------

git fetch --quiet origin >/dev/null || die 64 "git fetch origin failed; no current origin/main to compare against"
MAIN_HEAD=$(git rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}') \
    || die 64 "origin/main does not exist after fetching origin"

# --- 3. the base ---------------------------------------------------------------

PLAN_COMMIT=$(git log -1 --format=%H -- "$PLAN_REL")
if [ -z "$PLAN_COMMIT" ]; then
    PLAN_COMMIT=$(git rev-parse --verify --quiet 'HEAD^{commit}') \
        || die 64 "the PLAN is untracked and HEAD has no commit to take a merge-base from"
fi
BASE=$(git merge-base "$PLAN_COMMIT" "$MAIN_HEAD") \
    || die 64 "no merge-base between $PLAN_COMMIT and origin/main"
[ -n "$BASE" ] || die 64 "no merge-base between $PLAN_COMMIT and origin/main"

COMMITS=$(git rev-list --count "$BASE..$MAIN_HEAD") || COMMITS=0

# --- 4. reference tokens from the PLAN ---------------------------------------
#
# One record per line: <kind><TAB><token>. U = upstream, F = **Files**: entry,
# T = backticked token. Title, Scope Summary, and outline goals go to their own
# files for plan_intent.md.

awk -v tok="$WORK/tokens" -v title="$WORK/title" -v scope="$WORK/scope" \
    -v goals="$WORK/goals" -v ups="$WORK/upstreams" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function unquote(s) {
        s = trim(s)
        if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
        return s
    }
    NR == 1 && /^---[ \t]*$/ { fm = 1; next }
    fm && /^---[ \t]*$/ { fm = 0; next }
    fm {
        if ($0 ~ /^upstream:/) {
            v = $0; sub(/^upstream:/, "", v); v = unquote(v)
            if (v != "") { print "U\t" v > tok; print v > ups; in_up = 0 }
            else in_up = 1
            next
        }
        if (in_up && $0 ~ /^[ \t]*-[ \t]/) {
            v = $0; sub(/^[ \t]*-[ \t]*/, "", v); v = unquote(v)
            if (v != "") { print "U\t" v > tok; print v > ups }
            next
        }
        in_up = 0
        next
    }
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^# / && !got_title { print $0 > title; got_title = 1 }
    /^## / {
        in_scope = ($0 ~ /^## Scope Summary[ \t]*$/)
        issue = ""
        next
    }
    /^### Issue / { issue = $0; sub(/^### /, "", issue) }
    in_scope { print $0 > scope }
    /^\*\*Goal\*\*:/ && issue != "" {
        g = $0; sub(/^\*\*Goal\*\*:[ \t]*/, "", g)
        print "- " issue " -- " g > goals
    }
    /^\*\*Files\*\*:/ {
        f = $0; sub(/^\*\*Files\*\*:/, "", f)
        n = split(f, parts, ",")
        for (i = 1; i <= n; i++) {
            p = trim(parts[i]); gsub(/`/, "", p); p = trim(p)
            if (p != "") print "F\t" p > tok
        }
    }
    {
        line = $0
        while (match(line, /`[^`]+`/)) {
            print "T\t" substr(line, RSTART + 1, RLENGTH - 2) > tok
            line = substr(line, RSTART + RLENGTH)
        }
    }
' "$PLAN_REL" || die 65 "could not read PLAN doc [$PLAN_REL]"

touch "$WORK/tokens" "$WORK/title" "$WORK/scope" "$WORK/goals" "$WORK/upstreams"

# --- 5. resolve against the base tree ----------------------------------------
#
# refs holds one line per referenced path: <path><TAB><anchor>. A directory is
# written with a trailing slash. anchor is 1 for the PLAN and its upstreams,
# which are in the set by definition and don't count as naming code.

obj_type() {
    # $1 commit, $2 path -> blob | tree | "" (absent). ls-tree prints nothing
    # for a path that isn't there, where `cat-file -t` would print an error for
    # every probe. The pathspec is literal: tokens reaching here carry no glob
    # characters.
    git ls-tree "$1" -- "$2" | awk '{ print $2; exit }'
}

ANCHOR_SUFFIX_RE='^(.+)#L[0-9]+(-L[0-9]+)?$'
LINE_SUFFIX_RE='^(.+):[0-9]+([-,][0-9]+)?$'

# Normalizes a token to a repository-relative path, or prints nothing when the
# token is not path-shaped or is one of the rejected shapes.
normalize() {
    local t=$1
    case "$t" in
        *'{{'*|*'$'*|*'*'*|*'://'*) return 0 ;;
    esac
    # A line or anchor suffix still names the file: `a.go#L10-L20` and
    # `a.go:10`, `a.go:10-20`, `a.go:10,20` all reference `a.go`. The regexes
    # live in variables so bash 3.2 and later read them the same way.
    if [[ $t =~ $ANCHOR_SUFFIX_RE ]]; then
        t=${BASH_REMATCH[1]}
    fi
    if [[ $t =~ $LINE_SUFFIX_RE ]]; then
        t=${BASH_REMATCH[1]}
    fi
    case "$t" in
        *[!A-Za-z0-9._/@+-]*|'') return 0 ;;
    esac
    case "$t" in
        */*|*.*) ;;
        *) return 0 ;;
    esac
    while :; do
        case "$t" in
            ./*) t=${t#./} ;;
            *) break ;;
        esac
    done
    while :; do
        case "$t" in
            */) t=${t%/} ;;
            *) break ;;
        esac
    done
    case "$t" in
        ''|/*|..|../*|*/..|*/../*|.|wip|wip/*) return 0 ;;
    esac
    printf '%s' "$t"
}

: > "$WORK/refs"
printf '%s\t1\n' "$PLAN_REL" >> "$WORK/refs"

while IFS="$(printf '\t')" read -r kind token; do
    [ -n "$token" ] || continue
    if [ "$kind" = "U" ]; then
        # owner/repo:path names another repository's tree.
        case "$token" in
            *:*) continue ;;
        esac
    fi
    path=$(normalize "$token")
    [ -n "$path" ] || continue
    if [ "$kind" = "U" ]; then
        printf '%s\t1\n' "$path" >> "$WORK/refs"
        continue
    fi
    type=$(obj_type "$BASE" "$path")
    while [ -z "$type" ]; do
        case "$path" in
            */*) path=${path%/*} ;;
            *) path=""; break ;;
        esac
        type=$(obj_type "$BASE" "$path")
    done
    # The root-ancestor drop: nothing on the token's path existed at the base.
    [ -n "$path" ] || continue
    if [ "$type" = "tree" ]; then
        printf '%s/\t0\n' "$path" >> "$WORK/refs"
    else
        printf '%s\t0\n' "$path" >> "$WORK/refs"
    fi
done < "$WORK/tokens"

# De-duplicate by path, keeping the anchor flag if any record set it.
sort -t "$(printf '\t')" -k1,1 -k2,2r "$WORK/refs" | awk -F '\t' '!seen[$1]++' > "$WORK/refs.u"
CODE_REFS=$(awk -F '\t' '$2 == 0' "$WORK/refs.u" | wc -l | tr -d ' ')
cut -f1 "$WORK/refs.u" > "$WORK/refpaths"

# --- 6. what main changed, and what of it the PLAN references ----------------

TRUNCATED=false
: > "$WORK/status"
: > "$WORK/numstat"
TAB=$(printf '\t')

# -z output, so any path parses. A path that carries a tab or a newline can't
# go through the TSV below; rather than drop it silently, the payload is marked
# truncated, which routes to judge.
git diff -z --name-status -M "$BASE" "$MAIN_HEAD" > "$WORK/ns.z" \
    || die 64 "git diff between the base and origin/main failed"
git diff -z --numstat -M "$BASE" "$MAIN_HEAD" > "$WORK/num.z" \
    || die 64 "git diff between the base and origin/main failed"

has_bad_char() {
    case "$1" in
        *"$TAB"*|*'
'*) return 0 ;;
    esac
    return 1
}

while IFS= read -r -d '' st; do
    case "$st" in
        R*|C*)
            IFS= read -r -d '' old
            IFS= read -r -d '' new
            ;;
        *)
            IFS= read -r -d '' old
            # A tab is IFS whitespace, so `read` would collapse an empty field
            # and shift the ones after it. No git path starts with a slash,
            # which makes one a safe stand-in for "no new path".
            new="/"
            ;;
    esac
    if has_bad_char "$old" || has_bad_char "$new"; then
        TRUNCATED=true
        printf 'X\t/\t/\n' >> "$WORK/status"
        continue
    fi
    printf '%s\t%s\t%s\n' "$st" "$old" "$new" >> "$WORK/status"
done < "$WORK/ns.z"

while IFS= read -r -d '' rec; do
    case "$rec" in
        *"$TAB")
            # A rename: the paths follow as their own records.
            IFS= read -r -d '' _old
            IFS= read -r -d '' _new
            ;;
    esac
    added=${rec%%"$TAB"*}
    rest=${rec#*"$TAB"}
    removed=${rest%%"$TAB"*}
    printf '%s\t%s\n' "$added" "$removed" >> "$WORK/numstat"
done < "$WORK/num.z"

# The two diffs list entries in the same order, so they join by line number.
paste "$WORK/status" "$WORK/numstat" > "$WORK/changes"

status_word() {
    case "$1" in
        A*) echo added ;;
        C*) echo copied ;;
        D*) echo deleted ;;
        M*) echo modified ;;
        R*) echo renamed ;;
        T*) echo type-changed ;;
        *)  echo unknown ;;
    esac
}

# $1 changed path -> 0 when it equals a referenced file or sits under a
# referenced directory.
is_referenced() {
    local ref
    [ -n "$1" ] || return 1
    while IFS= read -r ref; do
        case "$ref" in
            */)
                case "$1" in
                    "$ref"*) return 0 ;;
                esac
                ;;
            *)
                [ "$1" = "$ref" ] && return 0
                ;;
        esac
    done < "$WORK/refpaths"
    return 1
}

: > "$WORK/overlap"
while IFS="$TAB" read -r st old new added removed; do
    [ "$st" = "X" ] && continue
    [ -n "$st" ] || continue
    [ "$new" = "/" ] && new=""
    if is_referenced "$old" || is_referenced "$new"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$old" "$(status_word "$st")" "$added" "$removed" "$new" >> "$WORK/overlap"
    fi
done < "$WORK/changes"

: > "$WORK/deleted"
while IFS= read -r ref; do
    p=${ref%/}
    [ -n "$(obj_type "$BASE" "$p")" ] || continue
    [ -z "$(obj_type "$MAIN_HEAD" "$p")" ] || continue
    printf '%s\n' "$ref" >> "$WORK/deleted"
done < "$WORK/refpaths"

# --- 7. plan_intent.md, then drift_facts.json --------------------------------

# Cuts a file to MAX_BYTES at a line boundary, so a multi-byte character is
# never split, and marks the cut.
cap_file() {
    local in=$1 out=$2 size
    size=$(wc -c < "$in" | tr -d ' ')
    if [ "$size" -le "$MAX_BYTES" ]; then
        cat "$in" > "$out"
        return 0
    fi
    head -c "$((MAX_BYTES - 32))" "$in" | sed '$d' > "$out"
    printf '\n[plan intent truncated]\n' >> "$out"
}

{
    if [ -s "$WORK/title" ]; then
        cat "$WORK/title"
    else
        printf '# %s\n' "$PLAN_REL"
    fi
    printf '\nPLAN: %s\n' "$PLAN_REL"
    if [ -s "$WORK/upstreams" ]; then
        printf '\nUpstream:\n'
        sed 's/^/- /' "$WORK/upstreams"
    fi
    printf '\n## Scope Summary\n'
    if [ -s "$WORK/scope" ]; then
        cat "$WORK/scope"
    else
        printf '\n(none)\n'
    fi
    printf '\n## Outline Goals\n\n'
    if [ -s "$WORK/goals" ]; then
        cat "$WORK/goals"
    else
        printf '(none)\n'
    fi
} > "$WORK/intent.raw"
cap_file "$WORK/intent.raw" "$WORK/intent.md"

koto context add "$SESSION" plan_intent.md < "$WORK/intent.md" >/dev/null \
    || die 66 "koto context add failed for plan_intent.md on session [$SESSION]"

REFS_JSON=$(jq -R . < "$WORK/refpaths" | jq -s -c .)
DELETED_JSON=$(jq -R . < "$WORK/deleted" | jq -s -c .)
OVERLAP_JSON=$(jq -R -c 'split("\t") | {path: .[0], status: .[1],
        added: (.[2] | tonumber? // null), removed: (.[3] | tonumber? // null)}
        + (if (.[4] // "") != "" then {renamed_to: .[4]} else {} end)' < "$WORK/overlap" | jq -s -c .)

# Everything but the three lists is fixed-size, so the lists are what gets cut.
# `cap` starts at the longest list and halves until the payload fits.
build() {
    # $1 cap (-1 = no cap), $2 truncated
    jq -n -c \
        --argjson refs "$REFS_JSON" --argjson overlap "$OVERLAP_JSON" \
        --argjson deleted "$DELETED_JSON" --argjson cap "$1" \
        --argjson truncated "$2" --argjson code_refs "$CODE_REFS" \
        --argjson commits "$COMMITS" \
        --arg plan "$PLAN_REL" --arg base "$BASE" --arg main "$MAIN_HEAD" '
        def cut: if $cap < 0 then . else .[:$cap] end;
        ([ (if $truncated then "truncated" else empty end),
           (if $code_refs == 0 then "no_code_references" else empty end),
           (if ($overlap | length) > 0 then "overlap" else empty end),
           (if ($deleted | length) > 0 then "deleted_references" else empty end)
         ]) as $judge
        | {
            route: (if ($judge | length) > 0 then "judge" else "none" end),
            schema: "drift-facts/v1",
            reasons: (if ($judge | length) > 0 then $judge
                      elif $commits == 0 then ["main_not_advanced"]
                      else ["no_overlap"] end),
            plan_doc: $plan,
            base: $base,
            main_head: $main,
            main_advanced: ($commits > 0),
            commits_since_base: $commits,
            referenced_paths: ($refs | cut),
            overlap: ($overlap | cut),
            deleted_referenced_paths: ($deleted | cut),
            truncated: $truncated
          }'
}

FACTS=$(build -1 "$TRUNCATED")
if [ "${#FACTS}" -gt "$MAX_BYTES" ] || [ "$(printf '%s' "$FACTS" | wc -c | tr -d ' ')" -gt "$MAX_BYTES" ]; then
    CAP=$(printf '%s\n%s\n%s\n' "$REFS_JSON" "$OVERLAP_JSON" "$DELETED_JSON" | jq -s 'map(length) | max')
    while :; do
        CAP=$((CAP / 2))
        FACTS=$(build "$CAP" true)
        [ "$(printf '%s' "$FACTS" | wc -c | tr -d ' ')" -le "$MAX_BYTES" ] && break
        [ "$CAP" -gt 0 ] || break
    done
fi

printf '%s' "$FACTS" | koto context add "$SESSION" drift_facts.json >/dev/null \
    || die 66 "koto context add failed for drift_facts.json on session [$SESSION]"

exit 0
