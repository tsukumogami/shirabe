# Usability Review Round 2: Decision Framework Design

Review of DESIGN-decision-framework.md after round 1 feedback incorporation.
Focus on new content and remaining problems for daily users.

## What round 1 fixed (not re-raised)

- D9 now has review priority (high/low) for ~20/80 visible split -- review noise addressed
- Progress protocol added to Decision Outcome for --auto feedback
- D14 consolidated to one file per invocation -- artifact proliferation reduced

## Analysis of new/changed content

### D12: Tier annotations in phase files

Phase files now carry `<!-- decision-tier: N -->` HTML comment annotations at
known decision points. Two concerns:

**Invisible by design -- so who benefits?** HTML comments don't render in
markdown viewers. A user reading a phase file in GitHub, an editor preview, or
a rendered doc page never sees these annotations. They exist solely for the
agent. That's fine for agent consumption, but the design doesn't say this
explicitly. A maintainer editing a phase file sees `<!-- decision-tier: 2 -->`
and has no context for what it means, why it's there, or what happens if they
delete it. There's no documentation trail from the annotation back to D12.

**Annotation drift.** 39 annotations spread across ~20 phase files. When a
phase file is rewritten or a decision point moves, the annotation must move
with it. Nothing enforces this. The design creates a maintenance surface it
doesn't acknowledge.

**Verdict:** Net positive for agents (eliminates runtime classification for
known points). Neutral-to-confusing for human maintainers. Needs a one-line
comment explaining what the annotation is, or a convention doc that phase file
editors can reference.

### D13: Auto-splitting design docs at 8-9 decisions

The scaling table says: at 8-9 decisions, "present a concrete split proposal,
require confirmation (--auto executes the split)."

**The user asked for one design doc.** In --auto mode, the agent silently
splits their request into two design docs. The user returns to find two files
they didn't ask for, each covering a subset of the problem. This violates the
principle of least surprise. The user's mental model is "I asked for a design
for X" not "I asked for two designs that together cover X."

**Split quality is unknowable in advance.** The split happens in Phase 1
before deep research. The agent picks a split boundary based on surface-level
analysis. If the boundary turns out wrong (decisions that looked independent
are actually coupled), both design docs produce flawed cross-validation.
There's no mechanism to re-merge.

**Interactive mode gets it right.** In interactive mode, the user sees the
split proposal and can reject it. The --auto behavior should match: when the
agent would ask for confirmation in interactive mode, --auto should treat this
as a high-priority assumption ("I split this into two docs because...") and
proceed with a single doc, not execute the split. The user reviews the
assumption and can re-run with an explicit split if they agree.

**Verdict:** Auto-splitting is the wrong default. In --auto, the 8-9 band
should proceed as a single doc with a high-priority assumption noting the
complexity concern. Only the 10+ hard ceiling should force a structural change.

### D14: Consolidated decisions.md format

One file instead of two -- clear improvement. The format is an index table at
the top plus detailed assumption entries below.

**Scanability for a 10-decision design.** The index table has 10 rows. Each
row has: ID, tier, status, location. That's scannable -- tables are good at
this. Below the table, only assumed decisions get detailed entries. With a
~50/50 confirmed/assumed split (D9), that's ~5 detailed entries. Each entry
has confidence, evidence summary, and "if wrong" restart path -- maybe 8-12
lines each. Total: ~100-110 lines for the full file (10-line table + 5x15-line
entries + headers).

**That's reviewable.** A 100-line file with a scannable table and 5 detailed
entries is within normal review capacity. The high/low priority from D9 further
reduces the visible surface since only high-priority assumptions surface in
the terminal summary.

**One gap:** the index table includes a "location" column pointing to where
the decision block lives in the source artifact. But the design doesn't
specify what "location" looks like. A file path? A file path + heading? A
file path + line number? Line numbers drift. Headings are more stable but
require the decision block to be near a heading.

**Verdict:** Good format. Scannable at expected scale. Needs location format
specified.

### Three-signal checklist for emergent decisions

During architecture writing, the agent hits a fork and evaluates:
1. Reversibility (irreversible -> Tier 4)
2. Heuristic confidence (decisive -> Tier 2, close -> Tier 3)
3. Phase primacy (primary question of the phase -> minimum Tier 3)

**Latency impact on user experience: none.** This checklist runs in the
agent's reasoning, not as a visible step. The agent already evaluates
decisions before acting -- this just structures the evaluation. No extra tool
calls, no extra files read, no user-visible delay. The three signals are
quick to evaluate from context already loaded.

