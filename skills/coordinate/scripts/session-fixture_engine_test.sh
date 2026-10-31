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
# coord/source.json reading `session`. The sections are in state-schema.jq's
# normal form, so each row has the columns a writer leaves.
#
# Proves, one line per case:
#   1. the fixture's keys, written into a run of its scope that a fresh start
#      opened on host A, read back as the fixture holds them;
#   2. the next start on A resumes that run (resumed=1, the same session), and
#      a diff of every key's name and JSON before and after the resume shows
#      only what that start writes into a record whose Run section holds no
#      `skill-` or `workspace-` rules row: one `rules` row per file
#      rule-files.sh lists, after the fixture's rows, which are unchanged (its
#      `rules coordinate` row included), set by the run; one `run` entry,
#      record/entries/000004, naming each label added with its digest; and
#      record/meta's written time, nothing else of record/meta changed;
#   3. host B imports it with --import, and every key of the imported copy
#      but record/host, the import's own, is the same by name and JSON as
#      after the resume on A, with one more where the import writes it (koto
#      0.24.0 and later): koto/imported-from, naming A's session and its
#      session id (an older koto adds no key). On koto 0.32.0 and later B's
#      opener, run as a Claude session, takes the copy over (imported=,
#      outcome=continued, predecessor= the copy, session= a new run), and the
#      new run holds every key under record/ and legs/ the resumed run held,
#      with the same JSON, but record/meta, which keeps the fixture's scope and
#      store, and
#      one entry more, the takeover's; on an older koto the copy is resumed
#      (imported=, resumed=1);
#   4. the run B goes on with (the new run on koto 0.32.0 and later, the copy
#      before) reads the legacy record, its `store session` row included, as
#      found: its find goes on to reconcile_pass and never to record_conflict.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/session-fixture_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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
ktg_on_exit 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac'
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
# A synthetic Claude session id for B's opener, built here so no id-shaped
# literal ships: on koto 0.32.0 and later an import is taken over, which
# records the Claude session running the opener as the new run's driver.
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
CALLER_ID=
tick() { host_on "$ON" koto next "$S" "$@" --no-cleanup 2>"$T/tick.err"; }
# start <args json>: the opener on host $ON, as the Claude session $CALLER_ID
# when it is set; OPEN_OUT its output, S the session.
start() {
    printf '%s' "$1" > "$T/args.json"
    OPEN_OUT=$(host_on "$ON" env ${CALLER_ID:+CLAUDE_CODE_SESSION_ID=$CALLER_ID} bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}
line() { printf '%s\n' "$OPEN_OUT" | sed -n "s/^$1=//p"; }
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
# The fixture's Run section holds no skill- or workspace- rules row, so the
# resume writes one per file this start loaded, read here from the same plugin
# root and working directory, and the entry naming them.
host_on a bash "$PS/rule-files.sh" --plugin-root "$PR" > "$T/rule-files" 2> "$T/rule-files.err"
eq "2: the files the start loaded are listed" 0 $?
[ -s "$T/rule-files" ] && ok "2:   ... at least the skill's own" || bad "2:   ... at least the skill's own" "$(cat "$T/rule-files.err")"
eq "2: every key's name and JSON but record/run, record/meta and the new entry are as before the resume" "" \
    "$(diff <(printf '%s\n' "$BEFORE" | grep -Ev '^record/(run|meta) ') <(printf '%s\n' "$AFTER" | grep -Ev '^record/(run|meta|entries/000004) '))"
eq "2:   ... and the fixture had no entry 000004" "" "$(printf '%s\n' "$BEFORE" | grep '^record/entries/000004 ')"
RUN_BEFORE=$(printf '%s\n' "$BEFORE" | sed -n 's|^record/run ||p')
RUN_AFTER=$(printf '%s\n' "$AFTER" | sed -n 's|^record/run ||p')
eq "2: record/run keeps the fixture's rows unchanged, then one rules row per loaded file, set by the run" \
    "$(jq -cSn --argjson b "$RUN_BEFORE" --arg s "$S" '$b + [inputs | {key: "rules", set_by: $s, value: "\(.label) sha256:\(.digest)"}]' "$T/rule-files")" \
    "$(jq -cS --argjson n "$(jq 'length' <<< "$RUN_BEFORE")" '.[:$n] + (.[$n:] | map(del(.set)))' <<< "$RUN_AFTER")"
eq "2:   ... each new row's Set a minute" true \
    "$(jq --argjson n "$(jq 'length' <<< "$RUN_BEFORE")" '.[$n:] | length > 0 and all(.set | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$"))' <<< "$RUN_AFTER")"
eq "2: the one new entry is the run entry naming each label added with its digest" \
    "$(jq -crn --arg s "$S" '[inputs | "\(.label) sha256:\(.digest)"] | "run 4 Run rules digests of the files this start loaded, set by \($s): added \(join(", "))."' "$T/rule-files")" \
    "$(printf '%s\n' "$AFTER" | sed -n 's|^record/entries/000004 ||p' | jq -r '"\(.kind) \(.n) \(.text)"')"
META_BEFORE=$(printf '%s\n' "$BEFORE" | sed -n 's|^record/meta ||p')
META_AFTER=$(printf '%s\n' "$AFTER" | sed -n 's|^record/meta ||p')
eq "2: record/meta is as before the resume but its written time" "$(jq -cS 'del(.written)' <<< "$META_BEFORE")" "$(jq -cS 'del(.written)' <<< "$META_AFTER")"
eq "2:   ... which the resume moves past the fixture's" true \
    "$(jq -n --argjson b "$META_BEFORE" --argjson a "$META_AFTER" '($a.written | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and $a.written > $b.written')"

