#!/usr/bin/env bash
# Tests for the settled-branch read carried by skills/execute/koto-templates/execute.md.
#
# The orchestrator reads the branch it settled on out of koto context twice: once
# when it spawns children and once on the dedup re-submit. Both reads decide which
# branch every child commits to, and neither is exercised by anything else in the
# repo, so this test pulls the live shell out of the template and runs it against a
# koto shim. It cannot drift from what ships.
#
# The exit codes below were measured against the installed koto binary:
#
#   0    a stored value, printed clean on stdout
#   3    key or session absent -- an error JSON printed on STDOUT, stderr empty
#   2    clap usage error -- message on stderr, stdout empty
#   127  binary absent -- the shell's own "command not found" on stderr
#
# Exit 3 is why `2>/dev/null || echo "impl/$SLUG"` was never a fix: the redirect
# discards an empty stream and koto's blob lands inside the variable next to the
# fallback. The assertions below therefore test the value and the assignment, not
# the presence or absence of a redirect. A test that only checked "the 2>/dev/null
# is gone" would pass with the defect fully intact.
#
# Usage: bash scripts/settled-branch-read_test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/skills/execute/koto-templates/execute.md"

PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Pulling the live blocks out of the template
# ---------------------------------------------------------------------------

# Each read starts at `SETTLED_ERR=$(mktemp)` and ends at the `esac` closing the
# branch-name sanitizer, which is the second `esac` in the block. Keying on the
# source lines rather than line numbers means an edit above the site does not
# break this test, while an edit to the read itself does -- which is the point.
extract_blocks() {
    awk '
        /^SETTLED_ERR=\$\(mktemp\)$/ { collecting = 1; esacs = 0 }
        collecting { print }
        collecting && /^esac$/ {
            esacs++
            if (esacs == 2) { collecting = 0; print "---BLOCK-END---" }
        }
    ' "$TEMPLATE"
}

RAW=$(extract_blocks)
BLOCK_COUNT=$(printf '%s\n' "$RAW" | grep -c -- '---BLOCK-END---')

if [[ "$BLOCK_COUNT" -ne 2 ]]; then
    bad "expected 2 settled-branch reads in $TEMPLATE, found $BLOCK_COUNT"
    echo "       Either a call site was removed, or the read no longer opens with"
    echo "       SETTLED_ERR=\$(mktemp) and close with the sanitizer's esac."
    echo
    echo "Passed: $PASS  Failed: $FAIL"
    exit 1
fi
ok "both call sites carry the exit-status branch"

# Split into per-site files with {{SESSION_NAME}} resolved.
mkdir -p "$WORK/blocks"
printf '%s\n' "$RAW" | awk -v dir="$WORK/blocks" '
    BEGIN { n = 1 }
    /^---BLOCK-END---$/ { close(dir "/site-" n ".sh"); n++; next }
    { print > (dir "/site-" n ".sh") }
'

# ---------------------------------------------------------------------------
# The koto shim
# ---------------------------------------------------------------------------
#
# Follows skills/work-on/evals/fixtures/bin/koto: an executable on PATH that reads
# a mode out of the environment and reproduces one measured koto behaviour,
# including the 127 arm, which prints the shell's own message and exits 127.

mkdir -p "$WORK/bin"
cat > "$WORK/bin/koto" <<'SHIM'
#!/usr/bin/env bash
case "${KOTO_MODE:-}" in
  ok)
    echo "impl/adopted-branch"
    exit 0
    ;;
  absent)
    # Measured: the error JSON goes to STDOUT, and stderr stays empty.
    echo '{"command":"context get","error":"failed to read context key '"'"'settled_branch'"'"' for session '"'"'s'"'"': /home/u/.koto/sessions/s/ctx/settled_branch"}'
    exit 3
    ;;
  usage)
    echo "error: the following required arguments were not provided:" >&2
    echo "  <KEY>" >&2
    echo "" >&2
    echo "Usage: koto context get <SESSION> <KEY>" >&2
    exit 2
    ;;
  missing)
    echo "bash: koto: command not found" >&2
    exit 127
    ;;
esac
echo "koto shim: KOTO_MODE unset" >&2
exit 1
SHIM
chmod +x "$WORK/bin/koto"

# ---------------------------------------------------------------------------
# Running one site under one mode
# ---------------------------------------------------------------------------
#
# The probe is an EXIT trap, so it reports on every path -- including the early
# `exit` the failure arms take. "SETTLED_BRANCH was never assigned" is then a
# fact about the run, not an inference from the absence of a later echo.

