#!/usr/bin/env bash
# panel-scope.sh -- for /work-on: what a panel round actually has to run,
# decided from the findings ledger and git rather than from the agent's
# judgment.
#
# Without it, a blocking finding from any of the three panels would clear all
# three verdicts and send the run back through all seven seats: three
# scrutiny, three review, one QA. Two retries could spawn 21 reviewers for one
# issue, and a QA finding about one test would re-run reviewers on code they
# had already passed.
#
# Every finding a reviewer raises is kept in the ledger under a content id,
# with the records written about it since. A retry is planned over those
# findings, not over seats: only the findings a fix touched (or that are
# otherwise due, below) are re-verified, by one run per panel, and the panel
# passes only when every blocking finding is closed by a record its writer
# was allowed to write.
#
# ## Planning a round (--plan)
#
# A round is **full** when any of these holds, checked in this order:
#
#   - a seat of the panel has no recorded verdict (the panel's first round)
#   - the ledger has no `findings` key (written before finding records)
#   - the acceptance criteria or the plan changed since a seat judged (the git
#     hash of the `context.md` and `plan.md` context keys differs). context.md
#     is written at setup and plan.md at analysis, so in practice this fires
#     when a scope_expanded_retry or scope_changed_retry rewrote the plan
#   - the working tree has uncommitted changes, untracked files included (the
#     fix may not be committed, and the diff below would miss it)
#   - there are no commits since impl_base, or no impl_base recorded (nothing
#     for a carried verdict to rest on; scrutiny's has_commits gate must not
#     be slipped past)
#   - a commit the panel recorded (a seat's judged_at, the re-verifier's
#     marker, a finding record not written by the agent) is no longer an
#     ancestor of HEAD (a rebase or reset rewrote what it judged)
#   - the panel's newest recorded commit has no commits since impl_base: its
#     seats judged an empty change, so they have not reviewed this one
#   - the diff from the panel's newest recorded commit to HEAD changes more
#     than THRESHOLD_LINES lines (added plus deleted per --numstat, a binary
#     file 1 per side), or that diff fails. A fix that large is new work, and
#     one re-verifier reading it is no substitute for the panel's seats. It is
#     measured from this panel's own records, so a large fix one panel
#     reviewed in full still reaches the next panel's seats. 200 is a
#     judgment, not a measurement: about one screenful of diff per seat
#   - nothing the ledger recorded can bound a fix diff: the panel recorded no
#     commit, or no commit any panel recorded is an ancestor of HEAD, or the
#     diff from it fails. The safe answer to a diff it can't judge is to
#     review everything
#
# In a full round every seat is `full`, gets a run id, and its decision
# carries the seat's own unclosed blocking findings, which it answers by id
# (holds, reverified, or dismissed with a reason: a full round is the one
# place a seat may dismiss its own finding). Unclosed blocking findings no
# seat of the panel raised (the fix-diff review's, a decider's) go to one
# `reverifier` decision in the same round, so a full round never drops one.
#
# Any other round runs no seat: every real seat is `keep`, and at most one
# run is planned, the panel's re-verifier (seat `reverifier`, a name no panel
# uses for a real seat), given every **due** blocking finding by id:
#
#   status        location touched   untouched   none or unresolvable
#   open          due                not due     due
#   fixed         due                due         due
#   unverified    due                due         due
#   closed        due (regression)   not due     not due
#
# Closed means a reverified or dismissed latest record that its writer was
# allowed to write; one written by any other writer leaves the finding open.
# A finding's base is the commit of its latest record not written by the
# agent, the last time something judged it; "touched" is judged on
# `git diff --no-renames <base> HEAD`. A `lines` location (numbered at the
# commit it was recorded at) is touched when a fix hunk's old-side range
# overlaps it -- a pure insertion (`@@ -a,0 ...`) sits between lines a and a+1
# and touches a range containing either -- but only when the file didn't
# change between the location's commit and the base; otherwise it is judged
# as a `file` location, touched when the fix changes the path at all.
# Renames are off, so moving a file touches it. A base or location commit
# that is gone, or a diff that fails, makes the location unresolvable. A
# finding judged at HEAD is not due unless a later `fixed` record asks for it.
# A not-due finding keeps its status and costs no run; an open one still
# blocks --verdict.
#
# The re-verifier also carries the **fix-diff review** when the diff from the
# newest commit any panel recorded (never counting a record the agent wrote:
# --mark-fixed stamps HEAD) to HEAD is non-empty. Its findings are raised by
# reviewer `fix-review` in this panel and block it. Once this panel records,
# that commit is HEAD, so later panels in the same retry see an empty diff and
# plan none. When two candidates aren't ordered by ancestry, the older is
# taken, which widens the diff. A full round plans no fix-diff review: its
# seats review the whole change.
#
# With nothing due and no fix-diff review, nothing runs. The panel carries
# (`<panel>_results.json`, marked carried) only when it also has no unclosed
# blocking finding; otherwise --verdict blocks it with no run spent.
#
# --plan mints a run id for every decision it spawns (`<panel>-r<round>-<seat>`),
# and --record accepts each run once, only as the decision it was planned for.
#
# ## Modes
#
# The template runs --plan on each entry to a panel state, and --carried,
# --recorded and --verdict as that state's gates (evaluated on every tick
# there); the agent runs --record once per round and --mark-fixed after a fix:
#
#   --plan <panel> <session>     default_action on `scrutiny`, `review`,
#                                `qa_validation` and `light_review`. Writes
#                                `<panel>_scope.json` and appends the round's
#                                decisions, with their reasons and the finding
#                                ids they carry, to the ledger's history. When
#                                every seat is `keep`, nothing is due and no
#                                blocking finding is unclosed, it also writes
#                                `<panel>_results.json`, marked carried.
#   --carried <panel> <session>  the `<panel>_carried` gate. Exit 0 when the
#                                tree is clean, the scope written for this
#                                HEAD keeps every seat, the carried results
#                                are in place and the panel has no unclosed
#                                blocking finding, so koto advances the panel
#                                with no spawn.
#   --recorded <panel> <session> the `<panel>_recorded` gate on the passed and
#                                blocking_retry edges. Exit 1 while a run the
#                                scope planned is not recorded.
#   --verdict <panel> <session>  the `<panel>_verdict` gate: the panel's pass,
#                                computed from the ledger rather than reported
#                                by the agent (DESIGN-output-gates Decision 4).
#                                Exit 0 when every blocking finding of the panel
#                                is closed, 1 printing one finding per unclosed
#                                one, 2 when the round is not fully recorded or
#                                the ledger can't be read.
#   --open-count <panel> <session>
#                                the number of findings --verdict would print,
#                                on stdout, with no side effect; for
#                                panel-retry-budget.sh.
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
#        panel-scope.sh --open-count <panel> <koto-session-name>
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
#                  "reason": "...", "path": "<optional new location>"}],
#     "test_edits": [{"path": "tests/a_test.sh", "judgment": "corrects|weakens",
#                     "reason": "<optional>"}]}]
#
# `test_edits` judges the unit's edited tests: the paths
# scripts/lib/test-classify.sh's test_classify_unit labels `edited` from
# impl_base (else the merge-base review-packet.sh falls back to) to HEAD, with
# the session's stored rules copy and, for a fix, the red's record, so they are
# the tests the packet's `## Test changes` section listed as edited. Every real
# seat of the panel in the round must judge each one `corrects` or `weakens`;
# a round where one doesn't is refused whole (65, naming rule
# review/test-edit-judgment), and so is a judgment with any other value. Each
# `weakens` is recorded as a blocking finding raised by that seat, under rule
# review/test-edit-weakens, with the reason in its summary, and closes like any
# other finding of that seat. The seat entry keeps its judgments as
# `test_edits`. The re-verifier and decider entries judge no test edit.
#
# `run` is required: when the scope's decision for the seat names a run, the
# entry must name the same one, and no run is recorded twice. A decision that
# names no run (one written by hand, or none at all on the fallback path)
# takes any well-formed run id. `answers` may
# name only the ids the seat's decision planned for it; a dismissal needs a
# reason and the seat that raised the finding, and the re-verifier (seat
# `reverifier`) may answer only holds or reverified, with a reason on each
# reverified, and may raise findings only when its decision planned a fix-diff
# review. A decider's verdict is an entry of its own,
# {"decider": {"state", "visit_seq", "gate", "rule_id", "declaration_hash",
# "input_sha256", "outcome"}}, accepted only when koto's session log holds a
# decider_checked event with those fields that no earlier entry used. The
# agent's answer to a criterion the decider couldn't grade is a
# decider_check_answered event, never decider_checked, so it can't back one.
#
# --record also imports every decider_checked event of the panel's state
# (scrutiny, review, qa_validation or light_review) that no entry used, so a
# decider batch's verdicts reach the ledger without the agent naming them. Of
# the events of one (state, visit, gate, criterion, declaration), a fail is the
# one kept, so the most severe outcome wins, and otherwise the last. A missing
# session log imports nothing; one that exists and can't be read is exit 65.
# A `koto session dir` that fails is exit 66 with koto's error, never an empty
# import, so a round whose log was never read can't pass as one with no
# decider verdict.
# Every decider entry, named or imported, takes its event's `mode`, and that
# decides what it does: a fail raises an advisory finding when the mode is
# exactly shadow and a blocking one otherwise (veto, a missing mode, anything
# else); a pass adds a reverified record to its own finding; any other outcome
# (escape, unanswered, not_graded) adds nothing in shadow and otherwise raises
# or records unverified, as a decider's no-verdict always has.
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
# locations are kept beside it, as `finding_locations`. Both carry forward from
# earlier rounds, so a seat's judged scope only grows; an earlier line range in
# a file that has changed since is carried as the bare path, because its
# numbers no longer name the same code.
#
# Every finding carries a `severity`, `blocking` or `advisory`, and a seat is
# recorded as blocking exactly while it raised an unclosed blocking finding. A
# finding with no severity, or any other value, makes --record refuse the
# whole round (65), so a seat can't be recorded as passing by leaving the
# field out. Advisory findings are recorded with `raised` and nothing else:
# they are never due, never counted and never block. `blocking_count`,
# `passed` and any other summary field are ignored: the verdict is the
# findings', not the agent's count of them.
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
#                          "spawned", "decisions": [{seat, decision, reason,
#                          findings?}]}]}
#                         Never cleared by a retry: it is what survives one.
#                         The seat entries are summaries of the findings, kept
#                         in the shape review-packet.sh reads.
#   <panel>_scope.json    this entry's decisions, for the agent to act on:
#                         {panel, head, rev, ac_sha, round, full, reason,
#                          decisions: [{seat, decision, reason, run?,
#                          findings?, fix_diff_from?, fix_review?,
#                          review_from?, judged_at?}]}
#   <panel>_results.json  only when the panel carries, read by --carried;
#                         otherwise the agent may write it at aggregation as
#                         the round's summary. No gate reads it for the pass:
#                         --verdict reads the ledger
#
# A `--plan` re-run at the same HEAD with no write to the ledger in between (a
# tick without evidence, say) replaces its own history entry instead of adding
# one, so the history counts rounds, not ticks. A --plan re-run at the same
# HEAD, on a clean tree and unchanged criteria, after every run the scope
# minted was recorded and with no `fixed` record written since, leaves the
# scope as it is, whether or not a finding is still open: that round is
# complete, and the <panel>_verdict gate reports its result. A `fixed` record
# written after the round re-plans it, so --mark-fixed takes effect at an
# unchanged HEAD.
#
# Diagnostics go to stderr. --plan prints the scope it wrote on stdout, for a
# human running it by hand; --verdict prints its findings and --open-count its
# count on stdout; the other modes print nothing.
#
# --verdict prints one koto finding per unclosed blocking finding:
#   ::koto-finding::{"rule_id":"panel/open-finding","level":"error",
#                    "message":"<rule summary>: <panel>/<raiser>: <summary>","path":"src/a.sh",
#                    "line":12,"rule_ref":"<path>#L<a>-L<b>@<revision>"}
# A finding that cites an active registry rule prints under that rule instead;
# one whose rule is no longer active prints under panel/open-finding, naming the
# old id in its message, so a retirement neither prints an inactive id nor
# wedges the gate. Rules resolve through scripts/lib/rule-findings.sh, which
# exits 2 when panel/open-finding itself can't be; `path` and `line` only when
# the finding names them. Every finding prints at panel/open-finding's stage,
# whichever rule it names (error at block, warning at warn, info at shadow,
# nothing at retired), and --verdict fails the panel only while that stage is
# block, after a line on stderr saying how to dispute a finding.
#
# Exit codes:
#   0   -- --plan/--record/--mark-fixed: written. --carried: the panel carries.
#          --recorded: every planned run was recorded, or there is no scope or
#          ledger to check. --verdict: every blocking finding is closed, or
#          panel/open-finding is below the block stage.
#          --open-count: the count is printed.
#   1   -- --carried: something has to run, a blocking finding is unclosed,
#          the working tree is dirty, or the scope is missing, stale,
#          unreadable or has no carried results beside it. --recorded: a
#          planned run wasn't recorded, or the keys can't be read. --verdict:
#          a blocking finding is unclosed. --carried and --recorded exit
#          nothing else: a gate exit the template does not route would hold
#          the state, and the safe answer to every doubt is "run the panel" or
#          "record the round".
#   2   -- --verdict and --open-count, for every doubt they have: a run the
#          scope planned has no record, a seat of the panel has no verdict at
#          all, the ledger is unreadable or has no `findings` key, the scope
#          can't be read, panel/open-finding can't be resolved, or a usage
#          error. 2 wins over 1: a verdict it can't compute holds the panel
#          state, where a 1 would send the agent to a retry or an escalation
#          on a guess.
#   64  -- not a git repository, HEAD names no commit, or mktemp failed
#   65  -- a JSON step failed or a write was refused: --record's round file
#          is missing, is not a JSON array of runs, names a seat outside the
#          panel, breaks a rule above (a run, an answer, a finding's shape or
#          severity, a rule id that isn't active, a decider event koto's log
#          doesn't hold), or --mark-fixed names an id that is unknown, advisory
#          or closed; or (--plan or --record) jq could not merge the result
#          into the ledger. A refused write leaves the ledger byte-identical
#   66  -- a `koto context add` failed, or --record's `koto session dir`
#          did; koto's own stderr says why
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
# The registry rule --verdict reports for a finding with no rule of its own
# (references/rule-registry.json). A finding that cites an active rule is
# reported under that rule, resolved at run time with rf_require_any.
RULE_IDS="panel/open-finding"
RULE_IDS_ANY_ACTIVE=1

