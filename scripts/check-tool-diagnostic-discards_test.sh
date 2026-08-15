#!/usr/bin/env bash
# check-tool-diagnostic-discards_test.sh -- Test harness for
# check-tool-diagnostic-discards.sh
#
# The case that matters most is the negative fixture: a site that discards a
# declared tool's diagnostics and is absent from the enumeration must fail the
# scan. That is the whole control -- `shirabe#279` was a site whose author
# decided at the call site that the fallback was not a masked failure, and was
# wrong. If an unenumerated discard can pass, nothing here does anything.
#
# The second class of case is the false positives the design named in advance:
# `koto` matching a directory name, and the unread-variable arm firing on a .md
# template whose consumer is an agent reading prose.
#
# Usage: scripts/check-tool-diagnostic-discards_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-tool-diagnostic-discards.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

WORK=$(mktemp -d); TMPS+=("$WORK")
TAB=$'\t'

# --- fixture builders -------------------------------------------------------

# new_fixture NAME -- a fixture repo root at $WORK/NAME holding skills/NAME/.
# Paths reported by the scan are relative to that root, so an enumeration
# record names `skills/NAME/<file>` exactly as it would in the real tree.
#
# The enumeration lives OUTSIDE the fixture root. Inside it, the scan would
# find the record block's own command text and charge the enumeration as a
# live site -- which is exactly why the real file lives in references/ and the
# real scan targets skills/.
FIXTURE=""
FNAME=""
ENUM=""
new_fixture() {
  FNAME="$1"
  FIXTURE="$WORK/$FNAME"
  ENUM="$WORK/$FNAME.enum.md"
  mkdir -p "$FIXTURE/skills/$FNAME"
  : > "$FIXTURE/skills/$FNAME/requires.tsv"
  : > "$ENUM"
}

# add_requires TOOL -- declare a tool in the fixture's requires.tsv.
add_requires() {
  printf '%s\t-\t-\talways\n' "$1" >> "$FIXTURE/skills/$FNAME/requires.tsv"
}

# add_file BASENAME LINE... -- a scanned file under skills/NAME/.
add_file() {
  local base="$1"; shift
  local dir
  dir="$(dirname "$FIXTURE/skills/$FNAME/$base")"
  mkdir -p "$dir"
  printf '%s\n' "$@" > "$FIXTURE/skills/$FNAME/$base"
}

# enum_open / enum_record / enum_close -- write the ```tsv record block.
enum_open() {
  {
    echo "# Fixture enumeration"
    echo
    echo '```tsv'
    echo "#schema${TAB}tool-diagnostic-discards/v1"
  } > "$ENUM"
}
enum_record() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$ENUM"
}
enum_raw() { printf '%s\n' "$1" >> "$ENUM"; }
enum_close() { echo '```' >> "$ENUM"; }

run_check() {
  bash "$CHECK" --enumeration "$ENUM" "$FIXTURE"
}

assert_accepts() {
  local label="$1" out rc
  out=$(run_check 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label"
  else
    fail "$label -- expected exit 0, got $rc: $out"
  fi
}

assert_rejects() {
  local label="$1" needle="$2" out rc
  out=$(run_check 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$label -- expected exit 1, but the check passed"
  elif [ "$rc" -ne 1 ]; then
    fail "$label -- expected exit 1, got $rc: $out"
  else
    case "$out" in
      *"$needle"*) pass "$label" ;;
      *) fail "$label -- exited 1 but did not say '$needle'; got: $out" ;;
    esac
  fi
}

WHY="Failure is the expected outcome and the fallback does equivalent work."
CITE="shirabe#279"

