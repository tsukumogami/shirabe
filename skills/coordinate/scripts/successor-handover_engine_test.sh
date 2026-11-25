#!/usr/bin/env bash
# successor-handover_engine_test.sh -- a roadmap run or a discipline rotation
# hands over to a successor with dispatch-worker.sh --successor, against real
# koto, the shipped coordinate.md and a niwa stand-in.
#
# Proves, on manager runs of a milestone roadmap opened by one Claude session
# (a synthetic CLAUDE_CODE_SESSION_ID per session):
#   1. a run at wait whose only open milestone owes its verdict, its role row
#      written with state-stored-set.sh --run role and its
#      successor_input.json naming no role, entry_args or repo: the mode exits
#      0 and prints session=<name>; the brief's Goal line and the prompt niwa
#      was given both read
#      Run `/shirabe:coordinate <ROADMAP> --role manager` in <owner/repo>.
#      with <ROADMAP> the run's ROADMAP variable and <owner/repo> its host;
#      the Run section niwa found at its call holds one successor row reading
#      `dispatching <topic> <date>` set by the run, and the record afterwards
#      reads `dispatched <topic> <date>`, with an entry naming the topic, the
#      brief's path and the role; the invocation line is the brief's only
#      line naming manager or director, and its keep-alive line names niwa;
#      `--run successor` is still a usage error that leaves the Run section
#      as it was, and the record holding the row reads back; the run's compat
#      reads 2;
#   2. the successor's opener, started from another Claude session with the
#      brief's tokens in its args file and --dispatched-by naming the
#      predecessor, prints outcome=continued and predecessor=<run>; its Run
#      section holds its own coordinator row, role manager and no successor
#      row; both runs' chain-start reads the same; and its first reconcile's
#      record line ends `Role: manager.`;
#   3. the same mode exits 0 with a dispatched row and one niwa launch on a
#      run whose roadmap lists no open milestone, on one whose only open
#      milestone a pause holds, and on one whose only open milestone is
#      parked on a decision;
#   4. a worker dispatch of each of those milestones (the owed verdict, the
#      pause, the decision) still exits 10 naming what holds it, and leaves
#      the Run section, the Holdings, the legs/ keys, the brief directory and
#      niwa's call log as they were;
#   5. a run with no role row refuses the mode with exit 1 naming
#      state-stored-set.sh --session <run> --run role, and leaves the same
#      five things as they were;
#   6. a takeover that doesn't name the run that set the row keeps it: one
#      from a third Claude session with no --dispatched-by, and one naming
#      another run, each against its own predecessor, both continue it and
#      leave the new run's successor row with its value and Set by.
#
# And on discipline rotations opened as --discipline <name> --host
# acme/widgets inside their window:
#   7. a director's run: the mode exits 0 though its input gave no
#      entry_args or repo; the brief's Goal line and niwa's prompt carry
#      `/shirabe:coordinate --discipline ci-health --host acme/widgets --role
#      director`, the brief's one line naming a role, and the row reads
#      dispatched; the successor started from the brief's tokens with
#      --dispatched-by prints outcome=continued and predecessor=<run>, shares
#      the chain start, holds role director and no successor row, and its
#      Record: line names acme/widgets and ends `Role: director.`;
#   8. the mode exits 0 with a dispatched row when pick lists no open issue,
#      when the only one is paused, and when it is parked on a decision; a
#      worker dispatch of the paused issue still exits 10, leaving the
#      record, legs/, briefs and niwa's log as they were;
#   9. no role row, a log run-facts can't read (exit 2) and a run with no
#      found record yet (exit 1) each exit 1 and leave the same as they were;
#  10. the other pairs, a discipline manager and a roadmap director, each
#      render their role on the brief's one role line and report it;
#  11. at each scope, a failed first launch (exit 4, dispatch-failed), the
#      role row changed by a person, and a second dispatch rendering the new
#      role;
#  12. at each scope, a start from the brief's tokens with --role manager
#      against a director's record is refused (role-mismatch, exit 2, the
#      record unchanged), and accepted with --role-change-by the reports-to
#      address and --role-change-source dispatcher.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and the store
# asserted under the scratch directory before any case runs. Needs koto, jq
# and git; SKIPs (exit 0) without one, which run-tests.sh --engine turns into
# a failure. On a koto without init --supersede the takeover cases are left
# out.
#
# Usage: bash skills/coordinate/scripts/successor-handover_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
. "$HERE/testdata/takeover-flags.sh"
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac

# Synthetic Claude session ids, built here so no id-shaped literal ships: A
# drives every predecessor, B starts the successor, C is a third session.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
C_ID=$(printf '%s-0000-4000-8000-%012d' cccccccc 3)
export DC_CLAUDE_HOME="$T/claude"
for j in b:"$B_ID" c:"$C_ID"; do
    mkdir -p "$DC_CLAUDE_HOME/jobs/job-${j%%:*}"
    jq -n --arg s "${j#*:}" --arg n "coord-${j%%:*}" '{sessionId: $s, name: $n, state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-${j%%:*}/state.json"
