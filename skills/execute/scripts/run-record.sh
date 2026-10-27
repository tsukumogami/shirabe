#!/usr/bin/env bash
# run-record.sh — for /execute: the one writer of a coordinated run's record.
#
# A coordinated run keeps its control-plane facts as `run/` keys in its koto
# session, `execute-<topic>` (the layout is in run-record-lib.sh, the one
# reader). Several steps write different facts, and each fact has one owning
# verb: this script holds the verb-to-field table below as data and refuses a
# write from any verb that doesn't own the field (exit 65 `not-owner`). A
# refused write changes nothing: the whole document is checked before any key
# is written.
#
# Usage: run-record.sh <verb> --session <S> --json <file>
#
#   <verb>     setup, push, observe, cascade, follow-up, recover, adopt, carry
#   <S>        the koto session, ^[A-Za-z0-9][A-Za-z0-9._-]*$
#   <file>     one JSON object {"<run/ key>": {<fields>}, ...}, one key or more
#
# The verbs, and the one script each is meant to be called from (the
# structure test checks the callers; this script does not):
#
#   setup      record-coord-setup.sh, sealing a new run's run/setup
#   push       node-push.sh node: a node's repo, pr, pushed head, and the
#              verification deferral reasons it carried at the push
#   observe    coord-render.sh, the coordination body's renderer: a merged
#              head it read live (the merge commit GitHub reports)
#   cascade    node-push.sh coordination (pushed, with the head) and
#              record-coordination-verdict.sh (failed, with the step); the one
#              verb with two callers, both steps of the cascade
#   follow-up  record-coord-setup.sh given --follow-up: a follow-up PR's repo,
#              pr and live head, or removed with --follow-up-remove
#   recover    record-coord-setup.sh rebuilding a lost record
#   adopt      record-coord-setup.sh on a recovering start with --adopt-run
#   carry      execute-open.sh, restoring a finished session's record into the
#              session koto replaced it with
#
# The verb-to-field table (key kind, fields, the verbs that own them). A
# field outside the verb's row for the key's kind is 65 `not-owner`; a field
# no verb owns, or a key outside the layout, is 66.
#
#   run/setup              store coordination_pr repos mode nodes run_lines
#                                                    setup recover carry
#   run/node/*             repo pr head deferrals    push recover carry
#   run/node/*             merged_head               observe recover carry
#   run/follow-up/*/*      repo pr head removed      follow-up recover carry
#   run/follow-up/*/*      merged_head               observe recover carry
#   run/cascade            verdict head step         cascade recover carry
#   run/recovered          pr source                 recover carry
#   run/adopted            id login at               adopt carry
#
# Values: store github|session; coordination_pr and a node's or follow-up's
# pr a positive integer; repos a sorted, de-duplicated array of owner/repo;
# mode `coordinated`; nodes an array of {name, kind (pr|gate), repo ("" for a
# gate), waits_on (node ids)} whose PR nodes' repositories are all in repos;
# run_lines an object whose keys are among topic, exit, outcome, intent, mode,
# each value ^[A-Za-z0-9._-]{1,64}$; repo owner/repo; head and merged_head 40
# hex; deferrals an array of distinct non-empty one-line strings (empty when
# the node deferred nothing); removed a boolean; verdict not-run|pushed|failed; step
# ^execute:[a-z-]+$; recovered's pr a pull request URL and source
# carried|run-line|markers|minted|adopted; id 32 hex; login a GitHub login; at
# UTC YYYY-MM-DDTHH:MM:SSZ. A follow-up's pr equals the <n> in its key.
#
# Write semantics. A verb that owns every field of the key's kind replaces the
# key (setup, cascade, recover, adopt, carry); any other merges into the
# stored object (push, observe, follow-up), so a push never clobbers a
# recorded merged_head. The result must hold the kind's required fields
# (run/setup all but run_lines; a node or follow-up repo, pr, head; run/cascade
# verdict, with head exactly when pushed and step exactly when failed;
# run/recovered and run/adopted all of theirs).
#
# Preconditions, read from the session: setup, recover and adopt refuse (67)
# when run/setup exists (a record is recovered only where there is none, and
# adopt is written just before recover seals it); push, observe, cascade and
# follow-up refuse (66) when it doesn't;
# push and follow-up refuse (66) a repo outside run/setup's repos; observe
# refuses (66) a key that doesn't exist yet; carry refuses (67) unless every
# run/ key the session already holds equals the document's value for it, so
# a carry that stopped part-way can be run again.
#
# Writes go in sorted key order with run/setup last, each through `koto
# context add <S> <key>` as canonical JSON (`jq -cS`). A failed add exits 70;
# keys earlier in the same call may already be written then.
#
# Output: `written=<key>` per key written. A refusal prints one line,
# `refused=<code>` with `key=<k>` and `field=<f>` when they apply, and a
# diagnostic on stderr. Codes: usage (64); not-owner (65); layout,
# unknown-field, invalid, incomplete, no-setup, repo-outside, absent (66);
# conflict (67). A koto failure prints `failed=koto-read` or
# `failed=koto-write key=<k>` (70).
#
# Exit codes:
#   0   written
#   64  usage error
#   65  not-owner: a field the verb doesn't own
#   66  invalid: a key or field outside the layout, a value outside its
#       pattern, a missing required field, or a precondition unmet
#   67  conflict: setup, recover or adopt over an existing record, or a
#       carry over a differing key
#   70  a koto read or write failed
#
# Requires: bash 3.2+, jq, koto.
set -uo pipefail

