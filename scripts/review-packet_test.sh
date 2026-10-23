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
# pin the packet's sections (the code packet's `## Test changes` lists added
# and edited tests apart, with the edited hunks, from the stored rules copy and
# a fix's red record, and says none without a test file), the base order
# (impl_base, then the merge-base),
# the caps and their trailers, that a failure leaves no packet behind, that a
# plan-outline child's session never reaches `gh issue view`, and that
# --issue reads its issue from the repository --issue-repo names and refuses
# to run without it.
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

ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$ROOT"' EXIT

# Stubs. KOTO_STORE is a directory with one file per context key.
STUBS="$ROOT/stubs"
mkdir -p "$STUBS"
# `session dir` answers from KOTO_SESSIONS, where a case writes a session's
# state log as koto lays it out. gh appends each call to GH_LOG when it is set.
cat > "$STUBS/koto" <<'EOF'
#!/bin/sh
if [ "$1" = session ] && [ "$2" = dir ]; then
    echo "${KOTO_SESSIONS:-/nonexistent}/$3"
    exit 0
fi
[ "$1" = context ] || exit 2
case "$2" in
    exists) [ -f "$KOTO_STORE/$4" ] ;;
    get)    [ -f "$KOTO_STORE/$4" ] && cat "$KOTO_STORE/$4" ;;
    *)      exit 2 ;;
esac
EOF
cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
[ -z "${GH_LOG:-}" ] || echo "$*" >> "$GH_LOG"
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

GH_BODY="$BODY" run "$STORE" code --session s --issue 12 --issue-repo ""
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
    && grep -q 'is not a commit here' <<<"$ERR"; then
    pass "code: a stale impl_base falls back with a diagnostic"
else
    fail "code: stale impl_base: exit $CODE, stderr: $ERR"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"

# An issue body with no acceptance-criteria heading is carried whole.
printf 'Just a paragraph.\n' > "$ROOT/plain.md"
GH_BODY="$ROOT/plain.md" run "$STORE" code --session s --issue 12 --issue-repo ""
if [ "$CODE" -eq 0 ] && grep -q '^## Acceptance criteria (issue #12, whole body' "$OUT" \
    && grep -q '^Just a paragraph\.$' "$OUT"; then
    pass "code: a body with no AC heading is carried whole and labelled so"
else
    fail "code: plain body: exit $CODE"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"

# gh failing is a read failure, and leaves no packet.
GH_FAIL=1 GH_BODY="$BODY" run "$STORE" code --session s --issue 12 --issue-repo ""
[ "$CODE" -eq 66 ] && pass "code: gh failure: exit 66" || fail "code: gh failure: exit $CODE"

# A plan-outline child's issue number names an item in its PLAN, not a GitHub
# issue: --issue is refused before gh is called, whatever the repository has
# under that number. The session's ISSUE_SOURCE comes from its koto state log.
# state_log <session> <issue-source>: writes the session's log as koto does,
# a header line, then workflow_initialized with the session's variables.
state_log() {
    mkdir -p "$ROOT/sessions/$1"
    printf '{"schema_version":1,"workflow":"%s"}\n{"seq":1,"type":"workflow_initialized","payload":{"template_path":"t","variables":{"ISSUE_NUMBER":"1","ISSUE_SOURCE":"%s"}}}\n{"seq":2,"type":"transitioned","payload":{"from":null,"to":"entry"}}\n' \
        "$1" "$2" > "$ROOT/sessions/$1/koto-$1.state.jsonl"
}
if ! command -v jq >/dev/null 2>&1; then
    fail "plan-outline: jq not on PATH, so no plan-outline case ran"