done
# The successor starts from a directory of its own, shaped like work/.
mkdir -p "$T/work2/.niwa" "$T/work2/.claude"
(cd "$T/work2" && git init -q && git remote add origin https://github.com/acme/widgets.git)
cp "$T/work/.niwa/instance.json" "$T/work2/.niwa/"; cp "$T/work/.claude/settings.json" "$T/work2/.claude/"
BRIEFS="$T/work/.niwa/dispatch-briefs"
TODAY=$(date -u +%Y-%m-%d)

# The niwa stand-in. `dispatch --help` lists the flags the launch reads;
# `list --json` prints the sessions launched so far; a launch logs its
# arguments to calls.log, keeps its prompt, and keeps the Run section the
# predecessor's record holds at that moment (NS_RUN names the run), then
# prints the `session name:` line niwa prints and lists the session. A case
# fails the next launch with NS/fail-next, and with NS/blind-next beside it
# the listing fails from that launch on, while NS/list-fail exists.
NS="$T/niwa-succ"
mkdir -p "$NS"
cat > "$NS/niwa" <<'EOF'
#!/usr/bin/env bash
case "${1-}" in
    list) [ ! -f "$NS/list-fail" ] || exit 1
          cat "$NS/sessions.json" 2>/dev/null || echo '[]' ;;
    dispatch)
        if [ "${2-}" = --help ]; then
            printf 'Flags:\n      --brief string\n      --detach\n      --grant strings\n      --name string\n      --parent-from string\n      --skill string\n'
            exit 0
        fi
        shift
        printf 'niwa dispatch' >> "$NS/calls.log"
        for a in "$@"; do printf ' [%s]' "$a" >> "$NS/calls.log"; done
        echo >> "$NS/calls.log"
        printf '%s\n' "$1" > "$NS/prompt"
        # One failed launch, when the case leaves NS/fail-next: nothing listed.
        # With NS/blind-next beside it, the listing fails from then on too,
        # until the case removes NS/list-fail.
        if [ -f "$NS/fail-next" ]; then
            rm -f "$NS/fail-next"
            [ ! -f "$NS/blind-next" ] || mv "$NS/blind-next" "$NS/list-fail"
            echo "niwa: launch failed" >&2; exit 1
        fi
        bash "$PS/state-read.sh" --session "$NS_RUN" --run > "$NS/run-at-call.json" 2> "$NS/run-at-call.err"
        name=""
        while [ $# -gt 0 ]; do [ "$1" = --name ] && name=$2; shift; done
        n="$(printf '%s' "$name" | tr 'A-Z-' 'a-z_' | cut -c1-40)-1a2b3c4d"
        jq -c --arg n "$n" '. + [{name: "x", path: "/p", session_name: $n}]' "$NS/sessions.json" > "$NS/s.tmp" && mv "$NS/s.tmp" "$NS/sessions.json"
        printf 'Dispatched session 0\n  instance: /p\n  session name: %s\n' "$n"
        ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$NS/niwa"
export NS PS
ns_reset() { echo '[]' > "$NS/sessions.json"; : > "$NS/calls.log"; rm -f "$NS/prompt" "$NS/run-at-call.json" "$NS/fail-next" "$NS/blind-next" "$NS/list-fail"; }

# milestone_roadmap <name> <status>: a milestone roadmap with one milestone,
# MV1, at <status>, on main and in work/.
milestone_roadmap() {
    local t
    t=$(printf -- '---\nschema: roadmap/v2\nstatus: Active\n---\n\n# ROADMAP: %s\n\n## Features\n\n### MV1: the plugin list\n\n**Outcome:** A maintainer lists the plugins they installed.\n\n**Evidence:**\n- A reviewer runs `widgets list` and sees three names.\n\n**Left open:** None\n\n**Dependencies:** None\n**Status:** %s\n\n## Progress\n\n- 2026-10-01: MV1 started\n' "$1" "$2")
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = $t' --arg n "$1" --arg t "$t"
    mkdir -p "$T/work/docs/roadmaps"
    printf '%s' "$t" > "$T/work/docs/roadmaps/ROADMAP-$1.md"
}
# The predecessor's Run rows, its role row left for state-stored-set.sh.
RUN_ROWS='[{"key":"arguments","value":"--roadmap","set_by":"the human","set":"2026-10-07T10:00Z"},
 {"key":"cap","value":"2","set_by":"the human","set":"2026-10-07T10:00Z"},
 {"key":"coordinator","value":"coord-a","set_by":"coord-a","set":"2026-10-07T10:00Z"},
 {"key":"reports-to","value":"the human","set_by":"the human","set":"2026-10-07T10:00Z"}]'

# mrun <name> <owed|done|paused|parked>: a manager run of a one-milestone
# roadmap opened by A, its role row written, MV1 owing its verdict (owed), at
# Done (done), held by a pause (paused) or parked on a decision (parked), and
# held at wait. Sets S and WD; returns non-zero when it doesn't get there.
mrun() {
    export CLAUDE_CODE_SESSION_ID=$A_ID
    if [ "$2" = done ]; then milestone_roadmap "$1" Done; else milestone_roadmap "$1" "In progress"; fi
    RAW_RECORD=1 seed_record "$1" "$(record_json roadmap "$1" | jq -c --argjson r "$RUN_ROWS" '.run = $r')"
    OPEN_ROLE=${MRUN_ROLE:-manager} open_run "$1" || { bad "$1: the run opens" "$(cat "$T/open.err")"; return 1; }
    [ "$(at)" = reconcile ] || { bad "$1: the run reaches reconcile" "$(cat "$T/tick.err")"; return 1; }
    write_as_agent state-stored-set.sh --run role "${MRUN_ROLE:-manager}" --by "the human" || { bad "$1: the role row is written" "$(cat "$T/w.err")"; return 1; }
    case "$2" in
        owed) write_as_agent roadmap-status.sh --unit MV1 || { bad "$1: MV1's verdict is owed" "$(cat "$T/w.err")"; return 1; } ;;
        paused) write_as_agent state-stored-set.sh --standing pause --on MV1 --until lifted --what "hold MV1" --owner "the human" \
                    || { bad "$1: MV1 is paused" "$(cat "$T/w.err")"; return 1; } ;;
    esac
    if [ "$2" = done ]; then
        # Every milestone done, pick's facts list no open unit and the run
        # goes on to close its roadmap, where it is held.
        [ "$(at --with-data '{"reconciled":"reported"}')" = roadmap_close_step ] \
            || { bad "$1: the run reaches roadmap_close_step" "$(cat "$T/tick.err")"; return 1; }
        eq "3 $1: pick's facts list no open unit" 0 "$(pickf | jq '[.units[] | select(.done | not)] | length')"
        return 0
    fi
    [ "$(at --with-data '{"reconciled":"reported"}')" = pick ] || { bad "$1: the run reaches pick" "$(cat "$T/tick.err")"; return 1; }
    if [ "$2" = parked ]; then
        [ "$(at --with-data '{"choice":"await_decision","unit":"MV1","rationale":"its framing is the human'"'"'s call"}')" = decision_raise ] &&
            write_as_agent state-decision.sh --open --question "MV1: list installed plugins only, or every known one?" \
                --option "installed -- what the user has" --option "known -- every plugin the registry names" --source self &&
            [ "$(at --with-data '{"raised":"raised"}')" = decision_raise ] &&
            write_as_agent state-stored-set.sh --work MV1 --kind decision --who "decision 1" --next "dispatch it with the answer" &&
            [ "$(at --with-data '{"raised":"raised"}')" = decision_take ] &&
            write_as_agent state-decision.sh --take &&
            [ "$(at --with-data '{"taken":"taken"}')" = decision_verdict ] &&
            write_as_agent state-decision.sh --escalate --recommendation installed --reason "the users asked for their own list" \
                --context "MV1 can't be scoped until its list is chosen." --problem "It changes the milestone's scope, which is the human's." \
                --grounds scope --option "installed -- what the user has" --option "known -- every plugin the registry names" &&
            [ "$(at --with-data '{"verdict":"escalate","rationale":"a scope call"}')" = escalate_send ] &&
            write_as_agent state-decision.sh --sent --route message &&
            [ "$(at --with-data '{"sent":"sent"}')" = pick ] \
            || { bad "$1: MV1 is parked on decision 1" "$(cat "$T/w.err" "$T/tick.err")"; return 1; }
    fi
    [ "$(at --with-data '{"choice":"hold"}')" = wait ] || { bad "$1: the run reaches wait" "$(cat "$T/tick.err")"; return 1; }
}

