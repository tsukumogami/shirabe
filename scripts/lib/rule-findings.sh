# rule-findings.sh -- how a gate script names the rules it reports.
#
# Sourced, never run. Before the `.` line a gate script defines:
#
#   RULE_IDS="<id> <id> ..."   every registry id the script can report, on one
#                              line of its own; scripts/check-rule-registry.sh
#                              reads that line with grep to know what each
#                              script can print
#   undecided() { ...; exit 2; }  the script's could-not-decide exit; the
#                              library calls it on every failure, so it has to
#                              exist before the library can fail
#
# and the `.` line itself ends in `|| undecided ...`, so a missing library holds
# the gate instead of letting it run without its rules. Then it calls:
#
#   rf_require <id>...         before checking anything, with the ids the mode
#                              can report written out literally (never
#                              "$RULE_IDS", which would make the membership test
#                              below check the list against itself): each must
#                              be in RULE_IDS and an active registry entry whose
#                              text resolves; otherwise `undecided`. Resolving
#                              up front means a broken anchor holds the gate at
#                              once, not only when a violation turns up. One
#                              script resolves late instead:
#                              skills/scope/scripts/check-hop-document.sh calls
#                              it after deciding, with only the ids its findings
#                              map to through a fixed in-source table, because
#                              resolving all seventeen on every run is too slow
#                              for a koto command gate; the membership test still
#                              applies, and CI's check-rule-registry.sh keeps
#                              every anchor resolvable.
#   rf_require_any <id>...     like rf_require, for an id the script reads from
#                              data rather than writes in its source (a
#                              finding's own rule). Each id must be an active
#                              registry entry whose text resolves; it need not
#                              be in RULE_IDS. Only a script that also defines
#                              `RULE_IDS_ANY_ACTIVE=1` on a line of its own may
#                              call it, and scripts/check-rule-registry.sh
#                              allows that line in panel-scope.sh alone, so the
#                              exception is declared and checked, not ambient
#   rf_finding <id> <detail> [<path> [<line>]]
#                              prints one ::koto-finding:: line whose rule_id is
#                              <id>, rule_ref is the reference rf_require
#                              resolved, and message is "<summary>: <detail>"
#                              with control characters replaced
#   rf_ref <id>, rf_summary <id>
#                              the resolved reference or summary, for a script
#                              that builds its finding objects itself; each calls
#                              `undecided` for an id rf_require didn't resolve.
#                              Such a script must prefix the message and replace
#                              control characters as rf_finding does
#                              (panel-scope.sh --verdict is the one that does)
#   rf_emit <json>             prints a finding object the script built and logs
#                              it; refuses (`undecided`) one whose rule_id was
#                              not resolved, whose rule_ref differs from the
#                              resolved one, or whose message lacks the summary
#                              prefix
#   rf_deliver                 the escalation ladder, below; called once, right
#                              before the script's non-zero exit that follows
#                              its findings
#
# Every printed finding also goes to `scripts/rule-registry.sh log-finding`,
# which appends it to $SHIRABE_FINDINGS_LOG when that names a safe file; the
# gate scripts' test suites use the log to verify what they printed.
#
# The escalation ladder. rf_emit records every rule id it prints in RF_REPORTED.
# rf_deliver then reads, from the koto session's own log, how many times koto has
# recorded this gate failing on each of those rules in the current state, and
# escalates on the count this failure will get (koto's rule_counts[id].session,
# plus one):
#
#   count 1                    nothing more: the finding's summary is rung 1
#   count >= RF_FULL_TEXT_AT   `rule-registry.sh release <id>`, the rule's full
#                              text; when release refuses it, its refusal line
#                              and then one line giving the rule's rule_ref
#   count >= RF_EXIT_AT        one ::shirabe-check-exit::{json} line, when the
#                              current state has a named exit, naming the rule,
#                              its count and the evidence that takes the exit
#
# The ladder runs only when the koto template supplies its context on the gate
# command, as environment assignments written the same in every state that
# shares the command:
#
#   SHIRABE_GATE_LOG    the session log, {{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl
#   SHIRABE_GATE_NAME   the gate's name in the template
#   SHIRABE_GATE_EXITS  "<state>:<status field> ...", the states with a named exit
#
# The state is read from the log (the last transition's `to`), never from the
# command. Without SHIRABE_GATE_LOG and SHIRABE_GATE_NAME, rf_deliver does
# nothing and the script prints what it always printed. With them, a log the
# ladder can't read puts every reported rule at count 2 and offers no exit.
# rf_deliver writes only to standard error and always returns 0, so it never
# changes a gate's exit status, its standard output or the findings koto records.
# DESIGN-validate-and-return.md has the reasoning.
#
# Written for the bash 3.2 floor: no associative arrays, so the resolved refs
# and summaries are kept as tab-separated lines.

