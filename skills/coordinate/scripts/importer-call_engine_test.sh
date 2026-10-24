#!/usr/bin/env bash
# importer-call_engine_test.sh -- when coordinate-open.sh calls the legacy
# importer (skills/coordinate/legacy-import/import.sh), against real koto on two
# simulated hosts sharing koto's cloud backend (testdata/cloud-hosts.sh over
# testdata/fake-s3.py), with the testdata/gh stand-in
# (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The legacy
# importer").
#
# The plugin is a copy whose import.sh logs each call and then runs the real
# importer beside it, so every call the opener makes is seen with its
# arguments. Every start runs from that copy.
#
# Proves, one line per case:
#   1. a fresh start of a roadmap scope (no session of the scope on this host
#      holds record/meta) calls the importer once, for its lookup of this run's
#      session, scope, name and repository, and, with no record on GitHub,
#      for nothing else;
#   2. a start that resumes the live run calls it no more;
#   3. a start that carries an ended run's record across into a new run calls
#      it no more;
#   4. an --import of the run on another host calls it no more, on either host;
#   5. a fresh start of a discipline scope calls it once, for the lookup at
#      discipline scope;
#   6. a fresh start whose lookup finds one open record calls it twice: the
#      lookup, then the import of that record by its number.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/importer-call_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh: the GitHub DB helpers, state_json and the counters. It
# puts testdata/ first on PATH, the koto stand-in included; this suite needs
# the real koto, so PATH is rebuilt with only the gh stand-in in front.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
. "$HERE/testdata/engine-session.sh"
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

# The plugin copy, its importer logging every call.
PR="$T/plugin"
mkdir -p "$PR"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$PR/"
IMP="$PR/skills/coordinate/legacy-import"
mv "$IMP/import.sh" "$IMP/import-real.sh"
cat > "$IMP/import.sh" <<EOF
#!/usr/bin/env bash
# A stand-in that logs the legacy importer's call, then runs it.
printf '%s\n' "\$*" >> "$T/import.calls"
exec bash "\$(dirname "\$0")/import-real.sh" "\$@"
EOF
chmod +x "$IMP/import.sh" "$IMP/import-real.sh"
: > "$T/import.calls"
PS="$PR/skills/coordinate/scripts"
calls() { grep -c . "$T/import.calls"; }
# has_args <line> <flag value>...: the call on that line of the log carries each
# flag with its value, in any order.
has_args() {
    local l=" $(sed -n "$1p" "$T/import.calls") " a
    shift
    for a in "$@"; do case "$l" in *" $a "*) ;; *) return 1 ;; esac; done
}

