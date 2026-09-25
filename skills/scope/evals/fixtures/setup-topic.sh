#!/usr/bin/env bash
# setup-topic.sh -- build the repository a /scope eval scenario runs in.
#
# Creates, under the current directory, `<topic>-repo/` (a git repository on
# branch docs/<topic>) and, unless --no-origin, `<topic>-origin.git/` (a local
# bare repository registered as `origin`, with main pushed), then prints the
# repository's path. The documents come from skills/scope/scripts/testdata/,
# the same frozen fixtures the substrate suite walks, with the topic written in,
# so every hop gate finds a document the validator passes.
#
# Usage:
#   setup-topic.sh <topic> [--docs all|upstreams|executed|none]
#                  [--mode single-pr|multi-pr|coordinated|mixed]
#                  [--pointer 1|2|3] [--intent continue|stop|none]
#                  [--split] [--no-origin]
#
#   --docs all        BRIEF, PRD, DESIGN and PLAN committed (default)
#   --docs upstreams  BRIEF, PRD and DESIGN only: the /plan hop still has to run
#   --docs executed   no PLAN, the DESIGN under docs/designs/current/ at
#                     Current and the PRD at Done: a PLAN the cascade executed
#   --docs none       nothing under docs/
#   --mode            the PLAN's execution_mode; `mixed` is the multi-pr PLAN
#                     fixtures/plans/PLAN-mixed-deps.md (two roots, a chain,
#                     a diamond)
#   --pointer N       write a fresh wip/scope_<topic>_state.md at
#                     phase_pointer N, so /scope resumes at discovery (1),
#                     the first open hop (2) or finalize (3)
#   --intent V        the intent that state file records (default none); it
#                     must equal the --intent the eval invokes /scope with,
#                     or intake refuses the run as intent-mismatch
#   --split           append to the DESIGN a delivery constraint /plan's split
#                     triggers read as a hard constraint to ship in several PRs
#   --no-origin       leave the repository without an origin remote
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TESTDATA="$(cd "$HERE/../../scripts/testdata" && pwd)"

TOPIC="${1:?usage: setup-topic.sh <topic> [options]}"
shift
case "$TOPIC" in
    ''|-*|*[!a-z0-9-]*) echo "setup-topic: bad topic [$TOPIC]" >&2; exit 64 ;;
esac
DOCS=all; MODE=single-pr; POINTER=""; SPLIT=0; ORIGIN=1; INTENT=none
while [ "$#" -gt 0 ]; do
    case "$1" in
        --docs) DOCS="$2"; shift ;;
        --mode) MODE="$2"; shift ;;
        --pointer) POINTER="$2"; shift ;;
        --intent) INTENT="$2"; shift ;;
        --split) SPLIT=1 ;;
        --no-origin) ORIGIN=0 ;;
        *) echo "setup-topic: unknown option $1" >&2; exit 64 ;;
    esac
    shift
done

R="$PWD/$TOPIC-repo"
O="$PWD/$TOPIC-origin.git"
rm -rf "$R" "$O"
git init -q -b main "$R"
cd "$R"
git config user.email eval@example.invalid
git config user.name eval
printf '# %s\n' "$TOPIC" >CLAUDE.md
git add CLAUDE.md
git commit -q -m "chore: start $TOPIC"
if [ "$ORIGIN" -eq 1 ]; then
    git init -q --bare -b main "$O"
    git remote add origin "$O"
    git push -q -u origin main
fi
git checkout -q -b "docs/$TOPIC"

sub() { sed "s/scope-koto-adoption/$TOPIC/g" "$1"; }
mkdir -p docs/briefs docs/prds docs/designs docs/plans wip

case "$DOCS" in
    all|upstreams)
        sub "$TESTDATA/brief.md.fixture" >"docs/briefs/BRIEF-$TOPIC.md"
        sub "$TESTDATA/prd.md.fixture" >"docs/prds/PRD-$TOPIC.md"
        sub "$TESTDATA/design.md.fixture" >"docs/designs/DESIGN-$TOPIC.md"
        if [ "$SPLIT" -eq 1 ]; then
            printf '\n## Delivery Constraint\n\n%s\n' \
                "Hard constraint: the schema migration and the reader change ship as separate pull requests, because the migration must be live in production before any reader depends on it." \
                >>"docs/designs/DESIGN-$TOPIC.md"
        fi
        if [ "$DOCS" = all ]; then
            if [ "$MODE" = mixed ]; then
                sed "s/@TOPIC@/$TOPIC/g" "$HERE/plans/PLAN-mixed-deps.md" >"docs/plans/PLAN-$TOPIC.md"
            else
                sub "$TESTDATA/plan.md.fixture" | sed "s/^execution_mode: .*/execution_mode: $MODE/" \
                    >"docs/plans/PLAN-$TOPIC.md"
            fi
        fi
        ;;
    executed)
        mkdir -p docs/designs/current
        sub "$TESTDATA/design.md.fixture" | sed 's/^status: .*/status: Current/' \
            >"docs/designs/current/DESIGN-$TOPIC.md"
        sub "$TESTDATA/prd.md.fixture" | sed 's/^status: .*/status: Done/' >"docs/prds/PRD-$TOPIC.md"
        ;;
    none) ;;
    *) echo "setup-topic: unknown --docs $DOCS" >&2; exit 64 ;;
esac
git add -A docs
git commit -q -m "docs: $TOPIC" || true

if [ -n "$POINTER" ]; then
    printf 'topic: %s\nlast_updated: %s\nphase_pointer: %s\nintent: %s\n' \
        "$TOPIC" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$POINTER" "$INTENT" >"wip/scope_${TOPIC}_state.md"
fi

printf '%s\n' "$R"
