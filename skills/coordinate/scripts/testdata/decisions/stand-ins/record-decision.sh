#!/usr/bin/env bash
# record-decision.sh -- STAND-IN for decisions-replay_engine_test.sh, until
# the coordinate-decisions plan's Issue 7 ships the real script; Issue 7
# removes it from the harness's STAND_INS.
#
# It takes the real script's arguments and reads the same things the real one
# reads: the entry decision_next routed from its sealed DECISION_NEXT capture,
# an answer's or evidence's entry and round from this visit's `wait` evidence,
# the report's questions from the context key coord/questions.json, the run's
# target from REPORTS_TO, and the live record through gh. It changes the
# Decisions section by the DESIGN's mode table (evidence resets, an owed reply
# unless the latest evidence is the source's withdrawal, a withdrawal owed only
# for a sent escalation, the answer by round, one escalated entry at a time,
# the queued escalation released by the write that frees the slot) and writes
# the body back with the real codec.
#
# What it doesn't do that the real script will: bind a mode to the state the
# session is in, refuse a second write for the same stamp, check the sealed
# question list or the message key against their seals, the carry, the size
# budget and the write core's checks, and compaction. Those are Issue 7's, and
# its own tests cover them.
#
# Usage: record-decision.sh --session S <mode>
#   --list | --read N
#   --open --question Q --option O [--option O]... [--source self|dispatcher]
#   --open-from-report --text-file F      F: {"<index>": {"question": Q, "options": [O, ...]}}
#   --take
#   --settle --outcome O --reason R
#   --escalate --recommendation R --reason W --context C --problem P --grounds G
#   --hold --reason R
#   --evidence --source S --text T
#   --answer --outcome O [--reason R] [--final D]
#   --sent
# Exit 0 done or printed; 1 no entry N (--read); 2 a read failed; 65 refused.
set -uo pipefail
PROG=record-decision
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= MODE= N= Q= SRC=self TEXTF= OUTC= REASON= REC= CTX= PROB= GROUNDS= ESRC= ETEXT= FINAL=
OPTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --session) SESSION=$2; shift 2 ;;
        --list|--take|--sent|--open|--open-from-report|--settle|--escalate|--hold|--evidence|--answer) MODE=${1#--}; shift ;;
        --read) MODE=read; N=$2; shift 2 ;;
        --question) Q=$2; shift 2 ;;
        --option) OPTS+=("$2"); shift 2 ;;
        --source) if [ "$MODE" = evidence ]; then ESRC=$2; else SRC=$2; fi; shift 2 ;;
        --text-file) TEXTF=$2; shift 2 ;;
        --text) ETEXT=$2; shift 2 ;;
        --outcome) OUTC=$2; shift 2 ;;
        --reason) REASON=$2; shift 2 ;;
        --recommendation) REC=$2; shift 2 ;;
        --context) CTX=$2; shift 2 ;;
        --problem) PROB=$2; shift 2 ;;
        --grounds) GROUNDS=$2; shift 2 ;;
        --final) FINAL=$2; shift 2 ;;
        --route) shift 2 ;;
        *) echo "$PROG: unknown argument $1" >&2; exit 64 ;;
    esac
done
SCOPE= NAME= REPO=
. "$HERE/record-common.sh"
lib_facts
lib_run_stamp
REF=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION" | jq -r .ref) || lib_die2 "no found record"
T=$(mktemp -d "${TMPDIR:-/tmp}/rd-standin.XXXXXX")
trap 'rm -rf "$T"' EXIT
refuse() { echo "$PROG: refused: $*" >&2; exit 65; }

gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$T/live.md" || lib_die2 "cannot read #$REF"
lib_parse "$T/live.md" "$T/rec.json" || { cat "$T/rec.json.err" >&2; lib_die2 "the record isn't canonical"; }
jq '.decisions //= {next: 1, entries: []}' "$T/rec.json" > "$T/r" && mv "$T/r" "$T/rec.json"

