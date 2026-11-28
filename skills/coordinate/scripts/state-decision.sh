#!/usr/bin/env bash
# state-decision.sh -- the one reader and writer of the record's Decisions
# section. The decision scripts read the section through --list and --read
# (closeout-read.sh and reconcile read it in the state state-read.sh hands
# them, as they read the rest of the record, and pick-facts.sh and
# decision-next.sh --parsed through
# --list's own projection, state-schema.jq decisions_list, over a read they
# already hold); the write modes are the only way anything changes it.
#
# Usage:
#   state-decision.sh --session S --list        print the section, and
#       `queued`: each queued escalation {decision, identity, since,
#       age_minutes} when there are any. An entry whose Updated doesn't read
#       as a time is refused by the record schema (exit 10), never printed without its age
#   state-decision.sh --session S --read N      print entry N; an entry held
#       by a question also carries `content`, koto decisions content read's
#       JSON for it (its question, options and reasons as koto holds them)
#   state-decision.sh --session S --open-questions
#       every question koto lists open and addressed to this session (koto
#       decisions open --at S, the addressee this session itself), oldest
#       first, as {questions: [{identity, raiser, raised, age_minutes,
#       decision, state, handled}], unhandled: [<identity>...]}. decision is
#       the entry holding the identity (null for none); handled is true when
#       that entry is escalated, queued for escalation or held (Verdict hold).
#       Exit 0 when every one is handled, 1 when any is not (each listed in
#       unhandled), 2 when a read failed. Read-only: a closing step calls it
#       to refuse while a question addressed to the coordinator waits on
#       nothing. Its age_minutes is null for a raise time koto gives that
#       doesn't read as a time
#   state-decision.sh --session S <write mode>
#   ... [--scope roadmap|discipline --name N --repo O/R]   (tests; reads only)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests of the read modes, with RS_SESSION naming the session that holds it.
#
# The write modes, each bound to the state the session is in (coord-log.sh
# current) and, where it has one, to the entry the workflow routed:
#
#   --carry                                        decision_carry
#       Copies the previous rotation's Decisions (the session this rotation's
#       record/rotation names as its predecessor) into this record: its
#       unsettled entries and its Next decision. Refused after the run's first
#       dispatch, for a rotation that names no predecessor, and when every
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
#       source, or, when it names a question identity (report-questions.sh
#       reads one from a withdrawal of an entry held by a question), on the
#       entry held by that identity. An addressed question also gets the addressed mark (the
#       state-schema.jq's d_addressed_mark) as an Evidence line with the same stamp.
#       An item held by a question identity (report-questions.sh takes those
#       from koto's listing) needs no wording, and a wording given for one is
#       refused, naming the item: it opens a proposed entry, Source
#       `question <identity>`, with koto's ask and option labels. An identity
#       that already has an entry adds only a stamped `reported again` line
#       there, so a re-report opens nothing and releases nothing twice.
#   --take                                         decision_take
#       The routed proposed entry to coordinator-verdict.
#   --settle --outcome O --reason R                decision_verdict
#       Settles the routed entry: Outcome `<O>; reason: <R>`, Decided by
#       `the coordinator`, Owed reply when the Source is a worker, a
#       coordinator or the dispatcher and the latest evidence isn't that
#       source's withdrawal. An entry held by a question settles only from
#       koto: while koto shows the question open --settle is refused (answer
#       it in koto with shirabe question settle, or pass it up), and once koto
#       shows it closed the outcome, reason and decider are koto's, as
#       --answer takes them, and an --outcome other than koto's is refused.
#       An entry carrying a reserved ground (contradicts-answer,
#       changes-scope, outward-facing, reserved-step: its Grounds cell, or
#       the ground of the latest pass-up that brought its question here, as
#       koto decisions history records it) is never settled by the
#       coordinator: --settle is refused and the refusal says to pass it up.
#   --identity I                                   decision_verdict
#       Holds the routed entry, which has no identity yet, by question I:
#       its Source becomes `question I`, keeping its stamp. Refused unless
#       koto shows I open and raised by this session (koto decisions
#       history). An entry held by a question owes no reply message: its
#       answer is koto's record.
#   --escalate --grounds G [--attempt A] [--reason W]  decision_verdict
#       Passes the routed entry's question up to the run's target
#       (REPORTS_TO, or the owner when there is none) with shirabe question
#       pass-up, on exactly one of pass-up's grounds (contradicts-answer,
#       changes-scope, outward-facing, reserved-step, outside-scope;
#       outside-scope never to a person). Only an entry held by a question
#       identity escalates; one with none is refused until --identity gives
#       it one, and the refusal says how (raise the question with shirabe
#       question raise, then --identity). An old-style entry already
#       escalated or queued with no identity (a run under way when entries
#       came to be held by identities) keeps its old path: a queued one keeps
#       its verdict and is released as before, when no entry is escalated,
#       or has its verdict cleared when escalation_problems no longer
#       passes, and decision-render.sh renders it as before. A decision needs --attempt A (`<id>` or `<session>:<id>`):
#       koto decisions attempts --in=<session> --question <identity> must
#       list A as an undecided attempt of this session's; a missing, decided,
#       provisional or untied attempt is refused, naming it, and nothing is
#       written. A need takes no attempt. The question's wording is its
#       content in koto, so --recommendation, --context, --problem and
#       --option are refused for it. Escalated means Round up by one, Owed
#       escalation, after pass-up lands; at most four entries are escalated
#       to a target at once, and the rest stay queued (Verdict escalate).
#       Every write releases queued entries into free places: most waiting
#       work items first (the `waiting` count shirabe question pending gives,
#       the length of the content's waiting list), then the oldest raise,
#       then the identity. A pass-up koto already shows for this session is
#       not repeated, so a retry after a failed write passes nothing up
#       twice. A release that can't pass up (no undecided attempt left, the
#       question closed) leaves the entry queued and says why on stderr.
#       Raise times are compared as instants, as shirabe orders them (a
#       fraction of a second counts; one that doesn't read sorts last).
#       Limit: only an attempt recorded in this session counts. A coordinator
#       restarted in a new session (a successor of the same chain) holds none
#       for a question its predecessor attempted, since koto decisions
#       attempts reads one session and pass-up takes only the passing
#       session's own; the refusal names the line that records one here,
#       shirabe question attempt --in <session> --what <question> --result
#       undecided --basis <raiser>:<decision id>.
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
#       is the reason) or an outcome with --reason. The same answer again (its
#       round, outcome and decider) leaves the entry as it is and adds only
#       its own stamped line; any other answer is evidence, as --evidence.
#       The arrival is the latest of its kind before this visit, so a retry
#       decision_next routes here after a write that didn't land reads it too.
#       An entry held by a question settles only from koto: when
#       decision_next routed `unrecorded-answer <n> koto` (koto shows the
#       question closed) after the latest arrival, or an arrival names such
#       an entry and koto shows it closed, the outcome, reason and decider
#       are koto's (koto decisions history, then show), an --outcome other
#       than koto's answer is refused, and a withdrawn question settles as
#       `withdrawn`. An arrival for such an entry koto still shows open (a
#       typed reply) adds only its stamped Evidence line: the entry stays as
#       it is, escalated or not. koto's answer to an entry carrying a reserved
#       ground (as --settle reads it), given by this session, is refused: the
#       coordinator doesn't answer what the ground keeps for the owner.
#   --sent [--route tool|message|record]           a *_send state
#       Marks the message the matching render state rendered as sent, when
#       coord/decision_message.txt checks against that render's seal and the
#       entry still owes it: Owed cleared (and Asked stamped for an
#       escalation), or, for a redirect, a `redirect <report seq>` Evidence
#       line. An escalation marks every entry its render listed
#       (`entries:<n>@<round>.<n>@<round>`). An escalation to a person records
#       its route as an `ask` Evidence line; --route is required then.
#       `record` means the question waits on the record, asked by no one now.
#       In a session read as unattended (KOTO_RUN_MODE=unattended or
#       CLAUDE_CODE_SESSION_ATTENDED=0, as shirabe reads it) --route tool is
#       refused and nothing is written: there is no one to ask.
#
# A record moved from a GitHub record may carry archived entries: an Archived
# line and `decisions` entries holding their rows as the old body did. An
# archived entry named by --evidence, --answer or a citation in
# --open-from-report is restored first: its row comes back from the latest
# unedited `decisions` entry holding it, and its identifier leaves the Archived
# line, in the same write that records the arrival. A withdrawal reaches only
# the entries in the section. Nothing archives an entry any more.
#
# The stamps, which decision-next.sh reads to tell whether this run's write
# landed. Each names the run (lib_run_stamp) and a log sequence:
#   raise <seq>        --open: the visit to decision_raise
#   report <seq>.<i>   --open-from-report: the report_questions visit that
#                      sealed the list, and the item's index
#   wait <seq>         --evidence, --answer: the arrival's evidence event
#                      (a wait event, or escalate_send's `answered`)
#   hold <seq>         --hold: the visit to decision_verdict
#   ask <seq>          --sent, an escalation to a person: the send visit
#   redirect <seq>     --sent, a redirect: the report's sequence
# A second write for a stamp already written is refused (exit 65), so a retry
# after a failed compare-and-swap never duplicates. The modes that write no
# stamp (--take, --settle, --escalate, --carry, --sent for a reply or a
# withdrawal) are held by their state instead: once one lands, the entry is no
# longer in the state the mode needs, and a repeat is refused (a verdict mode
# also needs the Verdict empty, so one visit records one verdict). Any single
# item holding a line break is refused, and a source or final decider holding
# a bracket, which could forge the stamp after it. Up to four entries are
# escalated to a target at a time; a write that frees one of those places
# releases the queued entry with the most waiting work items, then the oldest,
# then the lowest identity, or clears its verdict when it no longer passes. On every write but --carry (which copies
# the predecessor's entries as they stand), every settled entry that owes nothing, other
# than the one this write changed, is compacted (state-schema.jq's
# compact_settled), keeping the Evidence lines stamped by this run for as long
# as the run lasts. The state
# is written through state-write-core.sh with the Decisions section opened
# (DECISIONS_WRITER=1), which re-reads the record, compares its written time
# and checks provenance and visibility.
#
# Exit codes: 0 printed, or written (prints the session holding the record);
# 1 no entry N (--read only); 2 a read failed; 10 refused (no found record, a
# record that doesn't read back as this scope's, provenance, a directed
# transition, a writing session that isn't the record's driver); 11 the write failed; 12 the record changed since it was read
# (run it again); 64 usage; 65 refused: a transition the table doesn't list, a
# missing verdict part, a mode run outside its state, a stamp already written,
# or the state refused.
#
# The record, and for --carry the predecessor's, is read through
# state-read.sh; writes happen only in state-write-core.sh.
set -uo pipefail

