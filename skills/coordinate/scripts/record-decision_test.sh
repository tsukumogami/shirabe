#!/usr/bin/env bash
# record-decision_test.sh -- record-decision.sh's write modes against the gh
# and koto stand-ins, from prepared session logs.
#
# Covers, per mode: the write the DESIGN's mode table gives it; every refusal
# (exit 65, the record unchanged); the binding to the session's state
# (coord-log.sh current) and to the routed entry (the sealed DECISION_NEXT
# capture); stamps that name the run and refuse a replay; evidence in each
# state (the verdict cleared, a settled outcome kept, an owed reply cleared, a
# withdrawal owed only for a sent escalation); an owed reply exactly when the
# source is a worker, a coordinator or the dispatcher and its latest evidence
# isn't its own withdrawal; one escalation at a time and the release of the
# queued one; the answer by round, a nested decider, an option's explanation
# as the reason and the same answer twice; --sent against the render's seal
# for each kind, with the route of an escalation to a person; --open-from-
# report's coverage of the sealed list, its citations, addressed marks,
# coordinator escalations and withdrawals; --carry before and after the first
# dispatch; compaction; a line break in an item.
#
# Usage: bash skills/coordinate/scripts/record-decision_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RD="$HERE/record-decision.sh"
CL="$HERE/coord-log.sh"
RUN=20260926T080000Z

# --- fixtures ----------------------------------------------------------------------

E() { # E <n> <state> [jq merge]: one entry as the codec parses it
    local merge=${3-}
    [ -n "$merge" ] || merge='{}'
    jq -nc --arg n "$1" --arg s "$2" --arg run "$RUN" '{decision: $n, round: "0", question: "Ship the migration first?",
        options: "ship now -- users get the format this week\nwait -- one upgrade carries both", state: $s,
        source: "self [20260925T080000Z raise 3]", updated: "2026-09-26T07:00Z"}' | jq -c ". + ($merge)"
}
ESCALATED='{round: "1", verdict: "escalate", recommendation: "wait", reason: "the release is Friday", context: "The context.", problem: "The problem.", grounds: "scope", target: "a person", owed: "", asked: "2026-09-26T07:30Z"}'
# Merges with a comma live in variables: bash 3.2 brace-expands a {a, b}
# written inside a nested command substitution.
UNSENT="$ESCALATED + {owed: \"escalation\", asked: \"\"}"
QUEUED="$ESCALATED + {state: \"coordinator-verdict\", round: \"0\", asked: \"\"}"

# setup <entries-json-array> [next] [reports-to]: record #7 and a fresh session
# that found it. Sets S.
setup() {
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    db '.issues += [{repo: "acme/widgets", number: 7, title: "Coordinator record: ROADMAP-feat", body: $b, state: "open", author: "coord", editor: null}]' \
        --arg b "$(render "$(record_json roadmap feat | jq -c --argjson e "$1" --argjson n "${2:-10}" '.decisions = {next: $n, entries: $e}')" issue)"
    S="coordinate-roadmap-feat-$RUN"
    found_session "$S" "$(roadmap_vars feat | jq -c --arg r "${3-}" '.REPORTS_TO = $r')" 7
    LAST=reconcile
}
to() { log_to "$S" "$LAST" "$1"; LAST=$1; }   # to <state>: the session moves on
route() { # route <token> <state>: decision_next routes <token> to <state>
    to decision_next
    log_capture "$S" DECISION_NEXT "$(bash "$CL" seal --session "$S" --state decision_next --token "$1")"
    to "$2"
}
arrive() { # arrive <state> <wait fields-json>: a wait evidence, then <state>
    to wait
    log_evidence "$S" wait "$2"
    to "$1"
}
body() { jq -r '.issues[] | select(.number == 7) | .body' "$GH_DB"; }
sec() { bash "$RD" --session "$S" --list; }
ent() { sec | jq -c --arg n "$1" '.entries[] | select(.decision == $n)'; }
f() { ent "$1" | jq -r --arg f "$2" '.[$f] // ""'; }
rd() { OUT=$(bash "$RD" --session "$S" "$@" 2>"$T/err"); RC=$?; }
# refused <name> <mode args...>: exit 65 and the body byte for byte unchanged
refused() {
    local name=$1 before; shift
    before=$(body)
    rd "$@"
    if [ "$RC" = 65 ] && [ "$(body)" = "$before" ]; then ok "$name"; else bad "$name" "exit $RC: $(cat "$T/err")"; fi
}
wrote() { if [ "$RC" = 0 ]; then ok "$1"; else bad "$1" "exit $RC: $(cat "$T/err")"; fi; }

