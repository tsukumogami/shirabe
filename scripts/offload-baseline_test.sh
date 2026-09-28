#!/usr/bin/env bash
set -euo pipefail

# Tests for offload-baseline.sh.
#
# Every case runs against a throwaway git repository built here, so none of
# them depends on shirabe's own history, and a stub koto on PATH stands in for
# the real one: its `template compile` names the compiled file after the
# sha256 of the source, which is enough to tell a matching hash from a wrong
# one. The one case that reads the real repository is the public-content scan
# of the committed baseline directory, which is text only.
#
# Needs bash, git, jq and a sha256 tool (sha256sum or shasum). No koto, no
# network.
#
# Usage:
#   bash scripts/offload-baseline_test.sh
#
# Exit codes:
#   0 - all tests passed
#   1 - one or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/offload-baseline.sh"

PASS_COUNT=0
FAIL_COUNT=0
TEST_DIR=""

cleanup() {
    [ -n "$TEST_DIR" ] && rm -rf "$TEST_DIR"
    return 0
}
trap cleanup EXIT

fail() {
    echo "FAIL: $1 - $2" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $1" >&2
    PASS_COUNT=$((PASS_COUNT + 1))
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

TEST_DIR=$(mktemp -d)
FIX="$TEST_DIR/repo"
STUB_BIN="$TEST_DIR/bin"
mkdir -p "$FIX" "$STUB_BIN"

# A koto stand-in: `koto version` reports $STUB_KOTO_VERSION, and
# `koto template compile <file>` prints a cache path named by the file's
# sha256. Like the real koto, it refuses a template whose default_template
# names a child that does not exist relative to the template's own directory,
# which is what execute.md does with work-on.md.
cat > "$STUB_BIN/koto" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    version) echo "koto ${STUB_KOTO_VERSION:-9.9.9} (stub)" ;;
    template)
        [ "$2" = compile ] || exit 2
        child=$(sed -n 's/^default_template: *//p' "$3" | head -n 1)
        if [ -n "$child" ] && [ ! -f "$(dirname "$3")/$child" ]; then
            echo "child template not found: $child" >&2
            exit 1
        fi
        if command -v sha256sum >/dev/null 2>&1; then
            h=$(sha256sum "$3" | awk '{ print $1 }')
        else
            h=$(shasum -a 256 "$3" | awk '{ print $1 }')
        fi
        echo "/stub-cache/$h.json"
        ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$STUB_BIN/koto"

git_fix() {
    git -C "$FIX" "$@"
}

template() {
    # template <name> <version> <state>...
    local name="$1" version="$2"
    shift 2
    printf -- '---\nname: %s\nversion: "%s"\ndescription: fixture\n---\n\n' "$name" "$version"
    local s
    for s in "$@"; do
        printf '## %s\n\nDo the %s thing.\nThen stop.\n\n' "$s" "$s"
    done
}

# The fixture repository: one template per pinned skill (execute has two), a
# diagram that must not count as a template, and a SKILL.md with frontmatter.
git_fix init -q
git_fix config user.email test@example.com
git_fix config user.name test
for s in work-on scope deliver; do
    mkdir -p "$FIX/skills/$s/koto-templates"
    template "$s" 1.0 alpha beta > "$FIX/skills/$s/koto-templates/$s.md"
done
mkdir -p "$FIX/skills/execute/koto-templates" "$FIX/skills/other/koto-templates"
# execute.md names its child by a relative path, as the shipped one does, so
# verify-pin has to compile it with the other templates beside it.
template execute 1.0 alpha beta \
    | awk '{ print } $0 == "description: fixture" { print "default_template: ../../work-on/koto-templates/work-on.md" }' \
    > "$FIX/skills/execute/koto-templates/execute.md"
template execute-coordinated 1.0 gamma > "$FIX/skills/execute/koto-templates/execute-coordinated.md"
printf 'graph TD\n' > "$FIX/skills/execute/koto-templates/execute.mermaid.md"
template other 1.0 alpha > "$FIX/skills/other/koto-templates/other.md"
printf -- '---\nname: work-on\n---\n\n# Work on\n\n12345678\n' > "$FIX/skills/work-on/SKILL.md"
git_fix add -A
git_fix commit -q -m base
BASE=$(git_fix rev-parse HEAD)

