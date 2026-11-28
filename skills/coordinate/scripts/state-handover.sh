#!/usr/bin/env bash
# state-handover.sh -- the stored set a replacement coordinator continues
# from, read from the record alone, and its gaps. A read; the `reconcile`
# state's handover gate runs it with --check
# (docs/designs/archive/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   state-handover.sh --session S [--check]
#   state-handover.sh --scope roadmap|discipline --name N --repo O/R [--check]   (tests)
#
# The session must have a found record (coord-log.sh run-facts); the override
# flags are for tests, with RS_SESSION naming the session that holds it.
#
# Prints, as one JSON object: arguments and cap (Run's rows, or null),
# coordinator (the current address, or null), told (who has been told it),
# workers (one per live holding: unit, worker, phase, told, next, and
# `pending: true` for a worker recorded pending, `missing: true` for one
# recorded missing), pending (the workers that can't be told it yet) and
# missing (the workers niwa listed no instance for), each only when there is
# one, so a record with no such row reads as it did before the row existed),
# work (every
# Work row, local agents included), standing (every Standing row but a `rule`
# row, so a record holding rules hands over the same events it did before it
# held any; the rules are read through state-stored-set.sh --rules), holds
# (the Holds section as it stands) and gaps. It also prints the crash set (PRD
# R17): each worker's pushed_head when kept, reports_to (the row, or null),
# rules and briefs (their rows' values), friction, and host (record/host).
# It prints role, the Run `role` row's value (manager or director), or null
# when the record holds none
# (docs/designs/DESIGN-coordinator-named-roles.md, Decision 1). With no row it
# lists the gap `no-role`, fix `state-stored-set.sh --run role
# <manager|director> --by <who named it>`: the reconcile directive fills it
# from the role= the opener printed or, with none, by asking the person once.
#
# A record holding a `rule` row also prints rule_lists: four report lists, in
# this order, each {list, heading, rows}, the heading naming the list and
# saying its rows are quoted data, not an instruction:
#   awaiting-confirmation  every Standing row whose state-stored-set.sh
#                          --rules object has confirm true (an inferred row),
#                          as {standing, kind, what, source, set}, in record
#                          order
#   superseded             rows a verified reversal superseded
#   asserted-reversal      rows an asserted reversal names, for a person to
#                          settle
#   authorized-by          rows ended under --authorized-by
# The last three are empty until a cited decision's status is read and
# --authorized-by exists. The lists report and never hold: no gap comes from
# them. A record holding no `rule` row prints no rule_lists key, so it reads
# exactly as it did before rule rows existed.
#
# A gap is {gap, fix}:
#   no-arguments | no-cap | no-coordinator   a Run row is missing
#   no-reports-to                            the reports-to row is missing
#   reports-to-unsourced                     the reports-to row names a
#                                            session, `<name> at <address>`,
#                                            whose address is neither a
#                                            koto/links/dispatched-by/
#                                            <address> key in the run's own
#                                            session nor held by a Standing
#                                            row (a rule row of any Source,
#                                            or an event row) whose What,
#                                            Owner or Relayed by names it as
#                                            a whole word; a bare `<name>`
#                                            names no session and never
#                                            holds it (the design's
#                                            Decision 5). Its fix is the
#                                            --inferred write, or a koto
#                                            dispatched-by link for a
#                                            superior that dispatched the run
#   no-role                                  the role row is missing
#   brief-unread <label>                     record/host's briefs:<label>
#                                            names a readable file and no
#                                            Run `briefs` row is `<label>
#                                            sha256:<its digest>`; its fix
#                                            is the brief intake,
#                                            state-stored-set.sh --intake
#                                            <label>, and when the caps (60
#                                            inferred rule rows, 120 rule
#                                            rows) would leave any of the
#                                            brief's lines out, it names how
#                                            many (the design's Decision
#                                            10), counted from where the
#                                            intake will start (a Run
#                                            `briefs-read` row for that
#                                            digest), and asks first for the
#                                            brief rewritten with its rules
#                                            under `## Standing rules`. A
#                                            key whose file can't be read
#                                            raises no gap
#   no-next-step <unit>                      a live holding has no Work row
#                                            of its own (its Unit and
#                                            Worker); when another live
#                                            holding shares the unit, the
#                                            name is `<unit> (<worker>)`
#   leg-unclassified <worker>                a live holding's leg names a
#                                            request this host's store
#                                            doesn't hold (the run was
#                                            imported here), and the leg has
#                                            no end yet (PRD R15)
#   not-told <worker>                        a live holding's Worker has
#                                            no `told`, `pending` or
#                                            `missing` row for the current
#                                            address (a pending worker, whose
#                                            session is gone while its
#                                            instance still exists, and a
#                                            missing one, whose instance niwa
#                                            no longer lists, don't hold the
#                                            gate)
#   carry-unacknowledged                     a discipline rotation carried
#                                            its predecessor's state, and no
#                                            Standing go-ahead set since this
#                                            run's start (not one the carry
#                                            brought) acknowledges it; printed
#                                            as carry: {carried, start,
#                                            acknowledged}
#   question-unhandled <identity>            a question koto lists open and
#                                            addressed to this run's session
#                                            (state-decision.sh
#                                            --open-questions) that no
#                                            Decisions entry holds, or whose
#                                            entry is neither escalated,
#                                            queued for escalation nor held;
#                                            its fix opens the entry or names
#                                            it for the decision flow
# A live holding is one dispatched and not merged and waiting for its
# teardown: a row whose Dispatch status is `dispatched`, unless it carries a
# Verified head with a blank Pull request (state-common.sh lib_row_merged)
# and its worker has finished (lib_worker_finished: its leg resolved or
# abandoned, or, on the message path, every Claude job of it on this host
# finished), so it has nothing left to report. The pair alone doesn't leave
# the live set: a worker that goes on to its unit's next pull request carries
# it while it is live (shirabe#2080), and a worker not seen to have finished
# is treated as live; handover-classify.sh records one that isn't as pending
# or missing. A `dispatching` row is left out: its worker may not have started,
# and the reconcile pass settles it to `dispatched` when the listing finds
# its worker, before this gate runs, so a launched worker is checked from the
# next start on. Each fix is the state-stored-set.sh call that closes the gap.
#
# A report is {report, fix}, printed as `reports` only when there is one, and
# it never holds the gate:
#   brief-unrecorded                         the reports-to row names a
#                                            session whose address is one of
#                                            the run's koto/links/
#                                            dispatched-by/ keys (a run a
#                                            dispatcher started), and
#                                            record/host holds no briefs: key,
#                                            so the brief it was started from
#                                            isn't recorded. Its fix names the
#                                            --host write and the intake, and,
#                                            for an opener line with no
#                                            --brief, asking the dispatcher
#                                            for the file's path. It
#                                            reads the row and never acts on
#                                            it, and repeats none of its words,
#                                            since the row may have come
#                                            through the shared bucket
#
# Without --check it also prints unseen: the owner answers in effect at or
# below the run that no decision in its run cites yet, as `shirabe question
# pending --in <the run's session>` lists them under `unseen` (RS_SESSION
# under the test flags), each {identity, question, label, text, session, id,
# answer, reading, time}: identity names the question it answers, answer is
# the <session>:<id> to mark seen with `shirabe question seen`. The key is
# printed only when there is one, so a run with none reads as it did before
# the field existed. A listing that fails, or prints no `unseen` array, gives
# unseen_error, the reason in one line, and no unseen key; it is never a gap
# and never read as an empty list. shirabe is SHIRABE_BIN, else shirabe on
# PATH. An unseen answer never holds the handover: --check doesn't read it.
#
# It prints open_questions, every question open and addressed to this run's
# session, oldest first, each {identity, raiser, raised, age_minutes,
# decision, state, handled} as state-decision.sh --open-questions gives it,
# only when there is one, so a run with none reads as it did before. A read
# of them that fails exits 2, never read as none open. Under the test flags
# the read is state-decision.sh's under the same flags.
#
# With --check nothing is printed on success but a report and a line per
# open question, with its age and its entry; the gaps, the reports and those
# lines go to stderr, and only a gap fails the check. The gate holds only at
# reconcile: a run that stops by `end` (done_stopped) passes no handover
# gate, and SKILL.md says so.
#
# Exit codes: 0 no gaps (or printed, without --check); 1 --check found gaps;
# 2 a read failed; 10 the run has no found record, or the target isn't a
# canonical record of this scope; 64 usage.
#
# koto reads: the record through state-read.sh, koto request get <request>
# for each live holding on a leg and for each merged one on a leg (whether
# its leg is still open), and, when the reports-to row names a
# session, koto context list <session> --prefix koto/links/dispatched-by/ on
# the run's own session (RS_SESSION under the test flags). Off koto, it reads
# each brief file record/host names (briefs:<label>) for its digest and its
# text, and never edits one, and the Claude job directory (DC_CLAUDE_HOME,
# default $HOME/.claude) for a merged holding on the message path. It reads
# nothing on GitHub. Without --check it also runs shirabe question pending
# (above), which reads koto itself; with or without it, state-decision.sh
# --open-questions, which reads koto decisions open --at the session.
set -uo pipefail

