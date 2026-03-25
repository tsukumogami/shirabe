<!-- decision:start id="classification-trigger-adversarial-lead" status="assumed" -->
### Decision: Classification Trigger for the Adversarial Demand-Validation Lead

**Context**

The `/explore` skill dispatches parallel research agents in Phase 2, one per lead produced during Phase 1 scoping. The proposed adversarial demand-validation lead would fire as one of those agents — asking "is there real demand for this?" on directional (zero-to-one) topics. The trigger must be conditional: always-on would produce Phase 3 noise on diagnostic topics and train users to ignore the adversarial section over time, which defeats its purpose.

Research confirmed two structural facts that shape the decision. First, latency is not a differentiator: Phase 2 runs agents in parallel, so an always-on adversarial agent adds zero wall-clock cost. The choice between options rests entirely on signal quality and UX. Second, `/explore` is already directional-biased by routing — diagnostic users typically reach for `/work-on`, not `/explore`. This lowers the false-positive exposure and raises the acceptable false-negative tolerance compared to what the question framing implies.

The cost asymmetry is decisive: a false positive (fires on diagnostic topic) adds noise, causes the synthesis phase to dismiss a null finding, and degrades trust in the adversarial section. A false negative (misses a directional topic) means exploration proceeds without challenging the premise — recoverable in later phases, but the bigger risk on genuinely uncertain directional topics. Given this asymmetry, the threshold for firing should be conservative: ambiguous topics (migration, refactor, "improve X") default to not firing.

**Assumptions**

- Phase 0's triage output (specifically, the `needs-prd` routing) is a reliable proxy for "directional topic" when entering from an issue.
- The Phase 1 conversation reliably surfaces whether a topic has an existing broken behavior vs. additive intent — the distinction is classifiable from the scope file's "Core Question" and "Context" sections.
- Ambiguous topics (migration, refactor, improve X) will be more common than missed genuinely-uncertain directional topics, making conservative defaulting the right asymmetric choice.
- In `--auto` mode, Phase 1 runs a compressed scope conversation that still reveals enough intent signal to classify topic type; when no conversation is possible, label signals (or absence thereof) govern.

**Chosen: Option B — Label + conversation signal (two-gate trigger)**

The adversarial lead fires under two conditions, evaluated in order:

1. **Pre-conversation gate (label-based):** If entering from an issue with the `needs-prd` label, the adversarial lead is added to the scope file before Phase 2 without waiting for Phase 1 conversation output. `needs-prd` means "requirements unclear or contested" — which is a reliable proxy for directional topic. If entering from an issue with the `bug` label, the lead is explicitly skipped (reliable diagnostic proxy). `needs-design` and other labels defer to the post-conversation gate.

2. **Post-conversation gate (scope-based):** At the end of Phase 1, before writing the scope file, the orchestrator classifies topic type from what the conversation revealed. The classification uses three signals in combination:
   - **Intent signal**: additive phrasing ("I want to add / build / support...") vs. corrective phrasing ("X is broken / failing / incorrect...")
   - **Problem statement presence**: diagnostic topics almost always surface a concrete broken behavior; its absence is a positive directional signal
   - **Hedged intent**: if the user phrases goals as "maybe" or "should we...", that is a directional signal

   The threshold is conservative: classify as directional only when two or more signals align. Ambiguous topics (migration, refactor, "improve X") classify as not directional unless the intent signal is explicit and strong.

**Visibility at Phase 1 checkpoint:** The adversarial lead is named in the Phase 1 checkpoint summary when it fires — listed as a research lead like any other, phrased as "Is there evidence of real demand for this, and what do users do today instead?" This sets clear expectations and avoids surprising users when Phase 3 findings challenge the premise. It is not presented as an adversarial or challenging frame; it's framed as a validation question.

**`--auto` mode behavior:** In `--auto` mode, Phase 1 conversation is skipped or compressed. The trigger falls back to the pre-conversation gate only: fire if `needs-prd` label present; skip if `bug` label present; for all other cases (no issue, or `needs-design` / no label), default to not firing. This is consistent with the conservative threshold — when no conversation signal is available, ambiguous topics should not trigger the adversarial lead.

**Rationale**

Option B combines the strongest signal available before the conversation (issue labels) with the richest signal available after it (scope conversation output), applied at the right moment in each case. Label-only (Option A) leaves free-text directional topics unserved and never fires without an issue entry point — a significant gap when users invoke `/explore` directly on a topic string. Conversation-only (Option C) forces Phase 1 to run a full scope conversation even when a `needs-prd` label already resolves the question cleanly, adding unnecessary friction. Topic string heuristics (Option D) are unreliable as a primary signal: "add a workaround for the broken parser" reads as directional but is diagnostic; "fix how we handle new user onboarding" reads as diagnostic but addresses an improvement. The two-gate structure of Option B reuses existing classification machinery (Phase 0 triage labels, Phase 1 scope conversation) without inventing new logic, which is consistent with the constraint to reuse existing mechanisms.

**Alternatives Considered**

- **Option A — Label-only trigger**: Fire iff `needs-prd` label present; never fire without an issue entry point. Rejected because free-text topic invocations (no issue) are a common entry point for `/explore`, and the label gate would never fire for them. A directional free-text topic like "add adversarial demand validation" would always miss the adversarial lead under this option.

- **Option C — Conversation signal only**: Phase 1 always runs full conversation, classifies post-scope; labels inform but don't trigger alone. Rejected because it ignores the `needs-prd` label — the strongest available pre-conversation signal — forcing an unnecessary conversation when the classification is already settled. It also makes `--auto` mode behavior undefined (no conversation to classify from).

- **Option D — Topic string heuristic**: Keyword pattern matching on "add/build/new" vs "fix/debug/why" as the primary signal. Rejected as unreliable for primary classification. Research confirmed: "add a workaround for X" starts with a directional verb but is diagnostic; "fix how we onboard new users" starts with a diagnostic verb but is directional. String heuristics can serve as a weak tiebreaker within the post-conversation gate but should not be the primary mechanism.

**Consequences**

What changes: Phase 1 gains a classification step at the end of scoping — a few sentences of internal reasoning before writing the scope file — and the scope file gains a `Topic Type` field that Phase 2 reads as the trigger condition. Phase 0's label-checking logic is extended to forward `needs-prd` as a pre-set directional classification. No Phase 2, Phase 3, or resume logic changes; the adversarial lead enters the scope file like any other lead, and Phase 2 dispatches it automatically.

What becomes easier: Phase 2 dispatch requires no new branching — the lead either exists in the scope file or doesn't. Phase 3 synthesis is clean because the adversarial lead only appears when it's warranted.

What becomes harder: The classification step in Phase 1 requires the orchestrator to make a judgment call on topic type based on conversation output. For genuinely ambiguous topics, this judgment is imperfect. The conservative default (don't fire) means some directional topics on ambiguous verbs ("migrate", "refactor") will miss demand validation. This is the accepted trade-off given the cost asymmetry.

<!-- decision:end -->
