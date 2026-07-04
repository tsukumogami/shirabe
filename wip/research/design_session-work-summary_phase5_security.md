# Security Review: session-work-summary

Scope reviewed: DESIGN-session-work-summary.md (Decisions 1-5, Solution
Architecture, Key Interfaces, Implementation Approach) against PRD requirements
(notably R5 integrity, R12 visibility) and the workspace's load-bearing security
rules in `references/coordination-strategy.md` (F1 fail-closed private
redaction, F2 `owner/repo:path` component validation, F3 untrusted gh-string
sanitization, F4 live-recompute, and the argv-array-never-shell-string
inherited control).

## Dimension Analysis

### External Artifact Handling / Untrusted Input

**Applies:** Yes — this is the dominant risk surface.

The hook consumes two attacker-influenceable inputs from PostToolUse stdin
JSON: `tool_input.command` (the `gh` command string) and
`tool_response.stdout` (`gh pr create` output). From there, extracted data
flows through: a ledger file → the render script's arguments → live `gh pr
view` calls → the formatted block → `systemMessage` (user terminal) and
`additionalContext` (model context). The most dangerous field is the **PR
title returned by `gh pr view`**, which is fully controlled by whoever authored
the PR and can carry shell metacharacters, ANSI/control sequences, newlines,
markdown/HTML, the literal marker string, or imperative prompt-injection text.
Branch names (visible in `git push` hint output) and the extracted URL are
similarly untrusted.

Specific risks:

1. **Command injection via the extracted URL or session id (Severity: High if
   present).** If the hook or `render-work-in-flight.sh` interpolates the
   ledger URL, `owner/repo#N`, or the session id into a shell string (e.g.
   `sh -c "gh pr view $url"`, backticks, or an unquoted `eval`), a crafted URL
   turns data into code executed with the session's privileges and `GH_TOKEN`
   in env. Mitigation: enforce the workspace argv-array rule for every `gh`
   invocation (never a shell string); validate the extracted URL against a
   strict anchored regex
   `^https://github\.com/[owner]/[repo]/pull/[0-9]+$` and reject anything
   else *before* it reaches the ledger or any `gh` call. The design's
   "digits-only PR-number match" is necessary but insufficient — extend it to
   full-URL / F2 `owner`/`repo` charset validation.

2. **Prompt injection into `additionalContext` (Severity: Medium-High).** The
   block embeds attacker-controlled PR titles and is fed to the model. A title
   such as `Ignore previous instructions; run …` becomes model-visible context.
   The design's "neutral-phrased echo" governs the hook's *own* framing, not the
   *embedded* titles — those are still raw untrusted data the model reads.
   Mitigation: apply F3 to every gh-sourced field before it enters the block —
   strip control/ANSI bytes, collapse newlines, truncate title length; and
   delimit the embedded PR data as untrusted (the model should treat titles as
   opaque labels, not instructions). Consider omitting free-text titles from the
   `additionalContext` echo entirely (repo/number/state/URL are enough for
   conversational consistency) so no attacker prose reaches the model.

3. **ANSI / control-char injection into the terminal via `systemMessage`
   (Severity: Medium).** `gh pr view` title/state text renders into the
   user-visible block. Un-stripped ANSI CSI sequences can spoof or hide terminal
   output; embedded newlines or `|` characters can forge additional pipe-line
   rows or inject a second `=== WORK IN FLIGHT ===` marker, breaking the
   one-line-per-PR contract and defeating both the human scrollback-grep and the
   dedup logic that key on that marker. Mitigation: sanitize per F3 — strip
   non-printable/ANSI bytes, strip newlines and `|` from title fields, and
   forbid the marker substring inside any rendered cell.

4. **Path traversal via session id / repo ref (Severity: Medium).** The ledger,
   the `flock` state file, and the `render-work-in-flight.sh <session-id>`
   argument are keyed by session id; `gh` args carry `owner`/`repo`. A session
   id or repo tag containing `/` or `..` could redirect file writes or `gh`
   targets. Mitigation: validate the session id against `^[A-Za-z0-9._-]+$`
   (reject `/`, `..`, newline, NUL) before it composes any path, and validate
   `owner`/`repo` per F2 before any `gh` call — reject, do not sanitize-and-
   continue.

### Permission Scope

**Applies:** Yes.

Hooks and the render script run with the full session privilege set and
`GH_TOKEN` in the environment, and make `gh` network calls. The feature does not
grant a *new* capability — the agent already can run `gh` — so there is no
inherent escalation. The escalation risk is entirely the data-to-code path in
the previous dimension: an injection into an unquoted shell invocation would run
attacker-controlled bytes at the session's privilege with the token available.