case "$MODE" in
    list) jq -c '.decisions' "$T/rec.json"; exit 0 ;;
    read) jq -ce --arg n "$N" '.decisions.entries[] | select(.decision == $n)' "$T/rec.json" || exit 1; exit 0 ;;
esac

NOW=$(date -u +%Y-%m-%dT%H:%MZ)
seq_of() { bash "$HERE/coord-log.sh" entry --session "$SESSION" --state "$1" | cut -d' ' -f1; }
routed() { # the entry decision_next's sealed capture names
    bash "$HERE/coord-log.sh" capture --session "$SESSION" --name DECISION_NEXT --state decision_next | cut -d' ' -f2
}
target() {
    local rt
    rt=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.REPORTS_TO // ""')
    if [ -n "$rt" ]; then printf 'coordinator %s' "$rt"; else printf 'a person'; fi
}

# The DESIGN's rules, as jq definitions over one entry and the section.
LIB='include "record-codec";
def ev_line($who; $stamp; $text): "\($now) \($who) \($stamp): \($text)";
def add_ev($line): .evidence = (if (.evidence // "") == "" then $line else .evidence + "\n" + $line end);
def src_who: (.source | sub(" \\[.*$"; ""));
def withdrawn_by_source: src_who as $who
  | ((.evidence // "") | split("\n") | last // "" | sub("^[^ ]+ "; "")) as $l
  | ($l | startswith("\($who) [")) and ($l | test("\\]: withdrawn: "));
def owes_reply: (.source | test("^(worker|coordinator|dispatcher) ")) and (withdrawn_by_source | not);
def evidence($who; $stamp; $text):
  (if .state == "settled" then add_ev(ev_line("previous outcome"; $stamp; "\(.outcome) (decided by \(.decided_by))")) | .outcome = "" | .decided_by = "" else . end)
  | add_ev(ev_line($who; $stamp; $text))
  | .owed = (if .state == "escalated" then (if .owed == "escalation" then "" else "withdrawal" end)
             elif .owed == "reply" then "" else (.owed // "") end)
  | .verdict = "" | .state = "coordinator-verdict" | .updated = $now;
def settle($o; $by): .state = "settled" | .verdict = "settle" | .outcome = $o | .decided_by = $by
  | .owed = (if owes_reply then "reply" else "" end) | .updated = $now;
def escalate_now($t): .state = "escalated" | .round = ((.round | tonumber) + 1 | tostring) | .owed = "escalation"
  | .target = $t | .updated = $now;
# A write that frees the one escalated slot releases the queued escalation
# with the lowest identifier, or clears a queued verdict that no longer passes.
def release($t):
  if any(.entries[]; .state == "escalated") then .
  else ([.entries[] | select(.state == "coordinator-verdict" and .verdict == "escalate") | .decision | tonumber] | min) as $q
    | if $q == null then .
      else .entries |= map(if .decision == ($q | tostring) then
          (if (escalation_problems($t) | length) == 0 then escalate_now($t) else .verdict = "" end) else . end) end
  end;'

apply() { # apply <jq program over .decisions> [jq args]: write the record back
    local p=$1; shift
    jq -L "$HERE" --arg now "$NOW" "$@" "$LIB .decisions |= ($p)" "$T/rec.json" > "$T/next.json" 2> "$T/jq.err" \
        || { cat "$T/jq.err" >&2; refuse "the change doesn't apply"; }
    bash "$HERE/record-render.sh" --container issue --written "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$T/next.json" > "$T/body.md" 2> "$T/render.err" \
        || { cat "$T/render.err" >&2; refuse "the codec refuses the change"; }
    gh issue edit "$REF" --repo "$REPO" --body-file "$T/body.md" >/dev/null || lib_die2 "cannot write #$REF"
}
has() { # has <n> <filter> [jq args]
    local n=$1 f=$2; shift 2
    jq -e --arg n "$n" "$@" "$f" "$T/rec.json" >/dev/null
}

case "$MODE" in
open)
    [ -n "$Q" ] && [ ${#OPTS[@]} -gt 0 ] || refuse "a question and its options"
    OJ=$(jq -nc '$ARGS.positional | join("\n")' --args "${OPTS[@]}")
    apply '.entries += [{decision: (.next | tostring), round: "0", question: $q, options: $o, state: "proposed",
        source: "\($src) [\($run) raise \($seq)]", updated: $now}] | .next += 1' \
        --arg q "$Q" --argjson o "$OJ" --arg src "$SRC" --arg run "$RUN" --arg seq "$(seq_of decision_raise)" ;;
open-from-report)
    [ -r "$TEXTF" ] || refuse "a text file"
    koto context get "$SESSION" coord/questions.json > "$T/q.json" || lib_die2 "no question list"
    TOPIC=$(koto context get "$SESSION" report_topic)
    apply '
      reduce $q[0][] as $i (.;
        ("\($run) report \($seq).\($i.index)") as $st
        | ($w[0][($i.index | tostring)]) as $words
        | if $i.kind == "withdrawal" then
            .entries |= map(if (.source | startswith("coordinator \($topic) #\($i.n) round \($i.round) ")) and .state != "settled"
                            then evidence("coordinator \($topic) #\($i.n) round \($i.round)"; "[\($st)]"; "withdrawn: decision \($i.n) round \($i.round)") else . end)
          else
            (if $i.kind == "escalation" then "coordinator \($topic) #\($i.n) round \($i.round)" else "worker \($topic)" end) as $who
            | .entries += [{decision: (.next | tostring), round: "0", question: $words.question,
                options: ($words.options | join("\n")), state: "proposed", source: "\($who) [\($st)]", updated: $now}
                + (if $i.addressed then {evidence: ev_line($who; "[\($st)]"; "addressed to a person; redirected to the coordinator")} else {} end)]
            | .next += 1
          end)' \
        --slurpfile q "$T/q.json" --slurpfile w "$TEXTF" --arg run "$RUN" --arg seq "$(seq_of report_questions)" --arg topic "$TOPIC" ;;
take)
    N=$(routed); has "$N" '.decisions.entries[] | select(.decision == $n and .state == "proposed")' || refuse "entry $N isn't proposed"
    apply '.entries |= map(if .decision == $n then .state = "coordinator-verdict" | .updated = $now else . end)' --arg n "$N" ;;
settle)
    N=$(routed); [ -n "$OUTC" ] && [ -n "$REASON" ] || refuse "an outcome and its reason"
    has "$N" '.decisions.entries[] | select(.decision == $n and .state == "coordinator-verdict")' || refuse "entry $N isn't awaiting a verdict"
    apply '.entries |= map(if .decision == $n then settle("\($o); reason: \($r)"; "this coordinator") else . end) | release($t)' \
        --arg n "$N" --arg o "$OUTC" --arg r "$REASON" --arg t "$(target)" ;;
escalate)
    N=$(routed)
    has "$N" '.decisions.entries[] | select(.decision == $n and .state == "coordinator-verdict")' || refuse "entry $N isn't awaiting a verdict"
    apply '.entries |= map(if .decision == $n then .verdict = "escalate" | .recommendation = $rec | .reason = $why
              | .context = $c | .problem = $p | .grounds = $g | .target = $t | .updated = $now else . end)
           | (.entries[] | select(.decision == $n) | escalation_problems($t)) as $bad
           | if ($bad | length) > 0 then error("the escalation fails: \($bad | join("; "))") else . end
           | if any(.entries[]; .state == "escalated") then . else .entries |= map(if .decision == $n then escalate_now($t) else . end) end' \
        --arg n "$N" --arg rec "$REC" --arg why "$REASON" --arg c "$CTX" --arg p "$PROB" --arg g "$GROUNDS" --arg t "$(target)" ;;
