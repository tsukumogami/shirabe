---
schema: design/v1
status: Accepted
problem: |
  The pull request a /work-on or /execute run publishes passes no
  writing-style check, though its title and Part 1 become the commit message
  on main. The pull request gate already runs `shirabe validate --pr-body`
  and returns findings by registry rule id, but only for structure.
decision: |
  The check lives in `shirabe validate`, not in Vale and commitlint. An
  opt-in `--writing-style <rules-file>` flag on `--pr-body` reports banned
  terms in the title and body as `PB5`, using FC10's own matcher, rules loaded
  explicitly and failing loudly, and vocabulary from the working directory.
  The gate passes the plugin's own `rules.yaml`, maps `PB5` to a new registry
  rule `pr-body/banned-word` (never eligible to withhold), and holds on skew,
  which preflight reports at skill load.
rationale: |
  It puts a correctness rule where shirabe's `CLAUDE.md` says such rules go,
  reads the single word list with the matcher documents already use, honors
  declared vocabulary, adds no tool to any host or CI, and leaves adopters'
  CI and the pull-request-body hook byte-identical. External linters would
  add binaries, Node, branch-controlled JavaScript and a second rendering of
  the word list for checks that measured near-zero value on this corpus.
upstream: docs/prds/PRD-linter-check-states.md
decision_provenance: inline-resolved
---

# DESIGN: linter check states

## Status

Accepted

## Context and Problem Statement

The upstream PRD, `docs/prds/PRD-linter-check-states.md`, asks the pull
request gate in /work-on and /execute to hold a run whose title or body uses a
banned word from `skills/writing-style/rules.yaml`, and to tell the agent the
word, where it is, what to prefer, the registry rule id and where the rule's
text is.

The gate is `skills/work-on/scripts/check-pr-output.sh --pr-body`. koto runs
it as the `pr_body_conformant` command gate of `work-on:pr_creation` and as
`owned_pr_body_conformant` (with `--owned`) in `execute:pr_finalization`; both
states' success edges require it to exit 0. It reads the pull request's title
and body with `gh pr view --json title,body`, writes the body to a temporary
file, runs `shirabe validate --pr-body <file> --pr-title <title> --format
json`, and maps each finding's message to one of five registry ids
(`pr-body/conventional-title`, `pr-body/one-separator`,
`pr-body/no-ai-trailer`, `pr-body/no-heading-in-part1`,
`pr-body/conformance`), printing one `::koto-finding::` line per finding
through `scripts/lib/rule-findings.sh`. koto turns those lines into
`gate_evaluated` events and exports one `check_rule` record per rule id, which
is how the existing pull request rules are already counted.

The validator side has three gaps the research for the PRD found:

- `shirabe validate --pr-body` (`crates/shirabe/src/main.rs`,
  `run_pr_body_mode`; `crates/shirabe-validate/src/pr_body.rs`) loads no
  writing-style rules at all. Its findings have no code and no severity: any
  finding is a violation (exit 2).
- The document check that does match banned words (FC10,
  `check_writing_style_with` in `crates/shirabe-validate/src/checks.rs`) gets
  its rules from `cached_rules()`, which walks up from the working directory
  and returns nothing, silently, when no `rules.yaml` is found. In an
  adopting repository nothing is found, and the `--rules` flag some comments
  describe doesn't exist.
- The declared vocabulary (`resolve_prose_vocabulary` in
  `crates/shirabe-validate/src/visibility.rs`) walks up from the checked
  file's directory. The gate's body file sits under `$TMPDIR`, so no
  repository's declaration would ever be found.

koto runs the gate at the session's anchor (the repository under review) in a
cleared environment: PATH, HOME and XDG_CONFIG_HOME as recorded at
`koto init`, plus a fixed list that includes `TMPDIR` and `GH_TOKEN` but not
`SHIRABE_RULES`. The command has 30 seconds, and the `--owned` lookup already
takes up to 20 of them.

Two other callers share the validator's pull request check and must not
change: the reusable workflow `.github/workflows/pr-body.yml`, which adopters
pin at `@main` and which runs `shirabe validate --pr-body "$BODY_FILE"
--pr-title "$PR_TITLE" --format annotation`, and `shirabe pr-body-hook`, a
PreToolUse hook that calls `check_pr_body` directly.

