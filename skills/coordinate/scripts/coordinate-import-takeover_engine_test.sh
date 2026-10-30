#!/usr/bin/env bash
# coordinate-import-takeover_engine_test.sh -- coordinate-open.sh --import
# takes the imported run over in a second workspace, against real koto and the
# shipped coordinate.md, with both workspaces on koto's cloud backend over
# testdata/fake-s3.py (testdata/cloud-hosts.sh): one host, the workspaces
# `work` and `second` each with its own bucket prefix
# (docs/designs/DESIGN-coordinate-successor-continues.md, Phase 5).
#
# Proves, on a run A opened in `work` by one Claude session (a synthetic
# CLAUDE_CODE_SESSION_ID), reconciled to the hub, holding record entries, two
# legs, taken_legs and leg_children, with a `koto request watch` armed on it
# in `work`, and imported into `second` by another Claude session:
#   1. the opener prints imported=A, then outcome=continued, predecessor=A and
#      session=B, a new run, with no carried=, resumed= or rebound= line, and
#      predecessor_stopped=yes (A's last event before koto's session_imported
#      is seconds old);
#   2. watcher=stopped and the watch in `work` has exited and
#      leg_wake=supported, as a takeover on one host reports them, and no
#      state= or tick= line: B opens at the template's first state, so it
#      reconciles in `second` from its first tick;
#   3. `koto session hierarchy B` shows B continuing A, B's PLUGIN_ROOT is
#      this plugin's and its log holds no rebind; every key A held under
#      record/, legs/, taken_legs and leg_children (but record/meta and
#      record/run, which a takeover rewrites) is in B with the same value, and
#      record/host names `work` and A as the source;
#   4. B's record/meta names B's Claude session as driver, its coordinator row
#      names B's session, and it holds exactly one takeover entry naming A and
#      B;
#   5. `koto next A` is refused session_superseded naming B from `second`
#      (the copy) and from `work` (the source, which koto follows through its
#      migration), and a record write to A in `work` is refused; B's first
#      tick exits 0, so only B ticks the run;
#   6. the same import run again from B's Claude session prints
#      outcome=resumed and session=B, adding no takeover entry;
#   7. a run opened in `work` from a copy of the plugin whose coordinate.md
#      declares one more variable (another structure, at a compat the shipped
#      table doesn't list) is imported into `second` and refused
#      template-incompatible,
#      the refusal naming coordinate.md and both compat numbers, with no run
#      taking it over.
# On a koto older than 0.32.0, whose cloud backend can't fence, the import
# resumes the copy as before (imported=, resumed=1, no outcome=), and only
# that is checked.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME and cache,
# every KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and each
# workspace checked to resolve the fake S3 server before a session is
# written. Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not on PATH -- the engine cases did not run"; exit 0; }
. "$HERE/testdata/coordinate-engine-lib.sh"

