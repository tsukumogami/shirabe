#!/usr/bin/env bash
# render-brief.sh -- render a worker's brief from structured input.
#
# A brief is a worker's only context, and a section left out is something a
# worker starting cold can't notice is missing. So the coordinator never writes
# a brief by hand: it assembles one JSON object (stored in its koto session as
# brief_input.json) and this script checks every field and renders the
# sections of skills/coordinate/references/brief-template.md in order, adding
# the lines every brief carries. A refused input writes nothing anywhere.
#
# Input fields (a JSON object):
#
#   topic               required  the dispatch topic, ^[a-z0-9][a-z0-9-]*$
#   repo                required  owner/repo
#   unit                required  the unit of work, one line, as the holding's
#                                 Unit cell names it: a roadmap feature's
#                                 heading tag ("Feature 2") or "<tag>:
#                                 <title>", an issue's "#12" or
#                                 "owner/repo#12", or a unit a person
#                                 assigned as the record names it (an issue,
#                                 or "release owner/repo <tag>"), the forms
#                                 pick reads.
#                                 With --units, any other form is refused
#   entry_point         required  a skill listed in references/entry-points.tsv
#   entry_args          required  JSON array of tokens: the positional argument
#                                 first, then flags from the entry point's
#                                 allowed set
#   run_mode            required  the execution flags, space-separated, each
#                                 from the allowed set; empty only for an
#                                 entry point that takes neither --auto nor
#                                 --interactive (/shirabe:release)
#   phase               required  scoping-ahead or executing
#   authority           required  the authority sentence, in the human's voice
#   goal                required  one or two sentences
#   checkpoints         required  1+ strings; the last is where the worker
#                                 stops. None may contain "approv" or "wait
#                                 for": a worker never waits on an approval.
#   acceptance          required  1+ strings
#   dispatcher_session  required  the coordinator's koto session name, one
#                                 line: the run the worker's request leg
#                                 names as its requester, never an address
#   reports_to          required  the address the worker messages its
#                                 reports to: the record's Run `coordinator`
#                                 address, which dispatch-worker.sh writes
#                                 in from the record (shirabe#610)
#   decisions           optional  [{decision, by}]
#   read_first          optional  pointers: a repository-relative path, #n,
#                                 owner/repo#n, or an https:// URL
#   out_of_scope        optional  strings, beyond the standing exclusions
#   surfaces            optional  [{surface, coordinator}], one line each
#   standing_rules      optional  the workspace's own rules for workers,
#                                 copied verbatim
#   targets             optional  owner/repo strings: the repositories the
#                                 unit lands in besides `repo`. For a unit
#                                 driven by a PLAN (/execute, or a scoped
#                                 unit's execution), the repositories its
#                                 issues land in. Required, non-empty, when
#                                 the entry point's row pins `plan-slug`
#                                 (today /execute) and restricts its
#                                 targets' visibility.
#   review_level        optional  {floor, ceiling}, one or both, each light,
#                                 standard or full, the floor no higher than
#                                 the ceiling: the bound on the review level
#                                 every /work-on run under this worker picks.
#                                 Rendered as one Acceptance criteria line
#                                 and as --review-floor=<x> and
#                                 --review-ceiling=<y> on the invocation
#                                 (dispatch-common.sh dc_invocation). Refused
#                                 on an entry point whose row in
#                                 entry-points.tsv doesn't admit the flags.
#                                 The flags themselves are refused in
#                                 entry_args and run_mode: this field is
#                                 their only route, so the level names are
#                                 always checked. Absent, the brief is what
#                                 it was before the field existed.
#
# The entry point's target requirement. references/entry-points.tsv gives each
# entry point the visibility its targets must have (`any`, `public` or
# `private`). When it isn't `any`, each target (`repo`, then every `targets`
# entry) is read live from GitHub (`gh api repos/<r>`), and a target the entry
# point can't take refuses the input, naming the entry point to use instead.
# The refusal names the target by its field (`repo`, `targets[1]`), never the
# repository, so a private repository's name doesn't travel in the message. A
# visibility that can't be read exits 2: never read as a pass. With `any`, no
# read is made. The first target refused ends the reads.
#
# No value may carry a UUID-shaped token, so a session id never reaches a
# brief; a session name, which the worker needs to reach its coordinator, is
# not an id.
#
# Usage:
#   render-brief.sh --input <file> [--workspace-root <dir>] [--return-path <rp>] [--units <pick.json>] [--stdout]
#
#   --workspace-root  where .niwa/dispatch-briefs/ lives; found with
#                     dc_workspace_root when absent
#   --return-path     the worker's return path, `<request-id>:<leg>` or
#                     `message` (the default); a leg adds --koto-leg to the
#                     invocation the brief shows, so the brief and the
#                     dispatch prompt name the same command
#   --stdout          print the brief instead of writing it
#   --units           the units pick_facts listed (coord/pick.json): the unit
#                     must be a form pick reads as covering one of them
#                     (dispatch-common.sh dc_unit_forms), else the input is
#                     refused, naming the forms that would match.
#                     dispatch-worker.sh passes it on every new dispatch;
#                     a re-brief, or a resumed dispatch whose holding
#                     already records the unit, isn't checked
#   --targets-checked skip the entry point's target requirement: the caller
#                     already checked this input (dispatch-worker.sh's second
#                     render, after its leg is open, so a flaky read there
#                     can't strand the leg)
#
# Output: the written brief's path, or the brief with --stdout. The reason for
# a refusal on stderr, one line per problem.
#
# Exit codes:
#   0  written (or printed)
#   1  input refused; nothing written
#   2  usage error, unreadable input, no workspace root, a target's
#      visibility that can't be read live, or an entry-points.tsv
#      visibility value other than any, public or private
#
# Writes only <workspace-root>/.niwa/dispatch-briefs/<topic>.md, through a
# temporary file in the same directory and a rename. bash 3.2; needs jq.
set -uo pipefail

