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
#                              with control characters replaced; it goes
#                              through rf_emit, so its level and counting are
#                              rf_emit's (below)
#   rf_ref <id>, rf_summary <id>, rf_stage <id>
#                              the resolved reference, summary or stage, for a
#                              script that builds its finding objects itself or
#                              decides by a rule's stage; each calls
#                              `undecided` for an id rf_require didn't resolve.
#                              A script building findings must prefix the
#                              message and replace control characters as
#                              rf_finding does (panel-scope.sh --verdict is the
#                              one that does)
#   rf_level <stage>           the finding level a stage prints at: block is
#                              error, warn is warning, shadow is info; retired
#                              prints nothing and returns 1
#   rf_emit <json> [<stage-id>]
#                              prints a finding object the script built and logs
#                              it, at the level of <stage-id>'s stage (default:
#                              the finding's own rule_id); refuses (`undecided`)
#                              one whose rule_id was not resolved, whose
#                              rule_ref differs from the resolved one, whose
#                              message lacks the summary prefix, or whose
#                              <stage-id> was not resolved. A retired stage
#                              prints and logs nothing. Every finding it
#                              prints adds one to RF_PRINTED, so a script
#                              that reports what it printed counts no retired
#                              finding. A block stage adds one
#                              to RF_BLOCKING and records the rule for the
#                              ladder. RF_COUNTED is 1 after a finding that
#                              counted toward RF_BLOCKING and 0 otherwise
#   rf_deliver                 the escalation ladder, below; called once, right
#                              before the script's non-zero exit that follows
#                              its findings
#   rf_release <id>            `rule-registry.sh release <id>`, the rule's full
#                              text on standard error, plus its delivery
#                              marker (below) on standard output; returns 0
#                              when the text printed and 1 when release
#                              refused it. For a script that releases a rule's
#                              text itself, outside the ladder
#   rf_dispute_hint            one line on standard error telling the agent how
#                              to dispute a finding with scripts/rule-dispute.sh,
#                              for a script about to exit non-zero on block
#                              findings. The script knows neither its session
#                              nor its gate, so the line names them as
#                              placeholders the agent fills from the koto
#                              response it holds
#
# Stages. A rule's stage, read with its ref and summary in one
# `scripts/rule-registry.sh resolve` call per rule, decides how its findings
# print, not whether the check runs: the check still runs and its finding is
# still built and validated, then printed at the stage's level, or not at all
# at `retired`. RF_BLOCKING counts the findings that printed at `block`; it is
# the count for a gate script's exit to read, so a rule below block can report
# without holding the gate. The counters live in the script's main shell, so
# findings must be printed from it, not from a subshell or a pipeline.
#
# Every printed finding also goes to `scripts/rule-registry.sh log-finding`,
# which appends it to $SHIRABE_FINDINGS_LOG when that names a safe file; the
# gate scripts' test suites use the log to verify what they printed.
#
# The escalation ladder. rf_emit records in RF_REPORTED every rule id it prints
# at block: those are the findings that fail the gate and that koto counts.
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
#   SHIRABE_GATE_EXITS  "<state>:<status field> ...", the states with a named exit;
#                       a status field is lowercase letters and `_` only, and
#                       an entry with any other field offers no exit
#   SHIRABE_GATE_EXIT_END  optional: the state the named exit ends the run at,
#                       which the exit notice prints as `ends_at`. Unset, or
#                       anything but lowercase letters and `_`, gives
#                       `done_blocked`, where /work-on's exit ends; /scope's
#                       ends at `exit_abandonment`
#
# The state is read from the log (the last transition's `to`), never from the
# command. Without SHIRABE_GATE_LOG and SHIRABE_GATE_NAME, rf_deliver does
# nothing and the script prints what it always printed. With them, a log the
# ladder can't read puts every reported rule at RF_FULL_TEXT_AT and offers no
# exit.
# rf_deliver always returns 0 and writes the rule text and its notices only to
# standard error, so it never changes a gate's exit status or the findings koto
# records; on standard output it adds only the delivery markers below.
# DESIGN-validate-and-return.md has the reasoning.
#
# Delivery markers. For telemetry, every rule delivery prints one line on
# standard output, which koto records as a rule delivery:
#
#   ::koto-rule-delivered::{"rule_id":"<id>","extent":"<extent>","delivery":"<delivery>"}
#
#   extent summary, delivery printed   beside each finding rf_emit prints (a
#                                      retired finding prints none)
#   extent full, delivery printed      beside each full-text release that
#                                      printed the text (rf_release)
#   extent full, delivery refused      beside each release that refused it
#
# Only a rule this run resolved gets one; an id it didn't resolve prints no
# marker. A koto without marker support ignores the line. koto reads a marker
# only at the start of a line, and every line this library prints on standard
# output starts with its own marker, so text from a finding's detail can't
# start one.
#
# Written for the bash 3.2 floor: no associative arrays, so the resolved refs,
# summaries and stages are kept as tab-separated lines.

