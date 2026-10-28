#!/usr/bin/env bash
#
# check-inline-evidence_test.sh - the inline-evidence check, on the tree and
# on fixtures
#
# The first case runs the check against this repository, so one CI step
# covers both the scan and its own regressions. The rest build a throwaway
# tree under a mktemp directory and assert what the check refuses and what it
# lets through.
#
# Usage: scripts/check-inline-evidence_test.sh
#
# Exit 0 when every case passes, 1 otherwise.
#
# Runs on bash 3.2.

set -uo pipefail
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-inline-evidence.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/inline-evidence.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
ktg_on_exit 'rm -rf "$WORKDIR"'

# --- the tree -----------------------------------------------------------------

out=$(bash "$CHECK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "the repository's skills, references and templates pass no koto evidence inline"
else
  fail "the repository has inline koto evidence (exit $rc):
$out"
fi

# --- fixtures -----------------------------------------------------------------

# run_on <name> <relative path> <line>: a fresh tree holding one file with one
# line; sets OUT and RC from the check over it.
OUT=""
RC=0
run_on() {
  local root="$WORKDIR/$1"
  mkdir -p "$root/$(dirname "$2")"
  printf '%s\n' "$3" > "$root/$2"
  OUT=$(bash "$CHECK" "$root" 2>/dev/null)
  RC=$?
}

refused() { # <name> <path> <line>
  run_on "$1" "$2" "$3"
  if [ "$RC" -eq 1 ] && grep -q -F "$2:1:" <<<"$OUT"; then
    pass "$1: refused, naming $2:1"
  else
    fail "$1: expected exit 1 naming $2:1, got exit $RC: [$OUT]"
  fi
}

allowed() { # <name> <path> <line>
  run_on "$1" "$2" "$3"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    pass "$1: let through"
  else
    fail "$1: expected exit 0 and no sites, got exit $RC: [$OUT]"
  fi
}

refused single-quoted-json skills/x/SKILL.md \
  "koto next <WF> --with-data '{\"mode\": \"issue_backed\", \"issue_number\": \"<N>\"}' --no-cleanup"
refused escaped-double-quoted-json skills/x/references/phases/p.md \
  'koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}" --no-cleanup'
refused env-prefix skills/x/SKILL.md \
  "env -u GH_TOKEN koto next issue_1 --with-data '{\"mode\": \"issue_backed\"}' --no-cleanup"
refused empty-assignment-prefix skills/x/SKILL.md \
  "GH_TOKEN= koto next issue_1 --with-data '{\"mode\": \"issue_backed\"}' --no-cleanup"
refused decisions-record skills/x/koto-templates/x.md \
  "  \`koto decisions record <WF> --with-data '{\"choice\": \"a\", \"rationale\": \"b\"}'\`,"
refused equals-form references/r.md \
  "koto next s --with-data='{\"k\": \"v\"}' --no-cleanup"
refused variable-value koto-templates/t.md \
  'koto next s --with-data "$DATA" --no-cleanup'
refused command-substitution skills/x/SKILL.md \
  'koto next s --with-data "$(jq -n -c "{k: 1}")" --no-cleanup'

allowed file-form skills/x/SKILL.md \
  'koto next <WF> --with-data @"$EV/evidence.json" --no-cleanup'
allowed file-form-bare skills/x/SKILL.md \
  'koto decisions record <WF> --with-data @<scratch>/decision.json'
allowed prose-mention skills/x/koto-templates/x.md \
  '  `koto overrides record`, with or without --with-data, can manufacture'
allowed backticked-flag skills/x/SKILL.md \
  'Every command that passes `--with-data` (`koto next`) passes `@<file>`.'
allowed not-koto skills/x/SKILL.md \
  "some-tool --with-data '{\"k\": \"v\"}'"
allowed evals-fixture skills/x/evals/fixtures/f.md \
  "koto next s --with-data '{\"k\": \"v\"}' --no-cleanup"
allowed outside-scanned-dirs docs/designs/D.md \
  "koto next s --with-data '{\"k\": \"v\"}' --no-cleanup"
allowed not-markdown skills/x/scripts/s.sh \
  "koto next s --with-data '{\"k\": \"v\"}' --no-cleanup"

# Every site is reported, not only the first.
root="$WORKDIR/two-sites"
mkdir -p "$root/skills/x"
printf '%s\n' \
  "koto next a --with-data '{\"k\": 1}' --no-cleanup" \
  "prose" \
  "koto next b --with-data '{\"k\": 2}' --no-cleanup" > "$root/skills/x/SKILL.md"
OUT=$(bash "$CHECK" "$root" 2>/dev/null)
RC=$?
if [ "$RC" -eq 1 ] && grep -q -F "skills/x/SKILL.md:1:" <<<"$OUT" && grep -q -F "skills/x/SKILL.md:3:" <<<"$OUT"; then
  pass "two sites in one file are both reported"
else
  fail "expected both sites reported, got exit $RC: [$OUT]"
fi

# A root that isn't a directory, or more than one argument, is a usage error.
bash "$CHECK" "$WORKDIR/no-such-dir" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ]; then pass "a missing root exits 2"; else fail "a missing root exited $RC, expected 2"; fi
bash "$CHECK" "$WORKDIR" "$WORKDIR" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ]; then pass "two arguments exit 2"; else fail "two arguments exited $RC, expected 2"; fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
