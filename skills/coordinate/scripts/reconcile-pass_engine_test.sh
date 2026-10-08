#!/usr/bin/env bash
# reconcile-pass_engine_test.sh -- the reconcile_pass and reconcile states, as
# coordinate.md declares them, driven by real koto.
#
# The two state blocks and their directives are lifted verbatim from
# coordinate.md into a skeleton whose start_posture state seals "readable",
# so this tests the template's own declarations. The pass runs through its
# production entry from a copied plugin tree whose
# reconcile-read.sh and reconcile-check.sh are stand-ins; coord-log.sh and
# coord-verdict.sh are the record feature's own.
#
# Proves: a blocked pass and a pending pass hold the workflow in
# reconcile_pass; ticking after the listing re-read is due seals the report
# and moves to reconcile; the record's deferrals are read by the real
# disposal check against koto's own run start, which carries milliseconds,
# and each is reported with its disposition (shirabe#552); reconcile_pass refuses evidence; in reconcile, the
# evidence alone doesn't pass while the report key is absent, agent-written,
# or from an earlier visit, and passes once the sealed report is back; then
# the posture routes to pick_facts, once the handover gate passes (a gap in
# the stored set holds it). Also: no gate names
# reconcile/reasoning.md, both reconcile commands run from the plugin root,
# and the directive doesn't name RECONCILE_SEAL.
#
# Needs koto and jq, and waits 31 seconds once (the listing re-read). SKIPs
# (exit 0) without koto.
# Usage: bash skills/coordinate/scripts/reconcile-pass_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
[ -f "$HERE/coord-log.sh" ] && [ -f "$HERE/coord-verdict.sh" ] || { echo "SKIP: the record feature's coord-log.sh is not beside this script"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-engine.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
# The session store, named explicitly for the pass and this test alike.
export KOTO_SESSIONS_BASE="$HOME/.koto/sessions"
mkdir -p "$KOTO_SESSIONS_BASE"
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

# A copied plugin tree: reconcile's scripts and the record feature's
# session-log helpers, with the reads replaced by stand-ins. The deferral
# re-check is the real one: no GitHub read is involved unless a row says
# `filed #<n>`, and none here does.
PR="$T/plugin"
SC="$PR/skills/coordinate/scripts"
mkdir -p "$SC" "$PR/skills/execute/scripts"
for f in reconcile-pass.sh reconcile-deps.sh reconcile-report.sh reconcile-report-get.sh coord-log.sh coord-verdict.sh \
         deferral-check.sh record-common.sh dispatch-common.sh github-refs.sh; do
    cp "$HERE/$f" "$SC/"
done
cp "$HERE/reconcile-check.sh" "$SC/reconcile-check.real.sh"
cp "$REPO_ROOT/skills/execute/scripts/coord-common.sh" "$PR/skills/execute/scripts/"
STUB="$T/stub"
mkdir -p "$STUB"
cat > "$SC/reconcile-read.sh" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$STUB/reads" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$STUB/reads"
if [ -f "$STUB/read.rc" ]; then echo '{"status":"failed","reason":"the stand-in says so"}'; exit "\$(cat "$STUB/read.rc")"; fi
cat "$STUB/read.out"
EOF
cat > "$SC/reconcile-check.sh" <<EOF
#!/usr/bin/env bash
sub=\$1
n=\$(( \$(cat "$STUB/n.\$sub" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$STUB/n.\$sub"
case "\$sub" in
    host)
        if [ "\$n" = 1 ]; then echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}'
        else echo '{"kind":"host","status":"ok","state":"missed","reads":1,"read_at":"t"}'; fi ;;
    appeared) echo '{"kind":"appeared","status":"ok","prs":[],"read_at":"t"}' ;;
    deferral) exec "\$BASH" "$SC/reconcile-check.real.sh" "\$@" ;;
    *) echo '{"kind":"'"\$sub"'","status":"not_verified","reason":"not served","read_at":"t"}' ;;
