# Demand validation: Vale adoption in the tsukumogami workspace

Round 1 — lead-adversarial-demand. Visibility: Public.

## Method and sources searched

- Git history in `public/shirabe`, `public/tsuku`, `public/koto`, `public/niwa`
  (commit messages, `-S` pickaxe on `check_writing_style`, path-scoped logs).
- GitHub issues and PRs across `tsukumogami/shirabe`, `tsukumogami/tsuku`,
  `tsukumogami/koto`, `tsukumogami/niwa`, plus org-wide `gh search issues` and
  `gh search prs`.
- Durable docs: `docs/briefs/`, `docs/prds/`, `docs/designs/current/` in shirabe;
  `docs/designs/` in tsuku and niwa.
- Source: `crates/shirabe-validate/src/`, `crates/shirabe/src/main.rs`.
- CI: `.github/workflows/` in shirabe and tsuku.
- Config surfaces: workspace `CLAUDE.md`, `public/dot-niwa/.niwa/claude/workspace.md`,
  `public/.github/CONTRIBUTING.md`.
- Recipe provenance: `public/tsuku/recipes/v/vale.toml`,
  `public/tsuku/recipes/discovery/v/va/vale.json`, `data/queues/`.

Private repos were read for context only. Nothing from them appears below.

---

## Q1 — Is demand real?

**Confidence: Medium (for mechanized writing-style enforcement).
Absent (for Vale specifically).**

There is one durable, maintainer-authored statement of the underlying problem.
`docs/prds/PRD-shirabe-pattern-v1-ergonomics.md:679-684` records it as an
explicit meta-observation:

> The mechanical writing-style banned-word detection (R20) is itself a meta
> observation surfaced when authoring this chain. Phrases like "robust",
> "leverage", "comprehensive", "holistic", "facilitate", "tier", "tiered" recur
> in shirabe documents despite the writing-style reference banning them; DESIGN
> picks the surface that catches them mechanically.

That is a direct admission that skill-prose-only enforcement failed, written by
the maintainer, in a document that reached Done and shipped code. It is real
demand — but it is demand for a *seven-word banned-word grep*, and it was
already satisfied (see Q5).

The corpus confirms the underlying pattern still holds. A scan of shirabe's
`docs/` for the seven FC10 words returns 161 occurrences on 114 lines across 20
files. But the distribution undercuts the case: 135 of those 161 are the word
"tier", and 87 of those are `Tier N` / `tier-N` — shirabe's own term of art for
its lazy-load tiers and its decision-complexity tiers
(`docs/specs/decision-points.md`, `docs/designs/current/DESIGN-decision-framework.md`,
`docs/designs/current/DESIGN-plan-review.md`). Strip the term-of-art usage and
the real violation count across the entire shirabe doc corpus falls to roughly
26 occurrences: 7 "robust", 5 "leverage", 4 "comprehensive", 3 "holistic",
3 "facilitate", 4 "tiered". That is the measured size of the problem a prose
linter would attack on this corpus, and it is also a preview of the
false-positive burden.

For Vale itself: **zero mentions in any public repo**. `gh search issues --owner
tsukumogami "vale"` returns empty. `gh search prs` returns exactly two hits, both
the same automated recipe batch (Q5). No mention in shirabe's `docs/`, `crates/`,
`skills/`, `README.md`, or `CLAUDE.md`. No mention in koto, niwa, dot-niwa, or
`.github`.

## Q2 — What do people do today instead?

**Confidence: High.** The current stack has four layers, all found in durable
artifacts.

