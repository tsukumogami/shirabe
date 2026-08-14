# Completeness Verdict — PRD-upstream-link-legality

**Verdict:** PASS

Both second-round items are applied and correct, and nothing I previously
verified as holding has been disturbed.

## Claim verification

### R5.2's DESIGN attribution — **FIXED, AND NOW EXACT**

The revised text separates what `pipeline-model.md` says outright from what it
implies, and both halves check out:

- "states outright that a BRIEF's upstream is a ROADMAP" — the file's chain
  diagram reads "Brief (upstream: Roadmap, per feature)" and the prose adds
  "`/brief` crosses that boundary by taking a Roadmap as its upstream."
  Accurate.
- "and that a PRD's is a ROADMAP when no BRIEF was written" — near-verbatim:
  "A feature framed directly in its PRD has no BRIEF, so that PRD's upstream is
  the Roadmap." Accurate. `prd-format.md:27-29` does repeat it.
- "The DESIGN case is not stated outright but follows from the same file's
  nearest-produced rule — each artifact names the nearest artifact actually
  produced above it" — this is the correct sentence to lean on
  ("Each artifact's `upstream` field points to the nearest artifact actually
  produced above it, and the field is omitted when nothing was"). The
  misattributed PLAN sentence is gone.
- "exercised today by the cascade's short-chain design fixture and its matching
  test scenario" — `skills/execute/evals/fixtures/designs/DESIGN-cascade-test-short.md:3`
  carries `upstream: skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md`,
  and `run-cascade_test.sh` Scenario 1 builds `PLAN → DESIGN → ROADMAP` with the
  DESIGN carrying the pointer. Both exist as described.

The added sweep obligation — after the change no format or pipeline reference
documents a ROADMAP as a legal upstream for a BRIEF, a PRD, or a DESIGN — is the
right closure. It converts R5.2 from an observation about three changed rows
into a checkable instruction covering `pipeline-model.md` and `prd-format.md`
together, which is what the "encodes rather than changes" sentence was missing
two rounds ago.

### R22's fifth row — **PRESENT AND ACCURATE**

The added row names `skills/scope/evals/evals.json` /
`pre-authoring-notice-cold-start` and describes the assertion correctly: the
eval (id 25, `evals.json:373`) quotes the notice verbatim including "re-invoke
as `/scope inline-diff --upstream <path-to-the-ROADMAP>` and this chain will
attach the BRIEF to it." Disposition "reworded: the chain attaches the PLAN" is
the right call under R13 and R14.

The parenthetical about the prose is exact rather than approximate: the sentence
is committed at `skills/scope/references/phases/phase-1-discovery.md:304` and
`:341` — twice, as R22 says, and nowhere else in the tree.

R22's opening line reads "Five skill eval expectations," and the acceptance
criterion at line 378 reads "The five eval expectations named in R22 are
updated, and no eval outside that list changes." Count and criterion agree.

The other four rows are unchanged and were verified last round against the live
eval files.

### Two incidental improvements, both verified

Neither was requested; both are correct and worth recording.

**R21's check-code collision clause.** The new sentence — the two new codes may
not be `R5` or `FC99` — is grounded. `crates/shirabe-validate/src/validate.rs:523`
asserts `["L01", "L05", "FC1", "FC99", "R5", "IO", "fc01", ""]` are all
*unknown* codes, so naming a new check `R5` or `FC99` would break that existing
test and violate R21's own no-test-modification rule. Real hazard, correctly
fenced. (The same test fixes the known set as `SCHEMA`, `FC01`-`FC16`,
`FC-CONVENTIONS`, `R6`-`R9`.)

**R23's new-shape fixture chain.** R23 now adds a new-shape fixture chain beside
the two frozen ones, and R22's cascade row says the rewritten eval runs against
it. That resolves a tension I had not flagged: previously R22 rewrote the
full-chain cascade eval while R23 froze the very fixtures that eval runs
against. The two are now consistent.

### Previously verified claims — **ALL STILL HOLD**

Spot-checked after the edit, since renumbering and a table rewrite were
involved:

- R5's eight-row parent-set table is byte-for-byte what I verified: VISION←VISION,
  STRATEGY←VISION, ROADMAP←STRATEGY, BRIEF←none, PRD←BRIEF, DESIGN←{PRD, BRIEF},
  PLAN←{DESIGN, PRD, BRIEF, ROADMAP}, COMP←none.
- R5.1 and R5.3 are intact and unchanged.
- R24's eight rows and its trailing counts (73 legal edges under `docs/`, 68
  documents with no field) are undisturbed.
- R2's lifetime classes, R8's no-indexing claim, R9/R10, R25's exit-0 baseline,
  R21's golden-corpus assertion (which survives because
  `expected/real/PRD-roadmap-skill.md.stdout` is a schema-missing skip), and
  Known Limitations' three-versus-zero corpus yield all stand as verified in
  earlier rounds.

## Coverage

Every brief IN item maps to a requirement; both of the brief's deferred Open
Questions close in Decisions and Trade-offs; no brief OUT item has been
absorbed. The three producers that would otherwise emit forbidden links are each
named — `/brief` (R13), `/plan` as the new carrier (R14), `/explore` → `/roadmap`
(R15) — and each has an acceptance criterion.

## Gaps / scope creep

None that block. One standing note, unchanged from last round and not a defect:
no eval covers R14's new `/plan --upstream` surface. Adding a scenario is not
"changing an eval outside the list," so it does not conflict with R22's
acceptance criterion, but the flag ships ungraded unless one is written.
