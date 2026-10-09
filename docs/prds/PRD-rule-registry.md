---
schema: prd/v1
status: In Progress
problem: |
  shirabe's output gates, gate scripts and review-shadow criteria each keep their own rule
  list with their own id scheme and reference format, and the rule text they point at lives
  in prose none of them links back to. Stored line references go stale on the next edit and
  mostly pin commits that squash merges left off main. Nothing records which rules may ever
  leave an agent's default context, and the only delivery path for a rule is loading it up
  front, which blocks the offload work's next step.
goals: |
  Every rule a gate, script or review criterion cites resolves by a stable id to one registry
  entry that names its text, check, fixtures, level, timing and withhold safety. Gate events
  carry that id and a reference that opens the rule's current text. CI keeps ids and pointers
  honest. A script can release a rule's text into an agent's context when the rule applies,
  shown on one real trigger, with nothing yet withheld.
absorbed:
  - docs/briefs/BRIEF-rule-registry.md
---

# PRD: Rule registry

## Status

In Progress

Absorbed [BRIEF-rule-registry](docs/briefs/BRIEF-rule-registry.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists because shirabe's rules have no single home, and the offload work can't
take its next step without one. The brief framed four gaps: nobody can list which rules exist
and what checks each; a rule's stored location rots on the next edit and often pins a commit
that isn't on `main`; nothing marks which rules must never leave an agent's default context;
and a rule reaches an agent only by being loaded up front, so withholding one would lose it.
This document's Problem Statement states those in full.

The outcome it asked for is a maintainer or measurement reader who looks any rule id up in
one place and finds its text, check, fixtures, enforcement, timing and withhold safety, and
an agent who sees a rare rule's text from the script that noticed it applies, while the rule
stays in its default prose. That's this document's Goals. Its four journeys (a maintainer
tracing a gate finding, a measurement reader joining old records to new ones, an agent taking
over a pull request, a contributor adding a rule) are the User Stories, with the review-shadow
maintainer and the installed-copy user added.

Its boundary held the feature to giving rules a home and one delivery shape: no withholding,
no panel replacement, no koto change, no harness edits, no registering of uncited prose rules,
and the validator's own codes kept as aliases at most. Those are this document's Out of Scope.

## Problem Statement

shirabe checks its workflow rules in three places that don't know about each other. At
commit `4dc0df0` on `main`, the output gates' scripts report 22 rules, named like
`pr-body/no-ai-trailer`, from `skills/work-on/scripts/gate-rules.tsv`. The review-shadow
trial grades 17 criteria with opaque ids `rs-001` to `rs-017` from
`scripts/review-shadow/criteria.json`, whose reference for each criterion is a bare file path.
The offload measurement baseline (`docs/measurement/offload-baseline/`) keys a rule by its
line range at its pinned commit and expects a registry to give rules ids later. The words of
each rule live in skill prose, references and templates, and none of the three lists points
at the others or at a shared record of the rule.

Four consequences fall on the people doing the offload work now:

- A maintainer who meets a rule id in a finding or trial record can't tell from one place
  what the rule says, what checks it, or what tests the check.
- A gate finding's `rule_ref` is a stored line range at a stored commit. Because pull requests
  are squash-merged, three of the four commits the gate table pins at `4dc0df0` aren't
  ancestors of `main`, so the reference can't be opened from `main`, and the next edit above a
  rule moves its lines.
- Nothing says which rules must stay in an agent's default context. The first attempt to
  withhold a rule has to guess, and a wrong guess about a rule that guards a push, a merge or
  a published pull request is costly and hard to undo.
- A rule reaches an agent only by being loaded up front, so withholding one would lose it
  even in the run where it matters.

## Goals

- One registry is the authoritative record of every rule that shirabe's gates, gate scripts
  and review-shadow criteria cite, and every id already emitted keeps its meaning.
- A gate event's `rule_id` is the registry id and its `rule_ref` opens the rule's full text,
  correctly, after the text's file has been edited, at a revision a reader can reach from
  `main` for every installed release.
- Each rule declares whether it may ever be withheld, and the rules that guard irreversible or
  outward actions are held at never-withhold by a check, not by convention.
- A script can put a rule's text in front of an agent at the moment the rule applies, using
  only what koto already offers, proven on one trigger in a shipped code path.
- A measurement reader can join baseline records, gate events and trial records on one id.

## User Stories

- As a shirabe maintainer reading a held run, I want to look a finding's `rule_id` up in one
  place and reach the rule's text, its check and its fixtures, and open the `rule_ref` from a
  clone of `main`, so that I fix the cause rather than guess which list the rule came from.
- As a measurement reader, I want every registry entry to list, in a machine-readable field,
  the baseline keys it replaces, so that I can re-key baseline records to registry ids with
  one lookup per record and compare before and after a change.
- As a measurement reader, I want "a registered rule" to mean "an id with a registry entry"
  (R11), so that a koto fallback finding on a routing gate stays out of violation counts until
  koto's routing-gate declaration ships.
- As a maintainer of the review-shadow trial, I want the trial's criteria to keep loading and
  grading exactly as they do, under the same ids, so that trial records before and after this
  change stay comparable.
- As an agent running `/execute` that finds another run's pull request on the plan's shared
  branch, I want the lookup script to show me the takeover rule's text when it reports that
  case, so that I decide on the rule rather than on memory of a long template.
- As a contributor adding a rule, I want CI to refuse an entry with no withhold decision, an
  id nobody registered, a removed id, or a pointer that no longer finds its text, so that I
  can't land a rule that later work might withhold or mis-count by accident.
- As someone running an installed copy of the plugin, which carries no git metadata, I want
  the same rule ids and a `rule_ref` that still names a revision I can open, so that findings
  from real runs are as traceable as findings from a checkout.

## Requirements

### Functional

- **R1. One registry.** Every rule that a shirabe gate or gate script reports, every
  review-shadow criterion, and the rule R8's demonstration releases has exactly one entry in a
  single registry file, at a location the design chooses and justifies. The design also
  chooses the format and states how shell scripts and the review-shadow tool read it. The
  review-shadow criteria file may remain as the trial's grading configuration (R4), but the
  registry is the one place every rule id is defined.
- **R2. Entry fields.** Each entry has at least:
  - `id`, a stable id (R3);
  - the short text an agent sees when the rule is broken: gate scripts print it as the start of
    the finding's message, followed by their existing detail;
  - a full-text pointer: a repository path plus a way to find the first and the last line of
    the rule's text in that file that survives edits elsewhere in the file. The pointer
    "resolves" when its first line is found exactly once in the file at the revision checked
    and its last line is found at or after it (the first such line ends the range);
  - a status, `active` or `retired`;
  - the check that enforces it: a script path that exists, a review-shadow criterion id that
    exists in the criteria file, or an explicit value meaning nothing checks it;
  - its fixtures: repository paths of the tests or fixture files that exercise the check, each
    of which exists, or an explicit empty list;
  - its level (how strongly it is enforced) and its timing (at which workflow points it
    applies), each a value from a closed list the design defines and a check enforces;
  - what it guards: one or more values from a closed list that contains at least
    `pr-create`, `push`, `force-push`, `merge`, `close-issue`, `release`, `delete-branch`,
    `publish` and `destroy-record`, plus a value for rules that guard none of these;
  - its withhold marking (R7);
  - the baseline keys it replaces (R10);
  - optional aliases: other codes the rule is known by (a validator code such as `PB3` or `R7`),
    each unique across the registry and never used as a `rule_id`.
  The design may add fields and explains each one it adds.
- **R3. Stable ids.** An id never changes once committed, and is never reused for another
  rule. Ids match `^[a-z0-9-]+/[a-z0-9-]+$` (named rules) or `^rs-[0-9]{3}$` (review-shadow
  criteria); neither form can hold a line range. An entry is never deleted: a rule that stops
  applying is marked `retired` and keeps its id. A retired entry's pointer isn't required to
  resolve, since its text may be gone, and a gate script asked to print a retired id refuses
  with its could-not-decide exit. A rule whose meaning changes gets a new id; that part is a
  review judgment, and the retire-not-delete part is checked.
- **R4. Existing ids kept.** Every id in `gate-rules.tsv` and `criteria.json` at the pull
  request's base resolves to a registry entry under the same id. The review-shadow tool keeps
  loading `criteria.json` and grading as it does today: `review-shadow.py`, its test suite
  `test_review_shadow.py` and `criteria.json` are not changed by this feature. The set of `rs-` ids
  in the registry equals the set in `criteria.json`, and each such entry's full-text path equals
  that criterion's `rule_ref` path.
- **R5. Gate event contract.** In every finding a gate or gate script prints, `rule_id` is the
  registry id and `rule_ref` is `<path>#L<start>-L<end>@<revision>`, where the range starts at
  the first line and ends at the last line of the rule's full text (not its check) in the copy
  the script runs from. The revision is the release the installed copy was built from, written
  so a clone of `main` can resolve it (every release is a tag on `main`); real runs use an
  installed copy. In a git checkout, which is how shirabe's own tests and development runs
  work, the revision is the checkout's commit, which is on `main` only when the checkout is.
  The design states
  whether `rule_ref` is computed when the finding is printed or stored, and why, given that a
  stored line range goes stale on the next edit and a stored commit can be squashed away.
- **R6. Two CI checks.** (a) Every `rule_id` a gate or gate script can print resolves to a
  registry entry. The design names the discovery method, which covers every literal id in the
  gate scripts and every id their test suites produce; and a script that is asked to print an
  unregistered id refuses with its could-not-decide exit instead. (b) Every active entry's
  full-text pointer resolves at the head. Both run in a CI job whose path filter includes the registry,
  the gate scripts, the review-shadow criteria file, and every file a full-text pointer names.
- **R7. Withhold marking.** Each entry carries a required withhold field with no default and
  exactly two values, one meaning never withhold and one meaning eligible to be withheld by
  later work. An entry without it, or with another value, fails CI. An entry whose guards
  include any of the nine listed actions must be marked never-withhold, and CI enforces that.
  The design classifies every entry's guards, and the classification is in the registry for
  review.
- **R8. Deliver on trigger.** When `/execute`'s owned-PR lookup reports another run's pull
  request on the plan's shared branch (the takeover case), the script prints the takeover
  rule's text, read through the registry's full-text pointer, on standard error, so the text
  reaches the agent that ran it. It prints nothing extra in any other case. Its exit codes and
  standard output are unchanged in every case. When the registry or the pointer can't be read,
  it prints one line saying so on standard error and nothing else changes. The mechanism is a
  shared helper the design names, so later triggers reuse it, and it needs no koto capability
  koto 0.15.0 lacks. It copies the text: the template keeps its takeover prose byte for byte.
- **R9. No withholding.** This change removes no line from any file the offload baseline's load
  manifest (`docs/measurement/offload-baseline/load-manifest.tsv`) lists or from any skill
  template. After it lands, R6(b) keeps every active rule's text in the file its pointer names,
  so a later change that withholds a rule has to change its entry too.
- **R10. Baseline mapping.** Each entry records, as a list, the baseline source-location keys
  (`<path>#L<start>-L<end>`, at the baseline pin's commit in `template-pin.json`) that hold the
  rule's text at that commit, or an empty list when the text didn't exist there. No key appears
  in two entries. The baseline commits no list of rule keys, so completeness against one isn't
  checked; each listed key is checked to lie within its file at the pinned commit. The
  baseline's own files are not edited.
- **R11. Routing-gate rule.** The interim rule (a koto fallback finding whose `rule_id` isn't a
  registered rule is not a violation) is restated with "registered" defined as "has a registry
  entry", in `docs/designs/current/DESIGN-output-gates.md` (Decision 9) and in the registry's
  own documentation. Nothing in shirabe counts violations from event logs, so the rule stays
  documentation for readers; the constraint that routing gates print no findings is unchanged.
- **R12. Script-checkable criteria ship with scripts.** Every standing acceptance criterion
  below is checked by a committed script run by a CI job on every pull request whose paths it
  covers. Criteria marked *(this change)* hold for this pull request only: each compares the
  pull request against its merge base, and a standing job would wrongly forbid later edits
  (removing a template line is how later work will withhold a rule). They are checked by a
  script the pull request runs in CI and whose output its description quotes. The public-content
  criterion is covered by the existing public-content job.

### Non-functional

- **R13. Floors.** New and changed shell scripts pass `scripts/check-bash-floor.sh`, and the
  review-shadow tool is left unchanged, so its Python 3.8 floor holds. Registry readers in
  shell need only the `jq` the repository's bash-floor container and CI runners already
  provide, which the bash-floor suite exercises.
- **R14. No new koto requirement.** koto 0.15.0 remains the floor.
- **R15. Public content.** Nothing committed and nothing in the pull request names a private
  repository or its documents, a local path, a session or instance name, a job id, or an
  internal service, in any form, plain or encoded. The repository's existing public-content CI
  job runs on the pull request and passes.

## Acceptance Criteria

Standing criteria are checked on every pull request their paths cover; criteria marked
*(this change)* compare this pull request with its merge base (R12).

- [ ] A registry file exists at the path the design names, and a check fails on any entry
  missing an R2 field, carrying a status, level, timing, guard or withhold value outside the
  design's lists, naming a check script or fixture path that doesn't exist, naming a
  review-shadow criterion absent from `criteria.json`, repeating an alias another entry uses,
  or carrying an alias that is also some entry's id. A test shows each failure.
- [ ] *(this change)* Every id in `gate-rules.tsv` and `criteria.json` at the merge base is the
  `id` of exactly one registry entry. Standing: a check fails on a duplicate id or an id outside
  R3's patterns.
- [ ] A check comparing the registry at the merge base with the registry at the head fails
  when an id present at the base is missing at the head, demonstrated by a test.
- [ ] *(this change)* `review-shadow.py`, `test_review_shadow.py` and `criteria.json` are
  byte-identical to the merge base, and the review-shadow CI job passes. Standing: a check fails
  when the `rs-` id sets of the registry and `criteria.json` differ in either direction, or an
  entry's full-text path differs from the criterion's `rule_ref`, each shown by a test.
- [ ] Every `::koto-finding::` line the gate scripts' test suites produce has a `rule_id` that
  is a registry id and a `rule_ref` matching `<path>#L<start>-L<end>@<revision>`, where lines
  start to end of that file in the running copy are exactly the lines from the entry's first
  line to its last line.
- [ ] A test inserts lines above a rule's text in a scratch copy and shows the printed
  `rule_ref` range moves with the text with no registry edit (if the design computes refs), or
  shows CI failing until the stored ref is updated (if it stores them). The design says which.
- [ ] A test runs a gate script from a copy with no git metadata and shows the `rule_ref`
  revision is the release tag the design names; a test from a git checkout shows it is that
  checkout's commit.
- [ ] A CI job fails when a gate script can print an id with no registry entry, demonstrated by
  a test that adds such an id; and a gate script asked to print an unregistered or retired id
  exits with its could-not-decide code, shown by a test for each.
- [ ] A CI job fails when an active entry's first line is found zero times or more than once,
  or its last line isn't found at or after the first, demonstrated by a test for each; a
  retired entry with an unresolvable pointer passes.
- [ ] A CI job fails when an entry lacks the withhold field or has a value other than the two
  allowed, and when an entry with any of the nine protected guards isn't never-withhold, each
  shown by a test. Every entry for one of the 22 gate rules carries at least one protected guard
  and is never-withhold, as do `rs-001` (attribution), `rs-002` (private names) and `rs-003`
  (scratch paths), whose violations are published the moment a commit or body is pushed, and
  the takeover rule, which guards pushing onto and rewriting another run's pull request.
- [ ] In the takeover case, the owned-PR lookup's standard error contains the takeover rule's
  text exactly as the lines at its full-text pointer read; its standard output and exit code
  equal those of the same case without the registry change. In every other case its standard
  error contains no rule text. With the registry unreadable, it prints one notice line and its
  exit code and standard output are unchanged. Each is shown by a test.
- [ ] *(this change)* `git diff` of the merge base against the head shows no removed line in any
  file the baseline's load manifest lists or in `/execute`'s template.
- [ ] Each entry's baseline keys match `<path>#L<start>-L<end>`, each range lies within its file
  at the baseline's pinned commit, and no key is listed by two entries; a check enforces this.
- [ ] `DESIGN-output-gates.md` Decision 9 and the registry's documentation each define a
  registered rule as an id with a registry entry, and a check fails if Decision 9 still refers
  to the gate scripts' rule tables.
- [ ] `scripts/assert-koto-floor.sh` and the koto-floor CI jobs pass with the floor at 0.15.0.
- [ ] Every new or changed `.sh` file under `scripts/` or `skills/` runs in a suite that
  `scripts/check-bash-floor.sh` runs, and passes there.
- [ ] The repository's public-content CI job passes on the pull request.

## Out of Scope

- Withholding any rule from default context. The trigger demonstration copies text and leaves
  the default prose in place; removing it is a later feature.
- Letting a decider pass skip or replace a review panel, or changing what any pass can do.
- Any koto change, including the routing-gate declaration requested in koto issue #306.
- Edits to the measurement harness, the baseline's files or the ablation scripts, and adding
  the registry to the baseline's load manifest. The registry carries the mapping to baseline
  keys; the baseline keeps its own.
- Rewriting `rule_ref` values already recorded in past event logs or trial records. Old
  records keep the reference they were written with; the id is the join key.
- Registering prose rules that no gate, script or review criterion cites today.
- Making the doc validator's internal check codes registry ids, or looking a rule up by alias.
- Changing which states the gates run in, what they check, or how they route.
- Any other trigger than the takeover case; cascade recovery and later triggers reuse the
  helper in later work.

## Known Limitations

- A finding printed from a git checkout of an unmerged branch names that branch's commit,
  which a reader can open only while the branch exists; after a squash merge it isn't on
  `main`. Real runs use an installed release, whose tag is on `main`, so this affects
  shirabe's own tests and development runs, not the records a measurement reads.
- Whether a rule's meaning changed, and so needs a new id, stays a review judgment. CI catches
  a removed id but not a reworded rule that kept its id.
- The never-withhold check trusts each entry's guards. Classifying guards is reviewed once
  here, for every entry, and per entry after that.

## Decisions and Trade-offs

- **Withhold safety is checked from a recorded field.** Each entry records what it guards, and
  CI derives never-withhold from that, rather than trusting each entry's own marking.
  Alternative: rely on review of each new entry. Rejected because a mismarked rule is exactly
  the mistake a reviewer misses and the costliest one to make.
- **The registry covers what is already cited.** The 22 gate rules, the 17 criteria and the
  takeover rule (a new entry, named in the design). Alternative: register every prose rule now.
  Rejected as unbounded; later features add rules as they cite them.
- **Baseline keys are recorded, not rewritten.** The baseline's records keep their keys and
  the registry maps them, because the harness can't change in the same pull request as skill
  files and the baseline's comparison needs its original keys.
- **The takeover case is the demonstration.** It's a code path a normal `/execute` re-entry
  reaches, its rule guards pushing onto and rewriting another run's pull request, and the
  script that detects it already exists. Cascade recovery was the other candidate; it's left
  for a later trigger so this feature proves one shape end to end.
- **The text goes to standard error.** The lookup script's standard output is parsed by its
  callers; standard error reaches the agent in the same tool result without changing that
  contract.
