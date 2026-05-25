# Phase 6 Security Review: shirabe-progression-authoring

**Reviewer:** security-reviewer (Phase 6, second-look on Phase 5's
security-researcher draft)
**Method:** Read the Security Considerations section at lines
1304-1364, the Phase 5 full report at
`wip/research/design_shirabe-progression-authoring_phase5_security.md`,
and cross-referenced against Solution Architecture (lines 980-1221),
Implementation Approach (lines 1223-1302), Consequences (lines
1366-1454), Open Questions (lines 1455-1521), and Decision 4
(Pattern-surface ratification, lines 550-626) and Decision 6
(Conditional-feeder, lines 714-773).
**Phase 5 outcome under review:** Option 2 — document considerations,
no design changes.

---

## Question 1: Attack vectors not considered?

**Verdict:** PASS with two notes worth surfacing.

The four standard dimensions are thoroughly covered by Phase 5 and
the four-paragraph Security Considerations section reflects the
analysis accurately. The five project-specific dimensions named in
the coordinator brief are each addressed in Phase 5; the section
folds the load-bearing two (public-repo pre-merge wip/ visibility +
fail-closed Private default) into authored prose and treats the
other three (skill loader path resolution, cross-branch state-file
behavior, public-repo content safety) appropriately by either
inheriting an existing safe property or naming the failure mode as
functional rather than security-relevant.

Two attack vectors deserve a closer look. Both are NIT-severity —
neither requires a design change — but the second touches the
coordinator's explicit Q3 prompt about Decision 4's copy-paste
eval baseline.

**Note 1.1 (NIT) — Author-supplied prose at chain-proposal
acceptance time.** R7.5's chain proposal is interactive: the author
confirms the chain before execution. The state file's
`planned_chain` field (Solution Architecture, Component 3) captures
the accepted chain; the proposal text the author confirms may
include parent-specific prompt vocabulary that pulls verbatim from
author input (the topic slug after slug-rejection, plus any
free-text discovery prompts the author types). The slug regex (R3)
cuts off path-traversal-style escapes; the malformed-state hard
surface (R11) catches malformed reloads. Neither catches the case
where the author types something *they* later regret seeing in the
state file (e.g., a typo containing a customer name in a free-text
discovery prompt that gets summarized into the state file). This is
a usability/data-hygiene property, not a security defect; the
Security Considerations section's "do not paste secrets, customer-
identifiable context, or unpublished competitive positioning into
these fields" line already covers the spirit. No design change
needed; the existing prose is sufficient.

**Note 1.2 (NIT) — Decision 4 copy-paste eval baseline as a
trust-propagation surface.** The coordinator's Q3 asks whether the
copy-paste path itself introduces a trust boundary issue. The
chosen approach (Decision 4): `/charter`'s `evals.json` is the
canonical source; `/scope` and `/work-on` copy-and-adapt the
baseline scenarios. The trust property: a defect in `/charter`'s
baseline scenarios propagates to other parents only through human
copy-paste with hand-adaptation, not through automatic re-import.
This is the *safer* shape — a defect doesn't fan out automatically
— but it has the inverse risk: a *security improvement* to the
baseline (e.g., a new slug-injection eval that catches a class of
bug Phase 5 didn't anticipate) also doesn't fan out automatically.
The design accepts this trade-off as "drift" in the Negative
consequences (line 1420-1424). For Phase 6, the relevant question
is whether copy-paste introduces a *new* trust boundary the Phase 5
review missed. Answer: no — every parent's `evals.json` is in-repo,
author-reviewed at commit time, and runs against the same in-repo
skill code. The trust boundary is the repo's commit gate (PR
review), which is unchanged. The Security Considerations section's
sentence "the shared eval baseline (Decision 4) is copy-and-adapted
across parents rather than ref-imported; the trust boundary is
in-repo files" handles this correctly. No additional vector found.

**No new attack vectors warrant escalation.** No MUST-FIX, no
SHOULD-FIX from Question 1.

---

## Question 2: Mitigations sufficient?

**Verdict:** PASS.

Mitigations the Security Considerations section relies on:

| Risk surface | Mitigation | Sufficient? |
|---|---|---|
| Path traversal via topic slug | R3 slug regex hard-rejected at Phase 0 | Yes — `^[a-z0-9-]+$` excludes all path-meta and shell-meta chars |
| Malformed/maliciously-crafted state file on resume | R11 hard surface, no silent fall-through | Yes — explicit "MUST NOT silently fall through to Phase 0" |
| Conditional-feeder invocation in wrong visibility | R5 degenerate-silence + R12 visibility detection | Yes — fail-closed Private default plus skill-existence stat |
| Author confirms intent before visibility-gated content lands | R7.5 chain proposal is interactive | Yes — author confirms chain before any phase prompts surface |
| Public-repo durable artifact body content | Author-facing warning in Security Considerations | Yes for the documented surface — see Note 2.1 below |
| wip/ artifacts pre-merge in public repo | Author-facing warning in Security Considerations | Yes — explicit "durably public from the moment the branch is pushed" |

