#!/usr/bin/env bash
# setup-deliver.sh -- build the repository a /deliver eval scenario runs in.
#
# Builds on /scope's own fixture builder (skills/scope/evals/fixtures/
# setup-topic.sh): `<topic>-repo/` on branch docs/<topic> with a local bare
# `<topic>-origin.git/` as origin, the frozen BRIEF/PRD/DESIGN fixtures with
# the topic written in, and optionally a /scope state file. On top of that it
# writes the CLAUDE.md headers /deliver reads, and swaps in a PLAN small enough
# that /execute's work is one trivial change, so a scenario is about what
# /deliver does between its children rather than about the implementation.
# Prints the repository's path.
#
# Usage:
#   setup-deliver.sh <topic> [--state finalize|split|plan|executed|mid-hop]
#                    [--mode single-pr|coordinated|multi-pr]
#                    [--visibility public|private|none] [--exec-mode auto]
#                    [--intent continue|stop]
#
#   --state finalize  (default) BRIEF, PRD, DESIGN and the trivial PLAN
#                     committed, and a /scope state file at the finalize
#                     pointer recording --intent (default continue): /scope
#                     records its full-run exit, publishes, and ends.
#   --state split     BRIEF, PRD and a DESIGN carrying a hard delivery
#                     constraint, no PLAN: the /plan hop runs and splits.
#   --state plan      the trivial PLAN committed and no state file: a topic
#                     whose PLAN exists (the republish shortcut).
#   --state executed  no PLAN, the DESIGN under docs/designs/current/: an
#                     executed topic (the executed shortcut).
#   --state mid-hop   BRIEF, PRD and DESIGN, no PLAN, and a state file at
#                     pointer 2 recording --intent: an unfinished /scope run
#                     that resumes at its first open hop.
#   --mode            the trivial PLAN's execution_mode (default single-pr);
#                     coordinated writes a two-group outline PLAN.
#   --visibility      the `## Repo Visibility:` header (default public);
#                     none leaves it out.
#   --exec-mode auto  add `## Execution Mode: auto` to CLAUDE.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCOPE_SETUP="$(cd "$HERE/../../../scope/evals/fixtures" && pwd)/setup-topic.sh"

TOPIC="${1:?usage: setup-deliver.sh <topic> [options]}"
shift
case "$TOPIC" in
    ''|-*|*[!a-z0-9-]*) echo "setup-deliver: bad topic [$TOPIC]" >&2; exit 64 ;;
esac
STATE=finalize; MODE=single-pr; VIS=public; EXEC_MODE=""; INTENT=continue
while [ "$#" -gt 0 ]; do
    case "$1" in
        --state) STATE="$2"; shift ;;
        --mode) MODE="$2"; shift ;;
        --visibility) VIS="$2"; shift ;;
        --exec-mode) EXEC_MODE="$2"; shift ;;
        --intent) INTENT="$2"; shift ;;
        *) echo "setup-deliver: unknown option $1" >&2; exit 64 ;;
    esac
    shift
done

case "$STATE" in
    finalize) R=$(bash "$SCOPE_SETUP" "$TOPIC" --docs all --mode "$MODE" --pointer 3 --intent "$INTENT") ;;
    split) R=$(bash "$SCOPE_SETUP" "$TOPIC" --docs upstreams --split) ;;
    plan) R=$(bash "$SCOPE_SETUP" "$TOPIC" --docs all --mode "$MODE") ;;
    executed) R=$(bash "$SCOPE_SETUP" "$TOPIC" --docs executed) ;;
    mid-hop) R=$(bash "$SCOPE_SETUP" "$TOPIC" --docs upstreams --pointer 2 --intent "$INTENT") ;;
    *) echo "setup-deliver: unknown --state $STATE" >&2; exit 64 ;;
esac
cd "$R"

{
    printf '# %s\n' "$TOPIC"
    case "$VIS" in
        public) printf '\n## Repo Visibility: Public\n' ;;
        private) printf '\n## Repo Visibility: Private\n' ;;
        none) ;;
        *) echo "setup-deliver: unknown --visibility $VIS" >&2; exit 64 ;;
    esac
    [ "$EXEC_MODE" = auto ] && printf '\n## Execution Mode: auto\n'
} >CLAUDE.md

if [ -f "docs/plans/PLAN-$TOPIC.md" ]; then
    case "$MODE" in
        coordinated) src="$HERE/plans/PLAN-deliver-coordinated.md" ;;
        *) src="$HERE/plans/PLAN-deliver-single.md" ;;
    esac
    sed -e "s/@TOPIC@/$TOPIC/g" -e "s/^execution_mode: .*/execution_mode: $MODE/" "$src" >"docs/plans/PLAN-$TOPIC.md"
fi

git add -A CLAUDE.md docs
git -c user.email=eval@example.invalid -c user.name=eval commit -q -m "chore: $TOPIC eval fixture" || true
printf '%s\n' "$R"
