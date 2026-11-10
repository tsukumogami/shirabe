---
schema: design/v1
status: Accepted
problem: |
  /design commits its document at every stage, but before step 6.5 the
  document has no frontmatter status and only three of its nine required
  sections, on purpose, because the resume checks read a frontmatter
  Proposed as a finished design. A repository that validates design docs in
  a pre-commit hook refuses each of those commits with FC01, FC03 and FC04,
  and the skill's own document check refuses the same draft at Phases 5 and
  6. Both rules have a reason, they conflict, and the run has no stated way
  through.
decision: |
  Designs gain a Draft status. Every commit before step 6.5 carries a
  full-shape design at status Draft, with all nine sections and the
  unreached ones holding one fixed stub marker; only step 6.5 writes
  Proposed, through shirabe transition. The validator accepts Draft for
  designs, FC01 requires only status and problem at Draft, and a new
  lifecycle code, L11, makes a Draft design an error on a ready pull request.
  The commit rule is stated once in the shared commit-and-check reference.
  The resume checks read the committed status first, use the run's session
  keys only to catch an early Proposed in a session still attached on this
  host, and every loop-back resets the document to Draft. The binary ships
  first, then one plugin release with every plugin change; the hook and its
  setup script don't change.
rationale: |
  A Draft status is the only option that makes each refused commit valid on
  its own terms while satisfying the hook, the document check and the resume
  checks together, with nothing bypassed and no placeholder fields. It
  restores Proposed as a signal only the finishing step writes, which git
  carries between clones, so status can be read first. Making the checks
  draft-tolerable fails open, holding commits back loses the durable
  intermediate state in git, and narrowing the hook ships through its
  costliest channel and leaves an absent status as the in-progress signal.
  The session-key guard covers the one case status alone can't, a run that
  wrote Proposed early on this host.
upstream: docs/briefs/BRIEF-skeleton-commit.md
---

# DESIGN: Skeleton commit under a validating pre-commit hook

## Status

Accepted

## Context and Problem Statement

`/design` writes its document in stages and commits each stage. Phase 0 writes
a skeleton, `docs/designs/DESIGN-<topic>.md`, and commits it as
`docs(design): initialize design for <topic>`
(`skills/design/references/phases/phase-0-setup-freeform.md:61-108`, and the
PRD-mode twin at `phase-0-setup-prd.md:170-224`). The skeleton is incomplete
on purpose. Its frontmatter holds only `schema: design/v1`, and its body has
three of the nine required sections: Status, Context and Problem Statement,
and Decision Drivers. The missing `status` field is deliberate too. Phase 6's
resume check (`phase-6-final-review.md:14-17`) and the skill's Resume Logic
(`skills/design/SKILL.md:215`) read a frontmatter `status: Proposed` as a
finished design, so the skill holds the field back until step 6.5 writes the
whole frontmatter block (`phase-6-final-review.md:261-287`).

A repository can also run the design validator on every commit.
`shirabe install-hooks` writes a pre-commit hook that runs
`shirabe validate --format human` over the staged Markdown files and blocks the
commit on any non-zero exit (`crates/shirabe/src/main.rs:1479-1518`). In a niwa
workspace the hook arrives without anyone running that command:
`scripts/setup/shirabe-pre-commit.sh` installs it on `niwa create` and
`niwa apply`, and refreshes it whenever its body falls behind the one the
installed `shirabe` generates. The shirabe repository carries that setup
script, so its own clones run the hook.

The validator refuses the skeleton. Validating the exact text Phase 0
prescribes gives 11 errors and exit 2: four FC01 findings (`status`,
`problem`, `decision`, `rationale` missing; `crates/shirabe-validate/src/checks.rs:114`),
one FC03 (frontmatter status `""` against a body status of `Proposed`;
`checks.rs:170`), and six FC04 (the six later sections; `checks.rs:697`).
Review posture doesn't change this. Draft posture relaxes only the lifecycle
codes L02, L06, L07, L09 and L10; the whole FC family is always enforced
(`crates/shirabe-validate/src/validate.rs`, `posture_class`). Leaving the
frontmatter off entirely doesn't help either: the validator then skips the file
with a SCHEMA notice and exits 4, and the hook blocks on any non-zero exit.

Phase 0 is only the first refusal. Every commit the skill makes before step 6.5
carries a document without `status`, so FC01 and FC03 refuse each of them: the
Phase 5 draft commit (`phase-5-security.md:33`), the Phase 5 fix and section
commits (`:45`, `:166`), and the Phase 6 fix commits made before the frontmatter
is written (`phase-6-final-review.md:40`, `:191`). FC04 clears gradually as
phases add sections, but Security Considerations doesn't exist until Phase 5
writes it.

Two recent changes made this conflict real. Until #1319 the skeleton had no
frontmatter at all; that change added `schema: design/v1`, which turned the
skeleton from a file the validator skips into a design it checks. Days later,
#1445 had niwa's setup step install the hook in every clone that carries the
setup script, so a check that used to run only for people who installed it now
runs for everyone.

The design format is also the odd one out. Every other document format the
validator knows accepts a `Draft` status (`crates/shirabe-validate/src/formats.rs`;
the design list at `:388` is Proposed, Accepted, Planned, Current and
Superseded). `/brief` uses it the way `/design` can't: its Phase 2 writes the
frontmatter at `status: Draft`, stubs the sections Phase 3 will fill, commits
the partial draft (`skills/brief/references/phases/phase-2-draft.md:16`,
`:202-208`), and resumes by reading `status: Draft` as "drafting is under way"
(`:21`).

