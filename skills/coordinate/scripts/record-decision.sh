#!/usr/bin/env bash
# record-decision.sh -- the one reader and writer of the record's Decisions
# section. Every script that reads the section reads it through --list and
# --read; the write modes are the only way anything changes it.
#
# Usage:
#   record-decision.sh --session S --list        print the section
#   record-decision.sh --session S --read N      print entry N
#   record-decision.sh --session S <write mode>
#   ... [--scope roadmap|discipline --name N --repo O/R --ref N]   (tests; reads only)
#
# The session gives the scope, name, host and record number (coord-log.sh
# vars and run-facts); the override flags exist for tests of the read modes.
#
# The write modes, each bound to the state the session is in (coord-log.sh
# current) and, where it has one, to the entry the workflow routed:
#
#   --carry                                        decision_carry
#       Copies the previous rotation's handoff (docs/disciplines/<name>.md on
#       the default branch) into this record: its unsettled entries and its
#       Next decision. Refused after the run's first dispatch, and when every
#       entry is already here.
#   --open --question Q --option O [--option O]... [--source self|dispatcher]
#                                                  decision_raise
#       A proposed entry, Source `<source> [<run> raise <seq>]`.
#   --open-from-report --text-file F               decision_open
#       F maps each extracted item's index to the coordinator's wording,
#       {"<index>": {"question": Q, "options": [O, ...]}}. The list is read
#       from coord/questions.json, checked against report_questions' seal,
#       never from an argument. Every item but a withdrawal must be covered
#       exactly once. A question opens a proposed entry, Source `worker <topic>`
#       or `coordinator <topic> #<n> round <r>`, stamped
#       `[<run> report <seq>.<index>]`; a cited question is evidence on the
#       cited entry; a withdrawal is evidence on the entry opened from its
#       source. An addressed question also gets the addressed mark (the
#       codec's d_addressed_mark) as an Evidence line with the same stamp.
#   --take                                         decision_take
#       The routed proposed entry to coordinator-verdict.
#   --settle --outcome O --reason R                decision_verdict
#       Settles the routed entry: Outcome `<O>; reason: <R>`, Decided by
#       `the coordinator`, Owed reply when the Source is a worker, a
#       coordinator or the dispatcher and the latest evidence isn't that
#       source's withdrawal.
#   --escalate --recommendation R --reason W --context C --problem P
#              --grounds G[,G...] [--option '<option> -- <explanation>']...
#                                                  decision_verdict
#       Escalates the routed entry to the run's target (REPORTS_TO): Round up
#       by one, Owed escalation; or queues the verdict when another entry is
#       escalated. --option gives every option its explanation, the options
#       themselves unchanged. Refused unless the shared validator
#       (escalation_problems) passes.
#   --hold --reason R                              decision_verdict
#       Verdict hold, Reason what it waits on, a `hold` Evidence line.
#   --evidence --source S --text T                 decision_evidence
#       Evidence on the entry this visit's `wait` evidence names. Clears the
#       Verdict (a hold or a queued escalation too) and moves the entry to
#       coordinator-verdict; on a settled entry the old outcome and decider go
#       to Evidence and an owed reply clears; on a sent escalation Owed
#       becomes withdrawal, on an unsent one it clears.
#   --answer --outcome O [--reason R] [--final D]  decision_answer
#       The answer to the entry and round the `wait` evidence (the message
#       route) or the `escalate_send` evidence (the question-tool route) names.
#       On the escalated entry at that round it settles with Decided by the
#       run's target, followed by ` (final: D)` when a nested coordinator's
#       reply names a final decider; O is one of the options (its explanation
#       is the reason) or an outcome with --reason. An identical answer again
#       changes nothing; any other answer is evidence, as --evidence.
#   --sent [--route tool|message]                  a *_send state
#       Marks the message the matching render state rendered as sent, when
#       coord/decision_message.txt checks against that render's seal and the
#       entry still owes it: Owed cleared (and Asked stamped for an
#       escalation), or, for a redirect, a `redirect <report seq>` Evidence
#       line. An escalation to a person records its route as an `ask`
#       Evidence line; --route is required then.
#
# Every write carries a stamp naming its run (lib_run_stamp) and the visit
# that caused it; a second write for the same stamp is refused, so a retry
# after a failed compare-and-swap never duplicates. Any single item holding a
# line break is refused. A write that frees the one escalated slot releases
# the queued escalation with the lowest identifier, or clears its verdict when
# it no longer passes. Every settled entry that owes nothing, other than the
# one this write changed, is compacted (the codec's compact_settled). The body
# is written through record-write-core.sh with the Decisions section opened
# (DECISIONS_WRITER=1), which re-reads the record, compares its Written: line
# and checks provenance, visibility and the size budget.
#
# Exit codes: 0 printed, or written (prints the record's URL); 1 no entry N
# (--read only); 2 a read failed; 10 refused (not a canonical open record of
# this scope, provenance, a directed transition); 11 the write failed; 12 the
# record changed since it was read (run it again); 13 record-full: the body
# is over the size budget; 64 usage; 65 refused: a transition the table
# doesn't list, a missing verdict part, a mode run outside its state, a stamp
# already written, or the body refused.
#
# GitHub reads: gh issue view N --repo R --json body | gh pr view N --repo R
# --json body; gh api repos/R (the default branch) and its contents (the
# handoff, for --carry). Writes happen only in record-write-core.sh.
set -uo pipefail

