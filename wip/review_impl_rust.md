# Review: the Rust half of `feat/upstream-legality`

Scope: `git diff main -- crates/`, against `docs/designs/DESIGN-upstream-link-legality.md`
and `docs/plans/PLAN-upstream-link-legality.md` Issues 1 and 2.

**Verdict.** The check is correct on every entry shape I could construct except one, the
placement constraint holds and is genuinely enforced by the parity suite (verified by
breaking it), and every acceptance criterion in Issues 1 and 2 that can be measured from
the tree measures true. What follows is one real defect with low field probability, one
user-visible documentation gap, four tests that claim more than they assert, and two
pieces of code that do not earn their existence.

## Findings, most serious first

### 1. The cross-repo file component is split at the last colon; the rest of the crate splits at the first

`crates/shirabe-validate/src/checks.rs:910`

```rust
let file_component = match entry.value.rfind(':') {
    Some(idx) if entry.cross_repo => &entry.value[idx + 1..],
    _ => entry.value.as_str(),
};
```

`entry.cross_repo` is decided by `upstream::is_cross_repo_reference`
(`upstream.rs:134`), which takes the **first** colon and asks whether the text before it
is an `owner/repo` selector. The crate's canonical cross-repo parser,
`coordination::parse_cross_repo_ref` (`coordination.rs:88`), does the same. This is the
only place in the crate that splits such a value at the last colon, so for any value
carrying a second colon the flag and the extraction disagree, and they disagree in the
direction that drops the check.

Verified against the built binary. A BRIEF with

```yaml
upstream: owner/repo:docs/roadmaps/ROADMAP-q3:2026.md
```

produces **no finding**. Parsed the way the rest of the crate parses it, the file
component is `docs/roadmaps/ROADMAP-q3:2026.md`, basename `ROADMAP-q3:2026.md`, which
`detect_format` types as a ROADMAP — a durable document naming a working one, i.e. an
R11 that is silently skipped. The mirror case is worse in kind though even less likely:
`owner/repo:notes.md:PRD-x.md` is typed as a PRD under `rfind` and as nothing under the
canonical parse, so the same divergence can also invent a finding.

Field probability is low — artifact basenames are kebab slugs and colons in filenames are
not a shape this corpus produces. The fix is `find(':')`, which also makes the guard
honest: today the index is computed unconditionally and then discarded when `cross_repo`
is false, which reads as if the flag and the index came from one decision. They come from
two, computed by different functions, from different ends of the string.

The existing test cannot see this. `legality_judges_a_cross_repo_value_on_its_file_component`
(`checks.rs:3931`) uses two single-colon values, where `find` and `rfind` agree by
construction. A third case with a colon in the file component would pin the behaviour
either way.

### 2. `--check`'s own help text still advertises `R6`-`R9`

`crates/shirabe/src/main.rs:216`

The change updated the error message (`main.rs:529` → `R6-R11`) and the doc comment on
`is_known_check_code` (`validate.rs:147` → `` `R6`-`R11` ``), but not the clap doc comment
that becomes `shirabe validate --help`:

> Codes are the per-file checks: `SCHEMA`, `FC01`-`FC13`, `FC-CONVENTIONS`, `R6`-`R9`.

So `--help` tells a user R10 and R11 are not valid codes, while passing one works and
passing R12 produces an error message that says R6-R11 is the valid range. Issue 2's
criterion "Both codes are selectable with `--check`, and the CLI's valid-codes message
names them" is met for the error path only. The new CLI test
`unknown_check_code_message_names_the_legality_range` (`cli.rs:365`) asserts the stderr
copy, so nothing pins the help copy — which is why it drifted. The `FC01`-`FC13` half of
that line is pre-existing drift (codes reach FC16); the `R6`-`R9` half is this change's.
One line.

### 3. `format_id_display_is_upper_case_and_total` asserts almost nothing, and misses the assertion that would earn its place

`crates/shirabe-validate/src/formats.rs:538`

```rust
for spec in formats() {
    let shown = spec.id.display();
    assert!(!shown.is_empty());
    assert_eq!(shown, shown.to_uppercase(), "{shown} must be upper-case");
}
```

`display()` is a match over eight hardcoded upper-case string literals, so this can only
fail if someone types a lowercase literal directly into the match arm. It is a spelling
check on a constant table.

The fact nothing currently pins is the one worth pinning: that `spec.id` is the id of the
format it sits on. `assert_eq!(spec.prefix, format!("{}-", spec.id.display()))` holds for
all eight rows and would catch a copy-pasted `id:` on a newly added `FormatSpec` literal —
exactly the mistake `FormatId` was introduced to make impossible, and the mistake that
would silently mistype every finding message and every parent lookup for that format.
Today a mis-assigned id is caught only indirectly, by
`declared_lifetimes_and_parent_sets_match_the_contract` panicking when its `find` returns
`None`; a duplicate id whose parent sets happen to agree would slip.

