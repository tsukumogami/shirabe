# Tool Diagnostic Discards

The committed enumeration of every call site that discards a declared tool's
diagnostic output, and the policy that governs adding one. Normative prose, like
[`wip-hygiene.md`](wip-hygiene.md) and
[`tool-declaration-policy.md`](tool-declaration-policy.md): no skill loads this
file, and it is reviewed as part of a PR. `scripts/check-tool-diagnostic-discards.sh`
reads the record block below and fails a PR in either direction -- a discarding
site missing from the list, or a listed record matching nothing.

## The rule

No verification performed by the load-time check, and no call site for a tool
named in any `skills/<name>/requires.tsv`, may discard that tool's diagnostic
output or ignore its exit status. Discarding covers redirection to `/dev/null`
in any spelling, capture into a variable that is never read, and any other route
by which the text reaches nobody.

A site MAY discard where failure is an expected outcome it handles, and is then
recorded here, naming the site and the exit status the fallback is entered on.
A site that discards and is absent from this file fails the scan.

**No judgment about whether a discard was reasonable is made at scan time.**
That judgment moved into this file, which is the entire point. `shirabe#279` was
silent because its call site redirected stderr to `/dev/null` and did not check
the exit status; "the fallback is not a masked failure" was the exact judgment
whoever wrote that site made at the call site, and got wrong. The control is not
that the scan is clever. The control is that the judgment is written down where
a named reviewer reads it.

## Commit convention

A new entry MAY land in the same PR as the code it exempts -- splitting them
would mean landing code that fails CI and fixing it afterward. The entry MUST be
its own commit in that PR, so it is reviewable as a decision rather than buried
in a diff about something else.

**No adjudicator is named, and that is a known gap.** "It costs a reviewed
edit" is a claim about a process, and a process with no owner is not a control:
today an addition needs whoever happened to be on the PR, not a reviewer who
owns this decision. A `CODEOWNERS` entry is the obvious mechanism and was
deliberately not added here, because this repository has no `CODEOWNERS` file
and introducing the first one changes review mechanics repository-wide — that
is a maintainer's decision, not a side effect of shipping a check. It also only
binds if branch protection sets `require_code_owner_reviews`; without that the
file is inert, which is the same silent-no-op this document exists to prevent.

Until an owner is named, the enumeration is enforced mechanically (an
unenumerated discard fails CI) and adjudicated socially (the same-PR,
own-commit rule above keeps the decision visible in review). The mechanical
half holds on its own. The social half is discipline, and should be read as
discipline rather than as a gate.

## Record format

The canonical records live in the single ```` ```tsv ```` fenced block below.
Tab-separated, six fields, one record per line. Lines beginning with `#` are
comments. The block is the only ```` ```tsv ```` fence in the file; the scan
rejects the file if there is more than one.

| # | Field | Meaning |
|---|---|---|
| 1 | `path` | Repo-relative path to the file holding the site. Never carries a `:lineno` suffix. |
| 2 | `command` | The source line, whitespace-trimmed, byte-for-byte otherwise. |
| 3 | `count` | How many byte-identical trimmed copies of that line the file holds. |
| 4 | `exit-status` | The status the fallback is entered on. Comma-separated when a site has more than one expected failure status. |
| 5 | `justification` | One sentence saying why this site may discard its diagnostic. Mandatory. |
| 6 | `citation` | The reviewed record that admitted the entry. Mandatory, and never `-`. |

Field six is never `-` because a discard with no incident behind it is an
unexamined discard. For the seed batch the citation is
`PLAN-skill-preflight-checks.md#issue-17`, the reviewed decision that adjudicated
all 23 at once; the entries carrying `shirabe#279` are the ones whose discard
class is the incident's own, listed under "Flagged for remediation" below. A new
entry cites the issue that motivated it, not the seed citation.

Free text in field five is not a contradiction of the argument that kept a
justification field out of `requires.tsv`. This file is on the review path -- CI
joins on fields one through three and a human reads five and six -- and it is
never read at skill load, never rendered into model context, and never a source
of truth for behaviour. Its whole job is to make a human judgment reviewable,
which is what free text is for.

### The join key

The key is `path` plus the **trimmed source line**, plus the occurrence count.
Never `path:lineno`.

Line numbers drift whenever anything above a site is edited, so a `path:lineno`
key would break the build on unrelated changes and, worse, a stale key would go
on silencing whichever site had drifted into that line number. Keying on the
trimmed line tolerates reindentation but breaks on an edit to the command itself,
which is correct: changing what the command does should force the exemption back
through review. The count field catches a third byte-identical copy appearing
where two were adjudicated.

## What the scan considers in scope

Four redirect shapes:

```text
2>/dev/null
&>/dev/null
2>&1 >/dev/null
>/dev/null 2>&1
```

The fourth is in scope because the rule's own text forbids redirection to
`/dev/null` in any spelling, and `>/dev/null 2>&1` discards stderr just as
completely as the other three. It matches six more real sites. A bare
`>/dev/null` with no stderr clause is **not** in scope: only stdout is discarded
and the diagnostic still reaches the reader.

Plus a second arm: a `VAR=$(...)` capture of a declared tool's output where
`$VAR` is never read anywhere in the file. That arm runs against `*.sh` only.
In `.md` templates it false-positives on the first file it touches --
`skills/execute/koto-templates/execute.md` assigns `CASCADE_STATUS` and never
references it in shell, but the surrounding prose instructs the agent to submit
it, so the consumer is an agent reading prose rather than a shell reading a
variable.

Tool names come from the declarations rather than a hardcoded list, so the
scan's scope grows with them. Today: `gh`, `git`, `jq`, `koto`, `python3`,
`shirabe`.

Test files are out of scope: `*_test.sh` and anything under an `evals/`
directory.

The declared-tool test never sees a `path:lineno:` prefix. Where a `grep -n`
pipeline would have to strip it, the scan reads each file directly and tests
the source line alone, which is the same guarantee obtained by construction.

