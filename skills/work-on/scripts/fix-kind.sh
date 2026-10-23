#!/usr/bin/env bash
# fix-kind.sh -- for /work-on: decide whether a unit is a fix, record it, and
# never let a fix become a change again.
#
# A unit's kind (`change` or `fix`, references/red-first.md) lives in the
# rebindable template variable UNIT_KIND, which koto routes on at
# fix_determination, and in a per-run ledger, the context key
# `fix_kind.jsonl`. This script is the one way the kind changes: it rebinds the
# variable and appends to the ledger in the same call, so the two agree after
# every exit, as review-level.sh does for REVIEW_LEVEL.
#
# Usage:
#   fix-kind.sh resolve  <session> [--current <kind>] [--issue <n>] [--issue-repo <owner/name>]
#                        [--fix-report <text>] [--task-log <file>]
#   fix-kind.sh declare  <session> --reason <text>
#   fix-kind.sh withdraw <session> [--reason <text>]
#   fix-kind.sh agree    <session> <kind>
#   fix-kind.sh kind     <session>
#
#   resolve   fix_determination's default action. A unit is a fix when its
#             issue carries a label the repository's `## Fix Labels:`
#             declaration lists (CLAUDE.md read at impl_base; `bug` when it
#             declares none), or when --fix-report is non-empty (a plan
#             step's `**Fixes**:` line, passed as FIX_REPORT). Its source is
#             `label:<name>` or `step`. With no determination yet it records
#             one, fix or change. A later run adds a fix over a recorded
#             change, never the other way: a recorded fix stays a fix whatever
#             the labels say now. Otherwise it changes nothing, except that an
#             empty --current (UNIT_KIND reset by an attach that didn't pass
#             it) is rebound to the ledger's kind. A non-empty --current that
#             disagrees with the ledger is left alone, so `agree` holds the
#             run. It also stores the unit's report once, as `fix_report.txt`:
#             --fix-report when given, else the issue body, else the
#             free-form task text from --task-log (the session's event log),
#             else the session's `context.md`.
#   declare   run by the agent at fix_determination, or at analysis on a
#             return there: records the unit as a fix with source `declared`
#             and the reason. On a unit already recorded as a fix it writes no
#             line and rebinds UNIT_KIND to `fix`, which clears a hand
#             rebind's hold. Refused (exit 1) from any other state, since a
#             fix declared after fix_determination would skip its red.
#   withdraw  an attempt to make a fix a change. Always refused for a fix
#             (exit 1, a `refused:` line naming the recorded source, and a
#             `refuse` line in the ledger); on a change there is nothing to
#             withdraw (exit 0).
#   agree     the kind_unchanged gate. Read-only. Passes when <kind> (the
#             variable) equals the ledger's last kind; holds otherwise with a
#             `hold:` line naming both.
#   kind      the ledger's last kind, or nothing. Read-only.
#
# Ledger lines (JSON, one per line): `determine` (kind, source, sources,
# fix_labels, labels_from, report_source), `declare` (kind fix, source
# declared, reason), `refuse` (action withdraw, kind, source, reason). Every
# line has `ts` and `event`.
#
# Environment (tests only):
#   FIX_KIND_TEMPLATE  the template the rebind attaches with; default
#                      ../koto-templates/work-on.md beside this script.
#
# Exit codes:
#   0  -- recorded, unchanged, or the gate passes
#   1  -- refused (withdraw, or declare outside its states), or agree holds
#   64 -- usage: unknown subcommand, a bad session name, kind or flag, or a
#         CLAUDE.md that declares `## Fix Labels:` twice
#   66 -- a koto call failed (the rebind, a context read or write, the
#         state read), or the issue couldn't be read with gh. After 66
#         neither the variable nor the ledger has changed
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT_SELF=$(cd "$SKILL_DIR/../.." && pwd)
TEMPLATE="${FIX_KIND_TEMPLATE:-$SKILL_DIR/koto-templates/work-on.md}"

LEDGER=fix_kind.jsonl
REPORT_KEY=fix_report.txt
REASON_MAX=300
DEFAULT_FIX_LABELS=bug
# The states a fix may be declared in: before implementation, and on a return
# to analysis, which passes these again on its way to fix_determination.
DECLARE_STATES=" analysis offload_canary offload_arm_withheld offload_arm_preloaded review_level_choice fix_determination "

