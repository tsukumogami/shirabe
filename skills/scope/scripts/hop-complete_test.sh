#!/usr/bin/env bash
# Fixture suite for hop-complete.sh.
#
# Every case below is either a behaviour an acceptance criterion names or a
# defeat that review found in an earlier version of the predicate. The defeats
# are kept because a predicate rewritten without them in front of you is likely
# to reproduce one: each looked correct until it was attacked.
#
# Usage: skills/scope/scripts/hop-complete_test.sh
# Exit 0 when every case behaves as required.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
S="$HERE/hop-complete.sh"
T="demo"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT

PASS=0
FAIL=0

run() {
  local label="$1" root="$2" hop="$3" want="$4"
  local out rc
  out="$(bash "$S" --hop "$hop" --topic "$T" --root "$root" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ]; then
    PASS=$((PASS+1))
    printf 'ok   %-46s hop=%-6s exit=%d\n' "$label" "$hop" "$rc"
  else
    FAIL=$((FAIL+1))
    printf 'FAIL %-46s hop=%-6s exit=%d want=%d\n     %s\n' "$label" "$hop" "$rc" "$want" "$out"
  fi
}

# A real artifact of each type, derived from this repository's own documents so
# it validates clean. A hand-written stub does not: the predicate requires a
# clean validation, which is what stops a three-line file counting as a hop.
seed() {
  local root="$1" kind="$2"
  case "$kind" in
    brief)  mkdir -p "$root/docs/briefs"
            sed "s/scope-koto-adoption/$T/g" "$REPO/docs/briefs/BRIEF-scope-koto-adoption.md" \
              > "$root/docs/briefs/BRIEF-$T.md" ;;
    prd)    mkdir -p "$root/docs/prds"
            sed "s/scope-koto-adoption/$T/g" "$REPO/docs/prds/PRD-scope-koto-adoption.md" \
              > "$root/docs/prds/PRD-$T.md" ;;
    design) mkdir -p "$root/docs/designs"
            sed "s/scope-koto-adoption/$T/g" "$REPO/docs/designs/DESIGN-scope-koto-adoption.md" \
              > "$root/docs/designs/DESIGN-$T.md" ;;
    design-current)
            mkdir -p "$root/docs/designs/current"
            sed "s/scope-koto-adoption/$T/g" "$REPO/docs/designs/DESIGN-scope-koto-adoption.md" \
              > "$root/docs/designs/current/DESIGN-$T.md" ;;
    plan)   mkdir -p "$root/docs/plans"
            sed "s/scope-koto-adoption/$T/g" "$REPO/docs/plans/PLAN-scope-koto-adoption.md" \
              > "$root/docs/plans/PLAN-$T.md" ;;
  esac
}

# --- limb (a): the artifact is present -------------------------------------

C="$BASE/a1"; seed "$C" brief
run "artifact present" "$C" brief 0

# Both DESIGN locations are canonical. An earlier version tested only the
# current/ path, which is reached by a lifecycle transition long after a run
# ends -- so the gate was false on every run and the design hop livelocked
# against the fold state with the terminal hop unreachable.
C="$BASE/a2"; seed "$C" design
run "design at docs/designs/" "$C" design 0
C="$BASE/a3"; seed "$C" design-current
run "design at docs/designs/current/" "$C" design 0

C="$BASE/a4"; mkdir -p "$C/docs/briefs"; : > "$C/docs/briefs/BRIEF-$T.md"
run "zero-byte artifact" "$C" brief 1

C="$BASE/a5"; mkdir -p "$C/docs/briefs"; ln -sf /etc/hostname "$C/docs/briefs/BRIEF-$T.md"
run "symlink at canonical path" "$C" brief 1

C="$BASE/a6"; mkdir -p "$C/docs/briefs"
printf -- '---\nschema: brief/v1\n---\n' > "$C/docs/briefs/BRIEF-$T.md"
run "three-line stub" "$C" brief 1

C="$BASE/a7"; mkdir -p "$C/docs/briefs"; echo hello > "$C/docs/briefs/BRIEF-$T.md"
run "no frontmatter" "$C" brief 1

# A plan copied onto every other type's path satisfied an earlier version,
# which checked only that a schema key existed rather than that it matched.
C="$BASE/a8"; seed "$C" plan
mkdir -p "$C/docs/briefs" "$C/docs/prds" "$C/docs/designs"
cp "$C/docs/plans/PLAN-$T.md" "$C/docs/briefs/BRIEF-$T.md"
cp "$C/docs/plans/PLAN-$T.md" "$C/docs/prds/PRD-$T.md"
cp "$C/docs/plans/PLAN-$T.md" "$C/docs/designs/DESIGN-$T.md"
run "plan copied onto every path" "$C" brief 1

