#!/usr/bin/env bash
# state-decision_test.sh -- state-decision.sh's write modes against the gh
# and koto stand-ins, from prepared session logs.
#
# Covers, per mode: the write the DESIGN's mode table gives it; every refusal
# (exit 65, the record unchanged); the binding to the session's state
# (coord-log.sh current) and to the routed entry (the sealed DECISION_NEXT
# capture); stamps that name the run and refuse a replay; evidence in each
# state (the verdict cleared, a settled outcome kept, an owed reply cleared, a
# withdrawal owed only for a sent escalation); an owed reply exactly when the
# source is a worker, a coordinator or the dispatcher and its latest evidence
# isn't its own withdrawal; --escalate by question identity through shirabe
# question pass-up, behind an undecided attempt (refused when it is missing,
# decided, provisional or tied to another question; a need takes none), and
# --identity for an entry that holds none; at most four escalated per target,
# the queued ones released by most waiting work items, then oldest, then
# identity, and listed with their age; an entry held by a question settled
# from koto's answer (an --outcome that differs refused, a withdrawal settled
# as withdrawn), a typed reply leaving it escalated; --sent --route tool
# refused in an unattended session and --route record kept as waiting on the
# record; an identity item of the report opened once, its wording refused;
# the answer by round, a nested decider, an option's explanation
# as the reason and the same answer twice; --sent against the render's seal
# for each kind, with the route of an escalation to a person; --open-from-
# report's coverage of the sealed list, its citations, addressed marks,
# coordinator escalations and withdrawals; --carry from the predecessor
# session record/rotation names, before and after the first dispatch, and
# refused for a rotation that names none; compaction; a line break in an item;
# --open's and --escalate's options starting with a dash (-r, --flag=value)
# stored as given, and a dash-leading decision id refused as a bad id; a write to a record past 60,000 bytes (there is no size budget); the section kept in the run's session's record/decisions, an entry moving
# from proposed to coordinator-verdict to settled there, with nothing written
# on GitHub. Entries with no identity keep the escalation path they had (a
# queued one keeps its verdict, released only when none is escalated); --settle
# of an entry held by a question only from koto's closed answer; a reserved
# ground refusing the coordinator's own settle or answer; a withdrawal reaching
# the entry by its identity; --list failing on a queued entry with no time;
# raise times ordered as instants; --open-questions; the restart's attempt
# line; SHIRABE_BIN.
#
# Usage: bash skills/coordinate/scripts/state-decision_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
RD="$HERE/state-decision.sh"
CL="$HERE/coord-log.sh"
RUN=20260926T080000Z
# The shirabe question stand-in, for pass-up, pending and render.
PATH="$HERE/testdata/question-stand-in:$PATH"

# --- koto's record of a question (testdata/koto-decisions' fixtures) ---------------
QA=0a1b2c3d-a/000000000002
QB=0a1b2c3d-b/000000000003
qkey() { printf '%s' "$1" | tr '/' '_'; }
KD() { mkdir -p "$KOTO_STORE/decisions/$1"; printf '%s' "$KOTO_STORE/decisions/$1"; }
# question <identity> <true|false> [need] [raiser]: koto's history and content
question() {
    jq -nc --arg q "$1" --argjson o "$2" --arg n "${3:-decision}" --arg r "${4:-w1}" '{identity: $q, open: $o,
        raiser: {name: $r}, question: {need: $n, text: "Which store?"}, entries: [{entry: "raise", session: $r}], answer: null}' \
        > "$(KD history)/$(qkey "$1").json"
    printf '%s' '{"context":"CTX-MARK","problem":"PROB-MARK","ask":"Which store?","options":[{"label":"SQLite","reason":"REASON-MARK"}],"ground":"GROUND-MARK","waiting":["issue-12"],"label":"cache"}' \
        > "$(KD content)/$(qkey "$1").json"
}
# attempt <identity> <id> [result]: an attempt of $S's tied to the question
attempt() {
    local f
    f="$(KD attempts)/$S.json"
    [ -f "$f" ] || printf '{"attempts":[],"in":"%s","unreadable":[],"v":1}' "$S" > "$f"
    jq -c --arg q "$1" --arg i "$2" --arg r "${3:-undecided}" '.attempts += [{id: $i, result: $r, status: "in-effect", questions: [$q]}]' "$f" > "$f.new" && mv "$f.new" "$f"
}
# answered <identity> <answered|withdrawn> <text>: koto shows it closed, the
# answer recorded in session director as decision 000000000001
answered() {
    local h
    h="$(KD history)/$(qkey "$1").json"
    jq -c --arg o "$2" --arg t "$3" '.open = false | .answer = {session: "director", id: "000000000001", outcome: $o, text: (if $t == "" then null else $t end)}' "$h" > "$h.new" && mv "$h.new" "$h"
    printf '%s' '{"decision":{"kind":"answer","reason":"one file is enough","decider":{"kind":"session","session":{"value":"director"}}}}' \
        > "$(KD show)/director_000000000001.json"
}
qready() { question "$QA" true; attempt "$QA" 000000000005; }
# shirabe_calls <word>: the stand-in's calls of that subcommand
shirabe_calls() { grep -h " $1 " "$KOTO_STORE/shirabe-calls" 2>/dev/null; }

# --- fixtures ----------------------------------------------------------------------

