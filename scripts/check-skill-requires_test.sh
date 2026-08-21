#!/usr/bin/env bash
# check-skill-requires_test.sh -- Test harness for check-skill-requires.sh
#
# The cases that carry the weight are the negative fixtures. A conformance scan
# that cannot be shown to fail is a scan nobody should trust to pass: one
# fixture per property -- a missing sidecar, a record whose tabs became spaces,
# a tool absent from the route table, each direction of the cadence split, a
# `when` value outside the allowlist, and a flag used at a real call site and
# left out of the declaration.
#
# The tab fixture is exercised twice. Once against the scan, and once against
# the real entry point with CLAUDE_PLUGIN_ROOT pointed at the fixture, because
# the load-time reader is the load-bearing copy: a reviewer whose plugin root
# points at a pull-request checkout loads that branch's declarations before CI
# has seen them.
#
# The second class of case is the extractor's scoping. Every one of these was a
# real false positive before the rule that kills it: eval scenarios quoting
# `gh --json` and cargo's `--release`, a shell comment describing a flag that is
# the script's own argument, a Markdown table row running the word `koto` past
# an unrelated `--auto`, and a pipeline whose `jq -r` sits downstream of a
# shirabe call.
#
# Usage: scripts/check-skill-requires_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-skill-requires.sh"
PREFLIGHT="$SCRIPT_DIR/skill-preflight.sh"
ROUTES="$REPO_ROOT/scripts/lib/tool-routes.tsv"
POLICY="$REPO_ROOT/references/tool-declaration-policy.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT
WORK=$(mktemp -d)

TAB=$(printf '\t')

# --- fixture builders -------------------------------------------------------

# new_fixture NAME -- a fixture tree at $WORK/NAME holding skills/NAME/, with
# the declaration opened on the schema line. Paths the scan prints are relative
# to $WORK/NAME, so an exemption reads `skills/NAME/<file>` exactly as a
# committed one does.
FIXTURE=""
FNAME=""
DECL=""
new_fixture() {
  FNAME="$1"
  FIXTURE="$WORK/$FNAME"
  DECL="$FIXTURE/skills/$FNAME/requires.tsv"
  mkdir -p "$FIXTURE/skills/$FNAME"
  printf '#schema\tskill-requires/v1\n' > "$DECL"
}

# record TOOL SUB FLAGS WHEN
record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$DECL"; }

# raw LINE... -- append verbatim, for the malformed cases.
raw() { printf '%s\n' "$@" >> "$DECL"; }

# exempt PATH TOOL FLAG REASON
exempt() { printf '#not-a-call-site\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$DECL"; }

# add_file RELPATH LINE... -- a file inside the fixture skill.
add_file() {
  local base="$1"; shift
  mkdir -p "$(dirname "$FIXTURE/skills/$FNAME/$base")"
  printf '%s\n' "$@" > "$FIXTURE/skills/$FNAME/$base"
}

OUT=""
RC=0
run_scan() {
  OUT=$("$@" 2>&1)
  RC=$?
}

scan_fixture() {
  run_scan bash "$CHECK" --skills "$FIXTURE/skills" --routes "$ROUTES" --policy "$POLICY"
}

expect_ok() {
  if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1 (exit $RC)"; echo "$OUT" | sed 's/^/    /'; fi
}

expect_fail() {
  local what="$1" needle="$2"
  if [ "$RC" -eq 0 ]; then
    fail "$what -- scan passed a fixture that must fail"
    return
  fi
  case "$OUT" in
    *"$needle"*) pass "$what" ;;
    *) fail "$what -- failed, but the message did not name '$needle'"; echo "$OUT" | sed 's/^/    /' ;;
  esac
}

# ===========================================================================
# The committed tree
# ===========================================================================

run_scan bash "$CHECK"
expect_ok "the committed declarations conform"

# ===========================================================================
# A clean fixture, exercising every accepted shape at once
# ===========================================================================

