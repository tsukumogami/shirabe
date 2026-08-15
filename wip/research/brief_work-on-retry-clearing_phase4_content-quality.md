# Content-Quality Review: BRIEF-work-on-retry-clearing.md

Reviewer: content-quality juror, Phase 4 of `/brief`.
Rubric: `skills/brief/references/brief-format.md` ("Quality Guidance" and
"Per-section content rules"), plus `skills/writing-style/rules.yaml` via the
`shirabe:writing-style` skill.

## Verdict: PASS

No rubric item is genuinely violated. The brief states a real problem without
smuggling a solution, the outcome is outcome-shaped and names its users, the
four journeys are legitimately distinct entry points (not one journey retold),
and the Scope Boundary carries real, specific OUT exclusions. Writing-style
scan found zero banned-word hits and zero em-dash-density issues (the doc uses
`--` throughout, not the `—` character the frequency rule matches on).

## Section-by-section

### Problem Statement -- PASS

States a problem, not a solution. Nowhere does the section propose the fix
(no "add a content-hash gate type," no "implement `koto context remove`").
It diagnoses the current broken mechanism in detail: the presence-only gate,
the nonexistent `koto context remove` subcommand, the backwards causality in
`scrutiny`'s retry prose, and the compounding effect across `review` and
`qa_validation`. That's diagnostic, not prescriptive -- it stays on the right
side of the "smuggled solution" test.

Stands alone reasonably well for a reader of this workflow-orchestration
repo: it explains the phase sequence, the artifact names, and the gate
semantics inline rather than assuming the reader has read
`skills/work-on/references/phases/phase-4a-scrutiny.md` first. It's dense and
technical, but the density is inherent to the bug (a workflow-engine defect),
not a symptom of failing to stand alone.

One factual note, not a rubric violation: I spot-checked the claim that
`scrutiny`'s retry loop invokes `koto context remove` against
`skills/work-on/references/phases/phase-4a-scrutiny.md:45`, which does read
`koto context remove <WF> scrutiny_results.json`. The technical claim holds.

### User Outcome -- PASS

Outcome-shaped: describes what changes for the agent ("a `passed` submission
carried by last round's artifact is refused... rather than accepted"), the
operator ("the run says so in a sentence an operator can act on... on a
stream that survives the `2>/dev/null`"), and the maintainer ("a maintainer
reading the retry loop can predict the workflow's behaviour from it") --
never lists what gets built. Names concrete users in all three cases. Matches
the frontmatter `outcome` field's content (fresh verdict, gate holds until a
new artifact exists, failure surfaces on a stream operators don't filter
away, phases behave alike) -- no divergence that would signal staleness.

### User Journeys -- PASS

Four journeys, each with a `###` name heading, a concrete user, a trigger,
and an outcome shape:

1. "The scrutiny panel sends the work back" -- single-hop retry re-entering
   `scrutiny` only.
2. "A blocking finding lands two phases downstream" -- a retry raised at
   `review` that cascades back through `scrutiny` too. The journey's own text
   argues its distinctness ("the return path crosses a phase that already
   passed"), and this is the journey that motivates the brief's three-phase
   scope decision -- it is not journey 1 with a different phase name pasted
   in; it tests a materially different mechanic (multi-gate cascade).
3. "The clearing step cannot do its job" -- the failure-mode path: the
   clearing mechanism itself breaks, and the journey checks the workflow
   doesn't present that failure as success.
4. "A maintainer edits the retry directive a year later" -- not a runtime
   execution at all; a maintenance-time edit with a different user (a
   maintainer, not the orchestrating agent), a different trigger (a code
   edit), and a different outcome (a pre-merge test failure catching drift).

These are four distinct entry points -- happy-path single-hop, happy-path
cascade, failure-mode, and maintenance-time regression protection -- not one
journey told four ways.

### Scope Boundary -- PASS

IN list is concrete: names the three phases, the three phase-prose files, the
state-machine template, the clearing-step failure mode, the koto-session test,
and the evals. OUT list carries real exclusions, each one something a
downstream PRD author could plausibly have assumed was in:

- "Which mechanism forces the fresh verdict" -- correctly deferred to DESIGN,
  with a concrete reason (one option touches a second repo).
- "`/execute`'s settled-branch record" -- prevents redoing already-merged
  work; a reader unfamiliar with that precedent might otherwise assume it's
  in scope.
- "The rest of `/work-on`" -- borderline generic phrasing, but a reader
  scoping "retry clearing" could plausibly wonder whether adjacent phases or
  directives are touched; the one-sentence follow-up narrows it enough to
  count as real rather than filler.
- "Making `context_assignments:` work" -- a genuine, specific defect
  discovered in passing, correctly walled off with a reason (don't build the
  fix on a broken primitive).
- "A general freshness primitive for koto gates" -- guards against
  over-engineering; contrasts the narrow fix against a tempting general one.

None of these read as "not solving world peace" filler.

### Open Questions -- not present, appropriately

The one open framing question ("which mechanism enforces the contract") is
handled as a Scope Boundary OUT item rather than an Open Question, which is
consistent with the rubric's own example of an OUT item ("a general mechanism
the brief-specific one only gestures at"). Nothing here reads as an
unresolved blocker that should have stopped the brief; the exclusion is
final, not deferred-with-uncertainty.

### Content boundaries -- PASS, with one advisory note

No PRD-level acceptance criteria, no full DESIGN architecture, no PLAN-level
issue breakdown, no feature sequencing. Two Scope Boundary IN items lean
closer to DESIGN/PRD altitude than the rest of the document:

- "the gate shape and the transition conditions that reference it" (naming
  that the state machine's gate needs to change, without specifying the
  mechanism)
- "runs the text the phase files ship rather than a copy of it" (a specific
  testing methodology constraint)

Both stay on the "what must be true" side rather than prescribing "how,"
and the Status section explicitly disclaims picking a mechanism, so I'm not
calling these a boundary violation -- flagging as advisory since a downstream
DESIGN author should notice these are closer to the line than the rest of
the Scope Boundary.

## Writing-style scan

- Zero hits for any banned word in `rules.yaml` (`tier`, `robust`,
  `leverage`, `underscore`, `journey` used only as shirabe's declared term of
  art, etc.).
- Zero `—` (em-dash) characters; the document uses `--` throughout, which the
  frequency rule doesn't match on.
- No structural AI tells found ("serves as," "not just X, it's Y,"
  "boasts," "it's important to note," empty conclusions).
- Sentence length varies naturally (e.g., the one-line summary punch at the
  end of the Problem Statement's fifth paragraph next to the longer
  multi-clause sentences around it).

## Advisory findings (non-blocking)

1. **Frontmatter `problem` field, line 6:** "The one step that would names a
   koto subcommand that does not exist" has a subject-verb agreement slip
   after the modal ("would names" should be "would name"). Minor, one-word
   fix; the sentence is recoverable from context and the body Problem
   Statement is clean, so this doesn't rise to a rubric violation, but it's
   worth fixing before Accepted since frontmatter is sometimes read in
   isolation by downstream tooling.
2. Two Scope Boundary IN items ("gate shape and the transition conditions,"
   the koto-session test's methodology) sit close to the DESIGN/PRD
   boundary. Not a violation given the surrounding disclaimers, but worth a
   second look by the structural or DESIGN-alignment juror.
