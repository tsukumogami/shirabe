# Maintainability Review Round 3: Decision Framework Design

Reviewer focus: long-term sustainability of the system as described. Two prior rounds
addressed compiled prompt drift (D8 resolved: agents read SKILL.md directly), cross-cutting
protocol copies (resolved: shared reference file), format coupling ownership (D11 resolved:
single spec with consumer rendering sections), annotation-manifest drift (D12 resolved:
manifest is single source of truth, no phase-file annotations), auto-split mechanics
(D13 resolved: auto mode proceeds without splitting, records assumption), and Phase 1
split (resolved: 1a specs, 1b integration).

This round targets five specific areas the prior rounds did not examine deeply enough.

## 1. Decision Point Manifest Maintenance (references/decision-points.md)

The manifest catalogues 39 decision points with location, category, and pre-assigned tier.
It's the single source of truth per D12's resolution. The design eliminated dual-write by
removing phase-file annotations. Good. But the manifest still has a maintenance problem:
**it references phase files by path, and those paths change.**

### What triggers a manifest update

The manifest must update when any of these occur:

1. A phase file is renamed (e.g., design's `phase-3-deep-investigation.md` becomes
   `phase-4-investigation.md` after restructuring)
2. A phase file is split (e.g., a 400-line phase becomes two files)
3. A decision point moves between phases (restructuring changes where a judgment call lives)
4. A new decision point is added (a new phase introduces a blocking question)
5. A decision point is removed (a blocking question becomes non-blocking through automation)

The design's Phase 3 (design skill restructuring) will trigger cases 1, 3, and possibly 4
immediately upon implementation. The manifest created in Phase 1a will need updating in
Phase 3 -- and the implementation plan doesn't call this out.

### The missing enforcement mechanism

There is no CI check proposed. The manifest is markdown, not machine-validated. An
implementer who renames `phase-3-deep-investigation.md` to `phase-4-investigation.md`
will update the SKILL.md's phase listing but may not think to update a reference file
in a different directory.

**Recommendation:** Add an explicit note in the Phase 3 deliverables: "Update
`references/decision-points.md` to reflect new phase file paths." Better yet, define a
convention that the manifest references decision points by skill + semantic ID (e.g.,
`design.approach-selection`) rather than by file path. Semantic IDs survive renames. If
file paths are needed for agent navigation, they belong in a separate "location" column
that's understood to be volatile.

### Scale concern

39 entries today. The design adds a 6th skill (decision) with its own decision points.
The explore skill gains a new phase (produce-decision). Over 6 months, the manifest
could grow to 50+ entries. A single flat file at that size is manageable but benefits
from grouping by skill. The design doesn't specify the manifest's internal structure
beyond "catalogues all 39 known decision points."

