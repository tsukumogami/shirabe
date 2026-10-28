#!/usr/bin/env bash
# rule-registry.sh -- the one reader of references/rule-registry.json.
#
# Every rule a gate script reports, every review-shadow criterion, and every
# rule a script releases on a trigger has one entry in the registry. This script
# is how scripts read an entry: the gate scripts call `resolve` for the
# rule_ref, message prefix and stage of each finding, a trigger calls
# `release`, and the gate scripts' test suites call `verify-findings` on what
# they printed.
# references/rule-registry.md documents the fields; DESIGN-rule-registry.md
# says why the reference is computed here rather than stored.
#
# Usage:
#   rule-registry.sh [--root <dir>] [--registry <file>] <command> <arg>
#
#   ref <id>              <path>#L<first>-L<last>@<revision> for an active rule
#   summary <id>          the entry's short text
#   text <id>             the rule's lines, first to last
#   range <id>            "<first> <last>": the line numbers of the rule's text
#   withhold <id>         the entry's withhold value (never or eligible)
#   stage <id>            the effective lifecycle stage of a script-checked
#                         entry, active or retired: shadow, warn, block or
#                         retired (see "Effective stage" below)
#   resolve <id>          "<ref>\t<summary>\t<stage>" on one line, the three
#                         values ref, summary and stage print; an active entry
#                         that is not script-checked has no stage and prints
#                         block, so a rule outside the lifecycle keeps blocking
#   release <id>          the rule's lines between marker lines, on stderr;
#                         always exits 0
#   log-finding <line>    append a printed ::koto-finding:: line to
#                         $SHIRABE_FINDINGS_LOG when that names a safe file;
#                         always exits 0
#   verify-findings [--stage-source <id>] <log>
#                         check every logged finding's rule_id, rule_ref,
#                         summary prefix and level: the level must be the one
#                         its rule's stage prints at (block error, warn
#                         warning, shadow info), or <id>'s stage when given,
#                         and nothing may be logged at retired; a log with no
#                         findings fails
#
# --root and --registry exist for the tests, which point the script at a
# scratch plugin copy. No gate script passes them.
#
# The revision in a ref names the copy this script runs from:
#   <12-char commit>      a git checkout whose file matches its blob at HEAD
#   worktree              a git checkout whose file has uncommitted changes
#   vX.Y.Z                an installed release (plugin.json version X.Y.Z),
#                         which is a tag on main
#   <version>+<12-char blob>  any other installed version, such as X.Y.Z-dev;
#                         `git log --all --find-object=<blob>` finds the text
#   <version>             the same, when git is not installed
#   unknown               plugin.json's version has an unexpected shape
#
# git runs only on the plugin root, with the system and global configuration,
# hooks and the filesystem monitor disabled and the caller's GIT_* location
# variables cleared, so a configuration planted in the directory runs nothing.
# The plumbing used (rev-parse, hash-object --no-filters) runs no hook and no
# monitor anyway; those flags, and clearing GIT_CONFIG_COUNT and
# GIT_CONFIG_PARAMETERS, are defense in depth the tests can't exercise. The
# tests do show a planted clean filter not running, which --no-filters stops.
#
# Effective stage. `stage` fails closed: it prints block for a script entry
# with no stage (a registry from before the field), for a stage outside the
# four values, and for an active entry below block whose guards include a
# protected action that stage_backstops doesn't cover. A guard is covered by a
# backstop whose `before` names it and whose `check` is a regular file under
# the plugin root other than the entry's own check.path. This repeats the
# registry check's safety rule at run time, so a registry edited without
# passing CI still can't soften a guarded rule.
#
# Exit codes (ref, summary, text, stage, resolve):
#   0  printed
#   1  no such rule, or the rule is retired; for stage, no such rule or one
#      that isn't script-checked (a retired script entry prints its stage)
#   2  could not decide: unreadable registry, malformed id, unsafe path, or a
#      text whose anchors do not resolve
# verify-findings: 0 every finding checks out, 1 a finding does not, 2 could
# not read the log or the registry, or could not resolve the --stage-source
# rule.