# --- --open ------------------------------------------------------------------------

echo "== --open =="
setup '[]' 1
to decision_raise
RSQ=$(bash "$CL" current --session "$S" | cut -d" " -f2)
rd --open --question "Pin the plugin?" --option "pin -- freezes a version" --option "don't pin -- lets a break through"
wrote "--open writes"
eq "--open: a proposed entry with the next identifier and a raise stamp" "1|proposed|self [$RUN raise $RSQ]|pin -- freezes a version" \
    "$(ent 1 | jq -r '"\(.decision)|\(.state)|\(.source)|\(.options | split("\n")[0])"')"
eq "--open: Next decision goes up by one" 2 "$(sec | jq .next)"
refused "--open: a second write for the same visit is refused" --open --question "Again?" --option "a -- b"
to decision_next; to decision_raise
RSQ=$(bash "$CL" current --session "$S" | cut -d" " -f2)
rd --open --question "Ask the dispatcher?" --option "yes -- one" --option "no -- two" --source dispatcher
eq "--open: a dispatcher source" "dispatcher [$RUN raise $RSQ]" "$(f 2 source)"
to decision_next; to decision_raise
refused "--open: an empty question is refused" --open --question "" --option "a -- b"
refused "--open: no options are refused" --open --question "Why?"
refused "--open: a line break in an item is refused" --open --question "$(printf 'one\ntwo')" --option "a -- b"
refused "--open: a source other than self or the dispatcher is refused" --open --question "Q?" --option "a -- b" --source "worker w1"
to decision_take
refused "--open outside decision_raise is refused" --open --question "Q?" --option "a -- b"

# --- --take and the routed entry --------------------------------------------------------

echo "== --take =="
setup "[$(E 1 proposed), $(E 2 proposed)]"
route "take 2" decision_take
rd --take; wrote "--take writes"
eq "--take: the routed entry, not another, awaits a verdict" "proposed coordinator-verdict" "$(f 1 state) $(f 2 state)"
route "take 1" decision_take
to decision_next; to decision_take
refused "--take: a capture from an earlier decision_next visit is refused" --take
route "verdict 1" decision_take
refused "--take: an entry routed for a verdict is refused" --take
route "take 2" decision_take
refused "--take: an entry that isn't proposed is refused" --take

# --- --settle -----------------------------------------------------------------------------

echo "== --settle =="
setup "[$(E 1 coordinator-verdict '{source: "worker w1 [20260926T080000Z report 4.1]"}'), $(E 2 coordinator-verdict)]"
route "verdict 1" decision_verdict
rd --settle --outcome wait --reason "the release is Friday"; wrote "--settle writes"
eq "--settle: the outcome with its reason, decided by the coordinator, a reply owed to the worker" \
    "settled|wait; reason: the release is Friday|the coordinator|reply" "$(ent 1 | jq -r '"\(.state)|\(.outcome)|\(.decided_by)|\(.owed)"')"
route "verdict 2" decision_verdict
rd --settle --outcome ship --reason "nothing waits on it"
eq "--settle: an entry of its own owes no reply" "settled|" "$(f 2 state)|$(f 2 owed)"
setup "[$(E 1 coordinator-verdict '{source: "coordinator rr #4 round 1 [20260926T080000Z report 4.1]", evidence: "2026-09-26T07:40Z coordinator rr #4 round 1 [20260926T080000Z report 6.1]: withdrawn: decision 4 round 1"}')]"
route "verdict 1" decision_verdict
rd --settle --outcome wait --reason "moot"
eq "--settle: after the source's own withdrawal nothing is owed back" "settled|" "$(f 1 state)|$(f 1 owed)"
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
refused "--settle: an empty reason is refused" --settle --outcome ship --reason ""
refused "--settle: an empty outcome is refused" --settle --outcome "" --reason why
setup "[$(E 1 proposed)]"
route "verdict 1" decision_verdict
refused "--settle: an entry not awaiting a verdict is refused" --settle --outcome ship --reason why

# --- --escalate -----------------------------------------------------------------------------

