# Lead: where each candidate criterion's rule lives, and which public artifacts supply fixtures

Sources used: the worktree's files (docs/, skills/, references/, crates/, scripts/),
`git log` on this branch (243 commits; squash-merge subjects are PR titles and
squash bodies are PR Part 1), and one read-only `gh pr list --state merged --limit 200`
pull of full PR bodies (188 returned) to see Part 2 and the pre-`---` text as authored.

## Findings

### 1. PR body Part 1 is a factual summary of what changed and why

**Rule location.** `references/pr-body-conformance.md`, section "What the two-part
convention is":

> "**Part 1** (above the separator) becomes the squash commit body that lands
> permanently on `main`. It is a factual description of the change."

The same file says outright that this part is *not* mechanically checked, which is
why it's a judgment candidate: "What stays advisory (subjective) ... Whether Part 1
mentions an issue in prose, the exact wording of Part 1". PB4 (no ATX heading in
Part 1) is the only mechanical slice; `crates/shirabe-validate/src/pr_body.rs` is the
implementation of record. Note the rule text says "what changed" but not "why"; the
"and why" half isn't written anywhere as a rule, so the grader question should either
drop it or quote the shape the skills actually ask for (`/work-on` phase 6 and
`/execute` `pr_finalization` both defer to this reference).

**Good sources (plentiful).** Every squash body in `git log --format=%B` since roughly
v0.15 is a clean prose Part 1. Strong examples: #477 (has_commits from impl_base),
#467 (tsuku 0.15.2 pin), #385 (remove tests_passing gate), #420, #421, #425, #437,
#43, #13. Over 150 non-release commits to draw from.

**Bad sources.**
- Natural weak Part 1s in merged PRs: #136 (opens with plan/outline bookkeeping, "per
  `docs/plans/...` Outline 2", then a file-by-file inventory), #138 (Part 1 drifts into
  "Pure hygiene ... Pre-v0.7 cleanup so" reviewer framing), #64 (checklist of process
  steps and issue-closing bookkeeping rather than a description of the change).
