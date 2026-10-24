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
# session and the live run left alone, and so is --store, whatever its value,
# as usage naming it (the session is the only store); --reports-to sets
# REPORTS_TO, empty without it; ROADMAP_FORM is feature for a roadmap not in
# the working tree and milestone for a roadmap/v2 or roadmap/v3 one there; a
# second valid invocation cancels the first run without deleting its log. On a
# koto without the session store's features the only case is the start's
# refusal, store-unsupported, opening no session.
# On two simulated hosts sharing koto's cloud backend (testdata/cloud-hosts.sh
# over testdata/fake-s3.py): a plain session imported on host B arrives with
# every key, and host A's copy then refuses as session_migrated. The opener's
# --import, run on host B: a malformed or settings-bearing import is usage
# and a name that isn't a run of the scope refused session-name, neither of
# them calling `session import`; a discipline one reaches the import, which
# finds no such run; a
# run A opened whose find never ran (no session-store find) is imported, then
# refused session-source, and one A opened from a copy of the plugin at another path
# is imported, then refused session-provenance, naming the carry; a child
# source is refused with koto's import_source_is_child and leaves no session; a
# run from a template B lacks is refused import_template_unavailable, leaving
# no session either, and with --trust-template imported but refused
# template-mismatch, staying on B; with that run live, another import of the
# scope is refused session-live before koto runs.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for b in koto jq git python3; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open-engine.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */coordinate-open-engine.*) rm -rf "$T" ;; esac' EXIT
export HOME="$T/home"; mkdir -p "$HOME"; export GIT_CEILING_DIRECTORIES="$T"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
ln -s "$REPO_ROOT" "$T/plugin"
OPEN="$T/plugin/skills/coordinate/scripts/coordinate-open.sh"
# gh is the testdata/gh stand-in over a DB with no issue and no pull request:
# a fresh start's one lookup for a record still on GitHub (the legacy
# importer's) finds none, and nothing reaches the real gh.
export GH_DB="$T/gh.json"
jq -n '{login: "coord", repos: {"acme/widgets": {private: false, default_branch: "main"}}, issues: [], prs: [],
    branches: {}, commits: {}, permissions: {}, files: {}, fail: []}' > "$GH_DB"