# A second commit that changes one template and drops a state from another.
template scope 1.0 alpha beta delta > "$FIX/skills/scope/koto-templates/scope.md"
template deliver 1.0 alpha > "$FIX/skills/deliver/koto-templates/deliver.md"
git_fix commit -q -am second
SECOND=$(git_fix rev-parse HEAD)

# Builds a correct pin for $BASE under koto version 1.2.3.
make_pin() {
    local out="$1" entries="" p skill name blob hash tmp
    tmp="$TEST_DIR/extract.md"
    for p in skills/deliver/koto-templates/deliver.md \
             skills/execute/koto-templates/execute-coordinated.md \
             skills/execute/koto-templates/execute.md \
             skills/scope/koto-templates/scope.md \
             skills/work-on/koto-templates/work-on.md; do
        skill=${p#skills/}; skill=${skill%%/*}
        name=$(basename "$p" .md)
        blob=$(git_fix rev-parse "$BASE:$p")
        git_fix cat-file blob "$BASE:$p" > "$tmp"
        hash=$(sha256_of "$tmp")
        entries="$entries$(jq -n --arg s "$skill" --arg p "$p" --arg n "$name" --arg b "$blob" --arg h "$hash" \
            '{skill:$s, path:$p, declared_name:$n, declared_version:"1.0", git_blob:$b, koto_template_hash:$h}')"
    done
    printf '%s' "$entries" | jq -s --arg c "$BASE" '{pinned_commit:$c, koto_version:"1.2.3", templates:.}' > "$out"
}

GOOD_PIN="$TEST_DIR/pin.json"
make_pin "$GOOD_PIN"

# Runs the script inside the fixture repository with the stub koto first on
# PATH. Sets OUT (stdout), ERR (stderr) and STATUS.
run() {
    STATUS=0
    OUT=$(cd "$FIX" && PATH="$STUB_BIN:$PATH" STUB_KOTO_VERSION="${KV:-1.2.3}" "$SUT" "$@" 2>"$TEST_DIR/err") || STATUS=$?
    ERR=$(cat "$TEST_DIR/err")
}

# Writes a variant of the good pin, edited by a jq filter.
pin_with() {
    local out="$TEST_DIR/variant.json"
    jq "$1" "$GOOD_PIN" > "$out"
    printf '%s\n' "$out"
}

expect_pin_fails() {
    local name="$1" pin="$2"
    shift 2
    run verify-pin --pin "$pin"
    if [ "$STATUS" -ne 1 ]; then
        fail "$name" "expected exit 1, got $STATUS. stderr: $ERR"
        return
    fi
    local needle
    for needle in "$@"; do
        case "$ERR" in
            *"$needle"*) ;;
            *) fail "$name" "stderr lacks '$needle'. stderr: $ERR"; return ;;
        esac
    done
    pass "$name"
}

# -- verify-pin ---------------------------------------------------------------

run verify-pin --pin "$GOOD_PIN"
if [ "$STATUS" -eq 0 ] && ! printf '%s' "$ERR" | grep -q skipped; then
    pass "verify-pin: a correct pin passes, koto hashes compared"
else
    fail "verify-pin: a correct pin passes" "status $STATUS, stderr: $ERR"
fi

KV=0.0.1 run verify-pin --pin "$GOOD_PIN"
case "$STATUS:$ERR" in
    0:*"koto hash comparison skipped: installed koto 0.0.1, pinned 1.2.3"*)
        pass "verify-pin: another koto version skips the hash comparison" ;;
    *) fail "verify-pin: another koto version skips the hash comparison" "status $STATUS, stderr: $ERR" ;;
esac

# A different koto skips the hash comparison but still checks the blobs.
KV=0.0.1 run verify-pin --pin "$(pin_with '.templates[0].git_blob = "0000000000000000000000000000000000000000"')"
case "$STATUS:$ERR" in
    1:*"skills/deliver/koto-templates/deliver.md: git_blob"*)
        pass "verify-pin: blob checks still run when the hash comparison is skipped" ;;
    *) fail "verify-pin: blob checks still run when the hash comparison is skipped" "status $STATUS, stderr: $ERR" ;;