E() { # E <n> <state> [jq merge]: one entry as the state holds it
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
# The same, held by question QA: the escalation decision-render.sh renders
# (with qready run, so koto holds the question and an attempt behind it).
UNSENT_HELD="$UNSENT + {source: \"question $QA [20260926T070000Z report 3.1]\", options: \"\", grounds: \"changes-scope\"}"
QUEUED="$ESCALATED + {state: \"coordinator-verdict\", round: \"0\", asked: \"\"}"
# A queued escalation held by question QB, open in koto with an attempt behind
# it once qb_ready runs: the one a freed place releases. A queued entry with no
# identity (QUEUED, a run's from before entries were held by identities) is
# released as it was then: only when no entry is escalated.
QUEUED_HELD="$QUEUED + {source: \"question $QB [20260926T070000Z report 3.2]\", options: \"\", grounds: \"changes-scope\"}"
qb_ready() { question "$QB" true; attempt "$QB" 000000000006; }

# setup <entries-json-array> [next] [reports-to]: a fresh session that found
# its record, the record in its keys. Sets S.
setup() {
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context" "$KOTO_STORE/decisions" "$KOTO_STORE/shirabe-calls"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    S="coordinate-roadmap-feat-$RUN"
    found_session "$S" "$(roadmap_vars feat | jq -c --arg r "${3-}" '.REPORTS_TO = $r')"
    put_decisions "$1" "${2:-10}"
    LAST=reconcile
}
# put_decisions <entries-json-array> <next>: the run's record, holding them.
put_decisions() {
    seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "$1" --argjson n "$2" '.decisions = {next: $n, entries: $e}')"
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
body() { session_snapshot "$S"; }
sec() { bash "$RD" --session "$S" --list; }
ent() { sec | jq -c --arg n "$1" '.entries[] | select(.decision == $n)'; }
f() { ent "$1" | jq -r --arg f "$2" '.[$f] // ""'; }
rd() { OUT=$(bash "$RD" --session "$S" "$@" 2>"$T/err"); RC=$?; }
# refused <name> <mode args...>: exit 65 and the record byte for byte unchanged
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
# An option starting with a dash: jq reads none of them as its own option (-r
# is one of jq's, --flag=value isn't), so each is stored as given (#1405).
opts() { ent "$1" | jq -r '.options | split("\n") | join("|")'; }
setup '[]' 1
to decision_raise
rd --open --question "Which route?" --option "take the -r route" --option "-r"
wrote "--open: an option of -r is written"
eq "--open: an option of -r is stored as given, not taken as jq's" "take the -r route|-r" "$(opts 1)"
to decision_next; to decision_raise
rd --open --question "Which flag?" --option "--flag=value -- kept" --option "plain -- too"
wrote "--open: an option starting with -- is written"
eq "--open: an option starting with -- is stored as given" "--flag=value -- kept|plain -- too" "$(opts 2)"

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
route "take 5" decision_take
refused "--take: an entry missing from the live record is refused, the section untouched" --take

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
# An entry is escalated by its question identity: shirabe question pass-up
# passes it up in koto, behind an undecided attempt of the run's at it.
HELD_A="{source: \"question $QA [20260926T070000Z report 3.1]\", options: \"\"}"
HELD_B="{source: \"question $QB [20260926T070000Z report 3.2]\", options: \"\"}"
ESC_ARGS=(--grounds changes-scope --attempt 000000000005)
setup "[$(E 1 coordinator-verdict "$HELD_A"), $(E 2 coordinator-verdict "$HELD_B")]"
qready
route "verdict 1" decision_verdict
rd --escalate "${ESC_ARGS[@]}"; wrote "--escalate writes"
eq "--escalate: escalated to the run's target, round 1, an escalation owed" "escalated|1|a person|escalation" \
    "$(ent 1 | jq -r '"\(.state)|\(.round)|\(.target)|\(.owed)"')"
eq "--escalate: passed up with shirabe question pass-up, the attempt named and the owner as the addressee" \
    "question pass-up $QA --in $S --ground changes-scope --attempt 000000000005 --to person:owner" "$(shirabe_calls pass-up)"
question "$QB" true; attempt "$QB" 000000000006
route "verdict 2" decision_verdict
rd --escalate --grounds outward-facing --attempt "$S:000000000006"
eq "--escalate: a second entry for the same target is escalated too, its attempt given as <session>:<id>" "escalated|1" "$(ent 2 | jq -r '"\(.state)|\(.round)"')"
# Passing up needs an attempt: each refusal names it and leaves the record and koto as they were.
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
question "$QA" true
attempt "$QA" 000000000007 decided
attempt "$QA" 000000000008 provisional
attempt "$QB" 000000000009
route "verdict 1" decision_verdict
refused "--escalate: a decision with no --attempt is refused" --escalate --grounds changes-scope
for a in 000000000004 000000000007 000000000008 000000000009; do
    refused "--escalate: attempt $a (missing, decided, provisional or tied to another question) is refused" --escalate --grounds changes-scope --attempt "$a"
    grep -q "attempt $a " "$T/err" && ok "  ... and the refusal names attempt $a" || bad "  ... and the refusal names attempt $a" "$(cat "$T/err")"
done
refused "--escalate: another session's attempt is refused" --escalate --grounds changes-scope --attempt "w9:000000000005"
eq "--escalate: no refused escalation called pass-up" "" "$(shirabe_calls pass-up)"
refused "--escalate: a ground that isn't pass-up's is refused" --escalate --grounds scope --attempt 000000000005
refused "--escalate: outside-scope is never passed up to a person" --escalate --grounds outside-scope --attempt 000000000005
attempt "$QA" 000000000005
refused "--escalate: --recommendation, --context, --problem and --option don't apply to a question koto words" \
    --escalate "${ESC_ARGS[@]}" --recommendation SQLite
refused "--escalate: nor an --option, even one starting with a dash" --escalate "${ESC_ARGS[@]}" --option "-r -- the raw route"
answered "$QA" answered SQLite
refused "--escalate: a question koto shows closed is refused" --escalate "${ESC_ARGS[@]}"
# A need is passed up with no attempt.
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
question "$QA" true need
route "verdict 1" decision_verdict
refused "--escalate: a need takes no attempt" --escalate "${ESC_ARGS[@]}"
rd --escalate --grounds changes-scope
eq "--escalate: a need is passed up with no attempt" "escalated|question pass-up $QA --in $S --ground changes-scope --to person:owner" \
    "$(f 1 state)|$(shirabe_calls pass-up)"
# A pass-up koto refuses leaves the entry unescalated and the record unchanged.
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
qready; : > "$KOTO_STORE/decisions/passup-fail"
route "verdict 1" decision_verdict
refused "--escalate: a pass-up koto refuses is refused, the entry not escalated" --escalate "${ESC_ARGS[@]}"
# Unattended, the pass-up still lands.
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
qready
route "verdict 1" decision_verdict
KOTO_RUN_MODE=unattended rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: an unattended session's pass-up still lands" "escalated|1" "$(f 1 state)|$(shirabe_calls pass-up | wc -l | tr -d ' ')"
# A run reporting to a coordinator passes up to it, with no owner addressee.
setup "[$(E 1 coordinator-verdict "$HELD_A")]" 10 ws
qready
route "verdict 1" decision_verdict
rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: a run reporting to a coordinator escalates to it" "coordinator ws" "$(f 1 target)"
eq "  ... passed up with no --to" "question pass-up $QA --in $S --ground changes-scope --attempt 000000000005" "$(shirabe_calls pass-up)"
# An entry with no identity is refused until it holds one this session raised.
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
refused "--escalate: an entry holding no question identity is refused" --escalate "${ESC_ARGS[@]}"
question "$QA" true decision w1
refused "--identity: a question another session raised is refused" --identity "$QA"
refused "--identity: a malformed identity is refused" --identity "not-an-identity"
question "$QA" true decision "$S"
answered "$QA" answered SQLite
refused "--identity: a question koto shows closed is refused" --identity "$QA"
question "$QA" true decision "$S"
rd --identity "$QA"; wrote "--identity writes"
eq "--identity: the entry's source names the question, its stamp kept" "question $QA [20260925T080000Z raise 3]" "$(f 1 source)"
refused "--identity: an entry already held by a question is refused" --identity "$QB"
attempt "$QA" 000000000005
route "verdict 1" decision_verdict
rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: once it holds the identity, the entry escalates" "escalated" "$(f 1 state)"

# Four at a time per target, then by most waiting work items, oldest, identity.
QN() { printf 'w%s-0000/00000000000%s' "$1" "$1"; }
HELDN() { printf '{source: "question %s [20260926T070000Z report 3.%s]", options: "", grounds: "changes-scope", target: "a person"}' "$(QN "$1")" "$1"; }
four_and_two() { # four_and_two <pending-json>: entries 1-4 escalated, 5 and 6 queued
    local i list=
    for i in 1 2 3 4; do list="$list$(E "$i" escalated "$ESCALATED + $(HELDN "$i")"), "; done
    setup "[$list$(E 5 coordinator-verdict "$QUEUED + $(HELDN 5)"), $(E 6 coordinator-verdict "$QUEUED + $(HELDN 6)")]"
    for i in 1 2 3 4 5 6; do question "$(QN "$i")" true; attempt "$(QN "$i")" "00000000002$i"; done
    mkdir -p "$KOTO_STORE/decisions/pending"; printf '%s' "$1" > "$KOTO_STORE/decisions/pending/$S.json"
}
four_and_two "{\"questions\":[{\"identity\":\"$(QN 5)\",\"waiting\":1,\"raised\":\"2026-09-26T06:00:00Z\"},{\"identity\":\"$(QN 6)\",\"waiting\":3,\"raised\":\"2026-09-26T06:30:00Z\"}]}"
eq "--list: each queued entry with its age" "5|$(QN 5)|2026-09-26T07:00Z|yes,6" \
    "$(sec | jq -r '.queued | "\(.[0].decision)|\(.[0].identity)|\(.[0].since)|\(.[0].age_minutes > 0),\(.[1].decision)"')"
ev
eq "release: four at a time, the freed place goes to the entry with the most waiting work items" "coordinator-verdict|coordinator-verdict|escalated" "$(f 1 state)|$(f 5 state)|$(f 6 state)"
eq "  ... only that one passed up" "question pass-up $(QN 6) --in $S --ground changes-scope --attempt 000000000026 --to person:owner" "$(shirabe_calls pass-up)"
four_and_two "{\"questions\":[{\"identity\":\"$(QN 5)\",\"waiting\":2,\"raised\":\"2026-09-26T06:00:00Z\"},{\"identity\":\"$(QN 6)\",\"waiting\":2,\"raised\":\"2026-09-26T05:00:00Z\"}]}"
ev
eq "release: with as many waiting work items, the oldest goes first" "coordinator-verdict|escalated" "$(f 5 state)|$(f 6 state)"
four_and_two '{"questions":[]}'
ev
eq "release: with neither listed by pending, the lower identity goes first" "escalated|coordinator-verdict" "$(f 5 state)|$(f 6 state)"
# A fifth --escalate for the target queues: nothing is passed up until a place frees.
four_and_two '{"questions":[]}'
put_decisions "$(sec | jq -c '.entries | map(if .decision == "5" then .verdict = "" | .grounds = "" | .target = "" else . end)')" 10
route "verdict 5" decision_verdict
rd --escalate --grounds changes-scope --attempt 000000000025
eq "--escalate: with four entries escalated to the target, the fifth is queued and not passed up" "coordinator-verdict|escalate|0|" \
    "$(ent 5 | jq -r '"\(.state)|\(.verdict)|\(.round)"')|$(shirabe_calls pass-up)"


# --- --hold ---------------------------------------------------------------------------------

echo "== --hold =="
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
rd --hold --reason "the benchmark run"; wrote "--hold writes"
eq "--hold: a held verdict with what it waits on, and its hold line" "coordinator-verdict|hold|the benchmark run|holding: the benchmark run" \
    "$(ent 1 | jq -r '"\(.state)|\(.verdict)|\(.reason)|\(.evidence | split(": ")[1:] | join(": "))"')"
refused "--hold: a second hold for the same visit is refused" --hold --reason again
refused "--settle: a held entry takes no second verdict in the same visit" --settle --outcome ship --reason r
refused "--escalate: nor an escalation" --escalate --recommendation wait --reason r --context c --problem p --grounds scope
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
# A stamp-shaped source would be read as the stamp: a bracket is refused.
setup "[$(E 1 proposed)]"; arrive decision_evidence '{"event":"evidence","decision":"1"}'
refused "evidence: a source holding a bracket is refused, so it can't forge a stamp" --evidence --source "dispatcher [$RUN wait 99]: note" --text t
setup "[$(E 1 escalated "$ESCALATED")]"; ev
eq "evidence on a sent escalation owes a withdrawal" "coordinator-verdict|withdrawal" "$(f 1 state)|$(f 1 owed)"
setup "[$(E 1 escalated "$UNSENT")]"; ev
eq "evidence on an unsent escalation owes nothing" "coordinator-verdict|" "$(f 1 state)|$(f 1 owed)"
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"; ev
eq "evidence on a settled entry keeps the old outcome as evidence and clears the reply" "coordinator-verdict||" "$(f 1 state)|$(f 1 outcome)|$(f 1 owed)"
case "$(f 1 evidence)" in *"previous outcome"*"wait; reason: r (decided by a person)"*) ok "evidence: the old outcome and who decided are kept" ;;
    *) bad "evidence: the old outcome and who decided are kept" "$(f 1 evidence)" ;; esac