hold)
    N=$(routed); [ -n "$REASON" ] || refuse "what the verdict waits on"
    apply '.entries |= map(if .decision == $n then .verdict = "hold" | .reason = $r
              | add_ev(ev_line("this coordinator"; "[\($run) hold \($seq)]"; "holding: \($r)")) | .updated = $now else . end)' \
        --arg n "$N" --arg r "$REASON" --arg run "$RUN" --arg seq "$(seq_of decision_verdict)" ;;
evidence|answer)
    EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state wait) || lib_die2 "no wait evidence"
    N=$(printf '%s' "$EV" | jq -r '.fields.decision // ""')
    RND=$(printf '%s' "$EV" | jq -r '.fields.round // ""')
    WSEQ=$(printf '%s' "$EV" | jq -r '.seq')
    has "$N" '.decisions.entries[] | select(.decision == $n)' || refuse "no entry $N"
    TG=$(target)
    if [ "$MODE" = answer ]; then
        BY=$TG; [ -n "$FINAL" ] && BY="$TG (final: $FINAL)"
        [ -n "$REASON" ] || REASON="the answer chose this option"
        if has "$N" '.decisions.entries[] | select(.decision == $n and .state == "escalated" and .round == $r)' --arg r "$RND"; then
            apply '.entries |= map(if .decision == $n then settle("\($o); reason: \($why)"; $by) else . end) | release($t)' \
                --arg n "$N" --arg o "$OUTC" --arg why "$REASON" --arg by "$BY" --arg t "$TG"
            exit 0
        elif has "$N" '.decisions.entries[] | select(.decision == $n and .state == "settled" and .outcome == $o and .decided_by == $by)' \
                --arg o "$OUTC; reason: $REASON" --arg by "$BY"; then
            exit 0
        fi
        ESRC=$TG ETEXT="answer for round $RND: $OUTC"
    fi
    [ -n "$ESRC" ] && [ -n "$ETEXT" ] || refuse "evidence needs a source and a text"
    apply '.entries |= map(if .decision == $n then evidence($who; "[\($run) wait \($seq)]"; $text) else . end) | release($t)' \
        --arg n "$N" --arg who "$ESRC" --arg text "$ETEXT" --arg run "$RUN" --arg seq "$WSEQ" --arg t "$TG" ;;
