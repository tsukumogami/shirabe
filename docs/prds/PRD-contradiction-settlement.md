---
schema: prd/v1
status: Accepted
problem: |
  The koto-templated skills (/work-on, /execute, /scope, /deliver), the
  references they load, and the references /scope's hops load through /brief,
  /prd, /design and /plan give the agent incompatible instructions for the
  same situation, often disagree with what koto or a script enforces, and carry
  prose no run acts on. Later gate and ablation work has no stable list of
  these disagreements to depend on.
goals: |
  Every disagreement is listed once with a location for each side, a named
  winner and a reason, and a label saying whether it is mechanical or a policy
  call. Policy calls reach a person as decisions and stay open until answered.
  Dead prose is inventoried by category with its share of each skill's load,
  and executing the plan removes stale statements and duplicates without
  deleting the last statement of any rule still in force.
upstream: docs/briefs/BRIEF-contradiction-settlement.md
---

# PRD: Contradiction Settlement

## Status

Accepted

## Problem Statement

An agent running `/work-on`, `/execute`, `/scope` or `/deliver` reads the
skill's SKILL.md, the koto template's state directives, and whichever
references those name. Under `/scope` it also reads the references each child
hop loads. Several of those files now disagree with each other, and several
disagree with the script or template gate that actually decides what happens.

Some of the disagreements are staleness with an obvious answer, such as a
step that commits a file that moved into koto context. Others are choices
nobody has made, such as whether to force-push after a rebase or whether a
child skill opens its own pull request when `/scope` runs it. In both cases
the agent can't tell which instruction is current, and a reviewer can't tell
which one it followed. Separately, a large share of the loaded text is
history, rationale, repeated blocks, and descriptions of what koto already
does, which the agent takes no action from.

Gate work and ablation work planned after this feature need to cite individual
rules and know which statement of each is authoritative. Nothing lists the
disagreements today, so that work has nothing to depend on. The framing is in
`docs/briefs/BRIEF-contradiction-settlement.md`.

## Terms

- **Baseline pin.** The change in pull request #488 that adds
  `docs/measurement/offload-baseline/`: the koto templates these skills ship,
  pinned at commit `2a3719e`, and each skill profile's instruction-token load
  counted with `scripts/offload-baseline.sh`.
- **Load manifest.** `docs/measurement/offload-baseline/load-manifest.tsv` in
  the baseline pin: one row per file or template state a profile loads.
- **Profiles.** The five rows of the baseline pin's
  `token-baseline.tsv`: `work-on`, `execute-single-pr`,
  `execute-coordinated`, `deliver`, `scope`.
- **Raw load.** A profile's `raw` figure for the pinned commit in
  `token-baseline.tsv`. Tokens are bytes divided by four.
- **Inventory commit.** `662f6ec` on `main`. Every file under `skills/`,
  `references/` and `scripts/` is identical there to the pinned commit, so a
  line number at one is the same at the other.
- **Scoping pull request.** The pull request that carries this PRD, its BRIEF,
  DESIGN and PLAN. It changes documents only.
- **Work items.** The PLAN's items, executed in later pull requests.
- **Statement of a rule.** Prose the agent loads that tells it to do or not
  do something. A script or template gate enforcing the same rule is not a
  statement, because the agent does not read it before acting.
- **Recorded decision.** A file
  `docs/decisions/DECISION-contradiction-<identifier>-<YYYY-MM-DD>.md` naming
  the chosen option, merged to `main`.

## Goals

- A maintainer can find every statement of a rule these skills load and know
  which one is authoritative.
- A person, not an agent editing files, decides every disagreement that
  changes what the workflow is allowed to do.
- Later features can depend on one disagreement being resolved without
  waiting on all of them.
- The prose these skills load shrinks by the text nothing needs, measured
  against the baseline pin, without any rule silently disappearing.

## User Stories

- As a shirabe maintainer changing a rule, I want every place it's stated
  listed with the authoritative one named, so that I edit the right file and
  delete the stale copies.
- As the maintainer who owns workflow policy, I want each policy disagreement
  presented as a decision with options and a recommendation, so that I can
  answer it without reading the skill files myself.