echo "== --escalate =="
ESC_ARGS=(--recommendation wait --reason "the release is Friday" --context "The context." --problem "The problem." --grounds scope)
setup "[$(E 1 coordinator-verdict), $(E 2 coordinator-verdict)]"
route "verdict 1" decision_verdict
rd --escalate "${ESC_ARGS[@]}"; wrote "--escalate writes"
eq "--escalate: escalated to the run's target, round 1, an escalation owed" "escalated|1|a person|escalation" \
    "$(ent 1 | jq -r '"\(.state)|\(.round)|\(.target)|\(.owed)"')"
route "verdict 2" decision_verdict
rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: with one entry escalated, the next verdict is queued" "coordinator-verdict|escalate|0" "$(ent 2 | jq -r '"\(.state)|\(.verdict)|\(.round)"')"
setup "[$(E 1 coordinator-verdict '{options: "ship now\nwait"}')]"
route "verdict 1" decision_verdict
refused "--escalate: an option without its explanation is refused" --escalate "${ESC_ARGS[@]}"
rd --escalate "${ESC_ARGS[@]}" --option "ship now -- users get the format this week" --option "wait -- one upgrade carries both"
eq "--escalate: --option gives every option its explanation" "escalated|wait -- one upgrade carries both" "$(f 1 state)|$(f 1 options | sed -n 2p)"
setup "[$(E 1 coordinator-verdict '{options: "ship now\nwait"}')]"
route "verdict 1" decision_verdict
refused "--escalate: --option naming other options is refused" --escalate "${ESC_ARGS[@]}" --option "later -- x" --option "wait -- y"
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
refused "--escalate: a recommendation outside the options is refused" --escalate --recommendation later --reason r --context c --problem p --grounds scope
refused "--escalate: no ground is refused" --escalate --recommendation wait --reason r --context c --problem p --grounds ""
refused "--escalate: a blank context is refused" --escalate --recommendation wait --reason r --context "  " --problem p --grounds scope
setup "[$(E 1 coordinator-verdict)]" 10 ws
route "verdict 1" decision_verdict
rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: a run reporting to a coordinator escalates to it" "coordinator ws" "$(f 1 target)"

# --- --hold ---------------------------------------------------------------------------------

echo "== --hold =="
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
rd --hold --reason "the benchmark run"; wrote "--hold writes"
eq "--hold: a held verdict with what it waits on, and its hold line" "coordinator-verdict|hold|the benchmark run|holding: the benchmark run" \
    "$(ent 1 | jq -r '"\(.state)|\(.verdict)|\(.reason)|\(.evidence | split(": ")[1:] | join(": "))"')"
refused "--hold: a second hold for the same visit is refused" --hold --reason again
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
refused "--hold: an empty reason is refused" --hold --reason ""

# --- --evidence -----------------------------------------------------------------------------

echo "== --evidence =="
ev() { arrive decision_evidence '{"event":"evidence","decision":"1"}'; rd --evidence --source dispatcher --text "the check came back mixed"; }
setup "[$(E 1 proposed)]"; ev
eq "evidence on a proposed entry: awaiting a verdict" "coordinator-verdict" "$(f 1 state)"
eq "evidence: the line is last, with its time, source and wait stamp" "dispatcher [$RUN wait $(bash "$CL" evidence --session "$S" --state wait | jq -r .seq)]: the check came back mixed" \
    "$(f 1 evidence | tail -1 | cut -d' ' -f2-)"
setup "[$(E 1 coordinator-verdict '{verdict: "hold", reason: "r"}')]"; ev
eq "evidence on a held entry clears the hold" "coordinator-verdict|" "$(f 1 state)|$(f 1 verdict)"
setup "[$(E 1 escalated "$ESCALATED")]"; ev
eq "evidence on a sent escalation owes a withdrawal" "coordinator-verdict|withdrawal" "$(f 1 state)|$(f 1 owed)"
setup "[$(E 1 escalated "$UNSENT")]"; ev
eq "evidence on an unsent escalation owes nothing" "coordinator-verdict|" "$(f 1 state)|$(f 1 owed)"
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"; ev
eq "evidence on a settled entry keeps the old outcome as evidence and clears the reply" "coordinator-verdict||" "$(f 1 state)|$(f 1 outcome)|$(f 1 owed)"
case "$(f 1 evidence)" in *"previous outcome"*"wait; reason: r (decided by a person)"*) ok "evidence: the old outcome and who decided are kept" ;;
    *) bad "evidence: the old outcome and who decided are kept" "$(f 1 evidence)" ;; esac
