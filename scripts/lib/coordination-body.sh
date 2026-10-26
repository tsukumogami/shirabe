# coordination-body.sh -- the coordination pull request's body, rendered from
# a coordinated run's record and read back for recovery.
#
# Sourced, never run. The body of a coordination PR is the rendering of the
# run's record (the `run/` keys in its koto session), not a document anyone
# edits field by field: /execute's coord-render.sh builds one JSON document
# from the record, the live Part 1 and each indexed PR's live state, calls
# cb_render, and posts the result only when it differs from the live body.
# Nothing here reads GitHub or koto; every function works on files and JSON,
# so each one is testable byte for byte.
#
# The rendered body, exactly (one trailing newline):
#
#   <Part 1: the live one byte for byte, or the composed sentence>---
#
#   > This is a **coordination PR** for a coordinated effort. It is docs-only and
#   > merges **last**, once every indexed PR has merged and finalization is complete.
#   > See `references/coordination-strategy.md`.
#
#   topic=<v>      /scope's run lines, in this order, each only when recorded
#   exit=<v>
#   outcome=<v>
#   intent=<v>
#   mode=<v>
#   store=<github|session>
#   run=<32 hex>   left out when the document's run is ""
#   Run record: <session> (run <32 hex>)   the document's reference, left out
#                  when it is "" or absent (the run's switch is omit)
#
#   ## PR Index
#
#   - <node> | <owner/repo>:docs/plans/PLAN-<topic>.md#<n> | <state> | head=<sha>
#   - <node>/follow-up-<n> | <owner/repo>:docs/plans/PLAN-<topic>.md#<n> | <state> | head=<sha>
#
#   ## Merge Order
#
#   ```merge-order
#   # Rendered by /execute from the node list the run sealed at setup; not read by the merge gate.
#   # One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>
#   <node-id> | <pr|gate> | after: <node-ids joined ", ", or ->
#   ```
#
# Under omit (the document's `content` is "omit"), the body is Part 1 alone,
# with nothing after it: no separator, declaration, run lines, reference, PR
# index or merge order. Part 1 is then the live one (the caller passes the
# whole live body when it has no top-level `---`), or the composed sentence
# when the live body is empty. Nothing is indexed, so no visibility refusal
# arises; only the size cap applies. `content` absent reads include.
#
# The composed Part 1, used when the live body has no top-level `---`, is
# `Coordination pull request for <topic>. It carries the planning documents
# for <n> node pull requests and merges after all of them.` and a blank line,
# where <n> counts the `pr` nodes. The index lists the PR nodes in the order
# run/setup sealed them, only those with a recorded PR, each followed by its
# follow-ups (sorted by number, a removed one left out); a state the document
# doesn't hold is `unknown`; head= is the recorded merged_head, else the
# pushed head. The coordination PR never indexes itself. The merge-order
# section comes from run/setup's node list, so it outlives the PLAN, and
# skills/execute/scripts/testdata/merge-order-gated.txt pins its shape for the
# validator's own tests.
#
# Functions:
#
#   cb_render <doc.json>
#       Print the body (jq -j). Returns 0; 2 the document is invalid (a field
#       missing or outside its pattern, or an indexed repository with no
#       visibility under a public home); 3 an indexed repository is private
#       under a public home: the diagnostic names the node id, never the
#       repository, and nothing is printed; 4 the body would be over
#       CB_MAX_BYTES (UTF-8 bytes), nothing printed. The document:
#         {topic, part1: <string>|null, content?: include|omit,
#          reference?: <string>, run_lines: {topic?, exit?, outcome?,
#          intent?, mode?}, store, run: <32 hex>|"", nodes: <run/setup nodes>,
#          records: {<node>: <run/node/<node>>},
#          follow_ups: {<node>: [<run/follow-up/<node>/<n>>, ...]},
#          states: {"<owner/repo>#<n>": "open|merged|closed|unknown"},
#          home: {repo, pr, visibility}, visibility: {<owner/repo>: <vis>}}
#
#   cb_part1 <body-file>
#       Print Part 1 byte for byte: every line before the first line matching
#       ^[ \t]*---[ \t\r]*$ outside a ``` fence, each with its own line ending
#       (a \r kept). Returns 0, or 1 printing nothing when there is no such
#       line. The fence and separator rule is scripts/lib/squash-message.sh's,
#       so the squash message and the render agree on what Part 1 is. Write
#       its output to a file: $(...) strips trailing newlines.
#
#   cb_parse <body-file> [<self-repo> <self-number>]
#       Read a rendered or an older body back into a map. Its callers are
#       record-coord-setup.sh's new-run and recovery paths, the one place a
#       coordination PR's body is read. Prints one JSON object:
#         {"index": <a `## PR Index` section exists in the region>,
#          "nodes": {<node>: {repo, pr, state}},
#          "follow_ups": {<node>: [{repo, pr, state, fu}, ...]},
#          "run": <the first ^run=<32 hex>$ line's id, or null>,
#          "store": <the first ^store=(github|session)$ line's value, or null>,
#          "run_lines": {topic?, exit?, outcome?, intent?, mode?}}
#       The region. A body with a top-level `---` (cb_part1's rule: a line
#       matching ^[ \t]*---[ \t\r]*$ outside a ``` fence) is read only below
#       the first one, so nothing in Part 1 (a `## ` heading, a `run=` line,
#       a section someone titled `## PR Index`) is read as the record's. A
#       body with none (/scope's, or one from before the render) is read
#       whole, and its `run` is null: only a render writes `run=`. `run=`,
#       `store=` and the run lines come from the region above its first `## `
#       heading, the first well-formed line of each key (a run line's value
#       ^[A-Za-z0-9._-]{1,64}$, as run/setup holds it); the entries come from
#       the region's `## PR Index` section. A line for node `coordination`
#       (an older body's self row) is dropped, and so is a line whose ref is
#       <self-repo>#<self-number> when given (the repository compared
#       case-insensitively). A follow-up's `fu` is the number its id names
#       (<node>/follow-up-<fu>), kept beside the ref's `pr` so a reader can
#       refuse a line whose two numbers differ. Heads are never returned: a
#       head on a page is never trusted. Returns 0; 2 the file can't be read; 3 the body is
#       over CB_MAX_BYTES (nothing read); 4 an entry-shaped line outside the
#       grammar, a bad repository or path, or a node named twice (the line
#       number on stderr).
#
#   cb_parse_entry <line>
#       Set CB_E_NODE, CB_E_FU (the follow-up's number, or empty), CB_E_REPO,
#       CB_E_PATH, CB_E_NUM, CB_E_STATE. Returns 1 when the line is outside
#       CB_RE_ENTRY, or its repository or path is unusable (a `.` or `..`
#       segment, an absolute path, an empty segment).
#
# The index-entry grammar lives here and nowhere else. A head is matched and
# never captured.
#
# Callers may set PROG for diagnostics. Written for the bash 3.2 floor.
# Requires: jq (1.6+), awk.

