# Decision 2: rule source format

**Question.** In what format does the single rule source live, such that
`shirabe validate` parses it at enforcement time and a drafting skill reads it
as instructions, with neither restating it?

## Ground facts established first

Four facts constrain every option, and three of them were not obvious before
looking.

**The plugin ships the whole repository.** `.claude-plugin/marketplace.json`
declares `"source": "./"` and README.md's install path is
`claude plugin marketplace add "tsukumogami/shirabe"`. The plugin root is a
clone of the repo root, so `${CLAUDE_PLUGIN_ROOT}/<anything committed>`
resolves. `plugin.json`'s `"skills": "./skills/"` names where skills are found,
not what is shipped. 63 files already resolve
`${CLAUDE_PLUGIN_ROOT}/references/...`, which confirms non-`skills/` content
arrives. No option is disqualified on "can the agent reach the file".

**The validator ships a YAML parser already.** `crates/shirabe-validate`
depends on `saphyr =0.0.6` and `saphyr-parser =0.0.6`, and
`frontmatter.rs:189-216` drives `YamlLoader::<MarkedYamlOwned>` through
`Parser::new(BufferedInput::new(...))` on an arbitrary string. It reads
mappings with per-node `Span` line markers, and `early_parse(false)` preserves
as-written scalar text. Options B, C, and D need no new dependency and no new
parsing technique. Option A is the only one that needs code the crate does not
have.

**The validator already walks up from a checked file to find a config.**
`visibility.rs:82-92` ascends from the doc's canonicalized parent looking for
`CLAUDE.local.md` then `CLAUDE.md` at each level. That is the exact shape R16
needs for the per-repo vocabulary declaration, and it is orthogonal to the rule
source: vocabulary resolves from the *file being checked*, the rule source
resolves from *shirabe*. Every option inherits this precedent equally.

**Twelve pointers to the rulebook are repo-relative today, not plugin-rooted.**
Eleven SKILL.md files plus `skills/plan/references/plan-format.md` say
``Read `skills/writing-style/SKILL.md` for guidance`` with no
`${CLAUDE_PLUGIN_ROOT}` prefix, against 63 files elsewhere that use the
prefixed form. The drafting-side half of R2 is broken today for a reason that
has nothing to do with format. Every option pays this 12-file edit, so it
cancels out of the comparison, but it must not be forgotten in the plan.

## Options considered

### A. Parse the existing SKILL.md markdown tables

The rulebook stays at `skills/writing-style/SKILL.md`. The validator gains a
markdown table parser and reads the tables at validate time.

*R1 at enforcement time.* Satisfied in principle. Requires a table parser the
crate does not have, roughly 50 lines (measured below), plus section-heading
location logic.

*R2 both consumers.* The drafting consumer reads what it reads today, which is
the option's real attraction. The validator side needs the same resolution work
as every other option (see "The resolution problem" below).

*Fragility.* This is where A fails, and the failure is measured rather than
asserted. See the empirical section: three of four realistic edits break the
parser **silently**, dropping four to fifteen rules while exiting 0.

*Drafting consumer.* Best-in-class, because nothing changes.

*Migration cost.* Lowest on file count: no new file, no SKILL.md rewrite.
Still pays the 12 pointer edits, the `checks.rs` rewrite, the
`phase-4-validate.md` edit, the CI literal check, the contract doc, and the
resolution fix.

*Eval surface.* Unchanged.

*The disqualifier.* A cannot express R6 and R7. The em dash rule exists in the
SKILL.md today as one row of the formatting-tells table:
`| Em dash overuse (—) | Comma, parentheses, or colon |`. R7 requires the
implementation define and the documentation record a denominator, a reporting
unit, a finding line, and a threshold value. None of the four can live in that
row. Making them fit means inventing a micro-syntax inside a prose table, at
which point the file is a data file wearing markdown, and it has all of Option
C's authoring constraints plus a hand-rolled parser and none of C's error
reporting. A is not a cheaper C; it is C with the safety removed.

### B. A structured data file plus a generated or hand-written prose reference

Rules live in `rules.yaml`. The SKILL.md is either generated from it or
hand-written to point at it.

*R1.* Satisfied by the data file.

*R2.* Satisfied. Both consumers reach the same committed file.

*Fragility.* Low for the data file. The failure mode moves to the second
artifact.