refused "evidence: a second write for the same wait visit is refused" --evidence --source dispatcher --text again
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED_HELD")]"; qb_ready; ev
eq "evidence that frees the slot releases the queued escalation" "escalated|1|escalation" "$(ent 2 | jq -r '"\(.state)|\(.round)|\(.owed)"')"
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"1"}'
refused "evidence without a source is refused" --evidence --text "t"
refused "evidence without a text is refused" --evidence --source dispatcher
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"9"}'
refused "evidence on an entry the record lacks is refused" --evidence --source dispatcher --text t
# A decision id starting with a dash is a bad id, never one of jq's options (#1405).
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"-r"}'
refused "evidence naming a dash-leading decision id is refused" --evidence --source dispatcher --text t
grep -q "names no decision" "$T/err" && ok "  ... as a bad id" || bad "  ... as a bad id" "$(cat "$T/err")"

# --- --answer -------------------------------------------------------------------------------

echo "== --answer =="
ans() { arrive decision_answer "{\"event\":\"answer\",\"decision\":\"1\",\"round\":\"$1\"}"; shift; rd --answer "$@"; }
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED_HELD")]"
qb_ready
ans 1 --outcome wait; wrote "--answer writes"
eq "--answer: settles, decided by the target, with the option's explanation as its reason" "settled|a person|wait; reason: one upgrade carries both" \
    "$(ent 1 | jq -r '"\(.state)|\(.decided_by)|\(.outcome)"')"