### 4. `the_legality_change_alters_no_required_section_list` pins lengths, not lists

`crates/shirabe-validate/src/validate.rs:568`

Not a tautology — it hardcodes eight expected counts and does fail if a section is added
or removed. But it asserts only `required_sections.len()`, and `FormatSpec`'s own doc
comment says element order is contractual because FC15 enforces it. A renamed section, or
a reordering that would surface as an FC15 notice across the corpus, passes this test
unchanged. The test exists to prove this change disturbed no section contract; comparing
the lists costs the same as comparing their lengths and proves the claim it makes.

### 5. `legality_reads_no_file_from_disk` proves a weaker claim than its name

`crates/shirabe-validate/src/checks.rs:3984`

What it proves — the verdict does not depend on the target existing, for both a legal and
an illegal edge — is the property that matters, and the `assert!(!Path::new(missing).exists())`
guard is the right way to prove it. What it does not prove is its name: an implementation
that stat'd the path and ignored the answer passes unchanged. Either narrow the name and
the doc comment to "judged without the target existing", or drop the stronger claim.

Also: the PRD and Issue 2 both name `VISION-` **and** `STRATEGY-` basenames in this
criterion; the test uses `VISION-` for both of its cases. `STRATEGY-` is covered only
incidentally, by the `roadmap/v1 -> docs/strategies/STRATEGY-bet.md` row of
`legality_accepts_every_declared_parent`.

### 6. `the_legality_codes_are_selectable_and_the_set_gained_exactly_two` overstates itself and duplicates an existing test

`crates/shirabe-validate/src/validate.rs:512`

Its doc comment says "The whole set is asserted rather than only the additions, so a third
code added without a decision fails here." It asserts membership for 24 named codes and
non-membership for 5 named codes. Adding `FC20` to `is_known_check_code` passes this test;
the guarantee holds only for the five negatives it happens to enumerate.

Its 22-code positive list is also a verbatim copy of
`is_known_check_code_covers_per_file_codes_only` (`validate.rs:594`) plus the two new
codes, and its `R5` / `FC99` negatives are already in that test's negative list. The
no-modified-tests constraint is why this was written as a second test rather than an edit,
and that was the right call for this PR — but the standing result is two lists to keep in
sync, with the older one now silently under-enumerating the selectable set. Worth a
follow-up that folds them together once the constraint lifts.

### 7. `parents()` does not earn its existence

`crates/shirabe-validate/src/formats.rs:113`

```rust
fn parents(ids: &[FormatId]) -> Vec<FormatId> { ids.to_vec() }
```

