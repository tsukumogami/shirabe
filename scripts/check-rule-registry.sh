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
#      character and no `::`
#   2  withhold safety: a guard other than `none`, or check.kind `none`,
#      needs withhold `never`; a gate needs a guard; prose needs check `none`
#   3  paths: text, check and fixture paths have a safe shape and stay in the
#      repository; an active entry's check path and fixtures exist; a
#      review-shadow check names a criterion in criteria.json
#   4  pointers: every active entry's anchors resolve, through
#      rule-registry.sh's own lookup, to a range with no marker line and no
#      control character but tab; a retired entry is exempt
#   5  review-shadow agreement: the rs- ids of the registry and criteria.json
#      are one set, and each entry's text.path is its criterion's rule_ref
#   6  printable ids: every id on a RULE_IDS="..." line under skills/ or
#      scripts/, and every id a script passes to `rule-registry.sh release`,
#      is an active entry
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
#  11  id removal (--base <ref>): every id in the registry at <ref> is still
#      in it; a base with no registry passes
#
# The rules that rule-registry.sh enforces at run time (anchor lookup, safe
# path, releasable path) are asked of it rather than copied here, so the two
# can't drift apart.
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
ID_SHAPE='^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3})$'
RULE_IDS_LINE='^RULE_IDS="([a-z0-9/-]+( [a-z0-9/-]+)*)"$'

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

jqf "$TMP/shape" -r '
  def strs: type == "array" and all(.[]; type == "string");
  def ctl: explode | any(.[]; . < 32 or . == 127);
  ["id","status","summary","text","check","fixtures","level","timing","guards",
   "withhold","baseline_keys","aliases","notes"] as $fields
  | ["pr-create","push","force-push","merge","close-issue","release",
     "delete-branch","publish","destroy-record"] as $protected
  | .rules | to_entries[] | .key as $i | .value as $e
  | if ($e | type) != "object" then "entry \($i): not an object"
    else
      (if ($e.id | type) == "string" then $e.id else "entry \($i)" end) as $n
      | ($fields[] as $f | select(($e | has($f)) | not) | "\($n): missing field \($f)"),
        (select($e | has("id")) | $e.id
          | select(type != "string" or (test("^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3})$") | not))
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
            elif .kind == "none" then empty
            else "\($n): check.kind \(.kind | tojson) is not script, review-shadow or none" end),
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
            else (.[] | select(. != "none" and ($protected | index(.)) == null) | "\($n): guard \(tojson) is not in the vocabulary")
            end),
        (select(($e.guards | strs) and any($e.guards[]; . != "none") and $e.withhold == "eligible")
          | "\($n): a protected guard requires withhold never"),
        (select(($e.check | type) == "object" and $e.check.kind == "none" and $e.withhold == "eligible")
          | "\($n): check.kind none requires withhold never"),
        (select($e.level == "gate" and ($e.guards | strs) and all($e.guards[]; . == "none"))
          | "\($n): a gate entry needs a guard other than none"),
        (select($e.level == "prose" and ($e.check | type) == "object" and $e.check.kind != "none")
          | "\($n): a prose entry must have check.kind none")
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

    jqf "$TMP/reg-rs.raw" -r '.rules[] | objects | .id | strings | select(test("^rs-"))' "$REG"
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
jqf "$TMP/active" -r '.rules[] | objects | select(.status == "active") | .id | strings' "$REG"
while IFS= read -r id; do
    [[ $id =~ $ID_SHAPE ]] || continue
    if ! "$HELPER" --root "$ROOT" text "$id" > "$TMP/text" 2> "$TMP/text.err"; then
        problem "$id: its text does not resolve: $(head -n 1 "$TMP/text.err")"
        continue
    fi
    if grep -Eq "$MARK_LINE" "$TMP/text"; then
        problem "$id: its range holds a ::shirabe-rule marker line"
    fi
    if LC_ALL=C grep -q "$CTL" "$TMP/text"; then
        problem "$id: its range holds a control character other than tab"
    fi
done < "$TMP/active"

# ---------------------------------------------------------------- 6 and 10

is_active() {
    grep -qxF -- "$1" "$TMP/active"
}

# RULE_IDS lines: a gate script's whole list, at the start of a line,
# double-quoted ids separated by single spaces.
grep -rnE '^RULE_IDS=' "$ROOT/skills" "$ROOT/scripts" > "$TMP/rule-ids" 2>/dev/null
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

# Ids passed to `rule-registry.sh release` by the scripts that ship. The
# reader itself, its library, these checks and the test suites are not
# triggers. A release has to name its id literally so this can check it.
grep -rnE --include='*.sh' 'rule-registry\.sh"?[[:space:]]+release([[:space:]]|$)' "$ROOT/skills" "$ROOT/scripts" \
    > "$TMP/releases" 2>/dev/null
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    rel=${file#"$ROOT"/}
    case "$rel" in
        *_test.sh|scripts/rule-registry.sh|scripts/lib/*|scripts/check-rule-registry*.sh) continue ;;
    esac
    case "$text" in [[:space:]]*'#'*|'#'*) continue ;; esac
    id=$(printf '%s\n' "$text" | sed -E 's/.*rule-registry\.sh"?[[:space:]]+release[[:space:]]+([^[:space:]<>|&;]*).*/\1/')
    if ! [[ $id =~ $ID_SHAPE ]]; then
        problem "$rel:$lineno: release is passed [$id], not a literal rule id"
        continue
    fi
    if ! is_active "$id"; then
        problem "$rel:$lineno: releases $id, which is not an active registry entry"
        continue
    fi
    # The reader's own release rules decide; its one could-not-release line
    # is the answer.
    why=$("$HELPER" --root "$ROOT" release "$id" 2>&1 >/dev/null | grep '^rule-registry: could not release' | head -n 1)
    [ -z "$why" ] || problem "$rel:$lineno: $id would not be released: ${why#rule-registry: }"
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
        if grep -qiE 'rule tables?' "$TMP/d9"; then
            problem "DESIGN-output-gates.md Decision 9 still refers to the gate scripts' rule tables"
        fi
    fi
fi
grep -qF 'A **registered rule** is an id with an entry in `references/rule-registry.json`' "$REG_DOC" 2>/dev/null \
    || problem "references/rule-registry.md does not define a registered rule as an id with an entry in references/rule-registry.json"

# The check scripts and their suite name the removed table to look for it.
: > "$TMP/old-table"
for scan in skills scripts references docs/guides CLAUDE.md docs/designs/current/DESIGN-output-gates.md; do
    [ -e "$ROOT/$scan" ] || continue
    grep -rlF "$OLD_TABLE" "$ROOT/$scan" >> "$TMP/old-table" 2>/dev/null
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
            [ -n "$hit" ] || problem "$id: text.path $p is outside check-rule-registry.yml's paths filter"
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
    else
        echo "$PROG: the base has no registry; the id-removal check has nothing to compare"
    fi
fi

if [ "$PROBLEMS" -gt 0 ]; then
    echo "$PROG: $PROBLEMS problem(s)"
    exit 1
fi
echo "$PROG: ok"
exit 0
