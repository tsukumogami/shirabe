---
schema: prd/v1
status: Draft
problem: |
  The coordinate skill sends reviews, merges, verdict edits and finishing steps
  to "a person" in places where a bound coordinator's dispatcher is meant, and
  its posture passage reads as if a merge grant lets a coordinator merge without
  review. Dispatched coordinators end up asking the workspace owner for reviews
  their dispatcher owes them, and the control on a milestone's Done can't say
  who reviews once the coordinator isn't at the root.
goals: |
  Every passage that sends a review, merge, verdict edit or finishing step names
  the reviewer: whoever dispatched the coordinator, and a person only at the
  root. Review before merge reads as something the skill always expects, a merge
  grant as an allowance that never skips it, and a director with no merge grant
  passes up its own reading of a lane's work.
upstream: docs/briefs/BRIEF-coordinator-dispatcher-review.md
---

# PRD: Coordinator Dispatcher Review

## Status

Draft

## Problem Statement

A coordinator can be started by a person or by another coordinator. The
coordinate skill calls the two roles a manager (one lane) and a director (over
managers); "coordinator" means either. When a director dispatches a manager,
the director is the one that should read the manager's finished work before it
lands. A coordinator nobody dispatched, at the root, answers to a person.

The skill's text doesn't say this consistently. shirabe#1259 reworded six
passages so a merge, close or release a bound coordinator can't take goes to
the coordinator that dispatched it, and to a person only for a root
coordinator. The Glossary's "The human" entry redirects "the human" to the
dispatching coordinator. Neither reaches the passages that say "a person", and
about seventeen of them, across `SKILL.md`, `references/state-keys.md`,
`references/loop.md`, `references/verification-checklist.md` and the template's
directives and descriptions, still send a review, a merge or a verdict to a
person:

