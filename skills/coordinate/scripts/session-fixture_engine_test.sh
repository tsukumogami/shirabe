#!/usr/bin/env bash
# session-fixture_engine_test.sh -- a session-store coordinator's keys from the
# release before the GitHub record's removal resume and import on the release
# that removed it, unchanged, against real koto on two simulated hosts sharing
# koto's cloud backend (testdata/cloud-hosts.sh over testdata/fake-s3.py), the
# shipped coordinate.md and the testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The start").
#
# The fixture, testdata/session-fixture/roadmap-keys.json, is every key such a
# coordinator's session held, by name: record/meta with `store: session`, a key
# per section, the Run section holding the legacy `store session` row beside
# the stored set and two crash-set rows, a holding's pushed head, three entries
# (record/entries/<n>), a finished leg's key (legs/<request>/<leg>) and
# coord/source.json reading `session`. The sections were rendered and parsed by
# the codec, so each row has the columns a writer leaves.
#
# Proves, one line per case:
#   1. the fixture's keys, written into a run of its scope that a fresh start
#      opened on host A, read back as the fixture holds them;
#   2. the next start on A resumes that run (resumed=1, the same session), and
#      a diff of every key's name and JSON before and after the resume shows
#      no change;
#   3. host B imports it with --import and resumes it there (imported=,
#      resumed=1), and every key but record/host, the import's own, is the same
#      by name and JSON as before the resume on A;
#   4. the imported run's find reads the legacy record, its `store session` row
#      included, as found: it goes on to reconcile_pass and never to
#      record_conflict.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/session-fixture_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh: the GitHub DB helpers and the counters. It puts testdata/ first
# on PATH, the koto stand-in included; this suite needs the real koto, so PATH
# is rebuilt with only the gh stand-in in front.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
. "$HERE/testdata/engine-session.sh"
FX="$HERE/testdata/session-fixture/roadmap-keys.json"
mkdir -p "$T/bin"
# The gh stand-in finds its DB through GH_DB, which koto's import doesn't pass
# on, so gh on PATH names the DB itself.
printf '#!/bin/sh\nGH_DB=${GH_DB:-%s} exec "%s" "$@"\n' "$GH_DB" "$HERE/testdata/gh" > "$T/bin/gh"
chmod +x "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"

. "$HERE/testdata/cloud-hosts.sh"
trap 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac' EXIT
s3_start || { bad "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; done_tests session-fixture-engine; exit 1; }
host_make a; host_make b
for h in a b; do
    W="$T/hosts/$h/work"
    mkdir -p "$W/.niwa" "$W/.claude"
    (cd "$W" && git init -q && git remote add origin https://github.com/acme/widgets.git && printf '.koto/\n' >> .git/info/exclude)
    echo '{}' > "$W/.niwa/instance.json"
    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$W/.claude/settings.json"
done
WS_A=$(host_ws a)

ON=a
tick() { host_on "$ON" koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"; }
# start <args json>: the opener on host $ON; OPEN_OUT its output, S the session.
start() {
    printf '%s' "$1" > "$T/args.json"
    OPEN_OUT=$(host_on "$ON" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
# snap <host>: every key of $S on the host but record/host, its name and its
# JSON with sorted keys, one line each, sorted by name.
snap() {
    local k
    host_on "$1" koto context list "$S" | jq -r '.[]' | grep -vx record/host | LC_ALL=C sort | while IFS= read -r k; do
        printf '%s %s\n' "$k" "$(host_on "$1" koto context get "$S" "$k" | jq -cS .)"
    done
}
# entered <host> <state>: how many times the run entered the state.
entered() {
    jq -s --arg s "$2" '[.[] | select((.type == "transitioned" or .type == "directed_transition") and .payload.to == $s)] | length' \
        "$(host_on "$1" koto session dir "$S")/koto-$S.state.jsonl"
}

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-fixture.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** In progress\n')"
if ! koto_store_ready; then
    echo "koto lacks the session store's features; a start needs a newer koto"
    done_tests session-fixture-engine
    exit $?
fi
eq "the fixture is the scope's record" '{"kind":"roadmap","name":"fixture"} session' \
    "$(jq -r '."record/meta" | "\(.scope | tojson) \(.store)"' "$FX")"

echo "== 1. the fixture's keys in a run of its scope =="
start '["docs/roadmaps/ROADMAP-fixture.md"]' || { bad "1: a fresh start on A opens a run" "$(cat "$T/open.err")"; done_tests session-fixture-engine; exit 1; }
ok "1: a fresh start on A opens a run"
for k in $(jq -r 'keys[]' "$FX"); do
    jq -c --arg k "$k" '.[$k]' "$FX" | host_on a koto context add "$S" "$k" > /dev/null 2> "$T/add.err" \
        || bad "1: the fixture's $k is written" "$(cat "$T/add.err")"
done
MISS=
for k in $(jq -r 'keys[]' "$FX"); do
    [ "$(host_on a koto context get "$S" "$k" | jq -cS .)" = "$(jq -cS --arg k "$k" '.[$k]' "$FX")" ] || MISS="$MISS $k"
done
eq "1: every fixture key reads back as the fixture holds it" "" "$MISS"
BEFORE=$(snap a)
eq "1:   ... the run holding the fixture's keys" "$(jq -r 'keys | length' "$FX")" "$(printf '%s\n' "$BEFORE" | grep -c .)"

echo "== 2. the next start resumes it =="
FIRST=$S
sleep 1
start '["docs/roadmaps/ROADMAP-fixture.md"]'
grep -qx 'resumed=1' <<< "$OPEN_OUT" && [ "$S" = "$FIRST" ] && ok "2: the next start on A resumes the run" \
    || bad "2: the next start on A resumes the run" "$OPEN_OUT $(cat "$T/open.err")"
S=$FIRST
AFTER=$(snap a)
eq "2: every key's name and JSON are as before the resume" "" "$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER"))"

echo "== 3. host B imports it =="
ON=b
start "[\"docs/roadmaps/ROADMAP-fixture.md\", \"--import\", \"$FIRST\", \"--from\", \"$WS_A\"]"
grep -qx "imported=$FIRST" <<< "$OPEN_OUT" && grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "3: host B imports the run and resumes it" \
    || bad "3: host B imports the run and resumes it" "$OPEN_OUT $(cat "$T/open.err")"
S=$FIRST
IMPORTED=$(snap b)
eq "3: every key but record/host is the same by name and JSON as before the resume" "" "$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$IMPORTED"))"

echo "== 4. the imported run's find reads the legacy record =="
tick > /dev/null
[ "$(entered b reconcile_pass)" -ge 1 ] 2>/dev/null && ok "4: the find goes on to reconcile_pass" \
    || bad "4: the find goes on to reconcile_pass" "$(cat "$T/tick.err")"
eq "4:   ... and never to record_conflict" 0 "$(entered b record_conflict)"

done_tests session-fixture-engine
