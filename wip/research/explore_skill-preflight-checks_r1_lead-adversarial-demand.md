# Demand Validation: skill-preflight-checks (R1, lead-adversarial-demand)

Visibility: Public. Every citation below comes from a public repo
(`tsukumogami/shirabe`, `tsukumogami/koto`, `tsukumogami/niwa`,
`tsukumogami/tsuku`) or this repo's committed tree.

## Q1 — Is demand real?

**Confidence: Medium.**

Five durable incidents exist where a shirabe skill ran on a machine whose
environment did not match what the skill prose assumed, and the run went badly.
All five are filed by the same person, who is also the maintainer, so the
"distinct reporters" bar is not met; but four have merged or in-flight fixes,
which is maintainer acknowledgment in the strongest available form.

- **`tsukumogami/shirabe#80`** (OPEN, `dangazineu`). The `staleness_check` gate
  in `skills/work-on/koto-templates/work-on.md` calls `check-staleness.sh`,
  which does not ship with shirabe — it lives only in a private plugin. The
  issue states plainly: "Users installing shirabe alone get a broken gate (the
  `command not found` exit code misroutes through introspection accidentally
  rather than meaningfully)." This is the closest match to the topic's premise:
  a tool absent from the host, and the run silently taking a wrong branch
  instead of stopping.