# shellcheck source=../../../scripts/lib/claude-md-header.sh
. "$PLUGIN_ROOT_SELF/scripts/lib/claude-md-header.sh" || { echo "fix-kind: cannot load scripts/lib/claude-md-header.sh" >&2; exit 64; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fix-kind.XXXXXX") || { echo "fix-kind: could not create a temporary directory" >&2; exit 66; }
trap 'rm -rf "$WORK"' EXIT
# What the tools printed on stderr where a failure is expected (a key that
# doesn't exist yet, a probe), kept rather than discarded, and shown when the
# script gives up.
ERRLOG="$WORK/tool-stderr.log"
: > "$ERRLOG"

die() {
    echo "fix-kind: $2" >&2
    if [ -s "$ERRLOG" ]; then
        echo "fix-kind: the tools' last diagnostics:" >&2
        tail -n 5 "$ERRLOG" >&2
    fi
    exit "$1"
}

usage() {
    die 64 "$1
usage: fix-kind.sh resolve  <session> [--current <kind>] [--issue <n>] [--issue-repo <owner/name>] [--fix-report <text>] [--task-log <file>]
       fix-kind.sh declare  <session> --reason <text>
       fix-kind.sh withdraw <session> [--reason <text>]
       fix-kind.sh agree    <session> <kind>
       fix-kind.sh kind     <session>"
}

valid_session() {
    case "$1" in
        ""|-*|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

valid_kind() {
    case "$1" in change|fix) return 0 ;; esac
    return 1
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# clean <text>: control characters (newlines included) become spaces, capped.
clean() {
    printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c "1-$REASON_MAX"
}

ctx_get() {
    : > "$3"
    if koto context exists "$1" "$2" >/dev/null 2>>"$ERRLOG"; then
        koto context get "$1" "$2" > "$3" 2>>"$ERRLOG" || return 1
    fi
    return 0
}

ctx_put() {
    koto context add "$1" "$2" < "$3" >/dev/null 2>>"$ERRLOG" || return 1
    koto context get "$1" "$2" > "$WORK/readback" 2>>"$ERRLOG" || return 1
    cmp -s "$3" "$WORK/readback"
}

# last_kind <ledger-file>: the kind of the last determine or declare line.
last_kind() {
    jq -Rr 'fromjson? | select(type == "object" and (.event == "determine" or .event == "declare")) | .kind // ""' "$1" | tail -n 1
}

# last_source <ledger-file>: the source behind the ledger's kind. For a fix,
# the first line that made it one; for a change, the last line.
last_source() {
    local k
    k=$(last_kind "$1")
    if [ "$k" = fix ]; then
        jq -Rr 'fromjson? | select(type == "object" and (.event == "determine" or .event == "declare") and .kind == "fix") | .source // ""' "$1" | head -n 1
    else
        jq -Rr 'fromjson? | select(type == "object" and (.event == "determine" or .event == "declare")) | .source // ""' "$1" | tail -n 1
    fi
}

# append <session> <ledger-file> <line-file>: the ledger plus one line, read back.
append() {
    cat "$2" "$3" > "$WORK/ledger.next"
    ctx_put "$1" "$LEDGER" "$WORK/ledger.next"
}

REBIND_ERR=""
# rebind <session> <kind>: 0 when koto reports UNIT_KIND at <kind>.
#
# An attach re-applies every rebind variable from its own arguments and resets
# the ones it leaves out, so this passes all of work-on.md's: PLUGIN_ROOT (the
# plugin this script ships in) and REVIEW_LEVEL (the review-level ledger's
# last level), beside UNIT_KIND.
rebind() {
    local s="$1" k="$2" reply rc lvl rebind_detail
    set -- --var "UNIT_KIND=$k"
    if grep -q '^  PLUGIN_ROOT:' "$TEMPLATE" 2>>"$ERRLOG"; then
        set -- "$@" --var "PLUGIN_ROOT=$PLUGIN_ROOT_SELF"
    fi
    if grep -q '^  REVIEW_LEVEL:' "$TEMPLATE" 2>>"$ERRLOG"; then
        lvl=$("$SCRIPT_DIR/review-level.sh" level "$s" 2>"$WORK/level.err") || {
            REBIND_ERR="could not read the review level to carry it through the rebind: $(head -c 300 "$WORK/level.err")"
            return 1
        }
        set -- "$@" --var "REVIEW_LEVEL=$lvl"
    fi
    reply=$(koto init "$s" --template "$TEMPLATE" --attach-live "$@" 2>"$WORK/rebind.err")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        rebind_detail=$(head -c 400 "$WORK/rebind.err")
        REBIND_ERR="koto init --attach-live exited $rc: ${reply:0:400} $rebind_detail"
        return 1
    fi
    if printf '%s' "$reply" | jq -e --arg k "$k" \
        '.outcome == "attached"
         and (((.rebound // {}) | has("UNIT_KIND") | not) or .rebound.UNIT_KIND == $k)' >/dev/null 2>>"$ERRLOG"; then
        return 0
    fi
    REBIND_ERR="koto did not report UNIT_KIND rebound to [$k]: ${reply:0:400}"
    return 1
}

# record <session> <kind> <line-file> <old-kind>: rebind, then append; a
# failed append rebinds back, so variable and ledger never part. The rebind
# goes first because it is the step that can be undone: a ledger line, once
# appended, is the record, and a fix in it can't be taken back, so it is
# written only after the variable already says the same thing.
record() {
    local s="$1" k="$2" line="$3" old="$4"
    rebind "$s" "$k" || die 66 "$REBIND_ERR"
    if ! append "$s" "$WORK/ledger" "$line"; then
        rebind "$s" "$old" || true
        die 66 "could not write $LEDGER; UNIT_KIND was put back to [${old:-empty}]"
    fi
}

hold() {
    echo "hold: $1"
    exit 1
}

refuse() {
    echo "refused: $1"
    exit 1
}

# ------------------------------------------------------------------ report ----

# snapshot_report <session> <fix-report> <issue-body-file> <task-log>: stores
# the unit's report once, and prints where it came from (or nothing when it
# was already stored or none exists).
snapshot_report() {
    local s="$1" fr="$2" body="$3" log="$4" src=""
    if koto context exists "$s" "$REPORT_KEY" >/dev/null 2>>"$ERRLOG"; then
        return 0
    fi
    : > "$WORK/report"
    if [ -n "$fr" ]; then
        printf '%s\n' "$fr" > "$WORK/report"; src=fix_report
    elif [ -s "$body" ]; then
        cat "$body" > "$WORK/report"; src=issue
    elif [ -n "$log" ] && [ -r "$log" ] \
        && jq -Rr 'fromjson? | select(type == "object" and .type == "evidence_submitted" and .payload.state == "entry")
                   | .payload.fields.task_description // empty' "$log" 2>>"$ERRLOG" | head -n 1 | grep -q .; then
        jq -Rr 'fromjson? | select(type == "object" and .type == "evidence_submitted" and .payload.state == "entry")
                | .payload.fields.task_description // empty' "$log" | head -n 1 > "$WORK/report"
        src=task
    else
        ctx_get "$s" context.md "$WORK/report" || return 1
        [ -s "$WORK/report" ] && src=context
    fi
    [ -n "$src" ] || return 0
    ctx_put "$s" "$REPORT_KEY" "$WORK/report" || return 1
    printf '%s\n' "$src"
}

# ----------------------------------------------------------------- resolve ----

cmd_resolve() {
    [ $# -ge 1 ] || usage "resolve takes <session>"
    local s="$1" current="" issue="" repo="" fr="" log=""
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --current) [ $# -ge 2 ] || usage "--current needs a value"; current="$2"; shift 2 ;;
            --issue) [ $# -ge 2 ] || usage "--issue needs a value"; issue="$2"; shift 2 ;;
            --issue-repo) [ $# -ge 2 ] || usage "--issue-repo needs a value"; repo="$2"; shift 2 ;;
            --fix-report) [ $# -ge 2 ] || usage "--fix-report needs a value"; fr="$2"; shift 2 ;;
            --task-log) [ $# -ge 2 ] || usage "--task-log needs a value"; log="$2"; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    [ -z "$current" ] || valid_kind "$current" || usage "--current [$current] is not change or fix"
    case "$issue" in *[!0-9]*) usage "--issue [$issue] is not a number" ;; esac
    case "$repo" in
        "") ;;
        -*|/*|*/|*/*/*|*[!A-Za-z0-9_./-]*) usage "--issue-repo [$repo] is not owner/name" ;;
        */*) ;;
        *) usage "--issue-repo [$repo] is not owner/name" ;;
    esac

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    local last
    last=$(last_kind "$WORK/ledger")

    # The repository's fix labels, from CLAUDE.md at the run's base.
    local base labels_from fix_labels decl rc
    ctx_get "$s" impl_base "$WORK/base" || die 66 "could not read impl_base"
    base=$(tr -d '[:space:]' < "$WORK/base")
    [ -n "$base" ] || base=HEAD
    decl=$(claude_md_header_at "$base" 'Fix Labels' 2>"$WORK/hdr.err")
    rc=$?
    case "$rc" in
        0) fix_labels="$decl"; labels_from="CLAUDE.md" ;;
        1) fix_labels="$DEFAULT_FIX_LABELS"; labels_from=default ;;
        *) die 64 "$(cat "$WORK/hdr.err")" ;;
    esac

    # The issue's labels and body, when there is an issue.
    : > "$WORK/labels"
    : > "$WORK/body"
    if [ -n "$issue" ]; then
        if [ -n "$repo" ]; then
            gh issue view "$issue" --repo "$repo" --json labels,body > "$WORK/issue.json" 2>"$WORK/gh.err" \
                || die 66 "could not read issue $issue with gh: $(head -c 300 "$WORK/gh.err")"
        else
            gh issue view "$issue" --json labels,body > "$WORK/issue.json" 2>"$WORK/gh.err" \
                || die 66 "could not read issue $issue with gh: $(head -c 300 "$WORK/gh.err")"
        fi
        jq -r '.labels[]?.name // empty' "$WORK/issue.json" > "$WORK/labels" 2>>"$ERRLOG" \
            || die 66 "gh returned something that isn't an issue for $issue"
        jq -r '.body // ""' "$WORK/issue.json" > "$WORK/body" 2>>"$ERRLOG" || true
    fi

    # Every source that makes the unit a fix, in a fixed order: labels in the
    # declaration's order, then the step's Fixes line.
    local sources="" lbl want
    while IFS= read -r lbl; do
        lbl=$(printf '%s' "$lbl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$lbl" ] || continue
        if grep -Fxiq -- "$lbl" "$WORK/labels"; then
            sources="$sources