Mitigation sufficiency holds across all the named risks. The
section's wording is precise: the public-repo property is "inherited,
not worsened" and the persistence is named to "SE4 directive 9 /
durable-evidence policy." Authors who read the section understand
exactly what to avoid pasting.

**Note 2.1 (NIT) — Authoring-discipline mitigations rely on author
attention.** Both public-repo properties (wip/ pre-merge visibility,
durable Decision Record body) are mitigated by author-facing
warnings rather than by a system-enforced filter. This is correct:
the design is documentation-only, has no code component, and adding
a content-redaction filter would be an over-engineered control for
an author-driven workflow. The Phase 5 review and the Security
Considerations section both frame these as author-discipline
properties. The risk reduction relies on the author reading and
heeding the warning; the system doesn't enforce it. This is
acceptable because (a) the author is the trust principal in this
workflow, (b) the same author has commit access regardless of skill
behavior, and (c) the workspace-level CLAUDE.md wip-hygiene rule
already conveys the public-repo property to anyone who reads it.
No design change needed; the documented mitigations are sufficient
for the documentation-only scope.

**Note 2.2 (NIT — wording precision check requested by
coordinator).** The coordinator asks whether the section's wording
is "precise enough" for SE4 directive 9 wip/ persistence. The
section says:

> the persistence of wip/ artifacts (per the durable-evidence
> policy) means the surface lives longer than under the workspace's
> default wip-hygiene rule.

This is precise but does not explicitly name *which* artifacts in
this design persist. The Phase 5 report names them concretely
(coordination manifest, decision reports, security report, review
verdicts). The Security Considerations section's prose stays at the
schema level (state file + Decision Record body). A reader who
isn't tracking SE4 directive 9 may not realize the design's *own*
wip/ artifacts (this very security review file) also persist. This
is a clarity issue rather than a security defect — the durable
artifacts are the same scope either way — but if the coordinator
wants a sharper wording, append a clause like "(including this
design's own coordination, decision, and review artifacts under
`wip/research/`)" to make the persistence inventory explicit.
SHOULD-FIX-if-cheap-during-Phase 6 escalates to NIT because the
section's existing prose covers the surface; the more concrete
inventory would be polish, not a security fix.

**No insufficient mitigations identified.** No MUST-FIX, no
SHOULD-FIX from Question 2.

---

## Question 3: N/A justifications applicable?

**Verdict:** PASS. Phase 5 chose Option 2 (document considerations),
not Option 3 (N/A). Re-checking each sub-claim in the Security
Considerations section for mis-classification:

| Sub-claim | Phase 5 classification | Re-check verdict |
|---|---|---|
| "No network surface" | applicable, low severity | Correct — verified: no HTTPS/API/external resolver in design body |
| "No external-artifact ingestion" | applicable, low severity | Correct — verified: all inputs are local-FS or local-git |
| "No secret handling" | applicable, none-severity | Correct — verified: state file field list contains no creds/tokens |
| "No privilege escalation" | applicable, low severity | Correct — verified: skill runs in existing Claude Code authoring environment |
| "Filesystem activity inside worktree" | applicable, low severity | Correct — verified: paths are `docs/<type>/`, `wip/`, `skills/<name>/` |
| Cross-branch resume is "functional, not security-relevant" | applicable, security-N/A-but-functional-yes | **CHALLENGED — re-confirmed correct, see below** |
| "No third-party dependencies; copy-paste eval baseline" | applicable, low severity | Correct — see Question 1 Note 1.2 |

**Cross-branch framing challenge (per coordinator's Q3 prompt).**
The coordinator explicitly asks: "verify that framing [cross-branch
is functional, not security-relevant] holds."

Cross-branch concerns from Phase 5's three scenarios:
1. Merge child PR, resume `/charter` on main → state file is on
   feature branch, not main → resume fails the ladder, starts
   fresh.
2. Rebase/squash feature branch with state files present → durable
   `docs/<type>/` artifacts remain; status-aware re-entry fires.
3. Re-use topic slug across multiple feature branches → state is
   topic-keyed (I-4) and branch-isolated; no leakage between
   branches.

For each, I ask: could the failure mode produce a security-relevant
outcome (data leak, privilege escalation, integrity violation)?