This is what `vec![...]` already spells. Contrast the neighbouring `s()`, which earns its
name by converting `&str` to `String`; `parents` performs no conversion and adds no
meaning that `legal_upstream:` does not already carry. Its one measurable effect is nine
extra characters per call site, which pushes `formats.rs:278` (Plan's four-parent row) to
108 columns — the only line in the file over rustfmt's 100, so the next person to run
`cargo fmt` reformats it into a five-line block. `legal_upstream: vec![FormatId::Prd,
FormatId::Brief]` reads the same and wraps on its own.

(No CI job runs `cargo fmt --check`, so this is churn, not a break. The local rustfmt here
is 1.9.0 against the 1.95.0 pin and reports diffs across the whole tree, so I checked the
line length directly rather than trusting the diff: `formats.rs:278` is the only line over
100 columns in the file.)

### 8. `upstream_basename` is the third copy of the same private helper

`crates/shirabe-validate/src/checks.rs:975`

`finalize.rs:1150` and `transition.rs:1458` each carry a private `basename` that is
byte-identical apart from the empty-input → `"/"` case this copy drops. The difference is
harmless (neither `""` nor `"/"` matches an artifact prefix), so this is duplication
rather than divergence — but the doc comment "matching the basename the format detection
elsewhere in the crate is given" is the moment at which one of the existing two could have
been promoted instead.

Related, smaller: `FormatId::display` and `lifecycle::ChainRole::as_str` (`lifecycle.rs:150`)
now hold the same five strings with nothing tying them together, and the two use different
accessor names for the same job. The design consciously declines to unify the enums and
says the overlap "costs a comment naming `FormatId` as the legality authority" —
`formats.rs` does carry that comment for `lifetime` vs. the terminal-status map, but
`lifecycle.rs` says nothing, so a reader arriving at `ChainRole` learns nothing about
`FormatId`.

## What I checked and found correct

**Precedence emits at most one finding per entry.** The R11 arm `continue`s
(`checks.rs:940`) before the R10 arm can run, and R10 is the only other emitter. Confirmed
statically and on the corpus: eight offending documents, eight findings.

**Basename edges behave.** Trailing slashes are trimmed, so `docs/designs/DESIGN-x.md/`
still types as DESIGN (verified against the binary). `docs/roadmaps/` types as nothing. A
bare `docs/roadmaps/ROADMAP-` types as ROADMAP (verified) — which is precisely what
`detect_format` does everywhere else in the validator, and the design's spoofing section
already accepts that assumption. An empty file component (`owner/repo:`) matches no
prefix. The entry value itself is never empty: the shared normalizer trims and drops
blanks before the check sees it.

The one shape worth knowing about: a multi-line scalar `upstream:` arrives as a single
entry holding its whole text (`upstream.rs` semantic 1), so `upstream_basename` types it
on its last line only. R6 already reports such a value as unresolvable, so the miss is
masked rather than reachable.

**The design's placement constraint holds and the parity suite enforces it.** The call
sits at `validate.rs:232` — after the schema gate, after the R9 private-only gate,
immediately after R6 — exactly where the design's "The call site" section puts it. I moved
it above the schema gate (collecting its findings and returning them alongside the schema
notice) and ran `cargo test -p shirabe --test parity`:

```
---- real_prd_roadmap_skill stdout ----
--- expected (Go) ---
::notice file=real/PRD-roadmap-skill.md::schema field missing, skipping
--- actual (Rust) ---
::error file=real/PRD-roadmap-skill.md,line=12::[R11] PRD is durable and names
  "docs/roadmaps/ROADMAP-strategic-pipeline.md", a ROADMAP document, ...
::notice file=real/PRD-roadmap-skill.md::schema field missing, skipping
test result: FAILED. 27 passed; 1 failed; 1 ignored
```

It fails on exactly the fixture the design names, and only that one. The original
placement is restored (`git status` clean, working tree byte-identical to the committed
state) and `cargo test --workspace` is green again: 650 unit tests plus 13 integration
suites, 0 failures.

**The corpus behaves as the requirements predict.** `--check R10,R11` over all 152 files
under `docs/` produces findings on exactly the eight documents PRD R24 names, with the two
lifetime findings landing on the two documents the table marks as lifetime cases and R10
on the other six. No other document produces a legality finding. Every finding's line
number lands on the `upstream:` key (spot-checked against
`BRIEF-single-pr-plan-validation.md`, line 4, and `BRIEF-cascade-outline-ac-completeness.md`,
line 16). `shirabe validate --lifecycle . --mode=draft` exits 0 with the same single L02
orphan notice on `PRD-koto-adoption.md`. This PR's own 37 changed Markdown files validate
clean at `--visibility=public`.

**No existing test was modified.** The entire `crates/` diff removes four lines: one
`use`, one continuation of a `use` list, and two copies of the `R6-R9` code range. Nothing
inside a test module. No golden fixture is touched. `cargo clippy --workspace
--all-targets` reports nothing on any of the new code.

**The declarations are idiomatic.** `FormatId` and `Lifetime` sit beside `ChainRole`,
`RootKind` and `TargetState` in style, and the design's reasoning for an enum over a
`Vec<String>` is sound given the deliberate casing trap in `FormatSpec::name`.
`lifetime_agrees_with_the_finalization_terminal_map` is real coverage, not vacuous: it
exercises the `Deleted → Working` arm on Plan and Roadmap and the `Status(_) → Durable` arm
on Brief, PRD and Design, and only skips the three types the map genuinely does not model.
`no_durable_format_declares_a_working_parent` is the load-bearing one and it does what the
design claims.

## Two consequences worth being deliberate about

**A `--check R10` run under-reports by design.** `check_r10_is_silent_when_the_lifetime_finding_suppressed_it`
(`cli.rs:353`) pins that a brief naming a roadmap produces empty stdout and exit 0 under
`--check R10`. That is the precedence rule working as designed, but any consumer that
selects R10 alone gets a clean pass on a document with an illegal edge. Nothing in the
tree does this today.

**The eight pre-existing illegal edges become error-level for whoever touches them next.**
`validate-docs.yml` passes only the PR's changed files, so this PR stays green and so does
any PR that leaves those eight briefs alone. The first future PR that edits one of them
fails on an edge it did not create. The PRD accepts not repairing them; the accepted cost
is that the repair bill lands on an unrelated author.

## Test-hygiene note

`make_brief` (`cli.rs:312`) builds a fixed path under `std::env::temp_dir()` —
`shirabe-cli-legality-<tag>` — and `remove_dir_all`s it before writing. It copies the
existing `cli.rs:241` helper exactly, so it is consistent with its neighbour, but most
other temp-dir helpers in this workspace (`lifecycle_advisory.rs:33`, `work_summary.rs:53`,
`finalize.rs:1298`, `transition.rs:1507`) mix in `std::process::id()`. Two concurrent
`cargo test` runs on one machine will race here.
