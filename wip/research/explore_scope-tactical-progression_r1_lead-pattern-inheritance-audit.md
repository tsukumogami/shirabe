# Lead: pattern-inheritance-audit

## Findings

### Disposition Table

| Reference | Disposition | Justification (one-line) |
|---|---|---|
| `references/parent-skill-pattern.md` | **Verbatim** (cite, extend nothing) | Contract surface (I-1..I-7, three exits, team-lead discipline, substitution surfaces, conditional feeder shape, team-shape declarator) is substrate-agnostic and parent-shape-agnostic by design; `/scope` binds the same contract just with different per-parent values. |
| `references/parent-skill-state-schema.md` | **Verbatim** (cite, extend nothing in the reference itself) | The 5-field minimum (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`), the four invariants, the extension discipline, and the R9 finalization check spec are all parent-shape-agnostic. `/scope` adds its own parent-specific fields (its `chain_ran` will contain `/brief`,`/prd`,`/design`,`/plan` instead of `/vision`,`/strategy`,`/roadmap`) inside the schema's extension discipline — no reference rewrite needed. |
| `references/parent-skill-resume-ladder-template.md` | **Verbatim** (cite, fill body slots in `/scope`'s own SKILL.md) | The 9-row meta-ladder is fixed by design; rows 5-7 are explicitly body slots each parent fills in its own SKILL.md. `/scope` fills them with its own child set's prompts (4 partial-child-run rows for `/brief`/`/prd`/`/design`/`/plan` partials, status-aware re-entry against a PLAN doc instead of a STRATEGY) — the template does not need to learn about the tactical chain. |
| `references/parent-skill-child-inspection.md` | **Verbatim** (cite, extend per-parent surface table inside `/scope` SKILL.md by listing the four children's doc shapes) | The R14-widened isolation rule and the per-parent surface table accommodate both doc-emitting and issue/PR children. All four tactical-chain children are doc-emitting (BRIEF, PRD, DESIGN, PLAN), so they slot into the existing "doc-emitting" row of the table. The "table grows as new parents land children with new shapes" hook is already there — `/scope` adds no new shape. |

### Per-Reference Detailed Justification

#### 1. `parent-skill-pattern.md` — Verbatim

The pattern document is the contract surface itself: it is explicitly authored to be inherited unchanged. Three structural features make it transfer verbatim:

- **Two-Layer Contract (Semantic vs Reference Implementation).** Layer 1 invariants are substrate-agnostic AND parent-shape-agnostic. Nothing in I-1..I-7 names the strategic chain, references STRATEGY-as-terminal-artifact, or hardcodes the `/vision`/`/strategy`/`/roadmap` child set.
- **Three Exit Paths.** `full-run` / `re-evaluation` / `abandonment-forced` are pattern-level names. The doc explicitly says "the per-parent binding (which children produce which artifacts, which sub-shapes a Decision Record can take) is each parent's SKILL.md". For `/scope`: full-run terminal artifact is PLAN (not STRATEGY); re-evaluation Decision Record sub-shapes are TBD by SE7 authoring (likely no rejection sub-shape since `/plan` has no Phase 5 reject); abandonment-forced binding stays identical in mechanics.
- **Named Substitution Surfaces.** `storage_substrate: wip-yaml-md` and `team_primitive: single-team-per-leader-no-nested` are workspace-level commitments; both apply identically to `/scope`.
- **Team-Lead Operating Discipline (I-7 + 5-step loop).** The discipline binds the team-lead "of any team-emitting parent skill". The Binding Notes for `/charter` are an example, not a constraint — the doc says "at the parent-itself layer the binding is vacuous in v1" because `/charter` is single-agent. `/scope` will likely also be single-agent at the parent-itself layer (per `single-team-per-leader-no-nested`), so the same vacuous binding applies. The implementation-pass task class (120s window / 10-cycle patience budget) applies to each `/brief`,`/prd`,`/design`,`/plan` invocation just as it did for the strategic chain's children.

The pattern doc names `/charter` once in Binding Notes — that section is an example binding, not part of the contract. `/scope` adds its own analogous Binding Notes block to its SKILL.md without touching the pattern doc.

#### 2. `parent-skill-state-schema.md` — Verbatim

The schema is intentionally parent-shape-agnostic at every joint:

- **5-field minimum.** All five (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) are necessary AND sufficient for any chain-shaped parent. `/scope`'s state file under `wip-yaml-md` will live at `wip/scope_<topic>_state.md`, carry the same five fields, and extend with parent-specific fields (e.g., the chain-tracking unit `planned_chain`/`chain_ran`/`chain_skipped` with values drawn from `/brief`/`/prd`/`/design`/`/plan`).
- **Four invariants.** Per-child snapshot dual-check, conditional-field gating, chain-tracking, status-aware re-entry control — none names the strategic chain. The chain-tracking invariant in particular explicitly contemplates "parents whose run invokes a sequence of children" (which `/scope` is) vs. "non-chain-shaped parents (e.g., an implementation-loop parent)" — `/scope` lands in the chain-shaped bucket.
- **Extension discipline.** Three rules (no shadowing pattern-level names, conditional fields satisfy I-5, chain-tracking stays together) bind `/scope`'s extensions; nothing about the rules forces a substitution.
- **R9 hard-finalization check.** Three parts (`exit:` valid, sub-shape valid, conditional fields absent when ungated). `/scope`'s sub-shape inventory will differ from `/charter`'s (no `rejection` sub-shape if `/plan` lacks a Phase 5 reject equivalent — see Open Questions), but the check's spec is generic across sub-shape inventories.
- **Topic-slug regex `^[a-z0-9-]+$`.** Substrate-level, cited identically by every parent.

#### 3. `parent-skill-resume-ladder-template.md` — Verbatim

The template is built for the inheritance pattern this audit is testing. Three load-bearing features:

- **Body slots are explicit.** Rows 5-7 are named as "parent-specific body slots"; rows 1-4 and 8-9 are the meta-ladder. The template document is precisely the pattern surface — body content is per-parent by design.
- **Slot 5 (status-aware re-entry).** `/scope` fills this against its terminal artifact (PLAN, status Draft/Active/Done). The slot-filling rule says "the parent's SKILL.md names which child doc(s) trigger this slot and what statuses count as triggers" — `/scope`'s declaration goes in its own SKILL.md, not in the template.
- **Slot 6 (partial-child-run).** `/charter` filled this for `/strategy` and `/vision` wip artifacts (and unfilled slot 7 because the strategic chain has no feeder-doc case). `/scope` has FOUR children (`/brief`, `/prd`, `/design`, `/plan`), so slot 6 expands to more rows in `/scope`'s body — but the slot-filling rule already accommodates this: "the parent's SKILL.md enumerates which children expose partial-run signals". No template change.
- **Slot 7 (feeder-doc-detected).** `/scope` has no feeder skill in the tactical chain (see Surprises), so slot 7 stays unfilled — same as `/charter`'s pattern (slot 7 unfilled because `/charter` has no feeder-doc case beyond `/comp`'s degenerate-silence skip).
- **Stale-session threshold.** Pattern-level parametric concept. `/charter` picked 7 days. `/scope`'s threshold may differ (tactical chains arguably complete faster than strategic ones — see Open Questions), but the slot is pattern-level.

#### 4. `parent-skill-child-inspection.md` — Verbatim (with table addition inside `/scope` SKILL.md)

The R14-widened rule and per-parent surface table accommodate `/scope` without modification:

- **Isolation rule (R14 widened).** "A parent SHALL read only the child's durable externally-visible status surface; the parent SHALL NOT read child internals." Parent-shape-agnostic by construction.
- **Per-parent surface table.** Two rows: `doc-emitting` and `issue or PR`. ALL FOUR tactical-chain children are doc-emitting (BRIEF, PRD, DESIGN, PLAN — each has frontmatter with a status field). They all slot into the existing doc-emitting row; the surface for each is `(frontmatter status, git blob hash)`. No new row needed.
- **Drift detection.** Status flip OR blob hash diff — uniform across all four children.
- **Manual-fallback non-interference.** R13. Applies identically: a `/prd` run done directly outside `/scope` leaves the same `docs/prds/PRD-<topic>.md` artifact that an in-chain `/prd` run leaves; `/scope`'s resume ladder inspects the same surface either way.
- **Negative examples (internals).** `wip/research/<child>_*.md`, CI logs, comment threads, internal phase-pointer state, child resume-ladder choices — all already named. `/scope` inherits the list as-is.

### Pattern Surfaces `/charter` Introduced That `/scope` Does NOT Need

- **Conditional Feeder Invocation Shape (`/comp` gate).** The strategic chain has a private-only feeder (`/comp` for competitive analysis). The tactical chain has no analogous feeder skill — neither `/brief` nor `/prd` nor `/design` nor `/plan` has a visibility-gated optional companion in the same shape. `/scope` keeps slot 7 unfilled and keeps no `/comp`-style invocation rule. **The pattern reference still applies** (the Conditional Feeder Invocation Shape section says "a parent MAY offer a feeder skill"); `/scope` simply does not exercise the MAY.
- **Decision Record `rejection` sub-shape.** `/charter` introduced a `rejection` sub-shape gated on `/strategy` Phase 5 Reject firing INSIDE the chain. None of `/brief`/`/prd`/`/design`/`/plan` has an analogous in-chain reject phase whose firing means "the chain rejected its own work mid-stream"; see Open Questions about whether `/scope` defines a re-evaluation sub-shape at all.
- **Thesis-shift signal driving `/vision` invocation (R4 signal 2).** The strategic chain has an "is the thesis shifting?" signal that, when positive, triggers `/vision` even when a VISION already exists. Tactical chain has no analogous "shift" semantic — child invocations are driven by upstream-artifact presence/absence and Phase 0 artifact decisions, not by re-thesising. **The pattern reference's "Parents do not extend children's input surfaces" rule still applies verbatim** (parents pass children's existing input modes); only the specific R4-style signal is `/charter`-only.

### Surfaces SE7 Will Introduce That the Pattern Does Not Anticipate

- **Multi-output-mode children.** `/plan` (the tactical chain's terminal child) has TWO output modes: `single-pr` (PLAN doc with Issue Outlines, no GitHub) and `multi-pr` (PLAN doc + GitHub milestone + issues). The pattern's child inspection assumes a child produces ONE durable artifact shape. `/plan`'s output is a PLAN doc in both modes, so the inspection surface stays single — but `/scope`'s state will need to record which output mode the chain selected (an `execution_mode` parent-specific field), which the pattern's chain-tracking unit (`planned_chain`/`chain_ran`/`chain_skipped`) does not anticipate. This is an extension under the existing extension discipline, not a pattern hole.
- **Input-mode passthrough complexity.** `/plan` accepts `DESIGN-*.md`, `PRD-*.md`, `ROADMAP-*.md`, OR a topic-only freeform. `/scope`'s chain orchestration picks one (most likely DESIGN since `/scope` runs `/design` immediately before `/plan`), but the pattern's "Parents do not extend children's input surfaces" rule says `/scope` picks from `/plan`'s existing input modes. The pattern handles this; SE7 just needs to articulate the choice.
- **Status-aware re-entry against a PLAN (Active vs Done).** The pattern reference's status-aware re-entry slot assumes a binary "Accepted/Active" vs Draft surface. PLAN docs have three statuses (Draft/Active/Done); `/plan`'s `multi-pr` mode sets status to Active, `single-pr` to Draft, and Done is the terminal post-implementation state. `/scope`'s status-aware re-entry slot needs three rows (Draft / Active / Done) instead of `/charter`'s two (Accepted/Active / Draft). The slot-filling rule already allows this ("parent's SKILL.md names which child doc(s) trigger this slot and what statuses count as triggers"); SE7 just enumerates the three rows.
- **Validation as a chain-completion gate.** `/charter` invokes `shirabe validate` against the Draft STRATEGY as a chain-level enforcement gate (AC24). The pattern does not name this discipline. `/scope` may or may not have an analogous gate — the tactical chain's terminal artifact (PLAN) has different validation semantics. This is parent-specific orchestration logic, not a pattern gap; the pattern reference doesn't need to learn about it.

### Quoting Pattern Where /scope Inherits Verbatim

- **R1 structural elements (7 floors).** All seven (Input Modes, execution-mode flags, topic-slug constraint, Workflow Phases, Resume Logic ladder, Phase Execution, Reference Files) apply. `/scope` writes its SKILL.md with the same seven sections.
- **Default-option wording.** "Re-evaluate / Revise / Bail" triad is a literal-substring contract; `/scope`'s status-aware re-entry vocabulary should use the same triad against its PLAN surface, with parent-specific prompt content for the three statuses (Draft / Active / Done).
- **Idle-pings-are-not-inbox-messages rule.** Applies to `/scope`'s child-invocation dispatch identically.
- **Nudge content rule (artifact + location + verdict).** Applies identically.
- **`ci_outcome` semantics.** Applies if `/scope`'s `--auto` runs ever depend on CI (likely YES because `/plan`'s `multi-pr` mode creates GitHub issues whose downstream `/work-on` runs trigger CI — but the `/scope` chain itself terminates at PLAN creation, BEFORE the CI runs, so the `ci_outcome` semantics may be moot for `/scope` v1).

## Implications

### What This Means for `/scope`'s SKILL.md Structure

`/scope`'s SKILL.md follows `/charter`'s template verbatim with the seven structural elements (R1) and the same Reference Files table shape. The four pattern references appear in `/scope`'s Reference Files table identically:

```
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` | All phases — contract surface, invariants, exit paths, substitution surfaces |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` | Phase 0 (slug regex), Phase 2 (state writes), Phase N (R9 check) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` | Resume Logic — meta-ladder rows 1-4 and 8-9 |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` | Phase 2 — child-doc inspection (R14 widened rule, dual-check drift detection) |
```

### What `/scope` Authoring Owns (Parent-Specific Body)

- A Phase 2 chain-orchestration phase reference that declares the four per-child invocation rules (analogous to `/charter`'s phase-2-chain-orchestration.md with R4/R5+R12/R6/R7 sections).
- A resume-ladder phase reference (analogous to `/charter`'s phase-resume.md) with body slots filled for the tactical chain — slot 5 status-aware re-entry against PLAN (3 statuses), slot 6 partial-child-run for each of the 4 children (~4 rows), slot 7 unfilled.
- A finalization phase reference (analogous to `/charter`'s phase-finalization.md) with exit-path orchestration for `/scope`'s exit-binding shape: full-run terminal at PLAN, re-evaluation Decision Record (sub-shapes TBD), abandonment-forced binding.
- A state-management phase reference (analogous to `/charter`'s phase-state-management.md) defining parent-specific fields (e.g., `execution_mode` for `single-pr`/`multi-pr`, `input_source_artifact` for which upstream the chain was anchored to).

### Pattern Reference Files Stay Untouched

SE7 ships `/scope` WITHOUT editing any of the four pattern reference files. The pattern reference files were designed to absorb the second parent's body via the inheritance hooks (named substitution surfaces, body slots, per-parent surface table, extension discipline). If SE7 finds itself wanting to edit a pattern reference, that is a signal something has been misclassified as pattern-level when it was actually `/charter`-specific.

## Surprises

### 1. Tactical Chain Has No Feeder

The strategic chain ships with `/comp` as a private-only feeder, which forced the Conditional Feeder Invocation Shape into the pattern. The tactical chain has no equivalent — `/brief`, `/prd`, `/design`, `/plan` are all main-chain children, none is a side-channel companion. **This is unexpected because the pattern's three-condition gate (signal + skill-exists + visibility) is framed as the standard shape for any conditional companion**. The tactical chain having ZERO feeder users suggests either: (a) the tactical chain genuinely doesn't need one, or (b) there's a latent tactical-chain feeder candidate that hasn't been authored yet (e.g., a `/spike` skill for technical investigation in the prd→design gap, or a `/comp`-equivalent tactical-competitive-scan). Worth flagging as a question.

### 2. `/plan` Terminal Status Is NOT "Accepted"

`/charter`'s pattern naturally produces an "Accepted" terminal artifact (STRATEGY transitions Draft → Accepted on user approval). `/plan`'s output PLAN doc has lifecycle states `Draft` (single-pr mode) or `Active` (multi-pr mode), then later `Done` after implementation. **There is no "Accepted" status in the PLAN lifecycle**. The pattern's status-aware re-entry slot vocabulary (which `/charter`'s SKILL.md instantiates as "Re-evaluate / Revise / Bail against an Accepted upstream artifact") needs adapting at the wording level — `/scope` re-enters against an Active or Done PLAN, not an Accepted one. The literal-substring contract on the triad ("Re-evaluate / Revise / Bail") is fine; only the upstream noun changes.

### 3. `/plan`'s `multi-pr` Mode Creates Downstream Work That `/scope` Cannot Track

In `multi-pr` mode, `/plan` creates a GitHub milestone and a set of issues. The chain terminates at PLAN-creation time. But `/work-on` (a separate skill, not in the tactical chain) drives those issues to PRs. **This means `/scope`'s full-run exit fires BEFORE the work it scaffolded is actually implemented**. The pattern's framing of "the chain reaches its terminal artifact" still applies (the terminal artifact is the PLAN doc, not the implemented code), but a future amplifier-layer parent might want to extend the chain to track implementation completion. Out of scope for SE7.

### 4. Input Mode Diversity Is Higher in Tactical Chain

`/charter`'s input modes are tightly constrained: a topic slug, period (no path-as-upstream — paths are rejected at Phase 0). `/scope` will likely accept more input shapes: topic slug, BRIEF path, PRD path, DESIGN path, or ROADMAP path (since each downstream child accepts the upstream's artifact path as an Input Mode). **The pattern reference's "Parents do not extend children's input surfaces" rule still applies** — `/scope` passes through existing modes — but `/scope`'s OWN input modes are richer than `/charter`'s. This is parent-specific surface that needs explicit enumeration in `/scope`'s SKILL.md Input Modes section.

### 5. Children Have Heterogeneous Resume Logic Already

The four tactical-chain children have richer per-child resume ladders than the three strategic-chain children. `/brief` has 6 resume rows; `/prd` has 6; `/design` has 8; `/plan` has 8 (with `multi-pr` GitHub-issue check). **This raises the dispatch complexity for `/scope`'s Team-Lead Operating Discipline** — child invocations may complete fast (re-detect existing artifact → resume) or slow (full chain run). The pattern's implementation-pass task class (120s window / 10-cycle patience budget) might be over-tuned for fast cases and under-tuned for slow ones. SE7 may want to bind two task-class profiles, not one. This is parent-specific tuning under the pattern's "parents MAY tune them per their own runtime profile" allowance.

## Open Questions

1. **Does `/scope` need a `rejection` sub-shape on re-evaluation?** `/charter` defines it gated on `/strategy` Phase 5 Reject firing inside the chain. None of `/brief`/`/prd`/`/design`/`/plan` has an explicit in-chain reject phase that semantically maps to "the chain rejected its own work". `/scope`'s Decision Record sub-shape inventory might just be `{re-evaluation}` (single-shape) — but worth confirming whether any tactical-chain child has a reject-equivalent that escalates to chain-level abandonment.

2. **Stale-session threshold for `/scope`?** `/charter` picked 7 days. Tactical chains arguably complete faster (a PRD + design + plan sequence is days, not weeks), suggesting a shorter threshold. Or the opposite — tactical chains span longer because implementation work intercedes, suggesting a longer threshold. SE7 picks; pattern doesn't constrain.

3. **`/scope`'s terminal-artifact validation gate?** `/charter` invokes `shirabe validate` against the Draft STRATEGY (AC24). Does `/scope` invoke `shirabe validate` against the produced PLAN? The validator already handles PLAN docs; the chain-level gate is a separate orchestration commitment.

4. **`/scope`'s `--auto` re-evaluation cap?** `/charter` accepts `--max-rounds=N` to cap re-evaluations. Tactical chains may have different re-evaluation profiles (a re-evaluated PRD is more common than a re-evaluated STRATEGY, since requirements churn more than thesis), motivating a different default cap.

5. **What is `/scope`'s feeder-doc-detected slot (slot 7) actually doing if there's no feeder?** The slot is left unfilled in `/charter` too — but `/charter` AT LEAST has the conditional `/comp` integration shaped against a future feeder skill. `/scope` may have NO conditional feeder anywhere. If so, the slot is genuinely unused, which is fine but worth documenting explicitly to head off "but what about feeder X?" review questions.

6. **Does `/scope` need an `execution_mode` parent-specific field to record `/plan`'s single-pr vs multi-pr choice?** The pattern's chain-tracking unit (`planned_chain`/`chain_ran`/`chain_skipped`) does not capture per-child output-mode selection. `/scope`'s state likely needs this as a parent-specific field under extension discipline.

7. **Does `/scope` support multiple entry-point upstream paths (BRIEF, PRD, DESIGN, ROADMAP) or is it strictly topic-only like `/charter`?** Architecturally easier to constrain to topic-only and let Phase 1 discovery detect upstream artifacts at the published paths (mirroring `/charter`'s discipline). But the tactical chain has more upstream-artifact diversity than the strategic chain, and authors may reasonably want to invoke `/scope <PRD-path>` or `/scope <DESIGN-path>` to enter mid-chain.

## Summary

All four SE4 parent-skill pattern references transfer **verbatim** to `/scope`: the pattern doc, state schema, resume-ladder template, and child-inspection rule are parent-shape-agnostic by design, with explicit body-slot hooks (rows 5-7 of the ladder, the per-parent surface table, the named substitution surfaces, the conditional-feeder MAY clause) that absorb `/scope`'s tactical-chain specifics inside `/scope`'s own SKILL.md rather than forcing reference edits. The main implication is that SE7 authoring focuses entirely on parent-specific body files (chain-orchestration, resume, finalization, state-management) plus a `/scope`-flavored SKILL.md following `/charter`'s seven-element template — no pattern reference touches needed. The biggest open question is whether `/scope` needs an `execution_mode` parent-specific state field to record `/plan`'s `single-pr` vs `multi-pr` output-mode choice, since the pattern's chain-tracking unit (`planned_chain`/`chain_ran`/`chain_skipped`) does not capture per-child output-mode selection and the tactical chain genuinely needs this signal at re-entry time.

---

**Visibility flag for downstream BRIEF (Public-repo handoff):** This findings document cites only public-repo paths (`public/shirabe`). No private-repo content appears. Safe to inherit into a Public-shirabe BRIEF without redaction.