**Recommendation:** Specify that the manifest is organized by skill, with a section
per skill. This makes partial updates (touching only one skill's section) lower-risk
and makes it clear which skill's implementer owns which entries.

## 2. Validator Agent Contract Stability Across Phases

D8 describes a three-level agent hierarchy where validator agents are spawned in Phase 3
and re-messaged via SendMessage in Phases 4 and 5. This is the most complex agent
lifecycle in the system.

### The implicit contract

The decider sends validators instructions at three points:

- **Phase 3 spawn**: "Argue FOR alternative X. Here's the research context."
- **Phase 4 SendMessage**: "Here are your peers' findings. Revise your position."
- **Phase 5 SendMessage**: "Cross-examine peer Y's position."

Each message assumes the validator retains its Phase 3 context (the alternative it
advocates for, the evidence it gathered). The validator's response format must be
parseable by the decider for integration into the synthesis report (Phase 6).

### What happens when Phase 3 instructions change

If someone modifies Phase 3 to change how validators are initially prompted (different
role framing, different evidence format, different output structure), Phases 4 and 5
must be aware of the change because:

- Phase 4's "revise your position" message assumes a specific position format from Phase 3
- Phase 5's "cross-examine" message assumes validators can reference specific claims
  from their Phase 3/4 outputs
- Phase 6's synthesis assumes a consistent report structure across all validators

The phase files are independent files. There's no type system or contract enforcing
that Phase 3's output schema matches Phase 4's input expectations. The design says
"phase files are the single source of truth" but doesn't define the inter-phase data
contract for validator messages.

### Practical risk

This is a low-frequency, high-impact risk. Validator spawning only happens for Tier 4
decisions (the full 7-phase path). The fast path (Tier 3) skips Phases 3-5 entirely.
Most decisions will be Tier 2-3. But when a Tier 4 decision fails because the validator
contract broke silently, diagnosing the issue requires understanding the full three-phase
validator lifecycle -- which spans three files and involves asynchronous message passing.

**Recommendation:** Add a "Validator Contract" section to the decision skill's SKILL.md
(or a dedicated reference file) that defines:

1. The validator's expected input format at each phase (spawn, revise, cross-examine)
2. The validator's expected output format at each phase
3. The fields the decider extracts from validator outputs for synthesis

This gives phase file editors a single place to check compatibility when modifying
Phases 3, 4, or 5. It doesn't prevent drift (nothing short of a type system does),
but it makes the contract visible rather than implicit across three files.

## 3. Format Spec with Consumer Rendering Sections (D11) -- Bottleneck Analysis

D11 co-locates the decision report format with "How to render as Considered Options"
and "How to render as ADR" sections. Today that's two consumers. The design mentions
these two explicitly.

### Growth trajectory

Plausible future consumers within 6-12 months:

- **PR body decision summary**: a condensed rendering for PR descriptions (D2 already
  mentions a PR body section, but that's for assumptions, not the full decision report)
- **Issue body**: when explore crystallizes to a decision record, the issue body needs
  a rendering
- **Terminal summary**: the --auto progress output may want a one-line rendering per decision
- **Changelog entries**: if decisions drive release notes
- **Cross-reference format**: when one design doc references another's decision

Each new consumer adds a rendering section to the format spec file. At 5-6 consumers,
the file becomes a mixed-concern artifact: part canonical format definition, part
rendering adapter catalogue.

### When does it warrant splitting?

The design anticipated this: "Can migrate to [a dedicated format-mapping reference file]
if rendering rules grow complex enough to warrant separation." This is the right escape
valve. The question is whether the trigger is defined.

**Current state:** No defined trigger. The decision to split is itself an unstructured
judgment call -- ironic for a decision framework design.

**Recommendation:** Add a concrete trigger: "If the format spec exceeds 200 lines or
contains more than 4 consumer rendering sections, split rendering rules into
`references/decision-rendering.md`." This makes the migration mechanical rather than
requiring someone to notice the file has become unwieldy and make a judgment call about
whether it's "complex enough."

## 4. Implementation Phase Ordering -- Hidden Dependencies

The stated order is 1a (specs) -> 1b (integration) -> 2 (decision skill) -> 3 (design
restructuring) -> 4 (explore integration).

### Dependency analysis

**1a -> 1b**: Clean. 1b applies specs from 1a to existing skills.

**1b -> 2**: Partially clean, but with a subtle issue. Phase 1b adds `--auto` flag
handling and the lightweight decision protocol to all 5 existing skills. Phase 2 creates
the decision skill. The decision skill's SKILL.md needs to support `--auto` too. If
Phase 2 is implemented without awareness of 1b's flag-handling pattern, it'll use a
different pattern. The design doesn't say "Phase 2 follows the --auto pattern established
in Phase 1b," though an implementer would likely infer this.

**2 -> 3**: This has a real dependency gap. Phase 3 (design skill restructuring) creates
Phase 2 (DECISION EXECUTION), which invokes the decision skill via Task agents. Phase 3
can't be tested without Phase 2's decision skill existing. But Phase 3 also rewrites
the design skill's phases 1-3, which are the same files that Phase 1b just modified to
add --auto support. Phase 3's rewrite could undo Phase 1b's changes if the implementer
starts from the pre-1b phase files.

**3 -> 4**: Clean. Explore integration is independent of design restructuring.

### The 1b-then-3 rewrite risk

Phase 1b modifies every phase file in the design skill to add decision protocol
references and --auto behavior. Phase 3 rewrites three of those phase files entirely
(phases 1-3 become decomposition, execution, cross-validation) and modifies a fourth
(investigation). The Phase 1b changes to the old phases 1-3 are discarded because
those files are replaced.

This isn't a bug -- the new phase files written in Phase 3 should include --auto
support from the start. But it means Phase 1b's design skill changes are partially
throwaway work. The phases that survive (5-architecture, 6-security, 7-final-review)
keep their 1b modifications; the replaced phases don't.

**Recommendation:** Note in Phase 1b's deliverables that design skill phases 1-3 will
be replaced in Phase 3. Phase 1b should still add --auto support to the current phases
(for consistency and to exercise the pattern), but implementers should know the work is
temporary for those specific files. Alternatively, Phase 1b could skip design phases 1-3
and leave a TODO, knowing Phase 3 will write them from scratch with --auto built in.

### Could phases run in parallel?

Phase 2 (decision skill) and Phase 1b (integration into existing skills) have no
structural dependency -- 1b modifies existing skills, 2 creates a new skill. They could
run in parallel after 1a completes. The design's sequential ordering (1b before 2) isn't
wrong, but parallelizing would reduce the total implementation timeline.

Phase 3 and Phase 4 are also independent (design restructuring vs. explore integration).
They could run in parallel after Phase 2.

**Recommendation:** Add a note that Phases 1b and 2 can run in parallel, and Phases 3
and 4 can run in parallel. The sequential listing is fine as a default, but identifying
the parallelism helps if implementation is split across contributors.

## 5. Most Likely First Failure Mode (3-Month Horizon)

After considering all moving parts, the most likely first production failure is:

### Prediction: Lightweight protocol inconsistency across skills

**The scenario:** Three months in, all 5 skills have been using the lightweight decision
protocol at their 39 decision points for a few weeks. A bug report comes in: the explore
skill's assumption entries in `wip/explore_<topic>_decisions.md` use a different field
order than the design skill's entries. The terminal summary printer, which parses these
files, chokes on explore's format because it was tested against design's output.

**Why this breaks first:**

1. **Surface area.** 39 decision points across 5 skills, each writing decision blocks
   independently. The shared reference (`references/decision-protocol.md`) defines the
   format, but each phase file interprets and applies it. There's no runtime validation
   that the blocks produced match the spec.

2. **Agent variability.** LLMs don't produce identical output when following the same
   instructions in different contexts. A decision block written during explore's
   phase-3-converge (where the agent has a discovery-focused mindset) will be subtly
   different from one written during design's phase-5-architecture (where the agent has
   an implementation-focused mindset). Field ordering, optional field inclusion, and
   phrasing will vary.

3. **No consumer-side validation.** The terminal summary printer and PR body section
   generator consume decision blocks and consolidated files. The design doesn't specify
   whether these consumers validate their input or fail gracefully on malformed entries.
   A strict parser breaks on the first inconsistency. A lenient parser silently drops
   fields, making assumptions invisible in review surfaces -- which defeats the
   framework's purpose.

4. **Late detection.** The inconsistency only surfaces when someone actually reviews
   assumptions in the terminal summary or PR body. In --auto mode, the user may not
   check every run's output carefully, allowing format drift to accumulate across
   multiple invocations before discovery.

**Why not the other candidates:**

- **Manifest staleness** (references/decision-points.md): won't cause a runtime failure.
  Agents that can't find their decision point in the manifest fall through to the
  checklist heuristic. The system degrades to slightly more runtime classification
  overhead, not a crash.

- **Validator contract breakage** (Phases 3-5): Tier 4 decisions are rare. Most users
  will run months of Tier 2-3 decisions before encountering a full 7-phase run. When
  it does break, it'll be dramatic, but the probability is low in the first 3 months.

- **Format spec bottleneck** (D11): won't manifest as a failure. It manifests as
  implementation friction when adding the third or fourth consumer. That's a 6-12 month
  problem, not a 3-month one.

- **Phase ordering issues** (1b work being overwritten by Phase 3): this is a one-time
  implementation cost, not a recurring production failure. Once implemented, it's done.

**Mitigation the design should add:** Define 3-5 example decision blocks in the format
spec (not just the two currently shown) covering different skills, different tiers, and
edge cases (minimal block, maximal block, escalated block). These examples serve as
conformance tests -- an implementer modifying a phase file can check their output against
the examples. Additionally, specify whether the terminal summary printer and PR body
generator should validate input strictly (reject malformed) or leniently (best-effort
rendering with warnings). Strict is better for early detection; lenient is better for
user experience. The design should pick one.

## Summary of Recommendations

| # | Area | Recommendation | Severity |
|---|------|---------------|----------|
| 1 | Manifest maintenance | Use semantic IDs (not file paths) for decision points; organize by skill; note Phase 3 must update manifest | Medium |
| 2 | Validator contract | Add explicit validator I/O contract in SKILL.md or reference file | Medium |
| 3 | Format spec growth | Define concrete split trigger (>200 lines or >4 consumers) | Low |
| 4 | Phase ordering | Note 1b design phases 1-3 are throwaway; identify parallel opportunities (1b\|\|2, 3\|\|4) | Low |
| 5 | First failure mode | Add conformance examples to format spec; specify consumer parser strictness | High |

Severity reflects long-term maintenance impact, not implementation urgency.

The highest-priority addition is #5: without conformance examples and parser strictness
guidance, the lightweight protocol's 39-point surface area will produce format
inconsistencies that undermine the assumption review surfaces -- the framework's primary
user-facing value.
