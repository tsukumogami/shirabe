# Verdict: FAIL

Reviewed: `docs/designs/DESIGN-skill-preflight-checks.md` (status Proposed), Security
Considerations at lines 869-959 plus the load contract (610-660), probe (491-528), report
(530-608), and the existing `skills/execute/scripts/preflight.sh`. Compared against the
repo's established posture in `crates/shirabe/src/work_summary.rs` (`sanitize` at :334,
`additional_context` at :1073) and `docs/designs/current/DESIGN-session-work-summary.md`
(Security Considerations, "Untrusted-input handling" and "Model-context exposure").

The section is not a formality. It is one of the more serious security sections in the
`docs/designs/` corpus: it names the injected command, an unset `${CLAUDE_PLUGIN_ROOT}`,
declaration content reaching a shell, tool output reaching model context, the CI allowlist,
the route table, and the denial-of-service property, and it argues each rather than
asserting it. It fails anyway, on one structural ground and several specific ones: the
design applies the repo's own "the working directory during a skill load is a repository
whose contents may have arrived from a pull request" threat model to the *script path* and
then declines to apply it to the *binaries the script executes*, the *declaration it reads*,
or the *text it puts in front of the model*. The strongest control the repo already ships
for exactly this problem — sanitize, bound, and nonce-fence untrusted text before it enters
context — is not carried over, and the design does not say why it is not needed here.

## Surfaces the design identifies

**Correctly identified and adequately mitigated:**

- *The injected command itself* (871-881). Fixed string in a committed file, one literal
  argument, one `allowed-tools` pattern, `check-skill-injection.sh` as the CI invariant,
  and the residual (anyone who can land a commit can land a load-time command) stated
  honestly rather than argued away. Phase 2's permission-pattern gate (809-819) is the
  right shape: a mismatch deletes twenty skills, and the design treats it as a gate.
- *`${CLAUDE_PLUGIN_ROOT}` unset* (883-892). The reasoning is correct and specific: an
  unprivileged attacker cannot create `/scripts` on macOS or Linux, so the degenerate case
  is a 127 the outer guard swallows. The insistence that the path stay absolute, and the
  stated reason (a relative fallback resolves against a PR-supplied working directory), is
  the best security sentence in the document.
- *The route table emits commands an agent will run* (939-947). Committed file, probed
  availability, exactly one command, no reader choice. The `gh`-on-Linux exclusion with a
  cited incident is a real ownership rule.
- *Denial of service* (949-954). R17-as-security-property is a legitimate and well-argued
  framing, correctly noting that a blocking check hands anyone who influences a declaration
  or a tool's help output the ability to disable twenty workflows.

**Identified but under-mitigated:**

- *Declaration content reaching a shell* (894-906). Three controls named: no eval, explicit
  quoted argv, and a conformance scan enforcing four fields and a closed tool-name set. Two
  gaps, below (Required changes 2 and 3).
- *Tool output into model context* (908-924). The design calls this "the sharpest surface"
  and it is right, but the mitigation is a single argument (extraction, not verbatim) plus
  a trust-boundary claim. Below (Required change 1).
- *The enumeration as a CI gate* (926-937). Both-directions scan and a command-text join key
  are genuine hardening. But the design never says who adjudicates, and never requires the
  per-entry justification it requires of its own sibling data file. Below (Required change 5).

## Surfaces the design misses

