---
schema: design/v1
status: Accepted
problem: |
  A coordinator session drives a roadmap or a standing discipline by
  handing work to other sessions, but shirabe has no skill for it, so
  each one is started from a prose description of the job. The PRD fixes
  what the skill must carry. The open questions are technical: how the
  content splits between SKILL.md and its references, whether any step
  needs a workflow-engine gate, and how the record is laid out on GitHub
  so it survives restarts, rotation handoffs and the roadmap's own
  deletion.
decision: |
  Ship `skills/coordinate/` as prose with no koto template and no script.
  SKILL.md states every rule once: invocation, the seven-step loop with
  its failure branch and bounds, the never-does list, a nine-term
  glossary, the record's contents and placement, later work and known
  limitations. Four references hold only mechanics and templates: the
  loop's reconcile and failure procedures, the record template, the
  worker brief template and the verification checklist. The record is a
  scope-keyed ledger: one fixed branch and draft pull request per scope
  (`coordinate/roadmap-<name>` or `coordinate/discipline-<name>`), live
  holdings, deferrals, side effects and reversals in Part 2 of the body,
  roadmap Progress committed on that branch with the default branch
  merged in rather than rebased, and one overwritten handoff file per
  discipline at `docs/disciplines/<name>.md`.
rationale: |
  Prose is the PRD's default and no step clears the bar for a gate:
  reconcile and record tooling are later features, a record write is an
  outward-facing event shirabe keeps off koto default actions, and a
  koto session has no story for a loop that runs for days. Nearly every
  acceptance criterion reads SKILL.md's own text, so the rules must live
  there, and references can only add what SKILL.md doesn't say without
  creating a second copy that drifts. A constant branch per scope gets
  uniqueness from GitHub's one-open-PR-per-head rule instead of an
  ownership filter that is known to be broken, merging instead of
  rebasing keeps the Progress history and survives the roadmap's
  deletion, and a fixed handoff path gives a successor one read.
upstream: docs/prds/PRD-coordinate-skill.md
---

# DESIGN: coordinate-skill

## Status

Accepted

## Context and Problem Statement

A coordinator is a long-running session that drives a roadmap or a
standing discipline by handing units of work to other sessions,
verifying what they push, and landing it or putting it in front of a
person. The PRD (`docs/prds/PRD-coordinate-skill.md`) fixes what a skill
for that session must carry: a seven-step loop, a failure branch, a
default bound of three workers, the things a coordinator never does, a
nine-term vocabulary, a record that stores only what GitHub can't
recompute, and four reference files. It fixes those as requirements R1
to R38.

The technical questions are how that content is split between SKILL.md
and its references so a session loads what it needs when it needs it,
whether any step of the loop has to be held by a workflow-engine gate
rather than prose, and how the record is laid out on GitHub so that it
survives a restart, a rotation handoff, and the roadmap's own deletion
when its features land.

