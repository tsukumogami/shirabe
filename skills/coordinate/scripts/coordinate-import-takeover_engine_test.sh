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
#      taking it over;
#   8. the run's role (docs/designs/DESIGN-coordinator-named-roles.md,
#      Decision 1; PRD R5): an import given --role is checked on the source
#      where it is before koto imports, so a mismatch, a dispatcher change
#      naming a session the source doesn't report to, a failed bucket read
#      or a failed predecessor listing (failed=role_read) land nothing: no
#      session here, no migration marker on the source, its record and koto
#      state as they were, and a write from its workspace still accepted; an
#      accepted dispatcher change is written by finish_takeover with its
#      set_by, set and entry, the copy's row keeping the old role; the same
#      import again naming the new role resumes the successor, and naming the
#      old one is refused with the role_import_copy row ending the message
#      and both records unchanged; a source that continues another run
#      refuses a person change, and a dispatcher change whose address its
#      reports-to row holds, naming that run (role_change_self); a role-less
#      source given --role gets its row once the copy lands, and with no
#      --role lands unasked with no role= line, the handover check listing
#      no-role; a source the bucket doesn't hold is refused with koto's code;
#      a dispatcher change naming the source's own session is refused;
#   9. an import's person change is accepted; on an older koto (a stand-in
#      reporting 0.31.0 in front of the real one) an accepted change is written
#      on the resumed copy, and the same import again naming the new role
#      resumes it while naming the old one is refused on the copy; an import
#      whose source marker write failed (the fake bucket refuses that PUT) is
#      refused on a mismatched role with no marker written, then the same
#      import marks the source and a write there is refused; and an import
#      killed before or after the fence refuses a mismatched role against the
#      copy's row and finishes on a matching one.
#  10. a run opened in `work` from a copy of the plugin at another root, the
#      same template, is imported and taken over, nothing written to the copy
#      and record/host on the new run; a record/host write refused there
#      prints the writer's reason and outcome=incomplete, and the same import
#      again finishes it; one cut short before the fence finishes on a re-run
#      that leaves the copy's log one session_imported event.
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