else
    state_log outline-child plan_outline
    state_log github-child github
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session outline-child --issue 1 --issue-repo ""
    if [ "$CODE" -eq 67 ] && [ ! -s "$ROOT/gh.log" ] \
        && grep -q 'plan-outline child' <<<"$ERR" \
        && grep -q -- '--criteria <file>' <<<"$ERR"; then
        pass "code: --issue for a plan-outline child is refused (exit 67) with no gh call"
    else
        fail "code: plan-outline --issue: exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
    fi
    KOTO_SESSIONS="$ROOT/sessions" run "$STORE" code --session outline-child --criteria "$BODY"
    if [ "$CODE" -eq 0 ] && grep -q '^- \[ \] second$' "$OUT"; then
        pass "code: a plan-outline child's --criteria packet is built as usual"
    else
        fail "code: plan-outline --criteria: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session github-child --issue 12 --issue-repo ""
    if [ "$CODE" -eq 0 ] && grep -qx 'issue view 12 --json body -q .body' "$ROOT/gh.log" \
        && grep -q '^- \[ \] second$' "$OUT"; then
        pass "code: a github-sourced plan child still reads its issue"
    else
        fail "code: github child --issue: exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    # A session with no readable log (a lookup that finds nothing) keeps
    # reading its issue: an issue-backed run must not lose its packet.
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session no-log --issue 12 --issue-repo ""
    if [ "$CODE" -eq 0 ] && grep -qx 'issue view 12 --json body -q .body' "$ROOT/gh.log"; then
        pass "code: a session with no readable log still reads its issue"
    else
        fail "code: no-log --issue: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    # A log whose header this reader doesn't know reads its issue too, but
    # says on stderr that the check went quiet.
    state_log new-format plan_outline
    sed 's/"schema_version":1/"schema_version":2/' "$ROOT/sessions/new-format/koto-new-format.state.jsonl" \
        > "$ROOT/sessions/new-format/log.tmp"
    mv "$ROOT/sessions/new-format/log.tmp" "$ROOT/sessions/new-format/koto-new-format.state.jsonl"
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session new-format --issue 12 --issue-repo ""
    if [ "$CODE" -eq 0 ] && grep -qx 'issue view 12 --json body -q .body' "$ROOT/gh.log" \
        && grep -q 'schema_version 2; this reader knows 1' <<<"$ERR"; then
        pass "code: an unknown log schema reads its issue and warns that the check is off"
    else
        fail "code: unknown schema: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # An issue in another repository: --issue-repo names it, the issue is
    # read from there, and the packet names it owner/repo#N.
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session github-child --issue 12 --issue-repo acme/tracker
    if [ "$CODE" -eq 0 ] && grep -qx 'issue view 12 --repo acme/tracker --json body -q .body' "$ROOT/gh.log" \
        && grep -q '^## Acceptance criteria (issue acme/tracker#12, acceptance-criteria section)$' "$OUT" \
        && grep -q '^- \[ \] second$' "$OUT"; then
        pass "code: an issue in another repository is read from there and named owner/repo#N"
    else
        fail "code: cross-repo --issue: exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    # The flag is the only source: a session log that still carries an
    # ISSUE_REPO is not read for it, so an empty --issue-repo reads this
    # repository's issue, with the same call a same-repository run makes.
    # repo_log <session> <issue-repo> plants that decoy log; the script must
    # ignore it. (no-log, below, is a session with no log at all.)
    repo_log() {
        mkdir -p "$ROOT/sessions/$1"
        printf '{"schema_version":1,"workflow":"%s"}\n{"seq":1,"type":"workflow_initialized","payload":{"template_path":"t","variables":{"ISSUE_NUMBER":"12","ISSUE_REPO":"%s"}}}\n' \
            "$1" "$2" > "$ROOT/sessions/$1/koto-$1.state.jsonl"
    }
    repo_log xrepo acme/tracker
    rm -f "$ROOT/gh.log"
    GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
        run "$STORE" code --session xrepo --issue 12 --issue-repo ""
    if [ "$CODE" -eq 0 ] && grep -qx 'issue view 12 --json body -q .body' "$ROOT/gh.log"; then
        pass "code: an empty --issue-repo reads this repository's issue, whatever the session's log says"
    else
        fail "code: empty --issue-repo: exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    # Without --issue-repo, --issue never guesses this repository: exit 67
    # before any gh call, with a session log or without one.
    for sess in xrepo no-log; do
        rm -f "$ROOT/gh.log"
        GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
            run "$STORE" code --session "$sess" --issue 12
        if [ "$CODE" -eq 67 ] && [ ! -s "$ROOT/gh.log" ] && grep -q -- '--issue needs --issue-repo' <<<"$ERR"; then
            pass "code: --issue without --issue-repo exits 67 with no gh call ($sess)"
        else
            fail "code: --issue without --issue-repo ($sess): exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
        fi
    done
    # A malformed --issue-repo never reaches gh.
    for bad in 'acme/tracker --web' acme 'acme/tr;cker' 'acme/tracker
