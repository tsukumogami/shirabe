# state-schema.jq -- the coordinator state's checks, over JSON.
#
# Every rule a value in the coordinator's state must keep: the section and
# column definitions, each column's grammar, the worker and pull request link
# shapes, the Holds, stored set and Decisions rules, and the private-repository,
# home-directory path and token checks, which scan_strings runs over every
# string in the state. Each function takes the state, a section or a cell as
# JSON and refuses with a jq error() whose message starts with "refused: ".
# A Standing row's Source is checked here too (source_problem), and the class,
# status and pointer state-stored-set.sh --rules prints for a row are worked
# out here from it at read (rule_class, rule_status, rule_view); no column
# stores them.
#
# state-write-core.sh runs normalize_state over the next state before it
# writes anything, and state-read.sh over every state it hands a reader, so
# a reader and a writer see one normal form. A script reaches these functions
# with `jq -L <scripts dir> 'include "state-schema"; ...'`.
#
# $private, wherever a function takes it, is the list of repositories the host
# can't show as public (state-write-core.sh reads each named repository's
# visibility); a value naming one is refused. A private host passes [].

# The four sections every record has, in order, with their columns.
def sections: [
  {key: "holdings", title: "Holdings", cols: [
    ["unit", "Unit"], ["entry_point", "Entry point"], ["mode", "Mode"],
    ["phase", "Phase"], ["dispatch_status", "Dispatch status"],
    ["return_path", "Return path"], ["worker", "Worker"], ["repo", "Repo"],
    ["branch", "Branch"], ["verified_head", "Verified head"],
    ["dispatched", "Dispatched"], ["pull_request", "Pull request"]]},
  {key: "deferrals", title: "Deferrals", cols: [
    ["deferral", "Deferral"], ["reason", "Reason"], ["raised", "Raised"],
    ["disposition", "Disposition"]]},
  {key: "side_effects", title: "Side effects in flight", cols: [
    ["action", "Action"], ["target", "Target"], ["verified_head", "Verified head"],
    ["attempted", "Attempted"], ["how_to_confirm", "How to confirm"]]},
  {key: "reversals", title: "Reversals", cols: [
    ["date", "Date"], ["reversed", "Reversed"], ["now", "Now"],
    ["reason", "Reason"], ["from", "From"]]}
];

def refuse($m): error("refused: " + $m);

def re_time_min: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$";
def re_date: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$";
def re_repo: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$";
def re_name: "^[A-Za-z0-9._-]+$";
# A dispatch topic, the Worker cell's shape: state-common.sh's RE_TOPIC, the
# grammar every bash script holds a topic to.
def re_topic: "^[A-Za-z0-9][A-Za-z0-9._-]*$";

# pr_link_parts: a Pull request cell `[#a](https://github.com/o/r/pull/b)` as
# {a, r, b}, or nothing for any other value. The one jq parser of the cell
# (state-common.sh lib_pr_link is the bash one); a script reaches it with
# `jq -L <scripts dir> 'include "state-schema"; ...'`.
def pr_link_parts:
  strings | capture("^\\[#(?<a>[0-9]+)\\]\\(https://github\\.com/(?<r>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(?<b>[0-9]+)\\)$");
# pr_link: the cell as {repo, number} when its two numbers agree, else nothing.
def pr_link: pr_link_parts | select(.a == .b) | {repo: .r, number: .a};

# A Side effects row's Action is free text (merge, close, teardown,
# roadmap-status, ...), except the milestone roadmap edits
# roadmap-status.sh --verdict and --reopen write: an Action starting
# `milestone-` is one of these, so a misspelt one never reads as a pending
# edit nobody confirms.
def milestone_actions: ["milestone-done", "milestone-verdict", "milestone-reopen"];

# Columns a person may leave empty; every other column must hold a value.
def optional_cols: ["mode", "branch", "verified_head", "pull_request", "disposition"];

# Column names that would record what GitHub already knows.
def recomputable_names:
  ["status", "state", "ci", "checks", "checkstatus", "merge", "mergestate",
   "mergeable", "review", "reviewdecision"];