RF_HELPER="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/rule-registry.sh"
RF_CACHE=""
RF_TAB=$(printf '\t')
RF_REPORTED=""
RF_DELIVERED=""
RF_FULL_TEXT_AT=2
RF_EXIT_AT=3

rf_require() {
    local id ref summary
    [ -x "$RF_HELPER" ] || undecided "the rule registry reader $RF_HELPER is not executable"
    for id in "$@"; do
        case " $RULE_IDS " in
            *" $id "*) ;;
            *) undecided "rule $id is not in this script's RULE_IDS" ;;
        esac
        ref=$("$RF_HELPER" ref "$id" 2>&1) || undecided "cannot resolve rule $id: $ref"
        summary=$("$RF_HELPER" summary "$id" 2>&1) || undecided "cannot read rule $id: $summary"
        RF_CACHE="$RF_CACHE$id$RF_TAB$ref$RF_TAB$summary
"
    done
}

rf_require_any() {
    local id ref summary
    [ "${RULE_IDS_ANY_ACTIVE:-}" = 1 ] \
        || undecided "rf_require_any needs RULE_IDS_ANY_ACTIVE=1 in the calling script"
    [ -x "$RF_HELPER" ] || undecided "the rule registry reader $RF_HELPER is not executable"
    for id in "$@"; do
        # Already resolved this run: a second lookup would read the same entry.
        [ -z "$(rf_field "$id" 2)" ] || continue
        ref=$("$RF_HELPER" ref "$id" 2>&1) || undecided "cannot resolve rule $id: $ref"
        summary=$("$RF_HELPER" summary "$id" 2>&1) || undecided "cannot read rule $id: $summary"
        RF_CACHE="$RF_CACHE$id$RF_TAB$ref$RF_TAB$summary
"
    done
}

# rf_field <id> <2|3>: the cached ref (2) or summary (3), or nothing.
rf_field() {
    printf '%s' "$RF_CACHE" | awk -F'\t' -v id="$1" -v f="$2" '$1 == id { print $f; exit }'
}

rf_ref() {
    local v
    v=$(rf_field "$1" 2)
    [ -n "$v" ] || undecided "rule $1 was not resolved by rf_require in this run"
    printf '%s' "$v"
}

rf_summary() {
    local v
    v=$(rf_field "$1" 3)
    [ -n "$v" ] || undecided "rule $1 was not resolved by rf_require in this run"
    printf '%s' "$v"
}

rf_emit() {
    local json=$1 id ref msg want_ref want_summary line
    id=$(printf '%s' "$json" | jq -r '.rule_id // ""' 2>/dev/null)
    ref=$(printf '%s' "$json" | jq -r '.rule_ref // ""' 2>/dev/null)
    msg=$(printf '%s' "$json" | jq -r '.message // ""' 2>/dev/null)
    want_ref=$(rf_field "$id" 2)
    want_summary=$(rf_field "$id" 3)
    [ -n "$id" ] && [ -n "$want_ref" ] || undecided "a finding names rule [$id], which this run did not resolve"
    [ "$ref" = "$want_ref" ] || undecided "a finding for $id carries rule_ref [$ref], not [$want_ref]"
    case "$msg" in
        "$want_summary: "*) ;;
        *) undecided "a finding for $id does not start with the rule's summary" ;;
    esac
    line="::koto-finding::$json"
    printf '%s\n' "$line"
    "$RF_HELPER" log-finding "$line" </dev/null >/dev/null 2>&1 || true
    case " $RF_REPORTED " in
        *" $id "*) ;;
        *) RF_REPORTED="${RF_REPORTED:+$RF_REPORTED }$id" ;;
    esac
}

# rf_ladder_active: whether the template supplied the ladder's context.
rf_ladder_active() {
    [ -n "${SHIRABE_GATE_LOG:-}" ] || [ -n "${SHIRABE_GATE_NAME:-}" ]
}

# rf_exit_field <state>: the status field SHIRABE_GATE_EXITS names for the
# state, or nothing. Entries are split on spaces with globbing off and matched
# on the whole state name.
rf_exit_field() {
    local state=$1 entry field
    set -f
    # shellcheck disable=SC2086
    set -- ${SHIRABE_GATE_EXITS:-}
    set +f
    for entry in "$@"; do
        case "$entry" in
            "$state:"*)
                field=${entry#*:}
                case "$field" in
                    ''|*[!a-z_]*) return 0 ;;
                esac
                printf '%s' "$field"
                return 0
                ;;
        esac
    done
    return 0
}