evil/x'; do
        rm -f "$ROOT/gh.log"
        GH_LOG="$ROOT/gh.log" KOTO_SESSIONS="$ROOT/sessions" GH_BODY="$BODY" \
            run "$STORE" code --session github-child --issue 12 --issue-repo "$bad"
        if [ "$CODE" -eq 67 ] && [ ! -s "$ROOT/gh.log" ] && grep -q 'not owner/repo' <<<"$ERR"; then
            pass "code: a malformed --issue-repo [$bad] exits 67 with no gh call"
        else
            fail "code: malformed --issue-repo [$bad]: exit $CODE, gh calls: $(cat "$ROOT/gh.log" 2>/dev/null), stderr: $ERR"
        fi
    done
    # --issue-repo belongs to --issue; --criteria takes none.
    KOTO_SESSIONS="$ROOT/sessions" run "$STORE" code --session github-child --criteria "$BODY" --issue-repo acme/tracker
    [ "$CODE" -eq 67 ] && pass "code: --issue-repo with --criteria exits 67" \
        || fail "code: --issue-repo with --criteria: exit $CODE, stderr: $ERR"
    run "$STORE" code --session s --issue 12 --issue-repo
    [ "$CODE" -eq 67 ] && pass "code: a trailing --issue-repo with no value exits 67" \
        || fail "code: trailing --issue-repo: exit $CODE"
fi

run "$STORE" code --session s --criteria "$ROOT/nope"
[ "$CODE" -eq 64 ] && pass "code: missing criteria file: exit 64" || fail "code: missing criteria: exit $CODE"

# --- the test changes section ---

# A change touching no test file: the section is there, between the changed
# paths and the diff, and says none.
run "$STORE" code --session s
if [ "$CODE" -eq 0 ]; then
    awk '/^## Changed paths$/ { c = NR } /^## Test changes$/ { t = NR } /^## Diff$/ { d = NR }
         END { exit !(c && t && d && c < t && t < d) }' "$OUT" \
        && pass "code: ## Test changes sits between the changed paths and the diff" \
        || fail "code: the test changes section is missing or out of place"
    [ "$(awk '/^## Test changes$/ { getline; getline; print; exit }' "$OUT")" = none ] \
        && pass "code: a change with no test file prints none" || fail "code: no-test change: section is not none"
    rm -f "$OUT"
else
    fail "code: no-test run exit $CODE, stderr: $ERR"
fi

