#!/usr/bin/env bash
# review-packet_test.sh -- test harness for scripts/review-packet.sh, which
# assembles the input packet every review seat starts from.
#
# Usage: bash scripts/review-packet_test.sh
#        /bin/bash scripts/review-packet_test.sh     # the bash 3.2 floor
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# No real koto or gh is needed. A stub koto answers `context exists` and
# `context get` from a directory of files named after their keys, and a stub gh
# prints a canned issue body, so every case runs on a bare runner. The cases
# pin the packet's sections, the base order (impl_base, then the merge-base),
# the caps and their trailers, and that a failure leaves no packet behind.
# The spawn-site cases then check that every review spawn site still names
# a model, a call budget and the packet command.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PACKET_SH="$SCRIPT_DIR/review-packet.sh"
BASH_BIN=$(command -v "${BASH:-bash}")

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { printf "${GREEN}PASS${NC}: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf "${RED}FAIL${NC}: %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$PACKET_SH" ] || { echo "FAIL: review-packet.sh not found at $PACKET_SH" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH, no case ran"; exit 0; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

# Stubs. KOTO_STORE is a directory with one file per context key.
STUBS="$ROOT/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/koto" <<'EOF'
#!/bin/sh
[ "$1" = context ] || exit 2
case "$2" in
    exists) [ -f "$KOTO_STORE/$4" ] ;;
    get)    [ -f "$KOTO_STORE/$4" ] && cat "$KOTO_STORE/$4" ;;
    *)      exit 2 ;;
esac
EOF
cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
[ -n "${GH_FAIL:-}" ] && { echo "gh: not authenticated" >&2; exit 4; }
cat "$GH_BODY"
EOF
chmod +x "$STUBS/koto" "$STUBS/gh"

# A repository with one commit on main and two on a feature branch.
REPO="$ROOT/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main
    git config user.email t@example.com
    git config user.name t
    # A developer's global signing setup must not reach the fixture's commits.
    git config commit.gpgsign false
    echo base > a.txt
    git add a.txt
    git commit -q -m base
    git checkout -q -b feature
    echo changed >> a.txt
    echo new > b.txt
    git add a.txt b.txt
    git commit -q -m one
    echo more > c.txt
    git add c.txt
    git commit -q -m two
) || { echo "FAIL: could not build the fixture repository" >&2; exit 1; }
MAIN_SHA=$(git -C "$REPO" rev-parse main)
FIRST_SHA=$(git -C "$REPO" rev-parse feature~1)

run() {
    # Runs the script in the fixture repo with the stubs first on PATH.
    # Sets OUT, ERR, CODE.
    local store="$1"
    shift
    OUT=$( cd "$REPO" && KOTO_STORE="$store" GH_BODY="${GH_BODY:-/dev/null}" \
        PATH="$STUBS:$PATH" TMPDIR="$ROOT/tmp" "$BASH_BIN" "$PACKET_SH" "$@" 2>"$ROOT/err" )
    CODE=$?
    ERR=$(cat "$ROOT/err")
}
mkdir -p "$ROOT/tmp"

leftover_packets() { ls "$ROOT/tmp" | grep -c '^review-packet\.' ; }

# -------------------------------------------------------------- usage --------

run "$ROOT/none"
[ "$CODE" -eq 67 ] && pass "no kind: exit 67" || fail "no kind: exit $CODE"

run "$ROOT/none" bogus
[ "$CODE" -eq 67 ] && pass "unknown kind: exit 67" || fail "unknown kind: exit $CODE"

run "$ROOT/none" code --doc x
[ "$CODE" -eq 67 ] && pass "doc flag on code: exit 67" || fail "doc flag on code: exit $CODE"

run "$ROOT/none" code --session
[ "$CODE" -eq 67 ] && pass "flag with no value: exit 67" || fail "flag with no value: exit $CODE"