**1. The `writing-style` skill (model judgment).** `skills/writing-style/SKILL.md`
— a 73-line rulebook of banned words, phrases, structural patterns, formatting
tells, cognitive tells, and positive guidance. Eleven skills point at it with an
identical line: `**Writing style:** Read skills/writing-style/SKILL.md for
guidance.` (`skills/prd/SKILL.md:23`, `skills/design/SKILL.md:22`,
`skills/explore/SKILL.md:27`, `skills/plan/SKILL.md:23`,
`skills/brief/SKILL.md:42`, `skills/strategy/SKILL.md:50`,
`skills/roadmap/SKILL.md:58`, `skills/vision/SKILL.md:32`,
`skills/comp/SKILL.md:35`, `skills/decision/SKILL.md:24`,
`skills/review-plan/SKILL.md:19`). `README.md:56` states the contract: "`/writing-style`
runs automatically whenever shirabe drafts prose, so you don't [have to ask]".

**2. Jury reviewers (model judgment, per-artifact).**
`skills/brief/references/phases/phase-4-validate.md:244-247` gives the structural-format
reviewer an explicit writing-style step: "Check the prose against the
writing-style rules: no 'tier/tiered', 'robust', 'leverage',
'comprehensive/holistic', or 'facilitate'; direct prose without preamble; no
emojis; no AI attribution. Flag specific offending phrases." Note that this is
the same seven words, re-stated as an instruction to an LLM reviewer.

**3. FC10, a deterministic banned-word check in `shirabe validate`.** See Q5.

**4. CLAUDE.md prose.** The workspace `CLAUDE.md` "Writing Style" section and
`public/dot-niwa/.niwa/claude/workspace.md:74-86` both carry the same seven-word
quick reference with substitutions.

The notable structural fact: **the same seven-word list is duplicated in four
places** — the Rust constant `FC10_BANNED_WORDS`
(`crates/shirabe-validate/src/checks.rs:2550-2558`), the jury reviewer prose, the
workspace `CLAUDE.md`, and `dot-niwa`'s `workspace.md`. The `writing-style`
SKILL.md itself carries a much longer list (roughly 50 words plus phrase and
structural rules) that none of the mechanized surfaces implement.

**Also found: an explicitly documented deviation.** The design specified that
FC10 read the banned list from `skills/writing-style/SKILL.md` at validate-time
so "future reference updates propagate without a validator code change"
(`docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md:227` and `:396`).
The shipped implementation hardcodes the list, and the code comment at
`crates/shirabe-validate/src/checks.rs:2538-2549` argues the AC's intent is still
satisfied because "this constant is the authoritative compile-time copy". That
is a live single-source-of-truth gap that a Vale config file would, on its face,
close.

**No prose or markdown linter is in use anywhere in the workspace.** Grepping
all public repos for `markdownlint`, `remark-lint`, `textlint`, `proselint`,
`write-good`, `alex`, `LanguageTool`, and `ltex` returns only tsuku
recipe-registry data files (`data/disambiguations/audit/proselint.json`,
`markdownlint-cli.json`, `markdownlint-cli2.json`, `languagetool.json`,
`ltex-ls.json`) and the discovery queues. Those are packages tsuku knows how to
install, not tools tsuku uses.

## Q3 — Who specifically asked?

**Confidence: High that the answer is "nobody, for Vale."**

Every issue and PR in every public repo in this org is authored by
`@dangazineu` — a single maintainer, who is also the user requesting this
exploration. There are no distinct reporters, no external requests, no
maintainer-assigned labels on a Vale request, because there is no Vale request.

The nearest thing to a request is the maintainer's own R20 requirement
(`docs/prds/PRD-shirabe-pattern-v1-ergonomics.md:299-304`), which asked for
"mechanical writing-style banned-word detection" and left the mechanism to
DESIGN. That request was fulfilled in June 2026.

No PR review comment complaining about writing quality was found.
`gh search issues --owner tsukumogami` for `"AI tell"`, `"reads like AI"`,
`"AI-sounding"`, `"prose linter"`, and `"documentation quality prose"` all return
empty. No commit in any repo fixes prose for writing-quality reasons — commit-message
greps for `writing style`, `AI tell`, `em dash`, `humanize`, `prose lint`,
`proselint`, and `vale` return only false positives (matches on "prose surgery",
"MarshalText", and similar).

## Q4 — What behavior change counts as success?

**Confidence: High** — acceptance criteria exist, but they are FC10's, not Vale's.

