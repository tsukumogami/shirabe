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
#                              prints and logs nothing. A block stage adds one
#                              to RF_BLOCKING. RF_COUNTED is 1 after a finding
#                              that counted toward RF_BLOCKING and 0 otherwise
#   rf_dispute_hint            one line on standard error telling the agent how
#                              to dispute a finding with scripts/rule-dispute.sh,
#                              for a script about to exit non-zero on block
#                              findings. The script knows neither its session
#                              nor its gate, so the line names them as
#                              placeholders the agent fills from the koto
#                              response it holds
#
# Stages. A rule's stage (`scripts/rule-registry.sh stage`) decides how its
# findings print, not whether the check runs: the check still runs and its
# finding is still built and validated, then printed at the stage's level, or
# not at all at `retired`. RF_BLOCKING counts the findings that printed at
# `block`; it is the count for a gate script's exit to read, so a rule below
# block can report without holding the gate. The counters live in the script's main shell, so
# findings must be printed from it, not from a subshell or a pipeline.
#
# Every printed finding also goes to `scripts/rule-registry.sh log-finding`,
# which appends it to $SHIRABE_FINDINGS_LOG when that names a safe file; the
# gate scripts' test suites use the log to verify what they printed.
#
# Written for the bash 3.2 floor: no associative arrays, so the resolved refs,
# summaries and stages are kept as tab-separated lines.

RF_HELPER="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/rule-registry.sh"
RF_ROOT=$(dirname -- "$(dirname -- "$RF_HELPER")")
RF_CACHE=""
RF_TAB=$(printf '\t')
RF_BLOCKING=0
RF_COUNTED=0

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
# verify-findings; change both together.
rf_level() {
    case "$1" in
        warn) printf 'warning' ;;
        shadow) printf 'info' ;;
        retired) return 1 ;;
        *) printf 'error' ;;
    esac
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
    "$RF_HELPER" log-finding "$line" </dev/null >/dev/null 2>&1 || true
    if [ "$stage" = block ]; then
        RF_BLOCKING=$((RF_BLOCKING + 1))
        RF_COUNTED=1
    fi
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