# succ_input <topic>: the successor input a coordinator writes, naming no
# role, entry_args or repo, added to the run's context.
succ_input() {
    jq -nc --arg t "$1" '{topic: $t, authority: "You are working for the owner on acme/widgets.",
        goal: "Continue this roadmap from where its record stands.",
        checkpoints: ["The run is taken over and its first reconcile is reported."],
        acceptance: ["The first report names this run."]}' > "$T/succ.json"
    (cd "$WD" && koto context add "$S" successor_input.json --from-file "$T/succ.json" > /dev/null)
}
# successor <topic>: the mode, as the coordinator runs it from wait; SO its
# stdout, SE its stderr, SRC its exit.
successor() {
    succ_input "$1"
    : > "$T/work/.niwa/workspace.toml"
    SO=$(cd "$WD" && NIWA="$NS/niwa" NS_RUN="$S" bash "$PS/dispatch-worker.sh" --session "$S" --successor 2> "$T/succ.err"); SRC=$?
    SE=$(cat "$T/succ.err")
    rm -f "$T/work/.niwa/workspace.toml"
}
# worker <unit>: a worker dispatch of <unit>, at dispatch as the agent runs
# it; WO, WE, WRC.
worker() {
    brief mv1 "$1" deliver mv1 executing > "$T/wb.json"
    printf 'mv1' > "$T/topic"
    (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/wb.json" > /dev/null &&
        koto context add "$S" dispatch_topic --from-file "$T/topic" > /dev/null)
    : > "$T/work/.niwa/workspace.toml"
    WO=$(cd "$WD" && NIWA="$NS/niwa" NS_RUN="$S" bash "$PS/dispatch-worker.sh" --session "$S" 2> "$T/wk.err"); WRC=$?
    WE=$(cat "$T/wk.err")
    rm -f "$T/work/.niwa/workspace.toml"
}
run_rows() { (cd "${2:-$WD}" && bash "$PS/state-read.sh" --session "${1:-$S}" --run); }
succ_row() { run_rows "$@" | jq -c '[.[] | select(.key == "successor")]'; }
# shape: what a refusal must leave as it was: the Run section, the
# Holdings, the legs/ keys, the brief directory and niwa's call log.
shape() {
    printf 'run %s\n' "$(run_rows)"
    printf 'holdings %s\n' "$(live_body | jq -c '.holdings // []')"
    printf 'legs %s\n' "$( (cd "$WD" && koto context list "$S" --prefix legs/) | jq -c .)"
    printf 'briefs %s\n' "$(ls -A "$BRIEFS" 2>/dev/null | tr '\n' ' ')"
    printf 'niwa %s\n' "$(cat "$NS/calls.log")"
}
unchanged() { # unchanged <label> <shape before>
    local now
    now=$(shape)
    if [ "$now" = "$2" ]; then ok "$1: the Run section, Holdings, legs/, briefs and niwa's log are as they were"
    else bad "$1: the Run section, Holdings, legs/, briefs and niwa's log are as they were" "$(diff <(printf '%s\n' "$2") <(printf '%s\n' "$now"))"; fi
}
goal_line() { grep '^Run `/shirabe:coordinate ' "$BRIEFS/$1.md"; }
# opener_from <brief topic> <session id> [opener flags...]: the opener as the
# successor runs it from work2, its args file the tokens of the brief's
# invocation; OUT, ORC.
opener_from() {
    local topic=$1 id=$2
    shift 2
    goal_line "$topic" | sed -e 's/^Run `\/shirabe:coordinate //' -e 's/` in .*$//' | jq -R -c 'split(" ")' > "$T/args.json"
    OUT=$(cd "$T/work2" && CLAUDE_CODE_SESSION_ID=$id bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$@" "$T/args.json" 2> "$T/open.err"); ORC=$?
}
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

ROW_RE="^dispatched [a-z0-9-]+ $TODAY\$"

# ---- 1. a manager whose only open milestone owes its verdict hands over ------------------
ns_reset
if mrun handover owed; then
    A=$S
    eq "1: pick reads MV1, the only milestone, verdict_owed" "MV1 true" "$(pickf | jq -r '.units | map("\(.unit) \(.verdict_owed)") | join(",")')"
    eq "1: the run's compat reads 3" 3 "$(cd "$WD" && bash "$PS/coord-log.sh" compat --session "$A" 2>/dev/null | cut -d' ' -f1)"
    BEFORE=$(shape)
    worker MV1
    eq "4 verdict: a worker dispatch of MV1 exits 10" 10 "$WRC"
    case "$WE" in *"a verdict is owed on this milestone"*) ok "4 verdict: ... naming the owed verdict" ;; *) bad "4 verdict: ... naming the owed verdict" "$WE" ;; esac
    unchanged "4 verdict" "$BEFORE"
    ROADMAP=$(cd "$WD" && bash "$PS/coord-log.sh" vars --session "$A" | jq -r .ROADMAP)
    HOST=$(cd "$WD" && bash "$PS/coord-log.sh" run-facts --session "$A" | jq -r .repo)
    eq "1: the run's ROADMAP and host" "docs/roadmaps/ROADMAP-handover.md acme/widgets" "$ROADMAP $HOST"
    successor handover-successor-1
    eq "1: --successor exits 0" 0 "$SRC"
    eq "1: ... and prints session=<name>" "session=handover_successor_1-""1a2b3c4d" "$SO"
    WANT="Run \`/shirabe:coordinate $ROADMAP --role manager\` in $HOST."
    eq "1: the brief's Goal line" "$WANT" "$(goal_line handover-successor-1)"
    has_line() { if grep -Fq -- "$3" <<< "$2"; then ok "$1"; else bad "$1" "missing [$3] in [$2]"; fi; }
    has_line "1: the prompt niwa was given carries the same line" "$(cat "$NS/prompt" 2>/dev/null)" "$WANT"
    eq "1: niwa was called once" 1 "$(grep -c '^niwa dispatch' "$NS/calls.log")"
    eq "1: at the call, the Run section holds one successor row, dispatching, set by the run" \
        "[{\"value\":\"dispatching handover-successor-1 $TODAY\",\"set_by\":\"$A\"}]" \
        "$(jq -c '[.[] | select(.key == "successor") | {value, set_by}]' "$NS/run-at-call.json" 2>/dev/null)"
    eq "1: afterwards it reads dispatched" "[{\"value\":\"dispatched handover-successor-1 $TODAY\",\"set_by\":\"$A\"}]" \
        "$(run_rows | jq -c '[.[] | select(.key == "successor") | {value, set_by}]')"
    ENTRIES=$(cd "$WD" && bash "$PS/state-entry.sh" --session "$A" --list 2>/dev/null)
    eq "1: an entry names the topic, the brief's path and the role" 1 \
        "$(jq '[.[] | select((.text | contains("handover-successor-1")) and (.text | contains(".niwa/dispatch-briefs/handover-successor-1.md")) and (.text | test("\\bmanager\\b")))] | length | if . > 0 then 1 else 0 end' <<< "$ENTRIES")"
    eq "1: the invocation line is the brief's only line naming manager or director" "$WANT" \
        "$(grep -inwE 'managers?|directors?' "$BRIEFS/handover-successor-1.md" | sed 's/^[0-9]*://')"
    has_line "1: its keep-alive line names niwa" "$(cat "$BRIEFS/handover-successor-1.md")" "niwa schedules your keep-alive at dispatch. Don't schedule one."
    RUN_NOW=$(run_rows)
    (cd "$WD" && bash "$PS/state-stored-set.sh" --session "$A" --run successor "dispatched handover-successor-2 $TODAY" --by "$A" > /dev/null 2>&1)
    eq "1: --run successor is still a usage error" 64 "$?"
    eq "1: ... and the Run section is as it was" "$RUN_NOW" "$(run_rows)"
    (cd "$WD" && bash "$PS/state-read.sh" --session "$A" --run > /dev/null 2>&1)
    eq "1: a record holding the successor row reads back" 0 "$?"

    if needs_takeover "2: the successor takes the run over"; then
        opener_from handover-successor-1 "$B_ID" --dispatched-by "$A"
        eq "2: the successor's opener prints outcome=continued" "0 continued" "$ORC $(line outcome)"
        eq "2: ... and predecessor= names the run" "$A" "$(line predecessor)"
        SB=$(line session)
        eq "2: its Run section holds its own coordinator row, role manager and no successor row" "coord-b manager []" \
            "$(run_rows "$SB" "$T/work2" | jq -r '[([.[] | select(.key == "coordinator") | .value][0]), ([.[] | select(.key == "role") | .value][0]), ([.[] | select(.key == "successor")] | tojson)] | join(" ")')"
        CA=$(cd "$WD" && bash "$PS/coord-log.sh" chain-start --session "$A")
        CB=$(cd "$T/work2" && bash "$PS/coord-log.sh" chain-start --session "$SB")
        [ -n "$CA" ] && [ "$CA" = "$CB" ] && ok "2: both runs' chain-start reads the same ($CA)" || bad "2: both runs' chain-start reads the same" "[$CA] [$CB]"
        S=$SB WD=$T/work2
        N=0; ST=$(at)
        while [ "$ST" != reconcile ] && [ $N -lt 6 ]; do ST=$(at); N=$((N + 1)); done
        REPORT=$(cd "$WD" && bash "$PS/reconcile-report-get.sh" --session "$SB" --md 2>&1)
        case "$(printf '%s\n' "$REPORT" | grep '^Record: ')" in
            *"Role: manager.") ok "2: the successor's first reconcile's record line ends Role: manager." ;;
            *) bad "2: the successor's first reconcile's record line ends Role: manager." "$REPORT" ;;
        esac
    fi