# A change that edits one test, adds another and only appends to a third,
# from the same base.
TREPO="$ROOT/trepo"
mkdir -p "$TREPO"
(
    cd "$TREPO" || exit 1
    git init -q -b main
    git config user.email t@example.com
    git config user.name t
    git config commit.gpgsign false
    mkdir -p tests src
    seq 1 10 > tests/a_test.sh
    seq 1 4 > tests/old_test.sh
    echo one > src/x.sh
    git add -A && git commit -q -m base
    git checkout -q -b feature
    sed -i.bak '3d' tests/a_test.sh && rm -f tests/a_test.sh.bak
    printf '5\n6\n' >> tests/old_test.sh
    seq 1 3 > tests/b_test.sh
    echo two >> src/x.sh
    git add -A && git commit -q -m change
) || { echo "FAIL: could not build the test-change fixture" >&2; exit 1; }
TSTORE="$ROOT/tstore"
mkdir -p "$TSTORE"
git -C "$TREPO" rev-parse main > "$TSTORE/impl_base"
SAVED_REPO="$REPO"
REPO="$TREPO"
run "$TSTORE" code --session s
REPO="$SAVED_REPO"
if [ "$CODE" -eq 0 ]; then
    awk '/^## Test changes$/ { on = 1; next } on && /^## Diff$/ { exit } on' "$OUT" > "$ROOT/tsec"
    grep -q '^- tests/b_test.sh$' "$ROOT/tsec" && grep -q '^- tests/old_test.sh$' "$ROOT/tsec" \
        && pass "code: a new test and one that only gained lines are listed as added" \
        || fail "code: added tests not listed: $(cat "$ROOT/tsec")"
    [ "$(awk '/^Edited/ { on = 1 } on && /^- / { print; exit }' "$ROOT/tsec")" = "- tests/a_test.sh" ] \
        && pass "code: the test that lost a line is listed as edited" \
        || fail "code: edited list wrong: $(cat "$ROOT/tsec")"
    awk '/^Added/ { on = 1; next } /^Edited/ { on = 0 } on' "$ROOT/tsec" | grep -q 'a_test.sh' \
        && fail "code: the edited test is also listed as added" || pass "code: the edited test is not listed as added"
    grep -q '^### Edited: tests/a_test.sh$' "$ROOT/tsec" && grep -q '^-3$' "$ROOT/tsec" \
        && pass "code: the edited test's hunk is in the section" || fail "code: edited hunk missing: $(cat "$ROOT/tsec")"
    grep -q '^### Edited: tests/old_test.sh$' "$ROOT/tsec" \
        && fail "code: an added-to test got an edited hunk" || pass "code: an added-to test gets no hunk of its own"
    grep -q 'src/x.sh' "$ROOT/tsec" && fail "code: a non-test file is in the test section" \
        || pass "code: non-test files stay out of the test section"
    rm -f "$OUT"
else
    fail "code: test-change run exit $CODE, stderr: $ERR"
fi

# The session's stored rules copy decides the test class: one with no test
# class lists nothing.
printf 'class\tdocs\t*.md\n' > "$TSTORE/review_level_rules.tsv"
REPO="$TREPO"
run "$TSTORE" code --session s
REPO="$SAVED_REPO"
if [ "$CODE" -eq 0 ] && [ "$(awk '/^## Test changes$/ { getline; getline; print; exit }' "$OUT")" = none ]; then
    pass "code: the stored rules copy, not the shipped file, decides what a test is"
else
    fail "code: stored rules copy: exit $CODE"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"
rm -f "$TSTORE/review_level_rules.tsv"

# A fix's reproducing test changed after its red is edited, though it only
# gained lines.
RB=$(git -C "$TREPO" rev-parse main:tests/old_test.sh)
printf '{"red":{"tests":[{"path":"tests/old_test.sh","blob":"%s"}],"harness":[]}}\n' "$RB" > "$TSTORE/red_first.json"
REPO="$TREPO"
run "$TSTORE" code --session s
REPO="$SAVED_REPO"
if [ "$CODE" -eq 0 ] && grep -q '^### Edited: tests/old_test.sh$' "$OUT"; then
    pass "code: a reproducing test changed after the red is edited"
else
    fail "code: red record: exit $CODE, stderr: $ERR"
