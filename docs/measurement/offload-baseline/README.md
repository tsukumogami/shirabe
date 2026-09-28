# Instruction-offload baseline

This directory fixes the starting point for measuring changes to what
shirabe's four koto-templated skills (`/work-on`, `/execute`, `/scope`,
`/deliver`) put in an agent's context. It pins the templates those skills
ship, records how many instruction tokens each skill loads, and defines, as a
provisional proposal, how often a rule is broken while it's preloaded. Later
changes (removing prose, loading references per state, withholding a rule
until a check fails) are measured against it.

Nothing here is loaded by a run. The directory sits outside `skills/` and
`references/`, and pinning changed no template.

| File | Holds |
|------|-------|
| `template-pin.json` | The pinned commit, the koto version, and each template's identity |
| `load-manifest.tsv` | What each skill profile loads, and how often per run |
| `token-baseline.tsv` | The figures: the recount at the pinned commit and at e592501, and the September census reference |
| `../../../scripts/offload-baseline.sh` | `verify-pin` and `count`, the only tooling |

The requirements and the design behind it are in
[PRD-offload-baseline-pin](../../prds/PRD-offload-baseline-pin.md) and
[DESIGN-offload-baseline-pin](../../designs/DESIGN-offload-baseline-pin.md).

## The pinned commit

The pin is taken at `2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10`, which was
`main` when the baseline was taken. It isn't the census commit: the census
was measured at `e5925017d38aa592613b2a809937e530cf2118f9` (e592501), and
shirabe has moved since, so that commit is re-measured here beside the
September figures rather than pinned.

Every template declares `version: "1.0"` and has never bumped it, so the
declared version can't tell two texts apart. Each pin entry identifies its
template twice instead:

- `git_blob`, the git blob hash of the template at the pinned commit, which
  is what shirabe's history matches and doesn't depend on koto;
- `koto_template_hash`, the sha256 of the compiled template that koto
  records as `template_hash` on every session run from it, computed by koto
  0.14.1. This is the key a measurement filters run records on. A koto
  release that changes compiled output changes it without any change in
  shirabe, which is why the blob hash sits beside it.

The five pinned templates are `work-on.md`, `execute.md`,
`execute-coordinated.md`, `scope.md` and `deliver.md`. The koto hashes of all
of them except `execute-coordinated.md` were checked against the
`template_hash` of live sessions started from them.

To check the pin:

```bash
scripts/offload-baseline.sh verify-pin
```

It checks the set of templates, each entry's skill, blob, declared name and
version, and, when the installed koto is 0.14.1, the koto hash. With another
koto, or none, it reports the hash comparison as skipped and checks the rest.

## Re-running the count

```bash
scripts/offload-baseline.sh count <commit>
```

It prints one line per profile: the profile, raw tokens and weighted tokens.
It reads every span from git objects at the given commit, never from the
working tree, so it gives the same figures at the same commit from any
checkout and leaves the tree untouched. A commit, path or template state that
doesn't exist is an error, and nothing is printed.

To compare a branch against the baseline, run it at the branch's head and
set the output beside the pinned commit's rows in `token-baseline.tsv`. CI
re-runs every `recount` row in that file and fails on any difference.

## Method

The method follows the September census: every instruction a skill puts in
front of the agent (its `SKILL.md`, the state directives koto returns, and the
files those tell the agent to read), counted as bytes divided by 4, and
weighted by how often each piece loads in a typical run.