fi

# ---- 3 and 4. no open milestone, a pause, a decision -------------------------------------
for c in noopen:done paused:paused parked:parked; do
    name=${c%%:*} kind=${c#*:}
    ns_reset
    mrun "$name" "$kind" || continue
    BEFORE=$(shape)
    case "$kind" in
        paused)
            worker MV1
            eq "4 pause: a worker dispatch of MV1 exits 10" 10 "$WRC"
            case "$WE" in *"pause s1 holds this unit"*) ok "4 pause: ... naming the pause" ;; *) bad "4 pause: ... naming the pause" "$WE" ;; esac ;;
        parked)
            worker MV1
            eq "4 decision: a worker dispatch of MV1 exits 10" 10 "$WRC"
            case "$WE" in *"decision 1 parks this unit"*) ok "4 decision: ... naming the decision" ;; *) bad "4 decision: ... naming the decision" "$WE" ;; esac ;;
    esac
    [ "$kind" = done ] || unchanged "4 $kind" "$BEFORE"
    successor "$name-successor-1"
    eq "3 $name: --successor exits 0" 0 "$SRC"
    case "$SO" in "session=${name}_successor_1-1a2b3c4d") ok "3 $name: ... and prints session=<name>" ;; *) bad "3 $name: ... and prints session=<name>" "$SO $SE" ;; esac
    case "$(succ_row | jq -r 'map(.value) | join(",")')" in
        "dispatched $name-successor-1 $TODAY") ok "3 $name: one successor row, dispatched" ;;
        *) bad "3 $name: one successor row, dispatched" "$(succ_row)" ;;
    esac
    eq "3 $name: niwa was called once" 1 "$(grep -c '^niwa dispatch' "$NS/calls.log")"
done

# ---- 5. no role row ----------------------------------------------------------------------
ns_reset
if mrun norole owed; then
    # The record loses its role row, rewritten in place at its written time.
    live_body > "$T/rec.json"
    jq -c 'del(.written) | .run |= map(select(.key != "role"))' "$T/rec.json" > "$T/rec2.json"
    (cd "$WD" && session_seed "$S" "$(cat "$T/rec2.json")" "$(jq -r .written "$T/rec.json")") || bad "5: the role row is dropped" ""
    eq "5: the record holds no role row" 0 "$(run_rows | jq '[.[] | select(.key == "role")] | length')"
    BEFORE=$(shape)
    successor norole-successor-1
    eq "5: --successor exits 1" 1 "$SRC"
    case "$SE" in *"state-stored-set.sh --session $S --run role"*) ok "5: ... naming state-stored-set.sh --session <run> --run role" ;;
        *) bad "5: ... naming state-stored-set.sh --session <run> --run role" "$SE" ;; esac
    unchanged "5" "$BEFORE"
fi

# ---- 6. a takeover that doesn't name the row's run keeps it ------------------------------
if needs_takeover "6: the takeovers that keep the row"; then
    for c in keep-unnamed keep-other; do
        ns_reset
        mrun "$c" owed || continue
        P=$S
        successor "$c-successor-1"
        eq "6 $c: the successor is dispatched" 0 "$SRC"
        WANT_ROW=$(succ_row | jq -c 'map({value, set_by})')
        case "$WANT_ROW" in "[{\"value\":\"dispatched $c-successor-1 $TODAY\",\"set_by\":\"$P\"}]") ok "6 $c: its row reads dispatched, set by the run" ;;
            *) bad "6 $c: its row reads dispatched, set by the run" "$WANT_ROW" ;; esac
        if [ "$c" = keep-unnamed ]; then opener_from "$c-successor-1" "$C_ID"
        elif [ -z "${A:-}" ] || [ "$A" = "$P" ]; then
            bad "6 $c: case 1 opened another run to name" "${A:-none}"; continue
        else opener_from "$c-successor-1" "$C_ID" --dispatched-by "$A"; fi
        eq "6 $c: the takeover prints outcome=continued" "0 continued" "$ORC $(line outcome)"
        eq "6 $c: ... and predecessor= names the run" "$P" "$(line predecessor)"
        eq "6 $c: the new run keeps the successor row, its value and Set by unchanged" \
            "[{\"value\":\"dispatched $c-successor-1 $TODAY\",\"set_by\":\"$P\"}]" \
            "$(succ_row "$(line session)" "$T/work2" | jq -c 'map({value, set_by})')"
    done