: > "$GH_DB.calls"
mkdir -p "$T/bin" && ln -s "$HERE/testdata/gh" "$T/bin/gh"
export PATH="$T/bin:$PATH"
# koto_store_ready, the session store's koto features.
. "$HERE/testdata/engine-session.sh"
mkdir "$T/repo" && cd "$T/repo" && git init -q && git remote add origin https://github.com/acme/widgets.git
open_() { printf '%s' "$1" > "$T/args.json"; bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" 2>"$T/err"; }
sessions() { koto session list 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' '; }
var() { local d; d=$(koto session dir "$1"); jq -r --arg k "$2" 'select(.type == "workflow_initialized") | .payload.variables[$k]' "$d/koto-$1.state.jsonl"; }

# The session is the record's only store: on a koto without its features
# (`context list --prefix`, `session import`) every start is refused before a
# session opens, so that refusal is all this suite can prove there.
if ! koto_store_ready; then
    open_ '["docs/roadmaps/ROADMAP-plugin-system.md"]' > "$T/out"; rc=$?
    if [ $rc -ne 0 ] && grep -q store-unsupported "$T/out" "$T/err"; then pass "a koto without the session store's features refuses the start as store-unsupported"
    else fail "a koto without the session store's features refuses the start as store-unsupported" "rc=$rc $(cat "$T/out" "$T/err")"; fi
    eq "  ... opening no session" "" "$(sessions)"
    echo "koto lacks the session store's features; the other cases need a newer koto"
    echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit $?
fi

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
# The session is the only store: --store is no longer a setting, whatever its
# value.
for st in session github; do
    open_ "[\"docs/roadmaps/ROADMAP-plugin-system.md\",\"--store\",\"$st\"]" >/dev/null; rc=$?
    if [ $rc -eq 64 ] && grep -q -- '--store' "$T/err" && [ "$(sessions)" = "$BEFORE" ]; then pass "--store $st is usage naming --store, nothing opened"
    else fail "--store $st is usage naming --store, nothing opened" "rc=$rc $(cat "$T/err")"; fi
done
eq "a refused invocation leaves the live run alone" false "$(koto status "$S1" | jq -r .is_terminal)"
sleep 1
OUT=$(open_ '["docs/roadmaps/ROADMAP-plugin-system.md"]'); eq "a second invocation opens" 0 $?
S2=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
grep -qx "cancelled=$S1" <<<"$OUT" && pass "the earlier run is cancelled" || fail "the earlier run is cancelled" "$OUT"
[ -r "$(koto session dir "$S1")/koto-$S1.state.jsonl" ] && pass "the cancelled run's log is kept" || fail "the cancelled run's log is kept"
eq "the new run keeps the default cap" 5 "$(var "$S2" CAP)"
eq "without --reports-to the target is a person (REPORTS_TO empty)" "" "$(var "$S2" REPORTS_TO)"
# A roadmap/v2 roadmap in the working tree opens a milestone run.
mkdir -p docs/roadmaps
printf -- '---\nschema: roadmap/v2\nstatus: Active\n---\n\n# ROADMAP: milestones\n' > docs/roadmaps/ROADMAP-milestones.md
OUT=$(open_ '["docs/roadmaps/ROADMAP-milestones.md"]'); eq "a milestone roadmap's run opens" 0 $?
S3=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... with ROADMAP_FORM milestone" milestone "$(var "$S3" ROADMAP_FORM)"
# So does a roadmap/v3 one, the milestone roadmap that lists its milestones
# under `## Milestones`.
printf -- '---\nschema: roadmap/v3\nstatus: Active\n---\n\n# ROADMAP: milestones v3\n' > docs/roadmaps/ROADMAP-milestones-v3.md
OUT=$(open_ '["docs/roadmaps/ROADMAP-milestones-v3.md"]'); eq "a roadmap/v3 roadmap's run opens" 0 $?
S4=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... with ROADMAP_FORM milestone" milestone "$(var "$S4" ROADMAP_FORM)"

# --- two hosts on koto's cloud backend -----------------------------------------
# Hosts A and B share a bucket served by testdata/fake-s3.py; each has its own
# HOME, cache and workspace (testdata/cloud-hosts.sh). Everything from here
# needs koto's `session import`, which the start above already required.
echo "== two hosts =="
. "$HERE/testdata/cloud-hosts.sh"
trap 's3_stop; case "$T" in */coordinate-open-engine.*) rm -rf "$T" ;; esac' EXIT
s3_start || { fail "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; exit 1; }
host_make a; host_make b
for h in a b; do
    (cd "$T/hosts/$h/work" && git init -q && git remote add origin https://github.com/acme/widgets.git \
        && printf '.koto/\n' >> .git/info/exclude)
    printf -- '---\nname: plain\nversion: "1.0"\ndescription: One state, then done.\ninitial_state: work\nstates:\n  work:\n    accepts:\n      status:\n        type: enum\n        values: [ok]\n        required: true\n    transitions:\n      - target: done\n        when:\n          status: ok\n  done:\n    terminal: true\n---\n\n## work\n\nSubmit `status: ok`.\n\n## done\n\nTerminal.\n' \
        > "$T/hosts/$h/work/plain.md"
done
host_on a koto init plain-run --template plain.md > /dev/null 2>"$T/err"; eq "a plain session opens on host A" 0 $?
printf '{"a":1}' | host_on a koto context add plain-run record/meta > /dev/null 2>"$T/err"
printf '{"b":2}' | host_on a koto context add plain-run legs/r1/deliver > /dev/null 2>"$T/err"
host_on b koto template compile plain.md > /dev/null 2>"$T/err"
OUT=$(host_on b koto session import plain-run --from "$(host_ws a)" 2>"$T/err"); eq "host B imports it" 0 $?
eq "  ... with every key" 2 "$(printf '%s' "$OUT" | jq -r .keys)"
eq "  ... readable on B" '{"b":2}' "$(host_on b koto context get plain-run legs/r1/deliver 2>&1)"
host_on a koto context get plain-run record/meta > "$T/out" 2>"$T/err"; eq "host A's copy then refuses" 2 $?
grep -q session_migrated "$T/out" && pass "  ... as session_migrated" || fail "  ... as session_migrated" "$(cat "$T/out" "$T/err")"

# --- the opener's --import -----------------------------------------------------
# Host B runs the opener with koto behind a shim that logs every call, so a
# refusal made before koto runs is seen to make no `session import`.
echo "== --import =="
REAL_KOTO=$(command -v koto)
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$T/koto-calls" "$REAL_KOTO" > "$T/koto-shim"
chmod +x "$T/koto-shim"
import_b() { # import_b <args json>: the opener on host B; output in $T/out, stderr in $T/err
    : > "$T/koto-calls"
    printf '%s' "$1" > "$T/args.json"
    host_on b env KOTO_BIN="$T/koto-shim" bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" > "$T/out" 2>"$T/err"
}
# The opener's feature probe runs `session import --help`, which imports nothing.
imported() { grep '^session import' "$T/koto-calls" | grep -vc -- ' --help$'; }
RM='docs/roadmaps/ROADMAP-plugin-system.md'
WS_A=$(host_ws a)

for bad in "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\"]" \
           "[\"$RM\",\"--from\",\"$WS_A\"]" \
           "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\",\"--from\",\"work\"]" \
           "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\",\"--from\",\"$WS_A\",\"--cap\",\"4\"]" \
           "[\"$RM\",\"--import\",\"a\",\"--import\",\"b\",\"--from\",\"$WS_A\"]"; do
    import_b "$bad"; rc=$?
    if [ $rc -eq 64 ] && [ "$(imported)" = 0 ]; then pass "usage, nothing imported: $bad"; else fail "usage, nothing imported: $bad" "rc=$rc $(cat "$T/out" "$T/err")"; fi
done
import_b "[\"--discipline\",\"ci\",\"--host\",\"acme/widgets\",\"--import\",\"coordinate-discipline-ci-20260101T000000Z\",\"--from\",\"$WS_A\"]"
eq "--import at discipline scope reaches koto's import, which finds no such run" "2 refused=import_source_not_found" "$? $(cat "$T/out")"
import_b "[\"$RM\",\"--import\",\"plain-run\",\"--from\",\"$WS_A\"]"
eq "a name that isn't a run of the scope is refused" "2 refused=session-name" "$? $(cat "$T/out")"
eq "  ... before any import" 0 "$(imported)"

# Refusals after koto's import, each on a real run host A opened. Each leaves
# the run live on B (the source is marked migrated), so it is cancelled there
# before the next case, which needs no live run of the scope on B.
open_a() { # open_a <plugin root>: the opener on host A with the roadmap alone; the run in $OPENED
    printf '["%s"]' "$RM" > "$T/args-a.json"
    OPENED=$(host_on a bash "$1/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$1" "$T/args-a.json" 2>"$T/open-a.err" | sed -n 's/^session=//p')
}
# A run whose find never ran, so it never recorded the session store
# (coord/source.json): no record, and no run a start would resume.
open_a "$T/plugin"
[ -n "$OPENED" ] && pass "host A opens a plain run of the scope" || fail "host A opens a plain run of the scope" "$(cat "$T/open-a.err")"
import_b "[\"$RM\",\"--import\",\"$OPENED\",\"--from\",\"$WS_A\"]"
eq "a run whose find never recorded the session store is imported, then refused" "2 refused=session-source" "$? $(grep '^refused=' "$T/out")"
host_on b koto cancel "$OPENED" >/dev/null 2>&1
sleep 1
# A run opened from the plugin at another path: the same template, so the same
# hash, but the run's PLUGIN_ROOT isn't this host's.
mkdir -p "$T/plugin2"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin2/"
open_a "$T/plugin2"
[ -n "$OPENED" ] && pass "host A opens a run from a plugin at another path" || fail "host A opens a run from a plugin at another path" "$(cat "$T/open-a.err")"
import_b "[\"$RM\",\"--import\",\"$OPENED\",\"--from\",\"$WS_A\"]"
eq "a run from another plugin path is imported, then refused" "2 refused=session-provenance" "$? $(grep '^refused=' "$T/out")"
grep -q 'a plain start carries its record' "$T/err" && pass "  ... and the refusal names the carry" || fail "  ... and the refusal names the carry" "$(cat "$T/err")"
host_on b koto cancel "$OPENED" >/dev/null 2>&1
eq "  ... and neither refused run is left live on B" "" "$(host_on b bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-plugin-system --all 2>/dev/null)"

# A child session on host A: koto refuses to import it alone.
CHILD=coordinate-roadmap-plugin-system-20260101T000000Z
host_on a koto init parent-run --template plain.md > /dev/null 2>"$T/err"
host_on a koto init "$CHILD" --template plain.md --parent parent-run > /dev/null 2>"$T/err"; eq "a child session opens on host A" 0 $?
import_b "[\"$RM\",\"--import\",\"$CHILD\",\"--from\",\"$WS_A\"]"
eq "a child source is refused with koto's code" "2 refused=import_source_is_child" "$? $(head -1 "$T/out")"
eq "  ... no session on B" "" "$(host_on b koto session list 2>/dev/null | jq -r --arg s "$CHILD" '.[] | select(.id == $s) | .id')"

# A run compiled from a template host B doesn't have: koto refuses it without
# --trust-template; with it the run is imported, then refused as another
# template than the shipped one, and stays on B.
OTHER=coordinate-roadmap-plugin-system-20260102T000000Z
sed 's/One state, then done./Another template./' "$T/hosts/a/work/plain.md" > "$T/hosts/a/work/other.md"
host_on a koto init "$OTHER" --template other.md > /dev/null 2>"$T/err"; eq "a run from another template opens on host A" 0 $?
import_b "[\"$RM\",\"--import\",\"$OTHER\",\"--from\",\"$WS_A\"]"
eq "without --trust-template koto refuses the unknown template" "2 refused=import_template_unavailable" "$? $(head -1 "$T/out")"
grep -q -- '--trust-template' "$T/err" && pass "  ... and the refusal names --trust-template" || fail "  ... and the refusal names --trust-template" "$(cat "$T/err")"
eq "  ... leaving no session on B" "" "$(host_on b koto session list 2>/dev/null | jq -r --arg s "$OTHER" '.[] | select(.id == $s) | .id')"
import_b "[\"$RM\",\"--import\",\"$OTHER\",\"--from\",\"$WS_A\",\"--trust-template\"]"
eq "with --trust-template it is imported, then refused as another template" "2 refused=template-mismatch" "$? $(cat "$T/out")"
eq "  ... koto was asked with --trust-template" 1 "$(grep -c -- "^session import $OTHER --from $WS_A --trust-template\$" "$T/koto-calls")"
eq "  ... and the run stays on B" false "$(host_on b koto status "$OTHER" 2>/dev/null | jq -r .is_terminal)"

# That run is live on B now, so importing another run of the scope would make two.
import_b "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260103T000000Z\",\"--from\",\"$WS_A\"]"
eq "another live run of the scope refuses the import" "2 refused=session-live" "$? $(cat "$T/out")"
eq "  ... before any import" 0 "$(imported)"
echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