- The Verdicts rule says a milestone roadmap's edit pull requests "must not be
  auto-merged without a person's review." It is a forgery control from
  shirabe#730: anyone using the coordinator's login can post a comment shaped
  like a verdict, so an independent review of the roadmap pull request is what
  Done rests on. A manager reads it as "a person must review my verdict" when
  its director is the independent reviewer. `state-keys.md` and the template's
  `milestone_verdict` and `milestone_reopen` steps repeat it ("a person reviews
  the verdict there").
- The posture passage ends "Never ask the human for a step the workspace already
  permits." That is an allowance phrased as a rule, and a coordinator holding a
  merge grant can read it as permission to merge without review.
- `goal_fit` says a pull request the workspace doesn't let the coordinator merge
  goes "to the person, with the merge-order table"; a held pull request goes "to
  the person"; the progress table's "Blocked on you" rows are "what waits on the
  person". A newly dispatched lane following these asks the workspace owner for
  a review its dispatcher owes it.
- The worker's brief tells a worker which landing steps its grant covers, but
  never tells a worker dispatched with a merge grant to report its finished work
  for review before it merges.
- Nothing tells a director with no merge grant to read a lane's work itself. It
  can pass the lane's report up as if it were its own recommendation.

## Goals

A person or director who dispatches a coordinator gets that coordinator's
finished work back for review before it lands, a milestone verdict pull request
included, whether or not the coordinator holds a merge grant. Review before
merge is something the skill always expects; a merge grant only decides who
merges once the review is done. A root coordinator sends the same step to a
person, so the control on Done has an independent reviewer at every level.

A director with no merge grant reads a lane's work itself and passes up its own
recommendation to merge. A newly dispatched lane sends review requests to its
dispatcher from its first report and never asks the workspace owner for one.

## User Stories

- As a director that dispatched a manager, I want the manager's milestone
  verdict pull request sent to me for review, so that Done rests on a review by
  someone other than its author and no person is asked for a review I owe.
- As a manager holding a merge grant, I want the skill to tell me that my own
  finished work goes to my dispatcher for review before I merge it, so that my
  grant decides who merges after review and never stands in for it.
- As a director dispatched by a person with no merge grant, I want to be told to
  read a lane's ready work myself and send my own reading with a recommendation,
  so that the person above me gets a director's judgment and not a forwarded
  report.
- As a worker dispatched with a merge grant, I want my brief to tell me to
  report my finished work for review before I merge anything, so that the grant
  never lets me land unreviewed work.
- As a person running a root coordinator, director or manager, I want every
  review, merge and verdict step that has no dispatcher above it to come to me,
  so that the rule needs no exception at the root.

## Requirements

### Functional

- **R1. One definition of the reviewer.** `SKILL.md`'s Glossary defines "the
  reviewer" once: for a coordinator, whoever dispatched it, which is the
  coordinator that dispatched it when its session is bound and a person only
  when it is a root coordinator; for a worker, the coordinator that dispatched
  it. The entry also says what the reviewer is owed: finished work, reviewed
  before it merges. The Glossary's "The human" entry stays and is consistent
  with it.
- **R2. Review before merge is the rule; a merge grant is the allowance.**
  `SKILL.md` states that finished work is reviewed by its author's reviewer
  before it merges, whatever grant the author holds. A coordinator's land step
  is that review for the pull requests its workers open. A pull request a
  coordinator authored itself (a milestone verdict edit, a reopen edit, a
  roadmap or document edit a local agent made from its brief) goes to the
  coordinator's own reviewer. A merge grant decides who takes the merge once
  the review is done and never lets a session skip it.
- **R3. The posture passage reads as an allowance after review.** In `SKILL.md`'s
  "What a Coordinator Never Does" and in the template's `land` directive, the
  sentence "Never ask the human for a step the workspace already permits" is
  reworded so it no longer reads as letting a merge-capable coordinator skip
  review: a step the workspace permits isn't asked for again once its review is
  done. The `land` section keeps the literal fragments "Never ask the human for
  a" and "person's confirmation is reserved for a person too", which the rule
  coverage test pins.
- **R4. The verdict rule names the reviewer and keeps the control.** The
  Verdicts passage keeps its purpose and its reasoning (a comment shaped like a
  verdict can be posted by anyone using the coordinator's login, so the review
  of the roadmap pull request is the control on Done, and the author never
  approves its own Done). It names the reviewer: the dispatcher for a bound
  coordinator, a person for a root coordinator. The coordinator still never
  merges its own milestone roadmap edit pull requests, whatever grant it holds,
  and a repository that merges them automatically still gives up that review.
  The same change is made in `references/state-keys.md` and in the template's
  `milestone_verdict` and `milestone_reopen` steps. The verdict's author line
  ("given by you or a person", in `SKILL.md` and in `milestone_verdict`) names
  the coordinator or its reviewer.
- **R5. Every "a person" is checked.** Every occurrence of "a person", "a
  person's", "the person" and "a person who" in `skills/coordinate/SKILL.md`,
  `skills/coordinate/references/*.md` and
  `skills/coordinate/koto-templates/coordinate.md` (directives, details,
  variable and evidence `description:` strings, and comments) is classified as
  one of: sends a review, merge, verdict edit, close, release or other finishing
  step where the reviewer is meant (changed to name the reviewer, or the
  dispatcher-when-bound wording); already qualified for the root (unchanged);
  a genuine person (a pause or resume owner, a person's word or order, a
  teardown, a credential or account holder, a walkthrough, the AskUserQuestion
  route, a rendering rule; unchanged). The classification is recorded in the
  plan, occurrence by occurrence.
- **R6. A changed passage points to the reviewer.** A passage changed under R5
  names "the reviewer" (or "your reviewer") and relies on the Glossary
  definition, or reuses #1259's wording for a step handed over because the
  posture denies it. It does not invent a third phrasing of the bound and root
  split.
- **R7. A granted worker reports before it merges.** `references/brief-template.md`
  and the `Named authority:` line the brief renderer writes for a worker whose
  grant names any authority tell the worker to report its finished work to its
  coordinator for review before it merges anything, and to merge only once that
  review clears it. A worker holding no named authority keeps today's line.
- **R8. A director with no merge grant gives its own reading.** When a
  coordinator receives ready work it may not merge, from a worker or a lane, it
  reviews that work itself as the land step does and sends its reviewer its own
  reading (what it checked and what it found) with a recommendation to merge or
  not, never the lane's or worker's report passed through. `SKILL.md` states
  this, and the template's `goal_fit` and `surface` directives say it where a
  pull request leaves for the merge-order table or a reserved-step need.
- **R9. A new lane addresses its dispatcher.** Every passage that tells a
  coordinator where its ready pull requests, its merge-order table, its parked
  workers' merges or its "Blocked on you" rows go names the reviewer, so a
  coordinator dispatched by another coordinator sends them to its dispatcher
  from its first report. This covers `--parked-bound`'s description in
  `SKILL.md` and the template, `goal_fit`'s hand-off, `land_merge`'s held pull
  request, `references/loop.md`'s "Blocked on you" row kind and the
  `references/state-keys.md` hold passage.
- **R10. No exception at the root.** A root coordinator, director or manager,
  sends every review, merge and verdict step to a person, its own milestone
  verdict pull requests included. No class of pull request is carved out.

### Non-functional

- **R11. Wording only.** The change adds no template state, transition, gate,
  accepts field, enum value or action. The template's fingerprint is unchanged,
  and the compatibility table changes only by recording a new `gate_scripts`
  digest if a script the template's gates or actions reach (such as the brief
  renderer, through `dispatch-worker.sh`) changes.
