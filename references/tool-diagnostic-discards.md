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
all 23 at once; the six entries carrying `shirabe#279` are the ones whose discard
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
and there are two, both in `skills/execute/scripts/run-cascade.sh` -- the
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

Six entries are enumerated so the tree is green today, and are flagged as
discards that should be fixed rather than kept. Each carries `shirabe#279` in
field six because each is that incident's own class: a failure that is silenced
and then reported as success.

`shirabe#279` is **closed** — it was fixed at its own call site. The citation
names the canonical example of the class, not open work. A reader chasing an
entry here should read #279 for what the failure looks like and then fix the
site named in field one, which is still live.

- **`skills/execute/scripts/run-cascade.sh`, the three `git add` sites.** All
  three append to `STAGED_FILES` and record the step as `"ok"` unconditionally.
  A `git add` that fails leaves the file unstaged while the cascade reports it
  staged and goes on to commit, so the artifact silently does not land. The
  `|| true` is doing nothing for the caller that checking the status would not
  do better.
- **`skills/execute/koto-templates/execute.md`, the `git push` site.** The
  template's own prose two paragraphs below says to "submit `status: blocked`
  with `detail` if either step fails". `|| true` makes that failure unobservable,
  so the instruction cannot be followed.
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
skills/execute/koto-templates/execute.md	git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b impl/$PLAN_SLUG	1	1	Branch-existence probe: exit 1 means the shared branch does not exist yet and the -b fallback creates it, reaching the same end state.	PLAN-skill-preflight-checks.md#issue-17
skills/execute/koto-templates/execute.md	printf '%s' "$SETTLED_BRANCH" | koto context add {{SESSION_NAME}} settled_branch 2>/dev/null	1	1,2	Silences koto's migration-skipped noise on stderr; the read-back comparison on the next line, not the absence of an error, is what decides whether the record took.	shirabe#306
skills/execute/koto-templates/execute.md	RECORDED=$(koto context get {{SESSION_NAME}} settled_branch 2>/dev/null)	1	3	Same noise suppression on the verifying read; koto writes its key-absent payload to stdout, so the string comparison still sees the failure and the block exits 1 with a stdout diagnostic.	shirabe#306
skills/execute/koto-templates/execute.md	git push -u origin impl/$PLAN_SLUG 2>/dev/null || true	1	1,128	Re-run path expects an already-tracked branch to reject the push, but the guard also swallows a real push failure.	shirabe#279
skills/execute/scripts/run-cascade.sh	state=$(gh issue view "$number" --repo "$owner/$repo" --json state --jq '.state' 2>/dev/null) || {	1	1	Handled: the block logs a named warning and returns 1, so an unreachable issue is reported rather than treated as closed.	PLAN-skill-preflight-checks.md#issue-17
skills/execute/scripts/run-cascade.sh	finding_count=$(jq -r '.findings | length' <<< "$output" 2>/dev/null) || finding_count=""	2	5	The captured output is not guaranteed to be JSON; a parse failure sets the empty sentinel the very next conditional tests for.	PLAN-skill-preflight-checks.md#issue-17
skills/execute/scripts/run-cascade.sh	REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {	1	128	Handled: the block emits a structured cascade_status=skipped error naming "not a git repository" and exits 1.	PLAN-skill-preflight-checks.md#issue-17
skills/execute/scripts/run-cascade.sh	git add "$new_path" 2>/dev/null || git add "$target" 2>/dev/null || true	1	128	Post-move and pre-move paths are both tried because only one exists, but the trailing guard also swallows the case where neither stages.	shirabe#279
skills/execute/scripts/run-cascade.sh	git add "$target" 2>/dev/null || true	2	128	Staging a path finalize-chain just reported, where a failure is silenced and the step is still recorded ok.	shirabe#279
skills/execute/scripts/run-cascade.sh	errmsg=$(echo "$FINALIZE_ERR" | jq -r '.error // empty' 2>/dev/null) || errmsg=""	1	5	The captured stderr may not be JSON; the empty sentinel routes to the head -1 fallback that prints the raw text instead.	PLAN-skill-preflight-checks.md#issue-17
skills/plan/scripts/build-dependency-graph.sh	if ! echo "$input" | jq -e 'type == "array"' >/dev/null 2>&1; then	1	1,5	Used as a predicate over untrusted stdin; the branch emits its own json_error naming the expected shape.	PLAN-skill-preflight-checks.md#issue-17
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
skills/release/SKILL.md	LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")	1	128	A repo with no matching tag yet is the expected first-release case and the empty string is the value that path wants.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/references/scripts/extract-context.sh	if ! gh auth status &>/dev/null; then	1	1	Authentication predicate; the branch emits json_failed "gh CLI not authenticated", which is the actionable form of what was discarded.	PLAN-skill-preflight-checks.md#issue-17
skills/work-on/references/scripts/extract-context.sh	issue_body=$(gh issue view "$issue" --json body --jq '.body' 2>/dev/null) || {	1	1	Handled: the block emits json_failed "Failed to fetch issue" and exits, so the caller gets a structured failure.	PLAN-skill-preflight-checks.md#issue-17
# shirabe#304 -- /work-on retry clearing. Each retry path removes the keys
# its re-entry re-reads. Both redirects are deliberate: the block prints its
# own diagnostic, and `exists` is read for its exit status, not its text.
skills/work-on/references/phases/phase-4a-scrutiny.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4a-scrutiny.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4b-review.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4b-review.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4c-qa.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4c-qa.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-3-analysis.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-3-analysis.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-4-implementation.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-4-implementation.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/references/phases/phase-5-finalization.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/references/phases/phase-5-finalization.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
skills/work-on/koto-templates/work-on.md	koto context remove <WF> "$KEY" >/dev/null 2>&1	1	3	the block prints its own diagnostic naming the key and the way out, so koto's text would be duplicate noise; the exit status is captured into REMOVE_STATUS and tested on the next line rather than ignored	shirabe#304
skills/work-on/koto-templates/work-on.md	if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then	1	3	exit status IS the result being read here -- present or absent -- so there is no diagnostic to lose, and koto's stdout would corrupt the block's own output	shirabe#304
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