# --- Case 1: the tree as it stands is green ---------------------------------
# The check is only useful if it holds against the repo it guards, and against
# the enumeration seeded for that repo.
out=$(bash "$CHECK" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "current tree passes ($out)"
else
  fail "current tree should pass; got: $out"
fi

# --- Case 2 (NEGATIVE FIXTURE): a discard absent from the enumeration -------
# The control. Without this the file is decoration.
new_fixture unenumerated
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open; enum_close
assert_rejects "an unenumerated discarding site is rejected" "is not enumerated"

# --- Case 3: the same site, enumerated --------------------------------------
new_fixture enumerated
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open
enum_record 'skills/enumerated/probe.sh' 'gh issue view 5 2>/dev/null || true' 1 1 "$WHY" "$CITE"
enum_close
assert_accepts "the same site with a record is accepted"

# --- Case 4: a record matching nothing ---------------------------------------
# The other direction. Without it the list rots into a permanent allowlist.
new_fixture stale
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'echo nothing here'
enum_open
enum_record 'skills/stale/probe.sh' 'gh issue view 5 2>/dev/null || true' 1 1 "$WHY" "$CITE"
enum_close
assert_rejects "a stale record is rejected" "matches no live site"

# --- Case 5: the count field catches a third copy ---------------------------
new_fixture count-drift
add_requires git
add_file 'probe.sh' '#!/usr/bin/env bash' \
  '    git add a 2>/dev/null || true' \
  '    git add a 2>/dev/null || true' \
  '    git add a 2>/dev/null || true'
enum_open
enum_record 'skills/count-drift/probe.sh' 'git add a 2>/dev/null || true' 2 128 "$WHY" "$CITE"
enum_close
assert_rejects "a third byte-identical copy is rejected" "enumerated 2 time(s), found 3"

# --- Case 6: reindentation does not break the key ---------------------------
# The key is the trimmed line, so moving a site into a deeper block is not a
# re-adjudication.
new_fixture reindent
add_requires git
add_file 'probe.sh' '#!/usr/bin/env bash' 'if true; then' '        git add a 2>/dev/null || true' 'fi'
enum_open
enum_record 'skills/reindent/probe.sh' 'git add a 2>/dev/null || true' 1 128 "$WHY" "$CITE"
enum_close
assert_accepts "reindenting an enumerated site keeps the exemption"

# --- Case 7: editing the command revokes the exemption ----------------------
# Changing what the command does forces it back through review.
new_fixture edited
add_requires git
add_file 'probe.sh' '#!/usr/bin/env bash' 'git add -A 2>/dev/null || true'
enum_open
enum_record 'skills/edited/probe.sh' 'git add a 2>/dev/null || true' 1 128 "$WHY" "$CITE"
enum_close
assert_rejects "an edited command loses its exemption" "is not enumerated"

# --- Case 8: 'koto' in a directory name is not a koto call site -------------
# skills/work-on/koto-templates/work-on.md:441 is `go test ./... 2>/dev/null`.
# Charging it to `koto` because the directory is named koto-templates/ is the
# false positive the enumeration guarantees will recur, since the enumeration
# must itself cover koto-templates/.
new_fixture koto-dirname
add_requires koto
add_file 'koto-templates/work-on.md' 'Run the suite:' '        command: "[ ! -f go.mod ] || go test ./... 2>/dev/null"'
enum_open; enum_close
assert_accepts "'go test ./... 2>/dev/null' under koto-templates/ is not charged to koto"

# --- Case 9: a real koto call in the same directory IS charged --------------
# Case 8 must not be passing because the directory is skipped.
new_fixture koto-real
add_requires koto
add_file 'koto-templates/work-on.md' 'Read the key:' 'koto context get sess key 2>/dev/null || true'
enum_open; enum_close
assert_rejects "a real koto call under koto-templates/ is charged" "is not enumerated"

# --- Case 10: the fourth redirect shape ------------------------------------
# `>/dev/null 2>&1` is not in the acceptance criteria's three shapes, and it
# discards stderr just as completely. Six live sites use it.
new_fixture fourth-shape
add_requires jq
add_file 'probe.sh' '#!/usr/bin/env bash' 'if ! echo x | jq -e . >/dev/null 2>&1; then exit 1; fi'
enum_open; enum_close
assert_rejects "'>/dev/null 2>&1' is in scope" "is not enumerated"

# --- Case 11: the '&>/dev/null' and '2>&1 >/dev/null' shapes ----------------
new_fixture other-shapes
add_requires git
add_file 'a.sh' '#!/usr/bin/env bash' 'git status &>/dev/null || true'
add_file 'b.sh' '#!/usr/bin/env bash' 'git status 2>&1 >/dev/null || true'
enum_open
enum_record 'skills/other-shapes/a.sh' 'git status &>/dev/null || true' 1 128 "$WHY" "$CITE"
enum_close
assert_rejects "'2>&1 >/dev/null' is in scope too" "skills/other-shapes/b.sh"

# --- Case 12: a bare '>/dev/null' is not in scope ---------------------------
# Only stdout goes; the diagnostic still reaches the reader.
new_fixture stdout-only
add_requires git
add_file 'probe.sh' '#!/usr/bin/env bash' 'git status >/dev/null'
enum_open; enum_close
assert_accepts "a bare '>/dev/null' with stderr intact is not in scope"

# --- Case 13: the 'command -v' carve-out ------------------------------------
# Measured: zero bytes across both streams, exit 1, the declared tool never
# executed. Eight live sites, all of which already test the status.
new_fixture command-v
add_requires jq
add_requires shirabe
add_file 'probe.sh' '#!/usr/bin/env bash' \
  'if ! command -v jq &>/dev/null; then exit 1; fi' \
  'if command -v shirabe >/dev/null 2>&1; then echo yes; fi'
enum_open; enum_close
assert_accepts "'command -v <tool>' sites are carved out"

# --- Case 14: a probe-then-call line still counts ---------------------------
# The carve-out removes the `command -v <word>` text, not the whole line.
new_fixture command-v-plus
add_requires jq
add_file 'probe.sh' '#!/usr/bin/env bash' 'command -v jq >/dev/null && jq -r . f 2>/dev/null'
enum_open; enum_close
assert_rejects "a line that probes and then calls the tool still counts" "is not enumerated"

# --- Case 15: the unread-variable arm, in a .sh file ------------------------
new_fixture unread-sh
add_requires jq
add_file 'probe.sh' '#!/usr/bin/env bash' 'RESULT=$(jq -r .status f.json)' 'echo done'
enum_open; enum_close
assert_rejects "a capture nobody reads is a finding in a .sh file" "is not enumerated"

# --- Case 16: the same shape in a .md template is NOT a finding -------------
# skills/execute/koto-templates/execute.md assigns CASCADE_STATUS and never
# references it in shell, but the prose around it instructs the agent to submit
# it. The consumer is an agent reading prose, so the arm is *.sh only.
new_fixture unread-md
add_requires jq
add_file 'koto-templates/execute.md' \
  'Submit the cascade status koto reports:' \
  'CASCADE_STATUS=$(echo "$RESULT" | jq -r ".cascade_status")' \
  'Submit `CASCADE_STATUS` as the state result.'
enum_open; enum_close
assert_accepts "an unread capture in a .md template is not a finding"

# --- Case 17: a capture that IS read is not a finding -----------------------
new_fixture read-var
add_requires jq
add_file 'probe.sh' '#!/usr/bin/env bash' 'RESULT=$(jq -r .status f.json)' 'echo "$RESULT"'
enum_open; enum_close
assert_accepts "a capture that is read is not a finding"

# --- Case 18: tool names come from the declarations -------------------------
# An undeclared tool is out of scope; declaring it brings the site in. A
# hardcoded list would freeze the scan's scope at the moment it was written.
new_fixture undeclared
add_requires git
add_file 'probe.sh' '#!/usr/bin/env bash' 'cargo build 2>/dev/null || true'
enum_open; enum_close
assert_accepts "a site for an undeclared tool is out of scope"

new_fixture now-declared
add_requires git
add_requires cargo
add_file 'probe.sh' '#!/usr/bin/env bash' 'cargo build 2>/dev/null || true'
enum_open; enum_close
assert_rejects "declaring the tool brings its site into scope" "is not enumerated"

# --- Case 19: test files are out of scope -----------------------------------
new_fixture test-files
add_requires gh
add_file 'probe_test.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
add_file 'evals/test-cli.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open; enum_close
assert_accepts "*_test.sh and evals/ are out of scope"

# --- Case 20: field six is mandatory and never '-' --------------------------
# A discard with no incident behind it is an unexamined discard.
new_fixture no-citation
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open
enum_record 'skills/no-citation/probe.sh' 'gh issue view 5 2>/dev/null || true' 1 1 "$WHY" '-'
enum_close
assert_rejects "a '-' citation is rejected" "citation field is empty or '-'"

# --- Case 21: the justification is mandatory too ----------------------------
new_fixture no-why
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open
enum_record 'skills/no-why/probe.sh' 'gh issue view 5 2>/dev/null || true' 1 1 '-' "$CITE"
enum_close
assert_rejects "a '-' justification is rejected" "justification field is empty"

# --- Case 22: a record with the wrong field count ---------------------------
new_fixture five-fields
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open
enum_raw "skills/five-fields/probe.sh${TAB}gh issue view 5 2>/dev/null || true${TAB}1${TAB}1${TAB}$WHY"
enum_close
assert_rejects "a five-field record is rejected" "expected 6"

# --- Case 23: a 'path:lineno' key is rejected -------------------------------
# Line numbers drift, and a stale key would go on silencing whichever site
# drifted into that number.
new_fixture lineno-key
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'gh issue view 5 2>/dev/null || true'
enum_open
enum_record 'skills/lineno-key/probe.sh:2' 'gh issue view 5 2>/dev/null || true' 1 1 "$WHY" "$CITE"
enum_close
assert_rejects "a path:lineno key is rejected" "carries a ':lineno' suffix"

# --- Case 24: a nonexistent path is a usage error ---------------------------
out=$(bash "$CHECK" "$WORK/does-not-exist" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "a nonexistent path exits 2 (usage), not 1 (finding)"
else
  fail "a nonexistent path should exit 2; got $rc: $out"
fi

# --- Case 25: an enumeration with no record block ---------------------------
new_fixture no-block
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'echo hi'
printf 'Just prose, no fence.\n' > "$ENUM"
out=$(run_check 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "an enumeration with no \`\`\`tsv block exits 2"
else
  fail "missing record block should exit 2; got $rc: $out"
fi

# --- Case 26: two record blocks is ambiguous, not a guess -------------------
new_fixture two-blocks
add_requires gh
add_file 'probe.sh' '#!/usr/bin/env bash' 'echo hi'
enum_open; enum_close
enum_open2() { { echo '```tsv'; echo '```'; } >> "$ENUM"; }
enum_open2
out=$(run_check 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "two \`\`\`tsv blocks exit 2 rather than guessing which is canonical"
else
  fail "two record blocks should exit 2; got $rc: $out"
fi

echo
echo "check-tool-diagnostic-discards_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
