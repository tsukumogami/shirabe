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
# The recheck cases also need jq, as the script's recheck kind does, and
# fail without it. The spawn-site cases then check that every
# review spawn site still names a model, a call budget and the packet command,
# and that each /work-on panel gives the recheck packet command too.
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

# ------------------------------------------------------------- recheck -------
#
# A seat panel-scope.sh marked `recheck` gets its own findings and the diff
# since fix_diff_from, read from <panel>_scope.json, and nothing else. The
# scope files here are written the way panel-scope.sh --plan writes them;
# panel-scope_test.sh drives the two scripts together.

HEAD_SHA=$(git -C "$REPO" rev-parse feature)

# scope <dir> <panel> <seat> <decision-json-tail>: writes a scope with one
# recheck seat and one kept seat.
scope() {
    printf '{"panel":"%s","head":"%s","rev":1,"decisions":[{"seat":"other","decision":"keep","reason":"r","judged_at":"%s"},{"seat":"%s","decision":"recheck","reason":"r","findings":[{"summary":"c.txt says more","path":"c.txt","lines":"1"}]%s}]}\n' \
        "$2" "$HEAD_SHA" "$FIRST_SHA" "$3" "$4" > "$1/$2_scope.json"
}

if ! command -v jq >/dev/null 2>&1; then
    # A failure, not a skip: a runner that stopped shipping jq would otherwise
    # go green with the recheck kind untested.
    fail "recheck: jq not on PATH, so no recheck case ran"
