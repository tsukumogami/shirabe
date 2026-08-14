# Decision 2 — how the two legality checks are structured, dispatched, and coded

## Recommendation

**Option B — one check function, `check_upstream_legality(doc, spec) -> Vec<ValidationError>`,
emitting both codes**, called from the shared cross-format block in
`crates/shirabe-validate/src/validate.rs` immediately after
`check_upstream_resolves(doc)` (currently line 217), before the
`match spec.name.as_str()` format dispatch.

Codes: **`R10` = direction**, **`R11` = lifetime**.

---

## 1. The precedence rule (R7) decides this

R7: an entry violating both properties reports only the lifetime finding.

The reason this is not a rare tiebreak is R4 plus the R5 table. A lifetime
violation is only possible when the naming document is Durable and the target is
Working (a Working document naming a Working one — PLAN naming ROADMAP — is legal
because they are retired together). But R4 forbids any Durable type from
declaring a Working type among its legal parents, and R5's table honours that: no
Durable row lists ROADMAP or PLAN. So:

> **Every lifetime violation is also a direction violation.** The overlap is not
> an edge case; it is the whole lifetime finding.

The converse does not hold — BRIEF naming DESIGN is a direction violation and no
lifetime violation — so the two codes are still distinct findings with distinct
populations. What follows is that R7's suppression fires on 100% of lifetime
findings, which is exactly the case each option has to get right.

### Option A (two functions) — the precedence rule becomes a cross-function invariant

If direction and lifetime are separate functions, the direction function cannot
decide whether to emit without knowing the lifetime verdict for *that entry*. It
has two ways to find out, both bad:

