#!/usr/bin/env bash
# record-write.sh -- replace the coordinator record's whole state. Agent-run;
# every record update, record-holding.sh's included, goes through here so all
# of them share the same checks.
#
# The record is rewritten, never appended to: the state is one canonical
# render, written whole into the coordinator's session (record/meta and one key
# per section). Before writing it:
#   - the session must pass `coord-log.sh provenance` and show no directed
#     transition in the run (exit 10);
#   - the body must parse as a canonical record for this scope (exit 65);
#   - a fresh read must show the session holding this scope's record (exit
#     10), so a record that isn't there is never written over;
#   - the live record's written time must equal the body's own, the time of
#     the version it was edited from (exit 12, record-changed), so a write that
#     landed since the read, by another writer, is never silently overwritten;
#   - when the host is public, no repository the state names (a Holdings Repo,
#     a Pull request link, a Side effects Target, or any other string) may be
#     private or unreadable (exit 65, naming it): this script reads each named
#     repository's visibility and refuses a value naming one;
#   - the Decisions section must be as the live record has it (exit 65): only
#     record-decision.sh changes it, through the same write core;
#   - the body is always re-rendered with this script's own written time,
#     never the one in the body, since record-confirm.sh trusts that time,
#     and a render over 60,000 bytes is refused (exit 13, record-full);
#   - once the run has entered `dispatch`, Deferrals rows disposed as
#     `filed ...` or `closed: ...` are dropped before that render. Carried rows
#     stay. Before the first dispatch they stay too, because the deferral check
#     compares them with a predecessor's until then.
#
# Usage:
#   record-write.sh --session S --body-file F [--end YYYY-MM-DD]
#                   [--pushed-head TOPIC SHA]
#   record-write.sh --session S --pushed-head TOPIC SHA
#   record-write.sh [--session S] --scope roadmap|discipline --name N --repo O/R
#                   --skip-session-checks --body-file F [...]   (tests)
#
# --end (discipline only) names the rotation's end date, a real date; a
# rotation's window is its record/rotation key, which record-state.sh writes,
# so the state written here doesn't carry it.
# --pushed-head sets the last pushed head kept beside TOPIC's holding, 40 hex,
# or empty to clear it; every other holding keeps its own. The body has no
# column for it. record-holding.sh is the one script that passes it.
# With no --body-file it sets the head and nothing else: core_write_pushed
# rewrites the one session key that keeps it, past this script's session
# checks but none of the body's, since the body doesn't change.
# The run must have a found record (`coord-log.sh run-facts`); the override
# flags stand in for it in tests, with RS_SESSION naming the session.
#
# Exit codes: 0 written (prints the session holding the record); 10 not a
# record of this scope, no found record, provenance, or a directed transition;
# 12 the record changed since the body was read; 13 the body is over the size
# budget; 11 a write failed; 2 a read failed; 64 usage; 65 the body was
# refused.
#
# The write itself (every check from the parse on) is core_write in
# record-write-core.sh, which only write scripts source.
#
# GitHub reads: gh api --method GET repos/<repo> --jq .private (the host, then
# each named repository). It writes nothing on GitHub.
set -uo pipefail

PROG=record-write
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= BODY= END=
SKIP_CHECKS=0 PUSHED_SET=0 PUSHED_TOPIC= PUSHED_HEAD=

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --body-file) [ $# -ge 2 ] || usage; BODY=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; END=$2; shift 2 ;;
        --pushed-head) [ $# -ge 3 ] || usage; PUSHED_SET=1; PUSHED_TOPIC=$2; PUSHED_HEAD=$3; shift 3 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
if [ -z "$BODY" ]; then
    [ "$PUSHED_SET" = 1 ] && [ -z "$END" ] || usage
else
    [ -r "$BODY" ] || usage
fi
. "$HERE/record-common.sh"
lib_facts
if [ -n "$END" ]; then
    [ "$SCOPE" = discipline ] || { echo "$PROG: --end is for a discipline rotation" >&2; exit 64; }
    lib_valid_date "$END" || usage
fi
lib_write_guard

# Sourcing the core closes the Decisions section (DECISIONS_WRITER=0), and this
# script never opens it: only record-decision.sh does.
. "$HERE/record-write-core.sh"
if [ "$PUSHED_SET" = 1 ]; then
    CORE_PUSHED_SET=1 CORE_PUSHED_TOPIC=$PUSHED_TOPIC CORE_PUSHED_HEAD=$PUSHED_HEAD
fi
if [ -z "$BODY" ]; then core_write_pushed; else core_write; fi
