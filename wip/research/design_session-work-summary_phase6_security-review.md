# Phase 6 Security Review (independent second pass): session-work-summary

Scope: the `## Security Considerations` section of
`docs/designs/DESIGN-session-work-summary.md`, cross-checked against the
Phase 5 integrated review (`wip/research/design_session-work-summary_phase5_security.md`),
the workspace security contract (`references/coordination-strategy.md`, F1-F4 +
inherited controls), and niwa's actual materialization/state code
(`public/niwa/internal/workspace/{state,materialize,apply,status}.go`,
`docs/guides/file-distribution.md`).

**Verdict: CONCERNS.** The section is broad and the identified controls are the
right ones. But the single most load-bearing control — fingerprint verification
before executing the repo-tree `/status` script — is specified at a level of
abstraction that an implementer can satisfy incorrectly, and one of the
"best-effort residual" framings understates a real, reachable leak on the
background-worker path. Both are fixable with tightening, not redesign.

---

## Q1 — Attack vectors not considered

The section covers the core set well: shell injection (argv arrays), URL
validation, session-id path traversal, F3 title sanitization (ANSI / newline /
pipe / marker), prompt-injection into `additionalContext`, planted-script
execution, visibility leak on both residual paths, and ledger storage isolation.
That is a genuinely complete first-order enumeration. The gaps are second-order:

1. **The background-worker final-message block is the weakest surface and gets
   the lightest treatment.** Every other surface removes the model from the
   integrity path; this one *is* the model authoring a block from PR titles it
   read. A prompt-injection payload in a PR title can induce the model to author
   a fabricated PR row, a mis-placed `=== WORK IN FLIGHT ===` marker, or
   attacker prose into the final message — which then lands on the shared Agent
   View dashboard. The design's own residual note says "no security decision is
   delegated to model interpretation of block contents," but this path
   *does* delegate block authoring to the model over attacker-influenced input.
   Not considered as an attack vector distinct from the ambient path. (See Q3.)

2. **F3 is cited for terminal sanitization, but the F3 that exists is a
   markdown/HTML escaper.** In `coordination-strategy.md`, F3 is defined as
   "escape/strip markdown/HTML control characters" for a *PR-body* context. The
   design borrows the "F3" label for a *terminal pipe-line* context that needs
   ANSI-CSI stripping, newline stripping, `|`-delimiter removal, and
   marker-substring forbidding — none of which the existing F3 validator
   necessarily does. An implementer who reuses the existing F3 routine verbatim
   would strip markdown and believe the control is satisfied while ANSI and pipe
   injection sail through. The design should define terminal sanitization as its
   own named control (or explicitly extend F3), not alias it.

3. **"Every gh-sourced field (title, state)" understates the field set.** The
   state token can fold in attacker-influenceable check names and reviewer
   handles (a malicious workflow can name a check arbitrarily). If an
   implementer sanitizes the literal `title` and `state` strings but renders
   check names / logins unsanitized, injection re-opens. The rule must be "every
   gh-sourced byte without exception," stated as a closed rule, not a
   `(title, state)` example list.

4. **Ledger unbounded-growth / dedup (robustness-adjacent).** Nothing in the
   section bounds ledger size or dedups repeated appends of the same PR URL from
   repeated `gh pr create` retries. Low security weight (DoS at most), but a
   block that grows without bound also degrades the marker's usefulness.

5. **TOCTOU on verify-then-execute (low, but real under the design's own threat
   model).** The planted-script threat explicitly includes "a malicious branch,
   PR checkout, or clone." On a host where the attacker can also write the path,
   a fingerprint check followed by a separate `exec` has a swap window. Minor
   for the branch-planting model, but the mitigation (read bytes once, execute
   from the verified copy) is cheap and worth stating.

## Q2 — Are the mitigations sufficient?