label:$(grep -Fxi -- "$lbl" "$WORK/labels" | head -n 1)"
        fi
    done <<EOF
$(printf '%s\n' "$fix_labels" | tr ',' '\n')
EOF
    [ -z "$fr" ] || sources="$sources
step"
    sources=$(printf "%s" "$sources" | sed "/^$/d")
    if [ -n "$sources" ]; then want=fix; else want=change; fi

    # The report is stored on every path, once: a fix declared at analysis
    # before this ever ran still needs one for its red.
    local src rsrc
    src=$(head -n 1 <<<"$sources")
    rsrc=$(snapshot_report "$s" "$fr" "$WORK/body" "$log") || die 66 "could not store $REPORT_KEY"
    if [ -z "$last" ] || { [ "$last" = change ] && [ "$want" = fix ]; }; then
        jq -nc --arg ts "$(now)" --arg kind "$want" --arg source "${src:-none}" --arg sources "$sources" \
            --arg fl "$fix_labels" --arg lf "$labels_from" --arg rs "$rsrc" \
            '{ts: $ts, event: "determine", kind: $kind, source: $source,
              sources: ($sources | split("\n") | map(select(. != ""))),
              fix_labels: $fl, labels_from: $lf}
             + (if $rs == "" then {} else {report_source: $rs} end)' > "$WORK/line"
        record "$s" "$want" "$WORK/line" "${last}"
        if [ -z "$last" ]; then
            echo "recorded: $want (source ${src:-none})"
        else
            echo "recorded: fix (source $src), over the earlier change"
        fi
        exit 0
    fi

    # A determination stands. Restore a variable an attach reset; leave a
    # non-empty one alone, so a hand rebind holds at kind_unchanged.
    if [ -z "$current" ]; then
        rebind "$s" "$last" || die 66 "$REBIND_ERR"
        echo "restored: UNIT_KIND=$last from the ledger"
    else
        echo "unchanged: $last (source $(last_source "$WORK/ledger"))"
    fi
    if [ "$last" = fix ] && [ "$want" = change ]; then
        echo "note: no fix label or Fixes line marks the unit now; it stays a fix, since a fix determination is never withdrawn"
    fi
    exit 0
}

