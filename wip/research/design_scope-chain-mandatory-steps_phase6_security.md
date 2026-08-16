# Phase 6 Security Review — DESIGN-scope-chain-mandatory-steps

Reviewer: security. Artifact:
`docs/designs/DESIGN-scope-chain-mandatory-steps.md`.

## Verdict

PASS WITH CONDITIONS

The change introduces no new external surface, no network calls, no
credentials, and no new interpolation site. The one genuinely new surface —
a `wip/` handoff written by one skill and read by two others — is correctly
bounded by what the design bars it from carrying, and the reasoning behind
the path shape holds up. Five conditions below are precision and
completeness defects, not architecture defects: the design's own
highest-priority security item lands at an address the design never names,
the bail narrowing is worded in a way that reopens the bug it fixes on
exactly the new path the design creates, the clean-cancel deletion scope is
under-specified in the opposite direction, the malformed-handoff case has
no stated fallback, and the visibility argument credits the wrong mechanism
while omitting the free-text field the same decision ships.

## Surface Coverage

| Pattern-level surface | Touched? | Handled? |
|---|---|---|
| Slug re-validation on resume | Yes — a third ladder slot recovers a slug from an on-disk path | Partially. The requirement is stated and correct; the file holding the enumeration is never named as an edit site. See Required Change 1. |
| Closed write-target set | Yes — one new `wip/` path per parent | Partially. Correct in substance; the per-parent edit is larger and less uniform than "both gain one path". See Required Change 3 and Verified Claims. |
| State-file enum re-validation | Yes — `chain_skipped[].reason` becomes enum-typed, and `child:` becomes the entry key | Adequately. Closing the vocabulary strictly improves this surface: a field that was free text becomes a re-validatable enum. The design does not say the new enum joins the re-validation list; it should. See Optional 1. |
| Stale `parent_orchestration:` self-heal | No | N/A. Nothing in the change writes, reads, or conditions on the block. Phase 0 runs unchanged on a handoff-fed entry ("Run Phase 0's setup obligations against the current worktree"), so the unconditional clear still fires. |
| Visibility boundary | Yes — the reason vocabulary and `/charter`'s feeder membership | Partially. The conclusion (never-planned survives, no member names a private-only child) is right; the stated reason is wrong and the free-text sibling is unaddressed. See Required Change 5. |
| No untrusted-input interpolation | Yes — the handoff is a new untrusted read | Yes. Verified against what the design says the handoff carries: nothing in it reaches a shell argument, and the design deliberately keeps `--upstream` out of the file so the one value that reaches committed frontmatter keeps travelling through the parent's existing validated-flag path. One gate-reaching field is unnamed — see Required Change 4. |

## Handoff Threat Analysis

**What the file is.** `wip/scope_<topic>_handoff.md` or
`wip/charter_<topic>_handoff.md`, written by `/explore`'s produce phase,
read by the named parent's Slot 7. It is a world-writable file in the
working tree with no provenance binding, no signature, and no schema
validator. Treating it as untrusted is correct and the design does.

**Malformed, truncated, adversarial content.** The design's containment
argument is the right one and it is load-bearing: the handoff is barred
from carrying artifact existence, status, content hashes, visibility, or
the upstream path, so a hostile file cannot make a parent believe a
filesystem fact. Everything it does carry is prose that lands in a
discovery conversation a human is participating in. The residual gap is
the degenerate case rather than the hostile one. Slot 7 fires on a path
match, and the design pairs that with "the cold-start projection is
suppressed, because a handoff run is not a cold start." An empty,
truncated, or unparseable handoff therefore fires the slot, suppresses the
projection, and leaves Phase 1 with neither a handoff prior nor the
fallback it replaced. No rule says what to do. See Required Change 2.

