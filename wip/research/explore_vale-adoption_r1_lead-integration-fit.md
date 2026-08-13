# Lead: Where would Vale fit shirabe's existing enforcement machinery without duplicating it?

## Findings

### The headline: shirabe already has a prose linter, and it is FC10

The scope framing for this exploration says shirabe's `writing-style` skill is
"a 73-line rulebook applied by model judgment alone." That is not accurate.
`shirabe validate` has shipped a deterministic writing-style check since the
pattern-v1 ergonomics work: **FC10**, `check_writing_style`, at
`crates/shirabe-validate/src/checks.rs:2572`.

It is a case-insensitive whole-word grep over the document body against a
hardcoded seven-word list at `checks.rs:2551`:

```rust
const FC10_BANNED_WORDS: &[&str] = &[
    "tier", "tiered", "robust", "leverage",
    "comprehensive", "holistic", "facilitate",
];
```

It emits notice-level `ValidationError`s carrying file, line, code, and a
message pointing back at `skills/writing-style/SKILL.md`. It is registered in
the dispatch table at `crates/shirabe-validate/src/validate.rs:208`, runs on
every format (not per-format), and is listed as selectable via
`--check FC10`.

So the question is not "should shirabe get a prose check." It has one. The
question is whether Vale should **replace and widen** it. That reframing
changes the answer to almost every sub-question below.

### How much of the rulebook FC10 actually catches

`skills/writing-style/SKILL.md` (74 lines) is a much larger rulebook than the
constant: roughly 60 banned words across five categories, ~7 banned phrases,
7 structural patterns, 5 formatting tells, 6 over-formality substitutions, and
4 cognitive tells.

I built the binary in this worktree and measured. A deliberately tell-saturated
BRIEF containing 17 distinct rulebook violations produced exactly **5 findings**
— all from the seven-word list. Everything else passed clean:

| Violation planted | Rulebook section | FC10 caught it |
|---|---|---|
| tiered, robust, leverage, comprehensive, holistic | Avoid: words | yes (5) |
| Additionally (adverb opener) | Avoid: words | no |
| seamless, utilizes, journey, narrative, testament, tapestry, showcase | Avoid: words | no |
| "it's worth noting" | Avoid: phrases | no |
| "serves as" | Structural patterns | no |
| "in order to" | Over-formality | no |
| em dash | Formatting tells | no |

Coverage against its own canonical source is roughly 5 of 17 on that sample —
under a third, and zero coverage of the phrase, structural, formatting, and
cognitive categories, which is where most of the rulebook's substance lives.

### Two verified defects in the existing check

Both were reproduced against the built binary, not inferred from reading.

**1. FC10 line numbers are wrong.** `check_writing_style` uses `idx + 1` over
`doc.body` as the line number, but `doc.body` is the post-frontmatter body with
no offset applied — `scan_body` in `frontmatter.rs:291` offsets *section* line
numbers by `body_start_line` but pushes raw body lines unoffset. A hit on file
line 16 was reported as line 10 (six lines of frontmatter). The default output
mode is GitHub Actions annotations (`::notice file=...,line=...`), so every
FC10 annotation in CI points at the wrong line.

**2. FC10 has no markup awareness, and it produces false positives.** It scans
raw body lines including fenced code blocks, URLs, and tables. Probe result:

```
BRIEF-fence.md:15 notice [FC10] writing-style banned word "leverage"
BRIEF-fence.md:18 notice [FC10] writing-style banned word "robust"
```

Line 15 was `tier_config --leverage` inside a ```bash fence. Line 18 was the URL
`https://example.com/robust-guide`. Neither is prose. This is exactly the class
of problem Vale's format-aware markup parsing and `BlockIgnores`/`TokenIgnores`
scoping exists to solve, and it is the single most concrete technical argument
for Vale over widening the native check.

### The file-selection gate blocks non-artifact prose entirely

This is the most consequential structural finding for candidate placement.