# ----------------------------------------------------------------- declare ----

cmd_declare() {
    [ $# -ge 1 ] || usage "declare takes <session> --reason <text>"
    local s="$1" reason="" has_reason=0
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) [ $# -ge 2 ] || usage "--reason needs a value"; reason="$2"; has_reason=1; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    [ "$has_reason" -eq 1 ] || usage "declare needs --reason"
    reason=$(clean "$reason")
    [ -n "$(printf '%s' "$reason" | tr -d ' ')" ] || usage "--reason is empty"

    local state
    state=$(koto status "$s" 2>>"$ERRLOG" | jq -r '.current_state // empty' 2>>"$ERRLOG")
    [ -n "$state" ] || die 66 "could not read the session's state with koto status"
    case "$DECLARE_STATES" in
        *" $state "*) ;;
        *) refuse "a fix is declared at fix_determination, or at analysis on a return there (and the states between the two); the run is at $state, past the point its red would come first. Return to analysis (scope_expanded_retry) and declare it there" ;;
    esac

    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    local last
    last=$(last_kind "$WORK/ledger")
    if [ "$last" = fix ]; then
        rebind "$s" fix || die 66 "$REBIND_ERR"
        echo "unchanged: already a fix (source $(last_source "$WORK/ledger")); UNIT_KIND is fix"
        exit 0
    fi
    # No report is stored here: resolve stores it at fix_determination, which
    # every route to the red passes after a declaration.
    jq -nc --arg ts "$(now)" --arg reason "$reason" \
        '{ts: $ts, event: "declare", kind: "fix", source: "declared", reason: $reason}' > "$WORK/line"
    record "$s" fix "$WORK/line" "$last"
    echo "recorded: fix (source declared)"
    exit 0
}