- **R12. Tests and CI pass.** `scripts/check-skill.sh coordinate` passes, as do
  `scripts/check-template-compat.sh` against the committed table and the
  repository's other template and public-content checks. Tests that pin a
  sentence this change rewords (the rendered `Named authority:` line, the rule
  coverage rows) are updated with it, never deleted.
- **R13. Public content.** Nothing in the change names a private repository,
  path, session, figure or measurement. Commit messages and the pull request
  carry no AI attribution.
- **R14. Vocabulary.** Text the change adds uses "manager" and "director" for the
  roles and "coordinator" for either, and avoids the words the writing-style
  rules ban.

## Acceptance Criteria

- [ ] `SKILL.md`'s Glossary has one entry for "the reviewer" that says a bound
  coordinator's reviewer is the coordinator that dispatched it, a root
  coordinator's is a person, and a worker's is the coordinator that dispatched
  it.
- [ ] `SKILL.md` states that finished work is reviewed by its author's reviewer
  before it merges whatever grant the author holds, and that a merge grant
  decides only who merges after the review.
- [ ] The sentence beginning "Never ask the human for a step" in `SKILL.md` and
  in the template's `land` section no longer stands as an unqualified rule: each
  copy says the permitted step is taken once its review is done.
- [ ] The Verdicts passage still says a milestone roadmap's edit pull requests
  must not be merged without review, still says the coordinator never merges
  them, still gives the verdict-comment forgery reason, and names the
  dispatcher as the reviewer for a bound coordinator and a person for a root
  one.
- [ ] `references/state-keys.md`'s milestone pull request passage and the
  template's `milestone_verdict` and `milestone_reopen` steps name the reviewer
  where they said "a person's review" or "a person reviews".
- [ ] The plan lists every occurrence of "a person", "a person's", "the person"
  and "a person who" in the three file sets with its class, and after the change
  no occurrence in the first class remains unchanged.
- [ ] `grep` over `skills/coordinate/SKILL.md`, `skills/coordinate/references/`
  and `skills/coordinate/koto-templates/coordinate.md` finds no sentence that
  sends a review, a merge, a verdict, a merge-order table, a parked worker's
  merge or a close to "a person" or "the person" without saying it is the root
  case.
- [ ] `references/brief-template.md` and the rendered `Named authority:` line for
  a worker holding `merge-pr` both tell the worker to report its finished work
  for review before it merges; the line for a worker holding no named authority
  is unchanged; `render-brief_test.sh` and `dispatch-worker_test.sh` assert the
  new line.
