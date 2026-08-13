# Exploration Findings: vale-adoption

Round 1 complete. Five of six lead agents wrote full reports before the session
limit; the sixth (operational-cost) was run by the orchestrator directly with
Vale 3.17.1 installed. Every number below is measured on this workspace's own
corpus unless labelled otherwise.

## The premise was wrong, and correcting it reframes everything

The scope file says shirabe's writing-style rulebook is "applied entirely by
model judgment — nothing checks the output." That is false. `shirabe validate`
has shipped a deterministic banned-word check since June 2026: **FC10**,
`check_writing_style` at `crates/shirabe-validate/src/checks.rs:2572`, over a
hardcoded seven-word list at `checks.rs:2551` (`tier`, `tiered`, `robust`,
`leverage`, `comprehensive`, `holistic`, `facilitate`). Notice-level, registered
in the dispatch table at `validate.rs:208`, `--check FC10` selectable, five unit
tests, shipped in PR #172.

Architecturally FC10 *is* a hand-rolled Vale-lite: one `existence` rule over
seven tokens with a resolution pointer. So the question was never "should
shirabe mechanize prose checking." It already did. The question is whether Vale
should **replace and widen** that check — and separately, whether anything at
all should cover the files FC10 structurally cannot see.

## What Vale would actually catch here (measured)

A faithful translation of `skills/writing-style/SKILL.md` classifies into 38
rules: 16 fully mechanizable (A), 9 mechanizable-with-false-positives (B), 6
partial (C), 7 out of reach (D). A+B = 66% by raw count. That ratio is
misleading, and the empirical run is what matters:

**The high-precision half is the half the model already obeys.** Across 554,000
words of real shirabe prose, the entire class-A phrase apparatus — 15 of 16
rules, covering "it's worth noting", "in conclusion", "at its core", "delve
into", "I hope this helps", "as of my training" — produces **roughly two true
alerts**. Nearly every hit is `writing-style/SKILL.md` quoting the rule itself.
Those rules would run green forever.

**The word list fares worse.** Orchestrator-run measurement with a custom
Shirabe style over `docs/` (145 files, 463k words): 156 alerts, of which 128 are
`tier`/`Tier`/`tiered`. In shirabe, "Tier 1–4" is the defined complexity-routing
vocabulary of `DESIGN-decision-framework.md` and `DESIGN-plan-review.md`. The
lead agent's wider run adds `journey`/`journeys` at 112 hits — and `## User
Journeys` is a *required section heading* in the BRIEF and PRD templates
(confirmed at `docs/briefs/BRIEF-execute-skill.md:82`, enforced by FC04). Raw
precision on the word rules measures **1.7%**; after excluding the two domain
terms and the PRD that quotes the rulebook, about **16%** on 31 alerts.

**One rule carries the entire empirical case: em dash density.** Measured
directly: 3,195 em dashes in `docs/`, 1,222 in `skills/` — 7.84 and 7.59 per
thousand words, with 72% of `docs/` files over 3/1000 and worst offenders at
28.5/1000. Only 27 of them are in table cells; this is prose. An `occurrence`
rule at `scope: paragraph, max: 1` would flag 679 of 5,776 paragraphs (11.8%);
at `max: 2`, 246 (4.3%). The rulebook names em dash overuse as a formatting
tell, and the corpus that rulebook governs is saturated with it.

The reason matters more than the number: **frequency is a document-level
property invisible to a model composing one sentence at a time.** This is a
defect model judgment structurally cannot catch, and a counter trivially can.
Bold density (10.9 runs per 1000 words) and burstiness (a `script` rule
computing sentence-length stdev; flags 5–8 files per tree) are the same shape.
Contractions are already fine — the corpus ratio is 0.30, and turning on
`Microsoft.Contractions` as shipped would emit 1,892 wrong alerts.

## What Vale provably cannot catch

Orchestrator-run demonstration. A three-paragraph document of fluent, grammatical,
entirely vacuous prose ("The system is designed to handle the needs of the
platform. Its components work together in a way that supports the goals of the
project.") linted against write-good + proselint + Microsoft produced **10
alerts, none about the vacuity**. The single `error`-level alert — the only one
that would fail CI — was *"Use 'we've' instead of 'we have'."*

That is the shape of the ceiling. Vale is a markup-aware regex engine; its Tengo
`script` sandbox is deliberately closed to `os` and the network
(`internal/check/script.go` carries the maintainer comment declining it), so no
rule can ever consult anything beyond the text block it was handed. The four
cognitive tells in the rulebook — low information density, empty conclusions,
"this/that" without antecedent, uncited attribution — are permanently out of
reach, and so is the entire "What human writing has" section. A linter can only
subtract; it cannot make prose have a point of view.

Related: Vale ships a POS tagger and **none of the 143 rules across its six
flagship style packages use it**. Both write-good's and Microsoft's passive-voice
rules are the same regex, which flags "is red", "was tired", and "are excited"
as passive voice.

## Off-the-shelf styles are actively harmful on this corpus

Measured on shirabe's own `CLAUDE.md` with Microsoft + write-good + proselint:
**169 alerts in 1,636 words** (103/1000). Representative:

- `'Repo Visibility: Public' should use sentence-style capitalization` — a header
  shirabe's own FC-CONVENTIONS check parses by exact string
- `'shirabe' should use sentence-style capitalization` — deliberately lowercase
- `'BRIEF' has no definition`, `'PRD' has no definition`, `'PLAN' has no
  definition`, `'SKILL' has no definition` — artifact type names defined in that
  very section

Density across skills: `execute/SKILL.md` 645 alerts (107/1000),
`plan/SKILL.md` 222 (69/1000), `design/SKILL.md` 77 (48/1000). SKILL.md files are
instructions to a model, where imperative voice, bold labels, and "You MUST" are
load-bearing and correct. Adopting a stock style would demand changes that break
the validator. If Vale is adopted, the style must be hand-written from shirabe's
own rulebook — `Packages = Microsoft` would discredit the tool in week one.

## Three defects found along the way, independent of the Vale decision

1. **FC10 reports wrong line numbers.** It uses `idx + 1` over `doc.body`, which
   is post-frontmatter with no offset applied. A hit on file line 16 reports as
   line 10. Default output is GitHub Actions annotations, so every FC10
   annotation in CI points at the wrong line.
2. **FC10 has no markup awareness and produces false positives.** It scans raw
   body lines including fenced code and URLs; verified firing on
   `tier_config --leverage` inside a bash fence and on
   `https://example.com/robust-guide`.
