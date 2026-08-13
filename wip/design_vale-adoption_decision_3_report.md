# Decision 3: vocabulary declaration

**Question.** How does a repository declare the terms of art the rules must not
fire on?

Binding requirements: R8 (term-scoped, case-insensitive, no morphological
variants), R9 (extends, never replaces), R10 (repo-local, no built-in
exemptions), R16 (resolvable by validator, drafting skill, and local/pre-commit
run, without CI wiring), R17 (no declaration means nothing suppressed).

One framing correction before the options, because it changes the scale
analysis. The declaration is a **subset of the rule list**, not an open-ended
dictionary. You can only suppress a term the rules actually fire on, and the
word list is 47 entries (`skills/writing-style/SKILL.md:12-16`). So the
theoretical ceiling on any repo's declaration is 47 entries — a repo that
declares all 47 has disabled the word rules the long way — and the realistic
figure is single digits. shirabe needs 2. A repo with domain collisions on
`tier`, `journey`, `navigate`, `realm`, `landscape`, `narrative`, and
`align with` needs 7. "An adopter may need dozens" is an upper bound the rule
list itself forbids reaching until shirabe's rulebook grows several times over.

## `resolve_doc_visibility` algorithm

`crates/shirabe-validate/src/visibility.rs:70-101`. This is the only compiled
reader of a CLAUDE.md header in the tree, and the behavior a vocabulary reader
would mirror. Precisely:

1. **Canonicalize** the doc path (`std::fs::canonicalize`), so the ancestor
   walk is absolute and stable regardless of process CWD. On failure (file
   already consumed, broken symlink) fall back to the raw path.
2. **Walk up from the doc's *directory***, i.e. starting at
   `canonical.parent()` — not from the doc itself. In each directory, try
   `CLAUDE.local.md` first, then `CLAUDE.md`. Read each; if
   `parse_visibility_header` returns a value, **return immediately**. Otherwise
   continue to `d.parent()`. The loop ends at the filesystem root.
3. A **header-less `CLAUDE.md` does not stop the walk.** This is deliberate and
   documented in the code (`visibility.rs:79-81`): a nested workspace layout
   keeps the per-repo header below workspace-level `CLAUDE.md` files that lack
   it.
4. **Path inference** if the walk found nothing: `infer_visibility_from_path`
   walks the path components in reverse (leaf upward), returning on the first
   component equal (ASCII case-insensitive) to `private` or `public`. Nearest
   component wins.
5. **Default `"private"`** — fail safe toward restriction.

`parse_visibility_header` (`visibility.rs:31-46`) is line-oriented: for each
line, `trim()`, `to_ascii_lowercase()`, `strip_prefix("## repo visibility:")`,
trim the remainder, and accept a value that *starts with* `private` or `public`.
Case-insensitive on both key and value. An unrecognized value is skipped rather
than erroring, and a later well-formed header in the same file still wins. A
prose mention (`See the ## Repo Visibility: Public note`) does not match,
because the prefix strip happens after `trim()` on the whole line.

Two properties worth naming because a vocabulary reader must decide them:

- **First-declaration-wins, not merge.** Forced by the scalar shape here; a
  term set could merge, and that is a real design choice (addressed under the
  recommendation).
- **`CLAUDE.local.md` beats `CLAUDE.md` in every directory.** For vocabulary
  this hands adopters a free uncommitted local escape hatch.

One limitation in the canonicalize-failure fallback: for a bare relative path
with no directory component (`"CLAUDE.md"`), `Path::new("CLAUDE.md").parent()`
is `Some("")`, so the reader reads the CWD's `CLAUDE.md` and then stops — it
does not walk to real parent directories. Unreachable in the validate path
(the file was just parsed, so canonicalize succeeds), but a vocabulary reader
inherits it.

**Caller-side override.** `main.rs:588-597` uses `resolve_doc_visibility` only
when `--visibility` is empty; an explicit flag **overrides detection for every
file in the run**. And the reusable workflow always passes it:
`--visibility=${{ github.repository_visibility }}`
(`.github/workflows/validate-docs.yml`). So shirabe's one per-file resolver is
switched off in the exact consumer (CI) where per-file resolution matters most.
That is the precedent-warning for this decision: **do not give the vocabulary a
run-global flag with override-everything semantics**, or R10 dies the same way.

## Empirical results

Scratch tree at `/home/dgazineu/.claude/jobs/b0818094/tmp/d3/`, exercised with
the built binary (`target/release/shirabe`) using `comp/v1` docs, whose R9
private-only check (`checks.rs:883-899`) is visibility-gated and therefore a
direct read-out of what the walk resolved.

