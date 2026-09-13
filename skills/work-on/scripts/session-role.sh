#!/usr/bin/env bash
# session-role.sh -- is this koto session a root run, or a child of a batch?
# Part of the work-on skill
#
# Prints `root` or `child` for a koto session name. It is the single
# discriminator for every /work-on behaviour that has to differ between a
# directly-invoked run and one materialized as a child of /execute's
# `spawn_and_await`, so that two such behaviours cannot drift apart into two
# independently invented tests.
#
# Callers ask this script, they do not re-derive the answer:
#
#   ROLE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/session-role.sh" "$WF")
#   [ "$ROLE" = root ] && ...
#
# TEST POSITIVELY FOR `root`. The fail-safe below holds only for a caller that
# does. On a usage error this exits 2 having printed NOTHING to stdout, so a
# caller written as `[ "$ROLE" = child ] || treat-as-root` reads an empty string
# as "not child" and takes the root branch -- passing the flag on a session whose
# role was never determined, which is the one outcome the fail-safe exists to
# prevent. Anything that is not exactly `root` is `child`.
#
# From a work-on.md state directive, call it with koto's own session name:
#
#   bash ${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/session-role.sh {{SESSION_NAME}}
#
# The agent's shell expands ${CLAUDE_PLUGIN_ROOT}, since a directive is prose the
# agent reads; koto substitutes {{SESSION_NAME}} before the agent sees it. A
# {{KEY}} reference resolves when it names a declared `variables:` entry, a
# `capture_stdout_as` capture, or one of the two reserved runtime names
# (SESSION_NAME, SESSION_DIR), and fails template compilation otherwise -- so
# {{SESSION_NAME}} needs no declaration, while {{PLUGIN_ROOT}} would fail here
# because work-on.md declares no such variable. A command koto itself runs (a
# default_action, where there is no agent shell) would have to declare it.
#
# Usage:
#   session-role.sh <session-name>
#
# Exit codes:
#   0 -- a role was determined and printed
#   2 -- usage error (no session name, or more than one argument); nothing is
#        printed to stdout, so see the positive-test rule above
#
# ---------------------------------------------------------------------------
# The signal: koto's own parentage field, not the shape of the name
# ---------------------------------------------------------------------------
#
# koto records parentage explicitly. A session's state-file header carries
# `parent_workflow`, set from the parent when the session is created as a child
# and left unset on a root `koto init`, and koto's own code treats its absence
# as the definition of a root. `koto session list` emits it per session, keyed
# by `id`, which is how a shell reads it.
#
# koto also composes a child's id as `<parent>.<task>`, so a dot in the name
# usually means a child. That shape is NOT the test here, because it is unsound
# in both directions:
#
#   false negative -- koto supports non-composed children created through
#                     `koto init --parent`. Such a child has no dot, would read
#                     as a root, and would then pass `--no-cleanup` and wedge
#                     its parent's converge.
#   false positive -- nothing validates a session name against dots. A root
#                     whose caller chose a name containing one would read as a
#                     child and silently lose the retention this discriminator
#                     exists to grant.
#
# `koto session list` is used rather than `koto workflows` because it is the
# surface whose documented contract is "all sessions": `koto workflows`
# describes itself as listing the workflows "in the current directory", and a
# session whose execution anchor differs from the caller's cwd must not fall
# through to the unknown branch below. Both read the same flat session store
# today, so this is a choice of the contract that will keep holding rather than
# a workaround for a difference that exists now. `koto status` does not emit the
# field at all, so it is not a candidate.
#
# ---------------------------------------------------------------------------
# Which way it fails
# ---------------------------------------------------------------------------
#
# When the lookup cannot produce an answer -- koto absent, no jq, the session
# not listed -- this reports `child` and says why on stderr. That direction is
# chosen from the measured cost of each mistake, not from caution:
#
#   a root misread as a child loses one run's context record. Bad, and
#   recoverable -- the run's artifacts are still on the branch and in the PR.
#
#   a child misread as a root passes `--no-cleanup` on its terminal tick, which
#   suppresses the `request_store.result` and `ChildCompleted` events that
#   /execute's `children-complete` gate reads to learn the child finished. The
#   parent then reports `converge_blocked: true` permanently, with no event left
#   to emit, and the batch cannot be finished without manual intervention.
#
# So an unknown answer takes the recoverable failure, loudly.
#
# ---------------------------------------------------------------------------
#
# The first caller is the terminal-tick retention rule (#360). Later callers
# should route through here rather than re-deriving the test: if koto changes
# how it records parentage, this file is the one place that changes, and
# skills/work-on/scripts/terminal-retention_test.sh describes the behaviour
# ("a child classifies as child") rather than the mechanism, so the tests
# survive that swap.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    echo "usage: session-role.sh <session-name>" >&2
    exit 2
fi

SESSION="$1"

unknown() {
    echo "session-role.sh: cannot determine the role of '$SESSION' ($1);" \
         "reporting child, which withholds terminal-tick retention rather" \
         "than risking a permanently blocked parent converge" >&2
    echo child
    exit 0
}

# Nothing below discards a diagnostic. The probes test only the exit status of a
# shell builtin that produces no output, and both tools are left free to write to
# stderr: a caller who lands on the `unknown` branch needs the tool's own reason
# for it, and references/tool-diagnostic-discards.md is exactly the policy that a
# fallback entered silently is a failure nobody sees.
if ! command -v koto >/dev/null 2>&1; then
    unknown "the koto CLI is not on PATH"
fi
if ! command -v jq >/dev/null 2>&1; then
    unknown "jq is not on PATH"
fi

if ! LISTING=$(koto session list); then
    unknown "the session listing could not be read"
fi
[ -n "$LISTING" ] || unknown "the session listing was empty"

# A session listed without the field and one carrying it as null both mean root.
# A session absent from the listing yields no output, which is the unknown case.
ROLE=$(printf '%s' "$LISTING" | jq -r --arg s "$SESSION" '
    map(select(.id == $s))
    | if length == 0 then empty
      elif (.[0].parent_workflow // null) == null then "root"
      else "child"
      end
')

case "$ROLE" in
    root|child) echo "$ROLE" ;;
    *)          unknown "session not found in koto session list" ;;
esac