refused "evidence: a second write for the same wait visit is refused" --evidence --source dispatcher --text again
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED")]"; ev
eq "evidence that frees the slot releases the queued escalation" "escalated|1|escalation" "$(ent 2 | jq -r '"\(.state)|\(.round)|\(.owed)"')"
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"1"}'
refused "evidence without a source is refused" --evidence --text "t"
refused "evidence without a text is refused" --evidence --source dispatcher
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"9"}'
refused "evidence on an entry the record lacks is refused" --evidence --source dispatcher --text t

# --- --answer -------------------------------------------------------------------------------

echo "== --answer =="
ans() { arrive decision_answer "{\"event\":\"answer\",\"decision\":\"1\",\"round\":\"$1\"}"; shift; rd --answer "$@"; }
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED")]"
ans 1 --outcome wait; wrote "--answer writes"
eq "--answer: settles, decided by the target, with the option's explanation as its reason" "settled|a person|wait; reason: one upgrade carries both" \
    "$(ent 1 | jq -r '"\(.state)|\(.decided_by)|\(.outcome)"')"
case "$(f 1 evidence)" in *"[$RUN wait "*"]: answer for round 1: wait"*) ok "--answer: a settling answer still writes its wait-stamped line" ;;
    *) bad "--answer: a settling answer still writes its wait-stamped line" "$(f 1 evidence)" ;; esac
eq "--answer: freeing the slot releases the queued escalation" "escalated" "$(f 2 state)"
BEFORE=$(body)
ans 1 --outcome wait
eq "--answer: the same answer again changes nothing" "0 same" "$RC $([ "$(body)" = "$BEFORE" ] && echo same || echo changed)"
setup "[$(E 1 escalated "$ESCALATED + {round: \"2\"}")]"
ans 1 --outcome wait
eq "--answer: an answer for an earlier round is evidence" "coordinator-verdict" "$(f 1 state)"
case "$(f 1 evidence)" in *"answer for round 1: wait"*) ok "--answer: its text is kept as evidence" ;; *) bad "--answer: its text is kept as evidence" "$(f 1 evidence)" ;; esac
setup "[$(E 1 escalated "$ESCALATED")]"
arrive decision_answer '{"event":"answer","decision":"1","round":"1"}'
refused "--answer: an outcome that isn't an option needs its reason" --answer --outcome "ship half"
rd --answer --outcome "ship half" --reason "the reader is ready"
eq "--answer: another outcome with its reason settles" "ship half; reason: the reader is ready" "$(f 1 outcome)"
setup "[$(E 1 escalated "$ESCALATED + {target: \"coordinator ws\"}")]" 10 ws
ans 1 --outcome wait --final "a person"
eq "--answer: a nested reply names the final decider" "coordinator ws (final: a person)" "$(f 1 decided_by)"
setup "[$(E 1 escalated "$ESCALATED")]"
to escalate_send
log_evidence "$S" escalate_send '{"sent":"answered","decision":"1","round":"1"}'
to decision_answer
rd --answer --outcome wait
eq "--answer: from escalate_send, the question-tool route" "settled|a person" "$(f 1 state)|$(f 1 decided_by)"

# --- --sent ---------------------------------------------------------------------------------

echo "== --sent =="
# render <state> <kind> <token>: decision_next routes, the real renderer renders
render_msg() {
    route "$3" "$1"
    log_capture "$S" "$4" "$(bash "$HERE/decision-render.sh" --session "$S" --state "$1" --kind "$2" 2>"$T/render.err")"
}
setup "[$(E 1 escalated "$UNSENT")]"
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
to escalate_send
refused "--sent: an escalation to a person must name its route" --sent
rd --sent --route message; wrote "--sent writes"
eq "--sent: the escalation is no longer owed, and Asked is stamped" "|yes" "$(f 1 owed)|$([ -n "$(f 1 asked)" ] && echo yes)"
case "$(f 1 evidence)" in *"[$RUN ask "*"]: asked by message"*) ok "--sent: the route is recorded on the entry" ;; *) bad "--sent: the route is recorded on the entry" "$(f 1 evidence)" ;; esac
refused "--sent: marking it again is refused" --sent --route message
setup "[$(E 1 escalated "$UNSENT")]"
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
printf 'something else\n' > "$T/edited"; koto context add "$S" coord/decision_message.txt --from-file "$T/edited"
to escalate_send
refused "--sent: a text edited after the render is refused" --sent --route message
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"
render_msg decision_reply reply "reply 1" REPLY_MESSAGE
to decision_reply_send
rd --sent
eq "--sent: a reply is no longer owed" "" "$(f 1 owed)"
setup "[$(E 1 proposed '{source: "worker w1 [20260926T080000Z report 4.1]", evidence: "2026-09-26T07:40Z worker w1 [20260926T080000Z report 4.1]: addressed to a person"}')]"
render_msg decision_redirect redirect "redirect 1 4" REDIRECT_MESSAGE
to decision_redirect_send
rd --sent
case "$(f 1 evidence)" in *"[$RUN redirect 4]: redirect sent"*) ok "--sent: a redirect is marked with its report's sequence" ;; *) bad "--sent: a redirect is marked with its report's sequence" "$(f 1 evidence)" ;; esac
to decision_next; to decision_take
refused "--sent outside a send state is refused" --sent

