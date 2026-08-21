#!/usr/bin/env bash
# hop-complete.sh --hop <brief|prd|design|plan> --topic <slug> [--root <dir>]
#
# Exit 0 when the hop is complete under either limb of PRD R7:
#   (a) the hop's own artifact is a regular, non-empty file at a canonical path;
#   (b) a surviving downstream document declares this hop under its `absorbed:`
#       frontmatter key, as a whole entry.
#
# Reads only the artifact tree. Never reads wip/scope_<topic>_state.md.
#
# Exit statuses are three, not two, and the third carries weight: 0 complete,
# 1 not complete, 2 CANNOT TELL. Anything that stops this script deciding --
# no validator, a validator that could not parse the document, an argument it
# does not recognise -- is a 2. A caller that folds 2 into 1 turns every such
# case into a confident "not done", which is the failure this file has been
# defeated by more than once.
#
# ADDING A HOP means editing five `case` statements: the hop allowlist, the
# canonical-path map, the schema map, the downstream-hop map, and the
# FC18-entry map. A missed one fails OPEN for that hop rather than erroring,
# so change them together and add a fixture for the new hop in each direction.
set -uo pipefail
HOP=""; TOPIC=""; ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --hop) HOP="$2"; shift 2 ;;
    --topic) TOPIC="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$HOP" ] || [ -z "$TOPIC" ]; then
  echo "usage: --hop <brief|prd|design|plan> --topic <slug> [--root <dir>]" >&2
  exit 2
fi
# The slug is validated at Phase 0 and re-validated on resume; re-assert it here
# because this value composes every path below.
case "$TOPIC" in
  *[!a-z0-9-]*|"") echo "invalid topic slug" >&2; exit 2 ;;
esac

# Both limbs answer to the validator. Skipping the check when the binary is
# absent would silently degrade this predicate to bare existence, which four
# `cp` commands defeat -- so refuse instead of skipping, and let the environment
# be the thing that gets fixed.
if ! command -v shirabe >/dev/null 2>&1; then
  echo "cannot decide hop completion: shirabe is not on PATH" >&2
  exit 2
fi

# Structure only, deliberately narrower than a whole-document validation.
# R6 resolves a document's `upstream:` against the filesystem and against git,
# so whole-document `clean` would couple this hop's completion to the presence
# and tracking of a *different* document -- and would refuse a legitimate fold
# whose survivor names an upstream that was absorbed away. FC01, FC03 and FC04
# are the checks that answer the question this limb actually asks: is the file
# at this path a well-formed artifact of its type.
# A validator that reaches a verdict answers this limb's question, either way.
# A validator that reaches no verdict -- a check renamed out from under us, a
# broken install, an argument this build does not accept -- has answered
# nothing, and calling that "not clean" would make every fold in the repository
# uncreditable while the gate went on printing a confident "incomplete".
# Discarding stderr is precisely what would make those two indistinguishable,
# so the diagnostic is kept and the no-verdict case exits 2 (cannot tell)
# rather than 1 (not done) -- the status a missing binary already gets.
VALIDATOR_OUT=""
verdict_is() {
  printf '%s' "$VALIDATOR_OUT" | grep -q "\"outcome\": *\"$1\""
}