`crates/shirabe/src/main.rs:604` runs `detect_format(basename(path))` and
`continue`s on `None`. `detect_format` (`formats.rs:248`) does longest-prefix
matching against exactly eight prefixes: `COMP-`, `DESIGN-`, `PRD-`, `VISION-`,
`ROADMAP-`, `PLAN-`, `STRATEGY-`, `BRIEF-`. Any file whose basename does not
start with one of those is silently skipped.

Verified:

```
$ shirabe validate --format human -- CLAUDE.md README.md AGENTS.md \
    skills/writing-style/SKILL.md
All checks passed.
EXIT=0
```

**`shirabe validate` cannot see a single SKILL.md, CLAUDE.md, AGENTS.md, or
README.md.** Candidate use (a) from the exploration brief — "a tool authors run
when writing/updating skills and agent instructions" — is therefore *not
reachable through `shirabe validate` today* without changing the file-selection
model. That is the central constraint on the whole design space.

A corollary: **FC-CONVENTIONS is dead code.** `check_claude_md_conventions`
(`checks.rs:3167`) gates on `basename != "CLAUDE.md"` and returns early — but
`detect_format` returns `None` for `CLAUDE.md`, so `validate_file` is never
called for it. Verified with a CLAUDE.md deliberately missing the required
`## Release Notes Convention:` header *and* containing four FC10 banned words:

```
$ shirabe validate --format human -- /tmp/probe/CLAUDE.md
All checks passed.
EXIT=0
```

The check has full unit-test coverage (`checks.rs:6270`-`6331`), is documented
in `docs/guides/multi-consumer-cli-contract.md:90`, is named in shirabe's own
`CLAUDE.md:23` as the reason a header exists, and has a resolution-prose file at
`references/fixes/claude-md-conventions.md`. It has never fired.

### The rulebook is copied into four places, all divergent

| # | Location | Scope | Enforcement |
|---|---|---|---|
| 1 | `skills/writing-style/SKILL.md` | ~60 words, 7 phrases, 7 structural patterns, 5 formatting tells, 6 substitutions, 4 cognitive tells | model judgment |
| 2 | `crates/shirabe-validate/src/checks.rs:2551` | 7 words | deterministic, notice-level |
| 3 | workspace `CLAUDE.md` "Quick reference - avoid these words" | 5 entries | model judgment |
| 4 | `skills/brief/references/phases/phase-4-validate.md:244` (Structural Format Reviewer, step 8) | 5 entries | jury agent judgment |

The workspace `CLAUDE.md` also promises `.claude/helpers/writing-style.md` "for
details" — that file does not exist (`.claude/` contains only `bin`, `hooks`,
`rules`, `settings.json`, `settings.local.json`). A fifth pointer, dangling.

The FC10 constant carries a code comment rationalizing the hardcoding, but the
design that specified it (`docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md:227`)
explicitly required the opposite: *"the validator reads from it at validate-time
so future reference updates propagate without a validator code change."* The
implementation drifted from its own design decision, and the four-way divergence
above is the direct consequence.

**A single Vale styles directory collapsing four copies into one source is the
strongest structural argument in this investigation** — stronger than the
detection-quality argument.

### Where the jury phases sit

Seven skills run reviewer/jury phases over drafted documents:

| Skill | Jury phase file | Reviewers | Writing-style step |
|---|---|---|---|
| brief | `references/phases/phase-4-validate.md` | Content Quality, Structural Format | **yes** (step 8) |
| strategy | `references/phases/phase-4-validate.md` | Bet Quality, Altitude, Structural Format | no |
| prd | `references/phases/phase-4-validate.md` | Completeness, Clarity, Testability | no |
| vision | `references/phases/phase-4-validate.md` | Thesis Quality, Content Boundary, Section Guidance | no |
| roadmap | `references/phases/phase-4-validate.md` | Theme Coherence, Sequencing, Annotation/Boundary | no |
| comp | `references/phases/phase-4-validate.md` | (rubric-driven) | no |
| design | `references/phases/phase-6-final-review.md` | architecture, security, structural format | no |