new_fixture clean
record koto  'context add'      --from-file  always
record shirabe validate         --format     always
record gh    -                  -            'mode:issues'
add_file SKILL.md \
  'Phase 1 runs `koto context add --from-file notes.md` and then' \
  'checks the doc with `shirabe validate --format json <doc>`.' \
  'In the issues mode the skill files them with gh.'
scan_fixture
expect_ok "a clean declaration passes"

# ===========================================================================
# 1. Missing sidecar
# ===========================================================================

new_fixture missing
rm -f "$DECL"
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a missing sidecar fails" "requires.tsv is missing"

# ===========================================================================
# 2. Tabs converted to spaces -- the scan half
# ===========================================================================

new_fixture spaces
raw 'koto context add --from-file always'
add_file SKILL.md 'Runs `koto context add --from-file notes.md`.'
scan_fixture
expect_fail "a record whose tabs became spaces fails the scan" "expected exactly 4 tab-separated fields"

# ===========================================================================
# 2b. Tabs converted to spaces -- the reader half, through the real entry point
# ===========================================================================
#
# The scan is the after-the-fact copy. This is the one a reviewer hits first.

PLUGROOT="$WORK/plugroot"
mkdir -p "$PLUGROOT/.claude-plugin" "$PLUGROOT/skills/fx-spaces"
printf '{"name":"fixture"}\n' > "$PLUGROOT/.claude-plugin/plugin.json"
cp -R "$REPO_ROOT/scripts" "$PLUGROOT/scripts"
printf '#schema\tskill-requires/v1\nkoto context add --from-file always\n' \
  > "$PLUGROOT/skills/fx-spaces/requires.tsv"

reader_out=$(CLAUDE_PLUGIN_ROOT="$PLUGROOT" bash "$PREFLIGHT" fx-spaces 2>&1)
reader_rc=$?
if [ "$reader_rc" -ne 0 ]; then
  fail "the reader must exit 0 whatever it finds (got $reader_rc)"
else
  case "$reader_out" in
    *"expected exactly 4 tab-separated fields"*)
      pass "the same fixture fails the reader at load, through the injected entry point" ;;
    *)
      fail "the reader accepted a space-separated record"
      echo "$reader_out" | sed 's/^/    /' ;;
  esac
fi

# ===========================================================================
# 3. A tool outside the route table
# ===========================================================================

new_fixture unrouted
record curl - - always
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a tool absent from tool-routes.tsv fails" "is not in scripts/lib/tool-routes.tsv"

# ===========================================================================
# 4. The cadence split, both directions
# ===========================================================================

new_fixture cadence-coupled
record shirabe - - always
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a coupled tool with no subcommand fails" "must name a subcommand"
case "$OUT" in
  *references/tool-declaration-policy.md*) pass "the cadence failure names the policy file" ;;
  *) fail "the cadence failure did not name references/tool-declaration-policy.md" ;;
esac

new_fixture cadence-independent
record gh 'pr create' --title always
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "an independent-cadence tool with a subcommand fails" "takes '-' in fields two and three"
case "$OUT" in
  *references/tool-declaration-policy.md*) pass "the independent-cadence failure names the policy file" ;;
  *) fail "the independent-cadence failure did not name references/tool-declaration-policy.md" ;;
esac

# ===========================================================================
# 5. A `when` value outside the allowlist
# ===========================================================================

new_fixture bad-when
record git - - sometimes
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a 'when' value outside the allowlist fails" "field 4 (when)"

new_fixture dash-when
record git - - -
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "'-' in the when field fails rather than becoming always-required" "field 4 (when)"

# ===========================================================================
# 6. An undeclared flag at a real call site
# ===========================================================================

new_fixture undeclared-flag
record shirabe validate --format always
add_file SKILL.md 'Phase 2 runs `shirabe validate --format json --visibility=private <doc>`.'
scan_fixture
expect_fail "a flag used at a call site and left undeclared fails" "'shirabe --visibility' is used in skills/undeclared-flag/SKILL.md"