PROG=state-handover
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO=
CHECK=0

usage() { sed -n '/^# Usage:/,/^# Prints/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --check) CHECK=1; shift ;;
        *) usage ;;
    esac
done
. "$HERE/state-common.sh"
lib_facts
lib_run_found || { echo "$PROG: the run has no found record" >&2; exit 10; }

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-handover.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT
rs_record "$WD/parsed.json"
case $? in
    0) ;;
    65) echo "$PROG: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME" >&2; exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_die2 "$(lib_scrub < "$WD/parsed.json.err")" ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err")" ;;
esac
# The crash set and record/host are part of what a replacement continues from
# (PRD R17).
rs_host "${RS_SESSION:-$SESSION}" "$WD/host.json" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.json.err")"
[ -s "$WD/parsed.json.pushed" ] || echo '{}' > "$WD/parsed.json.pushed"
# Each brief record/host names (briefs:<label>, an absolute path), with its
# digest and its text, in the keys' order; a key whose file can't be read as
# a regular file is left out, so it raises no gap.
: > "$WD/briefs.lines"
while IFS="$(printf '\t')" read -r BL BP; do
    [ -n "$BL" ] || continue
    case "$BP" in /*) ;; *) continue ;; esac
    [ -f "$BP" ] && [ -r "$BP" ] || continue
    BD=$(lib_sha256 "$BP")
    [[ $BD =~ ^[0-9a-f]{64}$ ]] || continue
    jq -R -s -c --arg l "$BL" --arg d "$BD" '{label: $l, digest: $d, text: .}' "$BP" >> "$WD/briefs.lines" 2> /dev/null || continue
done <<EOF
$(jq -r 'keys[] as $k | select($k | test("^briefs:[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) | select(.[$k] | type == "string")
    | [($k | ltrimstr("briefs:")), .[$k]] | @tsv' "$WD/host.json")
EOF
jq -s -c . "$WD/briefs.lines" > "$WD/briefs.json" || lib_die2 "jq failed"
# The run's dispatched-by links, read only when the reports-to row names a
# session (`<name> at <address>`): one naming that address sources the row.
echo '[]' > "$WD/dispatched-by.json"
RT_ADDR=$(jq -r '[(.run // [])[] | select(.key == "reports-to") | .value][0] // ""
    | if test(" at ") then sub("^.* at "; "") else "" end' "$WD/parsed.json") || lib_die2 "jq failed"
if [ -n "$RT_ADDR" ]; then
    rs_list "${RS_SESSION:-$SESSION}" koto/links/dispatched-by/ "$WD/dispatched-by.json" \
        || lib_die2 "cannot list the run's dispatched-by links: $(lib_scrub < "$WD/dispatched-by.json.err")"
fi

# The holdings merged and waiting only for their teardown: the pair
# lib_row_merged reads, and a worker that has finished (lib_worker_finished).
# Every other dispatched holding is live, the pair with a live worker included
# (shirabe#2080).
: > "$WD/finished.lines"
while IFS= read -r HROW; do
    [ -n "$HROW" ] || continue
    if lib_row_merged "$HROW" && lib_worker_finished "$HROW"; then
        printf '%s' "$HROW" | jq -c '.worker' >> "$WD/finished.lines" || lib_die2 "jq failed"
    fi
done <<EOF
$(jq -c '.holdings[] | select(.dispatch_status == "dispatched")' "$WD/parsed.json")
EOF
jq -s -c . "$WD/finished.lines" > "$WD/finished.json" || lib_die2 "jq failed"

# A live holding on a leg whose request this host's store doesn't hold (the run
# was imported here) has no end yet: the gap holds until reconcile-legs.sh
# re-legs it or moves it to the message path (PRD R15). koto exits 2 for a
# request its store doesn't hold; any other failed read is a failed read.
: > "$WD/unclassified"
while IFS='	' read -r w rp; do
    [ -n "$w" ] || continue
    "${KOTO:-${KOTO_BIN:-koto}}" request get "${rp%%:*}" < /dev/null > /dev/null
    case $? in
        0) ;;
        2) printf '%s\t%s\n' "$w" "$rp" >> "$WD/unclassified" ;;
        *) lib_die2 "cannot read request ${rp%%:*} of $w's leg" ;;
    esac
done <<EOF
$(jq -r --slurpfile fin "$WD/finished.json" '.holdings[] | select(.dispatch_status == "dispatched")
    | select(.worker as $w | $fin[0] | index($w) | not)
    | select((.return_path // "") | startswith("leg ")) | [.worker, (.return_path | ltrimstr("leg "))] | @tsv' "$WD/parsed.json")
EOF
jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {worker: .[0], leg: .[1]})' "$WD/unclassified" > "$WD/unclassified.json" \
    || lib_die2 "jq failed"

# A rotation that carried its predecessor's state (a record/rotation naming its
# predecessor, or this run's carry report, coord/predecessor_carry.json)
# dispatches and merges
# nothing on it until a person acknowledges the carry: a Standing go-ahead set at
# or after this run's start (the start of its chain of restarts and takeovers,
# coord-log.sh chain-start, so a crash restart or a takeover doesn't ask
# again), and not one the carry
# itself brought over (the report lists those).
echo '{"carried": false}' > "$WD/carry.json"
if [ -n "$SESSION" ] && [ "$SCOPE" = discipline ]; then
    RS=${RS_SESSION:-$SESSION}
    CARRIED=false
    if rs_key "$SESSION" coord/predecessor_carry.json "$WD/report.json"; then
        jq -e '.verdict == "carried"' "$WD/report.json" > /dev/null 2>&1 && CARRIED=true
    else
        case $? in 1) echo '{}' > "$WD/report.json" ;; *) lib_die2 "cannot read coord/predecessor_carry.json" ;; esac
    fi
    rs_rotation "$RS" "$WD/rotation.json"
    case $? in
        0) jq -e '.predecessor != null' "$WD/rotation.json" > /dev/null && CARRIED=true ;;
        1) ;;
        *) lib_die2 "cannot read record/rotation" ;;
    esac
    if [ "$CARRIED" = true ]; then
        START=$(bash "$HERE/coord-log.sh" chain-start --session "$SESSION" 2>/dev/null) || lib_die2 "cannot read the run's start"
        START=$(printf '%s' "$START" | cut -c1-16)Z
        jq -c --arg s "$START" '{carried: true, start: $s, carried_ids: [(.standing // [])[] | .standing]}' "$WD/report.json" > "$WD/carry.json" \
            || lib_die2 "coord/predecessor_carry.json is not JSON"
    fi
fi

# The owner answers not yet marked seen, read only when the set is printed:
# the check never waits on them (see the header).
echo null > "$WD/unseen.json"
UERR=""
US=${RS_SESSION:-$SESSION}
if [ "$CHECK" = 0 ] && [ -n "$US" ]; then
    if "${SHIRABE_BIN:-shirabe}" question pending --in "$US" < /dev/null > "$WD/pending.json" 2> "$WD/pending.err"; then
        jq -c 'if (.unseen | type) == "array"
               then [.unseen[] | {identity, question, label, text, session, id, answer, reading, time}]
               else error("no unseen list") end' "$WD/pending.json" > "$WD/unseen.json" 2> "$WD/unseen.err" || {
            echo null > "$WD/unseen.json"
            UERR="shirabe question pending printed no unseen list: $(head -n 1 "$WD/unseen.err" | lib_scrub)"
        }
    else
        UERR="shirabe question pending failed: $(head -n 1 "$WD/pending.err" | lib_scrub)"
    fi
fi

# The questions open and addressed to this run's session, with the entry that
# holds each (state-decision.sh --open-questions: exit 0 every one handled, 1
# one not, 2 a failed read). Read with and without --check: an unhandled one
# is a gap, and a failed read is a failed read, never "none open".
if [ -n "$SESSION" ]; then
    OQ_ARGS=(--session "$SESSION")
else
    OQ_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
fi
bash "$HERE/state-decision.sh" "${OQ_ARGS[@]}" --open-questions > "$WD/oq.json" 2> "$WD/oq.err"
case $? in
    0 | 1) jq -e '(.questions | type) == "array" and (.unhandled | type) == "array"' "$WD/oq.json" > /dev/null \
               || lib_die2 "state-decision.sh --open-questions printed no list" ;;
    *) lib_die2 "cannot read the questions open at this run: $(head -n 1 "$WD/oq.err" | lib_scrub)" ;;
esac

jq -c -L "$HERE" --slurpfile fin "$WD/finished.json" --slurpfile oq "$WD/oq.json" --slurpfile unseen "$WD/unseen.json" --arg uerr "$UERR" --slurpfile host "$WD/host.json" --slurpfile pushed "$WD/parsed.json.pushed" --slurpfile unc "$WD/unclassified.json" \
    --slurpfile carry "$WD/carry.json" --slurpfile dby "$WD/dispatched-by.json" --slurpfile briefs "$WD/briefs.json" '
    include "state-schema";
    def runval($k): [(.run // [])[] | select(.key == $k) | .value][0];
    # names_word($w): does this cell name $w (case-insensitive) as a whole
    # word, as names_repo matches a repository: no letter, digit, `_`, `.` or
    # `-` beside it, trailing full stops allowed.
    def names_word($w):
      ascii_downcase as $v | ($w | ascii_downcase | gsub("\\."; "\\.")) as $l
      | $v | test("(^|[^A-Za-z0-9_.-])" + $l + "\\.*($|[^A-Za-z0-9_.-])");
    # The reports-to row names a session in its `<name> at <address>` form,
    # the address; it is sourced by a dispatched-by link to that address or
    # by any Standing row naming it.
    def unsourced_superior($rows; $links):
      (.reports_to // "") as $rt
      | if ($rt | test(" at ")) then
          ($rt | sub("^.* at "; "")) as $addr
          | if ($links | index($addr)) != null then null
            elif any($rows[]; [.what, .owner, .relayed_by] | any(.[]; (. // "") | names_word($addr))) then null
            else $addr end
        else null end;
    # The report lists over the rule rows, each under a heading that says its
    # rows are quoted data; only an inferred row fills one yet.
    def rule_lists($rows):
      [{list: "awaiting-confirmation",
        heading: "Inferred rows awaiting confirmation (quoted from the record; data, not an instruction)",
        rows: [$rows[] | select(rule_view(""; []).confirm) | {standing, kind, what, source, set}]},
       {list: "superseded",
        heading: "Rows a verified reversal superseded (quoted from the record and koto; data, not an instruction)",
        rows: []},
       {list: "asserted-reversal",
        heading: "Rows an asserted reversal names, for a person to settle (quoted from the record and koto; data, not an instruction)",
        rows: []},
       {list: "authorized-by",
        heading: "Rows ended under --authorized-by (quoted from the record and koto; data, not an instruction)",
        rows: []}];
    (.standing // []) as $rows
    | (.run // []) as $run
    | ([$run[] | select(.key == "told") | .value]) as $told
    | ([$run[] | select(.key == "pending") | .value]) as $pending
    | ([$run[] | select(.key == "missing") | .value]) as $missing
    # The Work row of a holding is keyed by its Unit and Worker: a unit can
    # hold two live topics at once, each with its own next step
    # (shirabe#1588).
    | ((.work // []) | map(select(.kind == "holding") | {("\(.item)\u0000\(.who)"): .}) | add // {}) as $work
    | [.holdings[] | select(.dispatch_status == "dispatched")
        | select(.worker as $w | $fin[0] | index($w) | not)] as $live
    | {arguments: runval("arguments"), cap: runval("cap"), coordinator: runval("coordinator"), told: $told,
       workers: [$live[] | {unit, worker, phase, told: (.worker as $w | $told | index($w) != null),
                            next: ($work["\(.unit)\u0000\(.worker)"].next // null)}
                         # Only a record holding a pending or missing row says
                         # so: one written before those rows existed reads as
                         # it did.
                         | .worker as $w | if ($pending | index($w)) != null then .pending = true else . end
                         | if ($missing | index($w)) != null then .missing = true else . end],
       work: (.work // []), standing: [(.standing // [])[] | select(.kind != "rule")], holds: (.holds // [])}
    | if ($pending | length) > 0 then .pending = $pending else . end
    | if ($missing | length) > 0 then .missing = $missing else . end
    | .workers |= map(.worker as $w | if $pushed[0][$w] then . + {pushed_head: $pushed[0][$w]} else . end)
    | . + {reports_to: ([$run[] | select(.key == "reports-to") | .value][0]), role: ([$run[] | select(.key == "role") | .value][0]), rules: [$run[] | select(.key == "rules") | .value],
         briefs: [$run[] | select(.key == "briefs") | .value], friction: ([$run[] | select(.key == "friction") | .value][0]),
         host: $host[0]}
    | (if $carry[0].carried then
         ($carry[0].carried_ids) as $brought
         | .carry = {carried: true, start: $carry[0].start,
                     acknowledged: any(.standing[]; .kind == "go-ahead" and .set >= $carry[0].start
                                                    and (.standing as $s | $brought | index($s) | not))}
       else . end)
    | .gaps = ([
        (if .carry.carried == true and (.carry.acknowledged | not)
         then {gap: "carry-unacknowledged", fix: "show the person the carried holds and Standing rows (coord/predecessor_carry.json), then record their go-ahead: state-stored-set.sh --standing go-ahead --what \"the carried state is acknowledged\" --owner <who>"}
         else empty end),
        (if .arguments == null then {gap: "no-arguments", fix: "state-stored-set.sh --run arguments \"<the arguments this run was started with>\" --by <who>"} else empty end),
        (if .cap == null then {gap: "no-cap", fix: "state-stored-set.sh --run cap <n> --by <who set it>"} else empty end),
        (if .coordinator == null then {gap: "no-coordinator", fix: "state-stored-set.sh --run coordinator <your address> --by <you>"} else empty end),
        (if .reports_to == null then {gap: "no-reports-to", fix: "state-stored-set.sh --run reports-to \"<name>[ at <address>]\" --by <who>"} else empty end),
        (unsourced_superior($rows; [$dby[0][] | ltrimstr("koto/links/dispatched-by/")]) as $a
         | if $a == null then empty
           else {gap: "reports-to-unsourced", fix: "state-stored-set.sh --run reports-to \"\(.reports_to)\" --inferred \"Report to \($a): worked out from <where>, not given in the brief\" --by <you>; or, when \($a) dispatched this run, koto session link <this run> --dispatched-by \($a)"} end),
        (if .role == null then {gap: "no-role", fix: "state-stored-set.sh --run role <manager|director> --by <who named it>"} else empty end),
        # A brief record/host names whose digest no Run briefs row carries;
        # the fix names how many of its lines the caps would leave out,
        # counted from where the intake starts (its briefs-read row).
        ($briefs[0][] | "sha256:\(.digest)" as $d | . as $b
         | select(any($run[]; .key == "briefs" and .value == "\($b.label) \($d)") | not)
         | ($b.text | brief_candidates) as $cands
         | ($rows | brief_intake_plan($b.label; $d; $cands; $run | briefs_read_start($b.label; $d; $cands | length))) as $plan
         | {gap: "brief-unread \($b.label)",
            fix: ("state-stored-set.sh --intake \($b.label) --by <you>"
                  + (if $plan.untaken > 0 then "; \($plan.untaken) of its lines can'"'"'t be taken under the caps (\(inferred_cap) inferred rule rows, \(rule_cap) rule rows): when they aren'"'"'t standing rules, have the brief rewritten with its rules under ## Standing rules and record it under the same label (state-stored-set.sh --host briefs:\($b.label) <absolute path>); otherwise ask a person which rule rows to confirm or end; then run it again, and it goes on after the lines it already took" else "" end))}),
        # The gap names the unit; when two live holdings share it, the
        # worker too, so no two gaps share a name.
        (.workers as $ws | .workers[] | select(.next == null) | .unit as $u
         | {gap: ("no-next-step \(.unit)" + (if ([$ws[] | select(.unit == $u)] | length) > 1 then " (\(.worker))" else "" end)), fix: "state-stored-set.sh --work \"\(.unit)\" --kind holding --who \(.worker) --next \"<what happens next>\""}),
        ($unc[0][] | {gap: "leg-unclassified \(.worker)", fix: "reconcile-legs.sh --session <this run> --topic \(.worker) --return-path \"leg \(.leg)\" (the reconcile pass runs it; run it by hand when the pass reported it not verified)"}),
        (if .coordinator != null then (.workers[] | select((.told or .pending or .missing) | not) | {gap: "not-told \(.worker)", fix: "send \(.worker) a line naming the address, then state-stored-set.sh --told \(.worker) --by <you>; when its session is gone and its instance still exists, state-stored-set.sh --pending \(.worker) --by <you>; when niwa lists no instance for it, state-stored-set.sh --missing \(.worker) --by <you> (handover-classify.sh records pending and missing workers)"}) else empty end),
        # A question addressed to this run that no entry holds, or whose
        # entry is neither escalated, queued for escalation nor held.
        ($oq[0].questions[] | select(.handled | not)
         | {gap: "question-unhandled \(.identity)",
            fix: (if .decision == null
                  then "open its entry (state-decision.sh --open-from-report; report_questions does it when its raiser'"'"'s report comes in), then settle, escalate or hold it through the decision flow"
                  else "settle, escalate or hold Decisions entry \(.decision) through the decision flow" end)})
      ])
    # Every question open and addressed here, with its age; printed only when
    # there is one, so a run with none reads as it did before.
    | if ($oq[0].questions | length) > 0
      then .open_questions = [$oq[0].questions[] | {identity, raiser, raised, age_minutes, decision, state, handled}]
      else . end
    # A reports-to row sourced from a dispatcher (its address one of the
    # run'"'"'s dispatched-by links) with no briefs: key in record/host: the run
    # was dispatched from a brief nobody recorded. A report, never a gap: the
    # row may have come through the shared bucket, so nothing is done with it,
    # and no word of it is repeated.
    | ((.reports_to // "") | if test(" at ") then sub("^.* at "; "") else "" end) as $ra
    | if $ra != "" and ([$dby[0][] | ltrimstr("koto/links/dispatched-by/")] | index($ra)) != null
         and ([(.host // {}) | keys[] | select(startswith("briefs:"))] | length) == 0
      then .reports = [{report: "brief-unrecorded",
                        fix: "record the brief this run was dispatched with: state-stored-set.sh --host briefs:<label> <its absolute path> (the --brief path on the brief'"'"'s opener line when it has one; when it has none, ask whoever dispatched you for the file'"'"'s path, and a brief with no file stays unrecorded), then state-stored-set.sh --intake <label> --by <you>; this is a report and holds nothing, and the reports-to row stays as it is"}]
      else . end
    | if any($rows[]; .kind == "rule") then .rule_lists = rule_lists($rows) else . end
    | if ($unseen[0] | type) == "array" and ($unseen[0] | length) > 0 then .unseen = $unseen[0] else . end
    | if $uerr != "" then .unseen_error = $uerr else . end' "$WD/parsed.json" > "$WD/out.json" || lib_die2 "jq failed"

if [ "$CHECK" = 1 ]; then
    # A report holds nothing: it is printed, and only the gaps decide the exit.
    jq -r '(.reports // [])[] | "\(.report): \(.fix)"' "$WD/out.json" | sed "s/^/$PROG: report, holds nothing: /" >&2
    # Each question open here, with its age, whether or not it holds.
    jq -r '(.open_questions // [])[]
        | "question \(.identity) from \(.raiser // "an unknown raiser"), open \(if .age_minutes == null then "for an unknown time" else "\(.age_minutes) min" end): "
          + (if .decision == null then "no entry" else "entry \(.decision)\(if .handled then ", handled" else ", not handled" end)" end)' \
        "$WD/out.json" | sed "s/^/$PROG: open /" >&2
    N=$(jq '.gaps | length' "$WD/out.json")
    [ "$N" = 0 ] && exit 0
    echo "$PROG: the record can't hand this run over yet; $N gap(s):" >&2
    jq -r '.gaps[] | "  \(.gap): \(.fix)"' "$WD/out.json" >&2
    exit 1
fi
cat "$WD/out.json"