# rf_ladder_counts: one pass over SHIRABE_GATE_LOG. Prints `state<TAB><name>`,
# then `<id><TAB><count>` for each id in RF_REPORTED, where count is 1 plus the
# highest rule_counts[id].session on gate_evaluated events of this state and
# SHIRABE_GATE_NAME. Returns non-zero, printing nothing, when the log can't be
# read: missing, not a schema-version-1 koto log, or no transition to name the
# state. jq's own message can quote the log, so it is discarded with its file.
rf_ladder_counts() {
    local log=${SHIRABE_GATE_LOG:-} err out rc
    [ -n "$log" ] && [ -n "${SHIRABE_GATE_NAME:-}" ] && [ -f "$log" ] && [ -r "$log" ] || return 1
    err=$(mktemp "${TMPDIR:-/tmp}/rule-findings.XXXXXX") || return 1
    out=$(jq -R -n -r --arg gate "$SHIRABE_GATE_NAME" --arg ids "$RF_REPORTED" '
        [inputs | fromjson?] as $ev
        | if ($ev | length) == 0 or ($ev[0] | type) != "object"
             or $ev[0].schema_version != 1 or ($ev[0] | has("seq"))
          then error("not a koto session log") else . end
        | ([$ev[] | select(type == "object"
                           and (.type == "transitioned" or .type == "directed_transition"
                                or .type == "rewound"))
               | .payload.to | select(type == "string")] | last) as $state
        | if $state == null then error("no transition names the state") else . end
        | ("state\t\($state)"),
          (($ids | split(" ")[] | select(length > 0)) as $id
           | "\($id)\t\(1 + ([0] + [$ev[] | select(type == "object" and .type == "gate_evaluated"
                                                and .payload.state == $state
                                                and .payload.gate == $gate)
                                  | (.payload.rule_counts[$id].session // 0)
                                  | select(type == "number")] | max))")
        ' < "$log" 2> "$err")
    rc=$?
    rm -f "$err"
    [ "$rc" -eq 0 ] && [ -n "$out" ] || return 1
    printf '%s\n' "$out"
}

# rf_deliver: the ladder (see the header). Once per process; stderr only;
# returns 0.
rf_deliver() {
    local counts state field id count released top_id="" top=0 notice
    [ -z "$RF_DELIVERED" ] || return 0
    RF_DELIVERED=1
    [ -n "$RF_REPORTED" ] || return 0
    rf_ladder_active || return 0
    if counts=$(rf_ladder_counts); then
        state=$(printf '%s\n' "$counts" | awk -F'\t' '$1 == "state" { print $2; exit }')
        counts=$(printf '%s\n' "$counts" | awk -F'\t' '$1 != "state"')
    else
        echo "rule-findings: could not read koto's counts from ${SHIRABE_GATE_LOG:-<no log>}; releasing every reported rule" >&2
        state=""
        counts=$(for id in $RF_REPORTED; do printf '%s\t%s\n' "$id" "$RF_FULL_TEXT_AT"; done)
    fi
    while IFS="$RF_TAB" read -r id count; do
        [ -n "$id" ] || continue
        case "$count" in ''|*[!0-9]*) continue ;; esac
        if [ "$count" -gt "$top" ]; then
            top=$count
            top_id=$id
        fi
        [ "$count" -ge "$RF_FULL_TEXT_AT" ] || continue
        released=$("$RF_HELPER" release "$id" 2>&1 </dev/null)
        [ -z "$released" ] || printf '%s\n' "$released" >&2
        case "$released" in
            "::shirabe-rule::"*) ;;
            *) echo "rule-findings: $id's full text is at $(rf_field "$id" 2)" >&2 ;;
        esac
    done <<EOF
$counts
EOF
    [ -n "$state" ] && [ -n "$top_id" ] && [ "$top" -ge "$RF_EXIT_AT" ] || return 0
    field=$(rf_exit_field "$state")
    [ -n "$field" ] || return 0
    notice=$(jq -cn --arg id "$top_id" --argjson n "$top" --arg state "$state" --arg field "$field" '
        {rule_id: $id, count: $n, state: $state,
         submit: {($field): "check_unsatisfiable",
                  check_exit_reason: "<why the check cannot be satisfied>"},
         ends_at: "done_blocked"}') || return 0
    printf '::shirabe-check-exit::%s\n' "$notice" >&2
    return 0
}

rf_finding() {
    local id=$1 detail=$2 path=${3-} line=${4-} ref summary json
    # A refusal inside a command substitution ends only the subshell; `|| exit
    # 2` carries the could-not-decide out to the caller's exit code.
    ref=$(rf_ref "$id") || exit 2
    summary=$(rf_summary "$id") || exit 2
    json=$(jq -cn --arg id "$id" --arg ref "$ref" --arg summary "$summary" --arg detail "$detail" \
        --arg path "$path" --arg line "$line" '
        {rule_id: $id, level: "error",
         message: ($summary + ": " + ($detail | gsub("[\u0000-\u001f\u007f]"; " "))),
         rule_ref: $ref}
        + (if $path != "" then {path: $path} else {} end)
        + (if $path != "" and ($line | test("^[1-9][0-9]*$")) then {line: ($line | tonumber)} else {} end)') \
        || undecided "could not build the finding for rule $id"
    rf_emit "$json"
}