fi

# ---- discipline scope ----------------------------------------------------------------------
#
# A discipline run's successor: its scope --discipline <name> --host
# <owner/repo> from coord-log.sh run-facts, --role after the four tokens.

has_line() { if grep -Fq -- "$3" <<< "$2"; then ok "$1"; else bad "$1" "missing [$3] in [$2]"; fi; }
day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
# drun <name> <role> <open|noopen|paused|parked>: a first rotation of the
# discipline <name> opened by A recorded <role>, its stored set written,
# with one open issue (#12, labelled <name>) at wait (open), none (noopen),
# #12 held by a pause (paused) or parked on a decision (parked). Sets S and
# WD; returns non-zero when it doesn't get there.
drun() {
    local st
    export CLAUDE_CODE_SESSION_ID=$A_ID
    WD=$T/work
    if [ "$3" != noopen ]; then
        db '.issues = ([(.issues // [])[] | select(.labels | index($n) | not)] + [{repo: "acme/widgets", number: 12, title: "the deploy job flakes", state: "open", labels: [$n]}])' --arg n "$1"
    fi
    jq -nc --arg d "$1" --arg r "$2" '["--discipline", $d, "--host", "acme/widgets", "--role", $r]' > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2> "$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ] || { bad "$1: the rotation opens" "$OPEN_OUT $(cat "$T/open.err")"; return 1; }
    [ "$(at)" = record_open ] || { bad "$1: the find reaches record_open" "$(cat "$T/tick.err")"; return 1; }
    write_as_agent state-open.sh --role "$2" --start "$TODAY" --end "$(day 6)" || { bad "$1: the rotation's record opens" "$(cat "$T/w.err")"; return 1; }
    [ "$(at --with-data '{"opened":"opened"}')" = reconcile ] || { bad "$1: the run reaches reconcile" "$(cat "$T/tick.err")"; return 1; }
    { write_as_agent state-stored-set.sh --run arguments "--discipline $1 --host acme/widgets" --by "the human" &&
      write_as_agent state-stored-set.sh --run cap 2 --by "the human" &&
      write_as_agent state-stored-set.sh --run coordinator coord-a --by coord-a &&
      write_as_agent state-stored-set.sh --run reports-to "the human" --by "the human"; } \
        || { bad "$1: the stored set is written" "$(cat "$T/w.err")"; return 1; }
    if [ "$3" = paused ]; then
        write_as_agent state-stored-set.sh --standing pause --on "#12" --until lifted --what "hold #12" --owner "the human" \
            || { bad "$1: #12 is paused" "$(cat "$T/w.err")"; return 1; }
    fi
    st=$(tick --with-data '{"reconciled":"reported"}')
    [ "$(jq -r '.state // empty' <<< "$st")" = pick ] || { bad "$1: the run reaches pick" "${st:0:1500} $(cat "$T/tick.err")"; return 1; }
    if [ "$3" = parked ]; then
        [ "$(at --with-data '{"choice":"await_decision","unit":"#12","rationale":"its fix is the human'"'"'s call"}')" = decision_raise ] &&
            write_as_agent state-decision.sh --open --question "#12: retry the deploy job, or pin its runner?" \
                --option "retry -- run it again on failure" --option "pin -- one runner image" --source self &&
            [ "$(at --with-data '{"raised":"raised"}')" = decision_raise ] &&
            write_as_agent state-stored-set.sh --work "#12" --kind decision --who "decision 1" --next "dispatch it with the answer" &&
            [ "$(at --with-data '{"raised":"raised"}')" = decision_take ] &&
            write_as_agent state-decision.sh --take &&
            [ "$(at --with-data '{"taken":"taken"}')" = decision_verdict ] &&
            write_as_agent state-decision.sh --escalate --recommendation pin --reason "a pinned image flakes less" \
                --context "#12 can't be fixed until the approach is chosen." --problem "It changes the pipeline, which is the human's." \
                --grounds scope --option "retry -- run it again on failure" --option "pin -- one runner image" &&
            [ "$(at --with-data '{"verdict":"escalate","rationale":"a scope call"}')" = escalate_send ] &&
            write_as_agent state-decision.sh --sent --route message &&
            [ "$(at --with-data '{"sent":"sent"}')" = pick ] \
            || { bad "$1: #12 is parked on decision 1" "$(cat "$T/w.err" "$T/tick.err")"; return 1; }
    fi
    [ "$(at --with-data '{"choice":"hold"}')" = wait ] || { bad "$1: the run reaches wait" "$(cat "$T/tick.err")"; return 1; }
}
dgoal() { printf 'Run `/shirabe:coordinate --discipline %s --host acme/widgets --role %s` in acme/widgets.' "$1" "$2"; }
succ_value() { succ_row | jq -r 'map(.value) | join(",")'; }
# opener_args <args json> <session id> [opener flags...]: the opener from
# work2 with <args json> as its args file; OUT, ORC.
opener_args() {
    local a=$1 id=$2
    shift 2
    printf '%s\n' "$a" > "$T/args.json"
    OUT=$(cd "$T/work2" && CLAUDE_CODE_SESSION_ID=$id bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$@" "$T/args.json" 2> "$T/open.err"); ORC=$?
}
brief_args() { goal_line "$1" | sed -e 's/^Run `\/shirabe:coordinate //' -e 's/` in .*$//' | jq -R -c 'split(" ")'; }
# first_record <session>: the successor's Record: line at its first
# reconcile, driven from work2.
first_record() {
    local n=0 st
    S=$1 WD=$T/work2
    st=$(at)
    while [ "$st" != reconcile ] && [ $n -lt 6 ]; do st=$(at); n=$((n + 1)); done
    (cd "$WD" && bash "$PS/reconcile-report-get.sh" --session "$1" --md 2>&1) | grep '^Record: '
}
# succeeds <label> <brief topic> <predecessor> <role>: the successor started
# from its brief's tokens with --dispatched-by, from B, continues the
# predecessor and reports its role. Sets SB.
succeeds() {
    local rec
    opener_from "$2" "$B_ID" --dispatched-by "$3"
    eq "$1: the successor's opener prints outcome=continued" "0 continued" "$ORC $(line outcome)"
    eq "$1: ... and predecessor= names the run" "$3" "$(line predecessor)"
    SB=$(line session)
    rec=$(first_record "$SB")
    case "$rec" in
        *"\`acme/widgets\`"*"Role: $4.") ok "$1: its first reconcile's Record: line names acme/widgets and ends Role: $4." ;;
        *) bad "$1: its first reconcile's Record: line names acme/widgets and ends Role: $4." "$rec $(cat "$T/open.err")" ;;
    esac
}

