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
  grant as an allowance that never skips it, and a coordinator that may not
  merge passes up its own reading of the work with a recommendation.
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
dispatching coordinator. Neither reaches the passages that say "a person" or
"the person". At the time of writing, a search of `SKILL.md`, the files under
`references/` and the template finds about 118 such occurrences, of which
twenty-one still send a review, a merge, a close, a verdict or the skill's own
landing step to a person (listed under R5):

- The Verdicts rule says a milestone roadmap's edit pull requests "must not be
  auto-merged without a person's review." It is a forgery control from
  shirabe#730: anyone using the coordinator's login can post a comment shaped
  like a verdict, so an independent review of the roadmap pull request is what
  Done rests on. A manager reads it as "a person must review my verdict" when
  its director is the independent reviewer. `state-keys.md` and the template's
  `milestone_verdict` and `milestone_reopen` steps repeat it.
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
- Nothing tells a coordinator that may not merge, a director with no merge grant
  being the common case, to read a lane's work itself. It can pass the lane's
  report up as if it were its own recommendation.

## Goals

A person or director who dispatches a coordinator gets that coordinator's
finished work back for review before it lands, a milestone verdict pull request
included, whether or not the coordinator holds a merge grant. "Finished work"
means what the coordinator authored: its verdict and reopen edits and any pull
request a local agent opened from its brief. Its workers' pull requests are
reviewed by the coordinator itself, at its land step, because it dispatched
them. Review before merge is something the skill always expects; a merge grant
only decides who merges once the review is done. A root coordinator sends the
same step to a person, so the control on Done has an independent reviewer at
every level.

A coordinator that may not merge, a director with no merge grant most often,
reads the work in front of it itself and passes up its own reading with a
recommendation. A newly dispatched lane sends review requests to its dispatcher
from its first report and never asks the workspace owner for one.

## User Stories

- As a director that dispatched a manager, I want the manager's milestone
  verdict pull request sent to me for review, so that Done rests on a review by
  someone other than its author and no person is asked for a review I owe.
- As a manager holding a merge grant, I want the skill to tell me that a pull
  request I authored goes to my director for review before it merges, and that
  my land step is the review of my workers' pull requests, so that my grant
  decides who merges after review and never stands in for it.
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

Terms. A coordinator is **bound** when `niwa authority check` reports its
session bound to the dispatch that launched it, as `SKILL.md`'s "What a
Coordinator Never Does" already defines; its dispatcher is the coordinator that
dispatched it. A **root** coordinator has no dispatcher: a person started it.
The **land step** is the template's `land`, `goal_fit` and `land_merge` states.

### Functional

- **R1. One definition of the reviewer.** `SKILL.md`'s Glossary has one entry,
  starting `**The reviewer** --`, that says: a bound coordinator's reviewer is
  the coordinator that dispatched it; a root coordinator's is a person; a
  worker's is the coordinator that dispatched it; and the reviewer reads
  finished work before it merges. The Glossary's "The human" entry stays, and
  its text doesn't contradict the new entry.
- **R2. Review before merge is the rule; a merge grant is the allowance.**
  `SKILL.md` states, in "Bounds and Authority", that finished work is reviewed
  by its author's reviewer before it merges whatever grant the author holds, and
  that a merge grant decides who merges after the review, never whether the
  review happens (that phrase, verbatim). It also states both halves of what
  that means for a coordinator: its land step is the review of the pull
  requests its workers open, and a pull request it authored (a milestone verdict
  edit, a reopen edit, or an edit a local agent made from its brief) goes to its
  own reviewer before it merges. It doesn't ask a coordinator to send its
  workers' pull requests to its own reviewer as well.
- **R3. The posture passage reads as an allowance after review.** In `SKILL.md`'s
  "What a Coordinator Never Does" and in the template's `land` details, the
  sentence beginning "Never ask the human for a step the workspace already
  permits" carries the words `once its review is done`, so a permitted step is
  not asked for again after its review and never skips one. The `land` section
  keeps the literal fragments `Never ask the human for a` and `person's
  confirmation is reserved for a person too`, which the rule coverage test
  pins.