# --- limb (b): the hop is declared absorbed --------------------------------

fold_into_prd() {
  local root="$1"
  seed "$root" prd
  python3 - "$root/docs/prds/PRD-$T.md" "$T" <<'PY'
import re, sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: prd/v1\n",
              "---\nschema: prd/v1\nabsorbed: docs/briefs/BRIEF-%s.md\n" % topic, 1)
s = s.replace("## Status\n\nAccepted\n",
              "## Status\n\nAccepted\n\nAbsorbed [BRIEF](docs/briefs/BRIEF-%s.md); carried in Absorbed Brief.\n\n"
              "## Absorbed Brief\n\nThe brief's framing, carried forward: the problem, the outcome a user\n"
              "should experience, the journeys, and the scope boundary.\n" % topic, 1)
open(p, "w").write(s)
PY
}

C="$BASE/b1"; fold_into_prd "$C"
run "legitimate fold into PRD" "$C" brief 0

# A survivor that declares a fold and fails validation must say so, rather than
# reporting that no declaration exists -- a true refusal with a false reason
# sends an author to the wrong file. This case also covers a declaration whose
# contribution section is absent, which nothing else here exercises.
C="$BASE/b2"; seed "$C" prd
python3 - "$C/docs/prds/PRD-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: prd/v1\n",
              "---\nschema: prd/v1\nabsorbed: docs/briefs/BRIEF-%s.md\n" % topic, 1)
open(p, "w").write(s)
PY
out="$(bash "$S" --hop brief --topic "$T" --root "$C" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "does not validate"; then
  PASS=$((PASS+1)); printf 'ok   %-46s hop=%-6s exit=1 (accurate reason)\n' "declares fold, fails validation" "brief"
else
  FAIL=$((FAIL+1)); printf 'FAIL %-46s exit=%d out=%s\n' "declares fold, fails validation" "$rc" "$out"
fi

# The reported incident: a terminal artifact on disk, the upstream hops asserted
# away in a Status sentence, no declaration anywhere.
C="$BASE/b3"; seed "$C" plan
python3 - "$C/docs/plans/PLAN-$T.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("## Status\n\nActive\n",
              "## Status\n\nActive\n\nNo BRIEF, PRD, or DESIGN was written: the effort is small, and three\n"
              "upstream documents restating that at three altitudes would be ceremony.\n", 1)
open(p, "w").write(s)
PY
run "the incident: prose claim only" "$C" brief 1
run "the incident: prose claim only" "$C" prd 1
run "the incident: prose claim only" "$C" design 1
run "the incident: prose claim only" "$C" plan 0

# The incident plus three lines of ordinary YAML. `upstream:` is convention in
# this repository, and an earlier version grepped the whole frontmatter block
# for a basename rather than reading the absorbed: key -- so this shape made
# every hop pass and reached the terminal carrying an engine-authored gate
# outcome vouching for a chain it never walked.
C="$BASE/b4"; seed "$C" plan
python3 - "$C/docs/plans/PLAN-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: plan/v1\n",
              "---\nschema: plan/v1\nsupersedes: docs/prds/PRD-%s.md\nrelated: docs/briefs/BRIEF-%s.md\n"
              % (topic, topic), 1)
open(p, "w").write(s)
PY
run "frontmatter name-drop" "$C" brief 1
run "frontmatter name-drop" "$C" prd 1

# A declaration in the body, including inside a fenced block, is invisible to
# the validator too: FC18 is gated on absorbed: being present as the validator's
# own frontmatter parser sees it, so a body-block declaration has no backstop.
C="$BASE/b5"; seed "$C" plan
{ printf '\n```yaml\nabsorbed:\n  - docs/briefs/BRIEF-%s.md\n```\n' "$T"; } >> "$C/docs/plans/PLAN-$T.md"
run "body code-block declaration" "$C" brief 1

C="$BASE/b6"; seed "$C" prd
python3 - "$C/docs/prds/PRD-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: prd/v1\n",
              "---\nschema: prd/v1\nabsorbed: vendor/docs/briefs/BRIEF-%s.md\n" % topic, 1)
open(p, "w").write(s)
PY
run "absorbed: substring of longer path" "$C" brief 1

C="$BASE/b7"; seed "$C" prd
python3 - "$C/docs/prds/PRD-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: prd/v1\n",
              "---\nschema: prd/v1\nabsorbed_by: docs/briefs/BRIEF-%s.md\n" % topic, 1)
open(p, "w").write(s)
PY
run "absorbed_by lookalike key" "$C" brief 1