1. **Recompute the lifetime predicate inside the direction check.** Then the
   direction check contains the entire lifetime check, and Option A is Option B
   with the shared predicate written twice and an invariant ("these two copies
   agree") that nothing enforces.
2. **Post-filter in `validate_file`** — drop an `R10` finding when an `R11`
   finding exists for the same entry. This is *not expressible*.
   `ValidationError` is `{ file: String, line: usize, code: String, message: String }`
   (`crates/shirabe-validate/src/doc.rs:100-107`) and carries no entry index; every
   per-entry `upstream:` finding sits at the same `field.line` (see §3). Two
   findings from the same document are therefore indistinguishable by
   `(file, line)`, so a post-filter would have to string-match the offending value
   out of `message`. That is the definition of getting it wrong.

### Option B — the precedence rule is one `else if` inside one loop

```rust
for entry in field_entries(field) {
    let Some(target) = detect_format(basename(&entry.value)) else { continue }; // R9: unchecked
    if target.lifetime == Working && spec.lifetime == Durable {
        errs.push(finding("R10-or-R11 lifetime", ...));   // R11
    } else if !spec.legal_parents.contains(&target.name) {
        errs.push(finding(..., ...));                      // R10
    }
}
```

One entry, one classification, at most one finding, precedence expressed as
branch order. There is no way to emit both for one entry and no invariant to
maintain across function boundaries. The R4 test the PRD already requires ("no
Durable type declares a Working type among its legal parents") is what guarantees
the `else if` never hides a *legal* edge behind the lifetime branch.

### Option C (fold into `check_upstream_resolves`) — couples a pure check to a subprocess check and endangers frozen bytes

`check_upstream_resolves` (`checks.rs:791-864`) is not a shape that legality can
ride inside without surgery:

- It hardcodes `code: "R6"` in a `finding` closure captured over `field.line`;
  three codes would need three closures or a code parameter.
- It `continue`s on `entry.cross_repo` (line 834) and on
  `!Path::new(path).exists()` (line 839). Legality must judge **both** of those:
  PRD R9 says a cross-repo value's file component is still resolved for its type,
  and legality is basename-only so a dangling path is still judged (R24's table
  predicts five briefs carrying *both* an R6 error and a new legality finding).
  Folding in means restructuring those two `continue`s — inside the one function
  whose output bytes two golden fixtures pin verbatim
  (`expected/real/PLAN-roadmap-plan-standardization.md.stdout:1` and
  `expected/synthetic/PLAN-r6-broken-upstream.md.stdout:1`).
- R6 shells out to `git ls-files` per entry; legality touches no disk at all
  (that is what makes the PRD's "no VISION or STRATEGY is drawn in" AC true by
  construction). Merging makes the pure check untestable without a git worktree.

Option C also loses the property that `--check R6` and `--check R10` name
functions you can read independently.

### Option D (separate pass, e.g. a `--lifecycle`-style mode) — contradicts three ACs

- `--check` filtering happens in the per-file loop only (`main.rs:642`), and
  `is_known_check_code`'s doc comment (`validate.rs:147-149`) states outright that
  lifecycle codes are not selectable because they are not produced by the per-file
  pass. A code emitted by a separate mode cannot satisfy "Both new check codes are
  selectable with `shirabe validate --check <CODE>`".
- R6 of the PRD says `shirabe validate` reports the finding; R24's table is a
  per-file finding table.
- Its only advantage is parity safety, which §2 shows A/B/C already have.

**Verdict: B.** A is B with duplication plus an unenforceable invariant; C risks
frozen bytes and couples pure logic to I/O; D trades ACs for a safety it does not
uniquely provide.

---

## 2. The hard constraint: byte parity with the golden corpus — verified

`crates/shirabe/tests/parity.rs` runs the built binary with
`tests/fixtures/golden/corpus` as CWD and byte-compares stdout/stderr/exit against
`tests/fixtures/golden/expected/<rel>.{stdout,stderr,exit}`.

### Every golden fixture carrying an `upstream:` field

Enumerated by `grep -rn "^upstream:" corpus/` — there are exactly four (the other
21 fixtures have no `upstream:` field at all and are unaffected under every
option).

| Fixture | `upstream:` value | Naming type | Target type | Schema gate | Legality verdict |
|---|---|---|---|---|---|
| `real/DESIGN-gha-doc-validation.md` (line 3) | `docs/prds/PRD-gha-doc-validation.md` | DESIGN | PRD | **no `schema:` field** → SCHEMA notice, early return | legal anyway (PRD ∈ DESIGN's parents) |
| `real/PLAN-roadmap-plan-standardization.md` (line 5) | `docs/designs/DESIGN-roadmap-plan-standardization.md` | PLAN | DESIGN | passes (`schema: plan/v1`) | legal (DESIGN ∈ PLAN's parents); already emits `[R6] ... does not exist on disk` |
| `real/PRD-roadmap-skill.md` (line 12) | `docs/roadmaps/ROADMAP-strategic-pipeline.md` | PRD | ROADMAP | **no `schema:` field** → SCHEMA notice, early return | **illegal on both properties** — lifetime wins under R7 |
| `synthetic/PLAN-r6-broken-upstream.md` (line 7) | `synthetic/this-upstream-does-not-exist.md` | PLAN | *(basename matches no artifact prefix)* | passes (`schema: plan/v1`) | unchecked (PRD R9); `detect_format` returns `None` for that basename |

Only one fixture is at risk: **`real/PRD-roadmap-skill.md`**. Its frozen expected
stdout is a single line:

```
::notice file=real/PRD-roadmap-skill.md::schema field missing, skipping
```

with exit 0. Verified directly by running the built binary from the corpus
directory:

```
$ cd crates/shirabe/tests/fixtures/golden/corpus
$ shirabe validate real/PRD-roadmap-skill.md
::notice file=real/PRD-roadmap-skill.md::schema field missing, skipping
exit=0
```

The mechanism is `validate_file`'s first statement (`validate.rs:184-187`):

```rust
if let Some(schema_err) = check_schema(doc, spec) {
    return vec![schema_err];
}
```

and `check_schema` (`checks.rs:54-72`) fires whenever `doc.schema != spec.schema_version`,
including the empty-schema case, which produces the `schema field missing, skipping`
wording. The independent proof that the gate is what protects this fixture: the
file's `upstream:` target `docs/roadmaps/ROADMAP-strategic-pipeline.md` does **not**
exist relative to the corpus directory (the roadmap lives at
`real/ROADMAP-strategic-pipeline.md`), so `check_upstream_resolves` would already
be emitting an `[R6] ... does not exist on disk` error today if anything ran past
the gate. It does not. The gate is load-bearing and proven.

### Which placements preserve byte parity, and which break it

**Preserve parity:**

- Anywhere inside `validate_file` **after** the schema gate — which includes the
  recommended slot right after `check_upstream_resolves` (line 217), anywhere else
  in the cross-format block, and inside any format arm. Options A, B and C are all
  in this class. `PRD-roadmap-skill.md` never reaches them; the other three
  fixtures produce no legality finding.
- A separate mode outside the per-file pass (Option D), trivially.

**Break parity:**

- Any call **before** the schema gate in `validate_file` (an "it doesn't need the
  schema, so it can run first" argument is exactly the trap here).
- Any call in the per-file driver loop in `main.rs` (around line 636) *outside*
  `validate_file`, next to the `validate_file(&doc, &spec, &cfg)` call. This
  placement is superficially attractive — it needs only `doc` and `spec`, both in
  scope — and it is the concrete way Option A or D could go wrong. It bypasses the
  gate and would add two findings to `PRD-roadmap-skill.md` (an R11 lifetime error
  under R7's precedence), flipping its stdout and its exit code from 0 to 2 and
  failing `real_prd_roadmap_skill`.
- Anything that makes the R9 private-only gate (`validate.rs:192-195`, returns
  early) run after legality. No golden fixture is a COMP doc, so this is
  theoretical for parity but is the same class of mistake.

### Other test corpora — checked, all clear

- `crates/shirabe/tests/fc07_corpus.rs` runs the real binary over `docs/plans/**`
  and `docs/roadmaps/**` and asserts **exit 0**. `docs/roadmaps/` does not exist
  and the single `docs/plans/PLAN-work-on-friction-fixes.md` carries **no**
  `upstream:` field, so no new error-level finding can reach it.
- `crates/shirabe/tests/absorption_parity.rs` and its
  `fixtures/absorption-golden/` corpus: `grep -rl upstream` finds nothing.
- `crates/shirabe/tests/lifecycle_posture.rs` builds briefs/PRDs/designs/plans
  *with* `upstream:` fields, but every invocation is `validate --lifecycle`
  (lines 125-131, 382-396), and `validate_file` is never called on that path
  (`grep -rn "validate_file("` finds call sites only at `main.rs:636`,
  `populate.rs:{1822,1918,2486}`, and one unit test).
- `crates/shirabe/src/populate.rs`'s three `validate_file` tests assert clean
  validation on generated ROADMAPs; `grep -n upstream populate.rs` shows the
  generator never writes an `upstream:` field.
- `crates/shirabe/tests/cli.rs`, `merge_gate.rs`, `transition*.rs`,
  `coordination_body.rs`, `work_summary.rs`, `lifecycle_advisory.rs`: no
  `upstream:` fixtures.
- `validate.rs`'s own unit tests (`validate_file_well_formed_brief_passes` etc.)
  build docs with no `upstream:` field, so the new check returns an empty vec and
  the `errs.len() == 0` assertions hold unmodified.

R21 ("no existing test modified") therefore holds for the recommended placement.

---

## 3. Reusing R10's per-entry independence and the `classify` front door

### `field_entries`, not a re-derived match

`check_upstream_resolves` re-derives its own `items` from `field.entries`
(`checks.rs:804-818`) rather than calling `crate::upstream::field_entries`, and
that divergence is *justified for R6 and not for legality*. R6 needs the cases
`field_entries` deliberately collapses:

- an empty scalar / empty sequence / `Other` shape is a distinct R6 finding
  (`checks.rs:805-817`);
- a `Blank` sequence item is an R6 finding naming the 1-based entry index
  (`checks.rs:825-827`) — which needs the raw index, and `field_entries` drops the
  entry entirely.

The legality check needs none of that. PRD R10 says a placeholder entry is skipped
and a blank entry "is already the resolution check's finding and is not re-reported
here", and its findings name the offending *value*, not an index. That is exactly
`field_entries`' contract (`upstream.rs:82-99`): drop blanks and placeholders via
`normalize`/`classify`, keep cross-repo entries **marked but present**
(semantic 2), preserve written order, `Other` yields no entries.

So: **the new check calls `crate::upstream::field_entries(field)`.** This keeps
`classify` the single answer to "what did the author write here" across all
readers, adds no fourth normalizer, and means the only reader that re-derives is
the one with documented extra reporting duties.

Note the check still needs the field itself (for `field.line`), so it looks up
`doc.fields.get("upstream")` and returns early on `None` — the same two lines R6
opens with (`checks.rs:792-795`) — then hands the `&FieldValue` to `field_entries`.

### Per-entry independence

One `for` loop over `field_entries`, one verdict per entry, no cross-entry state.
A three-entry `upstream:` with one illegal entry names that entry and no other,
matching R6's per-entry reporting.

### The basename→type front door already exists

`crate::formats::detect_format(basename)` (`formats.rs:248-260`) is a pure,
longest-prefix basename matcher that returns `Option<FormatSpec>` and returns
`None` for an unrecognized prefix (`detect_format("README.md").is_none()`, tested
at `formats.rs:283-286`). That is precisely PRD R9's "unchecked rather than
failed", and precisely PRD R8's "nothing causes `docs/visions/` to be indexed" —
it reads no file. Reuse it for the target type; do not write a second prefix table.

Two mechanical notes:

- **Basename helper.** There are already three private `basename` copies
  (`main.rs:1447`, `finalize.rs:1150`, `transition.rs:1458`) with identical
  bodies. Reuse one of the `shirabe-validate` copies (promote `finalize.rs`'s to a
  small shared helper) rather than adding a fourth.
- **Cross-repo values.** Plain `basename` already handles the common cross-repo
  shape: `owner/repo:docs/roadmaps/ROADMAP-x.md` → `ROADMAP-x.md`, because the
  colon precedes the last `/`. The degenerate `owner/repo:ROADMAP-x.md` (no path
  after the colon) basenames to `repo:ROADMAP-x.md` and falls through as unchecked.
  If D1 wants that caught, split at the cross-repo colon first — the discriminator
  is already public as `crate::upstream::is_cross_repo_reference`
  (`upstream.rs:133-141`). Either way this is within PRD R9's stated tolerance
  ("one naming a file whose prefix is unrecognizable is not [caught]").

### Naming document's type

From `spec`, not from the doc's own basename — `validate_file` already holds it,
and it is where D1 hangs the lifetime class and legal-parent set. Hence the
signature `check_upstream_legality(doc: &Doc, spec: &FormatSpec)`, unlike R6's
`check_upstream_resolves(doc)`.

---

## 4. Where `line` comes from

`field.line` — the `FieldValue`'s single line number
(`doc.rs:43-55`: `{ value, line, entries }`). The parser records **one line per
field, not one per sequence item**, which `check_upstream_resolves`' own doc
comment states (`checks.rs:777-778`): "Every finding sits at the field's line,
since the parser records one line for the field and not one per sequence item."

So **every** per-entry legality finding sits at the field's line, exactly as the
PRD's AC requires ("each carrying the `upstream:` field's line number, as the
resolution check's per-entry findings already do"). Confirmed against a frozen
baseline: `expected/real/PLAN-roadmap-plan-standardization.md.stdout:1` reads
`::error file=real/PLAN-roadmap-plan-standardization.md,line=5::[R6] ...` and the
fixture's `upstream:` is on line 5.

This is also the fact that makes Option A's post-filter impossible (§1).

---

## 5. Codes

### Recommendation: `R10` = direction, `R11` = lifetime

Rationale:

- The `R`-family already owns the cross-format frontmatter semantics: `R6` is the
  `upstream:` resolution check, `R9` is the whole-document visibility gate. These
  two checks are direct siblings of `R6` on the same field, so they belong to the
  same family; the `FC` family is per-format structural conformance.
- The range stays contiguous, so the two user-facing enumerations stay ranges
  rather than becoming lists: `R6-R9` → `R6-R11`.
- Free: `grep` finds no existing use of `R10`/`R11` as check codes anywhere in
  `crates/`.

Assign `R10` to direction and `R11` to lifetime (ascending with the R5 table's
reading order); the numbering carries no precedence meaning — precedence lives in
the `else if`, not in the code order.

*Caveat worth stating in the design:* the PRD's requirement numbers `R1`-`R25`
and the validator's check codes `R6`-`R11` are different namespaces that collide
by prefix (PRD `R7` is the precedence requirement; check code `R7` is
`check_vision_public`). This collision predates this work and adopting `R10`/`R11`
does not worsen it, but the design doc should say the two are unrelated so a
reader does not read "check code R10" as "PRD requirement R10".

### Constraint check

- **Selectable via `--check`:** yes, once added to `is_known_check_code`
  (`validate.rs:150-176`). Nothing else gates selection: `main.rs:526-534` rejects
  unknown codes up front, and `main.rs:642` filters findings by exact code match.
- **Not `R5` or `FC99`:** satisfied. The negative list in
  `is_known_check_code_covers_per_file_codes_only` (`validate.rs:525`) is
  `["L01", "L05", "FC1", "FC99", "R5", "IO", "fc01", ""]` — `R10` and `R11` appear
  in neither the positive nor the negative list, and the match is exact-string, so
  the existing test passes unmodified with the two new arms added.
- **Error-level, not notice-level:** satisfied **with no change to either
  function**.
  - `is_intrinsic_notice` (`validate.rs:83-98`) matches only
    `SCHEMA | FC07..FC15 | FC-CONVENTIONS`. `R10`/`R11` fall through to `false`.
  - `posture_class` (`validate.rs:110-115`) matches only `L02 | L06 | L07` as
    `DraftTolerable`; the `_` arm makes `R10`/`R11` `AlwaysEnforced`.
  - Therefore `effective_severity` returns `Severity::Error` in **both** postures
    (`validate.rs:127-135`), which is what R6 of the PRD asks for and what R24's
    table assumes.
  - The existing tests over those two functions iterate fixed code lists and do
    not enumerate exhaustively, so none of them changes — consistent with R21 and
    with the AC "`is_known_check_code` gains exactly the two new codes".
  - `advisory.rs` needs no change either: `explain` filters to
    `posture_class(..) == DraftTolerable` (`advisory.rs:144`), which `R10`/`R11`
    are not, so `remedy_for` never sees them.

### The hardcoded valid-codes string in `main.rs`

**`crates/shirabe/src/main.rs:529`**:

```rust
"unknown --check code {:?}; valid codes: SCHEMA, FC01-FC16, FC-CONVENTIONS, R6-R9",
```

Change `R6-R9` → `R6-R11`.

**Is it pinned by a test?** **No.** `grep -rn "unknown --check code\|valid codes"`
across `crates/` matches only `main.rs:523` (a comment) and `main.rs:529` itself;
nothing under `crates/shirabe/tests/` asserts the stderr text, and no file under
`docs/`, `skills/`, `references/`, or `scripts/` quotes it. The `--check` tests
that exist (`cli.rs:259/276/295`, `absorption_parity.rs:172`) all pass *valid*
codes, so they never reach this branch.

### Two more enumerations to update for consistency (neither is test-pinned)

- **`crates/shirabe/src/main.rs:216`** — the `--check` clap doc comment, currently
  `` `FC01`-`FC13`, `FC-CONVENTIONS`, `R6`-`R9` ``. Note it is *already* stale
  (says `FC13` where the code supports `FC16`); fix the `R` range at minimum.
  Clap renders this in `--help`, so it is user-facing.
- **`crates/shirabe-validate/src/validate.rs:147-149`** —
  `is_known_check_code`'s doc comment, currently
  "`SCHEMA`, `FC01`-`FC16`, `FC-CONVENTIONS`, and `R6`-`R9`".

Also worth a one-line touch: `checks.rs:1`'s module doc
("The individual validation checks (SCHEMA, FC01-FC06, R6, R7, R8)") and
`doc.rs:103-105`'s `ValidationError::code` doc comment, both already stale.

---

## 6. The recommended shape, concretely

`crates/shirabe-validate/src/checks.rs` — new function next to
`check_upstream_resolves`:

```rust
/// (R10/R11) Judges each `upstream:` entry for legality: direction (the
/// target's type is in the naming format's declared legal parent set) and
/// lifetime (a Durable document must not name a Working one).
///
/// Basename-only: no file is opened, so naming a VISION or STRATEGY draws
/// nothing into the orphan rule. Entries come from
/// `crate::upstream::field_entries`, so blanks and placeholders are the
/// resolution check's business and cross-repo entries are still judged on
/// their file component. A basename matching no artifact prefix is unchecked.
///
/// R7 precedence: an entry violating both reports only the lifetime finding.
/// Because R4 forbids a Durable type from declaring a Working parent, every
/// lifetime violation is also a direction violation, so the branch order
/// below is the rule rather than a tiebreak.
pub fn check_upstream_legality(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError> { ... }
```

`crates/shirabe-validate/src/validate.rs` — one line after line 217:

```rust
    errs.extend(check_upstream_resolves(doc));
    // 2c. (R10/R11) The same field's entries, judged for legality. Must stay
    // behind the schema gate above: a doc with no `schema:` field returns the
    // SCHEMA notice alone, and the golden fixture real/PRD-roadmap-skill.md
    // (a PRD naming a ROADMAP) depends on that early return for byte parity.
    errs.extend(check_upstream_legality(doc, spec));
```

plus the two new arms in `is_known_check_code` and the string edits in §5.