die() {
    # $1 exit code, $2 message
    echo "panel-scope: $2" >&2
    exit "$1"
}

# session_dir <why>: sets SDIR to the session's directory from
# `koto session dir`, or exits 66 with <why> and koto's own last line of
# error. koto's error is read on a line of its own, because
# scripts/check-skill-requires.sh reads any flag on a line that calls koto as
# one of koto's flags.
SDIR=""
session_dir() {
    local err
    if SDIR=$(koto session dir "$SESSION" 2>"$WORK/session-dir.err"); then
        return 0
    fi
    err=$(tail -n 1 "$WORK/session-dir.err")
    die 66 "$1, and koto session dir failed: $err"
}

MODE="${1:-}"
PANEL="${2:-}"
SESSION="${3:-}"

# The gate modes answer every doubt, usage errors included, with one exit: 1
# for --carried and --recorded, 2 for --verdict and --open-count. See Exit
# codes.
refuse() {
    # $1 exit code for the other modes, $2 message
    case "$MODE" in
        --carried|--recorded) echo "panel-scope: $2" >&2; exit 1 ;;
        --verdict|--open-count) echo "panel-scope: $2" >&2; exit 2 ;;
    esac
    die "$1" "$2"
}

case "$MODE" in
    --plan|--carried|--recorded|--verdict|--open-count|--record|--mark-fixed) ;;
    "") die 67 "missing mode: expected --plan, --carried, --recorded, --verdict, --open-count, --record or --mark-fixed" ;;
    *)  die 67 "unrecognised mode [$MODE]: expected --plan, --carried, --recorded, --verdict, --open-count, --record or --mark-fixed" ;;
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