run "$ROOT/none" code --session s --issue 12 --criteria /dev/null
[ "$CODE" -eq 67 ] && pass "--issue with --criteria: exit 67" || fail "--issue with --criteria: exit $CODE"

run "$ROOT/none" code --session s --issue '12;rm'
[ "$CODE" -eq 67 ] && pass "non-numeric --issue: exit 67" || fail "non-numeric --issue: exit $CODE"

run "$ROOT/none" doc --doc a.txt
[ "$CODE" -eq 67 ] && pass "doc without --format: exit 67" || fail "doc without --format: exit $CODE"

[ "$(leftover_packets)" -eq 0 ] && pass "usage refusals leave no packet" || fail "usage refusals left a packet"

# ---------------------------------------------------------------- doc --------

FMT="$ROOT/format.md"
printf '# Format\nRequired sections.\n' > "$FMT"
printf 'scope notes\n' > "$REPO/scope.md"

run "$ROOT/none" doc --doc a.txt --format "$FMT" --extra scope.md --extra scratch/missing.md
if [ "$CODE" -eq 0 ] && [ -f "$OUT" ]; then
    pass "doc: exit 0 and a packet path on stdout"
    grep -q '^## Document under review: a.txt$' "$OUT" && grep -q '^changed$' "$OUT" \
        && pass "doc: carries the document" || fail "doc: document section missing"
    grep -q "^## Format reference: $FMT\$" "$OUT" && grep -q '^Required sections\.$' "$OUT" \
        && pass "doc: carries the format reference" || fail "doc: format section missing"
    grep -q '^## Supporting: scope.md$' "$OUT" && grep -q '^scope notes$' "$OUT" \
        && pass "doc: carries an extra" || fail "doc: extra missing"
    grep -q '^\[absent: scratch/missing.md does not exist in this checkout\]$' "$OUT" \
        && pass "doc: a missing extra is recorded as absent" || fail "doc: missing extra not recorded"
    rm -f "$OUT"
else
    fail "doc: exit $CODE, stderr: $ERR"
fi

# A relative --format resolves against the plugin root, not the repository.
run "$ROOT/none" doc --doc a.txt --format skills/brief/references/brief-format.md
if [ "$CODE" -eq 0 ] && grep -q '^## Format reference: skills/brief/references/brief-format.md$' "$OUT"; then
    pass "doc: a relative --format resolves against the plugin root"
    rm -f "$OUT"
else
    fail "doc: relative --format: exit $CODE, stderr: $ERR"
fi

run "$ROOT/none" doc --doc nope.md --format "$FMT"
[ "$CODE" -eq 64 ] && pass "doc: missing document: exit 64" || fail "doc: missing document: exit $CODE"

run "$ROOT/none" doc --doc a.txt --format no/such-format.md
[ "$CODE" -eq 64 ] && pass "doc: missing format reference: exit 64" || fail "doc: missing format: exit $CODE"

# The document cap: a 70 KB document is cut at 64 KB with a trailer.
awk 'BEGIN { for (i = 0; i < 1000; i++) printf "%070d\n", i }' > "$REPO/big.md"
run "$ROOT/none" doc --doc big.md --format "$FMT"
if [ "$CODE" -eq 0 ] && grep -q '^\[truncated: kept [0-9]* of 71000 bytes' "$OUT"; then
    pass "doc: an over-cap document ends in a truncation trailer"
else
    fail "doc: no truncation trailer (exit $CODE)"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"
rm -f "$REPO/big.md"

# --------------------------------------------------------------- code --------

STORE="$ROOT/store"
mkdir -p "$STORE"
echo "$FIRST_SHA" > "$STORE/impl_base"
printf '## Design excerpt\nThe component does X.\n' > "$STORE/context.md"
BODY="$ROOT/body.md"
printf '## Goal\nDo it.\n\n## Acceptance Criteria\n- [ ] first\n- [ ] second\n\n## Dependencies\nNone.\n' > "$BODY"