fi
[ "$CODE" -eq 0 ] && rm -f "$OUT"
rm -f "$TSTORE/red_first.json"

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
        GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo ""
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
        && grep -q 'falls back to the code packet' <<<"$ERR"; then
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

    # The re-verifier, the one run a retry round plans: its findings by id
    # and, with a fix-diff review, every panel's criteria and the review
    # range. Written the way panel-scope.sh --plan writes the decision.
    # reverifier_scope <fix_review> <review_from>
    reverifier_scope() {
        printf '{"panel":"scrutiny","head":"%s","rev":2,"decisions":[{"seat":"completeness","decision":"keep","reason":"r"},{"seat":"reverifier","decision":"recheck","run":"scrutiny-r2-reverifier","reason":"r","findings":[{"id":"0123456789abcdef","severity":"blocking","summary":"c.txt says more","raiser":"intent","status":"open","path":"c.txt","lines":"1","due":"open, and the fix touched its location"}],"fix_diff_from":"%s","fix_review":%s,"review_from":"%s"}]}\n' \
            "$HEAD_SHA" "$MAIN_SHA" "$1" "$2" > "$RS/scrutiny_scope.json"
    }
    # section_of <heading prefix> <packet>: the lines of one section.
    section_of() {
        awk -v h="## $1" 'index($0, h) == 1 { on = 1; next } on && /^## / { exit } on { print }' "$2"
    }
    reverifier_scope true "$FIRST_SHA"
    run "$RS" recheck --session s --panel scrutiny --seat reverifier
    if [ "$CODE" -eq 0 ] && [ -f "$OUT" ]; then
        grep -q '^seat: reverifier$' "$OUT" && grep -q '^fix review: yes$' "$OUT" \
            && grep -q "^review from: $FIRST_SHA (review_from)\$" "$OUT" \
            && grep -q "^fix diff from: $MAIN_SHA (fix_diff_from)\$" "$OUT" \
            && pass "recheck: the re-verifier's header names the fix-diff review and where its range starts" \
            || fail "recheck: re-verifier header: $(sed -n 1,9p "$OUT")"
        FIND=$(section_of "Findings to re-verify, by id" "$OUT")
        grep -q '"id": "0123456789abcdef"' <<<"$FIND" \
            && grep -q '"summary": "c.txt says more"' <<<"$FIND" \
            && grep -q '"raiser": "intent"' <<<"$FIND" \
            && grep -q '"path": "c.txt"' <<<"$FIND" \
            && grep -q '"lines": "1"' <<<"$FIND" \
            && pass "recheck: each due finding is listed by id, with its text, location and raiser" \
            || fail "recheck: re-verifier findings: $FIND"
        CRIT=$(section_of "Every panel's blocking criteria" "$OUT")
        grep -q '^### Scrutiny$' <<<"$CRIT" && grep -q '^- \*\*Completeness reviewer\*\*' <<<"$CRIT" \
            && grep -q '^### Review$' <<<"$CRIT" && grep -q '^- \*\*Maintainer reviewer\*\*' <<<"$CRIT" \
            && grep -q '^### QA$' <<<"$CRIT" && grep -q 'acceptance criteria' <<<"$CRIT" \
            && pass "recheck: a fix-diff review carries the scrutiny, review and QA criteria, from the phase files" \
            || fail "recheck: fix-review criteria: $CRIT"
        RANGE=$(section_of "Changed paths (fix-diff review" "$OUT")
        grep -q '^A	c.txt$' <<<"$RANGE" && ! grep -q 'b.txt' <<<"$RANGE" \
            && pass "recheck: the review range's paths run from review_from" \
            || fail "recheck: review range: $RANGE"
        rm -f "$OUT"
    else
        fail "recheck: the re-verifier: exit $CODE, stderr: $ERR"
    fi

    reverifier_scope false "$FIRST_SHA"
    run "$RS" recheck --session s --panel scrutiny --seat reverifier
    if [ "$CODE" -eq 0 ] && grep -q '^fix review: no$' "$OUT" && ! grep -q '^review from:' "$OUT" \
        && ! grep -q "^## Every panel's blocking criteria" "$OUT" && ! grep -q '^## Changed paths (fix-diff review' "$OUT" \
        && grep -q '"id": "0123456789abcdef"' "$OUT"; then
        pass "recheck: without a fix-diff review, no criteria and no review range"
    else
        fail "recheck: re-verifier with no fix review: exit $CODE, stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    reverifier_scope true "--output=y"
    run "$RS" recheck --session s --panel scrutiny --seat reverifier
    [ "$CODE" -eq 0 ] && grep -q "^review from: $MAIN_SHA (fallback: the scope has a review_from \[--output=y\] that is not a commit id; impl_base)\$" "$OUT" \
        && [ ! -e "$REPO/y" ] \
        && pass "recheck: a bad review_from falls back to the code packet's base, and says so" \
        || fail "recheck: bad review_from: exit $CODE, stderr: $ERR"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"

    # A full round's seat answers its own unclosed findings by id: its code
    # packet lists them.
    printf '{"panel":"scrutiny","head":"%s","rev":2,"full":true,"decisions":[{"seat":"completeness","decision":"full","run":"scrutiny-r2-completeness","reason":"r","findings":[{"id":"fedcba9876543210","severity":"blocking","summary":"b.txt is wrong","raiser":"completeness","status":"open","path":"b.txt"}]},{"seat":"intent","decision":"full","run":"scrutiny-r2-intent","reason":"r","findings":[]}]}\n' \
        "$HEAD_SHA" > "$RS/scrutiny_scope.json"
    GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo "" --panel scrutiny --seat completeness
    OWN=$( [ "$CODE" -eq 0 ] && section_of "Your unclosed findings, by id" "$OUT")
    if grep -q '"id": "fedcba9876543210"' <<<"$OWN" && grep -q '"summary": "b.txt is wrong"' <<<"$OWN" \
        && grep -q '^## Diff$' "$OUT"; then
        pass "code: a full-round seat's packet lists its unclosed findings by id"
    else
        fail "code: own findings: exit $CODE, section [$OWN], stderr: $ERR"
    fi
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo "" --panel scrutiny --seat intent
    [ "$CODE" -eq 0 ] && [ "$(section_of "Your unclosed findings, by id" "$OUT" | grep -c .)" = 1 ] \
        && section_of "Your unclosed findings, by id" "$OUT" | grep -q '^\[none\]$' \
        && pass "code: a seat with no unclosed findings is told it has none" \
        || fail "code: no own findings: exit $CODE, stderr: $ERR"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo ""
    [ "$CODE" -eq 0 ] && ! grep -q '^## Your unclosed findings' "$OUT" \
        && pass "code: without --seat, no findings section" || fail "code: no --seat: exit $CODE"
    [ "$CODE" -eq 0 ] && rm -f "$OUT"
    run "$RS" code --session s --panel scrutiny
    [ "$CODE" -eq 67 ] && pass "code: --panel without --seat: exit 67" || fail "code: --panel alone: exit $CODE"
    GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo "" --panel scrutiny --seat justification
    [ "$CODE" -eq 64 ] && pass "code: a seat the scope has no decision for: exit 64" || fail "code: absent seat: exit $CODE"
    GH_BODY="$BODY" run "$RS" code --session s --issue 12 --issue-repo "" --panel review --seat pragmatic
    [ "$CODE" -eq 64 ] && pass "code: --seat with no scope for the panel: exit 64" || fail "code: no scope: exit $CODE"

    # The re-check prompt asks for answers by id and no longer says a passing
    # re-check records the seat as passed.
    PROMPT=$(awk '/^## The re-check prompt/ { on = 1; next } on && /^## / { exit } on { print }' \
        "$SCRIPT_DIR/../references/review-seat-commissioning.md")
    grep -q 'by id' <<<"$PROMPT" && grep -q '`holds`' <<<"$PROMPT" \
        && grep -q '`reverified`' <<<"$PROMPT" && grep -q 'reason' <<<"$PROMPT" \
        && ! grep -q 'records this seat as passed' <<<"$PROMPT" \
        && pass "the re-check prompt asks for holds or reverified by id, with a reason" \
        || fail "the re-check prompt: $PROMPT"

    # Refusals: a seat that isn't marked recheck gets the code packet, so
    # this kind refuses it rather than build a narrower one.
    scope "$RS" scrutiny intent ",\"fix_diff_from\":\"$FIRST_SHA\""
    run "$RS" recheck --session s --panel scrutiny --seat other
    [ "$CODE" -eq 64 ] && grep -q 'not recheck: commission it with the code packet' <<<"$ERR" \
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
    grep -q '[0-9][0-9]*-call budget' <<<"$line" \
        || fail "spawn site $site: names no call budget"
    grep -q 'scripts/review-packet.sh' <<<"$line" \
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
    grep -q "scripts/review-packet.sh\" recheck --session <WF> --panel ${entry#*:} --seat " <<<"$line" \
        && pass "spawn site $site: gives the recheck packet for panel ${entry#*:}" \
        || fail "spawn site $site: no recheck packet command for panel ${entry#*:}"