PLUGIN_ROOT_PS="$(cd "$(dirname "$0")/../../.." && pwd)"
REGISTRY="$PLUGIN_ROOT_PS/scripts/rule-registry.sh"
# shellcheck source=../../../scripts/lib/test-classify.sh
. "$PLUGIN_ROOT_PS/scripts/lib/test-classify.sh" || refuse 64 "cannot load scripts/lib/test-classify.sh"

# The jq every mode that reads or writes findings shares: the shapes --record
# accepts, a finding's id string, its status, whether it is closed, and the
# panel's unclosed blocking findings. Prepended to each program that needs it.
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
# The panel'"'"'s blocking findings that are not closed, oldest round first: what
# --verdict prints and --open-count counts.
def open_blocking($panel):
    . as $l
    | [ ($l.findings // {}) | to_entries[] | .value
        | select(type == "object" and .panel == $panel and .severity == "blocking")
        | select(closed($l.runs // {}) | not) ]
    | sort_by([(.round // 0), (.raiser.name // ""), (.summary // "" | tostring)]);
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
# The decisions of a scope whose runs the ledger does not hold as recorded,
# by seat. A decision with a run is recorded when the ledger holds that run;
# one without (a scope written by hand or by an older script) when its seat
# entry, or for the re-verifier the panel marker, is newer than the scope.
def unrecorded($s; $l; $panel):
    [ ($s.decisions // [])[] | select(.decision != "keep")
      | if (.run // null) != null then select((($l.runs // {})[.run].recorded // false) != true) | .seat
        elif .seat == "reverifier" then select(((($l.reverified // {})[$panel].rev) // -1) <= ($s.rev // -1)) | .seat
        else .seat | select((($l.seats // {})[$panel + "/" + .] // null) as $e
                            | $e == null or (($e.rev // -1) <= ($s.rev // -1)))
        end ];
'

# gate_ledger <exit>: the stored ledger in $ledger, or refuse with <exit> when
# it is absent, unreadable, or written before finding records.
gate_ledger() {
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || refuse "$1" "no $LEDGER: no $PANEL round is recorded (run panel-scope.sh --record $PANEL)"
    printf '%s' "$ledger" | jq -e 'type == "object" and ((.findings // null) | type) == "object"' >/dev/null \
        || refuse "$1" "$LEDGER is unreadable, or predates finding records: re-plan the panel as a full round"
}

# ---------------------------------------------------------------- --carried ---

if [ "$MODE" = "--carried" ]; then
    [ -z "$(git status --porcelain | head -1)" ] \
        || refuse 1 "the working tree has uncommitted changes"
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || refuse 1 "no ${PANEL}_scope.json for this round"
    printf '%s' "$scope" | jq -e --arg head "$HEAD" '
        .head == $head and (.decisions | length > 0)
        and all(.decisions[]; .decision == "keep")' >/dev/null 2>&1 \
        || refuse 1 "${PANEL}_scope.json does not keep every seat at HEAD"
    koto context exists "$SESSION" "${PANEL}_results.json" \
        || refuse 1 "every seat is kept but ${PANEL}_results.json is absent"
    gate_ledger 1
    n=$(printf '%s' "$ledger" | jq --arg panel "$PANEL" "$JQ_DEFS"'open_blocking($panel) | length') \
        || refuse 1 "could not read the findings in $LEDGER"
    [ "$n" = 0 ] || refuse 1 "$n blocking finding(s) of $PANEL are unclosed; --verdict reports them"
    exit 0
fi

# ---------------------------------------------------------------- --recorded --

# Refuses while a run this round planned is not recorded: that is a round
# whose --record was skipped, and the findings it would have answered or
# raised would be missing next round. Runs are minted per round, so a run the
# ledger holds as recorded was recorded since the scope was planned; that is
# why a first round with nothing recorded holds here too, where the old
# seat-by-seat check let a seat with no entry through. Every route this gate
# holds also needs --verdict, which holds that round anyway. No scope, or no
# ledger, passes, with nothing to compare.
#
# HEAD moving while the panel is open is --record's concern, not this gate's:
# --record refuses to stamp a round across a moved HEAD (68), and a round
# recorded before the move keeps its own commits, so the next round's fix
# diff includes the commit no run saw.
if [ "$MODE" = "--recorded" ]; then
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || exit 0
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || exit 0
    stale=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" "$JQ_DEFS"'
        unrecorded($s; $l; $panel) | join(" ")' 2>/dev/null) \
        || refuse 1 "could not read ${PANEL}_scope.json or $LEDGER"
    [ -z "$stale" ] || refuse 1 "no run recorded this round for: $stale (run panel-scope.sh --record $PANEL)"
    exit 0
fi

# ------------------------------------------------- --verdict and --open-count --

# The panel's pass, from the ledger's records, and the count of what blocks it.
# Both hold (2) on a round that isn't fully recorded: a count read off a
# half-recorded round would feed the retry budget a number no round produced.
if [ "$MODE" = "--verdict" ] || [ "$MODE" = "--open-count" ]; then
    if [ "$MODE" = "--verdict" ]; then
        # The generic rule resolves before the ledger is read, so a registry
        # problem holds the gate whether or not a finding is open.
        undecided() { refuse 2 "$*"; }
        # shellcheck source=../../../scripts/lib/rule-findings.sh
        . "$(cd "$(dirname "$0")" && pwd)/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
        rf_require panel/open-finding
    fi
    gate_ledger 2
    scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$scope" ]; then
        unrec=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" "$JQ_DEFS"'
            unrecorded($s; $l; $panel) | join(" ")' 2>/dev/null) \
            || refuse 2 "could not read ${PANEL}_scope.json against $LEDGER"
        [ -z "$unrec" ] \
            || refuse 2 "no run recorded since ${PANEL}_scope.json was planned for: $unrec (run panel-scope.sh --record $PANEL)"
    fi
    missing=$(printf '%s' "$ledger" | jq -r --arg panel "$PANEL" --arg seats "$SEATS" '
        [($seats | split(" "))[] as $s | select(((.seats // {})[$panel + "/" + $s].verdict // "") as $v
                                               | $v != "passed" and $v != "blocking") | $s] | join(" ")') \
        || refuse 2 "$LEDGER is unreadable"
    [ -z "$missing" ] || refuse 2 "no verdict on record for $missing (run panel-scope.sh --record $PANEL)"

    open=$(printf '%s' "$ledger" | jq -c --arg panel "$PANEL" "$JQ_DEFS"'open_blocking($panel)') \
        || refuse 2 "could not read the findings in $LEDGER"
    if [ "$MODE" = "--open-count" ]; then
        printf '%s' "$open" | jq 'length'
        exit 0
    fi
    [ "$(printf '%s' "$open" | jq 'length')" != 0 ] || exit 0

    # Each finding prints under its own rule when that is an active registry
    # entry now, and under panel/open-finding otherwise. A rule retired since
    # the finding was recorded falls back rather than holding the gate.
    # rf_ref and rf_summary refuse inside the command substitution, which can't
    # end this shell; `|| exit 2` carries their could-not-decide out.
    rules='{}'
    for rid in $(printf '%s' "$open" | jq -r '[.[] | .rule_id? // empty | strings] | unique | .[]'); do
        case "$rid" in *[!a-z0-9/_-]*|"") continue ;; esac
        "$REGISTRY" ref "$rid" >/dev/null 2>&1 || continue
        rf_require_any "$rid"
        r_ref=$(rf_ref "$rid") || exit 2
        r_sum=$(rf_summary "$rid") || exit 2
        rules=$(printf '%s' "$rules" | jq -c --arg id "$rid" --arg ref "$r_ref" --arg s "$r_sum" '. + {($id): {ref: $ref, summary: $s}}') \
            || refuse 2 "could not build the rule map"
    done
    g_ref=$(rf_ref panel/open-finding) || exit 2
    g_sum=$(rf_summary panel/open-finding) || exit 2
    # The message is the rule's summary, then the panel, raiser and the
    # finding's own summary, control characters replaced: the same shape
    # rf_finding in scripts/lib/rule-findings.sh builds, built here because one
    # ledger read yields every finding. rf_emit refuses a line whose rule_id,
    # rule_ref or summary prefix strays from it; replacing the control
    # characters is this jq's job, not rf_emit's.
    findings=$(printf '%s' "$open" | jq -c --arg panel "$PANEL" --argjson rules "$rules" \
        --arg gref "$g_ref" --arg gsum "$g_sum" '
        .[]
        | ((.rule_id // "") | tostring) as $rid
        | ($rules[$rid] // null) as $r
        | (if $r != null then {id: $rid, ref: $r.ref, summary: $r.summary}
           else {id: "panel/open-finding", ref: $gref, summary: $gsum} end) as $rule
        | ($panel + "/" + ((.raiser.name // "unknown") | tostring) + ": " + ((.summary // "a blocking finding") | tostring)
           + (if $rid != "" and $r == null then " (cites rule " + $rid + ", which is no longer active)" else "" end)) as $detail
        | ((.location.lines // "") | tostring | (capture("^(?<n>[1-9][0-9]*)") // null)) as $line
        | {rule_id: $rule.id, level: "error",
           message: ($rule.summary + ": " + ($detail | gsub("[\u0000-\u001f\u007f]"; " ")))}
          + (if (.location.path | type) == "string" and .location.path != "" then {path: .location.path}
               + (if $line != null then {line: ($line.n | tonumber)} else {} end)
             else {} end)
          + {rule_ref: $rule.ref}') \
        || refuse 2 "could not read the unclosed findings in $LEDGER"
    # Every finding takes panel/open-finding's stage, whatever rule it cites:
    # the gate is the panel's, and a cited rule's own stage is about the
    # script that checks it, not about a reviewer's finding.
    while IFS= read -r f; do
        [ -n "$f" ] && rf_emit "$f" panel/open-finding
    done <<EOF
$findings
EOF
    [ "$RF_BLOCKING" -gt 0 ] || exit 0
    rf_dispute_hint
    rf_deliver
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

# store_ledger <file>: store a new ledger, unless another write landed since
# this run read it (69): the compare is of revisions, which every write bumps.
# It catches overlapping honest writes; it is not a lock.
store_ledger() {
    local now
    now=$(ctx_get "$LEDGER" | jq -r 'if type == "object" then (.rev // 0) else 0 end')
    [ "${now:-0}" = "$(printf '%s' "$LEDGER_JSON" | jq -r '.rev // 0')" ] \
        || die 69 "$LEDGER changed while this write was being built (rev ${now:-?}); run it again"
    put "$LEDGER" "$1"
}

# edited_tests: the unit's edited test paths on stdout, one per line, as
# scripts/lib/test-classify.sh's test_classify_unit labels them: from
# impl_base (else the merge-base with origin's default branch, else with local
# main, the order review-packet.sh takes, so the round asks for what the packet
# listed) to HEAD, with the session's stored rules copy (else the shipped
# rules file) and, for a fix, the red's record. Exits 65 when no base resolves
# or the classifier fails: a round can't be checked for judgments it can't
# name.
edited_tests() {
    local base="" stored ref
    stored=$(ctx_get impl_base | tr -d '[:space:]')
    if [ -n "$stored" ]; then
        base=$(git rev-parse --verify -q "${stored}^{commit}") || base=""
    fi
    if [ -z "$base" ]; then
        ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
        if [ -z "$ref" ] && git rev-parse --verify -q "refs/remotes/origin/main^{commit}" >/dev/null; then
            ref=origin/main
        fi
        [ -z "$ref" ] || base=$(git merge-base HEAD "$ref" 2>>"$WORK/tc.err") || base=""
    fi
    if [ -z "$base" ] && git rev-parse --verify -q "refs/heads/main^{commit}" >/dev/null; then
        base=$(git merge-base HEAD main 2>>"$WORK/tc.err") || base=""
    fi
    [ -n "$base" ] || die 65 "no base to tell the change's edited tests by (no impl_base and no merge-base), so the round's test_edits can't be checked"
    ctx_get review_level_rules.tsv > "$WORK/tc_rules"
    [ -s "$WORK/tc_rules" ] || cp "$PLUGIN_ROOT_PS/skills/work-on/references/review-level-rules.tsv" "$WORK/tc_rules" \
        || die 65 "no rules file to tell test files by"
    awk -F '\t' '$1 == "class" && $2 == "test" && $3 != "" { f = 1 } END { exit !f }' "$WORK/tc_rules" || return 0
    ctx_get red_first.json > "$WORK/tc_red"
    test_classify_unit "$base" "$HEAD" "$WORK/tc_rules" "$WORK/tc_red" > "$WORK/tc_rows" 2>"$WORK/tc.err" \
        || die 65 "could not classify the change's test files: $(head -n 1 "$WORK/tc.err")"
    awk -F '\t' '$1 == "edited" { print $2 }' "$WORK/tc_rows"
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
    [ -z "$problems" ] || die 65 "$(head -n 3 <<<"$problems" | paste -sd ';' -)"
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
    if [ -n "$SCOPE_JSON" ] && ! printf '%s' "$SCOPE_JSON" | jq -e 'type == "object"' >/dev/null; then
        die 65 "${PANEL}_scope.json is unreadable"
    fi
    scope_head=$(printf '%s' "${SCOPE_JSON:-{\}}" | jq -r '.head // empty')
    [ -z "$scope_head" ] || [ "$scope_head" = "$HEAD" ] \
        || die 68 "HEAD moved since ${PANEL}_scope.json was planned at $scope_head; tick koto without evidence to re-plan, then run the round again"
    [ -n "$ROUND_FILE" ] || die 67 "missing round file for --record"
    [ -f "$ROUND_FILE" ] || die 65 "round file [$ROUND_FILE] not found"
    jq -e 'type == "array" and length > 0 and all(.[]; type == "object")' "$ROUND_FILE" >/dev/null \
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
                        (if (.outcome | type) != "string" or .outcome == "" then "a decider entry has no outcome" else empty end),
                        (if ($e.run // null) == null then empty
                         elif ($e.run | type) != "string" or ($e.run | test(run_re) | not) then "a decider entry has a malformed run id"
                         elif (($l.runs // {})[$e.run].recorded // false) then "run [\($e.run)] is already recorded"
                         else empty end) )
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
    [ -z "$problems" ] || die 65 "round file [$ROUND_FILE] refused: $(head -n 5 <<<"$problems" | paste -sd ';' -)"

    # Every rule id a finding names must be an active registry entry now.
    for rid in $(jq -r '[.[] | (.findings // [])[] | .rule_id? // empty] + [.[] | .decider?.rule_id? // empty] | unique | .[]' "$ROUND_FILE"); do
        "$REGISTRY" ref "$rid" >/dev/null 2>&1 || die 65 "round file [$ROUND_FILE] names rule [$rid], which is not an active registry entry"
    done

    # Every seat of the panel that ran judges every edited test as corrects or
    # weakens (rule review/test-edit-judgment). The edited tests are the shared
    # classifier's, so the round asks for the same tests the packet listed.
    edited_tests > "$WORK/edited_tests"
    problems=$(jq -r --rawfile edited "$WORK/edited_tests" --arg seats "$SEATS" '
        ($edited | split("\n") | map(select(. != ""))) as $E
        | ($seats | split(" ")) as $real
        | .[] | select((.seat? | type) == "string" and (.seat as $s | $real | index($s)) != null) | . as $e
        | if (.test_edits // []) | type != "array" then "seat [\(.seat)]: test_edits is not an array"
          else
            ( (.test_edits // [])[]
              | if type != "object" then "seat [\($e.seat)]: a test_edits entry is not an object"
                elif (.path | type) != "string" or .path == "" then "seat [\($e.seat)]: a test_edits entry has no path"
                elif (.judgment != "corrects" and .judgment != "weakens") then
                    "seat [\($e.seat)]: the judgment of [\(.path)] is not corrects or weakens"
                elif (.reason // "") != "" and ((.reason | type) != "string" or (.reason | utf8bytelength) > 1000) then
                    "seat [\($e.seat)]: the reason for [\(.path)] is not a string of at most 1000 bytes"
                else empty end ),
            ( $E[] as $p
              | select([($e.test_edits // [])[] | select(type == "object" and .path == $p)] | length == 0)
              | "seat [\($e.seat)] did not judge the edited test [\($p)] as corrects or weakens" )
          end' "$ROUND_FILE" 2>"$WORK/jq.err") \
        || die 65 "could not read the test_edits in round file [$ROUND_FILE]: $(head -n 1 "$WORK/jq.err")"
    [ -z "$problems" ] || die 65 "round file [$ROUND_FILE] refused, rule review/test-edit-judgment: $(head -n 5 <<<"$problems" | paste -sd ';' -)"

    # A decider entry is accepted only when koto's own log holds the event it
    # names, and each event backs one entry: the log is koto's to write, so a
    # round file alone can't mint a decider verdict.
    : > "$WORK/decider_events"
    if jq -e 'any(.[]; .decider? != null)' "$ROUND_FILE" >/dev/null; then
        session_dir "a decider entry needs koto's session log"
        slog="$SDIR/koto-$SESSION.state.jsonl"
        [ -r "$slog" ] || die 65 "a decider entry needs koto's session log, and [$slog] can't be read"
        jq -c '.[] | .decider? // empty' "$ROUND_FILE" | while IFS= read -r dec; do
            key=$(printf '%s' "$dec" | jq -r '"\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)"')
            if ! jq -e --argjson d "$dec" 'select(.type? == "decider_checked") | .payload
                    | select(.state == $d.state and .visit_seq == $d.visit_seq and .gate == $d.gate
                             and .rule_id == $d.rule_id and .declaration_hash == $d.declaration_hash
                             and .outcome == $d.outcome
                             and ((.input_sha256 // null) == ($d.input_sha256 // null)))' \
                    "$slog" >/dev/null 2>&1; then
                echo "MISSING $key"
            fi
            printf '%s\n' "$key"
        done > "$WORK/decider_events"
        if grep -q '^MISSING ' "$WORK/decider_events"; then
            die 65 "koto's log holds no decider_checked event for: $(grep '^MISSING ' "$WORK/decider_events" | head -n 1 | cut -c9-)"
        fi
        dup=$(sort "$WORK/decider_events" | uniq -d)
        dup=${dup%%$'\n'*}
        [ -z "$dup" ] || die 65 "decider event [$dup] backs two entries"
        used=$(printf '%s' "$LEDGER_JSON" | jq -r '(.decider_events // [])[]' | grep -Fxf "$WORK/decider_events")
        used=${used%%$'\n'*}
        [ -z "$used" ] || die 65 "decider event [$used] already backed an earlier entry"
    fi

    # The decider batch's verdicts, imported from koto's own log: every
    # decider_checked event of the panel's state that no entry used, one per
    # (state, visit, gate, criterion, declaration), a fail if the group has one.
    # Each entry, named or imported, then takes its event's mode, which decides
    # its severity below. The log is read whole, so a line jq can't parse
    # refuses the round rather than importing part of it.
    case "$PANEL" in
        qa) PANEL_STATE=qa_validation ;;
        light) PANEL_STATE=light_review ;;
        *) PANEL_STATE=$PANEL ;;
    esac
    printf '[]' > "$WORK/imported"
    printf '{}' > "$WORK/modes"
    # A log that isn't there imports nothing, but a `koto session dir` that
    # failed (koto missing, a session-store error) has read nothing, and
    # importing nothing then would look like a session that never consulted
    # the decider: the round is refused with koto's own error instead.
    session_dir "koto's log can't be read for decider verdicts"
    if [ -n "$SDIR" ] && [ -e "$SDIR/koto-$SESSION.state.jsonl" ]; then
        slog="$SDIR/koto-$SESSION.state.jsonl"
        [ -r "$slog" ] || die 65 "koto's session log [$slog] can't be read"
        { printf '%s' "$LEDGER_JSON" | jq -r '(.decider_events // [])[]'; cat "$WORK/decider_events"; } > "$WORK/skip" \
            || die 65 "could not read the ledger's decider events"
        jq -n --arg state "$PANEL_STATE" --rawfile skip "$WORK/skip" '
            def key: "\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)";
            ($skip | split("\n") | map(select(. != ""))) as $used
            | [inputs | select(type == "object" and .type? == "decider_checked") | .payload
               | select(type == "object" and .state == $state
                        and (.visit_seq | type) == "number" and (.gate | type) == "string"
                        and (.rule_id | type) == "string" and (.declaration_hash | type) == "string"
                        and (.outcome | type) == "string")]
            | group_by(key)
            | map((map(select(.outcome == "fail")) | last) // last)
            | map(select(key as $k | $used | index($k) | not)
                  | {decider: ({state, visit_seq, gate, rule_id, declaration_hash, outcome}
                               + (if .input_sha256 then {input_sha256} else {} end)
                               + (if .mode then {mode} else {} end))})' "$slog" > "$WORK/imported" \
            2>"$WORK/jq.err" || die 65 "koto's session log [$slog] can't be read: $(head -n 1 "$WORK/jq.err")"
        # A named entry's mode is its matched event's, never the round file's.
        jq -n '[inputs | select(type == "object" and .type? == "decider_checked") | .payload
                | select(type == "object" and (.mode | type) == "string")
                | {key: "\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)|\(.outcome)|\(.input_sha256 // "")",
                   value: .mode}] | from_entries' "$slog" > "$WORK/modes" \
            2>"$WORK/jq.err" || die 65 "koto's session log [$slog] can't be read: $(head -n 1 "$WORK/jq.err")"
    fi
    jq --slurpfile imp "$WORK/imported" --slurpfile modes "$WORK/modes" '
        map(if .decider? != null then
              .decider |= (del(.mode) + ((($modes[0])["\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)|\(.outcome)|\(.input_sha256 // "")"] // null)
                                         | if . == null then {} else {mode: .} end))
            else . end)
        + $imp[0]' "$ROUND_FILE" > "$WORK/round" || die 65 "could not merge the imported decider events"
    jq -r '$imp[0][] | .decider | "\(.state)|\(.visit_seq)|\(.gate)|\(.rule_id)|\(.declaration_hash)"' \
        --slurpfile imp "$WORK/imported" -n >> "$WORK/decider_events" || die 65 "could not read the imported decider events"
    for rid in $(jq -r '.[] | .decider.rule_id' "$WORK/imported" | sort -u); do
        "$REGISTRY" ref "$rid" >/dev/null || die 65 "koto's log has a decider verdict on [$rid], which is not an active registry entry"
    done
    ROUND_FILE="$WORK/round"

    # A seat that judged an edited test `weakens` raised a blocking finding on
    # it, under rule review/test-edit-weakens; it is recorded and closed like
    # any other finding of that seat.
    jq --rawfile edited "$WORK/edited_tests" --arg seats "$SEATS" '
        ($edited | split("\n") | map(select(. != ""))) as $E
        | ($seats | split(" ")) as $real
        | map(if (.seat? | type) == "string" and (.seat as $s | $real | index($s)) != null then
                .findings = ((.findings // [])
                    + [ (.test_edits // [])[] | select(.judgment == "weakens" and (.path as $p | $E | index($p)) != null)
                        | {severity: "blocking", path: .path, rule_id: "review/test-edit-weakens",
                           summary: ("the edit to " + .path + " weakens the test"
                                     + (if (.reason // "") != "" then ": " + (.reason | .[0:800]) else "" end))} ])
              else . end)' "$ROUND_FILE" > "$WORK/round.judged" || die 65 "could not add the test-edit findings"
    mv "$WORK/round.judged" "$WORK/round"

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
    [ -z "$problems" ] || die 65 "round file [$ROUND_FILE] refused: $(head -n 3 <<<"$problems" | paste -sd ';' -)"

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
                # Only an event koto marked shadow is advisory: a missing or
                # unknown mode blocks, as every decider fail did before modes.
                | (if $d.mode == "shadow" then "advisory" else "blocking" end) as $sev
                | if $d.outcome == "fail" then
                    raise($idr.id; $idr.canon; $raiser; $run; {severity: $sev, summary: $d.rule_id, rule_id: $d.rule_id})
                  elif $d.outcome == "pass" then
                    if (.findings[$idr.id] // null) == null then .
                    else .findings[$idr.id].records += [record("reverified"; $raiser + {run: $run}; "")] end
                  elif $sev == "advisory" then .
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
                        test_edits: [($e.test_edits // [])[] | {path, judgment}],
                        cited: ($old_cited + (($e.cited // []) | norm) | unique),
                        finding_locations: ($old_locs
                            + ([($e.findings // [])[] | select(.path) | {path, lines}] | norm) | unique)})
                  end
              end)
        # Every seat summary of the panel follows from the findings: a seat is
        # blocking exactly while it raised an unclosed blocking finding, and its
        # findings are the unclosed blocking ones it raised, in the shape
        # review-packet.sh expects of seat entries.
        | . as $L
        | reduce ($seats | split(" "))[] as $s (.;
            ("\($panel)/\($s)") as $k
            | if (.seats[$k] // null) == null then . else
                [ $L.findings[] | select(.panel == $panel and .raiser.kind == "reviewer" and .raiser.name == $s)
                  | select(.severity == "blocking" and (closed($L.runs) | not)) ] as $open
                | .seats[$k].findings = [ $open[] | {id, severity, summary}
                    + (if .location.path then {path: .location.path} else {} end)
                    + (if .location.lines then {lines: .location.lines} else {} end) ]
                | .seats[$k].verdict = (if any($open[]; .severity == "blocking") then "blocking" else "passed" end)
              end)
        # The round history counts the runs it recorded, so `spawned` is the
        # reviewer runs the round made, whatever its plan said.
        | ([(.history // []) | to_entries[] | select(.value.panel == $panel)] | last) as $h
        | if $h != null and $h.value.head == $head then
            .history[$h.key].runs = (((.history[$h.key].runs // []) + [$E[] | select(.seat? != null) | .run]) | unique)
            | .history[$h.key].spawned = (.history[$h.key].runs | length)
          else . end' > "$WORK/ledger" || die 65 "could not merge [$ROUND_FILE] into the ledger"
    store_ledger "$WORK/ledger"
    exit 0
fi


# ---------------------------------------------------------------- --plan ------

IMPL_BASE=$(ctx_get impl_base | tr -d '[:space:]')
US=$(printf '\037')

# is_commit <sha>: a full commit id that names a commit here. Ledger values are
# checked before they reach git as arguments.
is_commit() {
    case "$1" in *[!0-9a-f]*|"") return 1 ;; esac
    [ "${#1}" -eq 40 ] && git rev-parse --verify -q "$1^{commit}" >/dev/null
}

# pick_commit newest|oldest: of the commits on stdin (one per line, every
# one a commit), the newest or the oldest by ancestry. Two commits not ordered
# by ancestry (a merge brought them in on different sides) resolve to the one
# with fewer ancestors either way, which widens a diff rather than narrowing
# it. Prints nothing for an empty list.
pick_commit() {
    local want="$1" best="" c bc cc
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        if [ -z "$best" ]; then best=$c; continue; fi
        [ "$c" = "$best" ] && continue
        if git merge-base --is-ancestor "$c" "$best"; then
            [ "$want" = oldest ] && best=$c
        elif git merge-base --is-ancestor "$best" "$c"; then
            [ "$want" = newest ] && best=$c
        else
            bc=$(git rev-list --count "$best" || echo 0)
            cc=$(git rev-list --count "$c" || echo 0)
            [ "$cc" -lt "$bc" ] && best=$c
        fi
    done
    [ -z "$best" ] || printf '%s\n' "$best"
}

# changed_lines <from>: added plus deleted lines from <from> to HEAD, a binary
# file counting 1 per side. Fails when the diff does.
changed_lines() {
    git diff --no-renames --numstat "$1" HEAD > "$WORK/numstat" || return 1
    awk '{ a = ($1 == "-") ? 1 : $1; d = ($2 == "-") ? 1 : $2; n += a + d } END { print n + 0 }' "$WORK/numstat"
}

# loc_touched <base> <kind> <path> <lines> <at>: whether the fix diff from
# <base> to HEAD touches a finding's location. Prints touched, untouched,
# none (the location names no path) or unresolvable (a commit is gone or a
# diff failed).
loc_touched() {
    local base="$1" kind="$2" path="$3" lines="$4" at="$5" lo hi rc
    if [ "$kind" = none ] || [ -z "$path" ]; then echo none; return; fi
    is_commit "$base" || { echo unresolvable; return; }
    git --literal-pathspecs diff --no-renames --name-only "$base" HEAD -- "$path" > "$WORK/tp" \
        || { echo unresolvable; return; }
    [ -s "$WORK/tp" ] || { echo untouched; return; }
    [ "$kind" = lines ] || { echo touched; return; }
    # The range is in the numbering of the commit the location was recorded
    # at. When the file changed between that commit and the base, the numbers
    # no longer name the same code, and the location is judged as the file.
    if [ "$at" != "$base" ]; then
        is_commit "$at" || { echo unresolvable; return; }
        git --literal-pathspecs diff --no-renames --quiet "$at" "$base" -- "$path"
        rc=$?
        [ "$rc" -eq 0 ] || { [ "$rc" -eq 1 ] && echo touched || echo unresolvable; return; }
    fi
    lo=${lines%%-*}
    hi=${lines#*-}
    case "$lo$hi" in *[!0-9]*|"") echo touched; return ;; esac
    # Old-side range of each fix hunk in this file: `@@ -a,b +c,d @@`. A
    # missing b means 1; b == 0 is an insertion between lines a and a+1.
    if git --literal-pathspecs diff --no-renames -U0 "$base" HEAD -- "$path" | awk -v lo="$lo" -v hi="$hi" '
        /^@@ / {
            n = split(substr($2, 2), o, ",")
            a = o[1] + 0
            b = (n > 1) ? o[2] + 0 : 1
            if (b == 0) { s = a; e = a + 1 } else { s = a; e = a + b - 1 }
            if (s <= hi + 0 && e >= lo + 0) { found = 1; exit }
        }
        END { exit found ? 0 : 1 }'; then
        echo touched
    else
        echo untouched
    fi
}

DIRTY=""
[ -n "$(git status --porcelain | head -1)" ] && DIRTY=1
NOCOMMITS=""
if [ -z "$IMPL_BASE" ] || [ "$(git rev-list --count "$IMPL_BASE..HEAD" || echo 0)" = 0 ]; then
    NOCOMMITS=1
fi

# A round already planned at this HEAD stands. koto runs --plan on every tick
# that carries no evidence, and the agent ticks with none once the round is
# recorded, so the <panel>_verdict gate can route it. A fresh plan there would
# re-verify findings with no fix behind them. The scope stands while HEAD, a
# clean tree and the criteria are what it was planned against, every run it
# minted is recorded, and no `fixed` record was written since; anything else
# plans a new round.
if [ -z "$DIRTY" ]; then
    prev_scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$prev_scope" ] && [ "$(jq -n --argjson s "$prev_scope" --argjson l "$LEDGER_JSON" \
            --arg panel "$PANEL" --arg head "$HEAD" --arg ac "$AC_SHA" "$JQ_DEFS"'
            $s.head == $head and ($s.ac_sha // "") == $ac
            and all(($s.decisions // [])[]; .decision == "keep" or (.run // null) != null)
            and (unrecorded($s; $l; $panel) | length) == 0
            and ([($l.findings // {})[] | select(.panel == $panel) | (.records // [])[]
                  | select(.kind == "fixed" and ((.rev // 0) > ($s.rev // -1)))] | length) == 0' 2>/dev/null)" = true ]; then
        echo "panel-scope: the $PANEL round planned at $(printf '%.12s' "$HEAD") stands: every run it planned is recorded and nothing was marked fixed since" >&2
        printf '%s\n' "$prev_scope"
        exit 0
    fi
fi

REV=$(printf '%s' "$LEDGER_JSON" | jq '.rev // 0')
# The round this plan is: the previous one replanned when nothing was written
# to the ledger since it, the next one otherwise.
ROUND=$(printf '%s' "$LEDGER_JSON" | jq --arg p "$PANEL" --arg head "$HEAD" '
    [(.history // [])[] | select(.panel == $p)] as $h
    | ($h | last) as $prev
    | if $prev != null and $prev.head == $head and $prev.rev == (.rev // 0) then $prev.round
      else ($h | length) + 1 end') || die 65 "could not read the ledger history"

# The commits the ledger recorded: seats' judged_at, the re-verifier markers'
# heads, and the commits of finding records not written by the agent (its
# `fixed` records are stamped at HEAD after the fix, and counting them would
# empty the fix diff). Panel-scoped for the full-round checks, every panel's
# for the fix-diff review.
recorded_commits() {
    printf '%s' "$LEDGER_JSON" | jq -r --arg p "$1" '
        def mine($k): $p == "" or $k == $p;
        [ ((.seats // {}) | to_entries[] | select(mine(.key | split("/")[0])) | .value.judged_at),
          ((.reverified // {}) | to_entries[] | select(mine(.key)) | .value.head),
          ((.findings // {})[] | select(type == "object" and mine(.panel // "")) | (.records // [])[]
           | select((.writer.kind // "") != "agent") | .commit) ]
        | map(select(type == "string" and test("^[0-9a-f]{40}$"))) | unique | .[]'
}

FULL_REASON=""
for seat in $SEATS; do
    has=$(printf '%s' "$LEDGER_JSON" | jq -r --arg k "$PANEL/$seat" '(.seats // {})[$k].verdict // empty')
    if [ -z "$has" ]; then
        FULL_REASON="no verdict on record for $seat: the panel's first round"
        break
    fi
done
if [ -z "$FULL_REASON" ] && [ "$(printf '%s' "$LEDGER_JSON" | jq '(.findings // null) | type == "object"')" != true ]; then
    FULL_REASON="the ledger predates finding records"
fi
if [ -z "$FULL_REASON" ]; then
    for seat in $SEATS; do
        ac=$(printf '%s' "$LEDGER_JSON" | jq -r --arg k "$PANEL/$seat" '(.seats // {})[$k].ac_sha // ""')
        if [ "$ac" != "$AC_SHA" ]; then
            FULL_REASON="the acceptance criteria or the plan changed since $seat judged"
            break
        fi
    done
fi
if [ -z "$FULL_REASON" ] && [ -n "$DIRTY" ]; then
    FULL_REASON="the working tree has uncommitted changes, so the fix diff cannot be judged: commit the fix and tick again"
fi
if [ -z "$FULL_REASON" ] && [ -n "$NOCOMMITS" ]; then
    FULL_REASON="no commits since impl_base, or impl_base is unrecorded (has_commits fails either way); nothing for a carried verdict to rest on"
fi
if [ -z "$FULL_REASON" ]; then
    recorded_commits "$PANEL" > "$WORK/pcommits"
    while IFS= read -r c; do
        if ! is_commit "$c" || ! git merge-base --is-ancestor "$c" HEAD; then
            FULL_REASON="a commit the panel recorded ($(printf '%.12s' "$c")) is no longer an ancestor of HEAD"
            break
        fi
    done < "$WORK/pcommits"
fi
if [ -z "$FULL_REASON" ]; then
    PANEL_BASE=$(pick_commit newest < "$WORK/pcommits")
    if [ -z "$PANEL_BASE" ]; then
        FULL_REASON="the panel has recorded no commit to measure a fix from"
    elif [ "$(git rev-list --count "$IMPL_BASE..$PANEL_BASE" || echo 0)" = 0 ]; then
        FULL_REASON="the panel last judged no commit since impl_base, so its seats have not reviewed the change"
    elif ! changed=$(changed_lines "$PANEL_BASE"); then
        FULL_REASON="git diff from $(printf '%.12s' "$PANEL_BASE") failed"
    elif [ "$changed" -gt "$THRESHOLD_LINES" ]; then
        FULL_REASON="the fix diff since $(printf '%.12s' "$PANEL_BASE") changes $changed lines, over the $THRESHOLD_LINES-line threshold"
    fi
fi

# The fix-diff review's base: the newest commit any panel recorded that is an
# ancestor of HEAD. Planned only outside a full round. It is worked out before
# the due loop below because a failure here (no base at all, or a diff that
# fails) makes the round full, and a full round reads no due table.
FIXBASE=""
FIX_REVIEW=0
if [ -z "$FULL_REASON" ]; then
    recorded_commits "" | while IFS= read -r c; do
        is_commit "$c" && git merge-base --is-ancestor "$c" HEAD && printf '%s\n' "$c"
    done > "$WORK/acommits"
    FIXBASE=$(pick_commit newest < "$WORK/acommits")
    if [ -z "$FIXBASE" ]; then
        FULL_REASON="no commit the ledger recorded is an ancestor of HEAD"
    else
        git diff --no-renames --quiet "$FIXBASE" HEAD
        case $? in
            0) ;;
            1) FIX_REVIEW=1 ;;
            *) FULL_REASON="git diff from $(printf '%.12s' "$FIXBASE") failed" ;;
        esac
    fi
fi

# Which of the panel's blocking findings are due, one line of JSON each, with
# the base each was last judged at. A full round reads only the bases, for
# the re-verifier's diff.
printf '%s' "$LEDGER_JSON" | jq -r --arg p "$PANEL" "$JQ_DEFS"'
    . as $l | ($l.runs // {}) as $runs
    | ($l.findings // {})[]
    | select(type == "object" and .panel == $p and .severity == "blocking")
    | (.records // []) as $r
    | ([$r | to_entries[] | select((.value.writer.kind // "") != "agent")] | last) as $j
    | [ (.id | tostring),
        (if closed($runs) then "closed"
         else (status | if . == "reverified" or . == "dismissed" then "open" else . end) end),
        (($j.value.commit // .location.at // "") | tostring),
        (if $j == null then "yes" elif any($r[($j.key + 1):][]; .kind == "fixed") then "yes" else "no" end),
        ((.location.kind // "none") | tostring), ((.location.path // "") | tostring),
        ((.location.lines // "") | tostring), ((.location.at // "") | tostring) ]
    | join("\u001f")' > "$WORK/findings" || die 65 "could not read the findings in the ledger"
: > "$WORK/due"
while IFS="$US" read -r id st base fixed_after kind path lines at; do
    [ -n "$id" ] || continue
    if [ -n "$FULL_REASON" ]; then
        due=false
        why="full round"
    elif [ "$base" = "$HEAD" ] && [ "$fixed_after" = no ]; then
        due=false
        why="judged at HEAD"
    else
        case "$st" in
            fixed) due=true; why="marked fixed since it was last judged" ;;
            unverified) due=true; why="a decider could not verify it" ;;
            *)
                t=$(loc_touched "$base" "$kind" "$path" "$lines" "$at")
                case "$st:$t" in
                    open:touched) due=true; why="open, and the fix touched its location" ;;
                    open:untouched) due=false; why="open, and the fix did not touch its location" ;;
                    open:*) due=true; why="open, with no location the fix diff can be checked against ($t)" ;;
                    closed:touched) due=true; why="closed, and the fix touched its location: a regression check" ;;
                    *) due=false; why="closed, and the fix did not touch its location ($t)" ;;
                esac
                ;;
        esac
    fi
    jq -nc --arg id "$id" --arg st "$st" --arg base "$base" --argjson due "$due" --arg why "$why" \
        '{id: $id, status: $st, base: $base, due: $due, why: $why}' >> "$WORK/due"
done < "$WORK/findings"

# The re-verifier's diff starts at the oldest base among what it re-verifies:
# one packet diff, wider than any one finding needs rather than narrower.
oldest_base() {
    jq -r "$1"' | .base' "$WORK/due" | while IFS= read -r c; do
        is_commit "$c" && git merge-base --is-ancestor "$c" HEAD && printf '%s\n' "$c"
    done | pick_commit oldest
}
DUE_FROM=$(oldest_base 'select(.due)')
[ -n "$DUE_FROM" ] || DUE_FROM="$FIXBASE"
OPEN_FROM=$(oldest_base 'select(.status != "closed")')
[ -n "$OPEN_FROM" ] || OPEN_FROM="$IMPL_BASE"

# scripts/review-packet.sh recheck reads a recheck decision's `findings`,
# `fix_diff_from`, `fix_review` and `review_from` to build the re-verifier's
# packet. fix_diff_from is an ancestor of HEAD whenever oldest_base found one;
# otherwise it is the fix-diff base or impl_base, and the packet falls back to
# its own base, saying so, for any value that can't bound a diff. Renaming a
# field changes what that packet holds; panel-scope_test.sh drives the two
# scripts together.
jq -n --argjson l "$LEDGER_JSON" --arg panel "$PANEL" --arg seats "$SEATS" \
    --argjson round "$ROUND" --argjson rev "$REV" --arg head "$HEAD" --arg ac "$AC_SHA" \
    --arg full "$FULL_REASON" --slurpfile due "$WORK/due" --arg fixreview "$FIX_REVIEW" \
    --arg fixbase "$FIXBASE" --arg duefrom "$DUE_FROM" --arg openfrom "$OPEN_FROM" "$JQ_DEFS"'
    def mint($seat): ("\($panel)-r\($round)-\($seat)") as $r
        | if ((($l.runs // {})[$r].recorded) // false) then "\($r)-v\($rev)" else $r end;
    def fshape: {id, severity, summary, raiser: (.raiser.name // ""), status: status}
        + (if (.location.path // "") != "" then {path: .location.path} else {} end)
        + (if (.location.lines // "") != "" then {lines: .location.lines} else {} end)
        + (if (.rule_id // "") != "" then {rule_id} else {} end);
    ($seats | split(" ")) as $real
    | ($l | open_blocking($panel)) as $open
    | (if $full != "" then
        [ $real[] as $s
          | {seat: $s, decision: "full", run: mint($s), reason: $full,
             findings: [ $open[] | select(.raiser.kind == "reviewer" and .raiser.name == $s) | fshape ]} ]
        + ( [ $open[] | (.raiser.name // "") as $n
              | select((.raiser.kind == "reviewer" and ($real | index($n)) != null) | not) ] as $orph
            | if ($orph | length) > 0 then
                [{seat: "reverifier", decision: "recheck", run: mint("reverifier"),
                  reason: "\($orph | length) unclosed blocking finding(s) no seat of the panel raised",
                  findings: [ $orph[] | fshape ], fix_diff_from: $openfrom, fix_review: false}]
              else [] end )
      else
        [ $due[] | select(.due) ] as $d
        | [ $real[] as $s
            | ((($l.seats // {})[$panel + "/" + $s]) // {}) as $e
            | ([ $open[] | select(.raiser.kind == "reviewer" and .raiser.name == $s) ] | length) as $n
            | {seat: $s, decision: "keep", judged_at: $e.judged_at,
               reason: (if $n > 0 then "kept: its \($n) unclosed blocking finding(s) are re-verified by id when due, not by re-running the seat"
                        else "passed at \(($e.judged_at // "")[0:12]); outside a full round a passed seat is not re-run, and the fix-diff review sees new defects" end)} ]
          + (if ($d | length) > 0 or $fixreview == "1" then
               [ {seat: "reverifier", decision: "recheck", run: mint("reverifier"),
                  reason: ("re-verify \($d | length) due finding(s) by id"
                           + (if $fixreview == "1" then ", and review the fix diff since \($fixbase[0:12]) against every panel'"'"'s blocking criteria" else "" end)),
                  findings: [ $d[] | . as $x | ($l.findings[$x.id] | fshape) + {due: $x.why} ],
                  fix_diff_from: $duefrom, fix_review: ($fixreview == "1")}
                 + (if $fixreview == "1" then {review_from: $fixbase} else {} end) ]
             else [] end)
      end) as $decisions
    | {panel: $panel, head: $head, rev: $rev, ac_sha: $ac, round: $round,
       full: ($full != ""), reason: (if $full != "" then $full else "a retry: nothing re-runs but what is due" end),
       decisions: $decisions}' > "$WORK/scope" || die 65 "could not build ${PANEL}_scope.json"

# The history entry for this round. Replaced, not appended, when the previous
# entry for this panel is at the same HEAD and nothing was recorded since.
# `spawned` is the runs the round planned, and each run's decision lists the
# findings it carries, by id; --record rewrites `spawned` to the runs it
# recorded.
printf '%s' "$LEDGER_JSON" | jq --slurpfile scope "$WORK/scope" '
    ($scope[0]) as $s
    | .history = (.history // [])
    | (.rev // 0) as $rev
    | ([.history | to_entries[] | select(.value.panel == $s.panel)] | last) as $prev
    | {panel: $s.panel, head: $s.head, rev: $rev, round: $s.round,
       spawned: ([$s.decisions[] | select(.decision != "keep")] | length),
       decisions: [$s.decisions[] | {seat, decision, reason}
                   + (if .decision != "keep" then {findings: [(.findings // [])[] | .id]} else {} end)]} as $entry
    | if $prev != null and $prev.value.head == $s.head and $prev.value.rev == $rev
      then .history[$prev.key] = $entry
      else .history += [$entry]
      end' > "$WORK/ledger" || die 65 "could not update the ledger history"

# Order matters for the gate: the carried results go in before the scope, so a
# scope that keeps every seat is never visible without them. A panel with an
# unclosed blocking finding is not carried: --verdict blocks it.
if jq -e 'all(.decisions[]; .decision == "keep")' "$WORK/scope" >/dev/null \
    && [ "$(printf '%s' "$LEDGER_JSON" | jq --arg panel "$PANEL" "$JQ_DEFS"'open_blocking($panel) | length')" = 0 ]; then
    jq '{passed: true, carried: true, head: .head,
         seats: [.decisions[] | {seat, decision, reason}]}' "$WORK/scope" > "$WORK/results"
    put "${PANEL}_results.json" "$WORK/results"
fi
put "$LEDGER" "$WORK/ledger"
put "${PANEL}_scope.json" "$WORK/scope"
cat "$WORK/scope"
exit 0
