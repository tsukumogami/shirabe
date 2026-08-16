# Lead: Who reads the fold record (`docs/folds.md`) today, and what breaks if it disappears?

## Findings

### The single most important fact: the record has zero rows

`docs/folds.md` is 63 lines, all of it header — a title, a "why this exists"
section, a column table, a concurrency note, and the table header with no rows
beneath it (`docs/folds.md:60-63`). It was created by exactly one commit
(`83d29e1 feat(scope): decide absorbability from the documents, not the types
(#302)`) and no fold has ever been recorded. Every consumer below has therefore
never run against real data. The whole mechanism is unexercised.

### Consumer 1 — CI: the "Verify the fold record" step

`.github/workflows/validate-docs.yml:102-165`. This is the **only** consumer
that parses row content, and the only one that fails if the file is missing.

It fires on a fold signature, not a deletion (`:105-112`): a deleted chain
document matching `^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$`
(`:120-121`) *plus* an `absorbed:` declaration naming that path among the diff's
**added** lines (`:132-138`). With no deletion it exits 0 immediately (`:123-125`).

Three assertions, in order:

1. **Presence** (`:137-141`): `git show "$HEAD:docs/folds.md" | grep -qF "$doc"`.
   Needs only that the path appears somewhere in the file.
2. **Blob hash** (`:145-152`): `want=$(git rev-parse "$BASE:$doc")`, then greps
   the row for `$want`. This is the one assertion that needs the **Blob column's
   content**.
3. **Append-only shape** (`:155-163`): if the file changed in the diff, the
   `-U0` hunk must contain no removed line starting with `-` that also contains
   a `|`. This asserts **shape**, not content.

**If the file did not exist:** the step FAILS CLOSED on a fold PR —
`git show` errors, stdout is empty, `grep -qF` fails, `! ...` is true, and it
emits `::error::$doc was absorbed but docs/folds.md has no row for it` with
`status=1`. On every non-fold PR it exits 0 at `:123` having never touched the
file. So absence is invisible except on precisely the PRs the record exists for.

#### Defect found: the row lookup is column-blind and breaks on a two-hop chain

`:147` is `row=$(git show "$HEAD:docs/folds.md" | grep -F "$doc" | head -1)`.
`grep -F` matches the path in **any** column, including `Into`. A `/scope` chain
that folds twice — BRIEF→PRD, then PRD→DESIGN — appends hop 1 first, and hop 1's
`Into` cell is `docs/prds/PRD-topic.md`. When the loop reaches the PRD, `head -1`
returns **hop 1's row**, whose Blob is the BRIEF's hash, and the comparison
against the PRD's pre-fold blob fails. I reproduced this exactly
(`/home/dgazineu/.claude/jobs/83dd7c3d/tmp/rowprobe.sh`):

```
doc=docs/prds/PRD-topic.md
  row picked: | 2026-08-16 | docs/briefs/BRIEF-topic.md | docs/prds/PRD-topic.md | absorb | brief=true | AAAAblobOfBrief |
RESULT: hash check FAILS -- CI would error on a correct record
```

Both hops land in one squash PR (that is the premise the record was built on),
so this is the ordinary multi-hop case, not an edge case. It has never fired
because there are no rows. Note the same phenomenon — *the record names a live
survivor by path* — is explicitly known and handled one file over, in
`check-citations.sh:114-115`; the CI checker just did not account for it.

#### Second gap: the promised duplicate check does not exist

`docs/folds.md:53-55`, `.gitattributes:6-8`, and
`DESIGN-scope-artifact-persistence.md:330-336` all state that a union-merge
duplicate row is tolerable because "the checker flags it". Grepping
`validate-docs.yml` for `duplicate` returns nothing. There is no duplicate
detection anywhere. `head -1` actively hides one. Three documents assert a
safety property no code provides.

#### Third gap: a Current-lifecycle DESIGN cannot be folded at all