3. **FC-CONVENTIONS is unreachable dead code.** `check_claude_md_conventions`
   (`checks.rs:3167`) gates on `basename == "CLAUDE.md"`, but `detect_format`
   (`formats.rs:248`, confirmed) prefix-matches only `COMP-`, `DESIGN-`, `PRD-`,
   `VISION-`, `ROADMAP-`, `PLAN-`, `STRATEGY-`, `BRIEF-` and returns `None`
   otherwise, so `validate_file` is never called for it. Fully unit-tested,
   documented, cited in shirabe's own CLAUDE.md as the reason a header exists,
   and it has never fired.

## The coverage gap is real, and it is not where the rulebook is

Because `detect_format` is a prefix match, **`shirabe validate` cannot see a
single SKILL.md, CLAUDE.md, AGENTS.md, or README.md.** Verified: running the
validator over all four returns "All checks passed", exit 0. CI compounds it —
`validate-shirabe-docs.yml` triggers on `docs/**` and `crates/**`, so a PR
touching only `skills/**` never runs the validator at all. Counts: 28 SKILL.md
and 6 CLAUDE.md/AGENTS.md files across the public repos; shirabe's `skills/**`
alone is 211 files and 197,538 words, all mechanically unchecked.

This is genuinely uncovered ground and it maps exactly onto the author's first
named target. But note it could also be closed by relaxing FC10's format gate —
a smaller change than adopting a new tool.

## The rulebook exists in four divergent copies

| Location | Scope | Enforcement |
|---|---|---|
| `skills/writing-style/SKILL.md` | 47 words (7+15+10+8+7 across five categories), 7 phrases, 7 structural, 5 formatting, 6 substitutions, 4 cognitive | model judgment |
| `crates/shirabe-validate/src/checks.rs:2551` | 7 words | deterministic, notice |
| workspace `CLAUDE.md` quick reference | 5 entries | model judgment |
| `skills/brief/references/phases/phase-4-validate.md:244` | 5 entries | jury agent judgment |

Plus a fifth, dangling: workspace CLAUDE.md points at
`.claude/helpers/writing-style.md`, which does not exist. And the design that
specified FC10 (`DESIGN-shirabe-pattern-v1-ergonomics.md:227`) explicitly
required the validator read the list from the SKILL.md at validate-time "so
future reference updates propagate without a validator code change." The
implementation hardcodes it. The four-way divergence is the direct consequence.

**A single versioned rule source collapsing four copies into one is the
strongest structural argument for Vale in this investigation — stronger than the
detection-quality argument, which the data does not support.**

## Demand: absent for Vale, real but discharged for the underlying problem

These must not be merged. Demand for *mechanized writing-style enforcement* was
real and is recorded in a durable maintainer-authored artifact
(`PRD-shirabe-pattern-v1-ergonomics.md:679-684`): banned words "recur in shirabe
documents despite the writing-style reference." That became R20, AC4.3, and
shipped FC10. It is discharged demand, not open demand.

