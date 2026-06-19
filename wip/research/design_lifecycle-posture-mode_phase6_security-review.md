**Verdict:** PASS

# Security Review — DESIGN-lifecycle-posture-mode

Reviewed: `docs/designs/DESIGN-lifecycle-posture-mode.md` (Security Considerations section plus full architecture).
Cross-checked against the actual `crates/shirabe-validate` and `crates/shirabe` source it extends.

## Summary

The design's central security claim — **advisory-never-gates** — is sound and, importantly, is *structurally* enforceable in the existing codebase rather than merely asserted. The verdict is computed from `effective_severity(code, posture)` over `(documents, posture)`; the advisory layer is a separate composition step that only feeds human prose and additive JSON. The fork-PR attack surface (attacker-influenced `GITHUB_EVENT_PATH`) is correctly bounded: a crafted payload can at most alter advisory phrasing, never the exit code. The mitigations named (size-bound, parse-failure tolerance, fixed env var, no network) are real and consistent with patterns already in the codebase (`drain_capped`'s 4 MiB ceiling, the `ClientError::Malformed` isolation discipline in `gh.rs`).

Verdict is **PASS**, contingent on the two enforcement obligations below being honored at implementation time. Neither is a design flaw; both are "the design is correct only if the code matches it" obligations that should be written into Phase C as required tests/assertions.

Material findings: **4** (1 should-fix, 2 should-address, 1 note).

---

## Finding 1 (SHOULD-FIX) — Advisory prose flows into an UNSANITIZED human-output path; fork-controlled event JSON can inject terminal escape sequences

**This is the one gap the design's Security Considerations section misses.**

The design (Decision 3B, Architecture item 5) has the advisory layer render its explanation "into the human output by `report.rs`" and compose it partly from `pr_context`, which is read from the attacker-influenced `GITHUB_EVENT_PATH` JSON on a fork PR. The design correctly reasons about the *verdict* (advisory can't move it) but does not reason about the *rendering channel*.

The existing human-output renderer does **no** sanitization:

`crates/shirabe-validate/src/report.rs` lines 131-141 (`render_human`):
```rust
for e in findings {
    if e.line == 0 {
        out.push_str(&format!("{} {} {}\n", e.file, severity(e), e.message));
    } else {
        out.push_str(&format!("{}:{} {} {}\n", e.file, e.line, severity(e), e.message));
    }
}
```
Messages are emitted verbatim. By contrast, the annotation path (`annotation.rs`) *does* sanitize (strips `\n`/`\r`) and the JSON path *does* escape (`json_string()`). The human path is the unsanitized one.

If the advisory module composes any string from `pr_context` fields and routes it through this human path, a fork PR can place ANSI/OSC escape sequences (e.g. `\x1b]0;...`, cursor manipulation, color/clear-screen, or hyperlink/OSC-8 sequences) into CI log output and any terminal that reads it. This is a log-injection / terminal-escape class issue, not a gate bypass — but it is a real attacker-influenced-content-to-terminal path that the section's "can at most alter advisory phrasing" framing understates. "Altering phrasing" with raw escape bytes is exactly the concern.

Note a partial mitigation already exists by accident: `pr_context` today is heavily validated — `owner`/`repo` go through `is_valid_owner_or_repo` character-set checks, and `number` is parsed as `u64`. So the *current* `PrContext` fields are not injectable. The risk is specifically introduced by the new `draft` read and by **any additional event-JSON fields** the advisory layer pulls in (branch names, titles, author logins, etc. are classic injection carriers). If the implementation only reads the boolean `draft` and nothing else free-form, the practical exposure is small — but the design does not constrain it to that, and "lists, per draft-tolerable finding, what it needs before ready" invites pulling richer context later.

**Recommendation (write into Phase C):**
- Restrict the event-JSON read to typed, non-free-text fields only (the `draft` boolean). Do not interpolate any free-text event field (branch, title, head ref, login) into rendered output. State this constraint in the design's Security Considerations.
- Sanitize advisory text on the human path the same way annotations are sanitized (strip control bytes / escape sequences), or route advisory text through a shared sanitizer. This also retroactively hardens the existing `render_human` finding messages, which are document-derived and likewise unsanitized today.
- Add a test: event JSON containing escape bytes in any string field produces sanitized human output and unchanged exit code + JSON.

## Finding 2 (SHOULD-ADDRESS) — "Enforced in code" is the load-bearing claim; make it a test invariant, not prose

The design's own closing sentence makes the verdict PASS *contingent*: "low risk, contingent on the advisory/verdict separation being enforced in code (a finding's severity is resolved only by `effective_severity(code, posture)`, never by advisory context)." That contingency is correct and the design names the right invariant. But as written it is a comment, not an enforced property.

The architecture makes this enforceable: `effective_severity` takes only `(code, posture)` — it has no `pr_context` parameter, so by signature it *cannot* read advisory state. That is the right shape and should be preserved deliberately. The risk is drift: a later change that threads `pr_context` into severity resolution would silently break the invariant with no failing test.

