#!/usr/bin/env bash
# coordinate-open_engine_test.sh -- coordinate-open.sh against real koto and
# the shipped coordinate.md.
#
# Proves: a roadmap invocation opens a per-run session with the host taken
# from the repository's origin; text after `--` is decisions and changes no
# setting (`-- --cap 9` leaves the cap as given); the rotation length defaults
# to seven days; a discipline without --host asks and opens nothing; malformed
# values (a path outside docs/roadmaps/, an uppercase discipline, a rotation
# length of 0, a cap of 0, -1 or abc, a parked bound of abc, a host that isn't
# owner/repo, a --reports-to topic that isn't a topic) are refused with no new
# session and the live run left alone; --reports-to sets REPORTS_TO, empty
# without it; ROADMAP_FORM is feature for a roadmap not in the working tree
# and milestone for a roadmap/v2 one there; a
# second valid invocation cancels the first run without deleting its log.
#
# Needs koto and jq; SKIPs (exit 0) without koto, which run-tests.sh --engine
# turns into a failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for b in koto jq git; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open-engine.XXXXXX"); T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"; export GIT_CEILING_DIRECTORIES="$T"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
ln -s "$REPO_ROOT" "$T/plugin"
OPEN="$T/plugin/skills/coordinate/scripts/coordinate-open.sh"
mkdir "$T/repo" && cd "$T/repo" && git init -q && git remote add origin https://github.com/acme/widgets.git
open_() { printf '%s' "$1" > "$T/args.json"; bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" 2>"$T/err"; }
sessions() { koto session list 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' '; }
var() { local d; d=$(koto session dir "$1"); jq -r --arg k "$2" 'select(.type == "workflow_initialized") | .payload.variables[$k]' "$d/koto-$1.state.jsonl"; }

OUT=$(open_ '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","4","--reports-to","ws-lead","--","feature 3 waits","--cap","9"]'); eq "a roadmap invocation opens" 0 $?
S1=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
case "$S1" in coordinate-roadmap-plugin-system-2*Z) pass "the session is per run" ;; *) fail "the session is per run" "$S1" ;; esac
eq "the host is the roadmap's repository" acme/widgets "$(var "$S1" HOST_REPO)"
eq "the cap given before -- is set" 4 "$(var "$S1" CAP)"
eq "the rotation length defaults to seven days" 7 "$(var "$S1" ROTATION_DAYS)"
eq "--reports-to sets the run's escalation target" ws-lead "$(var "$S1" REPORTS_TO)"
eq "a roadmap not in the working tree is read as a feature roadmap" feature "$(var "$S1" ROADMAP_FORM)"

BEFORE=$(sessions)
open_ '["--discipline","ci-health"]' >/dev/null; eq "a discipline without --host asks" 10 $?
eq "asking opens nothing" "$BEFORE" "$(sessions)"
for bad in '["docs/other/ROADMAP-x.md"]' '["--discipline","CI","--host","acme/widgets"]' '["--discipline","ci","--host","acme/widgets","--rotation-days","0"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","0"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","-1"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","abc"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--parked-bound","abc"]' \
           '["--discipline","ci","--host","acme"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--reports-to","-lead"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--reports-to","ws lead"]'; do
    open_ "$bad" >/dev/null; rc=$?
    if [ $rc -ne 0 ] && [ "$(sessions)" = "$BEFORE" ]; then pass "refused, nothing opened: $bad"; else fail "refused, nothing opened: $bad" "rc=$rc"; fi
done
eq "a refused invocation leaves the live run alone" false "$(koto status "$S1" | jq -r .is_terminal)"
sleep 1
OUT=$(open_ '["docs/roadmaps/ROADMAP-plugin-system.md"]'); eq "a second invocation opens" 0 $?
S2=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
printf '%s\n' "$OUT" | grep -qx "cancelled=$S1" && pass "the earlier run is cancelled" || fail "the earlier run is cancelled" "$OUT"
[ -r "$(koto session dir "$S1")/koto-$S1.state.jsonl" ] && pass "the cancelled run's log is kept" || fail "the cancelled run's log is kept"
eq "the new run keeps the default cap" 5 "$(var "$S2" CAP)"
eq "without --reports-to the target is a person (REPORTS_TO empty)" "" "$(var "$S2" REPORTS_TO)"
# A roadmap/v2 roadmap in the working tree opens a milestone run.
mkdir -p docs/roadmaps
printf -- '---\nschema: roadmap/v2\nstatus: Active\n---\n\n# ROADMAP: milestones\n' > docs/roadmaps/ROADMAP-milestones.md
OUT=$(open_ '["docs/roadmaps/ROADMAP-milestones.md"]'); eq "a milestone roadmap's run opens" 0 $?
S3=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... with ROADMAP_FORM milestone" milestone "$(var "$S3" ROADMAP_FORM)"
echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