1. **No bound of any kind on tool-controlled text entering the report.** The report
   interpolates the advertised subcommand list, the advertised flag list, and the
   `command -v` resolved path (see the worked case at 535-556, "koto resolves at
   /Users/you/.tsuku/tools/current/koto"). All three are controlled by whatever binary is
   first on PATH. There is no charset allowlist, no per-token length cap, no item-count cap,
   no control-character or ANSI strip, no marker-forbidding rule, and no untrusted-data
   delimiter around the interpolated region. The repo already has all of these for the same
   class of input: `sanitize` (work_summary.rs:334) strips ANSI CSI, removes C0/DEL/C1 code
   points, removes the cell separator, truncates to 50 characters strip-before-truncate, and
   removes the block marker to a fixed point; `additional_context` (:1073) wraps the result
   in a non-imperative preamble and a 128-bit-nonce'd fence in *both* lines so embedded text
   cannot forge the close. DESIGN-session-work-summary.md states the rule plainly: free-text
   fields are "either omitted from the model-facing echo or delimited as opaque untrusted
   labels, so a PR title cannot act as a prompt-injection instruction."

   The design's counter-argument is that the extractor emits tokens, not prose, so
   "prose in a description never reaches the report" (919-921). That bounds the *position*
   the text is drawn from, not its *content*. The extractor keys on clap's layout — 2 to 6
   leading spaces marks an option line (513-516) — so a hostile binary controls the bytes at
   that position completely and simply emits its payload as the flag token. It also controls
   how many such lines it prints. Position-anchoring was chosen to defeat a *false positive*
   in honest help text (315-319); it was never designed as a security filter and the design
   does not claim it was tested as one.

   The trust-boundary argument (914-917) — a hostile binary on PATH already has a more
   direct path to the same outcome, so the check does not widen the boundary — is the better
   half of the paragraph and is partly right. It is not sufficient, for three reasons the
   design does not address. The check runs at *load*, unconditionally, before the model or
   the user has decided to do anything, whereas the tool's own execution is conditional on
   reaching a phase. It runs for `mode:` records the session may never select and for phases
   the run may never reach. And the placement differs in kind: the tool's normal output
   arrives as a tool result the model reads as data, while the report is substituted into
   the SKILL.md *body* ahead of the instructions it qualifies (270-276) — the highest-trust
   position in the context — inside a block whose surrounding fixed prose tells the reader to
   run a shell command. That is a strictly worse position than the one the boundary argument
   compares against.

2. **No execution-safety controls on the probe.** The design specifies no timeout, no
   `</dev/null`, and no output cap on any `--help` invocation. `grep -i "timeout\|hang\|stdin"`
   over the document returns nothing. R17's never-block promise is argued entirely at the
   exit-code level, and the injected line's `|| true` guard cannot rescue a process that has
   not exited. A shadowing or merely broken binary that hangs, reads stdin, or emits
   unbounded output on `--help` blocks skill load indefinitely or floods the context, and
   under the design's own R12 silence rule the user sees nothing while it does so. This is
   the direct refutation of the "cannot be used to deny service" claim at 949-954: the denial
   of service is not the check refusing, it is the check waiting.

3. **`command -v` resolution provenance is unconstrained.** The design reasons carefully that
   the plugin-root fallback must never resolve against `$PWD` because the working directory
   at skill load may be a PR checkout (887-892), then executes up to six PATH-resolved
   binaries with `--help` without applying that reasoning to them. `command -v` honors a PATH
   containing `.` or a relative entry, in which case the binary executed at skill load comes
   out of that same PR checkout. Nothing in the design requires the resolved path be absolute,
   or outside the working directory, or reported to the user when it is neither.

4. **`SHIRABE_PREFLIGHT_ROOTS` is never treated as input.** It appears twice (497, 836), both
   times as a test affordance, with no statement of who may set it or what setting it buys.
   Environment for a Claude Code session can come from a project-level `.claude/settings.json`
   `env` block — a file that ships in the repo under review. Today the consequence is bounded
   because roots are only `-x` tested and the R18 ordering means a root hit suppresses the
   install route rather than executing anything (491-503). That bound is a property of the
   current implementation sketch, not a stated invariant, and the design offers nothing that
   would stop a later revision from probing a root-resolved binary. It also does not note
   that the default root list is echoed verbatim into report text (561-562).

5. **The self-resolution fallback is specified against code that cannot provide it.** The
   design says the script's `${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback is "lifted from the
   existing `preflight.sh`" and "resolves from `$0` rather than from `$PWD`" (890-892). The
   existing script is `#!/usr/bin/env bash` and resolves from `${BASH_SOURCE[0]}`
   (`skills/execute/scripts/preflight.sh:19`). The new script is POSIX `sh`, invoked as
   `sh <path>` (621), where `BASH_SOURCE` does not exist: a literal lift yields
   `dirname ""` → `.` → a `$PWD`-relative root, which is precisely the outcome the design
   forbids. The design states the correct rule and then cites an implementation that
   contradicts it. Separately, whatever root is resolved is the path from which
   `scripts/lib/preflight-*.sh` are *sourced* (389) — execution, not reading — and the design
   nowhere requires the resolved root be validated (a `plugin.json` marker, say) before that
   source happens.

6. **The malicious-PR threat model has an ordering hole.** The design's answer to a hostile
   `requires.tsv` is that "the threat model here is a malicious pull request against shirabe
   itself, which the review of a four-field tab-separated line is well suited to catch"
   (903-906), backed by `check-skill-requires.sh` in CI. Both controls act on the PR. The
   reviewer who checks the branch out locally — with the plugin root pointing at that
   checkout, which `marketplace.json`'s `"source": "./"` makes the normal developer
   configuration (128-130) — loads a skill and runs the attacker's declaration *before*
   either control has run. Review is not a control against a payload that fires when the
   reviewer opens the branch. The same ordering applies to `scripts/lib/preflight-*.sh` and
   to `skill-preflight.sh` itself on that branch.

7. **Failure-open hides the check's own compromise, and the design does not say so.** R17
   plus R12 mean the observable output of a fully satisfied host is byte-identical to that of:
   a script that is missing; a script that is unreadable or truncated; an unexpanded
   `${CLAUDE_PLUGIN_ROOT}` producing a 127 the `|| true` swallows (643-651); a `requires.tsv`
   that is absent, empty, or silently mis-parsed because an editor converted tabs to spaces
   (1013-1014); an early `exit 0` inserted by anyone who can edit the script; and a packaging
   or marketplace-fetch problem that dropped `scripts/` entirely. Zero bytes for all of them.
   The design is aware of individual instances — it names the tab-conversion hazard, the 127,
   and the clap-layout break — but it never assembles them, and the Security Considerations
   section presents always-exit-0 purely as a benefit (949-954) with no counterpart sentence.
   The CI tests in Phase 3 (835-839) do assert a non-empty report for the absent case, which
   is a real partial answer, but they exercise the script in CI rather than the injection path
   on a user's host, and Phase 2 is a one-time manual gate on one machine rather than a
   recurring signal. This is the one place where the feature's own design principle works
   against detecting the feature's own compromise, and a design whose subject is
   *detecting drift* owes that observation an explicit paragraph.

## Adequacy of stated mitigations

| Surface | Stated mitigation | Adequate? |
|---|---|---|
| Injected command | Fixed string, one literal arg, `allowed-tools`, CI scan, Phase 2 gate | Yes |
| `${CLAUDE_PLUGIN_ROOT}` unset | Absolute path, `/scripts` unwritable, 127 caught | Yes for the injected line; no for the in-script fallback (miss 5) |
| Declaration → shell | No eval, explicit quoted argv, four-field scan, closed tool set | Partial: no charset rule, field-two word-split unaddressed, CI-after-the-fact (misses 6, and changes 2-3) |
| Tool output → context | Extraction not verbatim; trust boundary unchanged; fixed surrounding text | **No.** Below the repo's own bar (miss 1) |
| PATH resolution | Not addressed as a surface | **No** (misses 2, 3) |
| `SHIRABE_PREFLIGHT_ROOTS` | Not addressed as a surface | **No** (miss 4) |
| CI allowlist | Both-directions scan, command-text join key | Partial: no adjudicator, no per-entry justification (change 5) |
| Route table | Committed, probed, one command, cited exclusion | Yes |
| Never blocks | Always exit 0, doubled by the outer guard | Partial: true for exit codes, false for hangs (miss 2); silent about self-compromise (miss 7) |
| "Not applicable" (956-959) | No files, no state, no network, no credentials, no version compare | Accurate as written, and worth keeping |

The two paragraphs that carry the most weight are the weakest. The tool-output paragraph is
argued rather than controlled: every sentence in it is a reason the risk is smaller than it
looks, and none of them is a mechanism. The denial-of-service paragraph proves a property
about exit codes and then claims a property about availability.

One point in the design's favor that should survive the rewrite: the decision not to echo raw
stderr into the report on the probe path (923-924) is correct and deliberate, and the report's
refusal to offer the reader a choice of commands (581-584) is a genuine anti-injection
property — there is no path by which report text becomes an arbitrary command line. Both
should be stated as invariants the implementation must hold, not as descriptions of it.

## Required changes (if FAIL)

1. **Tool output reaching the model's context.** The Security Considerations section must
   specify a concrete filter, not an argument, for every byte of tool-derived text that
   enters the report — the advertised subcommand list, the advertised flag list, and the
   `command -v` resolved path. At minimum, and stated as normative: a character allowlist for
   extracted tokens (the design's own `--help` evidence supports something as tight as
   `[A-Za-z0-9._-]` plus a leading `-`/`--`, with a non-conforming token dropped rather than
   sanitized, following `extract_pr_url`'s reject-don't-sanitize rule); a per-token length cap
   and a per-list item cap, with an explicit "and N more" elision past the cap; a strip of ANSI
   CSI and C0/C1/DEL code points ahead of the allowlist; and a rule that the interpolated
   region is delimited as untrusted data. The design must either adopt the nonce-fenced,
   non-imperative-preamble framing that `work_summary.rs:1073` uses for exactly this problem,
   or state in the section why a report the model reads as body text needs less protection
   than a hook echo the model reads as a tool result. It currently does neither, and the
   asymmetry is not defensible as written. Note the R12 interaction and resolve it explicitly:
   these controls run only on the unsatisfied path, which emits bytes anyway, so none of them
   costs the satisfied path a byte.

2. **Command construction from declaration fields.** The section says fields are "never
   word-split into a command line by expansion" (897-898), but the format definition (406-414)
   makes field two "the full subcommand path including spaces," which the probe must split into
   argv elements. Those two sentences cannot both be true. State the actual rule: field two is
   split on spaces into argv elements, and therefore every field needs a character allowlist
   enforced *by the script at read time*, not only by CI. Specify the allowlist, specify that a
   record failing it is skipped with the skill named and the record's line number reported (not
   silently dropped — that reintroduces miss 7 at record granularity), and specify rejection of
   a leading `-` in fields one and two. The repo's discipline here is explicit and cited in
   `skills/scope/SKILL.md` (~752-754: canonicalize, quote, pass after `--`) and in
   work_summary.rs's alphanumeric-first owner/repo anchor, whose stated purpose is defeating
   `gh` flag-injection. A subcommand field of `--version` or `-x` currently reaches the probed
   tool as a flag with nothing in the design to stop it.