- **`tsukumogami/shirabe#215`** (CLOSED, fixed by PR #216). `preflight.sh` hard-
  required `CLAUDE_PLUGIN_ROOT`, which the harness does not export into Bash
  tool subprocesses. "A hard failure here blocks the entire single-pr
  `/execute` run." An environment assumption, not a tool absence, but the same
  failure class.
- **`tsukumogami/shirabe#270`** (CLOSED, fixed by PR #278). `plan-to-tasks.sh`
  used `local -A` (bash 4.0) and a nameref (bash 4.3); stock macOS ships bash
  3.2.57. "The script exits before emitting any tasks, so `spawn_and_await` has
  nothing to submit and the koto path cannot proceed. This is not exotic — it is
  any macOS developer who has not separately installed bash 5." The reporter
  listed three fix options, one of which is this topic verbatim: "add a version
  guard that fails with an actionable message naming the requirement."
- **`tsukumogami/shirabe#279`** (OPEN). `/execute`'s `orchestrator_setup`
  directive calls `koto context set`, a subcommand koto does not have. The
  follow-up comment is the most damaging evidence in the set: koto emits so much
  stderr noise that the reporter filtered it with `2>/dev/null`, which also
  swallowed `error: unrecognized subcommand 'set'`, so "the step *appears to
  succeed*." Consequence: all twelve children would have been dispatched against
  a branch that was never created. Reproduced independently on Linux.
- **`tsukumogami/shirabe#217`** (OPEN, friction log from the first real
  `/execute` run). Four of its nine numbered items are environment/version
  mismatches: item 3 (preflight false-fails on `CLAUDE_PLUGIN_ROOT`), item 4
  ("Version-path ambiguity" — three shirabe copies on disk, 0.12.0, 0.12.1-dev,
  0.13.1-dev, unclear which a run binds to), item 6 (`koto next` requires a
  positional the prose omits), item 7 (`koto --version` errors; the correct form
  is `koto version`).

**The adversarial finding.** None of these is the failure the topic names. The
topic frames the problem as a missing tool — koto, gh, jq, or the shirabe binary
absent from the host. I found no incident of `gh`, `jq`, or the `shirabe` binary
being absent, and no incident of koto being absent. What I found is four cases of
*version and surface skew* (a tool present at the wrong version, or a subcommand
that does not exist in the installed binary) and one case of a *file* that never
shipped (#80). A presence-and-version check as scoped would have caught #270 and
possibly #217 item 4; it would not have caught #279, #215, or #217 items 6-7,
which are skill prose naming a CLI surface the installed binary does not have.

## Q2 — What do people do today instead?

**Confidence: High.** Six distinct workarounds coexist, which is itself the
argument that no single place owns this.

1. **Prose in the skill body.** `skills/work-on/SKILL.md:176-182` — the only
   Prerequisites section in any SKILL.md: "Run `koto version` to verify koto >=
   0.3.3 is installed. If missing: `curl -fsSL .../install.sh | bash`." Git
   history (`git log -L 176,182`) shows it entered in PR #20 with floor 0.2.1
   and was bumped to 0.3.3 in PR #29. Hand-maintained, one skill only.
2. **`README.md` Requirements section** (lines 202-209) names Claude Code, the
   shirabe binary, and koto >= 0.3.3, and describes the prose check as the
   mechanism: "the skills check `koto version` first and give you an install
   command when it's missing." Read by humans before install, not by an agent
   mid-run.
3. **`.tsuku.toml` at the repo root** declares `"tsukumogami/koto" = "latest"`.
   It covers exactly one of the four tools, pins no floor (`latest`, not
   `>=0.3.3`, so it cannot express what the SKILL.md prose expresses), and
   `gh = "latest"` is commented out with `# disabled: segfaults on Linux
   (tsukumogami/tsuku#2245)`. So the declared-tools route exists and is already
   partial and already carrying a host-specific exception.
4. **Per-script guards, duplicated.** `skills/work-on/references/scripts/
   extract-context.sh:127-135` has a `check_prerequisites()` for `gh` and `jq`;
   `skills/plan/scripts/build-dependency-graph.sh:39`, `create-issues-batch.sh:
   140`, `plan-to-tasks.sh:1146`, and `render-template.sh:40` each re-implement
   a `jq` check; `skills/comp/evals/test-cli.sh:18` and
   `skills/brief/evals/test-cli.sh:26` each probe for the shirabe binary
   differently. `extract-context.sh:408` guards koto with `command -v`.
5. **`references/fixes/cli-version-preflight.md`.** This is the prose version of
   the topic, already shipped. It prescribes a `shirabe <subcommand> --help`
   probe, a `shirabe --version` detection step, a documented sed-edit fallback,
   and a four-step "preflight order summary." It is lazy-loaded — skills point
   at it only when a failure surfaces — so it is not a per-load tax, but it is
   prose describing a check rather than a check.
6. **CI encodes the host knowledge instead of the runtime doing it.**
   `.github/workflows/check-plan-scripts.yml` and `check-execute-scripts.yml`
   run a ubuntu/macos matrix, install `jq` per-OS (`apt-get` vs `brew`), and
   deliberately invoke `/bin/bash` on the macOS leg. The comment at lines 25-38
   is explicit that the matrix *is* the guard: "This matrix IS the guard against
   reintroducing a post-3.2 construct; there is deliberately no grep for
   `declare -A` and friends. A pattern list only catches what its author
   remembered."

Scale of the prose being replaced, measured: `jq` appears in 17 lines across
`skills/`, `gh <verb>` in 150, `shirabe <subcommand>` in 46 SKILL.md lines, and
`shirabe` in 78 files. Only one of those places states a requirement; the rest
just use the tool.

## Q3 — Who specifically asked?

**Confidence: Low** on breadth, **High** on identification.

Every citation traces to a single author, `dangazineu`, who is the repo
maintainer (`authorAssociation: MEMBER` on the #270 and #279 comments):

- `tsukumogami/shirabe#80` — issue body, options list including "Make the
  `staleness_check` gate conditional on script availability."
- `tsukumogami/shirabe#215` — issue body and acceptance criteria.
- `tsukumogami/shirabe#217` — friction log, items 3, 4, 6, 7.
- `tsukumogami/shirabe#270` — issue body ("add a version guard that fails with
  an actionable message naming the requirement") and the 2026-08-14 comment
  reproducing defect 1 on Linux.
- `tsukumogami/shirabe#279` — issue body and the 2026-08-15 comment on silent
  failure.
- `docs/prds/PRD-shirabe-pattern-v1-ergonomics.md` R30 and D3 — the only
  requirement in the repo that commits to a preflight contract.

No third-party issue, no comment from anyone else, no external adopter report.
There is no evidence anyone outside the maintainer has hit this or asked for it.

## Q4 — What behavior change counts as success?

**Confidence: Medium.** Three durable statements of desired behavior exist; none
is a measurable goal.

- **`skills/work-on/evals/evals.json`, eval id 10, `koto-not-installed`
  (tier 2).** The closest thing to an acceptance criterion for exactly this
  behavior, and it already exists with a fixture. Expected output: "Agent
  resolves issue #10, reads it successfully, detects koto is not installed when
  running koto version, then installs koto using the install script before
  proceeding." Five expectations, including the negative one: "Agent does NOT
  skip koto and fall back to manual orchestration."
  `skills/work-on/evals/fixtures/bin/koto` implements the scenario by exiting
  127 with `bash: koto: command not found`. So the repo already asserts the
  behavior it wants — via an eval over prose, not via a check.
- **`PRD-shirabe-pattern-v1-ergonomics.md` R30** (maintainer-authored, chain
  Accepted): "Any child SKILL body prescribing a `shirabe` subcommand SHALL
  surface a CLI-version preflight that detects whether the subcommand exists in
  the installed binary, with a documented fallback prose path (typically a
  manual sed-edit equivalent) when the subcommand is absent. The preflight
  mechanism — shell snippet inline, **capability detection at skill load**,
  parent-skill inheritance — is DESIGN territory." The emphasis is mine: the
  requirement names this topic's mechanism as an open option and leaves it to
  design.
- **`#215` acceptance criteria** — the shape a good check has: succeeds when the
  env var is unset, env var still takes precedence when set, and "the
  cross-skill child-template check remains the real assertion and still fails
  loudly when the template is missing."

Nothing anywhere states a token budget, a load-cost target, or a measurable
"silent and free when correctly configured" threshold. The premise that the
prose is a recurring tax is asserted in the exploration scope, not evidenced in
any issue or doc.

## Q5 — Is it already built?

**Confidence: Medium-High** that substantial partial work exists; **High** that
the specific thing is not built.

Not built:

- `crates/shirabe/src/` has no doctor-like surface. The `Commands` enum
  (`main.rs:64-101`) is `Validate`, `Roadmap`, `Transition`, `FinalizeChain`,
  `SlugPrefixDetect`, `InstallHooks`, `WorkSummary`, `PrBodyHook`. Grepping the
  crates for `doctor`, `command -v`, `which` returns nothing.
- No `scripts/` entry checks the environment. All ten are doc/template/eval
  checks (`check-sentinel.sh`, `check-template-interpolation.sh`,
  `validate-template-mermaid.sh`, etc.).

Built and adjacent:

- **`skills/execute/scripts/preflight.sh`** is a real, shipped preflight the
  skill runs at Step 1, with an eval asserting it runs before any child spawn
  (`skills/execute/evals/evals.json`, `cross-skill-work-on-path-preflight`). It
  checks exactly one thing — that `skills/work-on/koto-templates/work-on.md`
  resolves — and after PR #216 it self-resolves its own root from
  `BASH_SOURCE`. It is the existing proof that a skill can run a deterministic
  script early and halt on a non-zero exit.
- **`shirabe install-hooks`** is precedent for the binary writing to the host
  environment (a git pre-commit hook), with careful non-clobber classification
  (`classify_existing_hook`, `ExistingHook::{Ours,Framework,Other}`).
- **`references/fixes/cli-version-preflight.md`** — the prose contract, shipped.
- **The check-absorption chain** (`BRIEF-`/`PRD-`/`DESIGN-shirabe-check-
  absorption`, status Done) validates the general premise this topic rests on.
  The BRIEF's problem statement: "Some deterministic rules are written out as
  English in the workflow skills... The prose describes a rule a check could
  execute, but nothing keeps the prose and any executed check in step." Its
  disposition table classifies every candidate as A (pure over doc bytes), B
  (doc plus injected external state), C (cost-deferred), or D (judgment). Every
  row is a document check. Host and environment checks appear nowhere in the
  table — not absorbed, not deferred, not rejected. The precedent is
  encouraging; the scope never reached this.
- **Sibling precedent in the org:** `tsukumogami/tsuku` ships a `doctor`
  command. Its open bug tail is a cost signal worth carrying into design:
  tsuku#2507 ("doctor prints 'Everything looks good!' underneath its own WARN
  lines"), tsuku#2517 ("the orphaned-staging check matches a pattern nothing
  produces"), tsuku#2522, tsuku#2475, tsuku#2524. An environment checker is a
  maintained surface with its own failure modes, not a one-time write.

## Q6 — Is it already planned?

**Confidence: Low.**

- No BRIEF, PRD, DESIGN, or PLAN in `docs/` addresses host prerequisites. The
  47 designs in `docs/designs/current/` include no candidate; `docs/plans/`
  holds one unrelated PLAN; there is no `docs/roadmaps/` directory (removed in
  commit d432f13).
- The only planned commitment adjacent to this is **R30**, and
  `DESIGN-shirabe-pattern-v1-ergonomics.md` Decision 6 already resolved it as
  tier-2 lazy-loaded prose (`references/fixes/cli-version-preflight.md`) rather
  than a script. Two rejections in that decision bear directly on this topic's
  shape and should be read before re-proposing either:
  - *Inline shell snippet per SKILL.md:* "Rejected because inlining duplicates
    the pattern across seven SKILLs."
  - *Parent-skill inheritance running the probe once at chain entry:* "Rejected
    because the version-skew fires per-subcommand-invocation, not per-chain-
    entry; children invoked directly don't have a parent state file to inherit
    from."
- **`#80`** is the nearest open planned work: it asks for a DESIGN on
  `staleness_check` portability, with "Make the `staleness_check` gate
  conditional on script availability" as one of four options to evaluate. It is
  unassigned and unlabeled.
- The only artifact naming this exact topic is the exploration scope committed
  today (`dc8ef95`, `docs(explore): capture scope for skill-preflight-checks`),
  which lives under `wip/` and is non-durable by this repo's own hygiene rule.

## Calibration

**Demand is partially validated, and it is validated for a different problem
than the one the topic names.** This is not "demand not validated," and it is
emphatically not "demand validated as absent" — but it is not a clean green
light either.

What is validated (Medium-to-High): agents running shirabe skills do hit
environment mismatches, repeatedly, on more than one host, and those runs go
badly in exactly the way the topic anticipates — silently, taking a wrong branch
rather than stopping (#80's misrouted introspection, #279's swallowed error).
The workaround landscape is genuinely fragmented (six mechanisms, Q2), one
maintainer-authored requirement already commits to a preflight contract and names
"capability detection at skill load" as an open mechanism (R30), and an eval
already asserts the desired behavior (`koto-not-installed`, tier 2). The
general "prose restating a rule a check could execute" argument was accepted and
shipped for document checks in the check-absorption chain.

What is not validated (Low): that the failure is *tool absence*. Zero incidents
of `gh`, `jq`, the `shirabe` binary, or `koto` being absent. Four incidents of
version or subcommand-surface skew, which a presence check does not catch. The
"every load pays for that prose" premise has no supporting evidence in any
issue or doc — only one SKILL.md carries a Prerequisites section, and the
existing preflight prose (`cli-version-preflight.md`) is already lazy-loaded.
Breadth of demand is Low: one reporter, who is the maintainer, and no external
adopter has raised it.

**Two narrow negative signals, neither a rejection of the feature.** First,
`DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 evaluated and rejected the two
mechanisms nearest this topic's shape (per-skill inline snippet; once-per-chain-
entry probe) for R30, choosing lazy-loaded prose instead — a design that a
script-at-skill-load proposal must argue past, not around. Second, for the one
prerequisite where a maintainer was explicitly offered a version guard (#270's
bash 4 floor), PR #278 chose elimination and a CI matrix over a runtime check,
and the workflow comment argues the matrix is *better* than an enumerated check
because "a pattern list only catches what its author remembered." That reasoning
generalizes uncomfortably to a declared prerequisite list.

Neither constitutes positive evidence that host prerequisite checking was
evaluated and rejected. No closed PR, no de-scoping design section, no
maintainer comment declines it. The check-absorption chain simply never
considered host checks as candidates.

## Summary

Demand is real but narrower than the topic frames it: five durable incidents
(shirabe#80, #215, #217, #270, #279) show shirabe skills failing on mismatched
environments, several silently, but every one is version or subcommand skew or a
file that never shipped, and none is the plain tool absence a presence check
would catch. The workaround landscape is genuinely fragmented across six
mechanisms — SKILL.md prose, README Requirements, a partial `.tsuku.toml`,
duplicated per-script `jq`/`gh` guards, the lazy-loaded
`references/fixes/cli-version-preflight.md`, and a CI matrix that encodes the
bash 3.2 floor — and a maintainer-authored requirement (R30) already commits to
a preflight contract while explicitly leaving "capability detection at skill
load" open as a design choice. Nothing was rejected, but two design decisions
cut against the obvious shapes: R30's design already rejected both per-skill
inline snippets and a once-per-chain probe, and PR #278 chose portability plus a
CI matrix over the runtime version guard #270 offered, arguing that an
enumerated list "only catches what its author remembered."