**Command injection — yes, sufficient, and I can affirm *why*.** Argv arrays
defeat shell injection outright. The remaining vector argv does *not* close by
itself is gh **flag/option injection** (a value beginning with `-` consumed as a
`gh` flag). The anchored `^https://github\.com/...` URL regex and the F2
`^[A-Za-z0-9]...` owner/repo charset both forbid a leading `-`, so the two
controls *together* close flag injection as well. So "argv array + anchored URL
regex + F2" is genuinely sufficient for injection — but only because F2's
alphanumeric-first-char anchoring is doing load-bearing work that the section
credits to F3. State that dependency explicitly (or pass `--` before positional
values as belt-and-suspenders).

**Terminal / marker spoofing — sufficient in principle, with an ordering and
scope caveat.** Strip-newlines-then-forbid-marker-substring does prevent an
attacker from opening a new standalone line carrying the marker, and pipe
removal preserves the one-line-per-PR contract. Two implementability
requirements the section omits: (a) ANSI stripping MUST precede length
truncation, or truncation can sever an escape sequence and leave a dangling ESC;
(b) the sanitization must cover *every* rendered field (see Q1.3), not the
title/state pair named.

**Fingerprint verification for `/status` execution — under-specified; an
implementer can satisfy the words and miss the control.** I checked niwa's
actual code. The mechanism the control needs *does exist*, which is good — but
the design names it ambiguously in a way that points at the wrong primitive:

- niwa records each materialized file as a `ManagedFile` with a content hash in
  `InstanceState`, persisted to `.niwa/instance.json` **at the instance root**
  (`state.go`; `LoadState`/`statePath`). The instance root is the *container*
  above the repo working tree, so a malicious branch/checkout *inside* the repo
  cannot forge that record. That out-of-tree location is precisely what makes a
  verification control sound — and the design never says so. If an implementer
  instead anchors trust on anything inside the repo tree, the control is void.
- niwa has **two** different digests, and the design's phrase "materialization
  fingerprint / provenance" collides with the wrong one:
  - `ManagedFile.SourceFingerprint` (`ComputeSourceFingerprint`) hashes the
    *source inputs* niwa read. It answers "did the upstream source change," NOT
    "was the on-disk file tampered."
  - `CheckDrift` recomputes the on-disk file's content hash and compares it to
    the recorded `ManagedFile.Hash`. This is the primitive that detects a
    planted/swapped script.

  The planted-script threat requires **`CheckDrift` against the recorded content
  hash**, not `SourceFingerprint`. "Fingerprint / provenance" language plausibly
  routes an implementer to `SourceFingerprint`, which would build a check that
  never looks at the file's bytes. Name the drift/content-hash primitive
  explicitly.
- **Drift is a *benign, expected* state in niwa's own model.** `state.go`
  comments that niwa status distinguishes "user-edited drift (content changed,
  fingerprint matches)" as normal. So `/status` must NOT reuse niwa's drift
  *semantics* (which tolerate user edits); for this security control ANY drift
  is fail-closed. If the implementer calls niwa's drift check and treats its
  "benign user edit" verdict as pass, a tampered script that "merely drifted"
  executes. This inversion must be spelled out.
- **No machine-readable single-file verify surface was found.** `niwa status`
  iterates `ManagedFiles`, but I found no `cmd/` command that returns a
  pass/fail drift result for one path in a form a skill can branch on. So the
  control likely has a **prerequisite niwa CLI dependency** (a `niwa verify
  <path>`-style surface), analogous to the already-listed materializer
  duplicate-hook prerequisite. The design presents fingerprint verification as
  if the surface exists; it may need to be built. That is exactly the kind of
  hidden prerequisite that belongs in the Implementation Approach sequencing.
- **The `!`-injection execution model fights fail-closed.** Phase 5 notes
  `/status` runs the script via `!` dynamic injection "at skill-parse time, no
  confirmation." A `!` line has no conditional — you cannot run a verify `!`
  line, read its result, and *then* decide whether to run the exec line. To
  actually "fail closed to the fallback," verify-then-exec-or-fallback must be a
  **single command run from a trusted location** (a verifier shipped in the
  shirabe plugin under `${CLAUDE_PLUGIN_ROOT}`, which then decides to exec the
  repo-tree script or the gh fallback). If the wrapper itself lives at the
  repo-tree path, it has the same planting problem it is meant to solve. The
  design frames `/status` as "probe the path and execute it"; it needs an
  explicit trusted intermediary. Neither the design nor Phase 5 caught this.