Before any of that, the roadmap left one choice open: whether the check
should come from external linters, Vale for prose and commitlint for commit
messages, or from `shirabe validate`.

## Decision Drivers

- **The finding contract (PRD R2 to R5).** Every occurrence of a banned term
  in the title or the body's prose is one finding, matched the way FC10
  matches documents: case-insensitive, whole-word, never in inline or block
  code, link destinations, bare URLs, HTML comments or table cells. The title
  is checked too, except for a Conventional Commits `type(scope)!:` prefix.
  Each finding is a `::koto-finding::` line at level `error` with `rule_id`
  `pr-body/banned-word`, the registry's computed `rule_ref` for the
  banned-words range of `rules.yaml`, and a message naming the term, its body
  line (counted over the whole body) or "the title", and the category's
  guidance. At most 50 term findings, then one truncation finding.
- **Declared vocabulary (PRD R6).** A term the repository declares under
  `## Prose Vocabulary:` is not reported, the repository being the one the
  gate runs in.
- **No silent pass (PRD R7, R8).** The gate checks the plugin's own
  `rules.yaml`, whatever `SHIRABE_RULES` or the repository says, and holds
  (exit 2) when the rules can't load or `shirabe` can't run the check.
- **Nothing else moves (PRD R9, R11).** PB1 to PB4 keep their findings and
  ids. Without an explicit opt-in, `shirabe validate --pr-body` output and
  exit codes are byte-identical, and the hook decides as before.
- **Correctness checks belong in `shirabe validate`.** shirabe's `CLAUDE.md`
  makes it the feedback and correctness engine, and says new correctness
  rules belong there as checks or modes.
- **No new system dependency (PRD R16).** shirabe ships into the tsuku
  ecosystem, where a user needs nothing installed beyond tsuku; the gate runs
  on every agent host and the check must not add a tool to either skill's
  `requires.tsv`.
- **One rule source.** `rules.yaml` is the single authoritative word list; a
  copy anywhere under `crates/` or `skills/` fails CI's word-list check.
- **Time (PRD R15).** One validator process and one more rule id to resolve,
  no network call, inside koto's 30 seconds.
- **Skew shows up early (PRD R13).** Preflight names what the gate needs from
  `shirabe validate`.
- **Bash 3.2 floor** for the gate script, and no `set -e`, as its neighbours.

## Considered Options

### Decision 1: Where the pull request writing-style check lives

Delegated to /decision.

The question the roadmap left open: should the banned-word check on a pull
request's title and body, and any later commit-message rule, come from
external linters (Vale for prose, commitlint for commit messages) run by the
gate, from an extension of `shirabe validate`, or from a matcher written into
the gate script? The forces are the ones in Decision Drivers: shirabe's
`CLAUDE.md` puts correctness rules in `shirabe validate`; the gate runs on
every agent host and neither skill's `requires.tsv` may gain a tool;
`rules.yaml` is the one word list; findings need registry ids; declared
vocabulary must be honored; adopters' CI and the hook must not move.

Prior art weighs in. `docs/designs/current/DESIGN-writing-style-enforcement.md`
(Decision 1) already rejected Vale for documents on judgment rather than a
hard constraint: about 1.7% raw precision and roughly two true positives
across 554,000 words of shirabe's corpus, a 40 MB third-party binary and a
network `vale sync`, and a frequency rule hand-written in Tengo. Research for
this decision found the matcher the feature needs already exists:
`check_writing_style_with` takes explicit rules and vocabulary and does no
I/O, `prose::prose_spans` works on plain lines, and `run_pr_body_mode` is a
single early-return mode that neither `pr-body.yml` nor the hook reaches
through new flags.

Key assumptions:

- koto runs the gate with its working directory at the repository under
  review, so a vocabulary walk from the working directory finds that
  repository's `CLAUDE.md`.
- The shirabe binary and the plugin are released together, and a host
  upgrades the binary when preflight names a missing flag.
- Vale and commitlint start-up times were estimated, not measured; timing
  doesn't decide the question at any plausible value.

#### Chosen: an opt-in check inside `shirabe validate --pr-body`