# ---- 7. a discipline director hands over inside its rotation's window ---------------------
ns_reset
if drun ci-health director open; then
    D=$S
    eq "7: run-facts reads the discipline and host" "discipline ci-health acme/widgets" \
        "$(cd "$WD" && bash "$PS/coord-log.sh" run-facts --session "$D" | jq -r '"\(.scope) \(.name) \(.repo)"')"
    eq "7: the run's compat reads 3" 3 "$(cd "$WD" && bash "$PS/coord-log.sh" compat --session "$D" 2>/dev/null | cut -d' ' -f1)"
    successor ci-health-successor-1
    eq "7: --successor exits 0" 0 "$SRC"
    eq "7: ... and prints session=<name>" "session=ci_health_successor_1-""1a2b3c4d" "$SO"
    WANT=$(dgoal ci-health director)
    eq "7: the brief's Goal line" "$WANT" "$(goal_line ci-health-successor-1)"
    has_line "7: the prompt niwa was given carries the invocation" "$(cat "$NS/prompt" 2>/dev/null)" \
        '`/shirabe:coordinate --discipline ci-health --host acme/widgets --role director`'
    eq "7: the successor row reads dispatched" "dispatched ci-health-successor-1 $TODAY" "$(succ_value)"
    eq "7: the invocation line is the brief's only line naming manager or director" "$WANT" \
        "$(grep -inwE 'managers?|directors?' "$BRIEFS/ci-health-successor-1.md" | sed 's/^[0-9]*://')"
    if needs_takeover "7: the discipline successor takes the rotation over"; then
        succeeds "7" ci-health-successor-1 "$D" director
        eq "7: the successor's Run section holds role director and no successor row" "director []" \
            "$(run_rows "$SB" "$T/work2" | jq -r '[([.[] | select(.key == "role") | .value][0]), ([.[] | select(.key == "successor")] | tojson)] | join(" ")')"
        CA=$(cd "$T/work" && bash "$PS/coord-log.sh" chain-start --session "$D")
        CB=$(cd "$T/work2" && bash "$PS/coord-log.sh" chain-start --session "$SB")
        if [ -n "$CA" ] && [ "$CA" = "$CB" ]; then ok "7: both runs' chain-start reads the same ($CA)"; else bad "7: both runs' chain-start reads the same" "[$CA] [$CB]"; fi
    fi
fi

# ---- 8. a discipline run with no open issue, a paused one, a parked one ------------------
for c in ci-noopen:noopen ci-paused:paused ci-parked:parked; do
    name=${c%%:*} kind=${c#*:}
    ns_reset
    drun "$name" director "$kind" || continue
    if [ "$kind" = paused ]; then
        BEFORE=$(shape)
        brief issue-12 "#12" work-on "#12" executing > "$T/wb.json"
        printf 'issue-12' > "$T/topic"
        (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/wb.json" > /dev/null &&
            koto context add "$S" dispatch_topic --from-file "$T/topic" > /dev/null)
        : > "$T/work/.niwa/workspace.toml"
        (cd "$WD" && NIWA="$NS/niwa" NS_RUN="$S" bash "$PS/dispatch-worker.sh" --session "$S" > /dev/null 2> "$T/wk.err"); WRC=$?
        rm -f "$T/work/.niwa/workspace.toml"
        eq "8 pause: a worker dispatch of #12 exits 10" 10 "$WRC"
        case "$(cat "$T/wk.err")" in *"pause s"[0-9]*" holds this unit"*) ok "8 pause: ... naming the pause" ;; *) bad "8 pause: ... naming the pause" "$(cat "$T/wk.err")" ;; esac
        unchanged "8 pause" "$BEFORE"
        eq "8 pause: ... and no successor row" "[]" "$(succ_row)"
    fi
    successor "$name-successor-1"
    eq "8 $name: --successor exits 0" 0 "$SRC"
    case "$SO" in "session=$(printf '%s' "$name" | tr '-' '_')_successor_1-1a2b3c4d") ok "8 $name: ... and prints session=<name>" ;; *) bad "8 $name: ... and prints session=<name>" "$SO $SE" ;; esac
    eq "8 $name: one successor row, dispatched" "dispatched $name-successor-1 $TODAY" "$(succ_value)"
    eq "8 $name: the brief's Goal line" "$(dgoal "$name" director)" "$(goal_line "$name-successor-1")"
done

# ---- 9. a discipline run with no role row, and one whose facts can't be read -------------
ns_reset
if drun ci-norole director open; then
    live_body > "$T/rec.json"
    jq -c 'del(.written) | .run |= map(select(.key != "role"))' "$T/rec.json" > "$T/rec2.json"
    (cd "$WD" && session_seed "$S" "$(cat "$T/rec2.json")" "$(jq -r .written "$T/rec.json")") || bad "9: the role row is dropped" ""
    BEFORE=$(shape)
    successor ci-norole-successor-1
    eq "9 no role: --successor exits 1" 1 "$SRC"
    case "$SE" in *"state-stored-set.sh --session $S --run role"*) ok "9 no role: ... naming state-stored-set.sh --session <run> --run role" ;;
        *) bad "9 no role: ... naming state-stored-set.sh --session <run> --run role" "$SE" ;; esac
    unchanged "9 no role" "$BEFORE"
    eq "9 no role: ... and no successor row" "[]" "$(succ_row)"
    # The run's log can't be read: run-facts exits 2.
    LOGF=$(logf)
    chmod 000 "$LOGF"
    (cd "$WD" && bash "$PS/coord-log.sh" run-facts --session "$S" > /dev/null 2>&1); FRC=$?
    successor ci-norole-successor-2
    chmod 644 "$LOGF"
    eq "9 unreadable: run-facts exits 2" 2 "$FRC"
    eq "9 unreadable: --successor exits 1" 1 "$SRC"
    unchanged "9 unreadable" "$BEFORE"
fi
# A run whose find hasn't run yet holds no found record: run-facts exits 1.
ns_reset
export CLAUDE_CODE_SESSION_ID=$A_ID
WD=$T/work
jq -nc '["--discipline", "ci-unfound", "--host", "acme/widgets", "--role", "director"]' > "$T/args.json"
OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2> "$T/open.err")
S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
if [ -n "$S" ]; then
    (cd "$WD" && bash "$PS/coord-log.sh" run-facts --session "$S" > /dev/null 2>&1)
    eq "9 unfound: run-facts exits 1" 1 "$?"
    BEFORE=$(shape)
    successor ci-unfound-successor-1
    eq "9 unfound: --successor exits 1" 1 "$SRC"
    unchanged "9 unfound" "$BEFORE"
else
    bad "9 unfound: the run opens" "$OPEN_OUT $(cat "$T/open.err")"
fi

# ---- 10. the other two pairs: a discipline manager (a roadmap director in 11) ------------
ns_reset
if drun ci-lint manager open; then
    P=$S
    successor ci-lint-successor-1
    eq "10 discipline manager: --successor exits 0" 0 "$SRC"
    WANT=$(dgoal ci-lint manager)
    eq "10 discipline manager: the brief's Goal line" "$WANT" "$(goal_line ci-lint-successor-1)"
    eq "10 discipline manager: the invocation line is the brief's only line naming manager or director" "$WANT" \
        "$(grep -inwE 'managers?|directors?' "$BRIEFS/ci-lint-successor-1.md" | sed 's/^[0-9]*://')"
    if needs_takeover "10 discipline manager: the takeover"; then succeeds "10 discipline manager" ci-lint-successor-1 "$P" manager; fi