run_site() {
    local site="$1" mode="$2"
    local script="$WORK/run.sh"

    {
        echo '#!/usr/bin/env bash'
        echo 'PLAN_SLUG=test-slug'
        echo 'trap '\''printf "ASSIGNED=%s\nVALUE=%s\n" "${SETTLED_BRANCH+yes}" "${SETTLED_BRANCH-}" >&3'\'' EXIT'
        sed 's/{{SESSION_NAME}}/fixture-session/g' "$WORK/blocks/site-$site.sh"
    } > "$script"

    KOTO_MODE="$mode" PATH="$WORK/bin:$PATH" \
        bash "$script" 3>"$WORK/probe" >"$WORK/out" 2>"$WORK/err"
    RC=$?
    ASSIGNED=$(grep '^ASSIGNED=' "$WORK/probe" | tail -1 | cut -d= -f2-)
    VALUE=$(grep '^VALUE=' "$WORK/probe" | tail -1 | cut -d= -f2-)
    COMBINED=$(cat "$WORK/out" "$WORK/err")
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$label"
    else
        bad "$label (expected [$expected], got [$actual])"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$label"
    else
        bad "$label (no [$needle] in output)"
        echo "       output was: $haystack"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$label"
    else
        bad "$label (unexpected [$needle] in output)"
    fi
}

# ---------------------------------------------------------------------------
# Assertions, run against both sites
# ---------------------------------------------------------------------------

for site in 1 2; do
    label="site $site"

    # Exit 0: the stored value reaches SETTLED_BRANCH untouched.
    run_site "$site" ok
    assert_eq "[$label] exit 0 exits clean" 0 "$RC"
    assert_eq "[$label] exit 0 assigns SETTLED_BRANCH" yes "$ASSIGNED"
    assert_eq "[$label] exit 0 keeps the stored branch" "impl/adopted-branch" "$VALUE"

    # Exit 3: the fresh path. The fallback must be byte-for-byte impl/<slug>,
    # matching what the R7 comment above the line promises, with none of koto's
    # error JSON spliced in.
    run_site "$site" absent
    assert_eq "[$label] exit 3 exits clean" 0 "$RC"
    assert_eq "[$label] exit 3 assigns SETTLED_BRANCH" yes "$ASSIGNED"
    assert_eq "[$label] exit 3 falls back byte-for-byte" "impl/test-slug" "$VALUE"
    assert_not_contains "[$label] exit 3 splices no error blob into the value" \
        "failed to read context key" "$VALUE"

    # Exit 2: a usage error is a surface failure. SETTLED_BRANCH is never
    # assigned, so nothing fabricated flows onward to the children.
    run_site "$site" usage
    assert_eq "[$label] exit 2 stops the step" 2 "$RC"
    assert_eq "[$label] exit 2 never assigns SETTLED_BRANCH" "" "$ASSIGNED"
    assert_contains "[$label] exit 2 surfaces koto's diagnostic" \
        "required arguments were not provided" "$COMBINED"
    assert_not_contains "[$label] exit 2 fabricates no branch name" \
        "impl/test-slug" "$COMBINED"

    # Exit 127: a missing binary is a surface failure too, and koto's own
    # message has to reach the agent rather than being swallowed.
    run_site "$site" missing
    assert_eq "[$label] exit 127 stops the step" 127 "$RC"
    assert_eq "[$label] exit 127 never assigns SETTLED_BRANCH" "" "$ASSIGNED"
    assert_contains "[$label] exit 127 surfaces koto's own message" \
        "koto: command not found" "$COMBINED"
    assert_not_contains "[$label] exit 127 fabricates no branch name" \
        "impl/test-slug" "$COMBINED"
done

# ---------------------------------------------------------------------------
# The sanitizer stays, as defence in depth
# ---------------------------------------------------------------------------

# Matches the read-side sanitizer only. The write-side guard above
# `koto context add` shares the character class but refuses rather than falling
# back, and belongs to a different call site.
SANITIZERS=$(grep -c '\*\[!A-Za-z0-9\._/-\]\*|"") SETTLED_BRANCH="impl/\$PLAN_SLUG"' "$TEMPLATE")
assert_eq "the branch-name sanitizer survives at both sites" 2 "$SANITIZERS"

# ---------------------------------------------------------------------------
# The defect shape is gone
# ---------------------------------------------------------------------------
#
# Last, and on its own, because it is the weakest assertion in the file: the
# redirect was never the mechanism, so its absence proves nothing by itself.
#
# It is anchored on the SETTLED_BRANCH assignment rather than on the redirect,
# and that is the whole of its precision. orchestrator_setup's recording block
# reads the key straight back through `RECORDED=$(koto context get ...
# 2>/dev/null)` to verify the write took, and there the redirect is fine: the
# string comparison on the next line, not the presence of an error message, is
# what decides. A pattern that only asked whether `koto context get
# settled_branch 2>/dev/null` appears anywhere would fail on that verifying read
# and say nothing about the two sites this file is actually about.

if grep -q 'SETTLED_BRANCH=\$(koto context get .* settled_branch 2>/dev/null' "$TEMPLATE"; then
    bad "the 2>/dev/null || echo shape is still present at a spawn_and_await read"
else
    ok "the inert 2>/dev/null || echo shape is gone from both spawn_and_await reads"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