new_fixture undeclared-flag-shell
record koto next - always
add_file scripts/run.sh '#!/usr/bin/env bash' 'koto next --with-data "$payload"'
scan_fixture
expect_fail "the same holds for a command line in a shell script" "'koto --with-data' is used"

# ===========================================================================
# 7. Mode names are an interface
# ===========================================================================

new_fixture bad-mode
record gh - - 'mode:nowhere-at-all'
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a mode name used nowhere in the skill fails" "appears nowhere in the skill's own files"

# ===========================================================================
# 8. The schema line
# ===========================================================================

new_fixture no-schema
printf 'gh\t-\t-\talways\n' > "$DECL"
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a declaration with no schema line fails" "first line is not"

new_fixture wrong-schema
printf '#schema\tskill-requires/v2\ngh\t-\t-\talways\n' > "$DECL"
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a declaration on a later schema fails loudly" "first line is not"

new_fixture late-schema
printf '# a comment\n#schema\tskill-requires/v1\ngh\t-\t-\talways\n' > "$DECL"
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "a schema line that is not first fails" "first line is not"

# ===========================================================================
# 9. Extractor scoping -- the false positives that were real
# ===========================================================================

new_fixture scope-evals
record shirabe validate - always
add_file SKILL.md 'Runs `shirabe validate <doc>`.'
add_file evals/evals.json '{"prompt": "run gh pr list --json number --jq .[0] and /scope --coordinated"}'
scan_fixture
expect_ok "evals/ is out of scope"

new_fixture scope-test-file
record shirabe validate - always
add_file SKILL.md 'Runs `shirabe validate <doc>`.'
add_file scripts/build_test.sh '#!/usr/bin/env bash' 'cargo build --release -p shirabe'
scan_fixture
expect_ok "*_test.sh is out of scope"

new_fixture scope-comment
record koto 'context add' - always
add_file scripts/extract.sh \
  '#!/usr/bin/env bash' \
  '# Stores content via koto context add (if --session), or writes wip/' \
  'koto context add "$key"'
scan_fixture
expect_ok "a shell comment is not a command line"

new_fixture scope-prose
record koto next - always
add_file SKILL.md \
  '| stale parent_orch | koto template. | review; --auto runs the hard path |' \
  'Runs `koto next`.'
scan_fixture
expect_ok "Markdown prose outside a code span is not a command line"

new_fixture scope-pipeline
record shirabe validate --format always
add_file scripts/run.sh '#!/usr/bin/env bash' 'shirabe validate --format json "$doc" | jq -r ".verdict"'
scan_fixture
expect_ok "a downstream pipeline stage is not charged to the tool upstream of it"

new_fixture scope-word-boundary
record koto next - always
add_file SKILL.md \
  'The template lives in `koto-templates/x.md` and the path' \
  '`skills/scope-word-boundary/koto/notes.md --whatever` is not a call.' \
  'Runs `koto next`.'
scan_fixture
expect_ok "a directory or path segment named koto is not an invocation"

new_fixture scope-fence
record shirabe validate --format always
add_file SKILL.md \
  'Run it:' \
  '```bash' \
  '# shirabe validate --mode=ready is what CI runs' \
  'shirabe validate --format json "$doc"' \
  '```'
scan_fixture
expect_ok "a comment inside a fenced block is not a command line"

new_fixture scope-fence-teeth
record shirabe validate - always
add_file SKILL.md \
  'Run it:' \
  '```bash' \
  'shirabe validate --format json "$doc"' \
  '```'
scan_fixture
expect_fail "a command line inside a fenced block is still extracted" "'shirabe --format' is used"

# ===========================================================================
# 10. Exemptions
# ===========================================================================

new_fixture exempt-ok
record shirabe validate - always
exempt 'skills/exempt-ok/SKILL.md' shirabe --pr-body 'Names what CI enforces on the PR body, not a call this skill makes.'
add_file SKILL.md 'That rule is what `shirabe validate --pr-body` enforces in CI.'
scan_fixture
expect_ok "an exemption suppresses the citation it names"