- **R4. The verdict rule names the reviewer and keeps the control.** The
  Verdicts passage keeps the forgery reasoning (the sentence about anyone using
  the coordinator's login posting a comment shaped like a verdict, and that the
  review of the roadmap pull request is the control on Done). Its bold rule
  reads that a milestone roadmap's edit pull requests must not be auto-merged
  without the reviewer's review, and the passage says the reviewer is the
  coordinator that dispatched this one when bound and a person for a root
  coordinator, its own verdict edits included. The sentences "The coordinator
  never merges them" (now: whatever grant it holds) and "a repository that
  merges them automatically gives up the review that Done rests on" stay. The
  same change is made in `references/state-keys.md`'s milestone pull request
  passage and in the template's `milestone_verdict` and `milestone_reopen`
  steps. The verdict's author ("given by you or a person" in `SKILL.md`, "a
  verdict from you or a person" in `milestone_verdict`) becomes the coordinator
  or its reviewer, keeping the rule coverage fragment `A milestone reads Done
  only on a verdict from you`.
- **R5. Every "a person" is checked, and the changed sites are fixed.** Every
  occurrence of `a person`, `a person's`, `the person` and `a person who` in
  `skills/coordinate/SKILL.md`, `skills/coordinate/references/*.md` and
  `skills/coordinate/koto-templates/coordinate.md` (directives, details,
  variable and evidence `description:` strings, and comments) is classified by
  this rule: it is **changed** when the sentence sends a review, a merge, a
  close, a release, a verdict, a merge-order table, a parked worker's merge or
  the skill's landing step to that person and doesn't already say it is the
  root case; it is **already qualified** when the sentence already names the
  root case; otherwise it is **a genuine person** (a pause or resume owner, a
  person's word, order or walkthrough, a teardown, a credential or account
  holder, the AskUserQuestion route, a rendering rule, a decision escalated
  under #1259's routing). The classification, one row per occurrence with
  file, line, quoted phrase and class, goes in the implementation pull
  request's description. At the time of writing the changed sites are these
  phrases, each of which is gone from its file after the change:
  - `SKILL.md`: "in front of a person" (description), "waiting on a person's
    merge" (`--parked-bound`), "given by you or a person", "without a person's
    review".
  - `references/state-keys.md`: "goes to the person as held", "without a
    person's review".
  - `references/loop.md`: "waits on the person" ("Blocked on you").
  - `references/verification-checklist.md`: "the person merging".
  - The template: "in front of a person" (opening description), "wait on a
    person's merge" (`parked_bound`), "reserved when a person keeps the merge"
    and the close variable's "reserved when a person keeps it", "goes to the
    person" and "goes to the person as held" (comments at `goal_fit` and
    `land_merge`), "to the person, with the merge-order table" (`goal_fit`),
    "handing the close to a person" (close step description), "held pull
    request to the person" (`land_merge`), "the person merging" (`surface`),
    "verdict from you or a person" (`milestone_verdict`), "a person reviews
    the verdict there" and "a person reviews the report there".
  The teardown variable's "reserved when a person keeps it" stays.
