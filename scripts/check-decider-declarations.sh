#!/usr/bin/env bash
#
# check-decider-declarations.sh - hold shirabe's decider declarations to their
# modes table and their golden fixtures
#
# A koto template can declare an accepts field as decider-eligible with a
# `decider` block. koto compiles the block and enforces its own rules, but two
# things it has no view of are shirabe's to keep:
#
#   the modes -- every declared value ships in the mode the modes table,
#     scripts/decider-declarations.tsv, gives it. A value promoted in a
#     template without the table changing with it (or the reverse) fails here,
#     so a promotion is always an edit to both, reviewed together.
#
#   the fixtures -- every declaration has a golden fixture file beside its
#     template, <stem>.<state>.<field>.decider.jsonl, that meets the promotion
#     minimums `koto decider report --fixtures` applies: at least 10 cases per
#     declared value (the escape needs none) and 40 in all. Each line is a JSON
#     object with `inputs` (one string per declared input label, each within
#     that input's max_bytes, 8192 when unset), `expected` (a declared value or
#     the escape), and an optional `id`, unique in its file.
#
# Every accepts field with a `decider` block in skills/*/koto-templates/*.md
# is checked, the *.mermaid.md diagrams excluded. Discovery is a glob, so a new
# declaration is covered with no change here, and fails until it has a fixture
# file and table rows.
#
# The check reads files and nothing else. It never runs koto -- running the
# fixtures through a decider needs an opted-in user, an API key, and the
# network, which a pull request from a fork must not be able to spend -- and it
# makes no network call of any kind.
#
# Usage:
#   scripts/check-decider-declarations.sh [--root <dir>] [--table <tsv>]
#
# Options:
#   --root <dir>    the tree to check (default: this repository)
#   --table <tsv>   the modes table (default: <root>/scripts/decider-declarations.tsv)
#   -h, --help      this message
#
# Requires: bash 3.2 or later, jq, mikefarah yq v4.
#
# Exit codes:
#   0 - every declaration matches the table and has a passing fixture file
#   1 - a check failed; each failure names the template, state, field, and reason
#   2 - usage error, or a required tool is missing
#
# Bash 3.2: no associative arrays, no mapfile. Lists live in temp files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TABLE=""

# The promotion minimums koto's report applies to a fixture file.
MIN_PER_VALUE=10
MIN_TOTAL=40
DEFAULT_MAX_BYTES=8192

usage() {
    sed -e '1d' -e '/^[^#]/,$d' "$0" | sed 's/^#\{1,\} \{0,1\}//'
}

die() {
    echo "check-decider-declarations: $*" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || die "--root needs a directory"
            ROOT="$2"
            shift 2
            ;;
        --table)
            [ $# -ge 2 ] || die "--table needs a file"
            TABLE="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

[ -d "$ROOT" ] || die "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$TABLE" ] || TABLE="$ROOT/scripts/decider-declarations.tsv"

command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
command -v yq >/dev/null 2>&1 || die "yq is required (mikefarah yq v4) and is not on PATH"
case "$(yq --version 2>&1)" in
    *mikefarah/yq*' version v4.'* | *mikefarah/yq*' version 4.'*) ;;
    *) die "yq must be mikefarah yq v4; yq --version says [$(yq --version 2>&1)]" ;;
esac

WORK=$(mktemp -d) || die "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

TAB=$(printf '\t')
FAILURES=0

# fail <template> <state> <field> <reason>
fail() {
    echo "check-decider-declarations: FAIL: $1 state $2 field $3: $4" >&2
    FAILURES=$((FAILURES + 1))
}

# -- the declarations ---------------------------------------------------------
#
# declarations.jsonl gets one object per declared field:
#   {template, state, field, values, escape, labels: [{label, max}], modes: {value: mode}}
# and declared.tsv one row per declared value, in the table's shape.