CB_MAX_BYTES=60000
CB_RE_ENTRY='^- ([a-z][a-z0-9-]*)(/follow-up-([1-9][0-9]*))? \| ([A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+):([^ |#]+)#([1-9][0-9]*) \| (open|merged|closed|unknown)( \| head=[0-9a-f]{40})?[[:space:]]*$'
CB_RE_ENTRY_LIKE='^- [^|]+\|'
# The run lines cb_parse reads, with the value pattern run/setup holds them to.
CB_RE_RUN_LINE='^(topic|exit|outcome|intent|mode)=([A-Za-z0-9._-]{1,64})$'
CB_RE_STORE_LINE='^store=(github|session)$'

# The render, as one jq program: `check` reports {code[, node]}, `body` is the
# text. Both run over the same definitions, so what is checked is what renders.
read -r -d '' CB_JQ <<'JQ' || true
def is_repo: type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
    and ((split("/") | map(. == "." or . == "..") | any) | not);
def is_sha: type == "string" and test("^[0-9a-f]{40}$");
def is_posint: type == "number" and . >= 1 and . == floor;
def is_node: type == "string" and test("^[a-z][a-z0-9-]*$") and . != "coordination";
def is_rec: type == "object" and (.repo | is_repo) and (.pr | is_posint) and (.head | is_sha)
    and ((has("merged_head") | not) or (.merged_head | is_sha))
    and ((has("removed") | not) or (.removed | type == "boolean"));