**What reaches a shell command, a path, or committed frontmatter.**
Verified, and the design's claim holds. The only value reaching a command
is the topic slug, which comes from the parent's own `$ARGUMENTS`
validated at Phase 0 against `^[a-z0-9-]+$` — not from the file. The
`--upstream` value is the one author-supplied string in either parent that
reaches a committed frontmatter field (`/plan` writes it into the PLAN's
`upstream:`, `/strategy` into the STRATEGY's), and the design keeps it out
of the handoff for exactly that reason. That is the right call and it is
argued correctly.

Handoff *prose* does reach committed document bodies, by the ordinary
route: it informs the discovery conversation, which informs the BRIEF the
child authors. This is not a new surface — it is the same trust an author
typing into the discovery prompt already has — and it does not cross a
visibility boundary, because the handoff is repo-relative and therefore
carries the repo's own visibility. Checked and clean.

**Can it cause a parent to skip a check?** Traced. The handoff pre-supplies
one answer that gates a decision: the framing-shift answer for `/scope`
(thesis-shift for `/charter`). Per
`skills/scope/references/phases/phase-1-discovery.md`, a positive
framing-shift answer is the override on `/brief`'s
Mandatory-with-auto-skip gate: it fires `/brief` even when an Accepted
BRIEF sits at the canonical path. So the destructive direction is a
handoff asserting *yes* — it does not skip a check, it defeats re-entry
protection against settled work. A negative answer only lets the auto-skip
stand, which is re-entry protection working normally.

Severity is low, and three independent controls bound it. The design
already requires that the question be re-surfaced as a confirmation and
that "the author's response is what gets recorded". `/brief`'s own resume
ladder refuses to silently overwrite ("BRIEF exists with status Accepted
or Done -> Offer to revise or start fresh"). And `/brief` Phase 5 requires
explicit human approval for the Draft → Accepted transition. A hostile
handoff can nudge a prompt; it cannot clobber an Accepted BRIEF. The
finding is that the Security Considerations section never names this
field, and its mitigation sentence — "degrades to a discovery conversation
with a wrong prior rather than to a parent acting on false filesystem
beliefs" — is true of the predicate estimates and silent about the one
input that is not a filesystem belief and is not re-derived later. The
predicate estimates genuinely are re-derived against the real PRD one
child later; the framing-shift answer is consumed once and never
revisited.

**Confused deputy.** No. A parent acting on a handoff acts on its own
authority throughout: it runs its own Phase 0 (slug validation, visibility
detection, upstream validation against the current worktree), its own
Phase 1, and its own gates. The handoff supplies conversational priors,
not authority, and the ordering decision — Slot 5 above Slot 7, so a
settled artifact always wins — is the right one and is argued for
correctly. The pre-ladder-check alternative was rejected on exactly the
ground a reviewer would reject it on.

**Write direction.** Worth stating plainly since the design does not: the
chosen shape has `/explore` writing into each *parent's* `wip/` namespace,
rather than parents deleting from the router's. `/explore` declares no
closed write-target set, so this is not a contract violation, and the trust
direction is unchanged either way — but it means `wip/scope_<topic>_*` is
now a prefix two skills write under, and that prefix is also where the
state file lives. Nothing in the change exploits that; it is the reason
Required Changes 2 and 3 have to be precise about prefix-versus-path.

## Verified Claims

| Claim in the design | Verdict |
|---|---|
| "the rule currently enumerates two slots" (slug re-validation) | TRUE. `references/parent-skill-security.md` names a Slot 5 `docs/` glob and a Slot 6 `wip/<child>_<topic>_*` match, and nothing else. |
| The slug re-validation edit "is a one-line edit" | UNDERSTATED. One line in `references/parent-skill-security.md`, plus `skills/scope/references/phases/phase-resume.md`, which restates the rule under Slot 6 and would need it under Slot 7. `skills/charter/references/phases/phase-resume.md` restates it nowhere today, so `/charter` gets its first statement rather than an extension. |
| "Both parents' write-target sets are enumerated" | TRUE for both, but differently shaped. `/charter` SKILL.md L333-343 is a closed list of five concrete paths. `/scope` SKILL.md L789-852 is authoritative and is restated in `phase-3-exit-finalization.md` L291-310 and read back in `phase-4-cleanup.md` L88-120, with the file itself warning the restatements "must not diverge". |
| "both gain one path" | TRUE for `/charter` — the list is concrete, has no `wip/charter_<topic>_*` wildcard, and its prose count ("exactly five places") becomes six. IMPRECISE for `/scope` — the set and the Phase 4 sweep are already written as the prefix `wip/scope_<topic>_*`, which the handoff path matches, so no path is added; what is new is that a *second skill* writes under that prefix and `/scope` only removes. |
| A router-namespaced file "would have required each parent's set to admit a path in another skill's namespace" | TRUE and the distinction is real. Note `/charter`'s set already admits a non-`charter_`-prefixed path (`wip/roadmap_<topic>_scope.md`), but `/charter` composes that one itself, so the "paths this skill composes" boundary is intact and the design's argument survives the apparent counterexample. |
| The Phase 1 bail defect, link by link | TRUE. `/scope` SKILL.md L443-448: "If any wip state exists for the topic (the state file, any child intermediate, or any research scratch)". Phase 0 writes the state file unconditionally, so the first disjunct is always satisfied at Phase 1. |
| "the other parent grades its own equivalent" | TRUE. `/charter` `phase-finalization.md` Step 3 routes clean-cancel on `chain_ran` history plus `planned_chain` wip intermediates — the parent's own state file is not a disjunct — and AC12c names the Phase-1 bail as the canonical clean-cancel case. `/charter` needs no equivalent fix. |
| "the state file is durably public from feature-branch push" | TRUE and sourced. `skills/charter/references/phases/phase-finalization.md` L802-807 states it verbatim, including that squash-merge removes the file from main's history but not from the feature branch's pre-merge commits. |
| "The one parent with a private-only child keeps that child out of the field entirely, by convention documented locally" | MISATTRIBUTED. The rule is pattern-level, not local: `references/parent-skill-pattern.md` L215-232 states that a never-planned child produces no `chain_skipped:` entry, that the statement is conversational and "never recorded", and gives the visibility rationale. `/charter` SKILL.md L140 echoes it. |
| "A closed enum makes the leak impossible for every future feeder" | OVERSTATED. See Required Change 5. |
| The never-planned category still needs to exist | TRUE, and the design is not being conservative without cause. Because `chain_skipped[]` keys on `child:`, recording a private-only child at all names it, whatever the reason value says. Omission from both lists is what closes the leak; the enum cannot. |
| Clean-cancel deletion path is slug-composed and enumerated | TRUE. `wip/scope_<topic>_state.md` is composed from `$ARGUMENTS` validated at Phase 0 in the same session as any Phase 1 bail, and the path is already inside the enumerated `wip/scope_<topic>_*` prefix. Deletion cannot reach outside `wip/`. |
| A resume after a clean cancel is not confused by the absence | TRUE. No state file, no child wip (the narrowed test guarantees that, or the exit was not a clean cancel), no settled artifact — the ladder falls to Slot 7 against the surviving handoff, or to a cold start. Coherent. |
| "No new external surface" | TRUE. No network calls, no binaries, no credentials, no formats read from outside the repository. |

## Required Changes

1. **Name `references/parent-skill-security.md` as an edited file, in
   Layer 1 and in Implementation Phase 1.** The design calls the slug
   re-validation extension "the single most important security item in the
   change", and the enumeration it extends exists in exactly one place —
   the Slug Re-Validation on Resume section of
   `references/parent-skill-security.md`. Solution Architecture's Layer 1
   lists `parent-skill-pattern.md`, `parent-skill-state-schema.md`, and
   `parent-skill-resume-ladder-template.md`; the security reference appears
   nowhere in the design. Implementation Approach puts "the slug
   re-validation extension" in Phase 2 (the parents), which is the wrong
   layer for a pattern-level enumeration and would leave the pattern
   enumerating two slots while the parents implement three. State the edit
   as three sites: the pattern-level enumeration, `/scope`'s
   `phase-resume.md` (which restates the rule under Slot 6 and needs it
   under Slot 7), and `/charter`'s `phase-resume.md` (which restates it
   nowhere and needs a first statement covering its new row 8.5).

2. **Narrow the Phase 1 bail test by the parent's whole `wip/` prefix, not
   by the state file alone.** The design says "narrow the wip-state test to
   exclude the parent's own state file", singular. The live rule (`/scope`
   SKILL.md L443-448) tests "any wip state exists for the topic (the state
   file, any child intermediate, or any research scratch)". A handoff-fed
   run is the first case in which a Phase 1 bail happens with a
   non-state-file artifact already on disk under the parent's own prefix,
   and it is the case this change creates. An implementer who excludes only
   `wip/scope_<topic>_state.md` and then reads `wip/scope_<topic>_handoff.md`
   as "wip state for the topic" reproduces the exact defect being fixed —
   `abandonment-forced`, a `triggering_child` no child took part in, and an
   R9 violation — reachable only via the new path. Word the narrowed test
   positively: the bail routes to abandonment-forced only on a child
   intermediate (`wip/{brief,prd,design,plan}_<topic>_*`) or research
   scratch (`wip/research/{prd,design}_<topic>_*`); nothing under the
   parent's own `wip/scope_<topic>_*` prefix counts. Mirror the wording
   against `/charter`'s Step 2, which already tests exactly that way.