The skill already has its own notion of a legitimately incomplete document. Its
document check (`scripts/doc-check.sh`) reads a phase map,
`references/doc-check-phases.json`, and reports a required section the current
phase hasn't reached as `not_ready` instead of failing it. The pre-commit hook
has no such notion: it sees a staged file and validates it as finished.

This design hit the same refusal. Its own Phase 0 commit, in a shirabe clone
with the hook installed, was refused with the same eleven findings (four FC01,
one FC03, six FC04) and the validator's exit 2. The design was then written
uncommitted and first committed once it was whole. At Phase 5 the skill's own
document check refused the same draft, with no commit involved: its pre-jury
check exited 1 on two block-stage rules, `docs/required-fields` (FC01 for
`status`, `problem`, `decision` and `rationale`) and `docs/status-matches-body`
(FC03, frontmatter status `""` against a body status of `Proposed`), with
`docs/required-sections` reported as not ready.

The issue (#1646) records two runs that hit this, and both show what goes wrong
when a run improvises. One run filled the frontmatter, status included, before
Phase 6 so the hook would accept the commit. When that run resumed, both resume
checks read the early `status: Proposed` as progress: the Phase 6 check would
have skipped the review jury in step 6.1, and the Resume Logic row for
`Proposed` sits above the row that keys on the Phase 5 security report. The
other run stopped with the skeleton uncommitted rather than bypass the hook, and
stays blocked until either side changes.

The skill's intermediate commits do more than save work. `scripts/doc-events.sh`
diffs required sections between commits (`git show HEAD:<doc>`) to record which
sections each stage wrote, and `doc-check.sh` keys its state on the document's
commit. A fix that keeps the document uncommitted until it is whole changes
what those scripts see.

The question this design answers: when a repository validates design documents
at commit time, what does `/design` do with its partial document, and where
does that rule live (the skill, the validator, the hook's scope, or somewhere
else)?

Out of scope: changing the other document skills. They either commit only a
finished document or, like `/brief`, commit partial drafts under a status their
format accepts, so the conflict as reported is specific to `/design`. If the
chosen mechanism generalizes, the design says so, but it doesn't change those
skills. Also out of scope: Phase 5's empty summary commit
(#1642), except where the chosen commit rule settles it in passing.

## Decision Drivers

- **No route around the hook.** A run never commits with `--no-verify`, never
  edits or disables the hook, and never fakes a field to get past it. Any fix
  has to make the refused commit either valid or unnecessary.
- **The hook's guarantee stays meaningful.** A design that reaches review, or
  `main`, with missing frontmatter or sections must still be refused. Whatever
  is relaxed for an in-flight draft can't let an unfinished design through at
  the point where it is published.
- **Resume reads progress, not a placeholder.** A field the skill writes early
  to satisfy a check must not be readable as "this design is finished". The
  resume checks need a signal that only the step that finishes the work can
  produce.
- **Cost to adopters.** The skill ships in the plugin, the validator ships in
  the `shirabe` binary, and the hook body is regenerated by the binary and
  pushed into clones by the setup script. A fix that spans two of these has to
  work when a clone has a newer plugin than binary, or the reverse.
- **In-flight runs.** A run already stopped with an uncommitted skeleton, and a
  run that already filled its frontmatter early, both need a stated way to
  continue under the new rule.
- **Resumability.** A design run can be interrupted and picked up later,
  possibly from another clone. What the skill commits along the way is part of
  how that works, and the section-level telemetry depends on it.
- **One rule, one place.** The commit rule for a partial document should be
  stated once where every run reads it, not rediscovered per run.

## Considered Options

### Decision 1: What /design commits while its document is partial, and where the rule lives

Until step 6.5 the document is partial on purpose, and the pre-commit hook
refuses every commit the skill makes before then. The question is what those
commits should contain and which component owns the rule that lets them pass:
the skill, the validator, the hook's scope, or something else.

Two more readers of a partial design shape the answer. The skill's own document
check at Phases 5 and 6 runs the same validator and maps FC01 and FC03 to
block-stage rules with no phase awareness for frontmatter, so a statusless
design fails it whether or not a hook is installed. That, as much as the hook,
is what pushes a run to write `status: Proposed` early. And `/scope`'s
`skills/scope/scripts/hop-complete.sh` counts a design that passes SCHEMA,
FC01, FC03 and FC04 at the default posture as a finished design step. Anything
that lets a partial design pass those codes without another marker can let
`/scope` route past a design that is still being written.

Key assumptions:

- Repositories call `validate-docs.yml` and `lifecycle.yml` the way the example
  callers do, with the lifecycle check at `posture: auto`. If a repository runs
  no lifecycle job, or pins `posture: draft`, a hand-pushed Draft design with
  stub sections passes its review checks, and the guarantee rests on `/design`
  never opening a PR before 6.5. A repository can also pass `validate-docs.yml`
  its `custom-statuses` input, which replaces a format's status list; a design
  list without `Draft` refuses Draft designs in that repository's CI.
- The document check refuses the statusless draft at Phase 5. This was
  observed: the check refused this design's own draft at Phase 5 with FC01 and
  FC03 at block stage.
- A Draft design that has `status` and `problem` but not yet `decision` or
  `rationale` is acceptable once FC01 depends on the status. The fallback is
  plainly worded placeholder values, which would need the design to explain why
  Draft makes them honest.
- Step 6.2 records the review jury's keys before 6.5 writes `Proposed`, so a
  `Proposed` design in a live session with no jury keys was written early.
  Decision 2 makes this hold on the fallback jury path too.

#### Chosen: A Draft status for designs, one commit rule in the skill, permission in the validator

Every commit `/design` makes before step 6.5 carries a design at frontmatter
`status: Draft` with all nine required sections present, the unreached ones as
marked stubs. Step 6.5 is the only step that writes `status: Proposed`. The rule
has two parts with one owner each: the skill states the commit rule once, and
the validator holds the permission.

The commit rule goes in the shared commit-and-check reference every document
skill reads, `references/doc-check-steps.md`, and `/design`'s Phase 0 and later
commit steps point to it: a partial document is committed only in a form
`shirabe validate` accepts, which for a design means `status: Draft` with stub
sections, and a step with nothing new to commit makes no commit. That last
clause settles #1642's empty Phase 5 commit in passing.

In the binary:

- `Draft` joins the design status list (`crates/shirabe-validate/src/formats.rs:388`)
  and the design transition list (`transition.rs:448`), with a test that keeps
  the two lists equal.
- FC01 becomes status-conditional for designs. At `Draft` it requires `status`
  and `problem`; at every other status it requires all four fields, as today.
  FC01 stays an error at every posture, so the FC family is still always
  enforced.
- A new lifecycle code, draft-tolerable and an error at ready posture, refuses a
  design at `Draft` on a ready PR. An unfinished design is still refused where
  it is published.

In the plugin:

- Phase 0, in both the freeform and PRD variants, writes `schema`,
  `status: Draft`, `problem` and all nine sections, each unreached one carrying
  a single fixed stub marker line that is defined once and tested.
- Step 6.5 writes `decision` and `rationale` and moves `Draft` to `Proposed`.
- Section-based resume rows (has Solution Architecture, has Considered Options,
  and Phase 4's check) treat a section that still carries the stub marker as
  absent. How the status rows read progress is Decision 2.
- In `/scope`, `hop-complete.sh` treats a design at `Draft` as not complete,
  `resume-probe.sh` gains a `Draft` row that routes back to the design step, and
  `/plan`'s status table and the design format and lifecycle references list
  `Draft`.
- A Phase 0 probe validates a tiny Draft design. When an older binary refuses
  it, the run stops and names the `shirabe` release the plugin needs.

The hook body, `scripts/setup/shirabe-pre-commit.sh`, `validate-docs.yml`,
`lifecycle.yml` and the document check don't change. With status-conditional
FC01, a Draft design with stubs passes the document check's required-fields and
status-matches-body rules.

This is the only option that makes each refused commit valid on its own terms
while satisfying the hook, the skill's document check and the resume checks
together, with no change to the hook or the setup script. Nothing bypasses a
check, and nothing writes a placeholder field. It is also the only option where
the in-progress signal is a value the finishing step replaces: `Draft` is
written at Phase 0 and only 6.5 writes `Proposed`, so `Proposed` again means
"6.5 ran" for every reader, inside or outside a live session.

Under version skew it fails closed and narrowly. With a plugin newer than the
binary, the old validator refuses `Draft` with FC02 on the design file only, and
the Phase 0 probe turns that into a clear stop before any work. With a binary
newer than the plugin, the old plugin's statusless skeleton is refused exactly
as today. It keeps intermediate commits, so section telemetry and plain-git
moves of a partial draft between clones keep working. And the rule is one
sentence in the shared commit reference, backed by a status value the
validator owns.

The cost is a coordinated plugin and binary release, with the changes
Solution Architecture lists. A stubbed Draft design also passes per-file CI,
where today's statusless skeleton fails it. The Draft-at-ready lifecycle code
bounds that, and so do `/design` never pushing before 6.5 and the opt-in
`custom-statuses` input. Today's per-file CI doesn't refuse an unfinished design either: it refuses
only a missing `status` key, and a stubbed `Proposed` design passes it.

Every other format the validator knows already accepts `Draft`, and `/brief`
already commits partial drafts at `Draft` with stub sections. The commit rule
in `doc-check-steps.md` applies to every document skill as written; only
`/design` has to change to meet it.

#### Alternatives Considered

**Full-shape stub skeleton at Proposed, progress read from session keys
(skill only).** Phase 0 writes every field and section as stubs at `Proposed`,
and resume reads the skill's session keys and a stub marker. It needs no binary
change and so has no skew. Rejected because `Proposed` written at Phase 0 is
exactly the early field the resume driver forbids: `/plan`, a closed session or
another clone reads it as finished. `hop-complete.sh` and CI could only tell a
stub from a finished design through a marker convention, and refusing a
hand-pushed stub in CI would need binary code anyway. Its useful parts, the stub
marker and a key check on resume, are part of the chosen option.

**No commit until the document is whole (skill only, merged with holding the
body in session keys).** Nothing under `docs/designs/` is committed before 6.5,
the body is mirrored to a session key, the document check treats 6.5-only fields
as not ready, and `doc-events.sh` gains a working-tree mode. Rejected because it
makes the refused commits unnecessary by giving up what they provide: durable
intermediate state in git, plain-git moves of a draft between clones, and
commit-based section telemetry. In their place it puts a machine-local copy that
needs its own precedence rule and a change to a shared telemetry script. Its
list of required plugin changes is as long as the chosen option's. It is the
fallback if moving a partial draft between clones through git turns out not to
matter.

**Make FC01, FC03 and FC04 draft-tolerable in the validator.** Partial designs
get notices at draft posture and errors at `--mode=ready`, and the skill changes
nothing. Rejected because a notice-only run counts as clean
(`crates/shirabe/src/main.rs:825-838`), so the change fails open. With a binary
newer than the plugin, `hop-complete.sh` would report a bare skeleton as a
finished design step and `validate-docs.yml` would pass statusless designs on
draft PRs. The publish guarantee would then depend on every strict caller,
third-party CI included, adding `--mode=ready`. It also breaks the rule that the
FC family is always enforced.

**Narrow the hook's scope.** A commit-time mode that only the hook passes
relaxes FC01, FC03 and FC04 for a statusless `design/v1` file, leaving per-file
CI, `hop-complete.sh` and resume as they are and every publish check at today's
strictness. Rejected because it ships through the hook body, the costliest of
the three channels. A new body over an older binary blocks every Markdown
commit unless the static hook gains a capability probe, and repositories outside
niwa never get the new body without `shirabe install-hooks --force`. The rule
would be split across the validator mode, the hook body and a separate fix to
the document check, and its in-progress signal, an absent status, can't tell
"not yet" from "forgotten". It is the fallback if `Draft` is rejected for
designs.

### Decision 2: How the resume checks read a run's progress

Two places decide where an interrupted run picks up: the Resume Logic table in
`skills/design/SKILL.md`, where the `Proposed` row at :215 sits above the row
keyed on the Phase 5 security report at :216, and the Phase 6 resume check
(`phase-6-final-review.md:14-17`), which sends `Proposed` straight to 6.7. Both
read `status: Proposed` as a finished design. Decision 1 is binding here: under
it only step 6.5 writes `Proposed`, which makes the status trustworthy for new
runs, but not by itself on every path.

Four facts shape the answer. The session-open step (`scripts/skill-session.sh
open`) runs before every resume row and always leaves the session live, printing
`opened=new`, `opened=attached` or `opened=replaced`; a finished session's keys
are dropped on replace. So "the session is closed" can't be observed by the time
the rows run. Sessions are local to a host, so any signal kept in session keys
is missing on another clone, after a prune and after a replace. "Continue
revising" at 6.7 loops back with the document already `Proposed` and committed
and the round-one jury keys still present, and nothing removes them, so today's
check skips the second jury even without #1646. And under `--auto`, or under
`/scope` with the status prompt suppressed, the `Proposed` row continues
silently and 6.7 takes the recommended verdict, so an early `Proposed` can reach
Accepted with no jury and no human. There is also a crash window: a stop between
6.5 (`Proposed` written) and 6.6 (commit, push, PR) is skipped past by today's
check, losing the commit and the PR.

Key assumptions:

- The run keeps the session-open outcome from its first step, and the rows read
  it. If they can't, "attached" can't be told from "new" or "replaced", and the
  guard would have to treat every `Proposed` design without jury keys as early,
  re-running the jury on every resume from another clone.
- The run #1646 records as having written `Proposed` early still has its
  session on its original host, holding the Phase 5 security key and no jury
  keys. If not, that one run relies on a migration note in the release.
- The serial self-review fallback can write the same three review files as the
  parallel jury. If not, a fallback round leaves no keys, and a resume inside
  its own Phase 6 re-runs the jury: safe, but costly.
- Under a parent skill, the new rows state their outcome when status prompts are
  suppressed, and resolve as "continue".

#### Chosen: Status first, with a key guard for an attached session and a reset on every loop-back

The committed status is the progress signal, because under Decision 1 it is the
only signal that survives a move between clones and only 6.5 writes `Proposed`.
Session keys act as a guard only where they carry information: when the
session-open step printed `opened=attached`, so this host holds the run's live
keys.

The Resume Logic in `skills/design/SKILL.md`, in order after the
parent-dispatch row:

1. `Accepted`: offer to revise or start fresh (unchanged).
2. The document exists with no frontmatter `status`, which is the shape of a run
   stopped with a statusless skeleton: rewrite it to Decision 1's Draft shape
   (Draft block, all nine sections, unreached ones stubbed), commit, and
   continue down the rows.
3. `Proposed`, `opened=attached`, and no Phase 6 jury key in the session: the
   status was written early. Set the frontmatter and body Status back to
   `Draft`, take out any placeholder `decision` or `rationale`, commit, and
   continue down the rows. Under `--auto` or a suppressed prompt this row is
   taken without asking.
4. `Proposed` in any other case (`opened=new`, `opened=replaced`, or jury keys
   present): continue at Phase 6's own check.
5. `Draft`: continue down the key and section rows, which pick the phase. A
   section that still carries the stub marker counts as absent.
6. The existing key, section, coordination and summary rows, in their current
   order.

The Phase 6 resume check in `phase-6-final-review.md`:

- `Draft`: run from 6.1, the document check and then the jury.
- `Proposed` with the attached, no-jury-key shape: back to `Draft` as in row 3,
  then 6.1.
- `Proposed` but not yet committed (`git diff --quiet HEAD -- <doc>` fails, or
  HEAD's frontmatter status isn't `Proposed`): resume at 6.6, so the commit and,
  on a direct run, the push and PR happen.
- `Proposed` and committed: 6.7, present for approval.

Every loop-back resets both signals. "Continue revising" at 6.7 and 6.2's
loop-back set the frontmatter and body Status back to `Draft` and remove the
Phase 6 jury keys, the way `/brief` step 4.6 and `/design` Phase 5 already
remove their verdict keys. The serial self-review fallback writes the three
pinned review files, so 6.2 ingests its keys like a normal round. Step 6.4's
checklist expects `Draft` rather than "must be Proposed", and 6.5 writes
`Proposed` into the frontmatter and the body `## Status` together so FC03 holds.

A loop-back after 6.6 happens with the pull request already open. The revision
commits go to the same branch and the same pull request. While the document is
back at `Draft`, L11 reports it there, as a notice on a draft pull request and
an error on a ready one, so the pull request can't merge an unfinished design.
The next pass through 6.5 moves it to `Proposed`, and 6.6 commits and pushes to
the existing pull request without opening a second one.

By case:

- A new run with a live session: the status is `Draft` until 6.5, so the rows
  read progress from keys and sections exactly as today, and `Proposed` appears
  only after the jury.
- The session is gone (another clone or host, a pruned session, or a finished
  session the open step replaced): the guard doesn't apply and the committed
  status is read as written. A Draft design resumes down the section rows; a
  `Proposed` one goes to 6.6 or 6.7, with no repeated review and no duplicate PR.
- A run that wrote `Proposed` early: on its own host the session attaches, holds
  the Phase 5 key and no jury key, so row 3 reverts it to `Draft` and the jury
  runs. If its session is gone, the release note's one-line migration step
  covers it.
- A run stopped with an uncommitted statusless skeleton: row 2 rewrites it to
  the Draft shape and commits it, which retries the Phase 0 commit the run never
  made, and the summary and coordination keys pick the phase.
- A second review round: the reset leaves a `Draft` document with no jury keys,
  so the jury runs again whether or not the run is interrupted.

The driver asks for a signal only the finishing step can produce, and the
resumability driver asks that a run can be picked up from another clone.
Decision 1 already made the status a signal only 6.5 writes, and git carries it
between clones. Reading it first keeps resumes from another clone, or after the
session was closed, cheap and correct. The status goes wrong only where
something other than 6.5 produced a `Proposed`: an early fill by a run that
predates Decision 1, and the loop-back. The loop-back is closed at its source by
the reset. The early fill is closed by the key guard on the host where it
happened. This also follows the house pattern: `/brief`, `/prd`, `/strategy`,
`/roadmap` and `/vision` read status first, treat `Draft` as "continue down the
rows", check jury keys inside the jury phase, and remove verdict keys on
loop-back. It is plugin-only, so it adds no skew beyond Decision 1's.

#### Alternatives Considered

**Status alone, on the Draft/Proposed split.** Trust `Proposed` because only 6.5
writes it, with the same loop-back reset, crash-window row and statusless-skeleton
row, plus a migration note for runs that wrote `Proposed` early. Rejected
because an unattended resume of such a run on its own host would still read the
early `Proposed` as finished and could reach Accepted with no jury, even though
its session keys can prove the status is early. Leaving them unread means
counting on an author to find and apply a release note first. The chosen option
is this option plus that guard.

**Session keys, with status read only for Accepted.** A key that 6.5 writes,
plus the jury keys, decide progress. It is exact on one host, and fine-grained
enough to skip a jury that already ran. Rejected because keys are local to a
host and are dropped when a finished session is replaced. A finished design
resumed from another clone, or after its session was closed, would re-run the
security review and the whole jury, and 6.6 would collide with the PR that
already exists. That cost recurs on every such resume, while the case it alone
covers, an early `Proposed` whose session is gone, is a one-off legacy shape.

**Reorder the Resume Logic rows.** Moving the key rows above the `Proposed` row
fixes only the :215-above-:216 order. Rejected as a fix on its own because
Phase 6's check still sends `Proposed` to 6.7, and it does nothing when the
session is gone or after "Continue revising". Row 3 of the chosen option keeps
its useful part: a key check placed above the plain `Proposed` row.

**A completion marker in git history.** `Proposed` counts only if it was
introduced by the 6.6 commit, `docs(design): add design for <topic>`. It is
durable across clones and would catch an early `Proposed` whose session is gone.
Rejected because it adds a third progress signal and a new contract on a commit
subject nothing reads today. A rewording rebase, a hand-made status commit or a
squash breaks it, and the only case it adds over the chosen option is a known
one-off already covered by a migration note.

### Decision 3: How the plugin changes ship

The plugin changes fall into three groups: the commit rule and Draft skeleton,
the resume rows, and the other readers of design status. They could ship one
release at a time or together.

#### Chosen: One plugin release for all three groups, after the binary release

Each group closes only half of a failure on its own. A plugin that writes
`Draft` but still trusts any `Proposed` leaves an early `Proposed` from an older
run readable as finished. A plugin with the new resume rows but the old
statusless skeleton is still refused by the hook. A plugin that writes `Draft`
before `/scope`'s `hop-complete.sh` knows it can let `/scope` misread a draft.
Shipping them together, after a binary that accepts `Draft`, means no plugin
release ever carries half the rule.

#### Alternatives Considered

**One release per group.** Smaller releases, each easier to review. Rejected
because every intermediate release leaves one of the two reported failures in
place, or adds a new one in `/scope`, and the groups are small enough to review
together.

### Decision 4: Where the resume rows get the session-open outcome

The guard in Decision 2 needs to know whether the session-open step attached to
a live session or started a new one.

#### Chosen: The run carries the outcome from its first step

`scripts/skill-session.sh open` already prints `opened=new`, `opened=attached`
or `opened=replaced`, and it runs before every resume row in the same
invocation. The run reads that line and the rows use it.

#### Alternatives Considered

**Store the outcome in a session key.** It would survive a long run losing track
of its first step's output. Rejected because the value describes this
invocation, not the session: a key written by one invocation would be read by
the next one as stale, and the open step would have to rewrite it every time to
stay correct, which adds a write and buys nothing over reading the line it
already prints.

## Decision Outcome

The first two decisions settle one rule from two sides. Decision 1 gives a partial
design a status the validator accepts and the hook therefore passes, and makes
`Proposed` a value only step 6.5 writes. Decision 2 makes the resume checks read
that status first and closes the paths where a `Proposed` could still appear
without 6.5: a run that predates the change, and a review loop-back.

Decision 2 refines Decision 1's resume sketch in two ways, and Decision 2's
version governs. Decision 1 trusted `Proposed` only with jury keys or a closed
session. The session is never closed when the resume rows run, so Decision 2
uses the session-open outcome instead: keys are consulted only in an attached
session, and a `Proposed` design resumed anywhere else is read as written.
Decision 1 also assumed jury keys exist exactly when the jury ran. Decision 2
makes that hold by having the fallback jury write the same files and by removing
the keys on every loop-back, since a key left over from round one would
otherwise mark round two as reviewed.

Together they change four things. The validator gains `Draft` for designs and a
status-conditional FC01, and a lifecycle code refuses `Draft` on a ready PR. The
skill commits a full-shape Draft design from Phase 0 and writes `Proposed` only
at 6.5, under one commit rule in `references/doc-check-steps.md`. The resume
checks read status first, guard an attached session with its keys, and reset to
`Draft` on every loop-back. `/scope` and `/plan` learn `Draft`. The hook and its
setup script are untouched, so a repository that validates designs at commit
time needs nothing beyond a `shirabe` and plugin pair that both know `Draft`.

## Solution Architecture

### Overview

A design gets a lifecycle stage before `Proposed`. From Phase 0 to step 6.5 the
document sits at `status: Draft` in full shape: every frontmatter field the
format requires at that status, and all nine sections, the unreached ones
holding a stub marker. Each intermediate commit is therefore a valid document,
and the pre-commit hook passes it with no change to the hook. Step 6.5 is the
one place that moves the document to `Proposed`. The resume checks read the
committed status first, and use the run's session keys only to catch a
`Proposed` written early in a session that is still live on this host.

### Components

The binary (`crates/shirabe-validate`):

- `formats.rs:388`: the design status list gains `Draft`, ahead of `Proposed`.
- `transition.rs:448`: the design transition list gains `Draft`, so
  `shirabe transition` can move a design between `Draft` and `Proposed`. The
  design rule refuses any move into `Draft` except from `Proposed`, so the
  command can't send an Accepted, Planned or Current design back to drafting.
  A unit test asserts the status and transition lists are equal, so they
  can't drift.
- `checks.rs`, `check_fc01` (:114): for a design at `Draft`, the required fields
  are `status` and `problem`. Every other design status, and every other format,
  keeps its current list. FC01 stays always enforced.
- `lifecycle.rs`: a new code, L11, fires on a design at `Draft` in the change
  set. `validate.rs`'s `posture_class` lists it as draft-tolerable, so it is a
  notice on a draft PR and an error on a ready one, the same way L10 treats a
  plan step that is still an outline.

The plugin, the commit rule:

- `references/doc-check-steps.md` gains the commit rule: a partial document is
  committed only in a form `shirabe validate` accepts, and a step with nothing
  new to commit makes no commit. For a design, the accepted form is
  `status: Draft` with stub sections.
- One stub marker, a single fixed line defined once in
  `skills/design/references/design-format.md` and placed as the only body of an
  unreached section. A test checks that the Phase 0 templates and the resume
  rows use the same string.

The plugin, `/design`:

- `phase-0-setup-freeform.md` and `phase-0-setup-prd.md`: the skeleton
  frontmatter gains `status: Draft` and `problem`, the body Status reads
  `Draft`, and the six later sections are written with the stub marker. The
  commit step points to the commit rule.
- Every later commit step (`phase-5-security.md:33`, `:45`, `:166`;
  `phase-6-final-review.md:40`, `:191`) points to the commit rule instead of
  committing unconditionally.
- Step 6.4's checklist expects `Draft`. Step 6.5 writes `decision` and
  `rationale`, then runs `shirabe transition <doc> Proposed`, which rewrites
  the frontmatter `status:` line and the body `## Status` line together.
- `skills/design/SKILL.md` Resume Logic and the Phase 6 resume check: the rows
  Decision 2 lists, in that order.
- 6.2's loop-back and 6.7's "Continue revising": set the document back to
  `Draft` with `shirabe transition` and remove the Phase 6 jury keys before
  looping. After 6.6 the revision commits go to the open pull request, where
  L11 flags the Draft design until 6.5 runs again.
- The serial self-review fallback in 6.1 writes the same three pinned review
  files as the parallel jury.
- A Phase 0 probe: validate a minimal Draft design with the installed
  `shirabe`. If the binary refuses it, stop before any work and name the
  release the plugin needs.

The plugin, other readers of design status:

- `skills/scope/scripts/hop-complete.sh`: a design at `Draft` is not a complete
  design step.
- `skills/scope/scripts/resume-probe.sh`: a `Draft` design routes back to the
  design step.
- `skills/plan/references/phases/phase-1-analysis.md`,
  `skills/design/references/design-format.md` and
  `skills/design/references/lifecycle.md`: list `Draft` and what it means.

### Key Interfaces

- **The status contract.** `Draft` means drafting is under way and the document
  isn't reviewable. `Proposed` means step 6.5 ran. Only 6.5 writes `Proposed`,
  and every loop-back writes `Draft`.
- **FC01 for designs.** At `Draft`: `status` and `problem`. At any other status:
  `status`, `problem`, `decision` and `rationale`.
- **L11.** "Design is still a draft": draft-tolerable, so a notice at draft
  posture and an error at ready posture.
- **The stub marker.** One fixed line. A section whose only body is the marker
  counts as absent for every resume row and section check that reads sections.
- **The session-open outcome.** The `opened=new|attached|replaced` line that
  `scripts/skill-session.sh open` already prints. The run carries it from its
  first step to the resume rows; nothing new is written for it.
- **The commit rule.** A sentence in `references/doc-check-steps.md` that any
  document skill can cite.

### Data Flow

```
Phase 0      write Draft skeleton (all sections, stubs)  -> commit (hook passes)
Phases 1-5   replace stubs with content, status Draft    -> commit when changed
6.1-6.2      document check, review jury                 -> jury keys written
  loop-back  status back to Draft, jury keys removed     -> back to 6.1
6.4-6.5      checklist expects Draft; write decision,
             rationale; Draft -> Proposed                -> 6.6 commit, push, PR
6.7          Continue revising -> Draft, keys removed, same PR; or Accepted
```

On resume, the rows read the committed status, then the session-open outcome,
then the session keys and sections. A `Proposed` document in an attached session
with no jury keys goes back to `Draft` before anything else runs.

## Implementation Approach

### Phase 1: Validator accepts Draft for designs

The binary goes first, because every plugin change depends on a validator that
accepts `Draft`, and a binary that accepts it changes nothing for a plugin that
doesn't write it yet.

Deliverables:
- `Draft` in the design lists in `formats.rs` and `transition.rs`, with the
  list-equality test.
- Status-conditional FC01 for designs in `checks.rs`, with tests at `Draft` and
  at `Proposed`, and spelling tests: lowercase `draft`, quoted `"Draft"`,
  trailing whitespace.
- The design transition rule refusing moves into `Draft` except from
  `Proposed`, with tests.
- L11 in `lifecycle.rs` and its posture class in `validate.rs`, with tests at
  draft and ready posture.
- A `shirabe` release that carries them.

### Phase 2: The commit rule and the Draft skeleton

Depends on Phase 1's release. Phases 2 to 4 ship in one plugin release: a
plugin that writes `Draft` but still trusts an early `Proposed`, or the reverse,
would leave one of the two failures in place.

Deliverables:
- The commit rule in `references/doc-check-steps.md`.
- The stub marker in `design-format.md`, with its test.
- The Draft skeleton in both Phase 0 files, and every later commit step pointed
  to the commit rule.
- Step 6.4's checklist and step 6.5's `Draft` to `Proposed` move through
  `shirabe transition`.
- The Phase 0 validator probe.

### Phase 3: Resume reads progress

Deliverables:
- The Resume Logic rows in `skills/design/SKILL.md` and the Phase 6 resume check
  rows, as Decision 2 lists them.
- The loop-back reset in 6.2 and 6.7, and the post-6.6 revision window in 6.7.
- The pathspec on the resume rows' commits.
- The fallback jury writing the pinned review files.

### Phase 4: Other readers of design status

Deliverables:
- `Draft` handling in `hop-complete.sh` and `resume-probe.sh`, with tests.
- `Draft` in `/plan`'s status reading and in the design format and lifecycle
  references.
- A release note with the one-line migration step for a run that wrote
  `Proposed` early and whose session is gone: set the status back to `Draft`
  and resume.

## Security Considerations

This design adds no network access, downloads, credentials or new process
privileges. It changes what an integrity gate accepts, so the considerations
below concern that gate.

**What the gate defends against.** The validator and hook keep an unfinished
design from being published by mistake: a run that stops early, a resume that
misreads progress, or a branch pushed by hand. They don't defend against an
author who means to publish an unfinished design, who can already edit a
status by hand; review on the pull request covers that case.

**The gate is relaxed for one status.** A design at `status: Draft` with
`status` and `problem` set now passes FC01, FC03 and FC04, at every posture.
Before this change, no posture let a partial design pass. One check bounds the
relaxation: L11, which is an error on a ready pull request. Two other limits
are behavior rather than checks: `/design` opens its pull request only at 6.6,
after 6.5 has written `Proposed`, and a repository can drop `Draft` from its
design list with `validate-docs.yml`'s `custom-statuses` input. L11 holds only
where a repository runs the lifecycle check at `posture: auto`, and only on
pull requests. `/scope` and `/plan` refuse a Draft design regardless of CI.

**A finished design can't be moved back to Draft unnoticed.**
`shirabe transition` refuses any move into `Draft` except from `Proposed`. A
hand edit that sets an Accepted, Planned or Current design to `Draft` and drops
`decision` and `rationale` passes FC01, but L11 fires on any design at `Draft`
in the change set, so a ready pull request refuses it the same way it refuses a
new Draft design.

**Checks must agree on status.** FC01's conditional field list is selected from
the parsed frontmatter status, the same value FC02 and FC03 read. FC01 picks the
Draft list only when that value is exactly `Draft`, the comparison FC02 uses;
any other spelling, such as `draft` or a value with stray characters, gets the
full four-field list, and FC02 refuses it as outside the enum. YAML parsing
already removes quoting and surrounding whitespace. Tests cover a duplicate
`status` key, a status outside the enum, a lowercase `draft`, a quoted
`"Draft"` and trailing whitespace.

**Readers treat design text as data.** `hop-complete.sh`, `resume-probe.sh` and
the resume rows compare the status and the stub marker against fixed values
with quoted comparisons, treat unknown values as "not complete", and match the
stub marker only as the whole body of a section. The resume rows an agent runs
under `--auto` decide on those comparisons alone: the document's prose is data,
never instructions, and no row takes an action the document names. A stub
marker pasted into a written section only makes that section count as absent,
which sends the run back to write it; it can't move a run forward.

**The Phase 0 probe is read-only and local.** It validates a throwaway file in a
fresh directory from `mktemp -d`, outside the work tree, and decides on the
validator's exit status. On failure it prints the `shirabe` version the plugin needs,
without downloading or installing anything. It trusts the `shirabe` on `PATH`,
as every other validator call does.

**Automatic resume rewrites are narrow.** The status-revert and
skeleton-rewrite rows change only the design file's status, body Status and
placeholder fields, and commit through the hook like any other commit, naming
the design file as the commit's only pathspec, so nothing else staged goes with
them. They are
the only commits taken without a prompt under `--auto`. They reduce an existing
risk: an early `Proposed` could otherwise reach Accepted with no review.

**Residual risks.** A Draft design can reach the default branch in a repository
with no ready-posture lifecycle check, or through a push that skips pull
requests, because L11 runs only on pull requests. This design doesn't close
that gap. Running L11 on pushes to the default branch, or having
`validate-docs.yml` refuse a Draft design there by default, is left to the
maintainers to accept or act on. A run that wrote `Proposed` early and lost its
session relies on the release note's migration step. Both appear in
Consequences.

## Consequences

### Positive

- A repository that validates designs at commit time can run `/design` with no
  hook or setup change. Every intermediate commit is a valid document.
- The skill's own document check stops refusing its Phase 5 and Phase 6 drafts.
- `Proposed` means "step 6.5 ran" for every reader: resume, `/scope`, `/plan`
  and a person reading the file on any clone.
- A second review round always gets a jury. Today's check skips it whether or
  not the document's status was written early.
- A stop between 6.5 and 6.6 no longer loses the commit and the PR.
- Section telemetry and plain-git moves of a partial draft keep working,
  because the intermediate commits stay.
- Designs behave like every other format the validator knows, all of which
  already accept `Draft`.

### Negative

- It needs a coordinated release: a `shirabe` binary first, then a plugin
  release that depends on it.
- Every reader of design status has to change in step: the status and
  transition lists and FC01 in the binary, the two resume checks,
  `hop-complete.sh`, `resume-probe.sh` and `/plan`'s status table.
- The stub sections committed at Phase 0 show up in section telemetry as first
  writes, and the real content later as rewrites. `/brief` already has the same
  distortion.
- A stubbed Draft design passes per-file CI, and can reach the default branch
  in a repository with no ready-posture lifecycle check or through a direct
  push. Whether to close that is left to the maintainers.
- The resume rows read one more input, the session-open outcome, and the
  loop-back paths gain a status revert and a key removal that must stay
  together.
- A run that wrote `Proposed` early and whose session is gone still needs its
  author to apply the migration step by hand.

### Mitigations

- The Phase 0 probe turns a plugin-ahead-of-binary skew into a clear stop
  before any work, and the reverse skew behaves exactly as today.
- The list-equality test keeps the two binary lists together, and the stub
  marker test keeps the templates and resume rows on one string.
- L11 refuses a Draft design on a ready pull request wherever the lifecycle
  check runs at `posture: auto`, a design moved back to `Draft` included, and
  `/design` never pushes before 6.5.
- `doc-events.sh` can learn to treat a stub-marked section as absent, which
  removes the telemetry distortion. It isn't required for the fix.
- The release note carries the one-line migration step, and on its own host a
  run that wrote `Proposed` early is caught by the key guard with no hand edit.