Only BRIEF has a prose step, and it hardcodes a fourth copy of the five-word
list. Every skill has a Phase 4 (or Phase 6) validate phase, so **a per-skill
insertion point exists and is uniform** — but adding a step to seven files
recreates the duplication problem seven-fold.

More importantly, two parent skills already established the correct pattern:

- `skills/charter/references/phases/phase-finalization.md:142` — *"does NOT
  re-implement `shirabe validate`'s checks; it invokes the validator."*
- `skills/scope/references/phases/phase-2-chain-orchestration.md:58` —
  "Validator pass-through," running `shirabe validate --format json`.

**Anything landing in `shirabe validate` propagates to `/scope` and `/charter`
for free.** Anything landing in a per-skill phase does not.

### CI: what runs, and the adopter surface

shirabe has 24 workflows. On PRs: `build-and-test.yml` (cargo build + `cargo
test --workspace`), plus ten path-filtered `check-*`/`validate-*` jobs.
**Nothing lints prose or markdown anywhere.**

`validate-docs.yml` is the reusable adopter-facing workflow. It builds shirabe
from source (`cargo build --release`), then runs `shirabe validate` over the
PR's changed files. Confirmed adopters, all pinned `@main`:

- `public/koto/.github/workflows/validate-docs.yml`
- `public/niwa/.github/workflows/validate-docs.yml`
- `public/tsuku/.github/workflows/validate-docs.yml`

All three path-filter on `docs/**` only. shirabe self-calls via
`validate-shirabe-docs.yml` (paths `docs/**`, `crates/**`, manifests).

Two consequences. First, **a check added to `shirabe validate` ships to three
downstream repos automatically on next PR** — real leverage, and real blast
radius. Second, even via that channel, `skills/**` and root `CLAUDE.md` are
outside the path filters, so candidate use (a) stays unreachable without
editing four repos' workflow files.

The pattern for adding a standalone CI job is trivially established — e.g.
`check-sentinel.yml` is 14 lines: path filter, checkout, run
`scripts/check-sentinel.sh`. `scripts/` already holds six such check scripts.

### Nothing in the workspace lints prose or markdown today

No `.vale.ini`, `.markdownlint*`, `cspell.json`, or `.textlintrc` anywhere in
`public/`. This is greenfield — there is nothing to piggyback on and nothing to
conflict with, other than FC10 itself.

tsuku *packages* the tooling without using it: `recipes/v/vale.toml`,
`recipes/c/cspell.toml`, `recipes/m/` markdownlint entries, `recipes/l/ltex-ls.toml`,
and a proselint disambiguation record. Note the vale recipe installs via the
`homebrew` action with `supported_libc = ["glibc"]` — so "installation is
solved" is true for a developer workstation with brew, and *less* true for a
CI runner, where it is a heavier dependency than the `cargo build` the
reusable workflow already does.

### koto: a real gate mechanism, on the wrong workflows

koto workflow templates support named gates of `type: command` with exit-code
transition conditions. Live example at `skills/work-on/koto-templates/work-on.md:321`:

```yaml
staleness_check:
  gates:
    staleness_fresh:
      type: command
      command: "check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '...'"
      override_default:
        exit_code: 0
```

This is a clean, natural hook — `vale --output=JSON` returning non-zero would
drop straight into it, with `override_default` giving the author an escape hatch.

But only **two** skills have koto templates: `skills/work-on/koto-templates/`
and `skills/execute/koto-templates/`. Both are *implementation* workflows. Every
document-authoring skill (prd, design, brief, strategy, roadmap, vision, comp)
is wip/-based and has no koto template. **A koto gate would cover the workflows
that write code and miss every workflow that writes prose.** That asymmetry
rules koto out as the primary integration point for candidate use (b).

### Real counts

Public repos only.

| Repo | SKILL.md | CLAUDE.md / AGENTS.md | total `.md` |
|---|---|---|---|
| shirabe | 20 | 2 | 463 |
| koto + niwa + tsuku | 8 | 4 | 501 |
| **total** | **28** | **6** | **964** |