`docs/prds/PRD-shirabe-pattern-v1-ergonomics.md:510-514`, AC4.3:

> A document containing any of "robust", "leverage", "comprehensive", "holistic",
> "facilitate", "tier", "tiered" is surfaced by the mechanical writing-style
> check at the surface DESIGN chooses (validator notice, Phase 4 reviewer,
> pre-commit hook).

AC8.2 (`:571-574`) adds a sequencing criterion: "the writing-style mechanical
check (R20) lands alongside the writing-style reference it enforces."

There is a stated forward trajectory too. `crates/shirabe-validate/src/validate.rs:317-321`
carries a test comment naming the intended end state:

> SCHEMA, FC07-FC13, and FC-CONVENTIONS are the notice-level codes for v1. Each
> ships notice-level pending its respective corpus-cleanup PR; removing any arm
> from is_notice promotes the corresponding check to error in a one-line diff.

So the declared success condition for writing-style enforcement is: clean the
corpus, then flip FC10 from notice to error. No corpus-cleanup PR or issue for
FC10 exists — `gh issue list --search "corpus-cleanup"` returns nothing, and the
161-occurrence measurement above shows the corpus is not clean. FC10 has sat at
notice level for over two months.

No acceptance criteria, stated outcome, or measurable goal for Vale exists
anywhere.

## Q5 — Is it already built?

**Confidence: High. Substantially yes, in narrow form.**

**FC10 is a shipped, tested, deterministic prose check.** `check_writing_style`
in `crates/shirabe-validate/src/checks.rs:2561-2613` scans document bodies for
seven banned words, case-insensitively, whole-word only (hand-rolled
byte-boundary matching, no regex dependency), and emits one notice per hit with
file path, line number, and matched word, pointing the author at
`skills/writing-style/SKILL.md` for alternatives. It is registered as a
cross-format check that runs for every artifact type
(`crates/shirabe-validate/src/validate.rs:205-208`), is severity-registered as a
notice (`:90`, `:163`), and is `--check`-selectable (`:153-166`). Five unit tests
cover it (`checks.rs:6078-6130`). It shipped in commit `8dbcbea`, shirabe PR #172,
2026-06-06.

Architecturally, FC10 *is* a hand-rolled Vale-lite: the `existence` rule type,
applied to seven tokens, with notice severity and a resolution pointer. Vale's
value proposition over it is breadth (the other ~43 SKILL.md words, phrase
patterns, structural patterns) and configurability, not the core mechanism.

**The delivery surfaces are also already built.**
`docs/prds/PRD-shirabe-cli-multi-consumer.md` (status: **Done**) widened
`shirabe validate` into a three-consumer tool — CI, the workflow skills, and
local pre-commit hooks — with `--format json` / `--format human`, per-check
selection, and a multi-level exit-code contract. R7 of that PRD shipped as
`shirabe install-hooks` (`crates/shirabe/src/main.rs:81-85`, `:162`), which writes
a pre-commit hook (`crates/shirabe/src/main.rs:1209-1237`) that collects staged
`*.md` NUL-safely and runs `shirabe validate --format human`. Per-consumer
contract documented at `docs/guides/multi-consumer-cli-contract.md`.

**Two real coverage gaps remain, and both are exactly the topic's stated targets.**

1. **Skills and agent instructions are never checked.** `validate_doc` gates on
   schema resolution first — `check_schema` short-circuits and returns before any
   FC check runs (`crates/shirabe-validate/src/validate.rs:185-187`). A `SKILL.md`
   carries `name:`/`description:` frontmatter, not `schema:`, so it is skipped
   entirely. The generated pre-commit hook comment states this outright: "shirabe's
   own format detection skips any non-artifact .md file."
2. **CI only fires on `docs/**`.** `.github/workflows/validate-shirabe-docs.yml:11-18`
   triggers on `docs/**`, `crates/**`, `Cargo.toml`, `Cargo.lock`,
   `rust-toolchain.toml`, and the two workflow files. A PR touching only
   `skills/**` or `README.md` never runs the validator at all.