GH_BODY="$BODY" run "$STORE" code --session s --issue 12
if [ "$CODE" -eq 0 ] && [ -f "$OUT" ]; then
    pass "code: exit 0 and a packet path on stdout"
    grep -q "^base: $FIRST_SHA (impl_base)\$" "$OUT" \
        && pass "code: the base is impl_base when it is set" || fail "code: base not impl_base"
    grep -q '^- \[ \] second$' "$OUT" && ! grep -q '^Do it\.$' "$OUT" && ! grep -q '^None\.$' "$OUT" \
        && pass "code: only the acceptance-criteria section of the issue" || fail "code: AC section wrong"
    grep -q '^The component does X\.$' "$OUT" \
        && pass "code: carries context.md as design context" || fail "code: design context missing"
    grep -q "^A	c.txt\$" "$OUT" && ! grep -q "	b.txt\$" "$OUT" \
        && pass "code: changed paths cover impl_base..HEAD only" || fail "code: changed paths wrong"
    grep -q '^+more$' "$OUT" && ! grep -q '^+new$' "$OUT" \
        && pass "code: the diff covers impl_base..HEAD only" || fail "code: diff range wrong"
    rm -f "$OUT"
else
    fail "code: exit $CODE, stderr: $ERR"
fi

# No impl_base: the merge-base with local main, and every branch commit shows.
STORE2="$ROOT/store2"
mkdir -p "$STORE2"
run "$STORE2" code --session s --criteria "$BODY"
if [ "$CODE" -eq 0 ]; then
    grep -q "^base: $MAIN_SHA (merge-base with main)\$" "$OUT" \
        && pass "code: no impl_base falls back to the merge-base" || fail "code: fallback base wrong"
    grep -q '	b.txt$' "$OUT" && grep -q '	c.txt$' "$OUT" \
        && pass "code: the fallback range covers the whole branch" || fail "code: fallback range wrong"
    grep -q '^Do it\.$' "$OUT" \
        && pass "code: --criteria carries the file whole" || fail "code: --criteria content missing"
    grep -q '^\[none recorded\]$' "$OUT" \
        && pass "code: no context.md is recorded as none" || fail "code: missing design context not stated"
    rm -f "$OUT"
else
    fail "code: fallback run exit $CODE, stderr: $ERR"
fi

# An impl_base that names no commit falls back with a diagnostic.
STORE3="$ROOT/store3"
mkdir -p "$STORE3"
echo 0123456789abcdef0123456789abcdef01234567 > "$STORE3/impl_base"
run "$STORE3" code --session s
if [ "$CODE" -eq 0 ] && grep -q "^base: $MAIN_SHA (merge-base with main)\$" "$OUT" \
    && printf '%s' "$ERR" | grep -q 'is not a commit here'; then
    pass "code: a stale impl_base falls back with a diagnostic"
else
    fail "code: stale impl_base: exit $CODE, stderr: $ERR"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"

# An issue body with no acceptance-criteria heading is carried whole.
printf 'Just a paragraph.\n' > "$ROOT/plain.md"
GH_BODY="$ROOT/plain.md" run "$STORE" code --session s --issue 12
if [ "$CODE" -eq 0 ] && grep -q '^## Acceptance criteria (issue #12, whole body' "$OUT" \
    && grep -q '^Just a paragraph\.$' "$OUT"; then
    pass "code: a body with no AC heading is carried whole and labelled so"
else
    fail "code: plain body: exit $CODE"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"

# gh failing is a read failure, and leaves no packet.
GH_FAIL=1 GH_BODY="$BODY" run "$STORE" code --session s --issue 12
[ "$CODE" -eq 66 ] && pass "code: gh failure: exit 66" || fail "code: gh failure: exit $CODE"

run "$STORE" code --session s --criteria "$ROOT/nope"
[ "$CODE" -eq 64 ] && pass "code: missing criteria file: exit 64" || fail "code: missing criteria: exit $CODE"

