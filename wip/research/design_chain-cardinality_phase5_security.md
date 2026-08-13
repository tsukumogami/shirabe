# Phase 5 security review — DESIGN-chain-cardinality

Reviewed against the shipped code (`crates/shirabe-validate`, `crates/shirabe`),
the parent and child skill contracts, and the two references named in the brief.
Every claim below was read out of a file or measured against the release binary.

**Verdict.** The existing Security Considerations section is honest and correct on
the two things it addresses: the write-target set does stay closed, and the
fail-open compromise is characterised accurately. It is incomplete on the flag's
most consequential property — that the author-supplied value ends up in a
committed `upstream:` field in a repo of known visibility — and it under-states
the fail-open by covering only the total-failure case when the reachable failure
is partial and silent.

Four material findings, four minor. Nothing here is a reason to stop the design;
all eight are text-and-rule additions, not architecture changes.

---

## Surface 1 — the parent `--upstream <path>` flag

**Material risk, on three specific points. The canonicalization rule itself is
right and matches existing precedent.**

The design's core rule — canonicalize, reject if it resolves outside the
repository working tree, enforce the basename against the chain head's type — is
the same rule `/brief` already carries for its Input Mode 3 ROADMAP path
(`skills/brief/SKILL.md:139-143`, "Symlinks resolving to arbitrary filesystem
content would otherwise leak into a public commit") and the same shape as
`run-cascade.sh`'s `validate_upstream_path` (realpath, root confinement,
regular-file-and-not-symlink, git-tracked) and `finalize.rs`'s `validate_node_path`
(`crates/shirabe-validate/src/finalize.rs:785-802`). Reusing it is correct.

**What canonicalization must reject, concretely:**

- `..` traversal, after lexical normalization and after resolution — both, because
  they catch different things.
- Absolute paths landing outside the work tree.
- A final-component symlink. `fs::canonicalize` alone is not enough: it *follows*
  the link, so a symlink inside the tree pointing at a file inside the tree passes
  a resolve-then-confine check while still not being the file the author named.
  `finalize.rs:788-795` uses `symlink_metadata` for exactly this reason; the
  parents should say so too.
- Non-regular files. A fifo passes every path test and hangs whichever reader
  opens it.
- Paths into another repository. In this multi-repo workspace each repo is its own
  work tree, so root confinement rejects `../../private/vision/docs/...` for free —
  worth stating, because it is the reason the strategic use case has to reach for
  the cross-repo *syntax* instead (see Surface 2).
- **`wip/` paths — which the design does not mention at all.** See 1d.

### 1a. The shell-argument discipline is stated too weakly (material)

The design says the value "is never interpolated into an emitted shell command
without that validation." Validation-then-interpolate does not close the surface,
and this repo already holds a stronger house standard in two places:

- `crates/shirabe/src/main.rs:1198-1210` (the generated pre-commit hook's contract
  comment): staged paths are collected NUL-delimited and "passed to `validate`
  after a `--` end-of-options separator" so that "a filename with spaces,
  newlines, glob metacharacters, or leading dashes cannot split arguments or
  smuggle options."
- `skills/execute/scripts/run-cascade.sh:89-118`: canonicalize to an *absolute*
  path first, then quote, then `git ls-files --error-unmatch "$abs_path"`.

Two concrete cases the design's rule as written does not cover:

- A file literally named `docs/roadmaps/ROADMAP-$(id).md` canonicalizes inside the
  tree, is a regular file, and passes the basename rule. Every stated check
  succeeds; it still detonates in any double-quoted shell interpolation.
- A relative value beginning with `-` is read as an option by `git ls-files`
  (canonicalizing to absolute first is what neutralises this, which is why
  run-cascade.sh does it in that order).

This matters because R19 puts a resolution check on the resume path — "re-validated
on resume with a defined outcome when it no longer resolves" — and that check is
precisely where a skill author will write a shell command against the recorded
value. The rule should be: canonicalize to absolute before any interpolation,
quote, and pass after `--`.