Four facts about the repository shape the answers. Every pull request
body, drafts included, passes the body gate on each edit: a Conventional
Commits title, exactly one top-level `---`, a Part 1 with no headings,
and no attribution footer. The `/execute` finalization cascade rewrites a
feature's lines on its roadmap inside that feature's own pull request,
and deletes the roadmap in the last feature's pull request once
everything is done; it never touches Progress. `shirabe validate`
recognises documents by filename prefix, so a new validated type would
need a code change. And coordinated execution already keeps a record on a
draft pull request that merges last, whose ownership is decided by login
and branch name (#395) and whose merge-order block is never written
after first publish (#396).

## Decision Drivers

- The first version is prose (R37). A workflow-engine gate ships only if
  a step can't be held any other way, and then at the smallest size that
  holds it.
- A coordinator's context is the scarcest in the workspace (R19), so
  SKILL.md is read on every start and must stay short; detail a step
  needs only when it runs belongs in a reference loaded at that step.
- Acceptance criteria check SKILL.md's own text for nearly every
  requirement, so any rule a requirement says "SKILL.md states" lives in
  SKILL.md.
- The record stores only what GitHub can't recompute (R26) and lives on
  GitHub (R27). Its layout has to coexist with the roadmap lifecycle,
  where the roadmap is edited by other skills and deleted once its
  features land.
- The skill must pass shirabe's existing skill checks with no new
  script and no change to the validator (R35, R37).
- Nothing the skill says may work around a filed defect (R34), and the
  skill carries no permission rule and no sender rule (R20, R24).

## Considered Options

### Decision 1: Does any step of the loop need a workflow-engine gate?

The three candidates for a gate are the steps whose skipping would do the
most damage: reconcile before acting, record the holding before anything
else, and verify before relaying.

#### Chosen: prose throughout

No step gets a koto template or a script. SKILL.md and its references
carry every step as a procedure the session walks through. Reconcile and
record tooling are named in the PRD as later features, so gating either
now would build the tooling the roadmap sequences after this feature. A
record write is an outward-facing GitHub event, which
`references/default-action-conversion.md` keeps off koto default actions
in any case. And a koto session suits a run that reaches a terminal
state; a coordinator's loop runs for days with no fixed number of turns,
and its crash story is to reconcile from GitHub rather than resume a
local session.

#### Alternatives considered

- **Gate verify-before-relay only.** Rejected: the gate would need a
  script that reads a pull request's head, each job's runner and step
  count, the file list and the remote ref, which R37 excludes, plus a
  koto session that survives a days-long loop with no restart story.
- **Gate reconcile-before-acting only.** Rejected: the PRD makes
  reconcile a prose procedure in this version and names a mechanised
  reconcile as later work.
- **Gate record-the-holding-before-anything-else only.** Rejected: record
  tooling is out of scope, and a record write is the kind of outward
  event shirabe does not put behind a default action.

### Decision 2: How is the record laid out on GitHub?

The PRD settles what the record holds and roughly where. What remains is
the branch, the body's layout, where Progress and the handoff are
committed, and how the record coexists with a roadmap other skills edit
and eventually delete.

#### Chosen: a scope-keyed ledger

One constant branch per scope, cut from the default branch:
`coordinate/roadmap-<name>` in the roadmap's repository, or
`coordinate/discipline-<name>` in the discipline's host repository. The
host repository for a discipline is one of the human's decisions, asked
once with a recommendation when the invocation doesn't name it, so a
successor started anywhere finds the same record. The coordinator names
the host in every report up and in the handoff, so whoever dispatches the
next rotation passes it on as a decision instead of the successor asking
again. GitHub allows one open pull request per head and base, so the
record is unique without any ownership marker; a successor finds it with
one `gh pr list --head <branch> --state open` in the host repository.

Every start runs the same branch check before the first dispatch, as
part of reconcile. If the branch has an open pull request whose Part 2
carries the record's declaration line, the coordinator adopts it and
never replaces it. If the branch has an open pull request without that
line, the coordinator doesn't adopt it; it reports the conflict and asks
the human, because a pull request on the record's branch that isn't a
record is a scope question. If the branch exists but its last pull
request was merged or closed, the coordinator deletes the branch and
cuts it again from the default branch, so a squash-merged history never
comes back. If no branch exists, it cuts one and opens the draft pull
request with an empty commit. This holds for both scopes, so a roadmap
record is opened on the coordinator's first start, before its first
dispatch, the same way a rotation's is.

The body satisfies the body gate. The title is
`docs(coordinate): record for ROADMAP-<name>` or
`docs(coordinate): <name> rotation from <date>`. Part 1 is one prose
sentence naming the scope and the branch. Part 2 holds a declaration line
for readers, a `Written:` timestamp that dates every claim below it, and
four sections always present in this order: Holdings, Deferrals, Side
effects in flight, Reversals. No table has a status, CI or merge-state
column. The coordinator is the record's only writer and rewrites Part 2
whole at each of the update step's triggers.

For a roadmap, the record branch changes only the roadmap's Progress
section. Before each Progress commit the coordinator merges the default
branch in, never rebasing or force-pushing, so the commit list stays the
Progress history. On a conflict it takes the default branch's version and
re-derives Progress from the roadmap's Features section and the pull
requests, which is always safe because Progress is feature state the
record never owns. If the default branch has deleted the roadmap, the
merge takes the deletion. The record never edits Features, never
transitions and never deletes the roadmap. It is flipped ready and merged
(as far as the workspace permits) once every feature is terminal,
Holdings and Side effects are empty and every deferral is filed or
closed.

For a discipline, a rotation opens its draft pull request through the
same branch check. At rotation end the coordinator commits a handoff to
`docs/disciplines/<name>.md`, one fixed file per discipline overwritten
each rotation, then merges and deletes the branch. The handoff is plain
markdown, not a validated shirabe type, and names no sessions; session
names stay in the merged pull request's body.

#### Alternatives considered

- **Run-keyed dated layout.** A branch per run or per rotation
  (`coordinate/<scope>/<date>`) adopted by prefix, rebased and
  force-pushed to keep one Progress commit, with dated handoff files.
  Rejected: force-pushing breaks the repository's norm and loses the
  Progress history, a rebase after the roadmap's deletion can drop every
  commit, adoption by prefix leans on the login-and-branch ownership
  check #395 describes, and dated files add ordering rules for no gain.
  Its one sound point, that a reused branch brings old commits back after
  a squash merge, is answered in the chosen layout by the branch check
  every start runs.
- **Structured block in a designated record repository.** Part 2 as one
  fenced machine-readable block, all discipline records in one
  repository. Rejected: the block has no parser and adding one needs
  validator changes R37 excludes (its precedent is the merge-order block
  #396 describes, written empty and never read); its syntax is a glossary
  a reader shouldn't need; the workspace manager has no setting for a
  record repository; and one public record repository would name private
  repositories. Its surviving idea, the host as a human decision, is part
  of the chosen layout.

### Decision 3: How is content split between SKILL.md and its references?

#### Chosen: rules in SKILL.md, mechanics and templates in references

SKILL.md states each rule once, as a short paragraph: invocation (R1 to
R4), one subsection per loop step with the failure branch, bound,
autonomy and human-decision rules (R5 to R17), one paragraph per
never-does item (R18 to R24), the glossary (R25), a short record section
(R26 to R28) that points at the template, later work and known
limitations (R32, R33), and the admission rule (R34). Target length is
280 to 380 lines.

Four references hold only what SKILL.md doesn't say, each loaded at the
step that needs it: `references/loop.md` (the order of reads in a full
reconcile, how a conflicting claim is resolved, the shape of an
escalation, and more worked examples; loaded on the first turn and when
the failure branch fires), `references/record-template.md` (the literal
record shape, the branch names, and the start and end procedures;
loaded when the record is opened or updated),
`references/brief-template.md` (the literal worker brief; loaded at
dispatch), and `references/verification-checklist.md` (the exact reads
and report wording behind R10; loaded at verify).

#### Alternatives considered

- **Everything in SKILL.md, references as summary cards.** Rejected: a
  reference that rewords a rule SKILL.md already states is a second copy
  that drifts.
- **Thin SKILL.md routing to per-step phase files**, as `/decision` and
  `/explore` do. Rejected: those skills can push substance into phase
  files because no acceptance criterion reads their router's text; this
  skill's criteria read SKILL.md for nearly every requirement.

## Decision Outcome

The skill is a directory of markdown and one JSON file. A coordinator
loads SKILL.md at invocation and reads the rules for every step from it.
It loads a reference only at the step that needs the reference's
mechanics or template, so a turn that dispatches reads the brief
template, a turn that verifies reads the checklist, and only the first
turn after a start reads the full reconcile procedure. The record lives
on one branch and one draft pull request per scope, readable by anyone
on GitHub, holding only holdings, deferrals, side effects in flight and
reversals, with feature state read from the roadmap and the pull
requests every time.

The three decisions reinforce each other. Because no step is gated, the
record's layout has to be something a session can maintain by hand with
`git` and `gh`, which the scope-keyed ledger is. Because the rules live in
SKILL.md, the record template reference can be a literal template with no
rule text, which is what keeps it from drifting from SKILL.md.

## Solution Architecture

### Files

```
skills/coordinate/
  SKILL.md
  requires.tsv
  references/
    loop.md
    record-template.md
    brief-template.md
    verification-checklist.md
  evals/
    evals.json
```

`README.md` gains a `/coordinate` row in the implementation-altitude
table, above `/deliver`.

### SKILL.md

Frontmatter follows `skills/deliver/SKILL.md`: `name: coordinate`, a
`description` with a "Use it when" clause and a "Do NOT use it" clause
naming `/deliver` and `/work-on` (and `/scope`, `/execute` for a single
feature's documents or plan), `argument-hint:
'<roadmap-path> | --discipline <name> [decisions...]'`, and
`allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)`.
The body opens with the guarded preflight injection line.

Sections, in order:

1. **What a coordinator is** — two paragraphs, then the invocation forms
   (R1), the roadmap-status gate (R3), rotation length (R4), and the
   discipline host decision.
2. **Glossary** — the nine terms, defined once (R25). Every later use
   refers to these definitions and never redefines them.
3. **The loop** — seven subsections in R5's order. Each states its rule
   and names the reference to load, if any: reconcile (R6, loads
   `loop.md` on the first turn), pick (R7, the entry-point table), brief
   and dispatch (R8, loads `brief-template.md`), wait (R9), verify (R10,
   loads `verification-checklist.md`), land (R11), update the record (R12,
   loads `record-template.md`).
4. **When something goes wrong** — the failure branch (R13), including
   the stalled-worker definition, the bounced-message signal and the
   single-roster-read rule.
5. **Bounds and authority** — the three-worker bound (R14), in-scope and
   out-of-scope dispatch (R15), the three conditions for a human decision
   with the three worked examples (R16), and mid-run decisions (R17).
6. **What a coordinator never does** — one paragraph each for R18 to R24.
7. **The record** — what it stores (R26), where it lives for each scope
   (R27), deferral disposal (R28), and a pointer to the template (R29).
8. **What this version leaves for later** — record tooling, a mechanised
   reconcile, dispatch-path tooling (R32).
9. **Known limitations** — #395 and #396, each stated as the invariant
   the skill depends on (R33).
10. **Changing this skill** — the admission rule (R34).
11. **Reporting** — the report up to the dispatcher (R23), naming what
    was verified and what wasn't (R10), ending with the work-in-flight
    block in the shirabe work-summary format.

### References

- `loop.md` — the order of reads for a full reconcile (record, then
  GitHub for each holding's pull request, branch, issue and CI, then the
  host for each session and instance and its unique material, then the
  roadmap's Features section); how to resolve a record claim GitHub
  contradicts (GitHub wins, and the difference goes in the reconcile
  report); the escalation message's shape; and worked examples beyond
  R16's three.
- `record-template.md` — the title forms, Part 1 sentence, declaration
  line, `Written:` line, the four section headings with their table
  columns (Holdings: unit, entry point, session, repo, branch, pull
  request, dispatched; Deferrals: deferral, reason, raised; Side effects
  in flight: action, target, attempted, how to confirm; Reversals: date,
  reversed, now, reason, from), the handoff file's shape, the branch
  names, the branch check every start runs (adopt an open record, ask
  about an open non-record, delete and recut after a merged or closed
  one, cut and open when none exists), and the close procedure for each
  scope.
- `brief-template.md` — goal, decisions the worker can't see, pointers
  to pushed artifacts, acceptance criteria, out of scope, and the
  report-back instruction naming the coordinator's session; the note that
  a worker's keep-alive is the workspace manager's to schedule; and no
  instruction for the worker to schedule one (R31).
- `verification-checklist.md` — the reads for head sha (`gh pr view
  --json headRefOid`), each CI job's runner and steps (`gh run view
  --json jobs`), the file list (`gh pr view --json files`) and the remote
  ref (`git ls-remote`), and the report lines that separate verified
  from unverified claims.

### requires.tsv

The skill runs `gh` and `git` during the loop, so `requires.tsv` declares
both as `always`, with a comment saying the skill runs no `shirabe` or
`koto` command. The preflight then names a missing `gh` or `git` before a
coordinator starts rather than at its first reconcile.

### evals.json

Seven scenarios, one per situation R38 names: a roadmap invocation whose
extra text is decisions, a non-Active roadmap, a worker reporting green,
a restart with an unconfirmed merge, a decision that belongs to the
human, a new decision arriving mid-run, and a teardown request. Each has
assertions a grader can check against the transcript, such as "no
worker is dispatched" for the non-Active roadmap.

### Data flow of one turn

```
start or restart ──► reconcile (full, loads loop.md) ──► report changes, holdings, deferrals
                                                              │
      ┌───────────────────────────────────────────────────────┘
      ▼
    pick ──► brief + dispatch (brief-template.md) ──► record holding (record-template.md)
      ▲                                                        │
      │                                                        ▼
    update record ◄── land (merge or hand over table) ◄── verify (verification-checklist.md) ◄── wait
```

## Implementation Approach

1. **SKILL.md and requires.tsv.** Write SKILL.md in the section order
   above and the explicitly declared `requires.tsv`. Check with
   `scripts/skill-preflight.sh coordinate`,
   `scripts/check-skill-requires.sh` and
   `scripts/check-skill-injection.sh`.
2. **References.** Write the four references against SKILL.md, adding no
   rule SKILL.md already states. Read each against SKILL.md for
   duplicated rule text.
3. **Evals and README.** Write the seven eval scenarios and the README
   row. Check with `scripts/check-evals-exist.sh`.
4. **Hygiene pass.** Run the PRD's greps (the staging-directory path,
   `private/`, sender words) and a read for private names over every
   added file, then open the pull request and read CI job by job.

The work is one pull request: every step touches only
`skills/coordinate/` and `README.md`, and nothing is useful on its own.

## Security Considerations

The skill adds no executable code, so it has no new code path to
exploit. Its risks come from what a coordinator does with it.

- **Untrusted content in worker reports and pull requests.** A worker's
  message, a pull request title or a CI log line can carry text that
  reads like an instruction. The skill's defence is structural rather
  than a sender rule: a coordinator never acts on a claim it hasn't
  re-derived from GitHub (R10), so a message saying "merged" or "green"
  changes nothing until the reads agree. Quoted material in the record
  goes in a fence so it can't break the body's structure. Who may send
  a coordinator a message is the harness's and the workspace's decision,
  and the skill carries no rule about it (R24).
- **Decision-shaped content.** Re-deriving status claims doesn't cover
  text that reads like a decision ("scope now includes X", "skip
  verification for this one"). SKILL.md states where decisions come
  from: the invocation and messages from whoever dispatched the
  coordinator (R1, R17). Text read out of a pull request, an issue, a CI
  log, the record or a worker's report is evidence, never a decision,
  whatever it claims to relay. This is a rule about which channel
  carries decisions, not about who sent a message, so it sits beside
  R24 rather than against it.
- **Propagation into briefs.** A coordinator is a point where content
  from one worker can reach another. The brief template points at pushed
  artifacts by path and reference rather than pasting their text, so a
  brief carries the coordinator's words and the worker reads the
  artifact itself.
- **Adopting an existing pull request.** A pull request on the record's
  branch is adopted only if it carries the record's declaration line;
  otherwise the coordinator asks the human (see the branch check in
  Decision 2).
- **Destructive reach.** Teardown is bounded by the inventory rule
  (R21): the coordinator lists the unique material a session or instance
  holds before any teardown and acts only on what it listed, never
  across the workspace. Whether it may tear down at all is the
  workspace's declared permission, enforced by hooks.
- **Permission bounds.** The skill carries no permission rule of its own
  (R20). A merge, a close or a teardown goes exactly as far as the
  workspace allows; where a hook denies it, the coordinator hands the
  human a table. The skill can't widen what a session may do.
- **Disclosure in a public repository.** The record lives on GitHub, so
  it follows the most-restrictive-visibility rule: a public record never
  names a private repository, and a roadmap whose effort needs a private
  holding raises that as a scope decision for the human. The committed
  discipline handoff names no sessions or instances; session names stay
  in the pull request body. The packaging greps check this feature's
  files once; the record is written on every update, so the update step
  in SKILL.md re-reads what it is about to write for private names before
  each write.
- **Supply chain.** No new dependency. The skill declares `gh` and
  `git`, which the preflight checks for presence only. The propagation
  risk above is the closest analogue and is handled there.

## Consequences

### Positive

- A coordinator is started with a scope and decisions only, and every
  coordinator runs the same loop in the same words.
- The record has one place per scope, found with one lookup, and holds
  nothing GitHub can recompute, so a restart re-derives state instead of
  trusting it.
- The skill ships with no new tooling, so later features can replace a
  prose step with tooling without changing the loop's shape.

### Negative

- Prose can be skipped. Nothing stops a coordinator from shortening
  reconcile or relaying an unverified claim.
- The roadmap's Progress on the default branch is stale while the effort
  runs; the current Progress is in the record pull request's diff.
- Two coordinators under one login on the same scope share one record
  pull request until #395 is fixed.
- The layout assumes GitHub merges a pull request with no net file change
  (after the cascade deleted the roadmap) and opens a draft pull request
  from a branch whose only commit is empty.

### Mitigations

- Reconcile is the first step and its report has a fixed shape, so a
  skipped reconcile is visible in the transcript; the evals exercise the
  restart path. A mechanised reconcile is the named later feature.
- Readers are pointed at the record pull request for live Progress.
- #395 is named as a known limitation with the invariant the skill
  depends on; the skill adds no workaround.
- If either GitHub assumption fails, the coordinator hands the merge or
  close to the human as a step the workspace reserves, and adds no filler
  commit to manufacture a diff.