**The real question is reliability, not speed.** Will agents consistently
apply three ordered signals? LLMs tend to latch onto the first applicable
signal and skip the rest. Reversibility is easy to evaluate. Heuristic
confidence requires the agent to have already run a heuristic (which it may
not have for an emergent decision). Phase primacy requires knowing what the
phase "exists to answer" -- clear for well-scoped phases, ambiguous for
broad ones like Architecture.

**Verdict:** Invisible to users, which is the right design. Reliability of
agent application is an implementation concern, not a usability concern. The
override order (reversibility first) is well-chosen since it catches the
highest-stakes cases first.

### Overall complexity

14 decisions, 8 components, 4 implementation phases. The original issue was
"add a decision skill."

**Is this too much?** The 14 decisions cover three interrelated systems
(decision skill, lightweight protocol, non-interactive mode). The design
argues these are "tightly coupled" -- and the ask inventory supports this.
You can't build the decision skill without deciding how lightweight decisions
work (they share the decision block format). You can't build non-interactive
mode without both decision layers (--auto needs the assumption-tracking from
both).

**But a reader doesn't know that going in.** The design doc is ~815 lines.
A new contributor reading this to understand how decisions work in shirabe
faces a wall. The Decision Outcome section (lines 524-547) is the executive
summary, but it's buried after 14 decisions. The frontmatter summary helps,
but it's dense.

**The design doc itself would fail its own D13 test.** With 14 decisions, it
exceeds the 10+ ceiling from D13 that "requires splitting into multiple
design docs." This is ironic but also signals a real problem: if the framework
says 10+ decisions in a design doc is unreadable, and the framework's own
design doc has 14 decisions, the framework is self-contradicting. The counter-
argument is that D13 applies to the design skill's output (Considered Options
sections), not to this meta-design. But the readability concern is format-
independent.

---

## Top 3 remaining concerns for daily users

### 1. Auto-splitting design docs violates user expectations (D13)

When a user runs `/design some-feature --auto` and the agent identifies 8-9
decisions, --auto mode silently splits the request into two design docs. The
user didn't ask for two docs. They return to find their work split along a
boundary chosen by surface-level analysis before deep research. There's no
mechanism to re-merge if the split was wrong.

**Recommendation:** In --auto, the 8-9 band should proceed as a single doc
with a high-priority assumption noting complexity. Only the 10+ hard ceiling
should force structural change. Reserve auto-splitting for when the user
explicitly confirms (interactive mode) or explicitly requests it.

### 2. Phase file annotations lack maintainer context (D12)

39 `<!-- decision-tier: N -->` annotations are spread across ~20 phase files
with no in-file explanation of what they are or why they matter. A maintainer
editing a phase file sees an opaque HTML comment. If they move or delete it,
the tier classification silently degrades to the fallback checklist. Nothing
warns them.

**Recommendation:** Add a brief convention note to the phase file template
or a one-liner above each annotation (`<!-- Agent instruction: tier
classification for decision framework. See references/decision-protocol.md
-->`). Alternatively, document the annotation convention in the shared
reference file and trust that maintainers who edit phase files will read it.

### 3. The design doc's own size contradicts its scaling rule (D13 vs reality)

The design doc has 14 decisions and ~815 lines. Its own D13 says 10+
decisions in a design doc is unreadable and must be split. This creates a
credibility problem: either the rule is wrong (10 is too low) or the design
doc needs splitting. Neither answer is great for a user who encounters the
rule and then reads the framework's own design.

**Recommendation:** Acknowledge the distinction between a "decisions about
the system" design doc (where each decision is a Considered Options section
with full alternatives) and this meta-design (where decisions are lighter-
weight records of architectural choices). D13's ceiling applies to the former.
Add a sentence to D13 clarifying that the count applies to design skill
output format, not to design docs generally.

---

## Items verified as resolved (from round 1)

- Review fatigue: D9's high/low priority with ~20/80 split addresses this
  well. Terminal summary shows only high-priority assumptions.
- No --auto feedback: progress protocol in Decision Outcome covers this.
  One-line status per phase transition is lightweight and sufficient.
- Artifact proliferation: D14's single consolidated file is a clear
  improvement over two files per invocation.
- D14 format scanability: at expected scale (10 decisions, ~5 detailed
  assumptions), the file stays under ~110 lines. Reviewable.
- Three-signal checklist latency: invisible to users, runs in agent
  reasoning. No UX impact.