# --- --open-from-report -----------------------------------------------------------------------

echo "== --open-from-report =="
# listed <items-json>: report_questions sealed this list
listed() {
    to report_questions
    printf '%s' "$1" > "$T/q.json"
    local ks
    ks=$(bash "$CL" seal --session "$S" --state report_questions --file "$T/q.json" --key coord/questions.json)
    log_capture "$S" QUESTIONS "$(bash "$CL" seal --session "$S" --state report_questions --token "questions $(printf '%s' "$1" | jq length) keyseal:${ks#sealed:}")"
    RSEQ=${ks#sealed:}; RSEQ=${RSEQ%%:*}
    to decision_open
}
words() { printf '%s' "$1" > "$T/w.json"; rd --open-from-report --text-file "$T/w.json"; }
ITEMS='[{"index":1,"kind":"question","text":"please decide whether to ship","source":"worker w1","addressed":true,"cite":null},
        {"index":2,"kind":"question","text":"and the cap (decision 1)?","source":"worker w1","addressed":false,"cite":1}]'
setup "[$(E 1 proposed '{source: "worker w1 [20260926T080000Z report 2.1]"}')]" 2
listed "$ITEMS"
refused "--open-from-report: an item left uncovered is refused" \
    --open-from-report --text-file "$(printf '{"1":{"question":"Ship now?","options":["ship -- a","hold -- b"]}}' > "$T/w1.json"; echo "$T/w1.json")"
grep -q "each once" "$T/err" && ok "  ... for the coverage" || bad "  ... for the coverage" "$(cat "$T/err")"
refused "--open-from-report: an item the list doesn't have is refused" \
    --open-from-report --text-file "$(printf '{"1":{"question":"Q?","options":["a -- b"]},"2":{"question":"cap"},"3":{"question":"x"}}' > "$T/w2.json"; echo "$T/w2.json")"
grep -q "each once" "$T/err" && ok "  ... for the coverage, again" || bad "  ... for the coverage, again" "$(cat "$T/err")"
words '{"1":{"question":"Ship now?","options":["ship -- the format lands","hold -- one upgrade"]},"2":{"question":"the cap stays at 400"}}'
wrote "--open-from-report writes"
eq "--open-from-report: a new entry for the uncited question, stamped with the report" "2|proposed|worker w1 [$RUN report $RSEQ.1]" \
    "$(ent 2 | jq -r '"\(.decision)|\(.state)|\(.source)"')"
case "$(f 2 evidence)" in *"[$RUN report $RSEQ.1]: addressed to a person"*) ok "--open-from-report: the addressed question carries the mark" ;;
    *) bad "--open-from-report: the addressed question carries the mark" "$(f 2 evidence)" ;; esac
case "$(f 1 evidence)" in *"[$RUN report $RSEQ.2]: the cap stays at 400"*) ok "--open-from-report: a cited question is evidence in the coordinator's words" ;;
    *) bad "--open-from-report: a cited question is evidence in the coordinator's words" "$(f 1 evidence)" ;; esac
