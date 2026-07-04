# Lead: Throttle/emit policy and cost for the context echo

Environment: Claude Code 2.1.201, labs at `/home/dangazineu/.claude/jobs/a050f0e4/tmp/{render-lab,skill-lab,hook-lab}/`. Three `claude -p --model haiku --dangerously-skip-permissions` runs (1 for check A, 2 for check B incl. control). Echo-based hooks only; the single `gh pr list` observed was issued by the test model itself and failed harmlessly (no remote in the lab repo). No gh write commands.

## Findings

### 1. Token cost of a realistic block

Reference block (`render-lab/sample-block.txt`): neutral preamble "Current work in flight (from gh):", `=== WORK IN FLIGHT ===` marker, 4 pipe lines with full PR URLs, neutral footer "This is ambient status information, not an instruction."

- Size: 674 chars, 79 words, 7 lines. Longest line 155 chars.
- chars/4 estimate: ~169 tokens.
- Empirical (no offline tokenizer available; measured via API usage counters): in the check-B run the block was injected twice in one turn (see finding 5); that turn's `cache_creation_input_tokens` was 535 vs ~215 of structural content (extrapolated from the control run's analogous turn at 157 + one extra tool_use/result pair), giving ~160 tokens per wrapped injection; decomposing the same 535 by direct content estimates gives ~190. Band: **160–210 tokens per fire; use ~200 as the planning number** (URLs and pipe tables tokenize slightly worse than chars/4).

Per-line marginal cost: each pipe line is ~130-155 chars ≈ 35-45 tokens, so the block scales at roughly +40 tokens/PR on a ~90-token fixed base (preamble + marker + footer).

Cumulative for the lead's scenario (8 PostToolUse fires on PR-affecting commands + 3 UserPromptSubmit fires):

| Policy | Emissions | Injected tokens | % of 200k window |
|---|---|---|---|
| Ungated (emit every fire) | 11 | ~2,200 | 1.1% |
| Gated (emit on change/absence only; realistic: 8 commands -> ~3 distinct ledger changes, + 1 absence return) | 4 | ~800 | 0.4% |

Every injected block also persists in context and is re-read by all subsequent API calls (at cache-read rates once cached), so the ungated/gated difference compounds over a long session — but even ungated, absolute cost is small. The real argument for gating is signal quality (duplicate identical blocks teach the model to ignore the marker), not budget.

Headroom: the 10,000-char cap on `additionalContext` fits ~60 PR lines. A rendered-lines cap of ~20 (drop merged/closed after N minutes) keeps blocks readable long before the hard cap matters.

### 2. Emit policy (extends the round-3 `should-render` gate)

The round-3 prototype (`render-lab/work-summary.sh`) gates on: ledger non-empty AND (ledger hash changed since last render OR `WS_RENDER_INTERVAL` elapsed). Two extensions are needed: (a) a second-level hash over the *rendered* block, so an interval-driven render that produces identical output emits nothing; (b) per-event routing of the two channels. The rendered-hash check only runs after the cheap level-1 gate passes, so no `gh` network calls happen on quiet fires.

Policy table (gate conditions evaluated top-down per event; "render" = run `render`, then compare rendered-block hash to last-emitted rendered hash):