RF_HELPER="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/rule-registry.sh"
RF_ROOT=$(dirname -- "$(dirname -- "$RF_HELPER")")
RF_CACHE=""
RF_TAB=$(printf '\t')
RF_BLOCKING=0
RF_PRINTED=0
RF_COUNTED=0
RF_REPORTED=""
RF_DELIVERED=""
RF_FULL_TEXT_AT=2
RF_EXIT_AT=3

# rf_cache_add <id>: one `rule-registry.sh resolve` call, which prints the ref,
# summary and stage tab-separated, appended to RF_CACHE as
# "<id> <ref> <summary> <stage>". One call per rule rather than one per field:
# each call reads the registry and runs git, and check-hop-document.sh already
# resolves late to keep that cost down.
rf_cache_add() {
    local id=$1 out ref summary stage rest
    out=$("$RF_HELPER" resolve "$id" 2>&1) || undecided "cannot resolve rule $id: $out"
    # The reader prints exactly three fields and fails closed to block for a
    # stage it doesn't know, so anything else is a reader this library doesn't
    # match.
    case "$out" in
        *"$RF_TAB"*"$RF_TAB"*"$RF_TAB"*) undecided "rule $id resolved to more than a ref, a summary and a stage" ;;
        *"$RF_TAB"*"$RF_TAB"*) ;;
        *) undecided "rule $id resolved to [$out], not a ref, a summary and a stage" ;;
    esac
    ref=${out%%"$RF_TAB"*}
    rest=${out#*"$RF_TAB"}
    summary=${rest%%"$RF_TAB"*}
    stage=${rest#*"$RF_TAB"}
    [ -n "$ref" ] && [ -n "$summary" ] || undecided "rule $id resolved to an empty ref or summary"
    case "$stage" in
        block|warn|shadow|retired) ;;
        *) undecided "rule $id resolved to the unknown stage [$stage]" ;;
    esac
    RF_CACHE="$RF_CACHE$id$RF_TAB$ref$RF_TAB$summary$RF_TAB$stage
"
}

rf_require() {
    local id
    [ -x "$RF_HELPER" ] || undecided "the rule registry reader $RF_HELPER is not executable"
    for id in "$@"; do
        case " $RULE_IDS " in
            *" $id "*) ;;
            *) undecided "rule $id is not in this script's RULE_IDS" ;;
        esac
        rf_cache_add "$id"
    done
}

rf_require_any() {
    local id
    [ "${RULE_IDS_ANY_ACTIVE:-}" = 1 ] \
        || undecided "rf_require_any needs RULE_IDS_ANY_ACTIVE=1 in the calling script"
    [ -x "$RF_HELPER" ] || undecided "the rule registry reader $RF_HELPER is not executable"
    for id in "$@"; do
        # Already resolved this run: a second lookup would read the same entry.
        [ -z "$(rf_field "$id" 2)" ] || continue
        rf_cache_add "$id"
    done
}

# rf_field <id> <2|3|4>: the cached ref (2), summary (3) or stage (4), or
# nothing.
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

rf_stage() {
    local v
    v=$(rf_field "$1" 4)
    [ -n "$v" ] || undecided "rule $1 was not resolved by rf_require in this run"
    printf '%s' "$v"
}

# rf_level <stage>. The cache only ever holds the four stages. Anything else a
# caller passes gets error, block's level, so a value this library doesn't know
# never prints a finding softer than every finding printed before stages.
# scripts/rule-registry.sh's stage_level holds the same mapping for
# verify-findings, and rule-findings-testlib.sh's rf_test_level the suites'
# copy; scripts/rule-registry_test.sh fails when the three differ.
rf_level() {
    case "$1" in
        warn) printf 'warning' ;;
        shadow) printf 'info' ;;
        retired) return 1 ;;
        *) printf 'error' ;;
    esac
}

# rf_delivered <id> <extent> <delivery>: the delivery marker (see the header)
# on standard output, for a rule this run resolved; nothing for any other id.
# The caller passes extent and delivery from the header's fixed values.
rf_delivered() {
    local line
    [ -n "$(rf_field "$1" 2)" ] || return 0
    line=$(jq -cn --arg id "$1" --arg extent "$2" --arg delivery "$3" \
        '{rule_id: $id, extent: $extent, delivery: $delivery}' 2>/dev/null) || return 0
    printf '::koto-rule-delivered::%s\n' "$line"
}

# rf_release <id>: the rule's full text through `rule-registry.sh release`,
# which writes only to standard error and always exits 0: its
# ::shirabe-rule:: marker line first when it printed the text, its one
# `could not release` line otherwise (references/rule-registry.md,
# "Delivering a rule when it applies"). The marker is how the two are told
# apart. Returns 0 when the text printed, 1 when release refused it.
rf_release() {
    local id=$1 released
    released=$("$RF_HELPER" release "$id" 2>&1 </dev/null)
    [ -z "$released" ] || printf '%s\n' "$released" >&2
    case "$released" in
        "::shirabe-rule::"*)
            rf_delivered "$id" full printed
            return 0
            ;;
    esac
    rf_delivered "$id" full refused
    return 1
}