`parent-skill-security.md:141-146` says future parents adding direct author-input
handling "SHALL re-state the interpolation contract explicitly rather than silently
broadening the surface." The design cites the requirement but does not discharge
it.

### 1b. The re-statement has nowhere to land (material)

The design does not name where the re-statement goes, and both landing sites need
work:

- `/scope`'s Security Considerations currently asserts "The absorbed artifact's
  path is composed from the validated topic slug, **never from author-supplied
  text**, so the write-target set stays closed and enumerable"
  (`skills/scope/SKILL.md:679-683`). That sentence becomes false as written the
  moment the flag lands. It needs amending, not just supplementing.
- **`/charter` has no Security Considerations section at all.** Its only security
  content is one reference-table row (`skills/charter/SKILL.md:228`). So its closed
  write-target set is not enumerated anywhere, contrary to
  `parent-skill-security.md:41-47` ("confined to an enumerated set declared in the
  parent's SKILL.md"). Adding the first author-supplied input to a parent whose
  envelope was never declared should force that section to exist.

Both belong in the plan as explicit deliverables.

### 1c. Flag parsing versus the "AS PROVIDED" slug rule (material)

Both parents' contract says Phase 0 validates `$ARGUMENTS` **AS PROVIDED**,
byte-for-byte, with "No normalization, no derivation, no 'best effort' massaging"
(`skills/charter/SKILL.md:73-79`; `skills/scope/SKILL.md:183-192`). `--upstream
<path>` puts slashes, dots and uppercase into `$ARGUMENTS` — characters the slug
regex forbids. So "parsed before the positional slug" is a **change** to that rule,
not a no-op, and the design's claim that "the parents' rejection of artifact paths
there is untouched" holds only if the residue rule is written down.

The rule that needs stating: strip exactly the flag token and its single following
value; validate everything remaining against `^[a-z0-9-]+$`; reject if more than
one token remains. Left unspecified, a naive strip lets
`/charter docs/visions/VISION-x.md --upstream y` through, or lets a
space-containing value bleed a path fragment into the positional slot. Both
parents' Input Modes and Topic-Slug Constraint sections need the amendment.

(Pre-existing curiosity, not this design's problem: `--auto` on its own matches
`^[a-z0-9-]+$`, so the parents already do an unstated flag-strip pass.)

### 1d. `wip/` paths are not rejected (material, small fix)

Canonicalize + bounds + basename all pass for `wip/ROADMAP-staging.md`. It is
inside the tree, a regular file, and correctly prefixed. It would be recorded in
parent state, handed to the head child, written into the produced artifact's
`upstream:` frontmatter, and orphaned the moment wip-hygiene cleanup runs.

`/prd` hard-stops on exactly this as check 1 of 3
(`skills/prd/references/phases/phase-3-draft.md:36-42`) and carries an eval for it
(`skills/prd/evals/evals.json:125-130`). The workspace CLAUDE.md makes the rule
workspace-wide. Parents are *more* exposed than children here, because parents
stage their own handoffs under `wip/`. Add the reject.

---

## Surface 2 — the flag's path reaching a public commit

**Material risk. This is the design's largest gap: its Security Considerations
does not mention repo visibility at all.**

### The path is live, not hypothetical

The strategic hop is the private-to-public case by construction. The PRD's own Out
of Scope says strategic documents exist but "are simply not in this repository"
(`docs/prds/PRD-chain-cardinality.md:361-369`) — they live in the private `vision`
repo. So `/charter <topic> --upstream <VISION-path>` run in a public repo is
*naturally* pointed at a private artifact; R18 requires the head child to write that
path into the produced STRATEGY's `upstream:` frontmatter; the STRATEGY is committed
publicly. `cross-repo-references.md:49-56` forbids public → private outright and
states plainly that the rule is "enforced by content governance ... not by tooling."

### There is no tooling backstop, verified

`check_upstream_resolves` (`crates/shirabe-validate/src/checks.rs:784-798`) returns
an empty vec for any value `is_cross_repo_reference` matches — i.e. anything with a
`:` after a `/`. A public document carrying
`upstream: tsukumogami/vision:docs/visions/VISION-x.md` validates clean. Nothing in
the validator will ever catch it.

### The precedent exists and the design does not reuse it

`/prd` Phase 3 step 3.1 runs three ordered hard-stops on its `--upstream` value
(`skills/prd/references/phases/phase-3-draft.md:36-53`): reject `wip/`, confirm
`git ls-files` tracks it, and — if the path is out-of-repo and this repo is public
while the canonical upstream is private — STOP and omit the field. `/roadmap`'s
identical flag (`skills/roadmap/references/phases/phase-3-draft.md:29-35`) has
*none* of the three. The design would extend that asymmetry to two more parents and
two more head children rather than closing it.

### The design must also decide what a cross-repo value even does

Read strictly, "canonicalized and rejected if it resolves outside the repository
working tree" **rejects `owner/repo:path` outright** — it is not a filesystem path
and canonicalization fails. The design does not say which way this goes, and both
readings need an explicit answer:

- **Strict** (reject): safe, but the flag cannot express the documented cross-repo
  case at all, which is a functional gap against R18 on precisely the strategic hop
  R20 requires.
- **Lenient** (allow as an exception to canonicalization): the visibility violation
  above is reachable with zero tooling backstop, so the visibility check becomes
  mandatory rather than optional.

### Housekeeping the design owes

Both `references/cross-repo-references.md:84-99` and `references/wip-hygiene.md:73`
carry a "where this rule is enforced" table with an explicit keep-in-sync
instruction ("When updating either side, update the other: a new validation point
belongs in this table"). Four new validation points arrive with this change — two
parents plus the two head children. Neither table is mentioned in the design.

---

## Surface 3 — the referrer map in the finalization walk

**No exposure risk from reading more files. Two material correctness holes in how
the map is consulted, and one boundary worth naming.**

### Reading more files creates no exposure (no risk)

`build_doc_index` (`crates/shirabe-validate/src/lifecycle.rs:262-343`) reads six
fixed directories, **non-recursively**, requires `.md` plus one of five artifact
prefixes, canonicalizes every candidate, and drops anything escaping the root with
an L05. No new file classes, no directory recursion, no symlink following into
arbitrary content, no user-supplied path. ~150 documents in this repo; cost
negligible. The design's silence here is appropriate — there is nothing to say.

### 3a. Partial-index silent fail-open (material)

The design covers only the case where "a corpus cannot be indexed." That is not the
reachable failure. `build_doc_index` returns an empty index **only** if the root
itself fails to canonicalize; every other failure is *per-document*: `index_doc`
returns `Err` for an unparseable frontmatter or an undetectable format
(`lifecycle.rs:351-380`), the document is dropped, an L05 is pushed, and the index
is returned and used.

A dropped document contributes no referrer edges. Its ancestor therefore looks
unreferenced, the guard passes, and R12's protection silently does not apply — with
**no note**, because from the walk's point of view the corpus indexed fine. That is
a silent fail-open at exactly the granularity that matters, and it is far more
reachable than the total failure the design does cover. (No L05s in this repo's
corpus today — I ran the whole-tree check — so this is reachability, not a live
hole.)

Fix: treat any L05 emitted during index construction as a per-node note on the same
footing as the un-indexable-corpus note, so an incomplete referrer set is always
visible.

### 3b. Key-normalization mismatch between index and walk (material)

The index is keyed on `fs::canonicalize`d absolute paths (`lifecycle.rs:315`), and
`extract_upstreams` canonicalizes upstream targets too (`lifecycle.rs:414`). The
finalization walk's node paths are **lexically** normalized against a cwd join and
never canonicalized (`finalize.rs:812-830`, `reject_outside_root` /
`lexical_normalize`).

Wherever the two disagree, the lookup misses and the guard reports "no referrers"
for a document that has them: a repo reached through a symlinked path, a git
worktree (this very review session is running inside `.claude/worktrees/…`), or
`/tmp` → `/private/tmp` on macOS. The design says the walk "consults the referrer
map" without specifying the key.

Fix: state that walk node paths are canonicalized with the same primitive before
lookup, and that a canonicalize failure is a *block*, not a miss.

### 3c. The index is the guard's real scope boundary (minor)

R12 says "a document it is not itself retiring in this walk still names it as an
upstream." The implementation can only see six directories. `docs/specs/`,
`docs/spikes/`, `docs/decisions/`, `docs/guides/`, `docs/visions/`,
`docs/strategies/`, and any `docs/designs/<subdir>` other than `current/` are
invisible referrers. I checked: no document in specs, spikes, decisions or guides
carries an `upstream:` today, so nothing is exposed now. But this is the guard's
scope statement and belongs in Known Limitations beside the PRD's existing
"removed by other means" caveat.

### 3d. Out-of-root referrer-map keys (minor)

`extract_upstreams` canonicalizes upstream *targets* with no containment check, so a
document with `upstream: ../../elsewhere/X.md` puts an out-of-root key into the map.
Harmless — the walk's own nodes are root-confined, so such a key never matches — but
worth one sentence so a later reader does not treat a referrer-map key as
trusted-in-root.

---

## Surface 4 — the parser change

**No new risk from the change itself. One material pre-existing DoS whose likelihood
this design raises.**

### The design's claim is true (no risk)

"The parser accepts YAML it already parsed and previously discarded; making a
discarded value visible does not widen what the tool reads." Verified: saphyr's
loader expands aliases during `load()` — `Event::Alias(id)` looks the anchor up and
clones the node (`saphyr-0.0.6/src/loader.rs:293-311`) — which happens *before*
`scalar_source_text` returns `None` for non-scalars and the value is dropped
(`crates/shirabe-validate/src/frontmatter.rs:236, 264-270`). The expansion already
occurs today.

Measured directly: a document with `anch: &x docs/roadmaps/ROADMAP-a.md` and
`upstream: *x` already resolves the alias and reports
`[R6] upstream "docs/roadmaps/ROADMAP-a.md" does not exist on disk` on the shipped
binary. Aliases, anchors and merge keys are all intra-document — YAML has no include
or file-read primitive — so nothing outside the file becomes readable, before or
after. After the change an alias to a *sequence* becomes visible; each entry still
goes through R6 resolution and, on the mutation path, `validate_node_path`. No new
risk.

### 4a. The loader has no alias-expansion budget (material, pre-existing)

I built a 449-byte billion-laughs frontmatter (nine nested anchors, nine aliases
each) and ran the shipped release binary against it under a 4 GB address-space
limit:

```
memory allocation of 1152 bytes failed
Aborted (exit 134)
```

Untouched by this design — it detonates identically today — but the design *raises
its likelihood* in two ways worth naming:

- R21 makes sequence-valued frontmatter a first-class, documented shape. Anchors and
  sequences are the same YAML machinery, and the format references are about to
  invite authors into it.
- The finalization walk's new whole-corpus parse means one such document now kills
  the **mutation** path, where previously it affected only the file being validated.

Recommendation: record it as a known limitation with an expansion/nesting cap as
follow-up. The parser backstop already documented at `frontmatter.rs:8-20` (drop to
`saphyr-parser`'s `SpannedEventReceiver`) is the natural place a budget would live.

---

## Surface 5 — the un-indexable-corpus compromise

**Failing open is acceptable and correctly reasoned. The note as specified is not
sufficient.**

**Worst outcome.** `finalize-chain --apply` transitions a shared ancestor to a
terminal status while a live chain still depends on it — exactly the damage that
produced the five dangling references the PRD cites, plus a status mutation that has
to be reverted by hand. It is a correctness and auditability failure, not an
access-control one, which is how the design characterises it. Correct.

**Failing open is right.** Failing closed would let an unrelated parse error in any
document block every finalization, and R23 forbids modifying the existing tests that
would break. The design gives this reasoning and it holds.

**Three sufficiency gaps:**

- The note lands "on each transition node," i.e. in the JSON report.
  `run_finalize_chain_cmd` (`crates/shirabe/src/main.rs:1179-1195`) prints the report
  and exits 0 on success regardless of note contents, and `run-cascade.sh` is the
  automated caller. If the note is not also surfaced on the human/stderr path and
  logged by the cascade, "visibly open" is visible only to whoever reads the JSON.
- The partial-index case (3a) produces **no note at all**, and it is the reachable
  one. That is the larger half of this finding.
- The design says the plan "carries a test asserting the note appears." It should
  assert the note reaches the cascade's surfaced output, not just the report struct.

---

## Surface 6 — claims that do not hold, and surfaces not mentioned

**Claims tested:**

| Claim | Holds? |
|---|---|
| "The write-target set stays closed and enumerable" | True in substance — the supplied upstream is read-only and never a write destination. Not *verifiable* for `/charter`, which declares no write-target set in its SKILL.md at all (see 1b). |
| "the parents' security contract requires ... re-state the interpolation contract explicitly" | Correctly cited; not discharged. No deliverable named (1a, 1b). |
| "It is never interpolated into an emitted shell command without that validation" | Too weak. Validation does not neutralise command substitution in the filename or a leading dash; the repo's own standard is canonicalize-absolute, quote, and `--` (1a). |
| "It does not enter the positional slot whose regex is the parents' existing guard" | True only once the residue rule is specified; as written it contradicts the parents' "AS PROVIDED, byte-for-byte" text (1c). |
| "The parser accepts YAML it already parsed and previously discarded" | True, verified against the loader and the running binary (Surface 4). |
| "The validator changes introduce no new input surface" | True of the parser. **False of the finalization change**: the walk goes from parsing its own chain to parsing the whole indexed corpus. Every file in that set was already an input to the *validator*, but not to the *mutation* path. Should be stated. |
| "the walk fails visibly open" | True of total index failure; false of the reachable per-document failure, which is silent (3a). |
| "The finalization change reduces a security-adjacent risk rather than adding one" | Net true, and the framing is right. |

**Surfaces not mentioned at all:** repo-visibility direction (Surface 2); `wip/`
paths (1d); the resume-time re-resolution as an interpolation site (1a); the
referrer map's key normalization and index-coverage boundary (3b, 3c).

---

## Suggested minimum additions to the design's Security Considerations

1. A visibility paragraph: the flag's value reaches a committed `upstream:` field,
   the public → private direction is forbidden, no tooling enforces it, and the
   check is `/prd` Phase 3 step 3.1's third hard-stop applied at the parent. Decide
   explicitly whether `owner/repo:path` is accepted or rejected by the flag.
2. Add `wip/` to the inbound reject list, next to the bounds and basename rules.
3. State the interpolation discipline in the repo's own terms — canonicalize to
   absolute, quote, pass after `--` — and name both parents' SKILL.md Security
   Considerations as the place it is re-stated (creating `/charter`'s, which does
   not exist).
4. State the flag-strip residue rule so the positional rejection claim is true
   rather than asserted.
5. Extend the fail-open paragraph to the per-document case: an L05 during index
   construction means an incomplete referrer set, and must produce the same note.
6. State that walk node paths are canonicalized with the index's own primitive
   before referrer lookup, and that a canonicalize failure blocks.
7. Name the index's six-directory coverage as the guard's scope boundary in Known
   Limitations.
8. Record the unbounded YAML alias expansion as a pre-existing limitation the R21
   documentation work makes more reachable.