Demand for *Vale* is absent: zero mentions across all six public repos' issues,
PRs, commits, and design docs. The only `vale` artifact is
`recipes/v/vale.toml`, added by an automated Homebrew batch (PR #1473, "4
recipes included, 0 excluded", `llm_validation = "skipped"`) off a
download-count queue. Vale entered tsuku because Homebrew users download it.
Installation being solved is a real cost reduction, but it is not evidence of
demand.

No positive rejection of Vale exists either. Two adjacent rejections are on
record and both reject *shapes* a Vale proposal might take: pre-commit hooks as
the writing-style surface, and prose checks in the jury ("mechanical checks
belong in the validator; only natural-language checks belong in the reviewer
set"). Neither names Vale.

There is also a declared next move already written into the code
(`validate.rs:317-321`): clean the corpus, then promote FC10 from notice to
error. No cleanup issue exists and the corpus is not clean.

## Ecosystem evidence cuts against the transfer

Vale is genuinely well adopted — GitLab (82 rules over 2,827 pages in under 20
seconds), Datadog, Docker, Spotify, NVIDIA, ~85 others with verifiable
`.vale.ini` files. But every documented deployment solves the same problem:
**many human contributors of uneven skill, more PRs than reviewers, consistency
needed across people.** Vale raises a floor across contributors. This workspace
has one author, already given the rules in-context, already jury-reviewed.
There is no floor to raise.

- **Zero published measurements** exist, anywhere, of a prose linter improving
  prose in an agent revision loop. The pattern is implemented in at least three
  places (a Claude Code PostToolUse hook, an MCP server, a skill linter) and
  measured in none.
- **The best research finding**: every discriminative result on AI-writing
  markers in the literature is **corpus-level, not per-text**. These rules can
  be style nudges but never verdicts. Worse, "several markers invert for
  well-formed Simplified Technical English" — some AI-slop rules penalize good
  technical writing.
- **Goodhart is named in the source material.** Wikipedia's "Signs of AI
  writing", the origin of three of the four Vale AI-tell packages, warns: "do
  not merely treat these signs as the problems to be fixed; that could just make
  detection harder." An agent iterating to zero alerts optimizes the surface and
  leaves the flatness.
- **A ~250x adoption gap** favors the approach shirabe already has: a
  prompt-based anti-slop *skill file* has 15.6k stars; the best Vale AI-tells
  package has 62. All four AI-tell packages are under a year old,
  single-maintainer, with one self-reported precision number between them.
- **Nobody credible argues linter-instead-of-judge.** The Vale-MCP author built
  the integration because Vale "has no context of what you're actually writing";
  LintMe's own design is hybrid; Factory.ai frames it as "AGENTS.md = the why,
  linting = the how."

The one argument that survives all of this: **shirabe's jury is the same model
family reviewing its own prose, and self-enhancement bias in LLM judges is well
documented.** A deterministic check catches the mechanical half regardless of
what the jury feels like that day, offline, in 0.44 seconds for 463k words
(measured).

## Where it could go

The CLI anti-pattern does **not** bar this. A prose linter never produces a
body; it consumes one and emits `(code, severity, message, file, line)` —
literally shirabe's `ValidationError` shape and literally Vale's JSON shape. It
lands on the `validate` side, and FC10 is the settled precedent.

| Candidate | Verdict |
|---|---|
| `shirabe validate` gains a prose check | **Strongest for target 2.** Reaches 3 adopter repos via the reusable workflow, propagates to `/scope` and `/charter` through existing pass-throughs. Must *replace* FC10, not sit beside it. Cannot reach SKILL.md without changing `detect_format`. |
| Claude Code `PostToolUse` hook | **Uniquely well-matched to target 1.** Only candidate that catches prose at authoring time on any file with no prefix gate. Workspace-local; does not travel to adopters. |
| Standalone CI job | Viable, and reaches `skills/**` today. 14-line pattern already established (`check-sentinel.yml`). Double-reports on `docs/**`. |
| A step in each skill's Phase 4/6 jury | **Reject.** This is the mechanism that created the four-way drift. BRIEF step 8 is copy #4. |
| A skill that runs vale | **Reject as enforcement.** `charter/phase-finalization.md:142` explicitly forbids skills re-implementing validator checks. |
| koto gate | **Rules itself out.** Only `work-on` and `execute` have koto templates; every document-authoring skill is wip/-based. A koto gate covers the workflows that write code and misses every workflow that writes prose. |

Native vs shell-out is the live design question. `regex` is already a
`shirabe-validate` dependency and the validator already shells out to `gh` and
`git` with a graceful-degradation precedent (FC09's "Auth skip" notice). But
native means writing markup-aware scoping shirabe does not have — which is
exactly where FC10's verified false positives come from.

## Open questions for the crystallize decision

1. **Target 1 and target 2 have different answers.** Skills/instructions are
   uncovered ground reachable only by a hook or CI job; drafted artifacts are
   covered ground where the question is replace-FC10-or-not. Deciding them as
   one produces a design that half-works.
2. **Is em dash density (plus bold density and burstiness) enough to justify a
   new tool?** It is the one measured defect model judgment structurally cannot
   catch. Everything else Vale would add measures near-zero true positives.
3. **Would fixing FC10 get most of the value?** Fix the line-number offset, add
   markup awareness, relax the format gate to cover SKILL.md, read the word list
   from the SKILL.md as the design originally required, add an em dash
   occurrence rule. That is a smaller change than a new binary dependency in
   four repos' CI.
4. **Gate or report?** The Goodhart evidence argues report; the four-way drift
   argues single-source. Vale's exit code only goes non-zero on `error`-level
   alerts, so a naive gate passes everything.
5. **Who maintains the style?** Every adopter reports ongoing rule tuning as a
   real cost, landing on one person here.

## Decision: Crystallize