The signature regex (`:120`), `ABSORBED_ENTRY_PATTERN`
(`crates/shirabe-validate/src/formats.rs:187-188`) and `check-citations.sh`'s
`DOC_PATH_RE` (`:48`) all admit only `docs/designs/DESIGN-*.md`. But
`phase-2-chain-orchestration.md:273-280` says a DESIGN may be discovered at
`docs/designs/current/DESIGN-<topic>.md`. Folding one of those is refused by the
guard (exit 3 → `keep`), so it fails closed and consistently. Worth naming
because it bounds the record's real reach.

### Consumer 2 — `shirabe validate` (Rust): validates the record as prose

This was not on the candidate list and is a genuine binding. The reusable
workflow computes `FILES` from the PR's whole changed-file set
(`validate-docs.yml:88-90`) and passes it positionally, so **`docs/folds.md` is
handed to `shirabe validate` on every fold PR**.

`detect_format("folds.md")` returns `None` (`formats.rs:475-487` — no prefix
matches), but the file is Markdown, so `main.rs:694-704` does *not* skip it: it
falls to the prose family, `validate_prose` (`main.rs:762-765`,
`validate.rs:211-221`). Three checks run: `check_writing_style`,
`check_claude_md_conventions` (basename-gated, inert here), and **FC20
`check_stale_references`**.

FC20 matters. `reference_spans` parses table cells (its own probe list includes
`|a/b.md|`, `prose.rs:699`), and `is_candidate` accepts any path whose directory
is in `ARTIFACT_DIRS` and whose basename carries an artifact prefix
(`references.rs:132-143`) — which is exactly the shape of the Absorbed and Into
columns. So **every row is scanned as a reference candidate on every fold PR.**

It does not fire today, because FC20 only reports when the path is missing *and*
the same basename exists elsewhere in the index (`checks.rs:4029-4031`); a folded
document is gone entirely. But `ARTIFACT_DIRS` contains **both** `docs/designs`
and `docs/designs/current` (`references.rs:44-57`). A row recording
`docs/designs/DESIGN-x.md` becomes an FC20 finding — *"the document moved"* — the
moment any later artifact reusing that slug lands at
`docs/designs/current/DESIGN-x.md`. This is latent, narrow (needs slug reuse),
and entirely unremarked anywhere.

**If the file did not exist:** it is never in the changed-file set, so the
validator never sees it. Silently unaffected.

### Consumer 3 — `check-citations.sh`: needs the *path constant*, not the file

`skills/scope/scripts/check-citations.sh:69` defaults `record="docs/folds.md"`;
`:99-101` asserts its shape because it reaches a pathspec; `:117-125` and
`:139-147` interpolate it as `:!$record`, excluding it from both git-grep tiers.

The exclusion exists for the reason the header states at `:114-115`: the record
names a **live survivor** by path, so without it a chain's first fold would make
its second fold refuse. This is the correct read of "`--record` excludes the
file" — it is defence against the record poisoning the guard, not a use of it.

I verified empirically (`/home/dgazineu/.claude/jobs/83dd7c3d/tmp/foldtest.sh`)
that the script is **indifferent to whether the file exists**:

```
EXIT=0 (docs/folds.md ABSENT)
EXIT=0 (docs/folds.md PRESENT, excluded)
```

An exclusion pathspec naming a nonexistent path is harmless to `git grep`. This
consumer needs the *string* `docs/folds.md` to keep compiling, and nothing more.

