#!/usr/bin/env bash
# coordinate-takeover_engine_test.sh -- a second coordinator session takes a
# live run over with coordinate-open.sh, against real koto (0.28.0 or later,
# with `koto init --supersede`) and the shipped coordinate.md.
#
# Proves, on a run A opened by one Claude session (CLAUDE_CODE_SESSION_ID set
# by the suite, a synthetic value per session) and holding one dispatched and
# one parked holding (a verified, ready pull request waiting on a merge),
# record entries, two open legs (one taken), taken_legs and leg_children:
#   1. the opener run by another Claude session from another directory prints
#      outcome=continued, predecessor=A, session=B and, A's last koto event
#      being seconds old and no Claude job for A seen, predecessor_stopped=yes;
#   2. no session is cancelled, `koto session hierarchy B` shows B continuing
#      A, and every key A held under legs/, taken_legs, leg_children and
#      record/ (but record/meta and record/run, which the takeover rewrites)
#      is in B with the same value;
#   3. `koto next A` and a state-stored-set.sh write against A both exit
#      non-zero naming B, and the hub's directive tells A's agent to stop and
#      not re-arm its watch;
#   4. B's first `koto next` exits 0 with no rebind in its log, its first
#      reconcile reports both holdings with the classification A's gave them,
#      and taken_legs and leg_children are as A left them;
#   5. B's record has the coordinator row naming B's session, no told row,
#      record/meta naming B's Claude session as driver, and exactly one
#      takeover entry naming A and B;
#   6. the opener run again from B's Claude session prints outcome=resumed
#      and adds no entry, and the next brief dispatch-worker.sh renders from
#      B tells the worker to report to B's session;
#   7. with the liveness probe's clock 11 minutes on and no Claude job for
#      the predecessor, the same takeover prints predecessor_stopped=no.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and the store
# asserted under the scratch directory. The Claude job directory is a fixture
# (DC_CLAUDE_HOME). Needs koto, jq and git; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure. On a koto without --supersede it
# runs case 0 alone: the opener refuses the takeover and writes nothing.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
# A koto without the fence (older than 0.28.0, the entry floor among them)
# can't take a run over: there the suite proves the opener refuses the
# takeover and writes nothing, and runs no other case.
case "$(koto init --help 2>/dev/null)" in *--supersede*) SUPERSEDE=1 ;; *) SUPERSEDE=0 ;; esac
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

