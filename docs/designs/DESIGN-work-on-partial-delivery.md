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
- **The gate consults nothing the run can forge.** A gate whose command reads
  only template variables can't see evidence submitted on the same tick. A
  gate whose command reads the run's state log does see the records already
  logged there, but most of them are the run's own writes. So whatever the
  gate consults has to be either a template variable fixed at init or a
  record in the state log that the run can't produce, which is the engine's
  own `transitioned` event.
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
  settings. Nothing in the repository verifies it. If it doesn't, the commit
  check is a cheap precaution.
- The split declaration carries a stated reason that names the step and what
  is left to a later pull request, and it's refused without one, the way
  `work-on-open.sh` refuses `--verification=hosted-ci` without a reason. Open
  question: whether `--delivery=partial` should carry a mandatory reason the
  body repeats. If not, a declared split has no record of which criteria are
  this step's, and its later-step criteria go through `deferral_approval`
  instead.
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
mode. The change is one variable, one token mapping, one script flag and a
log read, all inside the `closing_keyword` command, so the five created
edges, the name-based stubs in the other suites and every existing case in
`closing-keyword-gate_test.sh` stay as they are. `Part of #N` follows the PRD
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

## Decision Outcome

A run holds a non-closing delivery in exactly two ways, and the run itself
can produce neither. The invocation declares a planned split with
`--delivery=partial` and a stated reason, which `work-on-open.sh` maps to a
new `DELIVERY` variable fixed at init. Or the run reaches `pre_pr_evidence`
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

Not written yet.

## Implementation Approach

Not written yet.

## Security Considerations

Not written yet.

## Consequences

### What changes

- `skills/work-on/koto-templates/work-on.md` declares `DELIVERY`. The
  `closing_keyword` command gains the `DELIVERY` test, the log probe and the
  non-closing branch, and its comment drops the claim that a same-repository
  run never starts the script. The `done_blocked` failure reason, the
  `pr_creation`, `finalization` and `deferral_approval` directives and the
  `deferral_detail` description are reworded.
- `check-closing-keyword.sh` gains `--non-closing`, with a reference word list
  and the three pass shapes built on it, and `--approved-pass`. `--repo`
  becomes optional only with `--non-closing`. Its header, usage line and
  "Needs" line (`check-closing-keyword.sh:116`, which adds jq) are rewritten.
- `work-on-open.sh` maps `--delivery`, and
  `skills/coordinate/references/entry-points.tsv` admits it on the work-on
  row.
- `phase-6-pr.md:48-52` and `phase-6-pr.md:109-111`,
  `skills/work-on/references/finishing-obligations.md:18` and the SKILL.md
  passages on the closing obligation, initialization and silent deferral
  change with the behavior, naming the three words, the forms for each kind
  of run, and that the reference goes in Part 2.
- `closing-keyword-gate_test.sh` keeps every existing case. `run_gate` gains
  three substitutions and a leftover-placeholder check, and the `gh` stub
  gains one JSON branch with `PR_TITLE` and `PR_COMMITS`. New cases cover the
  accepted words and their edges, both run forms, title and commit refusals,
  the approved-pass log fixtures, the `gh` call counts and the new usage
  refusals. Among them, `GH-N` and the issue link are refused in a
  same-repository non-closing body, the reverse of today's closing-mode
  reading, pinned on purpose.

### What becomes easier

Both honest bodies, #1735's `Refs #1646` and #1549's `Part of #1548`, reach
`ci_monitor` as written, with no override and no closing keyword written only
to satisfy the gate. An approved deferral leaves its issue open, as the
work-on PRD asks. The gate reads the same in both modes with one word changed,
and a pull request that also closes an unrelated issue isn't stopped. Each
mode's logic sits in one place: the template picks the mode, the script
decides the body, and every existing test case stays as it is.

### What becomes harder

- An invoker has to declare a split before the run starts. A split declared
  late, or with no recorded scope, goes through `deferral_approval` instead,
  which still reaches a non-closing body.
- A declared run that turns out to finish its issue can't close it, so a
  person closes it by hand. That's the cheap failure: an open issue is
  visible and closes in one step.
- A fix round on a deferred pull request asks for approval again, since its
  own log holds none. The person sees the same criterion and answers the same
  way.
- A split dispatched through /coordinate needs the new `entry-points.tsv`
  value, added in the same change.
- A body that names the issue only with another word, only by URL, or only in
  its title ends the run at `done_blocked`. The `pr_creation` directive names
  the three words, and the refusal message gives the exact line to add.
- Every issue-backed run now needs the script and jq present before the gate
  can pass, and a state log that exists but can't be parsed holds the run.
  Every run already needs jq at `fix_determination`, and every neighbouring
  gate already checks its script with `test -x`.
- The gate line grows to about twice its length. The test harness still
  extracts it, and the leftover-placeholder check catches a missed
  substitution.
- `--approved-pass`'s exit 1 means "no approved pass", not "refused". Anyone
  wiring that mode into another gate has to map it the way this command does,
  and the script header says so in that mode's exit block.
- The open questions on unattended approval, commit-message closing, a
  mandatory split reason, /coordinate's pick rule and title-only references
  stay open for review, as listed in each decision's key assumptions.