Layout: `outer/CLAUDE.md` = `## Repo Visibility: Private`;
`outer/inner/CLAUDE.md` = `## Repo Visibility: Public`;
`outer/inner/deep/CLAUDE.md` = no header.

| Doc | Nearest header | Result | Resolved |
|---|---|---|---|
| `outer/COMP-outer.md` | `outer/` (same dir) | FC01/FC04 only, no R9 | private |
| `outer/inner/docs/competitive/COMP-x.md` | `inner/`, 2 levels up | `[R9] ... visibility=public` | public |
| `outer/inner/deep/a/b/c/COMP-deep.md` | `inner/`, 5 levels up, past a header-less `deep/CLAUDE.md` | `[R9] ... visibility=public` | public |

**The exact rule: the nearest ancestor `CLAUDE.local.md`/`CLAUDE.md` that
carries the header wins, at any depth, and an intervening CLAUDE.md without the
header is transparent.** The same-directory case resolves against the file's
own directory, which answers the "what if the file IS CLAUDE.md" question: the
walk starts at the file's *parent directory* and never inspects the file
argument itself, so validating `<repo>/CLAUDE.md` reads `<repo>/CLAUDE.md` (or
`<repo>/CLAUDE.local.md` first) and finds its own declaration. A CLAUDE.md
governs the checking of itself. Under R3 that is exactly what you want, since
R3 puts CLAUDE.md into the checked set for the first time.

**Two repos in one invocation** — passing `outer/COMP-outer.md` and
`outer/inner/docs/competitive/COMP-x.md` to a single `shirabe validate` call
resolved them differently in the same run (the first got no R9, the second got
R9). Per-file resolution is real and already proven, provided no global flag is
passed.

**Relative paths work** (script at `.../d3/relcheck.sh`, run with CWD =
`outer/`): `inner/docs/competitive/COMP-x.md` still resolved to public. This is
the pre-commit hook's calling convention — the hook passes repo-root-relative
staged paths after `--` with CWD at the repo root
(`crates/shirabe/src/main.rs:1210-1236`) — and the CI workflow's, which passes
`git diff --name-only` output positionally from the caller checkout root.

**The nested-workspace case is live here, not hypothetical.** Grepping the four
ancestor CLAUDE.md files of this worktree: the workspace root, the org root,
and `public/` all carry zero `Repo Visibility` matches; only
`public/shirabe/CLAUDE.md` carries it (3 matches). The walk's
transparent-to-header-less-files behavior is what makes that resolve correctly.

**R10 is structurally guaranteed in CI, verified against the workflow layout.**
The caller repo is checked out at `$GITHUB_WORKSPACE`; shirabe goes to
`$GITHUB_WORKSPACE/.shirabe-src` (`path: .shirabe-src` in the workflow). An
adopter's doc at `$GITHUB_WORKSPACE/docs/prds/PRD-x.md` has ancestors
`docs/`, `$GITHUB_WORKSPACE`, `/home/runner/work/<repo>`, … — `.shirabe-src` is
a *child* of the checkout root and never an ancestor of any adopter doc. So
shirabe's own declaration cannot reach an adopter's files through the walk, and
`tier`/`journey` cannot become de-facto built-ins. On the self-caller (shirabe
validating shirabe), `$GITHUB_WORKSPACE/CLAUDE.md` *is* an ancestor, which is
the correct outcome.

## Options considered

### A — a new parsed CLAUDE.md header

`## Prose Vocabulary: tier, journey`

**R16, all four consumers.** CI: cwd is the adopter checkout root, paths are
repo-relative, the walk finds the adopter's `CLAUDE.md` — verified above, and
needs no workflow input, so zero adopter wiring. Local run: identical path.
Pre-commit hook: verified with relative paths and CWD at repo root. Drafting
skill: **CLAUDE.md is already injected into the agent's context on every
session.** No grep, no Read, no skill-prose instruction to look somewhere. This
is the only option where the second consumer gets the declaration for free, and
it is the sharpest R16 differentiator, because R16's stated failure mode is
precisely "the drafting agent firing on terms the validator has been told to
ignore."

**Scale.** Ceiling 47 by construction, realistic 2-10. Comma-delimited (not
space) is required anyway, because `align with` is a two-word entry on the rule
list. A 10-term heading is ~70 characters — long but readable. A 25-term
heading is bad. The breaking point is real but sits above where the rule list
puts almost every adopter, and a repo that passes it is telling you it wants to
argue about rules, not vocabulary — which R14/R15 and the per-check machinery,
not this decision, would answer.

**R10.** Inherits the proven per-file walk unchanged. Passes the two-repo test
today.

