#!/usr/bin/env bash
# Tests for check-citations.sh.
#
# The case that matters most is `survivor_upstream_citation_does_not_refuse`.
# Without the survivor exclusion this guard refuses every fold, so that test is
# the tripwire for the whole mechanism rather than one behaviour among several.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly GUARD="$SCRIPT_DIR/check-citations.sh"

pass=0
fail=0

fail_test() {
    printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
    fail=$((fail + 1))
}

ok_test() {
    printf 'ok: %s\n' "$1"
    pass=$((pass + 1))
}

# Build a throwaway repo with a BRIEF being absorbed into a PRD.
new_repo() {
    local dir
    dir=$(mktemp -d)
    (
        cd "$dir" || exit 1
        git init -q .
        git config user.email t@example.com
        git config user.name t
        mkdir -p docs/briefs docs/prds docs/designs skills crates/shirabe/tests/fixtures
        cat > docs/briefs/BRIEF-topic.md <<'EOF'
# BRIEF: Topic
EOF
        # The survivor always cites the absorbed artifact by path, more than
        # once, which is exactly the shape that makes the exclusion necessary.
        cat > docs/prds/PRD-topic.md <<'EOF'
---
upstream: docs/briefs/BRIEF-topic.md
---
# PRD: Topic

Framing carried from docs/briefs/BRIEF-topic.md.
EOF
        git add -A
        git commit -qm init
    ) || return 1
    printf '%s' "$dir"
}

run_guard() {
    local dir="$1"; shift
    ( cd "$dir" && "$GUARD" "$@" >/dev/null 2>&1 )
    printf '%s' "$?"
}

# --- 0: clean -------------------------------------------------------------
dir=$(new_repo) || exit 1
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "0" ]] \
    && ok_test "clean repo exits 0" \
    || fail_test "clean repo exits 0" "expected 0, got $got"

# --- the tripwire: the survivor's own citations must not refuse -----------
# This is the whole mechanism. The survivor cites the absorbed path twice
# above; if either counted, no fold could ever complete.
[[ "$got" == "0" ]] \
    && ok_test "survivor_upstream_citation_does_not_refuse" \
    || fail_test "survivor_upstream_citation_does_not_refuse" \
       "the survivor's own citation refused the fold; exclusion is broken"
rm -rf "$dir"

# --- 1: a third party cites the path --------------------------------------
dir=$(new_repo) || exit 1
printf 'See docs/briefs/BRIEF-topic.md for framing.\n' > "$dir/docs/designs/DESIGN-other.md"
( cd "$dir" && git add -A && git commit -qm third-party )
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "1" ]] \
    && ok_test "third-party path citation exits 1" \
    || fail_test "third-party path citation exits 1" "expected 1, got $got"
rm -rf "$dir"

# --- 2: bare name only ----------------------------------------------------
dir=$(new_repo) || exit 1
printf 'BRIEF-topic.md was the framing document.\n' > "$dir/docs/designs/DESIGN-other.md"
( cd "$dir" && git add -A && git commit -qm bare-name )
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "2" ]] \
    && ok_test "bare-name mention exits 2" \
    || fail_test "bare-name mention exits 2" "expected 2, got $got"
rm -rf "$dir"

# --- fixtures are not citations -------------------------------------------
dir=$(new_repo) || exit 1
printf 'docs/briefs/BRIEF-topic.md\n' > "$dir/crates/shirabe/tests/fixtures/sample.md"
( cd "$dir" && git add -A && git commit -qm fixture )
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "0" ]] \
    && ok_test "fixture corpora do not refuse a fold" \
    || fail_test "fixture corpora do not refuse a fold" "expected 0, got $got"
rm -rf "$dir"

# --- wip/ is not a citation -----------------------------------------------
dir=$(new_repo) || exit 1
mkdir -p "$dir/wip"
printf 'docs/briefs/BRIEF-topic.md\n' > "$dir/wip/scratch.md"
( cd "$dir" && git add -A && git commit -qm wip )
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "0" ]] \
    && ok_test "wip scratch does not refuse a fold" \
    || fail_test "wip scratch does not refuse a fold" "expected 0, got $got"
rm -rf "$dir"


# --- 3: a pathspec-shaped argument is refused, not obeyed -----------------
# `--` does not disable pathspec globbing. An argument like docs/* would blind
# the search and the fold would proceed on a clean exit, so the shape is
# asserted rather than trusted.
dir=$(new_repo) || exit 1
got=$(run_guard "$dir" --target 'docs/*' --survivor docs/prds/PRD-topic.md)
[[ "$got" == "3" ]] \
    && ok_test "a glob-shaped target exits 3" \
    || fail_test "a glob-shaped target exits 3" "expected 3, got $got"
rm -rf "$dir"

# --- 3: outside a git work tree -------------------------------------------
dir=$(mktemp -d)
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md --survivor docs/prds/PRD-topic.md)
[[ "$got" == "3" ]] \
    && ok_test "outside a work tree exits 3" \
    || fail_test "outside a work tree exits 3" "expected 3, got $got"
rm -rf "$dir"

# --- 3: missing required argument -----------------------------------------
dir=$(new_repo) || exit 1
got=$(run_guard "$dir" --target docs/briefs/BRIEF-topic.md)
[[ "$got" == "3" ]] \
    && ok_test "a missing --survivor exits 3" \
    || fail_test "a missing --survivor exits 3" "expected 3, got $got"
rm -rf "$dir"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
