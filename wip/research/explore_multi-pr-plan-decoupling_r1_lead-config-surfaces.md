# Lead: What repo-level configuration surfaces already exist in shirabe, and which one would a "PR decomposition preference" and a "work-tracking preference" naturally bind to?

## Findings

### The dominant channel: CLAUDE.md convention headers

shirabe already has a well-established, growing family of `## <Name>:` level-2
headers in the repo's own `CLAUDE.md`, documented centrally in
`references/fixes/claude-md-conventions.md`. The live set, as declared in
shirabe's own `CLAUDE.md` (this repo, `CLAUDE.md:1-266`):

- `## Repo Visibility: Public` (`CLAUDE.md:6`)
- `## Prose Vocabulary: tier, journey, underscore` (`CLAUDE.md:11`)
- `## Planning Context: Tactical` (`CLAUDE.md:29`)
- `## Release Notes Convention: docs/guides/` (`CLAUDE.md:35`)
- `## PR Grouping Policy: coarsest-legal` (`CLAUDE.md:46`)
- `## Reviewability Ceiling: default` (`CLAUDE.md:59`)
- `## Artifact Lifecycle: per-skill` (`CLAUDE.md:71`)

`references/fixes/claude-md-conventions.md:48-83` is the canonical cross-reference
list and additionally documents `## Execution Mode: auto|interactive` and
`## Roadmap Issues: optional|required`, which live in other repos'/contexts'
CLAUDE.md rather than shirabe's own. The doc states the general contract
explicitly: "Each header is independent. A repo may declare any subset; absent
headers fall through to their defaults... FC-CONVENTIONS only fires for the
Release Notes Convention header today; the other headers have their own
validators or are defaulted silently." (`claude-md-conventions.md:79-83`)

**Two of these headers are near-exact matches for what the author wants**,
already shipped:

- **`## PR Grouping Policy: coarsest-legal`** (`CLAUDE.md:46-57`) is the *PR
  decomposition preference* the author is asking for, already built, but scoped
  today to **coordinated multi-repo** efforts only. Quoting `CLAUDE.md:46-54`:
  > "The default PR-grouping policy for a coordinated multi-repo effort: one PR
  > per repository (the coarsest legal unit). A repo splits into more than one
  > PR only on a recorded trigger. This is a durable workspace preference,
  > resolved `flag > CLAUDE.md-header > default`."
  Its rule and split triggers are single-sourced in
  `references/coordination-strategy.md` under "Coarsest-Legal-Grouping Rule"
  (`coordination-strategy.md:126-138`): independently mergeable, independently
  rollback-able, exceeds the reviewability ceiling, or breaks a merge-order
  cycle. This is a *repo-splitting* policy for coordinated efforts, not a
  *within-repo PLAN → PR count* policy — see Implications for the gap this
  leaves for the author's actual ask.

- **`## Reviewability Ceiling: default`** (`CLAUDE.md:59-69`) is the companion
  threshold: "the size at which a single per-repo PR becomes too large to
  review and the grouping splits it," resolved the same `flag >
  CLAUDE.md-header > default` way, deferring to
  `references/coordination-strategy.md` unless overridden with a concrete
  value.

- **`## Roadmap Issues: optional|required`**, documented in
  `claude-md-conventions.md:64-74` and given a full DESIGN doc
  (`docs/designs/current/DESIGN-roadmap-issueless-preference.md`), is the
  closest existing precedent for the *work-tracking preference*, though its
  scope is narrower: it governs only whether `shirabe roadmap populate` files
  one GitHub issue per roadmap feature, not the milestone/issues/nothing
  three-way choice for multi-PR PLAN execution the author wants. Default is
  `optional` (issueless) per
  `docs/decisions/DECISION-populate-issueless-default-2026-08-10.md`, which
  superseded the DESIGN's original `required`-default choice.

### `execution_mode`: two different things share a name

