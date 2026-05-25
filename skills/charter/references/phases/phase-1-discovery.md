# Phase 1: Discovery

Phase 1 converts the validated topic slug and the author's intent into
the inputs the chain proposal will use. This phase prelude documents
three foundational behaviors that the rest of Phase 1 builds on:
repository-visibility detection, the manual-fallback non-interference
rule, and the thesis-shift signal prompt. The chain-shape decisions
and the chain-proposal output are appended below this prelude by the
companion outline that owns child-invocation logic.

## Goal

By the end of Phase 1's discovery prelude:

- The repository visibility (`Public` or `Private`) is recorded for
  use by downstream chain-shape gates.
- The discovery conversation runs the discover/converge loop against
  the author's topic without interfering with manual invocation of
  any of `/charter`'s children.
- The thesis-shift signal prompt has been surfaced and the author's
  response classified into one of the three signal categories or
  the default no-signal path.

Phase 1's chain-shape decisions, child-invocation gates, and the
chain-proposal confirmation prompt are NOT in this prelude — they
extend this file below and consume the three behaviors documented
here.

## 1.1 Detect Repository Visibility

`/charter` MUST detect repository visibility before any chain-shape
decision that depends on visibility runs. The detection idiom
matches the shipped `/strategy` skill's Phase 0 visibility check
(per Design Decision 1, the parent-skill pattern ratifies R12
verbatim — every workflow skill uses the same idiom).

Procedure:

1. Read the repo's `CLAUDE.md` (or `CLAUDE.local.md` when present)
   and look for a line matching `## Repo Visibility: (Public|Private)`.
2. If the line is found and the value is `Public` or `Private`,
   record that value as the visibility for the rest of the
   `/charter` run.
3. If the `## Repo Visibility:` header is absent (or its value is
   not in `{Public, Private}`), default to Private and emit the
   warning prose below.

### Default-Private Warning

When the `## Repo Visibility:` header is absent from CLAUDE.md (and
CLAUDE.local.md when present), `/charter` defaults to Private and
emits the following warning. The literal phrasing is the
pattern-level wording shared with `/strategy` and `/explore` — eval
scenarios assert against it byte-for-byte.

> *"No `## Repo Visibility:` header was found in CLAUDE.md.
> Defaulting to Private. Default to Private if unknown — restricting is easier to undo than oversharing.
> To set visibility explicitly, add a line to CLAUDE.md reading
> `## Repo Visibility: Public` or `## Repo Visibility: Private`."*

The warning prose names the missing `## Repo Visibility:` header
explicitly so the author knows what file to edit and what content
to add. The default-Private behavior is conservative: a public repo
that forgets to declare visibility gets the more-restrictive
treatment, and the warning prompts the author to correct CLAUDE.md
before continuing.

Phase 1's downstream chain-shape decisions consume the recorded
visibility as the governance gate for visibility-conditional
children; the specific gating logic is owned by the companion
outline that extends this file with child-invocation logic.

## 1.2 Manual-Fallback Non-Interference

`/charter` SHALL NOT detect, warn against, or otherwise interfere
with manual invocation of any of its children outside `/charter`.
Direct child invocation by an author (e.g., running `/strategy
<topic>` against the same topic slug `/charter` would invoke it
against) is first-class steady-state capability, not a degraded
path and not an error case.

The non-interference rule applies to any child skill `/charter`
might invoke in its chain. Children `/charter` may invoke include
`/strategy`, `/vision`, and `/roadmap`; the complete enumeration
is in the chain-shape section that extends this file below. The
manual-fallback discipline is uniform across the set — `/charter`
treats every child the same way.

The contract framing that makes non-interference safe is documented
in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
(see the R14-widened isolation rule and the Manual-Fallback
Non-Interference section). The short form: `/charter` reads only
the child's *durable externally-visible status surface* (frontmatter
`status:` plus the doc's git blob hash for doc-emitting children);
it never reads child internals. Because the read surface is
identical whether the child ran inside or outside `/charter`, manual
invocation leaves the same fingerprint a chain-run invocation
leaves — the parent's resume ladder treats both identically.