set -u

PROG=rule-registry

# `release` and `log-finding` run beside another script's own work, and must
# never change its result. So for those two, every failure before the
# dispatch (the script can't find itself, a bad option, a missing jq) exits 0
# like a failure inside them: release still prints its one could-not-release
# line, log-finding stays silent. This is decided first, before anything that
# can fail.
RELEASE_ID=""
QUIET=""
# The command is the first word after the options, so only that position is
# read: an id or a logged line that happens to say `release` is not a command.
ARGV=("$@")
i=0
while [ $i -lt ${#ARGV[@]} ]; do
    case "${ARGV[$i]}" in
        --root|--registry) i=$((i + 2)) ;;
        --) i=$((i + 1)); break ;;
        -*) i=$((i + 1)) ;;
        *) break ;;
    esac
done
case "${ARGV[$i]-}" in
    release) RELEASE_ID=${ARGV[$((i + 1))]-} ;;
    log-finding) QUIET=1 ;;
esac
die2() {
    if [ -n "$RELEASE_ID" ]; then
        echo "$PROG: could not release $RELEASE_ID: $*" >&2
        exit 0
    fi
    [ -z "$QUIET" ] || exit 0
    echo "$PROG: $*" >&2
    exit 2
}

SELF_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) \
    || die2 "cannot find its own directory"
ROOT=$(CDPATH='' cd -P -- "$SELF_DIR/.." && pwd -P) || die2 "cannot find the plugin root"
REGISTRY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || die2 "--root needs a directory"
            ROOT=$(CDPATH='' cd -P -- "$2" 2>/dev/null && pwd -P) || die2 "--root $2 is not a directory"
            shift 2 ;;
        --registry)
            [ $# -ge 2 ] || die2 "--registry needs a file"
            REGISTRY=$2; shift 2 ;;
        --) shift; break ;;
        -*) die2 "unknown option $1" ;;
        *) break ;;
    esac
done
[ -n "$REGISTRY" ] || REGISTRY="$ROOT/references/rule-registry.json"