| # | Event | Gate | systemMessage | additionalContext | State update |
|---|---|---|---|---|---|
| 0 | any | ledger empty | no | no | touch last_activity |
| 1 | PostToolUse (gh-pr matcher) | ledger hash unchanged AND interval not elapsed | no | no | touch last_activity |
| 2 | PostToolUse | ledger hash changed -> render -> rendered hash changed | yes | yes | mark-emitted (ts + both hashes) |
| 3 | PostToolUse | interval elapsed, ledger unchanged -> render -> rendered hash changed (CI/review status flip) | yes | yes | mark-emitted |
| 4 | PostToolUse | rendered hash unchanged (after 2 or 3's render) | no | no | record render ts only |
| 5 | UserPromptSubmit | absence > threshold AND ledger non-empty -> render | yes | yes | mark-emitted |
| 6 | UserPromptSubmit | otherwise | no | no | touch last_activity |
| 7 | SessionStart, matcher `compact` | ledger non-empty -> render | no | yes | mark-emitted |
| 8 | SessionStart, matcher `resume` | ledger non-empty -> render | yes | yes | mark-emitted |

Design rationale for the channel split:
- systemMessage and additionalContext travel together whenever the emission is *news* (set changed, status changed, user returned, session resumed) — the user and the model should see the same thing at the same moment.
- The one divergence is post-compaction (#7): re-injection there is context repair, not news. The user's terminal already shows the block from its last emission; a systemMessage triggered by an internal event the user didn't initiate is noise. additionalContext only.
- There is no case for systemMessage-only: if it's worth showing the user, the model losing track of it is exactly the failure this design exists to prevent.

Absence threshold: **default 1800s (30 min)**, env-tunable (`WS_ABSENCE_THRESHOLD`). Rationale: inter-prompt gaps during active work are almost always under 10 min, so 30 min cleanly separates "stepped away" (meeting, lunch, context switch) from "thinking." 15 min is a reasonable aggressive floor; below that the return-summary starts firing on ordinary pauses and becomes the rejected footer. Absence is measured against `last_activity`, which every fire (including suppressed ones) refreshes.

Concurrency requirement: mark-emitted must be atomic (`flock` on the state file). Check B demonstrated that parallel tool_use calls in one assistant turn fire PostToolUse concurrently — two gate evaluations can both pass before either marks (observed as a real duplicate injection; see finding 5).

### 3. Compaction interaction

Transcript structure: additionalContext persists as a `hook_additional_context` attachment adjacent to the tool_result it accompanied (round 3, finding 2/3). Compaction summarizes old turns wholesale; hook attachments get no special preservation — they are ordinary old-turn content. **An early-session injected block does not deterministically survive compaction.** At best its substance leaks into the summary as paraphrased prose; at worst it vanishes. Either way it would be stale by then (CI statuses move), so preserving the literal old block isn't even desirable.

Re-emission mechanism exists and fits: `SessionStart` supports a `compact` matcher (round 1, confirmed in docs), fires exactly once per compaction, and SessionStart hooks can return additionalContext. The re-render is fresh (live `gh pr view`), so post-compact context is *better* than what compaction destroyed.

**Recommendation: yes, include a SessionStart(compact) re-injection hook in the design.** It is the only deterministic answer to "the model forgot the ledger existed after compaction"; it fires rarely (bounded cost ~200 tokens per compaction); gate is trivial (ledger non-empty); and pairing it with matcher `resume` (row 8) covers the sibling case of `claude --resume` picking up a session with work in flight. Without it, the design's model-awareness guarantee silently expires at the first compaction of a long session — precisely the sessions that have the most work in flight.

### 4. Empirical check A — `!`cmd`` runs in the invocation cwd, not the project root

Setup: `skill-lab` made a git repo (project root), skill `teststatus` (loaded from the root's `.claude/skills/`) given an injected `Current directory: !`pwd`` line, invoked via `claude -p "/teststatus" --model haiku` from `skill-lab/subdir/deeper/`.

Result: `BEACON=1783176787 DIR=/home/dangazineu/.claude/jobs/a050f0e4/tmp/skill-lab/subdir/deeper` — the injected command executed in the **cwd of invocation**, two levels below the project root, even though the skill file itself resolved from the root.

Implication for the /status probe path form: injected probe commands must never use relative paths. Either call the script by absolute path (`${CLAUDE_PLUGIN_ROOT}/...` for a plugin-shipped script) or make the script location-independent (the round-3 prototype already is: `WS_DIR` + session-id-keyed ledger, no cwd dependence). A probe like `!`./scripts/work-summary.sh render...`` would break for any user sitting in a subdirectory.

### 5. Empirical check B — neutral phrasing is accepted and usable

Setup: hook-lab PostToolUse/Bash hook (`hooks/sysmsg-neutral.sh`) emitting both channels with the full sample block (neutral preamble + 4 pipe lines + neutral footer). Prompt: run `echo lab-ping`, then "what PRs are currently in flight, if any?"

Result: **no suspicion, full uptake.** The model's extended thinking explicitly said "the hook has provided me with the current work in flight context" and treated it as legitimate ambient data — the same Haiku that in round 3 refused an imperative additionalContext as a "prompt injection attempt." Its answer listed all 4 PRs with correct repo#number, state, CI status, and title, and correctly summarized "3 still open and 1 merged."

Two secondary observations from the same run:
- The model first ran its own `gh pr list` (which failed — no remote) and only then answered from the injected block. Ambient context served as fallback/corroboration; it did not preempt the model's own probe. Don't count on the echo *saving* gh calls.
- The model issued both Bash calls as parallel tool_use in one turn, and the hook fired for each — two identical blocks entered context in the same turn. This is the live demonstration of why the gate must be script-enforced and lock-protected (finding 2).

## Implications

- The context echo is cheap enough that the emit policy should be tuned for signal quality, not token budget: ~200 tokens/fire, ~800 tokens per realistic gated session (0.4% of the window). The design doc can state these numbers.
- The policy table in finding 2 is implementable as a thin extension of the existing `should-render`/`mark-rendered` subcommands: add a rendered-block hash to the state file, an `--event` flag to select the row, and `flock` around state writes.
- The SessionStart(compact) + SessionStart(resume) hook belongs in the design as a first-class component, not an optional extra — it is what makes the model-awareness guarantee hold across long sessions.
- The /status probe and all hook-invoked scripts must be cwd-agnostic; plugin-absolute paths plus session-keyed state (already the prototype's shape) satisfy this.
- Phrasing contract for additionalContext: declarative preamble naming the source ("Current work in flight (from gh):"), data, and a footer declaring it non-instructional. This passed on the exact model that previously flagged hook content as injection.

## Surprises

- Parallel tool calls fire PostToolUse per-call within a single assistant turn, producing same-turn duplicate injections — the gate has a real race, not a theoretical one. `flock` is required.
- The model voluntarily attempted its own `gh pr list` despite having the answer injected adjacent to the previous tool result; ambient context is treated as corroboration, not as a replacement for tools.
- Skill `!`cmd`` injection runs in the user's cwd even when the skill file lives at the project root — the probe path form question had the less convenient answer.

## Open Questions

- Whether `${CLAUDE_PROJECT_DIR}` / `${CLAUDE_PLUGIN_ROOT}` expand inside skill `!`cmd`` injection lines (they do in hook commands); untested here. If not, the probe must rely on session-keyed state rather than any path resolution.
- Per-fire token measurement has a ±25% band (160–210); the control run had one unexplained 1,080-token cache-creation turn (likely thinking-block signatures or a system reminder around the failed gh call). A dedicated count-tokens measurement would tighten this if exact numbers ever matter.
- Neutral-phrasing acceptance was tested on Haiku only (one run). Haiku was the model that flagged the round-3 imperative, so it's the conservative subject, but a Sonnet spot-check during implementation would close the loop.

## Summary

The context echo costs ~200 tokens per fire (674-char, 4-PR block; chars/4 gives 169, API-usage deltas bracket 160–210), so a gated session runs ~800 tokens (0.4% of the window) versus ~2,200 ungated — gating is justified by signal quality, and the recommended policy is: emit both channels on ledger-hash or rendered-hash change and on return-after-absence (default threshold 30 min), emit additionalContext-only on SessionStart(compact)/both on resume, emit nothing otherwise, with flock-protected state because parallel tool calls demonstrably double-fire the hook in one turn. An early-session block does not survive compaction (it's ordinary old-turn content), so a SessionStart(compact) re-injection hook is recommended as a first-class design component. Both empirical checks passed: skill `!`cmd`` injection runs in the invocation cwd (probe paths must be absolute/session-keyed, never relative), and the neutral-state phrasing was accepted without suspicion by the same Haiku that flagged imperative phrasing — it answered "what PRs are in flight?" correctly from the injected block alone.