So a Vale proposal aimed at SKILL.md files and READMEs is aimed at genuinely
uncovered ground. A Vale proposal aimed at shirabe's `docs/` artifacts largely
duplicates a shipped check.

**The `vale` recipe is not an adoption signal.** `public/tsuku/recipes/v/vale.toml`
was added in commit `73ba3d28` (2026-02-05), titled "feat(recipes): add batch
homebrew recipes (4 recipes)", landing `cloc`, `dust`, `swift-sh`, and `vale`
together from the automated homebrew pipeline. PR #1473 body: "Batch homebrew
recipe generation: 4 recipes included, 0 excluded." The recipe carries
`llm_validation = "skipped"`. Its provenance file
`recipes/discovery/v/va/vale.json` records `"builder": "homebrew"`, `"downloads":
53138` — a popularity-ranked queue entry. Vale entered tsuku because Homebrew
users download it, not because anyone here chose it. (This does mean installation
is solved, which is a genuine cost reduction — just not evidence of demand.)

## Q6 — Is it already planned?

**Confidence: High that Vale is not planned. Medium-High that a competing
direction is.**

No open or closed issue, roadmap item, design doc, or spike in any public repo
mentions Vale or prose linting. `docs/roadmaps/` does not exist in shirabe. The
tsuku, koto, and niwa issue trackers return nothing.

What *is* planned, and what any Vale proposal collides with:

- **Promote FC10 from notice to error after a corpus cleanup**
  (`crates/shirabe-validate/src/validate.rs:317-321`). Not yet scheduled as an
  issue, but written into the code as the intended next move.
- **`shirabe validate` as the single correctness engine.** shirabe's `CLAUDE.md:165-187`
  makes this a hard architectural rule: "**`shirabe validate` is the
  feedback/correctness engine.** It tells the agent what to fix and why. New
  correctness rules belong here as checks or modes... never in a renderer,"
  with a named anti-pattern and a worked example of a subcommand that was
  *removed* for violating it.

### Rejection evidence found

Two decisions in `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`
bear directly on candidate Vale deployment models. Neither names Vale, so neither
is a rejection *of Vale*, but both reject shapes a Vale proposal would likely take.

**Pre-commit hook as the writing-style surface — rejected** (`:239`):

> **Pre-commit hook for R20**: a git pre-commit hook runs the writing-style grep
> before commit. Rejected because pre-commit hooks block authors mid-flow and the
> workspace already has a validator surface for advisory notices; adding a hook
> layer is a new mechanism the workspace doesn't need.

Note this position later softened: `PRD-shirabe-cli-multi-consumer.md` (Done)
shipped `shirabe install-hooks` anyway. But the objection that survived is
"adding a hook layer is a new mechanism the workspace doesn't need" — the hook
that shipped runs the *existing* validator, adding no new tool.

**Prose checks in the jury — rejected** (`:237`):

> R20's mechanical grep would gain a per-DESIGN-judgment cost for a check that
> doesn't need judgment. Rejected because structural checks belong in the
> validator and mechanical checks belong in the validator; only natural-language
> checks belong in the reviewer set.

**And a standing cost objection to the validator route** (`:119`):

> adding new checks requires Rust code and a release-train cut (the validator
> ships as a Rust binary via `shirabe transition`). Skill-prose edits ship with
> the SKILL.md changes themselves; they don't require a binary release. The
> driver favors skill-prose unless the check is structural.

This last one cuts *for* Vale on one axis: a Vale config is data, not Rust, so
extending the banned list would not need a binary release. It cuts against on
another: it is a new external binary dependency in a workspace whose stated
posture is that validate is the one correctness engine.

---

## What a Vale proposal has to answer

Not a verdict — the evidence just makes three questions unavoidable.

1. **Overlap.** On shirabe `docs/`, FC10 already covers the seven words the
   maintainer complained about. What does Vale catch there that FC10 doesn't, and
   is 26 real violations across the whole corpus worth a second engine?
