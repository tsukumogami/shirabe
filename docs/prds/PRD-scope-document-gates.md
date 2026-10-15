---
schema: prd/v1
status: Draft
problem: |
  /scope credits a hop's document after the validator's schema gate and three
  structural checks (FC01, FC03, FC04). Every other error-level check
  `shirabe validate` runs for a BRIEF, PRD, DESIGN or PLAN is held only by a
  prose step telling the agent to run the validator and stop on violations,
  and the banned-words rule, checked only at notice level, is held by nothing.
  A hop that skips the step carries a broken document forward, and no failure
  carries a rule id anyone can count.
goals: |
  Every /scope hop, and the fold that can rewrite a hop's document, holds
  until the current document passes every error-level validator check for its
  type plus the banned-words check raised to blocking there. Each failure is a
  koto finding with a registered rule id, the rule's reference and the line,
  so `shirabe validate` becomes the lock on document-format rules and their
  failures can be counted per rule from koto's gate events.
upstream: docs/briefs/BRIEF-scope-document-gates.md
---

# PRD: scope document gates

## Status

Draft

## Problem Statement

A /scope run writes up to four documents, one per hop: a BRIEF, a PRD, a
DESIGN and a PLAN. Each hop is credited by `hop-complete.sh`, which asks the
validator four things: does the document carry a supported schema (SCHEMA),
are its required frontmatter fields present (FC01), does its frontmatter
status match its body (FC03), and are its required sections there (FC04).
That narrowness is deliberate, because the script answers "did this hop
land?", and it leaves the rest of the format to a prose step in Phase 2, the
validator pass-through, which tells the agent to run `shirabe validate` on the
new document and stop the chain on a violation. The fold that absorbs one
document into the next rewrites the survivor and re-validates it the same
way, in prose.

Nothing checks that the agent ran either step, or read the result right. The
error-level checks left to the prose include a valid status value (FC02),
upstream links that resolve (R6) and point in a legal direction (R10, R11),
stale prose references (FC20), absorb declarations and orphaned requirement
citations (FC18, FC19), and a PLAN's issue table and outline dependencies
(FC05, FC06, FC17). A document that breaks one of them is credited as landed
and the next hop builds on it; CI finds the breach on the pull request after
the chain is finished.

The banned-words rule from `skills/writing-style/rules.yaml` is worse off.
The validator reports it (FC10) only as a notice, so even a faithful agent is
told nothing it must act on, and the only thing holding the rule is the prose
that states it. That prose can't leave the instructions an agent loads,
because nothing would catch a breach once it did. And because none of these
failures carries a registered rule id, nobody can tell which rules agents
break often.

/work-on and /execute already gate their outputs on the checks shirabe
ships, with findings that carry a rule id from `references/rule-registry.json`
(the output-gates work, `DESIGN-output-gates.md`). /scope is the workflow that
writes the most documents and has the thinnest gate.

## Goals

- An author, or a worker a coordinator dispatched, can't advance a /scope hop
  past a document that fails an error-level validator check for its type, or
  that uses a banned word, and the hold names the rule and the line.
- A maintainer can treat `shirabe validate` as the lock on document-format
  rules at /scope's hops: every rule the gate holds has a registry entry that
  says so.
- Failures at the gate are countable per rule from koto's exported gate
  events, joined on the registered rule id.

## User Stories

- As an author running `/scope` on a feature, I want a PRD whose `upstream:`
  names a BRIEF path that doesn't exist to hold the PRD hop with a finding
  naming the upstream rule, the file and the line, so that I fix the path
  before the DESIGN and PLAN are written on top of it.
- As a worker running `/scope --auto` for a coordinator, I want a DESIGN that
  uses a banned word to hold its hop with a finding naming the banned-words
  rule and the line, so that I rewrite the sentence instead of reading a
  notice I'm free to ignore.
- As an author whose fold just absorbed the BRIEF into the PRD, I want the
  rewritten PRD checked before the run moves on, so that a broken `absorbed:`
  declaration or a dangling re-pointed upstream can't survive the fold.
- As a maintainer weighing whether the banned-words instruction can leave what
  an agent loads during a hop, I want the registry entry for that rule to name
  the scope hops as gate timings, so that I know a gate holds it there.
- As a maintainer reviewing live /scope runs, I want each gate finding to carry
  the registered rule id, so that I can count failures per rule from the
  exported gate events without reading transcripts.

## Requirements

### Functional