`shirabe validate --pr-body <file>` gains `--writing-style <rules-file>`,
valid only with `--pr-body`, which reports banned terms in the title and the
body as `PB5` findings in the existing `shirabe-pr-body/v1` envelope. As
for PB1 to PB4, `PB5` is the message's prefix (`[PB5] `), since a
`PrBodyFinding` carries only a line and a message. The
matching is FC10's own code, pulled out of `check_writing_style_with` into a
span-level function both call, so documents and pull requests are judged by
one matcher over one CommonMark scoping. The gate passes the plugin's
`rules.yaml` and maps `PB5` to a new registry rule. Decisions 2 to 4 settle
the details.

It is the only option that meets every constraint together: the correctness
rule sits where `CLAUDE.md` puts such rules, the single word list is read
directly, Prose Vocabulary is honored by the parser FC10 already uses, no
tool is added to either `requires.tsv`, findings are countable by registry
id, and adopters' CI and the hook stay byte-identical because nothing they
run passes the flag. Most of the code exists already. A `--pr-body` pass
measured about 38 ms, and the banned words ride the same call.

Commit-message rules stay native. The Conventional Commits title and subject
are already checked by PB1 and `commit/conventional-subject`; over those,
commitlint would add only `header-max-length`, `subject-full-stop`,
`subject-case` and `header-trim` (which PB1 already does by trimming). If
those are wanted later they arrive as opt-in title checks with their own
registry ids, not as changes to PB1, which also runs in adopters' CI and in
the hook.

#### Alternatives Considered

**External linters run by the gate (Vale plus commitlint).** Vale would add
its community style packages, Hunspell spelling, editor integration and
familiarity; commitlint would add the four header rules above and a plugin
ecosystem. Rejected: it adds Vale, Node and commitlint to both `requires.tsv`
files; it runs `commitlint.config.js`, which the branch under review can
supply, so a gate would execute JavaScript the branch controls; Vale has no
reading of `rules.yaml`, so the gate would generate a second rendering of the
word list each run, walk the vocabulary a second time and need parity tests
to keep pull request and document checks from disagreeing; Vale's packages
need a network `vale sync` that can't run inside a 30-second gate, and on this
corpus they measured near-zero value. commitlint has no word-list rule, so it
does nothing for the banned words that are this feature, and its body
line-length rules misfire on Part 1, which is written as long lines.

**A matcher in the gate script (bash and awk over `rules.yaml`).** Its real
advantage is that matcher and plugin always ship together, so there is no
binary skew. Rejected: it is a second engine for the same rule. It either
reimplements CommonMark scoping in bash 3.2 and BSD awk, the scoping a Rust
hand-roll already got wrong twice, or narrows to a subset that agrees with
FC10 only one way, the two-engines outcome the writing-style design rejected.
It also puts a correctness rule outside `shirabe validate`, against
`CLAUDE.md` and against the gate script's own header, which says it
translates checks rather than deciding them.

**The validator check as the gate, with Vale or commitlint as optional
advisors where installed.** Rejected: its blocking part is the chosen option
line for line, and the advisory part would run nowhere today, since no
repository in the organization configures Vale. Advisory findings would need
a new registry level and readers that filter on it, would differ from host
to host, and never reach the agent on a passing gate. commitlint is excluded
even as an advisor by the repository-JavaScript problem.

### Decision 2: The validator surface, rules loading and vocabulary

Resolved inline.

The gate needs the validator to check prose it has never checked, from rules
it currently can't find (the body is a temp file, koto clears
`SHIRABE_RULES`, and `cached_rules()` fails open), against a vocabulary it
currently can't find (the walk starts at the temp file's directory), without
changing what `pr-body.yml` or `pr-body-hook` see.

Key assumptions:

- koto keeps running command gates at the session anchor.
- A title's Conventional Commits `type(scope)!:` prefix is an identifier, not
  prose.

#### Chosen: `--writing-style <rules-file>`, loaded explicitly, vocabulary from the working directory

The flag's value is the rules path. Under it the validator:

- loads exactly that file through `rules::resolve_rules_path(Some(path), ..)`
  and `rules::load_rules`, never `cached_rules()`; a missing, unreadable or
  malformed file, or one with no banned term, is a tool error (exit 1, no
  envelope);
