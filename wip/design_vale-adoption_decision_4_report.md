# Decision 4: file-selection gate

Binary: `./target/release/shirabe` (pre-built, at HEAD `1f00e22`). All paths
relative to
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption`.

## Verified current behavior

### 1. A directory argument is silently skipped

```
$ ./target/release/shirabe validate --format human -- docs
All checks passed.

Advisory: Draft posture: no draft-tolerable findings to flag.
exit=0
```

The same corpus as an explicit file list:

```
$ find docs -name '*.md' -print0 | xargs -0 ./target/release/shirabe validate --format human --
docs/designs/current/DESIGN-plan-review.md:1 notice schema field missing, skipping
... (truncated)
docs/designs/current/DESIGN-shirabe-comp-skill.md:303 notice [FC10] writing-style banned word "tier" ...

5 error(s), 146 notice(s) -- violations
```

147 files. The PRD says 139 notices; the tree now emits **146** — the corpus
drifted between the PRD's measurement and HEAD. The error count (5) is
unchanged. Same corpus, same flags: exit 0 / "All checks passed" against exit 2
/ 5 errors, decided entirely by whether the caller expanded the glob.

The mechanism is not a directory-specific branch. `basename("docs")` is
`"docs"`, `detect_format("docs")` returns `None`, and `main.rs:604-607`
`continue`s. The file is never opened. Proof that nothing is read:

```
$ ./target/release/shirabe validate --format human -- /nonexistent/CLAUDE.md /nonexistent/README.md
All checks passed.
exit=0
```

A path that does not exist reports success. This is stronger than the PRD's
framing: the gate does not silently skip *directories*, it silently skips
*everything whose basename lacks an artifact prefix*, without stat-ing it.

### 2. Instruction files are never checked

```
$ ./target/release/shirabe validate --format human -- README.md AGENTS.md skills/design/SKILL.md
All checks passed.
exit=0
```

### 3. FC-CONVENTIONS is unreachable

```
$ ./target/release/shirabe validate --format human -- CLAUDE.md
All checks passed.
exit=0

$ grep -v 'Release Notes Convention' CLAUDE.md > /tmp/cmtest/CLAUDE.md   # header count now 0
$ ./target/release/shirabe validate --format human -- /tmp/cmtest/CLAUDE.md
All checks passed.
exit=0

$ ./target/release/shirabe validate --check FC-CONVENTIONS --format json -- /tmp/cmtest/CLAUDE.md
{"summary":{"outcome":"clean","errors":0,"notices":0},"findings":[], ...}
exit=0
```

`check_claude_md_conventions` (`crates/shirabe-validate/src/checks.rs:3167`) is
fully implemented, gates on `basename != "CLAUDE.md"`, is registered in the
cross-format dispatch block (`validate.rs:210`), in `is_intrinsic_notice`
(`validate.rs:96`), and in `is_known_check_code` (`validate.rs:170`), and has
four passing unit tests (`checks.rs:6270-6300`). Every touchpoint but one is
correct. The one that is wrong is upstream of all of them: `detect_format`
returns `None` for `CLAUDE.md`, so `validate_file` is never called and the
dispatch entry never executes. This is dead code that the check-code registry
believes is live.

### 4. Line numbers are off by the frontmatter length

```
$ ./target/release/shirabe validate --format json -- docs/prds/PRD-vale-adoption.md
  { "code": "FC10", ..., "line": 41 }
  { "code": "FC10", ..., "line": 164 }
