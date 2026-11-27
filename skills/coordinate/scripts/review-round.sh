#!/usr/bin/env bash
# review-round.sh -- a worker records its review round in its own run session,
# where the coordinator's land step reads it (land-check.sh step 4, through
# board-lib.sh's bl_review_evidence), so the round needs no table in the pull
# request body.
#
# Usage: review-round.sh record --session <worker session> <round-file|->
#        review-round.sh audit --session <work-on session> [--panel <panel>]
#
# The round is one JSON object, the shape panel-evidence.sh --round reads:
#
#   {"reviewed_head": "<40-hex sha>",
#    "seats": [{"seat": "architect", "model": "sonnet",
#               "run": "<the seat's run id>", "verdict": "pass"}, ...]}
#
# It is judged by panel-evidence.sh --round before anything is written, so a
# round the land step would call malformed is refused here, with the rule it
# breaks, rather than stored. A well-formed round is stored as the session's
# context key review_round.json, replacing any round recorded before: the
# land step reads the latest one, at the head the worker reports ready. A
# round with a failing seat is well-formed and is stored; the land step
# refuses it as not unanimous.
#
# The session is the worker's own: the run the coordinator's leg is bound to,
# or on the message path the one its opener opened (its name, such as
# issue_<N>). The coordinator finds it through the leg; a worker with no leg
# reports it instead, since render-result.sh carries the stored round in the
# result block of its final report.
#
# Once stored, the round is also sent to koto's run journal as review
# telemetry: `koto review record <session> code-round` (koto 0.33.0 and
# later) writes one code review round record and one verdict per seat, with
# its seat, model and verdict, apart from the document review kinds. koto
# keeps a seat the session's template declares in review_vocabulary and
# records any other as `other`. koto doesn't number rounds, so the session's
# context key review_round_count holds how many this script has sent: the
# round goes as that count plus one (an absent or unreadable count is 0), and
# the count is raised only once koto has taken it. The telemetry is best
# effort: a koto without the verb, a refusal or a failed count write prints
# one `review-round:` notice on stderr and changes nothing else, so the exit
# code, the stdout line and the stored round are the same either way. A
# finished session takes no review events, so a round recorded on one is
# stored with no telemetry and no notice.
#
# Exit codes: 0 stored (prints `recorded <count> seats at <reviewed head>`);
# 1 the round is malformed (prints `malformed <reason> row <n>` on stderr);
# 2 the round couldn't be read or koto couldn't store it; 64 usage.
#
# ## audit: the light-cap audit's miss or no-miss
#
# A /work-on run at the `light` review level runs one seat. One run in ten,
# the ones whose session name `review-level.sh audit` selects, goes on from
# its passed light panel to scrutiny, review and QA. A miss is such a run
# whose full panel raised a finding at blocking severity at a head the light
# seat passed. Nobody reports it: `panel-scope.sh --record` runs
# `review-round.sh audit` after every scrutiny, review or QA round it records
# (the moment the full panel's verdicts land in the verdict ledger), and this
# verb reads the ledger and records the outcome as a koto decision, which
# reaches the signals as koto.decision_recorded:
#
#   koto decisions record <s> --kind verdict --by check:light-audit
#       --subject what=light-audit/miss/<category> --outcome fail     a miss
#       --subject what=light-audit/no-miss         --outcome pass     no miss
#       --evidence context:verdict_ledger.json --reason <one line>
#
# koto's `verdict` kind takes pass, fail or inconclusive and a `what`
# subject, so a miss is `fail` and a no-miss is `pass`, each named in the
# subject. <category> is the category of the miss's most severe finding:
# security, then correctness, then other, then uncategorized for a finding
# its seat gave no category (panel-scope.sh keeps a finding's optional
# `category`). The reversal rule in skills/work-on/references/review-levels.md
# reads these decisions.
#
# From the session's verdict_ledger.json: the heads the light seat passed are
# the heads of the light panel's rounds (its history entries) at which no
# blocking light finding was raised or held. A miss is a `raised` record of a
# blocking scrutiny, review or qa finding at one of those heads; a decider's
# no-verdict (`unverified`) and an agent's promotion are not. A miss is
# recorded the first time one is found, and a no-miss once, when a QA round
# (--panel qa) is recorded at a head the light seat passed with no miss found:
# QA is the last full panel, and it runs only after scrutiny and review
# passed at that head. A run is a miss when any miss decision is recorded, so
# a later lap's miss after a no-miss still counts. The context key
# light_audit.json ({"miss": <decision id>|null, "no_miss": <id>|null})
# keeps each to once.
#
# Nothing is recorded, with exit 0 and a `none:` line, for a session that
# isn't audited, a run whose review level is no longer light (an escalated
# run reaches the full panels as a standard run, not as an audit), or one
# with no light round in its ledger. Prints `miss <category> <decision id>`,
# `no-miss <decision id>`, `pending: ...` (no miss yet and no QA round to
# close it), `none: ...`, or `unsupported: ...` with one notice on stderr
# when this koto's `decisions record` has no --kind (koto 0.33.0, the entry
# floor), in which case nothing is recorded. Exit 0, or 2 when a koto read, the decision or
# the key's write fails, or the review level can't be read; 64 usage.
set -uo pipefail

