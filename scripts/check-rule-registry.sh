#!/usr/bin/env bash
# check-rule-registry.sh -- the standing checks on references/rule-registry.json.
#
# The registry is the one home of every rule a gate script reports, every
# review-shadow criterion and every rule a script releases (see
# references/rule-registry.md). This script checks that it stays true to the
# repository around it, and prints one line per problem:
#
#   1  shape: every field, values from the vocabularies, id patterns, no
#      duplicate id or alias, no alias that is an id, `none` alone in guards,
#      every <skill>:<state> timing names a `## <state>` section of one of
#      that skill's koto templates, a one-line summary with no control
#      character and no `::`; a script entry's stage (shadow, warn, block,
#      retired), stage_since (YYYY-MM-DD) and gates (<skill>:<state>:<gate>,
#      non-empty while active, unless the check is scripts/doc-check.sh, which
#      runs from a skill's phase step and has no gate), stage retired on a
#      status retired entry, and
#      none of these or stage_backstops on any other entry; stage_backstops
#      entries name a protected action once each and a check, with notes; a
#      `decider` check names its template, state, gate and criterion, and a
#      `jev` contract is an object (its contents are
#      scripts/jev-criteria/jev_criteria.py's to check); `held_by` appears
#      only on an rs- entry and names an active script-checked entry
#   2  withhold safety: a guard other than `none`, or check.kind `none`,
#      needs withhold `never`; a gate that isn't a decider check needs a
#      guard, or a backstop: the
#      deterministic check that still blocks a protected action after the
#      gate (backstop.before), for a rule whose harm a later edit undoes; a
#      backstop needs level gate, guards ["none"], withhold `eligible` and
#      notes; prose needs check `none`. Stage safety: an active script
#      entry below block covers each protected guard with a stage_backstops
#      entry before it whose check isn't the entry's own check.path
#   3  paths: text, check, decider template, backstop, stage backstop and
#      fixture paths have a safe shape and stay in the repository; an active
#      entry's check path, decider template, backstop checks and fixtures
#      exist; a review-shadow check names a criterion in criteria.json
#   4  pointers: every active entry's anchors resolve, through
#      rule-registry.sh's own lookup, to a range with no marker line and no
#      control character but tab; a retired entry is exempt
#   5  review-shadow agreement: the rs- ids of the registry and criteria.json
#      are one set, and each entry's text.path is its criterion's rule_ref;
#      an rs- entry with check.kind `none` is a jury rubric item, judged by a
#      document jury seat (references/review-verdicts.md), and has no
#      criterion. `rs-verdict-missing` is the one rs- id outside rs-NNN
#   6  printable ids: every id on a RULE_IDS="..." line under skills/,
#      scripts/ or hooks/ (a hook's *_test.sh suite aside), and every id a
#      script passes to `rule-registry.sh release`,
#      is an active entry; a RULE_IDS_ANY_ACTIVE=1 line, the declared
#      exception for a script that resolves a finding's own rule at run time,
#      appears only in an allowed script and only beside an rf_require_any
#      call, and no other shipping script calls rf_require_any
#   7  baseline keys: template-pin.json's commit is 40 hex characters; each
#      key is <path>#L<a>-L<b>, a <= b, inside its file at that commit; an
#      entry sharing a key names the others in notes; an empty list has notes
#   8  routing-gate rule: DESIGN-output-gates.md's Decision 9 names the
#      registry and not the old rule tables, rule-registry.md defines a
#      registered rule, and no scanned file names the removed table
#   9  path filter: every active entry's text.path is matched by a glob in the
#      pull_request paths of check-rule-registry.yml
#  10  releasable ids: every released id passes rule-registry.sh's own
#      release rules (path, 60 lines, no marker), so CI fails before a run does
#  11  id removal and stage transitions (--base <ref>): every id in the
#      registry at <ref> is still in it. Joined by id: a new entry starts at
#      shadow, warn or block; a base entry with no stage takes block, or
#      retired when its status is retired; a stage moves one step up, any
#      steps down among block, warn and shadow, to retired, or from retired to
#      shadow on an active entry, and every move raises stage_since; a status
#      change to retired sets stage retired; a status retired base entry keeps
#      its status and stage; an active entry that drops a protected guard is
#      at block. A base with no registry passes; one that doesn't parse exits 2
#  12  hook links: a `deny` is an object of hook and before only, whose hook
#      is a safe relative path to an existing file and whose before is a
#      non-empty list of protected actions (the guards vocabulary less
#      `none`); every id on a RULE_IDS
#      line under hooks/ has a `deny` naming that script, and every `deny`
#      names a script whose RULE_IDS line lists the id
#  13  gates: every gates value names a state of that skill's koto templates
#      (frontmatter, not the mermaid renderings) and a command gate of that
#      state; for an active entry, a command that runs a script whose
#      RULE_IDS line lists the id, or a script in ANY_ACTIVE_ALLOWED. A gate
#      whose command runs a script in ANY_ACTIVE_ALLOWED is a panel gate, and
#      only PANEL_RULE may list one, whatever its status:
#      scripts/rule-lifecycle.sh counts every finding at a panel gate for
#      PANEL_RULE, so another entry listing one would count them as its own
#
# The rules that rule-registry.sh enforces at run time (anchor lookup, safe
# path, releasable path) are asked of it rather than copied here, so the two
# can't drift apart. The stage safety rule is the exception: rule-registry.sh
# repeats it at run time, so a registry edited without passing this check
# still can't soften a guarded rule.
#
# Usage: check-rule-registry.sh [--root <dir>] [--base <ref>]
#   --root  the repository to check (default: this script's repository); the
#           tests point it at a scratch copy
#   --base  also run check 11 against <ref>
#
# Exit codes: 0 no problems, 1 problems listed on stdout, 2 could not run.

set -u

PROG=check-rule-registry

die2() {
    echo "$PROG: $*" >&2
    exit 2
}

SELF_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) \
    || die2 "cannot find its own directory"
ROOT=$(CDPATH='' cd -P -- "$SELF_DIR/.." && pwd -P) || die2 "cannot find the repository root"
BASE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || die2 "--root needs a directory"
            ROOT=$(CDPATH='' cd -P -- "$2" 2>/dev/null && pwd -P) || die2 "--root $2 is not a directory"
            shift 2 ;;
        --base)
            [ $# -ge 2 ] || die2 "--base needs a ref"
            BASE=$2; shift 2 ;;
        *) die2 "usage: check-rule-registry.sh [--root <dir>] [--base <ref>]" ;;
    esac