case "$(f 1 evidence)" in *"[$RUN wait "*"]: answer for round 1: wait"*) ok "--answer: a settling answer still writes its wait-stamped line" ;;
    *) bad "--answer: a settling answer still writes its wait-stamped line" "$(f 1 evidence)" ;; esac
eq "--answer: freeing the slot releases the queued escalation" "escalated" "$(f 2 state)"
E1_BEFORE=$(ent 1 | jq -c 'del(.evidence, .updated)')
ans 1 --outcome wait
eq "--answer: the same answer again leaves the entry as it is" "0 same" \
    "$RC $([ "$(ent 1 | jq -c 'del(.evidence, .updated)')" = "$E1_BEFORE" ] && echo same || echo changed)"
case "$(f 1 evidence)" in *"answer for round 1 again: wait"*) ok "--answer: and adds its own stamped line, so the arrival reads as recorded" ;;
    *) bad "--answer: and adds its own stamped line, so the arrival reads as recorded" "$(f 1 evidence)" ;; esac
setup "[$(E 1 settled '{round: "1", outcome: "wait; reason: r", decided_by: "a person"}')]"
ans 2 --outcome wait
eq "--answer: the same outcome for another round is evidence, not the same answer" "coordinator-verdict" "$(f 1 state)"

# A retry: decision_next routes back after a write that didn't land.
setup "[$(E 1 proposed)]"
arrive decision_evidence '{"event":"evidence","decision":"1"}'
route "unrecorded-evidence" decision_evidence
rd --evidence --source dispatcher --text "the check came back mixed"
eq "--evidence: a retry reached from decision_next reads the same arrival" "0 coordinator-verdict" "$RC $(f 1 state)"
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
# An entry held by a question settles from koto's record of it, not from the reply.
HELD_ESC="$ESCALATED + {source: \"question $QA [20260926T070000Z report 3.1]\", options: \"\", grounds: \"changes-scope\"}"
setup "[$(E 1 escalated "$HELD_ESC")]"
qready; answered "$QA" answered SQLite
route "unrecorded-answer 1 koto" decision_answer
refused "--answer: an --outcome that isn't koto's answer is refused" --answer --outcome Postgres
grep -q "not koto's answer" "$T/err" && ok "  ... naming koto's answer" || bad "  ... naming koto's answer" "$(cat "$T/err")"
rd --answer; wrote "--answer: koto's closed question settles the entry"
eq "--answer: outcome and decider from koto" "settled|SQLite; reason: one file is enough|session director" "$(f 1 state)|$(f 1 outcome)|$(f 1 decided_by)"
case "$(f 1 evidence)" in *"koto answer director:000000000001: SQLite"*) ok "--answer: koto's answer is cited as evidence" ;; *) bad "--answer: koto's answer is cited as evidence" "$(f 1 evidence)" ;; esac
setup "[$(E 1 escalated "$HELD_ESC")]"
qready; answered "$QA" withdrawn ""
route "unrecorded-answer 1 koto" decision_answer
rd --answer --outcome withdrawn
eq "--answer: a withdrawn question settles the entry as withdrawn" "settled|withdrawn; reason: one file is enough" "$(f 1 state)|$(f 1 outcome)"
# A typed reply for an owner-escalated entry koto still shows open leaves it escalated.
setup "[$(E 1 escalated "$HELD_ESC")]"
qready
ans 1 --outcome "use SQLite, I typed it"
wrote "--answer: a typed reply koto doesn't hold is recorded"
eq "--answer: a typed reply leaves the owner-escalated entry escalated" "escalated|1|" "$(f 1 state)|$(f 1 round)|$(f 1 outcome)"
case "$(f 1 evidence)" in *"arrived outside koto"*) ok "  ... with a line saying it settles from koto's record" ;; *) bad "  ... with a line saying it settles from koto's record" "$(f 1 evidence)" ;; esac

# --- --sent ---------------------------------------------------------------------------------

echo "== --sent =="
# render <state> <kind> <token>: decision_next routes, the real renderer renders
render_msg() {
    route "$3" "$1"
    log_capture "$S" "$4" "$(bash "$HERE/decision-render.sh" --session "$S" --state "$1" --kind "$2" 2>"$T/render.err")"
}
setup "[$(E 1 escalated "$UNSENT_HELD")]"; qready
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
to escalate_send
refused "--sent: an escalation to a person must name its route" --sent
rd --sent --route message; wrote "--sent writes"
eq "--sent: the escalation is no longer owed, and Asked is stamped" "|yes" "$(f 1 owed)|$([ -n "$(f 1 asked)" ] && echo yes)"
case "$(f 1 evidence)" in *"[$RUN ask "*"]: asked by message"*) ok "--sent: the route is recorded on the entry" ;; *) bad "--sent: the route is recorded on the entry" "$(f 1 evidence)" ;; esac
refused "--sent: marking it again is refused" --sent --route message
# Unattended, no question tool is asked: --route tool writes nothing, and the
# escalation is recorded as waiting on the record.
setup "[$(E 1 escalated "$UNSENT_HELD")]"; qready
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
to escalate_send
KOTO_RUN_MODE=unattended refused "--sent: --route tool in an unattended session is refused, nothing written" --sent --route tool
CLAUDE_CODE_SESSION_ATTENDED=0 refused "--sent: so is it when Claude Code reads the session unattended" --sent --route tool
KOTO_RUN_MODE=unattended rd --sent --route record; wrote "--sent: an unattended escalation is marked --route record"
case "$(f 1 evidence)" in *"[$RUN ask "*"]: waiting on the record"*) ok "--sent: the route is recorded as waiting on the record" ;;
    *) bad "--sent: the route is recorded as waiting on the record" "$(f 1 evidence)" ;; esac