# The validator reports one of five outcome labels. Three -- clean, incomplete,
# violations -- are verdicts about the document, and answer this limb's question
# either way. The other two are not: `tool-error` and `io` are the validator
# saying it never examined the document at all. An unreadable file returns
# `"outcome": "io"` inside `"outcome": "tool-error"` JSON with a non-zero exit,
# and reading that as a failed validation is a confident "not done" about a file
# that is fine.
#
# So the three verdicts are matched by name and everything else falls through to
# cannot-tell. Testing for the `outcome` key alone cannot separate them, and an
# allowlist is the direction that fails safe: a sixth label added upstream reads
# as cannot-tell rather than silently joining the not-done pile.
#
# The classification reads the payload rather than the exit status, and that is
# not a stylistic choice: `shirabe validate` exits 1 for both cases. An unknown
# `--check` code exits 1 with plain text on stderr and no JSON; a document whose
# frontmatter never closes exits 1 with a full JSON envelope carrying
# `"outcome": "tool-error"`. An exit-status test cannot tell those apart, so
# simplifying this to `if shirabe validate ...; then` reopens the hole silently.
#
# One consequence of the `2>&1` capture: VALIDATOR_OUT is no longer guaranteed
# to be JSON -- a deprecation notice on stderr prepends to it. That is harmless
# for the substring matching below and would not be for a `jq` pipeline.
run_validator() {
  local status
  VALIDATOR_OUT=$(shirabe validate "$1" --check "$2" --format json 2>&1)
  status=$?
  if verdict_is clean || verdict_is incomplete || verdict_is violations; then
    return 0
  fi
  echo "cannot decide hop completion: shirabe validate reached no verdict on $1 (exit $status)" >&2
  if [ -n "$VALIDATOR_OUT" ]; then printf '%s\n' "$VALIDATOR_OUT" >&2; fi
  return 1
}

# This `exit 2` has to leave the script, and whether it does is decided three
# frames away rather than here. The two sites that must stay out of a subshell
# are the `for p in ...` / `if is_artifact` loop and the `if ! validates_fold`
# branch in the survivor scan, both near the bottom of this file; `is_artifact`
# sits between this function and the first of them and is the frame most likely
# to be edited. Putting any of the three inside a pipeline or a `$(...)` --
# `| head -1` on the loop is the tempting one -- is enough to break this.
#
# The failure is not that the exit is lost. There is no `set -e`, so a swallowed
# `exit 2` returns 2 from the subshell, the caller reads that as "not an
# artifact", the scan runs on, and the script prints `incomplete: no artifact at
# ...` about a file it could not examine. That is the confident wrong answer the
# whole cannot-tell distinction above exists to prevent, arriving by a different
# road.
is_clean() {
  run_validator "$1" "$2" || exit 2
  printf '%s' "$VALIDATOR_OUT" | grep -q '"outcome": *"clean"'
}

# SCHEMA is selected deliberately, and dropping it reopens a defeat. `--check`
# selection drives the outcome exactly as it drives reporting, so a run that
# deselected SCHEMA "has not been told to care about the skip and stays clean"
# (crates/shirabe/src/main.rs, the SCHEMA_SKIP_CODE branch). That is the rung a
# document reaches when the schema gate fires -- routed to a format and then
# checked against nothing. Without SCHEMA in this list, such a document reports
# clean here while the validator checked none of it.
validates_structure() { is_clean "$1" SCHEMA,FC01,FC03,FC04; }

# The absorption pairing specifically: FC18 requires the `absorbed:` declaration
# and the contribution section it implies to appear together, so a survivor that
# declares without carrying fails here.
# One call rather than two consecutive ones on the same file: both must be clean
# for the fold to be credited, so the combined check is the same question asked
# once.
# This list must stay a superset of validates_structure's. A fold is credited
# only where the survivor is both a well-formed document and carries what it
# declares; dropping a check from here but not from there would credit a fold on
# a document the other limb would have refused.
validates_fold() { is_clean "$1" SCHEMA,FC01,FC03,FC04,FC18; }

case "$HOP" in
  brief|prd|design|plan) ;;
  *) echo "unknown hop: $HOP (expected brief, prd, design or plan)" >&2; exit 2 ;;
esac

canonical() {
  case "$1" in
    brief)  echo "docs/briefs/BRIEF-${TOPIC}.md" ;;
    prd)    echo "docs/prds/PRD-${TOPIC}.md" ;;
    # Both DESIGN locations are canonical. Phase 2 treats the pair as one path,
    # and every gate that decides a design hop must read the same pair or two
    # gates in one graph disagree about the same file.
    design) echo "docs/designs/DESIGN-${TOPIC}.md docs/designs/current/DESIGN-${TOPIC}.md" ;;
    plan)   echo "docs/plans/PLAN-${TOPIC}.md" ;;
    *)      echo "" ;;
  esac
}