PROG=record-decision
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= REF= MODE= ENTRY=
Q= SRC= TEXTF= TEXT= OUTC= REASON= REC= CTX= PROB= GROUNDS= FINAL= ROUTE=
OPTS=()
SKIP_CHECKS=0 BODY= END= CLOSE=0

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
mode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --list) mode list; shift ;;
        --read) [ $# -ge 2 ] || usage; mode read; ENTRY=$2; shift 2 ;;
        --carry|--open|--open-from-report|--take|--settle|--escalate|--hold|--evidence|--answer|--sent) mode "${1#--}"; shift ;;
        --question) [ $# -ge 2 ] || usage; Q=$2; shift 2 ;;
        --option) [ $# -ge 2 ] || usage; OPTS+=("$2"); shift 2 ;;
        --source) [ $# -ge 2 ] || usage; SRC=$2; shift 2 ;;
        --text-file) [ $# -ge 2 ] || usage; TEXTF=$2; shift 2 ;;
        --text) [ $# -ge 2 ] || usage; TEXT=$2; shift 2 ;;
        --outcome) [ $# -ge 2 ] || usage; OUTC=$2; shift 2 ;;
        --reason) [ $# -ge 2 ] || usage; REASON=$2; shift 2 ;;
        --recommendation) [ $# -ge 2 ] || usage; REC=$2; shift 2 ;;
        --context) [ $# -ge 2 ] || usage; CTX=$2; shift 2 ;;
        --problem) [ $# -ge 2 ] || usage; PROB=$2; shift 2 ;;
        --grounds) [ $# -ge 2 ] || usage; GROUNDS=$2; shift 2 ;;
        --final) [ $# -ge 2 ] || usage; FINAL=$2; shift 2 ;;
        --route) [ $# -ge 2 ] || usage; ROUTE=$2; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in
    list) ;;
    read) [[ $ENTRY =~ ^[1-9][0-9]*$ ]] || usage ;;
    '') usage ;;
    *) [ -z "$SCOPE$NAME$REPO$REF" ] || { echo "$PROG: the write modes take no override flags" >&2; exit 64; } ;;
esac
. "$HERE/record-common.sh"
lib_facts
if [ "$OVERRIDE" = 1 ]; then
    [ -n "$REF" ] || { echo "$PROG: --ref goes with the override flags" >&2; exit 64; }