2. **The uncovered ground is real.** SKILL.md files, READMEs, and agent
   instructions get zero mechanical checking today, by construction (schema gate
   + `docs/**` CI filter). That gap is genuine. But it could also be closed by
   relaxing FC10's schema gate — a smaller change than adopting a new tool.
3. **False positives are measurable now, not hypothetical.** 87 of shirabe's 135
   "tier" hits are its own term of art (`Tier 1`, `Tier 4`). Any prose linter over
   this corpus starts with a 54% false-positive rate on its highest-frequency
   rule. This is the strongest single piece of evidence in this report, and it
   applies to FC10 today as much as it would to Vale.

---

## Calibration

**Demand is not validated for Vale. It is partially validated — and already
discharged — for the underlying problem.**

These are two different findings and must not be merged:

**Validated (Medium confidence): demand for mechanized writing-style enforcement
existed.** One maintainer-authored durable artifact
(`PRD-shirabe-pattern-v1-ergonomics.md:679-684`) explicitly records that banned
words recur despite the writing-style reference. It has an explicit requirement
(R20), an acceptance criterion (AC4.3), a design decision, and shipped code
(FC10, PR #172). This is not speculation. It is also, on the evidence, **already
satisfied for the corpus it was raised about** — which is why it counts as
discharged demand, not open demand.

**Not validated (Absent): demand for Vale.** Searched issues, PRs, commits,
design docs, PRDs, briefs, roadmaps, CI config, and code comments across all six
public repos. Zero mentions of Vale outside an auto-generated package recipe.
Zero mentions of any prose linter as a tool under consideration. No user asked;
no maintainer acknowledged; no acceptance criteria exist. This is a genuine
evidence gap, not evidence of rejection — the repo simply has never considered
the question, which is consistent with the user's own framing that they have
never used Vale.

**Not validated as absent — no positive rejection of Vale exists.** No closed PR
rejects it, no design doc de-scopes it, no maintainer comment declines it. The
two rejections found (pre-commit hooks as the writing-style surface, prose checks
in the jury) are rejections of *deployment shapes*, decided before
`shirabe install-hooks` shipped and without Vale in view. Citing either as "Vale
was rejected" would misread the record.

**One caveat on the demand signal's strength.** All six public repos have a
single issue author. Confidence vocabulary that keys on "distinct issue
reporters" and "maintainer acknowledgment" cannot reach High here for any
demand question, because reporter and maintainer are the same person. The
Medium ceiling on Q1 is structural to this workspace, not a judgment about the
maintainer's observation.

**What another round could surface that this one couldn't.** Whether FC10 has
actually fired in practice and been acted on (validator run logs and PR
annotations are not durable artifacts). Whether the ~43 SKILL.md rules FC10
doesn't implement were deliberately scoped out or simply not reached. And
whether the schema-gate exclusion of SKILL.md files was a deliberate decision or
an unexamined consequence of `check_schema` short-circuiting.

## Summary

Demand for Vale specifically is absent from the durable record — zero mentions
across all six public repos' issues, PRs, commits, and design docs, with the only
`vale` artifact being an auto-generated Homebrew recipe batch (PR #1473) that
tsuku's pipeline produced from a download-count queue. Demand for the underlying
capability is real but already discharged: the maintainer recorded in
`PRD-shirabe-pattern-v1-ergonomics.md:679-684` that banned words recur despite
the writing-style skill, and that observation became R20, AC4.3, and the shipped
FC10 check in `shirabe validate` (PR #172), alongside a design decision that
mechanical prose checks belong in the validator rather than the jury or a new
hook layer. Two facts should shape any recommendation: skills and agent
instructions are structurally exempt from all mechanical checking today (the
schema gate at `validate.rs:185-187` plus the `docs/**` CI filter), which is
genuinely uncovered ground, while a corpus scan shows 87 of shirabe's 135 "tier"
hits are its own term of art — a 54% false-positive rate on the highest-frequency
rule before any new tool is introduced.