# A real artifact: a regular file, not a symlink, not empty, carrying a schema
# key. `test -f` alone follows symlinks and accepts a zero-byte file, so it
# accepts `touch` and `ln -s /etc/hostname` as a completed hop.
is_document() {
  local f="$1"
  [ -f "$f" ] || return 1
  [ -L "$f" ] && return 1
  [ -s "$f" ] || return 1
  # No `head -n 1 == ---` test. The validator skips leading blank lines before
  # the opening delimiter, so requiring `---` on line 1 refused a document that
  # validates clean. Whether the frontmatter opens at all is frontmatter()'s
  # question, and it answers it the way the validator does.
  frontmatter "$f" | grep -Eq '^schema:[[:space:]]*[a-z]+/v[0-9]+' || return 1
  return 0
}

# A landed artifact is a well-formed document, not merely a file with a schema
# key: a three-line stub and a copy of a different artifact type both satisfy
# the structural check and neither is a landed hop.
# The schema a hop's artifact must declare. Checked directly rather than left
# to validation: FC01, FC03 and FC04 are type-agnostic, so a well-formed
# document of the wrong type passes them at any path. One `cp` of the terminal
# artifact onto the three upstream paths defeated an earlier version this way.
schema_for() {
  case "$1" in
    brief)  echo "brief/v1" ;;
    prd)    echo "prd/v1" ;;
    design) echo "design/v1" ;;
    plan)   echo "plan/v1" ;;
    *)      echo "" ;;
  esac
}

is_artifact() {
  local f="$1" want_schema="$2"
  is_document "$f" || return 1
  frontmatter "$f" | grep -Eq "^schema:[[:space:]]*${want_schema}\$" || return 1
  validates_structure "$f" || return 1
  return 0
}

# A reimplementation of the validator's frontmatter splitter
# (crates/shirabe-validate/src/frontmatter.rs, `split_frontmatter`). Every rule
# below exists because the two parsers disagreeing on one input is a defeat, not
# a cosmetic difference: whatever this reads as frontmatter and the validator
# reads as body carries an `absorbed:` declaration that FC18 never sees, and a
# check that never saw a declaration cannot fail on it -- so the backstop passes
# vacuously and every hop credits a fold that never happened. That has now
# happened twice, on two different inputs.
#
# Three rules, each mirroring a named site in that file, and each with a defeat
# behind it rather than a style preference:
#
#   Trailing CR is stripped before any comparison, as `split_lines` does.
#   Otherwise a closing `---\r` ends the frontmatter there and not here.
#
#   Blank lines BEFORE the opener are skipped, and a non-blank line before it
#   means no frontmatter. This is the pre-opener loop.
#
#   A blank line immediately AFTER the opener means no frontmatter at all: a
#   `---` followed by a blank is a thematic break, not a YAML opener, because
#   frontmatter always has a key on the next line. This is the rule that was
#   missing, and one blank line was enough to credit all four hops.
#
# Keep this function and that file in step. If the splitter grows a fourth rule
# and this does not, the seam reopens in whichever direction the new rule runs.
frontmatter() {
  awk '{ sub(/\r$/, "") }
       !opened {
         if ($0 == "---") { opened = 1; next }
         if ($0 ~ /^[[:space:]]*$/) next
         exit
       }
       opened && !seen && $0 ~ /^[[:space:]]*$/ { exit }
       opened && $0 == "---" { exit }
       opened { seen = 1; print }' "$1" 2>/dev/null
}