# Two hosts on one bucket, each workspace a clone-shaped directory in a niwa
# instance that permits every finishing step.
. "$HERE/testdata/cloud-hosts.sh"
trap 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac' EXIT
s3_start || { bad "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; done_tests importer-call-engine; exit 1; }
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
at() { tick "$@" | jq -r '.state // empty'; }
run() { local s=$1; shift; host_on "$ON" bash "$PS/$s" --session "$S" "$@"; } # run <script> <args...>: on session $S, on host $ON
# start <args json>: the opener on host $ON; OPEN_OUT its output, S the session.
start() {
    printf '%s' "$1" > "$T/args.json"
    OPEN_OUT=$(host_on "$ON" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ]
}

db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-calls.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n')"

if ! koto_store_ready; then
    echo "koto lacks the session store's features; a start needs a newer koto"
    done_tests importer-call-engine
    exit $?
fi

echo "== 1. a fresh start =="
start '["docs/roadmaps/ROADMAP-calls.md"]' || { bad "1: the fresh start opens" "$(cat "$T/open.err")"; done_tests importer-call-engine; exit 1; }
ok "1: the fresh start opens"
eq "1: it calls the importer once" 1 "$(calls)"
has_args 1 --lookup && ok "1:   ... for its lookup" || bad "1:   ... for its lookup" "$(cat "$T/import.calls")"
has_args 1 "--session $S" && ok "1:   ... of this run's session" || bad "1:   ... of this run's session" "$(head -1 "$T/import.calls")"
has_args 1 "--scope roadmap" "--name calls" "--repo acme/widgets" && ok "1:   ... at this scope, name and repository" \
    || bad "1:   ... at this scope, name and repository" "$(head -1 "$T/import.calls")"
grep -q -- '--ref' "$T/import.calls" && bad "1:   ... and with no record on GitHub, no import" "$(cat "$T/import.calls")" \
    || ok "1:   ... and with no record on GitHub, no import"
eq "1: the run stops at record_open" record_open "$(at)"
run record-open.sh > /dev/null 2> "$T/w.err"; eq "1: record-open.sh opens the record in the session" 0 $?
eq "1: the next find reaches reconcile" reconcile "$(at --with-data '{"opened":"opened"}')"

echo "== 2. a resume =="
FIRST=$S
sleep 1
start '["docs/roadmaps/ROADMAP-calls.md"]'
grep -qx 'resumed=1' <<< "$OPEN_OUT" && [ "$S" = "$FIRST" ] && ok "2: the next start resumes the run" || bad "2: the next start resumes the run" "$OPEN_OUT $(cat "$T/open.err")"
eq "2:   ... calling the importer no more" 1 "$(calls)"

echo "== 3. a carry across =="
host_on a koto cancel "$S" > /dev/null 2>&1
sleep 1
start '["docs/roadmaps/ROADMAP-calls.md"]'
grep -qx "carried=$FIRST" <<< "$OPEN_OUT" && [ "$S" != "$FIRST" ] && ok "3: a start after the run ended carries its record into a new run" \
    || bad "3: a start after the run ended carries its record into a new run" "$OPEN_OUT $(cat "$T/open.err")"
eq "3:   ... calling the importer no more" 1 "$(calls)"
eq "3: the new run's find reaches reconcile" reconcile "$(at)"

echo "== 4. an import on another host =="
ON=b
start "[\"docs/roadmaps/ROADMAP-calls.md\", \"--import\", \"$S\", \"--from\", \"$WS_A\"]"
grep -qx "imported=$S" <<< "$OPEN_OUT" && grep -qx 'resumed=1' <<< "$OPEN_OUT" && ok "4: host B imports the run and resumes it" \
    || bad "4: host B imports the run and resumes it" "$OPEN_OUT $(cat "$T/open.err")"
eq "4:   ... calling the importer no more" 1 "$(calls)"
ON=a

echo "== 5. a fresh discipline start =="
start '["--discipline", "calls-ops", "--host", "acme/widgets"]' || bad "5: the discipline's first start opens" "$(cat "$T/open.err")"
eq "5: it calls the importer once more" 2 "$(calls)"
has_args 2 --lookup "--session $S" "--scope discipline" "--name calls-ops" && ok "5:   ... for its lookup at discipline scope" \
    || bad "5:   ... for its lookup at discipline scope" "$(sed -n 2p "$T/import.calls")"

echo "== 6. a fresh start whose lookup finds a record =="
# A record still on GitHub for another scope, not in the moved shape, by an
# author with write access, under the title the importer looks for (read from
# the importer, its one definition).
TITLE_PREFIX=$(sed -n 's/^TITLE="\(.*\)\$NAME"$/\1/p' "$REPO_ROOT/skills/coordinate/legacy-import/import.sh")
[ -n "$TITLE_PREFIX" ] || bad "6: the importer's record title is read" "no TITLE= line in import.sh"
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-oldrec.md"] = $t' --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n')"
sed 's/ROADMAP-plugin-system/ROADMAP-oldrec/' "$REPO_ROOT/skills/coordinate/legacy-import/testdata/roadmap.md" > "$T/oldrec.md" # a GitHub record body for this scope, as the importer reads one
db '.issues += [{repo: "acme/widgets", number: 41, title: ($p + "oldrec"), body: $b, state: "open", author: "coord", editor: null}]' \
    --arg p "$TITLE_PREFIX" --rawfile b "$T/oldrec.md"
start '["docs/roadmaps/ROADMAP-oldrec.md"]' || bad "6: the start opens" "$(cat "$T/open.err")"
eq "6: it calls the importer twice more" 4 "$(calls)"
has_args 3 --lookup "--session $S" "--name oldrec" && ok "6:   ... first for the lookup" || bad "6:   ... first for the lookup" "$(sed -n 3p "$T/import.calls")"
if has_args 4 "--ref 41" "--session $S" "--name oldrec" && ! has_args 4 --lookup; then ok "6:   ... then for the import of record 41"
else bad "6:   ... then for the import of record 41" "$(sed -n 4p "$T/import.calls")"; fi

done_tests importer-call-engine