Net: the *intent* of the fingerprint control is right and *is* backed by real
niwa machinery, but as written it is hand-wavy at four decision points
(which digest, where the anchor lives, drift-is-fail-closed-not-benign, and
one-trusted-wrapper execution) each of which an implementer can get wrong while
still "verifying a fingerprint."

## Q3 — "Not applicable" / residual-risk justifications that understate risk

- **"no security decision is delegated to model interpretation of block
  contents" — understated for the background-worker path.** The ambient path
  earns this claim (titles omitted or opaque). The final-message path does not:
  the model authors the dashboard block from titles it read, so attacker prose
  *does* shape a surfaced output. This should be reclassified from "best-effort
  prompt-injection, no decision delegated" to "an explicit residual on the
  worker path where block authoring is model-mediated over attacker input,"
  with whatever bound applies (e.g., the block's authoritative fields come from
  captured URLs/numbers, titles are opaque even in the final message).

- **Storage isolation "opened with symlink-following disabled."** Plausible
  intent, but `O_NOFOLLOW` semantics are not trivially expressible from the
  shell `flock`/redirection the design implies. This is stated as a settled
  property; it is actually an implementation obligation that shell hooks often
  get wrong. Flag it as a requirement to verify, not a given.

- **The visibility residuals are correctly *not* understated** — the fallback
  repo-scoping + F1 redaction and the final-message F1 redaction are promoted to
  required controls, matching Phase 5's recommendation. No issue there.

## Q4 — Escalate to the user vs. document

Two items rise to escalation:

1. **Auto-execution of a repo-tree script at skill-parse time, with the
   fingerprint check as the *sole* barrier.** niwa's own file-distribution guide
   documents a supported `permissions = "bypass"` posture that suppresses trust
   prompts. In that posture there is no permission prompt and no user
   confirmation between a malicious checkout and code execution — the
   fingerprint verification is the only thing standing in the way. That elevates
   the under-specified control from Q2 to "the entire trust boundary of the
   feature," and makes it a design choice the user should explicitly accept
   rather than one buried in a Security Considerations paragraph. Recommend
   surfacing the residual: "if this workspace runs bypass-permission sessions,
   `/status` executes a repo-path script with no prompt; the fingerprint check
   is the only barrier."

2. **The fingerprint control may have an unbuilt niwa prerequisite.** If no
   machine-readable per-file verify surface exists (my search found none), this
   control cannot be implemented as described without new niwa work. That is a
   scoping fact the user should see before the design is accepted as "Proposed →
   ready," in the same breath as the already-acknowledged materializer fix
   prerequisite.

Everything else (ANSI ordering, field-set closure, F3-naming, ledger bounds,
TOCTOU) is document-and-tighten, not escalate.

---

## Recommended edits (minimal, no redesign)

1. Rename the terminal sanitization control so it is not confused with the
   markdown-oriented F3; enumerate ANSI-CSI strip, newline strip, `|` strip,
   marker-substring forbid, ANSI-before-truncate ordering, and "every gh-sourced
   field without exception."
2. In the supply-chain paragraph and the Cross-Layer Contract, replace
   "materialization fingerprint / provenance" with the concrete mechanism:
   recompute the on-disk file's content hash and compare to the recorded
   `ManagedFile` content hash in `.niwa/instance.json` **at the instance root
   (outside the repo tree)**; treat *any* drift as fail-closed (not benign);
   run verify-then-exec-or-fallback from a single shirabe-plugin-shipped verifier
   so `!`-injection cannot bypass the branch; note the possible `niwa verify`
   prerequisite.
3. Reclassify the background-worker final-message block as an explicit residual
   where block authoring is model-mediated over attacker input; bound it by
   keeping authoritative fields from captured URLs/numbers and titles opaque.
4. Add the bypass-permission escalation note.
5. Affirm (in Shell/permission discipline) that F2's alphanumeric-first-char
   anchoring is what closes gh flag-injection, or pass `--` before positionals.