# Three documents in this repository carry an inline backticked delimiter inside
# a frontmatter block scalar. An unanchored stop condition truncates the
# frontmatter there and misses a declaration below it -- a false refusal on a
# legitimate fold.
C="$BASE/b8"; fold_into_prd "$C"
python3 - "$C/docs/prds/PRD-$T.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("---\nschema: prd/v1\n",
              "---\nschema: prd/v1\nnote: |\n  The delimiter is written `---` in prose here.\n", 1)
open(p, "w").write(s)
PY
run "inline backticked --- in block scalar" "$C" brief 0

# A skipped hop satisfies neither limb: nothing on disk, nothing declared.
C="$BASE/b9"; seed "$C" prd
run "skipped hop satisfies neither limb" "$C" brief 1

# A cascading fold: brief and prd folded onward into the design, then all three
# declared by the plan. The design claims this needs no recursion because a
# survivor carries and declares every absorbed ancestor -- this is the fixture
# that holds it to that.
C="$BASE/b10"; seed "$C" plan
python3 - "$C/docs/plans/PLAN-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("---\nschema: plan/v1\n",
              "---\nschema: plan/v1\nabsorbed:\n"
              "  - docs/briefs/BRIEF-%s.md\n"
              "  - docs/prds/PRD-%s.md\n"
              "  - docs/designs/DESIGN-%s.md\n" % (topic, topic, topic), 1)
s = s.replace("## Status\n\nActive\n",
              "## Status\n\nActive\n\n"
              "Absorbed [BRIEF](docs/briefs/BRIEF-%s.md); carried in Absorbed Brief.\n"
              "Absorbed [PRD](docs/prds/PRD-%s.md); carried in Absorbed PRD.\n"
              "Absorbed [DESIGN](docs/designs/DESIGN-%s.md); carried in Absorbed Design.\n\n"
              "## Absorbed Brief\n\nThe problem, the outcome, the journeys, the scope boundary.\n\n"
              "## Absorbed PRD\n\nThe requirements and the criteria that decide it is done.\n\n"
              "## Absorbed Design\n\nThe approach, the alternatives weighed, and why this one.\n"
              % (topic, topic, topic), 1)
open(p, "w").write(s)
PY
run "cascading fold, all three declared" "$C" brief 0
run "cascading fold, all three declared" "$C" prd 0
run "cascading fold, all three declared" "$C" design 0

# A CR-terminated closing delimiter ends the frontmatter for the validator and
# not for a scan that compares the raw line. `absorbed:` placed just below it
# then reads as frontmatter here and as body there -- and FC18, silent on a
# declaration it never saw, passes vacuously. One invisible byte, every hop
# credited. This is the sixth defeat review found.
C="$BASE/b11"; seed "$C" plan
python3 - "$C/docs/plans/PLAN-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
idx = [i for i, l in enumerate(lines) if l == "---"][1]
lines[idx] = "---\r"
lines[idx+1:idx+1] = ["absorbed:",
                      "  - docs/briefs/BRIEF-%s.md" % topic,
                      "  - docs/prds/PRD-%s.md" % topic]
open(p, "w").write("\n".join(lines))
PY
run "CR delimiter, absorbed: below it" "$C" brief 1
run "CR delimiter, absorbed: below it" "$C" prd 1

# A trailing space on an entry is invisible in an editor and the validator does
# not care. Refusing it would be a true refusal with a false reason, on an
# authoring accident.
C="$BASE/b12"; fold_into_prd "$C"
python3 - "$C/docs/prds/PRD-$T.md" "$T" <<'PY'
import sys
p, topic = sys.argv[1], sys.argv[2]
s = open(p).read()
s = s.replace("absorbed: docs/briefs/BRIEF-%s.md\n" % topic,
              "absorbed: docs/briefs/BRIEF-%s.md  \n" % topic, 1)
open(p, "w").write(s)
PY
run "trailing space on entry (must credit)" "$C" brief 0

# --- the validator is not optional -----------------------------------------

# Both limbs answer to the validator, so a missing binary must refuse rather
# than degrade to bare existence, which four copies defeat.
C="$BASE/c1"; seed "$C" plan
mkdir -p "$C/docs/briefs"; cp "$C/docs/plans/PLAN-$T.md" "$C/docs/briefs/BRIEF-$T.md"
out="$(PATH=/usr/bin:/bin bash "$S" --hop brief --topic "$T" --root "$C" 2>&1)"; rc=$?
if [ "$rc" = 2 ]; then
  PASS=$((PASS+1)); printf 'ok   %-46s hop=%-6s exit=2 (refuses)\n' "validator absent" "brief"