setup "[$(E 1 escalated "$UNSENT_HELD")]"; qready
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
printf 'something else\n' > "$T/edited"; koto context add "$S" coord/decision_message.txt --from-file "$T/edited"
to escalate_send
refused "--sent: a text edited after the render is refused" --sent --route message
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"
render_msg decision_reply reply "reply 1" REPLY_MESSAGE
to decision_reply_send
rd --sent
eq "--sent: a reply is no longer owed" "" "$(f 1 owed)"
# The record edited by hand after the render: entry 1 is gone.
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"
render_msg decision_reply reply "reply 1" REPLY_MESSAGE
put_decisions "[$(E 3 proposed)]" 10
to decision_reply_send
refused "--sent: an entry gone from the live record is refused, the section untouched" --sent
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

# An item held by a question identity opens by that identity, worded by koto.
QITEM="{\"index\":1,\"kind\":\"question\",\"identity\":\"$QA\",\"text\":\"Which store?\",\"options\":[\"SQLite\"],\"source\":\"question $QA\",\"addressed\":false,\"cite\":null}"
setup "[]" 1
listed "[$QITEM]"
words '{"1":{"question":"in other words","options":["a -- b"]}}'
eq "--open-from-report: a wording for an item held by an identity is refused" 65 "$RC"
grep -q "item 1 is question $QA" "$T/err" && ok "  ... naming the item" || bad "  ... naming the item" "$(cat "$T/err")"
words '{}'
eq "--open-from-report: the identity item opens a proposed entry whose source is the question" "proposed|question $QA [$RUN report $RSEQ.1]" "$(f 1 state)|$(f 1 source)"
setup "[$(E 1 proposed "{source: \"question $QA [20260926T070000Z report 3.1]\"}")]" 2
listed "[$QITEM]"
words '{}'
eq "--open-from-report: an identity already held adds no entry" "1|2" "$(sec | jq -r '"\(.entries | length)|\(.next)"')"
case "$(f 1 evidence)" in *"reported again"*) ok "  ... only a line saying it was reported again" ;; *) bad "  ... only a line saying it was reported again" "$(f 1 evidence)" ;; esac

# A withdrawal naming a question identity reaches the entry held by it.
setup "[$(E 1 escalated "$HELD_ESC")]" 2
listed "[{\"index\":1,\"kind\":\"withdrawal\",\"text\":\"Withdrawn: decision 4 round 1.\",\"identity\":\"$QA\",\"source\":\"coordinator rr #4 round 1\",\"addressed\":false,\"cite\":null,\"n\":4,\"round\":1}]"
words '{}'
eq "--open-from-report: a withdrawal naming an identity reopens the entry held by it" "0 coordinator-verdict|withdrawal" "$RC $(f 1 state)|$(f 1 owed)"
setup "[$(E 1 escalated "$HELD_ESC")]" 2
listed "[{\"index\":1,\"kind\":\"withdrawal\",\"text\":\"Withdrawn: decision 4 round 1.\",\"identity\":\"$QB\",\"source\":\"coordinator rr #4 round 1\",\"addressed\":false,\"cite\":null,\"n\":4,\"round\":1}]"
refused "--open-from-report: a withdrawal naming an identity no entry holds is refused" --open-from-report --text-file "$(printf '{}' > "$T/w4.json"; echo "$T/w4.json")"

# --- entries from before identities: the escalation path they had ------------------------------

echo "== entries with no identity =="
# A run already under way holds queued entries with no identity: each keeps
# its verdict, and is released as before once no entry is escalated, with no
# pass-up (it has no question in koto).
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED"), $(E 3 proposed)]"
route "take 3" decision_take
rd --take
eq "an old queued entry keeps its verdict while an entry is escalated" "coordinator-verdict|escalate" "$(f 2 state)|$(f 2 verdict)"
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED")]"; ev
eq "evidence that frees the slot releases an old queued escalation, as before" "escalated|1|escalation" "$(ent 2 | jq -r '"\(.state)|\(.round)|\(.owed)"')"
eq "  ... with no pass-up" "" "$(shirabe_calls pass-up)"
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED")]"
ans 1 --outcome wait
eq "--answer: freeing the slot releases an old queued escalation, as before" "settled escalated" "$(f 1 state) $(f 2 state)"
setup "[$(E 1 escalated "$ESCALATED + {source: \"coordinator rr #4 round 1 [20260926T070000Z report 3.1]\"}"), $(E 2 coordinator-verdict "$QUEUED")]" 3
listed '[{"index":1,"kind":"withdrawal","text":"Withdrawn: decision 4 round 1.","source":"coordinator rr #4 round 1","addressed":false,"cite":null,"n":4,"round":1}]'
words '{}'
eq "--open-from-report: a withdrawal that frees the slot releases an old queued escalation, as before" "coordinator-verdict escalated" "$(f 1 state) $(f 2 state)"
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED + {options: \"ship now\\nwait\"}"), $(E 3 coordinator-verdict "$QUEUED")]"; ev
eq "release: the lowest old queued entry is the one, and one that no longer passes is cleared, not escalated" "coordinator-verdict||escalate" \
    "$(f 2 state)|$(f 2 verdict)|$(f 3 verdict)"
# An old entry escalates only once its question is raised here and held.
setup "[$(E 1 coordinator-verdict)]"
route "verdict 1" decision_verdict
refused "--escalate: an old entry with no identity is refused" --escalate "${ESC_ARGS[@]}"
grep -q "shirabe question raise --in $S" "$T/err" && grep -q -- "--identity <identity>" "$T/err" \
    && ok "  ... naming the raise and the --identity that hold it" || bad "  ... naming the raise and the --identity that hold it" "$(cat "$T/err")"