else
    RS="$ROOT/rstore"
    mkdir -p "$RS"
    echo "$MAIN_SHA" > "$RS/impl_base"
    printf '## Design excerpt\nThe component does X.\n' > "$RS/context.md"
    scope "$RS" scrutiny intent ",\"fix_diff_from\":\"$FIRST_SHA\""

    run "$RS" recheck --session s --panel scrutiny --seat intent
    if [ "$CODE" -eq 0 ] && [ -f "$OUT" ]; then
        pass "recheck: exit 0 and a packet path on stdout"
        grep -q '^# Review packet: recheck$' "$OUT" && grep -q '^panel: scrutiny$' "$OUT" \
            && grep -q '^seat: intent$' "$OUT" \
            && pass "recheck: the header names the panel and the seat" || fail "recheck: header wrong"
        grep -q "^fix diff from: $FIRST_SHA (fix_diff_from)\$" "$OUT" \
            && pass "recheck: the diff starts at fix_diff_from" || fail "recheck: diff base wrong"
        grep -q '"summary": "c.txt says more"' "$OUT" && grep -q '"lines": "1"' "$OUT" \
            && pass "recheck: carries the seat's findings verbatim" || fail "recheck: findings missing"
        grep -q "^A	c.txt\$" "$OUT" && grep -q '^+more$' "$OUT" \
            && ! grep -q '	b.txt$' "$OUT" && ! grep -q '^+new$' "$OUT" \
            && pass "recheck: the paths and diff cover fix_diff_from..HEAD only" \
            || fail "recheck: diff range wrong"
        ! grep -q '^## Acceptance criteria' "$OUT" && ! grep -q '^## Design context' "$OUT" \
            && ! grep -q '^The component does X\.$' "$OUT" \
            && pass "recheck: no acceptance criteria or design context" \
            || fail "recheck: carries sections a re-check does not read"
        RECHECK_BYTES=$(wc -c < "$OUT" | tr -d ' ')
        rm -f "$OUT"
        GH_BODY="$BODY" run "$RS" code --session s --issue 12
        CODE_BYTES=$(wc -c < "$OUT" | tr -d ' ')
        rm -f "$OUT"
        [ "$RECHECK_BYTES" -lt "$CODE_BYTES" ] \
            && pass "recheck: smaller than the code packet for the same session ($RECHECK_BYTES < $CODE_BYTES bytes)" \
            || fail "recheck: $RECHECK_BYTES bytes, the code packet $CODE_BYTES"
    else
        fail "recheck: exit $CODE, stderr: $ERR"
    fi

    # The light panel's one seat: its retry loop marks it recheck too.
    scope "$RS" light reviewer ",\"fix_diff_from\":\"$FIRST_SHA\""
    run "$RS" recheck --session s --panel light --seat reviewer
    if [ "$CODE" -eq 0 ] && grep -q '^panel: light$' "$OUT" && grep -q '^+more$' "$OUT"; then
        pass "recheck: the light panel's reviewer seat"
    else
        fail "recheck: light reviewer: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # Nothing committed since the seat blocked: the packet is still written,
    # and says the diff is empty.
    scope "$RS" scrutiny intent ",\"fix_diff_from\":\"$HEAD_SHA\""
    run "$RS" recheck --session s --panel scrutiny --seat intent
    if [ "$CODE" -eq 0 ] && grep -q '^changed paths: 0$' "$OUT" \
        && grep -q "^\[no changes between $HEAD_SHA and HEAD\]\$" "$OUT" \
        && grep -q "^\[empty: no commit since $HEAD_SHA changes anything\]\$" "$OUT" \
        && grep -q '"summary": "c.txt says more"' "$OUT"; then
        pass "recheck: an empty fix diff writes a packet that says so, findings included"
    else
        fail "recheck: empty fix diff: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # No fix_diff_from: the diff falls back to the code packet's base, here
    # impl_base, and the header and stderr say why.
    scope "$RS" scrutiny intent ""
    run "$RS" recheck --session s --panel scrutiny --seat intent
    if [ "$CODE" -eq 0 ] \
        && grep -q "^fix diff from: $MAIN_SHA (fallback: the scope has no fix_diff_from; impl_base)\$" "$OUT" \
        && grep -q '	b.txt$' "$OUT" && grep -q '	c.txt$' "$OUT" \
        && printf '%s' "$ERR" | grep -q 'falls back to the code packet'; then
        pass "recheck: a missing fix_diff_from falls back to impl_base, labelled"
    else
        fail "recheck: missing fix_diff_from: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # ... and with no impl_base either, to the merge-base.
    RS2="$ROOT/rstore2"
    mkdir -p "$RS2"
    scope "$RS2" scrutiny intent ',"fix_diff_from":null'
    run "$RS2" recheck --session s --panel scrutiny --seat intent
    if [ "$CODE" -eq 0 ] \
        && grep -q "^fix diff from: $MAIN_SHA (fallback: the scope has no fix_diff_from; merge-base with main)\$" "$OUT"; then
        pass "recheck: a null fix_diff_from with no impl_base falls back to the merge-base"
    else
        fail "recheck: null fix_diff_from: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    scope "$RS" scrutiny intent ',"fix_diff_from":"0123456789abcdef0123456789abcdef01234567"'
    run "$RS" recheck --session s --panel scrutiny --seat intent
    [ "$CODE" -eq 0 ] && grep -q '^fix diff from: .*that is not a commit here; impl_base)$' "$OUT" \
        && pass "recheck: a fix_diff_from that names no commit falls back" \
        || fail "recheck: unknown fix_diff_from: exit $CODE, stderr: $ERR"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    scope "$RS" scrutiny intent ',"fix_diff_from":"--output=x"'
    run "$RS" recheck --session s --panel scrutiny --seat intent
    [ "$CODE" -eq 0 ] && grep -q '^fix diff from: .*that is not a commit id; impl_base)$' "$OUT" \
        && [ ! -e "$REPO/x" ] \
        && pass "recheck: a fix_diff_from that is not a commit id never reaches git" \
        || fail "recheck: non-id fix_diff_from: exit $CODE, stderr: $ERR"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # A commit off to the side of HEAD can't bound a fix on it.
    SIDE_SHA=$(cd "$REPO" && git checkout -q -b side main && echo side > s.txt && git add s.txt \
        && git commit -q -m side && git rev-parse HEAD && git checkout -q feature)
    scope "$RS" scrutiny intent ",\"fix_diff_from\":\"$SIDE_SHA\""
    run "$RS" recheck --session s --panel scrutiny --seat intent
    [ "$CODE" -eq 0 ] && grep -q '^fix diff from: .*that is not an ancestor of HEAD; impl_base)$' "$OUT" \
        && ! grep -q 's.txt' "$OUT" \
        && pass "recheck: a fix_diff_from off HEAD's history falls back" \
        || fail "recheck: non-ancestor fix_diff_from: exit $CODE, stderr: $ERR"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # Refusals: a seat that isn't marked recheck gets the code packet, so
    # this kind refuses it rather than build a narrower one.
    scope "$RS" scrutiny intent ",\"fix_diff_from\":\"$FIRST_SHA\""
    run "$RS" recheck --session s --panel scrutiny --seat other
    [ "$CODE" -eq 64 ] && printf '%s' "$ERR" | grep -q 'not recheck: commission it with the code packet' \
        && pass "recheck: a kept seat: exit 64" || fail "recheck: kept seat: exit $CODE"
    run "$RS" recheck --session s --panel scrutiny --seat completeness
    [ "$CODE" -eq 64 ] && pass "recheck: a seat not in the scope: exit 64" || fail "recheck: absent seat: exit $CODE"
    run "$RS" recheck --session s --panel review --seat pragmatic
    [ "$CODE" -eq 64 ] && pass "recheck: no scope for the panel: exit 64" || fail "recheck: no scope: exit $CODE"
    printf 'not json\n' > "$RS/qa_scope.json"
    run "$RS" recheck --session s --panel qa --seat tester
    [ "$CODE" -eq 64 ] && pass "recheck: an unreadable scope: exit 64" || fail "recheck: unreadable scope: exit $CODE"

    run "$RS" recheck --session s --seat intent
    [ "$CODE" -eq 67 ] && pass "recheck: no --panel: exit 67" || fail "recheck: no --panel: exit $CODE"
    run "$RS" recheck --session s --panel jury --seat intent
    [ "$CODE" -eq 67 ] && pass "recheck: unknown panel: exit 67" || fail "recheck: unknown panel: exit $CODE"
    run "$RS" recheck --session s --panel scrutiny --seat 'x;y'
    [ "$CODE" -eq 67 ] && pass "recheck: a seat that is not a name: exit 67" || fail "recheck: bad seat: exit $CODE"
    run "$RS" recheck --session s --panel scrutiny --seat intent --issue 12
    [ "$CODE" -eq 67 ] && pass "recheck: a code flag: exit 67" || fail "recheck: code flag: exit $CODE"

    [ "$(leftover_packets)" -eq 0 ] && pass "recheck: refusals leave no packet" || fail "recheck: a refusal left a packet"