- resolves the declared vocabulary by walking up from the working directory
  (`resolve_prose_vocabulary_from_dir(current_dir())`, the existing header
  walk with `stop_at_repo_root` set, started at that directory), stopping after the first directory holding
  `.git`, `CLAUDE.local.md` before `CLAUDE.md` per directory, as documents do;
  with no `.git` above it the walk reaches the filesystem root and finds
  whatever declaration it finds, as FC10 does for a document outside a
  repository. It prints the banned terms the declaration suppressed on one
  stderr line, built only from the rules file's own term strings that the
  declaration matched (never the declaration's text), so a transcript shows
  what was waived;
- checks the body as a document with no frontmatter (`body_start_line` 1, so
  finding lines are lines of the whole body), and the title as a one-line
  document after removing a leading Conventional Commits prefix, recognised
  only when its type is one of PB1's own `CONVENTIONAL_TYPES` and its scope,
  if any, is a parenthesised token with no space (`feat(cli)!: `), so a
  banned word can't hide in a made-up prefix such as `leverage: `;
- appends one `PB5` finding per occurrence to the PB1 to PB4 findings, at
  most 50 across title and body, then one truncation finding; matching stops
  at the cap rather than scanning on.

A `PB5` message is built only from the rules file (the term and its
category's guidance) and the computed line, never from the title or body, so
a hostile body can't put text into a finding.

Both parts of the body are checked, on purpose: Part 2 is still prose
shirabe publishes on the pull request. A reviewer note that needs to quote a
banned word puts it in inline code, which is never matched.

Without the flag nothing changes: `check_pr_body` and the default output are
untouched, and the flag declares `requires = "pr_body"` like `--pr-title`.

Opt-in keeps the reusable workflow, the hook and every existing test exactly
as they are. Taking the path as the flag's value makes loading explicit and
loud for this check without touching FC10's behaviour for documents. Reusing
the envelope keeps the gate's exit mapping (0 clean, 2 violations).

#### Alternatives Considered

**Default-on prose check in `--pr-body` through `cached_rules()`.** Rejected:
it changes adopters' CI annotations and the hook's decisions without their
asking, and checks nothing, silently, wherever no `rules.yaml` is found, which
is every adopting repository.

**A boolean flag, with the gate setting `SHIRABE_RULES`.** Rejected: the path
travels implicitly through the environment, and the loading path would still
be the fail-open one unless reworked anyway.

**A separate generic mode (`--prose <file>`) the gate calls a second time.**
Rejected: two validator processes per evaluation, the title handled outside
the pull request logic, and findings merged in bash.

**A `--repo-root <dir>` flag for the vocabulary.** Rejected for now: its only
caller would pass `$PWD`. It's the fix if a caller ever checks a pull request
for a repository other than the one it runs in.

### Decision 3: The registry rule and its text

Resolved inline.

Every finding needs a registered `rule_id` and a `rule_ref` that opens the
rule's text. `prose/banned-word` already exists for /scope's documents, with
the same text.

Key assumptions:

- `scripts/check-rule-registry.sh`'s shared-key rule (each entry sharing a
  baseline key names the other in its notes) is the only extra obligation of
  sharing one.

#### Chosen: a new `pr-body/banned-word`, anchored in `rules.yaml`

A new entry, alias `PB5`, whose `text` uses the same anchors as
`prose/banned-word` (the `words:` block of `skills/writing-style/rules.yaml`),
`check` `skills/work-on/scripts/check-pr-output.sh` mode `--pr-body`,
`timing` `work-on:pr_creation` and `execute:pr_finalization`, `level` `gate`,
`guards` `pr-create` and `publish`, `withhold` `never`. It shares
`prose/banned-word`'s baseline key, `skills/writing-style/rules.yaml#L17-L89`,
and both entries' notes name each other. `references/pr-body-conformance.md`
gains a PB5 entry that points at `rules.yaml` instead of restating the list.

The registry's rule is that changing what a rule means takes a new id, and
each entry names one checking script; the pull request rules already split
this way (`commit/no-ai-trailer` beside `pr-body/no-ai-trailer`). Anchoring in
`rules.yaml` keeps one home for the list. Sharing the baseline key is
accurate: the preloaded text a run read at the pinned commit is the same range
for both rules.

#### Alternatives Considered

**Widen `prose/banned-word` to the pull request states.** Rejected: its
`check` names the /scope script, and counts per output would merge into one.

**Anchor the text in a PB5 section of `pr-body-conformance.md`.** Rejected:
the list would have to be restated, which CI forbids, or the anchor would
frame a pointer rather than the rule.

**An empty `baseline_keys`.** Rejected: it would claim the rule had no
preloaded text at the pinned commit, which is false.

### Decision 4: Version skew, and whether the gate needs a canary

Resolved inline.

A plugin newer than the installed binary meets a validator that doesn't know
`--writing-style`; clap rejects the flag with exit 1 and no envelope.
`check-hop-document.sh` runs a canary banned word because the document check
fails open on missing rules.

Key assumptions:

- Plugin and binary normally ship together in a release, so skew is mostly a
  development-time condition.

#### Chosen: fail closed, caught at preflight, no canary

The gate always passes `--writing-style`. An exit 1 from the validator is the
gate's could-not-decide exit 2, as it is today, and when stderr shows clap
rejected `--writing-style` the gate's stderr line says the installed shirabe
predates the check and should be upgraded. The state holds. Both skills'
always-applicable `shirabe validate` records in `requires.tsv` declare
`--pr-body`, `--pr-title` and `--writing-style`, so `skill-preflight.sh`
reports the gap when the skill loads. There's no canary: the explicit flag
fails loudly on a bad rules file, the flag's existence is the version check,
and message-prefix drift is caught by a real-validator case in the gate's
suite, which CI runs against a binary built from the same commit.

#### Alternatives Considered

**Degrade: run only PB1 to PB4 when the binary lacks the flag.** Rejected: a
check that silently does nothing is the failure `rules.yaml` exists to end.

**Rerun once without the flag on skew, print PB1 to PB4 problems on stderr,
and still exit 2.** Decision 1's decider proposed it so a developer sees the
structural problems during skew. Rejected for now: it adds a second validator
run and a probe to a path preflight already reports, and the structural
problems appear on the next tick after the upgrade. It is the change to make
if skew proves long-lived.

**A canary banned word per run.** Rejected: a second validator process for a
failure the explicit flag already reports.

**Refuse a `shirabe` inside the repository under review**, as the /scope gate
does. Rejected: the body isn't a file in the tree and the rules path is
pinned; the exposure is the one PB1 to PB4 already have, unchanged here.

## Decision Outcome

The check lives in `shirabe validate`, behind an opt-in flag that only the
workflow gate passes. The validator loads the rules file the gate names,
matches with FC10's own span-level matcher over FC10's CommonMark scoping, and
resolves vocabulary from the repository the gate runs in. The gate pins the
plugin's own rules file, maps the new `PB5` findings to
`pr-body/banned-word`, and holds when it can't decide. The registry gains one
rule, never eligible to withhold, sharing its text and baseline key with the
document rule. Preflight names the flag, so a host whose binary predates the
check learns it when the skill loads.

Together these meet the PRD without moving anything else: adopters' CI,
`pr-body-hook`, PB1 to PB4, FC10's document behaviour and every existing
consumer of `shirabe-pr-body/v1` see the same bytes they see today. No tool is
added anywhere. And the commit-message side of the original question is
answered too: the rules commitlint would bring are either already native or
recorded as later opt-in title checks.

## Solution Architecture

### Overview

```
koto (pr_creation / pr_finalization)
  └─ check-pr-output.sh --pr-body [--owned ...]
       ├─ gh pr view --json title,body          (unchanged)
       ├─ shirabe validate --pr-body <tmp> --pr-title <t> --format json \
       │      --writing-style <plugin>/skills/writing-style/rules.yaml
       │    ├─ check_pr_body / check_pr_title  → PB1..PB4   (unchanged)
       │    └─ check_pr_writing_style          → PB5        (new)
       │         ├─ rules::load_rules(<path>)  (explicit, fail loud)
       │         ├─ vocabulary from current_dir()
       │         └─ banned_terms_in_spans(..)  (shared with FC10)
       └─ rule_for_message: "[PB5] " → pr-body/banned-word, rf_finding
```

### Components

**`crates/shirabe-validate/src/checks.rs`.** The term loop inside
`check_writing_style_with` moves into a public span-level function,
`banned_terms_in_spans(spans, rules, vocabulary, cap) -> (Vec<TermHit>,
bool)`, returning each hit's term and line and whether the cap was reached.
`check_writing_style_with` calls it and builds the same FC10 errors as today,
so document output doesn't change by a byte (the golden parity tests pin it).

**`crates/shirabe-validate/src/pr_body.rs`.** A new public
`check_pr_writing_style(body: &str, title: Option<&str>, rules: &Rules,
vocabulary: &[String]) -> Vec<PrBodyFinding>`. It builds prose spans for the
body (no frontmatter, line 1 first) and for the title with its Conventional
Commits prefix removed, calls `banned_terms_in_spans` over the title first and
then the body with one cap of 50, and renders messages:

- `[PB5] writing-style banned word "<term>" in the title -- <guidance>`
- `[PB5] writing-style banned word "<term>" on line <n> -- <guidance>`
- `[PB5] writing-style findings truncated at 50 for this pull request; fix these and re-run to see the rest`

`<guidance>` is the term's category `guidance` from `Rules::category_for`,
with whitespace collapsed to one line; when it's empty the ` -- <guidance>`
part is left out. Title findings carry `line` 1, as PB1's do; the message,
not the line, says where the term is. `check_pr_body` is not touched.

**`crates/shirabe-validate/src/visibility.rs`.** A small public
`resolve_prose_vocabulary_from_dir(dir: &Path)` that runs the same header
walk starting at `dir` itself, so the CLI can pass `current_dir()`.

**`crates/shirabe/src/main.rs`.** `ValidateArgs` gains
`#[arg(long, value_name = "FILE", requires = "pr_body")] writing_style:
Option<String>`. `run_pr_body_mode` takes it: when present it loads the
rules (any `RulesError`, or a rule set with no banned term, prints
`--writing-style: <reason>` on stderr and returns `ToolError`), resolves the
vocabulary from the working directory, and appends
`check_pr_writing_style`'s findings to the PB1 to PB4 findings before the
outcome is decided. The three output formats render them as they render any
`PrBodyFinding`. The misleading comments in `rules.rs` and `rules.yaml` that
describe a `--rules` flag are corrected to say what actually resolves the
rules (the `SHIRABE_RULES` variable and the walk, plus the explicit path this
flag gives).

**`skills/work-on/scripts/check-pr-output.sh`.** In `--pr-body` mode only,
after argument parsing:

- `RULES_FILE=$(cd "$HERE/../../writing-style" && pwd -P)/rules.yaml`, the
  plugin's own file; if it isn't a readable regular file the gate is
  undecided;
- `RULE_IDS` and the `require_rules` call gain `pr-body/banned-word`;
- the validator call appends `--writing-style "$RULES_FILE"` after the
  existing arguments, so the suite's positional assertions hold;
- `rule_for_message` matches `"[PB5] "*` first, before the `PR title ` arm;
- on validator exit 1, when the whole of the validator's stderr (not its
  last line, which is clap's usage hint) mentions `--writing-style`, the
  undecided message names the upgrade.

The header comment's rule table gains PB5.

**`references/rule-registry.json`.** The `pr-body/banned-word` entry
(Decision 3), and `prose/banned-word`'s notes naming it.

**`skills/work-on/requires.tsv`, `skills/execute/requires.tsv`.** work-on's
`always` `shirabe validate` record adds `--writing-style`; execute's `always`
record adds `--pr-body`, `--pr-title` and `--writing-style`, closing the gap
where `pr_finalization` runs `--pr-body` with only the coordinated-mode record
declaring it.

**Prose.** The `pr_creation` gate comment and directive in
`skills/work-on/koto-templates/work-on.md`, the `pr_finalization` gate comment
and rule-id list in `skills/execute/koto-templates/execute.md`,
`skills/work-on/references/phases/phase-6-pr.md`, and
`references/pr-body-conformance.md` name the banned-word check and
`pr-body/banned-word`, point the agent at `skills/writing-style` when it
writes the title and body, and say the check runs at the workflow gate, not in
CI. `docs/designs/current/DESIGN-output-gates.md`'s mapping table gains the
PB5 row.

**CI.** `skills/writing-style/rules.yaml` joins the path filters of
`.github/workflows/check-work-on-scripts.yml`, which now reads it.

### Key Interfaces

```
shirabe validate --pr-body <file> [--pr-title <t>] [--writing-style <rules>] [--format json|annotation|human]
  exit 0  clean (no PB1..PB5 finding)
  exit 2  violations: findings in shirabe-pr-body/v1
  exit 1  tool error: unreadable body, --writing-style without --pr-body,
          rules file missing, unreadable, malformed or with no banned term

check-pr-output.sh --pr-body [--owned <owned-pr.sh args>]   (unchanged contract)
  exit 0  conformant; 1 violations (::koto-finding:: lines); 2 could not decide
```

A PB5 finding as the gate prints it:

```
::koto-finding::{"rule_id":"pr-body/banned-word","level":"error","message":"<summary>: [PB5] writing-style banned word \"leverage\" on line 3 -- Prefer the plain verb. ...","rule_ref":"skills/writing-style/rules.yaml#L17-L89@<revision>"}
```

### Data Flow

1. koto ticks `pr_creation` (or `pr_finalization`) at the session anchor and
   runs the gate.
2. The gate resolves `pr-body/banned-word` with the other pull request rules,
   reads the title and body from GitHub, and writes the body to a temp file.
3. It runs the validator once with `--writing-style` naming the plugin's
   `rules.yaml`.
4. The validator loads the rules (or exits 1), resolves the vocabulary from
   the working directory, and returns PB1 to PB5 findings with exit 2, or
   exit 0.
5. The gate maps each message to its rule id and prints one
   `::koto-finding::` per finding; koto records `rule_counts` in
   `gate_evaluated` and exports one `check_rule` record per rule id.
6. The agent reads the findings in `koto next`, fixes the pull request with
   `gh pr edit`, and submits again; the gate re-reads the live title and body.

## Implementation Approach

### Phase 1: The validator check

The span-level matcher, `check_pr_writing_style`, the working-directory
vocabulary helper, the `--writing-style` flag and its loading, and the comment
corrections, with unit tests for title, body, both parts, case and
whole-word matching, every exclusion, the prefix removal, vocabulary from
`CLAUDE.md` and `CLAUDE.local.md`, the cap, empty guidance, and every rules
failure; plus a test that the default `--pr-body` bytes are unchanged and the
hook's tests still pass.

### Phase 2: The gate, the registry and preflight

`check-pr-output.sh`'s rules pinning, mapping and skew message; the registry
entry and `prose/banned-word`'s notes; both `requires.tsv` records; the CI
path filter; and the gate suite's new cases with the stand-in validator, plus
one real-validator case pinning the PB5 prefixes.

Phases 1 and 2 land in one pull request and one release: a plugin whose gate
passes `--writing-style` must not ship ahead of a binary that knows it. CI's
`check-work-on-scripts.yml` already builds `shirabe` from the same commit on
its Linux leg, which is what the real-validator case runs against.

### Phase 3: What the workflows say

The template comments and directives, `phase-6-pr.md`,
`pr-body-conformance.md`, the output-gates mapping row, and the skills' eval
scenarios for the changed directives.

## Security Considerations

The gate reads three things an author can influence: the pull request's title
and body, the `## Prose Vocabulary:` header in the repository's `CLAUDE.md` or
`CLAUDE.local.md`, and the `shirabe` binary on the PATH koto recorded at
`koto init`. The rules file is not one of them. The gate names the plugin's
own `rules.yaml` by absolute path, resolved with `pwd -P` from the script's
location, and the validator loads exactly that file. It never reads
`SHIRABE_RULES` (which koto doesn't pass to a gate anyway) and never walks the
working directory for rules, so a `rules.yaml` planted in the repository, or
an inherited empty value, can't switch the check off. A missing, unreadable
or malformed file, or one with no banned term, is a tool error and the state
holds.

The title and body are untrusted text. They reach the validator as one
argument and one temporary file, with nothing evaluated, as they do today. A
`PB5` message is built only from the rules file and a line number the
validator computes; it never quotes the title or body, so a hostile body
can't put text into a finding. koto keeps each finding's message in the
session's own `gate_evaluated` event, and its exported run journal carries
only the gate, the rule id and counts, never a message. The gate builds
each finding with `jq` through `rf_finding`, which replaces control
characters, so no message can start a second `::koto-finding::` line, and
koto caps each message at 1,000 bytes. A message's length is bounded by the
guidance text in the rules file. The body is bounded by GitHub's size limit
and the findings by the cap of 50, at which matching stops; a validator test
runs the check on a body of GitHub's maximum size. The title prefix is
removed only for PB1's own types, so a banned word can't be hidden in a
made-up prefix.

The declared vocabulary is the one accepted way to suppress a term, and it
comes from the branch under review: a pull request that adds a term to
`## Prose Vocabulary:` passes for that term. That is the exposure documents
already have under FC10, and the check exists to catch slips, not to stop an
author who edits the declaration on purpose. To keep it visible the
validator prints the suppressed terms on stderr, using the rules file's
strings. The walk stops after the first directory holding `.git`, a
directory or a file (as worktrees use), so a declaration above the
repository is never read; outside any repository it reaches the filesystem
root, as FC10 does. It extracts one header line from each file it opens.
`CLAUDE.local.md` is often untracked and the agent under the gate can write
it, which is why the stderr line, not the diff, is the record of a waiver.

The verdict is only as trustworthy as the `shirabe` that gives it, which is
the binary that already decides PB1 to PB4 at this gate. The design doesn't
refuse a `shirabe` inside the repository under review, as the /scope gate
does: shirabe's own contributors are told to put a branch-built binary first
on PATH, the refusal would hold every one of their pull requests, and the
exposure it closes is unchanged by this feature. An older binary rejects the
flag with exit 1 (`exit_for_parse_error`, pinned by
`crates/shirabe/tests/cli.rs`), which the gate reads as could-not-decide and
names the upgrade; preflight reports it when the skill loads. The upgrade
wording is chosen by matching clap's `unexpected argument '--writing-style'`
text; whatever stderr says, the exit is the same 2, so a title crafted to
imitate that text changes only the message, never the verdict. A koto
timeout ends the gate with exit -1, which matches no edge, so the state
holds. No tool is
added to either skill's `requires.tsv`, which also keeps a commitlint
configuration's branch-controlled JavaScript out of the gate.

Residual risks accepted:

- A branch-declared vocabulary can waive any term.
- Text in code, HTML comments, link destinations and table cells isn't
  checked, as for documents, and matching is ASCII-literal: homoglyphs,
  zero-width characters and unlisted inflections pass.
- The gate reads the title and body when it runs; an edit after it passes
  isn't checked, as for PB1 to PB4.
- The rules file is the plugin's own. Where the plugin is loaded from a
  working tree rather than an installed cache, as when shirabe develops
  itself, that file is the branch's, and a pull request can edit the list it
  is checked against; review of `rules.yaml` and CI's checks on it are what
  catch that.

## Consequences

### Positive

- A banned word in a pull request title or body holds the run with a finding
  that names the word, the line, what to prefer and where the rule is, so the
  agent fixes it before review.
- Each hold is counted under `pr-body/banned-word` in koto's exported check
  events, beside the structural pull request rules.
- Documents and pull requests are judged by one matcher, so a term is allowed
  or flagged the same way in both.
- The new path loads its rules file explicitly and fails closed, unlike FC10's
  silent skip.
- Nothing is installed, and adopters' CI and the hook don't change.

### Negative

- The gate now depends on a validator release. A host with a newer plugin
  than binary holds every pull request at the gate until it upgrades.
- The check runs after `gh pr create`, so a banned word is public until the
  agent edits the pull request.
- Vocabulary comes from the repository the gate runs in, which for an
  /execute run finalizing a pull request in another repository isn't that
  pull request's repository.
- Spelling checks, off-the-shelf style packages and commitlint's header
  rules are given up.

### Mitigations

- Preflight names `--writing-style` when the skill loads, and the gate's
  undecided message names the upgrade.
- The rule is `withhold: never`, so the guidance stays preloaded while the
  check settles in, and a later lifecycle feature can watch its pass rate
  before anyone weighs withholding it.
- A `--repo-root` flag is the recorded fix for the cross-repository case if a
  caller needs it.
- commitlint's header rules are recorded as later opt-in title checks with
  their own ids.
