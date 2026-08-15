# Clarity Review: PRD-work-on-retry-clearing.md

Reviewed against `skills/prd/references/prd-format.md` (Quality Guidance,
Common Pitfalls) and `skills/writing-style/SKILL.md`.

## Verdict: FAIL

Two findings are genuine, build-changing ambiguities. Both are blocking.

## Blocking findings

### 1. R1/R2/Goals/AC foreclose a mechanism the doc says is still open

The Status section and the Decisions section both say the mechanism is
undecided: "The mechanism that satisfies R2 and R3 is left open for the
DESIGN... one live option changes another repository" (Status), and Out of
Scope names the two live options explicitly: "removal via a new koto
subcommand" and "replacement with a value a content gate rejects... the
DESIGN picks one and records why." R2's own sentence about *how* to
invalidate is written correctly, matching this stance: "'Invalidate' means
the artifact stops satisfying the phase's gate, whether by removal or by
replacement... " -- genuinely mechanism-neutral, as instructed.

But four other places in the same document do not hold that line, and they
foreclose the "new koto subcommand" option specifically:

- **R1**: "every `koto context` invocation in an instruction under `skills/`
  names one of `add`, `get`, `exists`, or `list`." This is a closed,
  hardcoded enumeration of koto's *current* four subcommands. It does not say
  "one of the subcommands koto supports" (which would flex if koto gains a
  fifth); it names the four by literal value. If DESIGN chooses the
  "add a subcommand to koto" path -- e.g. implementing a real `remove` -- an
  instruction that then names `remove` violates R1 as written, even though
  `remove` would, at that point, exist.
- **R2** itself: "carries a step that invalidates its own results artifact on
  the `blocking_retry` path, using koto's existing interface." "Existing"
  reads as "the interface koto has today," which rules out the same option.
- **Goals**, bullet 2: "The step that invalidates the previous round's
  artifact runs a command koto has" -- present tense, same effect.
- **Acceptance Criteria**: `grep -rnE "koto context
  (remove|set|delete|rm|unset|clear)" skills/` must return no instructing
  line. This is the most concrete instance: it bans the literal string
  `remove` from ever appearing as an instruction, which is exactly the verb
  the "new subcommand" mechanism would need to name once implemented.

Two competent implementers reading this PRD land in different places. One
reads Out of Scope/Decisions/Status, concludes DESIGN may still choose to add
a real `koto context remove` and wire instructions to call it, and treats R1
and the grep AC as describing *today's* defect (an instruction naming a verb
koto lacks), expected to be updated once the verb exists. The other reads R1,
R2, and the AC literally -- a permanent four-item allowlist and a permanent
ban on the string `remove` -- and concludes the "new subcommand" path is
already ruled out by the Requirements section itself, regardless of what
Decisions says is still open. That is not a stylistic quibble: it decides
whether a coordinated two-repo change (touching koto) is a legitimate design
outcome or a non-starter, which is precisely the question the PRD says it is
deliberately not answering.

**Fix**: Either (a) make R1 and the AC grok koto's state *after* this work
lands -- e.g. "names a subcommand koto has at completion of this work" --
and drop "existing" from R2 and "koto has" from Goals bullet 2 in favor of
neutral phrasing ("a command koto supports"), or (b) if the four-item
allowlist and the ban on `remove` really are meant to be permanent (i.e. the
"new subcommand" option is dead), say so plainly and delete it from Out of
Scope/Decisions instead of presenting it as live. Whichever is true, say it
once and make every other passage agree.

### 2. R2's "on the blocking_retry path" doesn't obviously cover the traversal scenario the Problem Statement builds around

The Problem Statement spends three paragraphs establishing that a retry is
never local to the phase that raised it: "Every `blocking_retry` targets
`implementation`... A retry always re-enters every review phase at or above
the one that raised it, each holding a gate open with its own previous
verdict." User Story 2 asks for exactly this to be fixed: "every review phase
the retry re-enters [should] demand a fresh verdict... so that the phases the
run already passed do not wave it through on last round's record" -- i.e.
when `qa_validation` is the phase that finds the blocking issue, `scrutiny`
and `review` (re-entered on the way back, but not themselves the ones that
raised the retry) must also be forced to produce a fresh verdict, not coast
on the `passed` artifact they wrote last round.

