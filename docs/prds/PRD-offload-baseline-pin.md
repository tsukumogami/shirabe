---
schema: prd/v1
status: Done
problem: |
  shirabe's four koto-templated skills (work-on, execute, scope, deliver) are
  about to change what they load into an agent's context, and nothing fixes
  the "before": every template declares version "1.0" and never bumps it, the
  preloaded rate of a rule has no definition, and the only instruction-token
  census was taken outside the repository at an older commit with a method
  nobody can re-run from shirabe.
goals: |
  One commit on main is pinned as the baseline, with the identity of every
  koto template the four skills ship at it; the per-skill instruction-token
  load at that commit is recorded and re-runnable; and preloaded rate is
  defined per rule, provisionally, so later instruction changes can be
  measured against the same starting point.
absorbed:
  - docs/briefs/BRIEF-offload-baseline-pin.md
---

# PRD: offload-baseline-pin

## Status

Done

The completeness, clarity and testability reviewers all passed it, the last
two on a second round. The downstream DESIGN owns the approach.

Absorbed [BRIEF-offload-baseline-pin](docs/briefs/BRIEF-offload-baseline-pin.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so that the first change to what shirabe's koto-templated
workflows load has something fixed to be measured against. The brief framed
that as three missing pieces, which this document's Problem Statement states in
full: template texts that can't be told apart because the declared version
never moves, a preloaded rate nobody has defined, and a token count taken
outside the repository at an older commit that nobody can re-run.

The outcome it asked for is that a maintainer landing such a change can name
the template versions the "before" ran, re-run the same token count on their
branch, and count rule violations with a written definition whose provisional
parts are marked. Those are this document's Goals, and the four people it
imagined doing that work (comparing a cleanup, selecting runs by template,
refining a definition, re-keying rules to ids) are its User Stories.

Its boundary held the baseline to measuring, never changing, what a run loads,
and left violation rates, a rule-id scheme and settling the definitions to later
work. Those are this document's Out of Scope.

## Problem Statement

Four shirabe skills run as koto workflows: `/work-on`, `/execute`, `/scope`
and `/deliver`. Planned work will change what those workflows put in front of
an agent: removing prose that directs nothing, loading references only in the
state that uses them, and later withholding a rule until a check shows it was
broken. Each change is meant to be judged by what it does to the instruction
tokens a run loads and to how often each rule is broken. Neither number has a
fixed starting point today.

The five templates behind those skills (`work-on.md`, `execute.md`,
`execute-coordinated.md`, `scope.md`, `deliver.md`) all declare
`version: "1.0"` and have never bumped it, so the declared version can't tell
one template text from another, and numbers gathered from runs can't be tied
to the text that produced them. The preloaded rate of a rule, meaning how
often the rule is broken while it's still in the agent's default context, is
the number the offload work is supposed to halve, yet nothing defines what
counts as a violation, what it's divided by, or how a rule is named. And the
only count of instruction tokens per skill was a census taken in September
2026 at shirabe commit e592501, recorded outside the repository with a method
nobody can re-run from shirabe. shirabe has moved more than 20 commits since, several
of them in these skills.

The completeness, clarity and testability reviewers all passed it; the last two on a second round. The downstream DESIGN owns the approach.
If the first instruction change lands before this is fixed, the "before" is
whatever someone reconstructs from git history afterwards, measured however
they choose.

The completeness, clarity and testability reviewers all passed it; the last two on a second round. The downstream DESIGN owns the approach.
## Goals

- A shirabe maintainer can name exactly which template texts the "before"
  ran, both as shirabe's history records them and as a run record does.
- The per-skill instruction-token load at the pinned commit is recorded, and
  anyone can re-run the same count on any later commit and get comparable
  numbers.
- Preloaded rate has a written, per-rule definition that two people applying
  it to the same run records would count the same way, and it's plainly
  marked provisional.

## User Stories

- As a maintainer landing an instruction cleanup, I want to re-run the
  recorded token count on my branch and compare it with the baseline, so that
  my PR can state what the cleanup removed per skill and a reviewer can check
  it.
- As a maintainer rebuilding a rule's violation rate from retained run
  records, I want each pinned template's identity in the form a run record
  carries, so that I select only runs of the pinned templates and treat every
  other text as a different version.
- As a maintainer settling shared measurement definitions, I want the
  preloaded-rate definition and its counting rules in one place with their
  provisional status stated, so that I can change them and record why without
  hunting for other copies.
- As a maintainer introducing rule ids, I want every rule the baseline names
  identified by its source location at the pinned commit, so that mapping
  each one to its new id is mechanical.
- As a reviewer of this change, I want each definitional choice laid out with
  its alternative, so that I can accept or change it before it becomes the
  baseline.

The completeness, clarity and testability reviewers all passed it; the last two on a second round. The downstream DESIGN owns the approach.
## Requirements

**Terms.** A *run* is one koto workflow session started from one of the
five templates named above, together with the skill files, references and
child-skill files that session's directives and SKILL.md tell the agent to
load. *Loaded files* are the files under `skills/` and `references/` that a
run can load. A template's *koto identity* is the `template_hash` koto
reports for a session started from it, which is the hash of the compiled
template and can be computed without starting a session.

### Functional

The completeness, clarity and testability reviewers all passed it; the last two on a second round. The downstream DESIGN owns the approach.
- **R1. Pinned commit.** The baseline names one shirabe commit on `main` as
  the pinned commit. It's the commit `main` pointed at when the baseline was
  taken, not the census commit.
- **R2. Template pin.** For each koto template the four skills ship at the
  pinned commit, a committed, machine-readable record gives: the skill, the
  template's repository path, its declared `name` and `version`, an identity
  that changes whenever the template's text changes, and its koto identity,
  with the koto version that identity was computed under.
- **R3. Pin verification.** A command re-derives every identity in the
  template pin from the pinned commit, without starting a koto session, and
  reports each mismatch by entry, so a pin edited by hand or taken from the
  wrong commit is caught. It also fails, naming the problem, when the pin
  can't be parsed, lacks a required field, lists a template the pinned commit
  doesn't have, omits one it does, or files an entry under the wrong skill.
  The koto identity is compared only when the installed koto version matches
  the recorded one; otherwise that comparison is reported as skipped.
- **R4. Preloaded-rate definition.** A written definition of preloaded rate,
  per rule, states: what one opportunity to break the rule is; what counts as
  a violation and when it's observed; the numerator and denominator; which
  runs are in the population (tied to the template pin); how runs that end
  early are treated; and the attribute names a measurement record carries.
- **R5. Rule identity.** The definition identifies a rule by its source
  location: a repository path plus a line range, or a path plus a heading, at
  the pinned commit. It states that these keys are replaced by rule-registry
  ids when that registry exists, and it defines no id scheme of its own.
- **R6. Provisional marking.** The definition, each counting rule and each
  attribute name is marked provisional, and the document says what settles
  them (a later measurement-definitions effort shared with other measurement
  work) and that the baseline may move when they do. Each counting rule names
  the alternative it was chosen over.
- **R7. Token baseline at the pinned commit.** Per skill (work-on, execute
  single-pr, execute coordinated, scope, deliver), the baseline records raw
  instruction tokens (each loaded file or span counted once) and weighted
  tokens (multiplied by expected loads per run), measured at the pinned
  commit.
- **R8. Re-runnable method.** The method is written down (what counts as
  loaded, how tokens are computed, where the load weights come from), and one
  command re-runs the count at any commit given as an argument, reading files
  from that commit rather than from the working tree and leaving the working
  tree unchanged. A commit that doesn't exist, or one missing a file the
  method lists, is an error naming the commit or file, not a partial count.
- **R9. September reference.** The September 2026 census figures at commit
  e592501 are recorded beside the new baseline and labelled as the reference,
  together with the re-run of the new method at e592501, so a reader can
  separate differences caused by the method from differences caused by the
  commits in between.

### Non-functional

- **R10. No change to what runs load.** No loaded file is edited, and every
  new file sits outside `skills/` and `references/`, where no run loads it.
- **R11. Public content.** Nothing committed names a private repository or
  its documents, an absolute filesystem path on a developer's machine, a
  session or instance name, or a job id.
- **R12. Minimal tooling.** The only new tooling is what R3 and R8 need, with
  tests for it that run in CI on every pull request touching the tooling or
  the pinned data, and it runs under bash 3.2, the floor shirabe's other
  scripts hold.

## Acceptance Criteria

Pin and verification:

- [ ] A machine-readable template pin names the pinned commit, which is an
      ancestor of `main` and is not e592501, and has exactly one entry per
      koto template shipped under `skills/{work-on,execute,scope,deliver}/koto-templates/`
      at that commit (five entries).
- [ ] Each pin entry carries the skill, path, declared name and version, a
      content identity, and the koto identity with the koto version it was
      computed under, and each entry's skill matches the `skills/<skill>/`
      directory of its path.
- [ ] The verification command exits 0 against the committed pin.
- [ ] It exits non-zero and names the entry for each of: one altered content
      identity, two altered identities (both named), an entry filed under the
      wrong skill, an entry for a template the pinned commit lacks, a missing
      entry, a missing required field, and a pin that fails to parse.
- [ ] With a koto version different from the recorded one, it reports the
      koto-identity comparison as skipped and still checks content identities.

Definitions:

- [ ] The preloaded-rate definition has a separately headed part for each of:
      opportunity, violation, observation point, numerator, denominator,
      population, early-ending runs, and attribute names; each part is
      labelled provisional and names the alternative it was chosen over.
- [ ] The definition states that a later measurement-definitions effort
      settles it and that the baseline may move when it does.
- [ ] The definition keys rules by path plus line range or path plus heading
      at the pinned commit, says those keys are re-keyed to rule-registry ids
      later, and defines no id format.

Token baseline:

- [ ] Recorded raw and weighted token figures exist for each of the five
      skill profiles (work-on, execute single-pr, execute coordinated, scope,
      deliver) at the pinned commit.
- [ ] Running the recount command at the pinned commit reproduces the
      recorded figures exactly, and `git status --porcelain` output is the
      same before and after the run.
- [ ] Running it at e592501 reproduces the recorded e592501 figures, which sit
      beside the September census figures, labelled as the reference.
- [ ] Running it with a commit that doesn't exist, with no commit, or with a
      commit that lacks a file the method lists, exits non-zero with a
      message naming the commit or file and prints no figures.

Boundaries:

- [ ] `git diff --name-only <pinned commit>` on the branch lists no path
      under `skills/` or `references/`.
- [ ] A check over the branch's added files finds no repository reference
      outside the public-repository allowlist, and no match for the
      home-directory path prefixes or the session, instance and job
      identifier formats, as the design lists them.
- [ ] The tooling's tests pass in CI on the pull request, including under
      bash 3.2.

## Out of Scope

- Any change to what a run loads, including instruction edits, deletions,
  contradiction fixes and per-state loading. Those are what this baseline
  measures.
- Measuring violation rates. This defines them; the rates are rebuilt later
  from retained run records.
- A rule-id scheme. Rules keep source-location keys until a rule registry
  gives them ids.
- Re-classifying each instruction by kind or offload verdict. The census's
  row-level judgments aren't needed to reproduce its token totals.
- Tooling beyond the recount and the pin check: no event export, dashboards
  or transcript parsing.
- Skills that don't run as koto workflows.
- Settling the definitions. They stay provisional until a separate
  measurement-definitions effort settles them.

The completeness, clarity and testability reviewers all passed it; the last two on a second round. The downstream DESIGN owns the approach.
## Known Limitations

- Weighted tokens depend on load weights (visits per state, re-read rates)
  taken from observed runs. They're recorded as fixed inputs, not re-measured,
  so a change that alters how often a state is visited isn't reflected in the
  weighted figure until the weights are refreshed.
- koto's template identity is a hash of the compiled template, so a koto
  release that changes compiled output changes the identity without any
  change in shirabe. The pin records the koto version for that reason.
- Line-range rule keys drift as soon as a file above the rule is edited.
  They're exact only at the pinned commit, which is why the definition ties
  them to it.

## Decisions and Trade-offs

- **Pin at current main, not at the census commit.** The census commit is
  already more than 20 commits behind, and the work this baseline exists for starts
  from main. Pinning the census commit would compare later changes against a
  state nobody runs. The September figures stay as the reference so nothing
  measured then is lost.
- **Identify templates by content, not by the declared version.** Bumping
  `version:` in every template would be an edit to what runs load, which this
  work must not make, and it would still depend on people remembering to bump
  it. Content identities change whenever the text does.
- **Record the definitions as provisional proposals.** They're choices, not
  facts, and a later effort settles them with other measurement work. Fixing
  them here would make that effort a migration.
- **Reproduce the census's totals, not its row-level judgments.** Kind and
  verdict per instruction are judgment and aren't needed for a token baseline;
  the file and line spans and the load weights are.

## Downstream Artifacts

- `docs/designs/current/DESIGN-offload-baseline-pin.md`: where the pin and definitions
  live, the proposed counting rules, and how the recount works.