Out-of-chain edits (the author invokes `/strategy <topic>` directly
between two `/charter` resumes, or hand-edits a STRATEGY doc's body)
are detected on the next `/charter` resume via child-snapshot drift
comparison: drift fires when EITHER the recorded frontmatter
`status:` OR the recorded git blob hash differs from live. The
detection mechanism is owned by the resume ladder authored in a
companion outline; this prelude documents only the rule and the
forward reference. When drift fires, the resume ladder offers a
staleness-warning prompt (typically: re-run the downstream child,
accept the downstream as still-valid, or proceed without it); the
parent does NOT act on drift unilaterally and does NOT block the
author from invoking children manually.

## 1.3 Discover / Converge Loop

Phase 1's conversational discovery uses the discover/converge engine
that lives at:

- `skills/explore/references/phases/phase-2-discover.md` — the
  discovery half (open-ended scoping, evidence gathering, frame
  the topic against existing repo artifacts).
- `skills/explore/references/phases/phase-3-converge.md` — the
  convergence half (narrow the candidate framings, pick the
  intent that the chain proposal will be built around).

Per Design Decision 1, the engine stays at its current location;
parent skills that need a discovery phase point cross-skill rather
than copying the engine into their own directory. `/charter`'s
Phase 1 loads both files when running the discovery conversation
and adapts the engine's prose to the charter-specific context
(topic-related child docs to inspect, the thesis-shift signal
question below, the chain-proposal output that extends this file).

The discover/converge loop is the conversational backbone of Phase
1. The thesis-shift signal prompt below runs inside the discovery
half; the chain-shape decisions and chain-proposal output run after
the convergence half.

## 1.4 Thesis-Shift Signal Prompt

During discovery, `/charter` MUST surface the following question to
the author verbatim:

> *"Is the long-term thesis shifting, or is this an operational layer below it?"*

The thesis-shift question is the signal-detection mechanism for
the `/vision` invocation decision the chain-shape gate consumes.
The question is asked once per `/charter` run during Phase 1
discovery; the author's response is then classified by agent
judgment into one of three positive-signal categories or the
default no-signal path.

### Positive-Signal Categories

The author's response is treated as a positive thesis-shift signal
when any of the following hold. Classification is agent judgment
over the response's content — the categories below are anchors,
not keyword lists.

1. **Thesis-change category** — the author explicitly says the
   long-term thesis is changing or has changed. Direct statements
   like "we're pivoting", "the long-term thesis is changing",
   "the long-term thesis has changed", or "the bet we made earlier
   no longer holds at the VISION layer" fall here.
2. **New-frame category** — the author names a new audience, value
   proposition, or org fit that the existing VISION does not cover.
   Statements naming new constituencies, new ways the product
   creates value, or new organizational positioning that the
   shipped VISION does not address fall here.
3. **VISION-rejection category** — the author indicates the
   existing VISION is no longer the right framing for the work
   they want to do. Statements like "the existing VISION is no
   longer relevant" or "we need a different framing than what
   VISION-`<topic>` captures" fall here.

When none of the three categories fits the author's response, the
default is no-signal: the chain proposal proceeds without inviting
`/vision` as a candidate.

Signal detection is agent judgment. The pattern-level requirement
is: the thesis-shift question is SURFACED to the author (verbatim
phrasing above), and any response matching any of the three
categories is treated as positive. The agent does NOT need
keyword-match precision; the agent reads the response as a human
reader would and classifies. When the agent is unsure between
positive and no-signal, the default is no-signal — false positives
trigger unwanted `/vision` invocations and the conservative
direction is to leave the existing VISION in place when the signal
is ambiguous.

The `/vision` invocation decision that consumes this signal is owned
by Phase 2 chain orchestration (the companion outline that extends
this file with child-invocation logic). This prelude does NOT
decide whether `/vision` is invoked; it only surfaces the question
and records the classification for the chain-shape gate to read.

---

<!--
Phase 1 discovery prelude ends here. The chain-proposal confirmation
prompt follows below; per-child invocation logic for the children
the proposal names is documented in
`skills/charter/references/phases/phase-2-chain-orchestration.md`.
The seam is preserved to mark where the prelude ends and the
chain-proposal output begins.
-->

## 1.5 Chain-Proposal Confirmation Prompt

Phase 1 concludes with the **chain-proposal confirmation prompt** —
the user-facing output that names the chain `/charter` derived from
discovery and asks the author to accept, adjust, or bail before any
child fires. The prompt is the canonical surface where the chain
shape becomes a committed plan; nothing downstream runs until the
author selects one of the three options.

### Prompt Shape

The prompt lists the children `/charter` plans to invoke, in order,
skipping those whose invocation gates (documented in
`skills/charter/references/phases/phase-2-chain-orchestration.md`)
do not hold for this run. The children appear in the order they
would be invoked, with each entry annotated by either "run" or
"skip" plus a one-line reason; the entry text is consistent across
runs so authors recognize the shape across re-invocations.

Three children are eligible to appear by name in the chain-
proposal output: `/vision`, `/strategy`, and `/roadmap`. The
prompt lists them in that order, in order to match the chain's
sequenced execution; entries for skipped children include the
reason the gate did not hold (e.g., "skip `/vision` because an
Accepted VISION already exists" or "skip `/roadmap` because the
STRATEGY's Building Blocks section has fewer than three blocks").

### Example Shape

The prompt's surface phrasing follows this template (the example
shows a chain where `/vision` is skipped, `/strategy` runs, and
`/roadmap` is skipped because the STRATEGY shape gate failed):

> *"Based on our conversation, here's the chain I propose: skip
> `/vision` because an Accepted VISION already exists, run
> `/strategy`, skip `/roadmap` because the STRATEGY's Building
> Blocks section has fewer than three blocks. Proceed / Adjust
> chain / Bail?"*

Variations on this template are produced by different gate
outcomes: when `/vision` fires the entry reads "run `/vision`"
without a skip reason; when `/roadmap` fires the entry reads "run
`/roadmap`"; and so on. The three options at the end of the
prompt — Proceed, Adjust, Bail — are stable across all variations.

### The Three Options

The chain-proposal prompt offers exactly three options. The
literal substrings "Proceed", "Adjust", and "Bail" are stable
across runs; agents and eval scenarios assert against them.

- **Proceed** — the author accepts the proposed chain. `/charter`
  advances to Phase 2 and the chain orchestration begins firing
  the children in the proposed order, skipping those marked
  skip.
- **Adjust** — the author wants a different chain shape. The
  prompt routes the author back to Phase 1 discovery for chain-
  shape redirection BEFORE any child fires. The redirected
  discovery may force a previously-skipped child on (e.g., "force
  `/vision` on, even though an Accepted VISION exists"), opt out
  of a child that would otherwise fire, or reframe the topic
  entirely. After the redirection, the chain proposal re-fires
  against the new discovery outputs; the prompt cycle repeats
  until the author Proceeds or Bails.
- **Bail** — the author abandons the chain. Routing is owned by
  the companion outline implementing the exit-path orchestration
  (the R8 tie-break rule between abandonment-forced and clean-
  cancel based on whether any wip/ state exists for the topic).
  The prompt option lives here; the routing behavior lives in
  the exit-path orchestration phase reference.

### Why the Prompt Is Stable

The three-option prompt is the stable contract between Phase 1
and Phase 2. Once the author Proceeds, Phase 2's chain
orchestration runs the children in the proposed order without
re-asking; once the author Bails, the exit-path orchestration
records the terminal state without further prompts. Adjusting
keeps the author in Phase 1 — the chain shape is malleable until
the author accepts it, but the option set itself is fixed across
all runs.