- **What loads.** `load-manifest.tsv` has one row per loaded span: a profile,
  a path, a selector and a weight. The selector is `file` (the whole file),
  `body` (the file after its YAML frontmatter) or `state:<name>` (one koto
  template state's `## <name>` section, directive and details together).
- **Raw tokens** count each distinct span of a profile once.
- **Weighted tokens** multiply each span by its weight, the expected loads per
  run.
- Each total is divided by 4 and rounded to the nearest integer once, at the
  end.

### Profiles

| Profile | Run it models |
|---------|---------------|
| `work-on` | One complete issue-backed code run |
| `execute-single-pr` | /execute's own load in a single-pr run; each child's /work-on load is the `work-on` profile's |
| `execute-coordinated` | /execute's own load in a coordinated run |
| `scope` | A typical public-repository run through all four hops with one plan review round and no resume; main-context loads only |
| `deliver` | /deliver's own files; the /scope and /execute runs it starts are their own profiles |

### Weights

The weights come from the September census's load model, which was measured
from recorded runs. They're fixed inputs, not re-measured by the count, and
each row's `note` says where its weight comes from:

| Note | Meaning |
|------|---------|
| `resident` | Loaded once per run (weight 1) |
| `visits` | Mean visits to the state per run, as measured |
| `reread` | A reference loaded once plus about half a load per return to the state that reads it |
| `conditional` | A probability that the run loads it at all |
| `failure-only` | Text koto shows only when a default action fails |
| `profile-excluded` | Counted in raw, weight 0: the file or state exists but the modelled run doesn't reach it |
| `subagent-only` | Counted in raw, weight 0: loaded into a subagent, not the main context |

Weights other than 1:

- `work-on`: states `entry` 1.2, `analysis` 1.2, `implementation` 2.25,
  `scrutiny` 2.46, `review` 1.62, `qa_validation` 1.4, `verification` 1.14,
  `finalization` 1.18, `pr_creation` 1.11, `introspection` 0.1,
  `cascade_run` 0.2, `done_already_complete` 0.1, `deferral_approval` 0.03,
  and the failure-only states `changed_paths_record`, `pr_precheck` and
  `cascade_entry` 0.02; the free-form and plan-backed-only states and the
  failure terminals 0. References: `phase-3-analysis.md` and its agent
  instructions 1.11, `phase-4-implementation.md` 1.63, `phase-4a-scrutiny.md`
  1.73, `phase-4b-review.md` 1.31, `phase-4c-qa.md` 1.2,
  `verification-map.md` 1.07, `phase-5-finalization.md` 1.09,
  `phase-6-pr.md` 1.3, `pr-body-conformance.md` 0.7,
  `koto-context-conventions.md` 0.5, `writing-style` 0.5, `public-content`
  0.6, `private-content` 0.4, `finishing-obligations.md` and
  `default-action-conversion.md` 0.3, `phase-6-design-diagram-update.md`,
  `decision-protocol.md` and `koto-session-retention.md` 0.2,
  `phase-2-introspection.md` 0.1, `decision-presentation.md` 0.05,
  `fixes/sub-agent-dispatch.md` 0.02.
- `execute-single-pr`: states `spawn_and_await` 2, `ci_monitor` 2,
  `merge_route` 3, `merge_attempt` 0.5, `merged` and `ready_awaiting_merge`
  0.4 each, `worktree_discipline_check` 0.3, `escalate`, `paused_for_review`
  and `done_blocked` 0.2, `worktree_sync` 0.1, the other failure-only states
  and the rare escalations 0.05, `done` 0. References: `phase-6-pr.md` 2, the
  two worktree-discipline references 0.3.
- `execute-coordinated`: `merged` and `ready_awaiting_merge` 0.4 each,
  `paused_awaiting_merges` 0.2, `coord_verdict` and `coord_merge_confirm`
  0.05, the failure terminals 0.
- `deliver`: `scope_run` and `execute_run` 1.5 (the directive on every tick,
  the details on arrival), `confirm` 0.5, the failure-only states 0.05, the
  non-success terminals 0.
- `scope`: `fold` 3 (once per hop edge), the state-machine states koto runs
  itself (`intake`, `branch_check`, `resume_route`) 0.05; 0 for every state
  the modelled run (no intent, no resume, a full run) never enters: the resume
  prompts, `hop_select`, the other exits and their cleanups, the publish,
  republish and executed-report states, and every terminal but
  `done_full_run`. `phase-0-setup-freeform.md` 0 (the run enters `/design`
  with a PRD) and `plan-format.md` 0 (no phase of the modelled run reads it);
  `brief-format.md`, `prd-format.md` and `decision-presentation.md` 2 (read at
  two hops), `writing-style` 6 and `public-content` 4 (re-read at each
  authoring hop).

### Left out on purpose

- `.claude/shirabe-extensions/work-on.local.md`, generated per workspace and
  not in the repository, and the PR-creation skill a workspace's extension may
  name, which lives outside shirabe.
- `/execute`'s "see" links from SKILL.md (`koto-session-retention.md`,
  `tool-declaration-policy.md`, the five `parent-skill-*.md` references,
  `coordination-strategy.md`, `default-action-conversion.md`): no directive
  tells the agent to read them, so they load only on demand.