PROG=review-round
HERE=$(cd "$(dirname "$0")" && pwd)
KOTO=${KOTO_BIN:-koto}
RE_SESSION='^[A-Za-z0-9._-]+$'

usage() { sed -n '/^# Usage:/,/^#$/p' "$0" | sed -e '/^#$/d' -e 's/^# \{0,1\}//' >&2; exit 64; }

# ---------------------------------------------------------------- audit -------
audit() {
    local session="" panel="" rl lvl t rc out id cat outcome what reason
    while [ $# -gt 0 ]; do
        case "$1" in
            --session) [ $# -ge 2 ] || usage; session=$2; shift 2 ;;
            --panel) [ $# -ge 2 ] || usage; panel=$2; shift 2 ;;
            *) usage ;;
        esac
    done
    [[ $session =~ $RE_SESSION ]] || usage
    case "$panel" in ""|scrutiny|review|qa|light) ;; *) usage ;; esac
    rl="$HERE/../../work-on/scripts/review-level.sh"
    rc=0
    bash "$rl" audit "$session" || rc=$?
    case "$rc" in
        0) ;;
        1) echo "none: $session is not audited"; return 0 ;;
        *) echo "$PROG: review-level.sh audit $session exited $rc" >&2; return 2 ;;
    esac
    lvl=$(bash "$rl" level "$session") || { echo "$PROG: could not read the review level of $session" >&2; return 2; }
    [ "$lvl" = light ] || { echo "none: $session's review level is ${lvl:-unset}, not light"; return 0; }

    AUDIT_T=$(mktemp -d "${TMPDIR:-/tmp}/review-round-audit.XXXXXX") || return 2
    trap 'rm -rf "$AUDIT_T"' EXIT
    t=$AUDIT_T
    ctx_read "$session" verdict_ledger.json "$t/ledger" || return 2
    ctx_read "$session" light_audit.json "$t/done" || return 2
    [ -s "$t/done" ] || printf '{}\n' > "$t/done"
    jq -e 'type == "object"' "$t/done" >/dev/null || printf '{}\n' > "$t/done"
    [ -s "$t/ledger" ] || printf '{}\n' > "$t/ledger"
    jq -c --arg panel "$panel" '
        def blocking_at($pn): [(.findings // {})[] | select(type == "object" and .severity == "blocking" and .panel == $pn)];
        ([blocking_at("light")[] | (.records // [])[] | select(.kind == "raised" or .kind == "holds") | .commit]) as $lblock
        | ([(.history // [])[] | select(.panel == "light") | .head | strings] | unique
           | map(. as $h | select(any($lblock[]; . == $h) | not))) as $passed
        | ([(.findings // {})[]
            | select(type == "object" and .severity == "blocking"
                     and (.panel == "scrutiny" or .panel == "review" or .panel == "qa"))
            | . as $f | (.records // [])[]
            | select(.kind == "raised" and (.commit as $c | any($passed[]; . == $c)))
            | {id: $f.id, panel: $f.panel, raiser: ($f.raiser.name // ""), commit: .commit,
               category: ($f.category // "uncategorized")}]) as $miss
        | def sev: if . == "security" then 0 elif . == "correctness" then 1 elif . == "other" then 2 else 3 end;
        {light_rounds: ([(.history // [])[] | select(.panel == "light")] | length),
         passed: $passed, miss: $miss,
         category: ([$miss[].category] | sort_by(sev) | .[0] // null),
         qa_at_passed: ($panel == "qa" and any((.history // [])[]; .panel == "qa" and (.head as $h | any($passed[]; . == $h))))}
    ' "$t/ledger" > "$t/verdict" || { echo "$PROG: could not read $session's verdict ledger" >&2; return 2; }

    if [ "$(jq -r .light_rounds "$t/verdict")" = 0 ]; then
        echo "none: $session's verdict ledger has no light round"
        return 0
    fi
    if [ "$(jq -r '.miss | length' "$t/verdict")" -gt 0 ]; then
        id=$(jq -r '.miss // empty' "$t/done")
        if [ -n "$id" ]; then echo "miss recorded: $id"; return 0; fi
        cat=$(jq -r .category "$t/verdict")
        outcome=fail
        what="light-audit/miss/$cat"
        reason=$(jq -r '"miss: the full panel raised \(.miss | length) blocking finding(s) at a head the light seat passed; first: \(.miss[0].panel)/\(.miss[0].raiser) \(.miss[0].id) at \(.miss[0].commit[0:12])"' "$t/verdict")
    elif [ "$(jq -r .qa_at_passed "$t/verdict")" = true ]; then
        id=$(jq -r '.no_miss // empty' "$t/done")
        if [ -n "$id" ]; then echo "no-miss recorded: $id"; return 0; fi
        outcome=pass
        what=light-audit/no-miss
        reason="no-miss: scrutiny, review and QA raised no blocking finding at a head the light seat passed"
    else
        echo "pending: no miss yet, and no QA round at a head the light seat passed"
        return 0
    fi
    # A koto older than the decision kinds (0.33.0, the entry floor, has no
    # --kind on `decisions record`) can't record a verdict decision. The audit
    # is best effort: it says so once and records nothing, so a later koto
    # records the run's outcome the next time a full-panel round lands.
    if ! koto_records_verdicts; then
        echo "$PROG: this koto's \`decisions record\` has no --kind, so the light audit's $what is not recorded" >&2
        echo "unsupported: koto can't record a verdict decision"
        return 0
    fi
    out=$("$KOTO" decisions record "$session" --kind verdict --outcome "$outcome" \
            --subject "what=$what" --by check:light-audit \
            --evidence context:verdict_ledger.json --reason "$reason") \
        || { echo "$PROG: koto did not record the audit's $what decision: ${out%%$'\n'*}" >&2; return 2; }
    id=$(jq -r '.id // .decision.id // empty' <<< "$out")
    [ -n "$id" ] || { echo "$PROG: koto recorded the $what decision but returned no id: ${out%%$'\n'*}" >&2; return 2; }
    if [ "$outcome" = fail ]; then
        jq -c --arg id "$id" '.miss = $id' "$t/done" > "$t/done.next"
        echo "miss $cat $id"
    else
        jq -c --arg id "$id" '.no_miss = $id' "$t/done" > "$t/done.next"
        echo "no-miss $id"
    fi
    "$KOTO" context add "$session" light_audit.json < "$t/done.next" >/dev/null \
        || { echo "$PROG: decision $id recorded, but light_audit.json couldn't be written in $session" >&2; return 2; }
    return 0
}

# koto_records_verdicts: 0 when `koto decisions record` takes the --kind,
# --subject and --evidence a verdict decision needs, read from its --help.
# koto's own error, if the help can't be printed, reaches stderr.
koto_records_verdicts() {
    local help
    help=$("$KOTO" decisions record --help) || return 1
    case "$help" in *--kind*) ;; *) return 1 ;; esac
    case "$help" in *--subject*) ;; *) return 1 ;; esac
    case "$help" in *--evidence*) ;; *) return 1 ;; esac
    return 0
}

# ctx_read <session> <key> <file>: the key into <file>, empty when koto says
# it is absent; 1 (koto's output on stderr) when the read fails.
ctx_read() {
    local rc=0
    : > "$3"
    "$KOTO" context exists "$1" "$2" > "$3.exists" || rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$3.exists" ]; then rm -f "$3.exists"; return 0; fi
    if [ "$rc" -ne 0 ]; then
        cat "$3.exists" >&2
        rm -f "$3.exists"
        echo "$PROG: koto context exists $1 $2 exited $rc" >&2
        return 1
    fi
    rm -f "$3.exists"
    "$KOTO" context get "$1" "$2" > "$3" || { cat "$3" >&2; : > "$3"; echo "$PROG: could not read $2 from $1" >&2; return 1; }
}

if [ "${1:-}" = audit ]; then
    shift
    audit "$@"
    exit $?
fi

[ $# -eq 4 ] && [ "$1" = record ] && [ "$2" = --session ] || usage
SESSION=$3 IN=$4
[[ $SESSION =~ $RE_SESSION ]] || usage
case "$IN" in --*) usage ;; esac

T=$(mktemp "${TMPDIR:-/tmp}/review-round.XXXXXX") || exit 2
trap 'rm -f "$T" "$T.seats"' EXIT
if [ "$IN" = - ]; then
    cat > "$T" || exit 2
else
    [ -r "$IN" ] || { echo "$PROG: can't read $IN" >&2; exit 2; }
    cat "$IN" > "$T" || exit 2
fi

EV=$(bash "$HERE/panel-evidence.sh" --round "$T") || { echo "$PROG: the round couldn't be judged" >&2; exit 2; }
if [ "$(printf '%s' "$EV" | jq -r .status)" != ok ]; then
    echo "$PROG: $(printf '%s' "$EV" | jq -r '"malformed \(.reason) row \(.row)"')" >&2
    exit 1
fi
# The stored copy is the round as given, compacted, so the land step parses
# exactly what was judged here.
jq -c . "$T" | "$KOTO" context add "$SESSION" review_round.json >/dev/null || {
    echo "$PROG: could not store review_round.json in $SESSION" >&2; exit 2; }

# The telemetry, best effort (the header says why). koto's own message is
# kept for the notice rather than discarded, so a refusal says what koto
# refused.
telemetry() {
    local n out code
    n=$("$KOTO" context get "$SESSION" review_round_count 2>&1) || n=0
    [[ $n =~ ^[1-9][0-9]{0,8}$ ]] || n=0
    n=$((n + 1))
    jq -c '[.seats[] | {seat, model, verdict}]' "$T" > "$T.seats" || {
        echo "$PROG: the round is stored, but its seats couldn't be written for koto's review telemetry" >&2; return; }
    out=$("$KOTO" review record "$SESSION" code-round --round "$n" \
            --head "$(printf '%s' "$EV" | jq -r .reviewed_head)" --file "$T.seats" 2>&1) || {
        # koto records review events only while a run is live, and a round
        # recorded on a finished session (a /work-on child at done, which the
        # template's fix round records on) is refused as session_terminal:
        # expected, so it gets no notice. Only the first line of each is
        # read, through a here-string and an expansion rather than a pipe into
        # head, which would stop reading early under pipefail.
        code=$(jq -Rr 'fromjson? | .error.code? // empty' <<< "$out")
        [ "${code%%$'\n'*}" = session_terminal ] && return
        echo "$PROG: the round is stored, but koto didn't record it as review telemetry: ${out%%$'\n'*}" >&2
        return; }
    printf '%s\n' "$n" | "$KOTO" context add "$SESSION" review_round_count >/dev/null || \
        echo "$PROG: round $n went to koto's review telemetry, but review_round_count couldn't be stored in $SESSION" >&2
}
telemetry
printf '%s\n' "$EV" | jq -r '"recorded \(.count) seats at \(.reviewed_head)"'