3. **Scope the clean-cancel deletion to the state-file path, and state the
   handoff carve-out where a sweep would find it.** This is Required Change
   2's mirror image and the two are easy to get backwards. The bail *test*
   must ignore the whole parent prefix; the bail *deletion* must remove only
   `wip/scope_<topic>_state.md` and leave `wip/scope_<topic>_handoff.md` in
   place, which is what the design intends ("leaving it is what makes a
   later invocation reach Slot 7 rather than starting cold") but never says
   in deletion terms. Since `/scope`'s enumerated set and its Phase 4 sweep
   are both written as the prefix `wip/scope_<topic>_*`, an implementer
   reading "the bail handler disposes of the parent's wip state" will sweep
   the prefix and destroy the handoff. State the carve-out explicitly and in
   the same shape the `docs/folds.md` carve-out already uses — the design
   correctly cites that precedent for the enumeration, and it applies just
   as directly to the non-sweep. While there, resolve two consequences the
   design leaves open: (a) `/charter`'s set is a closed list of five
   concrete paths with no prefix wildcard, so it gains
   `wip/charter_<topic>_handoff.md` *and* a count change from "exactly five
   places" to six; (b) `/scope`'s Phase 4 removes `wip/scope_<topic>_*` on
   *every* exit including `abandonment-forced`, whose carve-out preserves
   child wip for resumability — so the handoff dies on the one exit that
   exists to be resumed. That is benign, because an abandonment-forced
   resume hits Slot 5 against the force-materialized Draft and never reaches
   Slot 7, but the design should say so rather than leave the reader to
   derive it. If any of the three restatement sites is edited, all must be:
   `/scope` SKILL.md L789-852 is authoritative and warns that
   `phase-3-exit-finalization.md` and `phase-4-cleanup.md` must not diverge.

4. **Name the framing-shift answer in the Security Considerations section
   as the one handoff field that reaches a gate, and bind the control.**
   The section's untrusted-input paragraph accounts for shell arguments,
   file paths, frontmatter, and the predicate estimates, and stops there.
   The framing-shift answer is none of those: per
   `phase-1-discovery.md`, a positive answer is the override that fires
   `/brief` against an Accepted BRIEF at the canonical path — that is, the
   one handoff-carried value that can defeat re-entry protection, and the
   only one not re-derived later. The Mitigations paragraph's "a malformed
   or stale handoff degrades to a discovery conversation with a wrong prior
   rather than to a parent acting on false filesystem beliefs" is true of
   the predicates and silent here. State that the pre-supplied answer is
   never accepted as recorded state, that the confirmation is mandatory
   rather than a formality, and that the author's response is what gets
   recorded — the design already says this under "What pre-loaded means";
   the security section needs it as a control, not as an ergonomics note.
   Severity is low and the reason can be stated: `/brief`'s own resume
   ladder offers revise-or-start-fresh against an Accepted BRIEF, and its
   Phase 5 requires explicit human approval for Draft → Accepted, so the
   worst case is a nudged prompt, not a clobbered artifact. Say that; it
   turns an unaddressed surface into a bounded one.

5. **Fix the visibility argument: credit the never-planned rule, and bind
   the optional free-text sibling.** Two defects in one paragraph. First,
   "A closed enum makes the leak impossible for every future feeder" is not
   what the enum does. `chain_skipped[]` entries key on `child:`, so
   recording a private-only child names it regardless of what the reason
   field contains; the mechanism that actually prevents the leak is the
   pattern-level never-planned rule
   (`references/parent-skill-pattern.md` L215-232: a child whose gate never
   opened produces no entry, and the stated skip is conversational and
   "never recorded"). What the closed enum genuinely buys is that the reason
   field of a *recorded* skip can no longer carry arbitrary prose, and that
   it becomes re-validatable. Both are real; claim those. Second, Decision 5
   ships "an optional free-text sibling that is never the ground" alongside
   the enum, and the Security Considerations section does not mention it at
   all — so the same paragraph that argues free text is what makes the
   guard unenforceable ships a free-text field into the same durably-public
   record. State that the optional detail field is bound by the same
   visibility discipline as `rejection_rationale` already is in
   `/charter`'s `phase-finalization.md` L816-823 (no secrets, no
   customer-identifiable context, no unpublished competitive positioning,
   and no private artifact named from a public repo), and that it is
   advisory-only: a grep asserting membership in the closed set reads
   `reason`, never the sibling.