shirabe word counts:

| Corpus | Files | Words |
|---|---|---|
| `skills/**/*.md` (all) | 211 | 197,538 |
| — of which SKILL.md | 20 | 37,816 |
| — of which `references/**` | — | 143,366 |
| `docs/**/*.md` | 145 | 463,440 |
| root CLAUDE.md / README.md / AGENTS.md | 3 | 4,322 |

koto + niwa + tsuku SKILL.md: 8 files, 15,829 words.

Validator: 2 crates, 33,411 lines of Rust; `shirabe-validate/src` is 21 modules,
`checks.rs` alone 6,882 lines. Check codes: `SCHEMA`, `FC01`-`FC16`,
`FC-CONVENTIONS`, `R6`-`R9` (per-file, `--check`-selectable), `L01`-`L07`
(lifecycle traversal modes).

Corpus cleanliness, measured across `docs/` + `skills/`:

| Pattern | Hits |
|---|---|
| FC10's 7 words, in `docs/` (validator-visible) | 161 |
| FC10's 7 words, outside `docs/` (invisible to validator) | 62 |
| "journey" | 151 |
| "additionally" | 14 |
| all other wider-vocabulary words combined | ~30 |
| em dashes | 4,217 |
| "serves as" / "stands as" / "boasts" | 10 |
| "prior to" / "subsequent to" / "due to the fact that" / etc. | 8 |
| "in order to" | 3 |
| "worth noting" / "important to note" | 2 |

Two things stand out. The corpus is genuinely clean on the *wider vocabulary* —
most words register 1 hit, and that hit is the SKILL.md listing the word itself.
So Vale's word-list value over FC10 is small. The value is in the phrase,
structural, and formatting rules that a word grep cannot express.

And 4,217 em dashes. The rulebook names em-dash overuse as a formatting tell;
the corpus that rulebook governs is saturated with it.

### The `.claude/settings.json` hook precedent

Repo-level `.claude/settings.json` in shirabe carries only `enabledPlugins` and
`extraKnownMarketplaces` — no hooks. Workspace-level `.claude/settings.json`
does configure hooks (a `PreToolUse` matcher on `Bash`, and a `Stop` hook),
with scripts under `.claude/hooks/`. So the mechanism is proven in this
workspace, but it is workspace-local and does not travel to adopters.

### Does the CLI anti-pattern bar a prose linter? No.

`CLAUDE.md:165`-`187` draws the line at **authoring vs checking**: "do NOT add
a CLI subcommand that renders or creates an artifact body. Rendering a body is
authoring... Compiled CLI logic is justified only for deterministic
validation/feedback and gh-backed live checks."

A prose linter never produces a body. It consumes one and emits findings —
`(code, severity, message, file, line)`, which is literally shirabe's
`ValidationError` shape, and also literally Vale's JSON output shape. The two
models are isomorphic. `validate`'s stated job, "tell the agent what to fix and
why," is a verbatim description of what a prose linter does.

A prose check therefore lands cleanly on the **`validate` side**, and FC10 is
the settled precedent proving the maintainers already read it that way. The
anti-pattern is not a live constraint on this proposal.

The genuine open design question is not *which side of the line* but **native
check vs shell out to vale**, and separately **how non-artifact files get in
front of the checker at all**.

### Native vs shell-out, costed

**Native (widen FC10 in Rust).** `regex = "1"` is already a dependency of
`shirabe-validate`, so substitution and existence rules are cheap. Zero new
runtime dependency for the three adopter repos — their CI keeps working with
nothing but `cargo build`. Cost: reimplements Vale, and the hard part is not
the rules but the *markup-aware scoping* — skipping code fences, inline code,
URLs, link targets, table delimiters, and frontmatter. That is precisely where
FC10 already produces verified false positives, and building it properly means
writing a markdown parser shirabe does not have.