# verify-findings alone takes an option of its own, before its log.
STAGE_SOURCE=""
if [ "${1-}" = verify-findings ] && [ "${2-}" = --stage-source ]; then
    [ $# -eq 4 ] || die2 "usage: rule-registry.sh [--root <dir>] [--registry <file>] verify-findings [--stage-source <id>] <log>"
    STAGE_SOURCE=$3
    set -- "$1" "$4"
fi
[ $# -eq 2 ] || die2 "usage: rule-registry.sh [--root <dir>] [--registry <file>] ref|summary|text|range|withhold|stage|resolve|release|log-finding|verify-findings <arg>"
CMD=$1
ARG=$2

ID_NAMED='^[a-z0-9-]+/[a-z0-9-]+$'
ID_RS='^rs-([0-9]{3}|verdict-missing)$'
PATH_SHAPE='^[A-Za-z0-9._][A-Za-z0-9._/-]*$'
HEX40='^[0-9a-f]{40}$'
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'
VERSION_SHAPE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
RELEASE_MAX_LINES=60
MARK_OPEN='::shirabe-rule::'
MARK_CLOSE='::shirabe-rule-end::'
# The guards vocabulary less `none`, as scripts/check-rule-registry.sh has it.
PROTECTED='["pr-create","push","force-push","merge","close-issue","release","delete-branch","publish","destroy-record"]'

valid_id() {
    [[ $1 =~ $ID_NAMED ]] || [[ $1 =~ $ID_RS ]]
}

# safe_path <relative path>: prints the absolute path when the path has the
# allowed shape, no `..` segment, is not a symlink, and resolves to a regular
# file under ROOT; returns 1 otherwise.
safe_path() {
    local p=$1 dir base full
    [[ $p =~ $PATH_SHAPE ]] || return 1
    case "/$p/" in */../*|*/./*) return 1 ;; esac
    full="$ROOT/$p"
    [ -L "$full" ] && return 1
    [ -f "$full" ] || return 1
    dir=$(CDPATH='' cd -P -- "$(dirname -- "$full")" 2>/dev/null && pwd -P) || return 1
    base=$(basename -- "$full")
    case "$dir/" in "$ROOT"/*) ;; *) return 1 ;; esac
    printf '%s/%s' "$dir" "$base"
}

# entry <id> [retired-ok]: the entry's JSON on stdout. Exit 1 unknown or
# retired (a retired entry is printed when the second argument is given), 2
# when the registry can't be read, the id is malformed, or the entry itself is
# (no status, or two entries with the id; the check script refuses both in CI).
entry() {
    local id=$1 retired_ok=${2:-} e n status
    valid_id "$id" || { echo "$PROG: [$id] is not a rule id" >&2; return 2; }
    [ -r "$REGISTRY" ] || { echo "$PROG: cannot read $REGISTRY" >&2; return 2; }
    jq -e '.rules | type == "array"' "$REGISTRY" >/dev/null 2>&1 \
        || { echo "$PROG: $REGISTRY does not parse as a registry" >&2; return 2; }
    n=$(jq --arg id "$id" '[.rules[] | select(.id == $id)] | length' "$REGISTRY")
    case "$n" in
        0) echo "$PROG: no rule $id" >&2; return 1 ;;
        1) ;;
        *) echo "$PROG: rule $id has $n entries" >&2; return 2 ;;
    esac
    e=$(jq -c --arg id "$id" '.rules[] | select(.id == $id)' "$REGISTRY")
    status=$(printf '%s' "$e" | jq -r '.status // ""')
    case "$status" in
        active) ;;
        retired)
            [ -n "$retired_ok" ] || { echo "$PROG: rule $id is retired" >&2; return 1; } ;;
        *) echo "$PROG: rule $id has no valid status" >&2; return 2 ;;
    esac
    printf '%s\n' "$e"
}

# range <abs file> <first> <last>: prints "<first-line> <last-line>". The first
# anchor must occur on exactly one line; the last is the first line at or after
# it that contains the last anchor (the first line itself when last is empty).
# Anchors are compared as bytes, through the environment so awk never
# interprets a backslash in them.
range() {
    RR_FIRST=$2 RR_LAST=$3 LC_ALL=C awk '
        BEGIN { f = ENVIRON["RR_FIRST"]; l = ENVIRON["RR_LAST"] }
        index($0, f) { n++; if (n == 1) a = NR }
        a && !b && l != "" && index($0, l) { b = NR }
        END {
            if (n != 1) exit 3
            if (l == "") b = a
            if (!b) exit 4
            print a, b
        }' "$1"
}

# git_plain: git on the plugin root and nothing else. The caller's location
# variables are cleared so its environment can't point git at another
# repository, the system and global configuration are skipped, and hooks and the
# filesystem monitor are switched off. Only plumbing runs through it
# (rev-parse, and hash-object with --no-filters so no clean filter a planted
# .gitattributes names can run).
git_plain() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES \
        -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR \
        -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 \
        git -C "$ROOT" -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"
}

# revision <relative path> <abs file>
revision() {
    local rel=$1 abs=$2 top head at_head now version blob
    if command -v git >/dev/null 2>&1; then
        # A checkout only when the plugin root is the top of its own work tree:
        # an installed copy sitting inside some other repository would
        # otherwise name that repository's commit.
        if top=$(git_plain rev-parse --show-toplevel 2>/dev/null) \
            && top=$(CDPATH='' cd -P -- "$top" 2>/dev/null && pwd -P) \
            && [ "$top" = "$ROOT" ] \
            && head=$(git_plain rev-parse --verify --quiet HEAD 2>/dev/null) \
            && [[ $head =~ $HEX40 ]]; then
            at_head=$(git_plain rev-parse --verify --quiet "HEAD:$rel" 2>/dev/null)
            now=$(git_plain hash-object --no-filters -- "$abs" 2>/dev/null)
            if [[ $now =~ $HEX40 ]]; then
                if [ "$at_head" = "$now" ]; then
                    printf '%s' "${head:0:12}"
                else
                    printf 'worktree'
                fi
                return 0
            fi
        fi
    fi
    version=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
    if [[ $version =~ $SEMVER ]]; then
        printf 'v%s' "$version"
    elif [[ $version =~ $VERSION_SHAPE ]]; then
        blob=""
        if command -v git >/dev/null 2>&1; then
            blob=$(git_plain hash-object --no-filters -- "$abs" 2>/dev/null)
        fi
        if [[ $blob =~ $HEX40 ]]; then
            printf '%s+%s' "$version" "${blob:0:12}"
        else
            printf '%s' "$version"
        fi
    else
        printf 'unknown'
    fi
}

# resolve <id>: sets E (entry), P (relative path), F (absolute file), A and B
# (line range). Returns the exit code the commands use.
resolve() {
    local id=$1 rc first last r
    E=$(entry "$id"); rc=$?
    [ $rc -eq 0 ] || return $rc
    P=$(printf '%s' "$E" | jq -r '.text.path')
    F=$(safe_path "$P") || { echo "$PROG: rule $id names an unsafe or missing path [$P]" >&2; return 2; }
    first=$(printf '%s' "$E" | jq -r '.text.first')
    last=$(printf '%s' "$E" | jq -r '.text.last // ""')
    [ -n "$first" ] || { echo "$PROG: rule $id has no first anchor" >&2; return 2; }
    r=$(range "$F" "$first" "$last"); rc=$?
    case $rc in
        0) ;;
        3) echo "$PROG: rule $id: its first anchor is not on exactly one line of $P" >&2; return 2 ;;
        4) echo "$PROG: rule $id: its last anchor is not at or after its first in $P" >&2; return 2 ;;
        *) echo "$PROG: rule $id: could not read $P" >&2; return 2 ;;
    esac
    A=${r% *}
    B=${r#* }
    return 0
}

cmd_ref() {
    resolve "$1" || return $?
    printf '%s#L%s-L%s@%s\n' "$P" "$A" "$B" "$(revision "$P" "$F")"
}

cmd_summary() {
    E=$(entry "$1") || return $?
    printf '%s\n' "$E" | jq -r '.summary'
}

cmd_text() {
    resolve "$1" || return $?
    LC_ALL=C sed -n "${A},${B}p" "$F"
}

# range: the rule's first and last line numbers, for a script that leaves the
# rule's lines out of a copy of its file (the offload canary's rendering).
cmd_range() {
    resolve "$1" || return $?
    printf '%s %s\n' "$A" "$B"
}

# withhold: the entry's withhold value, printed only when it is one of the two
# the vocabulary allows, so a caller deciding whether it may leave a rule out
# never acts on anything else.
cmd_withhold() {
    local w
    E=$(entry "$1") || return $?
    w=$(printf '%s' "$E" | jq -r '.withhold // ""')
    case "$w" in
        never|eligible) printf '%s\n' "$w" ;;
        *) echo "$PROG: rule $1 has no valid withhold value" >&2; return 2 ;;
    esac
}

# STAGE_JQ reads one entry and prints tagged lines, one jq pass for everything
# `stage` and `resolve` need from it:
#   M <summary>   empty when the summary isn't a string free of control
#                 characters, so a tab can't split resolve's line
#   K <kind>      script, or other for any entry not script-checked
#   S <stage>     the stored stage, or block when it is missing or unknown
#   C <path>      the entry's check.path, empty when it isn't path-shaped
#   G <guard> <paths>  one line per protected guard of an active script entry
#                 below block, with the space-separated backstop paths whose
#                 `before` names it. Guards that aren't a list of strings give
#                 one `?` guard with no path, so the entry stays at block.
# Paths are filtered to the path shape here, so none carries a tab, a space or
# a line break into the lines the shell splits.
STAGE_JQ='
  def path_shaped: type == "string" and test("^[A-Za-z0-9._][A-Za-z0-9._/-]*$");
  . as $e
  | (if ($e.summary | type) == "string"
        and (($e.summary | explode | any(.[]; . < 32 or . == 127)) | not)
     then $e.summary else "" end) as $summary
  | (if ($e.check | type) == "object" and $e.check.kind == "script" then "script" else "other" end) as $kind
  | (if ($e.stage | type) == "string" and (["shadow","warn","block","retired"] | index($e.stage)) != null
     then $e.stage else "block" end) as $stage
  | (if ($e.check | type) == "object" and ($e.check.path | path_shaped) then $e.check.path else "" end) as $own
  | (if ($e.guards | type) == "array" and all($e.guards[]; type == "string")
     then [$e.guards[] | . as $g | select(($protected | index($g)) != null)]
     else ["?"] end) as $pg
  | "M\t\($summary)", "K\t\($kind)", "S\t\($stage)", "C\t\($own)",
    (select($kind == "script" and $e.status == "active" and $stage != "block")
      | $pg[] as $g
      | [($e.stage_backstops // []) | if type == "array" then .[] else empty end
          | objects | select(.before == $g) | .check | select(path_shaped)] as $paths
      | "G\t\($g)\t\($paths | join(" "))")
'

# stage_facts: reads E and sets SUMMARY, KIND and STAGE, the effective stage
# (see "Effective stage" in the header). Returns 2 when jq can't read E.
stage_facts() {
    local facts line tag rest guard paths p abs own="" own_abs="" raw="" covered uncovered=0
    facts=$(printf '%s' "$E" | jq -r --argjson protected "$PROTECTED" "$STAGE_JQ" 2>/dev/null) \
        || { echo "$PROG: could not read the entry's stage" >&2; return 2; }
    SUMMARY=""; KIND=""
    while IFS= read -r line; do
        tag=${line%%	*}
        rest=${line#*	}
        case "$tag" in
            M) SUMMARY=$rest ;;
            K) KIND=$rest ;;
            S) raw=$rest ;;
            C) own=$rest
               [ -z "$own" ] || own_abs=$(safe_path "$own") || own_abs="" ;;
            G) guard=${rest%%	*}
               paths=${rest#*	}
               covered=""
               for p in $paths; do
                   [ "$p" = "$own" ] && continue
                   abs=$(safe_path "$p") || continue
                   [ -n "$own_abs" ] && [ "$abs" = "$own_abs" ] && continue
                   covered=1
                   break
               done
               [ -n "$covered" ] || uncovered=1 ;;
        esac
    done <<EOF
$facts
EOF
    STAGE=${raw:-block}
    [ $uncovered -eq 0 ] || STAGE=block
    return 0
}

# stage: a script entry's effective stage, active or retired. An entry that
# isn't script-checked (a review-shadow criterion, a prose rule) has no stage.
cmd_stage() {
    E=$(entry "$1" retired-ok) || return $?
    stage_facts || return $?
    [ "$KIND" = script ] || { echo "$PROG: rule $1 is not script-checked and has no stage" >&2; return 1; }
    printf '%s\n' "$STAGE"
}

# resolve: ref, summary and stage on one line, so a gate script's library makes
# one call per rule. An active entry outside the lifecycle (not
# script-checked) prints block: a rule with no stage keeps blocking, as every
# rule did before stages existed.
cmd_resolve() {
    local ref
    resolve "$1" || return $?
    ref="$P#L$A-L$B@$(revision "$P" "$F")"
    stage_facts || return $?
    [ -n "$SUMMARY" ] || { echo "$PROG: rule $1 has no printable summary" >&2; return 2; }
    [ "$KIND" = script ] || STAGE=block
    printf '%s\t%s\t%s\n' "$ref" "$SUMMARY" "$STAGE"
}

# releasable_path <relative path>: only files a skill already loads in normal
# runs: anything under references/, and in one skill's directory its SKILL.md,
# its references/ and its koto-templates/. A case glob's * crosses slashes, so
# the skill name is split off before the rest is matched.
releasable_path() {
    local rest
    case "$1" in
        references/*) return 0 ;;
        skills/*) rest=${1#skills/*/} ;;
        *) return 1 ;;
    esac
    case "${1#skills/}" in */*) ;; *) return 1 ;; esac
    case "$rest" in
        SKILL.md|references/*|koto-templates/*) return 0 ;;
    esac
    return 1
}

cmd_release() {
    local id=$1 rc lines ref why errf
    fail() { echo "$PROG: could not release $id: $*" >&2; return 0; }
    # resolve sets the globals release reads, so it runs in this shell and its
    # reason goes through a file rather than a command substitution.
    errf=$(mktemp "${TMPDIR:-/tmp}/rule-registry.XXXXXX") || { fail "could not make a temporary file"; return 0; }
    resolve "$id" 2>"$errf"; rc=$?
    why=$(sed -n '1s/^rule-registry: //p' "$errf")
    rm -f "$errf"
    if [ $rc -ne 0 ]; then
        [ -n "$why" ] || why="the registry or the rule text could not be read"
        fail "$why"; return 0
    fi
    releasable_path "$P" || { fail "$P is not a file a skill loads"; return 0; }
    [ $((B - A + 1)) -le $RELEASE_MAX_LINES ] || { fail "the text is longer than $RELEASE_MAX_LINES lines"; return 0; }
    lines=$(LC_ALL=C sed -n "${A},${B}p" "$F") || { fail "could not read $P"; return 0; }
    if LC_ALL=C grep -q -e "$MARK_OPEN" -e "$MARK_CLOSE" -e '::koto-finding::' <<<"$lines"; then
        fail "the text holds a marker line"; return 0
    fi
    if LC_ALL=C grep -q '[[:cntrl:]]' <<<"$(LC_ALL=C tr -d '\t' <<<"$lines")"; then
        fail "the text holds a control character"; return 0
    fi
    ref="$P#L$A-L$B@$(revision "$P" "$F")"
    {
        printf '%s' "$MARK_OPEN"
        jq -cn --arg id "$id" --arg ref "$ref" '{rule_id: $id, rule_ref: $ref}'
        printf '%s\n' "$lines"
        printf '%s\n' "$MARK_CLOSE"
    } >&2
    return 0
}

# log-finding: the findings log the gate suites read. An agent can run a gate
# script from its own shell, where the environment isn't cleared, so the log is
# honored only under the temporary directory, never through a symlink, and only
# as a regular file.
cmd_log_finding() {
    local line=$1 log=${SHIRABE_FINDINGS_LOG:-} tmp dir
    [ -n "$log" ] || return 0
    tmp=$(CDPATH='' cd -P -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || return 0
    case "$log" in /*) ;; *) return 0 ;; esac
    [ -L "$log" ] && return 0
    [ -e "$log" ] && [ ! -f "$log" ] && return 0
    dir=$(CDPATH='' cd -P -- "$(dirname -- "$log")" 2>/dev/null && pwd -P) || return 0
    case "$dir/" in "$tmp"/*) ;; *) return 0 ;; esac
    printf '%s\n' "$line" >> "$log" 2>/dev/null || true
    return 0
}

# stage_level <stage>: the finding level a stage prints at, nothing for
# retired, and error for anything else. The same mapping as
# scripts/lib/rule-findings.sh's rf_level, repeated because this reader never
# sources the library; scripts/rule-registry_test.sh fails when it, rf_level
# and the test library's rf_test_level differ.
stage_level() {
    case "$1" in
        warn) printf 'warning' ;;
        shadow) printf 'info' ;;
        retired) ;;
        *) printf 'error' ;;
    esac
}

# verify-findings: every logged finding names an active rule, carries the
# rule_ref ref computes for it, starts its message with the rule's summary, and
# carries the level its rule's stage prints at. With --stage-source, the stage
# is that rule's for every finding: panel-scope.sh prints findings under the
# rules they cite at panel/open-finding's stage. A log with no findings fails:
# a suite that meant to check its findings and logged none has checked nothing.
cmd_verify_findings() {
    local log=$1 problems=0 n=0 line json id ref msg want summary got rest stage level want_level src="" tab
    tab=$(printf '\t')
    [ -r "$log" ] || die2 "cannot read findings log $log"
    [ -r "$REGISTRY" ] || die2 "cannot read $REGISTRY"
    if [ -n "$STAGE_SOURCE" ]; then
        got=$(cmd_resolve "$STAGE_SOURCE" 2>&1) || die2 "cannot resolve the stage source $STAGE_SOURCE: $got"
        src=${got##*"$tab"}
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '::koto-finding::'*) json=${line#::koto-finding::} ;;
            '') continue ;;
            *) echo "line is not a finding: $line"; problems=$((problems + 1)); continue ;;
        esac
        n=$((n + 1))
        id=$(printf '%s' "$json" | jq -r '.rule_id // empty' 2>/dev/null)
        ref=$(printf '%s' "$json" | jq -r '.rule_ref // empty' 2>/dev/null)
        msg=$(printf '%s' "$json" | jq -r '.message // empty' 2>/dev/null)
        level=$(printf '%s' "$json" | jq -r '.level // empty' 2>/dev/null)
        if [ -z "$id" ]; then
            echo "finding without rule_id: $json"; problems=$((problems + 1)); continue
        fi
        # One resolve gives the ref, summary and stage, as the library reads
        # them.
        if ! got=$(cmd_resolve "$id" 2>&1); then
            echo "finding $id: $got"; problems=$((problems + 1)); continue
        fi
        want=${got%%"$tab"*}
        rest=${got#*"$tab"}
        summary=${rest%%"$tab"*}
        stage=${rest#*"$tab"}
        [ -z "$src" ] || stage=$src
        if [ "$ref" != "$want" ]; then
            echo "finding $id: rule_ref [$ref] is not [$want]"; problems=$((problems + 1))
        fi
        case "$msg" in
            "$summary: "*) ;;
            *) echo "finding $id: message does not start with the rule's summary [$summary]"; problems=$((problems + 1)) ;;
        esac
        want_level=$(stage_level "$stage")
        if [ -z "$want_level" ]; then
            echo "finding $id: logged at stage $stage, which prints nothing"; problems=$((problems + 1))
        elif [ "$level" != "$want_level" ]; then
            echo "finding $id: level [$level] is not [$want_level], the level of stage $stage"; problems=$((problems + 1))
        fi
    done < "$log"
    if [ $n -eq 0 ]; then
        echo "$PROG: $log holds no findings" >&2
        return 1
    fi
    if [ $problems -gt 0 ]; then
        echo "$PROG: $problems of $n findings failed verification" >&2
        return 1
    fi
    echo "$PROG: $n findings verified" >&2
    return 0
}

command -v jq >/dev/null 2>&1 || die2 "jq is required"

case "$CMD" in
    ref) cmd_ref "$ARG" ;;
    summary) cmd_summary "$ARG" ;;
    text) cmd_text "$ARG" ;;
    range) cmd_range "$ARG" ;;
    withhold) cmd_withhold "$ARG" ;;
    stage) cmd_stage "$ARG" ;;
    resolve) cmd_resolve "$ARG" ;;
    release) cmd_release "$ARG"; exit 0 ;;
    log-finding) cmd_log_finding "$ARG"; exit 0 ;;
    verify-findings) cmd_verify_findings "$ARG" ;;
    *) die2 "unknown command $CMD" ;;
esac
