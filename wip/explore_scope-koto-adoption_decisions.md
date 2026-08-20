# Exploration Decisions: scope-koto-adoption

## Phase 1 (scoping)

- Both adoption shapes are in scope and get ranked by evidence: koto as
  `/scope`'s own phase substrate with inline child dispatch, and the full
  materialized binding. The prior exploration priced only the second and never
  asked whether the first is a legal koto shape. Costs one lead; forecloses
  nothing.
- `/charter` is investigated for whether the two parents may diverge on
  substrate, and is not committed to the adoption. It has no reported failure
  driving it, and answering the conformance question is cheap while committing
  it is not.
- The adversarial demand lead is skipped: issue #331 carries the `bug` label,
  which the Phase 1 label pre-gate resolves as an explicit skip.
- The framing and prose content rides inside this effort rather than being
  treated as superseded by the koto adoption, because koto governs when a
  directive arrives and never what it says.

## Round 1

- The sourcing property stays dropped. Round 1 added no evidence for it and
  removed the last reason to reach for it: no fresh-child context boundary
  exists anywhere in the repo, so there is nothing to withhold anything from.
- The prior run's deciding obstacle is retired. `/scope --auto` runs the whole
  chain with no author, `/prd` states that `/scope` pre-populates nothing for
  it, and `/charter` serializes parent conversation into a child under the
  inline binding. The obstacle was a reading of a long reference file rather
  than a property of the skill.
- The gating claim is restated downward rather than dropped. "The parent cannot
  skip a hop and still finish" is falsified by `koto next --to` and
  `koto overrides record`. What is claimed instead: a skipped hop stops being
  indistinguishable from compliance, because it leaves a typed event koto
  authored.
- **The author ruled that the surviving gating value counts**, on the grounds
  that a trace the agent did not author is different in kind from a post-hoc
  checker: no checker runs, nothing grades the agent, and a bypass is a
  deliberate command carrying a rationale rather than silence. This keeps
  gating in the case at reduced strength and keeps the effort clear of the
  deterministic-validation shape ruled out on #320.
- The koto case is argued as a conjunction, not as either half. Disclosure alone
  is reachable by relocating two sections into `phase-2-chain-orchestration.md`
  with no new dependency; gating alone is legibility. The dependency is
  justified by physical absence plus a state machine that must be bypassed by a
  named command.
- Shape (a), the phase substrate, is the working shape. It is the base case that
  materialization extends by one state rather than a rival to it, costs one
  template instead of four, leaves the Dispatch Contract untouched, and does not
  foreclose materializing children later.
- Premise-versus-verdict is extended to four categories: premise, verdict,
  bound, obituary. The binary would not classify two of the draft's five items,
  and bounds turn out to be most of what belongs in the bootstrap while
  obituaries are most of what should be deleted.
- **The author elected one narrow round 2** on exit finalization rather than
  crystallizing after round 1. Every disclosure argument so far concerns the
  chain-proposal decision and the Phase-2 judgment; #331's fabricated Status
  section was written at exit finalization, which no round-1 lead examined. It
  decides whether the adoption fixes the reported incident or an adjacent one.
- **The author elected to file the live defects found in round 1 as separate
  issues** rather than folding them into this effort or recording them only.
  `work-on.md:125` is degrading real `/work-on` runs today, and the fixes are
  independent of the adoption decision.

## Round 2

- Round 2's founding premise is withdrawn. #331's fabricated Status section was
  written at the `/plan` hop inside Phase 2, not at exit finalization. Round 1's
  disclosure lead asserted the latter and it was taken at face value; two
  round-2 leads falsified it independently, and the issue text says so in its
  own second paragraph. Recorded as a method note: the primary source was
  available the whole time.
- The recorded round-1 tension is resolved rather than carried. Deferring the
  reduction argument to the judgment state does reach the site of the incident,
  so the disclosure case is aimed correctly.
- Phase 3 is ruled out as a place to intervene. It carries no argument, reads no
  filesystem on the exit path the incident took, and writes nothing into the
  PLAN. A koto state there would sequence a transcription.
- The disclosure claim is restated at its true strength: what koto buys is that
  the *general* form of the reduction argument never enters the transcript, not
  that a delivered argument can be withdrawn from one. The scoped form must
  still be delivered at the judgment, and can still be restated afterward.
- Context economy is withdrawn as a reason to adopt. Measured, the net delta at
  end of run is about zero and plausibly negative. Any artifact this effort
  produces must not claim koto reduces total resident context.
- The gating claim is amended a second time, on durability. koto's event log is
  deleted at the terminal tick by default and is rewritable while it lives, so
  "a log the agent does not author" holds for the writer and not for the
  artifact. `--no-cleanup` is a requirement rather than an option, and the
  `/workflows` render is the surface that survives unaided.
- `/workflows` is accepted as the reader that closes round 1's "who reads the
  log" question. It is native, on by default, and rendered the #331 signature in
  four lines with no skill and no reader written for it.
- The R9 `full-run` predicate gap is recorded as a finding for other work rather
  than proposed here. Whether a one-line self-consistency condition counts as a
  checker under the author's exclusion is the author's call, and this effort
  does not need it.
- Terminal states are ruled out as a binding surface. They can require nothing,
  refuse nothing, and say nothing. Any binding `/scope` wants belongs on the
  pre-terminal `finalize` state, in an agent-proposes / koto-vetoes shape.