# One host on the fake bucket: its HOME holds the test-only credentials, and
# every command of this suite runs as that host, CLAUDE_CODE_SESSION_ID set
# per case and no other identity or configuration passed on.
. "$HERE/testdata/cloud-hosts.sh"
ktg_on_exit 's3_stop; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac'
s3_start || { bad "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; done_tests coordinate-import-takeover-engine; exit 1; }
host_make a; ws_make a second
export HOME="$T/hosts/a/userhome" XDG_CACHE_HOME="$T/hosts/a/cache"
unset XDG_CONFIG_HOME CLAUDE_CODE_SESSION_ID
W1=$(ws_path a work); W2=$(ws_path a second)
for w in "$W1" "$W2"; do
    mkdir -p "$w/.niwa" "$w/.claude"
    (cd "$w" && git init -q && git remote add origin https://github.com/acme/widgets.git && printf '.koto/\n' >> .git/info/exclude)
    echo '{}' > "$w/.niwa/instance.json"
    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$w/.claude/settings.json"
done
case "$(cd "$W1" && koto session dir probe)" in "$T"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

# Synthetic Claude session ids, built here so no id-shaped literal ships; B's
# job state file gives its session the name coord-b.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/job-b"
jq -n --arg s "$B_ID" '{sessionId: $s, name: "coord-b", state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-b/state.json"

line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
importer() { # importer <scope name> <run> [plugin root]: the opener in `second` as B; OUT its stdout, ORC its exit
    printf '["docs/roadmaps/ROADMAP-%s.md", "--import", "%s", "--from", "%s"]' "$1" "$2" "$W1" > "$T/args.json"
    OUT=$(cd "$W2" && CLAUDE_CODE_SESSION_ID=$B_ID bash "$PS/coordinate-open.sh" --plugin-root "${3:-$PR}" "$T/args.json" 2>"$T/open.err"); ORC=$?
}
keyset() { # keyset <session> <workdir>: every carried key and its value, but the two a takeover rewrites
    local p k
    for p in record/ legs/ taken_legs leg_children; do
        (cd "$2" && koto context list "$1" --prefix "$p") | jq -r '.[]'
    done | grep -v '^record/meta$' | grep -v '^record/run$' | grep -v '^record/host$' | sort -u | while read -r k; do
        printf '%s %s\n' "$k" "$( (cd "$2" && koto context get "$1" "$k") | jq -cS .)"
    done
}
put() { printf '%s' "$3" > "$T/v.json"; (cd "$W1" && koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null); }

# ---- A: a run in `work`, driven by one Claude session -----------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
db '.prs = [{repo: "acme/widgets", number: 12, title: "feat: one", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/x", headRefOid: "2222222222222222222222222222222222222222", author: "alice", mergeStateStatus: "CLEAN"}]'
three_features imp
seed_record imp "$(record_json roadmap imp | jq -c --argjson a "$(holding feat-1 '{"unit": "Feature 1"}')" '.holdings = [$a]')"
if open_run imp "$W1" && [ "$(at)" = reconcile ] && REACHED=$(at --with-data '{"reconciled":"reported"}') && [ -n "$REACHED" ]; then
    A=$S
    ok "A: the run opens in work and reconciles ($REACHED)"
    printf 'a first account line\n' > "$T/e1"; printf 'a second account line\n' > "$T/e2"
    write_as_agent state-entry.sh --text-file "$T/e1" && write_as_agent state-entry.sh --text-file "$T/e2"
    eq "A: two record entries are written" 0 $?
    put "$A" legs/req-a1/work-on '{"worker":"feat-1","request":"req-a1"}'
    put "$A" legs/req-a2/work-on '{"worker":"feat-2","request":"req-a2"}'
    put "$A" taken_legs '["req-a1:work-on"]'
    put "$A" leg_children '{"req-a1:work-on":"feat-1-session"}'
    BEFORE=$(keyset "$A" "$W1")
    NA=$(printf '%s\n' "$BEFORE" | grep -c .)
    [ "$NA" -ge 6 ] && ok "A: holds record, leg, taken_legs and leg_children keys ($NA)" || bad "A: holds record, leg, taken_legs and leg_children keys" "$BEFORE"
else
    bad "A: the run opens in work and reconciles" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    done_tests coordinate-import-takeover-engine; exit 1
fi
unset CLAUDE_CODE_SESSION_ID

# ---- an older koto resumes the import -----------------------------------------------
if ! koto_keeps_source; then
    importer imp "$A"
    eq "old koto: the import is resumed" "0 $A 1 $A" "$ORC $(line imported) $(line resumed) $(line session)"
    eq "  ... with no takeover" "" "$(line outcome)"
    echo "left out 1-7: this koto is older than 0.32.0, whose cloud backend can't fence an imported run"
    done_tests coordinate-import-takeover-engine; exit
fi

# A's agent still has its watch armed in `work`.
(cd "$W1" && exec koto request watch --session "$A" --timeout-secs 120) > "$T/watch.out" 2>&1 &
WPID=$!
sleep 1
kill -0 "$WPID" 2>/dev/null && ok "A: a koto request watch on A runs in work" || bad "A: a koto request watch on A runs in work" "$(cat "$T/watch.out")"

# ---- 1. B imports A into `second` and takes it over ----------------------------------
importer imp "$A"
eq "1: the opener exits 0" 0 "$ORC"
eq "1: imported= names A" "$A" "$(line imported)"
eq "1: outcome=continued" continued "$(line outcome)"
eq "1: predecessor= names A, the imported copy" "$A" "$(line predecessor)"
B=$(line session)
case "$B" in coordinate-roadmap-imp-2*Z) [ "$B" != "$A" ] && ok "1: session= names a new run ($B)" || bad "1: session= names a new run" "$B" ;; *) bad "1: session= names a new run" "$OUT $(cat "$T/open.err")" ;; esac
eq "1: no carried=, resumed= or rebound= line" "" "$(printf '%s\n' "$OUT" | grep -E '^(carried|resumed|rebound)=')"
eq "1: A's last event before the import is seconds old: predecessor_stopped=yes" yes "$(line predecessor_stopped)"