# --- --settle on an entry held by a question ---------------------------------------------------

echo "== --settle by koto =="
# by_me: the answer koto holds was decided by this session
by_me() {
    printf '{"decision":{"kind":"answer","reason":"mine","decider":{"kind":"session","session":{"value":"%s"}}}}' "$S" \
        > "$(KD show)/director_000000000001.json"
}
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
qready
route "verdict 1" decision_verdict
refused "--settle: an entry held by a question koto shows open is refused" --settle --outcome SQLite --reason "one file"
grep -q "settles only from koto's answer" "$T/err" && grep -q "shirabe question settle $QA --in $S" "$T/err" \
    && ok "  ... naming koto's settle" || bad "  ... naming koto's settle" "$(cat "$T/err")"
answered "$QA" answered SQLite
refused "--settle: an --outcome other than koto's answer is refused" --settle --outcome Postgres --reason r
rd --settle; wrote "--settle: once koto shows the question closed, the entry settles"
eq "  ... with koto's answer, reason and decider" "settled|SQLite; reason: one file is enough|session director" "$(f 1 state)|$(f 1 outcome)|$(f 1 decided_by)"

# A reserved ground keeps a decision for the owner: the coordinator passes it up.
setup "[$(E 1 coordinator-verdict '{grounds: "changes-scope"}')]"
route "verdict 1" decision_verdict
refused "--settle: an entry whose Grounds hold a reserved ground is refused" --settle --outcome ship --reason r
grep -q "reserved ground changes-scope" "$T/err" && grep -q -- "--escalate --grounds changes-scope" "$T/err" \
    && ok "  ... naming the ground and the pass-up" || bad "  ... naming the ground and the pass-up" "$(cat "$T/err")"
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
qready
h="$(KD history)/$(qkey "$QA").json"
jq -c '.entries += [{entry: "pass-up", session: "child", reason: "ground: outward-facing"}]' "$h" > "$h.new" && mv "$h.new" "$h"
answered "$QA" answered SQLite; by_me
route "verdict 1" decision_verdict
refused "--settle: this session's own answer to a question passed up to it on a reserved ground is refused" --settle
grep -q "reserved ground outward-facing" "$T/err" && ok "  ... the ground read from koto's pass-up" || bad "  ... the ground read from koto's pass-up" "$(cat "$T/err")"
setup "[$(E 1 coordinator-verdict "$HELD_A + {grounds: \"reserved-step\"}")]"
qready; answered "$QA" withdrawn ""; by_me
route "verdict 1" decision_verdict
rd --settle
eq "--settle: a withdrawal on a reserved entry settles it" "0 settled|withdrawn; reason: mine" "$RC $(f 1 state)|$(f 1 outcome)"
setup "[$(E 1 escalated "$HELD_ESC")]"
qready; answered "$QA" answered SQLite; by_me
route "unrecorded-answer 1 koto" decision_answer
refused "--answer: koto's answer by this session on a reserved entry is refused" --answer
grep -q "reserved ground changes-scope" "$T/err" && ok "  ... naming the ground" || bad "  ... naming the ground" "$(cat "$T/err")"

# --- a restart, SHIRABE_BIN ---------------------------------------------------------------------

echo "== restart and SHIRABE_BIN =="
# A restarted coordinator's new session holds no attempt for a question its
# predecessor attempted: the refusal names the line that records one here.
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
question "$QA" true
route "verdict 1" decision_verdict
refused "--escalate: with no attempt of this session's, refused" --escalate --grounds changes-scope
grep -qF "shirabe question attempt --in $S --what '<the question>' --result undecided --basis ${QA%/*}:${QA##*/}" "$T/err" \
    && ok "  ... naming the shirabe question attempt line for this session" || bad "  ... naming the shirabe question attempt line for this session" "$(cat "$T/err")"
printf '#!/usr/bin/env bash\nprintf "via SHIRABE_BIN\\n" >> "$KOTO_STORE/shirabe-bin-calls"\nexec "%s/testdata/question-stand-in/shirabe" "$@"\n' "$HERE" > "$T/shirabe-bin"
chmod +x "$T/shirabe-bin"
setup "[$(E 1 coordinator-verdict "$HELD_A")]"
qready; rm -f "$KOTO_STORE/shirabe-bin-calls"
route "verdict 1" decision_verdict
SHIRABE_BIN="$T/shirabe-bin" rd --escalate "${ESC_ARGS[@]}"
eq "--escalate: shirabe is SHIRABE_BIN when it is set" "0 escalated|1" "$RC $(f 1 state)|$(wc -l < "$KOTO_STORE/shirabe-bin-calls" | tr -d ' ')"

# --- --list's ages, release order by time, --open-questions -------------------------------------