Either way the guarantee is required, not cosmetic:
`skills/work-on/koto-templates/work-on.md`'s `go test ./... 2>/dev/null` is
charged to `koto` the moment the prefix is in the text, because `koto` appears
in the directory name `skills/work-on/koto-templates/`. Since the enumeration
must itself cover `koto-templates/`, that false-positive class is guaranteed to
recur, and the test suite asserts that exact line is not charged to `koto`
while a real `koto` call in the same directory still is.

### Tools held in a variable

A script that has to locate a tool usually resolves it first and calls it
through a variable: `KOTO=${KOTO_BIN:-koto}`, then
`"$KOTO" status "$id" 2>/dev/null`. That call has no literal name for the tool
test to find, so the scan reads each file's assignments (never running them)
and charges a variable to the declared tool its value resolves to. Both arms
see it.

Traced, on a line whose first word is the assignment, with an optional
`export`, `readonly`, `local`, `declare` or `typeset` and optional quotes around
the value:

```text
VAR=tool                      VAR=$(command -v tool)
VAR=${OTHER:-tool}            VAR=${OTHER:-$(command -v tool)}
VAR=/any/path/tool            VAR="$DIR/tool"
```

`$(which tool)`, the backtick spellings and a probe with its own `2>/dev/null`
count like `$(command -v tool)`. The `:=`, `-` and `=` expansions count like
`:-`, and `OTHER` is charged along with `VAR`, since it's the override for the
same tool. A value that only
contains the name, such as `koto-open.sh` or `"koto failed"`, isn't a binding.

A file also takes the bindings of each file it sources with `.` or `source`,
recursively. That's how `board-record.sh` gets `KOTO` from `state-common.sh`
through `board-lib.sh`. The path has to be literal, or start with one `$NAME/`,
`${NAME}/`, `$(dirname "$0")/` or `$(dirname "${BASH_SOURCE[0]}")/`, which is
read as the sourcing file's directory, quoted or not. The path ends at the
first operator after it, so `. "$HERE/lib.sh" || exit 2` is followed. A sourced
file's `local` bindings stay inside its functions. A sourced file outside the
scanned tree, a lib under `scripts/` for instance, lends its bindings all the
same. It is read for them, never reported as a site.

A variable is charged only at command position: `$VAR`, `"$VAR"`, `${VAR}` or
`"${VAR}"` at the start of the line, after a case arm's pattern that starts
the line or follows `in`, `;;`, `;&` or `;;&`
(`case "$x" in a|b) "$VAR" ...`), or after `;`, `&`, `|`, `(`, `{`, `!`, a
backtick, or one of `then`, `do`, `else`, `elif`, `if`, `while`, `until`,
`exec`, `command` and `time`. A variable holding the name as data isn't
charged: an argument, a message, or a directory with a path after it
(`"$CACHE"/run.sh`).
`command -v "$VAR"` falls under the carve-out below.

These aren't traced:

- a copy (`A=$B`), an array element, indirect expansion, `eval`, or a nested
  default
- an assignment that isn't the line's first word, such as
  `[ -n "$X" ] || K=koto` or `local a K=koto`
- a variable set only by a caller or the environment
- a call behind an env prefix (`FOO=1 "$VAR" ...`) or a runner such as
  `timeout`, `xargs`, `env`, `nohup` or `sudo`
- a tool wrapped in a shell function
- a case arm whose pattern is quoted or expands a variable
- a source path spelled any other way

When the scan landed, no discard in `skills/` called a declared tool through
any of these. A probe that charged every variable at command position
on a discard line found only sites the trace already covers. A site that needs
one of these shapes is enumerated by hand, with a comment line in the record
block naming the shape. Any traced assignment charges its variable, even when
another assignment in the same file gives it a different value. Command
position is judged without tracking quotes, so a separator inside a string
(`echo "a; $K"`) can charge a name held as data. That errs toward a finding,
which a record or a rewrite settles, never toward a miss.

Like a literal call, a variable-held call is judged on the line holding the
redirect. A command continued with `\` whose redirect sits on a later line
than the tool isn't seen, whether the tool is named or held.

The trace applies wherever the scan runs, and by default that's `skills/`.
Scripts under `scripts/`, such as `scripts/assert-koto-floor.sh`, are outside
the default scan for literal and held calls alike. Pointing the scan at them
brings their variable-held calls in too.

### The `command -v` carve-out

`command -v <tool>` is carved out, measured rather than assumed:

```text
$ out=$(command -v definitely-not-a-real-tool 2>&1); echo "${#out} $?"
0 1
```

Zero bytes across both streams, exit 1. There is no diagnostic to discard, and
the declared tool is never executed -- `command -v` is a shell builtin doing a
PATH lookup. Every such site in the corpus already tests the exit status.

Folding the eight of them in would add entries whose "exit status the fallback is
entered on" is a property of the shell rather than of the tool, diluting a list
whose only value is that a reader can scan it for genuine risk.

The carve-out is applied by removing `command -v <word>` from a line before the
declared-tool test, not by dropping the whole line. A line that probes with
`command -v` and then calls the tool for real still counts.

## The seed arithmetic

Reproduced against the tree as it stands, not carried over from the design:

| Step | Count |
|---|---|
| Raw hits for the four shapes under `skills/` | 181 |
| ... excluding test files (`*_test.sh`, `evals/`) | 43 |
| ... naming a declared tool, after stripping `path:lineno:` | 31 |
| ... of which the three shapes the acceptance criteria name | 25 |
| ... after the `command -v` carve-out (8 sites) | **23** |
| Distinct records after the trimmed-line join key | **21** |

The design predicted 33 / 25 / 23 for the three middle rows and 22 records. The
first two differ by exactly the two `koto context get` sites in
`skills/execute/koto-templates/execute.md` that were remediated before this file
was written: they now redirect stderr to `$SETTLED_ERR` and check `$?`, so they
fall outside every in-scope shape by construction. 33 - 2 = 31 and 25 - 2 = 23,
so the entry count lands where the design put it.

The record count does not: the design expected one pair of byte-identical lines
and there are two, both in `skills/work-on/scripts/run-cascade.sh` -- the
`finding_count` capture at two call sites and `git add "$target" 2>/dev/null || true`
in the `transition_prd` and `transition_brief` arms. 23 entries in 21 records,
not 22. Recorded here rather than reconciled, because the count field carries
the difference and the scan checks it.

The seed is a seed and the tree moved under it. The scan reports its own
current numbers on every clean run -- **26 sites in 24 records** as this is
written -- and that line, not the table above, is the figure to trust. The
three-site delta is the whole of it: `shirabe validate` absorbed the
upstream-status rule and `skills/plan/scripts/validate-plan.sh` went with its
two records; `skills/execute/koto-templates/execute.md` gained the
`koto context add` write and its verifying read; `skills/plan/scripts/plan-to-tasks.sh`
gained the repo-root probe and the outline-envelope parse; and
`skills/scope/scripts/check-citations.sh` arrived with a work-tree predicate.
The paragraph in `execute.md` that *explains* those two koto redirects is not
among them: it names the shape inside backticks and runs nothing, which the
redirect arm's inline-code carve-out is there to tell apart.

## Flagged for remediation

Five entries are enumerated so the tree is green today, and are flagged as
discards that should be fixed rather than kept. (A sixth, `execute.md`'s
`git push -u origin impl/<slug> 2>/dev/null || true`, is fixed: the push now
goes through `skills/execute/scripts/push-and-record.sh`, which reports a failed
push with its own exit code and records nothing.) Each carries `shirabe#279` in
field six because each is that incident's own class: a failure that is silenced
and then reported as success.