```

Frontmatter delimiters in that file are at lines 1 and 24, so `body[0]` is
absolute line 25 and the offset is 24.

```
$ sed -n '41p;65p;164p;188p' docs/prds/PRD-vale-adoption.md
41:  categories, plus phrase patterns, structural patterns, formatting tells,
65:  `tier`/`tiers`/`tiered` at 147 because Tier 1-4 is its decision vocabulary, and
164: occurrence in the file as the author sees it. The current check reports
188: SHALL NOT be rule-scoped: suppressing `tier` must not disable the word rules
```

Reported 41, real 65. Reported 164, real 188. Offset exactly 24 in both cases.

**The PRD asks whether `Doc` carries the body start line. It does not.**
`crates/shirabe-validate/src/doc.rs:29-39` has `path`, `schema`, `status`,
`fields`, `sections`, `body`. `sections` carries *absolute* lines (`scan_body`
is passed `body_start_line` and offsets each heading), and `fields` carries
absolute lines (`parse_yaml_fields` adds `fm_start_line - 1`). Only `body` is
bare `Vec<String>` with the offset discarded at `frontmatter.rs:130`. So the doc
model is 2/3 absolute and 1/3 body-relative, and nothing names the difference.

Three checks read `doc.body` with `line: idx + 1` and therefore carry the bug:
`check_writing_style` (FC10, `checks.rs:2599`), the AC field-shape check (FC12,
`checks.rs:2721`), and `check_eval_fixture_frontmatter` (FC13,
`checks.rs:2843`). FC13 is benign by accident — it only fires when the first
non-blank line is an HTML comment, i.e. when no frontmatter parsed, where the
offset is zero.

**Additional finding, not in the brief.** `mermaid.rs:158-215` mixes the two
conventions inside one struct. `BlockLocation.body_start` is `heading_line`
(absolute, read from `doc.sections`) on the missing-block path but `open_idx +
2` (body-relative) on the found-block path, and `checks.rs:1044` reindexes it
with `.saturating_sub(1)` on the assumption that it is body-relative. Retrofit
`Doc.body_start_line` into that module and FC08's slicing silently shifts by the
frontmatter length. Scope the R5 fix to the three `idx + 1` sites; treat the
mermaid mixing as a separate disclosed defect.

## Options considered

None of the three options adds or removes a check code, so **none of them
disturbs any of the seventeen registration touchpoints for existing codes**.
The seventeen become relevant only for the single new prose code R14 mandates,
which belongs to the rule-engine decision, not this one. What each option
disturbs instead is the *shape of touchpoint 4* — "where do I register a new
check so it actually runs" — and that is the fair comparison.

### Option A — two-tier format resolution (prose pseudo-format)

`detect_format` keeps returning `None`; a second step hands any `.md` file that
got `None` a synthetic prose-only `FormatSpec`.

The sentinel cannot live in `formats()`. `detect_format` iterates that table and
matches on `basename.starts_with(&spec.prefix)`; a spec with an empty prefix
matches every filename and wins nothing (longest-prefix keeps it last), but it
also becomes visible to `lifecycle.rs:361`, `transition.rs:658` and
`finalize.rs:371/423`, which all iterate or call into the same table and treat a
resolved format as an artifact type. So the sentinel must be a free-standing
constant that is deliberately absent from the table it is typed as belonging to.

Then the schema gate misfires. `validate_file` short-circuits at
`validate.rs:185` when `doc.schema != spec.schema_version`. A pseudo-spec with
`schema_version: ""` passes for a README with no frontmatter, but a non-artifact
`.md` that happens to carry `schema: something/v1` (skill eval fixtures do)
would emit `schema "something/v1" not in supported range, skipping` and get no
prose checks — a new false green in the exact class R3 exists to close. So the
gate needs a sentinel-aware bypass too.

Finally, every structural check would run against the sentinel unless each one
is taught to bail. `check_fc01` iterates `spec.required_fields`, `check_fc04`
iterates `spec.required_sections`, `check_fc15` checks section order — with
empty vectors they emit nothing *today*, but that is emergent, not declared.
Nothing in the type system stops a future check from reading `spec.name` or
assuming a non-empty section list. This is touchpoint 18, and it fails silently,
which is precisely the property the check-lifecycle research flags as this
surface's dominant failure mode (six of seventeen silent; two already stale in
the shipped tree).

**Blast radius:** `formats.rs` (sentinel const), `validate.rs` (schema-gate
bypass + guards), `main.rs` (fallback resolution). Three files, but it adds a
permanent stringly-typed invariant that no compiler enforces.

### Option B — make `FormatSpec` optional per check

`validate_file(doc: &Doc, spec: Option<&FormatSpec>, cfg: &Config)`. `Some`
runs today's path verbatim. `None` runs the schema-independent subset and
nothing else.

The subset already exists and is already schema-independent, visibly:
`check_writing_style(doc, _spec)`, `check_claude_md_conventions(doc, _spec)` and
`check_eval_fixture_frontmatter(doc, _spec)` all take a `FormatSpec` and all
name the parameter `_spec` because they ignore it. The natural refactor is to
drop the dead parameter from those three, lift them into
`run_prose_checks(doc, cfg)`, and call it from both arms.

That refactor is what answers question 3, and it answers it *by construction*:
`check_fc01`, `check_fc04` and `check_fc15` take `&FormatSpec` by value in their
signatures and cannot be called on the `None` path. It is not possible to
regress a README into FC01 without a compile error. Under Option A the same
guarantee is a convention.

It also makes touchpoint 4 self-documenting: a check that takes a spec is
structural, a check that does not is prose, and a new check author places their
function by looking at its own signature rather than by knowing a rule.

**Blast radius:** `validate.rs` (signature, one `Option` match, three functions
moved into a helper), `main.rs:604-607` and `:636` (resolve to `Option`, drop
the `continue`), `checks.rs` (three signatures lose `_spec`). One production
call site of `validate_file` — `main.rs:636` — and nine test call sites
(`validate.rs` ×5, `populate.rs` ×3, `checks.rs` ×1), all of which pass
`&spec_for(...)` and become `Some(&spec_for(...))`. Mechanical, compiler-driven.

### Option C — separate prose entry point

Prose becomes its own pass over the file list in `main.rs`, independent of
format detection, and `validate_file` is untouched.

Zero disturbance to the check dispatch table, which is genuinely attractive. But
it still requires removing the three prose checks from `validate.rs:208-210` or
they double-fire on artifact files — the same edit as B, with the shared helper
called from the binary crate instead of the library crate. That relocation is
the problem: `shirabe-validate` is a library with a stated crates.io ambition
(`frontmatter.rs:36-39` and the `Config` re-export both write to that goal), and
under C a library consumer calling `validate_file` gets structural checks and no
prose checks, with nothing in the API indicating a second pass exists. The three
`populate.rs` call sites are already such consumers.

C also reorders output. Findings are collected per-file today
(`main.rs:603-650`) and rendered once; a second pass appends all prose findings
after all artifact findings, changing the interleave for artifact files. No
current golden expectation contains a prose finding, so nothing breaks today,
but it is a latent parity hazard for exactly the corpus this PRD is about to
start emitting findings on.

## The directory argument: reject, do not walk

**Reject, exit 1 (tool error), with the corrected invocation in the message.**

The decisive fact is that a walk contradicts a committed contract.
`docs/guides/multi-consumer-cli-contract.md` states, above the three-consumer
table: *"`validate` does not decide which files to look at. It validates exactly
the paths it is given and reads no git history to discover changed files. The
caller — the CI workflow, or the installed pre-commit hook — computes the file
set and passes the paths in."* `validate-docs.yml:84` repeats it: *"The CLI
never discovers files itself."* All three documented consumers compute their own
file sets — CI from `git diff --name-only`, the pre-commit hook from `git diff
--cached`, the skills from the doc paths they care about. Adding discovery makes
the contract false for a capability nobody in the table asked for.

A walk also has to invent policy that does not currently exist anywhere in the
crate: `shirabe-validate` depends on `regex` and `saphyr` only, there is no
`walkdir`, and the sole existing directory read (`lifecycle.rs:284-344`) is a
non-recursive scan of six hardcoded paths with an explicit artifact-prefix
filter. A general walk needs an ignore policy (`target/`, `.git/`,
`.claude/worktrees/` — this checkout is itself nested inside another repo's
`.claude/worktrees/`), symlink-loop handling, and a deterministic traversal
order, because byte-stable output is a tested property. `find . -name '*.md'`
returns 483 files here against 147 under `docs/`. An implicit policy deciding
which 147 of 483 count is a surface reporting success over a file set the caller
cannot predict — the same defect class R12a exists to end, relocated.

Rejecting costs one `Path::is_dir()` check, one error string, and one test.

**Strongest counter:** R12a explicitly permits either, and a human typing
`shirabe validate -- docs` gets a hard error they must translate into a
`find | xargs` incantation, which is worse ergonomics than the walk they
obviously wanted. **Answer:** the ergonomic cost is one shell idiom, and it can
be printed verbatim in the error text, so the user is one copy-paste from the
result. The correctness gain — no false green — is identical under both. If a
walk later earns its place it should arrive as an explicit `--recurse` flag with
a written ignore policy and a contract amendment, not as an implicit behavior
change to a positional argument that three consumers already depend on being
literal.

## The 33 schema-skipped files

33 of the 147 files under `docs/` emit `schema field missing, skipping` (0 emit
the `not in supported range` variant). These are artifact-*prefixed* legacy docs
— `DESIGN-plan-review.md` and friends carry `status:`/`problem:`/`decision:`
frontmatter but no `schema:` field — so they resolve to `Some(spec)` and hit the
short-circuit at `validate.rs:185`. Under Option B as specified they are
unchanged: they keep emitting one SCHEMA notice and receive no prose checks.

**They should get prose checks, and the design should fold it in rather than
leave it undiscussed.** They are 22% of the corpus, they are prose, they were
authored by the same skills and are read by the same humans. The SCHEMA notice
says "skipping", which has always operationally meant "skipping the structural
checks that need a schema" — the change makes the word true and the message text
should be updated to say so. The edit is to run `run_prose_checks` *above* the
schema gate inside the `Some` arm, which is one line moved.

Note the requirement boundary honestly: R3 is scoped to *non-prefixed* files, so
it does not compel this. It is R12a's principle — a checking surface must not
report on a file without having checked it — applied to the other half of the
same gate.

**The cost is measured and it is not zero.** Two frozen golden baselines change:
`corpus/real/DESIGN-gha-doc-validation.md` (one banned-word line, 36 em-dash
lines) and `corpus/real/PRD-roadmap-skill.md` (3 em-dash lines) are both
schema-skipped fixtures whose captured stdout is currently one SCHEMA notice.
They would gain prose findings. `corpus/synthetic/DESIGN-missing-frontmatter.md`
is clean on both rule families and would not move.

Re-capturing those baselines from the Rust binary would hollow out the parity
suite, whose stated job (`parity.rs:1-15`) is byte-matching a Go baseline
captured at a pinned commit. The honest handling is to move the two fixtures out
of the frozen parity corpus into a Rust-owned expectation set, or to add an
explicit, documented exemption — and to say in the DESIGN that R3 is a
deliberate post-port divergence, so the parity contract is amended rather than
quietly re-baselined.

**A third golden fixture is a harder problem, and it exists regardless of this
sub-decision.** `crates/shirabe/tests/fixtures/golden/corpus/synthetic/README-unrecognized-format.md`
is a fixture whose entire content documents the defect as intended behavior:

> This file's basename (README-...) matches no known shirabe format prefix,
> so detect_format returns None and the validator skips it silently (no
> output, exit 0).

Its expected stdout is 0 bytes and its expected exit is 0. R3 makes that fixture
wrong. Its *bytes* happen to survive — the content carries no FC10 banned word
and no em dash — but that is luck contingent on the rule set the engine decision
picks, not design. The fixture and its prose must be reclassified as part of
this change, and it should be a named work item rather than an implementation
surprise.

## R5: the minimal change

Four edits, in order:

1. **`crates/shirabe-validate/src/doc.rs`** — add `pub body_start_line: usize`
   to `Doc`, documented as "the 1-indexed absolute line of `body[0]`", plus
   `pub fn abs_line(&self, body_idx: usize) -> usize { self.body_start_line + body_idx }`.
   The method matters more than the field: it gives the conversion a name, so
   the next check author writes `doc.abs_line(idx)` instead of re-deriving
   `idx + 1`.

2. **`crates/shirabe-validate/src/frontmatter.rs`** — set it. Both values are
   already in scope: `1` in the no-frontmatter branch (`:102-109`) and
   `body_start_line` in the main branch (`:132-139`). No new computation.

3. **`crates/shirabe-validate/src/checks.rs`** — replace `line: idx + 1` with
   `line: doc.abs_line(idx)` at `:2599` (FC10) and `:2721` (FC12). Convert
   `:2843` (FC13) too; it is a no-op today because that check only fires when no
   frontmatter parsed, but leaving one site on the old idiom is how the
   convention re-splits.

4. **Ten `Doc { .. }` literals** need the new field: two production
   (`frontmatter.rs:102`, `:132`) and eight test helpers (`validate.rs:304`,
   `populate.rs:2587`, `features.rs:356`, `checks.rs:3343`, `:6067`, `:6139`,
   `:6418`, `:6538`), all `body_start_line: 1`. The five other helpers that
   return `Doc` build through `parse_doc_bytes` and need nothing. Compile errors,
   not silent breakage — the compiler enumerates the list for you.

**Do not touch `mermaid.rs`.** Its `BlockLocation` mixes absolute and
body-relative in one struct (see §4 above) and `checks.rs:1044` depends on the
body-relative reading. Fixing it is correct and separable; bundling it into R5
risks a silent FC08 slicing shift with no test to catch it.

**Blast radius of R5 is zero on the frozen baselines**, which is worth stating
because it looks like it should not be. `format_notice`
(`annotation.rs:39-43`) emits `::notice file={}::{}` and drops `err.line`
entirely — only `format_error` carries `line=`. FC10, FC12 and FC13 are all
notice-level (`is_intrinsic_notice`, `validate.rs:83-98`), so their line numbers
never reach an annotation. `grep -rn "FC10" tests/fixtures/golden/expected/`
returns nothing across all 87 expected files. The corrupted value reaches only
`--format json` and `--format human`, exactly as the PRD states.

## Recommendation

**Option B**, with the three schema-independent checks lifted into a shared
`run_prose_checks(doc, cfg)` called from both arms of the `Option<&FormatSpec>`
match; directories **rejected** as a tool error rather than walked; prose run
above the schema gate so the 33 schema-less docs are covered, with the two
affected golden fixtures and the `README-unrecognized-format.md` fixture handled
as named work items.

Option B wins on one property the other two cannot supply: it makes "structural
checks must not fire on a file with no schema" a type error rather than a
convention. `check_fc01`, `check_fc04` and `check_fc15` take `&FormatSpec`
by signature; on the `None` path there is no spec to pass. Option A leaves the
same invariant to a sentinel value that must be remembered — an eighteenth
registration touchpoint on a surface where six of the existing seventeen already
fail silently and two are already stale in the shipped tree. Option C keeps
`validate_file` pristine but moves check dispatch into the binary crate, so a
library consumer silently loses prose checking.

FC-CONVENTIONS becomes reachable under all three, and under none of them as a
side effect: reachability comes from deleting the `continue` at `main.rs:606`,
which every option requires. What B adds is that the call replacing it is safe
to write — the `None` arm cannot reach a structural check — so FC-CONVENTIONS
arrives without dragging FC01 onto every README in the tree.

**Strongest counter to B:** changing the signature of the crate's central entry
point to `Option<&FormatSpec>` pushes an `if let` onto every caller for a
condition that only one caller (the CLI) can actually produce, and a
`validate_prose(doc, cfg)` sibling function would give the same compile-time
guarantee with no signature churn and no `Option` in the public API.

**Answer:** a sibling function gives the guarantee but not the exhaustiveness.
Two entry points means every future caller must know both exist and must decide
which to call, and nothing fails if they call only the artifact one — which is
how `check_claude_md_conventions` came to be dead code registered in four lists
while never executing. One entry point taking `Option` forces the caller to
state, at the call site, whether it has a schema; the compiler will not let them
not answer. The churn is one production call site and nine test call sites, all
mechanical. That is a low price for turning this decision's central invariant
from documentation into a type.

## Confidence

**High** on the verified behavior, the R5 mechanism, and the reject-not-walk
call. The four reproductions are direct binary output, the 24-line offset is
confirmed against `sed` on the real file, the contract text forbidding discovery
is quoted from a committed guide, and the `Doc` field's absence is read from the
struct definition. **High** on Option B over A and C; the type-enforcement
argument is structural, not stylistic, and the call-site count is exact
(`grep -rn "validate_file("`: one production, nine test).

**Medium** on the recommendation to run prose above the schema gate. R3 does not
compel it, the golden-fixture cost is real, and how to amend the parity contract
without hollowing it out is a judgment the design should make explicitly rather
than inherit from this report. The measurement behind it is solid — 33 files,
two fixtures affected, banned-word and em-dash counts taken directly — but the
call is a scope choice, not a finding.

**Medium** on the eventual em-dash blast radius, which depends on the rule set
the engine decision picks and is not this decision's to fix. The one fact this
decision hands that one: the moment prose checks reach non-prefixed files, the
denominator jumps from 147 files under `docs/` to 483 `.md` files in the tree,
of which 211 are under `skills/` and 23 under `references/`.