PROG=state-decision
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= MODE= ENTRY=
Q= SRC= TEXTF= TEXT= OUTC= REASON= REC= CTX= PROB= GROUNDS= FINAL= ROUTE= ATTEMPT= QID=
OPTS=()
SKIP_CHECKS=0 STATE_FILE=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
mode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --list) mode list; shift ;;
        --open-questions) mode open-questions; shift ;;
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
        --attempt) [ $# -ge 2 ] || usage; ATTEMPT=$2; shift 2 ;;
        --identity) [ $# -ge 2 ] || usage; mode identity; QID=$2; shift 2 ;;
        *) usage ;;
    esac
done
case "$MODE" in
    list|open-questions) ;;
    read) [[ $ENTRY =~ ^[1-9][0-9]*$ ]] || usage ;;
    '') usage ;;
    *) [ -z "$SCOPE$NAME$REPO" ] || { echo "$PROG: the write modes take no override flags" >&2; exit 64; } ;;
esac
. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-decision.XXXXXX") || lib_die2 "cannot make a temporary directory"
# The write core takes over the EXIT trap; CORE_CLEANUP has it remove this too.
CORE_CLEANUP=$WD
trap 'rm -rf "$WD"' EXIT

# read_live [<fields>]: the live record into $WD/parsed.json, only <fields>'
# sections when given.
read_live() {
    rs_record "$WD/parsed.json" "${1:-}"
    case $? in
        0) ;;
        4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
        12) lib_scrub < "$WD/parsed.json.err" >&2; exit 12 ;;
        65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2; exit 10 ;;
        *) lib_scrub < "$WD/parsed.json.err" >&2; echo >&2
           lib_die2 "cannot read the record" ;;
    esac
}

# --list and --read print from the Decisions section alone, so they read that
# one section; a write reads the whole record it writes back (shirabe#1315).
case "$MODE" in list|read|open-questions) read_live decisions ;; *) read_live ;; esac
# shirabe, as the other coordinate scripts call it: SHIRABE_BIN, else the one on PATH.
SHIRABE=${SHIRABE_BIN:-shirabe}
# The one question-identity pattern (state-schema.jq's re_identity).
RE_IDENTITY='^[A-Za-z0-9][A-Za-z0-9._-]*/[0-9]{1,20}$'