**Shell out to `vale`.** Direct precedent exists: the validator already shells
out to `gh` (`gh.rs:393`, `gh.rs:537`) and `git` (`finalize.rs:758`,
`transition.rs:1067`, `checks.rs:804`), and FC09 already models the
graceful-degradation pattern, emitting an "Auth skip" notice when credentials
are missing rather than failing the run. A `vale`-missing skip notice would be
the same shape. Cost: every adopter's CI gains a binary dependency that
currently installs via a homebrew-backed tsuku recipe; and shirabe would have
to ship and version a `.vale.ini` plus a styles directory and get it onto the
runner alongside the vendored binary — new surface in the reusable workflow
contract, which `docs/guides/multi-consumer-cli-contract.md` currently defines
in terms of three consumers, three output modes, and four exit codes with no
external-tool dependency.

### Candidate insertion points

Anti-pattern test = the `CLAUDE.md:179` authoring-vs-checking rule.

| # | Candidate | Anti-pattern verdict | Duplicates something? | Overall |
|---|---|---|---|---|
| 1 | `shirabe validate` gains a prose check | **Passes cleanly.** Checking, not authoring; FC10 is settled precedent | **Yes — FC10 already is this.** Any new check must replace FC10, not sit beside it | **Strongest.** Reaches 3 adopter repos free, propagates to /scope and /charter via existing pass-throughs, JSON envelope already consumed by skills. Blocked for candidate use (a) by the `detect_format` prefix gate |
| 2 | New skill / extend `writing-style` to run vale | **Fails.** A skill invoking a linter to get findings is the validator's job; `charter/phase-finalization.md:142` explicitly forbids skills re-implementing validator checks | Yes — duplicates FC10 *and* the SKILL.md rulebook, creating a fifth copy | **Reject as enforcement.** Defensible only as author-facing documentation of a tool, i.e. it collapses into row 7 |
| 3 | A step inside each authoring skill's Phase 4/6 jury | Passes (juries are checking) but conflicts with the pass-through principle | **Yes, badly.** BRIEF step 8 already does this and is copy #4 of the list. Replicating across 7 skills yields 7 divergent copies | **Reject.** This is the mechanism that created the drift. Correct move is the reverse: delete BRIEF's step 8 and point at the validator |
| 4 | A standalone CI job | N/A (CI is outside the CLI-surface rule) | Partially — would double-report on `docs/**` where FC10 already runs | **Viable, and the only candidate that reaches `skills/**` and `CLAUDE.md` today.** Pattern is 14 lines (`check-sentinel.yml`). But adopters get it only by copying a workflow, not by the reusable-workflow channel |
| 5 | Git pre-commit hook | Passes | Yes — `shirabe install-hooks` already installs one (`main.rs:1209`), running `validate --format human` fail-closed over staged `.md` | **Already exists; extend, don't add.** But note this was *explicitly rejected* for this exact use case — see Surprises |
| 6 | Claude Code `PostToolUse` hook on Write/Edit | Passes (outside the CLI surface) | No | **Viable for candidate use (a), and uniquely well-matched to it** — it is the only candidate that catches prose at authoring time in the editor loop, on any file, with no prefix gate. Precedent exists at workspace level (`PreToolUse` on Bash, `Stop`). Does not travel to adopters; workspace-local only |
| 7 | Nothing automated, documented tooling only | Passes trivially | No | **Weakest.** The corpus measurements show model judgment alone is not holding: 4,217 em dashes, 161 FC10 hits in validator-visible docs, and a four-way divergent rulebook |

### Where a Vale check would duplicate or conflict

1. **FC10 is the direct collision.** Vale's default `Vale.Terms`/`Vale.Spelling`
   plus a custom `substitution` rule for those seven words would double-report
   every existing FC10 notice. Adopting Vale means retiring FC10, not adding
   alongside it — which is a check-code deprecation with an entry in
   `is_known_check_code`, `is_intrinsic_notice`, the multi-consumer contract
   doc, and the `--check` selector surface.