# ---------------------------------------------------------------- withdraw ----

cmd_withdraw() {
    [ $# -ge 1 ] || usage "withdraw takes <session>"
    local s="$1" reason=""
    shift
    valid_session "$s" || usage "bad session name [$s]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) [ $# -ge 2 ] || usage "--reason needs a value"; reason="$2"; shift 2 ;;
            *) usage "unknown argument [$1]" ;;
        esac
    done
    reason=$(clean "$reason")
    ctx_get "$s" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    local last src
    last=$(last_kind "$WORK/ledger")
    if [ "$last" != fix ]; then
        echo "unchanged: nothing to withdraw; the unit is recorded as ${last:-nothing yet}"
        exit 0
    fi
    src=$(last_source "$WORK/ledger")
    jq -nc --arg ts "$(now)" --arg source "$src" --arg reason "$reason" \
        '{ts: $ts, event: "refuse", action: "withdraw", kind: "fix", source: $source, reason: $reason}' > "$WORK/line"
    append "$s" "$WORK/ledger" "$WORK/line" || die 66 "could not write $LEDGER"
    refuse "the unit is a fix (source $src), and a fix determination can't be withdrawn"
}

# ------------------------------------------------------------------- agree ----

cmd_agree() {
    [ $# -eq 2 ] || { echo "hold: agree takes <session> <kind>"; exit 1; }
    local s="$1" k="$2" last src
    valid_session "$s" || hold "bad session name [$s]"
    [ -z "$k" ] || valid_kind "$k" || hold "UNIT_KIND [$k] is not change or fix"
    ctx_get "$s" "$LEDGER" "$WORK/ledger" || hold "could not read $LEDGER"
    last=$(last_kind "$WORK/ledger")
    if [ -n "$k" ] && [ "$k" = "$last" ]; then
        echo "pass: UNIT_KIND $k matches the ledger"
        exit 0
    fi
    [ -n "$last" ] || hold "no determination is recorded yet; the next tick's action records it"
    src=$(last_source "$WORK/ledger")
    [ -n "$k" ] || hold "UNIT_KIND was bound to $last on this tick and koto routes on it from the next one; tick again"
    if [ "$last" = fix ]; then
        hold "UNIT_KIND is $k but the ledger records a fix (source $src), which can't be withdrawn. Put the variable back with fix-kind.sh declare $s --reason <why>"
    fi
    hold "UNIT_KIND is $k but the ledger records a change. A fix is recorded only through fix-kind.sh declare $s --reason <why>"
}

cmd_kind() {
    [ $# -eq 1 ] || usage "kind takes <session>"
    valid_session "$1" || usage "bad session name [$1]"
    ctx_get "$1" "$LEDGER" "$WORK/ledger" || die 66 "could not read $LEDGER"
    last_kind "$WORK/ledger"
    exit 0
}

command -v jq >/dev/null || die 66 "jq is not on PATH"
[ $# -ge 1 ] || usage "no subcommand"
sub="$1"
shift
case "$sub" in
    resolve)  cmd_resolve "$@" ;;
    declare)  cmd_declare "$@" ;;
    withdraw) cmd_withdraw "$@" ;;
    agree)    cmd_agree "$@" ;;
    kind)     cmd_kind "$@" ;;
    *) usage "unknown subcommand [$sub]" ;;
esac