**Precedent cost.** A second compiled header reader. The honest framing is that
it is not a *second* reader so much as the generalization of the first:
`resolve_doc_visibility` becomes `resolve_claude_md_header(path, key)` plus a
thin visibility wrapper that keeps the path-inference and private-default
steps. The module docstring already frames itself as "the idiom every shirabe
skill uses"; parameterizing it makes header number three cheap instead of
expensive. Nothing in CLAUDE.md's "CLI Surface" section forbids this — that
section forbids *authoring* subcommands (`shirabe brief`, `shirabe prd`) and
explicitly blesses "deterministic validation/feedback" in compiled code. It is
silent on config, and a validation input is not a renderer.

**Discoverability.** Best of the four. The adopter opens the file they already
have and already edit, and adds a ninth header beside the eight already there.
The remediation sentence writes itself and points at a file that exists.

**Wrinkles.** The declaration line is itself prose that R3/R4 will scan, and it
contains the very terms being declared — but it self-suppresses, so it is
consistent, and it adds a handful of words to CLAUDE.md's own frequency
denominator. Immaterial.

### B — a CLAUDE.md header naming a path

`## Prose Vocabulary: .shirabe/vocabulary.txt`, following
`## Release Notes Convention: docs/guides/`.

**R16.** Same walk finds the header in all four consumers, then every consumer
must resolve and read a second file. The validator can. The drafting skill
gets the *pointer* for free in context but not the *terms* — it must issue a
Read, which is one more instruction that can be omitted from a skill and one
more way the two consumers drift.

**Scale.** Unbounded, which is B's only genuine advantage over A, and the
analysis above says the bound A hits is a bound adopters do not reach.

**R10.** Identical to A.

**Precedent cost.** Same reader as A, plus path resolution, plus a new failure
mode A does not have: a **dangling pointer**. If the header names a path that
does not exist, the repo silently gets R17 day-zero behavior — full firing —
while believing it has declared. FC-CONVENTIONS already validates that the
Release Notes path resolves, so B inherits an obligation to do the same, which
means a new finding code or a new arm on an existing one. Two files to create,
two to keep in sync, one more thing to get wrong.

**Discoverability.** Good at the header, then a hop. An adopter reading a wall
of findings sees "add a header" and then "and create a file."

### C — a dedicated dotfile (`.shirabe.toml` / `.shirabe-vocab`)

**R16.** Needs repo-root discovery, which shirabe does not have — so it needs
the same ancestor walk A and B use, built new for a different filename. The
walk is a shared cost, not an A/B advantage; C simply pays it without reusing
the code. The drafting skill gets nothing automatically and must be told the
file exists.

**Scale.** Unbounded, and a structured format buys room for the reject
direction and per-rule control if those ever land — the strongest forward-looking
argument any option has.

**R10.** Fine if implemented as a walk; fails immediately if implemented as
"load config once at startup," which is the natural way people write config
loaders and the trap the two-repo acceptance criterion exists to catch.

**Precedent cost.** Highest. shirabe has no config file today — the four root
dotfiles are another tool's (`.tsuku.toml` is tsuku's project-tools file),
release scripts (`.release/`), git plumbing, and the plugin manifest
(`.claude-plugin/`). None is a shirabe-validate input. TOML also costs a new
dependency: `shirabe-validate` depends only on `regex` and `saphyr`, with no
`toml` crate and no `serde` anywhere in the workspace. (YAML via the existing
`saphyr` would avoid that, at the cost of picking YAML for a two-word list.)
Introducing the config-file concept for a comma-separated list of up to 47
words is the largest conceptual addition for the smallest payload.

**Discoverability.** Worst of the four for a first-time adopter, best for
someone who already expects tools to have dotfiles. Nothing in the repo hints
it exists.

### D — a fixed conventional path (`.shirabe/vocabulary.txt`), no header

**R16.** Same walk-for-a-filename as C. One term per line, zero parse
dependency — the cheapest reader of the four to *write*. Drafting skill: worst
case, because there is neither a pointer in context nor a config file a
convention-aware reader would look for; every drafting skill needs prose
telling it to check a path that may not exist.

**Scale.** Unbounded and the most readable at scale (one term per line, diffs
cleanly, comments possible).

**R10.** Same as C.

**Precedent cost.** Introduces both a config-file concept *and* an
undiscoverable convention, and splits the answer to "where does a repo declare
things to shirabe?" into two places with no cross-reference. Convention over
configuration works when the convention is famous; this one would have exactly
one implementation and one document.

**Discoverability.** Depends entirely on documentation being read, which R17's
framing ("writing a declaration is an adopting repository's first action")
specifically cannot rely on for a repo that just got a wall of findings.