esac
EOF
# The handover read the reconcile gate runs: a stand-in whose exit code is
# $STUB/handover.rc (0 when absent), so the gate's own routing is what's tested
# here; record-state_test.sh tests the read itself.
cat > "$SC/record-handover.sh" <<EOF
#!/usr/bin/env bash
rc=\$(cat "$STUB/handover.rc" 2>/dev/null || echo 0)
[ "\$rc" = 0 ] || echo "record-handover: a gap (the stand-in says so)" >&2
exit "\$rc"
EOF
chmod +x "$SC/record-handover.sh"
# Only the stand-ins are made executable here; the copied scripts keep the
# modes they are committed with, so a script the template can't run fails.
chmod +x "$SC/reconcile-read.sh" "$SC/reconcile-check.sh"
jq -nc '{status: "found", scope: {kind: "roadmap", name: "engine-test", repo: "acme/widgets"},
  record: {written: "2026-09-26T12:00:00Z", source: "record", handoff_date: null},
  holdings: [{row: {unit: "Feature", entry_point: "/shirabe:deliver", mode: "--auto", phase: "executing",
    dispatch_status: "dispatched", return_path: "message", worker: "quiet-worker", repo: "acme/widgets",
    branch: "feat/quiet", verified_head: "", dispatched: "2026-09-26", pull_request: ""}, source: "record"}],
  deferrals: [
    {row: {deferral: "open one", reason: "later", raised: "2026-09-25T10:00Z", disposition: ""}, source: "record"},
    {row: {deferral: "closed one", reason: "done", raised: "2026-09-25T10:01Z", disposition: "closed: shipped"}, source: "record"},
    {row: {deferral: "carried one", reason: "waits", raised: "2026-09-25T10:02Z", disposition: "carried 2099-01-01T00:00Z: waits on a release"}, source: "record"}],
  side_effects: [], unparseable: [], reasoning: null}' > "$STUB/read.out"

mkdir -p "$T/work"
cd "$T/work" && git init -q && git commit -q --allow-empty -m init 2>/dev/null

# The skeleton: start_posture seals "readable" (exit 25); reconcile_pass and
# reconcile come from coordinate.md; pick_facts and posture_ask end the run.
SRC="$HERE/../koto-templates/coordinate.md"
BLOCKS=$(awk '/^  reconcile_pass:$/{on=1} /^  posture_ask:$/{on=0} on' "$SRC")
DIRECTIVES=$(awk '/^## reconcile_pass$/{on=1} /^## posture_ask$/{on=0} on' "$SRC")
[ -n "$BLOCKS" ] && [ -n "$DIRECTIVES" ] || { echo "FAIL: the reconcile blocks are not in coordinate.md"; exit 1; }
TPL="$T/skeleton.md"
{
cat <<'EOF'
---
name: reconcile-skeleton
version: "1.0"
description: a skeleton for reconcile-pass_engine_test.sh
initial_state: start_posture
variables:
  PLUGIN_ROOT:
    description: plugin root
    required: true
states:
  start_posture:
    default_action:
      command: '"{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-log.sh" seal --session "{{SESSION_NAME}}" --state start_posture --token readable'
      capture_stdout_as: POSTURE
    gates:
      start_posture_verdict:
        type: command
        command: '"{{PLUGIN_ROOT}}/skills/coordinate/scripts/coord-verdict.sh" --session "{{SESSION_NAME}}" --state start_posture --capture "{{POSTURE}}"'
        overridable: false
    transitions:
      - target: reconcile_pass
        when:
          gates.start_posture_verdict.exit_code: 25
EOF
printf '%s\n' "$BLOCKS"
cat <<'EOF'
  posture_ask:
    terminal: true
  pick_facts:
    terminal: true
---

## start_posture

Seal the posture.

EOF
printf '%s\n' "$DIRECTIVES"
cat <<'EOF'

## posture_ask

Done.

## pick_facts

Done.
EOF
} > "$TPL"