PROG=run-record

SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 64
# shellcheck source=run-record-lib.sh
. "$SELF_DIR/run-record-lib.sh"

RE_SESSION='^[A-Za-z0-9][A-Za-z0-9._-]*$'

# The verb-to-field table, as data: <kind> TAB <fields> TAB <owning verbs>.
OWNERS='setup	store coordination_pr repos mode nodes run_lines	setup recover carry
node	repo pr head deferrals	push recover carry
node	merged_head	observe recover carry
follow-up	repo pr head removed	follow-up recover carry
follow-up	merged_head	observe recover carry
cascade	verdict head step	cascade recover carry
recovered	pr source	recover carry
adopted	id login at	adopt carry'

usage_error() {
    printf 'refused=usage\n'
    echo "$PROG: $*" >&2
    echo "usage: run-record.sh <setup|push|observe|cascade|follow-up|recover|adopt|carry> --session <koto-session> --json <file>" >&2
    exit 64
}

[ $# -ge 1 ] || usage_error "a verb is required"
VERB="$1"; shift
case "$VERB" in
    setup|push|observe|cascade|follow-up|recover|adopt|carry) ;;
    *) usage_error "unknown verb [$VERB]" ;;
esac
SESSION=""; FILE=""
SEEN=" "
while [ $# -gt 0 ]; do
    case "$1" in
        --session|--json)
            [ $# -ge 2 ] || usage_error "$1 needs a value"
            case "$SEEN" in *" $1 "*) usage_error "$1 given more than once" ;; esac
            SEEN="$SEEN$1 "
            case "$1" in
                --session) SESSION="$2" ;;
                --json) FILE="$2" ;;
            esac
            shift 2
            ;;
        *) usage_error "unexpected argument [$1]" ;;
    esac
done
[[ $SESSION =~ $RE_SESSION ]] || usage_error "session [$SESSION] is not a koto session name"
[ -f "$FILE" ] || usage_error "no JSON document at [$FILE]"
command -v jq >/dev/null || { printf 'failed=koto-read\n'; echo "$PROG: jq is not on PATH" >&2; exit 70; }

refuse() { # refuse <exit> <code> [key] [field] [why]
    local line="refused=$2"
    [ -n "${3:-}" ] && line="$line key=$3"
    [ -n "${4:-}" ] && line="$line field=$4"
    printf '%s\n' "$line"
    echo "$PROG: $VERB refused ($2${3:+, $3}${4:+.$4})${5:+: $5}; nothing was written" >&2
    exit "$1"
}