echo "== ages and --open-questions =="
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED + {updated: \"\"}")]"
bash "$RD" --session "$S" --list > "$T/list.out" 2> "$T/err"; RC=$?
eq "--list: a queued entry with no Updated time fails the read, never prints without its age" "2|" "$RC|$(cat "$T/list.out")"
# Raise times are instants: 06:00:00.5 is after 06:00:00, though it sorts first as a string.
four_and_two "{\"questions\":[{\"identity\":\"$(QN 5)\",\"waiting\":2,\"raised\":\"2026-09-26T06:00:00.500Z\"},{\"identity\":\"$(QN 6)\",\"waiting\":2,\"raised\":\"2026-09-26T06:00:00Z\"}]}"
ev
eq "release: raise times compared as times, a fraction of a second later is later" "coordinator-verdict|escalated" "$(f 5 state)|$(f 6 state)"
# open/<S>.json: what koto decisions open --at S lists
koto_open() { mkdir -p "$KOTO_STORE/decisions/open"; printf '%s' "$1" > "$KOTO_STORE/decisions/open/$S.json"; }
oq() { OUT=$(bash "$RD" --session "$S" --open-questions 2>"$T/err"); RC=$?; }
setup "[$(E 1 escalated "$HELD_ESC"), $(E 2 coordinator-verdict "$HELD_B + {verdict: \"hold\", reason: \"r\"}")]"
oq
eq "--open-questions: none open, exit 0" '0 {"questions":[],"unhandled":[]}' "$RC $OUT"
QC=0a1b2c3d-c/000000000004
koto_open "{\"at\":\"$S\",\"questions\":[
  {\"identity\":\"$QC\",\"session\":\"w3\",\"time\":\"2026-09-26T06:30:00Z\",\"addressee\":{\"kind\":\"session\",\"name\":\"$S\"}},
  {\"identity\":\"$QA\",\"session\":\"w1\",\"time\":\"2026-09-26T06:00:00.250Z\",\"addressee\":{\"kind\":\"session\",\"name\":\"$S\"}},
  {\"identity\":\"$QB\",\"session\":\"w2\",\"time\":\"2026-09-26T06:00:00Z\",\"addressee\":{\"kind\":\"session\",\"name\":\"$S\"}},
  {\"identity\":\"w9-0000/000000000009\",\"session\":\"$S\",\"time\":\"2026-09-26T05:00:00Z\",\"addressee\":{\"kind\":\"person\",\"name\":\"owner\"}}],\"v\":1}"
oq
eq "--open-questions: one no entry handles, exit 1" "1 [\"$QC\"]" "$RC $(printf '%s' "$OUT" | jq -c .unhandled)"
eq "  ... only those addressed to this session, oldest first, each with its entry" "$QB:2:true|$QA:1:true|$QC:null:false" \
    "$(printf '%s' "$OUT" | jq -r '[.questions[] | "\(.identity):\(.decision):\(.handled)"] | join("|")')"
eq "  ... each with its raiser and an age in minutes" "w2|yes" "$(printf '%s' "$OUT" | jq -r '"\(.questions[0].raiser)|\(if .questions[0].age_minutes > 0 then "yes" else "no" end)"')"
: > "$KOTO_STORE/decisions/open-fail"
oq
eq "--open-questions: a koto read that fails is exit 2, never none open" "2|" "$RC|$OUT"

echo "== compaction =="
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", verdict: "settle", evidence: "2026-09-26T07:40Z dispatcher [20260926T070000Z wait 3]: mixed"}'), $(E 2 proposed)]"
route "take 2" decision_take
rd --take
eq "a write compacts a settled entry that owes nothing, keeping its options" "|ship now -- users get the format this week|" \
    "$(f 1 verdict)|$(f 1 options | head -1)|$(f 1 evidence)"

# --- --carry ----------------------------------------------------------------------------------

echo "== --carry =="
PRED="coordinate-discipline-ci-20260919T080000Z"
carry_setup() { # carry_setup <record entries> <predecessor's decisions> [predecessor]
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context" "$KOTO_STORE/decisions" "$KOTO_STORE/shirabe-calls"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    seed_session "$PRED" "$(record_json discipline ci | jq -c --argjson d "$2" '.decisions = $d')"
    S="coordinate-discipline-ci-$RUN"
    found_session "$S" "$(discipline_vars ci)"
    seed_session "$S" "$(record_json discipline ci | jq -c --argjson e "$1" '.decisions = {next: 2, entries: $e}')"
    jq -nc --arg p "${3-$PRED}" '{start: "2026-09-26", end: "2026-10-03", host_repo: "acme/widgets"} + (if $p == "" then {} else {predecessor: $p} end)' \
        | koto context add "$S" record/rotation
    LAST=reconcile
    to decision_carry
}
carry_setup '[]' "{\"next\": 6, \"entries\": [$(E 5 escalated "$ESCALATED")]}"
rd --carry; wrote "--carry writes"
eq "--carry: the predecessor's unsettled entries and its Next decision" "5|escalated|6" "$(sec | jq -r '"\([.entries[].decision] | join(","))|\(.entries[0].state)|\(.next)"')"
eq "  ... into this session's record/decisions" "5" "$(koto context get "$S" record/decisions | jq -r '[.entries[].decision] | join(",")')"
eq "  ... the predecessor's own section untouched" "5" "$(koto context get "$PRED" record/decisions | jq -r '[.entries[].decision] | join(",")')"
refused "--carry: again, with every entry already here, is refused" --carry
carry_setup '[]' "{\"next\": 6, \"entries\": [$(E 5 escalated "$ESCALATED")]}" ""
refused "--carry: a rotation that names no predecessor is refused" --carry
carry_setup '[]' "{\"next\": 6, \"entries\": [$(E 5 escalated "$ESCALATED")]}"
log_to "$S" decision_carry dispatch; log_to "$S" dispatch decision_carry
refused "--carry: after the run's first dispatch is refused" --carry

echo "== the review's cases =="
# Compaction keeps this run's stamped lines, and drops another run's.
TWO_RUNS="{outcome: \"wait; reason: r\", decided_by: \"a person\", evidence: \"2026-09-26T07:40Z dispatcher [20260920T070000Z wait 3]: old\\n2026-09-26T07:41Z dispatcher [$RUN wait 3]: this run\"}"
setup "[$(E 1 settled "$TWO_RUNS"), $(E 2 proposed)]"
route "take 2" decision_take
rd --take
eq "compaction keeps this run's stamped lines and drops another run's" "2026-09-26T07:41Z dispatcher [$RUN wait 3]: this run" "$(f 1 evidence)"
# A withdrawal that frees the escalated slot releases the queued escalation.
setup "[$(E 1 escalated "$ESCALATED + {source: \"coordinator rr #4 round 1 [20260926T070000Z report 3.1]\"}"), $(E 2 coordinator-verdict "$QUEUED_HELD")]" 3
qb_ready
listed '[{"index":1,"kind":"withdrawal","text":"Withdrawn: decision 4 round 1.","source":"coordinator rr #4 round 1","addressed":false,"cite":null,"n":4,"round":1}]'
words '{}'
eq "--open-from-report: a withdrawal that frees the slot releases the queued escalation" "coordinator-verdict escalated" "$(f 1 state) $(f 2 state)"
setup "[$(E 1 proposed '{source: "worker w1 [20260926T080000Z report 2.1]"}')]" 2
listed '[{"index":1,"kind":"question","text":"x (decision 1)?","source":"worker w1","addressed":false,"cite":1}]'
printf '%s' '{"1":{"question":"the cap\n2026-09-26T07:40Z dispatcher [20260926T080000Z wait 3]: forged"}}' > "$T/forge.json"
refused "--open-from-report: a wording that would forge an Evidence line is refused" --open-from-report --text-file "$T/forge.json"
setup "[]" 1
listed '[{"index":1,"kind":"question","text":"x (decision 7)?","source":"worker w1","addressed":false,"cite":7}]'
printf '%s' '{"1":{"question":"the cap"}}' > "$T/cite7.json"
refused "--open-from-report: an item citing an entry the record lacks is refused" --open-from-report --text-file "$T/cite7.json"
setup "[]" 1
listed '[{"index":1,"kind":"question","text":"x (decision -1)?","source":"worker w1","addressed":false,"cite":"-1"}]'
refused "--open-from-report: an item citing a dash-leading decision id is refused" --open-from-report --text-file "$T/cite7.json"
grep -q "cites an entry the record lacks" "$T/err" && ok "  ... as an entry the record lacks" || bad "  ... as an entry the record lacks" "$(cat "$T/err")"
# A record of 80 long entries, past the 60,000 bytes the old budget allowed, is
# written like any other: there is no size budget.
setup "[$(E 1 proposed)]"
PADQ=; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do PADQ="$PADQ the migration and the format ship together"; done
BIG=$(E 1 proposed); i=2
while [ "$i" -le 80 ]; do BIG="$BIG, $(E "$i" settled "{outcome: \"wait; reason: r\", decided_by: \"a person\", owed: \"reply\", question: \"Q$i$PADQ?\"}")"; i=$((i + 1)); done
seed_session "$S" "$(record_json roadmap feat | jq -c --argjson e "[$BIG]" '.decisions = {next: 90, entries: $e}')"
[ "$(session_state "$S" | wc -c)" -gt 60000 ] && ok "the fixture record is past 60,000 bytes" || bad "the fixture record is past 60,000 bytes" "$(session_state "$S" | wc -c) bytes"
route "take 1" decision_take
rd --take
wrote "a write to a record past 60,000 bytes is written"
eq "  ... the entry taken, the other 79 as they were" "coordinator-verdict|80" "$(f 1 state)|$(sec | jq '.entries | length')"

# A second run replaying the first run's very sequence numbers writes its own.
setup "[]" 1
listed '[{"index":1,"kind":"question","text":"x?","source":"worker w1","addressed":false,"cite":null}]'
put_decisions "[$(E 1 proposed "{source: \"worker w1 [20260925T080000Z report $RSEQ.1]\"}")]" 2
words '{"1":{"question":"This run'"'"'s question?","options":["a -- b"]}}'
eq "--open-from-report: another run's stamp with this very sequence doesn't block this run's" "0 2" "$RC $(sec | jq -r '.entries | length')"
# A queued verdict that no longer passes is cleared when the slot frees.
setup "[$(E 1 escalated "$ESCALATED"), $(E 2 coordinator-verdict "$QUEUED + {options: \"ship now\\nwait\"}")]"
ev
eq "release: a queued verdict that no longer passes is cleared, not escalated" "coordinator-verdict|" "$(f 2 state)|$(f 2 verdict)"
# An owed reply for a coordinator's entry and for the dispatcher's.
for src in "coordinator rr #4 round 1 [20260926T070000Z report 3.1]" "dispatcher [20260926T070000Z raise 3]"; do
    setup "[$(E 1 coordinator-verdict "{source: \"$src\"}")]"
    route "verdict 1" decision_verdict
    rd --settle --outcome wait --reason r
    eq "--settle: a reply is owed to the source ${src%% *}" "reply" "$(f 1 owed)"