- As an implementer executing the plan, I want each work item to name the
  exact spans it removes or rewrites, so that the change is mechanical.
- As a reviewer of a work item's pull request, I want the item to cite the
  script or template that decides the winner, so that I can check the fix
  without re-deriving the finding.
- As the author of a later gate feature, I want a stable identifier for each
  disagreement, so that my plan can wait on the one it needs.
- As the author of the ablation feature, I want deletions that would remove a
  rule's last statement already set aside, so that withholding is tested
  deliberately rather than done by accident.

## Requirements

### Inventory

- **R1. Coverage.** The inventory covers every file the load manifest lists
  for any of the five profiles, plus every file a template directive or a
  SKILL.md in those profiles names that the manifest omits. The DESIGN lists
  the files examined for each profile. A script, validator check or template
  gate counts as one side of a disagreement when prose contradicts what it
  enforces.
- **R2. Required items.** The inventory includes each of the following as its
  own item, unless the DESIGN merges two with a stated reason:
  1. Force-push after a rebase: a reference says force-with-lease and ask the
     user after a few failures; the state that loads it says push, record,
     and don't stop under `--auto`.
  2. Retry caps: files state different limits for the same retry loop.
  3. Retry-count keys: one panel phase increments `round` while another
     hard-codes it.
  4. Reviewer detail files: where review panels write per-reviewer detail,
     versus the wip-hygiene rule.
  5. Decision recording: a reference records decisions in wip blocks while
     `/work-on`'s SKILL.md uses `koto decisions record`.
  6. Commits of missing files: instructions to commit files (baseline, plan,
     summary) that moved into koto context.
  7. `worktree-discipline.md` tells the agent to fetch, rebase, record and
     prompt, while `/execute`'s `worktree_discipline_check` state says that
     already happened.
  8. `/execute`'s pull request title: a check asks for a type choice while
     the command it runs hard-codes `feat`.
  9. `/scope`'s reference table says some references load in all phases,
     while its Running the Workflow section says not to read references up
     front and the template names the file per state.
  10. `/plan` commits a single-pr PLAN at Draft, which its own lifecycle
      rules forbid.
  11. PLAN complexity values differ between the format reference and the
      validator's FC05, and FC11's failure message points at the reference.
  12. PLAN required sections differ across the format reference, SKILL.md,
      the structure reference, the validator's single-pr map and phase 7.
  13. `/scope`'s initial state file uses pointer and exit values that
      `resume-probe.sh` rejects.
  14. `/design`'s `spawned_from` shape differs between files.
  15. `/design`: superseded designs move to an archive directory in one file
      and stay in place in another.
  16. `/design`: one file says `/plan` adds Implementation Issues to the
      DESIGN, another says a DESIGN never carries that table.
  17. Child skills under `/scope`: whether `/brief`, `/prd`, `/design` and
      `/plan` run their own approval, push and pull-request steps, including
      `/design`'s inline-decision fallback.
  18. Issue filing under `--auto`: a split plan with no intent files GitHub
      issues and a milestone without an approval step.
  19. Writing-style and `/brief`'s jury say mechanical terms are caught
      before the jury, while nothing runs FC10 at that point.
  An R2 item is in scope even when both statements sit in one file.
- **R3. Locations.** Each item names every side as a repository-relative path
  plus a line range (`<path>#L<start>-L<end>`) or a heading
  (`<path>#<heading>`), plus a verbatim excerpt from the span that occurs
  exactly once in that file at the inventory commit, so a work item can find
  it. All locations are at the inventory commit, named
  once at the top of the inventory.
- **R4. Identifier.** Each item has a kebab-case identifier, unique within the
  inventory, that does not change when line numbers do. Later documents cite
  the identifier. The inventory is closed when the DESIGN is accepted: a
  disagreement found later is proposed as a follow-up, not added, so existing
  identifiers never move.
- **R5. Winner and reason (mechanical items).** Each `mechanical` item names
  the side whose statement survives and why. The winner may be a script or
  template gate; then one prose statement, named in the item, is rewritten to
  match it and any other prose side is deleted. Deleting every prose side is
  withholding and follows R13. Where code enforces a side, the reason names
  the script, check or template state by path.