done

command -v jq >/dev/null 2>&1 || die2 "jq is required"
command -v git >/dev/null 2>&1 || die2 "git is required"

HELPER="$SELF_DIR/rule-registry.sh"
[ -x "$HELPER" ] || die2 "cannot run $HELPER"
REG="$ROOT/references/rule-registry.json"
REG_DOC="$ROOT/references/rule-registry.md"
CRITERIA="$ROOT/scripts/review-shadow/criteria.json"
PIN_FILE="$ROOT/docs/measurement/offload-baseline/template-pin.json"
WORKFLOW="$ROOT/.github/workflows/check-rule-registry.yml"
OUTPUT_GATES="$ROOT/docs/designs/current/DESIGN-output-gates.md"
OLD_TABLE="gate-rules.tsv"

PATH_SHAPE='^[A-Za-z0-9._][A-Za-z0-9._/-]*$'
HEX40='^[0-9a-f]{40}$'
KEY_SHAPE='^([A-Za-z0-9._][A-Za-z0-9._/-]*)#L([0-9]+)-L([0-9]+)$'
TIMING_SHAPE='^([a-z0-9-]+):([a-z0-9_]+)$'
ID_SHAPE='^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3}|rs-verdict-missing)$'
RULE_IDS_LINE='^RULE_IDS="([a-z0-9/-]+( [a-z0-9/-]+)*)"$'
COMMENT_LINE='^[[:space:]]*#'
# The guards vocabulary less `none`: the actions a guard, a backstop or a
# deny can name. rule-registry.sh keeps the same list for its run-time stage
# safety rule; check-rule-registry_test.sh fails when the two differ.
PROTECTED='["pr-create","push","force-push","merge","close-issue","release","delete-branch","publish","destroy-record"]'
# A script entry's stage, in rising order of what a finding does; retired
# prints nothing.
STAGES='["shadow","warn","block","retired"]'
# The one check that holds a skill's phase step rather than a koto gate: an
# entry it checks has no gates to name, so its gates may be empty.
STEP_CHECK=scripts/doc-check.sh

TMP=$(mktemp -d "${TMPDIR:-/tmp}/check-rule-registry.XXXXXX") || die2 "cannot make a scratch directory"
trap 'rm -rf "$TMP"' EXIT


PROBLEMS=0
problem() {
    printf '%s: %s\n' "$PROG" "$*"
    PROBLEMS=$((PROBLEMS + 1))
}

# report <file>: one problem per non-empty line of <file>.
report() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && problem "$line"
    done < "$1"
}

# jqf <out> <jq arguments...>: jq into <out>. A jq that fails is a check that
# could not run, never one that found nothing.
jqf() {
    local out=$1
    shift
    jq "$@" > "$out" 2> "$TMP/jq.err" || die2 "jq failed: $(head -n 1 "$TMP/jq.err")"
}

repo_git() {
    git -C "$ROOT" "$@"
}

# ---------------------------------------------------------------- 1 and 2

if ! jq -e '.rules | type == "array"' "$REG" >/dev/null 2>&1; then
    problem "references/rule-registry.json does not parse as {\"rules\": [...]}"
    echo "$PROG: $PROBLEMS problem(s)"
    exit 1
fi