# ---- 8. the run's role on an import ----------------------------------------------
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1; PRD R5. An import
# given --role checks it before koto session import, on the source where it
# is (state-read.sh --run --workspace), so a refused one lands nothing; a copy
# already here is checked on the run its re-run continues. A shim in front of
# the real koto fails every --workspace read (WS_FAIL=1), or only the source's
# predecessor listing (WS_FAIL=continues), with a plain error.
REAL_KOTO=$(command -v koto)
cat > "$T/wsshim" <<EOF
#!/bin/sh
if [ "\$1" = --workspace ]; then
    case "\${WS_FAIL:-}:\$*" in
        1:*|continues:*koto/links/continues/*) echo "koto: the bucket read failed" >&2; exit 1 ;;
    esac
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/wsshim"
# role_src <scope> <run-rows-json>: a run in work, opened by A's Claude session
# as a manager, holding a record whose Run section is <rows>, its find run;
# sets R.
role_src() {
    export CLAUDE_CODE_SESSION_ID=$A_ID
    seed_roadmap "$1"
    RAW_RECORD=1 seed_record "$1" "$(record_json roadmap "$1" | jq -c --argjson r "$2" '.run = $r')"
    open_run "$1" "$W1" && at > /dev/null || { bad "8: $1's run opens in work" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"; unset CLAUDE_CODE_SESSION_ID; return 1; }
    unset CLAUDE_CODE_SESSION_ID
    R=$S
    # Two workspaces on one host share koto's local cache, so what `second`
    # lists of the source before any import is the baseline a refusal keeps.
    HERE_BEFORE=$(here "$R")
}
# rimport <scope> <run> <args-after-the-import json> [KOTO_BIN]: the opener in
# `second` as B; OUT, ORC.
rimport() {
    jq -nc --arg r "docs/roadmaps/ROADMAP-$1.md" --arg i "$2" --arg f "$W1" --argjson a "$3" '[$r, "--import", $i, "--from", $f] + $a' > "$T/args.json"
    OUT=$(cd "$W2" && KOTO_BIN="${4:-koto}" CLAUDE_CODE_SESSION_ID=$B_ID bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
}
imsg() { grep '^coordinate-open: ' "$T/open.err" | tail -1; }
migrated() { (cd "$W1" && koto dashboard "$1" --detail 2>/dev/null) | jq -r '.migrated.target // empty'; }
here() { (cd "$W2" && koto session list 2>/dev/null) | jq -r --arg s "$1" '.[] | select(.id == $s) | .id'; }
srcstate() { printf '%s %s' "$(keyset "$1" "$W1" | $SHA256)" "$(wc -l < "$(cd "$W1" && koto session dir "$1")/koto-$1.state.jsonl" | tr -d ' ')"; }
irow() { (cd "$2" && koto context get "$1" record/run) | jq -r '[.[] | select(.key == "role")] | if length == 0 then "none" else (.[0] | "\(.value)|\(.set_by)") end'; }
ientry() { (cd "$W2" && bash "$PS/state-entry.sh" --session "$1" --list 2>/dev/null) | jq -r '[.[] | select(.text | startswith("Run role"))] | last | .text // empty'; }
# refused_clean <label> <run> <state before>: nothing landed: no copy here (no
# session `second` didn't list before, and none holding koto/imported-from),
# no marker on the source, which is as it was.
copies() { # copies <run>: the run a copy in `second` was imported from (its koto/imported-from), none for no copy
    local x
    # Listed first, as the opener reads it: the listing reads `second`'s
    # part of the bucket, and the get then finds the key the listing names.
    x=$( (cd "$W2" && koto context list "$1" --prefix koto/imported-from > /dev/null 2>&1 \
        && koto context get "$1" koto/imported-from 2>/dev/null) | jq -r '.from_session // empty' 2>/dev/null)
    printf '%s' "${x:-none}"
}
refused_clean() {
    eq "$1:   ... no session under this workspace's prefix" "$HERE_BEFORE|none" "$(here "$2")|$(copies "$2")"
    eq "$1:   ... no migration marker beside the source" "" "$(migrated "$2")"
    eq "$1:   ... the source's record and koto state as they were" "$3" "$(srcstate "$2")"
}
row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "the human", set: "2026-09-26T08:00Z"}'; }
IADDR=coordinate-roadmap-director-plan-20260926T080000Z
IRT="Lane lead at $IADDR"
if role_src imp-r1 "[$(row role manager),$(row reports-to "$IRT"),$(row coordinator coord-a)]"; then
    I1=$R; I1ST=$(srcstate "$I1")
    rimport imp-r1 "$I1" '["--role","director"]'
    eq "8: an import naming director for a source recorded manager is refused role-mismatch before koto imports" "2 refused role-mismatch" "$ORC $(line outcome) $(line reason)"
    eq "8:   ... the whole message, with no import-copy row" "coordinate-open: $I1 is recorded as manager; this start names director. A continuation keeps its role unless an intervention from above changes it; nothing was written and $I1 goes on as it was. Start again naming manager, or no role, or start director as a new lineage." "$(imsg)"
    refused_clean 8 "$I1" "$I1ST"
    rimport imp-r1 "$I1" '["--role","director","--role-change-by","lane-other","--role-change-source","dispatcher"]'
    eq "8: an import's dispatcher change naming a session the source doesn't report to is refused" "2 role-change-refused" "$ORC $(line reason)"
    eq "8:   ... naming the source's reports-to row" "coordinate-open: $I1 reports to $IRT; a role change from a dispatcher has to name the address in that row, and lane-other isn't it. This start names director; nothing was written and $I1 goes on as manager." "$(imsg)"
    refused_clean 8 "$I1" "$I1ST"
    rimport imp-r1 "$I1" "[\"--role\",\"director\",\"--role-change-by\",\"$I1\",\"--role-change-source\",\"dispatcher\"]"
    eq "8: an import's dispatcher change naming the run's own session is refused" "2 role-change-refused" "$ORC $(line reason)"
    eq "8:   ... as role_change_self, naming the source's reports-to row" "coordinate-open: $I1 reports to $IRT, and $I1 is $I1 itself or the run it continues: a run can't change its own role. This start names director; nothing was written and $I1 goes on as manager." "$(imsg)"
    refused_clean 8 "$I1" "$I1ST"
    WS_FAIL=1 rimport imp-r1 "$I1" '["--role","manager"]' "$T/wsshim"
    eq "8: a bucket read of the source's role that fails is failed=role_read, exit 1, never role-less" "1 role_read" "$ORC $(line failed)"
    refused_clean 8 "$I1" "$I1ST"
    WS_FAIL=continues rimport imp-r1 "$I1" '["--role","director","--role-change-by","lane-other","--role-change-source","person"]' "$T/wsshim"
    eq "8: a predecessor listing that fails is failed=role_read, exit 1, never no predecessor" "1 role_read" "$ORC $(line failed)"
    refused_clean 8 "$I1" "$I1ST"
    (cd "$W1" && CLAUDE_CODE_SESSION_ID=$A_ID bash "$PS/state-stored-set.sh" --session "$I1" --run cap 3 --by coord-a) > "$T/w.out" 2>&1
    eq "8: after the refusals a write from the source's workspace is accepted" 0 $?
    T0=$(date -u +%Y-%m-%dT%H:%MZ)
    rimport imp-r1 "$I1" "[\"--role\",\"director\",\"--role-change-by\",\"$IADDR\",\"--role-change-source\",\"dispatcher\"]"
    T1=$(date -u +%Y-%m-%dT%H:%MZ)
    I1B=$(line session)
    eq "8: an accepted dispatcher change imports and takes the copy over" "0 $I1 continued director manager" "$ORC $(line imported) $(line outcome) $(line role) $(line role_changed_from)"
    eq "8:   ... finish_takeover writing the row, set by the address" "director|$IADDR" "$(irow "$I1B" "$W2")"
    ISET=$( (cd "$W2" && koto context get "$I1B" record/run) | jq -r '.[] | select(.key == "role") | .set')
    [[ ! $ISET < $T0 ]] && [[ ! $ISET > $T1 ]] && ok "8:   ... at the write's time" || bad "8:   ... at the write's time" "$T0 <= $ISET <= $T1"
    eq "8:   ... with its entry" "Run role changed from manager to director by $IADDR, an intervention from above; source: dispatcher." "$(ientry "$I1B")"
    eq "8:   ... the copy's row still the old role" "manager|the human" "$(irow "$I1" "$W2")"
    # The same import again, its copy here and fenced: checked on the successor.
    rimport imp-r1 "$I1" '["--role","director"]'
    eq "8: the same import again naming the new role is a resume of the successor" "0 resumed $I1B director" "$ORC $(line outcome) $(line session) $(line role)"
    BSNAP=$(keyset "$I1B" "$W2"); CSNAP=$(keyset "$I1" "$W2")
    rimport imp-r1 "$I1" '["--role","manager"]'
    eq "8: the same import again naming the old role is refused role-mismatch" "2 refused role-mismatch" "$ORC $(line outcome) $(line reason)"
    eq "8:   ... the whole message ending with the role_import_copy row" "coordinate-open: $I1B is recorded as director; this start names manager. A continuation keeps its role unless an intervention from above changes it; nothing was written and $I1B goes on as it was. Start again naming director, or no role, or start manager as a new lineage. $I1B is on this host already, so its role here is director. Run the same import again, naming director or no role, not a plain start: the import marks the source if that's still to do, and its result says how the run goes on here." "$(imsg)"
    eq "8:   ... both records as they were" "$BSNAP|$CSNAP" "$(keyset "$I1B" "$W2")|$(keyset "$I1" "$W2")"
    rimport imp-r1 "$I1" '["--role","manager","--role-change-by","lane-other","--role-change-source","dispatcher"]'
    case "$(imsg)" in "coordinate-open: $I1B reports to $IRT; "*"goes on as director. $I1B is on this host already, so its role here is director. Run the same import again"*) ok "8:   ... and a role-change refusal there ends with it too" ;;
        *) bad "8:   ... and a role-change refusal there ends with it too" "$(imsg)" ;; esac
fi
# A source that continues another run: P1 took P0 over in work. A change
# naming P0, as a person or as a dispatcher whose address the source's
# reports-to row holds, is the run changing its own role.
if role_src imp-r2 "[$(row role manager),$(row reports-to "the human"),$(row coordinator coord-x)]"; then
    P0=$R
    printf '["docs/roadmaps/ROADMAP-imp-r2.md","--role","manager"]' > "$T/args.json"
    OUT=$(cd "$W1" && CLAUDE_CODE_SESSION_ID=$B_ID bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    P1=$(line session)
    eq "8: in work, a run takes P0 over" "continued $P0" "$(line outcome) $(line predecessor)"
    (cd "$W1" && CLAUDE_CODE_SESSION_ID=$B_ID bash "$PS/state-stored-set.sh" --session "$P1" --run reports-to "Prev at $P0" --by coord-a) > /dev/null 2>&1
    P1ST=$(srcstate "$P1") HERE_BEFORE=$(here "$P1")
    rimport imp-r2 "$P1" "[\"--role\",\"director\",\"--role-change-by\",\"$P0\",\"--role-change-source\",\"person\"]"
    eq "8: an import's person change naming the source's predecessor is refused before koto imports" "2 role-change-refused" "$ORC $(line reason)"
    eq "8:   ... as role_change_self" "coordinate-open: $P1 reports to Prev at $P0, and $P0 is $P1 itself or the run it continues: a run can't change its own role. This start names director; nothing was written and $P1 goes on as manager." "$(imsg)"
    refused_clean 8 "$P1" "$P1ST"
    rimport imp-r2 "$P1" "[\"--role\",\"director\",\"--role-change-by\",\"$P0\",\"--role-change-source\",\"dispatcher\"]"
    eq "8: a dispatcher change naming it, the address the reports-to row holds, is refused the same" "2 role-change-refused" "$ORC $(line reason)"
    case "$(imsg)" in "coordinate-open: $P1 reports to Prev at $P0, and $P0 is $P1 itself"*) ok "8:   ... as role_change_self" ;; *) bad "8:   ... as role_change_self" "$(imsg)" ;; esac
    refused_clean 8 "$P1" "$P1ST"
fi
# A source with no role row: given --role it goes on and gets its row once the
# copy lands; with no --role it goes on unasked, the gap left for reconcile.
if role_src imp-r3 "[$(row reports-to "the human"),$(row coordinator coord-a)]"; then
    rimport imp-r3 "$R" '["--role","manager"]'
    eq "8: an import given --role of a role-less source lands" "0 $R continued manager" "$ORC $(line imported) $(line outcome) $(line role)"
    eq "8:   ... its row written once the copy landed, set by the start's --role" "manager|start --role" "$(irow "$(line session)" "$W2")"
fi
if role_src imp-r4 "[$(row reports-to "the human"),$(row coordinator coord-a)]"; then
    rimport imp-r4 "$R" '[]'
    eq "8: an import with no --role of a role-less source lands, printing no ask=role and no role=" "0 $R continued " "$ORC $(line imported) $(line outcome) $(line role)$(line ask)"
    (cd "$W2" && bash "$PS/state-handover.sh" --session "$(line session)" --check) > /dev/null 2> "$T/gate"
    grep -q '^  no-role: ' "$T/gate" && ok "8:   ... and the handover check on it lists no-role" || bad "8:   ... and the handover check on it lists no-role" "$(cat "$T/gate")"
fi
# A source the bucket doesn't hold.
rimport imp-r9 coordinate-roadmap-imp-r9-20260101T000000Z '["--role","manager"]'
case "$ORC $(line refused)" in "2 session_not_found"|"2 workspace_not_found") ok "8: an import given --role of a source the bucket doesn't hold is refused with koto's code, exit 2 ($(line refused))" ;;
    *) bad "8: an import given --role of a source the bucket doesn't hold is refused with koto's code, exit 2" "$ORC $OUT $(cat "$T/open.err")" ;; esac
eq "8:   ... landing nothing" "" "$(here coordinate-roadmap-imp-r9-20260101T000000Z)"

# ---- 9. the role on an import: a person's change, an older koto, a copy already here --
# A person's change on an import no brief launched is accepted.
if role_src imp-r5 "[$(row role manager),$(row reports-to "$IRT"),$(row coordinator coord-a)]"; then
    rimport imp-r5 "$R" '["--role","director","--role-change-by","the human","--role-change-source","person"]'
    I5B=$(line session)
    eq "9: an import's person change on a start no brief launched is accepted" "0 continued director manager" "$ORC $(line outcome) $(line role) $(line role_changed_from)"
    eq "9:   ... finish_takeover writing the row, set by the person named" "director|the human" "$(irow "$I5B" "$W2")"
    eq "9:   ... with its entry" "Run role changed from manager to director by the human, an intervention from above; source: person." "$(ientry "$I5B")"
fi
# An older koto (before 0.32) resumes the import's copy instead of taking it
# over: a stand-in reports koto 0.31.0 and passes every other call to the real
# koto, so the opener takes its resume path.
cat > "$T/oldkoto" <<EOF
#!/bin/sh
[ "\$1" = version ] && { echo "koto 0.31.0 (stand-in)"; exit 0; }
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/oldkoto"
if role_src imp-o1 "[$(row role manager),$(row reports-to "$IRT"),$(row coordinator coord-a)]"; then
    O1=$R
    rimport imp-o1 "$O1" "[\"--role\",\"director\",\"--role-change-by\",\"$IADDR\",\"--role-change-source\",\"dispatcher\"]" "$T/oldkoto"
    eq "9 old koto: an accepted change imports and resumes the copy" "0 $O1 1 $O1 director manager" \
        "$ORC $(line imported) $(line resumed) $(line session) $(line role) $(line role_changed_from)"
    eq "9 old koto:   ... the opener writing the copy's row, set by the address" "director|$IADDR" "$(irow "$O1" "$W2")"
    eq "9 old koto:   ... with its entry" "Run role changed from manager to director by $IADDR, an intervention from above; source: dispatcher." "$(ientry "$O1")"
    rimport imp-o1 "$O1" '["--role","director"]' "$T/oldkoto"
    eq "9 old koto: the same import again naming the new role, no change flags, resumes the copy" "0 1 $O1 director" "$ORC $(line resumed) $(line session) $(line role)"
    OSNAP=$(keyset "$O1" "$W2")
    rimport imp-o1 "$O1" '["--role","manager"]' "$T/oldkoto"
    eq "9 old koto: naming the old role is refused role-mismatch" "2 refused role-mismatch" "$ORC $(line outcome) $(line reason)"
    case "$(imsg)" in "coordinate-open: $O1 is recorded as director; this start names manager. "*" $O1 is on this host already, so its role here is director. Run the same import again, naming director or no role, not a plain start: "*) ok "9 old koto:   ... checked on the copy, the message ending with the role_import_copy row" ;;
        *) bad "9 old koto:   ... checked on the copy, the message ending with the role_import_copy row" "$(imsg)" ;; esac
    eq "9 old koto:   ... the copy as it was" "$OSNAP" "$(keyset "$O1" "$W2")"
fi
# A source with no marker: koto pushed the run but its write of the source's
# marker failed (the fake bucket refuses that PUT), so the source still takes
# writes until the same import runs again. koto 0.34 reports it as
# import_push_failed (older ones as import_unmarked), and on this harness's one
# host, whose two workspaces share koto's local store, the run here then holds
# no koto/imported-from record, so the opener checks the role where the source
# is, which refuses the same mismatch; the role_import_copy ending is checked
# on the copies above that hold the record.
if role_src imp-u1 "[$(row role manager),$(row reports-to "the human"),$(row coordinator coord-a)]"; then
    U1=$R
    printf '/migrated.json\n' > "$T/s3/port.fail-put"
    rimport imp-u1 "$U1" '["--role","manager"]'
    rm -f "$T/s3/port.fail-put"
    case "$(line refused)" in import_unmarked|import_push_failed) ok "9 unmarked: an import whose marker write fails is refused ($(line refused)), exit $ORC" ;;
        *) bad "9 unmarked: an import whose marker write fails is refused import_unmarked" "$ORC $OUT $(cat "$T/open.err")" ;; esac
    eq "9 unmarked:   ... the source unmarked" "" "$(migrated "$U1")"
    USNAP=$(keyset "$U1" "$W2")
    rimport imp-u1 "$U1" '["--role","director"]'
    eq "9 unmarked: a mismatched --role is refused" "2 refused role-mismatch" "$ORC $(line outcome) $(line reason)"
    case "$(imsg)" in "coordinate-open: $U1 is recorded as manager; this start names director. "*) ok "9 unmarked:   ... naming the recorded role and the one asked" ;;
        *) bad "9 unmarked:   ... naming the recorded role and the one asked" "$(imsg)" ;; esac
    eq "9 unmarked:   ... no marker after the refused start, the run's keys as they were" "|$USNAP" "$(migrated "$U1")|$(keyset "$U1" "$W2")"
    rimport imp-u1 "$U1" '["--role","manager"]'
    eq "9 unmarked: the same import naming the recorded role continues the run" "0 continued manager" "$ORC $(line outcome) $(line role)"
    eq "9 unmarked:   ... and marks the source" "$U1" "$(migrated "$U1")"
    (cd "$W1" && CLAUDE_CODE_SESSION_ID=$A_ID bash "$PS/state-stored-set.sh" --session "$U1" --run cap 3 --by coord-a) > "$T/w.out" 2>&1
    [ $? -ne 0 ] && ok "9 unmarked:   ... and a write from the source's workspace is refused" || bad "9 unmarked:   ... and a write from the source's workspace is refused" "$(cat "$T/w.out")"
fi
# Imports cut short (koto 0.32 and later): a stand-in kills the opener at the
# fence, koto init --supersede, before it runs (the copy here, not fenced) or
# after (the copy fenced, its successor holding the carried record but no
# finished takeover). The re-run checks the role on the run it continues.
cat > "$T/killkoto" <<EOF
#!/usr/bin/env bash
REAL="$REAL_KOTO"
EOF
cat >> "$T/killkoto" <<'EOF'
# kill_opener: SIGKILL every process from this one's parent up to the
# opener's own bash (the topmost process running coordinate-open.sh; a command
# substitution's subshell shows the same arguments).
kill_opener() {
    local p=$PPID pp chain=
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        chain="$p $chain"
        pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        case "$(ps -ww -o args= -p "$p" 2>/dev/null)" in
            *coordinate-open.sh*) case "$(ps -ww -o args= -p "$pp" 2>/dev/null)" in
                *coordinate-open.sh*) ;; *) kill -9 $chain; exit 137 ;; esac ;;
        esac
        p=$pp
    done
    exit 137
}
case "$1 $*" in "init "*" --supersede "*)
    [ "${KILL_WHEN-}" = before ] && kill_opener
    "$REAL" "$@"; kill_opener ;;
esac
exec "$REAL" "$@"
EOF
chmod +x "$T/killkoto"
for when in before after; do
    if role_src "imp-c$when" "[$(row role manager),$(row reports-to "the human"),$(row coordinator coord-a)]"; then
        C=$R
        KILL_WHEN=$when rimport "imp-c$when" "$C" '["--role","manager"]' "$T/killkoto"
        eq "9 cut $when the fence: the opener is killed there" "137 $C" "$ORC $(line imported)"
        rimport "imp-c$when" "$C" '["--role","director"]'
        eq "9 cut $when the fence: a mismatched --role is refused" "2 refused role-mismatch" "$ORC $(line outcome) $(line reason)"
        case "$(imsg)" in *"is recorded as manager; this start names director."*"is on this host already, so its role here is manager."*) ok "9 cut $when the fence:   ... against the copy's row, ending with the role_import_copy row" ;;
            *) bad "9 cut $when the fence:   ... against the copy's row, ending with the role_import_copy row" "$(imsg)" ;; esac
        rimport "imp-c$when" "$C" '["--role","manager"]'
        eq "9 cut $when the fence: a matching --role is accepted, the takeover finished" "0 continued $C manager" "$ORC $(line outcome) $(line predecessor) $(line role)"
    fi
done

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
printf '["docs/roadmaps/ROADMAP-imp2.md","--role","manager"]' > "$T/args.json"
OTHER=$(cd "$W1" && CLAUDE_CODE_SESSION_ID=$A_ID bash "$T/plugin2/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$T/plugin2" "$T/args.json" 2>"$T/open.err" | sed -n 's/^session=//p')
[ -n "$OTHER" ] && ok "7: work opens a run from a plugin whose coordinate.md differs" || bad "7: work opens a run from a plugin whose coordinate.md differs" "$(cat "$T/open.err")"
importer imp2 "$OTHER"
eq "7: its import is refused template-incompatible" "2 template-incompatible" "$ORC $(line refused)"
grep -q "compiled from coordinate.md at compat [^ ]* (template [0-9a-f]\{64\}); this plugin ships compat [0-9][0-9]* (template [0-9a-f]\{64\})" "$T/open.err" \
    && ok "7:   ... naming coordinate.md, both compat numbers and both hashes" || bad "7:   ... naming coordinate.md, both compat numbers and both hashes" "$(cat "$T/open.err")"
eq "7:   ... and no run takes it over" "" "$(line outcome)$(line session)"
eq "7:   ... the copy the only run of its scope in second" "$OTHER" \
    "$(cd "$W2" && bash "$PS/coord-log.sh" live-session --scope-slug roadmap-imp2 --all 2>/dev/null)"

# ---- 10. an import of a run opened from another plugin root -------------------------
# The copy keeps the plugin root its source ran from, which the record writers
# refuse, so the opener writes nothing to it and record/host lands on the new
# run. A record/host write refused there stops the import with the writer's
# own reason and outcome=incomplete, and the same import again finishes it. An
# import cut short before the fence finishes on a re-run whose koto import
# adds nothing to the copy: its log keeps one session_imported event.
mkdir -p "$T/plugin3"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin3/"
cat > "$T/hostfail" <<EOF
#!/bin/sh
case "\$1 \$2 \${4:-}" in "context add record/host") echo "koto: the test stand-in refuses this record/host write" >&2; exit 1 ;; esac
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/hostfail"
imported_events() { jq -s '[.[] | select(.type == "session_imported")] | length' "$(cd "$W2" && koto session dir "$1")/koto-$1.state.jsonl"; }
host_names() { # host_names <run> <copy>: 0 when <run>'s record/host names work and <copy> as the source
    local h
    h=$(cd "$W2" && koto context get "$1" record/host 2>/dev/null)
    grep -qF "$W1" <<< "$h" && grep -qF "$2" <<< "$h"
}
other_root_src() { PS=$T/plugin3/skills/coordinate/scripts PR=$T/plugin3 role_src "$1" "[$(row role manager),$(row reports-to "the human"),$(row coordinator coord-a)]"; }
if other_root_src imp-x1; then
    X1=$R
    rimport imp-x1 "$X1" '[]'
    eq "10: a run opened from another plugin root is imported and taken over" "0 $X1 continued $X1" \
        "$ORC $(line imported) $(line outcome) $(line predecessor)"
    X1B=$(line session)
    host_names "$X1B" "$X1" && ok "10:   ... record/host on the new run names work and the copy" \
        || bad "10:   ... record/host on the new run names work and the copy" "$(cd "$W2" && koto context get "$X1B" record/host 2>&1)"
fi
if other_root_src imp-x2; then
    X2=$R
    rimport imp-x2 "$X2" '[]' "$T/hostfail"
    eq "10: a record/host write refused on the new run stops the import" "1 host_facts $X2 incomplete host_facts" \
        "$ORC $(line failed) $(line imported) $(line outcome) $(line reason)"
    eq "10:   ... imported= once and no session= line" "1|" "$(printf '%s\n' "$OUT" | grep -c '^imported=')|$(line session)"
    grep -qF "the test stand-in refuses this record/host write" "$T/open.err" \
        && ok "10:   ... the writer's own reason on stderr" || bad "10:   ... the writer's own reason on stderr" "$(cat "$T/open.err")"
    grep -qF "$X2 is imported here, and the same import run again from this session finishes it" "$T/open.err" \
        && ok "10:   ... naming the way to finish it" || bad "10:   ... naming the way to finish it" "$(cat "$T/open.err")"
    rimport imp-x2 "$X2" '[]'
    eq "10: the same import again finishes it" "0 continued $X2" "$ORC $(line outcome) $(line predecessor)"
    X2B=$(line session)
    host_names "$X2B" "$X2" && ok "10:   ... record/host on the new run names work and the copy" \
        || bad "10:   ... record/host on the new run names work and the copy" "$(cd "$W2" && koto context get "$X2B" record/host 2>&1)"
    eq "10:   ... the copy's log holds one session_imported event" 1 "$(imported_events "$X2")"
fi
if other_root_src imp-x3; then
    X3=$R
    KILL_WHEN=before rimport imp-x3 "$X3" '[]' "$T/killkoto"
    eq "10 cut before the fence: the opener is killed there, the copy here" "137 1" "$ORC $(imported_events "$X3")"
    rimport imp-x3 "$X3" '[]'
    eq "10 cut before the fence: the same import again finishes it" "0 continued $X3" "$ORC $(line outcome) $(line predecessor)"
    eq "10 cut before the fence:   ... its koto import adding no second session_imported event" 1 "$(imported_events "$X3")"
    host_names "$(line session)" "$X3" && ok "10 cut before the fence:   ... record/host on the new run" \
        || bad "10 cut before the fence:   ... record/host on the new run" "$(cat "$T/open.err")"
fi

done_tests coordinate-import-takeover-engine