- [ ] `SKILL.md` and the template's `goal_fit` and `surface` directives tell a
  coordinator that may not merge a ready pull request to send its own reading
  and a recommendation, and not to relay the worker's or lane's report.
- [ ] `--parked-bound`'s description, `goal_fit`'s and `land_merge`'s hand-offs,
  `references/loop.md`'s "Blocked on you" row kind and the `state-keys.md` hold
  passage name the reviewer instead of "a person" or "the person".
- [ ] No text the change adds carves a pull request class out of the root rule.
- [ ] `scripts/check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md --print` prints the fingerprint
  the committed table lists at compat 2, and the committed `gate_scripts` equals
  the printed digest.
- [ ] `scripts/check-skill.sh coordinate` exits 0, and the rule coverage test
  still finds every row it found before, with no row deleted.
- [ ] The diff names no private repository, path, session name, figure or
  measurement, and contains none of the banned words.

## Out of Scope

- Naming the manager and director roles in the skill's start, its arguments and
  its record. The roles are used as words in prose only; giving them a place in
  the run is later work.
- Standing-rule provenance, who settles a step under an authority model, and
  which grants a lane holds or how a grant is chosen. This change says who
  reviews; it doesn't decide who holds what.
- A state, gate or evidence field that enforces review. The change tells a
  coordinator what to do; mechanical enforcement is separate work and would
  raise the template's compat number.
- Sending every worker pull request a manager lands to its director. A
  manager's land step is the review of its workers' pull requests; a second
  review per pull request would need a new state (see Decisions and Trade-offs).
- Teardown, which no grant covers and which still goes to a person.
- Wording on the decision path ("a person decides", "waits on a person") that
  concerns an escalated decision rather than a review, merge, verdict or
  finishing step. #1259 and the Glossary already route escalated decisions to
  the dispatcher when bound.
- Open work on the coordinate skill tracked elsewhere, beyond what this wording
  needs.

## Known Limitations

- The rule is stated, not enforced. A coordinator whose posture permits a merge
  still reaches `land_merge` from `goal_fit` with no state in between; what keeps
  its own pull requests out of that path is the text, and for a milestone edit
  the existing "never merge it" step.
- Directors and managers often run under one login. The dispatcher's review is a
  separate session's judgment, not a separate account's; where the workspace
  needs a separate account, that is the workspace's branch protection to set.

## Decisions and Trade-offs

- **Whose review a merge-granted coordinator owes.** Decided: work is reviewed
  by whoever dispatched its author. A coordinator is the reviewer of its own
  workers' pull requests, and its land step is that review; the pull requests
  it authors go to its own reviewer. Alternative: every pull request a manager
  lands goes to its director before it merges. Rejected because it needs a new
  state between `goal_fit` and `land_merge` (outside a wording change and a
  compat raise), it reviews each worker pull request twice, and the manager
  already reviews what its workers send it. Recorded as assumed: an unattended
  run settled it from the evidence.
- **Who reviews a root director's own verdict pull requests.** Decided: a
  person, by the rule (no dispatcher means a person), with no class carved out.
  Alternative: let a root director merge its own verdict edits when it holds a
  grant. Rejected because the author would approve its own Done, which is what
  the verdict rule exists to prevent.
- **How the reviewer is cross-referenced.** Decided: define "the reviewer" once
  in the Glossary and have each changed passage name it. Alternative: repeat
  "to the coordinator that dispatched you when your session is bound, and to a
  person only when you are a root coordinator" at every site. Rejected because
  the formula is already long in six places and a seventeenth copy is how the
  Verdicts sentence was missed; the formula stays where #1259 put it, for steps
  the posture denies.
- **Where the granted worker's instruction lives.** Decided: in both
  `brief-template.md` and the rendered `Named authority:` line. A worker reads
  only the rendered brief, so a change to the reference alone would never reach
  it. Changing the renderer means updating its tests and recording a new
  `gate_scripts` digest at the same compat number.
- **Pinned fragments in `land`.** Decided: reword around "Never ask the human
  for a" and "person's confirmation is reserved for a person too" rather than
  edit the rule coverage rows, so the coverage map stays as it is.