# --- koto's record of a question -----------------------------------------------------
#
# A failed koto or shirabe read is an error (exit 2), never "absent".
# koto_read <file> <args...>: koto's answer into <file>.
koto_read() {
    local f=$1; shift
    "$KOTO" "$@" > "$f" 2> "$WD/koto.err" || { lib_scrub < "$WD/koto.err" >&2; echo >&2; lib_die2 "cannot read koto ($1 $2)"; }
}
# history_of <identity>: koto decisions history into $WD/history.json.
history_of() { koto_read "$WD/history.json" decisions history "$1"; }
# attempt_of <identity> <id or empty>: the undecided attempt of this
# session's tied to the question (the one named, else the latest), "" for none.
attempt_of() {
    koto_read "$WD/attempts.json" decisions attempts "--in=$SESSION" --question "$1"
    jq -r --arg q "$1" --arg a "$2" '[(.attempts // [])[] | select(.result == "undecided" and (.status // "in-effect") == "in-effect")
        | select(((.questions // []) | index($q)) != null or .question == $q)
        | select($a == "" or .id == $a) | .id] | last // ""' "$WD/attempts.json"
}
# unattended: shirabe's reading of the run mode.
unattended() { [ "${KOTO_RUN_MODE:-}" = unattended ] || [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 0 ]; }
# attempt_line <identity>: the line that records an undecided attempt at the
# question in this session, the one a refusal for a missing attempt names.
attempt_line() {
    printf "shirabe question attempt --in %s --what '<the question>' --result undecided --basis %s:%s" "$SESSION" "${1%/*}" "${1##*/}"
}

case "$MODE" in
list)
    # A queued escalation's age runs from its entry's Updated, the time its
    # verdict was recorded. An Updated that doesn't read as a time fails the
    # read: an age is never left out or made up.
    jq -c -L "$HERE" 'include "state-schema"; decisions_list
      | ([.entries[] | select(.state == "coordinator-verdict" and .verdict == "escalate")
          | {decision, identity: d_identity, since: .updated,
             age_minutes: ((.updated | age_minutes(now)) // error("entry \(.decision) has no Updated time to age its queued escalation from"))}]) as $q
      | if ($q | length) > 0 then . + {queued: $q} else . end' "$WD/parsed.json" 2> "$WD/list.err" \
        || { lib_scrub < "$WD/list.err" >&2; echo >&2; lib_die2 "cannot list the Decisions section"; }
    exit 0
    ;;
open-questions)
    # Every question koto lists open and waiting on this session itself (not
    # one it raised, nor one waiting below it), with the entry holding it.
    # Under the test flags the run's session is RS_SESSION, as for the record.
    AT=${RS_SESSION:-$SESSION}
    [ -n "$AT" ] || lib_die2 "no session to read the open questions at"
    koto_read "$WD/open.json" decisions open --at "$AT"
    jq -c -L "$HERE" --arg s "$AT" --slurpfile o "$WD/open.json" 'include "state-schema";
      (.decisions.entries // []) as $es
      | [($o[0].questions // [])[] | select(.addressee.kind == "session" and .addressee.name == $s)]
      | unique_by(.identity) | sort_by((.time | time_key), .identity)
      | map(.identity as $q | ([$es[] | select(d_identity == $q)] | first) as $e
          | {identity: $q, raiser: (.session // null), raised: (.time // null),
             age_minutes: (.time | age_minutes(now)),
             decision: ($e.decision // null), state: ($e.state // null),
             handled: ($e != null and ($e.state == "escalated" or (($e.verdict // "") | IN("hold", "escalate"))))})
      | {questions: ., unhandled: [.[] | select(.handled | not) | .identity]}' "$WD/parsed.json" > "$WD/oq.json" 2> "$WD/oq.err" \
        || { lib_scrub < "$WD/oq.err" >&2; echo >&2; lib_die2 "koto's open questions are not JSON"; }
    cat "$WD/oq.json"
    jq -e '.unhandled == []' "$WD/oq.json" > /dev/null && exit 0
    exit 1
    ;;
read)
    E=$(jq -c --arg n "$ENTRY" '[(.decisions.entries // [])[] | select(.decision == $n)][0] // empty' "$WD/parsed.json")
    [ -n "$E" ] || exit 1
    ID=$(printf '%s' "$E" | jq -r -L "$HERE" 'include "state-schema"; d_identity')
    if [ -n "$ID" ]; then
        koto_read "$WD/content.json" decisions content read "$ID"
        E=$(printf '%s' "$E" | jq -c --slurpfile c "$WD/content.json" '. + {content: $c[0]}') || lib_die2 "koto's content for $ID is not JSON"
    fi
    printf '%s\n' "$E"
    exit 0
    ;;
esac

# --- the write modes -----------------------------------------------------------------

refuse() { echo "$PROG: refused: $*" >&2; exit 65; }
lib_write_guard
lib_run_stamp
NOW=$(date -u +%Y-%m-%dT%H:%MZ)

# A single item never holds a line break: state-schema.jq's line break also
# separates Options and Evidence lines, so one could forge an item.
for v in "$Q" "$TEXT" "$OUTC" "$REASON" "$REC" "$CTX" "$PROB" "$GROUNDS" "$FINAL" "$SRC" "$ATTEMPT" "$QID" ${OPTS[@]+"${OPTS[@]}"}; do
    case "$v" in *$'\n'*|*$'\r'*) refuse "an item holds a line break" ;; esac
done
# A source or a final decider is written in front of a stamp, and stamps are
# read by position, so a bracket in one could forge the stamp that follows.
for v in "$SRC" "$FINAL"; do
    case "$v" in *'['*|*']'*) refuse "a source or a final decider holds a bracket" ;; esac
done

# The state the session is in binds the mode.
CUR=$(bash "$HERE/coord-log.sh" current --session "$SESSION") || lib_die2 "cannot read the session's current state"
CUR_STATE=${CUR%% *} CUR_SEQ=${CUR##* }
case "$MODE" in
    carry) WANT=decision_carry ;; open) WANT=decision_raise ;; open-from-report) WANT=decision_open ;;
    take) WANT=decision_take ;; settle|escalate|hold|identity) WANT=decision_verdict ;;
    evidence) WANT=decision_evidence ;; answer) WANT=decision_answer ;;
    sent) WANT="escalate_send decision_withdraw_send decision_reply_send decision_redirect_send" ;;
esac
case " $WANT " in *" $CUR_STATE "*) ;; *) refuse "--$MODE runs in ${WANT// / or }, and the session is in $CUR_STATE" ;; esac

TARGET_RT=$(bash "$HERE/coord-log.sh" vars --session "$SESSION" | jq -r '.REPORTS_TO // ""') || lib_die2 "cannot read the session's variables"
if [ -n "$TARGET_RT" ]; then TARGET="coordinator $TARGET_RT"; else TARGET="a person"; fi

# routed: decision_next's sealed capture from its latest visit, whole.
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

# The rules, as jq definitions over the Decisions section. $now, $run and $t (the
# run's target) are bound on every call.
LIB='include "state-schema";
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
# A queued escalation held by no question identity is an old-style one, queued
# before entries were held by identities (a run already under way): it keeps
# its verdict and is released as it was then. When no entry is escalated, the
# lowest such entry is escalated, or has its verdict cleared when
# escalation_problems no longer passes for it. Queued entries held by an
# identity are released by release_queued, after the program, since a release
# is a koto write (shirabe question pass-up).
def release:
  if any(.entries[]; .state == "escalated") then .
  else ([.entries[] | select(.state == "coordinator-verdict" and .verdict == "escalate" and d_identity == "") | .decision | tonumber] | min) as $q
    | if $q == null then .
      else .entries |= map(if .decision == ($q | tostring) then
          (if (escalation_problems($t) | length) == 0 then escalate_now else .verdict = "" end) else . end) end
  end;
def stamped($kind; $seq): any(d_section_stamps[]; .run == $run and .kind == $kind and .seq == $seq);
def stamped_report($seq): any(d_section_stamps[]; .run == $run and .kind == "report" and (.seq | split(".")[0]) == $seq);
# A routed entry missing from the live record (edited by hand since the route)
# is a refusal, never an empty result: an empty program output would be written
# as no section at all.
def entry($n): first(.entries[] | select(.decision == $n)) // error("the record has no entry \($n)");
# Compaction keeps every Evidence line stamped by this run: the replay guard
# (stamped) and the unrecorded-write rules of decision-next.sh read them for as
# long as the run lasts. A later run compacts them away.
def compact_except($n):
  .entries |= map(if .decision == $n then .
    else . as $e | compact_settled
      | if .state == "settled" and ($e.owed // "") == "" then
          ([($e.evidence // "") | split("\n")[] | select(length > 0)
            | select(test("^[^ ]+ [^\\[]+ \\[" + $run + " [a-z]+ [0-9.]+\\]: ")
                     or test("^[^ ]+ [^\\[]+ \\[[0-9]{8}T[0-9]{6}Z redirect [0-9]+\\]: "))]) as $keep
          | .evidence = ($keep | join("\n"))
        else . end
    end);'

SEC() { jq -c '.decisions // {next: 1, entries: []}' "$WD/parsed.json"; }
# change <program over the section> [jq args]: the new section, or a refusal
# (a jq error() is the refusal's reason).
change() {
    local p=$1; shift
    SEC | jq -c -L "$HERE" --arg now "$NOW" --arg run "$RUN" --arg t "$TARGET" "$@" "$LIB $p" > "$WD/section.json" 2> "$WD/jq.err" \
        || refuse "$(sed -n 's/^jq: error ([^)]*): //p' "$WD/jq.err" | head -1)"
    # The backstop for a program that selected nothing: never write an empty section.
    jq -e 'type == "object" and (.entries | type) == "array"' "$WD/section.json" > /dev/null 2>&1 \
        || refuse "the write produced no Decisions section"
}
# The most entries escalated to one target at once.
MAX_ESCALATED=4
# ESC_N and ESC_AID: the entry --escalate escalates and the attempt it named,
# which a release of that entry passes up with.
ESC_N= ESC_AID=
# passup <n> <identity> <ground>: passes the question up to the run's target
# with shirabe question pass-up. 0 passed up (or koto already shows this
# session's pass-up of it); 1 not passed up, with the reason on stderr.
passup() {
    local n=$1 id=$2 g=$3 aid= need rc
    local args
    history_of "$id"
    if jq -e --arg s "$SESSION" 'any((.entries // [])[]; .entry == "pass-up" and .session == $s)' "$WD/history.json" > /dev/null; then
        return 0
    fi
    if [ "$(jq -r '.open' "$WD/history.json")" != true ]; then
        echo "$PROG: question $id (entry $n) is closed in koto; it settles from koto's record, not by a pass-up" >&2
        return 1
    fi
    need=$(jq -r '.question.need // "decision"' "$WD/history.json")
    args=(--ground "$g")
    if [ "$need" = decision ]; then
        if [ "$n" = "$ESC_N" ]; then aid=$ESC_AID; else aid=$(attempt_of "$id" ""); fi
        if [ -z "$aid" ]; then
            echo "$PROG: entry $n (question $id) has no undecided attempt of $SESSION's behind it, so it isn't passed up; record one here with: $(attempt_line "$id")" >&2
            return 1
        fi
        args+=(--attempt "$aid")
    fi
    [ "$TARGET" = "a person" ] && args+=(--to person:owner)
    "$SHIRABE" question pass-up "$id" --in "$SESSION" "${args[@]}" > "$WD/passup.json" 2> "$WD/passup.err"
    rc=$?
    [ "$rc" = 0 ] && return 0
    echo "$PROG: shirabe question pass-up of question $id (entry $n) exited $rc: $(lib_scrub < "$WD/passup.err" | head -3)" >&2
    return 1
}
# release_queued: in $WD/section.json, the queued escalations held by an
# identity, into the free places for the run's target (at most MAX_ESCALATED
# escalated at once): most waiting work items first, then the oldest raise,
# then the identity, as shirabe question pending reports them. Each is passed
# up before it reads escalated. A release that fails leaves the entry queued,
# except the one --escalate named, whose failure refuses the write.
release_queued() {
    local free n id g ok
    free=$(jq -r --arg t "$TARGET" "$MAX_ESCALATED - ([.entries[] | select(.state == \"escalated\" and .target == \$t)] | length)" "$WD/section.json") \
        || lib_die2 "cannot count the escalated entries"
    [ "$free" -gt 0 ] || return 0
    jq -c -L "$HERE" 'include "state-schema"; [.entries[] | select(.state == "coordinator-verdict" and .verdict == "escalate")
        | select(d_identity != "") | {n: .decision, id: d_identity, g: (.grounds // "")}]' "$WD/section.json" > "$WD/queued.json" \
        || lib_die2 "cannot read the queued escalations"
    if [ "$(jq 'length' "$WD/queued.json")" -gt "$free" ]; then
        # Only a choice needs the order: shirabe question pending's waiting
        # count and raise time for each identity it lists. One it doesn't
        # list counts no waiting work items and sorts last. Raise times are
        # compared as instants (state-schema.jq's time_key), as shirabe
        # orders them, never as strings.
        "$SHIRABE" question pending --in "$SESSION" > "$WD/pending.json" 2> "$WD/pending.err" \
            || { lib_scrub < "$WD/pending.err" >&2; echo >&2; lib_die2 "cannot read shirabe question pending"; }
        jq -c -L "$HERE" --slurpfile p "$WD/pending.json" 'include "state-schema"; ($p[0].questions // []) as $pq
          | map(. as $c | ([$pq[] | select(.identity == $c.id)] | first // {}) as $r
                | . + {w: ($r.waiting // 0), r: ($r.raised // null | time_key)})
          | sort_by(-.w, .r, .id)' "$WD/queued.json" > "$WD/queued.sorted" || lib_die2 "cannot order the queued escalations"
        mv "$WD/queued.sorted" "$WD/queued.json"
    fi
    jq -r '.[] | [.n, .id, .g] | @tsv' "$WD/queued.json" > "$WD/queued.tsv" || lib_die2 "cannot read the queued escalations"
    while IFS=$'\t' read -r n id g; do
        [ "$free" -gt 0 ] || break
        ok=0
        passup "$n" "$id" "$g" || ok=1
        if [ "$ok" = 0 ]; then
            jq -c -L "$HERE" --arg now "$NOW" --arg run "$RUN" --arg t "$TARGET" --arg n "$n" \
                "$LIB .entries |= map(if .decision == \$n then escalate_now else . end)" "$WD/section.json" > "$WD/released.json" \
                || lib_die2 "cannot release entry $n"
            mv "$WD/released.json" "$WD/section.json"
            free=$((free - 1))
        elif [ "$n" = "$ESC_N" ]; then
            refuse "entry $n is not escalated: its pass-up didn't land"
        fi
    done < "$WD/queued.tsv"
}
# write: the section into the record, through the write core. The state keeps
# the written time of the version read, and its file stays in this script's
# private directory, readable by its owner only.
write() {
    release_queued
    jq --slurpfile d "$WD/section.json" '.decisions = $d[0]' "$WD/parsed.json" > "$WD/next.json" || lib_die2 "jq failed"
    chmod 600 "$WD/next.json" || lib_die2 "cannot make the state file private"
    STATE_FILE="$WD/next.json"
    . "$HERE/state-write-core.sh"
    # The one script that may change the section.
    DECISIONS_WRITER=1
    core_write
    exit 0
}
has_entry() { # has_entry <n> <jq test over the entry>
    SEC | jq -e --arg n "$1" '[.entries[] | select(.decision == $n) | '"$2"'] | any' >/dev/null
}
is_archived() { SEC | jq -e --argjson n "$1" '(.archived // []) | index($n) != null' >/dev/null; }
# reserved_ground <n> [<identity>]: the reserved ground entry n carries, ""
# for none: its Grounds cell, else, for an entry held by a question, the
# ground of the latest pass-up by another session in koto's history of it
# (pass-up records `ground: <ground>` as the readdress's reason). With an
# identity, $WD/history.json must hold that question's history already.
reserved_ground() {
    local g
    g=$(SEC | jq -r -L "$HERE" --arg n "$1" 'include "state-schema";
        [.entries[] | select(.decision == $n) | (.grounds // "") | split(", ")[] | select(IN(d_reserved_grounds[]))] | first // ""') \
        || lib_die2 "cannot read entry $1's grounds"
    if [ -z "$g" ] && [ -n "${2:-}" ]; then
        g=$(jq -r -L "$HERE" --arg s "$SESSION" 'include "state-schema";
            [(.entries // [])[] | select(.entry == "pass-up" and (.session // "") != $s)] | last // {}
            | [((.reason // "") | capture("^ground: (?<g>[a-z-]+)") | .g) | select(IN(d_reserved_grounds[]))] | first // ""' "$WD/history.json") \
            || lib_die2 "cannot read question $2's history"
    fi
    printf '%s' "$g"
}
# koto_facts <identity>: koto's answer to a question it shows closed, into
# KO_AS, KO_AID (the answer's session and id), KO_O (its text, or
# `withdrawn`), KO_WHY (its reason) and KO_BY (its decider, as the record
# writes it), and KO_BYS (the deciding session, "" when a person decided).
# Reads koto decisions history into $WD/history.json, then show.
koto_facts() {
    local id=$1
    history_of "$id"
    [ "$(jq -r '.open' "$WD/history.json")" = false ] || return 1
    KO_AS=$(jq -r '.answer.session // ""' "$WD/history.json")
    KO_AID=$(jq -r '.answer.id // ""' "$WD/history.json")
    local outk
    outk=$(jq -r '.answer.outcome // ""' "$WD/history.json")
    [ -n "$KO_AS" ] && [ -n "$KO_AID" ] || lib_die2 "koto shows question $id closed with no answer"
    koto_read "$WD/show.json" decisions show "$KO_AS" "$KO_AID"
    if [ "$outk" = withdrawn ]; then KO_O=withdrawn; else KO_O=$(jq -r '.answer.text // ""' "$WD/history.json"); fi
    [ -n "$KO_O" ] || lib_die2 "koto's answer to question $id has no text"
    KO_WHY=$(jq -r '.decision.reason // "" | if . == "" then "none given in koto" else . end' "$WD/show.json")
    KO_BY=$(jq -r '.decision.decider // {} | (if .kind == "session" then "session \(.session.value // .session // "")"
          elif .kind == "person" then "person \(.handle.value // .handle // .person.value // .person // "")"
          else (.kind // "unknown") end) | gsub("[\\[\\]]"; "") | gsub("@"; "&#64;")' "$WD/show.json")
    KO_BYS=$(jq -r '.decision.decider // {} | if .kind == "session" then (.session.value // .session // "") else "" end' "$WD/show.json")
    case "$KO_O$KO_WHY" in *$'\n'*|*$'\r'*) KO_O=$(printf '%s' "$KO_O" | tr '\r\n' '  '); KO_WHY=$(printf '%s' "$KO_WHY" | tr '\r\n' '  ') ;; esac
    return 0
}
# refuse_reserved <n> <identity or ""> <what>: refused when entry n carries a
# reserved ground, which keeps it for the owner: the coordinator passes it up.
refuse_reserved() {
    local g
    g=$(reserved_ground "$1" "$2") || exit 2
    [ -z "$g" ] || refuse "entry $1 carries the reserved ground $g, so the coordinator doesn't $3 it: pass it up (--escalate --grounds $g)"
}
# restore <n>...: the archived entries back into the section this write starts
# from, each from the latest unedited `decisions` entry holding its row.
restore() {
    bash "$HERE/state-entry.sh" --session "$SESSION" --list > "$WD/entries.json" 2> "$WD/ra.err" \
        || { lib_scrub < "$WD/ra.err" >&2; echo >&2; lib_die2 "cannot read the record's entries"; }
    # jq goes on reading options after --args, so the -- keeps a dash-leading
    # id an id, refused as a bad one, instead of taken as jq's own option.
    jq -c -L "$HERE" --argjson ids "$(jq -nc '$ARGS.positional | map(tonumber)' --args -- "$@")" --slurpfile es "$WD/entries.json" 'include "state-schema";
        ([$es[0][] | select(.kind == "decisions" and (.edited | not))] | reverse) as $arch
        | reduce $ids[] as $n (.;
            (first($arch[] | .text | d_archive_rows[] | select(.decision == ($n | tostring)))
              // error("entry \($n) is archived, and no decisions entry on the record holds it")) as $e
            | .decisions.entries += [$e] | .decisions.archived -= [$n])
        | .decisions.entries |= sort_by(.decision | tonumber)
        | if .decisions.archived == [] then del(.decisions.archived) else . end
        # The row it comes back with carries its stamps, so the kept ones go.
        | if .decisions.kept == null then .
          else .decisions.kept.stamps |= map(select(.decision as $k | $ids | index($k) | not))
            | if .decisions.kept.stamps == [] then del(.decisions.kept) else . end end' "$WD/parsed.json" > "$WD/restored.json" 2> "$WD/jq.err" \
        || refuse "$(sed -n 's/^jq: error ([^)]*): //p' "$WD/jq.err" | head -1)"
    mv "$WD/restored.json" "$WD/parsed.json"
}

case "$MODE" in
carry)
    [ "$SCOPE" = discipline ] || refuse "only a discipline rotation carries its predecessor's decisions"
    lib_dispatched && refuse "the run has dispatched; a carry comes before the first dispatch"
    rs_rotation "${RS_SESSION:-$SESSION}" "$WD/rotation.json"
    case $? in 0) ;; 1) refuse "this rotation holds no record/rotation, so it names no predecessor" ;; *) lib_die2 "cannot read record/rotation" ;; esac
    PRED=$(jq -r '.predecessor // ""' "$WD/rotation.json")
    [ -n "$PRED" ] || refuse "this rotation names no predecessor"
    rs_session_state "$PRED" "$WD/pred.json"
    case $? in
        0) ;;
        4|12) refuse "$PRED holds no readable record: $(lib_scrub < "$WD/pred.json.err" | head -1)" ;;
        *) lib_die2 "cannot read $PRED's record: $(lib_scrub < "$WD/pred.json.err" | head -1)" ;;
    esac
    change '. as $s | ($h[0].decisions // {next: 1, entries: []}) as $hd
      | ([$hd.entries[] | select(.state != "settled") | select(.decision as $d | all($s.entries[]; .decision != $d))]) as $add
      | if ($add | length) == 0 and $hd.next <= $s.next then error("every entry of the predecessor is already here") else . end
      | .entries += $add | .entries |= sort_by(.decision | tonumber) | .next = ([.next, $hd.next] | max)' \
        --slurpfile h "$WD/pred.json"
    write ;;
open)
    [ -n "$Q" ] && [ ${#OPTS[@]} -gt 0 ] || refuse "an entry needs a question and its options"
    SRC=${SRC:-self}
    case "$SRC" in self|dispatcher) ;; *) refuse "--source is self or dispatcher" ;; esac
    # The -- ends jq's options, so an option such as -r or --flag=value is
    # stored as given, not read as one of jq's.
    OJ=$(jq -nc '$ARGS.positional | join("\n")' --args -- "${OPTS[@]}")
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
    CITED=$(jq -r '[.[] | select(.kind != "withdrawal") | .cite // empty | tostring | select(test("^[1-9][0-9]*$"))] | unique | .[]' "$WD/questions.json")
    BACK=()
    for c in $CITED; do has_entry "$c" true || ! is_archived "$c" || BACK+=("$c"); done
    [ ${#BACK[@]} -eq 0 ] || restore "${BACK[@]}"
    change '($q[0]) as $items | ($w[0]) as $words
      | if stamped_report($seq) then error("this run already wrote report \($seq)") else . end
      # An item held by a question identity is worded by koto alone.
      | ([$items[] | select((.identity // "") != "") | select($words[(.index | tostring)] != null)] | first) as $worded
      | if $worded != null then error("item \($worded.index) is question \($worded.identity), worded by its content in koto; a wording for it is refused") else . end
      | ([$items[] | select(.kind != "withdrawal" and (.identity // "") == "") | .index | tostring]) as $need
      | if ($words | keys | sort) != ($need | sort) then
          error("the wording covers items [\($words | keys | sort | join(","))], and the list needs [\($need | sort | join(","))], each once") else . end
      # No wording may hold a line break: it could forge an Evidence line.
      | if any($words[] | (.question // ""), (.options // [])[]; test("[\\n\\r]")) then error("a wording holds a line break") else . end
      | reduce $items[] as $i (.;
          "\($run) report \($seq).\($i.index)" as $st
          | ($words[($i.index | tostring)] // {}) as $wd
          | if $i.kind == "withdrawal" then
              # A withdrawal naming a question identity reaches the entry held
              # by it; any other, the entry opened from its source.
              (($i.identity // "") as $wid | if $wid != "" then [.entries[] | select(d_identity == $wid)] else [.entries[] | select(.source | startswith("\($i.source) ["))] end) as $hits
              | if ($hits | length) == 0 then error("item \($i.index) withdraws an entry the record lacks") else . end
              | .entries |= map(if (if ($i.identity // "") != "" then d_identity == $i.identity else (.source | startswith("\($i.source) [")) end)
                  then evidence($i.source; $st; "withdrawn: decision \($i.n) round \($i.round)") else . end)
            elif ($i.identity // "") != "" then
              # One entry per identity: a re-report, or the same question
              # arriving twice, is a stamped line on the entry it already has.
              if any(.entries[]; d_identity == $i.identity) then
                .entries |= map(if d_identity == $i.identity then add_ev(ev_line("question \($i.identity)"; $st; "reported again")) else . end)
              else
                ((($i.text // "") | if blank then $i.identity else . end)) as $qq
                | (($i.options // []) | join("\n")) as $oo
                | if ($qq + $oo | test("[\\r]")) or ($qq | test("\\n")) then error("item \($i.index): koto'"'"'s question holds a line break") else . end
                | .entries += [{decision: (.next | tostring), round: "0", question: $qq, options: $oo, state: "proposed",
                    source: "question \($i.identity) [\($st)]", updated: $now}]
                | .next += 1
              end
            elif ($i.cite // null) != null then
              if any(.entries[]; .decision == ($i.cite | tostring)) | not then error("item \($i.index) cites an entry the record lacks") else . end
              | .entries |= map(if .decision == ($i.cite | tostring) then
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
      | release | compact_except("")' \
        --slurpfile q "$WD/questions.json" --slurpfile w "$TEXTF" --arg seq "$RSEQ"
    write ;;
take)
    N=$(routed_entry take) || exit $?
    change 'entry($n).state as $s | if $s != "proposed" then error("entry \($n) is \($s), not proposed") else . end
      | .entries |= map(if .decision == $n then .state = "coordinator-verdict" | .updated = $now else . end) | compact_except($n)' --arg n "$N"
    write ;;
settle|escalate|hold|identity)
    N=$(routed_entry verdict) || exit $?
    # One verdict per entry: a recorded one (queued, held or any other) is
    # cleared only by evidence, which brings the entry back to a fresh visit.
    has_entry "$N" '.state == "coordinator-verdict" and ((.verdict // "") == "")' || refuse "entry $N isn't awaiting a verdict"
    case "$MODE" in
    settle)
        ID=$(SEC | jq -r -L "$HERE" --arg n "$N" 'include "state-schema"; .entries[] | select(.decision == $n) | d_identity')
        if [ -n "$ID" ]; then
            # Held by a question: settled only from koto's record of it. While
            # koto shows it open, settling here would leave the question open
            # in koto, the worker waiting on it, and nothing routing it again.
            if ! koto_facts "$ID"; then
                refuse_reserved "$N" "$ID" settle
                refuse "koto shows question $ID open, so entry $N settles only from koto's answer: answer it there (shirabe question settle $ID --in $SESSION --chosen <choice> --reason <why>) or pass it up (--escalate)"
            fi
            [ "$KO_O" = withdrawn ] || [ "$KO_BYS" != "$SESSION" ] || refuse_reserved "$N" "$ID" settle
            [ -z "$OUTC" ] || [ "$OUTC" = "$KO_O" ] || refuse "--outcome \`$OUTC\` is not koto's answer to question $ID (\`$KO_O\`)"
            change '.entries |= map(if .decision == $n then settle("\($o); reason: \($why)"; $by) else . end) | release | compact_except($n)' \
                --arg n "$N" --arg o "$KO_O" --arg why "$KO_WHY" --arg by "$KO_BY"
        else
            [ -n "$OUTC" ] && [ -n "$REASON" ] || refuse "a settle needs an outcome and its reason"
            refuse_reserved "$N" "" settle
            change '.entries |= map(if .decision == $n then settle("\($o); reason: \($r)"; "the coordinator") else . end) | release | compact_except($n)' \
                --arg n "$N" --arg o "$OUTC" --arg r "$REASON"
        fi ;;
    identity)
        [[ $QID =~ $RE_IDENTITY ]] || refuse "\`$QID\` is not a question identity (<session id>/<decision id>)"
        ID=$(SEC | jq -r -L "$HERE" --arg n "$N" 'include "state-schema"; .entries[] | select(.decision == $n) | d_identity')
        [ -z "$ID" ] || refuse "entry $N is already held by question $ID"
        SEC | jq -e -L "$HERE" --arg q "$QID" 'include "state-schema"; any(.entries[]; d_identity == $q)' > /dev/null \
            && refuse "another entry is already held by question $QID"
        history_of "$QID"
        [ "$(jq -r '.open' "$WD/history.json")" = true ] || refuse "koto shows question $QID closed"
        RAISER=$(jq -r '.raiser.name // ""' "$WD/history.json")
        [ "$RAISER" = "$SESSION" ] || refuse "question $QID was raised by \`$RAISER\`, not by this session"
        change '.entries |= map(if .decision == $n then
            .source = "question \($q) " + ((.source // "") | capture("(?<s>\\[[^]]*\\])$").s) | .updated = $now else . end)
          | compact_except($n)' --arg n "$N" --arg q "$QID" ;;
    escalate)
        # Only a question identity escalates; its wording is koto's.
        ID=$(SEC | jq -r -L "$HERE" --arg n "$N" 'include "state-schema"; .entries[] | select(.decision == $n) | d_identity')
        [ -n "$ID" ] || refuse "entry $N holds no question identity: raise its question in this session (shirabe question raise --in $SESSION --content <file> --attempt <id>), hold the entry by it (--identity <identity>), then escalate"
        [ -z "$REC$CTX$PROB" ] && [ ${#OPTS[@]} -eq 0 ] \
            || refuse "entry $N is worded by question $ID's content in koto; --recommendation, --context, --problem and --option don't apply"
        case "$GROUNDS" in
            contradicts-answer|changes-scope|outward-facing|reserved-step|outside-scope) ;;
            *) refuse "--grounds is one of contradicts-answer, changes-scope, outward-facing, reserved-step, outside-scope" ;;
        esac
        [ "$GROUNDS" = outside-scope ] && [ "$TARGET" = "a person" ] && refuse "outside-scope is passed up to a session, never to a person"
        history_of "$ID"
        [ "$(jq -r '.open' "$WD/history.json")" = true ] || refuse "koto shows question $ID closed; it settles from koto's record"
        NEED=$(jq -r '.question.need // "decision"' "$WD/history.json")
        if [ "$NEED" = decision ]; then
            [ -n "$ATTEMPT" ] || refuse "escalating question $ID needs --attempt: an undecided attempt of $SESSION's at it, which $(attempt_line "$ID") records"
            A=$ATTEMPT
            case "$A" in *:*) [ "${A%%:*}" = "$SESSION" ] || refuse "attempt $ATTEMPT is not $SESSION's"; A=${A#*:} ;; esac
            ESC_AID=$(attempt_of "$ID" "$A")
            [ -n "$ESC_AID" ] || refuse "attempt $ATTEMPT is not an undecided attempt of $SESSION's tied to question $ID (koto decisions attempts --in=$SESSION --question $ID); record one here with: $(attempt_line "$ID")"
        else
            [ -z "$ATTEMPT" ] || refuse "question $ID is a need; it is passed up with no attempt"
        fi
        ESC_N=$N
        # Queued here; write's release_queued passes it up and escalates it
        # when a place is free for the target.
        change '.entries |= map(if .decision == $n then .verdict = "escalate" | .reason = $why
              | .grounds = $g | .target = $t | .updated = $now else . end)
          | (entry($n) | escalation_problems($t)) as $bad
          | if ($bad | length) > 0 then error("the escalation fails: \($bad | join("; "))") else . end
          | compact_except($n)' \
            --arg n "$N" --arg why "$REASON" --arg g "$GROUNDS" ;;
    hold)
        [ -n "$REASON" ] || refuse "a hold needs what the verdict waits on"
        change 'if stamped("hold"; $seq) then error("this visit already held a verdict") else . end
          | .entries |= map(if .decision == $n then .verdict = "hold" | .reason = $r
              | add_ev(ev_line("the coordinator"; "\($run) hold \($seq)"; "holding: \($r)")) | .updated = $now else . end) | compact_except($n)' \
            --arg n "$N" --arg r "$REASON" --arg seq "$CUR_SEQ" ;;
    esac
    write ;;
evidence|answer)
    # The arrival is the latest one of its kind before this visit, whether the
    # run came here from it or from decision_next retrying a write that didn't
    # land: an evidence event at wait, or an answer, either a wait answer event
    # (the message route) or escalate_send's `answered` (the question-tool
    # route), whichever is later. Its log sequence is the write's stamp.
    arrival() { # arrival <state> <field=value>: the latest such evidence, {} when none
        local e
        e=$(bash "$HERE/coord-log.sh" evidence --session "$SESSION" --state "$1" --where "$2" --before "$CUR_SEQ")
        case $? in 0) printf '%s' "$e" ;; 1) printf '{}' ;; *) lib_die2 "cannot read the $1 evidence" ;; esac
    }
    if [ "$MODE" = evidence ]; then
        EV=$(arrival wait event=evidence)
    else
        EV=$(jq -nc --argjson a "$(arrival wait event=answer)" --argjson b "$(arrival escalate_send sent=answered)" \
            '[$a, $b] | map(select(.seq != null)) | max_by(.seq) // {}')
    fi
    # koto_settle <n> <identity> <stamp seq>: entry n settled from koto's record
    # of its closed question: the answer's text (or `withdrawn`), the reason and
    # the decider koto decisions show gives for it. Writes and exits.
    koto_settle() {
        local n=$1 id=$2 seq=$3
        koto_facts "$id" || refuse "koto shows question $id open; entry $n settles only from koto's answer"
        [ -z "$OUTC" ] || [ "$OUTC" = "$KO_O" ] || refuse "--outcome \`$OUTC\` is not koto's answer to question $id (\`$KO_O\`)"
        # This session's own answer to a question a reserved ground keeps for
        # the owner is refused; a withdrawal, or another's answer, settles it.
        [ "$KO_O" = withdrawn ] || [ "$KO_BYS" != "$SESSION" ] || refuse_reserved "$n" "$id" answer
        change 'if stamped("wait"; $seq) then error("this answer is already recorded") else . end
          | .entries |= map(if .decision == $n then
              add_ev(ev_line($by; "\($run) wait \($seq)"; "koto answer \($as):\($aid): \($o)"))
              | (if .state == "settled" then . else settle("\($o); reason: \($why)"; $by) end) else . end)
          | release | compact_except($n)' \
            --arg n "$n" --arg o "$KO_O" --arg why "$KO_WHY" --arg by "$KO_BY" --arg seq "$seq" --arg as "$KO_AS" --arg aid "$KO_AID"
        write
    }
    # decision_next routed `unrecorded-answer <n> koto`: koto shows entry n's
    # question closed. It counts when that visit came after the latest arrival.
    if [ "$MODE" = answer ]; then
        KC=$(bash "$HERE/coord-log.sh" capture --session "$SESSION" --name DECISION_NEXT --state decision_next)
        case $? in 0|1) ;; *) lib_die2 "cannot read the decision_next capture" ;; esac
        set -f; set -- $KC; set +f
        if [ "${1-}" = unrecorded-answer ] && [ "${3-}" = koto ] && [[ ${2-} =~ ^[1-9][0-9]*$ ]]; then
            DN=$(bash "$HERE/coord-log.sh" entry --session "$SESSION" --state decision_next --before "$CUR_SEQ")
            case $? in 0|1) ;; *) lib_die2 "cannot read the session log" ;; esac
            DN=${DN%% *}
            if [ "${DN:-0}" -gt "$(printf '%s' "$EV" | jq -r '.seq // 0')" ]; then
                ID=$(SEC | jq -r -L "$HERE" --arg n "$2" 'include "state-schema"; .entries[] | select(.decision == $n) | d_identity')
                [ -n "$ID" ] || refuse "entry $2 holds no question identity"
                koto_settle "$2" "$ID" "$CUR_SEQ"
            fi
        fi
    fi
    [ "$(printf '%s' "$EV" | jq -r '.seq // ""')" != "" ] || refuse "no $MODE arrived before this visit"
    N=$(printf '%s' "$EV" | jq -r '.fields.decision // ""')
    RND=$(printf '%s' "$EV" | jq -r '.fields.round // ""')
    WSEQ=$(printf '%s' "$EV" | jq -r '.seq')
    [[ $N =~ ^[1-9][0-9]*$ ]] || refuse "the $MODE names no decision"
    has_entry "$N" 'true' || ! is_archived "$N" || restore "$N"
    has_entry "$N" 'true' || refuse "the record has no entry $N"
    ID=
    [ "$MODE" = answer ] && ID=$(SEC | jq -r -L "$HERE" --arg n "$N" 'include "state-schema"; .entries[] | select(.decision == $n) | d_identity')
    if [ -n "$ID" ]; then
        # An entry held by a question settles only from koto. An answer koto
        # doesn't hold yet (a typed reply, any route) is recorded as arrived
        # and changes nothing else: an escalated entry stays escalated.
        history_of "$ID"
        [ "$(jq -r '.open' "$WD/history.json")" = false ] && koto_settle "$N" "$ID" "$WSEQ"
        change 'if stamped("wait"; $seq) then error("this answer is already recorded") else . end
          | .entries |= map(if .decision == $n then
              add_ev(ev_line($t; "\($run) wait \($seq)"; "an answer for round \($r) arrived outside koto; the entry settles from koto'"'"'s record")) | .updated = $now else . end)
          | compact_except($n)' --arg n "$N" --arg r "${RND:-0}" --arg seq "$WSEQ"
        write
    fi
    if [ "$MODE" = answer ]; then
        [[ $RND =~ ^[1-9][0-9]*$ ]] || refuse "an answer names its round"
        [ -n "$OUTC" ] || refuse "an answer needs an outcome"
        BY=$TARGET
        [ -n "$FINAL" ] && [ "$FINAL" != "the coordinator" ] && BY="$TARGET (final: $FINAL)"
        if has_entry "$N" ".state == \"escalated\" and .round == \"$RND\""; then
            if [ -z "$REASON" ]; then
                REASON=$(SEC | jq -r -L "$HERE" --arg n "$N" --arg o "$OUTC" 'include "state-schema";
                    .entries[] | select(.decision == $n) | [d_options[] | select(.label == $o) | .explanation][0] // ""')
                [ -n "$REASON" ] || refuse "an answer that isn't one of the options needs --reason"
            fi
            change 'if stamped("wait"; $seq) then error("this answer is already recorded") else . end
              | .entries |= map(if .decision == $n then add_ev(ev_line($by; "\($run) wait \($seq)"; "answer for round \($r): \($o)"))
                  | settle("\($o); reason: \($why)"; $by) else . end) | release | compact_except($n)' \
                --arg n "$N" --arg r "$RND" --arg o "$OUTC" --arg why "$REASON" --arg by "$BY" --arg seq "$WSEQ"
            write
        fi
        # The same answer again (the round, outcome and decider that settled
        # the entry) changes nothing about the entry: it adds only its own
        # stamped line, so decision-next.sh sees this arrival recorded.
        if has_entry "$N" ".state == \"settled\" and .round == \"$RND\"" && SEC | jq -e --arg n "$N" --arg o "$OUTC" --arg by "$BY" \
                '.entries[] | select(.decision == $n) | (.outcome | startswith("\($o); reason: ")) and .decided_by == $by' >/dev/null; then
            change 'if stamped("wait"; $seq) then error("this answer is already recorded") else . end
              | .entries |= map(if .decision == $n then add_ev(ev_line($by; "\($run) wait \($seq)"; "answer for round \($r) again: \($o)")) else . end)
              | compact_except($n)' --arg n "$N" --arg r "$RND" --arg o "$OUTC" --arg by "$BY" --arg seq "$WSEQ"
            write
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
    # Unattended, no one is there to answer a question tool.
    [ "$ROUTE" = tool ] && unattended && refuse "the session is unattended: no question tool is asked; mark the escalation --route record"
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
            case "$ROUTE" in tool|message|record) ;; *) refuse "an escalation to a person records its route: --route tool, message or record" ;; esac
        else
            case "$ROUTE" in ''|message) ROUTE=message ;; *) refuse "an escalation to a coordinator is sent as a message" ;; esac
        fi
        # Every entry the render listed (`entries:<n>@<round>.<n>@<round>`),
        # or the one it names when it lists none.
        EL=$(printf '%s\n' "$CAP" | tr ' ' '\n' | sed -n 's/^entries://p')
        [ -n "$EL" ] || EL="$N@$R"
        [[ $EL =~ ^[1-9][0-9]*@[0-9]+(\.[1-9][0-9]*@[0-9]+)*$ ]] || refuse "the render's entry list is malformed"
        ELJ=$(printf '%s' "$EL" | jq -Rc 'split(".") | map(split("@") | {n: .[0], r: .[1]})')
        if [ "$ROUTE" = record ]; then TXT="waiting on the record"; else TXT="asked by $ROUTE"; fi
        change 'if stamped("ask"; $seq) then error("this visit already marked a message sent") else . end
          | reduce $el[] as $x (.;
              entry($x.n) as $e | if $e.owed != "escalation" or $e.round != $x.r then error("entry \($x.n) owes no escalation for round \($x.r)") else . end
              | .entries |= map(if .decision == $x.n then .owed = "" | .asked = $now
                  | (if $t == "a person" then add_ev(ev_line("the coordinator"; "\($run) ask \($seq)"; $txt)) else . end)
                  | .updated = $now else . end))
          | compact_except($n)' \
            --arg n "$N" --argjson el "$ELJ" --arg txt "$TXT" --arg seq "$CUR_SEQ" ;;
    withdrawal|reply)
        change 'entry($n) as $e | if $e.owed != $k or $e.round != $r then error("entry \($n) owes no \($k) for round \($r)") else . end
          | .entries |= map(if .decision == $n then .owed = "" | .updated = $now else . end) | compact_except($n)' \
            --arg n "$N" --arg k "$K" --arg r "$R" ;;
    redirect)
        [[ $RSEQ =~ ^[1-9][0-9]*$ ]] || refuse "the redirect's render names no report"
        change 'entry($n) as $e | if stamped("redirect"; $rs) then error("report \($rs) has had its redirect") else . end
          | .entries |= map(if .decision == $n then add_ev(ev_line("the coordinator"; "\($run) redirect \($rs)"; "redirect sent")) | .updated = $now else . end)
          | compact_except($n)' --arg n "$N" --arg rs "$RSEQ" ;;
    esac
    write ;;
esac
