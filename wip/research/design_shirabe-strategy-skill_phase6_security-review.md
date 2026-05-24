# Phase 6 Security QA Review: shirabe-strategy-skill

## Verdict

**minor-issues** — Phase 5's analysis is broadly correct, but a few
attack vectors and unsupportable "N/A" justifications warrant
patching the Security Considerations section before merge. None
require restructuring the design.

## Gaps and Attack Vectors Missed by Phase 5

### 1. `transition-status.sh` shell-injection via `[reason]` argument

Phase 5 only names path-traversal on the `<path>` argument as a
risk and labels it "Low" precedent-faithful. The third positional
argument (`[reason]`) is freeform user text that the script must
splice into the body Status section via `sed`/`awk`. Phase 5 does
not analyze this surface at all. Risks:

- **Sed metacharacter injection.** If `reason` contains `/`, `&`,
  `\`, or newlines, a naive `sed -i "s/.../<reason>/"` either
  corrupts the file or, with `eval`-adjacent shell constructions,
  could execute arbitrary commands. A `--reason='$(rm -rf .)'` style
  payload is unlikely to fire under bash quoting but is exactly the
  kind of thing that breaks if a future refactor introduces an
  unquoted expansion.
- **Frontmatter injection.** A reason like `"\n---\nstatus: Active\n"`
  could break the frontmatter / body boundary if naively inserted.
- **Markdown / commit-message escape.** Reasons land in body prose
  that downstream reviewers read; embedded markdown or HTML could
  social-engineer reviewers (low severity, but worth noting).

Phase 5's analysis is incomplete here. The Security Considerations
section in the design should require: (a) `reason` is inserted via
a sed `c\` command or awk variable assignment (not interpolated
into a regex pattern), and (b) newlines and frontmatter delimiters
are rejected or escaped before insertion.

### 2. wip/ filename injection via `<topic>` slug

Phase 4 verdicts go to
`wip/research/strategy_<topic>_phase4_<role>.md`. Phase 5 does not
analyze how `<topic>` is derived. If the topic is taken from the
user's `/strategy [topic-or-PRD-path]` argument or from frontmatter
without sanitization, an attacker-supplied slug containing `../`
or absolute path components could redirect verdict writes outside
`wip/research/`. The design must specify slug sanitization (kebab-
case, `[a-z0-9-]+` only) at Phase 0.

### 3. Subagent-output trust boundary at the orchestrator

Phase 5 names the `**Verdict:** PASS | FAIL` literal-parse
mitigation but does not analyze the case where a subagent's
verdict file is **legitimately authored** but contains malicious
Markdown that the orchestrator surfaces to the user. The verdict
file content is read back and rendered/quoted by the orchestrator
in Phase 4.3 aggregation. If a prompt-injection succeeded enough
to control verdict body text (not the PASS/FAIL marker), embedded
content could mislead the human reviewer at Phase 5. Mitigation:
the orchestrator should fence the verdict body when surfacing it
to the user, not interpret embedded Markdown commands.

### 4. Race condition on parallel reviewer writes

Phase 4 spawns three reviewers with `run_in_background: true`.
Phase 5 asserts each writes to a distinct path
(`strategy_<topic>_phase4_<role>.md`) so cross-agent state is
isolated. But the design does not specify what happens if two
invocations of `/strategy` (same topic, different sessions) run
concurrently. Without a lockfile or unique session ID component
in the filename, verdict files clobber each other and the
orchestrator could aggregate a mixed verdict set across runs.
Low severity (operator error, not adversarial) but worth a one-
liner in the design.

## "N/A" Justifications That Are Actually Applicable

### "External Artifact Handling: No" is partially wrong

Phase 5 marks this dimension N/A on the grounds that "no URL
fetches, no archive extraction." However:

- The skill ingests **user-supplied PRD/Vision paths** via
  `/strategy [path]`. The path is an external-input artifact from
  the agent's perspective even though it resolves to a local file.
  A symlink at the supplied path could point outside the repo,
  causing Phase 1 to read arbitrary filesystem content into the
  STRATEGY draft (and from there into a public-visibility commit).
  Severity: **Low–Medium**. The design should require Phase 0 to
  reject symlinks or paths resolving outside the repo root.

### "Supply Chain: No" is correct but understates eval-time trust

Phase 5 dismisses supply chain because no new deps are introduced.
The `scripts/run-evals.sh strategy` invocation spawns subagents
with `/skill-creator` loaded that execute scenarios from
`evals.json`. Eval fixtures are committed markdown — safe — but
the eval **assertions** can include commands the grader executes.
Phase 5 should have noted: assertions in `evals.json` are code
under the same review burden as any other committed script. Not
"no surface" — just "covered by code review."

## Mitigation Sufficiency Assessment

The three mitigations the design landed (R8 fail-closed, Phase 4
injection hardening, non-gated-section leakage) are correctly
scoped to the risks they name. Specific assessments:

- **R8 fail-closed.** Sufficient. The unit-test requirement and
  CI wiring derivation from `Repo Visibility:` are both concrete.
- **Phase 4 prompt injection.** Mostly sufficient, but the
  tool-surface minimization clause ("No Bash, no WebFetch, no
  Edit on arbitrary files") is aspirational unless the Agent tool
  actually supports per-spawn tool restriction. Phase 5
  acknowledged this caveat ("If the Agent tool does not currently
  support tool-surface restriction, treat this as a future-
  hardening note") but the design's Security Considerations
  section dropped that caveat. The design now reads as if the
  restriction is guaranteed. **Fix:** either confirm the Agent
  tool supports the restriction (cite the API) or restore Phase
  5's caveat language.
- **Non-gated-section leakage.** Sufficient as guidance but
  unenforceable. The Phase 4 structural reviewer is asked to
  "flag verbatim copies of likely-private content" — this is a
  judgment call with no deterministic rule. The mitigation reads
  as defense-in-depth (correct) rather than a guarantee. Worth
  stating explicitly.

## Residual Risk for User Escalation

One item rises above "implementer checklist" and should be raised
to the user before approval:

- **Tool-surface restriction guarantee for Phase 4 subagents.**
  The design's Security Considerations section claims subagents
  spawn with a minimal tool surface, but Phase 5's research notes
  this depends on Agent-tool capabilities that may not exist. If
  subagents inherit the parent's full tool surface (Bash,
  WebFetch, Edit), a successful prompt injection could
  exfiltrate repo content or modify files outside the verdict
  path. The user should be asked: is the tool-surface restriction
  actually enforceable today, or is this a "best-effort prompt
  framing + Phase 5 human gate" design? The answer changes
  whether prompt injection is medium-severity-mitigated or
  medium-severity-residual.

## Actionable Findings

- Add shell-safety guidance for `transition-status.sh` `[reason]`
  argument (sed metacharacters, newlines, frontmatter delimiters).
- Specify `<topic>` slug sanitization in Phase 0 to prevent wip/
  path-traversal via filename construction.
- Specify symlink rejection / path-canonicalization for
  user-supplied PRD/Vision paths in Phase 0.
- Either confirm Agent-tool supports per-spawn tool-surface
  restriction (cite mechanism) or restore Phase 5's caveat
  language — current design reads as a guarantee it may not be.
- Add a one-liner on concurrent `/strategy` invocation behavior
  (verdict-file collision under same `<topic>`).
- Note that `evals.json` assertions are code under code-review
  trust, not "no supply-chain surface."
- Specify that the orchestrator fences verdict body content when
  surfacing it to the human at Phase 5, not interprets embedded
  Markdown.

## Verdict Summary

**minor-issues.** Phase 5's six-dimension review is solid but
missed shell-injection on the `reason` arg, slug sanitization for
wip/ filenames, symlink handling on user-supplied paths, and a
concurrent-invocation race. The tool-surface restriction claim in
the design's Security Considerations section is the one item that
warrants user confirmation before approval — everything else is
implementer-checklist work that can be added to the section
directly.