echo "== 3. host B imports it =="
# The source's session id, from A's state-file header, for the record koto's
# import writes into the copy.
SRC_ID=$(head -n 1 "$(host_on a koto session dir "$S")/koto-$S.state.jsonl" | jq -r '.session_id // empty')
[ -n "$SRC_ID" ] && ok "3: A's session id is read" || bad "3: A's session id is read" "empty"
ON=b
# koto 0.32.0 and later keep the import's source as a read-only predecessor,
# and the opener takes the copy over into a new run; an older koto's copy is
# resumed.
NEW=
if koto_keeps_source; then
    CALLER_ID=$B_ID
    start "[\"docs/roadmaps/ROADMAP-fixture.md\", \"--import\", \"$FIRST\", \"--from\", \"$WS_A\"]"
    CALLER_ID=
    eq "3: host B imports the run and takes it over" "imported=$FIRST outcome=continued predecessor=$FIRST" \
        "imported=$(line imported) outcome=$(line outcome) predecessor=$(line predecessor)"
    NEW=$S
    [ -n "$NEW" ] && [ "$NEW" != "$FIRST" ] && ok "3:   ... into a new run ($NEW)" \
        || bad "3:   ... into a new run" "$OPEN_OUT $(cat "$T/open.err")"
else
    start "[\"docs/roadmaps/ROADMAP-fixture.md\", \"--import\", \"$FIRST\", \"--from\", \"$WS_A\"]"
    grep -qx "imported=$FIRST" <<< "$OPEN_OUT" && grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "3: host B imports the run and resumes it" \
        || bad "3: host B imports the run and resumes it" "$OPEN_OUT $(cat "$T/open.err")"
fi
S=$FIRST
IMPORTED=$(snap b)
# koto 0.24.0 is the first release whose import writes koto/imported-from; the
# entry-floor job runs this suite on an older koto, whose import adds no key.
KOTO_VER=$(koto version | head -n 1 | sed -n 's/^koto v\{0,1\}\([0-9][0-9]*\)\.\([0-9][0-9]*\)\..*$/\1 \2/p')
[ -n "$KOTO_VER" ] && ok "3: koto's version is read" || bad "3: koto's version is read" "$(koto version 2>&1 | head -n 1)"
read -r KOTO_MAJOR KOTO_MINOR <<< "${KOTO_VER:-0 0}"
if [ "$KOTO_MAJOR" -gt 0 ] || [ "$KOTO_MINOR" -ge 24 ]; then
    EXPECTED=$( { printf '%s\n' "$AFTER"
        printf 'koto/imported-from %s\n' "$(jq -cnS --arg s "$FIRST" --arg i "$SRC_ID" '{from_session: $s, from_session_id: $i}')"
        } | LC_ALL=C sort)
    # koto 0.32.0 and later also write the copy's one continues relation,
    # koto/links/continues/<source>, naming A's session; its body carries the
    # time of the import and the copy's own id, so it is checked on its own.
    REL="koto/links/continues/$FIRST"
    if [ "$KOTO_MAJOR" -gt 0 ] || [ "$KOTO_MINOR" -ge 32 ]; then
        eq "3: the copy's continues relation names A's session and its id" "$FIRST $SRC_ID" \
            "$(printf '%s\n' "$IMPORTED" | sed -n "s|^$REL ||p" | jq -r '"\(.session) \(.session_id)"')"
        IMPORTED=$(printf '%s\n' "$IMPORTED" | grep -v "^$REL ")
    fi
    eq "3: every key but record/host is the same by name and JSON as after the resume, plus koto/imported-from naming A's session" \
        "" "$(diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$IMPORTED"))"
else
    eq "3: every key but record/host is the same by name and JSON as after the resume (koto before 0.24.0 adds no key)" \
        "" "$(diff <(printf '%s\n' "$AFTER") <(printf '%s\n' "$IMPORTED"))"
fi

# The new run carries record/ and legs/ from the fenced copy: every key the
# resumed run held under them but record/meta has the same JSON (the rules
# rows A's resume wrote included: B loads the same files, so its start writes
# none), and the one key more is the takeover's entry. The takeover rewrites record/meta (its driver, the
# takeover and this plugin's compat), keeping the fixture's scope and store.
if [ -n "$NEW" ]; then
    S=$NEW
    CARRIED=$(snap b | grep -E '^(record|legs)/' | grep -v '^record/meta ')
    WANT=$(printf '%s\n' "$AFTER" | grep -E '^(record|legs)/' | grep -v '^record/meta ')
    eq "3: the new run holds every key of the resumed run under record/ and legs/ but record/meta, by name and JSON" \
        "" "$(grep -vxF -f <(printf '%s\n' "$CARRIED") <<< "$WANT")"
    eq "3:   ... and one key more, the takeover's entry" takeover \
        "$(grep -vxF -f <(printf '%s\n' "$WANT") <<< "$CARRIED" | sed 's/^[^ ]* //' | jq -r .kind)"
    eq "3: the new run's record/meta keeps the fixture's scope and store" \
        "$(jq -c '."record/meta" | {scope, store}' "$FX")" "$(host_on b koto context get "$NEW" record/meta | jq -c '{scope, store}')"
fi

echo "== 4. the run B goes on with reads the legacy record =="
[ -z "$NEW" ] || S=$NEW
tick > /dev/null
[ "$(entered b reconcile_pass)" -ge 1 ] 2>/dev/null && ok "4: the find goes on to reconcile_pass" \
    || bad "4: the find goes on to reconcile_pass" "$(cat "$T/tick.err")"
eq "4:   ... and never to record_conflict" 0 "$(entered b record_conflict)"

done_tests session-fixture-engine