- Scenario 1: starts fresh → no data leak (no state inherited), no
  privilege escalation (same author, same skill, same auth
  environment), no integrity violation (fresh chain produces
  fresh artifacts; if the author later notices the orphaned
  feature-branch state file, they can delete it manually). The
  failure mode is *usability* (lost work-in-progress), not
  security. Functional framing holds.

- Scenario 2: durable artifact remains, status-aware re-entry fires
  (R11, AC18). The re-entry surface is interactive; the author
  confirms before continuing. The squashed-away state file
  represents *lost* state, not *leaked* state — squash-merge removes
  it from main's history. Functional framing holds.

- Scenario 3: branch-isolated state files. Two feature branches
  with the same topic slug → two independent state files, each on
  its own branch. The branches don't share state. Could a malicious
  branch B craft a state file that, on rebase into branch A,
  poisons A's resume? No — the rebase would create a merge conflict
  on `wip/charter_<topic>_state.md` (both branches modify it); git
  surfaces the conflict; the author resolves. The author is the
  trust principal. No silent state poisoning. Functional framing
  holds.

**Verified: "functional, not security-relevant" is correct
classification for all three cross-branch scenarios.** Phase 5's
framing is accurate; no sub-claim is mis-classified.

**No mis-classifications identified.** No MUST-FIX, no SHOULD-FIX
from Question 3.

---

## Question 4: Residual risk escalation?

**Verdict:** PASS. I concur with Phase 5's Option 2 / no-design-
changes conclusion. The design has no security risk that requires
design-level changes; all residual risk lives in author-facing
authoring discipline, which the Security Considerations section
documents at acceptable precision.

**Residual risks the design carries (already documented):**
- Public-repo pre-merge visibility of `wip/<parent>_<topic>_state.md`
  and the Decision Record body. Documented; authors warned.
- Fail-closed Private default for missing CLAUDE.md visibility header.
  Documented; warning text + interactive chain-proposal (R7.5) are
  the compensating mitigations.
- Cross-branch resume gap. Documented as functional; fail-closed v1
  behavior is correct.
- Skill loader path-resolution assumption (`${CLAUDE_PLUGIN_ROOT}`
  is loader-resolved, not author-interpolated). Phase 5 correctly
  notes this is out of scope for the design and is an
  implementation-time check during Stage 2 of `/charter`'s SKILL.md
  authoring.

**Residual risks worth flagging but not escalating:**
- PRD line 1085-1090 documentation inconsistency (the PRD's
  known-limitation phrasing is inverted relative to actual
  behavior). Phase 5 already noted this. Recommend logging as a
  PRD docfix issue post-design rather than blocking on it; the
  design itself is correct.
- The design's *own* wip/ artifacts (decision reports, this Phase 6
  review file, the Phase 5 security report, coordination manifest)
  persist on the feature branch by SE4 directive 9. The
  authoring-discipline warning in Security Considerations applies
  to them — the security-reviewer (me) and the security-researcher
  (Phase 5) should treat our prose as durably public from push.
  Both reports comply: no private repo references, no internal
  business strategy, no competitor names.

**No risks require escalation to MUST-FIX.** The design is
ship-ready from a security review perspective.

---

## Severity Summary

| Finding | Severity | Action |
|---|---|---|
| 1.1 — Author-supplied free-text in state file may carry typos / regrettable content | NIT | No change; existing warning covers it |
| 1.2 — Copy-paste eval baseline trust-propagation | NIT | No change; correctly framed in Security Considerations |
| 2.1 — Author-discipline mitigations rely on author attention | NIT | No change; correct for documentation-only design |
| 2.2 — Persistence-inventory wording could be sharper | NIT (SHOULD-FIX-if-cheap) | Optional: append clause naming the design's own wip/ artifacts |
| 3 — Cross-branch framing | PASS — re-verified correct | None |
| 4 — Residual risk escalation | PASS — no escalation | None |

**No MUST-FIX findings.** **No SHOULD-FIX findings that aren't
also NIT-equivalent.** Four NITs total; all optional.

---

## Summary

The Phase 5 security-researcher's analysis is thorough, accurate,
and the resulting Security Considerations section faithfully
reflects it. I concur with Phase 5's Option 2 / no-design-changes
conclusion: the design ships no code, no network surface, no secret
handling, and the two visibility properties (pre-merge wip/ + fail-
closed Private default) are documented at sufficient precision for
authors to act on. The only optional polish is sharpening the
persistence-inventory wording in the section's wip/-artifacts
paragraph to enumerate that the design's own coordination, decision,
and review artifacts also persist; this is NIT-level and the
existing prose already covers the security surface.

**Verdict: PASS.** No escalation. Design approved from security
review perspective.
