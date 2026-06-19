**Verdict:** PASS

# Architecture Review — DESIGN-lifecycle-posture-mode

Scope: Solution Architecture and Implementation Approach, grounded against the
real seams (`validate.rs::is_notice`, `lifecycle.rs::run_lifecycle_check` /
`run_lifecycle_chain_check`, `gh.rs::detect_pr_context`, `main.rs` exit-code
computation, `report.rs` JSON/human renderers).

Overall: the design is implementable, the chosen seams match the real code, and
the phasing genuinely de-risks. It earns a PASS. There are **5 material
findings** — none fatal, but findings 1 and 2 should be folded into the doc
before planning, because they name call sites the Solution Architecture
currently leaves implicit and a naive implementer would miss.

---

## Q5 / Q2 (most load-bearing): does `effective_severity(code, posture)` align
with how `is_notice` and exit codes actually work today?

**Mostly yes, with one concreteness gap.** The real seam is:

- `is_notice(err: &ValidationError) -> bool` (validate.rs:35). Today every
  L-code (L01–L07) returns `false` (asserted by the test at validate.rs:241–255),
  i.e. lifecycle findings are *all* errors. FC07–FC15 / SCHEMA / FC-CONVENTIONS
  are the only notices.
- Exit code for lifecycle is computed in `render_lifecycle` (main.rs:501–524):
  iterate findings, `if !is_notice(ve) { worst = worst.merge(Violations) }`.
  For the per-file path the identical loop lives in `run_validate`
  (main.rs:436). The JSON/human envelopes derive `severity` and the
  error/notice counts from the *same* `is_notice` seam (report.rs:27–33, 68–69,
  144–145).

So the design's core claim — "replace the static `is_notice(code)` with
`effective_severity(code, posture)`, exit code = worst effective severity" — is
**structurally correct**: severity is resolved at render/exit time from a flat
`Vec<ValidationError>` carrying codes, and lifecycle findings already arrive in
exactly that shape. Resolving posture-tolerance at this seam (rather than at
finding-production time inside `run_lifecycle_check`) is the right call and
matches Decision 2B. The L01 case is correctly left alone: L01's posture
behavior is produced *inside* `run_lifecycle_check` via the `strict`→`Ready`
re-target (lifecycle.rs:845, 1105), not via severity, and the design preserves
that ("L01 keeps its existing posture re-target").

**Finding 1 (material — concreteness gap).** The Solution Architecture says
`effective_severity` "evolves the current static `is_notice`" and that the
"exit-code computation" consumes it, but it does **not** enumerate that the seam
has **7 production call sites across 3 files**, all of which must now receive
`posture`:

- `report.rs`: `severity()` (line 27), `render_json` counts (68–69),
  `render_human` counts (144–145) — JSON `severity` field + summary counts.
- `main.rs`: `run_validate` per-file loop (436, 446) and `render_lifecycle`
  (504, 512) — exit code + annotation split.
- `populate.rs:1223` — filters findings by `!is_notice(e)`.