fi

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
skills/work-on/references/phases/phase-4d-light.md
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

# Each /work-on panel can mark a seat recheck, so each panel's commissioning
# line also gives the recheck packet command, under the panel name
# panel-scope.sh uses for that panel.
RECHECK_SITES="
phase-4a-scrutiny.md:scrutiny
phase-4b-review.md:review
phase-4c-qa.md:qa
phase-4d-light.md:light
"
for entry in $RECHECK_SITES; do
    site="skills/work-on/references/phases/${entry%%:*}"
    line=$(grep '^\*\*Seat commissioning\*\*' "$REPO_ROOT/$site" 2>/dev/null)
    printf '%s\n' "$line" | grep -q "scripts/review-packet.sh\" recheck --session <WF> --panel ${entry#*:} --seat " \
        && pass "spawn site $site: gives the recheck packet for panel ${entry#*:}" \
        || fail "spawn site $site: no recheck packet command for panel ${entry#*:}"
done

# grep -vxF rather than a case inside $(...): bash 3.2 misparses the latter.
unlisted=$(cd "$REPO_ROOT" && grep -rl '^\*\*Seat commissioning\*\*' skills \
    | grep -vxF "$(printf '%s\n' $SITES)")
[ -z "$unlisted" ] && pass "spawn sites: no commissioning line outside SITES" \
    || fail "spawn sites: commissioning line in a file not in SITES: $unlisted"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