- **R6. A changed site names the reviewer.** Each changed site's new text
  contains the word "reviewer" (and relies on R1's definition), or, for a step
  handed over because the posture denies it, reuses #1259's words "the
  coordinator that dispatched you when your session is bound, and to a person
  only when you are a root coordinator". No other phrasing of the bound and root
  split is added.
- **R7. A granted worker reports before it merges.** `references/brief-template.md`'s
  description of the `Named authority:` line, and the line itself as the brief
  renderer writes it for any non-empty grant, tell the worker to report its
  finished work to the coordinator for review before it merges anything, and
  to merge only once that review clears it. The rendered line carries the
  words `for review before you merge`. The line for a worker holding no named
  authority is byte-for-byte unchanged.
- **R8. A coordinator that may not merge gives its own reading.** When a
  coordinator holds ready work it may not merge, from a worker or a lane, it
  reviews that work at its land step, as it does any pull request, and sends its reviewer its own
  reading, never the worker's or lane's report passed through. The reading
  names the pull request, the head it checked, what it checked (the board, the
  worker's review round, goal fit against the brief or the milestone's
  Evidence), what it found, and its recommendation with the reason. `SKILL.md`
  and the template's `goal_fit` and `surface` directives say this, each with the
  words `your own reading`.
- **R9. A new lane addresses its dispatcher.** The passages that say where a
  coordinator's ready pull requests, merge-order table, parked workers' merges,
  held pull requests and "Blocked on you" rows go are the R5 sites in
  `--parked-bound`/`parked_bound`, `goal_fit`, `land_merge`, `surface`,
  `references/loop.md`, `references/state-keys.md` and
  `references/verification-checklist.md`; each names the reviewer, so a
  coordinator dispatched by another coordinator sends them to its dispatcher
  from its first report. No passage in the three file sets asks "the owner" or
  "the workspace owner" for a review.
- **R10. No exception at the root.** A root coordinator, director or manager,
  sends every review, merge and verdict step to a person, its own milestone
  verdict pull requests included. The Verdicts passage says so in positive
  terms, and no text the change adds names a class of pull request a root
  coordinator may merge without a person's review.

### Non-functional

- **R11. No template structure change.** The change adds no template state,
  transition, gate, accepts field, enum value or action, so the template's
  fingerprint is unchanged. The brief renderer (`render-brief.sh`) changes
  under R7 and is reached from the template's actions through
  `dispatch-worker.sh`, so the compatibility table records the new
  `gate_scripts` digest at the same compat number, and nothing else in the
  table changes.
- **R12. Tests and CI pass.** `scripts/check-skill.sh coordinate`,
  `scripts/check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md` and
  `scripts/check-public-content.sh` pass. Tests that pin a sentence this change
  rewords (the rendered `Named authority:` line in `render-brief_test.sh` and
  `dispatch-worker_test.sh`, the rule coverage rows) are updated with it, never
  deleted. The coordinate evals mention "the human" for the merge-order table;
  the Glossary covers those, and they aren't changed.
- **R13. Public content.** Nothing in the change names a private repository,
  path, session, fleet figure or measurement, and commit messages and the pull
  request carry no AI attribution.
- **R14. Vocabulary.** Prose the change adds says "manager" and "director" for
  the roles and "coordinator" for either, and uses none of the words the
  repository's writing-style rules ban (`skills/writing-style/rules.yaml`).

## Acceptance Criteria

- [ ] `grep -c '^- \*\*The reviewer\*\* --' skills/coordinate/SKILL.md` prints
  1, and that entry names the coordinator that dispatched it (bound), a person
  (root) and a worker's coordinator.
- [ ] `SKILL.md`'s "Bounds and Authority" contains `never whether the review
  happens`, says the land step is the review of the coordinator's workers' pull
  requests, and says a pull request the coordinator authored goes to its own
  reviewer before it merges.
- [ ] `SKILL.md` doesn't tell a coordinator to send its workers' pull requests to
  its own reviewer for a second review.
- [ ] Both copies of the sentence beginning `Never ask the human for a step the
  workspace already permits` (in `SKILL.md` and in the template's `land`
  section) contain `once its review is done`.
- [ ] The template's `land` section still contains `Never ask the human for a`
  and `person's confirmation is reserved for a person too`.
- [ ] The Verdicts passage contains the forgery sentence (`Anyone using the
  coordinator's login can post a comment shaped like a verdict`), its bold rule
  says `without the reviewer's review`, it still says the coordinator never
  merges them and that a repository merging them automatically gives up the
  review, and it says a root coordinator's verdict pull requests, its own
  included, are reviewed by a person.
- [ ] `references/state-keys.md`'s milestone pull request passage and the
  template's `milestone_verdict` and `milestone_reopen` steps contain
  "reviewer" where they said "a person's review" or "a person reviews".
- [ ] `milestone_verdict` still contains `A milestone reads Done only on a
  verdict from you`.
- [ ] For each changed-site phrase listed in R5, `grep -F` of that phrase in its
  named file finds nothing, except the teardown variable's "reserved when a
  person keeps it", which is still present.
- [ ] Each changed site's new text contains "reviewer" or #1259's
  `the coordinator that dispatched you when your session is bound` wording.
- [ ] The implementation pull request's description has a table with one row
  per `grep -nE "a person|the person"` hit in the three file sets after the
  change, each with file, line, phrase and class, and no row is in the changed
  class.
- [ ] `grep -rniE "the (workspace )?owner" skills/coordinate/SKILL.md
  skills/coordinate/references skills/coordinate/koto-templates/coordinate.md`
  finds no line asking for a review.
- [ ] `references/brief-template.md` says a worker holding a named authority
  reports its finished work for review before it merges.
- [ ] `render-brief_test.sh` asserts that the `Named authority:` line for a grant
  of `merge-pr`, and for a grant of `close-issue`, contains `for review before
  you merge`, and that the line for no named authority equals its current text;
  `dispatch-worker_test.sh` asserts the same new line where it asserted the old.
- [ ] `SKILL.md`, the template's `goal_fit` and the template's `surface` each
  contain `your own reading`, and `SKILL.md`'s passage lists what the reading
  names (the pull request, the head checked, what was checked, what was found,
  the recommendation and reason).
- [ ] `scripts/check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md --print` prints the fingerprint
  the committed table lists at compat 2, the committed `gate_scripts` equals the
  printed digest, and `git diff` of `coordinate.compat.json` touches only the
  `gate_scripts` line.
- [ ] `scripts/check-skill.sh coordinate` and `scripts/check-public-content.sh`
  exit 0, and `rule-coverage.tsv` has the same row IDs before and after.
- [ ] The diff's added lines contain none of `robust`, `leverage`,
  `comprehensive`, `holistic`, `facilitate`, `tiered`, no emoji, no
  `Co-Authored-By`, no `measurement`, and no path or name from a private
  repository.

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
- The coordinate-open and takeover fixes tracked in shirabe#1442 and
  shirabe#1443.

## Known Limitations

- The rule is stated, not enforced. A coordinator whose posture permits a merge
  still reaches `land_merge` from `goal_fit` with no state in between; what keeps
  its own pull requests out of that path is the text, and for a milestone edit
  the existing "never merge it" step.
- A director and its managers may run under one login. The dispatcher's review
  is then a separate session's judgment, not a separate account's; the
  requirement still applies, and where the workspace needs a separate account,
  that is its branch protection to set.
- The line numbers in R5 and in the pull request's table describe the files at
  the time of writing; the phrases are what the criteria check.

## Decisions and Trade-offs

- **Whose review a merge-granted coordinator owes.** Decided: work is reviewed
  by whoever dispatched its author. A coordinator is the reviewer of its own
  workers' pull requests, and its land step is that review; the pull requests
  it authors go to its own reviewer. Alternative: every pull request a manager
  lands goes to its director before it merges. Rejected because it needs a new
  state between `goal_fit` and `land_merge` (outside a change with no template
  structure change, and a compat raise), it reviews each worker pull request
  twice, and the manager already reviews what its workers send it. An
  unattended run settled this from the evidence; the scoping pull request is
  where the dispatcher confirms or reverses it.
- **Who reviews a root director's own verdict pull requests.** Decided: a
  person, by the rule (no dispatcher means a person), with no class carved out.
  Alternative: let a root director merge its own verdict edits when it holds a
  grant. Rejected because the author would approve its own Done, which is what
  the verdict rule exists to prevent.
- **How the reviewer is cross-referenced.** Decided: define "the reviewer" once
  in the Glossary and have each changed passage name it. Alternative: repeat
  "to the coordinator that dispatched you when your session is bound, and to a
  person only when you are a root coordinator" at every site. Rejected because
  the formula is already long in six places and one more copy per site is how
  the Verdicts sentence was missed; the formula stays where #1259 put it, for
  steps the posture denies.
- **Where the granted worker's instruction lives.** Decided: in both
  `brief-template.md` and the rendered `Named authority:` line. A worker reads
  only the rendered brief, so a change to the reference alone would never reach
  it. Changing the renderer means updating its tests and recording a new
  `gate_scripts` digest at the same compat number.
- **Pinned fragments in `land`.** Decided: reword around `Never ask the human for
  a` and `person's confirmation is reserved for a person too` rather than edit
  the rule coverage rows, so the coverage map stays as it is.
- **The occurrence table's home.** Decided: the implementation pull request's
  description, which a reviewer reads beside the diff. Alternative: the PLAN.
  Rejected because the PLAN is deleted when its work completes and isn't part
  of the shipped change.