3. **PATH and binary resolution.** Add a paragraph. It must (a) state that the probe executes
   whatever binary PATH resolves, and either require the resolved path be absolute and outside
   the working directory or state why a CWD-derived resolution is acceptable — the design
   cannot invoke the PR-checkout-CWD threat model for `skill-preflight.sh` at 887-892 and stay
   silent about it for the binaries that script runs; (b) require every probe invocation carry a
   wall-clock timeout, `</dev/null`, and an output byte cap, with the timeout/cap path treated
   as "probe inconclusive" rather than as a finding; and (c) qualify the "cannot be used to deny
   service" claim so it covers hangs, not only non-zero exits. The 20 ms `gh --help` measurement
   (517-519) is an honest-host number and the section should say so.

4. **`SHIRABE_PREFLIGHT_ROOTS`.** State who can set it (anything that sets session environment,
   including a project-level `.claude/settings.json` in the repo under review), state what
   setting it buys today (flipping absent↔off-PATH, which suppresses or fabricates an install
   route in a report an agent will act on), and make the current bound an invariant rather than
   an accident: roots are only ever `-x` tested and a root-resolved path is never executed.
   Apply the same character allowlist as change 2 to the root entries before they are echoed
   into report text.

5. **Adjudication of `references/tool-diagnostic-discards.md`.** The design gives
   `scripts/lib/tool-routes.tsv` a stated ownership rule with issue citations (605-608) and
   gives the enumeration nothing equivalent, then names "a reviewer approving an entry they did
   not think about" as the residual (933-937). Close the gap the same way the sibling file
   closes it: require a justification field and an issue or incident citation per record, name
   who adjudicates an addition (a CODEOWNERS entry or a named required reviewer for that path),
   and say whether a new entry may land in the same PR as the code it exempts. Without an
   adjudicator, "it costs a reviewed edit" is a claim about a process nobody owns.