def is_vis: . == "public" or . == "private";
def valid:
    type == "object"
    and (.topic | type == "string" and test("^[a-z0-9-]+$"))
    and (.part1 == null or (.part1 | type == "string"))
    and ((has("content") | not) or .content == "include" or .content == "omit")
    and ((has("reference") | not) or (.reference | type == "string" and test("^(Run record: [A-Za-z0-9][A-Za-z0-9._-]* \\(run [0-9a-f]{32}\\))?$")))
    and (.run_lines | type == "object"
        and all(keys[]; . == "topic" or . == "exit" or . == "outcome" or . == "intent" or . == "mode")
        and all(.[]; type == "string" and test("^[A-Za-z0-9._-]{1,64}$")))
    and (.store == "github" or .store == "session")
    and (.run | type == "string" and (. == "" or test("^[0-9a-f]{32}$")))
    and (.nodes | type == "array" and length > 0
        and all(.[]; type == "object" and (.name | is_node) and (.kind == "pr" or .kind == "gate")
            and (if .kind == "pr" then (.repo | is_repo) else true end)
            and (.waits_on | type == "array" and all(.[]; is_node))))
    and (.records | type == "object" and all(.[]; is_rec))
    and (.follow_ups | type == "object" and all(.[]; type == "array" and all(.[]; is_rec)))
    and (.states | type == "object"
        and all(.[]; . == "open" or . == "merged" or . == "closed" or . == "unknown"))
    and (.home | type == "object" and (.repo | is_repo) and (.pr | is_posint) and (.visibility | is_vis))
    and (.visibility | type == "object" and all(.[]; is_vis));