refused "--open-from-report: the same report written twice is refused" --open-from-report --text-file "$T/w.json"
setup "[]" 1
listed '[{"index":1,"kind":"question","text":"x?","source":"worker w1","addressed":false,"cite":null}]'
koto context add "$S" coord/questions.json --from-file <(printf '[]')
refused "--open-from-report: a list that fails its seal is refused" --open-from-report --text-file "$(printf '{"1":{"question":"Q?","options":["a -- b"]}}' > "$T/w3.json"; echo "$T/w3.json")"
grep -q "check against report_questions" "$T/err" && ok "  ... for the seal" || bad "  ... for the seal" "$(cat "$T/err")"
setup "[]" 1
listed '[{"index":1,"kind":"escalation","text":"Merge first?","source":"coordinator rr #4 round 1","addressed":false,"cite":null,"n":4,"round":1,"options":["wait -- one upgrade","merge now -- this week"],"recommended":"wait"}]'
words '{"1":{"question":"Merge before the release?","options":["wait -- one upgrade","merge now -- this week"]}}'
eq "--open-from-report: a coordinator's escalation opens with that coordinator's entry as its source" "coordinator rr #4 round 1 [$RUN report $RSEQ.1]" "$(f 1 source)"
setup "[$(E 1 escalated "$ESCALATED + {source: \"coordinator rr #4 round 1 [20260926T070000Z report 3.1]\"}")]" 2
listed '[{"index":1,"kind":"withdrawal","text":"Withdrawn: decision 4 round 1.","source":"coordinator rr #4 round 1","addressed":false,"cite":null,"n":4,"round":1}]'
words '{}'
eq "--open-from-report: a withdrawal reopens the entry from that source and owes a withdrawal upward" "coordinator-verdict|withdrawal" "$(f 1 state)|$(f 1 owed)"
# A second run, whose log sequences restart, writes its own entries.
setup "[$(E 1 proposed '{source: "worker w1 [20260925T080000Z report 12.1]"}')]" 2
listed '[{"index":1,"kind":"question","text":"x?","source":"worker w1","addressed":false,"cite":null}]'
words '{"1":{"question":"A second run'"'"'s question?","options":["a -- b"]}}'
eq "--open-from-report: another run's stamps with the same sequence don't block this run's" "2" "$(sec | jq -r '.entries | length')"

# --- compaction -------------------------------------------------------------------------------

echo "== compaction =="
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", verdict: "settle", evidence: "2026-09-26T07:40Z dispatcher [20260926T070000Z wait 3]: mixed"}'), $(E 2 proposed)]"
route "take 2" decision_take
rd --take
eq "a write compacts a settled entry that owes nothing, keeping its options" "|ship now -- users get the format this week|" \
    "$(f 1 verdict)|$(f 1 options | head -1)|$(f 1 evidence)"

# --- --carry ----------------------------------------------------------------------------------

echo "== --carry =="
carry_setup() { # carry_setup <record entries> <handoff decisions>
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    db '.branches["acme/widgets"]["coordinate/discipline-ci"] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci rotation 2026-09-26 to 2026-10-03",
        body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: "coordinate/discipline-ci", headRefOid: $s, author: "coord", editor: null}]' \
        --arg s "$SHA_HEAD" --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "$1" '.decisions = {next: 2, entries: $e}')" pr)"
    record_json discipline ci | jq -c --argjson d "$2" '.decisions = $d | .rotation = {start: "2026-09-19", end: "2026-09-26", date: "2026-09-26", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/21"} | .reasoning = "Carry on."' > "$T/h.json"
    bash "$HERE/record-render.sh" --format handoff "$T/h.json" > "$T/h.md"
    db '.files["acme/widgets"]["main:docs/disciplines/ci.md"] = $t' --arg t "$(cat "$T/h.md")"
    S="coordinate-discipline-ci-$RUN"
    found_session "$S" "$(discipline_vars ci)" 22
    LAST=reconcile
    to decision_carry
}
carry_setup '[]' "{\"next\": 6, \"entries\": [$(E 5 escalated "$ESCALATED")]}"
rd --carry; wrote "--carry writes"
eq "--carry: the handoff's unsettled entries and its Next decision" "5|escalated|6" "$(sec | jq -r '"\([.entries[].decision] | join(","))|\(.entries[0].state)|\(.next)"')"
refused "--carry: again, with every entry already here, is refused" --carry
carry_setup '[]' "{\"next\": 6, \"entries\": [$(E 5 escalated "$ESCALATED")]}"
log_to "$S" decision_carry dispatch; log_to "$S" dispatch decision_carry
refused "--carry: after the run's first dispatch is refused" --carry

echo "== usage =="
setup '[]' 1
bash "$RD" --session "$S" >/dev/null 2>&1; eq "no mode is a usage error" 64 $?
bash "$RD" --session "$S" --take --scope roadmap --name feat --repo acme/widgets --ref 7 >/dev/null 2>&1
eq "a write mode takes no override flags" 64 $?

done_tests record-decision