# ---- 2. watcher= and leg_wake=, and no state= or tick= ----------------------------
eq "2: watcher=stopped" stopped "$(line watcher)"
kill -0 "$WPID" 2>/dev/null && bad "2: the watch on A in work has exited" "pid $WPID still runs" || ok "2: the watch on A in work has exited"
wait "$WPID" 2>/dev/null
eq "2: leg_wake=supported" supported "$(line leg_wake)"
eq "2: no state= or tick= line" "" "$(printf '%s\n' "$OUT" | grep -E '^(state|tick)=')"

# ---- 3. the relation and the carried keys ---------------------------------------------
(cd "$W2" && koto session hierarchy "$B") | grep -qx "continues: $A" && ok "3: koto session hierarchy shows B continuing A" \
    || bad "3: koto session hierarchy shows B continuing A" "$( (cd "$W2" && koto session hierarchy "$B") 2>&1)"
eq "3: B runs this plugin's root" "$PR" "$(cd "$W2" && bash "$PS/coord-log.sh" plugin-root --session "$B" 2>/dev/null | jq -r '.root')"
BLOG="$(cd "$W2" && koto session dir "$B")/koto-$B.state.jsonl"
eq "3: B's log holds no rebind" 0 "$(jq -s '[.[] | select((.type // "") | test("rebind"))] | length' "$BLOG")"
AFTER=$(keyset "$B" "$W2")
# grep, not comm: run-tests.sh's PATH has no comm, and a comparison that
# can't run must fail rather than leave MISSING empty.
MISSING=$(grep -vxF -f <(printf '%s\n' "$AFTER") <<< "$BEFORE"); rc=$?
if [ -z "$BEFORE" ] || [ $rc -gt 1 ]; then bad "3: every key A held is in B with the same value" "no comparison ran (grep exit $rc)"
else eq "3: every key A held is in B with the same value" "" "$MISSING"; fi
HOSTREC=$(cd "$W2" && koto context get "$B" record/host)
grep -qF "$W1" <<< "$HOSTREC" && grep -qF "$A" <<< "$HOSTREC" && ok "3: record/host names work and A as the source" \
    || bad "3: record/host names work and A as the source" "$HOSTREC"

# ---- 4. B's driver, coordinator row and takeover entry -------------------------------
eq "4: B's record/meta names B's Claude session as driver" "$B_ID" "$(cd "$W2" && koto context get "$B" record/meta | jq -r '.driver // empty')"
eq "4: B's coordinator row names B's session" coord-b \
    "$(cd "$W2" && bash "$PS/state-stored-set.sh" --session "$B" --list | jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0] // empty')"
TAKEOVERS=$(cd "$W2" && bash "$PS/state-entry.sh" --session "$B" --list | jq -c '[.[] | select(.kind == "takeover")]')
eq "4: one takeover entry" 1 "$(jq length <<< "$TAKEOVERS")"
jq -r '.[0].text' <<< "$TAKEOVERS" | grep -qF "$B continues $A" && ok "4:   ... naming A and B" || bad "4:   ... naming A and B" "$TAKEOVERS"