else
    [ -z "$REF" ] || usage
    FACTS=$(bash "$HERE/coord-log.sh" run-facts --session "$SESSION")
    case $? in
        0) REF=$(printf '%s' "$FACTS" | jq -r '.ref') ;;
        1) echo "$PROG: refused: the run has no found record" >&2; exit 10 ;;
        *) lib_die2 "cannot read the run's facts" ;;
    esac
fi
[[ $REF =~ $RE_NUM ]] || usage

WD=$(mktemp -d "${TMPDIR:-/tmp}/record-decision.XXXXXX")
# The write core takes over the EXIT trap; CORE_CLEANUP has it remove this too.
CORE_CLEANUP=$WD
trap 'rm -rf "$WD"' EXIT

# read_live: the live body, parsed canonically into $WD/parsed.json.
read_live() {
    if [ "$SCOPE" = roadmap ]; then
        gh issue view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.md" 2> "$WD/gh.err" < /dev/null \
            || { lib_scrub < "$WD/gh.err" >&2; echo >&2; lib_die2 "cannot read issue #$REF"; }
    else
        gh pr view "$REF" --repo "$REPO" --json body --jq .body > "$WD/live.md" 2> "$WD/gh.err" < /dev/null \
            || { lib_scrub < "$WD/gh.err" >&2; echo >&2; lib_die2 "cannot read pull request #$REF"; }
    fi
    lib_parse "$WD/live.md" "$WD/parsed.json"
    case $? in
        0) ;;
        3|65) echo "$PROG: refused: #$REF is not a canonical $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
        *) lib_die2 "record-parse.sh failed" ;;
    esac
}

read_live
case "$MODE" in
list)
    jq -c '.decisions // {next: 1, entries: []}' "$WD/parsed.json"
    exit 0
    ;;
read)
    E=$(jq -c --arg n "$ENTRY" '[(.decisions.entries // [])[] | select(.decision == $n)][0] // empty' "$WD/parsed.json")
    [ -n "$E" ] || exit 1
    printf '%s\n' "$E"
    exit 0
    ;;
esac

# --- the write modes -----------------------------------------------------------------

refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
lib_write_guard
lib_run_stamp
NOW=$(date -u +%Y-%m-%dT%H:%MZ)

# A single item never holds a line break: the codec's line break also
# separates Options and Evidence lines, so one could forge an item.
for v in "$Q" "$TEXT" "$OUTC" "$REASON" "$REC" "$CTX" "$PROB" "$GROUNDS" "$FINAL" "$SRC" ${OPTS[@]+"${OPTS[@]}"}; do
    case "$v" in *$'\n'*|*$'\r'*) refuse "an item holds a line break" ;; esac
done

# The state the session is in binds the mode.
CUR=$(bash "$HERE/coord-log.sh" current --session "$SESSION") || lib_die2 "cannot read the session's current state"
CUR_STATE=${CUR%% *} CUR_SEQ=${CUR##* }
case "$MODE" in
    carry) WANT=decision_carry ;; open) WANT=decision_raise ;; open-from-report) WANT=decision_open ;;
    take) WANT=decision_take ;; settle|escalate|hold) WANT=decision_verdict ;;
    evidence) WANT=decision_evidence ;; answer) WANT=decision_answer ;;
    sent) WANT="escalate_send decision_withdraw_send decision_reply_send decision_redirect_send" ;;
esac
case " $WANT " in *" $CUR_STATE "*) ;; *) refuse "--$MODE runs in ${WANT// / or }, and the session is in $CUR_STATE" ;; esac

TARGET_RT=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.REPORTS_TO // ""') || lib_die2 "cannot read the session's variables"
if [ -n "$TARGET_RT" ]; then TARGET="coordinator $TARGET_RT"; else TARGET="a person"; fi

