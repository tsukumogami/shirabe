#!/usr/bin/env bash
set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

# Tests for rule-registry.sh.
#
# Most cases run against scratch plugin roots built here: a copy of the script
# under <root>/scripts/, a small synthetic registry, and the files its anchors
# point at. The root is a git repository for the checkout cases and a plain
# directory for the installed-copy cases, so the revision forms are each
# exercised on purpose rather than inherited from shirabe's own checkout. The
# last group reads the real registry and checks its shape.
#
# Needs bash, git, jq, awk and sed. No network.
#
# Usage:
#   bash scripts/rule-registry_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/rule-registry.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 - $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/rule-registry-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */rule-registry-test.*) rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

# Commits in the scratch repositories must not depend on the host's identity.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

REGISTRY_JSON='{"schema":"shirabe-rule-registry/v1","rules":[
 {"id":"t/multi","status":"active","summary":"Multi-line rule","withhold":"eligible","text":{"path":"references/r.md","first":"RULE-MULTI starts","last":"RULE-MULTI ends"}},
 {"id":"t/single","status":"active","summary":"Single-line rule","withhold":"never","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}},
 {"id":"t/retired","status":"retired","summary":"Gone","text":{"path":"references/gone.md","first":"nothing"}},
 {"id":"t/dup","status":"active","summary":"Dup","text":{"path":"references/r.md","first":"DUP"}},
 {"id":"t/backwards","status":"active","summary":"Backwards","text":{"path":"references/r.md","first":"RULE-MULTI ends","last":"RULE-MULTI starts"}},
 {"id":"t/abs","status":"active","summary":"Abs","text":{"path":"/etc/passwd","first":"root"}},
 {"id":"t/dotdot","status":"active","summary":"Dotdot","text":{"path":"references/../references/r.md","first":"RULE-SINGLE only line"}},
 {"id":"t/dash","status":"active","summary":"Dash","text":{"path":"-r.md","first":"x"}},
 {"id":"t/link","status":"active","summary":"Link","text":{"path":"references/link.md","first":"RULE-SINGLE only line"}},
 {"id":"t/long","status":"active","summary":"Long","text":{"path":"references/long.md","first":"LONG-START","last":"LONG-END"}},
 {"id":"t/docs","status":"active","summary":"Docs","text":{"path":"docs/notes.md","first":"DOCS-RULE"}},
 {"id":"t/marker","status":"active","summary":"Marker","text":{"path":"references/marker.md","first":"MARKER-START","last":"MARKER-END"}},
 {"id":"t/template","status":"active","summary":"Template","text":{"path":"skills/demo/koto-templates/demo.md","first":"TEMPLATE-RULE starts","last":"TEMPLATE-RULE ends"}},
 {"id":"t/nested","status":"active","summary":"Nested","text":{"path":"skills/demo/sub/SKILL.md","first":"NESTED-RULE"}},
 {"id":"t/twice","status":"active","summary":"Twice","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}},
 {"id":"t/twice","status":"active","summary":"Twice again","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}},
 {"id":"t/nostatus","summary":"No status","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}},
 {"id":"rs-900","status":"active","summary":"Criterion","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}}
]}'

# make_root <dir> <version>: a plugin root with the script, the synthetic
# registry and the files it names; not a git repository.
make_root() {
    local d=$1 v=$2 i
    mkdir -p "$d/scripts" "$d/references" "$d/docs" "$d/.claude-plugin" "$d/skills/demo/koto-templates"
    cp "$SUT" "$d/scripts/rule-registry.sh"
    printf '%s\n' "$REGISTRY_JSON" > "$d/references/rule-registry.json"
    printf '{"name":"shirabe","version":"%s"}\n' "$v" > "$d/.claude-plugin/plugin.json"
    {
        echo "# Rules"
        echo ""
        echo "RULE-MULTI starts here, with a backslash \\n and a [bracket]."
        echo "middle line"
        echo "RULE-MULTI ends here."
        echo ""
        echo "RULE-SINGLE only line."
        echo "DUP one"
        echo "DUP two"
    } > "$d/references/r.md"
    ln -s r.md "$d/references/link.md"
    { echo "LONG-START"; i=0; while [ $i -lt 60 ]; do echo "line $i"; i=$((i + 1)); done; echo "LONG-END"; } > "$d/references/long.md"
    echo "DOCS-RULE in a file no skill loads" > "$d/docs/notes.md"
    printf 'MARKER-START\n::shirabe-rule-end::\nMARKER-END\n' > "$d/references/marker.md"
    printf 'TEMPLATE-RULE starts\n\ttabbed line\nTEMPLATE-RULE ends\n' > "$d/skills/demo/koto-templates/demo.md"
    mkdir -p "$d/skills/demo/sub"
    echo "NESTED-RULE in a SKILL.md that is not a skill's own" > "$d/skills/demo/sub/SKILL.md"
}

# make_repo <dir>: make_root, then commit it as a git repository.
make_repo() {
    make_root "$1" 9.9.9
    git -C "$1" init -q
    git -C "$1" add -A
    git -C "$1" commit -q -m init
}

run() { # run <root> <args...>: the copied script, stdout and stderr kept apart
    local root=$1; shift
    OUT=$("$root/scripts/rule-registry.sh" "$@" 2>"$T/err"); RC=$?
    ERR=$(cat "$T/err")
}

# --- the real registry, read from shirabe's own checkout ---------------------

out=$("$SUT" ref commit/conventional-subject) && rc=0 || rc=$?
if [ $rc -eq 0 ] && grep -Eq '^references/pr-body-conformance\.md#L[0-9]+-L[0-9]+@([0-9a-f]{12}|worktree)$' <<<"$out"; then
    pass "ref on the real registry prints path#La-Lb@revision"
else
    fail "ref on the real registry" "rc=$rc out=[$out]"
fi

# The printed range is checked against the file independently of the resolver:
# its first line holds the first anchor and its last line the last anchor.
first=$(jq -r '.rules[] | select(.id == "commit/conventional-subject") | .text.first' "$REPO_ROOT/references/rule-registry.json")
last=$(jq -r '.rules[] | select(.id == "commit/conventional-subject") | .text.last' "$REPO_ROOT/references/rule-registry.json")
range=${out#*#L}; range=${range%@*}; a=${range%-L*}; b=${range#*-L}
if sed -n "${a}p" "$REPO_ROOT/references/pr-body-conformance.md" | grep -qF -- "$first" \
   && sed -n "${b}p" "$REPO_ROOT/references/pr-body-conformance.md" | grep -qF -- "$last"; then
    pass "ref's range starts at the first anchor and ends at the last"
else
    fail "ref's range" "[$range] does not frame the anchors"
fi

# --- checkout revisions ------------------------------------------------------

R="$T/repo"; make_repo "$R"
head=$(git -C "$R" rev-parse HEAD)
run "$R" ref t/multi
if [ $RC -eq 0 ] && [ "$OUT" = "references/r.md#L3-L5@${head:0:12}" ]; then
    pass "a clean checkout names its HEAD commit"
else
    fail "clean checkout" "rc=$RC out=[$OUT] want references/r.md#L3-L5@${head:0:12}"
fi

run "$R" ref t/single
[ "$OUT" = "references/r.md#L7-L7@${head:0:12}" ] && pass "a one-line rule is a one-line range" \
    || fail "one-line rule" "out=[$OUT]"

# Lines inserted above the rule move the range, with no registry edit.
{ printf 'new 1\nnew 2\nnew 3\n'; cat "$R/references/r.md"; } > "$T/r.md" && cp "$T/r.md" "$R/references/r.md"
git -C "$R" commit -q -am "insert three lines"
head2=$(git -C "$R" rev-parse HEAD)
run "$R" ref t/multi
[ "$OUT" = "references/r.md#L6-L8@${head2:0:12}" ] && pass "inserting three lines above moves the range by three" \
    || fail "anchor movement" "out=[$OUT]"

echo "uncommitted" >> "$R/references/r.md"
run "$R" ref t/multi
[ "$OUT" = "references/r.md#L6-L8@worktree" ] && pass "a file with uncommitted changes gives the worktree revision" \
    || fail "dirty checkout" "out=[$OUT]"
git -C "$R" checkout -q -- references/r.md

# A clean filter planted in the repository's config and .gitattributes would run
# when git hashes the file through its filters; --no-filters is what stops it.
git -C "$R" config filter.planted.clean "touch $T/filter-ran; cat"
echo '*.md filter=planted' > "$R/.git/info/attributes"
run "$R" ref t/multi
if [ "$OUT" = "references/r.md#L6-L8@${head2:0:12}" ] && [ ! -e "$T/filter-ran" ]; then
    pass "a planted clean filter does not run"
else
    fail "planted filter" "out=[$OUT] filter=$( [ -e "$T/filter-ran" ] && echo ran)"
fi
rm -f "$R/.git/info/attributes"

# A caller's GIT_DIR and GIT_WORK_TREE can't point git at another repository.
mkdir -p "$T/other"; git -C "$T/other" init -q
OUT=$(GIT_DIR="$T/other/.git" GIT_WORK_TREE="$T/other" "$R/scripts/rule-registry.sh" ref t/multi 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && [ "$OUT" = "references/r.md#L6-L8@${head2:0:12}" ] && pass "a caller's GIT_DIR is ignored" \
    || fail "GIT_DIR" "rc=$RC out=[$OUT] err=[$(cat "$T/err")]"

# --- installed-copy revisions ------------------------------------------------

I="$T/installed"; make_root "$I" 1.2.3
run "$I" ref t/multi
[ "$OUT" = "references/r.md#L3-L5@v1.2.3" ] && pass "an installed release names its tag" \
    || fail "installed release" "out=[$OUT] err=[$ERR]"

D="$T/dev"; make_root "$D" 1.2.4-dev
blob=$(git hash-object --no-filters -- "$D/references/r.md")
run "$D" ref t/multi
[ "$OUT" = "references/r.md#L3-L5@1.2.4-dev+${blob:0:12}" ] && pass "an installed -dev copy names its version and the file's blob" \
    || fail "installed dev" "out=[$OUT] want blob ${blob:0:12}"

# No git on PATH: the version alone.
NOGIT="$T/nogit-bin"; mkdir -p "$NOGIT"
for tool in bash jq awk sed grep tr dirname basename env cat mktemp rm wc; do
    p=$(command -v "$tool") && ln -s "$p" "$NOGIT/$tool"
done
OUT=$(PATH="$NOGIT" "$D/scripts/rule-registry.sh" ref t/multi 2>"$T/err"); RC=$?
[ "$OUT" = "references/r.md#L3-L5@1.2.4-dev" ] && pass "without git, the version alone" \
    || fail "no git" "rc=$RC out=[$OUT] err=[$(cat "$T/err")]"

U="$T/unknown"; make_root "$U" "not a version"
run "$U" ref t/multi
[ "$OUT" = "references/r.md#L3-L5@unknown" ] && pass "a malformed version gives the unknown revision" \
    || fail "unknown version" "out=[$OUT]"

# --- refusals ----------------------------------------------------------------

expect_rc() { # expect_rc <want> <label> <args...>
    local want=$1 label=$2; shift 2
    run "$I" "$@"
    [ "$RC" -eq "$want" ] && pass "$label exits $want" || fail "$label" "rc=$RC want $want err=[$ERR]"
}
expect_rc 1 "an unknown id" ref t/none
expect_rc 1 "a retired id" ref t/retired
expect_rc 2 "an id matching neither pattern" ref 'T/Upper'
expect_rc 2 "an absolute path" ref t/abs
expect_rc 2 "a path with .." ref t/dotdot
expect_rc 2 "a path starting with -" ref t/dash
expect_rc 2 "a symlinked path" ref t/link
expect_rc 2 "a first anchor on two lines" ref t/dup
expect_rc 2 "a last anchor before the first" ref t/backwards
expect_rc 1 "summary of a retired id" summary t/retired
expect_rc 2 "an id with two entries" ref t/twice
expect_rc 2 "an entry with no status" ref t/nostatus

run "$I" summary t/multi
[ "$RC" -eq 0 ] && [ "$OUT" = "Multi-line rule" ] && pass "summary prints the short text" || fail "summary" "out=[$OUT]"

run "$I" text t/multi
want=$(sed -n '3,5p' "$I/references/r.md")
[ "$RC" -eq 0 ] && [ "$OUT" = "$want" ] && pass "text prints the lines byte for byte, backslash included" \
    || fail "text" "out=[$OUT]"

run "$I" range t/multi
[ "$RC" -eq 0 ] && [ "$OUT" = "3 5" ] && pass "range prints the text's first and last line numbers" || fail "range" "out=[$OUT]"
run "$I" range t/single
[ "$RC" -eq 0 ] && [ "$OUT" = "7 7" ] && pass "range of a one-line rule is that line twice" || fail "range single" "out=[$OUT]"
expect_rc 2 "range of a rule whose anchors don't resolve" range t/backwards
expect_rc 1 "range of a retired id" range t/retired

run "$I" withhold t/multi
[ "$RC" -eq 0 ] && [ "$OUT" = eligible ] && pass "withhold prints eligible" || fail "withhold eligible" "out=[$OUT]"
run "$I" withhold t/single
[ "$RC" -eq 0 ] && [ "$OUT" = never ] && pass "withhold prints never" || fail "withhold never" "out=[$OUT]"
run "$I" withhold t/dup
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && pass "withhold of an entry with no withhold value exits 2 and prints nothing" \
    || fail "withhold missing" "rc=$RC out=[$OUT]"
expect_rc 1 "withhold of an unknown id" withhold t/none

echo '{"rules": [' > "$T/broken.json"
OUT=$("$I/scripts/rule-registry.sh" --registry "$T/broken.json" ref t/multi 2>/dev/null); RC=$?
[ $RC -eq 2 ] && pass "a registry that doesn't parse exits 2" || fail "broken registry" "rc=$RC"

# --- release -----------------------------------------------------------------

run "$I" release t/template
want_ref="skills/demo/koto-templates/demo.md#L1-L3@v1.2.3"
want_body=$(printf 'TEMPLATE-RULE starts\n\ttabbed line\nTEMPLATE-RULE ends')
first_line=$(printf '%s\n' "$ERR" | sed -n '1p')
body=$(printf '%s\n' "$ERR" | sed -n '2,4p')
last_line=$(printf '%s\n' "$ERR" | sed -n '5p')
if [ $RC -eq 0 ] && [ -z "$OUT" ] \
   && [ "$first_line" = "::shirabe-rule::{\"rule_id\":\"t/template\",\"rule_ref\":\"$want_ref\"}" ] \
   && [ "$body" = "$want_body" ] && [ "$last_line" = "::shirabe-rule-end::" ]; then
    pass "release prints the marker, the lines and the end marker on stderr, and nothing on stdout"
else
    fail "release" "rc=$RC out=[$OUT] err=[$ERR]"
fi

expect_release_refused() { # <label> <id> [registry]
    local label=$1 id=$2
    if [ $# -ge 3 ]; then
        OUT=$("$I/scripts/rule-registry.sh" --registry "$3" release "$id" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err")
    else
        run "$I" release "$id"
    fi
    if [ $RC -eq 0 ] && [ -z "$OUT" ] && [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" = 1 ] \
       && grep -q "^rule-registry: could not release $id: " <<<"$ERR"; then
        pass "release refuses $label with one notice line and exit 0"
    else
        fail "release $label" "rc=$RC out=[$OUT] err=[$ERR]"
    fi
}
expect_release_refused "an unreadable registry" t/template "$T/missing.json"
expect_release_refused "a file no skill loads" t/docs
expect_release_refused "a text over 60 lines" t/long
expect_release_refused "a text holding a marker line" t/marker
expect_release_refused "an unknown id" t/none
expect_release_refused "a nested SKILL.md that is not a skill's own" t/nested

run "$I" release t/docs
if grep -q "^rule-registry: could not release t/docs: docs/notes.md is not a file a skill loads$" <<<"$ERR"; then
    pass "release names its reason"
else
    fail "release reason" "err=[$ERR]"
fi
run "$I" release t/dup
if grep -q "^rule-registry: could not release t/dup: rule t/dup: its first anchor is not on exactly one line" <<<"$ERR"; then
    pass "release passes the reader's own reason through"
else
    fail "release reader reason" "err=[$ERR]"
fi

# Failures before the dispatch still give release's notice and exit 0.
OUT=$("$I/scripts/rule-registry.sh" --bogus release t/template 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && grep -q "^rule-registry: could not release t/template: unknown option --bogus" "$T/err" \
    && pass "release with a bad option prints its notice and exits 0" || fail "release bad option" "rc=$RC err=[$(cat "$T/err")]"
OUT=$(PATH="$NOGIT" "$I/scripts/rule-registry.sh" release t/template 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && grep -q "^::shirabe-rule::.*@v1.2.3\"}$" "$T/err" \
    && pass "release works without git on an installed copy" || fail "release no git" "rc=$RC err=[$(cat "$T/err")]"
NOJQ="$T/nojq-bin"; mkdir -p "$NOJQ"
for tool in bash awk sed grep tr dirname basename env cat mktemp rm wc git; do
    p=$(command -v "$tool") && ln -s "$p" "$NOJQ/$tool"
done
OUT=$(PATH="$NOJQ" "$I/scripts/rule-registry.sh" release t/template 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && grep -q "^rule-registry: could not release t/template: jq is required" "$T/err" \
    && pass "release without jq prints its notice and exits 0" || fail "release no jq" "rc=$RC err=[$(cat "$T/err")]"
# An empty PATH: not even dirname. bash is called by its full path.
BASH_BIN=$(command -v bash)
OUT=$(PATH="" "$BASH_BIN" "$I/scripts/rule-registry.sh" release t/template 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && grep -q "^rule-registry: could not release t/template: " "$T/err" \
    && pass "release with an empty PATH prints its notice and exits 0" || fail "release empty PATH" "rc=$RC err=[$(cat "$T/err")]"
OUT=$(PATH="$NOJQ" SHIRABE_FINDINGS_LOG="$T/tmpdir/nojq.log" TMPDIR="$T/tmpdir" "$I/scripts/rule-registry.sh" log-finding x 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && [ ! -s "$T/err" ] && pass "log-finding without jq exits 0 silently" || fail "log-finding no jq" "rc=$RC err=[$(cat "$T/err")]"
OUT=$(PATH="" "$BASH_BIN" "$I/scripts/rule-registry.sh" log-finding x 2>"$T/err"); RC=$?
[ $RC -eq 0 ] && pass "log-finding with an empty PATH exits 0" || fail "log-finding empty PATH" "rc=$RC err=[$(cat "$T/err")]"

# --- the findings log --------------------------------------------------------

ref=$("$I/scripts/rule-registry.sh" ref t/multi)
good="::koto-finding::{\"rule_id\":\"t/multi\",\"level\":\"error\",\"message\":\"Multi-line rule: detail\",\"rule_ref\":\"$ref\"}"
printf '%s\n' "$good" > "$T/good.log"
run "$I" verify-findings "$T/good.log"
[ $RC -eq 0 ] && pass "verify-findings accepts a correct log" || fail "verify-findings good" "rc=$RC err=[$ERR] out=[$OUT]"

: > "$T/empty.log"
run "$I" verify-findings "$T/empty.log"
[ $RC -eq 1 ] && pass "verify-findings refuses a log with no findings" || fail "verify-findings empty" "rc=$RC"

printf '%s\n' "::koto-finding::{\"rule_id\":\"t/multi\",\"level\":\"error\",\"message\":\"detail only\",\"rule_ref\":\"$ref\"}" > "$T/nosummary.log"
run "$I" verify-findings "$T/nosummary.log"
[ $RC -eq 1 ] && pass "verify-findings refuses a message without the summary prefix" || fail "verify-findings prefix" "rc=$RC"

printf '%s\n' "$good" '::koto-finding::{"rule_id":"t/none","level":"error","message":"m","rule_ref":"references/r.md#L3-L5@v1.2.3"}' > "$T/unreg.log"
run "$I" verify-findings "$T/unreg.log"
[ $RC -eq 1 ] && pass "verify-findings refuses an unregistered id" || fail "verify-findings unregistered" "rc=$RC"

printf '%s\n' '::koto-finding::{"rule_id":"t/multi","level":"error","message":"Multi-line rule: m","rule_ref":"references/r.md#L3-L4@v1.2.3"}' > "$T/range.log"
run "$I" verify-findings "$T/range.log"
[ $RC -eq 1 ] && pass "verify-findings refuses a wrong range" || fail "verify-findings range" "rc=$RC"

mkdir -p "$T/tmpdir" "$T/elsewhere"
SHIRABE_FINDINGS_LOG="$T/tmpdir/f.log" TMPDIR="$T/tmpdir" "$I/scripts/rule-registry.sh" log-finding "$good"
[ "$(cat "$T/tmpdir/f.log" 2>/dev/null)" = "$good" ] && pass "log-finding appends under the temporary directory" \
    || fail "log-finding" "log not written"
SHIRABE_FINDINGS_LOG="$T/elsewhere/f.log" TMPDIR="$T/tmpdir" "$I/scripts/rule-registry.sh" log-finding "$good"
[ ! -e "$T/elsewhere/f.log" ] && pass "log-finding ignores a log outside the temporary directory" \
    || fail "log-finding outside" "log written"
ln -s "$T/elsewhere/target.log" "$T/tmpdir/link.log"
SHIRABE_FINDINGS_LOG="$T/tmpdir/link.log" TMPDIR="$T/tmpdir" "$I/scripts/rule-registry.sh" log-finding "$good"
[ ! -e "$T/elsewhere/target.log" ] && pass "log-finding ignores a symlinked log" || fail "log-finding symlink" "log written through the link"

# --- rf_require_any ------------------------------------------------------------

# A gate script that resolves a finding's own rule at run time. The probe sources
# the library from an installed-style copy, so the reader it reaches is that
# copy's registry, with its t/ fixtures.
A="$T/any"; make_root "$A" 1.2.3
mkdir -p "$A/scripts/lib"
cp "$REPO_ROOT/scripts/lib/rule-findings.sh" "$A/scripts/lib/rule-findings.sh"
cat > "$A/probe.sh" <<'PROBE'
#!/usr/bin/env bash
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="t/multi"
[ -z "${NO_MARKER:-}" ] && RULE_IDS_ANY_ACTIVE=1
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
rf_require_any "$@"
rf_finding "$1" "a finding under its own rule"
PROBE
chmod +x "$A/probe.sh"
OUT=$("$A/probe.sh" t/single 2>"$T/err"); RC=$?
if [ $RC -eq 0 ] && grep -q '"rule_id":"t/single"' <<<"$OUT" \
    && grep -q '"message":"Single-line rule: a finding under its own rule"' <<<"$OUT"; then
    pass "rf_require_any resolves an active id that is not in RULE_IDS"
else
    fail "rf_require_any active" "rc=$RC out=[$OUT] err=[$(cat "$T/err")]"
fi
"$A/probe.sh" t/retired >/dev/null 2>"$T/err"; RC=$?
[ $RC -eq 2 ] && pass "rf_require_any refuses a retired id" || fail "rf_require_any retired" "rc=$RC"
"$A/probe.sh" t/nope >/dev/null 2>"$T/err"; RC=$?
[ $RC -eq 2 ] && pass "rf_require_any refuses an unknown id" || fail "rf_require_any unknown" "rc=$RC"
NO_MARKER=1 "$A/probe.sh" t/single >/dev/null 2>"$T/err"; RC=$?
[ $RC -eq 2 ] && grep -q "RULE_IDS_ANY_ACTIVE=1" "$T/err" \
    && pass "rf_require_any refuses a script without the RULE_IDS_ANY_ACTIVE marker" \
    || fail "rf_require_any marker" "rc=$RC err=[$(cat "$T/err")]"
# rf_emit still refuses an id the run resolved neither way.
cat > "$A/probe2.sh" <<'PROBE'
#!/usr/bin/env bash
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="t/multi"
  RULE_IDS_ANY_ACTIVE=1
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
rf_require_any t/single
rf_emit '{"rule_id":"t/multi","level":"error","message":"Multi-line rule: x","rule_ref":"r"}'
PROBE
chmod +x "$A/probe2.sh"
"$A/probe2.sh" >/dev/null 2>"$T/err"; RC=$?
[ $RC -eq 2 ] && pass "rf_emit refuses an id rf_require_any did not resolve" || fail "rf_emit unresolved" "rc=$RC"

# --- stage and resolve -------------------------------------------------------

# A scratch registry of script entries at each stage, with backstops that do
# and don't count. The entries' own check is scripts/check.sh; hooks/deny.sh
# and the workflow are the distinct checks a backstop may name.
S="$T/stage"; make_root "$S" 1.2.3
mkdir -p "$S/hooks" "$S/.github/workflows"
echo '#!/bin/sh' > "$S/scripts/check.sh"
echo '#!/bin/sh' > "$S/hooks/deny.sh"
echo 'name: ci' > "$S/.github/workflows/ci.yml"
ln -s deny.sh "$S/hooks/deny-link.sh"
cat > "$S/references/rule-registry.json" <<'JSON'
{"schema":"shirabe-rule-registry/v1","rules":[
 {"id":"s/nostage","status":"active","summary":"No stage","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"]},
 {"id":"s/unknown","status":"active","summary":"Unknown stage","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["none"],"stage":"loud"},
 {"id":"s/nonstring","status":"active","summary":"Stage not a string","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["none"],"stage":["warn"]},
 {"id":"s/no-backstop","status":"active","summary":"No backstop","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"warn"},
 {"id":"s/missing-path","status":"active","summary":"Missing backstop path","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"warn","stage_backstops":[{"before":"pr-create","check":"hooks/missing.sh"}]},
 {"id":"s/self-path","status":"active","summary":"Backstop is its own check","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"warn","stage_backstops":[{"before":"pr-create","check":"scripts/check.sh"}]},
 {"id":"s/link-path","status":"active","summary":"Backstop is a symlink","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"warn","stage_backstops":[{"before":"pr-create","check":"hooks/deny-link.sh"}]},
 {"id":"s/partial","status":"active","summary":"One guard of two backed","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create","push"],"stage":"warn","stage_backstops":[{"before":"pr-create","check":"hooks/deny.sh"}]},
 {"id":"s/wrong-before","status":"active","summary":"Backstop for another action","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"warn","stage_backstops":[{"before":"merge","check":"hooks/deny.sh"}]},
 {"id":"s/bad-guards","status":"active","summary":"Guards not a list","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":"pr-create","stage":"warn"},
 {"id":"s/covered","status":"active","summary":"Every guard backed","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create","publish"],"stage":"warn","stage_backstops":[{"before":"pr-create","check":"hooks/deny.sh"},{"before":"publish","check":".github/workflows/ci.yml"}]},
 {"id":"s/shadow","status":"active","summary":"Unguarded shadow","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["none"],"stage":"shadow"},
 {"id":"s/block","status":"active","summary":"Guarded block","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"block"},
 {"id":"s/quiet","status":"active","summary":"Retired check, guard backed","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"retired","stage_backstops":[{"before":"pr-create","check":"hooks/deny.sh"}]},
 {"id":"s/quiet-bare","status":"active","summary":"Retired check, guard unbacked","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"retired"},
 {"id":"s/gone","status":"retired","summary":"Retired rule","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"script","path":"scripts/check.sh"},"guards":["pr-create"],"stage":"retired"},
 {"id":"rs-901","status":"active","summary":"A criterion","text":{"path":"references/r.md","first":"RULE-SINGLE only line"},"check":{"kind":"review-shadow","criterion":"x"},"guards":["none"]}
]}
JSON

# stage_is <id> <want> <label>
stage_is() {
    run "$S" stage "$1"
    if [ $RC -eq 0 ] && [ "$OUT" = "$2" ]; then pass "stage: $3"; else fail "stage: $3" "rc=$RC out=[$OUT] want [$2] err=[$ERR]"; fi
}
stage_is s/nostage block "a script entry with no stage is block"
stage_is s/unknown block "an unknown stage value is block"
stage_is s/nonstring block "a stage that isn't a string is block"
stage_is s/no-backstop block "a guarded entry at warn with no stage_backstops is block"
stage_is s/missing-path block "a guarded entry at warn whose backstop path doesn't exist is block"
stage_is s/self-path block "a guarded entry at warn whose backstop is its own check.path is block"
stage_is s/link-path block "a guarded entry at warn whose backstop path is a symlink is block"
stage_is s/partial block "an entry guarding pr-create and push with a backstop for pr-create only is block"
stage_is s/wrong-before block "an entry guarding pr-create whose only backstop names merge is block"
stage_is s/bad-guards block "an entry below block whose guards aren't a list is block"
stage_is s/covered warn "an entry at warn with every protected guard backed by an existing, distinct path is warn"
stage_is s/shadow shadow "an entry guarding none keeps its shadow stage without a backstop"
stage_is s/block block "a guarded entry at block needs no backstop"
stage_is s/quiet retired "an active entry at retired with its guard backed is retired"
stage_is s/quiet-bare block "an active entry at retired with its guard unbacked is block"
stage_is s/gone retired "a status-retired script entry prints its stage"

run "$S" stage rs-901
[ $RC -ne 0 ] && [ -z "$OUT" ] && pass "stage fails for an entry that isn't script-checked" || fail "stage review-shadow" "rc=$RC out=[$OUT]"
run "$S" stage s/none
[ $RC -ne 0 ] && [ -z "$OUT" ] && pass "stage fails for an id with no entry" || fail "stage unknown id" "rc=$RC out=[$OUT]"
run "$S" stage 'not an id'
[ $RC -eq 2 ] && pass "stage refuses a malformed id" || fail "stage malformed id" "rc=$RC"

# resolve prints what ref, summary and stage print, tab-separated, one line.
for id in s/covered s/partial s/shadow; do
    run "$S" ref "$id"; r=$OUT
    run "$S" summary "$id"; m=$OUT
    run "$S" stage "$id"; s=$OUT
    run "$S" resolve "$id"
    want=$(printf '%s\t%s\t%s' "$r" "$m" "$s")
    if [ $RC -eq 0 ] && [ "$OUT" = "$want" ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; then
        pass "resolve $id prints ref, summary and stage on one tab-separated line"
    else
        fail "resolve $id" "rc=$RC out=[$OUT] want [$want]"
    fi
done
run "$S" resolve rs-901
[ $RC -eq 0 ] && [ "${OUT##*	}" = block ] && pass "resolve gives an active entry outside the lifecycle block" \
    || fail "resolve review-shadow" "rc=$RC out=[$OUT]"
run "$S" resolve s/gone
[ $RC -eq 1 ] && [ -z "$OUT" ] && pass "resolve refuses a retired rule like ref" || fail "resolve retired" "rc=$RC out=[$OUT]"
run "$S" resolve s/none
[ $RC -eq 1 ] && pass "resolve fails for an id with no entry" || fail "resolve unknown id" "rc=$RC"

# --- the library resolves once per rule -----------------------------------------

# A stub reader that logs every call: the library resolves each id with one
# `resolve` call, never with separate ref and summary calls, and rf_require_any
# skips an id already resolved.
L="$T/stub"; mkdir -p "$L/scripts/lib"
cp "$REPO_ROOT/scripts/lib/rule-findings.sh" "$L/scripts/lib/rule-findings.sh"
cat > "$L/scripts/rule-registry.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1:${STUB_SHAPE:-}" in
    resolve:) printf 'references/r.md#L1-L1@v0.0.0\tSummary of %s\tblock\n' "$2" ;;
    resolve:two) printf 'references/r.md#L1-L1@v0.0.0\tSummary of %s\n' "$2" ;;
    resolve:four) printf 'references/r.md#L1-L1@v0.0.0\tSummary of %s\tblock\textra\n' "$2" ;;
    resolve:loud) printf 'references/r.md#L1-L1@v0.0.0\tSummary of %s\tloud\n' "$2" ;;
    log-finding:*) ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$L/scripts/rule-registry.sh"
cat > "$L/probe.sh" <<'PROBE'
#!/usr/bin/env bash
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="t/a t/b"
  RULE_IDS_ANY_ACTIVE=1
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
rf_require t/a t/b
rf_require_any t/c t/a t/c
printf '%s|%s|%s\n' "$(rf_ref t/c)" "$(rf_summary t/c)" "$(rf_stage t/c)"
PROBE
chmod +x "$L/probe.sh"
: > "$T/stub.log"
OUT=$(STUB_LOG="$T/stub.log" "$L/probe.sh" 2>"$T/err"); RC=$?
calls=$(tr '\n' ',' < "$T/stub.log")
if [ $RC -eq 0 ] && [ "$calls" = "resolve t/a,resolve t/b,resolve t/c," ] \
    && [ "$OUT" = "references/r.md#L1-L1@v0.0.0|Summary of t/c|block" ]; then
    pass "rf_require and rf_require_any make one resolve call per id and cache its ref, summary and stage"
else
    fail "one resolve per id" "rc=$RC calls=[$calls] out=[$OUT] err=[$(cat "$T/err")]"
fi
for shape in two four loud; do
    : > "$T/stub.log"
    STUB_SHAPE=$shape STUB_LOG="$T/stub.log" "$L/probe.sh" >/dev/null 2>"$T/err"; RC=$?
    [ $RC -eq 2 ] && pass "rf_require refuses a resolve line of shape [$shape]" \
        || fail "resolve shape $shape" "rc=$RC err=[$(cat "$T/err")]"
done

# --- the library applies the stage ----------------------------------------------

# The library run against the stage registry's reader: s/block, s/covered,
# s/shadow and s/quiet resolve to block, warn, shadow and retired.
mkdir -p "$S/scripts/lib"
cp "$REPO_ROOT/scripts/lib/rule-findings.sh" "$S/scripts/lib/rule-findings.sh"
cat > "$S/probe.sh" <<'PROBE'
#!/usr/bin/env bash
# probe.sh find <id>...            rf_finding for each id
# probe.sh emit <id> [<stage-id>]  rf_emit of a finding for <id>
# probe.sh stage <id>              rf_stage and rf_level
# probe.sh hint                    rf_dispute_hint
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="s/block s/covered s/shadow s/quiet"
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
mode=$1; shift
case "$mode" in
    find)
        rf_require s/block s/covered s/shadow s/quiet
        for id in "$@"; do
            rf_finding "$id" "detail"
            echo "counted=$RF_COUNTED"
        done ;;
    emit)
        rf_require s/block s/covered s/shadow s/quiet
        ref=$(rf_ref "$1") || exit 2
        sum=$(rf_summary "$1") || exit 2
        json=$(jq -cn --arg id "$1" --arg ref "$ref" --arg m "$sum: built by the script" \
            '{rule_id: $id, level: "error", message: $m, rule_ref: $ref}')
        rf_emit "$json" ${2+"$2"}
        echo "counted=$RF_COUNTED" ;;
    stage)
        rf_require "$1"
        s=$(rf_stage "$1") || exit 2
        l=$(rf_level "$s"); echo "stage=$s level=$l rc=$?" ;;
    hint)
        rf_dispute_hint ;;
esac
echo "blocking=$RF_BLOCKING"
PROBE
chmod +x "$S/probe.sh"
mkdir -p "$T/tmpdir"
LOGF="$T/tmpdir/stage.log"
probe() { : > "$LOGF"; OUT=$(SHIRABE_FINDINGS_LOG="$LOGF" TMPDIR="$T/tmpdir" "$S/probe.sh" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
levels() { printf '%s\n' "$OUT" | sed -n 's/^::koto-finding:://p' | jq -r '.level' | tr '\n' ' ' | sed 's/ $//'; }

probe find s/block
[ $RC -eq 0 ] && [ "$(levels)" = error ] && grep -qx 'counted=1' <<<"$OUT" && grep -qx 'blocking=1' <<<"$OUT" \
    && pass "rf_finding prints a block rule's finding at error, counts it and sets RF_COUNTED to 1" \
    || fail "rf_finding block" "rc=$RC out=[$OUT] err=[$ERR]"
probe find s/covered
[ $RC -eq 0 ] && [ "$(levels)" = warning ] && grep -qx 'counted=0' <<<"$OUT" && grep -qx 'blocking=0' <<<"$OUT" \
    && pass "rf_finding prints a warn rule's finding at warning without counting it" \
    || fail "rf_finding warn" "rc=$RC out=[$OUT] err=[$ERR]"
probe find s/shadow
[ $RC -eq 0 ] && [ "$(levels)" = info ] && grep -qx 'counted=0' <<<"$OUT" && grep -qx 'blocking=0' <<<"$OUT" \
    && pass "rf_finding prints a shadow rule's finding at info without counting it" \
    || fail "rf_finding shadow" "rc=$RC out=[$OUT] err=[$ERR]"
probe find s/quiet
[ $RC -eq 0 ] && ! grep -q '::koto-finding::' <<<"$OUT" && [ ! -s "$LOGF" ] \
    && grep -qx 'counted=0' <<<"$OUT" && grep -qx 'blocking=0' <<<"$OUT" \
    && pass "rf_finding prints and logs nothing for a retired rule and doesn't count it" \
    || fail "rf_finding retired" "rc=$RC out=[$OUT] log=[$(cat "$LOGF")] err=[$ERR]"
probe find s/block s/covered s/quiet s/block s/shadow
[ $RC -eq 0 ] && [ "$(levels)" = "error warning error info" ] && grep -qx 'blocking=2' <<<"$OUT" \
    && [ "$(grep -c '^::koto-finding::' "$LOGF")" = 4 ] \
    && pass "RF_BLOCKING counts only the block findings of a mixed run, and the log holds every printed one" \
    || fail "rf_finding mixed" "rc=$RC out=[$OUT] err=[$ERR]"
run "$S" verify-findings "$LOGF"
[ $RC -eq 0 ] && pass "verify-findings accepts findings printed at their rules' stages" \
    || fail "verify-findings stages" "rc=$RC out=[$OUT] err=[$ERR]"

probe emit s/shadow
[ $RC -eq 0 ] && [ "$(levels)" = info ] && grep -qx 'blocking=0' <<<"$OUT" \
    && pass "rf_emit sets a built finding's level from its own rule's stage" \
    || fail "rf_emit own stage" "rc=$RC out=[$OUT] err=[$ERR]"
probe emit s/shadow s/block
[ $RC -eq 0 ] && [ "$(levels)" = error ] && grep -qx 'counted=1' <<<"$OUT" && grep -qx 'blocking=1' <<<"$OUT" \
    && pass "rf_emit with a stage source prints at that rule's stage and counts a block" \
    || fail "rf_emit stage source block" "rc=$RC out=[$OUT] err=[$ERR]"
run "$S" verify-findings "$LOGF"
[ $RC -eq 1 ] && pass "verify-findings without --stage-source refuses a finding printed at another rule's stage" \
    || fail "verify-findings no stage source" "rc=$RC out=[$OUT]"
run "$S" verify-findings --stage-source s/block "$LOGF"
[ $RC -eq 0 ] && pass "verify-findings --stage-source checks the level against that rule's stage" \
    || fail "verify-findings stage source" "rc=$RC out=[$OUT] err=[$ERR]"
probe emit s/block s/quiet
[ $RC -eq 0 ] && ! grep -q '::koto-finding::' <<<"$OUT" && [ ! -s "$LOGF" ] && grep -qx 'blocking=0' <<<"$OUT" \
    && pass "rf_emit with a retired stage source prints, logs and counts nothing" \
    || fail "rf_emit stage source retired" "rc=$RC out=[$OUT] err=[$ERR]"
probe emit s/block s/partial
[ $RC -eq 2 ] && ! grep -q '::koto-finding::' <<<"$OUT" \
    && pass "rf_emit refuses a stage source the run did not resolve" \
    || fail "rf_emit unresolved stage source" "rc=$RC out=[$OUT]"

for pair in s/block:error s/covered:warning s/shadow:info; do
    probe stage "${pair%%:*}"
    [ $RC -eq 0 ] && grep -q "level=${pair#*:} rc=0" <<<"$OUT" \
        && pass "rf_stage and rf_level give ${pair%%:*} the level ${pair#*:}" || fail "rf_level ${pair%%:*}" "rc=$RC out=[$OUT] err=[$ERR]"
done
probe stage s/quiet
[ $RC -eq 0 ] && grep -q "stage=retired level= rc=1" <<<"$OUT" \
    && pass "rf_level prints nothing and fails for retired" || fail "rf_level retired" "rc=$RC out=[$OUT] err=[$ERR]"

probe hint
want="probe.sh: to dispute a finding you believe is wrong, run $S/scripts/rule-dispute.sh --session <session> --gate <gate> --rule <rule-id> --reason <why>; the session and gate are in the koto response"
[ $RC -eq 0 ] && [ "$ERR" = "$want" ] && [ "$OUT" = "blocking=0" ] \
    && pass "rf_dispute_hint prints one standard-error line naming rule-dispute.sh with its placeholders" \
    || fail "rf_dispute_hint" "rc=$RC err=[$ERR] out=[$OUT]"

# verify-findings on levels, with hand-written logs.
sref=$("$S/scripts/rule-registry.sh" ref s/covered)
qref=$("$S/scripts/rule-registry.sh" ref s/quiet)
printf '%s\n' "::koto-finding::{\"rule_id\":\"s/covered\",\"level\":\"error\",\"message\":\"Every guard backed: x\",\"rule_ref\":\"$sref\"}" > "$T/wrong-level.log"
run "$S" verify-findings "$T/wrong-level.log"
[ $RC -eq 1 ] && grep -q 'level \[error\] is not \[warning\]' <<<"$OUT" \
    && pass "verify-findings refuses a warn rule's finding logged at error" || fail "verify-findings wrong level" "rc=$RC out=[$OUT]"
printf '%s\n' "::koto-finding::{\"rule_id\":\"s/covered\",\"message\":\"Every guard backed: x\",\"rule_ref\":\"$sref\"}" > "$T/no-level.log"
run "$S" verify-findings "$T/no-level.log"
[ $RC -eq 1 ] && pass "verify-findings refuses a finding with no level" || fail "verify-findings no level" "rc=$RC out=[$OUT]"
printf '%s\n' "::koto-finding::{\"rule_id\":\"s/quiet\",\"level\":\"error\",\"message\":\"Retired check, guard backed: x\",\"rule_ref\":\"$qref\"}" > "$T/retired.log"
run "$S" verify-findings "$T/retired.log"
[ $RC -eq 1 ] && grep -q 'stage retired' <<<"$OUT" \
    && pass "verify-findings refuses any finding logged under a retired stage" || fail "verify-findings retired" "rc=$RC out=[$OUT]"
run "$S" verify-findings --stage-source s/none "$T/wrong-level.log"
[ $RC -eq 2 ] && pass "verify-findings exits 2 for a stage source that doesn't resolve" || fail "verify-findings bad source" "rc=$RC"
run "$S" verify-findings --stage-source s/block
[ $RC -eq 2 ] && pass "verify-findings --stage-source without a log is a usage error" || fail "verify-findings usage" "rc=$RC"

# --- the escalation ladder (rf_deliver) ----------------------------------------

# A gate script that prints one finding per argument and then delivers. The
# library is an installed-style copy, so release reads the t/ fixtures: t/multi
# and t/single release, t/long (longer than release allows) and t/docs (a docs/ path) don't.
L="$T/ladder"; make_root "$L" 1.2.3
mkdir -p "$L/scripts/lib"
cp "$REPO_ROOT/scripts/lib/rule-findings.sh" "$L/scripts/lib/rule-findings.sh"
cat > "$L/probe.sh" <<'PROBE'
#!/usr/bin/env bash
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="t/multi t/single t/long t/docs"
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
rf_require t/multi t/single t/long t/docs
for id in "$@"; do rf_finding "$id" "detail for $id"; done
rf_deliver
[ -z "${DELIVER_TWICE:-}" ] || rf_deliver
exit 1
PROBE
chmod +x "$L/probe.sh"
LOGS="$T/ladder-logs"; mkdir -p "$LOGS"
LADDER_EXITS="pr_creation:pr_status finalization:finalization_status"

# mklog <file> <state> [<event json>...]: a koto session log whose header is
# line 1, whose session entered <state> last, and which holds the given events.
mklog() {
    local f=$1 state=$2 seq=1 ev
    shift 2
    printf '%s\n' '{"schema_version":1,"workflow":"w","template_hash":"h","created_at":"2026-10-16T00:00:00Z"}' > "$f"
    printf '{"seq":%d,"timestamp":"t","type":"transitioned","payload":{"from":"start","to":"%s"}}\n' "$seq" "$state" >> "$f"
    for ev in "$@"; do
        seq=$((seq + 1))
        printf '{"seq":%d,"timestamp":"t","type":"gate_evaluated","payload":%s}\n' "$seq" "$ev" >> "$f"
    done
}
# fail_ev <state> <gate> <rule> <session> [<visit>]: a failed gate_evaluated payload.
fail_ev() {
    printf '{"state":"%s","gate":"%s","outcome":"failed","attempt":1,"visit_attempt":1,"rule_counts":{"%s":{"visit":%s,"session":%s}}}' \
        "$1" "$2" "$3" "${5:-1}" "$4"
}
# ladder <log> <gate> <ids...>: run the probe with the ladder's context.
ladder() {
    local log=$1 gate=$2
    shift 2
    SHIRABE_GATE_LOG="$log" SHIRABE_GATE_NAME="$gate" SHIRABE_GATE_EXITS="$LADDER_EXITS" \
        "$L/probe.sh" "$@" > "$T/lout" 2> "$T/lerr"
    RC=$?
}
released() { grep -c "^::shirabe-rule::{\"rule_id\":\"$1\"" "$T/lerr"; }
notices() { grep -c '^::shirabe-check-exit::' "$T/lerr"; }

"$L/probe.sh" t/multi > "$T/plain.out" 2> "$T/plain.err"; plain_rc=$?
[ $plain_rc -eq 1 ] && [ ! -s "$T/plain.err" ] && grep -q '"rule_id":"t/multi"' "$T/plain.out" \
    && pass "ladder: without the context rf_deliver prints nothing" \
    || fail "ladder no context" "rc=$plain_rc err=[$(cat "$T/plain.err")]"

mklog "$LOGS/none.jsonl" pr_creation
ladder "$LOGS/none.jsonl" g t/multi
[ $RC -eq 1 ] && [ "$(released t/multi)" = 0 ] && [ "$(notices)" = 0 ] \
    && pass "ladder: count 1 prints the summary finding and no release" \
    || fail "ladder count 1" "rc=$RC err=[$(cat "$T/lerr")]"
cmp -s "$T/lout" "$T/plain.out" && pass "ladder: standard output is the same with and without the context" \
    || fail "ladder stdout" "outputs differ"

mklog "$LOGS/one.jsonl" pr_creation "$(fail_ev pr_creation g t/multi 1)"
ladder "$LOGS/one.jsonl" g t/multi
[ $RC -eq 1 ] && [ "$(released t/multi)" = 1 ] && grep -qx '::shirabe-rule-end::' "$T/lerr" && [ "$(notices)" = 0 ] \
    && pass "ladder: count 2 releases the rule's text once and offers no exit" \
    || fail "ladder count 2" "rc=$RC err=[$(cat "$T/lerr")]"
full_marker() { printf '::koto-rule-delivered::{"rule_id":"%s","extent":"full","delivery":"%s"}\n' "$1" "${2:-printed}"; }
{ cat "$T/plain.out"; full_marker t/multi; } | cmp -s "$T/lout" - \
    && pass "ladder: count 2 adds only the full delivery marker to standard output" || fail "ladder stdout 2" "outputs differ"

DELIVER_TWICE=1 ladder "$LOGS/one.jsonl" g t/multi
[ "$(released t/multi)" = 1 ] && pass "ladder: rf_deliver runs once per process" || fail "ladder once" "released $(released t/multi) times"

mklog "$LOGS/two.jsonl" other "$(fail_ev other g t/multi 1)" "$(fail_ev other g t/single 3)"
ladder "$LOGS/two.jsonl" g t/multi t/single
[ "$(released t/multi)" = 1 ] && [ "$(released t/single)" = 1 ] && [ "$(notices)" = 0 ] \
    && pass "ladder: two rules at count 2 and 4 are each released once; no exit outside the exit table" \
    || fail "ladder two rules" "err=[$(cat "$T/lerr")]"

mklog "$LOGS/three.jsonl" finalization "$(fail_ev finalization g t/multi 2)"
ladder "$LOGS/three.jsonl" g t/multi
n=$(grep '^::shirabe-check-exit::' "$T/lerr" | sed 's/^::shirabe-check-exit:://')
if [ "$(released t/multi)" = 1 ] && [ "$(notices)" = 1 ] \
    && [ "$(jq -r '.rule_id' <<<"$n")" = t/multi ] && [ "$(jq -r '.count' <<<"$n")" = 3 ] \
    && [ "$(jq -r '.state' <<<"$n")" = finalization ] \
    && [ "$(jq -r '.submit.finalization_status' <<<"$n")" = check_unsatisfiable ] \
    && jq -e '.submit | has("check_exit_reason")' <<<"$n" >/dev/null \
    && [ "$(jq -r '.ends_at' <<<"$n")" = done_blocked ]; then
    pass "ladder: count 3 in an exit state releases the text and prints one exit notice"
else
    fail "ladder count 3" "err=[$(cat "$T/lerr")]"
fi

mklog "$LOGS/three-noexit.jsonl" verification "$(fail_ev verification g t/multi 2)"
ladder "$LOGS/three-noexit.jsonl" g t/multi
[ "$(released t/multi)" = 1 ] && [ "$(notices)" = 0 ] \
    && pass "ladder: count 3 in a state without an exit prints no notice" || fail "ladder no exit" "err=[$(cat "$T/lerr")]"

mklog "$LOGS/tie.jsonl" pr_creation "$(fail_ev pr_creation g t/single 2)" "$(fail_ev pr_creation g t/multi 2)"
ladder "$LOGS/tie.jsonl" g t/multi t/single
[ "$(notices)" = 1 ] && grep -q '^::shirabe-check-exit::{"rule_id":"t/multi"' "$T/lerr" \
    && grep -q '"pr_status":"check_unsatisfiable"' "$T/lerr" \
    && pass "ladder: a tie at count 3 names the rule printed first" || fail "ladder tie" "err=[$(cat "$T/lerr")]"

mklog "$LOGS/visit.jsonl" pr_creation "$(fail_ev pr_creation g t/multi 2 1)"
ladder "$LOGS/visit.jsonl" g t/multi
grep -q '"count":3' "$T/lerr" && pass "ladder: the count is koto's session count, not its visit count" \
    || fail "ladder session count" "err=[$(cat "$T/lerr")]"

mklog "$LOGS/elsewhere.jsonl" pr_creation "$(fail_ev pr_creation other-gate t/multi 4)" \
    "$(fail_ev finalization g t/multi 4)" "$(fail_ev pr_creation g t/single 4)"
ladder "$LOGS/elsewhere.jsonl" g t/multi
[ "$(released t/multi)" = 0 ] && [ "$(notices)" = 0 ] \
    && pass "ladder: counts under another gate, state or rule leave the rule at count 1" \
    || fail "ladder scoping" "err=[$(cat "$T/lerr")]"

# The same gate in two states: the state is read from the latest transition.
mklog "$LOGS/moved.jsonl" finalization "$(fail_ev finalization g t/multi 2)"
printf '%s\n' '{"seq":9,"timestamp":"t","type":"transitioned","payload":{"from":"finalization","to":"pre_pr_evidence"}}' >> "$LOGS/moved.jsonl"
ladder "$LOGS/moved.jsonl" g t/multi
[ "$(released t/multi)" = 0 ] && pass "ladder: a count recorded in another state doesn't follow the gate" \
    || fail "ladder moved" "err=[$(cat "$T/lerr")]"
printf '%s\n' '{"seq":10,"timestamp":"t","type":"rewound","payload":{"from":"pre_pr_evidence","to":"finalization"}}' >> "$LOGS/moved.jsonl"
ladder "$LOGS/moved.jsonl" g t/multi
[ "$(released t/multi)" = 1 ] && [ "$(notices)" = 1 ] \
    && pass "ladder: a rewind back makes the earlier state's count current" || fail "ladder rewound" "err=[$(cat "$T/lerr")]"

# Counts claimed anywhere but a gate_evaluated event of this gate change nothing.
mklog "$LOGS/claimed.jsonl" pr_creation
printf '%s\n' '{"seq":5,"timestamp":"t","type":"evidence_submitted","payload":{"state":"pr_creation","fields":{"rule_counts":{"t/multi":{"visit":9,"session":9}}}}}' \
    '{"seq":6,"timestamp":"t","type":"context_added","payload":{"key":"rule_counts","state":"pr_creation","gate":"g"}}' >> "$LOGS/claimed.jsonl"
printf '9\n' > "$LOGS/count"
ladder "$LOGS/claimed.jsonl" g t/multi
[ "$(released t/multi)" = 0 ] && pass "ladder: a count claimed in evidence, context or a file has no effect" \
    || fail "ladder claimed" "err=[$(cat "$T/lerr")]"

# Logs the ladder can't read: every reported rule at count 2, no exit.
printf '%s\n' '{"seq":1,"timestamp":"t","type":"transitioned","payload":{"from":"a","to":"pr_creation"}}' > "$LOGS/noheader.jsonl"
printf '%s\n' '{"schema_version":2,"workflow":"w"}' > "$LOGS/v2.jsonl"
printf '%s\n' '{"schema_version":1,"workflow":"w"}' > "$LOGS/notransition.jsonl"
printf 'not json at all\n' > "$LOGS/garbage.jsonl"
for bad in "$LOGS/missing.jsonl" "$LOGS/noheader.jsonl" "$LOGS/v2.jsonl" "$LOGS/notransition.jsonl" "$LOGS/garbage.jsonl"; do
    ladder "$bad" g t/multi t/single
    if [ $RC -eq 1 ] && [ "$(released t/multi)" = 1 ] && [ "$(released t/single)" = 1 ] && [ "$(notices)" = 0 ] \
        && grep -q "^rule-findings: could not read koto's counts from $bad" "$T/lerr" \
        && ! grep -q '^jq: ' "$T/lerr" \
        && cmp -s "$T/lout" <("$L/probe.sh" t/multi t/single 2>/dev/null; full_marker t/multi; full_marker t/single); then
        pass "ladder: an unreadable log ($(basename "$bad")) releases every rule and offers no exit"
    else
        fail "ladder unreadable $(basename "$bad")" "rc=$RC err=[$(cat "$T/lerr")]"
    fi
done
if [ "$(id -u)" != 0 ]; then
    mklog "$LOGS/locked.jsonl" pr_creation "$(fail_ev pr_creation g t/multi 2)"
    chmod 000 "$LOGS/locked.jsonl"
    ladder "$LOGS/locked.jsonl" g t/multi
    chmod 600 "$LOGS/locked.jsonl"
    [ "$(released t/multi)" = 1 ] && [ "$(notices)" = 0 ] && pass "ladder: an unreadable file releases and offers no exit" \
        || fail "ladder locked" "err=[$(cat "$T/lerr")]"
fi
SHIRABE_GATE_NAME=g "$L/probe.sh" t/multi > /dev/null 2> "$T/lerr"
[ "$(released t/multi)" = 1 ] && pass "ladder: a gate name with no log is the unreadable-log path, not silence" \
    || fail "ladder half context" "err=[$(cat "$T/lerr")]"
SHIRABE_GATE_LOG="$LOGS/one.jsonl" "$L/probe.sh" t/multi > /dev/null 2> "$T/lerr"
[ "$(released t/multi)" = 1 ] && grep -q "^rule-findings: could not read koto's counts" "$T/lerr" \
    && pass "ladder: a log with no gate name is the unreadable-log path, not silence" \
    || fail "ladder half context log" "err=[$(cat "$T/lerr")]"

# Text release refuses: its refusal line, then the rule's anchored reference.
mklog "$LOGS/refused.jsonl" pr_creation "$(fail_ev pr_creation g t/long 1)" "$(fail_ev pr_creation g t/docs 1)"
ladder "$LOGS/refused.jsonl" g t/long t/docs
long_ref=$("$L/scripts/rule-registry.sh" ref t/long 2>/dev/null); docs_ref=$("$L/scripts/rule-registry.sh" ref t/docs 2>/dev/null)
if grep -q '^rule-registry: could not release t/long: ' "$T/lerr" \
    && grep -qxF "rule-findings: t/long's full text is at $long_ref" "$T/lerr" \
    && grep -q '^rule-registry: could not release t/docs: ' "$T/lerr" \
    && grep -qxF "rule-findings: t/docs's full text is at $docs_ref" "$T/lerr" \
    && [ -n "$long_ref" ] && [ -n "$docs_ref" ]; then
    pass "ladder: a rule release refuses gets the refusal and its anchored reference"
else
    fail "ladder refused" "err=[$(cat "$T/lerr")]"
fi
if [ "$(grep -cxF -- "$(full_marker t/long refused)" "$T/lout")" = 1 ] \
    && [ "$(grep -cxF -- "$(full_marker t/docs refused)" "$T/lout")" = 1 ] \
    && ! grep -q 'koto-rule-delivered' "$T/lerr"; then
    pass "ladder: each refused release prints its full, refused delivery marker on standard output"
else
    fail "ladder refused markers" "out=[$(cat "$T/lout")]"
fi

# --- delivery markers -----------------------------------------------------------
#
# rf_emit prints a summary marker beside each finding it prints; rf_release
# a full one beside each release, printed or refused; an id the run didn't
# resolve gets none. Run against the ladder's installed-style copy.
cat > "$L/marker-probe.sh" <<'PROBE'
#!/usr/bin/env bash
undecided() { echo "undecided: $*" >&2; exit 2; }
  RULE_IDS="t/multi t/single t/long t/docs"
. "$(dirname "$0")/scripts/lib/rule-findings.sh" || undecided "no library"
rf_require t/multi t/long
mode=$1; shift
case "$mode" in
    find) for id in "$@"; do rf_finding "$id" "detail for $id"; done ;;
    release) for id in "$@"; do rf_release "$id"; echo "rc=$?"; done ;;
esac
PROBE
chmod +x "$L/marker-probe.sh"
summary_marker() { printf '::koto-rule-delivered::{"rule_id":"%s","extent":"summary","delivery":"printed"}' "$1"; }

"$L/marker-probe.sh" find t/multi > "$T/mout" 2> "$T/merr"; RC=$?
if [ $RC -eq 0 ] && [ "$(sed -n 2p "$T/mout")" = "$(summary_marker t/multi)" ] \
    && sed -n 1p "$T/mout" | grep -q '^::koto-finding::{"rule_id":"t/multi"' \
    && [ "$(wc -l < "$T/mout" | tr -d ' ')" = 2 ] && ! grep -q 'koto-rule-delivered' "$T/merr"; then
    pass "markers: a finding is followed on standard output by its exact summary marker"
else
    fail "markers summary" "rc=$RC out=[$(cat "$T/mout")] err=[$(cat "$T/merr")]"
fi

"$L/marker-probe.sh" release t/multi t/long > "$T/mout" 2> "$T/merr"; RC=$?
want="$(full_marker t/multi printed)
rc=0
$(full_marker t/long refused)
rc=1"
if [ $RC -eq 0 ] && [ "$(cat "$T/mout")" = "$want" ] \
    && grep -q '^::shirabe-rule::{"rule_id":"t/multi"' "$T/merr" \
    && grep -q '^rule-registry: could not release t/long: ' "$T/merr"; then
    pass "markers: rf_release prints full/printed for a release and full/refused for a refusal, text and refusal on stderr"
else
    fail "markers release" "rc=$RC out=[$(cat "$T/mout")] err=[$(cat "$T/merr")]"
fi

# t/single is registered but this run didn't resolve it; t/nope has no entry.
"$L/marker-probe.sh" release t/single t/nope > "$T/mout" 2> "$T/merr"; RC=$?
if [ $RC -eq 0 ] && ! grep -q 'koto-rule-delivered' "$T/mout" && ! grep -q 'koto-rule-delivered' "$T/merr" \
    && [ "$(cat "$T/mout")" = "rc=0
rc=1" ]; then
    pass "markers: an id the run didn't resolve, or with no entry, prints no delivery marker"
else
    fail "markers unresolved" "rc=$RC out=[$(cat "$T/mout")] err=[$(cat "$T/merr")]"
fi

# The rules a /work-on gate script can report that release refuses. A rule
# joining or leaving this set changes what an agent gets at rung 2, so the set
# is pinned. panel-scope.sh --verdict can also print under any active id a
# finding cites; this covers the ids the scripts name on their RULE_IDS lines.
refused=""
for s in check-pr-output check-branch-output check-verification panel-scope; do
    for id in $(sed -n 's/^RULE_IDS="\(.*\)"$/\1/p' "$REPO_ROOT/skills/work-on/scripts/$s.sh"); do
        out=$("$SUT" release "$id" 2>&1 </dev/null)
        case "$out" in "::shirabe-rule::"*) ;; *) refused="$refused $id" ;; esac
    done
done
refused=$(printf '%s\n' $refused | sort -u | tr '\n' ' ')
want="docs/private-only-type docs/visibility-strategy-sections docs/visibility-vision-sections pr-body/banned-word pr-body/conformance "
[ "$refused" = "$want" ] && pass "ladder: the /work-on gate rules release refuses are the five the design names" \
    || fail "ladder unreleasable set" "got [$refused] want [$want]"

# --- the stage-to-level map, in its three copies ------------------------------
#
# rule-registry.sh's stage_level (for verify-findings), rule-findings.sh's
# rf_level (what a gate prints) and the test library's rf_test_level (what the
# suites expect) each map a stage to a finding level. Each function is read
# out of its file and run on its own, so a copy that drifts fails here rather
# than as a verify-findings mismatch nobody can place.

# fn_body <file> <name>: the function's definition, from its `<name>() {` line
# to the first line that is a lone `}`.
fn_body() {
    awk -v start="$2() {" '$0 == start { on = 1 } on { print } on && $0 == "}" { exit }' "$1"
}
# level_of <file> <name> <stage>: what the copy prints for <stage>.
level_of() {
    local body
    body=$(fn_body "$1" "$2")
    [ -n "$body" ] || { printf '<no %s in %s>' "$2" "$1"; return; }
    ( eval "$body"; "$2" "$3" ) 2>/dev/null
}
parity_ok=1
for stage in block warn shadow retired unknown-stage ""; do
    a=$(level_of "$SUT" stage_level "$stage")
    b=$(level_of "$REPO_ROOT/scripts/lib/rule-findings.sh" rf_level "$stage")
    c=$(level_of "$REPO_ROOT/scripts/lib/rule-findings-testlib.sh" rf_test_level "$stage")
    if [ "$a" != "$b" ] || [ "$a" != "$c" ]; then
        parity_ok=0
        fail "stage-to-level parity" "stage [$stage]: stage_level [$a], rf_level [$b], rf_test_level [$c]"
    fi
done
want_map="block=$(level_of "$SUT" stage_level block) warn=$(level_of "$SUT" stage_level warn) shadow=$(level_of "$SUT" stage_level shadow) retired=$(level_of "$SUT" stage_level retired)"
[ "$want_map" = "block=error warn=warning shadow=info retired=" ] \
    || { parity_ok=0; fail "stage-to-level map" "got [$want_map]"; }
[ "$parity_ok" = 1 ] && pass "stage_level, rf_level and rf_test_level map every stage alike: block error, warn warning, shadow info, retired nothing, anything else error"

# The check above reads real functions: a copy renamed or reshaped so the
# reader finds nothing must fail, not pass as three empty answers.
printf 'other() {\n    :\n}\n' > "$T/no-level.sh"
[ "$(level_of "$T/no-level.sh" stage_level warn)" = "<no stage_level in $T/no-level.sh>" ] \
    && pass "stage-to-level parity: a file without the function is reported, not read as empty" \
    || fail "stage-to-level parity reader" "read a level from a file with no stage_level"

# --- the real registry's shape -----------------------------------------------

REG="$REPO_ROOT/references/rule-registry.json"
n=$(jq '.rules | length' "$REG"); gates=$(jq '[.rules[] | select(.level == "gate")] | length' "$REG")
rsn=$(jq '[.rules[] | select(.id | test("^rs-"))] | length' "$REG")
# The 14 scope document-gate rules (check-hop-document.sh) took this from 40
# rules and 22 gates to 54 and 36; pr-body/banned-word (the PR gate's PB5)
# took it to 55 and 37; work-on/review-level-fits-facts, the decider check's
# Jev contract, took it to 56 and 38; rs-018 to rs-020, the scrutiny seats'
# rejected questions, to 59 rules and 20 criteria; work-on/scrutiny-decision-
# reasons, the scrutiny batch's Jev contract, to 60 and 39;
# pr-body/workflow-content, the PR gate's workflow-records check, to 61 and 40;
# red-first/no-red, red-first/no-green and test-change/held (gates) and
# review/test-edit-judgment and review/test-edit-weakens (prose) to 66 and 43;
# pr-body/pr-missing, pr-body/body-missing and pr-body/read-failed, the PR
# gate's could-not-decide rules, to 69 and 46.
[ "$n" = 69 ] && [ "$gates" = 46 ] && [ "$rsn" = 20 ] && pass "the registry has 69 rules: 46 gates and 20 criteria" \
    || fail "registry shape" "n=$n gates=$gates rs=$rsn"

missing=$(jq -r --slurpfile reg "$REG" '.criteria[].rule_id | select(. as $id | ($reg[0].rules | map(.id) | index($id)) == null)' \
    "$REPO_ROOT/scripts/review-shadow/criteria.json")
[ -z "$missing" ] && pass "every review-shadow criterion has an entry" || fail "criteria coverage" "missing: $missing"

bad=$(jq -r '.rules[] | select(.withhold != "never" and ((.guards != ["none"]) or (.check.kind == "none"))) | .id' "$REG")
[ -z "$bad" ] && pass "every guarding or unchecked rule is never-withhold" || fail "withhold safety" "$bad"

# rs-007 to rs-020 are Jev criteria, and a Jev criterion's rule may be left
# out of a run only once it is trusted (references/jev-criteria.md); none is,
# so they are never-withhold. rs-004 to rs-006 are script criteria.
never=$(jq -r '[.rules[] | select(.level == "gate" or .id == "rs-001" or .id == "rs-002" or .id == "rs-003" or .id == "execute/pr-takeover-needs-signal") | select(.withhold == "never")] | length' "$REG")
eligible=$(jq -r '[.rules[] | select(.id | test("^rs-00[4-6]$")) | select(.withhold == "eligible" and .guards == ["none"])] | length' "$REG")
jev_never=$(jq -r '[.rules[] | select(.id | test("^rs-0(0[7-9]|1[0-9]|20)$")) | select(.withhold == "never")] | length' "$REG")
[ "$never" = 49 ] && [ "$eligible" = 3 ] && [ "$jev_never" = 14 ] \
    && pass "gates but PB4, rs-001 to rs-003 and the takeover rule are never; rs-004 to rs-006 are eligible; the Jev criteria rs-007 to rs-020 are never" \
    || fail "withhold marking" "never=$never eligible=$eligible jev_never=$jev_never"

# The one gate rule eligible to withhold, through its backstop (the live
# offload canary); every other gate rule stays never.
gate_eligible=$(jq -r '[.rules[] | select(.level == "gate" and .withhold == "eligible") | .id] | join(",")' "$REG")
backstop=$(jq -r '.rules[] | select(.id == "pr-body/no-heading-in-part1") | "\(.guards | join(","))|\(.backstop.before)|\(.backstop.check)"' "$REG")
[ "$gate_eligible" = pr-body/no-heading-in-part1 ] && [ "$backstop" = "none|merge|.github/workflows/validate-pr-body.yml" ] \
    && pass "PB4 is the one eligible gate rule, guarding none with the PR-body CI gate as its backstop" \
    || fail "eligible gate rules" "eligible=[$gate_eligible] backstop=[$backstop]"

unexplained=$(jq -r '
    (.rules | map(.baseline_keys[]) | group_by(.) | map(select(length > 1) | .[0])) as $shared
    | .rules[]
    | select((.baseline_keys == [] and .notes == "")
          or (any(.baseline_keys[]; . as $k | $shared | index($k)) and .notes == ""))
    | .id' "$REG")
[ -z "$unexplained" ] && pass "every empty or shared baseline key list is explained in notes" \
    || fail "baseline notes" "$unexplained"

# The lifecycle fields: every active script entry at block since the landing
# date with gates (an entry added later, at block since the day it was added:
# red-first/no-red and red-first/no-green, test-change/held,
# pr-body/workflow-content and the PR gate's three could-not-decide rules),
# both retired script entries at retired, and nothing on any entry that isn't
# script-checked.
STAGE_SINCE=2026-10-16
bad=$(jq -r --arg since "$STAGE_SINCE" '.rules[] | select(.check.kind == "script" and .status == "active")
    | select(.stage != "block"
             or .stage_since != ({"pr-body/workflow-content": "2026-10-23",
                                  "pr-body/pr-missing": "2026-10-27",
                                  "pr-body/body-missing": "2026-10-27",
                                  "pr-body/read-failed": "2026-10-27",
                                  "test-change/held": "2026-10-23",
                                  "red-first/no-red": "2026-10-22",
                                  "red-first/no-green": "2026-10-22"}[.id] // $since)
             or (.gates | type) != "array" or (.gates | length) == 0
             or any(.gates[]; type != "string" or (test("^[a-z0-9-]+:[a-z0-9_]+:[a-z0-9_]+$") | not)))
    | .id' "$REG")
nactive=$(jq '[.rules[] | select(.check.kind == "script" and .status == "active")] | length' "$REG")
[ -z "$bad" ] && [ "$nactive" = 42 ] && pass "all 42 active script entries are at block since their landing date with gates" \
    || fail "active script stages" "n=$nactive bad: $bad"
retired=$(jq -r '[.rules[] | select(.check.kind == "script" and .status == "retired") | "\(.id)=\(.stage)"] | join(",")' "$REG")
[ "$retired" = "branch/no-wip-files=retired,panel/blocking-finding=retired" ] \
    && pass "both status-retired script entries are at retired" || fail "retired script stages" "$retired"
bad=$(jq -r '.rules[] | select(.check.kind != "script")
    | select(has("stage") or has("stage_since") or has("gates") or has("stage_backstops")) | .id' "$REG")
[ -z "$bad" ] && pass "no entry outside the script checks carries a lifecycle field" || fail "non-script lifecycle fields" "$bad"

# Each gate value names a command gate of its skill's templates, in a state
# the entry's timing lists, whose command runs a script that reports the rule:
# one whose RULE_IDS line lists the id, or panel-scope.sh, which reports
# panel/open-finding. The awk reads each template's frontmatter: a state at two
# spaces under `states:`, `gates:` at four, a gate at six, its command at eight.
for tpl in "$REPO_ROOT"/skills/*/koto-templates/*.md; do
    case "$tpl" in *.mermaid.md) continue ;; esac
    skill=${tpl#"$REPO_ROOT"/skills/}; skill=${skill%%/*}
    awk -v skill="$skill" '
        NR == 1 && /^---/ { fm = 1; next }
        fm && /^---/ { exit }
        !fm { next }
        /^states:/ { in_states = 1; next }
        in_states && /^  [a-z0-9_]+:/ { state = $1; sub(":", "", state); in_gates = 0; next }
        in_states && /^    gates:/ { in_gates = 1; next }
        in_states && /^    [a-z_]+:/ { in_gates = 0 }
        in_gates && /^      [a-z0-9_]+:/ { gate = $1; sub(":", "", gate); next }
        in_gates && /^        command:/ { c = $0; sub(/^        command: /, "", c); print skill ":" state ":" gate "\t" c }
    ' "$tpl"
done > "$T/command-gates.tsv"
for s in "$REPO_ROOT"/skills/*/scripts/*.sh; do
    line=$(grep -m1 '^RULE_IDS=' "$s") || continue
    ids=${line#RULE_IDS=\"}; ids=${ids%\"}
    printf '%s\t%s\n' "${s##*/}" "$ids"
done > "$T/rule-ids.tsv"
unmatched=""
while IFS='	' read -r id timing gate; do
    case " $timing " in *" ${gate%:*} "*) ;; *) unmatched="$unmatched $id:$gate(timing)"; continue ;; esac
    cmd=$(awk -F'\t' -v g="$gate" '$1 == g { print $2; exit }' "$T/command-gates.tsv")
    [ -n "$cmd" ] || { unmatched="$unmatched $id:$gate(no-command-gate)"; continue; }
    ok=""
    while IFS='	' read -r script ids; do
        case "$cmd" in *"scripts/$script\""*) ;; *) continue ;; esac
        if [ "$script" = panel-scope.sh ] || case " $ids " in *" $id "*) true ;; *) false ;; esac; then ok=1; break; fi
    done < "$T/rule-ids.tsv"
    [ -n "$ok" ] || unmatched="$unmatched $id:$gate(script)"
done < <(jq -r '.rules[] | select(.check.kind == "script" and .status == "active")
    | .id as $id | (.timing | join(" ")) as $t | .gates[] | "\($id)\t\($t)\t\(.)"' "$REG")
[ -s "$T/command-gates.tsv" ] && [ -z "$unmatched" ] \
    && pass "every gate names a command gate, in a timing state, that runs a script reporting the rule" \
    || fail "gates against the templates" "$unmatched"

wrong=""
for id in $(jq -r '.rules[] | select(.check.kind == "script") | .id' "$REG"); do
    want=$(jq -r --arg id "$id" '.rules[] | select(.id == $id) | if .status == "retired" then "retired" else "block" end' "$REG")
    got=$("$SUT" stage "$id" 2>/dev/null) || got="rc=$?"
    [ "$got" = "$want" ] || wrong="$wrong $id=$got"
done
[ -z "$wrong" ] && pass "stage prints block for every active script entry and retired for the retired two" \
    || fail "stage on the real registry" "$wrong"
"$SUT" stage rs-001 >/dev/null 2>&1 && fail "stage rs-001" "printed a stage for a review-shadow entry" \
    || pass "stage fails for a review-shadow entry on the real registry"
"$SUT" stage nope/no-such-rule >/dev/null 2>&1 && fail "stage unknown" "printed a stage for no entry" \
    || pass "stage fails for an id with no entry on the real registry"

unresolved=""
for id in $(jq -r '.rules[] | select(.status == "active") | .id' "$REG"); do
    "$SUT" ref "$id" >/dev/null 2>&1 || unresolved="$unresolved $id"
done
[ -z "$unresolved" ] && pass "every active rule's text resolves" || fail "resolution" "$unresolved"

echo ""
echo "rule-registry_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