esac

# No koto on PATH at all: point PATH at a directory with only git and jq.
NOKOTO="$TEST_DIR/nokoto"
mkdir -p "$NOKOTO"
for tool in git jq awk sed sort comm grep basename mktemp rm cat tr wc dirname env bash; do
    t=$(command -v "$tool" 2>/dev/null) && ln -sf "$t" "$NOKOTO/$tool"
done
STATUS=0
ERR=$(cd "$FIX" && PATH="$NOKOTO" "$SUT" verify-pin --pin "$GOOD_PIN" 2>&1 >/dev/null) || STATUS=$?
case "$STATUS:$ERR" in
    0:*"koto hash comparison skipped: koto is not installed"*)
        pass "verify-pin: no koto skips the hash comparison" ;;
    *) fail "verify-pin: no koto skips the hash comparison" "status $STATUS, stderr: $ERR" ;;
esac

expect_pin_fails "verify-pin: an altered git blob is named" \
    "$(pin_with '.templates[1].git_blob = "1111111111111111111111111111111111111111"')" \
    "entry skills/execute/koto-templates/execute-coordinated.md: git_blob 1111"

expect_pin_fails "verify-pin: two altered entries are both named" \
    "$(pin_with '.templates[0].koto_template_hash = "bad" | .templates[3].git_blob = "2222222222222222222222222222222222222222"')" \
    "entry skills/deliver/koto-templates/deliver.md: koto_template_hash bad" \
    "entry skills/scope/koto-templates/scope.md: git_blob 2222" \
    "2 mismatch(es)"

expect_pin_fails "verify-pin: an entry under the wrong skill is named" \
    "$(pin_with '.templates[2].skill = "scope"')" \
    "entry skills/execute/koto-templates/execute.md: skill 'scope' does not match its path"

expect_pin_fails "verify-pin: an entry the commit lacks is named" \
    "$(pin_with '.templates += [.templates[0] | .path = "skills/deliver/koto-templates/ghost.md"]')" \
    "entry skills/deliver/koto-templates/ghost.md: no such template"

expect_pin_fails "verify-pin: a missing entry is named" \
    "$(pin_with 'del(.templates[4])')" \
    "missing entry for skills/work-on/koto-templates/work-on.md"

expect_pin_fails "verify-pin: a missing field is named" \
    "$(pin_with 'del(.templates[3].declared_version)')" \
    "entry skills/scope/koto-templates/scope.md: missing field declared_version"

expect_pin_fails "verify-pin: a mismatched declared name is named" \
    "$(pin_with '.templates[3].declared_name = "scoop"')" \
    "declared_name 'scoop', but the template says 'scope'"

expect_pin_fails "verify-pin: a mismatched declared version is named" \
    "$(pin_with '.templates[3].declared_version = "2.0"')" \
    "declared_version '2.0', but the template says '1.0'"

BAD_JSON="$TEST_DIR/bad.json"
printf '{ not json' > "$BAD_JSON"
expect_pin_fails "verify-pin: an unparseable pin fails" "$BAD_JSON" "does not parse"

WRONG_COMMIT_PIN="$TEST_DIR/wrong-commit.json"
jq --arg c "$SECOND" '.pinned_commit = $c' "$GOOD_PIN" > "$WRONG_COMMIT_PIN"
expect_pin_fails "verify-pin: a pin checked against the wrong commit fails" \
    "$WRONG_COMMIT_PIN" \
    "skills/deliver/koto-templates/deliver.md: git_blob" \
    "skills/scope/koto-templates/scope.md: git_blob"

expect_pin_fails "verify-pin: an unknown pinned commit fails" \
    "$(pin_with '.pinned_commit = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"')" \
    "is not a commit here"

# -- count --------------------------------------------------------------------

MANIFEST="$TEST_DIR/manifest.tsv"
{
    printf '# fixture manifest\n'
    printf 'profile\tpath\tselector\tweight\tnote\n'
    printf 'p1\tskills/work-on/SKILL.md\tbody\t1\tresident\n'
    printf 'p1\tskills/work-on/koto-templates/work-on.md\tstate:alpha\t2\tvisits\n'
    # The same span again in the same profile: raw counts it once.
    printf 'p1\tskills/work-on/koto-templates/work-on.md\tstate:alpha\t1\treread\n'
    printf '\n'
    printf 'p2\tskills/work-on/SKILL.md\tfile\t0.5\tconditional\n'
} > "$MANIFEST"