Caution for anyone reusing this precedent: **`## Execution Mode:
auto|interactive`** (a CLAUDE.md header controlling whether skills act
autonomously or prompt at each decision point — referenced in
`claude-md-conventions.md:61-63` and used across many skills'
`SKILL.md`s) is a **different concept** from the **`execution_mode`
PLAN-frontmatter field** with values `single-pr | multi-pr | coordinated`
(`crates/shirabe-validate/src/formats.rs:104-161,336,348`, and
`references/coordination-strategy.md:42-45`: "Coordinated mode is the third
`execution_mode` value... It is always multi-PR"). The frontmatter field is
per-document, validated by Rust (FC14 checks in `checks.rs:3358-3393`), and is
exactly the single-pr-vs-multi-pr decomposition axis the author is asking
about — but at the PLAN level, not the repo-preference level. A new repo-level
"prefer fewer PRs vs. atomic increments" header would need a name distinct
from `Execution Mode` to avoid colliding with this existing term.

### How headers get parsed: shared, both in skills (prose) and in Rust (compiled)

This directly answers whether "scripts reading a markdown header" is awkward:
**no** — it's an established pattern with dedicated, tested Rust code, not
duplicated ad hoc per skill.

`crates/shirabe-validate/src/visibility.rs` is compiled Rust that reads
`CLAUDE.md`/`CLAUDE.local.md` directly:
- `parse_visibility_header(contents: &str) -> Option<String>` (`visibility.rs:26-45`)
  parses `## Repo Visibility: (Public|Private)`, case-insensitive on key and
  value, tolerant of an unrecognized value (skips rather than errors).
- `parse_prose_vocabulary_header` (`visibility.rs:139-...`) parses `## Prose
  Vocabulary: a, b, c`.
- `resolve_claude_md_header<T>(path, extract)` (`visibility.rs:66-...`) is a
  **generic walker**: walks up from a doc's directory, preferring
  `CLAUDE.local.md` over `CLAUDE.md` at each level, stopping at the first
  `.git` boundary, and applying a caller-supplied `extract` closure — so a new
  header's parser plugs into the same walk instead of writing a new file-walk.
  Both `parse_visibility_header` and the prose-vocabulary parser are used as
  `extract` callbacks into this one function.
- The module's own doc comment states the design intent directly
  (`visibility.rs:6-17`): mirrors "the idiom every shirabe skill uses" so "the
  CLI's auto-detection and the skills' hand-detection resolve visibility the
  same way and cannot drift."

Only **one** header has a dedicated validator check today: `## Release Notes
Convention:` via `check_claude_md_conventions` / **FC-CONVENTIONS**
(`crates/shirabe-validate/src/checks.rs:3543-3599`), which fires a notice
(not an error) when the header is missing or malformed, pointing the reader at
`claude-md-conventions.md`. `Repo Visibility`, `Execution Mode`, `Planning
Context`, `Default Scope`, `PR Grouping Policy`, `Reviewability Ceiling`, and
`Roadmap Issues` have **no** validator-level enforcement — they are "read by
the skill, not the validator" (`claude-md-conventions.md:71-72`) and default
silently when absent or malformed. This means today's practice already
supports a header that only the skill (agent) reads, with no compiled
enforcement — but `Repo Visibility` and `Prose Vocabulary` prove compiled
Rust parsing is just as available when tooling-side enforcement is wanted, via
the same `resolve_claude_md_header` walker.

No shell script in `scripts/` reads `CLAUDE.md` at all (`grep -rln "CLAUDE.md"
scripts/` returned nothing) — all header-parsing precedent lives in either
skill prose (agent-facing, via plain-text instructions in `SKILL.md`/phase
files) or the compiled Rust validator, never in bash/shell tooling.

### team.yaml: unrelated to repo preferences

`skills/plan/team.yaml`, `skills/design/team.yaml`, and the other five
`team.yaml` files under `skills/*/` are **not** configuration surfaces for
repo-level preferences. They declare each skill's agent-fan-out topology for
koto orchestration: `parent_layer`/`child_layer` peers, each with a `role`,
`cardinality` (`worker`/`reviewer`), an `upper_bound`, a `phase`, and a
`purpose` string. Example, `skills/plan/team.yaml`:
```yaml
child_layer:
  peers:
    - role: decomposer
      cardinality: worker
      upper_bound: 20
      phase: phase-4-agent-generation
      purpose: generates an issue body per outline from Phase 3...
```
This is a static declaration of how many sub-agents a phase may spawn and
why — orthogonal to the author's ask. No grep hit found any script or Rust
code reading `team.yaml`; it appears to be consumed by koto itself (outside
this repo) rather than by shirabe's own tooling.

### `.claude/shirabe-extensions/*.md`: the closest structural precedent, but for a different axis

`.claude/shirabe-extensions/work-on.md`, imported via `@.claude/shirabe-extensions/work-on.md`
into the `/work-on` skill (per `.claude/shirabe-extensions/README.md:3-6`), is
a **per-repo declarative extension file** with its own documented schema
(`skills/work-on/references/verification-map.md`) that both the skill (agent,
via `@`-import) and the "definition-of-done gate" logic read to decide which
verification commands must pass for a changed-file set. It is the one
existing case of a repo declaring a structured, schema'd table (not a single
`## Header: value` line) that both agent prose and mechanical enforcement
consume. It is not a natural fit for a single enum-valued preference like "PR
decomposition style," though — it's built for file-glob-to-command mappings,
not scalar preferences, and CLAUDE.md headers are the established idiom for
scalar preferences specifically (7 of them exist there today, all singular
`## Name: value` lines).