*Drafting consumer.* This is B's problem. If the SKILL.md restates the rules in
prose, that restatement is a fourth copy, and R1 forbids exactly this: "The
three current copies SHALL be reduced to that one source plus references to
it." If the SKILL.md is generated instead, the checked-in generated file can
drift from its source whenever the generator is not rerun, which needs a
regenerate-and-diff CI job to catch. That job is real work and it is work spent
maintaining a copy the design chose to create.

*Migration cost.* Everything C pays, plus a generator and its CI check.

*Eval surface.* Unchanged, though evals would now be testing generated prose.

*Verdict.* B is C plus a derived duplicate. It differs from C only in that it
keeps a second prose artifact, and R1 is a requirement written specifically
against keeping second copies. If the prose in B's SKILL.md is not the rules
but guidance on applying them, B *is* C, and the distinction dissolves.

### C. A structured data file with the prose embedded in it

One file, `skills/writing-style/rules.yaml`. Machine-parseable. Its fields
carry the human-facing guidance the SKILL.md tables carry today: category,
term, the fix, the rationale, the qualifier. The SKILL.md keeps the material
that is genuinely not rules (`## What human writing has`, the invoked-directly
versus producing-prose framing) and points at the data file for the rules.

*R1.* Satisfied cleanly. One representation, read at enforcement time by both.

*R2.* Satisfied. The validator reaches
`.shirabe-src/skills/writing-style/rules.yaml`; a skill reaches
`${CLAUDE_PLUGIN_ROOT}/skills/writing-style/rules.yaml`; a local run reaches
the checkout's copy. Same bytes, same commit, three roots. The AC "a CI run's
log shows the rule source and the validator binary resolving from the same
commit SHA" is satisfiable because `validate-docs.yml` checks out shirabe at
`job.workflow_sha` into `.shirabe-src` and builds from that same tree.