# Expected figures, computed independently of the script.
fm_body=$(printf '\n# Work on\n\n12345678\n' | wc -c | tr -d ' ')
state_alpha=$(printf '## alpha\n\nDo the alpha thing.\nThen stop.\n' | wc -c | tr -d ' ')
whole=$(git_fix cat-file blob "$BASE:skills/work-on/SKILL.md" | wc -c | tr -d ' ')
exp_p1_raw=$(awk -v a="$fm_body" -v b="$state_alpha" 'BEGIN { printf "%d", (a + b) / 4 + 0.5 }')
exp_p1_w=$(awk -v a="$fm_body" -v b="$state_alpha" 'BEGIN { printf "%d", (a + 3 * b) / 4 + 0.5 }')
exp_p2_raw=$(awk -v a="$whole" 'BEGIN { printf "%d", a / 4 + 0.5 }')
exp_p2_w=$(awk -v a="$whole" 'BEGIN { printf "%d", a * 0.5 / 4 + 0.5 }')
EXPECTED=$(printf 'p1\t%s\t%s\np2\t%s\t%s' "$exp_p1_raw" "$exp_p1_w" "$exp_p2_raw" "$exp_p2_w")

git_fix status --porcelain > "$TEST_DIR/status-before"
# Leave an untracked file and a local edit in the tree: count must ignore both.
printf 'local edit\n' >> "$FIX/skills/work-on/SKILL.md"
printf 'scratch\n' > "$FIX/scratch.txt"
git_fix status --porcelain > "$TEST_DIR/status-before"
run count "$BASE" --manifest "$MANIFEST"
git_fix status --porcelain > "$TEST_DIR/status-after"
if [ "$STATUS" -eq 0 ] && [ "$OUT" = "$EXPECTED" ]; then
    pass "count: raw and weighted figures per profile, read from git objects"
else
    fail "count: raw and weighted figures per profile" "status $STATUS, got [$OUT], expected [$EXPECTED], stderr: $ERR"
fi
if cmp -s "$TEST_DIR/status-before" "$TEST_DIR/status-after"; then
    pass "count: the working tree is left as it was"
else
    fail "count: the working tree is left as it was" "$(diff "$TEST_DIR/status-before" "$TEST_DIR/status-after" || true)"
fi
git_fix checkout -q -- skills/work-on/SKILL.md
rm -f "$FIX/scratch.txt"

run count "$BASE" --manifest "$MANIFEST"
FIRST="$OUT"
run count "$BASE" --manifest "$MANIFEST"
if [ "$OUT" = "$FIRST" ]; then
    pass "count: repeated runs give identical figures"
else
    fail "count: repeated runs give identical figures" "[$FIRST] vs [$OUT]"
fi

expect_count_fails() {
    local name="$1" needle="$2"
    shift 2
    run "$@"
    if [ "$STATUS" -ne 2 ]; then
        fail "$name" "expected exit 2, got $STATUS. stdout: $OUT"
        return
    fi
    if [ -n "$OUT" ]; then
        fail "$name" "expected no stdout, got [$OUT]"
        return
    fi
    case "$ERR" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name" "stderr lacks '$needle'. stderr: $ERR" ;;
    esac
}

expect_count_fails "count: a commit that doesn't exist" "no such commit: nosuchref" \
    count nosuchref --manifest "$MANIFEST"
expect_count_fails "count: no commit" "count requires a commit" \
    count --manifest "$MANIFEST"
expect_count_fails "count: a commit argument starting with -" "starts with '-'" \
    count -rf --manifest "$MANIFEST"
expect_count_fails "count: a second positional argument" "unexpected argument: extra" \
    count "$BASE" extra --manifest "$MANIFEST"

MISSING_PATH="$TEST_DIR/missing-path.tsv"
{ printf 'profile\tpath\tselector\tweight\tnote\n'; printf 'p\tskills/nope/SKILL.md\tfile\t1\tx\n'; } > "$MISSING_PATH"
expect_count_fails "count: a path missing at the commit" "skills/nope/SKILL.md does not exist" \
    count "$BASE" --manifest "$MISSING_PATH"