jqf "$TMP/shape" -r --argjson protected "$PROTECTED" --argjson stages "$STAGES" --arg step_check "$STEP_CHECK" '
  def strs: type == "array" and all(.[]; type == "string");
  def ctl: explode | any(.[]; . < 32 or . == 127);
  ["id","status","summary","text","check","fixtures","level","timing","guards",
   "withhold","baseline_keys","aliases","notes"] as $fields
  | [.rules[] | objects] as $all
  | .rules | to_entries[] | .key as $i | .value as $e
  | if ($e | type) != "object" then "entry \($i): not an object"
    else
      (if ($e.id | type) == "string" then $e.id else "entry \($i)" end) as $n
      | ($fields[] as $f | select(($e | has($f)) | not) | "\($n): missing field \($f)"),
        (select($e | has("id")) | $e.id
          | select(type != "string" or (test("^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3}|rs-verdict-missing)$") | not))
          | "\($n): id \(tojson) matches neither <area>/<rule> nor rs-NNN"),
        (select($e | has("status")) | $e.status
          | select(. != "active" and . != "retired") | "\($n): status \(tojson) is not active or retired"),
        (select($e | has("level")) | $e.level
          | select(. != "gate" and . != "shadow" and . != "prose") | "\($n): level \(tojson) is not gate, shadow or prose"),
        (select($e | has("withhold")) | $e.withhold
          | select(. != "never" and . != "eligible") | "\($n): withhold \(tojson) is not never or eligible"),
        (select($e | has("summary")) | $e.summary
          | if type != "string" or . == "" then "\($n): summary is not a non-empty string"
            elif ctl then "\($n): summary holds a control character or a line break"
            elif contains("::") then "\($n): summary holds the marker ::"
            else empty end),
        (select($e | has("text")) | $e.text
          | if type != "object" then "\($n): text is not an object"
            elif (.path | type) != "string" then "\($n): text.path is not a string"
            elif (.first | type) != "string" or .first == "" then "\($n): text.first is not a non-empty string"
            elif has("last") and (.last | type) != "string" then "\($n): text.last is not a string"
            else empty end),
        (select($e | has("check")) | $e.check
          | if type != "object" then "\($n): check is not an object"
            elif .kind == "script" then (select((.path | type) != "string") | "\($n): a script check has no path")
            elif .kind == "review-shadow" then (select((.criterion | type) != "string") | "\($n): a review-shadow check has no criterion")
            elif .kind == "decider" then
              (. as $c | ["template","state","gate","criterion"][] | select(($c[.] | type) != "string" or $c[.] == "")
                 | "\($n): a decider check has no \(.)")
            elif .kind == "none" then empty
            else "\($n): check.kind \(.kind | tojson) is not script, review-shadow, decider or none" end),
        (select($e | has("jev")) | select(($e.jev | type) != "object") | "\($n): jev is not an object"),
        (select($e | has("held_by")) | $e.held_by
          | if ($e.id | type) != "string" or ($e.id | startswith("rs-") | not) then "\($n): held_by is only for an rs- jury or review-shadow item"
            elif type != "string" then "\($n): held_by is not a string"
            else . as $h | select([$all[] | select(.id == $h and .status == "active" and .check.kind == "script")] | length == 0)
              | "\($n): held_by \($h | tojson) is not an active script-checked entry" end),
        ("fixtures","timing","guards","baseline_keys","aliases" | . as $f
          | select($e | has($f)) | select($e[$f] | strs | not) | "\($n): \($f) is not a list of strings"),
        (select($e | has("notes")) | select(($e.notes | type) != "string") | "\($n): notes is not a string"),
        (select(($e.timing | strs) and ($e.timing | length) == 0) | "\($n): timing is empty"),
        (select($e.timing | strs) | $e.timing[]
          | select(. != "pre-merge" and (test("^[a-z0-9-]+:[a-z0-9_]+$") | not))
          | "\($n): timing \(tojson) is neither <skill>:<state> nor pre-merge"),
        (select($e.guards | strs) | $e.guards
          | if length == 0 then "\($n): guards is empty; use [\"none\"]"
            elif index("none") != null and length > 1 then "\($n): none is mixed with other guards"
            # $g, not the dot: inside `$protected | index(...)` the dot is the list.
            else (.[] | . as $g | select($g != "none" and ($protected | index($g)) == null) | "\($n): guard \(tojson) is not in the vocabulary")
            end),
        (select(($e.guards | strs) and any($e.guards[]; . != "none") and $e.withhold == "eligible")
          | "\($n): a protected guard requires withhold never"),
        (select(($e.check | type) == "object" and $e.check.kind == "none" and $e.withhold == "eligible")
          | "\($n): check.kind none requires withhold never"),
        # A decider check guards no protected action; its withholding is
        # governed by its jev contract (scripts/jev-criteria/jev_criteria.py).
        (select($e.level == "gate" and ($e.guards | strs) and all($e.guards[]; . == "none")
                and ($e | has("backstop") | not)
                and ((($e.check | type) == "object" and $e.check.kind == "decider") | not))
          | "\($n): a gate entry needs a guard other than none, or a backstop"),
        (select($e | has("backstop")) | $e.backstop as $b
          | if ($b | type) != "object" then "\($n): backstop is not an object"
            elif ($protected | index($b.before)) == null then "\($n): backstop.before \($b.before | tojson) is not a protected action"
            elif ($b.check | type) != "string" or $b.check == "" then "\($n): backstop.check is not a path"
            elif $e.level != "gate" then "\($n): a backstop needs level gate"
            elif ($e.guards != ["none"]) then "\($n): a backstop needs guards [\"none\"]"
            elif $e.withhold != "eligible" then "\($n): a backstop needs withhold eligible"
            elif ($e.notes | type) != "string" or $e.notes == "" then "\($n): a backstop needs notes saying why"
            else empty end),
        (select($e.level == "prose" and ($e.check | type) == "object" and $e.check.kind != "none")
          | "\($n): a prose entry must have check.kind none"),
        # The check lifecycle: stage, stage_since and gates on every script
        # entry and on no other; stage_backstops only beside them.
        (($e.check | type) == "object" and $e.check.kind == "script") as $script
        | (if $script then
             ("stage","stage_since","gates" | . as $f | select($e | has($f) | not) | "\($n): missing field \($f)")
           else
             ("stage","stage_since","gates","stage_backstops" | . as $f | select($e | has($f))
               | "\($n): \($f) is only for an entry with check.kind script")
           end),
        (select($script and ($e | has("stage"))) | $e.stage
          | . as $s | select(($s | type) != "string" or ($stages | index($s)) == null)
          | "\($n): stage \(tojson) is not shadow, warn, block or retired"),
        (select($script and ($e | has("stage_since"))) | $e.stage_since
          | select(type != "string" or (test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$") | not))
          | "\($n): stage_since \(tojson) is not a YYYY-MM-DD date"),
        (select($script and $e.status == "retired" and ($e | has("stage")) and $e.stage != "retired")
          | "\($n): a status retired entry needs stage retired"),
        (select($script and ($e | has("gates"))) | $e.gates
          | if strs | not then "\($n): gates is not a list of strings"
            elif length == 0 and $e.status == "active" and $e.check.path != $step_check then "\($n): gates is empty on an active entry"
            else (.[] | select(test("^[a-z0-9-]+:[a-z0-9_]+:[a-z0-9_]+$") | not)
                  | "\($n): gate \(tojson) is not <skill>:<state>:<gate>")
            end),
        (select($script and ($e | has("stage_backstops"))) | $e.stage_backstops
          | if type != "array" or length == 0 or any(.[]; type != "object") then
              "\($n): stage_backstops is not a non-empty list of objects"
            else
              (.[] | .before as $a | select(($a | type) != "string" or ($protected | index($a)) == null) | $a
                | "\($n): stage_backstops before \(tojson) is not a protected action"),
              ([.[].before | strings] | group_by(.) | map(select(length > 1)[0])[]
                | "\($n): stage_backstops names \(.) more than once"),
              (.[] | .check | select(type != "string" or . == "")
                | "\($n): a stage_backstops check is not a path"),
              (select(($e.notes | type) != "string" or $e.notes == "")
                | "\($n): stage_backstops needs notes saying why")
            end),
        # The safety rule: a guarded rule below block keeps every protected
        # action it guards behind another deterministic check.
        (select($script and $e.status == "active" and ($e.stage | type) == "string"
                and $e.stage != "block" and ($stages | index($e.stage)) != null
                and ($e.guards | strs))
          | (if ($e.stage_backstops | type) == "array" then [$e.stage_backstops[] | objects] else [] end) as $bs
          | $e.guards[] | . as $g | select(($protected | index($g)) != null)
          | select(any($bs[]; .before == $g and (.check | type) == "string" and .check != "" and .check != $e.check.path) | not)
          | "\($n): guards \($g) at stage \($e.stage) with no stage_backstops entry before \($g) naming a check other than its own")
    end
' "$REG"
report "$TMP/shape"

jqf "$TMP/dups" -r '
  ([.rules[] | objects | .id | strings] | group_by(.) | map(select(length > 1)[0])[]
     | "id \(.) is used by more than one entry"),
  ([.rules[] | objects | .aliases | arrays | .[] | strings] | group_by(.) | map(select(length > 1)[0])[]
     | "alias \(.) is used more than once"),
  ([.rules[] | objects | .id | strings] as $ids
     | .rules[] | objects | .id as $id | (.aliases | arrays | .[] | strings)
     | select(. as $a | $ids | index($a)) | "\($id): alias \(.) is also an id")
' "$REG"
report "$TMP/dups"

# Each <skill>:<state> timing names a `## <state>` heading in one of the
# skill's koto templates.
jqf "$TMP/timing" -r '.rules[] | objects | select(.timing | type == "array") | .id as $id
       | .timing[] | strings | select(. != "pre-merge") | "\($id)\t\(.)"' "$REG"
while IFS='	' read -r id timing; do
    [ -n "$timing" ] || continue
    [[ $timing =~ $TIMING_SHAPE ]] || continue
    skill=${BASH_REMATCH[1]}
    state=${BASH_REMATCH[2]}
    found=""
    for t in "$ROOT/skills/$skill/koto-templates/"*.md; do
        [ -f "$t" ] || continue
        if grep -qxF "## $state" "$t"; then found=1; break; fi
    done
    [ -n "$found" ] || problem "$id: timing $timing names no '## $state' section in skills/$skill/koto-templates/"
done < "$TMP/timing"

# ---------------------------------------------------------------- 3

# safe_rel <path>: 0 when the path has the allowed shape, no `.` or `..`
# segment, is not a symlink and stays inside ROOT (it need not exist).
safe_rel() {
    local p=$1 dir
    [[ $p =~ $PATH_SHAPE ]] || return 1
    case "/$p/" in */../*|*/./*) return 1 ;; esac
    [ -L "$ROOT/$p" ] && return 1
    dir=$(dirname -- "$ROOT/$p")
    while [ ! -d "$dir" ]; do dir=$(dirname -- "$dir"); done
    dir=$(CDPATH='' cd -P -- "$dir" 2>/dev/null && pwd -P) || return 1
    case "$dir/" in "$ROOT"/*) return 0 ;; esac
    return 1
}

jqf "$TMP/paths" -r '.rules[] | objects | .id as $id | (.status // "") as $s
       | ((.text | objects | .path | strings | "\($id)\t\($s)\ttext\t\(.)"),
          (.check | objects | select(.kind == "script") | .path | strings | "\($id)\t\($s)\tcheck\t\(.)"),
          (.check | objects | select(.kind == "decider") | .template | strings | "\($id)\t\($s)\ttemplate\t\(.)"),
          (.backstop | objects | .check | strings | "\($id)\t\($s)\tbackstop\t\(.)"),
          (.stage_backstops | arrays | .[] | objects | .check | strings | select(. != "")
             | "\($id)\t\($s)\tstage backstop\t\(.)"),
          (.fixtures | arrays | .[] | strings | "\($id)\t\($s)\tfixture\t\(.)"))' "$REG"
while IFS='	' read -r id status what p; do
    [ -n "$p" ] || continue
    if ! safe_rel "$p"; then
        problem "$id: $what path [$p] is unsafe (shape, a . or .. segment, a symlink, or outside the repository)"
        continue
    fi
    # A retired rule's check and fixtures may be gone with it.
    if [ "$status" = active ] && [ "$what" != text ] && [ ! -f "$ROOT/$p" ]; then
        problem "$id: $what path $p does not exist"
    fi
done < "$TMP/paths"

# ---------------------------------------------------------------- 3 and 5

if ! jq -e '.criteria | type == "array"' "$CRITERIA" >/dev/null 2>&1; then
    problem "scripts/review-shadow/criteria.json does not parse"
else
    jqf "$TMP/crit-ids" -r '.criteria[].rule_id | strings' "$CRITERIA"
    jqf "$TMP/rs-checks" -r '.rules[] | objects | select(.check.kind? == "review-shadow")
                             | "\(.id)\t\(.check.criterion)"' "$REG"
    while IFS='	' read -r id crit; do
        [ -n "$id" ] || continue
        grep -qxF "$crit" "$TMP/crit-ids" || problem "$id: review-shadow criterion $crit is not in criteria.json"
    done < "$TMP/rs-checks"

    # A jury rubric item (check.kind none) is judged by a document jury seat,
    # not by review-shadow.py, so it has no criterion (references/review-verdicts.md).
    jqf "$TMP/reg-rs.raw" -r '.rules[] | objects | select(.check.kind? != "none")
                              | .id | strings | select(test("^rs-"))' "$REG"
    sort -u "$TMP/reg-rs.raw" > "$TMP/reg-rs"
    grep '^rs-' "$TMP/crit-ids" | sort -u > "$TMP/crit-rs"
    comm -23 "$TMP/reg-rs" "$TMP/crit-rs" | sed 's/$/: in the registry but not in criteria.json/' > "$TMP/rs-only-reg"
    report "$TMP/rs-only-reg"
    comm -13 "$TMP/reg-rs" "$TMP/crit-rs" | sed 's/$/: in criteria.json but not in the registry/' > "$TMP/rs-only-crit"
    report "$TMP/rs-only-crit"
    jqf "$TMP/rs-paths" -r --slurpfile c "$CRITERIA" '
        ($c[0].criteria | map(select(.rule_id | type == "string") | {key: .rule_id, value: .rule_ref})
           | from_entries) as $refs
        | .rules[] | objects | select((.id | type) == "string" and (.id | test("^rs-")))
        | select($refs[.id] != null and .text.path? != $refs[.id])
        | "\(.id): text.path \(.text.path? | tojson) differs from the criterion rule_ref \($refs[.id] | tojson)"' "$REG"
    report "$TMP/rs-paths"
fi

# ---------------------------------------------------------------- 4

MARK_LINE='^::shirabe-rule(-end)?::'
CTL=$(printf '[\001-\010\013-\037\177]')
# matches <grep arguments...>: 0 a match, 1 none; a grep that couldn't run is
# no answer, so it exits 2.
matches() {
    local rc
    LC_ALL=C grep -q "$@"
    rc=$?
    [ "$rc" -le 1 ] || die2 "grep could not run: grep $*"
    return "$rc"
}

jqf "$TMP/active" -r '.rules[] | objects | select(.status == "active") | .id | strings' "$REG"
# Every check below reads the active entries; with none, each would pass on
# nothing.
[ -s "$TMP/active" ] || problem "the registry has no active entries"
while IFS= read -r id; do
    [[ $id =~ $ID_SHAPE ]] || continue
    if ! "$HELPER" --root "$ROOT" text "$id" > "$TMP/text" 2> "$TMP/text.err"; then
        problem "$id: its text does not resolve: $(head -n 1 "$TMP/text.err")"
        continue
    fi
    if matches -E "$MARK_LINE" "$TMP/text"; then
        problem "$id: its range holds a ::shirabe-rule marker line"
    fi
    if matches "$CTL" "$TMP/text"; then
        problem "$id: its range holds a control character other than tab"
    fi
done < "$TMP/active"

# ---------------------------------------------------------------- 6 and 10

is_active() {
    grep -qxF -- "$1" "$TMP/active"
}

# RULE_IDS lines: a gate script's whole list, at the start of a line,
# double-quoted ids separated by single spaces.
# grep exits 1 for no match and 2 when it couldn't read; only the first is an
# answer.
scan() {
    local out=$1 rc
    shift
    grep "$@" > "$out" 2> "$TMP/grep.err"
    rc=$?
    [ "$rc" -le 1 ] || die2 "a scan could not read the tree: $(head -n 1 "$TMP/grep.err")"
}

scan "$TMP/rule-ids.skills" -rnE '^RULE_IDS=' "$ROOT/skills" "$ROOT/scripts"
# A hook script's line is a declaration too (check 12 reads it again). A
# hook's own suite reads that line with a `RULE_IDS=$(...)` of its own, which
# is not one.
: > "$TMP/hook-ids"
if [ -d "$ROOT/hooks" ]; then
    scan "$TMP/hook-ids" -rnE --exclude='*_test.sh' '^RULE_IDS=' "$ROOT/hooks"
fi
cat "$TMP/rule-ids.skills" "$TMP/hook-ids" > "$TMP/rule-ids"
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    rel=${file#"$ROOT"/}
    if ! [[ $text =~ $RULE_IDS_LINE ]]; then
        problem "$rel:$lineno: malformed RULE_IDS line; want RULE_IDS=\"<id> <id> ...\""
        continue
    fi
    for id in ${BASH_REMATCH[1]}; do
        is_active "$id" || problem "$rel:$lineno: RULE_IDS names $id, which is not an active registry entry"
    done
done < "$TMP/rule-ids"

# The one declared exception to "every printable id is on a static line":
# a script that prints a finding under the finding's own rule resolves that id
# at run time with rf_require_any, and says so with RULE_IDS_ANY_ACTIVE=1. The
# runtime still refuses any id that isn't active; this keeps the exception
# visible, paired and confined to the scripts listed here.
ANY_ACTIVE_ALLOWED="skills/work-on/scripts/panel-scope.sh"
# The one entry that may list a gate those scripts run (rule 13). The same
# exception lives in panel-scope.sh (rf_emit ... panel/open-finding) and in
# rule-lifecycle.sh (panel_rule); change the three together.
PANEL_RULE="panel/open-finding"
scan "$TMP/any-marker" -rnE '^RULE_IDS_ANY_ACTIVE=' "$ROOT/skills" "$ROOT/scripts"
scan "$TMP/any-calls" -rlE --include='*.sh' '(^|[^A-Za-z0-9_])rf_require_any([[:space:]]|$)' "$ROOT/skills" "$ROOT/scripts"
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    rel=${file#"$ROOT"/}
    if [ "$text" != "RULE_IDS_ANY_ACTIVE=1" ]; then
        problem "$rel:$lineno: malformed RULE_IDS_ANY_ACTIVE line; want RULE_IDS_ANY_ACTIVE=1"
        continue
    fi
    case " $ANY_ACTIVE_ALLOWED " in
        *" $rel "*) ;;
        *) problem "$rel:$lineno: RULE_IDS_ANY_ACTIVE is allowed only in: $ANY_ACTIVE_ALLOWED" ;;
    esac
    grep -qxF -- "$file" "$TMP/any-calls" \
        || problem "$rel:$lineno: declares RULE_IDS_ANY_ACTIVE=1 but never calls rf_require_any"
done < "$TMP/any-marker"
while IFS= read -r file; do
    rel=${file#"$ROOT"/}
    case "$rel" in
        *_test.sh|scripts/lib/*|scripts/check-rule-registry*.sh) continue ;;
    esac
    grep -qE '^RULE_IDS_ANY_ACTIVE=1$' "$file" \
        || problem "$rel: calls rf_require_any without declaring RULE_IDS_ANY_ACTIVE=1"
done < "$TMP/any-calls"

# Ids passed to `rule-registry.sh release` by the scripts that ship. The
# reader itself, its library, these checks and the test suites are not
# triggers. A release has to name its id literally so this can check it.
#
# The exclusions are by path: a new non-shipping script that calls release
# (another test helper, say) needs adding here, or the check reads its call
# as a trigger.
scan "$TMP/releases" -rnE --include='*.sh' 'rule-registry\.sh"?[[:space:]]+release([[:space:]]|$)' \
    "$ROOT/skills" "$ROOT/scripts"
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    rel=${file#"$ROOT"/}
    case "$rel" in
        *_test.sh|scripts/rule-registry.sh|scripts/lib/*|scripts/check-rule-registry*.sh) continue ;;
    esac
    # A comment line only: `#` as the first character after any indent. A
    # call with a trailing comment is still a call.
    [[ $text =~ $COMMENT_LINE ]] && continue
    id=$(printf '%s\n' "$text" | sed -E 's/.*rule-registry\.sh"?[[:space:]]+release[[:space:]]+([^[:space:]<>|&;]*).*/\1/')
    if ! [[ $id =~ $ID_SHAPE ]]; then
        problem "$rel:$lineno: release is passed [$id], not a literal rule id"
        continue
    fi
    if ! is_active "$id"; then
        problem "$rel:$lineno: releases $id, which is not an active registry entry"
        continue
    fi
    # The reader's own release rules decide. release always exits 0, so its
    # first stderr line is the answer: the opening marker when it would
    # release, its one could-not-release line when it wouldn't, and anything
    # else means the reader itself didn't run, which is no answer at all.
    "$HELPER" --root "$ROOT" release "$id" > /dev/null 2> "$TMP/release.err" </dev/null
    first=$(head -n 1 "$TMP/release.err")
    case "$first" in
        '::shirabe-rule::'*) ;;
        'rule-registry: could not release '*)
            problem "$rel:$lineno: $id would not be released: ${first#rule-registry: }" ;;
        *) die2 "rule-registry.sh release $id gave no answer: ${first:-no output}" ;;
    esac
