#!/usr/bin/env bash
# panel-scope.sh -- for /work-on: which review seats a panel round actually
# needs, decided from git rather than from the agent's judgment.
#
# Without it, a blocking finding from any of the three panels would clear all
# three verdicts and send the run back through all seven seats: three
# scrutiny, three review, one QA. Two retries could spawn 21 reviewers for one
# issue, and a QA finding about one test would re-run reviewers on code they
# had already passed.
#
# Each seat's verdict is kept in a ledger, and on every panel entry this
# script decides, per seat, what the round does:
#
#   full     no verdict on record yet (the first round): a fresh full review
#   recheck  the seat raised a blocking finding last time: it checks only
#            whether that finding is fixed, given the finding and the fix diff.
#            A blocking seat goes through checks 0-3 below first, and is rerun
#            if any holds, or if it recorded no findings
#   rerun    the seat passed, but the fix touched what it judged: a fresh review
#   keep     the seat passed and the fix touched nothing it judged: its verdict
#            carries and the seat is not spawned
#
# "Touched" is objective. The fix diff is `git diff <judged_at> HEAD`, where
# judged_at is the commit the seat's verdict was given at. A passed seat is
# rerun when any of these holds, checked in this order:
#
#   0. the working tree has uncommitted changes, untracked files included
#      (the fix may not be committed, and the diff below would miss it), or
#      there are no commits since impl_base or no impl_base recorded (nothing
#      for a pass to rest on; scrutiny's has_commits gate must not be slipped
#      past by a carried verdict)
#   1. the acceptance criteria or the plan changed since it judged (the git
#      hash of the `context.md` and `plan.md` context keys differs). context.md
#      is written at setup and plan.md at analysis, so in practice this fires
#      when a scope_expanded_retry or scope_changed_retry rewrote the plan
#   2. judged_at is no longer a commit, or no longer an ancestor of HEAD
#      (a rebase or reset rewrote what it judged)
#   3. the fix diff changes more than THRESHOLD_LINES lines in total -- a fix
#      that large is new work, not a fix. It is also the only check that sees
#      files a fix adds, since a new file was never cited. 200 is a judgment,
#      not a measurement: about one screenful of diff per seat to re-read
#   4. the fix diff overlaps what it cited: a cited path with a line range is
#      touched when a fix hunk's old-side range overlaps it; a cited path with
#      no range is touched when the fix changes the file at all; a seat that
#      cited nothing is taken to have cited every path in the diff it reviewed
#      (impl_base..judged_at), and is rerun if that diff is empty. The
#      locations of findings the seat raised are checked too, on top of
#      either.
#
# Renames are off (`--no-renames`), so moving a cited file counts as touching
# it. A pure insertion (`@@ -a,0 ...`) sits between lines a and a+1 and touches
# a range containing either.
#
# The template runs --plan on each entry to a panel state, and --carried,
# --recorded and --verdict as that state's gates (evaluated on every tick
# there); the agent runs --record once per round:
#
#   --plan <panel> <session>     default_action on `scrutiny`, `review`,
#                                `qa_validation` and `light_review`. Writes
#                                `<panel>_scope.json`
#                                and appends the round's decisions, with their
#                                reasons, to the ledger's history. When every
#                                seat is `keep` it also writes
#                                `<panel>_results.json`, marked carried.
#   --carried <panel> <session>  the `<panel>_carried` gate. Exit 0 when the
#                                tree is clean, the scope written for this
#                                HEAD keeps every seat, and the carried results
#                                are in place, so koto advances the panel with
#                                no spawn.
#   --recorded <panel> <session> the `<panel>_recorded` gate on the passed and
#                                blocking_retry edges. Exit 1 while a seat the
#                                scope spawned holds a verdict recorded before
#                                the scope was planned: this round was not
#                                recorded.
#   --verdict <panel> <session>  the `<panel>_verdict` gate: the panel's pass,
#                                computed from the ledger rather than reported
#                                by the agent (DESIGN-output-gates Decision 4).
#                                Exit 0 when every seat of the panel has a
#                                recorded verdict and none is blocking, 1 when
#                                a seat is blocking (one finding per blocking
#                                finding), 2 when the round is not fully
#                                recorded or the keys can't be read.
#   --record <panel> <session> <round-file>
#                                the agent, at aggregation, for every run it
#                                spawned this round, passed or blocking. Records
#                                each finding raised and each answer given, by
#                                finding id, stamps judged_at=HEAD and the
#                                criteria hash on the seats that ran, and
#                                recomputes every seat entry from the findings.
#   --mark-fixed <panel> <session> <id>...
#                                the agent, after committing a fix: a `fixed`
#                                record per finding, asking for its
#                                re-verification. It never closes anything.
#
# Usage: panel-scope.sh --plan    <panel> <koto-session-name>
#        panel-scope.sh --carried <panel> <koto-session-name>
#        panel-scope.sh --recorded <panel> <koto-session-name>
#        panel-scope.sh --verdict <panel> <koto-session-name>
#        panel-scope.sh --record  <panel> <koto-session-name> <round-file>
#        panel-scope.sh --mark-fixed <panel> <koto-session-name> <id>...
#
# <panel> is scrutiny, review, qa (the qa_validation state) or light (the
# light_review state, the `light` review level's one seat).
#
# ## The round file
#
# A JSON array, one object per spawned run:
#
#   [{"seat": "completeness", "run": "<the run id its decision names>",
#     "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
#     "findings": [{"severity": "blocking", "summary": "...",
#                   "path": "src/a.sh", "lines": "12-12", "rule_id": "<optional>"}],
#     "answers": [{"id": "<finding id>", "record": "holds|reverified|dismissed",
#                  "reason": "...", "path": "<optional new location>"}]}]
#
# `run` is required: when the scope's decision for the seat names a run, the
# entry must name the same one, and no run is recorded twice. `answers` may
# name only the ids the seat's decision planned for it; a dismissal needs a
# reason and the seat that raised the finding, and the re-verifier (seat
# `reverifier`) may answer only holds or reverified, with a reason on each
# reverified. A decider's verdict is an entry of its own,
# {"decider": {"state", "visit_seq", "gate", "rule_id", "declaration_hash",
# "input_sha256", "outcome"}}, accepted only when koto's session log holds a
# decider_checked event with those fields that no earlier entry used.
#
# Each finding's id is the first 16 hex characters of `git hash-object` over
# its panel, raiser kind and name, path and whitespace-collapsed summary, so a
# finding raised again keeps its id; two findings of one run with one id are
# refused. Its location is `lines` (path and range), `file` (path) or `none`,
# recorded at the commit it was judged at. Its status is its latest record's:
# raised and holds are open, reverified and dismissed are closed when their
# writer was allowed to write them (a reviewer; a check on a check's finding; a
# decider on its own finding; a dismissal only by the raising seat), fixed (the
# agent's) and unverified (a decider's no-verdict) are open.
#
# `cited` is what the seat judged: the paths and, where it can say, the line
# ranges ("N" or "N-M", in HEAD's numbering) its verdict rests on. Findings'
# locations are kept beside it, as `finding_locations`, so a seat that cited
# nothing still falls back to the whole diff it judged. Both carry forward from
# earlier rounds, so a seat's judged scope only grows; an earlier line range in
# a file that has changed since is carried as the bare path, because its
# numbers no longer name the same code.
#
# Every finding carries a `severity`, `blocking` or `advisory`, and a seat is
# recorded as blocking exactly while it raised an unclosed blocking finding. A finding
# with no severity, or any other value, makes --record refuse the whole round
# (65), so a seat can't be recorded as passing by leaving the field out.
# `blocking_count`, `passed` and any other summary field are ignored: the
# verdict is the findings', not the agent's count of them.
#
# ## Context keys
#
#   verdict_ledger.json   {"rev": N, "seats": {"<panel>/<seat>": {...}},
#                          "findings": {"<id>": {id, panel, severity, round,
#                          raiser, run, location, summary, rule_id?, records}},
#                          "runs": {"<run>": {panel, rev, recorded}},
#                          "reverified": {"<panel>": {rev, run, head}},
#                          "decider_events": [...],
#                          "history": [{"panel", "round", "head", "rev",
#                          "spawned", "decisions": [{seat, decision, reason}]}]}
#                         Never cleared by a retry: it is what survives one.
#                         The seat entries are summaries of the findings, kept
#                         in the shape review-shadow.py and review-packet.sh
#                         read.
#   <panel>_scope.json    this entry's decisions, for the agent to act on
#   <panel>_results.json  only when every seat is kept, read by --carried;
#                         otherwise the agent may write it at aggregation as
#                         the round's summary. No gate reads it for the pass:
#                         --verdict reads the ledger
#
# A `--plan` re-run at the same HEAD with no `--record` in between (a tick
# without evidence, say) replaces its own history entry instead of adding one,
# so the history counts rounds, not ticks. A --plan re-run at the same HEAD,
# on a clean tree and unchanged criteria, after every seat the round spawned
# was recorded and one of them blocked, leaves the scope as it is: that round
# is complete, and the <panel>_verdict gate reports its block.
#
# Diagnostics go to stderr. --plan prints the scope it wrote on stdout, for a
# human running it by hand; --verdict prints its findings on stdout; the other
# modes print nothing.
#
# --verdict prints one koto finding per blocking finding:
#   ::koto-finding::{"rule_id":"panel/blocking-finding","level":"error",
#                    "message":"<rule summary>: <panel>/<seat>: <summary>","path":"src/a.sh",
#                    "line":12,"rule_ref":"<path>#L<a>-L<b>@<revision>"}
# with the rule resolved through scripts/lib/rule-findings.sh, which exits 2 when
# it can't be; `path` and `line` only when the finding names them.
#
# Exit codes:
#   0   -- --plan/--record: written. --carried: every seat is kept.
#          --recorded: every spawned seat was recorded this round, or there is no
#          scope or ledger to check. --verdict: every seat of the panel has a
#          recorded verdict and none is blocking.
#   1   -- --carried: something has to run, the working tree is dirty, or
#          the scope is missing, stale, unreadable or has no carried results
#          beside it. --recorded: a spawned seat wasn't recorded this round,
#          or the keys can't be read. --verdict: a seat is blocking. --carried
#          and --recorded exit nothing else: a gate exit the template does not
#          route would hold the state, and the safe answer to every doubt is
#          "run the panel" or "record the round".
#   2   -- --verdict only, for every doubt it has: a seat the round's scope
#          spawned has no verdict recorded since the scope was planned, a seat
#          of the panel has no verdict at all, the ledger or the scope can't be
#          read, or a usage error. It is the first mode to use 2: a verdict it
#          can't compute holds the panel state, where a 1 would send the agent
#          to a retry or an escalation on a guess.
#   64  -- not a git repository, HEAD names no commit, or mktemp failed
#   65  -- a JSON step failed or a write was refused: --record's round file
#          is missing, is not a JSON array of runs, names a seat outside the
#          panel, breaks a rule above (a run, an answer, a finding's shape or
#          severity, a rule id that isn't active, a decider event koto's log
#          doesn't hold), or --mark-fixed names an id that is unknown, advisory
#          or closed; or (--plan or --record) jq could not merge the result
#          into the ledger. A refused write leaves the ledger byte-identical
#   66  -- a `koto context add` failed; koto's own stderr says why
#   67  -- a mode, panel or argument is missing or unrecognised
#   68  -- --record only: HEAD moved since the panel's scope was planned, so
#          the round's verdicts are about a commit that is no longer HEAD
#   69  -- --record or --mark-fixed: the ledger changed while the write was
#          being built; nothing was stored
#   127 -- jq is not on PATH
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