: > "$WORK/declarations.jsonl"
for f in "$ROOT"/skills/*/koto-templates/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *.mermaid.md) continue ;; esac
    rel=${f#"$ROOT"/}
    if ! yq --front-matter=extract -o=json '.states // {}' "$f" > "$WORK/states.json" 2>"$WORK/yq.err"; then
        echo "check-decider-declarations: FAIL: $rel: yq could not read the front matter: $(cat "$WORK/yq.err")" >&2
        FAILURES=$((FAILURES + 1))
        continue
    fi
    jq -c --arg t "$rel" --argjson dflt "$DEFAULT_MAX_BYTES" '
        to_entries[] | .key as $s
        | ((.value.accepts // {}) | if type == "object" then to_entries[] else empty end)
        | select((.value | type) == "object" and (.value | has("decider")))
        | .key as $fld | .value as $spec | ($spec.decider // {}) as $d
        | {
            template: $t, state: $s, field: $fld,
            values: (if $spec.type == "boolean" then ["true", "false"]
                     else [($spec.values // [])[] | tostring] end),
            escape: (($d.escape // {}).value // null),
            labels: [($d.inputs // [])[] | {label: (.label | tostring), max: (.max_bytes // $dflt)}],
            modes: (($d.answers // {}) | with_entries(.value = ((.value // {}).mode // "shadow")))
          }
    ' "$WORK/states.json" >> "$WORK/declarations.jsonl" || {
        echo "check-decider-declarations: FAIL: $rel: could not read its accepts fields" >&2
        FAILURES=$((FAILURES + 1))
    }
done

jq -r '. as $d | $d.values[] | [$d.template, $d.state, $d.field, ., ($d.modes[.] // "shadow")] | @tsv' \
    "$WORK/declarations.jsonl" > "$WORK/declared.tsv"

# -- the modes table ----------------------------------------------------------

: > "$WORK/table.tsv"
if [ ! -f "$TABLE" ]; then
    echo "check-decider-declarations: FAIL: the modes table $TABLE does not exist" >&2
    FAILURES=$((FAILURES + 1))
else
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        case "$line" in ''|'#'*) continue ;; esac
        fields=$(printf '%s\n' "$line" | awk -F '\t' '{print NF}')
        if [ "$fields" -ne 5 ]; then
            echo "check-decider-declarations: FAIL: ${TABLE##*/} line $n has $fields tab-separated columns, want 5 (template, state, field, value, mode)" >&2
            FAILURES=$((FAILURES + 1))
            continue
        fi
        mode=$(printf '%s\n' "$line" | cut -f5)
        case "$mode" in
            off|shadow|auto|never) ;;
            *)
                echo "check-decider-declarations: FAIL: ${TABLE##*/} line $n: [$mode] is not a mode (off, shadow, auto, never)" >&2
                FAILURES=$((FAILURES + 1))
                continue
                ;;
        esac
        key=$(printf '%s\n' "$line" | cut -f1-4)
        if grep -Fxq "$key" "$WORK/table.keys" 2>/dev/null; then
            echo "check-decider-declarations: FAIL: ${TABLE##*/} line $n repeats a row for $(printf '%s' "$key" | tr '\t' ' ')" >&2
            FAILURES=$((FAILURES + 1))
            continue
        fi
        printf '%s\n' "$key" >> "$WORK/table.keys"
        printf '%s\n' "$line" >> "$WORK/table.tsv"
    done < "$TABLE"
fi

# Every declared value has a row with its effective mode.
while IFS="$TAB" read -r t s f v m; do
    [ -n "$t" ] || continue
    row=$(awk -F '\t' -v t="$t" -v s="$s" -v f="$f" -v v="$v" \
        '$1 == t && $2 == s && $3 == f && $4 == v {print $5; exit}' "$WORK/table.tsv")
    if [ -z "$row" ]; then
        fail "$t" "$s" "$f" "value [$v] is declared (mode $m) but has no row in ${TABLE##*/}"
    elif [ "$row" != "$m" ]; then
        fail "$t" "$s" "$f" "value [$v] has effective mode $m, but its row in ${TABLE##*/} says $row"
    fi
done < "$WORK/declared.tsv"

# Every row names a declared value.
while IFS="$TAB" read -r t s f v m; do
    [ -n "$t" ] || continue
    if ! awk -F '\t' -v t="$t" -v s="$s" -v f="$f" -v v="$v" \
        'BEGIN {found = 1} $1 == t && $2 == s && $3 == f && $4 == v {found = 0; exit} END {exit found}' "$WORK/declared.tsv"; then
        fail "$t" "$s" "$f" "${TABLE##*/} has a row for value [$v] (mode $m), but no template declares that value"
    fi
done < "$WORK/table.tsv"

# -- the fixtures -------------------------------------------------------------