6. **The self-resolution fallback.** Correct the citation and the mechanism. `BASH_SOURCE` is a
   bash array that does not exist under the POSIX `sh` the entry point runs as, so the lift from
   `preflight.sh:19` yields a `$PWD`-relative root — the exact failure the same paragraph
   forbids. Specify `$0`-based resolution with its preconditions stated, and require the
   resolved root be validated against a plugin marker before anything under
   `scripts/lib/` is sourced, since sourcing is code execution from that root.

7. **The malicious-PR ordering hole.** Amend 903-906. The declaration, the helper scripts, and
   the entry point on a PR branch all execute when a reviewer loads a skill with the plugin root
   pointed at that checkout — before CI and before human review. Either state the mitigation
   (for example: load-time enforcement of changes 2 and 6 inside the script, so the script's own
   committed-and-reviewed copy is the control rather than the reviewer's attention), or state
   plainly that reviewing a shirabe PR locally means running its preflight code, so reviewers
   know the exposure they are accepting.

8. **Failure-open as a detection blind spot.** Add a paragraph to Security Considerations that
   enumerates what silence covers: satisfied, script missing, script unreadable or truncated,
   `${CLAUDE_PLUGIN_ROOT}` unexpanded (127 swallowed by `|| true`), sidecar absent or empty,
   sidecar tabs converted to spaces, an inserted early `exit 0`, and `scripts/` lost in
   packaging. State that no host-side signal distinguishes them, credit the Phase 3 CI tests
   and the Phase 2 gate as partial coverage while naming what they do not cover (the injection
   path on a real user's host, continuously), and take a position on whether that is accepted or
   whether the design owes a liveness mechanism — an eval asserting a non-empty report against a
   deliberately-unsatisfiable fixture skill on the injection path is the cheapest option and
   costs the satisfied path nothing. The design need not solve this. It must stop presenting
   always-exit-0 as unambiguously a security benefit when it is also the reason this subsystem
   cannot report its own subversion.