done

# Each /work-on code-packet site says that a run with no GitHub issue passes
# --criteria rather than --issue: a plan-outline child that follows a bare
# `--issue <N>` reads whatever the repository has under its PLAN item number.
CODE_SITES="
phase-4a-scrutiny.md
phase-4b-review.md
phase-4c-qa.md
phase-4d-light.md
phase-4-implementation.md
"
for entry in $CODE_SITES; do
    site="skills/work-on/references/phases/$entry"
    line=$(grep '^\*\*Seat commissioning\*\*' "$REPO_ROOT/$site" 2>/dev/null)
    grep -q -- '`--criteria <file>` in place of `--issue <N>`' <<<"$line" \
        && grep -q 'plan-outline child' <<<"$line" \
        && pass "spawn site $site: gives --criteria for a plan-outline child" \
        || fail "spawn site $site: no --criteria form for a run with no GitHub issue"
    # --issue goes with the repository the directive gives, never without it.
    grep -q -- 'code --session <WF> --issue <N> --issue-repo "<ISSUE_REPO>"' <<<"$line" \
        && pass "spawn site $site: --issue carries --issue-repo" \
        || fail "spawn site $site: the code packet's --issue has no --issue-repo"
done

# The phase files say `<ISSUE_REPO>`; the value comes from the state's
# directive in the work-on template, so each state that builds a code packet
# or runs extract-context.sh must give it. A directive that dropped it would
# leave the agent a command the scripts refuse.
TEMPLATE="$REPO_ROOT/skills/work-on/koto-templates/work-on.md"
directive() { # directive <state>: the template's `## <state>` section
    awk -v h="## $1" '$0 == h { on = 1; next } on && /^## / { exit } on' "$TEMPLATE"
}
for state in implementation scrutiny review qa_validation light_review; do
    grep -qF -- 'review-packet.sh code --issue` packet takes `--issue-repo "{{ISSUE_REPO}}"`' <<<"$(directive "$state")" \
        && pass "directive $state: gives --issue-repo \"{{ISSUE_REPO}}\" for the code packet" \
        || fail "directive $state: no --issue-repo \"{{ISSUE_REPO}}\" for the code packet"
done
grep -qF -- 'extract-context.sh" {{ISSUE_NUMBER}} --session {{SESSION_NAME}} --issue-repo "{{ISSUE_REPO}}"' <<<"$(directive context_injection)" \
    && pass "directive context_injection: gives the extract-context.sh command with --issue-repo" \
    || fail "directive context_injection: no extract-context.sh command with --issue-repo"

# grep -vxF rather than a case inside $(...): bash 3.2 misparses the latter.
unlisted=$(cd "$REPO_ROOT" && grep -rl '^\*\*Seat commissioning\*\*' skills \
    | grep -vxF "$(printf '%s\n' $SITES)")
[ -z "$unlisted" ] && pass "spawn sites: no commissioning line outside SITES" \
    || fail "spawn sites: commissioning line in a file not in SITES: $unlisted"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