# One jq pass per fixture file. Each raw line is parsed on its own, so a bad
# line is reported by number and the rest are still checked. Output lines are
# `E<TAB>reason` for a failure and `C<TAB>expected` for each case counted.
FIXTURE_JQ='
    def inlist($x; $l): any($l[]; . == $x);
    ($labels | map(.label) | sort) as $want
    | [inputs] | to_entries
    | (
        # duplicate ids across the file
        [ .[] | (try (.value | fromjson) catch null) as $o
          | select(($o | type) == "object" and ($o | has("id")))
          | {id: ($o.id | tojson), line: (.key + 1)} ]
        | group_by(.id)[] | select(length > 1)
        | "E\tid \(.[0].id) is used on lines \(map(.line | tostring) | join(", ")); ids must be unique in the file"
      ),
      ( .[] | (.key + 1) as $n | .value as $raw
        | (try ($raw | fromjson) catch "\u0000unparsed") as $o
        | if ($raw | test("^[[:space:]]*$")) then "E\tline \($n) is empty; every line must be one JSON object"
          elif $o == "\u0000unparsed" then "E\tline \($n) is not valid JSON"
          elif ($o | type) != "object" then "E\tline \($n) is a JSON \($o | type), not an object"
          else
            ([$o | keys[] | select(inlist(.; ["id", "inputs", "expected"]) | not)]) as $extra
            | ($o.expected | if type == "boolean" then tostring else . end) as $exp
            | if ($extra | length) > 0 then "E\tline \($n) has key(s) \($extra | join(", ")); only id, inputs, and expected are allowed"
              elif ($o | has("expected") | not) then "E\tline \($n) has no expected"
              elif ($o | has("inputs") | not) then "E\tline \($n) has no inputs"
              elif ($o.inputs | type) != "object" then "E\tline \($n): inputs is a JSON \($o.inputs | type), not an object"
              elif (($exp | type) != "string") or ((inlist($exp; $values) or ($escape != null and $exp == $escape)) | not)
                then "E\tline \($n): expected \($o.expected | tojson) is neither a declared value (\($values | join(", ")))\(if $escape != null then " nor the escape (\($escape))" else "" end)"
              elif ($o.inputs | keys) != $want
                then "E\tline \($n): input labels [\($o.inputs | keys | join(", "))] differ from the declared labels [\($want | join(", "))]"
              else
                ( [ $labels[] as $l | $o.inputs[$l.label] as $v
                    | if ($v | type) != "string" then "E\tline \($n): input \($l.label) is a JSON \($v | type), not a string"
                      elif ($v | utf8bytelength) > $l.max then "E\tline \($n): input \($l.label) is \($v | utf8bytelength) bytes, over its max_bytes of \($l.max)"
                      else empty end ] ) as $errs
                | if ($errs | length) > 0 then $errs[] else "C\t\($exp)" end
              end
          end
      )
'

while IFS= read -r decl; do
    [ -n "$decl" ] || continue
    t=$(printf '%s' "$decl" | jq -r .template)
    s=$(printf '%s' "$decl" | jq -r .state)
    f=$(printf '%s' "$decl" | jq -r .field)
    dir=$(dirname "$ROOT/$t")
    stem=$(basename "$t" .md)
    fixture="$dir/$stem.$s.$f.decider.jsonl"
    fixture_rel=${fixture#"$ROOT"/}

    if [ ! -f "$fixture" ]; then
        fail "$t" "$s" "$f" "no fixture file at $fixture_rel"
        continue
    fi

    if ! jq -nR -r \
        --argjson values "$(printf '%s' "$decl" | jq -c .values)" \
        --argjson escape "$(printf '%s' "$decl" | jq -c .escape)" \
        --argjson labels "$(printf '%s' "$decl" | jq -c .labels)" \
        "$FIXTURE_JQ" < "$fixture" > "$WORK/result" 2>"$WORK/jq.err"; then
        fail "$t" "$s" "$f" "could not read $fixture_rel: $(cat "$WORK/jq.err")"
        continue
    fi

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        fail "$t" "$s" "$f" "$fixture_rel ${line#E"$TAB"}"
    done <<EOF
$(grep "^E$TAB" "$WORK/result")
EOF

    total=$(grep -c "^C$TAB" "$WORK/result")
    summary=""
    for v in $(printf '%s' "$decl" | jq -r '.values[]'); do
        count=$(grep -cx "C$TAB$v" "$WORK/result")
        summary="$summary $v=$count"
        if [ "$count" -lt "$MIN_PER_VALUE" ]; then
            fail "$t" "$s" "$f" "$fixture_rel has $count case(s) labelled $v; every declared value needs at least $MIN_PER_VALUE"
        fi
    done
    esc=$(printf '%s' "$decl" | jq -r '.escape // empty')
    if [ -n "$esc" ]; then
        summary="$summary $esc=$(grep -cx "C$TAB$esc" "$WORK/result")"
    fi
    if [ "$total" -lt "$MIN_TOTAL" ]; then
        fail "$t" "$s" "$f" "$fixture_rel has $total case(s) in all; it needs at least $MIN_TOTAL"
    fi
    echo "  $t $s.$f: $fixture_rel, $total cases ($(printf '%s' "$summary" | sed 's/^ //'))"
done < "$WORK/declarations.jsonl"

declared=$(wc -l < "$WORK/declarations.jsonl" | tr -d ' ')
values=$(wc -l < "$WORK/declared.tsv" | tr -d ' ')
if [ "$FAILURES" -eq 0 ]; then
    echo "check-decider-declarations: PASS - $declared declared field(s), $values value(s), all matching ${TABLE##*/}"
    exit 0
fi
echo "check-decider-declarations: FAIL - $FAILURES failure(s)" >&2
exit 1