- **R1. A document gate at each hop.** `hop_brief`, `hop_prd`, `hop_design`
  and `hop_plan` each carry a command gate that checks the hop's document at
  its canonical path (either DESIGN location for the design hop). The
  `landed` transition requires the gate to pass, in addition to the existing
  completion gate. The `skipped`, `rejected` and `bail` transitions don't
  depend on it.
- **R2. A document gate at the fold.** The `fold` state carries the same
  gate over the survivor: the most downstream of the run's documents present
  on disk after the verdict's stages ran. Every verdict transition requires
  it to pass, so a survivor rewritten by an absorb is checked before the run
  moves on.
- **R3. Every error-level check.** The gate runs `shirabe validate --format
  json` once over the document, at the repository's declared visibility, and
  treats every finding the validator reports at severity `error` as a
  violation. It doesn't select checks with `--check`, so an error-level check
  the validator gains later is held without a change here.
- **R4. The banned-words check raised to blocking.** FC10 findings for a
  banned word, and FC10's truncation finding when the banned-word findings
  overflow its cap, are violations at this gate though the validator reports
  them as notices. FC10's em-dash-density finding, and every other
  notice-level code, stays a notice at the gate.
- **R5. Findings in the work-on shape.** Each violation prints one
  `::koto-finding::` line with `rule_id` set to a registry id, `level`
  `error`, `rule_ref` computed through `scripts/lib/rule-findings.sh`,
  `path` and `line` from the validator's finding, and a `message` that
  starts with the entry's summary, then `: `, the validator's code and its
  message.
- **R6. A registry entry per reportable rule.** Every rule the gate can
  print has an active entry in `references/rule-registry.json` with every
  field the registry requires: the validator code as an alias, `level`
  `gate`, the scope states it applies in as `timing`, the gate script as its
  check, its test as a fixture, and `withhold` `never`. A rule that already
  has an entry (R7, R8, R9 from the output-gates work) keeps its id and gains
  the scope timings. `scripts/check-rule-registry.sh` passes.
- **R7. Three exit statuses.** The gate exits 0 when the document passes,
  1 with at least one finding when it doesn't, and 2, printing no finding,
  when it can't decide: no `shirabe` or `jq`, no parseable envelope, a
  validator tool error, a document the validator skipped as schema-less, or
  an error-level code with no registry entry. No transition names exit 2, so
  the run holds with the gate reported, as `hop-complete.sh`'s exit 2 does.
- **R8. Absent document passes.** When the hop's canonical path holds no
  document (a hop the fold already absorbed, or a document a skipped hop
  never wrote), the gate exits 0 and says so on stderr; whether the hop
  landed stays the completion gate's question.
- **R9. Not overridable.** The gate is declared `overridable: false`. A run
  that can't satisfy it fixes the document or submits `bail`.
- **R10. No prose removed.** No hop or fold directive loses text. The
  directives gain a short statement of what a held hop means and how to read
  its findings, and the Phase 2 validator pass-through and the fold's
  re-validation step stay as they are.

### Non-functional

- **R11. Fast and local.** One gate evaluation runs the validator once and
  finishes well inside koto's command-gate time limit; a PLAN, the largest
  document, validates in about a second today.
- **R12. Tested.** The gate script has a test suite covering a passing
  document, each violation class, the raised banned-word finding, an
  em-dash-density finding that doesn't hold, an absent document and each
  cannot-decide case, with every printed finding checked by `rule-registry.sh
  verify-findings`. A test fails when an error-level code the validator can
  emit for these four types has no registry mapping.
- **R13. Repository checks pass.** `scripts/check-skill.sh scope` passes, and
  the new suite runs in CI in a job that builds `shirabe` from source and in
  the scope suite's bash-floor list, so its validator cases don't skip.
- **R14. Run from the repository root.** The gate resolves the repository's
  top level before validating, because R6 asks git whether an upstream is
  tracked and resolves paths against the working directory.

## Acceptance Criteria

- [ ] A /scope PRD hop whose PRD has an `upstream:` naming a path that
      doesn't exist holds on `landed`, and the blocking condition carries a
      finding with `rule_id` equal to the registry id whose alias is `R6`,
      the PRD's path and the field's line.
- [ ] A DESIGN containing a banned word from `skills/writing-style/rules.yaml`
      holds `hop_design` on `landed` with a finding whose `rule_id` is the
      banned-words entry's id and whose line is the word's line.
