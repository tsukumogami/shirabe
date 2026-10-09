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
#                              once, not only when a violation turns up.
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
#
# Every printed finding also goes to `scripts/rule-registry.sh log-finding`,
# which appends it to $SHIRABE_FINDINGS_LOG when that names a safe file; the
# gate scripts' test suites use the log to verify what they printed.
#
# Written for the bash 3.2 floor: no associative arrays, so the resolved refs
# and summaries are kept as tab-separated lines.

RF_HELPER="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/rule-registry.sh"
RF_CACHE=""
RF_TAB=$(printf '\t')

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
}

rf_finding() {
    local id=$1 detail=$2 path=${3-} line=${4-} ref summary json
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