# Synthetic Claude session ids, built here so no id-shaped literal ships.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
export DC_CLAUDE_HOME="$T/claude"
mkdir -p "$DC_CLAUDE_HOME/jobs/job-b"
jq -n --arg s "$B_ID" '{sessionId: $s, name: "coord-b", state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-b/state.json"
# B works from a directory of its own, shaped like work/.
mkdir -p "$T/work2/.niwa" "$T/work2/.claude"
(cd "$T/work2" && git init -q && git remote add origin https://github.com/acme/widgets.git)
cp "$T/work/.niwa/instance.json" "$T/work2/.niwa/"; cp "$T/work/.claude/settings.json" "$T/work2/.claude/"

opener() { # opener <name> <workdir>: coordinate-open.sh as the agent runs it; OUT its stdout, ORC its exit
    printf '["docs/roadmaps/ROADMAP-%s.md"]' "$1" > "$T/args.json"
    OUT=$(cd "$2" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
}
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
keyset() { # keyset <session> <workdir>: every carried key and its value's digest
    local p k
    for p in record/ legs/ taken_legs leg_children; do
        (cd "$2" && koto context list "$1" --prefix "$p") | jq -r '.[]'
    done | grep -v '^record/meta$' | grep -v '^record/run$' | grep -v '^koto/' | sort -u | while read -r k; do
        printf '%s %s\n' "$k" "$( (cd "$2" && koto context get "$1" "$k") | $SHA256 | cut -d' ' -f1)"
    done
}
two_holdings() {
    record_json roadmap "$1" | jq -c --argjson a "$(holding feat-1 '{"unit": "Feature 1"}')" --argjson b "$(holding feat-2 '{"unit": "Feature 2"}')" '.holdings = [$a, $b]'
}
# The takeover run's holdings: feat-1 dispatched on #12, feat-2 parked on #13,
# verified at its head and ready.
VH=1111111111111111111111111111111111111111
dispatched_and_parked() {
    record_json roadmap "$1" | jq -c --argjson a "$(holding feat-1 '{"unit": "Feature 1"}')" \
        --argjson b "$(holding feat-2 "$(jq -nc --arg h "$VH" '{unit: "Feature 2", branch: "feat/y", verified_head: $h, pull_request: "[#13](https://github.com/acme/widgets/pull/13)"}')")" \
        '.holdings = [$a, $b]'
}
classes() { # classes <session> <workdir>: each holding's topic and next_code in the run's sealed reconcile report
    (cd "$2" && bash "$PS/reconcile-report-get.sh" --session "$1") | jq -c '[.report.holdings[] | {topic, next_code}] | sort_by(.topic)'
}
put() { printf '%s' "$3" > "$T/v.json"; (cd "$WD" && koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null); }

# ---- A: a run driven by one Claude session -----------------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
db '.prs = [{repo: "acme/widgets", number: 12, title: "feat: one", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/x", headRefOid: "2222222222222222222222222222222222222222", author: "alice", mergeStateStatus: "CLEAN"},
    {repo: "acme/widgets", number: 13, title: "feat: two", body: "", state: "OPEN", isDraft: false, isCrossRepository: false,
        baseRefName: "main", headRefName: "feat/y", headRefOid: $h, author: "alice", mergeStateStatus: "CLEAN"}]' --arg h "$VH"
three_features takeover; seed_record takeover "$(dispatched_and_parked takeover)"
if open_run takeover && [ "$(at)" = reconcile ] && A_CLASS=$(classes "$S" "$WD") && REACHED=$(at --with-data '{"reconciled":"reported"}') && [ -n "$REACHED" ]; then
    A=$S
    ok "A: the run opens and reconciles ($REACHED)"
    eq "A: its reconcile classifies two holdings" 2 "$(printf '%s' "$A_CLASS" | jq length)"
    printf 'a first account line\n' > "$T/e1"; printf 'a second account line\n' > "$T/e2"
    write_as_agent state-entry.sh --text-file "$T/e1" && write_as_agent state-entry.sh --text-file "$T/e2"
    eq "A: two record entries are written" 0 $?
    put "$A" legs/req-a1/work-on '{"worker":"feat-1","request":"req-a1"}'
    put "$A" legs/req-a2/work-on '{"worker":"feat-2","request":"req-a2"}'
    put "$A" taken_legs '["req-a1:work-on"]'
    put "$A" leg_children '{"req-a1:work-on":"feat-1-session"}'
    BEFORE=$(keyset "$A" "$WD")
    NA=$(printf '%s\n' "$BEFORE" | grep -c .)
    [ "$NA" -ge 6 ] && ok "A: holds record, leg, taken_legs and leg_children keys ($NA)" || bad "A: holds record, leg, taken_legs and leg_children keys" "$BEFORE"
else
    bad "A: the run opens and reconciles" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 0. on a koto without the fence, the takeover is refused -------------------
if [ "$SUPERSEDE" = 0 ]; then
    export CLAUDE_CODE_SESSION_ID=$B_ID
    opener takeover "$T/work2"
    eq "0: a koto without init --supersede refuses the takeover" "2 refused" "$ORC $(line outcome)"
    eq "0:   ... opening no run" "" "$(line session)"
    ALOG="$(koto session dir "$A")/koto-$A.state.jsonl"
    eq "0:   ... and cancelling nothing" 0 "$(jq -s '[.[] | select(.type == "workflow_cancelled")] | length' "$ALOG")"
    eq "0:   ... and A's keys are as they were" "$BEFORE" "$(keyset "$A" "$WD")"
    echo; echo "coordinate-takeover engine: $PASS passed, $FAIL failed (this koto has no init --supersede: only the refusal ran)"
    [ "$FAIL" -eq 0 ]; exit
fi

# ---- 1. B takes it over --------------------------------------------------------
export CLAUDE_CODE_SESSION_ID=$B_ID
opener takeover "$T/work2"
eq "1: the opener exits 0" 0 "$ORC"
eq "1: outcome=continued" continued "$(line outcome)"
eq "1: predecessor= names A" "$A" "$(line predecessor)"
B=$(line session)
case "$B" in coordinate-roadmap-takeover-2*Z) [ "$B" != "$A" ] && ok "1: session= names a new run" || bad "1: session= names a new run" "$B" ;; *) bad "1: session= names a new run" "$OUT $(cat "$T/open.err")" ;; esac
eq "1: A's last event is seconds old and no job for A is seen: predecessor_stopped=yes" yes "$(line predecessor_stopped)"

# ---- 2. nothing cancelled, the relation, the carried keys -------------------------
ALOG="$(koto session dir "$A")/koto-$A.state.jsonl"
eq "2: A is not cancelled" 0 "$(jq -s '[.[] | select(.type == "workflow_cancelled")] | length' "$ALOG")"
grep -q "^cancelled=" <<< "$OUT" && bad "2: the opener cancels nothing" "$OUT" || ok "2: the opener cancels nothing"
(cd "$T/work2" && koto session hierarchy "$B") | grep -qx "continues: $A" && ok "2: koto session hierarchy shows B continuing A" \
    || bad "2: koto session hierarchy shows B continuing A" "$( (cd "$T/work2" && koto session hierarchy "$B") 2>&1)"