PROG=render-brief
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh"

usage() {
    printf 'usage: %s --input <file> [--workspace-root <dir>] [--return-path <rp>] [--units <pick.json>] [--stdout]\n' "$PROG" >&2
    exit 2
}

INPUT=""
ROOT=""
TO_STDOUT=0
SKIP_TARGETS=0
RETURN_PATH=message
UNITS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --input) [ $# -ge 2 ] || usage; INPUT="$2"; shift 2 ;;
        --workspace-root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --return-path) [ $# -ge 2 ] || usage; RETURN_PATH="$2"; shift 2 ;;
        --stdout) TO_STDOUT=1; shift ;;
        --targets-checked) SKIP_TARGETS=1; shift ;;
        --units) [ $# -ge 2 ] || usage; UNITS="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$INPUT" ] || usage
[ -r "$INPUT" ] || { printf '%s: cannot read %s\n' "$PROG" "$INPUT" >&2; exit 2; }
jq -e 'type == "object"' "$INPUT" >/dev/null || {
    printf '%s: input is not a JSON object\n' "$PROG" >&2
    exit 2
}

PROBLEMS=""
refuse() { PROBLEMS="${PROBLEMS}$1
"; }

# --- structural checks, in jq ----------------------------------------------------

JQ_CHECKS='
def str($k): (.[$k] | type == "string") and ((.[$k] // "") | test("\\S"));
def oneline($s): ($s | test("[\\r\\n]") | not);
def strs($k): (.[$k] | type == "array") and all(.[$k][]; type == "string" and test("\\S"));
def uuid: test("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
. as $in | (
( ["topic","repo","unit","entry_point","phase","authority","goal","dispatcher_session","reports_to"][]
  | . as $k | select(($in | str($k)) | not) | "\($k): required and must be a non-empty string" ),
( if (.run_mode | type) != "string" then "run_mode: required, a string (empty only for an entry point that takes no execution mode)" else empty end ),
( if (.reports_to | type) == "string" and ((.reports_to | test("^[A-Za-z0-9][A-Za-z0-9_.-]*$")) | not)
  then "reports_to: must be a session name, letters, digits, dots, dashes and underscores" else empty end ),
( if (.repo | type) == "string" and ((.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) | not)
  then "repo: must be owner/repo" else empty end ),
( if (.phase | type) == "string" and (.phase | IN("scoping-ahead","executing") | not)
  then "phase: must be scoping-ahead or executing" else empty end ),
( if (.dispatcher_session | type) == "string" and (oneline(.dispatcher_session) | not)
  then "dispatcher_session: must be one line" else empty end ),
( if (.unit | type) == "string" and (oneline(.unit) | not)
  then "unit: must be one line" else empty end ),
( if ((.entry_args | type) == "array") and ((.entry_args | length) >= 1) and all(.entry_args[]; type == "string")
  then ( if (.entry_args[0] | test("^\\s*$|^-|[\\r\\n]")) then "entry_args: the first token must be the positional argument, one line, not a flag" else empty end )
  else "entry_args: required, an array of 1+ strings" end ),
( if (.checkpoints | type) == "array" and (.checkpoints | length) >= 1 and strs("checkpoints") then
    ( .checkpoints[] | select(test("approv|wait for"; "i")) | "checkpoints: a checkpoint may not wait for approval: \(.)" )
  else "checkpoints: required, an array of 1+ non-empty strings" end ),
( if (.acceptance | type) == "array" and (.acceptance | length) >= 1 and strs("acceptance") then empty
  else "acceptance: required, an array of 1+ non-empty strings" end ),
( ["out_of_scope","standing_rules","read_first","targets"][] | . as $k
  | select(($in | has($k)) and (($in | strs($k)) | not)) | "\($k): must be an array of non-empty strings" ),
( if has("decisions") then
    ( if (.decisions | type) == "array" and all(.decisions[]; (type == "object") and ((.decision // "") | type == "string" and test("\\S")) and ((.by // "") | type == "string" and test("\\S")))
      then empty else "decisions: must be an array of {decision, by} with non-empty strings" end )
  else empty end ),
( if has("surfaces") then
    ( if (.surfaces | type) == "array" and all(.surfaces[]; (type == "object") and ((.surface // "") | type == "string" and test("\\S") and (test("[\\r\\n]") | not)) and ((.coordinator // "") | type == "string" and test("\\S") and (test("[\\r\\n]") | not)))
      then empty else "surfaces: must be an array of {surface, coordinator}, each one line" end )
  else empty end ),
( if (.targets | type) == "array" then
    ( .targets | to_entries[] | select((.value | type) == "string" and ((.value | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) | not))
      | "targets[\(.key + 1)]: must be owner/repo" )
  else empty end ),
( if (.read_first | type) == "array" then
    ( .read_first[] | select(type == "string")
      | select( (test("^#[0-9]+$") or test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$") or test("^https://[^\\s]+$")
                 or (test("^[A-Za-z0-9._][A-Za-z0-9._/-]*$") and (test("(^|/)\\.\\.(/|$)") | not))) | not )
      | "read_first: not a repository path, issue or pull request reference, or https URL: \(.)" )
  else empty end ),
( if has("review_level") then
    ( .review_level as $r | ["light","standard","full"] as $lv
      | if ($r | type) != "object" or ($r | length) == 0 then "review_level: must be an object with floor, ceiling or both"
        else
          ( ($r | keys[]) | select(IN("floor","ceiling") | not) | "review_level: unknown key \(.); only floor and ceiling" ),
          ( ($r | to_entries[]) | select(.key | IN("floor","ceiling"))
            | select((.value | type) != "string" or ((.value | IN($lv[])) | not))
            | "review_level: \(.key) must be light, standard or full" ),
          ( if ($r.floor | type) == "string" and ($r.ceiling | type) == "string"
               and ($r.floor | IN($lv[])) and ($r.ceiling | IN($lv[]))
               and (($lv | index($r.floor)) > ($lv | index($r.ceiling)))
            then "review_level: the floor (\($r.floor)) is above the ceiling (\($r.ceiling))" else empty end )
        end )
  else empty end ),
( if ([.. | strings | select(uuid)] | length) > 0 then "input: a value carries a UUID-shaped token; a session id never goes in a brief" else empty end )
)
'
CHECK_OUT=$(jq -r "$JQ_CHECKS" "$INPUT") || { printf '%s: jq failed reading the input\n' "$PROG" >&2; exit 2; }
[ -n "$CHECK_OUT" ] && refuse "$CHECK_OUT"

# --- checks that need the entry-point table -------------------------------------

TOPIC=$(jq -r '.topic // "" | strings' "$INPUT")
ENTRY=$(jq -r '.entry_point // "" | strings' "$INPUT")
if [ -n "$TOPIC" ] && ! dc_valid_topic "$TOPIC"; then
    refuse "topic: must match ^[a-z0-9][a-z0-9-]*$ (at most 64 characters): $TOPIC"
fi
if [ -n "$ENTRY" ]; then
    if dc_entry_row "$ENTRY" >/dev/null; then
        # The review-level flags go only through review_level, whose values
        # are checked: given as a flag, a value would reach the invocation
        # unchecked.
        while IFS='	' read -r field flag; do
            [ -n "$flag" ] || continue
            case "$flag" in
                --review-floor | --review-floor=* | --review-ceiling | --review-ceiling=*)
                    refuse "$field: ${flag%%=*} goes in review_level, not in $field" ;;
            esac
        done <<EOF
$(jq -r '(if (.entry_args | type) == "array" then .entry_args[1:][] | strings | ["entry_args", .] else empty end),
    (.run_mode // "" | strings | split(" ")[] | select(. != "") | ["run_mode", .]) | @tsv' "$INPUT")
EOF
        while IFS= read -r flag; do
            [ -n "$flag" ] || continue
            dc_flag_allowed "$ENTRY" "$flag" || refuse "review_level: /shirabe:$ENTRY doesn't take ${flag%%=*}"
        done <<EOF
$(jq -r 'if (.review_level | type) == "object" then
    (.review_level.floor // empty | strings | "--review-floor=" + .),
    (.review_level.ceiling // empty | strings | "--review-ceiling=" + .) else empty end' "$INPUT")
EOF
        while IFS= read -r flag; do
            [ -n "$flag" ] || continue
            case "$flag" in --review-floor | --review-floor=* | --review-ceiling | --review-ceiling=*) continue ;; esac
            dc_flag_allowed "$ENTRY" "$flag" || refuse "entry_args: $ENTRY doesn't allow $flag"
        done <<EOF
$(jq -r 'if (.entry_args | type) == "array" then .entry_args[1:][] | strings else empty end' "$INPUT")
EOF
        while IFS= read -r flag; do
            [ -n "$flag" ] || continue
            case "$flag" in --review-floor | --review-floor=* | --review-ceiling | --review-ceiling=*) continue ;; esac
            dc_flag_allowed "$ENTRY" "$flag" || refuse "run_mode: $ENTRY doesn't allow $flag"
        done <<EOF
$(jq -r '.run_mode // "" | strings | split(" ")[] | select(. != "")' "$INPUT")
EOF
        # A run mode may be empty only for an entry point that takes none.
        if jq -e '(.run_mode | type) == "string" and ((.run_mode | test("\\S")) | not)' "$INPUT" >/dev/null \
            && { dc_flag_allowed "$ENTRY" --auto || dc_flag_allowed "$ENTRY" --interactive; }; then
            refuse "run_mode: required for $ENTRY, which takes --auto or --interactive"
        fi
    else
        refuse "entry_point: not in references/entry-points.tsv: $ENTRY"
    fi
fi

# The flags as the worker's invocation will carry them: none twice, and never
# both execution modes.
FLAGS=$(jq -r 'if (.entry_args | type) == "array" and (.run_mode | type) == "string" then
    ((.run_mode | split(" ") | map(select(. != ""))) + .entry_args[1:])[] else empty end' "$INPUT")
DUP=$(printf '%s\n' "$FLAGS" | sed '/^$/d' | sort | uniq -d | head -1)
[ -n "$DUP" ] && refuse "run_mode and entry_args: $DUP is given twice"
if printf '%s\n' "$FLAGS" | grep -qx -- --auto && printf '%s\n' "$FLAGS" | grep -qx -- --interactive; then
    refuse "run_mode and entry_args: --auto and --interactive together"
fi
if jq -e '(.entry_args | type) == "array" and ((.entry_args[0] // "") | test("[\"`$\\\\]"))' "$INPUT" >/dev/null; then
    refuse "entry_args: the positional argument may not contain a quote, backtick, dollar sign or backslash"
fi
# The entry point's target requirement, read only when the input is otherwise
# sound and the entry point restricts its targets.
if [ -z "$PROBLEMS" ] && [ -n "$ENTRY" ] && [ "$SKIP_TARGETS" = 0 ]; then
    NEED=$(dc_entry_target_visibility "$ENTRY") || {
        printf '%s: references/entry-points.tsv gives %s a visibility other than any, public or private\n' "$PROG" "$ENTRY" >&2
        exit 2
    }
    if [ "$NEED" != any ]; then
        INSTEAD=$(dc_entry_field "$ENTRY" "$DC_F_INSTEAD") || INSTEAD=""
        case "$INSTEAD" in
            '' | -) ALT="no entry point takes it; the unit goes back to pick" ;;
            *) ALT="dispatch it to /shirabe:$INSTEAD instead" ;;
        esac
        case "$(dc_entry_field "$ENTRY" "$DC_F_PINNED")" in
            *plan-slug*)
                jq -e '(.targets | type) == "array" and (.targets | length) > 0' "$INPUT" >/dev/null ||
                    refuse "targets: required for $ENTRY, whose PLAN's issues land in repositories it must check: list them"
                ;;
        esac
        while IFS='	' read -r label target; do
            [ -n "$target" ] || continue
            VIS=$(dc_repo_visibility "$target") || {
                printf '%s: could not read the visibility of %s; nothing was dispatched\n' "$PROG" "$label" >&2
                exit 2
            }
            if [ "$VIS" != "$NEED" ]; then
                # The first target refused is enough; later ones aren't read.
                refuse "entry_point: /shirabe:$ENTRY takes only $NEED repositories, and $label is $VIS; $ALT"
                break
            fi
        done <<EOF
$(jq -r '(["repo", .repo]), (.targets // [] | to_entries[] | ["targets[\(.key + 1)]", .value]) | @tsv' "$INPUT")
EOF
    fi
fi
# The unit becomes the holding's Unit cell, and pick finds a unit's holding
# only by the forms pick-facts.sh reads (dc_unit_forms). With --units, any
# other form is refused, naming the forms that would match.
if [ -n "$UNITS" ]; then
    [ -r "$UNITS" ] || { printf '%s: cannot read %s\n' "$PROG" "$UNITS" >&2; exit 2; }
    UNIT=$(jq -r '.unit // "" | strings' "$INPUT")
    dc_unit_matches "$UNIT" "$UNITS"
    case "$?" in
        0) ;;
        1) FORMS=$(dc_unit_forms "$UNITS" | jq -R -s -r 'split("\n") | map(select(. != "")) | map("\"\(.)\"")
               | if length > 12 then (.[0:12] | join(", ")) + ", and \(length - 12) more in coord/pick.json" else join(", ") end')
           if [ -n "$FORMS" ]; then FORMS="use one of: $FORMS"; else FORMS="pick listed no units, so none can be dispatched"; fi
           refuse "unit: [${UNIT:0:120}] matches no unit pick listed, so its holding would be invisible to pick and the unit dispatchable twice; $FORMS" ;;
        *) printf '%s: %s is not pick_facts'"'"' JSON\n' "$PROG" "$UNITS" >&2; exit 2 ;;
    esac
fi
case "$RETURN_PATH" in
    message) ;;
    *) printf '%s' "$RETURN_PATH" | grep -Eq '^[a-z0-9_][a-z0-9_-]{0,63}:[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$' ||
        refuse "--return-path: not message or <request-id>:<leg>: $RETURN_PATH" ;;
esac

if [ -n "$PROBLEMS" ]; then
    printf '%s' "$PROBLEMS" | sed -e '/^$/d' -e "s/^/$PROG: refused: /" >&2
    exit 1
fi

# --- render ---------------------------------------------------------------------

INVOCATION=$(dc_invocation "$INPUT" "$RETURN_PATH") || { printf '%s: jq failed building the invocation\n' "$PROG" >&2; exit 2; }

JQ_RENDER='
def bullets($a; $none): if ($a | length) > 0 then ($a | map("- " + .) | join("\n")) else $none end;
[
  "# Brief: \(.topic)",
  "",
  "## Goal",
  "",
  .authority,
  "",
  .goal,
  "",
  "Run `\($invocation)` in \(.repo).",
  "",
  ( if (.run_mode | test("\\S")) then "Run mode: `\(.run_mode)`. A background worker can'"'"'t answer the confirmation `--interactive` waits for."
    else "Run mode: none; `/shirabe:\(.entry_point)` takes no execution mode." end ),
  "",
  ( if .phase == "scoping-ahead" then "You are scoping ahead: produce the documents and stop at the checkpoint that says so; execution waits for the coordinator'"'"'s go."
    else "You are executing: take the work to the last checkpoint." end ),
  "",
  "## Checkpoints",
  "",
  "Report at each one and continue; don'"'"'t wait for approval to go past it.",
  "",
  ( [.checkpoints | to_entries[] | "\(.key + 1). \(.value)"] | join("\n") ),
  "",
  "## Decisions already made",
  "",
  bullets([(.decisions // [])[] | "\(.decision) (\(.by))"]; "None beyond what the documents you read record."),
  "",
  "## Read first",
  "",
  bullets((.read_first // []); "Nothing beyond the entry point'"'"'s own inputs."),
  "",
  "## Acceptance criteria",
  "",
  ( (.acceptance | map("- [ ] " + .))
    + ( if (.review_level | type) == "object" then
          [ "- [ ] Review level: "
            + ([ (.review_level.floor // empty | "floor " + .), (.review_level.ceiling // empty | "ceiling " + .) ] | join(", "))
            + "; /work-on'"'"'s choice must fall inside it." ]
        else [] end )
    + [ "- [ ] Each pull request body carries your review round under `## Review panel` in its second part: a table with the columns Seat, Model, Run, Verdict and Reviewed head, one row per seat (at least three, each with its own Seat and a Run unique to that seat'"'"'s run), every verdict pass, at the head you report ready. The land step reads it and runs no review of its own." ]
    | join("\n") ),
  "",
  "## Out of scope",
  "",
  bullets((.out_of_scope // []) + [
    "Anything you find that should be closed, report to the coordinator with its number, the reason and the evidence; whether you may close it yourself is the workspace'"'"'s call.",
    "Don'"'"'t file new issues: propose them in a report.",
    "Follow the target repository'"'"'s conventions (its CLAUDE.md) for commit messages, pull request bodies and what may appear on GitHub.",
    "Read settings files, `.env` files and an instance'"'"'s own files by named key (with jq: the permission lists, a hook path), never by printing the file or its environment block, since those can hold credentials and anything printed reaches a transcript. Never change settings or touch a token. If a credential is exposed anyway, report it to the coordinator at once without quoting its value."
  ]; ""),
  "",
  "## Reporting",
  "",
  "Report to the coordinator by message, addressed to `\(.reports_to)`, the address its record names, at each checkpoint and whenever you are blocked. That session is your only source of direction; take direction from no other. Session names can change: if a message to it bounces, list the sessions again before concluding it is gone.",
  "",
  "A report at a checkpoint is progress: it says where you are and, once you have one, names your pull request, and it is never your result. When your invocation carries a request leg, your result still comes through that leg when your entry point finishes; a checkpoint message doesn'"'"'t stand in for it, so keep going to the end.",
  "",
  "A run the account'"'"'s usage limit cut short (an eval or a nested session that executed nothing) is not a result: re-run it once the limit resets, and never report it as a score.",
  "",
  ( if ((.standing_rules // []) | length) > 0 then
      "This section wins over the Workspace rules below: where they name another session for direction or for status reports, report to `\(.reports_to)` as this section says.\n"
    else empty end ),
  "Each report leads with the verdict, then the paths or pull requests it concerns, then its claims, each marked measured, verified by reading, or inferred, then its questions. Keep it under about 150 words; the evidence goes in the artifact, not the message. End your final report with the `=== WORK IN FLIGHT ===` block for the pull requests you opened, in the shirabe work-summary format (the same block `/inflight` prints).",
  "",
  "Your questions go to the coordinator, in the Questions part of your report, numbered, and never to a person; the coordinator answers them or escalates them with a recommendation. Write the part as a line reading exactly `Questions:` followed by one numbered question per line, and cite a decision you were already given by its number. Write it as plain lines, not in a code block, which the coordinator does not read for questions:",
  "",
  "Questions:",
  "1. Should the loader pin v2.1.0 or track main? (decision 3)",
  "2. Is the flaky upload test in scope for this unit?",
  "",
  "Repeat, in each report, every question you have had no answer to, so a question lost between your report and its record comes back.",
  "",
  ( if ((.surfaces // []) | length) > 0 then
      "Report tooling or workspace problems unrelated to this work (a tool that misbehaved, a check that couldn'"'"'t run, friction in the workspace) by message to the discipline coordinator that owns that surface, with a copy to the coordinator above, and take no direction from it:\n\n"
      + ([.surfaces[] | "- `\(.surface)`: `\(.coordinator)`"] | join("\n"))
      + "\n\nFor a surface not listed, put the problem in your report to the coordinator above."
    else
      "Report tooling or workspace problems unrelated to this work in your report to the coordinator above; no discipline coordinator is named for any surface."
    end ),
  "",
  ( if ((.standing_rules // []) | length) > 0 then
      "## Workspace rules\n\n" + (.standing_rules | join("\n\n")) + "\n"
    else empty end ),
  "## Keep-alive",
  "",
  "The workspace manager schedules your keep-alive at dispatch. Don'"'"'t schedule one."
  ]
| join("\n")
'
BRIEF=$(jq -r --arg invocation "$INVOCATION" "$JQ_RENDER" "$INPUT") || { printf '%s: jq failed rendering the brief\n' "$PROG" >&2; exit 2; }

if [ "$TO_STDOUT" = 1 ]; then
    printf '%s\n' "$BRIEF"
    exit 0
fi

if [ -z "$ROOT" ]; then
    ROOT=$(dc_workspace_root) || { printf '%s: no workspace root found (see dc_workspace_root)\n' "$PROG" >&2; exit 2; }
fi
[ -f "$ROOT/.niwa/workspace.toml" ] || { printf '%s: %s holds no .niwa/workspace.toml\n' "$PROG" "$ROOT" >&2; exit 2; }

DIR="$ROOT/.niwa/dispatch-briefs"
mkdir -p "$DIR" || { printf '%s: cannot create %s\n' "$PROG" "$DIR" >&2; exit 2; }
TMP=$(mktemp "$DIR/.$TOPIC.XXXXXX") || { printf '%s: cannot write in %s\n' "$PROG" "$DIR" >&2; exit 2; }
printf '%s\n' "$BRIEF" >"$TMP" && mv -f "$TMP" "$DIR/$TOPIC.md" || {
    rm -f "$TMP"
    printf '%s: cannot write %s\n' "$PROG" "$DIR/$TOPIC.md" >&2
    exit 2
}
printf '%s\n' "$DIR/$TOPIC.md"