R2 says: "Each of `scrutiny`, `review`, and `qa_validation` carries a step
that invalidates its own results artifact on the `blocking_retry` path."
Known Limitations glosses this the same way: "R2 places the step on the same
path as the `blocking_retry` submission so that skipping it means skipping a
command the agent is already running" -- language that ties the invalidation
step to *that phase's own* blocking_retry submission specifically.

Read that way, when `qa_validation` retries, only `qa_validation`'s own
artifact gets invalidated by its own blocking_retry step. `scrutiny` and
`review` are re-entered from `implementation` and, on this reading, never
execute an invalidation step at all in that traversal -- their prior
`passed`-round artifacts (written before `qa_validation` ever objected) are
never touched. That is the exact defect the Problem Statement calls out for
`review`/`qa_validation` ("document no clearing step at all, so the same
staleness sits there unnamed"), just recurring one level up the traversal for
`scrutiny`/`review` when the retry originates deeper in.

The other defensible reading is that the invalidation step lives at each
phase's *entry*, runs unconditionally whenever the phase is reached via any
loop-back through `implementation` (regardless of which phase's
blocking_retry caused the loop), and is merely described loosely as being
"on the blocking_retry path" because that loop-back is the only way to reach
the step a second time. Nothing in R2, R3, or the Acceptance Criteria
disambiguates between these two readings -- the ACs test only the effect of
an *already-invalidated* artifact on the gate ("with the phase's results
artifact invalidated, submitting the phase's passed outcome does not advance
the workflow"), never which trigger performs the invalidation or whether a
downstream-raised retry invalidates the phases it merely passes back through.

This is load-bearing: under the first reading, an implementation that
satisfies R2's literal text and every AC as written can still leave the
central traversal problem -- the one the Problem Statement's last line calls
out as "where it is most expensive" -- unfixed for `scrutiny` and `review`
whenever `qa_validation` is the phase that objects.

**Fix**: State explicitly whether the invalidation step fires (a) only when
the phase itself submits `blocking_retry`, or (b) at phase entry, every time
the phase is reached via any loop-back, regardless of which phase raised the
retry. Then add an acceptance criterion (or extend an existing one) that
exercises the multi-phase traversal directly: raise `blocking_retry` in
`qa_validation` and assert that `scrutiny`'s and `review`'s prior `passed`
artifacts no longer satisfy their gates on re-entry.

## Advisory findings

- **Terminology drift around the central operation.** The operative term
  settles on "invalidate"/"invalidation" (Goals, R2-R7, Known Limitations,
  Decisions), which is fine and precisely defined in R2. But the Problem
  Statement narrates the same operation as "delete the stale artifact" /
  "deletion" (lines ~51, 61, 64) before Goals switches to "invalidates" (line
  86) and then, two bullets later, back to "the clearing step" (line 95)
  without ever stating the two are the same thing. "Clearing," in particular,
  connotes removal specifically, in mild tension with R2's explicit
  removal-or-replacement neutrality. One Acceptance Criterion also names
  "the retry-clearing contract" (line ~223) where R6/R7/Goals bullet 4 call
  the same thing just "the contract" -- a reader checking that AC has to
  infer it's the same contract rather than something narrower. None of these
  land in a Requirement, so they don't rise to blocking, but a terminology
  pass that picks one name and uses it in the prose sections too would remove
  the doubt.
- **No contractions anywhere in the document** (consistently "does not,"
  "cannot," "is not"). `skills/writing-style/SKILL.md` flags this as a
  formatting tell. Given the document's legal-spec register this reads as a
  deliberate choice rather than an AI tell, and it doesn't affect testability,
  so this is a low-priority style note, not a blocker.
- **R5's "reads its own result back and compares it"** is more prescriptive
  than most requirements in this document (closer to "how" than "what"), but
  it's explicitly defended in Decisions and Trade-offs with a concrete reason
  (`koto context get` on a missing key writes an error to stdout rather than
  failing cleanly, so an emptiness test is insufficient). Since the
  Decisions section owns this as a settled requirements-level call rather
  than something deferred to DESIGN, it's consistent with the rest of the
  document's own rules and not a smuggled mechanism -- flagged only as a
  minor "is this the intended amount of prescription in a PRD" note.

## Sections that hold up well

- **Goals** are outcome-shaped throughout (behavioral refusals, observable
  diagnostics, a workflow-enforced guarantee, doc accuracy) rather than a
  feature list.
- **User Stories** are four distinct personas/scenarios (orchestrating agent
  closing a panel it shouldn't, orchestrating agent whose retry was raised
  two phases down, an operator reading redirected stderr, a maintainer a year
  from now), each with a real who/what/why and none overlapping.
- **Out of Scope** entries are all real, specific exclusions (a named
  mechanism decision, a merged precedent PR, other phases, a discovered
  no-op bug filed separately, a generalized koto primitive, two pre-existing
  template warnings) -- nothing reads as filler.

## Re-review

### Verdict: PASS

Both blocking findings are genuinely resolved. The document still carries two
small residual softnesses, noted below as advisory, but neither reopens the
loophole the original findings were about.

### Finding 1 -- resolved

R1 now reads: "every `koto context` invocation in an instruction under
`skills/` names a subcommand koto actually provides at merge time. Today
that set is `add`, `get`, `exists`, and `list`; if the DESIGN's chosen
mechanism adds one to koto, the requirement is that the named subcommand
exists and works, not that the set is unchanged." That is checkable under
both mechanism answers and explicitly time-anchors the four-verb set to
"today" rather than treating it as permanent. The AC set follows suit: the
first AC ("For every verb `V` appearing in a `koto context V` instruction
under `skills/`, `koto context V --help` exits 0... it passes if the verb
was already there and it passes if the chosen mechanism added it, and it
fails for `remove` today") is explicit that it is mechanism-neutral by
construction, and the second AC ("contains no instruction to run `koto
context remove` unless that subcommand exists") uses the same conditional
form. Both ACs still fail against `main`: `phase-4a-scrutiny.md` instructs
`koto context remove`, which is not in koto's current four-verb set, so
`koto context remove --help` fails today and the second AC's "unless that
subcommand exists" escape clause does not apply yet. R2's "existing
interface" language is gone, replaced with "a koto subcommand that exists
and works at merge time." The Decisions section now documents the fix
explicitly as a self-correction: "An earlier draft failed its own
neutrality test on this point... Both now key on whether the named
subcommand resolves against the koto CI installs." Two implementers reading
this today land in the same place regardless of which mechanism DESIGN
eventually picks.

### Finding 2 -- resolved

R2's body now states the traversal directly: "the run then walks forward
through `scrutiny`, `review`, and `qa_validation` in order. Every one of
those phases is re-entered... including the artifacts of phases that passed
this round and will not themselves submit `blocking_retry`. The retry
invalidates all of them," followed by an explicit rejection of the narrow
reading: "Scoping the invalidation to the raising phase alone would leave
the PRD's own headline scenario unfixed." Two acceptance criteria exercise
this directly rather than leaving it to inference -- "**Traversal.** After a
`blocking_retry` raised in `qa_validation`, neither `scrutiny` nor `review`
advances on `passed` until each has a fresh artifact -- even though neither
raised the retry and both passed that round," and "**Traversal, upward.**
After a `blocking_retry` raised in `scrutiny`, before `review` or
`qa_validation` has ever run, the invalidation step exits 0 rather than
failing on the two artifacts that do not exist yet." An implementation that
only self-invalidates (the exact loophole the original finding described)
now fails the first Traversal AC outright, so the requirement and the ACs
together close the gap the original finding identified. Both Traversal ACs
would fail against `main` today, since neither `scrutiny` nor `review`
carries any invalidation step at all currently.

The "artifact does not exist yet" case, which the check list asked about
specifically, is now handled head-on in R2 itself ("A phase whose artifact
does not exist yet -- `review` and `qa_validation` on a retry raised in
`scrutiny`, before either has run -- is not an error. The requirement is
that no stale artifact survives the retry, not that every key is written")
and is exercised by the "Traversal, upward" AC. This is new ground the
previous draft did not cover and it is handled cleanly -- no new ambiguity
introduced here.

### R6 "same step" claim and the "same path as blocking_retry submission" language -- residual wording tension, advisory only

R6 commits to a specific shape: "the invalidation step itself is not merely
parallel across the three phase files -- it is the same step," and the
gate/transition/prose "differ[] only in the key and outcome names." Read
together with R2's traversal language, the natural mechanism this implies is
per-phase, unconditional invalidation of a phase's own artifact at
(re-)entry -- the only model under which the step is truly identical across
files modulo one key name, and the only model that explains how `scrutiny`
and `review`'s artifacts get invalidated when *`qa_validation`* is the phase
that raises the retry.

Known Limitations still says "R2 places the step on the same path as the
`blocking_retry` submission so that skipping it means skipping a command the
agent is already running," and one AC checks that "the invalidation step
runs on the same path as the `blocking_retry` submission... checked by
extracting the shipped block and confirming the submission and the
invalidation are in it." Taken in isolation, that phrasing reads as
colocated with *this phase's own* retry decision specifically, which is the
narrower model the original finding flagged. It does not reopen the
loophole -- the Traversal ACs independently and unambiguously pin the
cross-phase behavior, so an implementation cannot pass the AC suite by
satisfying only the local co-location check -- but the prose in Known
Limitations and that one AC have not been brought fully into line with R2
and R6's broader framing. Worth a follow-up tightening pass (e.g., "on the
same path as *a* `blocking_retry` traversal" or similar), not a blocker.

### Terminology -- holds

"Invalidate" is used consistently as the operative verb across Goals,
R2-R7, the ACs, and Known Limitations. The new closing sentence of Goals --
"Where the text says *delete* or *remove*, it is quoting the phase file's
current broken instruction, not naming the requirement" -- states the rule
explicitly, and the document holds it: every remaining "delete"/"deletion"
instance sits in the Problem Statement's characterization of
`phase-4a-scrutiny.md`'s current (broken) prose, and every "remove" instance
either quotes the literal `koto context remove` command name or appears in
Out of Scope/Decisions describing "removal via a new koto subcommand" as one
of the two mechanism options R2 explicitly names ("whether by removal or by
replacement with a value the gate rejects"). That usage is correct, not
drift -- R2 itself uses "removal" as one of the two things "invalidate"
might cash out to. One minor stray: Known Limitations' "koto's engine has no
way to write or clear a context key on a transition" uses "clear" generically
about koto's API surface rather than the PRD's operation; it doesn't
introduce a competing name for the requirement, just a loose word choice.
Advisory, not blocking. The "clearing" and "the retry-clearing contract"
instances flagged in the original advisory findings are gone from Goals and
the ACs in this revision.

### One more residual softness (advisory)

Goals bullet 2 ("runs a command koto actually provides") and the frontmatter
`goals` field ("runs through a command koto actually has") do not carry
R1's explicit "at merge time" anchor, unlike R1 itself. In isolation these
read closer to present tense than R1's carefully time-anchored phrasing.
Because Requirements and Acceptance Criteria are what governs build
correctness, and R1/AC1 are unambiguous, this doesn't create the
two-implementer disagreement the original finding described -- but a
tightening pass that echoes "at merge time" in Goals and the frontmatter
would remove the last trace of the ambiguity rather than leaving it to be
resolved by cross-reference to R1.
