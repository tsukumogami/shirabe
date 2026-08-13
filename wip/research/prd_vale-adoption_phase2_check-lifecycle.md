# Lead: check lifecycle and severity

All paths are relative to
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption`.
Binary used: the pre-built `./target/release/shirabe` (reports `shirabe 0.0.0`).
Measurement scripts written to `/home/dgazineu/.claude/jobs/b0818094/tmp/`
(`measure.py`, `thresholds.py`, `prs.py`, `adopters.py`); every number below is
reproducible from those.

## Findings

### 1. The check-code surface: every touchpoint

Commands run:

```
grep -rn "FC10" . | grep -v '^./wip/' | grep -v '^./target/'
grep -rn "is_notice\|is_known_check_code\|is_intrinsic_notice\|effective_severity" crates/ --include=*.rs
grep -rn "FC16\|check_roadmap_reserved_sections" --include=*.rs --include=*.md --include=*.yml .
grep -n "^pub fn check_\|^fn check_" crates/shirabe-validate/src/checks.rs
```

The check-code vocabulary is registered in **four independent lists**, none of
which is derived from the others, plus three test copies and two prose copies.
There is no central registry, no enum, no table. A code is a `&str` literal
matched in `matches!` arms.

**(a) Adding a new check code.** Touchpoints, in the order the compiler and CI
will find them:

| # | File:line | What changes | Failure if missed |
|---|---|---|---|
| 1 | `crates/shirabe-validate/src/checks.rs` | new `pub fn check_*` returning `Vec<ValidationError>` with `code: "FCnn"` | — |
| 2 | `crates/shirabe-validate/src/checks.rs` (test mod, from line 3400ish) | unit tests for the new fn | CI: none. Convention only |
| 3 | `crates/shirabe-validate/src/validate.rs:9-15` | add to the `use crate::checks::{...}` import list | compile error |
| 4 | `crates/shirabe-validate/src/validate.rs:205-211` (cross-format block) **or** `:224-262` (per-format `match spec.name`) | `errs.extend(check_*(doc, spec))` | silent: the check never runs, exactly the FC-CONVENTIONS dead-code case |
| 5 | `crates/shirabe-validate/src/validate.rs:83-97` `is_intrinsic_notice` | add an arm if the code ships notice-level | silent: the code ships **error-level** by default |
| 6 | `crates/shirabe-validate/src/validate.rs:107-113` `posture_class` | add an arm if the code is draft-tolerable | silent: defaults to `AlwaysEnforced` |
| 7 | `crates/shirabe-validate/src/validate.rs:150-172` `is_known_check_code` | add an arm | `--check FCnn` becomes a tool error, exit 1 |
| 8 | `crates/shirabe-validate/src/validate.rs:327` | the notice-membership list in `is_notice_only_schema_and_fc_advisory_codes` | test failure (only if notice-level) |
| 9 | `crates/shirabe-validate/src/validate.rs:354` | `"FC01", "FC02", ... "FC16", "L01", ...` always-enforced list in `effective_severity_always_enforced_is_posture_independent` | test failure (only if error-level) |
| 10 | `crates/shirabe-validate/src/validate.rs:508-514` | the code list in `is_known_check_code_covers_per_file_codes_only` | test failure |
| 11 | `crates/shirabe/src/main.rs:529` | the user-facing string `"unknown --check code {:?}; valid codes: SCHEMA, FC01-FC16, FC-CONVENTIONS, R6-R9"` | silent: stale help text |
| 12 | `crates/shirabe/src/main.rs:213-219` | the `--check` clap doc comment (currently reads `FC01`-`FC13`) | silent: stale `--help` |
| 13 | `crates/shirabe-validate/src/validate.rs:145-149` | `is_known_check_code` doc comment (currently `FC01`-`FC16`) | silent |
| 14 | `crates/shirabe/tests/fc07_corpus.rs:95-107` | the `line.contains("[FCnn]")` allowlist that asserts every notice on the committed corpus comes from a notice-level code | test failure (only if notice-level) |
| 15 | `docs/guides/multi-consumer-cli-contract.md:87` | "The selectable codes are the per-file checks: `SCHEMA`, `FC01`-`FC13`, `FC-CONVENTIONS`, and `R6`-`R9`." | silent: stale contract |
| 16 | `crates/shirabe/tests/fixtures/golden/expected/**` | byte-for-byte captured stdout/stderr/exit for 29 corpus files | test failure **if the new check fires on any golden fixture** |
| 17 | optional: `references/fixes/<name>.md` | resolution prose the notice text points at | none |

Touchpoints 5, 6, 11, 12, 13, 15 fail **silently**. Two of them are already
wrong in the shipped tree: `main.rs:213-219` and
`multi-consumer-cli-contract.md:87` both say the selectable set is
`FC01`-`FC13`, while `main.rs:529` and `is_known_check_code` both say
`FC01`-`FC16`. FC14, FC15 and FC16 landed and nobody updated the two prose
copies. That is the empirical drift rate for this surface: three codes added,
two of six prose/help touchpoints missed.

Touchpoint 16 is not hypothetical for a prose rule.
`crates/shirabe/tests/fixtures/golden/corpus/real/BRIEF-shirabe-strategy-skill.md`
carries 8 em dashes and its captured baseline
(`expected/real/BRIEF-shirabe-strategy-skill.md.stdout`) is **empty** — a clean
run. Any em-dash rule that fires on it breaks byte-parity against the frozen Go
baseline and forces a re-capture or a fixture edit.

**(b) Retiring an existing code.** There is **no deprecation mechanism**. No
`#[deprecated]`, no "retired codes" set, no alias map, no warning path. Retiring
means deleting the arms at touchpoints 3-10 and the check fn at 1-2. The
consequences:

- `shirabe validate --check FC10 <file>` goes from a working invocation (exit 0,
  verified below) to a **tool error, exit 1**, with the message `unknown --check
  code "FC10"; valid codes: ...`. Verified:

  ```
  $ ./target/release/shirabe validate --check FC10 --format human -- docs/briefs/BRIEF-vale-adoption.md
  docs/briefs/BRIEF-vale-adoption.md:55 notice [FC10] writing-style banned word "tier" -- ...
  0 error(s), 5 notice(s) -- clean
  EXIT=0
  $ ./target/release/shirabe validate --check FC99 --format human -- docs/briefs/BRIEF-vale-adoption.md
  unknown --check code "FC99"; valid codes: SCHEMA, FC01-FC16, FC-CONVENTIONS, R6-R9
  EXIT=1
  ```

  Exit 1 is "tool error", which the contract doc ranks as *more severe than a
  violation*. A consumer that pinned `--check FC10` does not get a quiet
  degradation; it gets a hard failure.

- The JSON envelope's `schema_version` is `shirabe-validate/v1`. The contract
  (`docs/guides/multi-consumer-cli-contract.md:48-50`) says "Additive changes
  keep the major; a breaking change bumps it." It does not say whether removing
  a check code from the emittable set is breaking. **This is undecided and the
  PRD has to decide it.**

- No adopter currently greps for `FC10` in the workspace: `grep -rn "FC10"`
  across `public/koto`, `public/niwa`, `public/tsuku` was not run as part of
  this lead, but no shirabe-side script, workflow or skill selects it either.
  The only `--check` reference anywhere in `skills/`, `scripts/`, `.github/` or
  `koto-templates/` is a generic mention in `skills/prd/references/prd-format.md:171`
  (`--check <CODE>` to evaluate one in isolation). So the *scripted* blast
  radius of retiring FC10 is zero today; the *human* blast radius is anyone who
  has learned to type it.

**(c) Changing a code's severity.** One line, in one place:
`is_intrinsic_notice` at `validate.rs:83-97`. Plus the two test lists at
`validate.rs:327` and `:354` (a code moves from one list to the other), plus
`fc07_corpus.rs:99-107` if it was in the notice allowlist. Four edits, all of
which fail loudly. This is the cheapest operation on the surface by a wide
margin.

### 2. The notice/error model

**Severity is a compile-time property of the code string.** There is no config
file, no per-repo policy, no flag. `ValidateArgs` (`crates/shirabe/src/main.rs:202-300`)
has no `--fail-on-notice`, no `--severity`, no `--error-on`. Resolution happens
in exactly one function:

```rust
// crates/shirabe-validate/src/validate.rs:127
pub fn effective_severity(code: &str, posture: ReviewPosture) -> Severity {
    if is_intrinsic_notice(code) {
        return Severity::Notice;
    }
    match posture_class(code) {
        PostureClass::DraftTolerable if posture == ReviewPosture::Draft => Severity::Notice,
        _ => Severity::Error,
    }
}
```

Three severity behaviours exist, not two:

1. **Intrinsic notice** (`is_intrinsic_notice`): `SCHEMA`, `FC07`-`FC15`,
   `FC-CONVENTIONS`. Notice in every posture. Never affects exit code.
2. **Draft-tolerable** (`posture_class`): `L02`, `L06`, `L07`. Notice under
   `--mode=draft` (the default), error under `--mode=ready`.
3. **Always enforced**: everything else, including `FC16`, which was
   deliberately shipped error-level:

   > `FC16` (roadmap reserved-section shape) is intentionally *absent* here: it
   > ships error-level, so a malformed roadmap reserved section fails the build
   > rather than emitting an advisory notice.
   > — `crates/shirabe-validate/src/validate.rs:78-82`

**Behaviour 2 is the middle option the lead's question implicitly assumes does
not exist.** A frequency rule could ship draft-tolerable: advisory while a PR is
in flight, blocking once the PR is marked ready-for-review. The CI wiring
already computes this (`lifecycle.yml` asserts `ready` only when
`github.event.pull_request.draft == false`). Note it is only wired for the
lifecycle modes today, not the per-file pass — `validate-docs.yml` passes no
`--mode`, so the per-file pass always runs under `Draft`. Making a per-file code
draft-tolerable therefore does nothing until `validate-docs.yml` also threads
`--mode`. That is a small workflow edit, but it is a real prerequisite.

**Exit codes** (`docs/guides/multi-consumer-cli-contract.md:57-79`, verified
against `main.rs`):

| Code | Meaning |
|---|---|
| `0` | Clean — no error-level violations |
| `1` | Tool error (bad invocation, unreadable file, unknown `--check` code) |
| `2` | Violations — at least one error-level result |
| `3` | I/O error |

> **Notice-level results never make a run non-clean.** A run that emits only
> notices exits `0`.
> — `docs/guides/multi-consumer-cli-contract.md:70-72`

Confirmed in the code at three sites, all guarded identically:
`main.rs:645` (`if !is_notice(&ve, posture) { worst = worst.merge(ValidateOutcome::Violations); }`),
`main.rs:1046` (lifecycle render), and `report.rs:95/232` (count roll-ups).
Verified empirically: the full 124-file validator-visible corpus run below emits
133 notices and exits 0 on the notice half.

**Do notices ever make a run non-clean? No.** Not through any flag, config,
posture, or output mode. A notice is invisible to every gate.

**Is there a documented promotion path?** No, other than a code comment.
`grep -rn "promot" docs/guides/*.md README.md AGENTS.md` returns only
release-workflow hits ("promote the draft"). Nothing in `docs/guides/`,
`references/`, or `README.md` describes how a check moves from notice to error,
what evidence justifies it, or who decides.

**One more model gap worth naming.** The advisory layer
(`crates/shirabe-validate/src/advisory.rs:139-143`) composes its remedy notes
from `posture_class(&e.code) == PostureClass::DraftTolerable` only. Intrinsic
notices get **no advisory note and no remedy line**. The corpus run below,
carrying 91 FC10 notices, printed:

```
Advisory: Draft posture: no draft-tolerable findings to flag.
```

So the one surface that exists for telling an author "this is tolerated now but
will block later" is structurally unable to say it about FC10, or about any
future intrinsic-notice prose rule.

### 3. The stated plan for FC10

Two comments state it. The production one:

> **Promotion seam.** FC07-FC15 and FC-CONVENTIONS ship notice-level for
> v1; remove the corresponding arm from this match to promote the check
> from notice to error in a single-line diff. The match expression is
> the one place that drives the intrinsic notice-vs-error split.
>
> `SCHEMA` is the long-standing notice; `FC07` through `FC15` and
> `FC-CONVENTIONS` are notice-level additions pending their respective
> corpus-cleanup PRs.
> — `crates/shirabe-validate/src/validate.rs:67-77`

And the test one the lead asked about, at `validate.rs:316-321`:

> ```rust
>     #[test]
>     fn is_notice_only_schema_and_fc_advisory_codes() {
>         // SCHEMA, FC07-FC13, and FC-CONVENTIONS are the notice-level
>         // codes for v1. Each ships notice-level pending its respective
>         // corpus-cleanup PR; removing any arm from is_notice promotes
>         // the corresponding check to error in a one-line diff.
> ```

A third, in `crates/shirabe/tests/fc07_corpus.rs:79-80`:

> ```rust
>     // AC-4.1: exit 0. FC07 and FC09 are notice-level for v1; promotion
>     // to error is a one-line is_notice change in a later cleanup PR.
> ```

The plan is: **ship notice, clean the corpus, delete one match arm.** The
mechanism is correct and cheap. The precondition has never been met.

**Has any corpus-cleanup work happened? No.**

- `gh issue list --state all --limit 200` returns 141 issues. None is a
  corpus-cleanup issue for any notice-level code. `gh issue list --search
  "cleanup notice"` returns **zero rows**. `gh issue list --search "FC10"`
  returns one row, #154, which is `feat(validate): add fc10 single-pr plan
  validation` — the *misnumbered* issue that became FC14, not the writing-style
  check.
- The only issue matching `corpus` that is actually about corpus content is
  **#113, `docs(corpus): migrate committed roadmap and plan tables to the
  canonical profiles`**, closed 2026-05-31, which predates FC07 and is about
  table structure, not prose.
- `git log --all -S 'fn is_intrinsic_notice'` returns exactly one commit
  (`47349c3`, the posture-mode PR that created the function).
  `git log --all -S '"FC07"' -- crates/shirabe-validate/src/validate.rs` returns
  four commits, all of which *add* codes to the notice list. **No commit in the
  repository's 292-commit history has ever removed a code from the notice set.**
  No check has ever been promoted.

FC07 shipped notice-level on 2026-06-05 (`0b47617`). FC10 shipped
2026-06-something in `8dbcbea` (PR #172). Nine notice-level codes have now
accumulated behind cleanup PRs that were never filed. That is the base rate the
PRD should assume for "we'll promote it later."

Current state of the promise, measured. Command:

```
find docs -name '*.md' | grep -E '/(COMP|DESIGN|PRD|VISION|ROADMAP|PLAN|STRATEGY|BRIEF)-' \
  | xargs ./target/release/shirabe validate --format human --visibility=public --
```

Result over 124 validator-visible docs: **5 errors, 133 notices**. Breakdown:
`FC10` 91, `FC08` 7, `R6` 5 (all errors, all dangling `upstream:` to a
long-deleted `DESIGN-roadmap-plan-standardization.md`), `FC15` 1, `FC09` 1, plus
**33 files emitting `schema field missing, skipping`**.

Two things fall out of that:

- The committed corpus does not pass at error level *today*, for reasons
  unrelated to prose (5 dangling upstreams). Any claim that "the corpus is clean
  except for notices" is false.
- **33 of 124 validator-visible docs (27%) run zero checks.** They are skipped
  at the schema gate before any check fires (21 DESIGN, 12 PRD). Whatever
  severity a prose rule ships at, it will not see a quarter of the corpus. This
  is a scoping fact the PRD needs, independent of the severity question.

### 4. Replace vs extend FC10, costed

**What FC10 is today** (`crates/shirabe-validate/src/checks.rs:2535-2613`): a
7-element `const FC10_BANNED_WORDS` (`tier`, `tiered`, `robust`, `leverage`,
`comprehensive`, `holistic`, `facilitate`), scanned with `line.to_lowercase()`
then `lower[search_from..].find(banned)` in a loop, with hand-rolled
`is_ascii_alphanumeric() || *b == b'_'` boundary tests on the bytes either side.
It runs over every line of `doc.body`, including fenced code, table rows and
HTML comments, and reports `line: idx + 1`.

**`regex` IS already a direct dependency.** Verified:

```
$ cat crates/shirabe-validate/Cargo.toml
[dependencies]
regex = "1"
saphyr = "=0.0.6"
saphyr-parser = "=0.0.6"
```

Also `regex = "1"` in `crates/shirabe/Cargo.toml:18`. So the hand-rolled
matching is not a dependency-avoidance decision; it is just how it was written.
Replacing it with `\b(...)\b` case-insensitive is a strict simplification.

**The line-number bug reproduces, and the delta is the frontmatter length.**
`doc.body` is built by `scan_body` (`frontmatter.rs:291-306`) from the bytes
*after* the closing `---`. `Doc` (`doc.rs:24-39`) stores `path`, `schema`,
`status`, `fields`, `sections`, `body`. **It does not store the body start
line.** `Section` carries absolute lines; body lines do not. So FC10's `idx + 1`
is body-relative. Verified on this chain's own brief: FC10 reports `tier` at
lines 55, 56, 90, 133, 167; `grep -n -i -w tier` finds it at 74, 75, 109, 152,
186. Delta is exactly 19, and the closing `---` of that file's frontmatter is on
line 19. Fixing this means adding a field to the shared `Doc` struct, which is a
slightly wider change than "fix FC10".

**Cost of extending FC10 in place** to become a markup-aware frequency rule:

| Work item | Files | Notes |
|---|---|---|
| Add `body_start_line: usize` to `Doc`; set it in `parse_doc_bytes` | `doc.rs`, `frontmatter.rs` | shared struct; every `Doc` construction site in tests updates |
| Rewrite word matching on `regex` | `checks.rs:2572-2613` | net line reduction |
| Add a prose-scoping helper (skip fenced blocks, table rows, HTML comments, headings) | `checks.rs` | precedent exists but is section-scoped, not doc-scoped: `section_has_prose` and `first_fence_info` at `checks.rs:316-368` already do fence and `\|`-row detection inside one `## ` section |
| Add the counting/threshold logic | `checks.rs` | genuinely new (see §6) |
| Update the 5 FC10 unit tests | `checks.rs:6064-6130` | mechanical |
| Update golden baselines if the rule fires on fixtures | `tests/fixtures/golden/expected/**` | `BRIEF-shirabe-strategy-skill.md` has 8 em dashes and an empty expected stdout |
| Severity registration | none | FC10 is already in all four lists |

**Cost of replacing FC10 with a new code**: everything above, *plus* all 17
touchpoints from §1(a) for the new code, *plus* the deletion of FC10 from
touchpoints 3-10, *plus* a decision on whether `--check FC10` returning exit 1
is a v1-breaking change to the JSON contract, *plus* rewriting the 11 prose
references to FC10 in `docs/` (5 in `BRIEF-vale-adoption.md`, 3 in
`BRIEF-single-pr-plan-validation.md`, 5 in `PRD-single-pr-plan-validation.md`,
7 in `DESIGN-shirabe-pattern-v1-ergonomics.md`, 2 in
`skills/plan/references/plan-format.md`).

**Extending is smaller, and not marginally.** The delta is roughly 17 touchpoint
edits plus a contract decision plus a docs sweep. There is one caveat that cuts
the other way: FC10's *name* is "writing-style banned word", and its notice text
hardcodes `see skills/writing-style/SKILL.md for canonical alternatives`. If the
new mechanism checks things that are not banned words, keeping the FC10 code
means the code's documented meaning widens, and `--check FC10` becomes a coarser
selector than it was. That is a naming cost, not an engineering one, and the
existing FC-family precedent already tolerates it (FC14 has five lettered
sub-checks under one code; FC08 has three).

Note also that `PRD-single-pr-plan-validation.md:373-375` already recorded and
**rejected** a rename of FC10, on the grounds that it "would force a churning
rename of every reference to writing-style FC10 across the docs". That reasoning
applies unchanged to retiring it.

### 5. Severity for a frequency rule, empirically bounded

Method (`/home/dgazineu/.claude/jobs/b0818094/tmp/measure.py`): prose scope is
the file with YAML frontmatter, fenced blocks (``` and ~~~), lines starting `|`,
and lines starting `#` removed. Paragraphs are blank-line-separated blocks of
what remains. My numbers differ slightly from the BRIEF's (2,785 vs 3,114 em
dashes; 6,194 vs 5,776 paragraphs) because I exclude headings from the
numerator, where the BRIEF's method counted the 126 heading em dashes, and
because paragraph splitting differs on list items. The distribution shape is
identical and the conclusions do not turn on the delta.

**Corpus, shirabe, 124 validator-visible `docs/` files:** 2,785 em dashes,
381,923 prose words, **7.29 per thousand**. 92 of 124 files (74%) exceed 3 per
thousand. 95 of 124 (77%) contain at least one. 628 of 6,194 paragraphs (10.1%)
contain 2 or more.

**Error on day one — file-level rate rule** (`thresholds.py`):

| Threshold | Files failing | Em dashes to remove to pass |
|---|---|---|
| >1/1000 | 94 (76%) | ~2,487 |
| >3/1000 | 92 (74%) | ~1,897 |
| >5/1000 | 77 (62%) | ~1,352 |
| >8/1000 | 63 (51%) | ~704 |
| >10/1000 | 49 (40%) | ~384 |
| >12/1000 | 24 (19%) | ~192 |
| >15/1000 | 11 (9%) | ~77 |
| >20/1000 | 1 (1%) | ~17 |
| >25/1000 | 0 | 0 |

**Error on day one — paragraph-level rule:**

| Threshold | Paragraphs failing | Files with ≥1 failing paragraph | Em dashes to remove |
|---|---|---|---|
| ≥2 per paragraph | 628 (10.1%) | 91 of 124 (73%) | ~1,212 |
| ≥3 | 231 (3.7%) | 77 (62%) | ~584 |
| ≥4 | 126 (2.0%) | 57 (46%) | ~353 |
| ≥5 | 76 (1.2%) | 37 (30%) | ~227 |
| ≥6 | 54 (0.9%) | 31 (25%) | ~151 |

The paragraph framing looks gentler as a percentage of paragraphs but is not
gentler as a percentage of *files*, which is what CI gates on: at the ≥2
threshold, 91 of 124 files carry at least one failing paragraph. A gate is
per-file.

**PR-level, measured rather than inferred** (`prs.py`). CI validates only the
changed-file set (`validate-docs.yml:88-90`, `git diff --name-only
--diff-filter=ACMR base...head`), so the right question is what fraction of
*changes* touch a failing file. Over the last 174 commits on this branch, 77
touched at least one validator-visible doc. Of those 77:

- **52 (68%)** touched a file that was, at that commit, above 3 em dashes per
  thousand words.
- **50 (65%)** touched a file containing a paragraph with 2 or more em dashes.

Commits are a lower bound on PRs, since a PR bundles several commits and fails
if any changed file fails. So the realistic PR-level day-one failure rate for
either rule at these thresholds is **at least two thirds, and closer to
three quarters** on the file-level evidence.

**For comparison, the presence rule.** FC10 fires 91 notices but they are
concentrated in **7 of 124 files**: `DESIGN-shirabe-pattern-v1-ergonomics.md`
(60), `PRD-shirabe-pattern-v1-ergonomics.md` (22), `BRIEF-vale-adoption.md` (5),
and four files with one each. Promoting FC10 to error today would fail 7 files.
A frequency rule at any defensible threshold fails 60 to 90. **A frequency rule
is an order of magnitude more corpus-invasive than the presence rule that has
been sitting unpromoted for two months.**

**Adopters get it on merge, with no version gate.** All three adopter repos
pin the reusable workflow at `@main`:

```
public/koto/.github/workflows/validate-docs.yml:19:  uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main
public/niwa/.github/workflows/validate-docs.yml:19:  uses: .../validate-docs.yml@main
public/tsuku/.github/workflows/validate-docs.yml:20: uses: .../validate-docs.yml@main
```

and the workflow builds the binary from `job.workflow_sha`, i.e. the called ref
(`validate-docs.yml:52-76`). A severity change merged to shirabe's `main` reaches
all three repos on their next PR. There is no opt-in window and no adopter-side
pin to hide behind. Their day-one exposure (`adopters.py`):

| Repo | Validator-visible docs | Em/1000 | Files >3/1000 | Files with ≥1 em | Paragraphs ≥2 em |
|---|---|---|---|---|---|
| koto | 58 | 5.07 | 27 (47%) | 28 | 170 / 3,847 |
| niwa | 104 | 5.01 | 51 (49%) | 62 | 348 / 5,611 |
| tsuku | 159 | 2.01 | 32 (20%) | 49 | 164 / 12,741 |

Roughly half of koto's and niwa's docs fail a 3-per-thousand gate on the day it
merges, and none of those repos has agreed to a cleanup.

**Warning/notice on day one — what the author actually sees.** There is no
"warning" level; the choice is notice or error. At notice level, the author sees
one `::notice file=...,line=...` annotation per finding in the GitHub Files
Changed view, and the run exits 0. On shirabe's corpus that is roughly 2,785
annotations if every em dash is reported, or 92 if only the file-level verdict
is reported. The advisory layer says nothing (see §2). The pre-commit hook
(`shirabe install-hooks`) does not block, because it gates on exit code. So
notice-level means: **visible in CI annotations, invisible everywhere else, and
with no built-in escalation story.** That is exactly FC10's situation, and FC10's
situation has produced no cleanup in two months.

**Error-after-cleanup — what cleanup costs.** At 3 per thousand: **92 files
touched, ~1,897 em dashes rewritten**. Every one is a judgment call about
sentence structure, not a mechanical substitution — an em dash becomes a comma,
a colon, a period, or a restructured clause depending on context, and the wrong
choice degrades the prose. At a paragraph threshold of ≥3: 77 files, ~584 edits.
At a file rate of >10 per thousand: 49 files, ~384 edits. The knee of the curve
is between 10 and 15 per thousand, where the file count drops from 49 to 11 and
the edit count from 384 to 77.

**What the evidence supports for a first release.**

Ship it **notice-level, and only if the PRD simultaneously requires the
promotion precondition to be a named, filed, tracked artifact** — not a code
comment. Error on day one fails two thirds of doc-touching PRs in shirabe and
about half in two adopter repos that never agreed to it, and does so through a
`@main` pin with no rollback window shorter than a revert. That is not a
defensible first release.

But "notice" alone is the option with a two-month track record of producing
nothing. So the recommendation has a second half: **the promotion condition must
be stated as a measurable threshold in the PRD, and the cleanup must be a filed
issue that exists before the check merges.** Concretely, something of the shape
"promote when fewer than N validator-visible files in `docs/` exceed the
threshold", with N measured, plus a cleanup issue referenced from the check's
own notice text.

If the PRD wants a first release with teeth, the honest middle is
**draft-tolerable** (`posture_class`), which already exists: notice while the PR
is a draft, error once it is marked ready-for-review. That gives an author the
whole drafting window and still blocks. Its cost is one arm in `posture_class`
plus threading `--mode` through `validate-docs.yml`, which does not pass it
today. It is the only option that is both enforcing and survivable, and it is
the one the current architecture supports and nobody has used for a per-file
check.

Threshold, if a number is wanted for a first release: a **file-level rate above
10 per thousand prose words** fails 49 of 124 shirabe files and needs ~384 edits;
above 15 fails 11 files and needs ~77. Fifteen is the only threshold that is
both cleanable in a single afternoon-sized PR and non-vacuous.

### 6. Is there any frequency-shaped check today? No.

Every check function in `crates/shirabe-validate/src/checks.rs` (enumerated with
`grep -n "^pub fn check_\|^fn check_"`) is presence/absence, enum-membership,
structural, or cross-reference:

- `check_schema`, `check_fc01`-`check_fc04`, `check_fc15`: field presence,
  status-enum membership, section presence, section order.
- `check_fc05`/`check_fc06`: issues-table row shape and column content.
- `check_fc07`/`check_fc08`: table-vs-mermaid bijection and legend-vs-classdef
  set reconciliation. Set comparison, not counting.
- `check_fc09`: live `gh` state reconciliation.
- `check_writing_style` (FC10): substring presence.
- `check_plan_section_structure`, `check_plan_design_field_consistency`,
  `check_eval_fixture_frontmatter`, `check_claude_md_conventions`,
  `check_roadmap_reserved_sections`, `check_upstream_resolves`,
  `check_vision_public`, `check_strategy_public`, `check_private_only`: all
  presence or structure.
- Lifecycle `L01`-`L07` (`lifecycle.rs`): graph traversal and state assertions.

The two things that come closest, and why neither counts:

1. **FC14 sub-check D** (`checks.rs:3003-3033`) compares the frontmatter
   `issue_count` against an observed row count:
   `"[FC14] frontmatter 'issue_count: {}' does not match observed count {} in {}"`.
   That is *parity between a declared number and an observed one* — a
   consistency check whose expected value comes from the document. It has no
   threshold and no rate.
2. **`detect_slug_prefix`** (`checks.rs:3230-3300`) genuinely computes a
   frequency: "the most-frequent word above the 50% threshold wins". But it is a
   CLI helper for the `shirabe slug-prefix-detect` subcommand, returns a
   `SlugPrefixCheck` enum rather than `Vec<ValidationError>`, is not registered
   in `validate_file`'s dispatch, and emits no check code.

So **no registered check counts occurrences against a threshold, and none
computes a rate.** A frequency rule is a new check *shape*, not just a new check.
Everything shape-specific has to be invented: what the denominator is (words?
sentences? paragraphs? the document?), what the unit of report is (the document,
the paragraph, or each individual occurrence — the difference between 92
annotations and 2,785), what line number a document-level finding carries (the
`ValidationError` struct requires a `line: usize`; a whole-document rate has no
natural one, and `line: 0` renders as `file:0` in human mode), and where the
threshold is configured (nothing in `Config` at `doc.rs` carries a numeric
knob today — it holds `custom_statuses`, `visibility`, `allow_untracked_acs`).

## Implications for requirements

State these mechanism-neutrally; none of them names a tool.

1. **The PRD must decide the identity question explicitly, and it should decide
   "extend".** Extending the existing writing-style check code is materially
   cheaper than retiring it and minting a new one: no new registration across
   four independent lists plus three test lists plus two prose lists, no
   `--check` exit-1 regression, no contract-version decision, no 22-reference
   docs sweep. The counter-argument is naming, and the repo has already rejected
   an FC-code rename once for the same churn reason.

2. **If any check code is ever retired, the PRD must require a deprecation
   path, because none exists.** Today retirement turns a working `--check <code>`
   invocation into a tool error (exit 1, ranked more severe than a violation).
   A requirement here reads: retiring a check code SHALL NOT cause a previously
   valid `--check` selection to fail; the code SHALL remain selectable as a
   no-op for at least one release.

3. **Whether the emittable check-code set is part of the `shirabe-validate/v1`
   contract must be decided.** The contract doc versions the JSON envelope shape
   but is silent on the code vocabulary. Removing a code is either additive
   (keeps v1) or breaking (bumps to v2), and nothing currently says which.

4. **A new check code SHALL be registered in every list that gates it, and the
   PRD SHOULD require the two prose copies be brought back into agreement.**
   Six of the seventeen touchpoints fail silently, and two are already stale in
   the shipped tree (`main.rs:213-219` and
   `docs/guides/multi-consumer-cli-contract.md:87` both say `FC01`-`FC13` when
   the truth is `FC01`-`FC16`). This is cheap to fix inside the same PR and it
   is the exact drift the check is nominally about.

5. **Severity SHALL be notice-level or draft-tolerable on first release, never
   always-error.** Grounded: error-level fails 74% of shirabe's validator-visible
   docs, at least 68% of doc-touching commits, and roughly half of koto's and
   niwa's corpora — reaching all three adopters immediately, because they pin
   `@main` and the workflow builds from the called ref.

6. **A notice-level release SHALL ship with its promotion precondition as a
   filed, tracked artifact, not a code comment.** The evidence for this
   requirement is that nine codes have accumulated behind "pending its
   respective corpus-cleanup PR" and not one such PR or issue exists; no code
   has ever been removed from the notice set in 292 commits. The requirement
   should name a measurable promotion condition (a file count or rate below a
   stated number) and require the cleanup issue to exist before the check
   merges.

7. **The PRD SHOULD state that a frequency rule is a new check shape and name
   the shape decisions.** No existing check counts against a threshold or
   computes a rate. Requiring answers for: the denominator, the reporting unit
   (document vs paragraph vs occurrence — a 30x difference in annotation
   volume), the line number a document-level finding carries, and where the
   threshold lives, since `Config` has no numeric knob today.

8. **Prose scoping is a stated requirement, not an implementation detail.** The
   existing check reads raw body lines including fenced code, table rows and
   HTML comments, and reports body-relative line numbers that are off by the
   frontmatter length (verified: delta 19 on a file whose frontmatter closes at
   line 19). Any measurement the check reports has to be scoped to prose or the
   number is not the number the author sees. Fixing the line number requires
   `Doc` to carry the body start line, which it does not.

9. **The PRD SHOULD acknowledge that 27% of the validator-visible corpus is
   unreachable.** 33 of 124 files (21 DESIGN, 12 PRD) emit `schema field
   missing, skipping` and run zero checks. Whatever the rule and whatever the
   severity, it does not see them. If the feature's success measure is corpus
   coverage, that gap belongs in the requirements or in the explicit
   out-of-scope list.

10. **If enforcement is wanted on a first release, the draft-tolerable path is
    the mechanism to require.** It already exists (`posture_class`), it already
    has CI wiring precedent in `lifecycle.yml`, and its only prerequisite is
    that `validate-docs.yml` thread `--mode`, which it does not today.

11. **The advisory surface cannot currently explain an intrinsic notice.** If
    the PRD requires that an author be told what a finding means and when it
    will start blocking, that is a change to `advisory.rs`, which today composes
    notes only for draft-tolerable codes and prints "no draft-tolerable findings
    to flag" on a run carrying 91 prose notices.

## Open questions

1. **Is removing a check code from the emittable set a breaking change to
   `shirabe-validate/v1`?** The contract doc versions the envelope shape and is
   silent on the code vocabulary. A human owns this call.

2. **Do the three adopter repos accept a notice flood, and would they accept a
   later promotion?** They pin `@main`, so they get whatever merges, and nobody
   has asked them. At notice level this is an annotation-volume question; at
   error level it is a "half your docs stop merging" question. koto and niwa are
   at ~5 em dashes per thousand with roughly half their files above 3.

3. **Reporting unit: per occurrence, per paragraph, or per document?** The
   difference on shirabe's corpus is 2,785 annotations versus 628 versus 92.
   This is a product decision about what an author should see, and it also
   settles the `line:` field question.

4. **What is the actual threshold, and who owns it?** I recommend 15 per
   thousand for a cleanable first release and 10 if the appetite is larger, but
   the number encodes a house style opinion nobody has stated. Related: should
   it be per-repo configurable? Nothing in `Config` supports a numeric knob
   today, and adding one is a contract change.

5. **Should the promotion precondition be corpus-clean or corpus-below-N?** The
   existing plan says "clean the corpus", which for 1,897 judgment-call edits
   has never happened for any code. A threshold-based precondition is
   achievable; a cleanliness one demonstrably is not.

6. **Do the 5 pre-existing R6 errors get fixed first?** The committed corpus
   does not pass at error level today for reasons unrelated to prose (five
   dangling `upstream:` links to a deleted design). Any "the corpus is clean"
   framing in the PRD is currently false, and issue #268 is open on an adjacent
   symptom.

## Summary

Changing a check's severity is a genuinely one-line edit at
`crates/shirabe-validate/src/validate.rs:83-97`, but adding or retiring a code
touches seventeen places across four unrelated registration lists, three test
lists, two prose copies and a byte-for-byte golden baseline — six of which fail
silently, and two of which are already stale in the shipped tree — and retiring
one has no deprecation path at all, so `--check FC10` would go from working to a
hard exit-1 tool error; extending the existing check is therefore clearly the
cheaper of the two. Notices never affect any exit code, no flag or config can
make them, no check has ever been promoted out of the notice set in 292 commits,
and the "clean the corpus then flip the arm" plan quoted at `validate.rs:316-321`
has produced zero cleanup issues or PRs across nine notice-level codes in two
months. Error-level on day one would fail 92 of shirabe's 124 validator-visible
docs, at least 68% of doc-touching commits, and about half of koto's and niwa's
corpora, reaching all three adopters immediately because they pin the reusable
workflow at `@main` — so a frequency rule should ship notice-level or
draft-tolerable, with a filed cleanup issue and a numeric promotion condition as
hard requirements rather than a code comment, and the PRD should say plainly
that no check today counts occurrences or computes a rate, making this a new
check shape rather than a new check.