J=$(koto template compile "$TPL" 2>&1) || { echo "FAIL: the skeleton does not compile: $J"; exit 1; }

# Static checks on coordinate.md's own blocks.
CJ=$(koto template compile "$SRC" 2>/dev/null) || { echo "FAIL: coordinate.md does not compile"; exit 1; }
eq "reconcile_pass has no accepts block" null "$(jq -c '.states.reconcile_pass.accepts' "$CJ")"
eq "reconcile_pass does not poll" null "$(jq -c '.states.reconcile_pass.default_action.polling' "$CJ")"
eq "every reconcile_pass gate is overridable: false" true "$(jq '[.states.reconcile_pass.gates[] | .overridable == false] | all' "$CJ")"
eq "reconcile_pass has one transition, to reconcile" '["reconcile"]' "$(jq -c '[.states.reconcile_pass.transitions[].target]' "$CJ")"
eq "every reconcile gate is overridable: false" true "$(jq '[.states.reconcile.gates[] | .overridable == false] | all' "$CJ")"
eq "no gate names reconcile/reasoning.md" 0 "$(jq '[.states[] | (.gates // {})[] | (.command // "") + (.key // "") | select(test("reasoning"))] | length' "$CJ")"
eq "the pass and the report check run from the plugin root" true \
    "$(jq '[.states.reconcile_pass.default_action.command, .states.reconcile.gates.reconcile_report.command] | all(startswith("\"{{PLUGIN_ROOT}}/skills/coordinate/scripts/reconcile-"))' "$CJ")"
eq "the reconcile_pass directive does not name RECONCILE_SEAL" 0 "$(jq '[.states.reconcile_pass | (.directive // "") + (.details // "") | select(test("RECONCILE_SEAL"))] | length' "$CJ")"
for f in $(jq -r '[.states.reconcile_pass.default_action.command, (.states.reconcile_pass.gates[].command), (.states.reconcile.gates[].command)] | .[] | capture("scripts/(?<f>[a-z-]+\\.sh)").f' "$CJ" | sort -u); do
    [ -x "$HERE/$f" ] && pass "$f, which the template runs directly, is executable" || fail "$f, which the template runs directly, is executable"
done
eq "PLUGIN_ROOT is declared without rebind" null "$(jq -c '.variables.PLUGIN_ROOT.rebind' "$CJ")"

S=reconcile-engine
koto init "$S" --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>&1 || { echo "FAIL: koto init"; exit 1; }
next() { koto next "$S" --no-cleanup "$@" 2>/dev/null | jq -r '.state // .error.code // "?"'; }
ctx() { koto context get "$S" "$1" 2>/dev/null; }

# A blocked pass holds the state.
echo 5 > "$STUB/read.rc"
eq "a record read that fails holds the workflow in reconcile_pass" reconcile_pass "$(next)"
ctx reconcile/refusal | grep -q '^case: unreadable' && pass "and names the case in reconcile/refusal" || fail "and names the case in reconcile/refusal" "$(ctx reconcile/refusal)"
koto context exists "$S" reconcile/report.json && fail "no report while blocked" || pass "no report while blocked"
rm -f "$STUB/read.rc"

# A pending pass holds it too: the worker was missed, and its re-read is 30
# seconds away.
eq "a pass with the listing re-read still due holds the workflow in reconcile_pass" reconcile_pass "$(next)"
ctx reconcile/progress | grep -q 're-checks left' && pass "and says so in reconcile/progress" || fail "and says so in reconcile/progress" "$(ctx reconcile/progress)"
r=$(next --with-data '{"reconciled":"reported"}')
[ "$r" != reconcile ] && [ "$(koto status "$S" 2>/dev/null | jq -r .current_state)" = reconcile_pass ] \
    && pass "evidence is refused in reconcile_pass ($r)" || fail "evidence is refused in reconcile_pass" "$r"