# routed <word>: the entry decision_next's sealed capture routed here, with that word.
routed() {
    local cap
    cap=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name DECISION_NEXT --state decision_next)
    case $? in 0) ;; 1) refuse "no sealed decision_next verdict from its latest visit" ;; *) lib_die2 "cannot read the decision_next capture" ;; esac
    printf '%s' "$cap"
}
routed_entry() { # routed_entry <word>: prints N, refusing another word
    local cap w n
    cap=$(routed) || exit $?
    w=$(printf '%s' "$cap" | cut -d' ' -f1)
    n=$(printf '%s' "$cap" | cut -d' ' -f2)
    [ "$w" = "$1" ] || refuse "decision_next routed \`$w\`, not \`$1\`"
    [[ $n =~ ^[1-9][0-9]*$ ]] || refuse "decision_next's verdict names no entry"
    printf '%s' "$n"
}

# The rules, as jq definitions over the parsed record. $now, $run and $t (the
# run's target) are bound on every call.
LIB='include "record-codec";
def blank: (. // "") | gsub("^\\s+|\\s+$"; "") == "";
def ev_line($who; $stamp; $text): "\($now) \($who) [\($stamp)]: \($text)";
def add_ev($line): .evidence = (if (.evidence // "") == "" then $line else .evidence + "\n" + $line end);
def src_who: (.source // "") | sub(" \\[[^]]*\\]$"; "");
def withdrawn_by_source: src_who as $who
  | ((.evidence // "") | split("\n") | map(select(length > 0)) | last // "") as $l
  | ($l | sub("^[^ ]+ "; "") | startswith("\($who) [")) and ($l | test("\\]: withdrawn: "));
def owes_reply: (.source | test("^(worker|coordinator|dispatcher) ")) and (withdrawn_by_source | not);
def evidence($who; $stamp; $text):
  (if .state == "settled" then add_ev(ev_line("previous outcome"; $stamp; "\(.outcome) (decided by \(.decided_by))"))
     | .outcome = "" | .decided_by = "" else . end)
  | add_ev(ev_line($who; $stamp; $text))
  | .owed = (if .state == "escalated" then (if .owed == "escalation" then "" else "withdrawal" end)
             elif .owed == "reply" then "" else (.owed // "") end)
  | .verdict = "" | .state = "coordinator-verdict" | .updated = $now;
def settle($o; $by): .state = "settled" | .verdict = "settle" | .outcome = $o | .decided_by = $by
  | .owed = (if owes_reply then "reply" else "" end) | .updated = $now;
def escalate_now: .state = "escalated" | .round = ((.round | tonumber) + 1 | tostring)
  | .owed = "escalation" | .target = $t | .updated = $now;
# The write that frees the one escalated slot releases the queued escalation
# with the lowest identifier, or clears its verdict when it no longer passes.
def release:
  if any(.entries[]; .state == "escalated") then .
  else ([.entries[] | select(.state == "coordinator-verdict" and .verdict == "escalate") | .decision | tonumber] | min) as $q
    | if $q == null then .
      else .entries |= map(if .decision == ($q | tostring) then
          (if (escalation_problems($t) | length) == 0 then escalate_now else .verdict = "" end) else . end) end
  end;
def stamped($kind; $seq): any(.entries[] | d_stamps[]; .run == $run and .kind == $kind and .seq == $seq);
def stamped_report($seq): any(.entries[] | d_stamps[]; .run == $run and .kind == "report" and (.seq | split(".")[0]) == $seq);
def entry($n): .entries[] | select(.decision == $n);
def compact_except($n): .entries |= map(if .decision == $n then . else compact_settled end);'

SEC() { jq -c '.decisions // {next: 1, entries: []}' "$WD/parsed.json"; }
# change <program over the section> [jq args]: the new section, or a refusal
# (a jq error() is the refusal's reason).
change() {
    local p=$1; shift
    SEC | jq -c -L "$HERE" --arg now "$NOW" --arg run "$RUN" --arg t "$TARGET" "$@" "$LIB $p" > "$WD/section.json" 2> "$WD/jq.err" \
        || refuse "$(sed -n 's/^jq: error ([^)]*): //p' "$WD/jq.err" | head -1)"
}
# write: the section into the record, through the write core.
write() {
    jq --slurpfile d "$WD/section.json" '.decisions = $d[0] | del(.written)' "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    bash "$HERE/record-render.sh" --container "$CONTAINER" --written "$(jq -r '.written' "$WD/parsed.json")" "$WD/next.json" \
        > "$WD/body.md" 2> "$WD/render.err" || { echo "$PROG: refused:" >&2; lib_scrub < "$WD/render.err" >&2; echo >&2; exit 65; }
    BODY="$WD/body.md"
    . "$HERE/record-write-core.sh"
    # The one script that may change the section.
    DECISIONS_WRITER=1
    core_write
    exit 0
}
has_entry() { # has_entry <n> <jq test over the entry>
    SEC | jq -e --arg n "$1" '[.entries[] | select(.decision == $n) | '"$2"'] | any' >/dev/null
}

case "$MODE" in
carry)
    [ "$SCOPE" = discipline ] || refuse "only a discipline rotation carries a handoff"
    lib_dispatched && refuse "the run has dispatched; a carry comes before the first dispatch"
    lib_default_branch || lib_die2 "cannot read $REPO's default branch"
    lib_file_at "docs/disciplines/$NAME.md" "$DEFAULT_BRANCH" "$WD/handoff.md"
    case $? in 0) ;; 1) refuse "no handoff at docs/disciplines/$NAME.md" ;; *) lib_die2 "cannot read the handoff" ;; esac
    bash "$HERE/record-parse.sh" --format handoff "$WD/handoff.md" > "$WD/handoff.json" 2> "$WD/handoff.err" \
        || { lib_scrub < "$WD/handoff.err" >&2; echo >&2; refuse "the handoff isn't canonical"; }
    change '. as $s | ($h[0].decisions // {next: 1, entries: []}) as $hd
      | ([$hd.entries[] | select(.state != "settled") | select(.decision as $d | all($s.entries[]; .decision != $d))]) as $add
      | if ($add | length) == 0 and $hd.next <= $s.next then error("every entry of the handoff is already here") else . end
      | .entries += $add | .entries |= sort_by(.decision | tonumber) | .next = ([.next, $hd.next] | max)' \
        --slurpfile h "$WD/handoff.json"
    write ;;
open)
    [ -n "$Q" ] && [ ${#OPTS[@]} -gt 0 ] || refuse "an entry needs a question and its options"
    SRC=${SRC:-self}
    case "$SRC" in self|dispatcher) ;; *) refuse "--source is self or dispatcher" ;; esac
    OJ=$(jq -nc '$ARGS.positional | join("\n")' --args "${OPTS[@]}")
    change 'if stamped("raise"; $seq) then error("this visit to decision_raise already opened an entry") else . end
      | .entries += [{decision: (.next | tostring), round: "0", question: $q, options: $o, state: "proposed",
          source: "\($src) [\($run) raise \($seq)]", updated: $now}] | .next += 1 | compact_except("")' \
        --arg q "$Q" --argjson o "$OJ" --arg src "$SRC" --arg seq "$CUR_SEQ"
    write ;;
open-from-report)
    [ -n "$TEXTF" ] && [ -r "$TEXTF" ] || usage
    jq -e 'type == "object"' "$TEXTF" >/dev/null || refuse "the text file is not a JSON object"
    QCAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name QUESTIONS --state report_questions)
    case $? in 0) ;; 1) refuse "no sealed report_questions verdict from its latest visit" ;; *) lib_die2 "cannot read the report_questions capture" ;; esac
    QSEAL=$(printf '%s\n' "$QCAP" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p')
    [ -n "$QSEAL" ] || refuse "report_questions' verdict carries no list"
    bash "$HERE/coord-log.sh" check --session "$SESSION" --state report_questions --sealed "$QSEAL" --key coord/questions.json > "$WD/questions.json"
    case $? in 0) ;; 1) refuse "coord/questions.json doesn't check against report_questions' seal" ;; *) lib_die2 "cannot check the question list" ;; esac
    RSEQ=$(printf '%s' "$QSEAL" | cut -d: -f2)
    change '($q[0]) as $items | ($w[0]) as $words
      | if stamped_report($seq) then error("this run already wrote report \($seq)") else . end
      | ([$items[] | select(.kind != "withdrawal") | .index | tostring]) as $need
      | if ($words | keys | sort) != ($need | sort) then
          error("the wording covers items [\($words | keys | sort | join(","))], and the list needs [\($need | sort | join(","))], each once") else . end
      | reduce $items[] as $i (.;
          "\($run) report \($seq).\($i.index)" as $st
          | ($words[($i.index | tostring)] // {}) as $wd
          | if $i.kind == "withdrawal" then
              .entries |= map(if (.source | startswith("\($i.source) [")) then evidence($i.source; $st; "withdrawn: decision \($i.n) round \($i.round)") else . end)
            elif ($i.cite // null) != null then
              .entries |= map(if .decision == ($i.cite | tostring) then
                  evidence($i.source; $st; ($wd.question // "") | if blank then error("item \($i.index) has no wording") else . end)
                  | (if $i.addressed then add_ev(ev_line($i.source; $st; d_addressed_mark)) else . end) else . end)
            else
              (($wd.question // "") | if blank then error("item \($i.index) has no question") else . end) as $qq
              | (($wd.options // []) | if length == 0 then error("item \($i.index) has no options") else . end
                 | if any(.[]; test("[\\n\\r]")) then error("an option holds a line break") else . end | join("\n")) as $oo
              | if ($qq | test("[\\n\\r]")) then error("a question holds a line break") else . end
              | .entries += [{decision: (.next | tostring), round: "0", question: $qq, options: $oo, state: "proposed",
                  source: "\($i.source) [\($st)]", updated: $now}
                  + (if $i.addressed then {evidence: ev_line($i.source; $st; d_addressed_mark)} else {} end)]
              | .next += 1
            end)
      | compact_except("")' \
        --slurpfile q "$WD/questions.json" --slurpfile w "$TEXTF" --arg seq "$RSEQ"
    write ;;
take)
    N=$(routed_entry take) || exit $?
    change 'entry($n).state as $s | if $s != "proposed" then error("entry \($n) is \($s), not proposed") else . end
      | .entries |= map(if .decision == $n then .state = "coordinator-verdict" | .updated = $now else . end) | compact_except($n)' --arg n "$N"
    write ;;
settle|escalate|hold)
    N=$(routed_entry verdict) || exit $?
    has_entry "$N" '.state == "coordinator-verdict"' || refuse "entry $N isn't awaiting a verdict"
    case "$MODE" in
    settle)
        [ -n "$OUTC" ] && [ -n "$REASON" ] || refuse "a settle needs an outcome and its reason"
        change '.entries |= map(if .decision == $n then settle("\($o); reason: \($r)"; "the coordinator") else . end) | release | compact_except($n)' \
            --arg n "$N" --arg o "$OUTC" --arg r "$REASON" ;;
    escalate)
        OJ=$(jq -nc '$ARGS.positional' --args ${OPTS[@]+"${OPTS[@]}"})
        change '($opts | map(split(" -- ")[0])) as $given
          | (entry($n) | d_options | map(.label)) as $labels
          | if ($opts | length) > 0 and ($given | sort) != ($labels | sort) then
              error("--option names [\($given | join(", "))], and the entry'"'"'s options are [\($labels | join(", "))]") else . end
          | .entries |= map(if .decision == $n then
              (if ($opts | length) > 0 then .options = ($opts | join("\n")) else . end)
              | .verdict = "escalate" | .recommendation = $rec | .reason = $why | .context = $c | .problem = $p
              | .grounds = $g | .target = $t | .updated = $now else . end)
          | (entry($n) | escalation_problems($t)) as $bad
          | if ($bad | length) > 0 then error("the escalation fails: \($bad | join("; "))") else . end
          | if any(.entries[]; .state == "escalated") then . else .entries |= map(if .decision == $n then escalate_now else . end) end
          | compact_except($n)' \
            --arg n "$N" --arg rec "$REC" --arg why "$REASON" --arg c "$CTX" --arg p "$PROB" --arg g "$GROUNDS" --argjson opts "$OJ" ;;
    hold)
        [ -n "$REASON" ] || refuse "a hold needs what the verdict waits on"
        change 'if stamped("hold"; $seq) then error("this visit already held a verdict") else . end
          | .entries |= map(if .decision == $n then .verdict = "hold" | .reason = $r
              | add_ev(ev_line("the coordinator"; "\($run) hold \($seq)"; "holding: \($r)")) | .updated = $now else . end) | compact_except($n)' \
            --arg n "$N" --arg r "$REASON" --arg seq "$CUR_SEQ" ;;
    esac
    write ;;
evidence|answer)
    FROM=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state "$CUR_STATE" | cut -d' ' -f2) || lib_die2 "cannot read how the run reached $CUR_STATE"
    case "$FROM" in wait|escalate_send) ;; *) refuse "$CUR_STATE was reached from $FROM, which names no entry" ;; esac
    [ "$FROM" = escalate_send ] && [ "$MODE" != answer ] && refuse "only an answer comes from escalate_send"
    EV=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state "$FROM" --before "$CUR_SEQ") || lib_die2 "cannot read the $FROM evidence"
    N=$(printf '%s' "$EV" | jq -r '.fields.decision // ""')
    RND=$(printf '%s' "$EV" | jq -r '.fields.round // ""')
    WSEQ=$(printf '%s' "$EV" | jq -r '.seq')
    [[ $N =~ ^[1-9][0-9]*$ ]] || refuse "the $FROM evidence names no decision"
    has_entry "$N" 'true' || refuse "the record has no entry $N"
    if [ "$MODE" = answer ]; then
        [[ $RND =~ ^[1-9][0-9]*$ ]] || refuse "an answer names its round"
        [ -n "$OUTC" ] || refuse "an answer needs an outcome"
        BY=$TARGET
        [ -n "$FINAL" ] && [ "$FINAL" != "the coordinator" ] && BY="$TARGET (final: $FINAL)"
        if has_entry "$N" ".state == \"escalated\" and .round == \"$RND\""; then
            if [ -z "$REASON" ]; then
                REASON=$(SEC | jq -r -L "$HERE" --arg n "$N" --arg o "$OUTC" 'include "record-codec";
                    .entries[] | select(.decision == $n) | [d_options[] | select(.label == $o) | .explanation][0] // ""')
                [ -n "$REASON" ] || refuse "an answer that isn't one of the options needs --reason"
            fi
            change 'if stamped("wait"; $seq) then error("this answer is already recorded") else . end
              | .entries |= map(if .decision == $n then add_ev(ev_line($by; "\($run) wait \($seq)"; "answer for round \($r): \($o)"))
                  | settle("\($o); reason: \($why)"; $by) else . end) | release | compact_except($n)' \
                --arg n "$N" --arg r "$RND" --arg o "$OUTC" --arg why "$REASON" --arg by "$BY" --arg seq "$WSEQ"
            write
        fi
        # The same answer again, to an entry it already settled, is recorded.
        if has_entry "$N" '.state == "settled"' && SEC | jq -e --arg n "$N" --arg o "$OUTC" --arg by "$BY" \
                '.entries[] | select(.decision == $n) | (.outcome | startswith("\($o); reason: ")) and .decided_by == $by' >/dev/null; then
            echo "$PROG: entry $N is already settled by this answer; nothing to write" >&2
            exit 0
        fi
        SRC_EV=$TARGET TEXT="answer for round $RND: $OUTC"
    else
        [ -n "$SRC" ] || refuse "evidence names its source (--source)"
        [ -n "$TEXT" ] || refuse "evidence needs its text"
        SRC_EV=$SRC
    fi
    change 'if stamped("wait"; $seq) then error("this evidence is already recorded") else . end
      | .entries |= map(if .decision == $n then evidence($who; "\($run) wait \($seq)"; $text) else . end) | release | compact_except($n)' \
        --arg n "$N" --arg who "$SRC_EV" --arg text "$TEXT" --arg seq "$WSEQ"
    write ;;
sent)
    case "$CUR_STATE" in
        escalate_send) RS=escalate CN=ESCALATE_MESSAGE K=escalation ;;
        decision_withdraw_send) RS=decision_withdraw CN=WITHDRAW_MESSAGE K=withdrawal ;;
        decision_reply_send) RS=decision_reply CN=REPLY_MESSAGE K=reply ;;
        decision_redirect_send) RS=decision_redirect CN=REDIRECT_MESSAGE K=redirect ;;
    esac
    CAP=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name "$CN" --state "$RS")
    case $? in 0) ;; 1) refuse "no sealed render from $RS's latest visit" ;; *) lib_die2 "cannot read the $RS capture" ;; esac
    set -f; set -- $CAP; set +f
    [ "${1-}" = message ] && [ "${2-}" = "$K" ] || refuse "$RS rendered \`${1-} ${2-}\`, not a $K"
    N=${3-} R=${4-}
    [[ $N =~ ^[1-9][0-9]*$ ]] || refuse "the render names no entry"
    KSEAL=$(printf '%s\n' "$CAP" | tr ' ' '\n' | sed -n 's/^keyseal:/sealed:/p')
    RSEQ=$(printf '%s\n' "$CAP" | tr ' ' '\n' | sed -n 's/^report://p')
    bash "$HERE/coord-log.sh" check --session "$SESSION" --state "$RS" --sealed "$KSEAL" --key coord/decision_message.txt > /dev/null
    case $? in 0) ;; 1) refuse "coord/decision_message.txt doesn't check against $RS's seal: send only the text as rendered" ;; *) lib_die2 "cannot check the message" ;; esac
    case "$K" in
    escalation)
        if [ "$TARGET" = "a person" ]; then
            case "$ROUTE" in tool|message) ;; *) refuse "an escalation to a person records its route: --route tool or --route message" ;; esac
        else
            case "$ROUTE" in ''|message) ROUTE=message ;; *) refuse "an escalation to a coordinator is sent as a message" ;; esac
        fi
        change 'entry($n) as $e | if $e.owed != "escalation" or $e.round != $r then error("entry \($n) owes no escalation for round \($r)") else . end
          | if stamped("ask"; $seq) then error("this visit already marked a message sent") else . end
          | .entries |= map(if .decision == $n then .owed = "" | .asked = $now
              | (if $t == "a person" then add_ev(ev_line("the coordinator"; "\($run) ask \($seq)"; "asked by \($route)")) else . end)
              | .updated = $now else . end) | compact_except($n)' \
            --arg n "$N" --arg r "$R" --arg route "$ROUTE" --arg seq "$CUR_SEQ" ;;
    withdrawal|reply)
        change 'entry($n) as $e | if $e.owed != $k then error("entry \($n) owes no \($k)") else . end
          | .entries |= map(if .decision == $n then .owed = "" | .updated = $now else . end) | compact_except($n)' \
            --arg n "$N" --arg k "$K" ;;
    redirect)
        [[ $RSEQ =~ ^[1-9][0-9]*$ ]] || refuse "the redirect's render names no report"
        change 'if stamped("redirect"; $rs) then error("report \($rs) has had its redirect") else . end
          | .entries |= map(if .decision == $n then add_ev(ev_line("the coordinator"; "\($run) redirect \($rs)"; "redirect sent")) | .updated = $now else . end)
          | compact_except($n)' --arg n "$N" --arg rs "$RSEQ" ;;
    esac
    write ;;
esac
