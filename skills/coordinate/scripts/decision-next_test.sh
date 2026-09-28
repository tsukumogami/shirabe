#!/usr/bin/env bash
# decision-next_test.sh -- decision-next.sh against the gh and koto stand-ins,
# from fixtures built of the rules they owe.
#
# Covers: every word from a fixture owing only it; the routing order, pair by
# pair, from fixtures owing two adjacent rules; a copy of the script with two
# adjacent rules swapped failing that order; held entries skipped; a cited or
# withdrawal-only report counting as recorded; a report left behind by
# overflow or a detour through wait giving clear; only this run's stamps
# counting; an identical answer's line counting it recorded; the verdict's
# entry in coord/decision.json; clear-report only for a report with a
# holding; record-full on a record too close to the budget; --owed dispatch
# and pick by the DESIGN's blocking table.
#
# Usage: bash skills/coordinate/scripts/decision-next_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
. "$HERE/testdata/test-lib.sh"
CL="$HERE/coord-log.sh"
RUN=20260926T080000Z
DN="$HERE/decision-next.sh"

ESC='"round": "1", "verdict": "escalate", "recommendation": "wait", "reason": "r", "context": "c", "problem": "p", "grounds": "scope", "target": "a person"'
E() { # E <n> <state> <extra JSON members, without braces>
    printf '{"decision": "%s", "round": "0", "question": "Q%s?", "options": "ship -- now\\nwait -- later", "state": "%s", "source": "self [20260925T080000Z raise %s]", "updated": "2026-09-26T07:00Z"%s}' \
        "$1" "$1" "$2" "$1" "${3:+, $3}"
}
# The entry each message and entry rule owes, by rule.
entry_for() {
    case "$1" in
        withdraw) E 2 coordinator-verdict '"owed": "withdrawal"' ;;
        reply) E 3 settled '"owed": "reply", "outcome": "wait; reason: r", "decided_by": "a person", "source": "worker w1 [20260925T080000Z report 1.1]"' ;;
        redirect) E 4 proposed "\"source\": \"worker w1 [$RUN report 7.1]\", \"evidence\": \"2026-09-26T07:10Z worker w1 [$RUN report 7.1]: addressed to a person\"" ;;
        escalate) E 5 escalated "$ESC, \"owed\": \"escalation\"" ;;
        take) E 6 proposed ;;
        verdict) E 7 coordinator-verdict ;;
    esac
}