sleep 31
eq "once the re-read is done the report is sealed and the workflow moves to reconcile" reconcile "$(next)"
ctx reconcile/report.md | grep -q 'not found on this read' && pass "the sealed report says the worker was not found on this read" || fail "the sealed report says the worker was not found on this read" "$(ctx reconcile/report.md)"
# koto's run start carries milliseconds; the deferral read takes it.
RS=$(bash "$SC/coord-log.sh" run-start --session "$S" 2>/dev/null)
printf '%s' "$RS" | grep -Eq '\.[0-9]+Z$' \
    && pass "the session's run start carries milliseconds" || fail "the session's run start carries milliseconds" "$RS"
ctx reconcile/report.json | jq -e '[.deferrals[] | {deferral, why}] == [{deferral: "open one", why: "empty"}]' >/dev/null \
    && pass "an open deferral is reported undisposed, with why" || fail "an open deferral is reported undisposed, with why" "$(ctx reconcile/report.json | jq -c '.deferrals, .not_verified')"
ctx reconcile/report.json | jq -e '[.deferrals_disposed[] | {deferral, how}] == [{deferral: "closed one", how: "closed"}, {deferral: "carried one", how: "carried 2099-01-01T00:00Z"}]' >/dev/null \
    && pass "each disposed deferral is reported with how" || fail "each disposed deferral is reported with how" "$(ctx reconcile/report.json | jq -c '.deferrals_disposed')"
ctx reconcile/report.json | jq -e '[.not_verified[] | select(.what | startswith("deferral"))] == []' >/dev/null \
    && pass "no deferral is left not verified" || fail "no deferral is left not verified" "$(ctx reconcile/report.json | jq -c '.not_verified')"

# In reconcile, the evidence passes only with the sealed report in place.
# The exact bytes: a $(...) copy would drop the trailing newline, which
# changes the digest and is itself an altered report.
koto context get "$S" reconcile/report.json > "$T/good.json"
koto context remove "$S" reconcile/report.json >/dev/null
eq "with the report key absent, the evidence does not pass" reconcile "$(next --with-data '{"reconciled":"reported"}')"
jq -c '.holdings = []' "$T/good.json" | koto context add "$S" reconcile/report.json >/dev/null
eq "with a report the agent wrote, the evidence does not pass" reconcile "$(next --with-data '{"reconciled":"reported"}')"
koto context add "$S" reconcile/report.json --from-file "$T/good.json" >/dev/null
echo 1 > "$STUB/handover.rc"
eq "with the sealed report back but a gap in the stored set, the handover gate holds" reconcile "$(next --with-data '{"reconciled":"reported"}')"
rm -f "$STUB/handover.rc"
eq "with the sealed report back, the evidence passes and the posture routes to pick_facts" pick_facts "$(next --with-data '{"reconciled":"reported"}')"

# A report sealed in an earlier visit fails once the state is entered again.
S2=reconcile-engine-two
koto init "$S2" --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>&1
jq -c '.holdings = []' "$STUB/read.out" > "$STUB/read.tmp" && mv "$STUB/read.tmp" "$STUB/read.out"
S_SAVE=$S; S=$S2
eq "a record with nothing to re-check seals on its first pass" reconcile "$(next)"
bash "$SC/reconcile-report-get.sh" --session "$S2" --check >/dev/null 2>&1
eq "the sealed report checks in its own visit" 0 "$?"
koto rewind "$S2" >/dev/null 2>&1
eq "a rewind enters reconcile_pass again" reconcile_pass "$(koto status "$S2" 2>/dev/null | jq -r .current_state)"
bash "$SC/reconcile-report-get.sh" --session "$S2" --check >/dev/null 2>&1
eq "a report sealed in an earlier visit to reconcile_pass fails the check" 1 "$?"
S=$S_SAVE

echo
echo "reconcile engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
