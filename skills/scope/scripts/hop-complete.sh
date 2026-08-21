#!/usr/bin/env bash
# hop-complete.sh --hop <brief|prd|design|plan> --topic <slug> [--root <dir>]
#
# Exit 0 when the hop is complete under either limb of PRD R7:
#   (a) the hop's own artifact is a regular, non-empty file at a canonical path;
#   (b) a surviving downstream document declares this hop under its `absorbed:`
#       frontmatter key, as a whole entry.
#
# Reads only the artifact tree. Never reads wip/scope_<topic>_state.md.
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
validates_structure() {
  shirabe validate "$1" --check FC01,FC03,FC04 --format json 2>/dev/null \
    | grep -q '"outcome": *"clean"'
}

# The absorption pairing specifically: FC18 requires the `absorbed:` declaration
# and the contribution section it implies to appear together, so a survivor that
# declares without carrying fails here.
validates_absorption() {
  shirabe validate "$1" --check FC18 --format json 2>/dev/null \
    | grep -q '"outcome": *"clean"'
}

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
  head -n 1 "$f" | grep -qx -- '---' || return 1
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

frontmatter() {
  awk 'NR==1 && $0 != "---" { exit }
       NR>1 && $0 == "---" { exit }
       NR>1 { print }' "$1" 2>/dev/null
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
                                           gsub(/^["'"'"']+|["'"'"']+$/,"",line);
                                           if(line!="") print line; next }
    inblk && /^[[:space:]]*-[[:space:]]+/ { line=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line);
                                            gsub(/^["'"'"']+|["'"'"']+$/,"",line);
                                            sub(/[[:space:]]+#.*$/,"",line);
                                            if(line!="") print line; next }
    inblk && /^[^[:space:]-]/            { inblk=0 }
  '
}

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
    # Structural check only here. Validating first would skip a survivor that
    # declares the absorption and fails to validate, and the run would then be
    # told no declaration exists when one does -- a true refusal with a false
    # reason, sending an author to the wrong file.
    # Guard on shape and type only, never on validation. FC04's required-section
    # list is dynamic: declaring `absorbed:` makes the contribution section
    # required, so a survivor that declares without carrying fails the structure
    # check too. Validating here would skip it before the declaration is matched,
    # and the run would be told no declaration exists when one does -- a true
    # refusal with a false reason, sending an author to the wrong file.
    is_document "$ROOT/$sp" || continue
    frontmatter "$ROOT/$sp" | grep -Eq "^schema:[[:space:]]*$(schema_for "$d")\$" || continue
    if absorbed_entries "$ROOT/$sp" | grep -Fxq -- "$WANT"; then
      if ! validates_absorption "$ROOT/$sp" || ! validates_structure "$ROOT/$sp"; then
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