DOC=$(jq -cS -s 'if length == 1 and (.[0] | type) == "object" and (.[0] | length) > 0
    and all(.[0][]; type == "object") then .[0] else error("no document") end' "$FILE") \
    || refuse 66 invalid "" "" "the document is not one non-empty JSON object of key objects"

CUR=$(rr_record "$SESSION") || { printf 'failed=koto-read\n'; echo "$PROG: could not read the run record in session $SESSION" >&2; exit 70; }

# The whole check, in one jq pass over the document and the stored record:
# the first failure, in order (layout and ownership per key, then values,
# then the merged result, then the preconditions), or the writes.
VERDICT=$(jq -nc --arg verb "$VERB" --arg owners "$OWNERS" --arg keyre "$RR_KEY_RE" \
    --argjson doc "$DOC" --argjson cur "$CUR" '
    ($owners | split("\n") | map(select(length > 0) | split("\t"))
     | reduce .[] as $r ({}; reduce ($r[1] | split(" "))[] as $f (.; .[$r[0]][$f] = ($r[2] | split(" ")))))
    as $own
    | def kind:
        if . == "run/setup" then "setup"
        elif . == "run/cascade" then "cascade"
        elif . == "run/recovered" then "recovered"
        elif . == "run/adopted" then "adopted"
        elif startswith("run/node/") then "node"
        elif startswith("run/follow-up/") then "follow-up"
        else "" end;
      def in_layout: test($keyre) and (startswith("run/node/coordination") | not)
        and (startswith("run/follow-up/coordination/") | not);
      def is_repo: type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
        and ((split("/") | map(. == "." or . == "..") | any) | not);
      def is_posint: type == "number" and . >= 1 and . == floor;
      def is_sha: type == "string" and test("^[0-9a-f]{40}$");
      def is_node: type == "string" and test("^[a-z][a-z0-9-]*$") and . != "coordination";
      def is_str($re): type == "string" and test($re);
      def valid($k; $f):
        if $f == "store" then . == "github" or . == "session"
        elif $f == "coordination_pr" then is_posint
        elif $f == "repos" then type == "array" and length > 0 and all(.[]; is_repo) and . == unique
        elif $f == "mode" then . == "coordinated"
        elif $f == "nodes" then type == "array" and length > 0
          and all(.[]; type == "object" and (keys == ["kind", "name", "repo", "waits_on"])
            and (.name | is_node) and (.kind == "pr" or .kind == "gate")
            and (if .kind == "pr" then (.repo | is_repo) else .repo == "" end)
            and (.waits_on | type == "array" and all(.[]; is_node)))
          and ((map(.name) | unique | length) == length)
        elif $f == "run_lines" then type == "object"
          and all(keys[]; . == "topic" or . == "exit" or . == "outcome" or . == "intent" or . == "mode")
          and all(.[]; is_str("^[A-Za-z0-9._-]{1,64}$"))
        elif $f == "repo" then is_repo
        elif $f == "pr" then (if ($k | kind) == "recovered"
          then is_str("^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$")
          else is_posint end)
        elif $f == "head" or $f == "merged_head" then is_sha
        elif $f == "deferrals" then type == "array"
          and all(.[]; type == "string" and length > 0 and (test("[\n\r]") | not))
          and ((unique | length) == length)
        elif $f == "removed" then type == "boolean"
        elif $f == "verdict" then . == "not-run" or . == "pushed" or . == "failed"
        elif $f == "step" then is_str("^execute:[a-z-]+$")
        elif $f == "source" then . == "carried" or . == "run-line" or . == "markers" or . == "minted" or . == "adopted"
        elif $f == "id" then is_str("^[0-9a-f]{32}$")
        elif $f == "login" then is_str("^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$")
        elif $f == "at" then is_str("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
        else false end;
      # A verb that owns every field of a kind replaces the key; any other
      # merges into the stored object.
      def replaces($kind): all($own[$kind][]; index($verb) != null);
      # The first required field the merged object lacks, or null.
      def required($kind):
        . as $o
        | if $kind == "setup" then ["store", "coordination_pr", "repos", "mode", "nodes"]
          elif $kind == "node" or $kind == "follow-up" then ["repo", "pr", "head"]
          elif $kind == "cascade" then ["verdict"]
          elif $kind == "recovered" then ["pr", "source"]
          else ["id", "login", "at"] end
        | map(select(. as $f | $o | has($f) | not)) | .[0]
        | if . == null and $kind == "cascade" then
            (if ($o.verdict == "pushed") != ($o | has("head")) then "head"
             elif ($o.verdict == "failed") != ($o | has("step")) then "step"
             else null end)
          else . end;
      def err($x; $c; $k; $f): {refuse: {exit: $x, code: $c, key: $k, field: $f}};
      # first_or(rest): the first refusal of a stage, else the stages after it.
      def first_or(rest): if length > 0 then .[0] else rest end;
      def merged($k): if replaces($k | kind) then $doc[$k] else (($cur[$k] // {}) + $doc[$k]) end;
      ($doc | keys) as $keys
      # 1. The layout, and the verb-to-field table.
      | [ $keys[] as $k
          | if ($k | in_layout | not) then err(66; "layout"; $k; "")
            else ($k | kind) as $kind
            | ($doc[$k] | keys[]) as $f
            | if ($own[$kind] | has($f) | not) then err(66; "unknown-field"; $k; $f)
              elif ($own[$kind][$f] | index($verb)) == null then err(65; "not-owner"; $k; $f)
              else empty end
            end ]
      | first_or(
          # 2. Every value against its pattern, and the run/setup PR nodes
          # in its repos.
          [ $keys[] as $k | ($doc[$k] | to_entries[]) as $e
            | if ($e.value | valid($k; $e.key)) then empty else err(66; "invalid"; $k; $e.key) end ]
          + [ $keys[] as $k | select(($k | kind) == "setup") | $doc[$k] as $s
              | select(($s | has("nodes")) and ($s | has("repos")))
              | $s.nodes[] | select(.kind == "pr") | select(.repo as $r | $s.repos | index($r) == null)
              | err(66; "repo-outside"; $k; "nodes") ]
          | first_or(
              # 3. The preconditions the session decides.
              (if ($verb == "setup" or $verb == "recover" or $verb == "adopt") and ($cur | has("run/setup"))
                 then [err(67; "conflict"; "run/setup"; "")]
               elif ($verb == "push" or $verb == "observe" or $verb == "cascade" or $verb == "follow-up")
                    and ($cur | has("run/setup") | not) then [err(66; "no-setup"; "run/setup"; "")]
               else [] end)
              + [ select($verb == "observe") | $keys[] | select(. as $k | $cur | has($k) | not)
                  | err(66; "absent"; .; "") ]
              + [ select($verb == "carry") | ($cur | keys[]) as $k
                  | select(($doc | has($k) | not) or $doc[$k] != $cur[$k])
                  | err(67; "conflict"; $k; "") ]
              | first_or(
                  # 4. The object each key would hold.
                  [ $keys[] as $k | ($k | kind) as $kind | merged($k) as $o
                    | ($o | required($kind)) as $missing
                    | if $missing != null then err(66; "incomplete"; $k; $missing)
                      elif $kind == "follow-up" and ($o.pr | tostring) != ($k | split("/") | .[3])
                        then err(66; "invalid"; $k; "pr")
                      elif ($verb == "push" or $verb == "follow-up")
                           and ($cur["run/setup"].repos | index($o.repo)) == null
                        then err(66; "repo-outside"; $k; "repo")
                      else empty end ]
                  | first_or(
                      # The writes: sorted, run/setup last.
                      {writes: [ (($keys | map(select(. != "run/setup"))) + ($keys | map(select(. == "run/setup"))))[] as $k
                                 | [$k, merged($k)] ]}))))
    ') || { echo "$PROG: the record check could not run" >&2; printf 'failed=koto-read\n'; exit 70; }

if printf '%s' "$VERDICT" | jq -e 'has("refuse")' >/dev/null; then
    refuse "$(printf '%s' "$VERDICT" | jq -r '.refuse.exit')" \
        "$(printf '%s' "$VERDICT" | jq -r '.refuse.code')" \
        "$(printf '%s' "$VERDICT" | jq -r '.refuse.key')" \
        "$(printf '%s' "$VERDICT" | jq -r '.refuse.field')"
fi

N=$(printf '%s' "$VERDICT" | jq '.writes | length')
i=0
while [ "$i" -lt "$N" ]; do
    K=$(printf '%s' "$VERDICT" | jq -r ".writes[$i][0]")
    V=$(printf '%s' "$VERDICT" | jq -cS ".writes[$i][1]")
    i=$((i + 1))
    printf '%s' "$V" | koto context add "$SESSION" "$K" >/dev/null || {
        printf 'failed=koto-write key=%s\n' "$K"
        echo "$PROG: could not write $K in session $SESSION; keys before it in this call may already be written" >&2
        exit 70
    }
    printf 'written=%s\n' "$K"
done
exit 0