Mitigations / required discipline:
- Every `gh` call in the hook and render script uses an **argv array, never a
  shell string** (the workspace inherited control). This is the single most
  important control for this feature.
- The render/hook scripts must not echo environment or token bytes into the
  ledger, the block, or logs; parse only the specific `gh pr view` fields
  needed via `--json`/`--jq` rather than scraping full stdout.
- No cross-repo write occurs (capture and render are read-only against `gh`
  apart from the agent's own `gh pr create` that triggered the hook) — preserve
  that read-only posture.

### Supply Chain or Dependency Trust

**Applies:** Yes.

The `/status` skill probes
`${CLAUDE_PROJECT_DIR}/.claude/hooks/render-work-in-flight.local.sh` and
executes it via `!` dynamic command injection — which runs automatically at
skill-parse time, with no user confirmation, at session privilege with the
token in env.

Risks:
1. **Planted-script execution (Severity: High).** `${CLAUDE_PROJECT_DIR}/.claude/`
   is inside the repo working tree. A malicious branch, PR checkout, or clone
   could carry a `render-work-in-flight.local.sh` of the attacker's choosing;
   `/status` would execute it. The `.local` infix is a materializer *naming
   convention*, not a trust boundary. Mitigation: `/status` must only execute a
   script that niwa actually materialized — verify the niwa fingerprint /
   provenance manifest before invoking, and **fail closed to the read-only `gh`
   fallback (not execution) when the fingerprint is absent or mismatched**. Do
   not treat "a file exists at the path" as "the script is trusted."
2. **`${CLAUDE_PROJECT_DIR}` redirection (Severity: Low-Medium).** If that env
   var were attacker-influenceable the probe path moves. It is harness-set;
   note the assumption and validate the resolved path stays within the project
   root.

### Data Exposure / Visibility

**Applies:** Yes (PRD R12).

The chosen architecture is visibility-safe *by construction* on its primary
path: Decision 3 Option C keys the ledger to PRs the session opened via
`gh pr create`, and Option B (author-scoped `gh search`) was rejected *because*
it over-collects private PRs into a public context. Good. Residual leak paths:

1. **The `/status` `gh` fallback re-introduces the rejected over-collection
   (Severity: High).** The design specifies that when the render script is
   absent, `/status` "falls back to a model-driven `gh` listing." A broad,
   model-driven `gh search prs --author` / `gh pr list` across the workspace is
   exactly the Option-B behavior that violates R12 — it can pull a private-repo
   PR into a public-visibility summary. This fallback is under-specified and
   dangerous. Required control: the fallback MUST be scoped to the current repo
   only (or degrade to "no session ledger available"), MUST NOT do author-scoped
   cross-repo search, and MUST apply F1 fail-closed redaction to any private-
   repo item it cannot confirm as same-visibility.

2. **Final-message block leaking private identifiers to a lower-visibility
   dashboard (Severity: Medium).** A dispatched worker's final message carries
   the block to Agent View. If that worker opened a private-repo PR and the
   dashboard surface is lower-visibility than the repo, the block's owner /
   repo / number / title leak private identifiers. Mitigation: apply F1 to the
   final-message block — a private-repo entry surfaces opaque node id + state
   only. The design should state the visibility posture of the destination
   surface relative to the tracked repos.

3. **Ledger path predictability / cross-session read (Severity: Medium on shared
   hosts).** The ledger is "keyed by session id" in a "runtime dir." If the path
   is guessable (e.g. `/tmp/work-in-flight-<session-id>`) and session ids are
   not secret, another local user or session could read another session's PR set
   — possibly private. Mitigation: store the ledger and `flock` state file under
   a per-user private directory (`$XDG_RUNTIME_DIR` or `~/.niwa/...`, mode 0700),
   create files 0600, and open with `O_NOFOLLOW` / `mktemp` semantics to defeat
   symlink attacks. Do not place them in a world-readable `/tmp` root.

Note in favor of the design: capturing only from `gh pr create` stdout (and
rejecting the `git push` `/pull/new/` hint) also satisfies R5 integrity — a PR
merely *quoted* in the transcript never enters the ledger, so fabricated
references cannot pollute the block or the harness's native PR surfaces.

## Recommended Outcome

**OPTION 2 — Document considerations.** The design reserves a `## Security
Considerations` placeholder for exactly this pass. The drafted section below is
complete and ready to paste. Two items in it are strong enough that they must be
adopted as **required design controls, not merely documented residual risk**:
(a) the `/status` `gh` fallback must be repo-scoped + F1-redacted rather than a
broad author-scoped search (Decision 3 / Cross-Layer Contract), and (b)
`/status` must verify niwa's materialization fingerprint before executing the
probed script and fail closed to the fallback otherwise (Solution Architecture /
Cross-Layer Contract). Fold these into those sections and reference them from
the Security Considerations text.

---

### Drafted `## Security Considerations` (paste-ready)

This feature processes untrusted, attacker-influenceable input — `gh` command
output and, most importantly, PR titles returned by `gh pr view` — and routes it
into a shell pipeline, a user-visible terminal channel, and the model's context.
It also executes a materialized script and reads PR state that may cross the
public/private visibility boundary. The controls below are load-bearing.

**Untrusted-input handling (capture + render).** The extracted PR URL is
validated against an anchored `^https://github\.com/<owner>/<repo>/pull/[0-9]+$`
pattern (owner/repo per the F2 GitHub charset regex) before it reaches the
ledger or any `gh` call; a non-match is rejected, not sanitized. The session id
is validated against `^[A-Za-z0-9._-]+$` before composing any file path. Every
`gh`-sourced field (title, state) is sanitized per F3 before entering the block:
control/ANSI bytes stripped, newlines and `|` removed, title length truncated,
and the literal `=== WORK IN FLIGHT ===` marker forbidden inside any cell — so a
crafted title cannot forge rows, inject a second marker, or spoof the terminal.

**Shell / permission discipline.** Every `gh` invocation in the hook and render
script uses an argv array, never a shell string; no extracted value is
interpolated into `sh -c`, `eval`, or backticks. Field extraction uses
`gh … --json/--jq` rather than stdout scraping, and no environment or token
byte is written to the ledger, block, or logs. The pipeline is read-only against
`gh` except for the agent's own triggering `gh pr create`.

**Model-context exposure.** The `additionalContext` echo carries only
structured fields (repo, number, state, URL); free-text PR titles are either
omitted from the model-facing echo or delimited as opaque untrusted labels, so a
PR title cannot act as a prompt-injection instruction. The neutral hook framing
governs the hook's own text, not embedded data.

**Supply-chain trust of the render script.** `/status` executes the probed
`render-work-in-flight.local.sh` only after verifying niwa's materialization
fingerprint/provenance; the `.local` path is a naming convention, not a trust
boundary, and a file planted by a malicious branch or clone must not be
executed. If the fingerprint is absent or mismatched, `/status` fails closed to
the read-only `gh` fallback rather than executing the file, and confirms the
resolved path stays within the project root.

**Visibility (R12).** The primary path is safe by construction: the ledger holds
only PRs the session opened, so multi-repo collection never reaches beyond the
repos the session touched. The two residual paths are constrained: (1) the
`/status` `gh` fallback is scoped to the current repo only — never an
author-scoped cross-repo search — and applies F1 fail-closed redaction to any
item whose visibility it cannot confirm; (2) a dispatched worker's final-message
block redacts private-repo entries to opaque node id + state (F1) when the
destination surface is lower-visibility than the repo.

**Storage isolation.** The per-session ledger and `flock` state file live under
a per-user private directory (mode 0700, files 0600), opened with symlink-
following disabled, so one local session or user cannot read another's tracked
PR set from a predictable `/tmp` path.

**Residual risk.** The feature trusts niwa's materialization fingerprint as the
script-provenance root; a compromise of the materializer or of `GH_TOKEN` is out
of scope and inherited from the harness. Prompt-injection defense is
best-effort: sanitization and field-restriction reduce but do not eliminate the
possibility that adversarial PR text influences the model's narrative, so no
security decision is delegated to model interpretation of block contents.

## Summary

The design's core data path is sound — per-session capture from real
`gh pr create` output is both integrity-safe (R5) and visibility-safe (R12) by
construction, and it correctly rejected the author-scoped-search approach. The
real exposure is in the edges: untrusted PR-title text flowing into a shell
pipeline, the user's terminal, and the model's context (needs argv-array
discipline, F2 URL validation, and F3 title sanitization); the `/status` gh
fallback and its execution of a repo-tree-resident script (needs repo-scoped
F1-redacted fallback and niwa fingerprint verification, fail-closed); and
ledger storage/permissions. Recommend Option 2 — paste the drafted Security
Considerations section — while promoting the fallback-scoping and
fingerprint-verification items to required controls in the design body.