done < "$TMP/releases"

# ---------------------------------------------------------------- 7

PIN=$(jq -r '.pinned_commit // ""' "$PIN_FILE" 2>/dev/null)
if ! [[ $PIN =~ $HEX40 ]]; then
    problem "template-pin.json's pinned_commit [$PIN] is not 40 lowercase hex characters"
    PIN=""
elif ! repo_git cat-file -e "$PIN^{commit}" 2>/dev/null; then
    die2 "the pinned commit $PIN is not in this repository's history (a shallow clone?)"
fi

: > "$TMP/linecounts"
# lines_at_pin <path>: the file's line count at the pinned commit, -1 when it
# isn't there; counted once per path.
lines_at_pin() {
    local p=$1 n
    n=$(awk -F'\t' -v p="$p" '$1 == p { print $2; exit }' "$TMP/linecounts")
    if [ -z "$n" ]; then
        if repo_git cat-file -e "$PIN:$p" 2>/dev/null; then
            n=$(repo_git cat-file -p "$PIN:$p" | awk 'END { print NR }')
        else
            n=-1
        fi
        printf '%s\t%s\n' "$p" "$n" >> "$TMP/linecounts"
    fi
    printf '%s' "$n"
}

jqf "$TMP/keys" -r '.rules[] | objects | .id as $id | .baseline_keys | arrays | .[] | strings | "\($id)\t\(.)"' "$REG"
while IFS='	' read -r id key; do
    [ -n "$key" ] || continue
    if ! [[ $key =~ $KEY_SHAPE ]]; then
        problem "$id: baseline key [$key] is not <path>#L<start>-L<end>"
        continue
    fi
    p=${BASH_REMATCH[1]}; a=${BASH_REMATCH[2]}; b=${BASH_REMATCH[3]}
    if [ "$a" -lt 1 ] || [ "$a" -gt "$b" ]; then
        problem "$id: baseline key $key has start after end"
        continue
    fi
    [ -n "$PIN" ] || continue
    n=$(lines_at_pin "$p")
    if [ "$n" -lt 0 ]; then
        problem "$id: baseline key $key names a file not at the pinned commit"
    elif [ "$b" -gt "$n" ]; then
        problem "$id: baseline key $key runs past the file's $n lines at the pinned commit"
    fi