`shirabe#279` is **closed** — it was fixed at its own call site. The citation
names the canonical example of the class, not open work. A reader chasing an
entry here should read #279 for what the failure looks like and then fix the
site named in field one, which is still live.

- **`skills/work-on/scripts/run-cascade.sh`, the three `git add` sites.** All
  three append to `STAGED_FILES` and record the step as `"ok"` unconditionally.
  A `git add` that fails leaves the file unstaged while the cascade reports it
  staged and goes on to commit, so the artifact silently does not land. The
  `|| true` is doing nothing for the caller that checking the status would not
  do better.
- **`skills/plan/scripts/create-issues-batch.sh`, the milestone lookup.** A
  `gh api` failure (auth, rate limit, network) yields an empty
  `existing_milestone`, and the very next branch creates a milestone that may
  already exist. The fallback is not equivalent work.
- **`skills/plan/scripts/create-issues-batch.sh`, the Pass 3 body fetch.** A
  failed fetch yields an empty `current_body`, `check_placeholders ""` passes,
  and the placeholder-validation pass reports clean on an issue it never read.

## Records

```tsv
#schema	tool-diagnostic-discards/v1
#path	command	count	exit-status	justification	citation
skills/execute/koto-templates/execute.md	git checkout impl/{{PLAN_SLUG}} 2>/dev/null || git checkout -b impl/{{PLAN_SLUG}}	1	1	Branch-existence probe: exit 1 means the shared branch does not exist yet and the -b fallback creates it, reaching the same end state. Re-adjudicated unchanged when the shell-derived slug became the declared {{PLAN_SLUG}}.	DESIGN-koto-default-action-adoption.md#c5
skills/coordinate/scripts/board-lib.sh	"$KOTO" context exists "$child" review_round.json </dev/null >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate: exit 1 is the worker that recorded no round there, which falls through to the round its report carried; rc is captured and any other status returns 2 with its own error naming koto's status, so the tick reads again.	shirabe#1114
skills/execute/scripts/record-settled-branch.sh	DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)	1	1	resolving the default branch is a probe whose failure is the ordinary case: refs/remotes/origin/HEAD is absent in a clone that never fetched it. The empty result is handled by ${DEFAULT:-main} and by main and master being named literally in the same case statement, so a failed resolution cannot leave the default-branch refusal satisfied by every branch.	DESIGN-koto-default-action-adoption.md#c2
skills/work-on/scripts/run-cascade.sh	state=$(gh issue view "$number" --repo "$owner/$repo" --json state --jq '.state' 2>/dev/null) || {	1	1	Handled: the block logs a named warning and returns 1, so an unreachable issue is reported rather than treated as closed.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/scripts/run-cascade.sh	finding_count=$(jq -r '.findings | length' <<< "$output" 2>/dev/null) || finding_count=""	2	5	The captured output is not guaranteed to be JSON; a parse failure sets the empty sentinel the very next conditional tests for.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/scripts/run-cascade.sh	REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {	1	128	Handled: the block emits a structured cascade_status=skipped error naming "not a git repository" and exits 1.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/scripts/run-cascade.sh	git add "$new_path" 2>/dev/null || git add "$target" 2>/dev/null || true	1	128	Post-move and pre-move paths are both tried because only one exists, but the trailing guard also swallows the case where neither stages.	shirabe#279
skills/work-on/scripts/run-cascade.sh	git add "$target" 2>/dev/null || true	2	128	Staging a path finalize-chain just reported, where a failure is silenced and the step is still recorded ok.	shirabe#279
skills/work-on/scripts/run-cascade.sh	errmsg=$(echo "$FINALIZE_ERR" | jq -r '.error // empty' 2>/dev/null) || errmsg=""	1	5	The captured stderr may not be JSON; the empty sentinel routes to the head -1 fallback that prints the raw text instead.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/build-dependency-graph.sh	if ! echo "$input" | jq -e 'type == "array"' >/dev/null 2>&1; then	1	1,5	Used as a predicate over untrusted stdin; the branch emits its own json_error naming the expected shape.	PLAN-skill-preflight-checks.md#issue-17
skills/deliver/scripts/deliver-open.sh	if LISTING=$("$KOTO" session list </dev/null 2>/dev/null); then	1	1,2	The listing only decides whether the probe can be skipped, and any failure leaves LISTED=unknown so the probe and the open run exactly as they did before the listing existed, each reporting koto's own refusals.	shirabe#1278
skills/deliver/scripts/deliver-open.sh	err=$("$KOTO" session cleanup "$SESSION" </dev/null 2>&1 >/dev/null)	1	0	Only stdout is discarded: stderr is captured and printed back in full on any failure, and after a successful cleanup only koto's retention warning about a session this invocation's own probe made is dropped, because it would name a seconds-old session as if a kept one had been lost.	shirabe#1278
skills/plan/scripts/plan-to-tasks.sh	root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""	1	128	Repo-root probe inside resolve_shirabe_bin: outside a repo there is no target/ to look in, the empty sentinel skips both probes, and the caller's die_input names every way to supply the binary.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/plan-to-tasks.sh	schema=$(printf '%s' "$envelope" | jq -r '.schema // empty' 2>/dev/null) || schema=""	1	5	The envelope is not guaranteed to be JSON; the empty sentinel fails the very next schema comparison, which reports the version skew by name.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/create-issues-batch.sh	repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)	1	1	Handled: the next conditional tests for an empty result, logs a named error and exits 1.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/create-issues-batch.sh	2>/dev/null | jq -r --arg title "$MILESTONE" '.[] | select(.title == $title) | .number' 2>/dev/null || true)	1	1,5	Milestone-existence probe, but an API failure is indistinguishable from absence and the fallback creates a possibly-duplicate milestone.	shirabe#279
skills/plan/scripts/create-issues-batch.sh	if gh issue edit "$github_number" --body "$body" >/dev/null 2>&1; then	1	1	Status is tested and the else branch logs the failed issue number, though gh's own reason for the failure is lost.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/create-issues-batch.sh	current_body=$(gh issue view "$github_number" --json body --jq '.body' 2>/dev/null || true)	1	1	A failed fetch yields an empty body that the placeholder check then passes, reporting clean on an issue never read.	shirabe#279
skills/plan/scripts/render-template.sh	if ! echo "$input" | jq -e '.' >/dev/null 2>&1; then	1	5	Parse predicate over untrusted stdin; the branch emits its own json_error naming invalid JSON.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/render-template.sh	if ! echo "$input" | jq -e '.complexity' >/dev/null 2>&1; then	1	1	Field-presence predicate; jq exits 1 on a null result and the branch names the missing field.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/render-template.sh	if ! echo "$input" | jq -e '.goal' >/dev/null 2>&1; then	1	1	Field-presence predicate; jq exits 1 on a null result and the branch names the missing field.	PLAN-skill-preflight-checks.md#issue-17
skills/scope/scripts/check-citations.sh	git rev-parse --is-inside-work-tree >/dev/null 2>&1 \	1	128	Work-tree predicate guarding the git grep sweep below; the || branch calls die_incomplete "not inside a git work tree", which is the actionable form of what was discarded.	PLAN-skill-preflight-checks.md#issue-17
skills/release/scripts/release-state.sh	last_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")	1	128	A repo with no matching tag yet is the expected first-release case and the empty string is the value that path wants.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/references/scripts/extract-context.sh	if ! gh auth status &>/dev/null; then	1	1	Authentication predicate; the branch emits json_failed "gh CLI not authenticated", which is the actionable form of what was discarded.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/references/scripts/extract-context.sh	issue_body=$(gh issue view "$issue" ${repo_args[@]+"${repo_args[@]}"} --json body --jq '.body' 2>/dev/null) || {	1	1	Handled: the block emits json_failed "Failed to fetch issue", naming the issue's repository when it is another one, and exits, so the caller gets a structured failure. Re-adjudicated unchanged when the call gained --repo for an issue in another repository.	shirabe#1030
# shirabe#304 -- /work-on retry clearing. Each retry path removes the keys
# its re-entry re-reads. Both redirects are deliberate: the block prints its
# own diagnostic, and `exists` is read for its exit status, not its text.
skills/work-on/references/phases/phase-4a-scrutiny.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4a-scrutiny.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4b-review.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4b-review.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4c-qa.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4c-qa.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4d-light.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4d-light.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-3-analysis.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-3-analysis.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4-implementation.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4-implementation.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-5-finalization.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-5-finalization.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/coordinate/scripts/reconcile-check.sh	b=$(jq -r --arg p "$1" '.blobs[$p] // (if .truncated then "?" else "absent" end)' "$TREE" 2>/dev/null) || return 1	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-check.sh	OUT=$(rd_deadline "$DEADLINE" koto request get "$REQ" </dev/null 2>/dev/null)	1	non-zero,124	A failed or late read of GitHub, the host or koto becomes a not_verified fact, a refusal or a stop carrying its own reason; the tool text is replaced by that reason and never taken as a result.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-check.sh	WROOT=$(printf '%s' "$OUT" | jq -r '[.[].path | select(type == "string") | sub("/[^/]+$"; "")] | unique | if length == 1 then .[0] else empty end' 2>/dev/null)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-deps.sh	pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null	1	1	Stopping the children of a process that may already have ended: no match (exit 1) is the ordinary case, and the kill beside it handles the process itself.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-deps.sh	pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null	1	1	Stopping the children of a process that may already have ended: no match (exit 1) is the ordinary case, and the kill beside it handles the process itself.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	fact=$(jq -c '.' "$R/$id.out" 2>/dev/null | head -1)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	if [ "$clipped" = 1 ] && printf '%s' "$fact" | jq -e '.status != "ok" and ((.reason // "") | test("timed out"))' >/dev/null 2>&1; then	1	1,2,4,5	The jq test is the validation of untrusted JSON: a false result or a parse error is the expected not-this-shape outcome, handled by the branch it guards.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	if [ -z "$fact" ] || ! printf '%s' "$fact" | jq -e '(.kind | type) == "string" and (.status | type) == "string"' >/dev/null 2>&1; then	1	1,2,4,5	The jq test is the validation of untrusted JSON: a false result or a parse error is the expected not-this-shape outcome, handled by the branch it guards.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	koto context get "$SESSION" reconcile/report.json > "$T/back.json" 2>/dev/null || die "the stored report can't be read back"	1	non-zero,124	A failed or late read of GitHub, the host or koto becomes a not_verified fact, a refusal or a stop carrying its own reason; the tool text is replaced by that reason and never taken as a result.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	pkill -TERM -P "${RUN_PIDS[$i]}" 2>/dev/null; kill -TERM "${RUN_PIDS[$i]}" 2>/dev/null	1	1	Stopping the children of a process that may already have ended: no match (exit 1) is the ordinary case, and the kill beside it handles the process itself.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-pass.sh	REASON=$(printf '%s' "$REC" | jq -r '.reason // empty' 2>/dev/null)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-read.sh	NAME=$(printf '%s' "$FACTS" | jq -r '.name // empty' 2>/dev/null)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-read.sh	REPO=$(printf '%s' "$FACTS" | jq -r '.repo // empty' 2>/dev/null)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-read.sh	SCOPE=$(printf '%s' "$FACTS" | jq -r '.scope // empty' 2>/dev/null)	1	2,4,5	Reading a field from JSON this script or its own read produced: unparseable input leaves the value empty, and the value is then checked against a fixed pattern before any use.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-read.sh	jq -c '. + {unparseable: []}' "$T/view.json" > "$T/record.json" 2>/dev/null \	1	2,5	The view is the state this script's own deadline-bounded session read just wrote; jq failing on it refuses the read as failed (5), naming the record's response as unreadable, so nothing is reported from it.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-report-get.sh	jq -e '.schema == "coordinate-reconcile-report/v1"' "$T/report.json" >/dev/null 2>&1 \	1	1,2,4,5	The jq test is the validation of untrusted JSON: a false result or a parse error is the expected not-this-shape outcome, handled by the branch it guards.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-report-get.sh	koto context get "$SESSION" "$KEY" > "$T/report.json" 2>/dev/null || fail 2 "context key $KEY can't be read"	1	non-zero,124	A failed or late read of GitHub, the host or koto becomes a not_verified fact, a refusal or a stop carrying its own reason; the tool text is replaced by that reason and never taken as a result.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-report.sh	SCHEMA=$(printf '%s' "$INPUT" | jq -r '.schema? // empty' 2>/dev/null)	1	2,4,5	Reading the schema field of the input document: unparseable input leaves it empty, and the script then refuses the input with exit 65 as not a facts document.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/reconcile-report.sh	if ! printf '%s' "$INPUT" | jq -e '(.header | type) == "object" and ([.changes, .holdings, .waiting, .nowhere_else, .side_effects, .deferrals, .not_verified] | all(type == "array"))' >/dev/null 2>&1; then	1	1,2,4,5	The jq test is the validation of untrusted JSON: a false result or a parse error is the expected not-this-shape outcome, handled by the branch it guards.	DESIGN-coordinate-reconcile.md (a read that fails or runs late is not verified)
skills/coordinate/scripts/unit-cost.sh	uc_jq() { jq "$@" 2>/dev/null; }	1	1,2,4,5	The cost capture's one jq wrapper over files the worker or GitHub wrote (koto state, ledgers, transcripts, run lists): a jq message can quote that input, which must never reach the one stderr line the teardown pass prints, so every caller acts on the status instead and turns a failure into that figure's invalid input.	skills/coordinate/references/unit-cost.md (Evidence, not proof: the capture reads its sources as untrusted input)
# DESIGN-resume-convention.md Decision 2 -- /scope's state and prior-run facts
# live as session keys, and the resume scripts read them as predicates: exit 1
# is the ordinary key-absent row outcome, any other status is captured and
# turned into the probe's cannot-tell or the caller's own refusal, and the
# publish-side removal warns and defers to cleanup rather than failing a
# publish that already succeeded.
skills/scope/scripts/check-recorded-intent.sh	"$KOTO" context exists "$SESSION" work/prior-run.md >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate: exit 1 is the no-prior-run row; rc is captured and any status outside 0 and 1 is refused by the branch below, which dies with its own error naming the command and status.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/check-recorded-intent.sh	"$KOTO" context exists "$SESSION" work/state.md >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate: exit 1 is the no-state row; rc is captured and any status outside 0 and 1 is refused by the branch below, which dies with its own error naming the command and status.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/check-recorded-intent.sh	PRIOR=$("$KOTO" context get "$SESSION" work/prior-run.md 2>/dev/null) \	1	non-zero	The key was proved present one line above; a read failing anyway falls to the || branch, which dies with its own error naming the unreadable key rather than treating the empty value as a recorded intent.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/publish-scoping-pr.sh	koto context remove "${KOTO_TICK_SESSION:-$SESSION}" work/prior-run.md >/dev/null 2>&1 \	1	non-zero	The PR exists by this line, so a failed removal must not report the publish as failed: the || branch prints its own warning naming the key, and the cleanup phase removes it too.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resolve-intent.sh	"$KOTO" context exists "$SESSION" "$1" >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate over the two state keys: exit 1 is the absent-key fallthrough to the next intent source; rc is captured and other statuses surface as the script's own cannot-read error.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resolve-intent.sh	out=$("$KOTO" context get "$SESSION" "$1" 2>/dev/null && printf '.') \	1	non-zero	The read follows a passed existence check; the || branch reports a read that fails anyway as the script's own error instead of parsing an empty document.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resume-probe.sh	"$KOTO" context exists "$SESSION" "$STATE" >/dev/null 2>&1 &	1	1,127	Key-existence predicate for work/state.md, run as a background job beside the other lookups: its status is collected with wait and read by key_exists at the ladder's own point, where exits 1 and 127 are the no-row outcome (127 because a missing koto means no session can exist) and any other status is the probe's cannot-tell [2], never a row. Re-adjudicated unchanged in meaning when the lookups began running together (shirabe#1396).	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resume-probe.sh	"$KOTO" context exists "$SESSION" "$PRIOR" >/dev/null 2>&1 &	1	1,127	Key-existence predicate for work/prior-run.md, run as a background job beside the other lookups: its status is collected with wait and read by key_exists at the ladder's own point, where exits 1 and 127 are the no-row outcome (127 because a missing koto means no session can exist) and any other status is the probe's cannot-tell [2], never a row. Re-adjudicated unchanged in meaning when the lookups began running together (shirabe#1396).	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resume-probe.sh	"$KOTO" context exists "$HANDOFF_SESSION" "$HANDOFF" >/dev/null 2>&1 &	1	1,127	Key-existence predicate for the /explore handoff (Slot 7), run as a background job beside the other lookups: its status is collected with wait and read by key_exists at the ladder's own point, where exits 1 and 127 are the no-row outcome (127 because a missing koto means no session can exist) and any other status is the probe's cannot-tell [2], never a row. Re-adjudicated unchanged in meaning when the lookups began running together (shirabe#1396).	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
skills/scope/scripts/resume-probe.sh	out=$("$KOTO" context get "$1" "$2" 2>/dev/null && printf '.') || return 1	1	non-zero	Key read used as a predicate with the trailing dot guarding trailing-newline loss; each caller handles the failure itself: an unreadable work/state.md fires the malformed-state row directly, and an unreadable work/prior-run.md yields the same no-row outcome the absent key takes.	DESIGN-resume-convention.md#d2 (finished-run facts travel in keys, read as status-tested predicates)
# The coordinate engine suites' shared setup: helpers that sat in
# coordinate_engine_test.sh, out of scope as a test file, until the suite was
# split into four parts sourcing one testdata file. Test-only reads whose empty
# result is the value the calling assertion compares.
skills/coordinate/scripts/testdata/coordinate-engine-lib.sh	now_at() { koto status "$S" 2>/dev/null | jq -r '.current_state // .state // empty'; }	1	non-zero	Test helper: a run koto cannot report reads as an empty state. Where a case asserts on it, its eq names the state it wanted against the empty one it got; where a tick loop polls it, an empty state never matches the state the loop waits for, so the loop runs to its bound and the eq after it fails.	references/tool-diagnostic-discards.md (test files are out of scope; moved from coordinate_engine_test.sh)
skills/coordinate/scripts/testdata/coordinate-engine-lib.sh	pickf() { (cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null); }	1	1	Test helper: an absent pick fact reads as empty, which the case's assertion over it fails on and names, so the discard hides no failure.	references/tool-diagnostic-discards.md (test files are out of scope; moved from coordinate_engine_test.sh)
# shirabe resume-import (issue 3 of the coordinator session record): the
# opener's import and resume decision, and the closing report's host facts. Each
# read's failure lands on a refusal, a fallback the next line names, or a carry
# that keeps the record.
skills/coordinate/scripts/coordinate-open.sh	COMPILED=$("$KOTO" template compile "$TEMPLATE" 2>/dev/null </dev/null) || COMPILED=	2	non-zero	A template koto can't compile leaves the hash empty, and the next line ends the start as failed=template_compile with its own message before anything is opened or imported.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
skills/coordinate/scripts/coordinate-open.sh	CODE=$(jq -r '.error.code // empty' "$DIR/out" 2>/dev/null)	1	2,5	Reads the code from koto's error output after the import already failed; output that isn't koto's JSON error reads as no code, and the next line refuses as import_failed with koto's exit status.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
skills/coordinate/scripts/coordinate-open.sh	[ -n "$TEXT" ] || TEXT=$(jq -r '.error.message // empty' "$DIR/out" 2>/dev/null | head -c 400)	1	2,5	Reads koto's message only when the wording file has none for the code; output that isn't koto's JSON error falls back to naming koto's exit status, and the refusal line is printed either way.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
skills/coordinate/scripts/coordinate-open.sh	AT=$("$KOTO" status "$IMPORT" 2>/dev/null </dev/null | jq -r '.current_state // empty' 2>/dev/null)	1	non-zero	Runs after the import succeeded, only to say where the run stands: an unreadable state prints state=unknown and a note that the run reconciles when it next reaches wait, whose own check sends it through moved.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
skills/coordinate/scripts/coordinate-open.sh	HELP=$("$KOTO" context list --help < /dev/null 2>/dev/null) || HELP=	1	non-zero	A feature probe of the installed koto: a koto without `context list` or its `--prefix` flag failing here is the expected outcome, read as that feature missing, and the start is refused as store-unsupported, naming it; the help text is never a result.	DESIGN-coordinator-record-teardown.md (the koto feature probe moves into coordinate-open.sh as the store-unsupported refusal)
skills/coordinate/scripts/coordinate-open.sh	"$KOTO" cancel "$SESSION" </dev/null >/dev/null 2>&1 || echo "coordinate-open: $SESSION couldn't be cancelled; cancel it before starting again" >&2	1	non-zero	Cancelling the run this start just opened, on the way out of a start the legacy importer stopped: the stop's own reason is what the operator reads, and a cancel that fails says so on its own line naming the run to cancel.	DESIGN-coordinator-record-teardown.md (The legacy importer: a refusal stops the start)
skills/coordinate/scripts/coordinate-open.sh	[ "$("$KOTO" context get "$IMPORT" coord/source.json < /dev/null 2>/dev/null | jq -r '.source // empty' 2>/dev/null)" = session ] \	1	non-zero,2,4,5	Whether the imported run's find recorded the session: a key that is absent or unreadable, or JSON that doesn't parse, reads as not recorded, and the import is refused as session-source with its own reason.	DESIGN-coordinator-session-record.md (Decision 6: a run whose find never ran is no resume candidate)
skills/coordinate/scripts/coordinate-report.sh	if [ -n "$(printf '%s' "$PAYLOAD" | jq -r '.source_session // empty' 2>/dev/null)" ]; then	1	2,5	The host facts come from state-read.sh --host or default to {}; facts that aren't JSON print no import lines, the report's other lines are unchanged, and the reconcile report names the source independently.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
skills/coordinate/scripts/state-read.sh	0) src=$(jq -r '.source // ""' "$d/src" 2>/dev/null) ;;	1	2,5	coord/source.json is written only by the find, through jq; a value jq can't parse reads as a run not on the session store, the same as an absent key, so the start opens a new run as with no session here rather than resuming it.	DESIGN-coordinator-session-record.md (Decision 6: resume, carry and import; shirabe#767)
# A coordinator's successor continues its run: run-facts treats a successor
# holding its carried record as found, and the liveness probe reads Claude job
# state files and a run's koto log. Each discard below is a presence or parse
# probe whose failure has one reading, stated beside it.
skills/coordinate/scripts/coord-log.sh	"$KOTO" context exists "$SESSION" koto/superseded-carry-complete </dev/null >/dev/null 2>&1 \	1	non-zero	Only asked once the run's own find hasn't run: a successor without the carry's completion marker hasn't found a record, so run-facts exits 1 as it did before the takeover existed.	DESIGN-coordinate-successor-continues.md (Decision 1: the successor continues through koto's fence)
skills/coordinate/scripts/coord-log.sh	&& "$KOTO" context exists "$SESSION" record/meta </dev/null >/dev/null 2>&1 || exit 1	1	non-zero	The second half of the same probe: a carried run without record/meta holds no record, and run-facts exits 1, read as not found.	DESIGN-coordinate-successor-continues.md (Decision 1: the successor continues through koto's fence)
skills/coordinate/scripts/dispatch-common.sh	[ "$(jq -r '.sessionId // "" | strings' "$f" 2>/dev/null)" = "$sid" ] || continue	1	2,5	A Claude job state file that is unreadable or not JSON names no session, so the search goes on to the next job; the liveness probe then falls back to the run's koto log.	DESIGN-coordinate-successor-continues.md (the liveness probe)
skills/coordinate/scripts/dispatch-common.sh	[ "$(jq -r '.name // "" | strings' "$f" 2>/dev/null)" = "$name" ] || continue	1	2,5	The same search by name: a state file that can't be read names no one, and the search goes on.	DESIGN-coordinate-successor-continues.md (the liveness probe)
skills/coordinate/scripts/dispatch-common.sh	name=$(jq -r '.name // "" | strings' "$home/jobs/$job/state.json" 2>/dev/null) || return 1	1	2,5	The caller's own job state file: one that can't be read gives no name, dc_claude_name returns 1, and the opener resumes rather than taking over, saying so on stderr.	DESIGN-coordinate-successor-continues.md (the liveness probe)
skills/coordinate/scripts/dispatch-common.sh	if jq -e 'select(.type == "workflow_cancelled")' "$log" >/dev/null 2>&1; then	1	1,5	Whether the run's koto log records a cancel: no match is the common answer, and a line jq can't parse reads as not cancelled, after which the job and event-age checks still decide.	DESIGN-coordinate-successor-continues.md (the liveness probe)
skills/coordinate/scripts/dispatch-common.sh	last=$(tail -n 1 "$log" | jq -r '.timestamp // empty' 2>/dev/null)	1	5	The log's last event time: a last line that isn't JSON leaves it empty, and the next line returns 2 saying the log has no timed event, which the takeover reports as predecessor_stopped=no.	DESIGN-coordinate-successor-continues.md (the liveness probe)
skills/coordinate/scripts/dispatch-common.sh	at=$(jq -rn --arg t "$last" '$t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null) \	2	5	A timestamp jq can't parse as ISO 8601: the continuation returns 2 naming the unreadable time, which the takeover reports as predecessor_stopped=no.	DESIGN-coordinate-successor-continues.md (the liveness probe)
# The plan/v2 outline gate reads a plan through `shirabe plan outlines`. A
# shirabe older than plan/v2 cannot read a step plan, which is the failure
# these two lines expect: the first read keeps its stdout clean for jq, and
# on failure the second read captures the first stderr line for the refusal.
skills/work-on/scripts/step-detail-check.sh	if ! ENVELOPE=$("$BIN" plan outlines "$REAL" 2>/dev/null); then	1	non-zero	The read that feeds jq keeps stderr out of the envelope; a shirabe that cannot read the plan (an older one on a step plan) takes the branch below, which reads again for the diagnostic and refuses with exit 2 quoting it.	DESIGN-functional-steps.md (step-detail-check.sh: a step plan's work waits until its step is detailed, and the check refuses a plan it cannot read)
skills/work-on/scripts/step-detail-check.sh	why=$("$BIN" plan outlines "$REAL" 2>&1 >/dev/null | sed -n 1p)	1	non-zero	Only stdout is discarded: stderr goes into the capture, and its first line, control characters stripped and cut to 240 characters, is quoted in the refusal the caller sees.	DESIGN-functional-steps.md (step-detail-check.sh: a step plan's work waits until its step is detailed, and the check refuses a plan it cannot read)
# A worker reports to its run's newest member: resolve-coordinator.sh walks
# the supersede chain and reads the member's record, and the handover lists
# each untold worker's koto sessions. Each read below that fails has one
# reading, stated beside it, and none is a value the caller acts on unchecked.
skills/coordinate/scripts/dispatch-common.sh	next=$(jq -r 'select(.type == "session_superseded") | .payload.by // "" | strings' "$log" 2>/dev/null | tail -n 1) || return 1	1	2,5	A run's koto log jq can't parse fails the pipeline under every caller's pipefail, so dc_newest_member returns 1, the chain can't be read, and the worker reports to the address its brief names.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/handover-classify.sh	KS=$("$KOTO" session list --execution-dir "$IPATH" </dev/null 2>/dev/null \	1	non-zero	A session list that fails for a worker's instance stops the handover with exit 2 naming the instance, so no worker is classified from a read that didn't happen.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	dir=$("$KOTO" session dir "$1" </dev/null 2>/dev/null) || return 1	1	non-zero	A session koto can't find has no directory: key returns 1, the value it feeds is empty, and the resolve exits 1 naming what was missing, so the worker reports to the address its brief names.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	ed=$(head -n 1 "$dir/koto-$1.state.jsonl" 2>/dev/null | jq -r '.execution_dir // "" | strings' 2>/dev/null)	1	non-zero	A log header that can't be read or parsed leaves the execution directory empty, and the context read below runs from the current directory, koto's own default, instead.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	(cd "$ed" && "$KOTO" context get "$1" "$2" </dev/null 2>/dev/null)	1	non-zero	A context key that is absent or unreadable prints nothing, and the caller's check on the value exits 1 naming what was missing, so the worker reports to the address its brief names.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	"$KOTO" context get "$1" "$2" </dev/null 2>/dev/null	1	non-zero	The same read without an execution directory: an absent or unreadable key prints nothing, and the caller's check on the value exits 1 naming what was missing.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	DSCOPE=$(key "$DISP" record/meta | jq -c '.scope // empty' 2>/dev/null)	1	non-zero,2,5	The dispatcher's record/meta, unread or not JSON, leaves the scope empty, and the next line exits 1 saying the dispatcher holds no record naming its run.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	MSCOPE=$(key "$MEMBER" record/meta | jq -c '.scope // empty' 2>/dev/null)	1	non-zero,2,5	The newest member's record/meta, unread or not JSON, leaves the scope empty, and the next line exits 1 saying the member holds no record naming its run.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
skills/coordinate/scripts/resolve-coordinator.sh	ADDR=$(key "$MEMBER" record/run | jq -r '[(. // [])[] | select(.key == "coordinator") | .value][0] // "" | strings' 2>/dev/null)	1	non-zero,2,5	The member's Run section, unread or not JSON, leaves the address empty, which fails the session-name check on the next line, and the resolve exits 1 saying the member names no coordinator address.	DESIGN-coordinate-successor-continues.md (Decision 4: the coordinator address, pending workers and reaching the newest member)
# ps is declared by /coordinate and /work-on (shirabe#1329), which brings
# their existing process reads into scope. Each asks about one pid or the
# process table, and an empty answer or exit 1 is the ordinary "no such
# process" reading the caller is written around. A missing ps now fails the
# load-time check instead of reaching these lines as exit 127.
skills/coordinate/scripts/dispatch-common.sh	if kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1; then	1	1	ps exits 1 when no process holds the pid, which with kill -0 also failing is the answer dc_job_finished asks for: the job is not running, and its state file decides the rest.	shirabe#1329
skills/work-on/scripts/run-verification.sh	case "$(ps -p "$pid" -o command= 2>/dev/null)" in	1	1	A pid that ended between kill -0 and this read prints no command and matches no arm, so lock_live returns 1 and the lock is treated as stale, which is what an ended supervisor means.	shirabe#1329
skills/work-on/scripts/run-verification.sh	ps -A -o pgid= 2>/dev/null | awk -v g="$1" '$1 == g { c++ } END { print c + 0 }'	1	non-zero	A table read that fails counts the group as 0, so the process bound passes that poll while the time limit and the kill of the group after the job still apply.	shirabe#1329
skills/work-on/scripts/test-change.sh	ctl=$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')	1	non-zero	A controlling terminal ps can't read leaves ctl empty, and one_terminal returns 1, so the check fails closed: no evidence of a terminal.	shirabe#1329
skills/work-on/scripts/test-change.sh	ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'	1	1	A pid that has ended gives an empty start time, which differs from the one the lock recorded, so take_lock breaks the lock as its owner's, gone or reused.	shirabe#1329
skills/execute/scripts/execute-open.sh	koto context exists "$session" review_round.json </dev/null >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate before a replace: exit 1 is a session with no round, which carries nothing; rc is captured and any other status marks the read failed, so a replace prints the one warning naming the session and review-round.sh.	shirabe#1367
skills/execute/scripts/execute-open.sh	if koto context get "$session" review_round.json </dev/null >"$ROUND_FILE" 2>/dev/null; then	1	non-zero	A failed read marks the round unread, and only a replace acts on it, by printing the one warning naming the session and review-round.sh; koto's own text would be a second stderr line for the same failure.	shirabe#1367
skills/execute/scripts/execute-open.sh	if ! jq -s -e 'length == 1 and (.[0] | type) == "object"' <"$ROUND_FILE" >/dev/null 2>&1; then	1	non-zero	The shape check of a round about to be carried: any failure, a parse error included, means the value isn't one JSON object, which is reported as the one warning naming the session and review-round.sh, and nothing is written.	shirabe#1367
skills/execute/scripts/execute-open.sh	elif ! koto context add "$session" review_round.json <"$ROUND_FILE" >/dev/null 2>&1; then	1	non-zero	A failed write of the carried round is reported as the one warning naming the session and review-round.sh, and the open goes on with its stdout and exit unchanged; koto's own text would be a second stderr line for the same failure.	shirabe#1367
skills/deliver/scripts/deliver-open.sh	"$KOTO" context exists "$session" review_round.json </dev/null >/dev/null 2>&1 || rc=$?	1	1	Key-existence predicate before the probe: exit 1 is a session with no round, which carries nothing; rc is captured and any other status marks the read failed, so an accepted replace or attach prints the one warning naming the session and review-round.sh.	shirabe#1367
skills/deliver/scripts/deliver-open.sh	if "$KOTO" context get "$session" review_round.json </dev/null >"$ROUND_FILE" 2>/dev/null; then	1	non-zero	A failed read marks the round unread, and only an accepted replace or attach acts on it, by printing the one warning naming the session and review-round.sh; koto's own text would be a second stderr line for the same failure.	shirabe#1367
skills/deliver/scripts/deliver-open.sh	if ! jq -s -e 'length == 1 and (.[0] | type) == "object"' <"$ROUND_FILE" >/dev/null 2>&1; then	1	non-zero	The shape check of a round about to be carried: any failure, a parse error included, means the value isn't one JSON object, which is reported as the one warning naming the session and review-round.sh, and nothing is written.	shirabe#1367
skills/deliver/scripts/deliver-open.sh	elif ! "$KOTO" context add "$session" review_round.json <"$ROUND_FILE" >/dev/null 2>&1; then	1	non-zero	A failed write of the carried round is reported as the one warning naming the session and review-round.sh, and the open goes on with its stdout and exit unchanged; koto's own text would be a second stderr line for the same failure.	shirabe#1367
```

## Running the scan

```text
scripts/check-tool-diagnostic-discards.sh                # scans <repo>/skills
scripts/check-tool-diagnostic-discards.sh PATH [PATH...] # scans files or directories
scripts/check-tool-diagnostic-discards.sh --enumeration FILE PATH
```

Exit 0 when the live sites and the records agree exactly, 1 on any finding, 2 on
a usage error. `.github/workflows/check-tool-diagnostic-discards.yml` runs it on
every PR touching `skills/`, this file, or the script.