# Outside a repository.
OUT=$( cd "$ROOT/tmp" && KOTO_STORE="$STORE" PATH="$STUBS:$PATH" TMPDIR="$ROOT/tmp" \
    "$BASH_BIN" "$PACKET_SH" code --session s 2>/dev/null )
CODE=$?
[ "$CODE" -eq 64 ] && pass "code: outside a repository: exit 64" || fail "code: outside a repository: exit $CODE"

[ "$(leftover_packets)" -eq 0 ] && pass "failures leave no packet behind" || fail "a failure left a packet behind"

# The diff cap: a 120 KB change is cut, the path list is not.
(
    cd "$REPO" || exit 1
    awk 'BEGIN { for (i = 0; i < 1500; i++) printf "%079d\n", i }' > huge.txt
    git add huge.txt
    git commit -q -m huge
)
run "$STORE" code --session s
if [ "$CODE" -eq 0 ] && grep -q '^\[truncated: kept [0-9]* of [0-9]* bytes' "$OUT" \
    && grep -q '	huge.txt$' "$OUT"; then
    pass "code: an over-cap diff is cut with a trailer and the path list stays whole"
else
    fail "code: diff cap: exit $CODE"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"

# --------------------------------------------------------- spawn sites -------
#
# Every review spawn site carries a Seat commissioning line that names a model
# for each seat, a call budget, and the packet command. SITES is the list of
# those sites; a file under skills/ that gains a commissioning line without
# being added here fails, and so does a listed site that loses its line.
# ALLOWED_MODELS is the models a seat may name without a written exception
# (references/review-seat-commissioning.md, "Why a model is named").

REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
ALLOWED_MODELS="sonnet haiku"
SITES="
skills/work-on/references/phases/phase-4a-scrutiny.md
skills/work-on/references/phases/phase-4b-review.md
skills/work-on/references/phases/phase-4c-qa.md
skills/work-on/references/phases/phase-4-implementation.md
skills/brief/references/phases/phase-4-validate.md
skills/prd/references/phases/phase-4-validate.md
skills/design/references/phases/phase-5-security.md
skills/design/references/phases/phase-6-final-review.md
skills/vision/references/phases/phase-4-validate.md
skills/strategy/references/phases/phase-4-validate.md
skills/roadmap/references/phases/phase-4-validate.md
skills/comp/references/phases/phase-4-validate.md
skills/review-plan/SKILL.md
"

for site in $SITES; do
    file="$REPO_ROOT/$site"
    line=$(grep '^\*\*Seat commissioning\*\*' "$file" 2>/dev/null)
    if [ -z "$line" ]; then
        fail "spawn site $site: no Seat commissioning line"
        continue
    fi
    models=$(printf '%s\n' "$line" | grep -o 'model: "[a-z0-9.-]*"' | sed 's/model: "\(.*\)"/\1/')
    [ -n "$models" ] || fail "spawn site $site: names no model"
    for m in $models; do
        case " $ALLOWED_MODELS " in
            *" $m "*) ;;
            *) fail "spawn site $site: model [$m] is not in ALLOWED_MODELS" ;;
        esac
    done
    printf '%s\n' "$line" | grep -q '[0-9][0-9]*-call budget' \
        || fail "spawn site $site: names no call budget"
    printf '%s\n' "$line" | grep -q 'scripts/review-packet.sh' \
        || fail "spawn site $site: does not give the packet command"
done
pass "spawn sites: every listed site checked"

# grep -vxF rather than a case inside $(...): bash 3.2 misparses the latter.
unlisted=$(cd "$REPO_ROOT" && grep -rl '^\*\*Seat commissioning\*\*' skills \
    | grep -vxF "$(printf '%s\n' $SITES)")
[ -z "$unlisted" ] && pass "spawn sites: no commissioning line outside SITES" \
    || fail "spawn sites: commissioning line in a file not in SITES: $unlisted"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