done < "$TMP/keys"

jqf "$TMP/key-notes" -r '
  [.rules[] | objects | {id, keys: (.baseline_keys | arrays)}] as $all
  | .rules[] | objects | select((.id | type) == "string") | . as $e
  | if (.baseline_keys | type) == "array" and (.baseline_keys | length) == 0 then
      select((.notes // "") == "") | "\(.id): an empty baseline_keys needs a reason in notes"
    else
      (.baseline_keys | arrays | .[] | strings) as $k
      | $all[] | . as $o
      | select($o.id != $e.id and ($o.keys // [] | index($k)) != null)
      | select(($e.notes // "") | contains($o.id) | not)
      | "\($e.id): shares baseline key \($k) with \($o.id) but its notes do not name it"
    end' "$REG"
report "$TMP/key-notes"

# ---------------------------------------------------------------- 8

if [ ! -f "$OUTPUT_GATES" ]; then
    problem "docs/designs/current/DESIGN-output-gates.md is missing"
else
    awk '/^### Decision 9:/ { on = 1; print; next } on && /^##/ { exit } on { print }' "$OUTPUT_GATES" > "$TMP/d9"
    if [ ! -s "$TMP/d9" ]; then
        problem "DESIGN-output-gates.md has no '### Decision 9:' section"
    else
        grep -qF 'references/rule-registry.json' "$TMP/d9" \
            || problem "DESIGN-output-gates.md Decision 9 does not name references/rule-registry.json"
        stale=$(grep -iE 'rule tables?' "$TMP/d9" | head -n 1)
        [ -z "$stale" ] || problem "DESIGN-output-gates.md Decision 9 still refers to the gate scripts' rule tables: [$stale]"
    fi
fi
grep -qF 'A **registered rule** is an id with an entry in `references/rule-registry.json`' "$REG_DOC" 2>/dev/null \
    || problem "references/rule-registry.md does not define a registered rule as an id with an entry in references/rule-registry.json"

# The check scripts and their suite name the removed table to look for it.
# When the adoption script goes, its name goes from this list too.
: > "$TMP/old-table"
for target in skills scripts references docs/guides CLAUDE.md docs/designs/current/DESIGN-output-gates.md; do
    [ -e "$ROOT/$target" ] || continue
    scan "$TMP/old-table.part" -rlF "$OLD_TABLE" "$ROOT/$target"
    cat "$TMP/old-table.part" >> "$TMP/old-table"
done
while IFS= read -r f; do
    rel=${f#"$ROOT"/}
    case "$rel" in
        scripts/check-rule-registry.sh|scripts/check-rule-registry-adoption.sh|scripts/check-rule-registry_test.sh) ;;
        *) problem "$rel names $OLD_TABLE, which the registry replaced" ;;
    esac
done < "$TMP/old-table"

# ---------------------------------------------------------------- 9

# The pull_request paths of this check's own workflow. The filter uses only
# literal paths and a trailing /**, so each glob is matched as a literal path
# or a directory prefix rather than through GitHub's glob syntax.
if [ ! -f "$WORKFLOW" ]; then
    problem ".github/workflows/check-rule-registry.yml is missing"
else
    awk -v q="'" '
        /^on:/ { on = 1; next }
        on && /^[^ #]/ { on = 0 }
        on && /^  pull_request:/ { pr = 1; next }
        pr && /^  [^ #]/ { pr = 0 }
        pr && /^    paths:/ { paths = 1; next }
        paths && /^    [^ #]/ { paths = 0 }
        paths && /^ *- / {
            s = $0
            sub(/^ *- */, "", s); sub(/ +#.*$/, "", s)
            first = substr(s, 1, 1); last = substr(s, length(s), 1)
            if ((first == q || first == "\"") && last == first) s = substr(s, 2, length(s) - 2)
            print s
        }
    ' "$WORKFLOW" > "$TMP/globs"
    if [ ! -s "$TMP/globs" ]; then
        problem "check-rule-registry.yml has no pull_request paths list"
    else
        while IFS= read -r g; do
            case "${g%/\*\*}" in
                *'*'*|*'?'*|*'['*|'!'*)
                    problem "check-rule-registry.yml path [$g] is a glob this check can't read; use a literal path or a trailing /**" ;;
            esac
        done < "$TMP/globs"
        jqf "$TMP/text-paths" -r '.rules[] | objects | select(.status == "active") | "\(.id)\t\(.text.path? // "")"' "$REG"
        while IFS='	' read -r id p; do
            [ -n "$p" ] || continue
            hit=""
            while IFS= read -r g; do
                case "$g" in
                    */\*\*) case "$p" in "${g%\*\*}"*) hit=1 ;; esac ;;
                    *) [ "$p" = "$g" ] && hit=1 ;;
                esac
                [ -z "$hit" ] || break
            done < "$TMP/globs"
            [ -n "$hit" ] || problem "$id: text.path $p is outside check-rule-registry.yml's paths filter; add it, or its directory with /**, to the pull_request paths"
        done < "$TMP/text-paths"
    fi
fi

# ---------------------------------------------------------------- 11

if [ -n "$BASE" ]; then
    repo_git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || die2 "--base $BASE is not a commit"
    if repo_git cat-file -e "$BASE:references/rule-registry.json" 2>/dev/null; then
        repo_git show "$BASE:references/rule-registry.json" > "$TMP/base-registry.json" \
            || die2 "cannot read the registry at $BASE"
        jqf "$TMP/base-ids.raw" -r '.rules[] | objects | .id | strings' "$TMP/base-registry.json"
        sort -u "$TMP/base-ids.raw" > "$TMP/base-ids"
        jqf "$TMP/head-ids.raw" -r '.rules[] | objects | .id | strings' "$REG"
        sort -u "$TMP/head-ids.raw" > "$TMP/head-ids"
        comm -23 "$TMP/base-ids" "$TMP/head-ids" \
            | sed "s/\$/: in the registry at the base but removed; retire an entry instead of deleting it/" > "$TMP/removed"
        report "$TMP/removed"
        # Stage transitions: each head entry against its base entry, by id.
        # The moves allowed are the header's list for check 11: one step up,
        # any steps down among block, warn and shadow, any stage to retired,
        # and retired to shadow on an active entry. Because a stage rises one
        # step per change and a guard is dropped only at block, promoting
        # past warn, or dropping a guard and softening the stage, takes two
        # reviewed changes.
        jqf "$TMP/transitions" -r --argjson protected "$PROTECTED" --slurpfile base "$TMP/base-registry.json" '
          def rank: if type == "string" then {"shadow": 0, "warn": 1, "block": 2}[.] else null end;
          def pguards: if (.guards | type) == "array"
                       then [.guards[] | strings | . as $g | select(($protected | index($g)) != null)]
                       else [] end;
          ([$base[0].rules[] | objects | select((.id | type) == "string") | {key: .id, value: .}]
             | from_entries) as $old
          | .rules[] | objects | select((.id | type) == "string") | .id as $n | . as $h
          | $old[$n] as $b
          | if $b == null then
              select($h.stage == "retired") | "\($n): a new entry starts at shadow, warn or block, not retired"
            else
              (select($b.status == "retired" and ($h.status != "retired"
                        or (($b | has("stage")) and $h.stage != $b.stage)))
                | "\($n): a status retired entry keeps its status and stage (was \($b.stage // "no stage"), now \($h.status) at \($h.stage // "no stage"))"),
              (select($b.status != "retired" and $h.status == "retired" and $h.stage != "retired"
                      and ($h | has("stage")))
                | "\($n): a status change to retired sets stage retired, not \($h.stage | tojson)"),
              (select(($b | has("stage") | not) and ($h | has("stage")))
                | select($h.stage != "block" and ($h.stage != "retired" or $h.status != "retired"))
                | "\($n): an entry with no stage at the base takes block (or retired when its status is retired), not \($h.stage | tojson)"),
              (select(($b | has("stage")) and ($h | has("stage")) and $b.stage != $h.stage and $b.status != "retired")
                | $b.stage as $from | $h.stage as $to
                | (if $to == "retired" then empty
                   elif $from == "retired" then
                     (if $to == "shadow" and $h.status == "active" then empty
                      else "\($n): stage retired may change only to shadow on an active entry, not to \($to | tojson)" end)
                   elif ($from | rank) != null and ($to | rank) != null and ($to | rank) > ($from | rank) + 1 then
                     "\($n): stage \($from) to \($to) skips a step; promote one step at a time"
                   else empty end),
                  (select(($h.stage_since | type) != "string" or ($b.stage_since | type) == "string" and $h.stage_since <= $b.stage_since)
                   | "\($n): stage changed from \($from) to \($to) but stage_since \($h.stage_since | tojson) is not later than the base \($b.stage_since | tojson)")),
              (select($h.status == "active" and ($h.stage // "block") != "block")
                | ($b | pguards) - ($h | pguards) | select(length > 0)
                | "\($n): drops protected guard(s) \(join(", ")) while at stage \($h.stage); drop a guard only at block, and soften the stage in a later change")
            end' "$REG"
        report "$TMP/transitions"
    else
        echo "$PROG: the base has no registry; the id-removal check has nothing to compare"
    fi
fi

# ---------------------------------------------------------------- 12

# A `deny` names the plugin hook that denies a protected action when the rule
# is broken, and the hook script declares the rules it denies on its RULE_IDS
# line. The link is checked both ways, so neither side can name a rule the
# other doesn't.
jqf "$TMP/deny-shape" -r --argjson protected "$PROTECTED" '
  .rules[] | objects | select(has("deny"))
  | (if (.id | type) == "string" then .id else "an entry" end) as $n | .deny
  | if type != "object" then "\($n): deny is not an object"
    elif (keys - ["hook", "before"]) != [] then "\($n): deny has a field other than hook and before: \(keys - ["hook", "before"] | join(", "))"
    elif (.hook | type) != "string" or .hook == "" then "\($n): deny.hook is not a path"
    elif (.before | type) != "array" or (.before | length) == 0 then "\($n): deny.before is not a non-empty list"
    # Bind each action before the lookup: inside `$protected | index(.)` the
    # dot is the list itself, which always finds itself at 0.
    else .before[] | . as $a | select(($a | type) != "string" or ($protected | index($a)) == null)
      | "\($n): deny.before \(tojson) is not a protected action"
    end' "$REG"
report "$TMP/deny-shape"

jqf "$TMP/deny-links" -r '.rules[] | objects
       | select((.id | type) == "string" and (.deny | type) == "object" and (.deny.hook | type) == "string")
       | "\(.id)\t\(.deny.hook)"' "$REG"
while IFS='	' read -r id p; do
    [ -n "$p" ] || continue
    if ! safe_rel "$p"; then
        problem "$id: deny.hook [$p] is unsafe (shape, a . or .. segment, a symlink, or outside the repository)"
        continue
    fi
    if [ ! -f "$ROOT/$p" ]; then
        problem "$id: deny.hook $p does not exist"
        continue
    fi
    listed=""
    line=$(grep -E '^RULE_IDS=' "$ROOT/$p" | head -n 1)
    if [[ $line =~ $RULE_IDS_LINE ]]; then
        case " ${BASH_REMATCH[1]} " in *" $id "*) listed=1 ;; esac
    fi
    [ -n "$listed" ] || problem "$id: deny names $p, whose RULE_IDS line does not list it"
done < "$TMP/deny-links"

while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    rel=${file#"$ROOT"/}
    # Check 6 has already reported a malformed line.
    [[ $text =~ $RULE_IDS_LINE ]] || continue
    for id in ${BASH_REMATCH[1]}; do
        grep -qxF -- "$id	$rel" "$TMP/deny-links" \
            || problem "$rel:$lineno: RULE_IDS names $id, whose registry entry has no deny naming $rel"
    done
done < "$TMP/hook-ids"

# ---------------------------------------------------------------- 13

# Each skill's koto templates, frontmatter only: a state at two spaces under
# `states:`, `gates:` at four, a gate at six and its command at eight. One
# `S skill:state` line per state and one `G skill:state:gate command` line per
# command gate. The mermaid renderings carry no frontmatter of their own.
: > "$TMP/template-gates"
for t in "$ROOT"/skills/*/koto-templates/*.md; do
    [ -f "$t" ] || continue
    case "$t" in *.mermaid.md) continue ;; esac
    skill=${t#"$ROOT"/skills/}
    skill=${skill%%/*}
    awk -v skill="$skill" '
        NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
        !fm { exit }
        /^---[[:space:]]*$/ { exit }
        /^[^ #]/ { in_states = ($0 ~ /^states:/); in_gates = 0; next }
        !in_states { next }
        /^  [a-z0-9_]+:/ { state = $1; sub(/:$/, "", state); in_gates = 0; print "S\t" skill ":" state; next }
        /^    gates:/ { in_gates = 1; next }
        /^    [^ ]/ { in_gates = 0; next }
        in_gates && /^      [a-z0-9_]+:/ { gate = $1; sub(/:$/, "", gate); next }
        in_gates && /^        command:/ {
            c = $0; sub(/^        command:[[:space:]]*/, "", c)
            print "G\t" skill ":" state ":" gate "\t" c
        }' "$t" >> "$TMP/template-gates" || die2 "could not read $t"
done

# The scripts that declare what they report: <path> <ids>, one line each.
: > "$TMP/script-ids"
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    text=${rest#*:}
    [[ $text =~ $RULE_IDS_LINE ]] || continue
    printf '%s\t%s\n' "${file#"$ROOT"/}" "${BASH_REMATCH[1]}" >> "$TMP/script-ids"
done < "$TMP/rule-ids"

jqf "$TMP/gates" -r '.rules[] | objects | select((.id | type) == "string" and (.gates | type) == "array")
       | .id as $id | (.status // "") as $s | .gates[] | strings
       | select(test("^[a-z0-9-]+:[a-z0-9_]+:[a-z0-9_]+$")) | "\($id)\t\($s)\t\(.)"' "$REG"
# One awk pass over the three lists. A gate command runs a script when it
# names the plugin's path to it, closed by a quote or a space. A retired rule
# has left every RULE_IDS line, so only its gate names are checked. A script
# that resolves a finding's own rule at run time (ANY_ACTIVE_ALLOWED) may
# report any active rule, which makes its gates panel gates: only PANEL_RULE
# may list one, active or retired. The awk tells its inputs apart by position
# (ARGV[1] the template gates, ARGV[2] the declaring scripts, then the
# registry's gate values), so keep the three arguments in that order.
awk -F'\t' -v any="$ANY_ACTIVE_ALLOWED" -v panel="$PANEL_RULE" -v q='"' '
    function runs(c, p) { return index(c, "{{PLUGIN_ROOT}}/" p q) || index(c, "{{PLUGIN_ROOT}}/" p " ") }
    FILENAME == ARGV[1] {
        if ($1 == "S") state_of[$2] = 1
        else if ($1 == "G") { n[$2]++; cmd[$2, n[$2]] = $3 }
        next
    }
    FILENAME == ARGV[2] { ns++; spath[ns] = $1; sids[ns] = " " $2 " "; next }
    {
        id = $1; status = $2; gate = $3
        sg = gate; sub(/:[^:]*$/, "", sg)
        skill = gate; sub(/:.*$/, "", skill)
        state = sg; sub(/^[^:]*:/, "", state)
        if (!(sg in state_of)) { print id ": gate " gate " names no state " state " in skills/" skill "/koto-templates/"; next }
        if (!(gate in n)) { print id ": gate " gate " is not a command gate of state " state; next }
        na = split(any, a, " ")
        if (id != panel) {
            pg = 0
            for (i = 1; i <= n[gate] && !pg; i++)
                for (j = 1; j <= na; j++) if (runs(cmd[gate, i], a[j])) pg = 1
            if (pg) { print id ": gate " gate " is a panel gate; only " panel " may list one"; next }
        }
        if (status != "active") next
        ok = 0
        for (i = 1; i <= n[gate] && !ok; i++) {
            c = cmd[gate, i]
            for (j = 1; j <= na; j++) if (runs(c, a[j])) ok = 1
            for (k = 1; k <= ns; k++) if (runs(c, spath[k]) && index(sids[k], " " id " ")) ok = 1
        }
        if (!ok) print id ": gate " gate " runs no script whose RULE_IDS line lists " id
    }' "$TMP/template-gates" "$TMP/script-ids" "$TMP/gates" > "$TMP/gate-problems" \
    || die2 "the gates check could not run"
report "$TMP/gate-problems"

if [ "$PROBLEMS" -gt 0 ]; then
    echo "$PROG: $PROBLEMS problem(s)"
    exit 1
fi
echo "$PROG: ok"
exit 0