- **R6. Classification.** Each item is `mechanical` or `policy`. An item is
  `policy` when choosing a winner changes whether the workflow pushes,
  force-pushes, merges, files issues, asks for or skips approval, retries, or
  stops. When a classifier is unsure, the item is `policy`. R2 items 1, 2, 17
  and 18 are `policy`.
- **R7. Profiles.** Each item names the profiles that load its prose sides.
- **R8. Resolved items.** An R2 item that no longer disagrees at the
  inventory commit is listed as `resolved`, with the evidence, and gets no
  work item.

### Policy calls

- **R9. Decision form.** Each `policy` item is written as a decision: the
  context, the problem, two or more options each explained, and exactly one
  recommended option with the reason. Its winner field reads `open` and
  names the recommendation; it does not name a surviving file.
- **R10. Not settled in the scoping pull request.** The scoping pull request
  settles no `policy` item. The PLAN lists every `policy` identifier as an
  open decision, and every work item that edits a `policy` item's statements
  is blocked on that item's recorded decision.

### Dead prose

- **R11. Categories.** Dead prose is a span the agent would lose nothing by
  not reading: either it contains no instruction, condition or value the
  agent uses at any state, or it repeats an instruction the same profile
  already loads from a named surviving copy. It is inventoried under four categories, each listing its entries or stating
  none were found: design rationale shipped as a prompt; duplicated blocks,
  including every copy of the retry-clearing block, with the surviving copy
  named; steps naming files that no longer exist; and text describing what
  koto or a script already does.
- **R12. Load share.** For each profile, the inventory gives the dead prose's
  size in tokens, summed from the listed spans, and its share of the
  profile's raw load. A span loaded by more than one profile counts toward
  each.
- **R13. No withholding.** No work item removes the only statement of a rule
  still in force. Each dead-prose item says whether it is the only statement;
  an item that is not names where the surviving statement is. Items that are
  go under the DESIGN heading "Withholding candidates (out of this feature)"
  for the ablation feature. A rule is still in force unless a `mechanical`
  item in this inventory shows code enforcing the opposite.

### Execution

- **R14. Baseline first.** Every work item that changes a file under
  `skills/`, `references/` or `scripts/` depends on the baseline pin having
  merged.
- **R15. Re-location.** A work item finds its spans at the commit it runs on
  by the excerpt recorded in the DESIGN, not by line number. When the excerpt
  isn't found, or is found more than once, that work item stops and reports
  the identifier; other work items continue.
- **R16. Result.** After a work item lands: each `mechanical` item it covers
  has its losing statement removed or rewritten to match the winner, and the
  winner's text is still present; each duplicate it covers is down to the
  named survivor; and no `policy` item's statements changed before its
  recorded decision merged.
- **R17. Policy items after their decision.** The maintainer who owns
  workflow policy answers each `policy` item, and whoever drives execution
  writes the recorded decision, which names the file that will carry the
  rule. A work item for that item then makes that file's statement the
  winner, writing it there when the chosen option was stated nowhere, and
  R16's result check applies to it as to a `mechanical` item. A `policy` item with no recorded decision keeps its statements
  unchanged.
- **R18. Granularity and coverage.** Each work item covers the identifiers
  of one skill (its SKILL.md, template and references) or of one policy
  decision, and names them. Every `mechanical` identifier and every dead-prose
  item that isn't a withholding candidate is covered by exactly one work
  item. No work item covers more than
  one `policy` item, so a later feature can wait on exactly the identifiers
  it needs.
- **R19. Measured effect.** A final measurement work item, which depends on
  every other work item that isn't blocked on an open decision, re-counts
  each profile with the baseline pin's script and records the before and after raw figures next
  to the R12 estimate less the withholding candidates and less the spans of
  `policy` items still undecided. A shortfall of more than 10% of that
  estimate is explained per item.

### Content

- **R20. Public content.** Nothing committed, and no pull request body, names
  a repository outside the public ones this project publishes, contains an
  absolute home path, a `wip/` path in a committed document, a session or
  instance name, or a job identifier.

## Acceptance Criteria

Scoping pull request:

- [ ] The DESIGN lists, per profile, the files examined, and the list
      contains every load-manifest file for that profile plus every file a
      loaded directive or SKILL.md names (R1).
- [ ] Each of the 19 R2 items appears as an item or as `resolved` with
      evidence, or is merged with another with a stated reason (R2, R8).
- [ ] Every location has a path and a line range or heading, and the
      inventory commit is named once at the top (R3).
- [ ] Identifiers are unique kebab-case strings (R4).
- [ ] Every `mechanical` item names a winner and reason, and every item whose
      winner is enforced by code names the enforcing path (R5).
- [ ] R2 items 1, 2, 17 and 18 are labelled `policy` (R6).
- [ ] Every item names the profiles that load its prose sides (R7).
- [ ] Every `policy` item has context, problem, at least two explained
      options, one recommendation, and a winner field reading `open` (R9).
- [ ] The PLAN lists every `policy` identifier as an open decision, and every
      work item touching a `policy` item's statements names that recorded
      decision as a blocker (R10).
- [ ] Each of the four dead-prose categories lists entries or says none were
      found, and the retry-clearing block's copies are all located with one
      survivor named (R11).
- [ ] Each profile has a dead-prose token total and a share of its raw load,
      reproducible by summing the listed spans' bytes divided by four (R12).
- [ ] Every dead-prose item says whether it is the only statement; each that
      isn't names the surviving location; each that is sits under
      "Withholding candidates (out of this feature)" and has no work item
      (R13).
- [ ] `git diff --name-only main...HEAD` on the scoping pull request lists
      only paths under `docs/` (R10, R14).
- [ ] A search of the committed files and the pull request body for
      `/home/`, `/Users/`, `wip/` (outside `wip/` itself), repository names
      outside the project's public set, session URLs and job identifiers
      finds nothing (R20).
- [ ] The scoping pull request is open against `main` with every CI job
      green.

Work items:

- [ ] Every work item that changes `skills/`, `references/` or `scripts/`
      depends on the baseline pin (R14) and says it stops and reports when
      its recorded text isn't found (R15).
- [ ] After each work item merges, a check of its covered identifiers shows
      the losing text absent, the winner's text present, and duplicates at
      their survivor (R16).
- [ ] The final re-count records before and after raw figures for all five
      profiles beside the R12 estimate, with any shortfall over 10% explained
      (R19).
- [ ] Every `policy` item with a recorded decision has a work item that
      applies the chosen option, and no `policy` item's statements differ
      from the inventory commit before its decision merged (R17).
- [ ] No work item covers more than one `policy` identifier, each lists the
      identifiers it covers, and every `mechanical` identifier and every
      non-withholding dead-prose item appears in exactly one work item
      (R18).

## Out of Scope

- Settling any policy call in the scoping pull request.
- Removing the last statement of a rule still in force (withholding). That
  belongs to the ablation feature.
- Per-state reference loading, gates, and a rule registry.
- The `/coordinate` skill.
- Contradictions within one file that aren't R2 items, unless the same rule
  is also stated in another in-scope file or enforced by code.

## Decisions and Trade-offs

- **Identifier form.** A kebab-case identifier for citing, plus source
  locations in the baseline pin's rule-key form for finding. Sequential
  numbers were rejected because they shift when items split or drop; location
  alone was rejected because a disagreement has at least two locations and a
  line range isn't readable in prose. When a rule registry exists, its ids
  replace these.
- **Where the inventory lives.** In the DESIGN. Choosing the winner per item
  is the technical decision this feature makes; the PLAN keys work items to
  the same identifiers rather than restating the inventory.
- **Code beats prose for mechanical items.** When a script or template gate
  enforces one side, that side wins unless the item is `policy`, because the
  enforced behavior is what runs today and the prose is what drifted.
- **Code enforcement doesn't make a deletion safe.** Removing the only prose
  statement of a rule that a gate enforces is still withholding: the agent
  learns the rule only by failing the gate. Whether that's acceptable is what
  the ablation feature measures.
- **Decisions recorded as files.** A policy answer is a decision record under
  `docs/decisions/`, because it is durable, reviewable, and gives a work item
  a checkable blocker.