AFTER=$(keyset "$B" "$T/work2")
MISSING=$(comm -23 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER"))
eq "2: every key A held is in B with the same value" "" "$MISSING"

# ---- 3. A is refused by name ---------------------------------------------------------
NA_OUT=$(cd "$WD" && koto next "$A" --no-cleanup 2>&1); rc=$?
if [ $rc -ne 0 ] && grep -q session_superseded <<< "$NA_OUT" && grep -q "$B" <<< "$NA_OUT"; then ok "3: koto next A is refused session_superseded, naming B"
else bad "3: koto next A is refused session_superseded, naming B" "rc=$rc $NA_OUT"; fi
eq "3:   ... and A's log gains nothing" "$(wc -l < "$ALOG")" "$( (cd "$WD" && koto next "$A" --no-cleanup >/dev/null 2>&1); wc -l < "$ALOG")"
S=$A write_as_agent state-stored-set.sh --run cap 3 --by "the human"; rc=$?
if [ $rc -ne 0 ] && grep -q "$B" "$T/w.err"; then ok "3: a state-stored-set.sh write against A is refused, naming B"
else bad "3: a state-stored-set.sh write against A is refused, naming B" "rc=$rc $(cat "$T/w.err")"; fi
WAIT_TEXT=$(awk '/^## wait$/{on=1; next} /^## /{on=0} on' "$TPL")
grep -q 'session_superseded' <<< "$WAIT_TEXT" && grep -q "don't re-arm the watch" <<< "$WAIT_TEXT" \
    && ok "3: the hub's directive tells a superseded run's agent to stop and not re-arm its watch" \
    || bad "3: the hub's directive tells a superseded run's agent to stop and not re-arm its watch"

# ---- 4. B ticks with no rebind and reconciles both holdings ------------------------------
S=$B WD=$T/work2
FIRST=$(tick); rc=$?
eq "4: B's first koto next exits 0" 0 "$rc"
BLOG="$(koto session dir "$B")/koto-$B.state.jsonl"
eq "4: no rebind in B's log" 0 "$(jq -s '[.[] | select(.type == "variables_rebound")] | length' "$BLOG")"
N=0; ST=$(printf '%s' "$FIRST" | jq -r '.state // empty')
while [ "$ST" != reconcile ] && [ $N -lt 6 ]; do ST=$(at); N=$((N + 1)); done
eq "4: B reaches its first reconcile" reconcile "$ST"
REPORT=$(cd "$WD" && bash "$PS/reconcile-report-get.sh" --session "$B" --md 2>&1)
grep -q feat-1 <<< "$REPORT" && grep -q feat-2 <<< "$REPORT" && ok "4: B's first reconcile reports both holdings" \
    || bad "4: B's first reconcile reports both holdings" "$REPORT"
eq "4:   ... with the classification A's reconcile gave them" "${A_CLASS:-A unclassified}" "$(classes "$B" "$WD")"
eq "4: B took neither of A's legs again: taken_legs as A left it" '["req-a1:work-on"]' "$( (cd "$WD" && koto context get "$B" taken_legs) | jq -c .)"
eq "4:   ... and leg_children as A left it" '{"req-a1:work-on":"feat-1-session"}' "$( (cd "$WD" && koto context get "$B" leg_children) | jq -c .)"
eq "4: with nobody told B's address, the handover gate holds B at reconcile" reconcile "$(at --with-data '{"reconciled":"reported"}')"

# ---- 5. B's record -------------------------------------------------------------------------
RUN=$(cd "$WD" && koto context get "$B" record/run)
eq "5: B's coordinator row names B's session" coord-b "$(printf '%s' "$RUN" | jq -r '[.[] | select(.key == "coordinator") | .value][0]')"
eq "5: B's told set is empty" 0 "$(printf '%s' "$RUN" | jq '[.[] | select(.key == "told")] | length')"
eq "5: B's record/meta names B's Claude session as driver" "$B_ID true" "$( (cd "$WD" && koto context get "$B" record/meta) | jq -r '"\(.driver) \(.takeover_done)"')"
ENTRIES=$(cd "$WD" && bash "$PS/state-entry.sh" --session "$B" --list 2>/dev/null)
TK=$(printf '%s' "$ENTRIES" | jq -c '[.[] | select(.kind == "takeover")]')
eq "5: exactly one takeover entry" 1 "$(printf '%s' "$TK" | jq length)"
TKT=$(jq -r '.[0].text' <<< "$TK")
grep -q "$A" <<< "$TKT" && grep -q "$B" <<< "$TKT" \
    && ok "5:   ... naming A and B" || bad "5:   ... naming A and B" "$TK"

# ---- 6. a re-run from B resumes ---------------------------------------------------------------
NE=$(printf '%s' "$ENTRIES" | jq length)
opener takeover "$T/work2"
eq "6: the opener again from B's session resumes B" "0 resumed $B" "$ORC $(line outcome) $(line session)"
eq "6:   ... adding no entry" "$NE" "$( (cd "$WD" && bash "$PS/state-entry.sh" --session "$B" --list 2>/dev/null) | jq length)"

# ---- 6. the next brief B renders names B's session as reports_to -------------------------------
# niwa, for the dispatch: `list --json` names the sessions launched so far,
# `dispatch --name <topic>` launches one.
mkdir -p "$T/niwa-bin"
printf '[]\n' > "$T/niwa-sessions.json"
cat > "$T/niwa-bin/niwa" <<EOF
#!/usr/bin/env bash
case "\$1 \${2-}" in
    "list --json") cat "$T/niwa-sessions.json" ;;
    "dispatch --help") : ;;
    dispatch*) shift; t=; while [ \$# -gt 0 ]; do [ "\$1" = --name ] && t=\$2; shift; done
        n="\$(printf '%s' "\$t" | tr '-' '_')-1a2b3c4d"
        jq -c --arg n "\$n" '. + [{name: "w", path: "/w", session_name: \$n}]' "$T/niwa-sessions.json" > "$T/niwa-s.tmp" && mv "$T/niwa-s.tmp" "$T/niwa-sessions.json"
        printf 'Dispatched\n  session name: %s\n' "\$n" ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$T/niwa-bin/niwa"
# B's agent tells both live workers its address, as the handover gate asks.
write_as_agent state-stored-set.sh --told feat-1 --by coord-b && write_as_agent state-stored-set.sh --told feat-2 --by coord-b
eq "6: B records both workers told" 0 $?
eq "6: B is at pick after its reconcile" pick "$(at --with-data '{"reconciled":"reported"}')"
eq "6: B's pick dispatches Feature 3" dispatch "$(at --with-data '{"choice":"dispatch","unit":"feat-3"}')"
brief feat-3 "Feature 3" deliver feat-3 executing > "$T/brief.json"
(cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/brief.json" >/dev/null)
: > "$WD/.niwa/workspace.toml"
(cd "$WD" && NIWA="$T/niwa-bin/niwa" bash "$PS/dispatch-worker.sh" --session "$S" >"$T/dw.out" 2>"$T/dw.err"); DW_RC=$?
rm -f "$WD/.niwa/workspace.toml"
eq "6: dispatch-worker.sh launches the worker from B" 0 "$DW_RC"
BRIEF=$(cat "$WD/.niwa/dispatch-briefs/feat-3.md" 2>/dev/null)
case "$BRIEF" in *'addressed to `coord-b`, the address its record names'*) ok "6: the brief B renders carries B's session as reports_to" ;;
    *) bad "6: the brief B renders carries B's session as reports_to" "$(printf '%s' "$BRIEF" | grep -i 'report to the coordinator') $(cat "$T/dw.err")" ;; esac