- In `work-on`, `staleness-signals.md`, which only a stale-issue path reads.
  In `deliver`, SKILL.md's "see" link to `koto-session-retention.md`.
- In `scope`, the parent-skill references and `worktree-discipline.md` are in
  the manifest at weight 0: SKILL.md's reference table names them, but the
  modelled run doesn't read them. `design-format.md` goes to a subagent, also
  weight 0. `phase-resume.md` and the four decision-record templates are
  weight 0, reached only on a resume or a re-evaluation exit.
- Also in `scope`, files the modelled run reaches only through a "see" link,
  a mode it doesn't run in, or a branch it doesn't take, and which aren't
  listed: `pipeline-model.md` and `cross-repo-references.md` (upstream
  validation detail), `decision-protocol.md` and `decision-block-format.md`
  (`--auto` only), `split-triggers.md`, `workflow-principles.md`,
  `issues-table.md` and `dependency-diagram.md` (a plan that splits),
  `/plan`'s `plan-doc-examples.md`, `consumer-validation-rules.md`,
  `agent-prompt-planning.md`, `walking-skeleton-issue.md` and the three
  `ac-*.md` templates (roadmap input, a walking skeleton, or the per-issue
  subagents), and `/review-plan`'s `phase-6-loop-back.md` (a failing review).
  `skills/writing-style/rules.yaml` is read by the validator and by reviewer
  subagents, not by the main context. The per-skill extension files the child
  skills `@`-import don't exist in this repository.

The same manifest runs at both recorded commits; no row differs at e592501.

## The figures

| Profile | Pinned commit (raw / weighted) | e592501 recount (raw / weighted) | September census (raw / weighted) |
|---------|------------------------------|----------------------------------|-----------------------------------|
| `work-on` | 46,671 / 36,789 | 45,776 / 35,761 | 48.0k / 37.8k |
| `execute-single-pr` | 41,083 / 37,300 | 41,065 / 37,283 | 37.2k / 33.5k |
| `execute-coordinated` | 24,844 / 24,004 | 24,987 / 24,148 | 22.0k / 21.5k |
| `deliver` | 6,181 / 5,303 | 6,203 / 5,325 | 5.9k / 5.0k |
| `scope` | 226,407 / 192,499 | 226,437 / 192,549 | 181k across its files / 135k to 145k per run |

`token-baseline.tsv` holds the same numbers.

**Why the recount and the census differ.** The census split each file into
instruction rows by hand and, in places, left out rationale prose that told
the agent nothing to do; it also left template frontmatter out except for the
field descriptions koto shows. The recount counts whole spans: whole files,
or whole template state sections including the text koto shows only on
arrival. So the recount runs higher for every profile but `work-on`, most
visibly for `scope`, where the census reports setting aside about 28k tokens
of rationale and history and counted only the main context of one run.
`work-on` comes out lower because the census also counted text the recount
can't read from the repository: the workspace-generated
`work-on.local.md` it treated as resident, and the `expects` field
descriptions and `default_action` fallbacks koto shows from template
frontmatter. The two recount columns use the same method, so the difference
between them is what the 22 commits between e592501 and the pinned commit
changed. Compare a later change with the
pinned commit's recount, never with the census.

## Preloaded rate (provisional)

Everything in this section is **provisional**, as version `provisional-1`. A
later measurement-definitions effort, shared with other measurement work,
settles it, and the baseline may move when it does. Each part names the
alternative it was chosen over.

The preloaded rate of a rule is the share of checkable opportunities in which
the rule was broken, in runs of the pinned templates, while the rule sat in
the agent's default context.

### Rule

A rule is keyed by its source location at the pinned commit:
`<path>#L<start>-L<end>` for a line range, or `<path>#<heading text>` for a
whole section, recorded with the commit as `rule.source_commit`. When a rule
registry gives rules ids, each key is re-keyed to its registry id and kept on
the record as provenance. No id format is defined here.
*Provisional.* *Alternative:* key by census row number; rejected because those
numbers exist only outside the repository.

### Opportunity