`check-citations_test.sh:117-129` covers exactly this ("the fold record does not
refuse a later hop"). Its fixture row is **four columns**, not six —
`| date | absorbed | into | absorb |`, no Carried, no Blob — because only the
path matters to the exclusion. The test therefore does not pin the real schema.

### Consumer 4 — `/scope`: the sole writer

- `phase-2-chain-orchestration.md:667-669` — step 6 of the absorb: "Append one
  row to `docs/folds.md` and `git add` it", ordered **before** the delete so a
  failed append aborts with nothing lost.
- Rollback table `:684-697`: steps 6-9 all un-append. The un-append is called out
  explicitly because a revert that skipped it would strand a durable row
  asserting a fold that was undone.
- `:820-823` — `verdict:` and `stage:` are enum-revalidated because both are
  "serialized into the durable fold record".
- `phase-3-exit-finalization.md:318`, `SKILL.md:824-827` — enumerated in the
  closed write-target set as "a fixed constant with nothing interpolated".
- `phase-4-cleanup.md:101-111` — a carve-out: enumerated in the write set but
  never swept, stated explicitly so "enumerated" does not read as "authorised to
  delete".

**The append mechanism is unspecified.** It is prose only; there is no script and
no `shirabe` subcommand. See the context section below — this is where the only
real context exposure lives.

### Consumer 5 — `/execute`: mentions it, explicitly disclaims reading it

`skills/execute/SKILL.md:590-600` handles "a finalized chain that folded every
artifact away", where there is no durable anchor to seed the lifecycle guard on.
The record is named as the evidence a human uses to tell that case from a chain
that never ran — and the text is emphatic that this is not a code path:

> "The record is the evidence; it is not a seed, and nothing here reads it to
> make a lifecycle decision."

`skills/execute/scripts/run-cascade.sh:465` writes the literal string
`**Downstream:** _none (chain folded; see docs/folds.md)_` into a ROADMAP feature
line when `CASCADE_DESIGN_PATH` is empty. That is a **prose pointer emitted into
a durable document** — it makes the record's path a citation target in ROADMAPs,
which is a small argument against renaming or removing the path.

**If the file did not exist:** `/execute` is unaffected mechanically; the
run-cascade line becomes a dangling pointer, and the human troubleshooting story
in SKILL.md loses its evidence.

### Consumer 6 — `.gitattributes`: shape, not content

`.gitattributes:3-10` sets `docs/folds.md merge=union` with a comment explaining
that concurrent chains would otherwise conflict, and that union cannot dedupe.
If the file is absent the attribute is inert. Pure shape assertion.

### Consumer 7 — `docs/guides/doc-validation.md`: prose only

`:54-68` documents the fold-record verification for downstream repos pinning the
reusable workflow. Describes; reads nothing.

### Consumer 8 — design/PRD docs: prose only, plus falsified claims

`DESIGN-scope-artifact-persistence.md:19, 164-174, 231, 305-336, 412`;
`DESIGN-scope-consolidation-over-skipping.md:846`;
`PRD-scope-consolidation-over-skipping.md:414`. All rationale. The persistence
design's `:164-174` records that *the survivor's frontmatter* was the closest
losing alternative, killed because "the record dies with the document at the next
hop, and the terminal fold has no survivor at all" — the constraint any
replacement carrier must clear.

### Consumer table

| Consumer | Reads rows / writes rows / asserts shape / mentions | Behavior if the file is absent |
|---|---|---|
| `.github/workflows/validate-docs.yml:102-165` | **reads rows** (presence, Blob hash) + **asserts shape** (append-only) | **Fails** on a fold PR (`::error`, exit 1). Exits 0 on every non-fold PR without touching it. |
| `shirabe validate` (`main.rs:694-765` → `validate_prose`) | **reads rows** incidentally (FC20 scans every path cell) | Never in the changed-file set; silently unaffected |
| `skills/scope/scripts/check-citations.sh:69,99-101,117-147` | **mentions** (path used only as a git-grep exclusion) | **Silently identical.** Verified: exit 0 either way |
| `check-citations_test.sh:117-129` | writes a 4-column fixture row | Test would need its fixture removed; asserts nothing about schema |
| `/scope` Phase 2 (`phase-2:667-669, 684-697`) | **writes rows** (sole writer) | Creates it on first append (design says "created on first append") |
| `/scope` Phases 3/4 (`phase-3:318`, `phase-4:101-111`, `SKILL.md:824`) | **asserts shape** (enumerated write target; carved out of the sweep) | Enumeration is vacuous; nothing breaks |
| `skills/execute/SKILL.md:590-600` | **mentions** (explicitly disclaims reading) | Human troubleshooting story loses its evidence; no code path changes |
| `skills/execute/scripts/run-cascade.sh:465` | **mentions** (emits the path into a durable ROADMAP line) | Emits a dangling pointer |
| `.gitattributes:3-10` | **asserts shape** (merge driver) | Inert |
| `docs/guides/doc-validation.md:54-68` | **mentions** | Doc describes a check that fails |
| Design/PRD docs | **mentions** | Rationale becomes stale |

### Row content vs. "a fold happened"

Only **one** assertion in the entire tree needs row content: the CI blob-hash
comparison (`validate-docs.yml:145-152`), which needs the Absorbed path paired
with the Blob column. Presence needs only the path. Append-only needs only the
shape of the diff hunk. Everything else needs nothing at all.

The **Carried** column has **zero readers.** Nothing parses it, nothing asserts
it, no test covers it. It is written by the absorb (`phase-2:820-823`) and never
consumed. **Verdict** is likewise unread, and is documented as a constant
(`docs/folds.md:35`: "always `absorb`; a `keep` writes no row") — a column whose
value is fixed by construction. **Date** has no reader either.

So of six columns, two (Absorbed, Blob) carry the machine-checked assertion, and
four are for human eyes only.

### Is `docs/folds.md` loaded into an agent's context window?

**No code path or skill instruction reads it into context today.** I grepped
`skills/`, `crates/`, `.claude/`, `.claude-plugin/`, `AGENTS.md`, `CLAUDE.md`,
`scripts/`, `references/`, and the eval/test trees. Every hit is an append
instruction, a write-set enumeration, a sweep carve-out, or prose. There is no
"read the record", no `Read` directive, no `cat`, no `grep` of it by any agent.
`execute/SKILL.md:597-600` goes out of its way to say nothing reads it.

CI reads it in a runner subprocess (`git show`), which never touches an agent's
context.

**The one real exposure is the append itself, and it is unspecified.**
`phase-2:667-669` says only "Append one row to `docs/folds.md` and `git add` it".
There is no script, no `shirabe` subcommand, no `>>` shown. Under Claude Code the
Edit tool requires a prior Read of the file, so an agent taking the natural
"edit the table" route pulls the **entire record** into context on every fold —
growing linearly and forever. An agent using `printf ... >> docs/folds.md` reads
nothing. Which happens is left to the model. The rollback path
(`:688`, "un-stage and remove the appended row") is a mutation of existing
content and pushes harder toward a read-modify-write.

**So the user's concern is directionally right but misattributed.** The record is
not a context hog because anything consumes it; it is a *potential* one because
the writer's procedure never says how to append without reading. That is a
one-line fix (mandate an append-only shell redirect, or add a `shirabe` subcommand),
not a reason to delete the file — and it is worth separating cleanly from the
question of whether the record earns its keep at all.

**No documented future use would change this.** Nothing in the persistence
design, the consolidation design, or the PRD proposes a reader. The design's
section headed "The record" (`:305-336`) describes only writing and checking.

## Implications

1. **The removal cost is far lower than the file's ceremony suggests.** Delete
   `docs/folds.md` and exactly one thing breaks: a CI step that has never had
   data to check, and which is itself broken for the ordinary two-hop chain.
   Every other consumer is a mention, a merge attribute, or an exclusion string.

2. **A cheaper carrier is viable for most of the payload.** Four of six columns
   have no reader. If the requirement is only "distinguish absorbed from never
   produced", the survivor's `absorbed:` frontmatter already carries that — and
   `absorbed:` is what the CI step *triggers on*, so it necessarily exists on
   every fold. What `absorbed:` cannot carry is (a) the blob hash and (b) the
   terminal fold, where no survivor remains. Those two are the entire residual,
   and they are exactly the objections the design recorded at `:164-174`.

3. **The blob hash's value is worth re-examining on its own.** It is the only
   column with a machine consumer, and its consumer is currently miscomputed.
   Ask what it buys: it proves the row describes the bytes actually deleted, but
   the pre-fold bytes are only recoverable from the PR branch, which is squashed
   and deleted — so the hash verifies a claim about content nobody can retrieve.

4. **Any "replace it" option must answer the terminal fold.** A chain that folds
   DESIGN into PLAN and then has `/execute` delete the PLAN leaves no document at
   all. That is the case the record was built for, and it is the case a
   frontmatter-only carrier cannot serve.

5. **The three latent defects should be priced into "keep it".** Keeping the
   record means fixing the row lookup, building the duplicate check that three
   documents already promise, and deciding whether FC20's slug-reuse false
   positive matters. That is real work on a mechanism with zero rows.

## Surprises

- **Zero rows, ever.** The whole apparatus — merge driver, CI checker, exclusion
  set, carve-out, four documents of rationale — has never processed a single
  fold. Every behavioral claim in this repository about the record is a
  prediction.
- **The CI hash check is wrong for a two-hop chain**, reproduced above. It picks
  the row where the path appears in the `Into` column. This is the normal case a
  `/scope` chain produces, and the failure mode is a red CI on a *correct* record.
- **The duplicate check that `.gitattributes`, `docs/folds.md`, and the design
  all cite does not exist.** The design even calls the duplicate residual "the
  one genuinely new mechanism in this design" (`:330-336`) — and its mitigation
  was never built.
- **`shirabe validate` is an undocumented consumer.** The record is prose-validated
  on every fold PR, and FC20 scans every row's paths. Nobody wrote this down.
- **The `Carried` column has no reader at all** — not CI, not a test, not a skill.
  It is the most expensive column to produce and the only one nothing consumes.
- **`check-citations.sh` exists partly to defend against the record**, not to use
  it. The record's own growth is a hazard to the fold guard, mitigated by
  excluding it.
- **The test fixture uses a 4-column row** against a 6-column schema, so the
  schema is unpinned by any test.

## Open Questions

1. Should the append be mandated as a shell redirect (`>>`) to close the context
   exposure — and is that sufficient given the rollback path mutates rows?
2. Is the blob hash worth keeping given the bytes it hashes are unrecoverable
   after a squash-merge? This decides whether a frontmatter carrier suffices.
3. For the terminal fold (no survivor), what is the intended reader story — who
   asks "did a chain run here?", how often, and would a git trailer or the PR
   body serve? Note the design killed the PR body on a measured fidelity failure
   (`:172-174`), which a replacement proposal must not re-tread.
4. Should the three CI defects be fixed before the remove-or-replace decision, or
   does their existence argue the mechanism was never load-bearing?
5. Does any downstream repo pin `validate-docs.yml` and rely on the fold step?
   Removing it is a reusable-workflow contract change.
6. Is `Carried` intended for a future reader, or was it speculative?

## Summary

`docs/folds.md` has exactly one machine consumer that parses row content — the CI
step at `.github/workflows/validate-docs.yml:102-165` — and that step has never
seen a row, since the file is 63 lines of header with an empty table; every other
reference (`check-citations.sh`, `/execute`, `.gitattributes`, the guides and
designs) is a prose mention, a merge attribute, or a git-grep exclusion that I
verified behaves identically whether the file exists or not. Nothing loads the
record into an agent's context today, so the "context hog" concern is not true as
stated — the real exposure is that Phase 2's append step is unspecified prose, so
an agent that reaches for the Edit tool must read the whole growing file, which a
mandated `>>` would fix in one line. The biggest open question is whether the blob
hash earns the mechanism at all, given it verifies bytes that a squash-merge makes
unrecoverable, and given that the CI check reading it is itself defective — it
picks the wrong row on any chain that folds twice, which is the ordinary case.