# deliver.md loses its beta state in the second commit.
MISSING_STATE="$TEST_DIR/missing-state.tsv"
{ printf 'profile\tpath\tselector\tweight\tnote\n'; printf 'p\tskills/deliver/koto-templates/deliver.md\tstate:beta\t1\tx\n'; } > "$MISSING_STATE"
run count "$BASE" --manifest "$MISSING_STATE"
if [ "$STATUS" -eq 0 ]; then
    pass "count: a state present at one commit counts there"
else
    fail "count: a state present at one commit counts there" "status $STATUS, stderr: $ERR"
fi
expect_count_fails "count: a state missing at the commit" "state 'beta' not found in skills/deliver/koto-templates/deliver.md" \
    count "$SECOND" --manifest "$MISSING_STATE"

BAD_SELECTOR="$TEST_DIR/bad-selector.tsv"
{ printf 'profile\tpath\tselector\tweight\tnote\n'; printf 'p\tskills/work-on/SKILL.md\tlines:1-3\t1\tx\n'; } > "$BAD_SELECTOR"
expect_count_fails "count: an unknown selector" "unknown selector 'lines:1-3'" \
    count "$BASE" --manifest "$BAD_SELECTOR"

BAD_WEIGHT="$TEST_DIR/bad-weight.tsv"
{ printf 'profile\tpath\tselector\tweight\tnote\n'; printf 'p\tskills/work-on/SKILL.md\tfile\tlots\tx\n'; } > "$BAD_WEIGHT"
expect_count_fails "count: a non-numeric weight" "bad weight 'lots'" \
    count "$BASE" --manifest "$BAD_WEIGHT"

# -- the committed baseline -----------------------------------------------------

# Public-content scan of the committed baseline directory. Repository
# references are checked against the organization's public repositories rather
# than a list of private names, so no private name is written anywhere.
public_content_violations() {
    local dir="$1"
    {
        grep -rnoE 'tsukumogami/[A-Za-z0-9._-]+' "$dir" 2>/dev/null \
            | grep -vE 'tsukumogami/(shirabe|koto|tsuku|niwa|dot-niwa|\.github)([^A-Za-z0-9._-]|$)' || true
        grep -rnE '(/home/|/Users/)[A-Za-z]|~/\.' "$dir" 2>/dev/null || true
        grep -rnE 'session_[A-Za-z0-9]{6,}|[a-z_]+-[0-9a-f]{8}([^0-9a-f]|$)|jobs/[0-9a-f]{8}' "$dir" 2>/dev/null || true
    }
}

SCAN_FIX="$TEST_DIR/scan"
mkdir -p "$SCAN_FIX"
for sample in 'see tsukumogami/secret-plans for details' \
              'written from /home/someone/dev' \
              'written from /Users/someone/dev' \
              'cached under ~/.cache' \
              'logged as session_ABCdef123' \
              'ran in worker_pin-0a1b2c3d' \
              'output in jobs/0a1b2c3d/tmp'; do
    printf '%s\n' "$sample" > "$SCAN_FIX/sample.md"
    if [ -n "$(public_content_violations "$SCAN_FIX")" ]; then
        pass "public-content scan catches: $sample"
    else
        fail "public-content scan catches: $sample" "no violation reported"
    fi
done
printf 'tsukumogami/shirabe and tsukumogami/koto are public; sha e592501.\n' > "$SCAN_FIX/sample.md"
if [ -z "$(public_content_violations "$SCAN_FIX")" ]; then
    pass "public-content scan allows public repositories and short shas"
else
    fail "public-content scan allows public repositories" "$(public_content_violations "$SCAN_FIX")"
fi

if [ -d "$REPO_ROOT/docs/measurement/offload-baseline" ]; then
    found=$(public_content_violations "$REPO_ROOT/docs/measurement/offload-baseline")
    if [ -z "$found" ]; then
        pass "public-content scan: the committed baseline directory is clean"
    else
        fail "public-content scan: the committed baseline directory is clean" "$found"
    fi
fi

echo "" >&2
echo "offload-baseline_test: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]