fi

# ---- 11. a role row changed between a failed and a second dispatch -----------------------
# At each scope a run recorded manager: the first launch fails (exit 4,
# dispatch-failed), the person changes the role row to director, and a second
# dispatch under a new topic renders --role director. The roadmap run's
# second successor is the roadmap director pair: its brief has one role line,
# and its successor reports director.
for sc in discipline roadmap; do
    ns_reset
    if [ "$sc" = discipline ]; then
        drun ci-rerole manager open || continue
        n=ci-rerole
    else
        mrun rerole owed || continue
        n=rerole
    fi
    P=$S
    : > "$NS/fail-next"
    successor "$n-successor-1"
    eq "11 $sc: a failed launch exits 4" 4 "$SRC"
    eq "11 $sc: ... the successor row reads dispatch-failed" "dispatch-failed $n-successor-1 $TODAY" "$(succ_value)"
    case "$(goal_line "$n-successor-1")" in *"--role manager\` in acme/widgets.") ok "11 $sc: ... its brief rendered --role manager" ;;
        *) bad "11 $sc: ... its brief rendered --role manager" "$(goal_line "$n-successor-1")" ;; esac
    write_as_agent state-stored-set.sh --run role director --by "the human" --intervention person
    eq "11 $sc: the person changes the role row to director" "0 director" "$? $(run_rows | jq -r '[.[] | select(.key == "role") | .value][0]')"
    successor "$n-successor-2"
    eq "11 $sc: a second dispatch under a new topic exits 0" 0 "$SRC"
    case "$(goal_line "$n-successor-2")" in *"--role director\` in acme/widgets.") ok "11 $sc: ... rendering --role director" ;;
        *) bad "11 $sc: ... rendering --role director" "$(goal_line "$n-successor-2")" ;; esac
    eq "11 $sc: ... and the row reads dispatched" "dispatched $n-successor-2 $TODAY" "$(succ_value)"
    if [ "$sc" = roadmap ]; then
        WANT="Run \`/shirabe:coordinate docs/roadmaps/ROADMAP-rerole.md --role director\` in acme/widgets."
        eq "10 roadmap director: the brief's Goal line" "$WANT" "$(goal_line rerole-successor-2)"
        eq "10 roadmap director: the invocation line is the brief's only line naming manager or director" "$WANT" \
            "$(grep -inwE 'managers?|directors?' "$BRIEFS/rerole-successor-2.md" | sed 's/^[0-9]*://')"
        if needs_takeover "10 roadmap director: the takeover"; then succeeds "10 roadmap director" rerole-successor-2 "$P" director; fi
    fi
done

# ---- 12. the opener's role check at both scopes -----------------------------------------
# A start from the successor brief's tokens but --role manager against a
# record holding director is refused, the record unchanged; the same start
# with the change flags naming the record's reports-to address is accepted.
if needs_takeover "12: the role check on a takeover"; then
    for sc in discipline roadmap; do
        ns_reset
        if [ "$sc" = discipline ]; then
            drun ci-mismatch director open || continue
            n=ci-mismatch
        else
            MRUN_ROLE=director mrun mismatch owed || continue
            n=mismatch
        fi
        P=$S
        # The run reports to a session now, the address a change from above
        # names.
        write_as_agent state-stored-set.sh --run reports-to "the human at hub-a" --inferred "Report to hub-a: the human named it, not in a brief" --by "the human"
        eq "12 $sc: the reports-to row names hub-a" "0 the human at hub-a" "$? $(run_rows | jq -r '[.[] | select(.key == "reports-to") | .value][0]')"
        successor "$n-successor-1"
        eq "12 $sc: the successor is dispatched" 0 "$SRC"
        MM=$(brief_args "$n-successor-1" | jq -c 'map(if . == "director" then "manager" else . end)')
        REC_BEFORE=$(live_body)
        opener_args "$MM" "$B_ID" --dispatched-by "$P"
        eq "12 $sc: --role manager against director exits 2" 2 "$ORC"
        eq "12 $sc: ... printing outcome=refused and reason=role-mismatch" "refused role-mismatch" "$(line outcome) $(line reason)"
        S=$P WD=$T/work
        eq "12 $sc: ... the record unchanged" "$REC_BEFORE" "$(live_body)"
        opener_args "$(jq -c '. + ["--role-change-by", "hub-a", "--role-change-source", "dispatcher"]' <<< "$MM")" "$B_ID" --dispatched-by "$P"
        eq "12 $sc: with --role-change-by the reports-to address the start is accepted" "0 continued" "$ORC $(line outcome)"
        eq "12 $sc: ... and prints role_changed_from=director" director "$(line role_changed_from)"
    done
fi