2. **BRIEF jury step 8** would become a third opinion on the same five words.
3. **"journey" is a format keyword, not a tell.** It is on the SKILL.md banned
   list under "Abstract nouns," and it is also the name of a *required BRIEF
   section* (`## User Journeys`) enforced by FC04. 151 of the ~180 wider-vocabulary
   hits are this one word. A naive Vale rule transcribed from the SKILL.md
   would fire on the BRIEF format's own mandatory heading. Any Vale styles
   package needs a scoping exception here on day one.
4. **The em-dash rule cannot ship enabled.** 4,217 hits. It would have to ship
   disabled, or as an occurrence-threshold rule, or the corpus needs a cleanup
   pass first.
5. **Exit-code semantics.** `validate` treats notices as exit 0
   (`multi-consumer-cli-contract.md`, "Notice-level results never make a run
   non-clean"). Vale's own severity model (suggestion/warning/error) would need
   an explicit mapping into shirabe's notice/error split, which is centralized
   at `validate.rs:127` (`effective_severity`) — a good seam, but one more
   contract to define.

## Implications

**The exploration's framing needs correcting before the decision is made.** The
premise "a 73-line rulebook applied by model judgment alone" is wrong — a third
of it is already mechanically enforced, badly, by FC10. The real question is
whether to replace a narrow, buggy, markup-blind grep with Vale, not whether to
introduce mechanical prose checking for the first time. Anyone arguing "don't
automate prose, use judgment" is arguing to *remove* something that already
ships.

**The two candidate uses have genuinely different answers, and should be
decided separately.** Candidate (b) — a step shirabe skills invoke at drafting
time — belongs in `shirabe validate`, replacing FC10, because the pass-through
plumbing in `/scope` and `/charter` already exists and the reusable workflow
already reaches three adopter repos. Candidate (a) — a tool for authors editing
skills and agent instructions — **cannot** go there without changing
`detect_format`'s prefix gate, and is better served by a `PostToolUse` hook
(row 6) or a standalone CI job (row 4). Treating them as one decision will
produce a design that half-works.

**The duplication argument outranks the detection-quality argument.** The
wider-vocabulary yield is small (most words: one hit, and that hit is the
rulebook listing itself). What Vale buys is a single versioned styles directory
replacing four divergent hand-maintained copies plus one dangling pointer, and
markup-aware scoping that stops the false positives FC10 demonstrably produces.
Pitching Vale on "catches more bad words" is the weak case and the data does not
support it; pitching it on single-sourcing and markup-awareness is the strong
case and the data does.

**Two defects should be fixed regardless of the Vale decision.** The FC10 line
number is off by the frontmatter length, so its CI annotations point at wrong
lines. FC-CONVENTIONS is unreachable dead code with full test coverage and
documentation. Neither depends on adopting Vale, and both are small. They also
serve as evidence for the review process: a fully unit-tested, documented check
shipped without a single integration test that would have revealed it never
runs.

**Blast radius is larger than it looks.** `validate-docs.yml` is pinned `@main`
by koto, niwa, and tsuku. A prose check merged to shirabe main starts producing
findings in three other repos on their next docs PR, with no version bump and no
opt-in. That is an argument for shipping notice-level first (FC10's own
precedent, and the promotion seam at `validate.rs:83` is designed for exactly
this one-line promotion later), and an argument for actually measuring against
each adopter's corpus before merging, not just shirabe's.

## Surprises

**The pre-commit hook for this exact use case was already proposed and
explicitly rejected.** `DESIGN-shirabe-pattern-v1-ergonomics.md:239`, under
rejected alternatives: *"Pre-commit hook for R20: a git pre-commit hook runs
the writing-style grep before commit. Rejected because pre-commit hooks block
authors mid-flow and the workspace already has a validator surface for advisory
notices; adding a hook layer is a new mechanism the workspace doesn't need."*
Candidate 5 is not an open question — it is a settled decision with recorded
reasoning. Anyone re-proposing it must argue against that record. (The irony:
shirabe then shipped `install-hooks` anyway, so a pre-commit hook running
`validate` exists — it just was not built for the prose check.)

**FC10's hardcoding contradicts its own design.** The design said the validator
"reads from it at validate-time so future reference updates propagate without a
validator code change" (`:227`). The implementation hardcoded seven words and
wrote a code comment arguing the design's intent was satisfied anyway. The
four-way divergence in the rulebook is the direct, predicted consequence.

**FC-CONVENTIONS has never fired.** Fully implemented, six unit tests, a
`references/fixes/` resolution file, a line in shirabe's own CLAUDE.md
explaining that a header exists so the check "can find it," and an entry in the
public multi-consumer contract. It is structurally unreachable. Verified.

**The corpus is cleaner than expected on vocabulary and dirtier than expected
on punctuation.** Most banned words appear exactly once — in the SKILL.md that
bans them. But 4,217 em dashes across `docs/` and `skills/`, in a corpus whose
own style guide lists em-dash overuse as a formatting tell. The rulebook's
formatting section is the least observed and the least enforceable by the
mechanism currently in place.

**"journey" collides with a mandatory section heading.** A banned abstract noun
in the writing-style rulebook is simultaneously required by the BRIEF format
(`## User Journeys`, enforced by FC04). 151 of ~180 wider-vocabulary hits are
this single word. Two shirabe-owned contracts contradict each other, and nobody
noticed because FC10 never included "journey."

**Not a finding, but worth flagging:** the workspace `.claude/settings.json`
contains a GitHub personal access token in plaintext. The workspace root is not
a git repo, so it is not committed, but it is worth the author's attention
independently of this exploration.

## Open Questions

1. **Is candidate use (a) worth changing `detect_format` for?** Letting
   `shirabe validate` see SKILL.md and CLAUDE.md means either a new
   non-prefix-matched path, or a `--prose-only` mode that bypasses format
   detection. Both are real surface changes to a contract three repos depend
   on. Needs a decision, not an assumption.
2. **Native widened check, or shell out to `vale`?** I have costed both above
   but this is a genuine trade and needs the author's call. The deciding factor
   is probably whether adopter CI can carry a `vale` binary dependency — worth
   asking whether the reusable workflow should vendor it rather than install it.
3. **What happens to FC10?** Retire it, or keep it as the always-available
   fallback when `vale` is absent? The FC09 auth-skip precedent suggests the
   latter is idiomatic here, but it perpetuates a second copy of the word list.
4. **Does the em-dash rule ship at all?** 4,217 hits means either it ships
   disabled, or the corpus gets a cleanup pass first. That is a scoping call
   with real work attached, and it materially affects whether "adopt Vale"
   is a small change or a large one.
5. **Should the BRIEF jury's step 8 be deleted as part of this?** The
   pass-through principle says yes. Confirm that removing a jury rubric step
   does not break the skill's evals at `skills/brief/evals/evals.json`.
6. **Do koto, niwa, and tsuku's corpora look like shirabe's?** I measured
   shirabe only. Since all three consume `validate-docs.yml@main`, their
   findings-volume on day one determines whether this lands as a quiet notice
   stream or a flood. This should be measured before anything merges.

## Summary

shirabe already ships a deterministic prose check — FC10, a hardcoded seven-word
grep in `shirabe validate` — that catches under a third of its own rulebook,
reports wrong line numbers, and produces verified false positives inside code
fences and URLs, while the rulebook itself exists in four divergent copies plus
one dangling pointer. The prose linter belongs on the `validate` side of
shirabe's authoring-vs-checking line (checking is exactly what it does, and FC10
is settled precedent), so the strongest placement is replacing FC10 there, which
propagates free to /scope, /charter, and three adopter repos — but the
`detect_format` prefix gate means `validate` cannot see a single SKILL.md or
CLAUDE.md, so the "tool for authors editing skills" use case needs a different
home (a PostToolUse hook or a standalone CI job) and should be decided
separately. The biggest open question is whether to widen the native Rust check
or shell out to `vale`, which turns on whether adopter CI can carry a binary
dependency that shirabe's reusable workflow does not currently have.