THRESHOLD_LINES=200
LEDGER=verdict_ledger.json
# The one registry rule --verdict reports (references/rule-registry.json).
RULE_IDS="panel/blocking-finding"
# A ledger entry's blocking findings, as a jq expression over the entry. A
# finding with no severity counts: it comes from a ledger written before
# severity existed, when the agent listed only blocking findings. --record
# admits no such finding now.
BLOCKING_FINDINGS='(.findings // [])[] | select(type == "object" and ((.severity // "blocking") == "blocking"))'

die() {
    # $1 exit code, $2 message
    echo "panel-scope: $2" >&2
    exit "$1"
}

MODE="${1:-}"
PANEL="${2:-}"
SESSION="${3:-}"

# The gate modes answer every doubt, usage errors included, with one exit: 1
# for --carried and --recorded, 2 for --verdict. See Exit codes.
refuse() {
    # $1 exit code for the other modes, $2 message
    case "$MODE" in
        --carried|--recorded) echo "panel-scope: $2" >&2; exit 1 ;;
        --verdict) echo "panel-scope: $2" >&2; exit 2 ;;
    esac
    die "$1" "$2"
}

case "$MODE" in
    --plan|--carried|--recorded|--verdict|--record|--mark-fixed) ;;
    "") die 67 "missing mode: expected --plan, --carried, --recorded, --verdict, --record or --mark-fixed" ;;
    *)  die 67 "unrecognised mode [$MODE]: expected --plan, --carried, --recorded, --verdict, --record or --mark-fixed" ;;
esac

case "$PANEL" in
    scrutiny) SEATS="completeness justification intent" ;;
    review)   SEATS="pragmatic architect maintainer" ;;
    qa)       SEATS="tester" ;;
    light)    SEATS="reviewer" ;;
    "") refuse 67 "missing panel" ;;
    *)  refuse 67 "unrecognised panel [$PANEL]: expected scrutiny, review, qa or light" ;;
esac
[ -n "$SESSION" ] || refuse 67 "missing session argument for $MODE"
command -v jq >/dev/null || refuse 127 "jq not on PATH"

HEAD=$(git rev-parse --verify -q "HEAD^{commit}") \
    || refuse 64 "not a git repository, or HEAD names no commit"

# A missing key reads as empty. `koto context exists` exits 1, silently, for an
# absent key.
ctx_get() {
    if koto context exists "$SESSION" "$1"; then
        koto context get "$SESSION" "$1"
    fi
}

# ---------------------------------------------------------------- --carried ---

if [ "$MODE" = "--carried" ]; then
    [ -z "$(git status --porcelain | head -1)" ] \
        || refuse 1 "the working tree has uncommitted changes"
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || refuse 1 "no ${PANEL}_scope.json for this round"
    printf '%s' "$scope" | jq -e --arg head "$HEAD" '
        .head == $head and (.decisions | length > 0)
        and all(.decisions[]; .decision == "keep")' >/dev/null \
        || refuse 1 "${PANEL}_scope.json does not keep every seat at HEAD"
    koto context exists "$SESSION" "${PANEL}_results.json" \
        || refuse 1 "every seat is kept but ${PANEL}_results.json is absent"
    exit 0