new_fixture exempt-stale
record shirabe validate - always
exempt 'skills/exempt-stale/SKILL.md' shirabe --pr-body 'The line this exempts is gone.'
add_file SKILL.md 'The citation was removed.'
scan_fixture
expect_fail "an exemption matching nothing fails as stale" "matches no extracted flag"

new_fixture exempt-cross-skill
record shirabe validate - always
exempt 'skills/somebody-else/SKILL.md' shirabe --pr-body 'Reaching across a skill boundary.'
add_file SKILL.md 'Nothing here.'
scan_fixture
expect_fail "an exemption cannot name a path outside its own skill" "outside skills/exempt-cross-skill/"

new_fixture exempt-no-reason
record shirabe validate - always
raw "#not-a-call-site${TAB}skills/exempt-no-reason/SKILL.md${TAB}shirabe${TAB}--pr-body${TAB}-"
add_file SKILL.md 'Cites `shirabe validate --pr-body`.'
scan_fixture
expect_fail "an exemption with no reason fails" "no reason"

new_fixture exempt-narrow
record shirabe validate - always
exempt 'skills/exempt-narrow/SKILL.md' shirabe --pr-body 'Only this file is exempt.'
add_file SKILL.md 'Cites `shirabe validate --pr-body`.'
add_file references/phase-1.md 'Runs `shirabe validate --pr-body <doc>` for real.'
scan_fixture
expect_fail "an exemption is scoped to the file it names" "references/phase-1.md"

# ===========================================================================
# 10b. Placeholders do not hide the flags that follow them
#
# These are instruction files, so `cmd <topic> --flag` is how a call site is
# normally written. Cutting the line at the `<` of `<topic>` -- which the
# redirect handling used to do -- discarded every flag after it, and the check
# passed one-sidedly: the flag was invisible with a placeholder before it and
# caught without one. It hid real call sites across this repository, not just
# one skill's.
#
# The pair is the assertion. Either case alone can be satisfied by a scan that
# is simply wrong in the other direction.
# ===========================================================================

new_fixture placeholder-before-flag
record koto init --template always
add_file SKILL.md 'Open the session:' '```bash' 'koto init scope-<topic> --undeclared-flag' '```'
scan_fixture
expect_fail "a flag after a <placeholder> is still extracted" "--undeclared-flag"

new_fixture placeholder-no-flag
record koto init --template always
add_file SKILL.md 'Open the session:' '```bash' 'koto init scope-<topic> --template x' '```'
scan_fixture
expect_ok "a declared flag after a <placeholder> does not become a finding"

# A genuine stdin redirect still ends the segment: what follows it is a
# filename, not a flag of this command.
new_fixture redirect-still-cuts
record koto context - always
add_file SKILL.md 'Write it:' '```bash' 'koto context add origin < --notaflag' '```'
scan_fixture
expect_ok "a real stdin redirect still ends the command segment"

# ===========================================================================
# 11. Usage errors
# ===========================================================================

run_scan bash "$CHECK" --skills "$WORK/nope/skills"
if [ "$RC" -eq 2 ]; then pass "a missing skills tree is a usage error"; else fail "a missing skills tree exited $RC, expected 2"; fi

printf '# no cadence table here\n' > "$WORK/empty-policy.md"
new_fixture policy-unreadable
record gh - - always
add_file SKILL.md 'Nothing here.'
run_scan bash "$CHECK" --skills "$FIXTURE/skills" --routes "$ROUTES" --policy "$WORK/empty-policy.md"
if [ "$RC" -eq 2 ]; then
  pass "a policy file with no cadence row is a usage error rather than a guess"
else
  fail "a policy file with no cadence row exited $RC, expected 2"
fi

# ===========================================================================

echo
echo "check-skill-requires_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
