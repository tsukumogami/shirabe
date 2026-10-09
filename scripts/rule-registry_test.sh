#!/usr/bin/env bash
set -u

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
T=$(cd -P "$T" && pwd -P)
cleanup() { rm -rf "$T"; return 0; }
trap cleanup EXIT

# Commits in the scratch repositories must not depend on the host's identity.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

REGISTRY_JSON='{"schema":"shirabe-rule-registry/v1","rules":[
 {"id":"t/multi","status":"active","summary":"Multi-line rule","text":{"path":"references/r.md","first":"RULE-MULTI starts","last":"RULE-MULTI ends"}},
 {"id":"t/single","status":"active","summary":"Single-line rule","text":{"path":"references/r.md","first":"RULE-SINGLE only line"}},
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

out=$("$SUT" ref branch/no-wip-files) && rc=0 || rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -Eq '^references/wip-hygiene\.md#L[0-9]+-L[0-9]+@([0-9a-f]{12}|worktree)$'; then
    pass "ref on the real registry prints path#La-Lb@revision"
else
    fail "ref on the real registry" "rc=$rc out=[$out]"
fi

# The printed range is checked against the file independently of the resolver:
# its first line holds the first anchor and its last line the last anchor.
first=$(jq -r '.rules[] | select(.id == "branch/no-wip-files") | .text.first' "$REPO_ROOT/references/rule-registry.json")
last=$(jq -r '.rules[] | select(.id == "branch/no-wip-files") | .text.last' "$REPO_ROOT/references/rule-registry.json")
range=${out#*#L}; range=${range%@*}; a=${range%-L*}; b=${range#*-L}
if sed -n "${a}p" "$REPO_ROOT/references/wip-hygiene.md" | grep -qF -- "$first" \
   && sed -n "${b}p" "$REPO_ROOT/references/wip-hygiene.md" | grep -qF -- "$last"; then
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

# Planted repository config and a caller's GIT_DIR change nothing and run nothing.
git -C "$R" config core.fsmonitor "touch $T/fsmonitor-ran; false"
mkdir -p "$R/.githooks"; printf '#!/bin/sh\ntouch %s/hook-ran\n' "$T" > "$R/.githooks/post-checkout"
chmod +x "$R/.githooks/post-checkout"; git -C "$R" config core.hooksPath .githooks
mkdir -p "$T/other"; git -C "$T/other" init -q
OUT=$(GIT_DIR="$T/other/.git" GIT_WORK_TREE="$T/other" "$R/scripts/rule-registry.sh" ref t/multi 2>"$T/err"); RC=$?
if [ $RC -eq 0 ] && [ "$OUT" = "references/r.md#L6-L8@${head2:0:12}" ] && [ ! -e "$T/fsmonitor-ran" ] && [ ! -e "$T/hook-ran" ]; then
    pass "planted fsmonitor and hooks don't run, and a caller's GIT_DIR is ignored"
else
    fail "git hardening" "rc=$RC out=[$OUT] fsmonitor=$( [ -e "$T/fsmonitor-ran" ] && echo ran) hook=$( [ -e "$T/hook-ran" ] && echo ran)"
fi

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
for tool in bash jq awk sed grep tr dirname basename env cat mktemp; do
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

run "$I" summary t/multi
[ "$RC" -eq 0 ] && [ "$OUT" = "Multi-line rule" ] && pass "summary prints the short text" || fail "summary" "out=[$OUT]"

run "$I" text t/multi
want=$(sed -n '3,5p' "$I/references/r.md")
[ "$RC" -eq 0 ] && [ "$OUT" = "$want" ] && pass "text prints the lines byte for byte, backslash included" \
    || fail "text" "out=[$OUT]"

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
       && printf '%s' "$ERR" | grep -q "^rule-registry: could not release $id: "; then
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

# --- the findings log --------------------------------------------------------

ref=$("$I/scripts/rule-registry.sh" ref t/multi)
good="::koto-finding::{\"rule_id\":\"t/multi\",\"level\":\"error\",\"message\":\"m\",\"rule_ref\":\"$ref\"}"
printf '%s\n' "$good" > "$T/good.log"
run "$I" verify-findings "$T/good.log"
[ $RC -eq 0 ] && pass "verify-findings accepts a correct log" || fail "verify-findings good" "rc=$RC err=[$ERR] out=[$OUT]"

printf '%s\n' "$good" '::koto-finding::{"rule_id":"t/none","level":"error","message":"m","rule_ref":"references/r.md#L3-L5@v1.2.3"}' > "$T/unreg.log"
run "$I" verify-findings "$T/unreg.log"
[ $RC -eq 1 ] && pass "verify-findings refuses an unregistered id" || fail "verify-findings unregistered" "rc=$RC"

printf '%s\n' '::koto-finding::{"rule_id":"t/multi","level":"error","message":"m","rule_ref":"references/r.md#L3-L4@v1.2.3"}' > "$T/range.log"
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

# --- the real registry's shape -----------------------------------------------

REG="$REPO_ROOT/references/rule-registry.json"
n=$(jq '.rules | length' "$REG"); gates=$(jq '[.rules[] | select(.level == "gate")] | length' "$REG")
rsn=$(jq '[.rules[] | select(.id | test("^rs-"))] | length' "$REG")
[ "$n" = 39 ] && [ "$gates" = 21 ] && [ "$rsn" = 17 ] && pass "the registry has 39 rules: 21 gates and 17 criteria" \
    || fail "registry shape" "n=$n gates=$gates rs=$rsn"

missing=$(jq -r --slurpfile reg "$REG" '.criteria[].rule_id | select(. as $id | ($reg[0].rules | map(.id) | index($id)) == null)' \
    "$REPO_ROOT/scripts/review-shadow/criteria.json")
[ -z "$missing" ] && pass "every review-shadow criterion has an entry" || fail "criteria coverage" "missing: $missing"

bad=$(jq -r '.rules[] | select(.withhold != "never" and ((.guards != ["none"]) or (.check.kind == "none"))) | .id' "$REG")
[ -z "$bad" ] && pass "every guarding or unchecked rule is never-withhold" || fail "withhold safety" "$bad"

never=$(jq -r '[.rules[] | select(.level == "gate" or .id == "rs-001" or .id == "rs-002" or .id == "rs-003" or .id == "execute/pr-takeover-needs-signal") | select(.withhold == "never")] | length' "$REG")
eligible=$(jq -r '[.rules[] | select(.id | test("^rs-0(0[4-9]|1[0-7])$")) | select(.withhold == "eligible" and .guards == ["none"])] | length' "$REG")
[ "$never" = 25 ] && [ "$eligible" = 14 ] && pass "gates, rs-001 to rs-003 and the takeover rule are never; rs-004 to rs-017 are eligible" \
    || fail "withhold marking" "never=$never eligible=$eligible"

unexplained=$(jq -r '
    (.rules | map(.baseline_keys[]) | group_by(.) | map(select(length > 1) | .[0])) as $shared
    | .rules[]
    | select((.baseline_keys == [] and .notes == "")
          or (any(.baseline_keys[]; . as $k | $shared | index($k)) and .notes == ""))
    | .id' "$REG")
[ -z "$unexplained" ] && pass "every empty or shared baseline key list is explained in notes" \
    || fail "baseline notes" "$unexplained"

unresolved=""
for id in $(jq -r '.rules[] | select(.status == "active") | .id' "$REG"); do
    "$SUT" ref "$id" >/dev/null 2>&1 || unresolved="$unresolved $id"
done
[ -z "$unresolved" ] && pass "every active rule's text resolves" || fail "resolution" "$unresolved"

echo ""
echo "rule-registry_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