## Optional Improvements

1. **Add `chain_skipped[].reason` to the state-file enum re-validation
   list.** Closing the vocabulary converts a free-text field into an
   enum-typed one, and `references/parent-skill-security.md`'s State-File
   Enum Re-Validation section is written to apply to "all enum-typed
   state-file fields" and then enumerates the known ones (`boundary:`,
   `decision_record_sub_shape:`, `triggering_child:`,
   `plan_execution_mode:`). Naming the new enum there costs a clause and
   makes the surface's coverage checkable rather than inferable. Low value
   on its own — the field does not reach a shell command — but it is the
   difference between a list a reviewer can read and a list a reviewer must
   reconstruct.

2. **Say what a `/scope` clean-cancel leaves on the branch.** After
   Required Change 3, a clean-cancel deliberately leaves
   `wip/scope_<topic>_handoff.md` on disk and Phase 4 never runs. That is
   correct for resumability and it does collide with the workspace
   wip-hygiene rule, which requires every `wip/` file to be removed before a
   PR can merge. The collision is not new — `abandonment-forced` already
   defers cleanup on the same reasoning, and `phase-4-cleanup.md` L80-86
   handles it by observing that the abandoned state is by construction not a
   mergeable state — but the design should make the same observation for
   clean-cancel rather than leave a reviewer to notice an orphan wip file
   with no stated owner.

3. **Note the write-direction inversion in one sentence.** The chosen path
   shape means `/explore` writes into each parent's `wip/` namespace. The
   design argues the alternative at length in terms of what parents would
   have to admit into their sets and never states the converse plainly. One
   sentence saying that `wip/<parent>_<topic>_*` is now written by two
   skills, and that this is acceptable because the parent composes and
   validates the path independently and `/explore` declares no closed set of
   its own, would close the question a reviewer will otherwise ask twice.

4. **Consider a provenance line in the handoff skeleton.** The design lists
   "provenance" among the six shared sections without saying what it
   carries. If it carries the producing command and a timestamp, a parent
   can announce what it is acting on and an author can recognize a handoff
   that is months stale or that they did not produce. Not a control — a file
   can lie about its own provenance — but it makes the announcement the
   design already requires at Slot 5 more informative, at no cost.