# ---- 5. only B ticks the run --------------------------------------------------------
for w in "$W2" "$W1"; do
    NA_OUT=$(cd "$w" && koto next "$A" --no-cleanup 2>&1); rc=$?
    if [ $rc -ne 0 ] && grep -q session_superseded <<< "$NA_OUT" && grep -q "$B" <<< "$NA_OUT"; then
        ok "5: koto next A from ${w##*/} is refused session_superseded, naming B"
    else bad "5: koto next A from ${w##*/} is refused session_superseded, naming B" "rc=$rc $NA_OUT"; fi
done
(cd "$W1" && CLAUDE_CODE_SESSION_ID=$A_ID bash "$PS/state-stored-set.sh" --session "$A" --run cap 3 --by coord-a) > "$T/w.out" 2>&1
[ $? -ne 0 ] && ok "5: a record write to A in work is refused" || bad "5: a record write to A in work is refused" "$(cat "$T/w.out")"
(cd "$W2" && koto next "$B" --no-cleanup) > "$T/b.out" 2>"$T/tick.err"; rc=$?
eq "5: B's first tick exits 0" 0 "$rc"
[ -n "$(jq -r '.state // empty' "$T/b.out" 2>/dev/null)" ] && ok "5:   ... and lands on $(jq -r .state "$T/b.out")" || bad "5:   ... and lands on a state" "$(cat "$T/b.out" "$T/tick.err")"

# ---- 6. the same import again --------------------------------------------------------
importer imp "$A"
eq "6: the same import again resumes B" "0 resumed $B" "$ORC $(line outcome) $(line session)"
eq "6:   ... adding no takeover entry" 1 \
    "$(cd "$W2" && bash "$PS/state-entry.sh" --session "$B" --list | jq '[.[] | select(.kind == "takeover")] | length')"

# ---- 7. a changed template refuses by name ---------------------------------------------
# The copy's template gains a variable, so its structure (the compat
# fingerprint) differs, and its own compat table raises compat and lists the
# new structure there; the shipped table lists neither. A change to directive
# text alone keeps the structure, which the shipped table already lists.
mkdir -p "$T/plugin2"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin2/"
PT=$T/plugin2/skills/coordinate/koto-templates
awk '{ print } /^variables:$/ && !d { print "  COMPAT_PROBE:\n    description: A variable only this copy declares, so its structure differs.\n    default: \"\""; d = 1 }' \
    "$PT/coordinate.md" > "$T/p2.md" && mv "$T/p2.md" "$PT/coordinate.md"
PFP=$(bash "$T/plugin2/skills/coordinate/scripts/template-fingerprint.sh" "$(koto template compile "$PT/coordinate.md" 2>/dev/null)")
jq --arg f "$PFP" '.compat += 1 | .fingerprints[$f] = .compat' "$PT/coordinate.compat.json" > "$T/p2compat.json" && mv "$T/p2compat.json" "$PT/coordinate.compat.json"
printf '["docs/roadmaps/ROADMAP-imp2.md"]' > "$T/args.json"
OTHER=$(cd "$W1" && CLAUDE_CODE_SESSION_ID=$A_ID bash "$T/plugin2/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$T/plugin2" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$OTHER" ] && ok "7: work opens a run from a plugin whose coordinate.md differs" || bad "7: work opens a run from a plugin whose coordinate.md differs" "$(cat "$T/open.err")"
importer imp2 "$OTHER"
eq "7: its import is refused template-incompatible" "2 template-incompatible" "$ORC $(line refused)"
grep -q "compiled from coordinate.md at compat [^ ]* (template [0-9a-f]\{64\}); this plugin ships compat [0-9][0-9]* (template [0-9a-f]\{64\})" "$T/open.err" \
    && ok "7:   ... naming coordinate.md, both compat numbers and both hashes" || bad "7:   ... naming coordinate.md, both compat numbers and both hashes" "$(cat "$T/open.err")"
eq "7:   ... and no run takes it over" "" "$(line outcome)$(line session)"
eq "7:   ... the copy the only run of its scope in second" "$OTHER" \
    "$(cd "$W2" && bash "$PS/coord-log.sh" live-session --scope-slug roadmap-imp2 --all 2>/dev/null)"

done_tests coordinate-import-takeover-engine