else
  FAIL=$((FAIL+1)); printf 'FAIL %-46s exit=%d want=2 out=%s\n' "validator absent" "$rc" "$out"
fi

# The seventh defeat. A blank line immediately after the opening delimiter is a
# thematic break to the validator and frontmatter to a naive scan. With SCHEMA
# deselected, a document the validator never checked against its format still
# reports clean, so FC18 is silent about a declaration it never saw and every
# hop credits a fold that never happened. One blank line restored the original
# incident; both halves of the fix are needed, and each is pinned here.
C="$BASE/c3"; mkdir -p "$C/docs/plans"
{
  echo '---'
  echo ''
  echo 'schema: plan/v1'
  echo 'status: Active'
  echo 'title: demo'
  echo 'absorbed:'
  echo "  - docs/briefs/BRIEF-$T.md"
  echo "  - docs/prds/PRD-$T.md"
  echo "  - docs/designs/DESIGN-$T.md"
  echo '---'
  echo ''
  echo '## Status'
  echo ''
  echo 'Active'
} > "$C/docs/plans/PLAN-$T.md"
for h in brief prd design plan; do
  run "thematic break credits nothing" "$C" "$h" 1
done

# The mirror. Blank lines BEFORE the opener are skipped by the validator, so a
# document carrying them validates clean and must be credited. An earlier
# version tested line 1 for the delimiter and refused it -- a false refusal
# about a document that is fine, which is the same class of wrong answer in the
# other direction.
C="$BASE/c4"; seed "$C" brief
printf '\n\n%s' "$(cat "$C/docs/briefs/BRIEF-$T.md")" > "$C/docs/briefs/BRIEF-$T.md.tmp"
mv "$C/docs/briefs/BRIEF-$T.md.tmp" "$C/docs/briefs/BRIEF-$T.md"
run "leading blank lines still credit" "$C" brief 0

# Unclosed frontmatter is the reachable tool-error path: the file is readable
# and opens with a delimiter, so the validator IS consulted, and it answers that
# it could not parse the document. That is a cannot-tell, not a not-done.
C="$BASE/c5"; mkdir -p "$C/docs/prds"
{
  echo '---'
  echo 'schema: prd/v1'
  echo 'status: Accepted'
  echo 'title: demo'
  echo ''
  echo '## Status'
} > "$C/docs/prds/PRD-$T.md"
run "unclosed frontmatter is cannot-tell" "$C" prd 2

# The slug composes every path below it, so it is re-asserted here even though
# Phase 0 validated it. An explicit acceptance criterion.
out="$(bash "$S" --hop brief --topic '../../etc' --root "$BASE" 2>&1)"; rc=$?
if [ "$rc" = 2 ]; then
  PASS=$((PASS+1)); printf 'ok   %-46s exit=2 (refuses)\n' "traversal slug refused"
else
  FAIL=$((FAIL+1)); printf 'FAIL %-46s exit=%d want=2 out=%s\n' "traversal slug refused" "$rc" "$out"
fi

# A validator that is present but reaches no verdict -- a check renamed out
# from under us, a build that rejects an argument -- has answered nothing. The
# hop must read as cannot-tell, not as not-done: collapsing the two would make
# every fold uncreditable while the gate printed a confident "incomplete".
C="$BASE/c2"; seed "$C" plan
STUB="$BASE/stub"; mkdir -p "$STUB"
{
  echo '#!/bin/sh'
  echo 'echo "error: unrecognised check name FC18" >&2'
  echo 'exit 64'
} > "$STUB/shirabe"
chmod +x "$STUB/shirabe"
out="$(PATH="$STUB:$PATH" bash "$S" --hop plan --topic "$T" --root "$C" 2>&1)"; rc=$?
case "$rc:$out" in
  2:*"reached no verdict"*)
    PASS=$((PASS+1)); printf 'ok   %-46s hop=%-6s exit=2 (cannot tell)\n' "validator present, no verdict" "plan" ;;
  *)
    FAIL=$((FAIL+1)); printf 'FAIL %-46s exit=%d want=2 out=%s\n' "validator present, no verdict" "$rc" "$out" ;;
esac

# The same stub must not silence the diagnostic: the reason has to reach stderr,
# or the refusal is unactionable.
case "$out" in
  *"unrecognised check name FC18"*)
    PASS=$((PASS+1)); printf 'ok   %-46s %s\n' "no-verdict diagnostic is surfaced" "(validator stderr kept)" ;;
  *)
    FAIL=$((FAIL+1)); printf 'FAIL %-46s out=%s\n' "no-verdict diagnostic is surfaced" "$out" ;;
esac

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