# Whole entries under the `absorbed:` key only. A scalar on the key's own line,
# or `- ` sequence entries beneath it, or an inline [a, b] list. Any other
# frontmatter key naming the same path -- `upstream:`, `supersedes:`, a comment --
# is not an absorption, and must not satisfy limb (b).
absorbed_entries() {
  frontmatter "$1" | awk '
    /^absorbed:[[:space:]]*$/            { inblk=1; next }
    /^absorbed:[[:space:]]*\[/           { line=$0; sub(/^absorbed:[[:space:]]*\[/,"",line);
                                           sub(/\].*$/,"",line);
                                           n=split(line,parts,",");
                                           for(i=1;i<=n;i++){ gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/,"",parts[i]);
                                                              if(parts[i]!="") print parts[i] }
                                           next }
    /^absorbed:[[:space:]]*[^[:space:]]/ { line=$0; sub(/^absorbed:[[:space:]]*/,"",line);
                                           sub(/[[:space:]]+$/,"",line);
                                           gsub(/^["'"'"']+|["'"'"']+$/,"",line);
                                           sub(/[[:space:]]+$/,"",line);
                                           if(line!="") print line; next }
    inblk && /^[[:space:]]*-[[:space:]]+/ { line=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line);
                                            sub(/[[:space:]]+#.*$/,"",line);
                                            gsub(/^["'"'"']+|["'"'"']+$/,"",line);
                                            sub(/[[:space:]]+$/,"",line);
                                            if(line!="") print line; next }
    inblk && /^[^[:space:]-]/            { inblk=0 }
  '
}

# The `$(canonical ...)` below and in the survivor scan are deliberately
# UNQUOTED. `canonical design` returns two paths separated by a space, and the
# loop has to see two words. Quoting the substitution -- the reflex fix, and
# what a linter will suggest -- collapses them into one path that exists nowhere,
# so every design hop refuses and both limbs go with it. If the design hop ever
# stops needing two locations, delete the second path rather than adding quotes.
WANT_SCHEMA="$(schema_for "$HOP")"
for p in $(canonical "$HOP"); do
  if is_artifact "$ROOT/$p" "$WANT_SCHEMA"; then
    echo "complete: artifact present at $p"
    exit 0
  fi
done

case "$HOP" in
  brief)  DOWNSTREAM="prd design plan" ;;
  prd)    DOWNSTREAM="design plan" ;;
  design) DOWNSTREAM="plan" ;;
  *)      DOWNSTREAM="" ;;
esac

# The exact entry FC18's anchored pattern would accept for this hop.
case "$HOP" in
  brief)  WANT="docs/briefs/BRIEF-${TOPIC}.md" ;;
  prd)    WANT="docs/prds/PRD-${TOPIC}.md" ;;
  design) WANT="docs/designs/DESIGN-${TOPIC}.md" ;;
  *)      WANT="" ;;
esac

for d in $DOWNSTREAM; do
  for sp in $(canonical "$d"); do
    # Guard on shape and type only, never on validation. FC04's required-section
    # list is dynamic: declaring `absorbed:` makes the contribution section
    # required, so a survivor that declares without carrying fails the structure
    # check too. Validating here would skip it before the declaration is matched,
    # and the run would be told no declaration exists when one does -- a true
    # refusal with a false reason, sending an author to the wrong file.
    is_document "$ROOT/$sp" || continue
    frontmatter "$ROOT/$sp" | grep -Eq "^schema:[[:space:]]*$(schema_for "$d")\$" || continue
    if absorbed_entries "$ROOT/$sp" | grep -Fxq -- "$WANT"; then
      if ! validates_fold "$ROOT/$sp"; then
        echo "incomplete: $sp declares $WANT absorbed but does not validate"
        exit 1
      fi
      echo "complete: absorbed into $sp"
      exit 0
    fi
  done
done

echo "incomplete: no artifact at ${WANT:-$(canonical "$HOP" | awk '{print $1}')}, and no downstream absorbed: entry names it"
exit 1