Phase C already lists the correct anti-gating test ("identical `(docs, posture)` with differing PR context yields identical exit code + JSON"). That is the right test. Strengthen it:
- Make it a table test across postures AND across present/absent/malformed/fork-crafted event payloads, all asserting identical exit code and identical *gating* JSON fields (additive advisory fields may differ).
- Keep `effective_severity`'s signature free of any PR-context parameter, and add a one-line comment at its definition stating that this is a security invariant. The type signature is the cheapest enforcement available; use it.

## Finding 3 (SHOULD-ADDRESS) — The deprecated `--strict` alias is a low but real footgun; bound it explicitly

Question 4 flags the deprecated `--strict` alias. It is not a verdict-integrity risk (it maps to `--mode=ready`, the stricter posture — failing safe). Two smaller concerns:

1. **Cascade behavior change is correct but worth a test.** `run-cascade.sh` currently passes `--strict` *unconditionally* (lines ~288-299), independent of draft state — it asserts the terminal posture as a forcing function. The design preserves this by mapping it to `--mode=ready`. Good. Add a test/assertion that the cascade still asserts `ready` (a silent regression to `draft` here would weaken the terminal gate, which *is* security-relevant for the chain-completion contract).
2. **Alias lifetime.** The design says "one migration window" but defines no removal trigger. A hidden boolean that maps to the strict posture is harmless, but leaving it indefinitely is latent surface. Recommend naming the removal condition (e.g. "removed in the next minor after both internal callers are migrated," which Phase D does) so it does not become permanent.

No change to the PASS verdict; these are hygiene.

## Finding 4 (NOTE) — "No path traversal" and "no network" justifications are accurate and correctly scoped

Verifying the "not applicable / low risk" justifications against code:

- **No path traversal — ACCURATE.** The read target is the fixed `GITHUB_EVENT_PATH` env var set by the runner, never a path from document content or a user argument. The existing `detect_pr_context` (gh.rs:129-195) already follows this pattern (reads only fixed env names), so the new read is consistent. The justification holds.
- **No secrets, no network — ACCURATE and stronger than FC09.** The advisory path reads a local file + env and shells out to nothing, unlike FC09's `gh api` subprocess (gh.rs:224-264). This genuinely keeps the advisory path hermetic (PRD R13). Justification holds.
- **Size-bound / parse-failure tolerance — ACCURATE as a pattern, must be implemented.** No code reads `GITHUB_EVENT_PATH` today, so the size-bound is net-new. The codebase has the right precedent (`drain_capped`, 4 MiB ceiling, `ClientError::Malformed` → degrade). The design says "size-bounded, parse-failure tolerant → None." Implementation must actually cap the file read (a runner-written but fork-influenced file could be large) and must `serde`-tolerate arbitrary JSON shape, degrading to `None`. Add the explicit test Phase C already implies (absent/oversized/malformed → clean degrade, unchanged verdict).
- **Determinism as a security property — ACCURATE.** Because the verdict is a pure function of `(documents, posture)` and posture is asserted on the command line (Decision 4A, CI shell asserts `--mode=ready`), ambient env cannot silently move the audit trail. This is a genuine security property, correctly identified. The rejected Decision 1C / 4B (CLI auto-detects posture from ambient state) would have undermined it; rejecting them was the right call.

---

## Answers to the posed questions

1. **Attack vectors / fork-PR `GITHUB_EVENT_PATH`:** The advisory-never-gates separation IS sufficient for verdict integrity and IS enforceable in code — `effective_severity(code, posture)` has no channel to advisory context by signature. The one vector the section misses is not gating but **rendering**: fork-controlled event JSON flowing into the unsanitized human-output path (Finding 1). Fix by constraining the read to the typed `draft` boolean and sanitizing advisory text.

2. **Mitigations sufficient for identified risks:** Yes for size-bound, parse-failure tolerance, fixed env var, and no-network — all are real, consistent with existing code patterns, and correctly scoped. They must be *implemented* (net-new file read) and locked with tests; the design schedules these in Phase C.

3. **"Not applicable / low risk" justifications:** All checked justifications (no path traversal, no secrets/network, determinism) are accurate, not understated — except the "can at most alter advisory phrasing" line, which understates the terminal-escape-in-phrasing risk (Finding 1).

4. **Residual risk to escalate:** (a) terminal escape / log injection via advisory output — escalated as Finding 1, the one should-fix; (b) deprecated `--strict` alias — low risk, fails safe toward `ready`, bound its lifetime (Finding 3); (c) determinism as a security property — correctly claimed, preserve the `effective_severity` signature as the enforcement mechanism (Finding 2).

## Required follow-ups before implementation lands (all in Phase C scope)

1. Constrain the event-JSON read to the typed `draft` boolean; do not interpolate free-text event fields into output. (Finding 1)
2. Sanitize advisory text on the human path; ideally share the annotation-path sanitizer and retroactively cover existing `render_human` messages. (Finding 1)
3. Keep `effective_severity` signature free of PR context; comment it as a security invariant; make the anti-gating test a table over present/absent/malformed/crafted payloads asserting identical exit + gating JSON. (Finding 2)
4. Test that the cascade still asserts `ready`. (Finding 3)
5. Test absent/oversized/malformed event file → clean degrade, unchanged verdict. (Finding 4)
