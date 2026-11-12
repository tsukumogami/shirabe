---
schema: design/v1
status: Draft
problem: |
  work-on's closing_keyword gate at pr_creation accepts only a pull request
  body that closes its issue. A pull request that delivers one planned step
  of its issue, or follows an approved deferral, references the issue
  without closing it, so the gate exits 1 and the run ends at done_blocked
  instead of going on to CI monitoring.
---

# DESIGN: work-on partial delivery

## Status

Draft

## Context and Problem Statement

work-on's `pr_creation` state runs a `closing_keyword` gate on the pull
request it just opened. For an issue in the same repository the gate greps the
body for `close`, `fix` or `resolve` (in any of their forms) followed by
`#N`. For an issue in another repository it runs
`skills/work-on/scripts/check-closing-keyword.sh`, which wants the qualified
form `owner/repo#N` and refuses a reference that would close the wrong issue.
Either way, a body that only references the issue fails with exit 1, and the
transition on that exit sends the run to `done_blocked` rather than to
`ci_monitor`. No variable, evidence field or flag changes what the gate asks
for. The only runs it skips are free-form runs with no issue number and
`/execute` children on a shared branch, which open no pull request of their
own.

That's right for the common case, and wrong for two others.

The first is an issue delivered in more than one pull request on purpose.
#1735 is step one of #1646's two steps: it lands the validator and transition
side, and the second step can only merge after a release carries the first.
Its body says `Refs #1646`, because #1646 stays open until the second step
lands. The gate exited 1 on that body at `pr_creation` (#1736). Nothing in
#1646's criteria was set aside; the split was the plan from the start.

The second is a run that holds an approved deferral. A run that can't meet one
of its issue's acceptance criteria asks at `deferral_approval`, and a person
approves or rejects setting it aside. When it's approved, the pull request
should reference the issue without closing it, since the deferred criterion is
still open there. #1549 did that (`Part of #1548`) after its deferral was
approved, and the gate exited 1 anyway (#1550). The approval was already
reviewed earlier in the same run, but the gate doesn't read it.

In both cases the run's honest body can't pass. The way past is to write
`Fixes #N` only to satisfy the gate, which closes an issue that's still partly
open, or to stop the run at `done_blocked` and finish it by hand.

This design works out how a run declares that its pull request doesn't close
its issue, who may make that declaration, what the gate then accepts and
refuses on both the same-repository and cross-repository paths, and how the
deferral case enters through the same mechanism or why it doesn't.

Out of scope: closing the issue when its last step lands, which keeps using
the ordinary closing keyword; `/execute`'s shared-branch path and `multi-pr`
plans; free-form runs with no issue number; and any change to which keywords
count as closing or to the cross-repository old-name lookups.

## Decision Drivers

- **Both cases, or a stated reason.** The planned split (#1735, #1736) and the
  approved deferral (#1549, #1550) fail at the same gate on the same kind of
  body. A mechanism keyed only on the deferral record misses the split, which
  has no deferral.
- **No self-reported deferral.** The template doesn't let a run set an
  acceptance criterion aside on its own say; that only happens through
  `deferral_approval`. A declaration that an issue stays open mustn't become a
  second way around that rule.
- **The gate consults nothing the run can forge through koto.** A gate whose
  command reads only template variables can't see evidence submitted on the
  same tick. A gate whose command reads the run's state log does see the
  records already logged there, but most of them are the run's own writes. So
  whatever the gate consults has to be either a template variable fixed at
  init or a record in the state log that the run can't produce through koto,
  which is the engine's own `transitioned` event. Events the run can produce
  may only cancel an approval, never grant one.
- **A declared run still has a body rule.** Dropping the closing keyword
  requirement shouldn't leave the body free to say nothing about the issue, or
  free to close it after all.
- **Both gate paths.** The same-repository inline check and the
  cross-repository script both need the new behavior, whether they stay
  separate or merge.
- **The existing contracts hold.** The script's exit codes (0 passes, 1
  refuses, 2 is a usage error, 3 is a failed lookup) and the routes on them
  stay. `closing-keyword-gate_test.sh` pulls the gate command out of the
  template and runs it against a `gh` stub, and it has to keep working.
- **The text moves with the behavior.** The `pr_creation` directive, the
  `done_blocked` failure reason, `references/phases/phase-6-pr.md`,
  `references/finishing-obligations.md` and the SKILL.md passages on the
  closing obligation describe what the gate wants, so they change with it.

## Considered Options

### Decision 1: Where a non-closing delivery comes from

The gate needs a fact that tells it a pull request leaves its issue open.
That fact can't come from the run itself, since the template lets no run set
an acceptance criterion aside on its own say, and it has to be readable when
the gate runs. The two cases have different owners. A planned split is known
before the run starts: #1735's body says step two merges only after a release
carries step one. An approved deferral is learned partway through, at
`deferral_approval`.

The template constrains where the fact can live. Variables are fixed at init
unless declared `rebind: true`, and an attach resets every rebindable variable
it doesn't pass. `VERIFICATION` and `VERIFICATION_DEFERRAL_REASON` are the
precedent for a non-rebindable value, set by the invocation, that a
`pr_creation` gate reads (`skills/work-on/koto-templates/work-on.md:2545`).
Evidence, context writes and recorded decisions are all logged as the run's
own writes; the engine's `transitioned` event is the one record the run can't
produce. `pre_pr_evidence` has exactly two engine in-edges, from
`finalization` on `ready_for_pr` (`work-on.md:2157`) and from
`deferral_approval` on approval (`work-on.md:2211`), and it's the only way
into `pr_creation`. A recount at `pr_precheck` can send an approved run back to
`finalization`, where it can then submit `ready_for_pr`, so an earlier
approval can go stale.

The text disagrees with itself on the deferral body.
`skills/work-on/references/phases/phase-6-pr.md:48-52` makes `Fixes #<N>`
unconditional, and `phase-6-pr.md:109-111` asks an approved-deferral body to
name the criterion left undone and where it's tracked. Read together, they
keep `Fixes #N`. #1550 asks for `Part of #N`. The work-on PRD requires that
/work-on never report an issue done while any acceptance criterion is unmet or
deferred, and #1549 kept the remaining work on #1548.

Key assumptions:

- An unattended run's answer at `deferral_approval` stays as it is today. The
  `--auto` passage (`skills/work-on/SKILL.md:862-868`) doesn't list that gate.
  Open question: what an `--auto` or dispatched run does at
  `deferral_approval`. If it may never approve, every genuine deferral in an
  unattended run, and every split whose scope isn't recorded at init, ends at
  `done_blocked`.
- GitHub may close an issue from a closing keyword in a commit that reaches
  the default branch, so the non-closing check reads the pull request's title
  and commit messages as well as its body. Open question: whether GitHub
  closes an issue from a branch commit message under the repository's merge
  settings. Nothing in the repository verifies it. With a squash merge, the
  default squash message can carry the branch's commit messages and the pull
  request's title onto the default branch, so a closing keyword in either can
  close the issue that way. If GitHub closes nothing from either, the commit
  check is a cheap precaution.
- The split declaration carries a stated reason that names the step and what
  is left to a later pull request, and it's refused without one, the way
  `work-on-open.sh` refuses `--verification=hosted-ci` without a reason.
  Decision 4 makes that reason mandatory, and Decision 7 settles whether the
  body repeats it.
- No reader besides the gate needs the delivery fact. /coordinate reads a
  work-on leg's outcome, step, reason and pull request, with no delivery field
  (`skills/coordinate/koto-templates/coordinate.md:867`), and the completion
  cascade reads GitHub's issue state
  (`skills/work-on/scripts/run-cascade.sh:172-210`). Open question: whether
  /coordinate's pick rule (`skills/coordinate/references/loop.md:118-119`),
  which counts only a pull request that closes the issue, should read a
  delivery record. If it should, an engine-written `delivery` context key on
  the two edges into `pre_pr_evidence` can be added on top without changing
  the gate.
- Hand edits to the state log are outside the threat model, as they are for
  every existing gate that reads it (`probe.sh`, `fix-kind.sh`,
  `decision-reasons.sh`).

#### Chosen: An init declaration for the split and the engine's deferral transition, feeding one non-closing rule

Two sources, each held by the authority that already owns its case, feed one
body rule inside the existing `closing_keyword` command.

1. **The planned split is declared at init.** A new variable `DELIVERY`
   (`values: [closes, partial]`, `default: closes`, not rebindable) is set from
   a typed `--delivery=partial` token, which `work-on-open.sh` maps the way it
   maps `--verification`, with its stated reason. The invocation's author sets
   it: a person typing the flag, or /coordinate dispatching with a new exact
   `--delivery=partial` value on the work-on row of
   `skills/coordinate/references/entry-points.tsv:67`. The run copies the
   token only as typed and never adds it, and nothing in the run can set it
   later. No PLAN step field is forwarded: a `plan/v2` step at
   `tracking_level: none` already carries no issue number and passes the gate,
   and `multi-pr` plans are out of scope. `fix-round.sh` copies the variable
   into a fix round unchanged.
2. **Declaring a split doesn't loosen finalization.** The `finalization`
   directive's `ready_for_pr` sentence (`work-on.md:3981`) gains one
   qualification: with `DELIVERY=partial`, "every acceptance criterion" means
   every criterion the declared step owns, as its reason states it. A
   criterion of that step the run can't meet still goes to
   `deferral_requested` and a person at `deferral_approval`. A split with no
   recorded scope isn't declared at init; its later-step criteria are unmet,
   so it goes through `deferral_approval`.
3. **The approved deferral reaches the rule through the engine's record, not
   the variable.** The gate reads the run's state log and treats the pass as
   approved when the latest `transitioned` or `directed_transition` arrival
   into `pre_pr_evidence` is a `transitioned` event from `deferral_approval`,
   and no later arrival into `finalization` or `deferral_approval` (by
   `transitioned`, `directed_transition` or `rewound`) exists. A directed
   arrival never counts as approved, and `rewound` events aren't counted as
   arrivals into `pre_pr_evidence`. An absent log, or no approved arrival,
   means closing mode. A log that exists but can't be parsed holds the state.
   The deferral doesn't write `DELIVERY`, and can't: variables are fixed at
   init, and a rebindable one would hand the run a way to declare itself
   partial. A fix round's own log holds no approval, so a round that still
   leaves the criterion unmet asks again.
4. **One body rule serves both.** When `DELIVERY` is `partial` or the pass is
   approved, `closing_keyword` calls `check-closing-keyword.sh --issue N
   --non-closing`, adding `--repo` for an issue elsewhere. That mode refuses
   every form the script already knows to close N (its own-repository forms,
   the qualified forms and their links, old names), requires a plain
   reference, and reads the pull request's title and commit messages as well
   as its body. Exit codes 0, 1, 2 and 3 and their routes don't change, and
   `--issue N` with neither `--repo` nor `--non-closing` stays a usage error.
   With neither source, the gate behaves exactly as it does today. The
   command stays one single-quoted line, so the test harness still extracts
   it, and the log read lives in the script, not in inline jq.
5. **An approved deferral's body writes `Part of #N`.** It never uses a
   closing form, and the person approving doesn't choose one, which settles
   the text in #1550's favor. `phase-6-pr.md:48-52` becomes the closing case
   only, and `phase-6-pr.md:109-111` says the undone criterion stays open on
   issue N. A person who wants the criterion tracked elsewhere edits the issue
   and files the follow-up. Then nothing on issue N is deferred, and
   `Fixes #N` follows the ordinary path.

Each case keeps its owner. A planned split belongs with the invocation, beside
`VERIFICATION`: it's fixed before any work, so it can't be a reaction to a
criterion the run then missed. An approved deferral is learned at
`deferral_approval`, and the only record of it the run can't write is the
engine's transition out of that state. Neither source gives the run a new way
to set a criterion aside, since `DELIVERY` changes which body the gate
accepts, not what `finalization` accepts, and the deferral half goes through
the existing human gate. Misusing either one leaves an issue open, which a
person sees and closes in one step. The opposite failure, an issue closed
with work missing, is the one the gate exists to stop.

The option covers both cases, as the first driver requires; a deferral-only
mechanism would miss the split. Both gate paths go through the script's new
mode. The change is two variables, their two tokens and two script modes, one
of them the log read, and of the gates it touches only the `closing_keyword` command, so
the five `pr_creation` edges the command feeds (four to `ci_monitor`, one to
`done_blocked`), the name-based stubs in the other suites and every existing
case in `closing-keyword-gate_test.sh` stay as they are. `Part of #N` follows the PRD
and how #1549 was actually handled. Letting the approver choose `Fixes #N`
would put a closing form back on an issue with a deferred criterion, on a
field the run submits.

#### Alternatives Considered

- **A run-time human gate for both cases.** Route the planned split through
  `deferral_requested` and `deferral_approval` too, with a record-only
  `deferral_kind: criterion | phased_step`, so one engine transition is the
  only source. Rejected because its main case works only if an unattended run
  may approve at that gate, which stays an open question, and a background
  run can't wait for a person
  (`skills/coordinate/references/brief-template.md:230-231`). It also files a
  split where nothing was set aside under a state named for a deferred
  acceptance criterion (`work-on.md:2170-2176`), and it asks again on every
  recount and fix round for a decision the plan already made. Its deferral
  half is kept as the chosen option's deferral source, and it stays the route
  for a split whose scope isn't recorded at init.
- **One engine-written `delivery` context key.** `context_assignments` would
  write `delivery: "{{DELIVERY}}"` on `ready_for_pr` and `delivery: partial`
  on the approved edge, and the gate would read it back from the
  `transitioned` events, checking for later writes. Rejected for now because
  the run can overwrite any context key outside the engine's own namespace,
  so the gate would have to read the log anyway, and no reader needs the key
  today. It can be added on top without touching the gate if /coordinate's
  pick rule comes to read a delivery record.
- **The approved deferral keeps `Fixes #N` and files a follow-up issue.**
  Only the split gets a mechanism, and `phase-6-pr.md` stays as written.
  Rejected because closing the issue reports it done while a criterion is
  deferred, which the PRD forbids. Nothing in the run files or checks the
  follow-up, and #1549 kept the work on #1548.
- **The approver chooses the closing form at `deferral_approval`.** A
  required `issue_disposition: stays_open | follow_up` field would decide the
  body. Rejected because the field would be submitted by the run, like
  `approval_decision`, and a `follow_up` value would close an issue with a
  deferred criterion on the run's word. Moving a criterion is an edit to the
  issue, which a person makes where it shows.
- **A committed PLAN step as the split's scope record.** A
  `--delivery-step=<PLAN>:<N>` value, checked by a gate at `finalization`
  that the PLAN step exists. Rejected because it can't bind the step to the
  issue (`docs/plans/PLAN-skeleton-commit.md` never names #1646). It also
  depends on `multi-pr` plans, which this design leaves out of scope, and on
  PLAN files that are deleted when the work completes
  (`phase-6-pr.md:88-89`), and it adds a gate to the `ready_for_pr` edge that
  every suite driving that edge would have to stub.
- **Body-only refusals.** Non-closing mode refuses closing forms of N in the
  pull request body only, with no title or commit reads. Rejected because the
  title and commit messages can reach the default branch through a squash
  merge, so a body-only check leaves those paths open.

### Decision 2: What the gate requires of a non-closing body

Once a run holds a non-closing delivery, Decision 1 has already fixed three
things: every form the script knows to close N is refused in the body, the
title and the commit messages; a run without a non-closing delivery keeps
today's gate; and an approved deferral writes `Part of #N`. What's left is the
other half of the body rule. A declared run still has to say something about
its issue, so the question is which plain reference the body must carry, in
which forms and where, plus what happens to closing keywords for other issues
and what a refusal tells its reader.

Today's pass side gives the shapes. The inline expression reads the body a
line at a time, case-insensitively, as a keyword, an optional colon,
whitespace, then `#N` not running into more digits (`work-on.md:2515`). The
script accepts `<keyword> owner/repo#N` with a word-start anchor and, for an
issue elsewhere, the link
`<keyword> [owner/repo#N](https://<host>/owner/repo/issues/N)`. When the issue
is in the pull request's own repository it accepts the bare or the qualified
form (`skills/work-on/scripts/check-closing-keyword.sh:197-208`,
`check-closing-keyword.sh:236-240`). A bare `#N` in a cross-repository run
names the pull request's own repository's issue N
(`check-closing-keyword.sh:12-15`). Exit 1 routes to `done_blocked`, which is
terminal (`work-on.md:2644-2649`, `work-on.md:3146-3148`), so every refusal
ends the run, and the person who finishes it reads the script's stderr.

The repository already prescribes one non-closing form. The design skill
tells a pull request spawned from an issue to use `Ref #<N>` rather than
`Fixes`, because the issue stays open until implementation completes
(`skills/design/references/phases/phase-6-final-review.md:296`,
`phase-6-final-review.md:392-393`), and its evals pin that
(`skills/design/evals/evals.json:247`, `evals.json:252`). Merged commit bodies
in the repository use `Refs #N` 16 times, `Part of #N` 7 times and `Ref #N` 4
times, never with a colon, and several mix a closing keyword for one issue
with a plain reference to another: `Fixes #494` with `Refs #490` (#580),
`Closes #206` with `Part of #205` (#210), six `Fixes` lines with
`Part of #949` (#1071). No other code parses these words; the plan
validator's PR-body closure check reads only close, fix and resolve
(`crates/shirabe-validate/src/checks.rs:2620-2622`). Issue references belong
in Part 2, not the title (`references/pr-body-conformance.md:49-50`), and
`phase-6-pr.md:48` puts the closing line there.

Key assumptions:

- GitHub treats `Ref`, `Refs` and `Part of` as plain mentions: its closing
  keywords are close, fix and resolve and their forms, with an optional
  colon. If that's wrong, a body that passes this rule could close the issue
  on merge, and the refusal side wouldn't catch it, since it refuses only the
  known closing forms.
- GitHub records a cross-reference on the issue's timeline for a mention in
  the body, whatever word comes before it. If not, /coordinate's timeline read
  (`skills/coordinate/references/loop.md:111-115`) could miss a non-closing
  pull request.
- A run writes its body to the `pr_creation` directive, which names the three
  accepted words. If runs often write `See #N` or `Related to #N` anyway,
  those bodies end at `done_blocked`, and the word list should be revisited.
- Open question: whether a reference that appears only in the pull request's
  title creates GitHub's cross-reference event. The rule requires the
  reference in the body either way. If a title reference does link the issue,
  the rule refuses a pull request GitHub already links, and the fix is one
  line in Part 2.
- Open question: how /coordinate's pick rule (`loop.md:118-119`) treats an
  open pull request that references its issue without closing it. The rule
  counts an open or merged pull request that closes the issue as the unit
  taken or done, and says nothing of a non-closing one. If an open non-closing
  pull request should count as taking the unit, the pick rule needs its own
  change, and the body form chosen here is what it would read.

#### Chosen: Three words, mirrored on the closing-mode pass set, in the body

1. **The accepted words are `Ref`, `Refs` and `Part of`.** Matching is
   case-insensitive. An optional colon may follow the word, then whitespace,
   the same separator closing mode passes on (`Refs: #N`, `Part of: #N`).
   `Part` and `of` are separated by whitespace on one line. The word must
   start a word, so `prefs #42` doesn't count, and `#N` must not run into more
   digits, so `Refs #421` doesn't satisfy issue 42. The reference may stand
   anywhere on a line, followed by anything (`Refs #636.`,
   `Refs #841, part of #824.`), and the body is read a line at a time, like
   the pass side today. `See`, `Related to`, `References`, a bare `#N` and an
   issue URL alone don't satisfy the rule. They aren't refused either, since
   none of them closes anything.
2. **The accepted forms are closing mode's, with the word swapped in.** In a
   same-repository run (`ISSUE_REPO` empty, or naming the pull request's own
   repository in any case), `<word> #N` and `<word> <PR repo>#N` both count,
   as the script's same-repository branch already accepts both. In a
   cross-repository run only `<word> <ISSUE_REPO>#N` or the matching link
   `<word> [<ISSUE_REPO>#N](https://<host>/<ISSUE_REPO>/issues/N)` counts. A
   bare `<word> #N` there names this repository's issue N, so it isn't the
   reference. The approved deferral's `Part of #N` reads as
   `Part of <ISSUE_REPO>#N` for an issue elsewhere.
3. **The reference must be in the body.** The title and commit messages are
   read for refusals only, since a closing keyword there may close the issue.
   A reference that appears only in the title or a commit doesn't satisfy the
   rule.
4. **Closing keywords for other issues are allowed, as in closing mode.**
   `Fixes #M` for M other than N, and `Fixes other/repo#N` for a repository
   that isn't an old name of this one, pass as they do today. The old-name
   lookups and their exit 3 hold stay as they are. The gate is about issue N
   only, and the plan validator already checks other closers against the
   PLAN doc.
5. **A refusal names what to fix.** For a closing form of N, the script's
   message gives the matched text as it stands; where it stands (the body,
   the title, or the commit by its short SHA, for each location that holds
   one); that the run doesn't close its issue and why (a declared partial
   delivery or an approved deferral), so the reader doesn't "fix" the body by
   adding `Fixes #N`; and the line to write instead. For a missing reference,
   it says the body has no `Ref`, `Refs` or `Part of` reference to the issue
   in this run's form, and gives the exact line to add (`Part of #N`, or
   `Part of <ISSUE_REPO>#N`). The `done_blocked` failure reason is fixed
   template text that can't tell the modes apart, so it states both readings
   and points at the gate's message. The exact wording is left to the
   implementation.

A declared run still has a body rule, and this one makes the body say the
pull request delivers part of the issue, in the words the repository already
uses for exactly that. `Ref` is the only form a skill prescribes, and `Refs`
and `Part of` are the two the repository's history uses most. The set takes
both honest bodies, #1735's `Refs #1646` and #1549's `Part of #1548`, and the
deferral text Decision 1 chose.

Mirroring closing mode's pass shapes keeps one picture of the gate. The same
repository-qualification rule, separator, anchors and line-by-line reading
apply in both modes; only the word changes. So the script reuses its bare,
qualified and qualified-link shapes with a second word list, and the
cross-repository rule that a bare `#N` names the wrong issue carries over
unchanged. The body is where a reviewer reads a pull request's relation to
its issue, and where every prescription puts the reference. Allowing other
issues' closers keeps the refusal side to what closes issue N. That's the
script's own principle (`check-closing-keyword.sh:39-40`: only forms measured
to close are refused), and it matters more here because a refusal is
terminal.

The accepted trade-off is narrowness. A body that says only `See #N` or
`Related to #N` ends at `done_blocked`. The directive names the three words,
so a run that follows it never meets that, and a word can be added later
without touching anything else.

#### Alternatives Considered

- **A wider word list.** The same rule with `References`, `Related to`,
  `Relates to` and `See` added. Rejected because none of them has a
  prescriptive use in the repository, `See` appears almost only in prose,
  where it reads as a passing mention rather than a partial delivery, and each
  extra word is one more thing the directive, the docs and the script have to
  keep in step.
- **Any non-closing mention of the issue.** Any `#N`, `owner/repo#N` or issue
  URL in the body counts, since the closing forms are refused separately.
  Rejected because it doesn't say the issue stays open. A body whose only
  mention is "unrelated to #N" passes, which leaves the body free to say
  nothing about the delivery, against the driver that a declared run still
  has a body rule.
- **A pull request in non-closing mode closes nothing.** The chosen reference
  rule, plus a refusal of every closing keyword whatever issue it names,
  which would also make the old-name lookups unnecessary in this mode.
  Rejected because it refuses forms that don't close issue N, so `Fixes #M`
  ends the run at `done_blocked`. The repository's history mixes such closers
  with plain references routinely, and the script's rule is to refuse only
  what closes.
- **The reference may stand in the body, the title or a commit.** The chosen
  words and forms, satisfied by any source the refusal side reads. Rejected
  because it leaves Part 2 free to say nothing about the issue, against where
  `phase-6-pr.md` and the PR-body conformance rules put issue references. The
  PR-title rule also already refuses an issue number as a title scope
  (`crates/shirabe-validate/src/pr_body.rs:250-255`).

### Decision 3: How the gate picks its mode, and the script and test surface behind it

Decisions 1 and 2 fix most of the shape. The non-closing rule lives inside
the existing `closing_keyword` command (`work-on.md:2513-2515`), which stays
one single-quoted line. Non-closing mode always runs
`check-closing-keyword.sh --issue N --non-closing`, adding `--repo` for an
issue elsewhere. The approved-pass read of the state log lives in the script,
not in inline jq. A run with neither `DELIVERY=partial` nor an approved pass
behaves as it does today, and exit codes 0, 1, 2 and 3 keep their routes
(`work-on.md:2600-2649`).

That leaves one real choice. A same-repository run with `DELIVERY=closes`
takes today's inline grep, which never starts the script
(`check-closing-keyword.sh:6-10`). But only the script may read the log, and
only the log says whether this pass came out of an approved deferral. So the
command has to ask the script something before it knows which branch to run.

Today's harness constrains the answer.
`skills/work-on/scripts/closing-keyword-gate_test.sh:45-53` pulls the command
out by its `closing_keyword:` key and the next `command:` line, then strips
one quote at each end. `run_gate` (`closing-keyword-gate_test.sh:120-128`)
substitutes only `ISSUE_NUMBER`, `ISSUE_REPO` and `PLUGIN_ROOT`. The `gh` stub
(`closing-keyword-gate_test.sh:71-111`) prints the body for any `pr view`
call and adds the URL only when the field list is exactly `url,body`
(`closing-keyword-gate_test.sh:108`). The check at
`closing-keyword-gate_test.sh:186-198` pins that a same-repository run makes
one `gh` call, `pr view --json body --jq .body`, and never asks for `url`.
The script has no test file of its own: its usage refusals live in the gate
test (`closing-keyword-gate_test.sh:548-563`), and `--issue 42` alone exiting
2 is already pinned there. The routing suites replace the command wholesale
with fixed exits (`skills/work-on/scripts/output-gates-routing_test.sh:300-313`),
so its text doesn't reach them.

Key assumptions:

- `gh pr view --json commits` gives each commit's `oid`, `messageHeadline`
  and `messageBody`. The repository reads only `oid` and `committedDate` from
  that field today (`skills/execute/scripts/merge-verdict.sh:342`,
  `merge-verdict.sh:386`). If the message fields aren't there, the commit
  check reads `gh api repos/<owner>/<repo>/pulls/<n>/commits` instead, and the
  stub gains that branch.
- A pull request's commits arrive in one `gh pr view` read for the sizes
  work-on opens. If gh caps the list, a closing keyword in a commit past the
  cap goes unread. The body and title checks don't depend on this.
- `directed_transition` and `rewound` events carry `payload.from` and
  `payload.to` the way `transitioned` does. Test fixtures show this
  (`scripts/rule-registry_test.sh:800`, `rule-registry_test.sh:804`,
  `skills/coordinate/scripts/coord-log_test.sh:85`), but no captured engine
  log in the repository confirms it for `directed_transition`. If the fields
  differ, the approved-pass read misses a directed arrival, and the fixtures
  pin that.
- The engine leaves plain `$name` shell variables in a gate command alone, as
  it leaves `$?` (`work-on.md:774`). If it doesn't, the command spells the
  script's path out on each call, as every other gate does.

#### Chosen: A log-only mode in the script, then branch in the command

1. **The command tests `DELIVERY`, then asks the script about the log, then
   branches.** In order, all on one line: an empty `ISSUE_NUMBER` passes, as
   now; `test -x` on the script, or exit 2; if `{{DELIVERY}}` is `partial`,
   the pass is non-closing and the log isn't read, the same inline variable
   test `verification_deferral_recorded` already uses (`work-on.md:2545`);
   otherwise `check-closing-keyword.sh --approved-pass <state log>`, with the
   log path the other log-reading gates pass (`work-on.md:1383`), mapped with
   `case $? in 0) <non-closing> ;; 1) ;; *) exit 2 ;; esac`, the idiom of
   `work-on.md:774` and `work-on.md:2557`. Non-closing runs
   `check-closing-keyword.sh --issue "{{ISSUE_NUMBER}}" --non-closing`, with
   `--repo "{{ISSUE_REPO}}"` added when it isn't empty, written as two `if`
   branches because the variable is substituted text, not a shell variable.
   Closing with `ISSUE_REPO` empty is today's
   `gh pr view --json body --jq .body | grep -qiE "..."`, unchanged; closing
   with `ISSUE_REPO` set is today's `--issue N --repo R` call, unchanged. The
   line keeps double quotes only, so the harness's awk still extracts it, and
   it discards no tool's stderr, so `scripts/check-tool-diagnostic-discards.sh`
   has nothing new to list.

   The inline expression stays, but now it has a price. The script starts on
   every issue-backed run, at least as the log probe, so a missing script
   holds a same-repository closing run at exit 2 where today the grep would
   still decide. jq becomes a prerequisite of that run, though every run
   already needs it at `fix_determination` (`work-on.md:887`) and for the
   decision-reasons slice (`work-on.md:1383`). A log that exists but can't be
   parsed holds a run that has neither source, which Decision 1 accepted. The
   "never started" sentences in the template comment (`work-on.md:2510-2512`),
   the script header (`check-closing-keyword.sh:6-10`) and the test comment
   (`closing-keyword-gate_test.sh:187-189`) are reworded to say that a
   same-repository closing run reads only its body. The assertion at
   `closing-keyword-gate_test.sh:193` doesn't change, because the probe makes
   no `gh` call.
2. **The script takes the log path as the value of `--approved-pass`.** That's
   the script's own `--name value` style
   (`check-closing-keyword.sh:145-154`), and the shape of
   `decision-reasons.sh slice <log>`
   (`skills/work-on/scripts/decision-reasons.sh:42`) and `fix-kind.sh
   --task-log` (`work-on.md:887`), all fed the same path. The
   `SHIRABE_GATE_LOG` environment value isn't used: it switches on the
   rule-findings ladder in scripts that source `scripts/lib/rule-findings.sh`,
   and an environment value can't be seen in the usage tests. The mode exits 0
   when the latest `transitioned` or `directed_transition` arrival into
   `pre_pr_evidence` is a `transitioned` event with `payload.from` equal to
   `deferral_approval`, and no later event of type `transitioned`,
   `directed_transition` or `rewound` has `payload.to` equal to
   `finalization` or `deferral_approval`, "later" meaning later in the file.
   It exits 1 for no approved pass: no file at the path, a file with no
   qualifying arrival, or an empty file. An absent log is a normal answer
   here, unlike for `decision-reasons.sh`, which refuses it. It exits 2 for a
   file that exists but can't be read, a line that isn't JSON, jq missing, or
   a usage error. The parse is strict, like `decision-reasons.sh:61`: one
   `jq -n` over every line, so a single bad line fails the read and nothing
   is half-decided. The header line has no `type`, so the event filter skips
   it rather than demanding it, and header-less fixtures still read. In this
   mode exit 1 isn't a refusal; the command maps it, so it never reaches the
   gate's routes, and the script header says so in its own exit block, as
   `skills/work-on/scripts/check-pr-output.sh:168` does per mode.
3. **Non-closing mode reads the pull request once, as JSON.**
   `gh pr view --json url,title,body,commits` with no `--jq`, parsed locally
   with jq, which the script already needs for the log. One read keeps body,
   title and commits from the same snapshot inside the lookup deadline
   (`check-closing-keyword.sh:71-74`). From each commit it takes `oid`, cut to
   the short SHA the refusal message names, and `messageHeadline` plus
   `messageBody`. A failed read, or output jq can't parse, refuses with exit
   1, like the closing read at `check-closing-keyword.sh:171-172`. Closing
   mode keeps its `--json url,body --jq '.url, .body'` call unchanged, so
   every existing stub branch still serves it. The stub gains one branch for
   the field list `url,title,body,commits`, built with `jq -n` from new
   `PR_TITLE` and `PR_COMMITS` variables (a JSON array of
   `{oid, messageHeadline, messageBody}`) next to `PR_URL` and `PR_BODY`, and
   `run_gate` passes the two through as it passes `PR_URL`.
4. **The usage surface has four valid shapes:** `--issue N --repo R`, as
   today; `--issue N --non-closing`; `--issue N --repo R --non-closing`; and
   `--approved-pass <log>`. `--non-closing` is a bare flag. Each of these
   exits 2, per the header's mapping (`check-closing-keyword.sh:110-111`): no
   arguments; `--issue N` alone, already pinned; `--repo R` without
   `--issue`; `--non-closing` without `--issue`, or followed by a stray value,
   which reads as an unknown argument; `--approved-pass` with no value or an
   empty one; `--approved-pass` together with `--issue`, `--repo` or
   `--non-closing`; an unknown flag; and today's malformed issue and
   repository values.
5. **The tests stay in `closing-keyword-gate_test.sh`.** Every existing case
   stays as written. `run_gate` gains three substitutions in its existing
   style: `{{DELIVERY}}` from `${DELIVERY:-closes}`, and the two template
   variables that make up the log path, from a temporary directory made once
   for the file and a fixed default name. It also fails the case if any `{{`
   is left in the command after substitution; without that check, an
   unsubstituted log path reads as an absent log, and every approved-pass
   case would pass for the wrong reason. Existing cases write no log, so they
   run in closing mode, as today. New cases cover `DELIVERY=partial` in the
   same-repository and cross-repository forms; log fixtures for an approved
   pass, a recount back through `finalization` to `ready_for_pr`, a directed
   arrival from `deferral_approval`, a `rewound` event, an absent log, a
   header-less log and an unparseable log; title and commit refusals and the
   location the message names; a `GH_LOG` check that a same-repository closing
   run with a non-approved log present still makes only the one inline call;
   a `GH_LOG` check that a non-closing run makes one `pr view` with the new
   field list; and the new usage refusals in the loop at
   `closing-keyword-gate_test.sh:548-563`.

This is the only option that keeps all of the earlier decisions' constraints
at once. The inline grep and its single `gh` call stay byte-identical, so the
pin at `closing-keyword-gate_test.sh:193` holds without editing it. The
gate's 0/1/2/3 contract is untouched, because the new mode has its own exits,
which the command maps and never passes through. `--issue N` alone is still a
usage error. Testing `DELIVERY` before the probe means a declared split never
depends on the log at all. Each command piece (an inline variable test,
`case $?` on a script, an `if` over `ISSUE_REPO`) is already used in
`pr_creation`'s own gates. The accepted cost is that the script and jq now
sit in front of every issue-backed run, which every neighbouring gate already
asks for with `test -x ... || exit 2`.

#### Alternatives Considered

- **One script call with a fall-back exit code.** The script reads the log
  and `DELIVERY` itself, and returns a new code, 4, that tells the command to
  run the inline grep. Rejected because it adds a fifth exit to a contract
  the drivers keep at four, and the command still has to branch on it. It
  also turns `--issue N` with no `--repo` into a valid call, which Decision 1
  keeps as a usage error.
- **Move the same-repository closing check into the script.** Drop the inline
  expression and send every run through the script's same-repository branch.
  Rejected because that branch isn't today's behavior: it accepts
  `Fixes acme/app#42` (`check-closing-keyword.sh:201`,
  `check-closing-keyword.sh:238`), refuses an unparseable URL
  (`check-closing-keyword.sh:180-185`), holds on a leading-zero issue number
  (`check-closing-keyword.sh:157-159`), which `ISSUE_NUMBER` doesn't forbid
  (`work-on.md:34-36`), and asks `gh` for `url`, which
  `closing-keyword-gate_test.sh:193` forbids. Keeping today's results would
  mean copying the inline expression into the script as a separate branch.
- **A separate helper script for the log read.** The same branching, with
  the read in its own file. Rejected because Decision 1 puts the read in
  `check-closing-keyword.sh`, and a second file adds a second `test -x` to an
  already long line, another entry in the review-level rules, and a second
  header to keep in step with the template comment, all for a read only this
  gate uses.

### Decision 4: Where the split's reason lives

Decision 1 narrows `finalization` for a declared split to the criteria the
step owns "as its reason states it", and leaves the reason to this decision:
where it's kept, and whether a split may go without one. koto can't relate two variables
(`work-on-open.sh:114-116`), so a rule that a split needs a reason has to live
in the opener, as the hosted-ci deferral's does
(`scripts/lib/verification-deferral.sh:49-59`). #1736's body asks that "a run
can declare that its pull request delivers part of its issue", and a later
comment there adds a pull request with no second step planned, one that "adds
diagnostics for an intermittent test failure, so the next failure shows which
branch fired, while the root cause stays open on its issue".

Key assumptions:

- One line is enough for a run to tell which criteria are this pull
  request's. If it isn't, the criteria it can't place still go through
  `deferral_approval`.

#### Chosen: A mandatory `DELIVERY_REASON`, set by `--delivery-reason=<why>`

A non-rebindable `DELIVERY_REASON`, with `VERIFICATION_DEFERRAL_REASON`'s
pattern and character rules, says what this pull request delivers and what
stays open on the issue. `work-on-open.sh` maps `--delivery-reason=<why>` to
it and refuses `--delivery=partial` without a non-empty one (`error=usage`,
exit 64). Saying what stays open, rather than naming a later step, covers the
diagnostics case too. Finalization's narrowed bar gets a written scope, fixed
before any work.

#### Alternatives Considered

- **No reason.** Rejected because Decision 1's narrowed bar then has nothing
  to point at. Either every later-step criterion goes through
  `deferral_approval`, the cost Decision 1 rejected the run-time gate for, or
  the run reads its own scope from the issue.
- **An optional reason.** Rejected because it makes two kinds of split with
  different finalization bars.
- **The reason in `DELIVERY`'s value** (`partial:<text>`). Rejected because
  Decision 1 fixes the values to `closes` and `partial`, and the gate's test
  would become a pattern match.
- **The reason in a context key at init.** Rejected because the run can
  overwrite context keys, the argument Decision 1 makes against a `delivery`
  key, and the variable is already recorded at init.

### Decision 5: How a reason passes through /coordinate

Decision 1 has /coordinate start a split through the work-on row of
`skills/coordinate/references/entry-points.tsv:67`, and Decision 4 makes the
reason mandatory, so the row needs `--delivery-reason=*` as well.
`dc_flag_allowed` refuses any flag holding whitespace
(`skills/coordinate/scripts/dispatch-common.sh:521`), and /coordinate stores
a run's flags joined with spaces and splits them back on spaces
(`dispatch-common.sh:386-391`). A reason written as a sentence can't pass.

Key assumptions:

- A one-token reason in koto's allowlist, such as
  `step-1-of-2:validator-side`, says enough for finalization. If it doesn't,
  the criteria it can't place go through `deferral_approval`.

#### Chosen: The row admits `--delivery-reason=*`, and a reason sent that way is one token

The work-on row gains `--delivery-reason=*` next to `--delivery=partial`. A
reason sent through /coordinate holds no whitespace and uses koto's
`. _ / : @ + -` to join its words. A typed invocation keeps a full sentence.
Nothing in /coordinate's rendering changes.

#### Alternatives Considered

- **Quote whitespace in flag values**, as `dc_invocation` already quotes the
  positional (`dispatch-common.sh:396`). Rejected because it changes the
  rendering and the stored flag list for every skill's entry point, for one
  flag.
- **No reason for a split started through /coordinate.** Rejected because it
  gives one declaration two rules, and the waived case loses Decision 4's
  scope record.
- **/coordinate doesn't start splits.** Rejected because /coordinate passes a
  work-on run only the flags the work-on row admits. With no entry for the
  split, a run it dispatches can't declare one, so it ends at `done_blocked` at the
  gate, which is the failure #1736 reports.

### Decision 6: A split declared without a reason

A hand `koto init --var` is a documented way to set a variable
(`work-on.md:186-188`), and it bypasses the opener's refusal. The hosted-ci
deferral has a template backstop for its missing reason, an edge to
`done_blocked` (`work-on.md:1954-1963`), because there a missing reason means
verification is skipped with nothing said.

Key assumptions:

- Few runs are opened by hand with `DELIVERY=partial` and no reason. If many
  are, a template backstop can be added without touching the gate.

#### Chosen: The finalization directive falls back to every criterion

With `DELIVERY=partial` and an empty `DELIVERY_REASON`, the `finalization`
directive's "every acceptance criterion" means every criterion, as today.
The gate still runs non-closing mode, per Decision 3, so the only effect left
is the body rule, and misusing it leaves an issue open. No template edge is
added.

#### Alternatives Considered

- **A `done_blocked` backstop like `verification_deferred`'s.** Rejected
  because nothing is skipped under the fallback, and a new edge changes the
  routing suites for a path only a hand init reaches.
- **The gate counts `partial` only with a reason.** Rejected because it
  rewrites Decision 3's mode test, and an honest `Part of #N` body would then
  end at `done_blocked` under a message that doesn't name the cause.

### Decision 7: Whether the body repeats the reason

The hosted-ci deferral's `verification_deferral_recorded` gate holds
`pr_creation` until the body carries `Reason: <reason>` verbatim
(`work-on.md:2530-2545`), and the reason is copied into context
(`work-on.md:1957`). Decision 1 leaves to this decision whether the body
repeats the split's reason.

Key assumptions:

- A run writes the Part 2 prose the `pr_creation` directive asks for. If it
  doesn't, the body still says the issue stays open, since Decision 2
  requires the reference.

#### Chosen: No gate and no context copy; Part 2 states the split in plain words

Only the `finalization` and `pr_creation` directives read
`{{DELIVERY_REASON}}`. The `pr_creation` directive asks Part 2 to say what
the pull request delivers and what stays open on the issue. That's the same
kind of directive-only ask `phase-6-pr.md:109-111` makes for a deferral.

#### Alternatives Considered

- **A verbatim gate like `verification_deferral_recorded`.** Rejected because
  it adds a gate condition to all four `ci_monitor` edges
  (`work-on.md:2601-2640`) and a script mode. The reason is also limited to
  koto's allowlist, with no commas or apostrophes and sometimes one token
  (Decision 5), which reads badly as required body text.
- **A context copy of the reason.** Rejected because no reader needs it, and
  the variable is already in `workflow_initialized`.

### Decision 8: Which word the directives prescribe

Decision 2 accepts `Ref`, `Refs` and `Part of`. Decision 1 fixes `Part of #N`
for an approved deferral, and Decision 2's refusal message gives `Part of #N`
as the line to add in either mode. Nothing fixes what the `pr_creation`
directive and `phase-6-pr.md` tell a declared split to write. #1735 wrote
`Refs #1646`, #1736's body asks the gate to accept "`Refs #N` or
`Part of #N`", and the design skill prescribes `Ref #<N>`
(`skills/design/references/phases/phase-6-final-review.md:296`).

Key assumptions:

- A run writes what its directive prescribes. If it writes `Refs` anyway, the
  gate passes it.

#### Chosen: `Part of #N` in both modes

The `pr_creation` directive and `phase-6-pr.md` prescribe `Part of #N`, or
`Part of <ISSUE_REPO>#N`, for both a split and a deferral, and name `Ref` and
`Refs` as also accepted. The directive, the docs and the refusal message give
the same line.

#### Alternatives Considered

- **`Refs #N` for a split, `Part of #N` for a deferral.** Rejected because two
  prescriptions have to be kept in step, and the refusal message, which can't
  tell the modes apart (Decision 12), would suggest a different line from the
  directive.
- **`Ref #N`, as the design skill writes.** Rejected because that use is a
  design pull request pointing at its source issue, not a step of an
  implementation, and the repository's history uses `Ref` least of the three.

### Decision 9: Which runs may declare a split

Free-form runs and `multi-pr` plans are out of scope. A free-form run passes
the gate on its empty `ISSUE_NUMBER`, but the `finalization` directive's
narrowing would still apply to it. A `multi-pr` PLAN run opens each issue's
run through `work-on-open.sh` with the PLAN path among its tokens
(`work-on-open.sh:48-50`), so one flag would cover every issue. The opener
already tells both apart: the entry mode from the `ISSUE_NUMBER` var
(`work-on-open.sh:362-365`) and the PLAN-path check it runs for `--koto-leg`
(`work-on-open.sh:288-314`).

Key assumptions:

- No free-form or PLAN run needs a split. If one does, the refusal is one
  check to remove.

#### Chosen: The opener refuses `--delivery=partial` on both

`work-on-open.sh` refuses `--delivery=partial` on a free-form run and with a
PLAN path among the tokens (`error=usage`, exit 64), reusing the detection it
already has.

#### Alternatives Considered

- **Accept and ignore.** Rejected because the gate ignores it but the
  `finalization` directive doesn't, so a free-form run could narrow its bar for
  nothing, and a PLAN run would declare every issue partial.
- **Refuse free-form runs only.** Rejected because a `multi-pr` PLAN run would
  still take a flag that applies to each of its issues.

### Decision 10: How a non-closing refusal reports

Today's script stops at its first refusal
(`check-closing-keyword.sh:244-250`). Decision 2 names each location holding a
closing form, but doesn't say whether a missing reference is reported beside
them. A refusal is terminal, and the person who finishes the run reads the
script's stderr once.

Key assumptions:

- Collecting every finding costs nothing that matters: the pull request read
  is one call, and the local checks are greps over it.

#### Chosen: Every local finding at once, before any lookup

The script collects every closing form with its source, and a missing
reference, reports them all, and exits 1 without looking anything up. The
lookups run only when the local checks found nothing, as today's script gives
its answer before any lookup when the reference is missing
(`check-closing-keyword.sh:247-250`).

#### Alternatives Considered

- **Stop at the first finding.** Rejected because a pull request with
  `Fixes #N` in a commit and no reference in the body would take two failed
  runs, or two passes by hand, to show both problems.

### Decision 11: Old-name lookups across the body, title and commits

Decision 1 refuses old-name forms and reads the title and commit messages, so
names found there are looked up too, and the lookups now also run on a
same-repository run. The script looks up at most `MAX_LOOKUPS` (5)
repositories, within `LOOKUP_SECS` (20) of its start, inside koto's 30-second
gate default (`check-closing-keyword.sh:71-76`).

Key assumptions:

- A pull request work-on opens rarely names more than five other repositories
  across its body, title and commits. One that does is refused, as a body over
  the cap is today.

#### Chosen: One pool of names, one cap, one deadline

The names from every source are pooled and deduplicated, and the one
`MAX_LOOKUPS` cap and the one `LOOKUP_SECS` deadline cover them all.

#### Alternatives Considered

- **A cap per source.** Rejected because the calls grow with the commit count
  and can't fit in 20 seconds.
- **Lookups for the body only.** Rejected because an old-name closer in a
  commit message, which Decision 1 reads, would pass.

### Decision 12: What the refusal message says about why

Decision 2 has the message say that the run doesn't close its issue and why.
Decision 3 makes `--non-closing` a bare flag, called the same way for both
sources, so the script isn't told which one applies.

Key assumptions:

- A reader can tell which source applied from the run: a split shows
  `--delivery=partial` in its invocation, and a deferral its recorded
  approval.

#### Chosen: One sentence naming both causes

The message says the run declared a partial delivery or came from an approved
deferral. The `done_blocked` failure reason, fixed template text, already
names both, so the two read alike.

#### Alternatives Considered

- **The script reads the log again to say which.** Rejected because it's a
  second log read on every non-closing run, and the script still can't see
  `DELIVERY` unless it's passed in.
- **A valued flag, `--non-closing=split|deferral`.** Rejected because it adds
  two usage shapes and a second set of gate and usage tests, while the
  command already knows the source from the invocation and the reader can
  see it in the run, so the message gains little.

### Decision 13: How the implementation lands

Each phase of the Implementation Approach is one commit, but nothing yet says
how many pull requests carry them. shirabe's CLAUDE.md declares
`## PR Grouping Policy: coarsest-legal`, one pull request per repository by
default. An implementation pull request that delivers only part of #1736
would reference it without closing it, which the gate as it stands refuses.

Key assumptions:

- The five commits are small enough to review as one pull request.

#### Chosen: One pull request, five commits, script first

The commits land in the Implementation Approach's order: script modes, the
init declaration, the gate, the text, the /coordinate row. Nothing calls the
new modes until the gate commit.

#### Alternatives Considered

- **Several pull requests.** Rejected because each early one would reference
  #1736 without closing it and end at `done_blocked`, or write `Fixes #1736`
  before the work is done, and the repository's grouping policy asks for one.
- **The gate first.** Rejected because every commit before the script lands
  would fail the suite that extracts the gate command: the new command calls
  `--approved-pass`, which today's script refuses as a usage error, so every
  closing-mode case in `closing-keyword-gate_test.sh` exits 2. Script first
  keeps each commit green.

### Decision 14: Where the reason's character check lives

The hosted-ci reason's allowlist check is `vd_reason_chars_refusal`
(`scripts/lib/verification-deferral.sh:33-47`). The lib's own comment
(`verification-deferral.sh:35-40`) says the allowlist agreement case in
`work-on-open_test.sh` reads the class from that file's one such line, and
that a second such line breaks the case. `execute-open.sh` sources the same
lib.

Key assumptions:

- `execute-open.sh` refusing a malformed `--delivery-reason` is harmless,
  since /execute never maps the flag.

#### Chosen: Extend `vd_reason_chars_refusal`

The existing function also reads `--delivery-reason=` values, and the
allowlist stays in its one line.

#### Alternatives Considered

- **A copy of the check in `work-on-open.sh`.** Rejected because the
  agreement case doesn't read a second class line, so it can drift from
  koto's allowlist unnoticed.
- **A new lib for the delivery flags.** Rejected for the same drift, and a
  third sourced file for a two-flag mapping.

## Decision Outcome

A run holds a non-closing delivery in exactly two ways, and neither comes
from anything the run submits to koto. The invocation declares a planned split with
`--delivery=partial` and a stated reason, `--delivery-reason=<why>`, which
`work-on-open.sh` maps to new `DELIVERY` and `DELIVERY_REASON` variables
fixed at init. Or the run reaches `pre_pr_evidence`
through the engine's approved transition out of `deferral_approval`, with no
later return to `finalization` or `deferral_approval` in its state log.
Declaring a split doesn't loosen `finalization`: `ready_for_pr` still means
every criterion the declared step owns is met, and any criterion the run
can't meet still goes to a person.

At `pr_creation` the `closing_keyword` command picks its mode in a fixed
order. An empty `ISSUE_NUMBER` passes, as today. `DELIVERY=partial` goes
straight to non-closing mode without reading the log. Otherwise the command
asks `check-closing-keyword.sh --approved-pass <state log>` and maps its exit:
0 means non-closing, 1 means closing, and anything else holds the state at
exit 2. Closing mode is today's gate unchanged, the inline grep for a
same-repository issue and `--issue N --repo R` for an issue elsewhere, so a
run with neither source sees no difference beyond the script and jq now being
required.

Non-closing mode runs `check-closing-keyword.sh --issue N --non-closing`, with
`--repo` for an issue elsewhere. It reads the pull request's URL, title, body
and commits in one `gh pr view` call. It refuses every form it already knows
to close issue N, wherever it stands, and names the location. It requires the
body to carry `Ref`, `Refs` or `Part of` followed by the issue in the form
closing mode would accept with the word swapped: bare or qualified for the
same repository, qualified or linked for an issue elsewhere. Closing keywords
for other issues pass as they do today. An approved deferral's body writes
`Part of #N`, so its issue stays open with the deferred criterion on it.

The gate's exit codes 0, 1, 2 and 3 and their routes don't change, and the
probe's own exits never leave the command. The template decides the mode from
what it may read, the script holds both the log read and the body rule, and
the tests stay in `closing-keyword-gate_test.sh`. The `pr_creation` and
`finalization` directives, the `done_blocked` failure reason,
`phase-6-pr.md`, `finishing-obligations.md` and the SKILL.md passages on the
closing obligation change to describe both modes.

## Solution Architecture

### Overview

The design adds no state and no edge to the work-on template. It changes what
one gate, `closing_keyword` at `pr_creation`, asks of the pull request, and it
adds one way to start a run. Two facts can put the gate into non-closing mode,
and neither comes from anything the run submits to koto: the `DELIVERY`
variable, fixed at init
from the invocation, and the engine's `transitioned` event from
`deferral_approval` into `pre_pr_evidence`, read back from the run's state
log. The gate command picks the mode from those two. `check-closing-keyword.sh`
does the log read and judges the non-closing body. A run with neither fact
runs today's checks, unchanged.

In non-closing mode the script reads the pull request once. It refuses any
form it knows to close the issue, in the body, the title or a commit message,
and it requires the body to carry `Ref`, `Refs` or `Part of` followed by the
issue in the run's form. A planned split is declared as
`--delivery=partial --delivery-reason=<why>`, where the reason says what this
pull request delivers and what stays open on the issue. `work-on-open.sh` maps
the two tokens to `DELIVERY` and `DELIVERY_REASON`. An approved deferral needs
no declaration, since the run's state log already holds the transition.

The template, `skills/work-on/koto-templates/work-on.md`, declares `DELIVERY`
and `DELIVERY_REASON` next to `VERIFICATION` and
`VERIFICATION_DEFERRAL_REASON`. Its `closing_keyword` command gains the
`DELIVERY` test, the log probe and the non-closing branch, and the comment above
it stops claiming that a same-repository run never starts the script. The
failure reason on the gate's exit-1 edge to `done_blocked`, the
`finalization`, `deferral_approval` and `pr_creation` directives, and the
`deferral_detail` description are reworded to cover both modes.

`check-closing-keyword.sh` gains two modes. `--non-closing` brings a list of
reference words and the three pass shapes built on it, and it's the one case
where `--repo` may be left off. `--approved-pass <log>` answers whether this
pass came out of an approved deferral. The script's header, usage line and
"Needs" line (`check-closing-keyword.sh:116`, which gains jq) are rewritten.
`work-on-open.sh` maps `--delivery` and `--delivery-reason` and refuses a
declared split that has no reason. The work-on row of
`skills/coordinate/references/entry-points.tsv` admits both flags, so
/coordinate can start a split run.

The text that describes the gate moves with it: `phase-6-pr.md:48-52` and
`phase-6-pr.md:109-111`, `skills/work-on/references/finishing-obligations.md:18`,
and the SKILL.md passages on the argument hint, initialization, the closing
obligation, no silent deferral and the script list. They name the three
words, the forms each kind of run accepts, and that the reference goes in
Part 2. `closing-keyword-gate_test.sh` keeps every existing case and gains the
new ones. Among them, `GH-N` and the issue URL are refused in a
same-repository non-closing body. Closing mode doesn't accept either as
closing the issue there, and non-closing mode refuses both as closing it,
since GitHub closed the issue on each (#1044). That reversal is pinned on
purpose.

### Components

- **Template variables** (`work-on.md`, after `VERIFICATION_DEFERRAL_REASON`
  at `work-on.md:194-209`).
  - `DELIVERY`: `values: [closes, partial]`, `default: closes`, no `rebind`.
    The `closing_keyword` command reads it, and so do the `finalization` and
    `pr_creation` directives, by substitution.
  - `DELIVERY_REASON`: one line saying what this pull request delivers and
    what stays open on the issue. Same `pattern: ^([a-zA-Z0-9].*)?$` and
    character rules as `VERIFICATION_DEFERRAL_REASON`, no `rebind`. Only the
    `finalization` and `pr_creation` directives read it, by substitution, and
    it's ignored when `DELIVERY` is `closes`. No gate reads it, and no context
    key copies it.
- **The `closing_keyword` gate** (`work-on.md:2513-2515`). Still one
  single-quoted line holding only double quotes. It picks the mode and runs
  either today's check or the script's non-closing mode. Its exits keep their
  routes: 0 to `ci_monitor` (with the other four gates), 1 to `done_blocked`,
  2 and 3 hold (`work-on.md:2600-2649`).
- **`skills/work-on/scripts/check-closing-keyword.sh`**, in three modes:
  - closing, `--issue N --repo R`: unchanged;
  - non-closing, `--issue N --non-closing [--repo R]`: the refusal side and
    the reference requirement, over one `gh pr view` read;
  - log probe, `--approved-pass <log>`: reads the state log and makes no `gh`
    call.
- **`skills/work-on/scripts/work-on-open.sh`**. A `bound()` line for each new
  flag next to the `--verification` pair (`work-on-open.sh:355-356`), and three
  refusals of its own, each `error=usage`, exit 64, before any koto call:
  `--delivery=partial` with no non-empty `--delivery-reason`; a reason with a
  character outside koto's allowlist; and `--delivery=partial` on a run that
  isn't a single issue-backed run (no `ISSUE_NUMBER` var, or a PLAN path among the
  tokens). The character check is the one in
  `scripts/lib/verification-deferral.sh:33-47`, extended to read
  `--delivery-reason=` values too, because the allowlist agreement case in
  `work-on-open_test.sh` reads the class from that file's one
  `select(test(...))` line, and a second copy would break it.
- **`skills/work-on/scripts/fix-round.sh`**: no change. It copies every init
  variable except `REVIEW_LEVEL`, `UNIT_KIND` and `PLUGIN_ROOT` into the round
  (`fix-round.sh:136-143`), so a round keeps `DELIVERY` and `DELIVERY_REASON`.
- **`skills/coordinate/references/entry-points.tsv:67`**. The work-on row's
  flag list gains the exact `--delivery=partial` and `--delivery-reason=*`.
  `dc_flag_allowed` refuses any flag holding whitespace
  (`skills/coordinate/scripts/dispatch-common.sh:521`), so a reason sent
  through /coordinate is written as one token, for example
  `--delivery-reason=step-1-of-2:validator-side`.
- **Text**: the `finalization`, `deferral_approval` and `pr_creation`
  directives (`work-on.md:3901`, `work-on.md:3990`, `work-on.md:4090`), the
  `deferral_detail` description (`work-on.md:2204-2209`), the failure reason
  at `work-on.md:2649`, `phase-6-pr.md`, `finishing-obligations.md:18`, and
  `skills/work-on/SKILL.md` (the argument hint at `SKILL.md:15`, the
  initialization passage, the closing obligation, **Finalization and No Silent
  Deferral**, and the script list entry for `check-closing-keyword.sh`).
- **Tests**: `closing-keyword-gate_test.sh` for the gate and all three script
  modes; `work-on-open_test.sh` and `verification-deferral_test.sh` for the
  tokens and refusals; `dispatch-common_test.sh` for the entry-point row;
  `fix-round_test.sh` for the carried variables; and work-on's eval scenarios
  in `skills/work-on/evals/evals.json`.

Nothing else changes. `execute-open.sh` doesn't map `--delivery`, since
`/execute`'s runs are out of scope. The routing suites replace the gate
command with fixed exits (`output-gates-routing_test.sh:300-313`), so they
don't see it. The completion cascade and /coordinate's pick rule read
GitHub's issue state and pull requests as they do today.

### Key Interfaces

**Invocation.** `--delivery=partial --delivery-reason=<why>`, kept in the
tokens file like `--verification` and its reason, never passed as `--var`.
koto refuses a `DELIVERY` outside its two values, or a reason outside its
pattern, as `invalid_var`. `--delivery=closes` is accepted and changes
nothing. `--delivery-reason` given alone, or with `--delivery=closes`, is
accepted and ignored, but its characters are still checked the same way
`--verification-reason`'s are.

**Script modes and exits.**

| Call | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| `--issue N --repo R` | closes R#N | doesn't close it, closes the wrong issue, or can't read the pull request | usage | a lookup failed or ran out of time |
| `--issue N --non-closing [--repo R]` | refers to N without closing it | closes N somewhere, has no reference in the body, or can't read the pull request | usage | a lookup failed or ran out of time |
| `--approved-pass <log>` | this pass came out of an approved deferral | it didn't, or there's no log | unreadable log, a line that isn't JSON, no jq, usage | not used |

Exit 1 from `--approved-pass` isn't a refusal. The command maps it, and it
never reaches the gate's routes. The usage refusals are those of Decision 3,
item 4.

**Gate command**, laid out for reading. In the template it's one line, and
`<script>` stands for
`"{{PLUGIN_ROOT}}/skills/work-on/scripts/check-closing-keyword.sh"`, spelled
out at each call:

```sh
test -z "{{ISSUE_NUMBER}}" || {
  test -x <script> || exit 2
  if test "{{DELIVERY}}" = partial; then m=open
  else
    <script> --approved-pass "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"
    case $? in 0) m=open ;; 1) m=close ;; *) exit 2 ;; esac
  fi
  if test "$m" = open; then
    if test -z "{{ISSUE_REPO}}"; then <script> --issue "{{ISSUE_NUMBER}}" --non-closing
    else <script> --issue "{{ISSUE_NUMBER}}" --repo "{{ISSUE_REPO}}" --non-closing; fi
  elif test -z "{{ISSUE_REPO}}"; then
    gh pr view --json body --jq .body | grep -qiE "<today's expression>"
  else
    <script> --issue "{{ISSUE_NUMBER}}" --repo "{{ISSUE_REPO}}"
  fi
}
```

The last branch and the inline grep are byte-for-byte today's.

**Approved-pass rule.** The script parses every line of the log with one
`jq -n` over `inputs`, so a single bad line exits 2. Lines with no `type`,
the header among them, are skipped. Then:

1. Take the last event of type `transitioned` or `directed_transition` whose
   `payload.to` is `pre_pr_evidence`. None means exit 1.
2. It has to be a `transitioned` event with `payload.from` equal to
   `deferral_approval`. Otherwise exit 1.
3. No later event of type `transitioned`, `directed_transition` or `rewound`
   may have `payload.to` equal to `finalization` or `deferral_approval`.
   Otherwise exit 1.
4. Exit 0.

A missing file at the path exits 1. "Later" means later in the file.

**Non-closing read.** One `gh pr view --json url,title,body,commits`, with no
`--jq`, parsed with jq. Each commit's text is its `messageHeadline` and
`messageBody`, and the refusal message names it by the first seven characters
of its `oid`. A failed read, or output jq can't parse, exits 1.

**Non-closing refusals.** Every source (the body, the title, each commit's
message) is read with its lines joined, like today's refusal side
(`check-closing-keyword.sh:225-234`), with the wider separator and no
word-start anchor:

- same-repository run (`ISSUE_REPO` empty, or naming the pull request's own
  repository in any case): every form `OWN` and `OWN_LINK` match today
  (`check-closing-keyword.sh:216-220`): a bare `#N`, `GH-N`, `<PR repo>#N`,
  the issue URL, and the markdown link to it;
- cross-repository run: those same forms, which close this repository's
  issue N as they do in closing mode, plus `<ISSUE_REPO>#N` and the link
  closing mode accepts for it;
- both: a closing reference under another `owner/name` that resolves to the
  issue's repository. The names come from every source together, each
  spelling once, under the one `MAX_LOOKUPS` cap and the one
  `LOOKUP_SECS` deadline. A failed lookup exits 3 and holds, as today.

The local checks run first. The script collects every finding (each closing
form with its source, and a missing reference) and reports them all before
it exits 1, without any lookup. Lookups run only when the local checks
found nothing.

**Non-closing reference.** In the body only, a line at a time,
case-insensitive. `REF` is `(ref|refs|part[[:space:]]+of)`, anchored at a
word start, and the separator is closing mode's `:?[[:space:]]+`:

| Run | Accepted |
|-----|----------|
| same repository | `<REF> #N`, `<REF> <PR repo>#N` |
| another repository | `<REF> <ISSUE_REPO>#N`, `<REF> [<ISSUE_REPO>#N](https://<host>/<ISSUE_REPO>/issues/N)` |

`#N` must not run into more digits. Anything may follow on the line.

**Refusal message.** For each closing form: the matched text, its source
(`body`, `title` or `commit <short SHA>`), and the line to write instead.
Then one sentence saying the run doesn't close its issue because it declared
a partial delivery or came from an approved deferral. `--non-closing` is a
bare flag, so the script isn't told which, and the sentence names both. For
a missing reference: the exact line to add, `Part of #N` or
`Part of <ISSUE_REPO>#N`. The `done_blocked` failure reason is fixed text, so
it names both modes and points the reader at the gate's message.

**Directives.**

- `finalization`, the `ready_for_pr` sentence: with `DELIVERY` `partial` and
  a reason, "every acceptance criterion" means every criterion the step in
  `{{DELIVERY_REASON}}` owns. The directive quotes the reason as the
  invoker's stated scope, not as an instruction. With an empty reason it
  means every criterion, as today.
- `pr_creation`: names the run's delivery (`{{DELIVERY}}`) and says when the
  body closes the issue (`Fixes`) and when it writes `Part of #N` (or
  `Part of <ISSUE_REPO>#N`): a declared split, or a pass that came straight
  from an approved deferral. It names `Ref` and `Refs` as the other accepted
  words, and says Part 2 states what the pull request delivers and what stays
  open, from `{{DELIVERY_REASON}}` for a split or the deferred criterion for
  a deferral.
- `deferral_approval`: on approval, the pull request references the issue
  with `Part of #N` and leaves it open with the criterion on it.

### Data Flow

```
invocation: /work-on #N --delivery=partial --delivery-reason=<why>
      |
      v
work-on-open.sh -- refuses: no reason, bad characters, not one issue-backed run
      |
      v
koto init: workflow_initialized { DELIVERY, DELIVERY_REASON, ... }
      |
      v
... -> finalization --ready_for_pr--------> pre_pr_evidence -> pr_precheck -> ... -> pr_creation
           |                          ^
           +--deferral_requested--> deferral_approval
                                      | approved (engine `transitioned`)

pr_creation, closing_keyword:
  ISSUE_NUMBER empty ............................ pass (0)
  DELIVERY=partial .............................. non-closing
  else --approved-pass <log>:  0 non-closing | 1 closing | other: exit 2 (hold)
  closing ....................................... today's check
  non-closing ................................... --issue N --non-closing [--repo R]
  gate exit: 0 -> ci_monitor | 1 -> done_blocked | 2, 3 -> hold
```

A declared split carries `DELIVERY` and `DELIVERY_REASON` in its
`workflow_initialized` event from the first tick. `finalization` holds it to
the criteria its reason names. Any of those it can't meet still goes to
`deferral_requested` and a person. At `pr_creation` the gate sees
`DELIVERY=partial` and goes straight to non-closing mode without reading the
log.

An approved deferral leaves the records it leaves today: the decision from
`koto decisions record`, and the engine's `transitioned` event from
`deferral_approval` to `pre_pr_evidence`. At `pr_creation` the gate probes the
log, finds that event as the latest arrival into `pre_pr_evidence` with no
return to `finalization` or `deferral_approval` after it, and runs
non-closing mode. If `pr_precheck`'s recount sends the run back to
`finalization` and it then submits `ready_for_pr`, the latest arrival comes
from `finalization`, and the next `pr_creation` is in closing mode. A
`koto rewind` from `done_blocked` back to `pr_creation` writes a `rewound`
event into `pr_creation`, which neither counts as an arrival nor as a return,
so the mode doesn't change. A fix round has its own log with no approval in
it. It keeps the split's variables through `fix-round.sh`, but a deferral
has to be approved again in the round.

The design writes no new context key and no new state. The only workflow
state it adds is the two variables in `workflow_initialized`.

## Implementation Approach

The five phases are one commit each, in one pull request. The first two add
code that nothing calls yet, so every run behaves as it does today until
Phase 3 switches the gate. Phase 4 has to land with Phase 3, since the
directives and docs describe what the gate asks for. Splitting the phases
across pull requests would make each early one a partial delivery of #1736,
which the gate it's changing still refuses.

### Phase 1: The script's two new modes

`--approved-pass` and `--non-closing` go into `check-closing-keyword.sh`
first. The template doesn't call either yet, so nothing a run does changes,
and the modes can be tested by calling the script directly.

Deliverables:
- `skills/work-on/scripts/check-closing-keyword.sh`: argument parsing for the
  four valid shapes and the new usage refusals; the `--approved-pass` log
  read; the `--non-closing` read of `url,title,body,commits`, its refusal
  side over the body, the title and each commit, the reference requirement
  in the body, the collected findings and the old-name lookups over every
  source, with names from the title and commits cut out by `NAME_RE`, `.` and
  `..` dropped and each name matched as a fixed string, as the body's are
  today; refusals that quote only the matched phrase and the commit's short
  SHA; the header's mode descriptions, exit block per mode, usage line and
  "Needs" line.
- `skills/work-on/scripts/closing-keyword-gate_test.sh`: the `gh` stub's new
  branch, and direct calls to the script for the log fixtures, the title and
  commit refusals and the usage refusals listed in Decision 3, item 5.

### Phase 2: Declaring a split at init

The two variables and the tokens that set them. No gate reads `DELIVERY`
yet, so a run started with `--delivery=partial` behaves as any other until
Phase 3.

Deliverables:
- `skills/work-on/koto-templates/work-on.md`: `DELIVERY` and
  `DELIVERY_REASON` in the `variables` block, with descriptions in the style of
  `VERIFICATION` and its reason.
- `skills/work-on/scripts/work-on-open.sh`: the two `bound()` lines, the
  missing-reason refusal, the refusal of `--delivery=partial` on a free-form
  run or with a PLAN path, and the header's mapping section.
- `scripts/lib/verification-deferral.sh`: the character check also reads
  `--delivery-reason=` values, keeping the allowlist in its one line.
- `skills/work-on/scripts/work-on-open_test.sh` and
  `skills/work-on/scripts/verification-deferral_test.sh`: the mapping, each
  refusal, and the allowlist agreement case still finding one line; a
  `--delivery-reason` given alone or with `--delivery=closes` is accepted and
  ignored, and its characters are still checked.
- `skills/work-on/scripts/fix-round_test.sh`: a case that a round's init
  carries `DELIVERY` and `DELIVERY_REASON`.

### Phase 3: The gate switches modes

The `closing_keyword` command becomes the mode-picking line. This needs the
script modes from Phase 1 and the variable from Phase 2.

Deliverables:
- `skills/work-on/koto-templates/work-on.md`: the new `closing_keyword`
  command at `work-on.md:2515`, and the gate comment at `work-on.md:2493-2512`
  rewritten for both modes.
- `skills/work-on/scripts/closing-keyword-gate_test.sh`: the `run_gate`
  changes, and cases run through the gate command for `DELIVERY=partial`, an
  approved-pass log and the two `GH_LOG` checks listed in Decision 3, item 5;
  the comment at `closing-keyword-gate_test.sh:187-189` reworded.

### Phase 4: Directives and documentation

Every passage that tells a run what the gate wants, rewritten for both modes.

Deliverables:
- `skills/work-on/koto-templates/work-on.md`: the `finalization`,
  `deferral_approval` and `pr_creation` directives, the `deferral_detail`
  description and the failure reason at `work-on.md:2649`.
- `skills/work-on/references/phases/phase-6-pr.md`: lines 48-52 as the
  closing case plus the non-closing case, and lines 109-111 saying the
  undone criterion stays open on the issue and the body writes `Part of #N`.
- `skills/work-on/references/finishing-obligations.md`: the `closing_keyword`
  row at line 18.
- `skills/work-on/SKILL.md`: the argument hint, the initialization passage on
  the new tokens, the closing obligation, **Finalization and No Silent
  Deferral**, and the script list entry.
- `skills/work-on/evals/evals.json`: a scenario for a declared split and one
  for an approved deferral, each ending with a `Part of #N` body and the run
  at `ci_monitor`.

### Phase 5: The /coordinate entry point

The work-on row admits the new flags, so /coordinate can start a split run.
It depends only on Phase 2, but it ships in the same pull request, so a
`--delivery=partial` sent through /coordinate never reaches a work-on that
doesn't know it.

Deliverables:
- `skills/coordinate/references/entry-points.tsv`: `--delivery=partial` and
  `--delivery-reason=*` on the work-on row at line 67.
- `skills/coordinate/scripts/dispatch-common_test.sh`: the two flags are
  allowed on work-on, and a reason holding whitespace is refused.

## Security Considerations

The change lets a run open a pull request that references its issue without
closing it. It downloads and runs nothing new, adds no dependency, and asks
for nothing a run doesn't already have: `gh` with the token that reads the
pull request, `jq`, which every run already needs at `fix_determination`,
and a read of the run's own state log, as `probe.sh`, `fix-kind.sh` and
`decision-reasons.sh` already do. Its exposure is in three places: what can
switch the gate to non-closing mode, the pull request text that mode now
reads, and the reason a declared split carries.

### What can switch the gate to non-closing mode

Two facts, and neither comes from anything the run submits to koto.
`DELIVERY` is fixed at init from
the invocation, takes only `closes` or `partial`, and isn't rebindable. The
approved deferral is the engine's own `transitioned` event out of
`deferral_approval`, read from the state log under the approved-pass rule in
Key Interfaces. Evidence, context writes and recorded decisions can't produce
that event. A directed arrival never counts, a later arrival into
`finalization` or `deferral_approval` cancels an earlier approval, and a
`rewound` event into `pr_creation` doesn't change the mode, so a recount or a
`koto rewind` from `done_blocked` can't keep a stale approval alive. A missing
log means closing mode, and a log with a line jq can't parse holds the state
at exit 2. Hand edits to the state log are outside the threat model, as they
are for every gate that reads it (Decision 1).

That doesn't make the log unforgeable. The run has shell access, so it could
append a line to its own state log. Safety here rests on the direction of
failure, not on the log: a forged approval can only leave an issue open,
never close one.

The gate command's new substitutions aren't run-controlled either.
`{{DELIVERY}}` has two values, and `{{SESSION_DIR}}` and `{{SESSION_NAME}}`
already appear, double-quoted, in other gates' commands, such as
`red_recorded`'s. `{{ISSUE_NUMBER}}` and `{{ISSUE_REPO}}` are substituted as
they are today. The template holds `ISSUE_REPO` to an `owner/repo` pattern,
and the script checks the issue number and the repository again before
either reaches an expression (`check-closing-keyword.sh:157-164`). The mode
is kept in a shell variable inside the command, not read back from the run.

### Direction of failure

When the gate runs, non-closing mode can only leave an issue open. The
closing branch is today's
check, byte for byte, and non-closing mode refuses every form the script
knows to close issue N. A misdeclared split, or a hand
`koto init --var DELIVERY=partial` with no reason (Decision 6), costs a person
one manual close. It doesn't make the failure the gate exists to stop, an
issue closed with work missing, any easier.

What a declared split does loosen is `finalization`'s bar. With a reason,
"every acceptance criterion" means every criterion the step in
`DELIVERY_REASON` owns. That reason is free text the invoker writes, and the
model applies it when it reads the directive. No gate checks that the
criteria set aside belong to a later step. A careless or dishonest reason can
scope out hard criteria for that run. Three things bound it: the reason is
fixed at init and recorded in `workflow_initialized`, so it can't be written
after the run misses a criterion; a criterion inside the declared step that
the run can't meet still goes to `deferral_approval` and a person; and the
issue stays open, so whatever the run didn't do is still on it. The backstop
is the run that finally closes the issue: it runs with `DELIVERY=closes` and
the full every-criterion bar. If that run never happens, the issue stays
open.

### Untrusted text in the title, body and commits

Non-closing mode reads the pull request's title, body and every commit
message. Any contributor to the branch writes commit messages, not only the
run. The script reads all of it with one `gh pr view` and parses the output
with jq. No part of it reaches `eval`, an unquoted expansion, or a command
line other than as a quoted argument.

Repository names taken from that text feed the old-name lookups (Decision
11), and the title and commits are new sources for them. The implementation
holds them to what the body's names get today, and Phase 1's deliverables
include it:

- Names are cut out with the script's `NAME_RE`, an owner of letters, digits,
  `-` and `_` that starts with a letter or digit, then a repository of
  letters, digits, `_`, `.` and `-` (`check-closing-keyword.sh:223`). A
  repository part that is `.` or `..` is dropped before any lookup
  (`check-closing-keyword.sh:277`), so no name can turn `repos/<name>` into
  another API path.
- A name is matched as a fixed string. It's compared, lower-cased, with
  `ISSUE_REPO`, the pull request's repository and the lookup's answer
  (`check-closing-keyword.sh:317`, `check-closing-keyword.sh:345`), and it
  reaches `gh api` as the one quoted argument `repos/<name>`
  (`check-closing-keyword.sh:291`). It's never built into an expression.
  `ISSUE_REPO` and the pull request's repository go into expressions only
  after `literal()` escapes their `.` (`check-closing-keyword.sh:192`).
- The pooled names stay under the one `MAX_LOOKUPS` cap (5) and the one
  `LOOKUP_SECS` deadline (20 seconds). Over the cap, the script refuses
  before making any call, and a failed or late lookup exits 3 and holds.
- A refusal quotes only the closing phrase the pattern matched and its
  source: `body`, `title`, or `commit` with the first seven characters of
  its `oid`. It never echoes a whole commit message, so text in a commit,
  a pasted secret included, isn't copied into the run's output beyond the
  matched phrase.

The match patterns are fixed in the script, and the pull request text is only
ever the input they run over. A check that runs past koto's 30-second gate
timeout is killed, and a killed command doesn't exit 0, so long or crafted
input can't pass the gate by running slow.

### The new flags

`--delivery-reason` is limited to koto's character allowlist, letters,
digits, spaces and `. _ / : @ + -`, by the same `vd_reason_chars_refusal`
check the hosted-ci reason uses (Decision 14). None of those characters means
anything special to a shell, and only the `finalization` and `pr_creation`
directives substitute the reason; no command does. The allowlist protects the
shell, not the model. The reason reaches the model as text inside those
directives. It's written by whoever invoked the run, and the directives quote
it as that invoker's stated scope, not as an instruction. Through /coordinate,
`dc_flag_allowed` also refuses a flag holding whitespace
(`skills/coordinate/scripts/dispatch-common.sh:521`), and the work-on row
admits `--delivery` only as the exact `--delivery=partial`.
Anyone who can dispatch through /coordinate can now declare a split, and the
effect is the one above: an issue left open, and a narrower bar for that run.

### Residual risk

- **Closing forms the script doesn't know.** The refusal side refuses only
  forms measured to close (`check-closing-keyword.sh:39-40`). If GitHub
  closes an issue on a keyword or a reference spelling outside that set, a
  non-closing pull request could close its issue with a criterion still
  open. GitHub's documentation lists close, fix and resolve and their forms,
  and Decision 2 rests on that; nothing in the repository measures the rest.
- **Closing from a branch commit message.** Whether GitHub closes an issue
  from a closing keyword in a commit on the branch, under the repository's
  merge settings, is unverified (Decision 1). With a squash merge, the
  default squash message can carry the branch's commit messages and the pull
  request's title onto the default branch, so a closing keyword in either can
  close the issue that way. The title and commit checks cover those cases;
  if GitHub closes nothing from them, the checks are a precaution that costs
  a reworded commit.
- **Changes after the gate.** The gate runs once, at `pr_creation`, and
  doesn't check again. An edit to the body, the title or the commits after
  it passes can still put a closing form of N where GitHub reads it and close
  the issue.
- **Commits past gh's list.** If `gh pr view` caps the commit list, a
  closing keyword in a commit past the cap isn't read. The body and
  title checks don't depend on the commit list.
- **The split's reason.** A vague or self-serving reason narrows the
  `finalization` bar for that run, and only the model's reading of it
  enforces the narrowing. Nothing checks mechanically which criteria a
  partial delivery left out; the bound is the closing run's full bar
  (Direction of failure). Accepting this design accepts that loosening of
  the every-criterion bar for partial deliveries.
- **Renamed repositories.** An old name another repository has since taken
  resolves to that repository, for the script and for GitHub alike, which is
  GitHub's own limit and unchanged from closing mode.

## Consequences

### Positive

- Both honest bodies, #1735's `Refs #1646` and #1549's `Part of #1548`,
  reach `ci_monitor` as written, with no override and no closing keyword
  written only to satisfy the gate.
- An approved deferral leaves its issue open with the deferred criterion on
  it, as the work-on PRD asks.
- A declared split carries a written scope from init, so finalization's
  narrowed bar rests on something fixed before any work rather than on the
  run's own reading of the issue.
- The gate reads the same in both modes with one word changed, and a pull
  request that also closes an unrelated issue isn't stopped.
- Each mode's logic sits in one place: the template picks the mode and the
  script decides the body. Every existing test case stays as it is, and a run
  with neither source sees today's gate.

### Negative

- An invoker has to declare a split before the run starts.
- A declared run that turns out to finish its issue can't close it, so a
  person closes it by hand.
- A fix round on a deferred pull request asks for approval again, since its
  own log holds none.
- A split started through /coordinate needs the new `entry-points.tsv`
  values. Without them, /coordinate refuses the flags.
- The reason pulls two ways. Decision 4 wants it to say what the pull request
  delivers and what stays open on the issue, which reads best as a sentence.
  Decision 5 makes a reason sent through /coordinate's work-on row one token
  with no whitespace, because `dc_flag_allowed` refuses a flag holding
  whitespace and /coordinate stores a run's flags joined with spaces and
  splits them back on spaces. Those runs get a shorter, harder-to-read reason,
  such as `step-1-of-2:validator-side`.
- A run opened by hand with `DELIVERY=partial` and no reason still gets
  non-closing mode at the gate.
- A body that names the issue only with another word, only by URL, or only in
  its title ends the run at `done_blocked`.
- Every issue-backed run now needs the script and jq present before the gate
  can pass, and a state log that exists but can't be parsed holds the run.
- The gate line grows to about twice its length.
- `--approved-pass`'s exit 1 means "no approved pass", not "refused", so
  wiring that mode into another gate takes the same mapping this command does.
- The open questions on unattended approval, commit-message closing,
  /coordinate's pick rule and title-only references stay open.
- GitHub's handling of three things is assumed, not verified in the
  repository. That a closing keyword in a commit message or the title can
  close the issue (Decision 1): if it can't, the title and commit checks are a
  cheap precaution. That `Ref`, `Refs` and `Part of` are plain mentions
  (Decision 2): this rests on GitHub's documented closing keywords, and if
  it's wrong, a body that passes could close its issue on merge. That a
  mention in the body records a cross-reference on the issue (Decision 2): if
  not, /coordinate's timeline read could miss a non-closing pull request.

### Mitigations

- A split declared late, or with no recorded scope, goes through
  `deferral_approval` instead, which still reaches a non-closing body.
- An issue left open by mistake is the cheap failure: it's visible and closes
  in one step.
- The person asked again in a fix round sees the same criterion and answers
  the same way.
- The `entry-points.tsv` values land in the same pull request as the rest
  (Decision 13), so /coordinate never sends a flag work-on doesn't know.
- Only runs started through /coordinate's work-on row get the one-token
  reason. Typed invocations keep full sentences. koto's allowlist still admits
  `: / - _ .`, enough for `step-1-of-2:validator-side/step-2-after-release`.
  And the reason isn't what a reviewer reads: Part 2 of the body states the
  split in plain words (Decision 7).
- A run with no reason keeps finalization's full bar (Decision 6), so nothing
  is set aside, and the misuse can only leave an issue open.
- The `pr_creation` directive names the three words and prescribes
  `Part of #N` (Decision 8), and the refusal message gives the exact line to
  add and lists every finding at once (Decision 10). It quotes only the
  matched phrase and a commit's short SHA, and a name looked up from the
  title or a commit passes the same checks as one from the body (Security
  Considerations).
- Every run already needs jq at `fix_determination`, and every neighbouring
  gate already checks its script with `test -x`.
- When a state-log line can't be parsed and the gate holds, jq's parse
  error on stderr points at the line. The fix is to repair that line or finish the pull
  request by hand.
- The test harness still extracts the longer line, and the leftover-placeholder
  check catches a missed substitution.
- The script header says what exit 1 means in that mode's own exit block, and
  only this command calls the mode.
- Each open question is listed in its decision's key assumptions, with what
  changes if the assumption turns out wrong.