# ---- 7. a predecessor quiet for 11 minutes, with no job seen ---------------------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
WD=$T/work
mkdir -p "$T/pcopy" && cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/pcopy/"
if PR=$T/pcopy PS=$T/pcopy/skills/coordinate/scripts to_reconciled quiet "$(two_holdings quiet)"; then
    A2=$S
    export CLAUDE_CODE_SESSION_ID=$B_ID
    # B runs the opener from this plugin and A2 from a copy of it, so the
    # candidate asks for a rebind; the takeover comes first and A2 is never
    # written.
    DC_NOW=$(( $(date +%s) + 660 )) opener quiet "$T/work2"
    eq "7: the takeover of a run quiet for 11 minutes" "0 continued $A2 no" "$ORC $(line outcome) $(line predecessor) $(line predecessor_stopped)"
    eq "7: from another plugin root, A2 is taken over without a rebind" 0 \
        "$(jq -s '[.[] | select(.type == "variables_rebound")] | length' "$(koto session dir "$A2")/koto-$A2.state.jsonl")"
    eq "7:   ... and B2 runs from this plugin's root" "$PR" "$( (cd "$T/work2" && bash "$PS/coord-log.sh" vars --session "$(line session)") | jq -r .PLUGIN_ROOT)"
else
    bad "7: the second run opens and reconciles" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

echo; echo "coordinate-takeover engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