rf_emit() {
    local json=$1 source=${2-} id ref msg want_ref want_summary stage level line
    RF_COUNTED=0
    id=$(printf '%s' "$json" | jq -r '.rule_id // ""' 2>/dev/null)
    ref=$(printf '%s' "$json" | jq -r '.rule_ref // ""' 2>/dev/null)
    msg=$(printf '%s' "$json" | jq -r '.message // ""' 2>/dev/null)
    want_ref=$(rf_field "$id" 2)
    want_summary=$(rf_field "$id" 3)
    [ -n "$id" ] && [ -n "$want_ref" ] || undecided "a finding names rule [$id], which this run did not resolve"
    [ -n "$source" ] || source=$id
    stage=$(rf_field "$source" 4)
    [ -n "$stage" ] || undecided "a finding for $id takes its stage from rule [$source], which this run did not resolve"
    [ "$ref" = "$want_ref" ] || undecided "a finding for $id carries rule_ref [$ref], not [$want_ref]"
    case "$msg" in
        "$want_summary: "*) ;;
        *) undecided "a finding for $id does not start with the rule's summary" ;;
    esac
    # At retired the check still ran and the finding was still validated
    # above; it just isn't shown, logged or counted.
    level=$(rf_level "$stage") || return 0
    json=$(printf '%s' "$json" | jq -c --arg level "$level" '.level = $level' 2>/dev/null)
    [ -n "$json" ] || undecided "could not set the level of a finding for $id"
    line="::koto-finding::$json"
    printf '%s\n' "$line"
    rf_delivered "$id" summary printed
    RF_PRINTED=$((RF_PRINTED + 1))
    "$RF_HELPER" log-finding "$line" </dev/null >/dev/null 2>&1 || true
    if [ "$stage" = block ]; then
        RF_BLOCKING=$((RF_BLOCKING + 1))
        RF_COUNTED=1
        case " $RF_REPORTED " in
            *" $id "*) ;;
            *) RF_REPORTED="${RF_REPORTED:+$RF_REPORTED }$id" ;;
        esac
    fi
    return 0
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
# state. The header is line 1 and, unlike every event, carries no `seq`
# (koto's session-feed contract), which is how a log cut from the middle or an
# event file passed by mistake is told from a real one. jq's own message can
# quote the log, so it goes to a file that is removed unread; not /dev/null,
# because scripts/check-tool-diagnostic-discards.sh refuses discarding a
# declared tool's diagnostics there. A temporary file that can't be made is
# reported like a log that can't be read.
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

# rf_deliver: the ladder (see the header). Once per process; stderr only,
# apart from the delivery markers; returns 0.
rf_deliver() {
    local counts state field id count top_id="" top=0 notice end
    [ -z "$RF_DELIVERED" ] || return 0
    [ -n "$RF_REPORTED" ] || return 0
    rf_ladder_active || return 0
    RF_DELIVERED=1
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
        rf_release "$id" \
            || echo "rule-findings: $id's full text is at $(rf_field "$id" 2)" >&2
    done <<EOF
$counts
EOF
    [ -n "$state" ] && [ -n "$top_id" ] && [ "$top" -ge "$RF_EXIT_AT" ] || return 0
    field=$(rf_exit_field "$state")
    [ -n "$field" ] || return 0
    # The end state is a template's own state name; anything else is not one,
    # and the notice falls back to the end /work-on's exit has.
    end=${SHIRABE_GATE_EXIT_END:-}
    case "$end" in
        ''|*[!a-z_]*) end=done_blocked ;;
    esac
    notice=$(jq -cn --arg id "$top_id" --argjson n "$top" --arg state "$state" --arg field "$field" \
        --arg end "$end" '
        {rule_id: $id, count: $n, state: $state,
         submit: {($field): "check_unsatisfiable",
                  check_exit_reason: "<why the check cannot be satisfied>"},
         ends_at: $end}') || return 0
    printf '::shirabe-check-exit::%s\n' "$notice" >&2
    return 0
}

rf_finding() {
    local id=$1 detail=$2 path=${3-} line=${4-} ref summary json
    # A refusal inside a command substitution ends only the subshell; `|| exit
    # 2` carries the could-not-decide out to the caller's exit code.
    ref=$(rf_ref "$id") || exit 2
    summary=$(rf_summary "$id") || exit 2
    # The level written here is a placeholder: rf_emit sets it from the stage.
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

rf_dispute_hint() {
    printf '%s: to dispute a finding you believe is wrong, run %s/scripts/rule-dispute.sh --session <session> --gate <gate> --rule <rule-id> --reason <why>; the session and gate are in the koto response\n' \
        "$(basename -- "$0")" "$RF_ROOT" >&2
}