sent)
    # The send state the session is in names the render state and its capture.
    ST=$(jq -r 'select(.type == "transitioned" or .type == "directed_transition") | .payload.to' \
        "$(koto session dir "$SESSION")/koto-$SESSION.state.jsonl" | tail -1)
    case "$ST" in
        escalate_send) RS=escalate CN=ESCALATE_MESSAGE ;;
        decision_withdraw_send) RS=decision_withdraw CN=WITHDRAW_MESSAGE ;;
        decision_reply_send) RS=decision_reply CN=REPLY_MESSAGE ;;
        decision_redirect_send) RS=decision_redirect CN=REDIRECT_MESSAGE ;;
        *) refuse "not in a send state ($ST)" ;;
    esac
    CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name "$CN" --state "$RS") || refuse "no render to mark sent"
    set -- $CAP
    KIND=$2 N=$3
    case "$KIND" in
        escalation) apply '.entries |= map(if .decision == $n then .owed = "" | .asked = $now | .updated = $now else . end)' --arg n "$N" ;;
        withdrawal|reply) apply '.entries |= map(if .decision == $n then .owed = "" | .updated = $now else . end)' --arg n "$N" ;;
        redirect)
            RS=$(printf '%s\n' "$CAP" | tr ' ' '\n' | sed -n 's/^report://p')
            [ -n "$RS" ] || refuse "the redirect's render names no report"
            apply '.entries |= map(if .decision == $n then
                     add_ev(ev_line("this coordinator"; "[\($run) redirect \($rs)]"; "redirect sent")) | .updated = $now else . end)' \
                --arg n "$N" --arg run "$RUN" --arg rs "$RS" ;;
    esac ;;
*) echo "$PROG: no mode" >&2; exit 64 ;;
esac