## Recommendation

**Option A: a new parsed CLAUDE.md header, `## Prose Vocabulary: <terms>`,
comma-delimited, resolved by generalizing `resolve_doc_visibility` into a
key-parameterized ancestor walk.**

Concretely:

- **Reader.** Refactor `visibility.rs` into `resolve_claude_md_header(path,
  key) -> Option<String>` carrying steps 1-3 of the algorithm above (canonicalize,
  walk up from the file's directory, `CLAUDE.local.md` before `CLAUDE.md`,
  header-less files transparent, first hit wins). `resolve_doc_visibility`
  becomes that call plus its path-inference and private-default tail;
  `resolve_prose_vocabulary` becomes that call plus a comma split.
- **Grammar.** Split on commas, trim, ASCII-lowercase, drop empties. Commas
  rather than whitespace because `align with` is a rule-list entry. Sanity-cap
  the value (the `--custom-statuses` 64 KiB cap at `main.rs:1379` is the
  precedent for capping an adopter-supplied list at all).
- **Matching.** Case-insensitive whole-term match, so declared `tier`
  suppresses `Tier` (R8) and does not suppress `tiered` (R8) — `tier/tiered` is
  one row on the rule table but two independent terms, and a repo wanting both
  declares both.
- **Default.** Absent header means the empty set. Nothing suppressed, which is
  R17 verbatim. No path inference, no fail-safe inversion; unlike visibility
  there is nothing to fail safe *toward*.
- **First-declaration-wins, not merge up the chain.** Mirrors the proven code,
  keeps R10 crisp, and stops an adopter's effective vocabulary from depending
  on directories above their repo root that they may not control. A repo that
  declares anything states its vocabulary completely.
- **No run-global flag.** Per-file resolution only. `--visibility` is the
  cautionary tale: it exists, the reusable workflow always passes it, and it
  switches per-file detection off for the whole run.
- **Unknown declared terms are not an error.** A term that no rule fires on
  suppresses nothing and is harmless. Erroring on it (the `--check` unknown-code
  precedent at `main.rs:526-534`) would break R9 outright: when shirabe *removes*
  a word from the rule list, every repo that declared it would start failing,
  which is the opposite of "receives removals with no action on its part."
  Silent acceptance, or notice at most.
- **shirabe declares its own** `tier, journey` in its own CLAUDE.md, next to the
  eight existing headers. That is R10 satisfied by construction, and it is also
  the working example every adopter reads.

**Strongest counter: a list-valued heading breaks the convention that every
CLAUDE.md header is a single scalar, and it puts structured data into a
human-and-agent prose document that is not a config file.**

It is a real break and the DESIGN should say so rather than pretend the header
convention absorbs it — the research's Implication 4 is right that this is a new
shape. Three things answer it. First, the payload is bounded by the rule list at
47 and sits at 2-10 in practice, so the "unreadable heading" failure is a
hypothetical adopter the rulebook currently makes impossible. Second, the
alternatives trade that break for a worse one: B adds a dangling-pointer failure
mode and a second file, C adds a config-file concept plus a dependency, D adds a
config-file concept plus an invisible convention — each a larger addition than
widening one header's value grammar from scalar to comma-list. Third, and
decisively, the counter argues about the shape of the declaration while R16
argues about who can *read* it, and CLAUDE.md is the only file in an adopter's
repo that is already in the drafting agent's context. Every other option makes
the drafting consumer do work that a skill author can forget to specify, which
reintroduces the validator/skill split this whole PRD exists to close.

If a repo ever does exceed a readable line, the escape is additive and does not
change any consumer: teach the same header's value grammar to accept a path
(Option B) alongside inline terms, disambiguated by a `/` or a file extension.
That is a later one-branch change to one reader, not a migration. Deferring it
is safe; building it now is speculative.

## Confidence

**High** on the mechanism (CLAUDE.md header read by a generalized ancestor
walk) — R16's four-consumer trace is empirically verified end to end, R10 is
structurally guaranteed by the CI checkout layout, and the code being
generalized already solves the nested-workspace, `.local` override, and
transparent-header-less-file cases.

**Medium** on inline-versus-path for the value. The bound that makes inline
safe (47) is today's rule list, and R6's frequency rules plus any future
expansion move it. The mitigation is that widening the grammar later is
additive.

**Medium-low** on first-wins-versus-merge. First-wins mirrors the proven code
and is the safer default, but it is genuinely a choice rather than a
consequence, and a monorepo host wanting an org-wide baseline vocabulary is a
plausible future request that first-wins forecloses without a second mechanism.