done
# --sent reads the render's kind and round, and holds the entry to them.
setup "[$(E 1 escalated "$UNSENT_HELD")]"; qready
render_msg escalate escalation "escalate 1" ESCALATE_MESSAGE
put_decisions "[$(E 1 escalated "$UNSENT_HELD + {round: \"2\"}")]" 10
to escalate_send
refused "--sent: an entry whose round moved since the render is refused" --sent --route message
setup "[$(E 1 settled '{outcome: "wait; reason: r", decided_by: "a person", owed: "reply", source: "worker w1 [20260926T080000Z report 4.1]"}')]"
to decision_reply
printf 'Answer: decision 1 round 0.\n' > "$T/fake.txt"
KS=$(bash "$CL" seal --session "$S" --state decision_reply --file "$T/fake.txt" --key coord/decision_message.txt)
log_capture "$S" REPLY_MESSAGE "$(bash "$CL" seal --session "$S" --state decision_reply --token "message escalation 1 0 keyseal:${KS#sealed:}")"
to decision_reply_send
refused "--sent: a render of another kind than the send state's is refused" --sent

echo "== the section in the session: a Decisions transition =="
# The section lives in the run's session, record/decisions: --open writes it
# there, --take and --settle move the entry on, and --list reads it back.
setup '[]' 1
reset_calls
to decision_raise
rd --open --question "Pin the plugin?" --option "pin -- freezes a version" --option "don't pin -- lets a break through"
wrote "--open writes the section"
eq "  ... into record/decisions" "1|proposed|2" \
    "$(koto context get "$S" record/decisions | jq -r '"\(.entries[0].decision)|\(.entries[0].state)|\(.next)"')"
eq "  ... read back" "Pin the plugin?" "$(f 1 question)"
route "take 1" decision_take
rd --take; wrote "--take moves it on"
eq "  ... proposed to coordinator-verdict, in record/decisions" "coordinator-verdict" \
    "$(koto context get "$S" record/decisions | jq -r '.entries[0].state')"
route "verdict 1" decision_verdict
rd --settle --outcome pin --reason "the release is Friday"
wrote "--settle settles it"
eq "  ... coordinator-verdict to settled, in record/decisions" "settled|pin; reason: the release is Friday" \
    "$(koto context get "$S" record/decisions | jq -r '.entries[0] | "\(.state)|\(.outcome)"')"
eq "  ... and nothing read or written on GitHub but the host's visibility" "" "$(calls | grep -v -- '--jq .private')"

echo "== usage =="
setup '[]' 1
bash "$RD" --session "$S" >/dev/null 2>&1; eq "no mode is a usage error" 64 $?
bash "$RD" --session "$S" --take --scope roadmap --name feat --repo acme/widgets >/dev/null 2>&1
eq "a write mode takes no override flags" 64 $?
bash "$RD" --session "$S" --list --ref 7 >/dev/null 2>&1
eq "--ref is no option" 64 $?

done_tests state-decision