*Fragility.* A YAML syntax error fails loudly at parse. A dropped rule requires
someone deleting a list entry, which is visible in review as a deleted line
rather than as a table row that reflows. The set-equality AC ("a test asserts
the equality and names the count") becomes meaningful here: under A it is a
tautology, since both sides parse the same markdown with the same parser and
agree on the same wrong answer.

*Drafting consumer.* Better than today, which is the part worth arguing rather
than assuming. The current material a drafting model gets for the Verbs
category is fifteen words jammed into one comma list with no per-word guidance
at all. Under C each rule carries its own `fix:` and can carry `why:`. The
`landscape (fig.)` qualifier stops being an uninterpretable parenthetical and
becomes a field. Structured lists of rules-with-rationale are ordinary
instruction material for a model; nothing about YAML makes it unreadable, and
the format is what the frontmatter of every artifact the model already writes
is in.

*R6 and R7.* Native. `threshold: 3`, `unit: per-document`,
`denominator: prose-words`, `line: 1` are fields. The AC "the test reads the
threshold from the recorded value rather than hardcoding it" is satisfiable
without a second source of truth.

*R8 and R16.* The per-repo vocabulary declaration becomes a sibling file in the
same format, found by the `visibility.rs` walk-up from the checked file, parsed
by the same loader. One format, two files, consistent story.

*Migration cost.* Highest, and honestly so: a new file, a SKILL.md rewrite, a
loader module, the `checks.rs` rewrite, `phase-4-validate.md`, 12 pointers, the
CI literal check, the contract doc, the resolution fix.

*Eval surface.* `skills/writing-style/evals/evals.json` restates the word list
inside its assertion strings, which the PRD's AC explicitly exempts. Those
assertions stay as they are and stay valid: they assert on *output*, not on the
rulebook's shape. What changes is that the AC's new propagation eval ("the same
added rule is honored by a drafting skill without a second edit") gets easier
to write, because appending one YAML entry is a cleaner fixture mutation than
editing a table cell.

### D. Frontmatter in the SKILL.md

Rules in the SKILL.md's YAML frontmatter, prose in the body. Genuinely one
file.

*R1 and R2.* Satisfied, and elegantly: one path, one file, both consumers,
nothing new shipped.

*Parsing.* Cheapest of all four. `frontmatter.rs`'s `parse_doc` already splits
frontmatter and hands back per-key line numbers. D reuses it verbatim.

*Fragility.* Low, same as C.

*Drafting consumer.* Fine. Same content as C, different location.

*Migration cost.* Lower than C by one file.

*The problem.* SKILL.md's frontmatter schema is owned by Claude Code, not by
shirabe. Every one of shirabe's 20 skills carries exactly two frontmatter keys,
`name` and `description`; there is zero precedent in this repo for a third. D
would put roughly 120 lines of shirabe-defined YAML into a block another
vendor's loader reads and validates, and shirabe would be betting that unknown
keys stay tolerated across Claude Code versions. If that bet loses, the skill
stops loading, and it does not stop loading for the writing-style skill alone:
12 skills route through it. Against that, the saving is one file. D also makes
the rules structurally unavailable to any consumer that is not willing to parse
a markdown file's frontmatter, which forecloses reuse the design has no reason
to foreclose.

D is the option to revisit if the extra-frontmatter-key question is answered
affirmatively and cheaply. It is a twenty-minute test: add a key, load the
plugin. If someone runs it and it passes, D's file-count saving is real and the
coupling is the only remaining objection. It is not enough of a saving to
justify the coupling, but the DESIGN should say so rather than leave the reader
to wonder whether it was considered.

## Empirical results

Throwaway parsers in `/home/dgazineu/.claude/jobs/b0818094/tmp/d2/`.

**The word list extracts, at 48 lexical terms rather than 47.** The parser
(`parse_a.py`, 48 non-blank non-comment lines: frontmatter strip, section
locate, pipe-row split, separator and header skip, comma split, slash split)
returns 5 rows and 48 terms across all five categories. The PRD says 47 because
`tier/tiered` is one comma-separated entry and two lexical terms. A parser has
to pick, and either count is defensible, which means the acceptance criterion
"a test asserts the equality and names the count" forces the question that the
markdown format leaves ambiguous. In C the ambiguity does not arise: two
entries or one entry with two surface forms, written explicitly.

**Three edge cases bite, exactly as anticipated.**

`landscape (fig.)` extracts as the literal string `landscape (fig.)`, which
matches nothing. Stripping the parenthetical yields `landscape`, which discards
the only thing the row said: ban it in figurative use, not literal. The
qualifier is unrepresentable in a flat word list either way. It needs a field.

`align with` extracts correctly and, checked against the current matcher in
`checks.rs:2572-2604`, would work: that matcher is a substring `find` with
byte-level word-boundary tests, not a tokenizer. A token-based rewrite would
break on it.

The seven Adverb openers extract with their capitalization, and the
capitalization is load-bearing: `Additionally`, `Notably`, `Ultimately` are
tells at sentence start and unremarkable mid-sentence. `Ultimately` mid-clause
is fine prose. The current matcher lowercases the line before searching, so it
would fire on all of them everywhere. The markdown table encodes the
position-scoping in a convention (initial capitals in one row, lowercase in the
other four) that no parser can be expected to read as semantics.

**Slash-joining is exercised exactly once.** `tier/tiered` is the only slash
entry in the table. Single-instance conventions are the ones a later editor
does not know exists.

**The other four rule classes do not share the word table's shape.** Parsing
all seven sections (`parse_a2.py`) returns four distinct shapes: a two-column
table whose second cell is a comma list (words); two-column tables of quoted
literals (over-formality substitutions, 6 rows); two-column tables mixing
quoted literals, prose descriptions, and parentheticals (structural patterns 7
rows, formatting tells 5 rows); and bullet lists with the rule and its
rationale separated by an em dash (phrases 7, cognitive tells 4, what human
writing has 4). Option A does not need one table parser. It needs four
extractors, one of which (`| Em dash overuse (—) | Comma, parentheses, or
colon |`) has no machine-actionable content at all.

**Fragility is worse than "a reformat could break it".** `mutate.py` applies
seven semantics-preserving edits and diffs the extracted set:

| Edit | Result |
|---|---|
| Prettier-style column padding | ok, 48 terms |
| Verbs row split across two rows for readability | ok, 48 terms |
| Sections reordered | ok, 48 terms |
| Heading reworded to `## Avoid: words (all categories)` | **crash**, loud |
| Leading and trailing pipes dropped (valid GFM) | **silent**, 40 terms, lost `comprehensive` `crucial` `holistic` `paramount` |
| A third column added to the table | **silent**, 40 terms, same four lost |
| An entry containing a literal pipe | **silent**, 33 terms, lost 15 |

Three of the four breaks exit 0 and report a smaller rule set as if it were the
whole rule set. The third-column case is the one to sit with: someone adds a
`Why` column to help the drafting model, which is a good-faith improvement to a
prose file, and the Organizing row silently stops being enforced. That is the
failure the PRD's Problem Statement opens with, a checking surface reporting
success without having checked, reintroduced by the mechanism chosen to fix it.

Naming the count in the equality test catches these three, which is a real
mitigation and worth stating. It converts silent to loud. It does not convert
fragile to durable: the test then fails on every good-faith table edit, and the
fix is to edit a hardcoded count in Rust, which is a second place the rule set
is written down.

## The resolution problem, which no format solves

Worth surfacing for whichever Decision owns it, because it changes the plan
regardless of format. `validate-docs.yml:74-78` builds the binary from
`.shirabe-src/target/release/shirabe` and then runs
`install -m 0755 ... /usr/local/bin/shirabe`. The binary is detached from its
source tree, so resolving the rule file relative to `std::env::current_exe()`
lands in `/usr/local/bin/`. The working directory is the caller's repo root, so
`.shirabe-src/skills/writing-style/rules.yaml` happens to resolve from cwd
today, but that is incidental to this workflow rather than a contract, and it
does not hold for a local run or for a drafting skill.

The rule source needs an explicit resolution: an env var set by the workflow, a
`--rules` flag, or dropping the `install` step so exe-relative works. None is an
install, fetch, download, or package-manager step, so R18 and the AC on the
workflow diff are safe, and `validate-docs.yml` is shirabe's own reusable
workflow rather than an adopter caller, so R20 is untouched.

## Recommendation

**Option C: one YAML file at `skills/writing-style/rules.yaml` carrying both
the machine-parseable rules and the per-rule prose, with the SKILL.md reduced
to application guidance plus a pointer.**

The rules parse with `saphyr`, already a dependency and already driven over
arbitrary strings in `frontmatter.rs`. R6 and R7's threshold, denominator,
reporting unit, and finding line become fields rather than prose a parser must
guess at. The per-repo vocabulary declaration in R8 and R16 reuses the same
format and the same `visibility.rs` walk-up. The drafting consumer gets better
material than the comma-jammed table rows it gets today, not worse.

**The strongest counter is Option A's,** and it is a good one: the rulebook is
prose written for a model to read, the model reads it fine today, and moving it
into YAML risks degrading the consumer that actually works in order to serve
the one that does not. Migration cost falls almost entirely on the working
side.

The answer is that A cannot do the job the PRD asks for. R6 and R7 require a
threshold, a denominator, a reporting unit, and a finding line for the em dash
rule, and the row that rule occupies today reads `Em dash overuse (—)`. Fitting
four machine-readable values into that row means designing a syntax inside a
markdown table, which produces a data file with worse ergonomics and a
hand-rolled parser. And the measured fragility is not hypothetical: adding a
helpful third column to that table drops four rules and exits 0. A prose file
can be edited by anyone who reads it; that is its virtue as instructions and
its defect as a parse target. The degradation risk to the drafting consumer is
also the cheapest thing in this decision to falsify, because
`skills/writing-style/evals/evals.json` and `scripts/run-evals.sh` exist and
the PRD already requires a propagation eval. Run the existing evals against the
rewritten SKILL.md before merging. If they regress, the fix is more prose in
the YAML, not a different format.

Option B is C with a derived duplicate and a generator to keep it honest, which
is the copy-that-drifts shape this capability exists to end. Option D saves one
file by putting 120 lines of shirabe-owned YAML into a frontmatter block whose
schema Claude Code owns, with zero precedent across shirabe's 20 skills and 12
skills downstream of a load failure.

## Confidence

**High** that Option A should be rejected. The R6/R7 disqualifier is a
requirements argument that does not depend on judgment, and the silent-drop
behavior is measured, not predicted.

**High** that B collapses into C or violates R1.

**Medium-high** on C over D. D's objection is a coupling risk rather than a
demonstrated failure, and it is cheap to test: add an unknown frontmatter key
to a skill and load the plugin. If the DESIGN wants to spend twenty minutes,
the answer either removes D or strengthens the case against it. C stands either
way, because the file-count saving D offers is not what makes this decision
hard.

**Medium** on the specific path `skills/writing-style/rules.yaml` rather than
`references/writing-style-rules.yaml`. Both ship in the plugin and both resolve
from `.shirabe-src`. Co-location with the owning skill is the better default;
the counter is that the acceptance criterion's CI check scans `skills/**` for
word-list-shaped literals and would need this path exempted alongside the
`skills/writing-style/evals/` exemption it already carries. That is one line in
a check that already has an exemption list, not a reason to move the file.