# The index lines, in order: each PR node with a record, then its follow-ups.
def entries:
    . as $d
    | [ $d.nodes[] | select(.kind == "pr") | .name as $n | select($d.records | has($n))
        | ({id: $n, node: $n} + ($d.records[$n] | {repo, pr, head: (.merged_head // .head)})),
          (($d.follow_ups[$n] // []) | map(select((.removed // false) | not)) | sort_by(.pr) | .[]
           | {id: "\($n)/follow-up-\(.pr)", node: $n, repo, pr, head: (.merged_head // .head)}) ];
def vis($r):
    if ($r | ascii_downcase) == (.home.repo | ascii_downcase) then .home.visibility
    else .visibility[$r] end;
def part1:
    if .part1 == null then
        "Coordination pull request for \(.topic). It carries the planning documents for \([.nodes[] | select(.kind == "pr")] | length) node pull requests and merges after all of them.\n\n"
    else .part1 end;
def omit: (.content // "include") == "omit";
def body:
    . as $d
    | entries as $es
    | if $d | omit then $d | part1 else
      ($d | part1)
      + "---\n\n"
      + "> This is a **coordination PR** for a coordinated effort. It is docs-only and\n"
      + "> merges **last**, once every indexed PR has merged and finalization is complete.\n"
      + "> See `references/coordination-strategy.md`.\n\n"
      + ([("topic", "exit", "outcome", "intent", "mode") as $k | select($d.run_lines | has($k))
          | "\($k)=\($d.run_lines[$k])\n"] | join(""))
      + "store=\($d.store)\n"
      + (if $d.run == "" then "" else "run=\($d.run)\n" end)
      + (if ($d.reference // "") == "" then "" else "\($d.reference)\n" end)
      + "\n## PR Index\n\n"
      + (if ($es | length) == 0 then ""
         else ($es | map("- \(.id) | \(.repo):docs/plans/PLAN-\($d.topic).md#\(.pr) | \($d.states["\(.repo)#\(.pr)"] // "unknown") | head=\(.head)\n") | join("")) + "\n"
         end)
      + "## Merge Order\n\n```merge-order\n"
      + "# Rendered by /execute from the node list the run sealed at setup; not read by the merge gate.\n"
      + "# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>\n"
      + ($d.nodes | map("\(.name) | \(.kind) | after: \(if (.waits_on | length) == 0 then "-" else (.waits_on | join(", ")) end)\n") | join(""))
      + "```\n"
      end;
def check:
    if valid | not then {code: 2}
    elif omit then (body | utf8bytelength) as $n
      | if $n > $max then {code: 4, bytes: $n} else {code: 0} end
    else . as $d
      | [entries[] | . as $e | {id: $e.id, vis: ($d | vis($e.repo))}] as $vs
      | if $d.home.visibility == "public" and any($vs[]; .vis == null) then {code: 2}
        elif $d.home.visibility == "public" and any($vs[]; .vis == "private") then
          {code: 3, node: ([$vs[] | select(.vis == "private")][0].id)}
        else (body | utf8bytelength) as $n
          | if $n > $max then {code: 4, bytes: $n} else {code: 0} end
        end
    end;
JQ

cb_render() {
    local verdict code
    verdict=$(jq -c --argjson max "$CB_MAX_BYTES" "$CB_JQ check" "$1") || {
        echo "${PROG:-coordination-body}: the render document [$1] is not JSON jq could read" >&2
        return 2
    }
    code=$(printf '%s' "$verdict" | jq -r '.code') || return 2
    case "$code" in
        0) ;;
        2) echo "${PROG:-coordination-body}: the render document is invalid: a field is missing or outside its pattern, or an indexed repository has no visibility under a public coordination PR" >&2
           return 2 ;;
        3) echo "${PROG:-coordination-body}: refused: $(printf '%s' "$verdict" | jq -r '.node') lands in a private repository, and the coordination PR is public; a public coordination PR never indexes a private pull request" >&2
           return 3 ;;
        4) echo "${PROG:-coordination-body}: the rendered body would be $(printf '%s' "$verdict" | jq -r '.bytes') bytes, over the $CB_MAX_BYTES-byte cap" >&2
           return 4 ;;
        *) return 2 ;;
    esac
    jq -j --argjson max "$CB_MAX_BYTES" "$CB_JQ body" "$1"
}

cb_part1() {
    [ -r "$1" ] || return 1
    awk '
        { line = $0; sub(/\r$/, "", line) }
        line ~ /^[ \t]*```/ { fence = !fence; buf[++n] = $0; next }
        !fence && line ~ /^[ \t]*---[ \t]*$/ { found = 1; exit }
        { buf[++n] = $0 }
        END {
            if (!found) exit 1
            for (i = 1; i <= n; i++) printf "%s\n", buf[i]
        }
    ' "$1"
}

cb_parse_entry() {
    CB_E_NODE=""; CB_E_FU=""; CB_E_REPO=""; CB_E_PATH=""; CB_E_NUM=""; CB_E_STATE=""
    [[ $1 =~ $CB_RE_ENTRY ]] || return 1
    CB_E_NODE="${BASH_REMATCH[1]}"
    CB_E_FU="${BASH_REMATCH[3]}"
    CB_E_REPO="${BASH_REMATCH[4]}"
    CB_E_PATH="${BASH_REMATCH[5]}"
    CB_E_NUM="${BASH_REMATCH[6]}"
    CB_E_STATE="${BASH_REMATCH[7]}"
    case "/$CB_E_REPO/" in */./*|*/../*) return 1 ;; esac
    case "/$CB_E_PATH/" in */./*|*/../*|*//*) return 1 ;; esac
    return 0
}

cb_parse() {
    local file="$1" self_repo="${2:-}" self_num="${3:-}" size line lineno=0 insec=0 seen_heading=0
    local index=false run="" store="" lines="" rows="" seen=" " key val self_lc sep
    [ -r "$file" ] && [ -f "$file" ] || {
        echo "${PROG:-coordination-body}: can't read the body file [$file]" >&2
        return 2
    }
    size=$(wc -c < "$file") || return 2
    size=$((size + 0))
    if [ "$size" -gt "$CB_MAX_BYTES" ]; then
        echo "${PROG:-coordination-body}: the body is $size bytes, over the $CB_MAX_BYTES-byte cap; not reading it" >&2
        return 3
    fi
    # The region: below the first top-level `---` (cb_part1's rule), else the
    # whole body. sep is that line's number, 0 when there is none.
    sep=$(awk '
        { line = $0; sub(/\r$/, "", line) }
        line ~ /^[ \t]*```/ { fence = !fence; next }
        !fence && line ~ /^[ \t]*---[ \t]*$/ { print NR; found = 1; exit }
        END { if (!found) print 0 }
    ' "$file") || return 2
    self_lc=$(printf '%s' "$self_repo" | tr 'A-Z' 'a-z')
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        [ "$lineno" -le "$sep" ] && continue
        line="${line%$'\r'}"
        case "$line" in
            "## "*)
                seen_heading=1
                if [[ $line =~ ^##\ PR\ Index[[:space:]]*$ ]]; then insec=1; index=true; else insec=0; fi
                continue
                ;;
        esac
        if [ "$seen_heading" -eq 0 ]; then
            # Above the region's first heading: the run lines, the first
            # well-formed one of each key. Only a render writes run=, below
            # its separator.
            if [ "$sep" -gt 0 ] && [ -z "$run" ] && [[ $line =~ ^run=[0-9a-f]{32}$ ]]; then
                run="${line#run=}"
            elif [ -z "$store" ] && [[ $line =~ $CB_RE_STORE_LINE ]]; then
                store="${line#store=}"
            elif [[ $line =~ $CB_RE_RUN_LINE ]]; then
                key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
                case " $lines" in
                    *" $key="*) ;;
                    *) lines="$lines$key=$val " ;;
                esac
            fi
            continue
        fi
        [ "$insec" -eq 1 ] || continue
        [[ $line =~ $CB_RE_ENTRY_LIKE ]] || continue
        if ! cb_parse_entry "$line"; then
            echo "${PROG:-coordination-body}: line $lineno of the PR index is outside the entry grammar, or names an unusable repository or path" >&2
            return 4
        fi
        [ "$CB_E_NODE" = coordination ] && continue
        if [ -n "$self_repo" ] && [ "$(printf '%s' "$CB_E_REPO" | tr 'A-Z' 'a-z')" = "$self_lc" ] \
            && [ "$CB_E_NUM" = "$self_num" ]; then
            continue
        fi
        key="$CB_E_NODE${CB_E_FU:+/follow-up-$CB_E_FU}"
        case "$seen" in
            *" $key "*)
                echo "${PROG:-coordination-body}: line $lineno of the PR index names $key a second time" >&2
                return 4
                ;;
        esac
        seen="$seen$key "
        rows="$rows$CB_E_NODE	$CB_E_FU	$CB_E_REPO	$CB_E_NUM	$CB_E_STATE
"
    done < "$file"
    printf '%s' "$rows" | jq -RncS --argjson index "$index" --arg run "$run" --arg store "$store" \
        --arg lines "$lines" '
        [inputs | select(length > 0) | split("\t")
         | {node: .[0], fu: .[1], v: ({repo: .[2], pr: (.[3] | tonumber), state: .[4]}
              + (if .[1] == "" then {} else {fu: (.[1] | tonumber)} end))}] as $rs
        | {index: $index,
           nodes: ([$rs[] | select(.fu == "") | {(.node): .v}] | add // {}),
           follow_ups: (reduce ($rs[] | select(.fu != "")) as $r ({}; .[$r.node] += [$r.v])
                        | map_values(sort_by(.pr))),
           run: (if $run == "" then null else $run end),
           store: (if $store == "" then null else $store end),
           run_lines: ([$lines | split(" ")[] | select(length > 0) | capture("^(?<k>[a-z]+)=(?<v>.*)$")
                        | {(.k): .v}] | add // {})}'
}