# check_worker: a Worker cell, and a Run `coordinator`, `told` or `pending`
# value (a messaging address). re_topic takes letters, digits, `.`, `_` and `-`, so a
# session name such as niwa's `plugin_api-worker` passes; an id, a path, a
# job id, an instance name and a `session_` value never do.
def check_worker:
  if . == "" then refuse("worker: empty")
  elif test("/") then refuse("worker: contains '/', the shape of a path")
  elif test("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    or test("[0-9A-Fa-f]{32}") then refuse("worker: the shape of an instance or session id")
  elif test("^session_"; "i") then refuse("worker: the shape of a session id")
  elif test("\\+") then refuse("worker: the shape of an instance name")
  elif test("^[0-9]+$") then refuse("worker: the shape of a job id")
  elif (test(re_topic) | not) then refuse("worker: not a dispatch topic")
  else . end;

# names_repo($r): does this cell name repository $r (case-insensitive), as a
# whole owner/repo token rather than a substring of a longer name?
def names_repo($r):
  ascii_downcase as $v | ($r | ascii_downcase | gsub("\\."; "\\.")) as $l
  | $v | test("(^|[^A-Za-z0-9_.-])" + $l + "(\\.git)?\\.*($|[^A-Za-z0-9_.-])");

# Free text a person reads on a public host: a Decisions text column, or a
# record entry (state-entry.sh). text_named_repos lists the repositories the
# text names unambiguously, a github.com/<owner>/<repo> link or
# <owner>/<repo>#<n>, since in prose "and/or" or "CI/CD" is not a repository;
# both callers (state-write-core.sh for the Decisions columns,
# state-entry.sh for an entry) read each one's visibility and pass the ones
# that aren't public back as $private. text_problem($private) is null, or what
# makes the text unfit: a repository on the $private list, a home-directory
# path or a token-shaped string. check_dcell, the stored set's text cells,
# scan_strings and state-entry.sh use it.
def text_named_repos:
  def clean: sub("\\.git$"; "") | sub("\\.+$"; "");
  [ (scan("github\\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)") | .[0] | clean),
    (gsub("[A-Za-z][A-Za-z0-9+.-]*://[^\\s)\\]>]*"; " ")
     | scan("(?:^|[\\s(\\[<,;:])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#[0-9]") | .[0] | clean) ]
  | map(select(. != "")) | unique;
def text_problem($private):
  . as $v
  | ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
  | if $hit != null then "names \($hit), a repository that isn't public"
    elif ($v | test("(^|[\\s(\"'`])(/home/|/Users/)[^/[:space:]]")) then "a home-directory path"
    elif ($v | test("(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})")) then "a token-shaped string"
    else null end;

def check_cell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("\($key): a control character")
    elif ($v == "") and (any(optional_cols[]; . == $key) | not) then refuse("\($key): empty")
    elif $v == "" then $v
    elif $key == "worker" then check_worker
    elif $key == "action" and startswith("milestone-") then
      (if any(milestone_actions[]; . == $v) then . else refuse("action: \($v) is not one of the milestone roadmap edits, \(milestone_actions | join(" or "))") end)
    elif $key == "phase" then (if test("^(scoping|scoping-ahead|executing|held)$") then . else refuse("phase: not scoping, scoping-ahead, executing or held") end)
    elif $key == "dispatch_status" then (if test("^(dispatching|dispatched|dispatch-failed|stranded)$") then . else refuse("dispatch_status: not dispatching, dispatched, dispatch-failed or stranded") end)
    elif $key == "return_path" then (if test("^(message|leg [a-z0-9_][a-z0-9_-]{0,63}:[a-z0-9_-]+)$") then . else refuse("return_path: not `message` or `leg <request-id>:<leg>` (the word leg, a space, then the request and leg)") end)
    elif $key == "repo" then (if test(re_repo) then . else refuse("repo: not owner/repo") end)
    elif $key == "branch" then (if test("^[A-Za-z0-9._/-]+$") then . else refuse("branch: not a branch name") end)
    elif $key == "verified_head" then (if test("^[0-9a-f]{40}$") then . else refuse("verified_head: not a full sha") end)
    elif $key == "dispatched" then (if test(re_date) then . else refuse("dispatched: not YYYY-MM-DD") end)
    elif ($key == "raised" or $key == "attempted" or $key == "date") then (if test(re_time_min) then . else refuse("\($key): not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "pull_request" then (if ([pr_link_parts] | length) > 0 then . else refuse("pull_request: not [#n](https://github.com/owner/repo/pull/n), or empty for none yet") end)
    elif $key == "disposition" then (if test("^(filed #[0-9]+|closed: [\\s\\S]+|carried [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z( until [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)?: [\\s\\S]+)$") then . else refuse("disposition: not filed #<n>, closed: <reason> or carried <YYYY-MM-DDTHH:MMZ> [until <YYYY-MM-DDTHH:MMZ>]: <reason>") end)
    else . end
  | if ($v != "") and (($key == "repo") or ($key == "pull_request") or ($key == "target")) then
      ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
      | if $hit != null then refuse("\($key): names \($hit), a repository that isn't public") else . end
    else . end;

def check_row($sec; $private):
  . as $row
  | if type != "object" then refuse("\($sec.key): a row that isn't an object") else . end
  | ($sec.cols | map(.[0])) as $keys
  | ([keys[] | . as $k | select(any($keys[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then
      ($extra[0] | ascii_downcase | gsub("[-_ ]"; "")) as $n
      | if any(recomputable_names[]; . == $n)
        then refuse("\($sec.key).\($extra[0]): status, CI and merge-state columns are read from GitHub, never recorded")
        else refuse("\($sec.key).\($extra[0]): not a column of this section") end
    else . end
  | reduce $sec.cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_cell($c[0]; $private)));

def holds_cols: [
  ["hold", "Hold"], ["on", "On"], ["until", "Until"], ["set_by", "Set by"],
  ["set", "Set"], ["lifted", "Lifted"]];
def re_pr_ref: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$";
def re_tag: "^[A-Za-z0-9][A-Za-z0-9._+-]*$";

def check_hcell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("holds.\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("holds.\($key): a control character")
    elif ($v | test("[\r\n]")) then refuse("holds.\($key): a line break")
    elif $v == "" and $key != "lifted" then refuse("holds.\($key): empty")
    elif $v == "" then $v
    elif $key == "hold" then (if test(re_name) then . else refuse("holds.hold: not a short name") end)
    elif $key == "on" then (if test(re_pr_ref) then . else refuse("holds.on: not owner/repo#n") end)
    elif $key == "until" then
      (if . == "lifted" then .
       elif (split(" ") | length == 2 and .[0] == "merged" and (.[1] | test(re_pr_ref))) then .
       elif (split(" ") | length == 3 and .[0] == "tag" and (.[1] | test(re_repo)) and (.[2] | test(re_tag))) then .
       else refuse("holds.until: not `merged owner/repo#n`, `tag owner/repo <tag>` or `lifted`") end)
    elif $key == "set" then (if test(re_time_min) then . else refuse("holds.set: not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "lifted" then (if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z by .+$") then . else refuse("holds.lifted: not `<YYYY-MM-DDTHH:MMZ> by <who>`") end)
    else . end
  | if ($v != "") and ($key == "on" or $key == "until") then
      ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
      | if $hit != null then refuse("holds.\($key): names \($hit), a repository that isn't public") else . end
    else . end;

def check_holds($h; $private):
  if $h == null then null
  elif ($h | type) != "array" then refuse("holds: not a list")
  else
    ($h | map(. as $row
      | if type != "object" then refuse("holds: a row that isn't an object") else . end
      | ([keys[] | . as $k | select(any(holds_cols[]; .[0] == $k) | not)]) as $extra
      | if ($extra | length) > 0 then refuse("holds.\($extra[0]): not a column of this section") else . end
      | reduce holds_cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_hcell($c[0]; $private)))
      | if .lifted != "" and .until != "lifted" then refuse("holds: \(.hold): only a `lifted` hold is lifted by hand") else . end)) as $rows
    | if ($rows | map(.hold) | unique | length) != ($rows | length) then refuse("holds: a hold name is used twice") else $rows end
  end;

# ---- the stored set: Run, Standing and Work ---------------------------------
#
# What a replacement coordinator needs to continue from the record alone
# (docs/designs/archive/DESIGN-coordinate-record-container.md, Decision 3). Each sits
# after Holds and before Decisions, in this order, and a state holds it only
# once it has a row (normalize_state leaves an empty one out). Only
# state-stored-set.sh changes them.
#
# Run, one row per key from a closed set; `told` and `pending` repeat, and
# `rules` and `briefs` once per label:
#   Key      arguments | cap | coordinator | told | pending | store | rules |
#            briefs | friction | reports-to
#   Value    arguments: the run's arguments as given; cap: a number;
#            coordinator: the address messages to the coordinator reach;
#            told: a party that has been sent that address; pending: a worker
#            that can't be sent it yet (its session is gone while its instance
#            still exists), never one that is also told. The last three are
#            messaging addresses (check_worker): a dispatch topic or a session
#            name, which may hold `_`, never an id or a path.
#            store: session only, the legacy row (see run_keys below). The
#            last four are the crash set (see run_keys below).
#   Set by   who set it, in words
#   Set      when, YYYY-MM-DDTHH:MMZ
# Standing, the events only a person owns that still bind the run, and the
# rules that bind the coordinator until they are ended:
#   Standing s<n>, unique
#   Kind     pause | go-ahead | approval | answer | assignment | rule. A rule
#            row holds nothing: no reader of pauses, go-aheads or assignments
#            reads it, whatever its What says
#   On       a pause's or go-ahead's scope: `all` (a pause only: the whole
#            coordinator) or one unit as pick lists it (`Feature 2`, `ED1`,
#            `#12`, `owner/repo#12`); required on a pause, optional on a
#            go-ahead; on an assignment, the unit a person assigned outside
#            the scope, an issue or `release owner/repo <tag>`, required;
#            blank on the other kinds
#   Until    a pause's resume condition: `lifted` (until a person ends the
#            row), `time <YYYY-MM-DDTHH:MMZ>` (UTC), `merged owner/repo#n` or
#            `tag owner/repo <tag>`; required on a pause, blank otherwise
#            (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1)
#   What     what it says, one line
#   Owner    who decided it; blank on a rule row, whose Source says who
#   Relayed by  who carried it to this coordinator, blank when nobody did;
#            blank on a rule row
#   Set      when, YYYY-MM-DDTHH:MMZ
#   Source   where the row's words come from (source_problem below): required
#            on a rule row, optional on the other kinds, and left out of the
#            normal form when blank, so a row written before the column
#            existed reads and is written back byte for byte
#            (docs/designs/DESIGN-coordinator-standing-rule-provenance.md)
# Work, a next step for each holding and a row for work no holding covers:
#   Item     a holding's Unit, or what the work is; unique within its Kind
#   Kind     holding | local-agent | decision (a unit pick parked on a
#            decision entry) | follow-up (a unit whose scoping landed, its
#            execution not yet dispatched) | verdict-owed (a milestone whose
#            work the coordinator judged finished, its verdict not yet
#            confirmed on the roadmap; only roadmap-status.sh writes and
#            clears it) | rework (a milestone a confirmed changes-needed
#            verdict, or a confirmed reopen on a reported failure, sent back
#            for more work; roadmap-status.sh --confirm writes it,
#            state-stored-set.sh --done removes it once a worker is dispatched
#            for it)
#   Who      a holding's Worker (a dispatch topic), or who does the work; for
#            a decision row `decision <n>`, the entry it waits on; for a
#            follow-up row the pull request that landed its scoping,
#            `owner/repo#n`; for a verdict-owed row the topic of the worker
#            that held the milestone, or `none`; for a rework row
#            `verdict <id>` or `failure <id>`, the comment holding the
#            verdict or failure entry, or that entry's number when it stayed
#            in the session
#   Next step  what happens next, one line; a verdict-owed row's is
#            `verdict owed since YYYY-MM-DD`; a rework row's is the
#            verdict's not-held clauses and Changes needed line, or the
#            failure's `Evidence clause <n> failed: <what was seen>`, one
#            paragraph of at most 600 bytes with no URL or markdown link
#            (rework_problem), since the next brief quotes it
#   Wakes    a holding's wakes counted so far (state-stored-set.sh adds this run's
#            from the session log at each write); 0 for a local agent, and
#            read as 0 when blank (docs/designs/current/DESIGN-coordinate-paused-state.md,
#            Decision 4)
#   Updated  when, YYYY-MM-DDTHH:MMZ
#
# The text cells (Run's arguments, Set by, Standing's What, Owner and Relayed
# by, Work's Item, Who and Next step) get text_problem on a public host.

def state_secs: [
  {key: "run", title: "Run", cols: [["key", "Key"], ["value", "Value"], ["set_by", "Set by"], ["set", "Set"]]},
  {key: "standing", title: "Standing", cols: [["standing", "Standing"], ["kind", "Kind"], ["on", "On"],
    ["until", "Until"], ["what", "What"], ["owner", "Owner"], ["relayed_by", "Relayed by"], ["set", "Set"],
    ["source", "Source"]]},
  {key: "work", title: "Work", cols: [["item", "Item"], ["kind", "Kind"], ["who", "Who"], ["next", "Next step"],
    ["wakes", "Wakes"], ["updated", "Updated"]]}];
# store: the legacy row. The record's store is always the coordinator's
# session (docs/designs/current/DESIGN-coordinator-record-teardown.md); a
# session opened before the store choice was removed holds a `store session`
# row, which a carry or an import keeps as written, so it is still accepted.
# No writer adds one, and a row reading anything else (`github`) is refused.
# The crash set (docs/designs/DESIGN-coordinator-session-record.md, Decision
# 9; PRD R17), what a replacement needs after a crash, in any Run section:
#   rules, briefs  `<label> sha256:<64 hex>`, the digest of a file the
#                  coordinator ran with, one row per label; its location is in
#                  record/host, never here
#   friction       a label, one row; its location is in record/host
#   reports-to     `<role>` or `<role> at <address>`: words naming who the
#                  coordinator reports up to, and their messaging address
def run_keys: ["arguments", "cap", "coordinator", "told", "pending", "store", "rules", "briefs", "friction", "reports-to"];
def re_label: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$";
def standing_kinds: ["pause", "go-ahead", "approval", "answer", "assignment", "rule"];
# A Standing row's Source, where its words come from, in one of five forms
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md):
#   decision <session> <id>               a koto decision: <session> a session
#                                         name, <id> 12 digits
#   skill <owner/repo> <path> <commit>    a line of a skill's text
#   doc <owner/repo> <path> <commit>      a document a public host can name
#                                         (<path> relative, with no `.` or
#                                         `..` segment; <commit> 40 hex)
#   pinned <label> sha256:<64 hex>        a file the Run section pins as
#                                         `rules <label>` or `briefs <label>`
#   inferred [brief <label> sha256:<64 hex>]
#                                         the coordinator's own reading, with
#                                         the brief it read it from
# source_problem: null for a Source in one of them, or what is wrong with it.
def re_source_path: "^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$";
def re_digest: "^sha256:[0-9a-f]{64}$";
def source_problem:
  split(" ") as $p
  | ($p | length) as $n
  | def label_digest($l; $d):
      if ($l | test(re_label) | not) then "names a label that isn't letters, digits, `.`, `_` and `-`"
      elif ($d | test(re_digest) | not) then "names a digest that isn't sha256:<64 hex>"
      else null end;
    if $p[0] == "decision" then
      (if $n != 3 then "is not `decision <session> <12-digit id>`"
       elif ($p[1] | test(re_topic) | not) then "names a session that isn't a session name: letters, digits, `.`, `_` and `-`, starting with a letter or a digit"
       elif ($p[2] | test("^[0-9]{12}$") | not) then "names a decision id that isn't 12 digits"
       else null end)
    elif $p[0] == "skill" or $p[0] == "doc" then
      (if $n != 4 then "is not `\($p[0]) <owner/repo> <path> <40-hex commit>`"
       elif ($p[1] | test(re_repo) | not) or any($p[1] | split("/")[]; . == "." or . == "..") then "names a repository that isn't owner/repo"
       elif ($p[2] | test(re_source_path) | not) or any($p[2] | split("/")[]; . == "." or . == "..") then "names a path that isn't relative, or that has a `.` or `..` segment"
       elif ($p[3] | test("^[0-9a-f]{40}$") | not) then "names a commit that isn't 40 hex"
       else null end)
    elif $p[0] == "pinned" then
      (if $n != 3 then "is not `pinned <label> sha256:<64 hex>`" else label_digest($p[1]; $p[2]) end)
    elif $p[0] == "inferred" then
      (if $n == 1 then null
       elif $n != 4 or $p[1] != "brief" then "is not `inferred` or `inferred brief <label> sha256:<64 hex>`"
       else label_digest($p[2]; $p[3]) end)
    else "is not one of `decision <session> <id>`, `skill <owner/repo> <path> <commit>`, `doc <owner/repo> <path> <commit>`, `pinned <label> sha256:<64 hex>` or `inferred [brief <label> sha256:<64 hex>]`" end;
# The repository a `skill` or `doc` Source names, or nothing.
def source_repo: (.source // "") | split(" ") | select(.[0] == "skill" or .[0] == "doc") | .[1] // empty;
# A unit a person assigns outside the scope: an issue, or a release.
def re_assigned: "^(#[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|release [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+ [A-Za-z0-9][A-Za-z0-9._+-]*)$";
def work_kinds: ["holding", "local-agent", "decision", "follow-up", "verdict-owed", "rework"];
# The rework text a rework row carries into a worker's brief: one paragraph
# (the cell already refuses a line break and a control character), at most
# 600 bytes, with no URL and no markdown link, so what a brief quotes as data
# can't point a worker anywhere. null when it fits.
def rework_problem:
  if utf8bytelength > 600 then "over 600 bytes"
  elif test("[a-z][a-z0-9+.-]*://"; "i") or test("(^|[^A-Za-z0-9])www\\."; "i") then "a URL"
  elif test("\\]\\(|\\]\\[|<[a-z][a-z0-9+.-]*:"; "i") then "a markdown link"
  else null end;
# A milestone's heading tag, as a verdict-owed row's Item names it: the
# heading-tag grammar roadmap-status.sh takes (`Feature 7`, `Milestone 7`, `ED1`, `AB10b`).
def re_heading_tag: "^(Feature [0-9]+|Milestone [0-9]+|[A-Za-z]+[0-9]+[a-z]?)$";
def s_text_cols: {run: ["value", "set_by"], standing: ["what", "owner", "relayed_by"], work: ["item", "who", "next"]};
# A unit as pick lists it: a roadmap feature's heading tag or an issue.
def re_unit: "^(Feature [1-9][0-9]*|Milestone [1-9][0-9]*|[A-Za-z]+[1-9][0-9]*|#[1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*)$";
# A pause's resume condition: the merge policy's hold conditions and a time.
def pause_until_ok:
  . == "lifted"
  or (split(" ") | length == 2 and .[0] == "time" and (.[1] | test(re_time_min)))
  or (split(" ") | length == 2 and .[0] == "merged" and (.[1] | test(re_pr_ref)))
  or (split(" ") | length == 3 and .[0] == "tag" and (.[1] | test(re_repo)) and (.[2] | test(re_tag)));

def check_scell($sk; $key; $private):
  . as $v
  | "\($sk).\($key)" as $n
  | if ($v | type) != "string" then refuse("\($n): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("\($n): a control character")
    elif ($v | test("[\r\n]")) then refuse("\($n): a line break")
    elif $v == "" and $sk == "work" and $key == "wakes" then "0"
    elif $v == "" and ($sk != "standing" or ($key != "relayed_by" and $key != "on" and $key != "until" and $key != "source")) then refuse("\($n): empty")
    elif $v == "" then $v
    elif ($key == "set" or $key == "updated") then (if test(re_time_min) then . else refuse("\($n): not YYYY-MM-DDTHH:MMZ") end)
    elif $sk == "run" and $key == "key" then (if any(run_keys[]; . == $v) then . else refuse("run.key: not one of \(run_keys | join(", "))") end)
    elif $sk == "standing" and $key == "standing" then (if test("^s[1-9][0-9]*$") then . else refuse("standing.standing: not s<n>") end)
    elif $sk == "standing" and $key == "kind" then (if any(standing_kinds[]; . == $v) then . else refuse("standing.kind: not one of \(standing_kinds | join(", "))") end)
    elif $sk == "work" and $key == "kind" then (if any(work_kinds[]; . == $v) then . else refuse("work.kind: not holding, local-agent, decision, follow-up, verdict-owed or rework") end)
    elif $sk == "work" and $key == "wakes" then (if test("^(0|[1-9][0-9]{0,5})$") then . else refuse("work.wakes: not a count") end)
    elif $sk == "standing" and $key == "on" then (if . == "all" or test(re_unit) or test(re_assigned) then . else refuse("standing.on: not `all` or a unit (`Feature 2`, `Milestone 2`, `ED1`, `#12`, `owner/repo#12`, `release owner/repo <tag>`)") end)
    elif $sk == "standing" and $key == "until" then (if pause_until_ok then . else refuse("standing.until: not `lifted`, `time <YYYY-MM-DDTHH:MMZ>`, `merged owner/repo#n` or `tag owner/repo <tag>`") end)
    else . end
  | if ($v != "") and $sk == "standing" and ($key == "on" or $key == "until") then
      ([$private[] as $p | select($v | names_repo($p)) | $p] | first) as $hit
      | if $hit != null then refuse("\($n): names \($hit), a repository that isn't public") else . end
    else . end
  | if ($v != "") and any(s_text_cols[$sk][]; . == $key) then
      ($v | text_problem($private)) as $why
      | if $why != null then refuse("\($n): \($why)") else . end
    else . end;

def check_srow($sec; $private):
  . as $row
  | if type != "object" then refuse("\($sec.key): a row that isn't an object") else . end
  | ([keys[] | . as $k | select(any($sec.cols[]; .[0] == $k) | not)]) as $extra
  | if ($extra | length) > 0 then refuse("\($sec.key).\($extra[0]): not a column of this section") else . end
  # A rule row's Owner is blank (check_srow refuses one that isn't, naming the
  # row); every other row's is required.
  | reduce $sec.cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") as $v
      | if $sec.key == "standing" and $c[0] == "owner" and $v == "" and $row.kind == "rule" then $v
        else $v | check_scell($sec.key; $c[0]; $private) end))
  | if $sec.key == "run" then
      (if .key == "cap" then (if .value | test("^[1-9][0-9]?$") then . else refuse("run.value: a cap is a number from 1 to 99") end)
       elif .key == "coordinator" or .key == "told" or .key == "pending" then (.value | check_worker) as $_ | .
       elif .key == "store" then (if .value == "session" then . else refuse("run.value: the store is the session; a store row reads session, never \(.value)") end)
       elif .key == "rules" or .key == "briefs" then
         (if (.value | test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63} sha256:[0-9a-f]{64}$")) then .
          else refuse("run.value: a \(.key) row is `<label> sha256:<64 hex>`, the label letters, digits, `.`, `_` and `-`") end)
       elif .key == "friction" then
         (if (.value | test(re_label)) then . else refuse("run.value: a friction row is a label: letters, digits, `.`, `_` and `-`") end)
       elif .key == "reports-to" then
         (if (.value | test(" at ")) then
            (.value | sub("^.* at "; "")) as $addr | (.value | sub(" at [^ ]*$"; "")) as $role
            | if ($addr | test(" ")) or $role == "" then refuse("run.value: a reports-to row is `<role>` or `<role> at <address>`")
              else ($addr | check_worker) as $_ | . end
          else . end)
       else . end)
    elif $sec.key == "work" and .kind == "holding" then (.who | check_worker) as $_ | .
    elif $sec.key == "work" and (.kind == "decision" or .kind == "follow-up") then
      (if ((.item | test(re_unit)) or (.item | test(re_assigned))) | not then refuse("work.item: a \(.kind) row's Item is a unit as pick lists it (`Feature 2`, `Milestone 2`, `ED1`, `#12`, `owner/repo#12`, `release owner/repo <tag>`)")
       elif .kind == "decision" and (.who | test("^decision [1-9][0-9]*$") | not) then refuse("work.who: a decision row's Who is `decision <n>`")
       elif .kind == "follow-up" and (.who | test(re_pr_ref) | not) then refuse("work.who: a follow-up row's Who is the pull request that landed its scoping, `owner/repo#n`")
       else . end)
    elif $sec.key == "work" and .kind == "verdict-owed" then
      (if (.item | test(re_heading_tag) | not) then refuse("work.item: a verdict-owed row's Item is a milestone's heading tag (`Feature 2`, `Milestone 2`, `MV1`, `AB10b`)")
       elif (.next | test("^verdict owed since [0-9]{4}-[0-9]{2}-[0-9]{2}$") | not) then refuse("work.next: a verdict-owed row's Next step is `verdict owed since YYYY-MM-DD`")
       else (.who | check_worker) as $_ | . end)
    elif $sec.key == "work" and .kind == "rework" then
      (if (.item | test(re_heading_tag) | not) then refuse("work.item: a rework row's Item is a milestone's heading tag (`Feature 2`, `Milestone 2`, `MV1`, `AB10b`)")
       elif (.who | test("^(verdict|failure) [1-9][0-9]*$") | not) then refuse("work.who: a rework row's Who is `verdict <id>` or `failure <id>`, the comment holding its verdict or failure entry, or that entry's number when it stayed in the session")
       elif (.next | rework_problem) != null then refuse("work.next: a rework row's text is one paragraph of at most 600 bytes with no URL or markdown link: \(.next | rework_problem)")
       else . end)
    elif $sec.key == "standing" then
      (if .kind == "rule" then
         (if .owner != "" then refuse("standing.\(.standing): a rule row's Owner is blank; its Source says who said it")
          elif .relayed_by != "" then refuse("standing.\(.standing): a rule row's Relayed by is blank; its Source says where it came from")
          elif .on != "" or .until != "" then refuse("standing.\(.standing): a rule row has no On and no Until; it binds until it is ended")
          elif .source == "" then refuse("standing.\(.standing): a rule row names its Source")
          else . end)
       elif .kind == "pause" then
         (if .on == "" or .until == "" then refuse("standing.\(.standing): a pause names its On and its Until") else . end)
       elif .kind == "go-ahead" then
         (if .until != "" then refuse("standing.\(.standing): a go-ahead has no Until; it ends when used")
          elif .on == "all" then refuse("standing.\(.standing): a go-ahead names one unit, never `all`")
          else . end)
       elif .kind == "assignment" then
         (if .until != "" then refuse("standing.\(.standing): an assignment has no Until; it ends when its work is done")
          elif (.on | test(re_assigned) | not) then refuse("standing.\(.standing): an assignment's On is an issue (`#12`, `owner/repo#12`) or `release owner/repo <tag>`")
          else . end)
       elif .on != "" or .until != "" then refuse("standing.\(.standing): only a pause, a go-ahead or an assignment has an On, and only a pause an Until")
       else . end)
      # The Source, on any kind that has one, in one of its five forms and
      # naming no repository the host can't show; a blank one is left out of
      # the normal form, so a row written before the column reads as written.
      | (if .source == "" then del(.source)
         else (.source | source_problem) as $why
           | if $why != null then refuse("standing.\(.standing): the Source \($why)") else . end
           | ([source_repo as $sr | $private[] as $p | select($sr | names_repo($p)) | $p] | first) as $hit
           | if $hit != null then refuse("standing.\(.standing): the Source names \($hit), a repository that isn't public") else . end
         end)
    else . end;

def check_state($sec; $rows; $private):
  if $rows == null then null
  elif ($rows | type) != "array" then refuse("\($sec.key): not a list")
  else ($rows | map(check_srow($sec; $private))) as $r
    | if $sec.key == "run" then
        ($r | map(select(.key != "told" and .key != "pending" and .key != "rules" and .key != "briefs") | .key)) as $once
        | ($r | map(select(.key == "told") | .value)) as $told
        | ($r | map(select(.key == "pending") | .value)) as $pending
        | ($r | map(select(.key == "rules" or .key == "briefs") | "\(.key) \(.value | split(" ")[0])")) as $labels
        | if ($once | map(select(. == "store")) | length) > 1 then refuse("run: the store row is used twice")
          elif ($once | unique | length) != ($once | length) then refuse("run: a key other than told, pending, rules and briefs is used twice")
          elif ($told | unique | length) != ($told | length) then refuse("run: a party is told twice")
          elif ($pending | unique | length) != ($pending | length) then refuse("run: a worker is pending twice")
          elif any($pending[]; . as $p | $told | index($p) != null) then refuse("run: a worker is both told and pending")
          elif ($labels | unique | length) != ($labels | length) then refuse("run: a rules or briefs label is used twice")
          else $r end
      elif $sec.key == "standing" then
        (if ($r | map(.standing) | unique | length) != ($r | length) then refuse("standing: an id is used twice") else $r end)
      else
        (if ($r | map([.item, .kind]) | unique | length) != ($r | length) then refuse("work: an item is listed twice under one kind") else $r end)
      end
  end;

# rule_class: a Standing row's class, worked out at read from its Source; no
# column stores it, so nothing can disagree with where the words came from.
#   relayed     no Source: an event a person owns, carried here by --standing
#   inferred    `inferred`, with or without its brief
#   skill-says  `skill ...`
#   doc         `doc ...`
#   charter     `pinned ...`
#   unreadable  `decision ...`: what koto recorded about the decision isn't
#               read yet, so the row is neither the owner's word nor anyone
#               else's until it is
# rule_status, over a class: in-force, unconfirmed (an inferred row, waiting
# for a person to confirm it) or unreadable.
def rule_class:
  ((.source // "") | split(" ")[0] // "") as $f
  | if $f == "" then "relayed"
    elif $f == "inferred" then "inferred"
    elif $f == "skill" then "skill-says"
    elif $f == "doc" then "doc"
    elif $f == "pinned" then "charter"
    else "unreadable" end;
def rule_status:
  if . == "inferred" then "unconfirmed" elif . == "unreadable" then "unreadable" else "in-force" end;

# rule_view($session; $entries): one Standing row, as state-stored-set.sh
# --rules prints it, for the record in $session whose entries
# (state-entry.sh --list) are $entries:
#   class, status   rule_class and rule_status
#   owner           the row's Owner for a relayed row, else null: the Source
#                   and the pointer say who or what said it
#   said            the row's Set, or null for an unreadable row, whose
#                   decision's time isn't read
#   pointer         a relayed row's entry, the first whose kind is the row's
#                   and whose text begins `s<n> (`, the one its own --standing
#                   wrote: {entry: "<session> record/entries/<n>"}, or
#                   {row: "<session> record/standing s<n>"} when no entry
#                   matches; a decision's {decision: "<session> <id>"}; a
#                   skill's or doc's {repo, path, commit}; a pinned file's
#                   {pinned: <label>, digest}; an inferred brief rule's
#                   {brief: <label>, digest}; a bare inferred row's own row
#   words           null: only a cited decision's recorded words would go
#                   here, and none is read yet
#   source          the Source, or null for none
#   reversal        null: no reversal is read yet
#   confirm         true for an inferred row, which a person confirms
def rule_view($session; $entries):
  . as $r
  | rule_class as $c
  | (($r.source // "") | split(" ")) as $p
  | {row: "\($session) record/standing \($r.standing)"} as $self
  | {standing: $r.standing, kind: $r.kind, class: $c, what: $r.what,
     owner: (if $c == "relayed" then $r.owner else null end),
     said: (if $c == "unreadable" then null else $r.set end),
     set: $r.set,
     pointer: (if $c == "relayed" then
                 (first($entries[] | select(.kind == $r.kind and ((.text // "") | startswith($r.standing + " (")))) // null) as $e
                 | if $e == null then $self
                   else {entry: "\($session) record/entries/\("000000\($e.id)" | .[-6:])"} end
               elif $c == "unreadable" then {decision: "\($p[1]) \($p[2])"}
               elif $c == "skill-says" or $c == "doc" then {repo: $p[1], path: $p[2], commit: $p[3]}
               elif $c == "charter" then {pinned: $p[1], digest: $p[2]}
               elif ($p | length) == 4 then {brief: $p[2], digest: $p[3]}
               else $self end),
     words: null,
     source: (if ($r.source // "") == "" then null else $r.source end),
     status: ($c | rule_status), reversal: null, confirm: ($c == "inferred")};

# Whether a row may grant, over one rule_view object
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md). shirabe keeps
# two expectations about a row's text and builds no grant model: what a grant
# allows is the session's, as niwa's authority read answers it.
#
# rule_floor: true for a row that can only restrict: a pause, an inferred row,
# a `pinned` row, an unreadable row, a row not in force (superseded,
# unconfirmed) and a row with a reversal (an `asserted` one leaves it in force
# but never lets it grant).
def rule_floor:
  ((.source // "") | split(" ")[0] // "") as $f
  | .kind == "pause" or .class == "inferred" or .class == "unreadable" or $f == "pinned"
    or .status != "in-force" or .reversal != null;
# rule_anchored($facts): false for a `skill` row citing any repository but the
# one the installed plugin's manifest names ($facts.plugin_repo, null when it
# names none) and for a `doc` row citing any repository but the record's host
# ($facts.host_repo); true for every other row. It is a rule about whose
# merged words a row may quote, and the authority read doesn't replace it.
def rule_anchored($facts):
  ((.source // "") | split(" ")) as $p
  | def same($r): ($r | type) == "string" and $r != "" and ($p[1] | ascii_downcase) == ($r | ascii_downcase);
    if $p[0] == "skill" then same($facts.plugin_repo)
    elif $p[0] == "doc" then same($facts.host_repo)
    else true end;
# rule_passes($facts): the row passes the floor and the anchor, so only the
# authority read settles it.
def rule_passes($facts): (rule_floor | not) and rule_anchored($facts);
# grant_allows: over `niwa authority check --json`'s document, the authorities
# its grant holds, in niwa's order, when it is a niwa.authority.check/v1
# document with state bound, a grant array whose every authority is merge-pr,
# close-issue or cut-release, and a level of autonomous, supervised or strict;
# null for any other document or value.
def grant_allows:
  def in_set($s): . as $v | any($s[]; . == $v);
  if type == "object"
     and .schema == "niwa.authority.check/v1"
     and .state == "bound"
     and (.grant | type == "array")
     and all(.grant[]; type == "object" and (.authority | in_set(["merge-pr", "close-issue", "cut-release"])))
     and (.level | in_set(["autonomous", "supervised", "strict"]))
  then [.grant[].authority] else null end;
# rule_grants($facts): {under_session_grant, session_allows} for one
# rule_view object. $facts is {plugin_repo, host_repo, answer}, answer the
# authority read's document, or null when no read was made or it failed. The
# row grants nothing itself: under_session_grant is true only for a row that
# passes the floor and the anchor under a bound answer, and session_allows is
# then the session's grant as that answer gives it, never more whatever the
# row's words say, and [] otherwise.
def rule_grants($facts):
  (if $facts.answer == null then null else ($facts.answer | grant_allows) end) as $a
  | if $a != null and rule_passes($facts) then {under_session_grant: true, session_allows: $a}
    else {under_session_grant: false, session_allows: []} end;

def decisions_cols: [
  ["decision", "Decision"], ["round", "Round"], ["question", "Question"],
  ["options", "Options"], ["state", "State"], ["source", "Source"],
  ["verdict", "Verdict"], ["recommendation", "Recommendation"], ["reason", "Reason"],
  ["context", "Context"], ["problem", "Problem"], ["grounds", "Grounds"],
  ["target", "Target"], ["owed", "Owed"], ["asked", "Asked"],
  ["evidence", "Evidence"], ["outcome", "Outcome"], ["decided_by", "Decided by"],
  ["updated", "Updated"]];

def d_states: ["proposed", "coordinator-verdict", "escalated", "settled"];
def d_grounds: ["scope", "supplied-decision", "reserved-step", "outside-scope"];
# The columns a person or the coordinator writes in words: a public host's
# check reads them, and `@` is encoded in them so a record never mentions
# anyone.
def d_text_cols: ["question", "options", "recommendation", "reason", "context",
  "problem", "evidence", "outcome", "decided_by"];
# A stamp names the run (the UTC stamp in the session's name) and the visit
# that caused a write, so no run's write is mistaken for another's.
def re_stamp: "\\[[0-9]{8}T[0-9]{6}Z (report|wait|raise|hold|redirect|ask) [1-9][0-9]*(\\.[1-9][0-9]*)?\\]";

# check_dcell($key; $private): one Decisions cell, by this section's grammars.
def check_dcell($key; $private):
  . as $v
  | if ($v | type) != "string" then refuse("decisions.\($key): not a string")
    elif $v | test("[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]") then refuse("decisions.\($key): a control character")
    elif ($v | test("\r")) then refuse("decisions.\($key): a carriage return")
    elif ($v != "") and (($key != "options") and ($key != "evidence")) and ($v | test("\n")) then refuse("decisions.\($key): a line break inside a single item")
    elif $v == "" then $v
    elif $key == "decision" then (if test("^[1-9][0-9]*$") then . else refuse("decisions.decision: not a positive integer") end)
    elif $key == "round" then (if test("^(0|[1-9][0-9]*)$") then . else refuse("decisions.round: not a count") end)
    elif $key == "state" then (if any(d_states[]; . == $v) then . else refuse("decisions.state: not proposed, coordinator-verdict, escalated or settled") end)
    elif $key == "source" then (if test("^(worker [A-Za-z0-9][A-Za-z0-9._-]*|coordinator [A-Za-z0-9][A-Za-z0-9._-]* #[1-9][0-9]* round [1-9][0-9]*|dispatcher|self) " + re_stamp + "$") then . else refuse("decisions.source: not `worker <topic>`, `coordinator <topic> #<n> round <r>`, `dispatcher` or `self`, then a stamp") end)
    elif $key == "verdict" then (if test("^(settle|escalate|hold)$") then . else refuse("decisions.verdict: not settle, escalate or hold") end)
    elif $key == "grounds" then (if (split(", ") | all(. as $g | any(d_grounds[]; . == $g))) then . else refuse("decisions.grounds: not a comma list of \(d_grounds | join(", "))") end)
    elif $key == "target" then (if test("^(a person|coordinator [A-Za-z0-9][A-Za-z0-9._-]*)$") then . else refuse("decisions.target: not `a person` or `coordinator <topic>`") end)
    elif $key == "owed" then (if test("^(escalation|withdrawal|reply)$") then . else refuse("decisions.owed: not escalation, withdrawal or reply") end)
    elif ($key == "asked" or $key == "updated") then (if test(re_time_min) then . else refuse("decisions.\($key): not YYYY-MM-DDTHH:MMZ") end)
    elif $key == "options" then (if (split("\n") | all(length > 0)) then . else refuse("decisions.options: an empty option") end)
    elif $key == "evidence" then (if (split("\n") | all(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z [^\\[]+ " + re_stamp + ": .+$"))) then . else refuse("decisions.evidence: a line that isn't `<time> <source> <stamp>: <text>`") end)
    else . end
  | if ($v != "") and any(d_text_cols[]; . == $key) then
      ($v | text_problem($private)) as $why
      | if $why != null then refuse("decisions.\($key): \($why)") else . end
    else . end;

def re_kept_stamp: "^[1-9][0-9]* (report|wait|raise|hold|redirect|ask) [1-9][0-9]*(\\.[1-9][0-9]*)?( addressed)?$";

def check_drow($private):
  . as $row
  | if type != "object" then refuse("decisions: a row that isn't an object") else . end
  | (decisions_cols | map(.[0])) as $keys
  | ([keys[] | . as $k | select(any($keys[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then refuse("decisions.\($extra[0]): not a column of this section") else . end
  | (reduce decisions_cols[] as $c ({}; .[$c[0]] = (($row[$c[0]] // "") | check_dcell($c[0]; $private)))) as $r
  | def need($ks; $why): ($ks | map(select(($r[.] // "") == "")) | first) as $m
      | if $m != null then refuse("decisions: entry \($r.decision): \($m) is empty, and \($why)") else . end;
    ($r | need(["decision", "round", "question", "state", "source", "updated"]; "every entry needs it"))
  | if $r.state == "escalated" then need(["options", "recommendation", "reason", "context", "problem", "grounds", "target"]; "an escalated entry needs it")
    elif $r.state == "settled" then need(["outcome", "decided_by"]; "a settled entry needs it")
    elif $r.state == "proposed" then need(["options"]; "a proposed entry needs it")
    elif $r.verdict == "hold" then need(["reason"]; "a held verdict needs what it waits on")
    else . end
  | if $r.state == "proposed" and $r.verdict != ""
    then refuse("decisions: entry \($r.decision): a proposed entry has no verdict yet") else . end
  | if $r.verdict == "hold" and $r.state != "coordinator-verdict"
    then refuse("decisions: entry \($r.decision): only an entry awaiting a verdict can be held") else . end
  | $r;

# check_decisions($d; $private): the section's JSON, checked; null when absent.
def check_decisions($d; $private):
  if $d == null then null
  elif ($d | type) != "object" then refuse("decisions: not an object")
  elif (($d | keys) - ["entries", "next", "archived", "kept"]) != [] then refuse("decisions.\((($d | keys) - ["entries", "next", "archived", "kept"])[0]): not a field of this section")
  elif ($d.next | type) != "number" or $d.next < 1 or $d.next > 999999 or ($d.next | floor) != $d.next then refuse("decisions.next: not a positive integer below a million")
  elif (($d.entries // []) | type) != "array" then refuse("decisions.entries: not a list")
  elif (($d.archived // []) | type) != "array" or any(($d.archived // [])[]; type != "number" or . < 1 or floor != .)
    then refuse("decisions.archived: not a list of identifiers")
  elif $d.kept != null and (($d.kept | type) != "object" or ($d.kept | keys) != ["run", "stamps"]
      or ($d.kept.run | type) != "string" or ($d.kept.run | test("^[0-9]{8}T[0-9]{6}Z$") | not)
      or ($d.kept.stamps | type) != "array" or ($d.kept.stamps | length) == 0
      or any($d.kept.stamps[]; type != "object" or keys != ["addressed", "decision", "kind", "seq"]
             or (.decision | type) != "number" or (.addressed | type) != "boolean"
             or ("\(.decision) \(.kind) \(.seq)" | test(re_kept_stamp) | not)))
    then refuse("decisions.kept: not {run, stamps: [{decision, kind, seq, addressed}]}")
  else
    ($d.entries // [] | map(check_drow($private))) as $rows
    | ($rows | map(.decision | tonumber)) as $ids
    | ($d.archived // [] | unique) as $arch
    | if ($ids | unique | length) != ($ids | length) then refuse("decisions: an identifier is used twice")
      elif any($ids[]; . >= $d.next) then refuse("decisions: an identifier at or above Next decision (\($d.next))")
      elif any($arch[]; . >= $d.next) then refuse("decisions.archived: an identifier at or above Next decision (\($d.next))")
      elif any($arch[]; . as $a | $ids | index($a)) then refuse("decisions.archived: an identifier the section still holds")
      elif $d.kept != null and any($d.kept.stamps[]; .decision as $k | $arch | index($k) | not)
        then refuse("decisions.kept: a stamp of an entry that isn't archived")
      # floor: a number written 7.0 or 7e0 is kept as 7, the one form a
      # reader is handed.
      else {next: ($d.next | floor), entries: $rows}
        + (if ($arch | length) > 0 then {archived: $arch} else {} end)
        + (if $d.kept != null then {kept: $d.kept} else {} end) end
  end;

def checked_sections($in; $private):
  sections | map(. as $sec
    | ($in[$sec.key] // []) as $rows
    | if ($rows | type) != "array" then refuse("\($sec.key): not a list") else . end
    | {sec: $sec, rows: ($rows | map(check_row($sec; $private)))});

def check_top($in; $allowed):
  ([$in | keys[] | . as $k | select(any($allowed[]; . == $k) | not)]) as $extra
  | if ($extra | length) > 0 then refuse("\($extra[0]): not a field of this format") else . end;

# check_scope($s): the record's scope, {kind: roadmap|discipline, name}.
def check_scope($s):
  if ($s | type) != "object" then refuse("scope: missing")
  elif ($s.name // "" | test(re_name) | not) then refuse("scope.name: not a name")
  elif $s.kind != "roadmap" and $s.kind != "discipline" then refuse("scope.kind: not roadmap or discipline")
  else $s end;

# The top-level fields a record's state may hold. `written` is the version a
# write was edited from; the write core compares it, so no grammar is held here.
def record_fields: ["scope", "written", "holdings", "deferrals", "side_effects", "reversals", "holds", "run", "standing", "work", "decisions"];

# scan_strings($private): every string in the value, at any depth, the value
# itself when it is one, through text_problem: a repository on the $private
# list, a home-directory path or a token-shaped string is refused, naming the
# string's path (`holdings[0].branch`). It walks the value instead of a list
# of columns, so a field added later is scanned without being named here.
# Gives the value back unchanged.
def scan_strings($private):
  . as $v
  | ([paths(strings)] + (if type == "string" then [[]] else [] end)) as $ps
  | (first($ps[] as $p | ($v | getpath($p) | text_problem($private)) as $why
      | select($why != null) | {p: $p, why: $why}) // null) as $hit
  | if $hit == null then $v
    else refuse("\($hit.p | map(if type == "number" then "[\(.)]" else ".\(.)" end) | join("") | ltrimstr(".") | if . == "" then "value" else . end): \($hit.why)") end;

# check_record($private): a whole state, checked in this order: the
# top-level fields, the scope, the four sections, Holds, the
# stored set and Decisions, then every string in it (scan_strings). Gives the
# state back as the checks normalize it (every column present, a blank Wakes
# read as 0, an absent optional section left out), or refuses with the first
# rule it breaks.
def check_record($private):
  . as $in
  | check_top($in; record_fields)
  | check_scope($in.scope) as $_
  | ({scope: $in.scope}
    + (if $in | has("written") then {written: $in.written} else {} end)
    + (checked_sections($in; $private) | map({(.sec.key): .rows}) | add)
    + (check_holds($in.holds; $private) | if . == null then {} else {holds: .} end)
    + reduce state_secs[] as $sec ({};
        check_state($sec; $in[$sec.key]; $private) as $rows
        | if $rows == null then . else .[$sec.key] = $rows end)
    + (check_decisions($in.decisions; $private) | if . == null then {} else {decisions: .} end)) as $out
  | ($in | scan_strings($private)) as $_
  | $out;

# normalize_state($private): the state as a reader is handed it and a writer
# stores it. check_record's normal form, less the optional sections that hold
# nothing: a Holds or stored-set section with no rows, and a Decisions section
# with no entries whose Next decision is 1. Those are the sections a record
# with nothing in them never carried, so a state written through here holds no
# key for them, as a state written through the old markdown body never did
# (normalize_test.sh holds normalize_state to that result for every section
# shape).
def normalize_state($private):
  check_record($private)
  | (if (.holds // null) == [] then del(.holds) else . end)
  | reduce state_secs[] as $sec (.; if (.[$sec.key] // null) == [] then del(.[$sec.key]) else . end)
  | (if .decisions != null and (.decisions.entries | length) == 0 and .decisions.next == 1 then del(.decisions) else . end);

# ---- the Decisions entries' helpers -----------------------------------------
#
# escalation_problems($target): what keeps a recorded escalate verdict from
# being escalated to $target, as a list (empty when it may be). The one
# validator state-decision.sh and decision-render.sh share.
#
# An escalated entry's Options lines each carry an explanation, written
# `<option> -- <explanation>` so the column's grammar is unchanged; the
# recommendation names the option part. d_options gives them as
# {label, explanation}, in the record's order.
def d_options:
  (.options // "") | split("\n") | map(select(length > 0)
    | split(" -- ") as $p | {label: $p[0], explanation: ($p[1:] | join(" -- "))});
def escalation_problems($target):
  def blank: (. // "") | gsub("^\\s+|\\s+$"; "") | . == "";
  . as $e
  | [ (if ([$e | d_options[].label] | index($e.recommendation // "")) == null then "the recommendation is not one of the options" else empty end),
      (if any($e | d_options[]; .explanation | blank) then "an option has no explanation" else empty end),
      (if ($e.reason | blank) then "the reason is empty" else empty end),
      (if ($e.context | blank) then "the context is empty" else empty end),
      (if ($e.problem | blank) then "the problem is empty" else empty end),
      (if ($e.grounds | blank) then "no ground" else empty end),
      (if ($e.target // "") != $target then "the target is not the run's (\($target))" else empty end) ];

# The stamps an entry carries, by position: the one ending its Source, and the
# one after each Evidence line's source. A stamp-like string inside a line's
# text is not a stamp. Each is {run, kind, seq, text}; text is the Evidence
# line's text, "" for the Source's.
def d_stamps:
  [ ((.source // "") | capture(" \\[(?<run>[0-9]{8}T[0-9]{6}Z) (?<kind>[a-z]+) (?<seq>[0-9.]+)\\]$") | . + {text: ""}),
    ((.evidence // "") | split("\n")[] | select(length > 0)
      | capture("^[^ ]+ [^\\[]+ \\[(?<run>[0-9]{8}T[0-9]{6}Z) (?<kind>[a-z]+) (?<seq>[0-9.]+)\\]: (?<text>.*)$")) ];
# The text of the Evidence line that marks an extracted question as addressed
# to a person, stamped with the report that carried it. A report with one owes
# its worker a redirect; decision-next.sh routes it, decision-render.sh renders
# it, and state-decision.sh --open-from-report writes the mark.
def d_addressed_mark: "addressed to a person";

# compact_settled: a settled entry that owes nothing keeps its identity, round,
# question, options, source, outcome, who decided, when, and its redirect
# lines; every other cell is blanked. `Next decision` keeps its identifier from
# being reused.
def compact_settled:
  if .state == "settled" and (.owed // "") == "" then
    . as $e | reduce (decisions_cols[] | .[0]) as $k ({}; .[$k] = "")
    | .decision = $e.decision | .round = $e.round | .question = $e.question
    | .options = $e.options
    | .state = "settled" | .source = $e.source | .outcome = $e.outcome
    | .decided_by = $e.decided_by | .updated = $e.updated
    # Options stay because evidence can reopen a settled entry, which then
    # needs them to be escalated again; a redirect line stays because losing it
    # would owe the report's redirect a second time.
    | .evidence = ([($e.evidence // "") | split("\n")[]
        | select(test("^[^ ]+ [^\\[]+ \\[[0-9]{8}T[0-9]{6}Z redirect [0-9]+\\]: "))] | join("\n"))
  else . end;

# A record moved from a GitHub record may keep entries its body archived: an
# `archived` list of identifiers, and `kept`, the archiving run's stamps on
# them, {run, stamps: [{decision, kind, seq, addressed}]}. The replay guard
# (state-decision.sh) and the unrecorded and redirect rules (decision-next.sh)
# read a kept stamp as they read a row's. Nothing archives an entry any more.
#
# d_section_stamps: every stamp a Decisions section holds, in its rows and kept,
# each {run, kind, seq, text, decision}; a kept stamp's text is the addressed
# mark or empty.
def d_section_stamps:
  [(.entries // [])[] | . as $e | d_stamps[] | . + {decision: $e.decision}]
  + (if .kept == null then [] else .kept.run as $r
       | [.kept.stamps[] | {run: $r, kind, seq, text: (if .addressed then d_addressed_mark else "" end), decision: (.decision | tostring)}] end);

# d_archive_rows: the entries a `decisions` entry's text holds, the rows of a
# Decisions table a GitHub record's body archived, under the table's header,
# whatever precedes it. A cell was written escaped (dec_d reads it back), and
# state-decision.sh restores an archived entry from the latest entry holding
# its row.
def dec:
  gsub("&#9;"; "\t") | gsub("&#32;"; " ") | gsub("<br>"; "\n")
  | gsub("&#13;"; "\r") | gsub("\\\\\\|"; "|") | gsub("&#92;"; "\\")
  | gsub("&gt;"; ">") | gsub("&lt;"; "<") | gsub("&amp;"; "&");
def dec_d: gsub("&#64;"; "@") | dec;
def d_header:
  ("| " + (decisions_cols | map(.[1]) | join(" | ")) + " |") + "\n"
  + ("|" + (decisions_cols | map("---") | join("|")) + "|");
def parse_drow:
  (if (startswith("| ") and endswith(" |")) | not then refuse("table row: not | cell | ... |") else . end
   | .[2:-2] | gsub("\\\\\\|"; "\u001f") | split(" | ") | map(gsub("\u001f"; "\\|") | dec_d)) as $cells
  | if ($cells | length) != (decisions_cols | length) then refuse("Decisions: a row with \($cells | length) cells, not \(decisions_cols | length)")
    else [range(0; decisions_cols | length) as $i | {(decisions_cols[$i][0]): $cells[$i]}] | add end;
def d_archive_rows:
  split("\n") | (index([d_header | split("\n")[0]]) // null) as $h
  | if $h == null then [] else .[$h + 2:] | map(select(startswith("| ")) | parse_drow) end;

# ---- the rework text ---------------------------------------------------------
#
# rework_cap: a failure's rework text held to the 600 bytes rework_problem
# allows. What was seen may itself be 600 bytes and the row's text puts
# `Evidence clause <n> failed: ` before it, so a longer text is cut, a whole
# codepoint at a time, and ends `...` to show the cut. A changes-needed
# verdict's text is refused instead (roadmap-status.sh --verdict), since the
# coordinator writes it and can shorten it.
def rework_cap:
  if utf8bytelength <= 600 then .
  else (explode | until((implode | utf8bytelength) <= 597; .[:-1]) | implode) + "..." end;

# ---- the listers' projections ------------------------------------------------
# What state-holding.sh, state-stored-set.sh, state-decision.sh and
# roadmap-status.sh print for --list, from a record. pick-facts.sh takes all of
# them from one read rather than running each lister, which would read the
# record once apiece (shirabe#840).
def holdings_list: .holdings;
def state_list: {run: (.run // []), standing: (.standing // []), work: (.work // [])};
def decisions_list: .decisions // {next: 1, entries: []};
# The Side effects Actions that are roadmap edits: a feature's Done
# (roadmap-status), a milestone verdict's (milestone-done, milestone-verdict)
# and a milestone's reopen (milestone-reopen).
def roadmap_edit_actions: ["roadmap-status", "milestone-done", "milestone-verdict", "milestone-reopen"];
# The pending roadmap pull requests, {unit, pull_request, attempted, action,
# how_to_confirm}: the Target is `<TAG> [#n](URL)`.
def pending_rows: roadmap_edit_actions as $acts
  | [.side_effects[] | select(.action as $a | any($acts[]; . == $a))
     | (.target | capture("^(?<unit>.+) (?<pr>\\[#[0-9]+\\]\\(https://github\\.com/[^)]+\\))$")) as $t
     | {unit: ($t.unit // .target), pull_request: ($t.pr // ""), attempted, action, how_to_confirm}];
def pending_list: pending_rows | map(del(.how_to_confirm));