- Part 1s containing headings, checklists or `Fixes #N` lines (a scan flagged #412,
  #385, #378, #345, #336, #309, #291, #281, #239, #169, #167, #135, #123). Some of
  these are only list items and are fine; triage needed. Heading ones are
  already PB4-mechanical and shouldn't be used as Jev fixtures, because the mechanical
  check already decides them.
- Seeding is easy: move a real Part 2 (test plan, "What this enables", review notes)
  above the separator; replace Part 1 with a vague "Various improvements to work-on";
  write a Part 1 narrating the session ("I first tried X, then the reviewer asked...");
  write one that describes intent without the change ("This PR aims to make
  finalization better"); write one that contradicts the title. 20+ is straightforward.
- Adversarial: a one-line Part 1 (the conformance doc explicitly allows it: "A
  legitimate docs-only PR with a one-line Part 1 ... passes"), and a steered bad
  one that opens "Summary of changes:" but contains only reviewer instructions.

**Ease: high.**

### 2. A code comment gives a reason, not a restatement of the code

**Rule location.** `skills/work-on/references/phases/phase-4-implementation.md`,
"A. Write Code":

> "**Record why the code is shaped this way, next to the code** — the decision the
> diff cannot show ... a comment explaining *what* the code does is usually redundant
> with the code. A comment explaining *why* it is this way and not the obvious
> alternative is not recoverable from anywhere else."

Secondary: `skills/public-content/SKILL.md:62` ("Code comments should be clear for OSS
contributors", too weak to grade against). No rule file in the repo is more specific.

**Good sources.** Rust and bash comments that record a constraint or a rejected option:
`crates/shirabe-validate/src/merge_gate.rs:210` (parse every PR reference up front),
`crates/shirabe-validate/src/finalize.rs:527` (read `upstream:` before anything is
applied), `skills/execute/scripts/settled-branch-record_test.sh:412`, and
`skills/writing-style/rules.yaml` `min_words` comment ("At 98 words one em dash is 10.2
per thousand..."). The phase-4a and phase-5 retry-loop prose also shows the house
style for "why" text, though it isn't a code comment.

**Bad sources (natural, in repo).** Restatement comments exist:
`skills/plan/scripts/render-template.sh:39,46,71,160,211` ("# Check prerequisites",
"# Read and validate input JSON", "# Get template path for complexity", "# Run main if
script is executed"), `skills/plan/scripts/build-dependency-graph.sh:38,45,67,127`,
`skills/work-on/scripts/run-cascade.sh:126,132,138` ("# Check path does not escape repo
root", "# Check file is tracked by git"). That's roughly a dozen natural cases; seed the
rest by writing a "what" comment over any real line (Rust or bash).

**Fixture shape.** Comment plus the 3-10 lines of code it annotates. Small inputs.

**Adversarial.** A restatement dressed as reasoning ("# We check the file is tracked
because we need to check it is tracked"), or one with a "because" clause that just
restates the next line. Also borderline: docstring-style header comments that describe
a function's contract (`run-cascade.sh:148-152` "Returns 0 if closed, 1 if open") —
these are "what" comments that are legitimately useful, so they test whether the rule
wording is too strict. Label these carefully or exclude them.

**Ease: high.**

### 3. An acceptance criterion can be answered yes or no

**Rule location.** `skills/prd/references/prd-format.md`, "Acceptance Criteria" quality
guidance:

> "Binary pass/fail -- no subjective judgment
> A developer who didn't write the PRD can verify each criterion"

Reinforced in the same file ("Subjective acceptance criteria -- every criterion must be
verifiable") and in `skills/prd/references/phases/phase-3-draft.md:108` ("Each criterion
is binary pass/fail") and `skills/prd/references/phases/phase-4-validate.md:99` ("Are
acceptance criteria binary pass/fail? Could a reviewer objectively verify each one?").
The PLAN side is weaker: `skills/plan/references/templates/agent-prompt.md:139`
("Checkboxes for specific, testable criteria"). A related but different rule is
`/review-plan`'s discriminability taxonomy
(`skills/review-plan/references/templates/ac-discriminability-taxonomy.md`), which asks
whether a criterion would pass for a wrong implementation; that's a harder question and
shouldn't be conflated with yes/no answerability.

**Good sources (abundant).** 1,381 `- [ ]` lines across `docs/prds/` and `docs/plans/`.
Crisp examples in `docs/prds/PRD-pr-template-gate.md`, `PRD-single-pr-plan-validation.md`,
`PRD-scope-koto-adoption.md` (AC34), and the koto issue in
`skills/work-on/koto-templates/work-on.plan_validation.verdict.decider.jsonl`
(`pv-shirabe-scope-then-execute-1`, e.g. "a template with ... (typo) fails `koto template
compile` with an error naming the state, the target and the unknown field").

**Bad sources.** Natural soft ones are few but present:
`docs/prds/PRD-session-work-summary.md:181` ("the agent can still answer correctly about
the..."), and the ACs in `pv-shirabe-250-needs-design` in the same jsonl ("solved without
adding organization-specific data", "can opt into staying current"). The taxonomy file's
concrete examples are public and usable. Seeding is easy: degrade real ACs with
"appropriately", "is intuitive", "performs well", "handles errors gracefully",
"is improved", "users are happy with", or turn one into a goal statement.

**Adversarial.** A criterion that sounds measurable but has no threshold ("latency is
low, measured in ms"), or one with a number that isn't observable ("reduces confusion by
50%"). Also the reverse: long, checkable ACs with a subjective-sounding word
("well-formed PR" in `PRD-pr-template-gate.md:248` is defined by PB1-PB3, so it's
binary) — a good false-fail probe.

**Ease: high.**

### 4. A scrutiny finding is resolved by a given diff

**Rule location.** `skills/work-on/references/phases/phase-4a-scrutiny.md`. The rule is
procedural, not a stated test for "resolved":

> "If any `blocking_count > 0`: collect blocking findings, spawn the coder agent with
> combined feedback ..., and re-enter this phase."

The reviewer prompts give the dimensions ("Does every acceptance criterion have a
corresponding implementation? Are evidence claims verifiable from the diff?"). The koto
state is `scrutiny` in `skills/work-on/koto-templates/work-on.md` (~line 724, directive
~1791). Nothing states what makes a finding resolved; a fresh reviewer round decides.

**Sources.** Scrutiny findings are written to `wip/research/work-on_scrutiny_*` and
deleted before merge; none survive in history (searched `git log` for wip scrutiny
paths — none). `skills/work-on/evals/fixtures/scenarios/scrutiny-blocking-retry-entry/`
has a koto response, not finding text. Fixtures would have to be authored: take a real
fix commit's diff (for example #477, #420, #309) and write findings that the diff does
or doesn't address. Inputs are large (diffs), labels are author-made, and
"partially resolved" is a real third answer that a yes/no question forces into one bucket.

**Ease: low.** Needs synthetic findings and long inputs; no rule wording to quote as the
question.

### 5. A doc section sits at the right altitude

**Rule location.** Several, consistent with each other:
- `skills/design/references/phases/phase-6-final-review.md:75-77`: "Section-altitude
  conformance: does each section contain the altitude of content the reference
  prescribes (no PRD-altitude requirements, no PLAN-altitude atomic issues)?"
- `skills/design/references/design-format.md` "Content Boundaries": "A DESIGN does NOT
  contain: Requirements articulation ... Atomic issue decomposition ... Strategic
  justification".
- `skills/prd/references/prd-format.md` "Content Boundaries": "A PRD does NOT contain:
  Technical architecture or design decisions ... Implementation approach or task
  breakdown ... Code examples or API specifications".
- `skills/brief/references/brief-format.md:215-226,497-498` ("functional requirements,
  acceptance criteria, and user stories live one altitude down"; "has climbed down into
  PRD or DESIGN altitude").
- `skills/strategy/references/strategy-format.md:212-220,450-456` and the strategy
  altitude reviewer in `skills/strategy/references/phases/phase-4-validate.md`.

**Good sources.** 64 PRDs, ~75 plan/design docs, plus `docs/briefs/`. Any Requirements
section of a PRD, any Considered Options section of a DESIGN, any Problem section of a
BRIEF.

**Bad sources.** Mostly seeded by transplanting: put a DESIGN's Solution Architecture
into a PRD's Requirements, a PLAN issue list into a DESIGN's Implementation Approach,
PRD acceptance criteria into a BRIEF. Natural drift exists but finding it needs reading
(e.g. PRDs that name file paths and function names in requirements, such as
`docs/prds/PRD-shirabe-child-dispatch-contract.md` AC7, which is close to design
altitude). Fixtures must carry the doc type and section name alongside the text.

**Adversarial.** The formats allow short citations across altitude ("A PRD MAY briefly
cite competitive findings"; "The DESIGN cites requirements (R1, R2, ...) but does not
introduce new ones"; "The DESIGN names batches or phases"). Sections that cite downward
or upward legitimately are a natural false-fail probe.

**Ease: medium.** Plenty of text, but inputs are long, seeded bad cases are somewhat
obvious (transplants), and the question needs the per-type boundary list as context.

### 6. Hedge language with no approved deferral

**Rule location.** Two statements of the same rule:
- `skills/work-on/SKILL.md`, "Finalization and No Silent Deferral": "A
  finalization-checklist item disallows unapproved caveat or hedge language
  ("experimental", "not yet handled", "known limitation") in the issue's shipped
  artifacts. A caveat is legitimate only where it records an approved deferral ...
  not by a brittle word-grep that would flag legitimate uses of those words."
- `skills/work-on/references/phases/phase-5-finalization.md:176-180`: "A caveat or hedge
  ... in the issue's shipped artifacts is legitimate only where it records a
  human-approved deferral."
- Eval: `skills/work-on/evals/evals.json:463-469`.

`skills/writing-style/rules.yaml` has no hedge rule; `skills/writing-style/SKILL.md:68`
only covers stacked qualifiers ("could potentially possibly"), which is a different rule.

**Sources.** The verdict depends on a fact outside the text: whether a human approved a
deferral (recorded via `koto decisions record`). A fixture therefore needs (text,
list-of-approved-deferrals) pairs, and the approvals are invented. Public hedge text is
thin: `skills/coordinate/SKILL.md:323` "## Known Limitations" (cites shirabe#395/#421 —
legitimately documented, a strong adversarial case), the #404 squash body ("names ... the
known limitations with their cost"), #385 ("Remove ... for now"). Seeding hedges is easy;
grounding them in public artifacts isn't, and "approved" can't be read off the text.

**Ease: medium-low.** Easy to write seeded bad text, hard to make labels non-arbitrary.
It also tests context-matching (does a hedge match an approved item) more than prose
judgment.

### 7. PR title's Conventional Commits type matches the change

**Rule location.** `references/pr-body-conformance.md` PB1 fixes the allowed set ("`<type>`
is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`,
`build`, `revert`") and links conventionalcommits.org, but says nothing about which type
fits which change. The only choosing guidance is
`skills/execute/koto-templates/execute.md:1395`: "`<type>` defaults to **`feat`** (a PLAN
normally lands feature work). Use `fix` only when the PLAN is purely remediation, or
`docs`/`chore` when every child change is docs/chore." `/work-on`'s `commit_convention`
gate (`skills/work-on/references/finishing-obligations.md:22`) checks syntax only.

**Sources.** 243 titles in `git log` with their squash bodies (86 feat, 61 chore, 50 fix,
31 docs, 9 ci, 5 test). Good pairs are trivial: title + Part 1 (e.g. #477 fix, #467 ci,
#404 feat, #392 docs, #442 test). Seed bad by swapping the type on a real title/body
(docs for a behavior change, feat for a CI pin, chore for a bug fix). Natural borderline:
#457 and #461 are `chore` but change behavior (koto minimum, workaround removal); #339
`docs(skills)` rewrites skill descriptions that change triggering; `fix(ci)` vs `ci:`
(#427, #419 vs #423). These are ambiguity cases where a human label is contestable.

**Ease: high for seeded bad, low for label confidence on real ones.** The rule text
gives the grader almost nothing to go on beyond the type names, so a false-fail result
would partly measure the vague rule, not the grader.

### Census of model-gradable rules

No "Jev" mention anywhere in docs/ or skills/. The nearest things to a census:
- `skills/writing-style/rules.yaml` `judgment_only:` — eight rules explicitly marked as
  needing a reader rather than a matcher (landscape used figuratively, synonym cycling,
  forced rule of three, low information density, empty conclusions, this/that without
  antecedent, vague attribution, from X to Y). None of the seven candidates is in it, but
  it's the clearest in-repo list of "a model has to decide this".
- `docs/designs/current/DESIGN-shirabe-check-absorption.md` (category A/B/C/D rubric and
  disposition table; category D = "needs human or model judgment", kept out). It records
  "there are no judgment-only keep-outs among the current candidates" and names the `wip/`
  path-hygiene rule as category D.
- `references/pr-body-conformance.md` "What stays advisory (subjective)" — the explicit
  list of PR rules left to judgment (Part 1 wording, Part 2 section choice).
- Decider declarations: `scripts/decider-declarations.tsv` (14 value rows across
  work-on, execute, coordinate) with golden fixture files
  `skills/work-on/koto-templates/work-on.plan_validation.verdict.decider.jsonl`,
  `work-on.issue_type_routing.issue_type.decider.jsonl`,
  `skills/execute/koto-templates/execute.worktree_discipline_check.impact.decider.jsonl`,
  `skills/coordinate/koto-templates/coordinate.pick.choice.decider.jsonl`,
  `coordinate.classify_report.classification.decider.jsonl`, checked by
  `scripts/check-decider-declarations.sh`. `docs/designs/current/DESIGN-coordinate-record.md`
  asks for "at least 40 fixtures per decider". "Model-graded" appears only in
  `docs/prds/PRD-scope-koto-adoption.md` (R27/AC34), about eval scenarios, not rules.
- `skills/coordinate/scripts/testdata/rule-coverage.tsv` is a 190-rule inventory of the
  prose `/coordinate` skill, with carrier file and key phrase per rule. It isn't graded by
  a model but it's a working example of a rule census format.

## Implications

Criteria 1, 2 and 3 are the cheapest to fixture well: each has a quotable rule sentence,
short inputs, hundreds of public good examples, a handful of natural bad ones, and an
obvious seeding method. Criterion 5 is worth including because it's the one the design
and strategy skills already run as a reviewer question, but it needs the doc type and
boundary list in the prompt and longer inputs. Criterion 7 is easy to seed but its rule
text is thin, so the question should quote execute.md's guidance and the fixture set
should keep contestable real titles in a separate "ambiguous" bucket not counted toward
false-fail. Criteria 4 and 6 both depend on information that isn't in the text being
graded (a diff plus an author-written finding; an approval record), so they test
context-matching more than prose judgment and their labels would be invented.

The grader question should quote the rule file's sentence, not a paraphrase — the spike
scope says rule wording becomes the question. For criterion 1, the wording in
pr-body-conformance.md says "factual description of the change" only; adding "and why"
invents a rule.

## Surprises

- No scrutiny finding text survives anywhere public; the wip cleanup deletes all of it.
- Several merged PRs (#136, #138, #64) have Part 1s that a strict grader would fail,
  which makes natural bad fixtures available for criterion 1.
- The repo itself carries restatement comments (render-template.sh, build-dependency-graph.sh,
  run-cascade.sh) that contradict the phase-4 rule — ready-made natural bad fixtures.
- The hedge rule deliberately rejects word-matching ("not by a brittle word-grep"), which
  is exactly the case for a model grader, but its verdict turns on an external approval.
- The Conventional Commits type has no written "which type when" rule outside `/execute`'s
  coordination-PR default.

## Open Questions

- For criterion 1, should the Part 1 fixtures be Part 1 alone or Part 1 plus title? The
  title helps judge "factual" but also lets the grader shortcut on title/body agreement.
- For criterion 7, does the harness give the grader the Part 1 body, the diffstat, or the
  full diff? The choice changes the difficulty more than the grader does.
- Should `rules.yaml` `judgment_only` entries be considered as substitutes for 4 or 6?
  The scope says no new criteria, so they're noted only.

## Summary

Every candidate has a quotable rule in public shirabe, but only some have fixture material that makes labels trustworthy. The PR body rule is in `references/pr-body-conformance.md` ("It is a factual description of the change"). Merged squash bodies give 150+ good examples, and #136, #138 and #64 are natural weak ones. The comment rule is in `skills/work-on/references/phases/phase-4-implementation.md`, and the repo's own `render-template.sh`, `build-dependency-graph.sh` and `run-cascade.sh` contain restatement comments. The acceptance-criterion rule is in `skills/prd/references/prd-format.md` ("Binary pass/fail -- no subjective judgment"), with 1,381 ACs in docs/prds and docs/plans. Altitude rules sit in the design, PRD and brief format files and in the design phase-6 review. They're usable, but inputs are long and the bad cases are mostly transplants.

The Conventional Commits type rule is thin. Only `skills/execute/koto-templates/execute.md:1395` says which type to pick, so real titles give contestable labels, though swapped-type seeds are easy. The scrutiny rule (`phase-4a-scrutiny.md`) never defines "resolved", and no finding text survives wip cleanup. The hedge rule (`skills/work-on/SKILL.md`, `phase-5-finalization.md:176`) turns on an approval record that isn't in the text. Both of those need invented context. Nothing mentions Jev. The closest thing to a census of model-gradable rules is `skills/writing-style/rules.yaml` `judgment_only:`, plus the category-D rubric in `docs/designs/current/DESIGN-shirabe-check-absorption.md`, plus the "advisory" list in pr-body-conformance.md. Existing decider fixtures are listed in `scripts/decider-declarations.tsv`.

Recommended six, most solid first: (1) PR Part 1 is a factual summary, from `references/pr-body-conformance.md`; (2) comment gives a reason, from `skills/work-on/references/phases/phase-4-implementation.md`; (3) AC is yes/no, from `skills/prd/references/prd-format.md`, with phase-4-validate.md:99 as the grader phrasing; (4) doc section altitude, from `skills/design/references/phases/phase-6-final-review.md` plus the Content Boundaries in `skills/design/references/design-format.md` and `skills/prd/references/prd-format.md`; (5) PR title type matches the change, from `references/pr-body-conformance.md` PB1 plus `skills/execute/koto-templates/execute.md:1395`, with contestable real titles held out as a separate bucket; (6) optional, hedge without approved deferral, from `skills/work-on/SKILL.md` and `skills/work-on/references/phases/phase-5-finalization.md`, with an explicit approved-deferrals list in each fixture. Drop scrutiny resolution.