fi

# ---------------------------------------------------------------- --recorded --

# Refuses while a seat this round spawned still holds a verdict recorded
# before the scope was planned: that is a round whose --record was skipped,
# and the seat's old verdict -- a pass, possibly, for a seat that has just
# blocked -- would be read as current next round. A spawned seat with no entry
# at all passes: skipping its record costs a full review next round, never a
# wrong carry. No scope passes too, with nothing to compare.
#
# HEAD moving while the panel is open is --record's concern, not this gate's:
# --record refuses to stamp a round across a moved HEAD (68), and a round
# recorded before the move keeps its own judged_at, so the next round's fix
# diff includes the commit no seat saw.
if [ "$MODE" = "--recorded" ]; then
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || exit 0
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || exit 0
    # Compared by ledger revision, not by commit: a panel re-entered at an
    # unchanged HEAD (a fix left uncommitted, say) would otherwise find the
    # seat's previous verdict already "at HEAD" and let a skipped record by.
    stale=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" '
        [$s.decisions[] | select(.decision != "keep") | .seat
         | select(($l.seats[$panel + "/" + .] // null) as $e
                  | $e != null and (($e.rev // -1) <= ($s.rev // -1)))] | join(" ")') \
        || refuse 1 "could not read ${PANEL}_scope.json or $LEDGER"
    [ -z "$stale" ] || refuse 1 "no verdict recorded this round for: $stale (run panel-scope.sh --record $PANEL)"
    exit 0
fi

# ---------------------------------------------------------------- --verdict ---

# The panel's pass, from the ledger. Unlike --recorded, a spawned seat with no
# entry at all holds here: --recorded only stops a stale verdict from being
# read as this round's, while this gate has to have a verdict for every seat
# before it can say the panel passed. With no scope (the --plan fallback path)
# there is nothing to date the verdicts against, so only their presence is
# checked.
if [ "$MODE" = "--verdict" ]; then
    # The rule resolves before the ledger is read, so a registry problem holds
    # the gate whether or not a seat is blocking.
    undecided() { refuse 2 "$*"; }
    # shellcheck source=../../../scripts/lib/rule-findings.sh
    . "$(cd "$(dirname "$0")" && pwd)/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
    rf_require panel/blocking-finding
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || refuse 2 "no $LEDGER: no $PANEL seat has a recorded verdict (run panel-scope.sh --record $PANEL)"
    printf '%s' "$ledger" | jq -e 'type == "object"' >/dev/null \
        || refuse 2 "$LEDGER is unreadable"
    scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$scope" ]; then
        unrecorded=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" '
            [$s.decisions[] | select(.decision != "keep") | .seat
             | select(($l.seats[$panel + "/" + .] // null) as $e
                      | $e == null or (($e.rev // -1) <= ($s.rev // -1)))] | join(" ")') \
            || refuse 2 "could not read ${PANEL}_scope.json against $LEDGER"
        [ -z "$unrecorded" ] \
            || refuse 2 "no verdict recorded since ${PANEL}_scope.json was planned for: $unrecorded (run panel-scope.sh --record $PANEL)"
    fi
    missing=""
    for seat in $SEATS; do
        v=$(printf '%s' "$ledger" | jq -r --arg k "$PANEL/$seat" '.seats[$k].verdict // empty') \
            || refuse 2 "$LEDGER is unreadable"
        case "$v" in passed|blocking) ;; *) missing="$missing $seat" ;; esac
    done
    [ -z "$missing" ] || refuse 2 "no verdict on record for$missing (run panel-scope.sh --record $PANEL)"

    # rf_ref and rf_summary refuse inside the command substitution, which can't
    # end this shell; `|| exit 2` carries their could-not-decide out.
    ref=$(rf_ref panel/blocking-finding) || exit 2
    summary=$(rf_summary panel/blocking-finding) || exit 2
    # One finding per blocking finding. A seat recorded as blocking with no
    # finding marked blocking (a ledger from before severity) still blocks, and
    # gets one finding naming the seat. The message is the rule's summary, then
    # the panel, seat and the seat's own summary, control characters replaced:
    # the same shape rf_finding in scripts/lib/rule-findings.sh builds, built
    # here because one ledger read yields every finding. rf_emit refuses a line
    # whose rule_id, rule_ref or summary prefix strays from it; replacing the
    # control characters is this jq's job, not rf_emit's.
    findings=$(printf '%s' "$ledger" | jq -c --arg panel "$PANEL" --arg seats "$SEATS" --arg ref "$ref" \
        --arg rule_summary "$summary" \
        "def blocking_findings: [$BLOCKING_FINDINGS];"'
        [($seats | split(" "))[] as $seat
         | (.seats[$panel + "/" + $seat]) as $e
         | select($e.verdict == "blocking")
         | ($e | blocking_findings) as $bf
         | if ($bf | length) > 0 then ($bf[] | {seat: $seat, f: .})
           else {seat: $seat, f: {summary: "recorded as blocking, with no finding marked blocking"}} end]
        | .[]
        | ((.f.lines // "") | tostring | (capture("^(?<n>[1-9][0-9]*)") // null)) as $line
        | {rule_id: "panel/blocking-finding", level: "error",
           message: ($rule_summary + ": "
                     + (($panel + "/" + .seat + ": " + ((.f.summary // "a blocking finding") | tostring))
                        | gsub("[\u0000-\u001f\u007f]"; " ")))}
          + (if (.f.path | type) == "string" and .f.path != "" then {path: .f.path}
               + (if $line != null then {line: ($line.n | tonumber)} else {} end)
             else {} end)
          + {rule_ref: $ref}') \
        || refuse 2 "could not read the blocking findings in $LEDGER"
    [ -n "$findings" ] || exit 0
    while IFS= read -r f; do
        rf_emit "$f"
    done <<EOF
$findings
EOF
    exit 1
fi

WORK=$(mktemp -d) || die 64 "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

AC_SHA=$( { ctx_get context.md; printf '\n--- plan ---\n'; ctx_get plan.md; } | git hash-object --stdin)

LEDGER_JSON=$(ctx_get "$LEDGER")
if [ -z "$LEDGER_JSON" ] || ! printf '%s' "$LEDGER_JSON" | jq -e 'type == "object"' >/dev/null; then
    [ -n "$LEDGER_JSON" ] && echo "panel-scope: $LEDGER is unreadable; starting a new ledger" >&2
    LEDGER_JSON='{"rev": 0, "seats": {}, "findings": {}, "history": []}'
fi

put() {
    # $1 key, $2 file
    koto context add "$SESSION" "$1" < "$2" >/dev/null \
        || die 66 "koto context add failed for $1 on session [$SESSION]"
}

# The jq every mode that reads or writes findings shares: the shapes --record
# accepts, a finding's id string, its status, and whether it is closed.
# Prepended to each program that needs it.
JQ_DEFS='
def run_re: "^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$";
def name_re: "^[a-z][a-z0-9_-]*$";
def rule_re: "^[a-z0-9][a-z0-9/_-]*$";
def path_re: "^[A-Za-z0-9._][A-Za-z0-9._/@+-]*$";
def lines_re: "^[1-9][0-9]*(-[1-9][0-9]*)?$";
# The string a finding id hashes: panel, raiser kind and name, path, and the
# summary with runs of whitespace collapsed. Line ranges stay out, so a finding
# whose lines shift keeps its id.
def canon($panel; $kind; $name; $path; $summary):
    [$panel, $kind, $name, $path,
     ($summary | tostring | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" "))] | join("\n");
def status:
    ({raised: "open", holds: "open", reverified: "reverified", dismissed: "dismissed",
      fixed: "fixed", unverified: "unverified"})[(.records[-1].kind // "raised")] // "open";
# Closed: the latest record is a reverified or dismissed one that its writer
# was allowed to write, naming a run the ledger holds as recorded. Checked when
# read as well as when written, so a ledger edited by hand can not close a
# finding with a record --record would have refused.
def closed($runs):
    (.records[-1] // {}) as $r
    | (($runs[$r.writer.run // ""].recorded // false) == true)
      and (($r.kind == "reverified"
            and ($r.writer.kind == "reviewer"
                 or ($r.writer.kind == "check" and .raiser.kind == "check")
                 or ($r.writer.kind == "decider" and .raiser.kind == "decider" and $r.writer.name == .raiser.name)))
           or ($r.kind == "dismissed" and $r.writer.kind == "reviewer" and .raiser.kind == "reviewer"
               and $r.writer.name == .raiser.name and (($r.reason // "") != "")));
def bad_path:
    (type != "string") or (test(path_re) | not) or test("(^|/)[.][.](/|$)");
def finding_problem($seat):
    if type != "object" then "seat [\($seat)]: a finding is not an object"
    elif (.severity != "blocking" and .severity != "advisory") then
        "seat [\($seat)]: a finding has no severity, or one that is not blocking or advisory"
    elif (.summary | type) != "string" or (.summary | length) == 0 then "seat [\($seat)]: a finding has no summary"
    elif (.summary | utf8bytelength) > 1000 then "seat [\($seat)]: a finding summary is over 1000 bytes"
    elif (.path // null) != null and (.path | bad_path) then "seat [\($seat)]: a finding has an unsafe path"
    elif (.lines // null) != null and (((.path // "") == "") or ((.lines | tostring) | test(lines_re) | not)) then
        "seat [\($seat)]: a finding has lines without a path, or malformed lines"
    elif (.rule_id // null) != null and ((.rule_id | type) != "string" or (.rule_id | test(rule_re) | not)) then
        "seat [\($seat)]: a finding has a malformed rule_id"
    else empty end;
def answer_problem($seat; $d; $l; $panel):
    . as $a
    | if type != "object" then "seat [\($seat)]: an answer is not an object"
      elif (.id | type) != "string" or (.id | test("^[0-9a-f]{16}$") | not) then "seat [\($seat)]: an answer has a malformed id"
      elif ((($l.findings // {})[.id] // null) == null) or ($l.findings[.id].panel != $panel) then
          "seat [\($seat)] answers id [\(.id)], which the \($panel) ledger does not hold"
      elif $d == null or ([($d.findings // [])[] | .id] | index($a.id)) == null then
          "seat [\($seat)] answers id [\(.id)], which its decision did not plan for it"
      elif (.record != "holds" and .record != "reverified" and .record != "dismissed") then
          "seat [\($seat)]: an answer record is not holds, reverified or dismissed"
      elif (.reason // "") != "" and ((.reason | type) != "string" or (.reason | utf8bytelength) > 1000) then
          "seat [\($seat)]: an answer reason is not a string of at most 1000 bytes"
      elif .record == "dismissed" and $seat == "reverifier" then "the reverifier may answer only holds or reverified"
      elif .record == "dismissed" and (.reason // "") == "" then "seat [\($seat)]: a dismissed answer needs a reason"
      elif .record == "dismissed" and ($l.findings[.id].raiser.name != $seat) then
          "seat [\($seat)] dismissed id [\(.id)], which another raiser raised"
      elif .record == "reverified" and $seat == "reverifier" and (.reason // "") == "" then
          "the reverifier answered reverified for id [\(.id)] without a reason"
      elif (.path // null) != null and (.path | bad_path) then "seat [\($seat)]: an answer has an unsafe path"
      elif (.lines // null) != null and (((.path // "") == "") or ((.lines | tostring) | test(lines_re) | not)) then
          "seat [\($seat)]: an answer has lines without a path, or malformed lines"
      else empty end;
'

# store_ledger <file>: store a new ledger, unless another write landed since
# this run read it (69): the compare is of revisions, which every write bumps.
# It catches overlapping honest writes; it is not a lock.
store_ledger() {
    local now
    now=$(ctx_get "$LEDGER" | jq -r 'if type == "object" then (.rev // 0) else 0 end' 2>/dev/null)
    [ "${now:-0}" = "$(printf '%s' "$LEDGER_JSON" | jq -r '.rev // 0')" ] \
        || die 69 "$LEDGER changed while this write was being built (rev ${now:-?}); run it again"
    put "$LEDGER" "$1"
}

REGISTRY="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/rule-registry.sh"

# The decider shadow for the round just recorded: review-shadow.py's site
# command reads these verdicts from the ledger and records the decider's beside
# them (docs/designs/DESIGN-jev-closed-criteria.md). It runs in the background
# with its output discarded, so --record's status, ledger and timing are what
# they would be without it; it runs whether or not REVIEW_SHADOW_SITES opts in,
# because the site command records an unset opt-in rather than staying silent.
# REVIEW_SHADOW_SITE_CMD replaces the command, for tests.
shadow_site() {
    local cmd root
    case "$PANEL" in scrutiny|review|light) ;; *) return 0 ;; esac
    # This script lives at skills/work-on/scripts/ under the plugin root.
    cmd="${REVIEW_SHADOW_SITE_CMD:-$(cd "$(dirname "$0")/../../.." && pwd)/scripts/review-shadow/review-shadow.py}"
    [ -x "$cmd" ] || return 0
    # A stand-in command needs no python3; the real script does.
    [ -n "${REVIEW_SHADOW_SITE_CMD:-}" ] || command -v python3 >/dev/null 2>&1 || return 0
    # HEAD resolved above, so this is a work tree and the call can't fail here.
    root=$(git rev-parse --show-toplevel) || return 0
    # The shadow's own output is discarded on purpose: nothing reads it, and its
    # result is the record it writes.
    ( "$cmd" site work-on --session "$SESSION" --panel "$PANEL" --head "$HEAD" --repo-path "$root" \
        </dev/null >/dev/null 2>&1 & )
    return 0
}

# ---------------------------------------------------------------- --mark-fixed

# The agent's claim that it fixed findings, by id: one `fixed` record each,
# written by writer `agent`. It asks for re-verification and never closes
# anything; --verdict counts a fixed finding as open. Refuses (65) an id the
# panel doesn't hold, an advisory finding (never re-verified), and one that is
# already closed, all before anything is written.
if [ "$MODE" = "--mark-fixed" ]; then
    shift 3
    [ $# -gt 0 ] || die 67 "--mark-fixed needs at least one finding id"
    : > "$WORK/fixids"
    for id in "$@"; do
        case "$id" in
            *[!0-9a-f]*|"") die 65 "finding id [$id] is not 16 lowercase hex characters" ;;
        esac
        [ "${#id}" -eq 16 ] || die 65 "finding id [$id] is not 16 lowercase hex characters"
        printf '%s\n' "$id" >> "$WORK/fixids"
    done
    problems=$(printf '%s' "$LEDGER_JSON" | jq -r --arg panel "$PANEL" --rawfile ids "$WORK/fixids" "$JQ_DEFS"'
        . as $l
        | ($ids | split("\n") | map(select(. != "")) | unique)[] as $id
        | ($l.findings // {})[$id] as $f
        | if $f == null or $f.panel != $panel then "the \($panel) ledger holds no finding [\($id)]"
          elif $f.severity != "blocking" then "finding [\($id)] is advisory, and advisory findings are never re-verified"
          elif ($f | closed($l.runs // {})) then "finding [\($id)] is already closed"
          else empty end') || die 65 "could not read $LEDGER"
    [ -z "$problems" ] || die 65 "$(printf '%s' "$problems" | head -n 3 | tr '\n' ';')"
    ROUND_NO=$(printf '%s' "$LEDGER_JSON" | jq --arg p "$PANEL" '[(.history // [])[] | select(.panel == $p) | .round] | max // 1')
    printf '%s' "$LEDGER_JSON" | jq --arg head "$HEAD" --argjson round "$ROUND_NO" --rawfile ids "$WORK/fixids" '
        .rev = ((.rev // 0) + 1)
        | .rev as $rev
        | reduce ($ids | split("\n") | map(select(. != "")) | unique)[] as $id (.;
            .findings[$id].records += [{kind: "fixed", writer: {kind: "agent", name: "work-on"},
                                        round: $round, commit: $head, rev: $rev}])' > "$WORK/ledger" \
        || die 65 "could not write the fixed records"
    store_ledger "$WORK/ledger"
    exit 0
fi

# ---------------------------------------------------------------- --record ----

# The round file is checked whole before anything is written, the new ledger
# is built whole in $WORK, and it is stored with one `koto context add`, so a
# refusal (65) or a racing write (69) leaves the stored ledger byte-identical.
if [ "$MODE" = "--record" ]; then
    ROUND_FILE="${4:-}"
    # The seats judged the commit the scope was planned at. If HEAD has moved
    # since, stamping their verdicts with it would vouch for a commit none of
    # them saw. No scope (the --plan fallback path) has nothing to compare.
    SCOPE_JSON=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$SCOPE_JSON" ] && ! printf '%s' "$SCOPE_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
        die 65 "${PANEL}_scope.json is unreadable"
    fi
    scope_head=$(printf '%s' "${SCOPE_JSON:-{\}}" | jq -r '.head // empty')
    [ -z "$scope_head" ] || [ "$scope_head" = "$HEAD" ] \
        || die 68 "HEAD moved since ${PANEL}_scope.json was planned at $scope_head; tick koto without evidence to re-plan, then run the round again"
    [ -n "$ROUND_FILE" ] || die 67 "missing round file for --record"
    [ -f "$ROUND_FILE" ] || die 65 "round file [$ROUND_FILE] not found"
    jq -e 'type == "array" and length > 0 and all(.[]; type == "object")' "$ROUND_FILE" >/dev/null 2>&1 \
        || die 65 "round file [$ROUND_FILE] is not a JSON array of runs"

    # Every problem in the round file, one per line. Empty means it may be
    # recorded. The checks need the scope (which runs were planned, which ids
    # each run may answer) and the ledger (which runs are already recorded,
    # which ids exist).
    problems=$(jq -r --argjson scope "${SCOPE_JSON:-null}" --argjson l "$LEDGER_JSON" \
        --arg panel "$PANEL" --arg seats "$SEATS" "$JQ_DEFS"'
        ($seats | split(" ")) as $real
        | (($scope // {}).decisions // []) as $decs
        | [ .[] | . as $e
            | if (.decider? != null) then
                (.decider | if type != "object" then "a decider entry is not an object"
                 else ( (if (.state | type) != "string" or .state == "" then "a decider entry has no state" else empty end),
                        (if (.visit_seq | type) != "number" then "a decider entry has no visit_seq" else empty end),
                        (if (.gate | type) != "string" or (.gate | test(name_re) | not) then "a decider entry has no valid gate" else empty end),
                        (if (.rule_id | type) != "string" or (.rule_id | test(rule_re) | not) then "a decider entry has no valid rule_id" else empty end),
                        (if (.declaration_hash | type) != "string" or (.declaration_hash | test("^[0-9a-f]{8,64}$") | not) then "a decider entry has no valid declaration_hash" else empty end),
                        (if (.outcome | type) != "string" or .outcome == "" then "a decider entry has no outcome" else empty end) )
                 end)
              else
                (.seat // "") as $seat
                | ([$decs[] | select(.seat == $seat)][0] // null) as $d
                | ( (if ($seat | type) != "string" or $seat == "" then "an entry names no seat"
                     elif ($real | index($seat)) == null and ($seat != "reverifier" or $d == null) then "seat [\($seat)] is not a \($panel) seat"
                     else empty end),
                    (if ($e.run | type) != "string" or ($e.run | test(run_re) | not) then "seat [\($seat)] has no valid run id"
                     elif $d != null and ($d.run // null) != null and $d.run != $e.run then "seat [\($seat)] names run [\($e.run)], but the scope minted [\($d.run)]"
                     elif ($scope != null) and $d == null then "seat [\($seat)] was not planned in \($panel)_scope.json"
                     elif $d != null and $d.decision == "keep" then "seat [\($seat)] was kept, not spawned, in \($panel)_scope.json"
                     elif (($l.runs // {})[$e.run].recorded // false) then "run [\($e.run)] is already recorded"
                     else empty end),
                    (if ($e.findings // []) | type != "array" then "seat [\($seat)]: findings is not an array"
                     elif ($e.findings // [] | length) > 50 then "seat [\($seat)]: more than 50 findings"
                     elif $seat == "reverifier" and ($e.findings // [] | length) > 0 and (($d.fix_review // false) | not) then "the reverifier raised findings, but the scope planned no fix-diff review"
                     else ($e.findings // [])[] | finding_problem($seat) end),
                    (if ($e.answers // []) | type != "array" then "seat [\($seat)]: answers is not an array"
                     elif ($e.answers // [] | length) > 50 then "seat [\($seat)]: more than 50 answers"
                     else ($e.answers // [])[] | answer_problem($seat; $d; $l; $panel) end),
                    (if ($e.cited // []) | type != "array" then "seat [\($seat)]: cited is not an array" else empty end) )
              end ]
        + ( [ .[] | select(.run? != null) | .run ] | group_by(.) | map(select(length > 1) | "run [\(.[0])] appears twice in the round file") )
        | .[]' "$ROUND_FILE" 2>"$WORK/jq.err") || die 65 "could not read round file [$ROUND_FILE]: $(head -n 1 "$WORK/jq.err")"
    [ -z "$problems" ] || die 65 "round file [$ROUND_FILE] refused: $(printf '%s' "$problems" | head -n 5 | tr '\n' ';')"

    # Every rule id a finding names must be an active registry entry now.
    for rid in $(jq -r '[.[] | (.findings // [])[] | .rule_id? // empty] + [.[] | .decider?.rule_id? // empty] | unique | .[]' "$ROUND_FILE"); do
        "$REGISTRY" ref "$rid" >/dev/null 2>&1 || die 65 "round file [$ROUND_FILE] names rule [$rid], which is not an active registry entry"
    done

    # A decider entry is accepted only when koto's own log holds the event it
    # names, and each event backs one entry: the log is koto's to write, so a
    # round file alone can't mint a decider verdict.
    : > "$WORK/decider_events"
    if jq -e 'any(.[]; .decider? != null)' "$ROUND_FILE" >/dev/null; then
        sdir=$(koto session dir "$SESSION" 2>/dev/null) || die 65 "a decider entry needs koto's session log, and koto session dir failed"
        slog="$sdir/koto-$SESSION.state.jsonl"
        [ -r "$slog" ] || die 65 "a decider entry needs koto's session log, and [$slog] can't be read"
        jq -c '.[] | .decider? // empty' "$ROUND_FILE" | while IFS= read -r dec; do
            key=$(printf '%s' "$dec" | jq -r '"\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)"')
            if ! jq -e --argjson d "$dec" 'select(.type? == "decider_checked") | .payload
                    | select(.state == $d.state and .visit_seq == $d.visit_seq and .gate == $d.gate
                             and .rule_id == $d.rule_id and .declaration_hash == $d.declaration_hash
                             and .outcome == $d.outcome
                             and (($d.input_sha256 // null) == null or .input_sha256 == $d.input_sha256))' \
                    "$slog" >/dev/null 2>&1; then
                echo "MISSING $key"
            fi
            printf '%s\n' "$key"
        done > "$WORK/decider_events"
        if grep -q '^MISSING ' "$WORK/decider_events"; then
            die 65 "koto's log holds no decider_checked event for: $(grep '^MISSING ' "$WORK/decider_events" | head -n 1 | cut -c9-)"
        fi
        dup=$(sort "$WORK/decider_events" | uniq -d | head -n 1)
        [ -z "$dup" ] || die 65 "decider event [$dup] backs two entries"
        used=$(printf '%s' "$LEDGER_JSON" | jq -r '(.decider_events // [])[]' | grep -Fxf "$WORK/decider_events" | head -n 1)
        [ -z "$used" ] || die 65 "decider event [$used] already backed an earlier entry"
    fi

    # The id of every finding raised this round: a hash of panel, raiser kind
    # and name, path and whitespace-collapsed summary. jq builds the string and
    # git hashes it from stdin; nothing a reviewer wrote reaches an argument.
    jq -c --arg panel "$PANEL" "$JQ_DEFS"'
        to_entries[] | .key as $i | .value
        | if .decider? != null then
            {i: $i, j: 0, canon: canon($panel; "decider"; "\(.decider.gate)/\(.decider.rule_id)"; ""; .decider.rule_id)}
          else
            (if .seat == "reverifier" then "fix-review" else .seat end) as $name
            | (.findings // []) | to_entries[]
            | {i: $i, j: .key, canon: canon($panel; "reviewer"; $name; (.value.path // ""); .value.summary)}
          end' "$ROUND_FILE" > "$WORK/canon" || die 65 "could not read the findings in round file [$ROUND_FILE]"
    : > "$WORK/ids"
    while IFS= read -r c; do
        id=$(printf '%s' "$c" | jq -j '.canon' | git hash-object --stdin) || die 65 "git hash-object failed"
        printf '%s' "$c" | jq -c --arg id "${id:0:16}" '{i, j, id: $id, canon}' >> "$WORK/ids"
    done < "$WORK/canon"
    problems=$(jq -rs --argjson l "$LEDGER_JSON" '
        ( group_by(.i) | map(group_by(.id) | map(select(length > 1) | "two findings of one run share id \(.[0].id): word their summaries apart")) | flatten[] ),
        ( .[] | . as $f | ($l.findings // {})[$f.id] // null | select(. != null and .canon != $f.canon)
          | "finding id \($f.id) collides with a different finding already in the ledger" )' "$WORK/ids")
    [ -z "$problems" ] || die 65 "round file [$ROUND_FILE] refused: $(printf '%s' "$problems" | head -n 3 | tr '\n' ';')"

    # A seat's earlier citations carry forward, but their line ranges are in
    # the numbering of the commit it judged then. Where the file has changed
    # since, the range no longer names the same code, so only the path is
    # carried: coarser, never wrong.
    : > "$WORK/moved"
    for s in $(jq -r '.[] | .seat? // empty' "$ROUND_FILE"); do
        old=$(printf '%s' "$LEDGER_JSON" | jq -r --arg k "$PANEL/$s" '.seats[$k].judged_at // empty')
        [ -n "$old" ] || continue
        if git rev-parse --verify -q "${old}^{commit}" >/dev/null; then
            git diff --no-renames --name-only "$old" HEAD | jq -R --arg s "$s" '{seat: $s, path: .}'
        else
            jq -n --arg s "$s" '{seat: $s, path: "*"}'
        fi >> "$WORK/moved"
    done
    ROUND_NO=$(printf '%s' "$LEDGER_JSON" | jq --arg p "$PANEL" '[(.history // [])[] | select(.panel == $p) | .round] | max // 1')
    printf '%s' "$LEDGER_JSON" | jq --arg panel "$PANEL" --arg head "$HEAD" --arg ac "$AC_SHA" \
        --arg seats "$SEATS" --argjson round "$ROUND_NO" --argjson scope "${SCOPE_JSON:-null}" \
        --slurpfile entries "$ROUND_FILE" --slurpfile ids "$WORK/ids" --slurpfile moved "$WORK/moved" \
        --rawfile events "$WORK/decider_events" "$JQ_DEFS"'
        def norm: map(select(.path | type == "string")
                      | {path} + (if .lines then {lines: (.lines | tostring)} else {} end));
        def carry($seat): map(. as $c
            | if any($moved[]; .seat == $seat and (.path == $c.path or .path == "*"))
              then {path: $c.path} else $c end);
        def idof($i; $j): ([$ids[] | select(.i == $i and .j == $j)][0]);
        def loc($f): if ($f.path // "") == "" then {kind: "none", at: $head}
                     elif ($f.lines // "") != "" then {kind: "lines", path: $f.path, lines: ($f.lines | tostring), at: $head}
                     else {kind: "file", path: $f.path, at: $head} end;
        def record($kind; $writer; $reason):
            {kind: $kind, writer: $writer, round: $round, commit: $head, rev: .rev}
            + (if ($reason // "") != "" then {reason: $reason} else {} end);
        # raise($id; $canon; $raiser; $run; $f): add or re-open a finding.
        def raise($id; $canon; $raiser; $run; $f):
            .rev as $rev
            | (.findings[$id] // null) as $old
            | .findings[$id] = (
                if $old == null then
                  {id: $id, canon: $canon, panel: $panel,
                   severity: $f.severity, round: $round, raiser: $raiser, run: $run,
                   location: loc($f), summary: $f.summary, records: []}
                  + (if ($f.rule_id // "") != "" then {rule_id: $f.rule_id} else {} end)
                else
                  $old
                  | .severity = (if .severity == "blocking" or $f.severity == "blocking" then "blocking" else "advisory" end)
                  | .location = loc($f)
                end
                | .records += [{kind: ($f.first_kind // "raised"),
                                writer: ($raiser + {run: $run}), round: $round, commit: $head, rev: $rev}])
            ;
        $entries[0] as $E
        | .rev = ((.rev // 0) + 1)
        | .seats = (.seats // {})
        | .findings = (.findings // {})
        | .runs = (.runs // {})
        | .decider_events = ((.decider_events // []) + ($events | split("\n") | map(select(. != ""))))
        | reduce ($E | to_entries[]) as $x (.;
            $x.key as $i | $x.value as $e
            | if $e.decider? != null then
                ($e.decider) as $d
                | idof($i; 0) as $idr
                | {kind: "decider", name: "\($d.gate)/\($d.rule_id)",
                   ref: ($d | {state, visit_seq, gate, rule_id, declaration_hash} + (if .input_sha256 then {input_sha256} else {} end))} as $raiser
                | ($e.run // "decider:\($d.visit_seq):\($d.gate):\($d.rule_id)") as $run
                | .runs[$run] = {panel: $panel, rev: .rev, recorded: true}
                | if $d.outcome == "fail" then
                    raise($idr.id; $idr.canon; $raiser; $run; {severity: "blocking", summary: $d.rule_id, rule_id: $d.rule_id})
                  elif $d.outcome == "pass" then
                    if (.findings[$idr.id] // null) == null then .
                    else .findings[$idr.id].records += [record("reverified"; $raiser + {run: $run}; "")] end
                  elif (.findings[$idr.id] // null) == null then
                    raise($idr.id; $idr.canon; $raiser; $run; {severity: "blocking", summary: $d.rule_id, rule_id: $d.rule_id, first_kind: "unverified"})
                  else .findings[$idr.id].records += [record("unverified"; $raiser + {run: $run}; "")] end
              else
                $e.seat as $seat
                | {kind: "reviewer", name: (if $seat == "reverifier" then "fix-review" else $seat end)} as $raiser
                | {kind: "reviewer", name: $seat, run: $e.run} as $writer
                | .runs[$e.run] = {panel: $panel, rev: .rev, recorded: true}
                | reduce (($e.findings // []) | to_entries[]) as $fx (.;
                    idof($i; $fx.key) as $idr
                    | raise($idr.id; $idr.canon; $raiser; $e.run; $fx.value))
                | reduce ($e.answers // [])[] as $a (.;
                    .findings[$a.id].records += [record($a.record; $writer; $a.reason)]
                    | if ($a.path // "") != "" then .findings[$a.id].location = loc($a) else . end)
                | if $seat == "reverifier" then
                    .reverified[$panel] = {rev: .rev, run: $e.run, head: $head}
                  else
                    ("\($panel)/\($seat)") as $k
                    | ((.seats[$k].cited // []) | carry($seat)) as $old_cited
                    | ((.seats[$k].finding_locations // []) | carry($seat)) as $old_locs
                    | .seats[$k] = ((.seats[$k] // {}) + {
                        panel: $panel, seat: $seat, judged_at: $head, rev: .rev, ac_sha: $ac,
                        cited: ($old_cited + (($e.cited // []) | norm) | unique),
                        finding_locations: ($old_locs
                            + ([($e.findings // [])[] | select(.path) | {path, lines}] | norm) | unique)})
                  end
              end)
        # Every seat summary of the panel follows from the findings: a seat is
        # blocking exactly while it raised an unclosed blocking finding, and its
        # findings are the unclosed ones it raised, in the shape the readers of
        # seat entries (review-shadow.py, review-packet.sh) expect.
        | . as $L
        | reduce ($seats | split(" "))[] as $s (.;
            ("\($panel)/\($s)") as $k
            | if (.seats[$k] // null) == null then . else
                [ $L.findings[] | select(.panel == $panel and .raiser.kind == "reviewer" and .raiser.name == $s)
                  | select(closed($L.runs) | not) ] as $open
                | .seats[$k].findings = [ $open[] | {id, severity, summary}
                    + (if .location.path then {path: .location.path} else {} end)
                    + (if .location.lines then {lines: .location.lines} else {} end) ]
                | .seats[$k].verdict = (if any($open[]; .severity == "blocking") then "blocking" else "passed" end)
              end)' > "$WORK/ledger" || die 65 "could not merge [$ROUND_FILE] into the ledger"
    store_ledger "$WORK/ledger"
    shadow_site
    exit 0
fi

# ---------------------------------------------------------------- --plan ------

IMPL_BASE=$(ctx_get impl_base | tr -d '[:space:]')
TAB=$(printf '\t')

# Does the fix diff from $1 to HEAD touch a cited entry? Reads the cited list
# (one "path<TAB>lines" per line, lines possibly empty) on stdin. Prints the
# first touched entry and returns 0, or returns 1. A diff that fails to run
# counts as touching: the safe answer is to review again.
touches() {
    local from="$1" path lines lo hi
    git diff --no-renames --name-only "$from" HEAD > "$WORK/fixpaths" \
        || { echo "(git diff failed)"; return 0; }
    while IFS="$TAB" read -r path lines; do
        [ -n "$path" ] || continue
        grep -Fxq -- "$path" "$WORK/fixpaths" || continue
        if [ -z "$lines" ]; then
            printf '%s\n' "$path"
            return 0
        fi
        lo=${lines%%-*}
        hi=${lines#*-}
        case "$lo$hi" in *[!0-9]*|"") printf '%s\n' "$path"; return 0 ;; esac
        # Old-side range of each fix hunk in this file: `@@ -a,b +c,d @@`. A
        # missing b means 1; b == 0 is an insertion between lines a and a+1.
        if git diff --no-renames -U0 "$from" HEAD -- "$path" | awk -v lo="$lo" -v hi="$hi" '
            /^@@ / {
                n = split(substr($2, 2), o, ",")
                a = o[1] + 0
                b = (n > 1) ? o[2] + 0 : 1
                if (b == 0) { s = a; e = a + 1 } else { s = a; e = a + b - 1 }
                if (s <= hi + 0 && e >= lo + 0) { found = 1; exit }
            }
            END { exit found ? 0 : 1 }'; then
            printf '%s:%s\n' "$path" "$lines"
            return 0
        fi
    done
    return 1
}

# Two facts that hold for every seat this entry. A dirty tree means the fix
# may not be committed yet, and the diff below would not see it. No commits
# since impl_base, or none recorded, means there is nothing to have passed:
# the has_commits gate on scrutiny's passed edge holds, and a carried verdict
# must not slip past it.
DIRTY=""
[ -n "$(git status --porcelain | head -1)" ] && DIRTY=1
NOCOMMITS=""
if [ -z "$IMPL_BASE" ] || [ "$(git rev-list --count "$IMPL_BASE..HEAD" || echo 0)" = 0 ]; then
    NOCOMMITS=1
fi

# A blocking round already recorded at this HEAD is not planned again. koto
# runs --plan on every tick that carries no evidence, and the agent ticks with
# none once the round is recorded, so the <panel>_verdict gate can route it. A
# fresh plan there would turn the seat that just blocked into a new round's
# recheck, with no fix to re-check, and --verdict would hold the panel (exit 2)
# on a round that is complete instead of reporting the block (exit 1). The
# scope stands while HEAD, a clean tree and the criteria are what the round
# was recorded against, every seat it spawned has a verdict recorded since it
# was planned, and one of them is blocking. Anything else plans as before: a
# commit, an uncommitted change, rewritten criteria or a seat still unrecorded
# start a new round, and a recorded round with no blocking seat re-plans to
# keep every seat, which is the carried route.
if [ -z "$DIRTY" ]; then
    prev_scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$prev_scope" ] && [ "$(jq -n --argjson s "$prev_scope" --argjson l "$LEDGER_JSON" \
            --arg panel "$PANEL" --arg head "$HEAD" --arg ac "$AC_SHA" '
            [$s.decisions[] | select(.decision != "keep") | $l.seats[$panel + "/" + .seat] // null] as $spawned
            | $s.head == $head
              and ($spawned | length > 0)
              and all($spawned[]; . != null and ((.rev // -1) > ($s.rev // -1)) and .ac_sha == $ac)
              and any($spawned[]; .verdict == "blocking")')" = true ]; then
        echo "panel-scope: the $PANEL round planned at $(printf '%.12s' "$HEAD") is recorded with a blocking seat; its scope stands" >&2
        printf '%s\n' "$prev_scope"
        exit 0
    fi
fi

: > "$WORK/decisions"
for seat in $SEATS; do
    entry=$(printf '%s' "$LEDGER_JSON" | jq -c --arg k "$PANEL/$seat" '.seats[$k] // empty')
    if [ -z "$entry" ]; then
        decision=full
        reason="no verdict on record for this seat"
    else
        verdict=$(printf '%s' "$entry" | jq -r '.verdict')
        judged=$(printf '%s' "$entry" | jq -r '.judged_at // ""')
        ac=$(printf '%s' "$entry" | jq -r '.ac_sha // ""')
        short=$(printf '%.12s' "$judged")
        # The blocking findings only: an advisory one is not what the seat
        # blocked on, and a re-check is about what it blocked on. A finding
        # with no severity is from a ledger written before severity existed,
        # when every recorded finding was a blocking one.
        nfind=$(printf '%s' "$entry" | jq "[$BLOCKING_FINDINGS] | length")
        # A blocking seat goes through the same invalidation checks as a
        # passed one before it is offered the narrow re-check: a re-check that
        # passes stamps the seat passed at HEAD, so anything that would make a
        # passed seat re-run must not reach it disguised as a fix.
        if [ "$verdict" = "blocking" ] && [ "$nfind" -eq 0 ]; then
            decision=rerun
            reason="blocked at $short but recorded no findings to re-check"
        elif [ -n "$DIRTY" ]; then
            decision=rerun
            reason="the working tree has uncommitted changes, so the fix diff cannot be judged: commit the fix and tick again"
        elif [ -n "$NOCOMMITS" ]; then
            decision=rerun
            reason="no commits since impl_base, or impl_base is unrecorded (has_commits fails either way); nothing to carry a pass for"
        elif [ "$ac" != "$AC_SHA" ]; then
            decision=rerun
            reason="acceptance criteria changed since it judged at $short"
        elif ! git rev-parse --verify -q "${judged}^{commit}" >/dev/null \
            || ! git merge-base --is-ancestor "$judged" HEAD; then
            decision=rerun
            reason="the commit it judged ($short) is not an ancestor of HEAD"
        else
            changed=$(git diff --no-renames --numstat "$judged" HEAD \
                | awk '{ a = ($1 == "-") ? 1 : $1; d = ($2 == "-") ? 1 : $2; n += a + d } END { print n + 0 }')
            nfiles=$(git diff --no-renames --name-only "$judged" HEAD | wc -l | tr -d ' ')
            if [ "$verdict" = "blocking" ]; then
                if [ "$changed" -gt "$THRESHOLD_LINES" ]; then
                    decision=rerun
                    reason="raised $nfind blocking finding(s) at $short, but the fix diff changes $changed lines, over the $THRESHOLD_LINES-line threshold"
                else
                    decision=recheck
                    reason="raised $nfind blocking finding(s) at $short; re-check them against the fix diff ($changed lines in $nfiles files)"
                fi
            else
                # The seat's own citations decide whether it fell back to the diff
                # it judged; the locations of findings it raised are added either
                # way, so a fix near a finding re-checks the seat that raised it.
                printf '%s' "$entry" | jq -r '.cited[]? | [.path, (.lines // "" | tostring)] | @tsv' > "$WORK/cited"
                cited_what="what it cited"
                if [ ! -s "$WORK/cited" ]; then
                    git diff --no-renames --name-only "$IMPL_BASE" "$judged" \
                        | awk -v t="$TAB" '{ print $0 t }' > "$WORK/cited"
                    cited_what="the diff it judged"
                fi
                printf '%s' "$entry" | jq -r '.finding_locations[]? | [.path, (.lines // "" | tostring)] | @tsv' >> "$WORK/cited"
                if [ "$changed" -eq 0 ]; then
                    decision=keep
                    reason="nothing changed since it passed at $short"
                elif [ "$changed" -gt "$THRESHOLD_LINES" ]; then
                    decision=rerun
                    reason="fix diff since $short changes $changed lines, over the $THRESHOLD_LINES-line threshold"
                elif [ ! -s "$WORK/cited" ]; then
                    decision=rerun
                    reason="cited nothing, and the diff it judged is empty"
                elif hit=$(touches "$judged" < "$WORK/cited"); then
                    decision=rerun
                    reason="fix diff since $short touches $hit, in $cited_what"
                else
                    decision=keep
                    reason="fix diff since $short ($changed lines in $nfiles files) touches nothing in $cited_what"
                fi
            fi
        fi
    fi
    # scripts/review-packet.sh recheck reads a recheck decision's `findings`
    # and `fix_diff_from` to build that seat's packet, and relies on
    # fix_diff_from being an ancestor of HEAD (checked above). Renaming either
    # field, or offering recheck on a commit off HEAD's history, changes what
    # that packet holds; panel-scope_test.sh drives the two scripts together.
    jq -nc --arg seat "$seat" --arg d "$decision" --arg r "$reason" --argjson e "${entry:-null}" \
        "def blocking_findings: [$BLOCKING_FINDINGS];"'
        {seat: $seat, decision: $d, reason: $r}
        + (if $d == "recheck" then {findings: ($e | blocking_findings), fix_diff_from: $e.judged_at} else {} end)
        + (if $d == "rerun" or $d == "keep" then {judged_at: $e.judged_at} else {} end)
        ' >> "$WORK/decisions"
    entry=""
done

jq -s --arg panel "$PANEL" --arg head "$HEAD" --argjson rev "$(printf '%s' "$LEDGER_JSON" | jq '.rev // 0')" \
    '{panel: $panel, head: $head, rev: $rev, decisions: .}' \
    "$WORK/decisions" > "$WORK/scope"

# The history entry for this round. Replaced, not appended, when the previous
# entry for this panel is at the same HEAD and nothing was recorded since.
printf '%s' "$LEDGER_JSON" | jq --slurpfile scope "$WORK/scope" '
    ($scope[0]) as $s
    | .history = (.history // [])
    | (.rev // 0) as $rev
    | ([.history | to_entries[] | select(.value.panel == $s.panel)] | last) as $prev
    | {panel: $s.panel, head: $s.head, rev: $rev,
       spawned: ([$s.decisions[] | select(.decision != "keep")] | length),
       decisions: [$s.decisions[] | {seat, decision, reason}]} as $entry
    | if $prev != null and $prev.value.head == $s.head and $prev.value.rev == $rev
      then .history[$prev.key] = ($entry + {round: $prev.value.round})
      else .history += [$entry + {round: ([.history[] | select(.panel == $s.panel)] | length + 1)}]
      end' > "$WORK/ledger" || die 65 "could not update the ledger history"

# Order matters for the gate: the carried results go in before the scope, so a
# scope that keeps every seat is never visible without them.
if jq -e 'all(.decisions[]; .decision == "keep")' "$WORK/scope" >/dev/null; then
    jq '{passed: true, carried: true, head: .head,
         seats: [.decisions[] | {seat, decision, reason}]}' "$WORK/scope" > "$WORK/results"
    put "${PANEL}_results.json" "$WORK/results"
fi
put "$LEDGER" "$WORK/ledger"
put "${PANEL}_scope.json" "$WORK/scope"
cat "$WORK/scope"
exit 0