One production, in a run, of an output the rule governs (a PR body, a commit
message, a document section, a submitted evidence value), in a state where the
rule is in the agent's default context. An output is produced when a tool call
first writes it outside the agent's reply: to disk, to git, to GitHub, or to
koto. Drafts revised before that write aren't visible and aren't counted, and
each distinct output (each PR, each commit, each document) is one opportunity
however often it's rewritten later.

For a rule that governs an action rather than an output (passing
`--no-cleanup` on every root tick, naming a branch, running a check before
committing, never skipping hooks with `--no-verify`), an opportunity is one
occurrence of the governed action (one tick, one commit, one push), observed
from the tool call itself.

*Provisional.* *Alternative:* one opportunity per run; rejected because it
hides repeat violations. Leaving action rules out was also rejected: they
would all land in `not-checkable`, and they include some of the most frequent
slips, branch naming among them.

### Violation

The output or action breaks the rule, as decided by the rule's check: a script
where one exists, otherwise a grader or a human reading against the rule's
text.
*Provisional.* *Alternative:* count only script-detected violations; rejected
because most rules have no script yet, and the baseline would cover only them.

### Observation point

The first time the output is written (the first `gh pr create`, the first
commit, the first evidence submission), before any check, gate retry or
reviewer has fed back on it.

The preloaded rate is one of a pair. Its offloaded counterpart, the rate for a
rule withheld from default context, is observed at the first production after
the rule's text has been delivered once. The counterpart isn't computed here;
it's named so a later feature can't measure the two at inconsistent points.

*Provisional.* *Alternative:* the final output; rejected because it measures
the review loop, not the preloaded rule.

### Numerator

Opportunities with at least one violation of the rule.
*Provisional.* *Alternative:* the count of violations; rejected because one
output can break a rule in many places, and a rate above 1 isn't a rate.

### Denominator

Checkable opportunities: those where the rule's check could reach a verdict.
Opportunities it couldn't judge are counted as `not-checkable` and reported
beside the rate.
*Provisional.* *Alternative:* all opportunities, counting unjudged ones as
complied; rejected because it understates the rate by however much went
unchecked.

### Population

Runs whose session `template_hash` equals a `koto_template_hash` in
`template-pin.json`. A run of any other template text is a different version,
even with the same declared version.
*Provisional.* *Alternative:* runs in a date window; rejected because a window
mixes template versions whenever a change lands inside it.

### Early-ending runs

A run that ends before producing an output contributes no opportunity for it;
one that produced the output counts, whatever happened afterwards.
*Provisional.* *Alternative:* drop incomplete runs entirely; rejected because a
run abandoned after a bad PR body still broke the rule.

### Attribute names

A measurement record carries:

| Attribute | Value |
|-----------|-------|
| `definition.version` | `provisional-1` |
| `rule.source` | the rule's source-location key |
| `rule.source_commit` | the commit the key is exact at |
| `skill` | `work-on`, `execute`, `scope` or `deliver` |
| `template.path` | the template's repository path |
| `template.git_blob` | the pin's `git_blob` |
| `template.koto_hash` | the session's `template_hash` |
| `state` | the koto state the opportunity arose in |
| `run.id` | the run the opportunity belongs to |
| `opportunity.index` | the opportunity's position within the run |
| `opportunity.outcome` | `complied`, `violated` or `not-checkable` |
| `observed_by` | `script`, `grader` or `human` |

*Provisional.* *Alternative:* flat snake_case names; rejected because dotted
groups keep rule, template and opportunity fields apart when records are
merged with other measurement data.

### To reconcile

These stay as written until the later measurement-definitions effort takes
them up:

- the attribute names, including the dotted namespace;
- `run.id`, and what identifies a run across the records that effort merges;
- `rule.source`, keyed by source location, against the opaque rule id that
  koto's gate events will carry.

## Maintaining the baseline

- **A skill starts loading a new file.** Add a manifest row with its weight and
  provenance. Re-run `count` at the pinned commit; if the file existed there,
  the pinned figures change, so record them and say why in the commit.
- **Refreshing weights.** Weights are data. Changing one changes the weighted
  figures at every recorded commit; re-run `count` at each and update
  `token-baseline.tsv` in the same commit.
- **Moving the pin.** Regenerate `template-pin.json` at the new commit, re-run
  `count` there, and keep the old rows for comparison.
- **Line-range rule keys drift** once the file above a rule is edited. They
  stay resolvable with `git show <rule.source_commit>:<path>`.