The current `is_notice(&ValidationError)` signature takes the whole error, not
`(code, posture)`. The design's named signature `effective_severity(code,
posture)` is a different shape, and `render_json`/`render_human`/`severity()`/
`populate.rs` are not mentioned anywhere in the component list. A naive
implementer following the doc literally would change `validate.rs` and the exit
loop, then discover the JSON envelope's `severity` field and counts still call
the old posture-free `is_notice` and silently disagree with the exit code (a
draft-tolerable L02 would exit 0 but render `"severity":"error"` with
`errors: 1`). **Recommendation:** the doc should state that (a) `render_json`,
`render_human`, and the `populate.rs` filter must thread posture too, OR (b)
the per-file path keeps a posture-free wrapper (`is_notice(e)` ==
`effective_severity(&e.code, Posture::Ready)` is the natural identity, since
per-file/FC severity is posture-invariant) so only the lifecycle render path
passes a real posture. Option (b) is simpler and preserves the per-file call
sites unchanged — worth calling out as the recommended shape.

---

## Q1: Is the Solution Architecture clear enough to implement?

Largely yes. Components, the `Posture { Draft, Ready }` enum, the CLI surface,
the lifecycle threading, and the data-flow narrative are concrete and map onto
real functions. Two further gaps beyond Finding 1:

**Finding 2 (material — naming/threading collision).** There is already a
`pub enum Posture` in `lifecycle.rs:82` with five variants
(`MultiPrInFlight`, `MultiPrWorkCompleting`, `MultiPrAtMerge`, `SinglePrMidPR`,
`SinglePrAtMerge`). The design introduces a *new* `Posture { Draft, Ready }`.
Two enums named `Posture` in the same crate is a real collision the doc never
acknowledges. The new enum is the *caller-declared* posture (replacing
`strict: bool`); the existing one is the *inferred chain* posture. They are
genuinely different concepts, but sharing the name will confuse the
implementation and every future reader. **Recommendation:** name the new one to
disambiguate (e.g. `Mode`/`PostureMode`/`ReviewPosture`) or explicitly note in
the doc that the new enum supersedes nothing and lives at the CLI/threading
layer while the chain-inference enum keeps its name. Note `Mode` is already
taken by an unrelated re-export in main.rs:18, so pick carefully. This is a
1-line doc fix but a real implementer trap.

**Finding 3 (minor — advisory JSON shape underspecified).** Decision 3B says the
advisory adds "additive fields to the JSON envelope." The real envelope
(report.rs:67–116) is hand-rolled string concatenation with a fixed
`schema_version` / `summary` / `findings` shape; `summary` has exactly
`outcome`/`errors`/`notices`. "Additive, non-breaking" is achievable (append a
sibling `advisory` key), but the design should name *where* the advisory object
attaches (top-level sibling vs inside `summary`) and confirm it stays `v1` per
the SCHEMA_VERSION additive-change rule (report.rs:20–24). Since `render_json`
takes `(findings, outcome)` today, threading an `AdvisoryReport` into it is a
signature change worth flagging. Not blocking, but the "additive JSON" claim is
currently a hand-wave over a concrete renderer.

---

## Q3: Are the phases correctly sequenced and de-risking?

**Yes — this is the strongest part of the design.** Phase A (plumbing with the
draft-tolerable set empty, so `Ready`==old-strict, `Draft`==old-non-strict) is a
genuine behavior-preserving refactor: I confirmed that with the tolerable set
empty, every L-code still resolves to error (matching today's `is_notice`), and
the L01 re-target stays inside `run_lifecycle_check` keyed on `posture==Ready`,
reproducing today's `strict==true` exactly. The existing lifecycle test suite
(the 11 PRD-R10 scenarios + cycle/missing/malformed, lifecycle.rs:1376+) becomes
the Phase A green-bar. That is real de-risking, not ceremony.

Phase B (populate L02/L06/L07, add the #197 reproduction) is the only behavior
change and is isolated behind Phase A. Phase C (advisory) is correctly last
among the code phases and is verdict-orthogonal. Phase D (callers/docs/evals) is
correctly terminal. Sequencing is sound.

**Finding 4 (minor — Phase A "tests green" claim needs a caveat).** Phase A says
"land with existing tests green." But the CLI surface changes in Phase A
(`--strict` → `--mode`, deprecation alias), and existing tests/evals that invoke
`--strict` (e.g. `run-cascade.sh:298`, `lifecycle_probe`) plus any CLI-arg tests
will exercise the alias path. Phase A must therefore *also* land the
`--strict`-alias mapping and its deprecation-notice test, not just the enum. The
doc lists the alias under Phase A, so this is consistent — but "existing tests
green" understates that the alias compatibility shim is itself Phase-A-critical.
Worth a sentence so the alias isn't deferred.

---

## Q4: Simpler alternatives overlooked / overbuild?

The design is generally lean (reuses the severity seam and `detect_pr_context`
rather than widening `ValidationError` — the right rejection of Decision 2A).
One observation:

**Finding 5 (minor — advisory `GITHUB_EVENT_PATH` reader may be more than #197
needs).** The motivating bug (#197) is fixed entirely by Phase A+B (severity
downgrade of L02 under Draft). The advisory layer + `GITHUB_EVENT_PATH` draft-bit
reader (Phase C) is driven by PRD R8, not by #197. That's legitimate scope, but
the design should be explicit that #197 closes at end of Phase B and Phase C is
PRD-driven polish — so if Phase C slips, the bug is still fixed and shippable.
The current doc bundles them such that a reader might think the advisory is
load-bearing for the fix. Also: `detect_pr_context` (gh.rs:145) today reads
`SHIRABE_PR_NUMBER`/`GITHUB_REF`/`GITHUB_REPOSITORY` and never touches
`GITHUB_EVENT_PATH`; the design's "extend `detect_pr_context` to additionally
read the draft boolean" is a clean additive change to that function, but note
`PrContext` (gh.rs:75–80) is `{owner, repo, number}` with no draft field — the
struct grows or a parallel return is needed. Minor, but the "extend
`detect_pr_context`" phrasing hides a struct change. Keeping the advisory's
file-read size-bounded and parse-tolerant (as stated) is correctly scoped given
the fork-payload untrusted-input concern in Security Considerations.

---

## Security note (sanity check, not a finding)

The advisory-never-gates invariant is structurally sound *given Finding 1 is
resolved correctly*: if the JSON `severity` field is left on the old posture-free
seam while the exit code moves to `effective_severity`, the envelope and the gate
disagree — which is exactly the kind of split the Security section claims cannot
happen ("a finding's severity is resolved only by `effective_severity`"). So
Finding 1 is also the enforcement point for the stated security property. Worth
making the single-seam claim literally true by routing report.rs through the same
resolver.

---

## Recommendation

PASS. Before planning, fold in Findings 1 and 2 (enumerate the full call-site set
for the severity seam + resolve the `Posture` name collision) — both are 1–3
sentence doc edits that prevent concrete implementation traps. Findings 3–5 are
clarifications that improve the doc but don't block decomposition.
