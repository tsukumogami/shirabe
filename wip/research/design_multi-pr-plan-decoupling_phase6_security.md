# Verdict: PASS

## 1. Attack-vector coverage

All four introduced surfaces are addressed, not hand-waved:

- **New CLAUDE.md config read** — covered concretely (closed enumeration, no interpolation, `.git`-bounded walk).
- **New free-text frontmatter field (`split_rationale`)** — covered with a specific claim about consumers (none interpolate it).
- **New derived identifier scheme (`m-<slug>`)** — covered by reuse argument, checked against source (see below).
- **Preference gating remote artifact creation (`Tracking Level`)** — covered, and correctly argues the gate re-key is a net *tightening*, not a loosening.

One vector the section does not name: `resolve_claude_md_header` resolves to the **nearest** CLAUDE.md/CLAUDE.local.md to the document, not necessarily the repo-root one. The section's `.git`-boundary claim is accurate but incomplete as a security statement — it establishes an upper bound (can't escape the repo) but says nothing about the lower bound (a CLAUDE.md/CLAUDE.local.md in a subdirectory closer to the PLAN file wins over one at repo root). For `Delivery Preference`, this means the FC20 departure-branch predicate is resolved per-nearest-config, not per-repo. This is inherited, unmodified behavior from the existing walker (same as `resolve_doc_visibility`), so it isn't a vector this design *introduces* in the sense of new code — but the design does introduce a new *consumer* (FC20) whose correctness depends on this resolution semantics, and the section doesn't mention it. Worth one sentence; not a hole in the mechanism itself.

## 2. Verifying claimed mitigations against code

- **"Unrecognized header values fall through to default rather than being used"** — confirmed against `parse_visibility_header` (`crates/shirabe-validate/src/visibility.rs:31-46`): an unmatched value simply doesn't produce a `Some`, the loop continues, and the function returns `None` if nothing matches. Test `parse_header_absent_or_malformed_is_none` (line 226-231) confirms `"internal"` → `None`. Holds.
- **"`resolve_claude_md_header` stops at the first `.git` boundary walking up"** — confirmed at `visibility.rs:79-100`: the walk reads CLAUDE.local.md/CLAUDE.md at the *current* directory first, then checks `d.join(".git").exists()` and returns `None` if so, before ascending further. So the repo-root's own CLAUDE.md is read (correct — it's in-repo), and nothing above it is ever reached. Holds, as described.
- **"`split_rationale` is never interpolated into a shell command, branch name, or path"** — grepped `skills/plan/scripts/plan-to-tasks.sh` and `skills/work-on/references/scripts/extract-context.sh`. `plan-to-tasks.sh`'s frontmatter reads are limited to `schema` and `execution_mode` (lines 1197-1206); `split_rationale` doesn't appear anywhere in either script. No consumer exists today, interpolating or otherwise. Holds — and the search also confirms the field currently has zero references outside `wip/` scratch files and the design doc itself, i.e. nothing yet built against it that the design could have overlooked.
- **"`m-<slug>` inherits single-pr's slugify, collision-suffixing and 64-char truncation"** — confirmed the machinery exists in `plan-to-tasks.sh`: `slugify()` (lines 221-230), `KOTO_NAME_MAX=64` truncation with trailing-dash stripping (lines 592-601), and count-based collision suffixing via the `kv_*` store (lines 607-630), currently applied to `o-<slug>` in `process_single_pr`. The claim that this machinery is available to reuse for `m-<slug>` in a future `plan_item` branch is accurate — it's the same function and the same pattern already proven out, not a promise of something that doesn't exist.

No claim in the section fails verification.

## 3. Visibility boundary (Public repo)

`split_rationale` is author-written prose landing in a committed PLAN frontmatter field, in a Public repo. This is the same trust boundary as every other free-text field already in a PLAN (problem statements, rationale blocks, outline titles) — the design doesn't grant a new party write access, and an author who wants to leak something already has dozens of prose fields available. The section doesn't spell this "no new privilege" reasoning out explicitly, but the underlying fact holds and nothing in the design routes private-only content toward a public artifact. No finding here beyond noting the section could say this in one sentence for a reader who doesn't already know the trust model.

## 4. Residual risk honesty

The stated residual risk (FC20 can't confirm the reason is *true*) is real and correctly scoped as "auditability, not authorization." It is not the only risk touched by the design, but the others are honestly disclosed — just filed under Consequences rather than duplicated in Security Considerations: the live-config non-determinism risk ("FC20's departure branch reads live repository configuration... can see the finding appear or disappear without the plan changing") is called out at line 531-536. That's a reasonable place for it since it's a stability/DX property, not a security one — nothing is silently dropped. The nearest-CLAUDE.md-wins point from §1 is the one thing not surfaced anywhere in the document.

## 5. "Not applicable" abuse

None found. The section doesn't wave off any of the four vectors as out of scope, and doesn't invoke "not applicable" language anywhere.

## Required Changes

1. Add one sentence to "Untrusted configuration read" noting that `resolve_claude_md_header` resolves to the nearest CLAUDE.md/CLAUDE.local.md to the PLAN document, not the repo root specifically — so FC20's departure-branch predicate can differ by directory within one repo. This is inherited, correct-by-precedent behavior (same as visibility resolution), not a defect, but it should be stated rather than left implicit given FC20 is a new consumer relying on it.
2. Optional, non-blocking: note (or explicitly decide against) a size bound on the two new header values, for consistency with `parse_prose_vocabulary_header`'s explicit 64 KB cap — low severity since both new values are short closed-enumeration matches, not compiled patterns or unbounded lists.

Neither item changes the verdict; both are additions to an already-adequate section, not corrections of a wrong claim.