- [ ] A DESIGN whose only finding is FC10 em-dash density passes the gate.
- [ ] A document that validates clean passes the gate (exit 0) and the hop
      advances on `landed` as it does today.
- [ ] After an absorb at `fold`, a survivor with a malformed `absorbed:`
      declaration holds the fold's verdict transition with a finding whose
      `rule_id` is the entry aliased `FC18`.
- [ ] With the hop's canonical path empty, the gate exits 0.
- [ ] With `shirabe` absent from `PATH`, with a validator tool error, and with
      a schema-less document, the gate exits 2 and prints no finding.
- [ ] Every error-level code the validator can emit for brief/v1, prd/v1,
      design/v1 and plan/v1 maps to an active registry entry, checked by a
      test.
- [ ] Each notice-level check raised to blocking is named in the DESIGN with
      the rule it guards, and its registry entry lists the scope gate timings.
- [ ] `scripts/check-rule-registry.sh` exits 0 with the new entries.
- [ ] Every finding the test suite prints passes `rule-registry.sh
      verify-findings`.
- [ ] `scripts/check-skill.sh scope` passes.
- [ ] No line is removed from any directive or details block in
      `skills/scope/koto-templates/scope.md`, and no registry entry has
      `withhold: eligible`.

## Out of Scope

- **Withholding.** No prose leaves the hop directives and no rule is marked
  eligible to withhold; that is the withholding features' work, gated on a
  backstop check after the gate.
- **Validator severities.** The validator's own notice and error levels don't
  change. FC10 stays a notice in CI and in every other caller.
- **The check lifecycle.** Shadow, warn, block and retirement for checks, and
  a dispute path for a check that fails wrongly, are separate work.
- **Documents outside /scope.** A `/prd`, `/design` or `/plan` run on its own
  gets no new gate.
- **Offline measurement.** No ablation or long eval run; the effect is
  measured live from the exported gate events.
- **Other notice-level checks.** Plan-structure notices (FC07, FC08, FC11,
  FC12, FC14), section order (FC15), GitHub reconciliation (FC09) and the
  em-dash density rule stay notices; the Decisions section says why.

## Decisions and Trade-offs

**Which notice-level checks are raised (the BRIEF's open question).** Only
FC10's banned-word findings. A notice is raised when the rule it checks is
prohibitive (an author can write a conforming document without ever reading
the rule, so its prose is a real candidate to withhold), the check is local
and deterministic, and each finding names a line the author fixes in place.
The banned words meet all three. The plan-structure checks (FC07, FC08, FC11,
FC14) and section order (FC15) are generative: the author needs the format's
text to write the document at all, so that prose isn't going anywhere and a
blocking check buys little. FC12, the PLAN/DESIGN field consistency check, is
closer to prohibitive, but it reads the upstream DESIGN's acceptance criteria
and skips silently without one, so its silence says little; it stays a notice
until a withholding feature names it. FC09 reads GitHub, so it isn't local. Em-dash density is prohibitive and local but
it's a rate over the whole document, reported at its first occurrence, and a
quarter of the repository's scoping documents are over its threshold today;
blocking on it would hold many hops on a style rate nobody has decided must
hold. Alternative considered: raise every notice that can fire on these four
types. Rejected because it holds hops on generative rules whose prose stays
loaded anyway.

**A separate gate rather than a wider completion check.** `hop-complete.sh`
answers whether a hop landed, and its own comments explain why it validates
structure only: whole-document validation there would make completion depend
on another document's state. The new gate sits beside it and only the
`landed` edge needs both. Alternative: widen the completion check's `--check`
list. Rejected because it would change the fold's routing gates, which read
the same predicate to decide which hop is next.

**The fold is gated too.** The absorb rewrites the survivor after that
survivor's own hop gate passed, and its re-validation is prose. Gating only
the hops would leave the one write that splices `upstream:` and adds
`absorbed:` unchecked.

**Error severity read from the envelope, not a code list.** The gate counts
what the validator itself calls an error, so a check added or promoted later
is held without editing the gate, and a code with no registry entry stops the
run (exit 2) rather than passing silently.

## Known Limitations

- A PLAN's validation still runs FC09's `gh auth status` probe. Without a pull
  request context the reconciliation itself does nothing, and the probe's
  result is a notice the gate ignores.
- The banned-word findings are told apart from em-dash density by the
  validator's message text, since both carry FC10. A test pins the message
  prefix against the built validator so a reworded message fails CI rather
  than silently changing what the gate holds.