# build <rule>...: a discipline record and a session owing exactly those rules,
# at decision_next. Sets S.
build() {
    local r entries="" handoff='{"next": 1, "entries": []}' open=0 ans=0 evi=0 raise=0
    for r in "$@"; do
        case "$r" in
            carry) handoff="{\"next\": 60, \"entries\": [$(E 50 escalated "$ESC")]}" ;;
            unrecorded-open) open=1 ;; unrecorded-answer) ans=1 ;; unrecorded-evidence) evi=1 ;; unrecorded-raise) raise=1 ;;
            *) entries="$entries${entries:+, }$(entry_for "$r")" ;;
        esac
    done
    [ "$ans$evi" = 00 ] || entries="$entries${entries:+, }$(E 1 escalated "$ESC")"
    rm -rf "$KOTO_STORE/sessions" "$KOTO_STORE/context"; mkdir -p "$KOTO_STORE/sessions"
    db_init
    db '.branches["acme/widgets"]["coordinate/discipline-ci"] = $s | .prs += [{repo: "acme/widgets", number: 22, title: "docs(coordinate): ci rotation 2026-09-26 to 2026-10-03",
        body: $b, state: "OPEN", isDraft: true, isCrossRepository: false, baseRefName: "main", headRefName: "coordinate/discipline-ci", headRefOid: $s, author: "coord", editor: null}]' \
        --arg s "$SHA_HEAD" --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$entries]" '.decisions = {next: 20, entries: $e}')" pr)"
    record_json discipline ci | jq -c --argjson d "$handoff" '.decisions = $d | .rotation = {start: "2026-09-19", end: "2026-09-26", date: "2026-09-26", host_repo: "acme/widgets", record_url: "https://github.com/acme/widgets/pull/21"} | .reasoning = "Carry on."' > "$T/h.json"
    bash "$HERE/record-render.sh" --format handoff "$T/h.json" > "$T/h.md"
    db '.files["acme/widgets"]["main:docs/disciplines/ci.md"] = $t' --arg t "$(cat "$T/h.md")"
    S="coordinate-discipline-ci-$RUN"
    found_session "$S" "$(discipline_vars ci)" 22
    LAST=reconcile
    # The log, in the order the rules need: arrivals at wait before the report.
    [ "$raise" = 1 ] && { to decision_raise; to decision_next; }
    [ "$evi" = 1 ] && { to wait; log_evidence "$S" wait '{"event":"evidence","decision":"1"}'; to decision_evidence; to decision_next; }
    [ "$ans" = 1 ] && { to wait; log_evidence "$S" wait '{"event":"answer","decision":"1","round":"1"}'; to decision_answer; to decision_next; }
    [ "$open" = 1 ] && report holding
    [ "$LAST" = decision_next ] || to decision_next
}
to() { log_to "$S" "$LAST" "$1"; LAST=$1; }
# report <holding|unknown> [questions|overflow]: a report reaches decision_open
report() {
    to report_facts
    if [ "$1" = holding ]; then log_capture "$S" REPORT "$(bash "$CL" seal --session "$S" --state report_facts --token "holding none w1")"
    else log_capture "$S" REPORT "$(bash "$CL" seal --session "$S" --state report_facts --token "unknown w1")"; fi
    to report_questions
    if [ "${2:-questions}" = questions ]; then
        printf '[{"index":1,"kind":"question","text":"x?","source":"worker w1","addressed":false,"cite":null}]' > "$T/q.json"
        KS=$(bash "$CL" seal --session "$S" --state report_questions --file "$T/q.json" --key coord/questions.json)
        RSEQ=${KS#sealed:}; RSEQ=${RSEQ%%:*}
        log_capture "$S" QUESTIONS "$(bash "$CL" seal --session "$S" --state report_questions --token "questions 1 keyseal:${KS#sealed:}")"
        to decision_open
    else
        log_capture "$S" QUESTIONS "$(bash "$CL" seal --session "$S" --state report_questions --token overflow)"
        to rebrief
    fi
}
# next [script]: the routed verdict's words, without its seal
next() { bash "${1:-$DN}" --session "$S" 2>"$T/err" | sed 's/ sealed:.*//'; }
word() { next "$@" | cut -d' ' -f1; }

RULES="carry unrecorded-open unrecorded-answer unrecorded-evidence unrecorded-raise withdraw reply redirect escalate take verdict"

echo "== each word =="
for r in $RULES; do
    build "$r"
    eq "$r alone routes to $r" "$r" "$(word)"
done
build redirect
eq "a redirect names its entry and its report" "redirect 4 7" "$(next)"
build verdict
next >/dev/null
eq "a verdict writes its entry to coord/decision.json" "7" "$(koto context get "$S" coord/decision.json | jq -r .decision)"
build
eq "nothing owed is clear" "clear" "$(word)"

echo "== the order, pair by pair =="
# pairs <script>: how many adjacent pairs route to the higher rule
pairs() {
    local prev="" r n=0
    for r in $RULES; do
        if [ -n "$prev" ]; then
            build "$prev" "$r"
            [ "$(word "$1")" = "$prev" ] && n=$((n + 1))
        fi
        prev=$r
    done
    printf '%s' "$n"
}
eq "every adjacent pair routes to the higher rule" 10 "$(pairs "$DN")"
# The same suite against a copy with withdraw and reply swapped must fail.
SW="$T/swapped"; mkdir -p "$SW"; cp "$HERE"/*.sh "$HERE"/*.jq "$SW/"; cp -R "$HERE/../references" "$T/"
awk '/elif lowest\(.owed == "withdrawal"\)/ { w = $0; getline r1; print r1; print w; next } { print }' "$DN" > "$SW/decision-next.sh"
if cmp -s "$DN" "$SW/decision-next.sh"; then bad "the swapped copy differs from the script"
else [ "$(pairs "$SW/decision-next.sh")" -lt 10 ] && ok "a copy with two adjacent rules swapped fails the order" || bad "a copy with two adjacent rules swapped fails the order"; fi

echo "== what counts =="
build
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 7 coordinator-verdict '"verdict": "hold", "reason": "the benchmark"')]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "a held entry is skipped" "clear" "$(word)"
build
report holding
to decision_next
eq "a report whose write didn't land is unrecorded" "unrecorded-open" "$(word)"
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 8 settled "\"outcome\": \"w; reason: r\", \"decided_by\": \"a person\", \"evidence\": \"2026-09-26T07:20Z worker w1 [$RUN report $RSEQ.1]: the cap\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "a report recorded only as evidence (all cited) counts as recorded, and is still to classify" "clear-report" "$(word)"
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 8 settled "\"outcome\": \"w; reason: r\", \"decided_by\": \"a person\", \"evidence\": \"2026-09-26T07:20Z worker w1 [20260925T080000Z report $RSEQ.1]: another run\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "another run's stamp with the same sequence doesn't count" "unrecorded-open" "$(word)"
build
report holding overflow
to decision_next
eq "a report that overflowed leaves nothing owed" "clear" "$(word)"
build
report holding
to wait; to decision_next
eq "a report left behind by a detour through wait is clear" "clear" "$(word)"
build
report unknown
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 8 proposed "\"source\": \"worker w1 [$RUN report $RSEQ.1]\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 8 settled "\"outcome\": \"w; reason: r\", \"decided_by\": \"a person\", \"source\": \"worker w1 [$RUN report $RSEQ.1]\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
to decision_next
eq "a recorded report with no holding is clear, not clear-report" "clear" "$(word)"
build unrecorded-answer
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 1 settled "\"round\": \"1\", \"outcome\": \"wait; reason: r\", \"decided_by\": \"a person\", \"evidence\": \"2026-09-20T07:20Z a person [20260920T080000Z wait 9]: answer for round 1: wait\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "an answer line from an earlier run doesn't count: a re-sent answer owes its own stamped line" "unrecorded-answer" "$(word)"
WSEQ=$(bash "$CL" evidence --session "$S" --state wait --where event=answer | jq -r .seq)
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 1 settled "\"round\": \"1\", \"outcome\": \"wait; reason: r\", \"decided_by\": \"a person\", \"evidence\": \"2026-09-20T07:20Z a person [20260920T080000Z wait 9]: answer for round 1: wait\\n2026-09-26T08:20Z a person [$RUN wait $WSEQ]: answer for round 1 again: wait\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "the re-sent answer's own line, with this run's stamp, counts as recorded" "clear" "$(word)"
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 1 settled "\"round\": \"1\", \"outcome\": \"ship; reason: r\", \"decided_by\": \"a person\", \"evidence\": \"2026-09-26T07:20Z a person [$RUN wait 3]: answer for round 1: ship\"")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "another answer line for the same round, under another stamp, doesn't hide this one" "unrecorded-answer" "$(word)"

echo "== record-full =="
build take
BIG=$(head -c 57000 /dev/zero | tr '\0' 'x')
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 6 proposed)]" --arg r "$BIG" \
    '.decisions = {next: 20, entries: $e} | .deferrals = [{deferral: "a long one", reason: $r, raised: "2026-09-26T07:00Z", disposition: ""}]')" pr)"
eq "an owed write on a record near the budget is record-full" "record-full" "$(word)"
build take
eq "the same owed write on a small record is routed" "take" "$(word)"

echo "== --owed =="
owed() { bash "$DN" --session "$S" --owed "$1" 2>"$T/err"; }
for r in $RULES; do
    build "$r"
    eq "--owed pick: $r blocks pick" "$r" "$(owed pick)"
    eq "--owed dispatch before the first dispatch: $r blocks it" "$r" "$(owed dispatch)"
done
for r in carry take verdict; do
    build "$r"; to dispatch; to decision_next
    [ "$r" = carry ] && exp=none || exp=none
    eq "--owed dispatch after the first dispatch: $r doesn't block it" "$exp" "$(owed dispatch)"
done
for r in unrecorded-raise withdraw reply redirect escalate; do
    build "$r"; to dispatch; to decision_next
    eq "--owed dispatch after the first dispatch: $r still blocks it" "$r" "$(owed dispatch)"
done
build
db '(.prs[0].body) = $b' --arg b "$(render "$(record_json discipline ci | jq -c --argjson e "[$(E 7 coordinator-verdict '"verdict": "hold", "reason": "r"'), $(E 5 escalated "$ESC")]" '.decisions = {next: 20, entries: $e}')" pr)"
eq "--owed: a held entry and an escalated one owing nothing block nothing" "none none" "$(owed pick) $(owed dispatch)"
eq "--owed seals nothing and writes nothing" "" "$(owed pick >/dev/null; koto context get "$S" coord/decision.json 2>/dev/null)"

done_tests decision-next