## Implications

**The CLAUDE.md convention-header channel is the right reuse target for both
new preferences**, for three reasons converging on the same answer:

1. It's already the single channel used for every scalar repo-level
   preference in shirabe (7 headers, one file, one canonical cross-reference
   doc). Both preferences the author wants are scalar/enum-valued ("fewest
   PRs vs. atomic increments"; "issues | issues+milestones | nothing"), which
   is exactly this channel's shape.
2. The parsing infrastructure is not per-skill ad hoc: `resolve_claude_md_header`
   in `visibility.rs` is a generic, tested, reusable walker. Adding a header
   that Rust tooling needs to read (the author explicitly wants "the tooling"
   to enforce or hint back) is a `extract` closure away, not a new subsystem.
   Adding a header only skills need is even cheaper — most existing headers
   (`Execution Mode`, `Planning Context`, `Default Scope`, `PR Grouping
   Policy`, `Reviewability Ceiling`, `Roadmap Issues`) take that path today
   with zero Rust involvement.
3. There's direct precedent for **exactly this pairing of concerns** —
   `PR Grouping Policy` + `Reviewability Ceiling` is already a two-header
   preference-plus-threshold pair for a PR-decomposition-shaped question, and
   `Roadmap Issues` is already a two-valued work-tracking-shaped preference
   with a full DESIGN doc precedent for how to introduce, default, and
   document a new header (`DESIGN-roadmap-issueless-preference.md` Decision A
   explicitly rejects a new `.shirabe.toml` config-file layer "for one
   boolean" as disproportionate, `DESIGN-roadmap-issueless-preference.md:134-137`).

**The existing `PR Grouping Policy` header does not directly cover the
author's ask** — it governs repo-splitting within a *coordinated multi-repo*
effort, not "how many PRs should a single PLAN in one repo produce." The
author's preference is closer in spirit to the PLAN-frontmatter
`execution_mode` (`single-pr | multi-pr | coordinated`) promoted to a
repo-level default that `/plan` reads to pick its own frontmatter value absent
an override — i.e., a new header (not reusing `PR Grouping Policy` verbatim,
to avoid conflating "split within a repo" with "split across repos in a
coordinated effort") that resolves `flag > CLAUDE.md-header > default` into a
default `execution_mode`, mirroring exactly how `Roadmap Issues` defaults the
roadmap skill's populate mode and `PR Grouping Policy` defaults the
coordination-splitting decision.

**Naming should avoid `Execution Mode`** — that name is taken by the
auto/interactive header and would collide semantically with the
already-distinct `execution_mode` frontmatter enum the author's preference
maps onto. Something like `## PR Decomposition:` (values e.g.
`consolidated|atomic`, or reusing `single-pr|multi-pr` to match the
frontmatter enum directly) avoids the collision while staying in the same
naming family (`## <Noun Phrase>: <value>`) as `PR Grouping Policy` and
`Roadmap Issues`.

**For the work-tracking preference**, `Roadmap Issues: optional|required` is
the nearest precedent but is roadmap-specific (issue-per-feature at the
ROADMAP layer). The author's ask — issues vs. issues+milestones vs. nothing,
for multi-PR PLAN execution — is a different layer (PLAN/`/plan` and
`/execute`, not `/roadmap`) and a three-way rather than two-way enum. A new
header (e.g. `## Work Tracking: issues|issues+milestones|none`) following the
same `flag > CLAUDE.md-header > default` stack, documented alongside the
others in `claude-md-conventions.md`, is the natural extension — no new
mechanism required.

## Surprises

- **`Execution Mode` name collision.** The CLAUDE.md header `## Execution
  Mode: auto|interactive` and the PLAN-frontmatter field `execution_mode:
  single-pr|multi-pr|coordinated` are unrelated concepts that happen to share
  a name. Nothing in the docs cross-references or disambiguates this; a reader
  skimming `claude-md-conventions.md` next to `coordination-strategy.md`
  could easily conflate them. Worth flagging so the new headers don't add a
  third meaning to an already-overloaded term.
- **The coordination-specific `PR Grouping Policy` header is close enough to
  the author's ask to be mistaken for it**, but is scoped to cross-repo
  coordination, not single-repo PLAN decomposition. The author's preference
  needs its own header even though the *pattern* (default grouping + a
  reviewability-ceiling-style threshold + recorded-trigger override) is
  directly reusable.
- **Rust already parses CLAUDE.md headers with a shared, generic, tested
  walker function** (`resolve_claude_md_header<T>`), which fully answers the
  "is a script reading a markdown header awkward" question in the negative —
  it's a solved, reused problem, not a one-off hack. No shell script does
  this, though; the only two consumers are skill prose (agent-facing) and this
  one Rust module.
- **`DESIGN-roadmap-issueless-preference.md` explicitly rejected a new config
  file** (`.shirabe.toml`) as the mechanism for a single boolean preference,
  citing D6 (minimal surface) and the fact that "no such loader exists" — a
  directly on-point precedent against inventing a third config channel for
  either of the author's two preferences.

## Open Questions

- Should the new "PR decomposition preference" header directly set the PLAN's
  `execution_mode` frontmatter default, or introduce a separate preference
  name that `/plan` translates into `execution_mode`? The former is more
  DRY but ties a repo preference name 1:1 to an internal frontmatter enum
  that also has `coordinated` as a third value with different semantics
  (cross-repo, not just cross-PR); the latter avoids that coupling but adds a
  translation step.
- Should the new work-tracking header apply uniformly to both `/plan` (issue
  creation at planning time) and `/execute` (tracking during multi-PR
  execution), or does it need to be two separate headers the way `Roadmap
  Issues` is scoped only to `/roadmap populate`? Not yet investigated —
  would require reading `skills/plan/SKILL.md` and `skills/execute/SKILL.md`
  in full for how they currently create/consume issues and milestones.
- Whether FC-CONVENTIONS (the one validator-enforced header check) should be
  extended to the two new headers, or whether they should follow the
  silent-default pattern the majority of existing headers use — not
  investigated here; depends on how strongly the author wants "the tooling to
  enforce" (their phrasing) vs. merely hint back.

## Summary

shirabe already has seven CLAUDE.md convention headers as its one established
repo-level scalar-preference channel, with a generic, tested Rust parser
(`resolve_claude_md_header` in `crates/shirabe-validate/src/visibility.rs`)
proving that both skills (agent prose) and compiled tooling can read this
channel without awkwardness — and two headers (`PR Grouping Policy`+
`Reviewability Ceiling` for decomposition-shaped preferences, `Roadmap Issues`
for work-tracking-shaped preferences) are near-exact structural precedents,
though both are scoped to a narrower case (cross-repo coordination;
roadmap-feature issues) than the author's PLAN-level, single-repo ask. The
main implication is that both new preferences should ship as new `##
<Name>: <value>` headers on the same `flag > CLAUDE.md-header > default`
resolution stack, documented in `references/fixes/claude-md-conventions.md`,
rather than any new file format — a prior DESIGN doc already rejected a
`.shirabe.toml` config-file alternative for exactly this reason. The biggest
open question is whether the PR-decomposition header should directly set (or
merely default) the existing PLAN-frontmatter `execution_mode` field, given
that name is already doing double duty with the unrelated `## Execution
Mode: auto|interactive` header.