# ---- 13. a discipline successor started after its rotation's window -----------------------
# A director's rotation dispatches its successor, and its window ends
# yesterday. The successor started from the brief's tokens opens the next
# rotation rather than taking the ended one over, and predecessor_carry's
# state-open.sh --carry carries the record and the role director. The carried
# successor row is cleared only when the new run's koto/links/dispatched-by/
# names the run that set it: a start with --dispatched-by naming the
# predecessor clears it; a start with no --dispatched-by (the next rotation
# opened by hand), or one naming another run, keeps it as it stood.
#
# end_window <session>: the rotation's window ended yesterday, as the agent
# writes it.
end_window() {
    local y
    y=$(day -1)
    (cd "$T/work" && koto context get "$1" record/rotation) | jq -c --arg e "$y" '.end = $e | if .start > $e then .start = $e else . end' > "$T/rot.json" \
        && (cd "$T/work" && bash "$PS/state-stored-set.sh" --session "$1" --rotation "$T/rot.json" > /dev/null 2> "$T/w.err")
}
OTHER=${D:-${A:-}}
for c in ci-after-clear:clear ci-after-hand:hand ci-after-other:other; do
    name=${c%%:*} kind=${c#*:}
    [ "$kind" != other ] || [ -n "$OTHER" ] || { bad "13 other: an earlier case's run to name" "cases 1 and 7 opened none"; continue; }
    ns_reset
    drun "$name" director open || continue
    P=$S
    successor "$name-successor-1"
    eq "13 $kind: the successor is dispatched" "0 dispatched $name-successor-1 $TODAY" "$SRC $(succ_value)"
    ROW=$(succ_row | jq -c 'map({value, set_by})')
    end_window "$P"
    eq "13 $kind: the rotation's window ended yesterday" "0 $(day -1)" "$? $( (cd "$T/work" && koto context get "$P" record/rotation) | jq -r .end)"
    case "$kind" in
        clear) opener_from "$name-successor-1" "$B_ID" --dispatched-by "$P"; ID=$B_ID ;;
        hand) opener_from "$name-successor-1" "$C_ID"; ID=$C_ID ;;
        other) opener_from "$name-successor-1" "$C_ID" --dispatched-by "$OTHER"; ID=$C_ID ;;
    esac
    SN=$(line session)
    if [ "$ORC" != 0 ] || [ -z "$SN" ] || [ "$SN" = "$P" ] || [ -n "$(line outcome)" ]; then
        bad "13 $kind: the start opens the next rotation, a new run" "$ORC [$OUT] $(cat "$T/open.err")"
        continue
    fi
    ok "13 $kind: the start opens the next rotation, a new run"
    eq "13 $kind: ... printing role=director" director "$(line role)"
    S=$SN WD=$T/work2
    LINKS=$( (cd "$WD" && koto context list "$SN" --prefix koto/links/dispatched-by/) | jq -r 'map(ltrimstr("koto/links/dispatched-by/")) | join(" ")')
    case "$kind" in
        clear) eq "13 clear: the new run's dispatched-by link names the predecessor" "$P" "$LINKS" ;;
        hand) eq "13 hand: the new run has no dispatched-by link" "" "$LINKS" ;;
        other) eq "13 other: the new run's dispatched-by link names another run" "$OTHER" "$LINKS" ;;
    esac
    eq "13 $kind: its find leads to predecessor_carry" predecessor_carry "$(at)"
    CLAUDE_CODE_SESSION_ID=$ID write_as_agent state-open.sh --carry --role director
    eq "13 $kind: state-open.sh --carry exits 0 printing carried=<predecessor>" "0 $P" "$? $(sed -n 's/^carried=//p' "$T/w.out")"
    if [ "$kind" = clear ]; then
        CLAUDE_CODE_SESSION_ID=$ID write_as_agent state-open.sh --carry --role director
        eq "13 clear: the carry run again reads as carried, the row still gone" "0 $P []" "$? $(sed -n 's/^carried=//p' "$T/w.out") $(succ_row "$SN" "$WD")"
    fi
    eq "13 $kind: ... and the carry reaches reconcile" reconcile "$(at --with-data '{"carry":"carried"}')"
    eq "13 $kind: the next rotation names the predecessor" "$P" "$( (cd "$WD" && koto context get "$SN" record/rotation) | jq -r .predecessor)"
    eq "13 $kind: ... and holds role director" director "$(run_rows "$SN" "$WD" | jq -r '[.[] | select(.key == "role") | .value][0] // "none"')"
    if [ "$kind" = clear ]; then
        eq "13 clear: the carried successor row is cleared" "[]" "$(succ_row "$SN" "$WD")"
        eq "13 clear: ... told as an entry" 1 "$( (cd "$WD" && bash "$PS/state-entry.sh" --session "$SN" --list 2>/dev/null) \
            | jq --arg v "dispatched $name-successor-1 $TODAY" '[.[] | select(.text | startswith("Run successor \($v) cleared by"))] | length')"
    else
        eq "13 $kind: the carried successor row is kept, its value and Set by unchanged" "$ROW" "$(succ_row "$SN" "$WD" | jq -c 'map({value, set_by})')"
    fi
    REC=$(first_record "$SN")
    case "$REC" in
        *"\`$SN\`"*"\`acme/widgets\`"*"Role: director.") ok "13 $kind: the next rotation's first Record: line names it and ends Role: director." ;;
        *) bad "13 $kind: the next rotation's first Record: line names it and ends Role: director." "$REC" ;;
    esac
done

# ---- 14. one pending successor at a time, and a same-topic re-run ------------------------
# A manager run dispatches its first successor; a second topic is refused
# with exit 12 and changes nothing; the first topic again confirms with no
# second launch. With the session gone from the listing, a second topic
# settles the row stranded first and then dispatches. A second run whose
# first launch fails with the listing unreadable exits 6 with the row
# dispatching, and its re-run launches once.
entries_with() { (cd "$WD" && bash "$PS/state-entry.sh" --session "$S" --list 2>/dev/null) | jq --arg t "$1" '[.[] | select(.text | contains($t))] | length'; }
ns_reset
if mrun pending owed; then
    successor pending-successor-1
    eq "14: the first successor is dispatched" "0 dispatched pending-successor-1 $TODAY" "$SRC $(succ_value)"
    ROW1=$(succ_row); LOG1=$(cat "$NS/calls.log"); BRIEFS1=$(ls "$BRIEFS" | sort)
    successor pending-successor-2
    eq "14: a second topic while one is pending exits 12" 12 "$SRC"
    case "$SE" in *"dispatched pending-successor-1"*) ok "14: ... naming the row's status and topic" ;; *) bad "14: ... naming the row's status and topic" "$SE" ;; esac
    eq "14: ... the row unchanged" "$ROW1" "$(succ_row)"
    eq "14: ... no launch" "$LOG1" "$(cat "$NS/calls.log")"
    eq "14: ... no brief" "$BRIEFS1" "$(ls "$BRIEFS" | sort)"
    successor pending-successor-1
    eq "14: the first topic again is confirmed" "0 session=pending_successor_1-""1a2b3c4d" "$SRC $SO"
    eq "14: ... with no second launch" "$LOG1" "$(cat "$NS/calls.log")"
    eq "14: ... the row unchanged" "$ROW1" "$(succ_row)"
    echo '[]' > "$NS/sessions.json"
    successor pending-successor-2
    eq "14: with the first session gone, a second topic is dispatched" "0 dispatched pending-successor-2 $TODAY" "$SRC $(succ_value)"
    eq "14: ... the first row settled stranded, told as an entry" 1 "$(entries_with "Run successor stranded pending-successor-1")"
    eq "14: ... and the new one told too" 1 "$(entries_with "Run successor dispatched pending-successor-2")"
fi
ns_reset
if mrun relaunch owed; then
    : > "$NS/fail-next"; : > "$NS/blind-next"
    successor relaunch-successor-1
    eq "14 relaunch: a failed launch with the listing unreadable exits 6" 6 "$SRC"
    eq "14 relaunch: ... the row dispatching" "dispatching relaunch-successor-1 $TODAY" "$(succ_value)"
    rm -f "$NS/list-fail"
    successor relaunch-successor-1
    eq "14 relaunch: the re-run with the same topic exits 0" "0 session=relaunch_successor_1-""1a2b3c4d" "$SRC $SO"
    eq "14 relaunch: ... launching once more" 2 "$(grep -c '^niwa dispatch' "$NS/calls.log")"
    eq "14 relaunch: ... the row dispatched" "dispatched relaunch-successor-1 $TODAY" "$(succ_value)"
    eq "14 relaunch: ... one dispatching entry for the topic across both runs" 1 "$(entries_with "Run successor dispatching relaunch-successor-1")"
fi

echo; echo "successor-handover engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
