# D4 Research: Is the existing corpus in scope for a retroactive sweep?

Measured 2026-08-14 against the workspace at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe280_take2-e297cbad/`.
All numbers below are from commands run on disk, not estimates, unless
explicitly labelled as an estimate.

## Research conducted

**Corpus inventory.** Enumerated every markdown file under any `docs/`
directory in all ten repo checkouts, then classified by filename prefix:

```
find <root> -path '*/docs/*' -name '*.md' -not -path '*/node_modules/*' \
     -not -path '*/.git/*' -not -path '*/.claude/worktrees/*' > /tmp/allmd.txt
grep -oE '[^/]+$' /tmp/allmd.txt | grep -oE '^[A-Z][A-Z]+-' | sort | uniq -c
```

The first pass reproduced the exploration's headline exactly (366 DESIGN, 107
PRD, 64 BRIEF = 537). It was wrong: it swept in
`public/shirabe/crates/shirabe/tests/fixtures/{transition,absorption}-golden/corpus/**`,
which contains synthetic `docs/designs/DESIGN-x.md` trees. Excluding
`/tests/fixtures/` (`grep -v '/tests/fixtures/'`, 44 files removed) gives the
real corpus: **352 DESIGN, 103 PRD, 61 BRIEF = 516**, plus 11 PLAN, 15 ROADMAP,
14 SPIKE, 7 VISION, 6 ADR, 6 DECISION, 4 STRATEGY.

The fixtures are also where the exploration's "smallest DESIGN is 10 lines"
signal would have come from — every sub-60-line "DESIGN" on disk is a golden
fixture. Real minimum DESIGN is 81 lines.

**Graph reconstruction.** Parsed YAML frontmatter from all 823 doc files,
resolved every `upstream:` value three ways (relative to the citing file,
relative to its repo root, and by basename within the same repo), and inverted
the edge set to get children. Scripts: `/tmp/corpus_analysis.py`,
`/tmp/foldability.py`, `/tmp/ratio.py`.

**Full referrer map.** Walked all ten repos (12,586 text files across `.md`,
`.rs`, `.go`, `.sh`, `.yml`, `.toml`, `.json`, `.py`, `.ts`, `.js`) matching
both `docs/…/X.md` paths and bare `DESIGN-…\.md`-style basenames, then
classified each referring file by zone (docs prose / skills / code / CI /
scripts / other). Scripts: `/tmp/refscan.py`, `/tmp/refscan2.py`,
`/tmp/sweep_sim.py`.

**Validator behaviour, executed not read.** Ran the installed
`shirabe v0.16.0` binary against the live tree:

```
shirabe validate --visibility=public --lifecycle . --mode=ready    # exit 2
shirabe validate docs/briefs/BRIEF-lifecycle-passing-state-validation.md \
                 docs/briefs/BRIEF-cascade-outline-ac-completeness.md  # exit 2
```

**Git archaeology** in the shirabe repo (the only one reachable — see
Assumptions): located the commit that stranded the live dangling refs, and
computed per-document first-commit / last-commit / commit-count for all 125
shirabe BRIEF+PRD+DESIGN files (`/tmp/gitdocs.sh`, `/tmp/agestats.py`).

**Source reading.** `crates/shirabe-validate/src/lifecycle.rs` (referrer map,
L02 orphan rule), `src/finalize.rs` (who calls the referrer map),
`src/transition.rs` (the existing archive move),
`docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`,
and the `validate-docs.yml` / `lifecycle.yml` workflows in each repo.

---

## Findings

### 1. There is almost nothing to fold into. A DESIGN sweep is 96% pure delete.

The forward operation folds an upstream into a *surviving downstream*. Measured
per hop, asking whether the hop's downstream type still exists on disk:

| Hop | n | Downstream exists | No downstream at all |
|---|---|---|---|
| BRIEF → PRD | 61 | **60 (98%)** | 1 |
| PRD → DESIGN | 103 | **94 (91%)** | 9 |
| DESIGN → PLAN | 352 | **8 (2%)** | **338 (96%)** |

What actually points back at a DESIGN, across the whole workspace: 8 PLANs,
4 DESIGNs, 4 BRIEFs, and for 338 of them, nothing.

Per repo, DESIGNs with any downstream document at all: tsuku 4/147, niwa 0/56,
shirabe 2/48, koto 2/40, private/tools 6/47, private/vision 0/14.

The reason is structural, not accidental: the PLAN is deleted at finalization by
design (`transition.rs`: PLAN's lifecycle is `Draft → Active → Done → DELETED`,
"Done is a terminal status; the PLAN file is deleted from the tree at this
point"). Eleven PLANs survive workspace-wide, and ten of those are in-flight
(Draft or Active). So the DESIGN→PLAN hop's fold target is *guaranteed absent*
for every completed chain.

**The asymmetry the decision context flagged is real and it is the dominant
case.** Retroactively, BRIEF→PRD and PRD→DESIGN are genuinely foldable — 154 of
164 upstream documents have a live target. DESIGN→PLAN is not foldable at all:
338 of 352 DESIGNs can only be discarded, never distilled into anything. That
runs straight into the exploration's own constraint that reduction stays a
content-preserving move and there is no discard verdict.

### 2. Inbound reference density: 43% of the sweep candidates are cited by
something that survives, and no validator checks any of those citations.

Across the corpus, by cited type:

| Type | n | cited by anything | cited from outside `docs/` | uncited by anything |
|---|---|---|---|---|
| DESIGN | 352 | 211 | 68 | **141** |
| PRD | 103 | 100 | 5 | 3 |
| BRIEF | 61 | 61 | 4 | 0 |
| PLAN | 11 | 5 | 0 | 6 |

Total referrer edges by zone: docs prose 1,022, other 115, CI/.github 95, code
89, skills 49, scripts 49.

Per-repo DESIGN citation status:

```
private/tools    47  uncited=12  docs-only=30  outside-docs= 5
private/vision   14  uncited= 5  docs-only= 3  outside-docs= 6
public/koto      40  uncited=18  docs-only=17  outside-docs= 5
public/niwa      56  uncited=23  docs-only=27  outside-docs= 6
public/shirabe   48  uncited=19  docs-only=16  outside-docs=13
public/tsuku    147  uncited=64  docs-only=50  outside-docs=33
```

**Simulated the sweep.** Deleting all 338 no-downstream DESIGNs and re-scanning
the surviving tree:

- **147 of the 338 (43%) are cited by a file that survives.**
- 191 are cited by nothing surviving — genuinely clean deletes.
- **201 distinct surviving files would be left holding a broken reference**,
  111 of them outside `docs/`.
- Broken-edge breakdown: docs prose 160, code 66, other 48, skills 25, CI 9,
  scripts 3.

Named examples of surviving non-doc files that would break:
`private/tools/plugin/tsukumogami/skills/design-doc/SKILL.md`,
`.../skills/pr-creation/SKILL.md`, `.../skills/upstream-context/SKILL.md`,
`public/koto/plugins/koto-skills/hooks/session-start-workflows.sh`,
`private/dot-niwa-overlay/.niwa/CLAUDE.overlay.md`,
`private/tools/scripts/ci/tests/test-implementation-issues.sh`.

**Not one of those 201 breaks would be caught.** Only `upstream:` frontmatter is
validated (rule R6 — verified live: `[R6] upstream "…" does not exist on disk`,
exit 2), and by construction the 338 candidates have zero inbound `upstream:`
edges. Prose, skill, code, CI, and script citations have no rule anywhere.

The exploration's "73 files cite a PRD path" figure is repo-local; in this
worktree the count is **104** files matching `docs/prds/PRD-` outside fixtures.

**`build_referrer_map` is wired, but not to anything useful here.** Contrary to
the decision context, it *is* called — `finalize.rs:506`, once per
`finalize-chain` invocation, to block retiring an ancestor that a non-terminal
document still names. It is not called from the consolidation path. Running it
corpus-wide is trivial (`build_referrer_map(&repo_root)` takes a repo root and
walks the whole tree), but it would be near-useless for a sweep: it reads only
`upstream:` edges, so it sees 118 of 352 DESIGNs' inbound links and none of the
prose/code/skill/CI references that are 100% of the actual sweep blast radius.
**A full referrer map today would require new machinery** — a prose-path and
bare-basename scanner across non-doc file types, which is exactly what
`/tmp/refscan.py` prototypes and nothing in `shirabe-validate` does.

### 3. Lifecycle state: the corpus is already at its terminal state, an
archive path already exists, and a prior decision already ruled on this.

Status counts (fixtures excluded):

```
DESIGN  Current 307   Superseded 22   Planned 13   <none> 6   Accepted 4
PRD     Done 87   Accepted 5   In Progress 4   Delivered 2   + 5 one-offs
BRIEF   Done 61
PLAN    Draft 6   Active 4   Done 1
```

**Yes, there is a status meaning "the work shipped and this is history":** it is
`Current` for DESIGN and `Done` for PRD/BRIEF. 307/352 DESIGNs (87%), 87/103
PRDs, and 61/61 BRIEFs are already sitting in it.

**Retire-without-delete tooling already exists and is tested.**
`shirabe transition <design> Superseded --superseded-by <x>` git-mv's the file
to `docs/designs/archive/` (`transition.rs:453`, tests at 2107-2146). 22
documents live there today (niwa 9, tsuku 7, koto 4, tools 1, vision 1). The
transition *requires* a successor pointer, which is precisely the thing a
retroactive judgment on an orphan DESIGN cannot supply.

**The workspace has already asked and answered the question the sweep argument
says it never asked.** `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
(status Accepted) rules that "orphans at the artifact's target state (BRIEF
Done, PRD Done, DESIGN Current) pass," and calls a DESIGN at `Current` whose
PLAN was deleted post-completion **"the post-completion healthy case."** Its
rationale explicitly rejected orphan-strict because it "fails 28+ docs on day
one." That is a deliberate, recorded, still-Accepted judgment that these
documents earn their place — which contradicts the premise that they persist
only because nothing ever asked.

**Prior mass migration and what it broke.** There was no single Accepted→Current
migration; the moves were incremental, one chain at a time, inside
`chore(cascade): post-implementation artifact transitions`-style commits
(`git log --all --diff-filter=R -- 'docs/designs/**'` shows 11 such renames).
The one that stranded references is **`a133581` "chore(plan): verify-then-delete
roadmap-plan-standardization (#190)", 2026-06-11**. It touched four files: moved
`DESIGN-roadmap-plan-standardization.md` into `current/`, deleted
`PLAN-roadmap-plan-standardization.md`, and updated the two docs *in its own
chain*. It did not touch the five briefs from *other* chains created 2026-06-05
to 06-07 that pointed at the moved DESIGN and the deleted PLAN. Those five have
been broken for **64 days** and are still broken today:

```
BRIEF-lifecycle-passing-state-validation.md   -> docs/designs/DESIGN-roadmap-plan-standardization.md
BRIEF-legend-vs-classdef-reconciliation.md    -> docs/designs/DESIGN-roadmap-plan-standardization.md
BRIEF-table-diagram-reconciliation.md         -> docs/designs/DESIGN-roadmap-plan-standardization.md
BRIEF-cascade-outline-ac-completeness.md      -> docs/plans/PLAN-roadmap-plan-standardization.md
BRIEF-single-pr-plan-validation.md            -> docs/plans/PLAN-roadmap-plan-standardization.md
```

Six more exist in the other repos (11 workspace-wide), including
`public/tsuku/docs/designs/current/DESIGN-auto-install.md` and
`public/koto/docs/designs/current/DESIGN-migrate-koto-go-to-rust.md`.

**This is the precedent, and it scales badly.** A four-file cascade commit
stranded five references and went unnoticed for two months. A sweep is that
operation at 100x, against a reference surface that is 96% unvalidated.

### 4. The 3.5-DESIGNs-per-PRD ratio is a counting artifact. The real chain
ratio is 1.03.

```
repo             DESIGNs  PRDs  ratio | PRD-parent  other-upstream  NO-upstream
private/tools         47     2  23.50 |          1               1           45
private/vision        14     5   2.80 |          2               1           11
public/koto           40    14   2.86 |         18               2           20
public/niwa           56    33   1.70 |         32               0           24
public/shirabe        48    42   1.14 |         38               0           10
public/tsuku         147     7  21.00 |         15               2          130
TOTAL                352   103   3.42 |        106               6          240
```

Restricted to DESIGNs that are actually in a PRD chain: **106 chained DESIGNs /
103 PRDs = 1.03.**

The 3.42 is entirely produced by tsuku (21.0) and private/tools (23.5) — repos
that predate the PRD-first workflow and write standalone DESIGNs with no PRD
above them. 240 of 352 DESIGNs (68%) have no `upstream:` at all. In shirabe, the
repo where `/scope` actually runs, the ratio is 1.14 and 38/48 DESIGNs have a
PRD parent.

PRD fan-out confirms it: **94 of 103 PRDs have exactly one child DESIGN.** Only
three have more (2, 4, and 9 children). Nine have zero.

Topic redundancy is likewise absent. Sharing a slug prefix with a sibling in the
same repo: 56% at one token, **12% at two tokens**, 0.6% at three. There is no
population of near-duplicate designs.

**So the corpus does not contain a population of foldable documents.** It
contains a lot of independent design work, most of which never had a PRD to fold
and never had a PLAN to fold into.

### 5. Operational feasibility: six repos, all writable, none uniform, and CI
provides zero protection against a deletion PR.

All six doc-bearing repos are present with `.git` and writable `docs/`:
`public/{tsuku,koto,niwa,shirabe}`, `private/{tools,vision}`. (Four further
checkouts — `public/.github`, `public/dot-niwa`, `private/coding-tools`,
`private/dot-niwa-overlay` — carry no workflow artifacts, though
`dot-niwa-overlay` *cites* one.)

**Layouts differ.** `docs/designs/current/` + `docs/designs/archive/` in tsuku,
koto, niwa, shirabe. private/tools is mixed (37 in `current/`, 10 flat in
`docs/designs/`). private/vision is flat (`docs/designs/`, 6 files) and also
holds a parallel unmanaged tree at `private/vision/projects/**` containing more
DESIGN/PLAN/ROADMAP files that the doc-lifecycle tooling does not see.

**Validate tooling differs.**

| repo | doc workflows |
|---|---|
| shirabe | `validate-docs.yml`, `lifecycle.yml`, `validate-lifecycle.yml`, `validate-shirabe-docs.yml`, + 18 others |
| koto, niwa | `validate-docs.yml`, `lifecycle.yml` |
| tsuku | `validate-docs.yml` **plus legacy Go-era** `validate-design-docs.yml`, `validate-diagram-classes.yml`, `validate-diagram-status.yml` |
| private/tools | **only legacy** `validate-design-docs.yml`, `validate-diagram-*.yml` — no `validate-docs.yml`, no `lifecycle.yml` |
| private/vision | `validate-docs.yml` only |

**CI would not notice a sweep.** The shared `validate-docs.yml` is diff-scoped
and the workflow comment says so outright: "this workflow computes the changed-
file set with git diff and passes the paths positionally. The CLI never
discovers files itself." The diff filter is `--diff-filter=ACMR` — Added,
Copied, Modified, Renamed. **Deletions are excluded.** A PR that only deletes
documents produces an empty `FILES`, hits `::notice::No doc files changed in
this PR`, and exits 0.

The whole-tree gate does not close the gap either. `lifecycle.yml` runs
`shirabe validate --lifecycle .` with no `paths:` filter, but R6 (the
dangling-`upstream:` rule) is not part of the lifecycle check. Verified live in
this worktree:

```
$ shirabe validate --visibility=public --lifecycle . --mode=ready
::error file=docs/prds/PRD-koto-adoption.md,line=1::[L02] orphan PRD at status 'Accepted' ...
exit 2                              # one L02; the five R6 breaks are invisible

$ shirabe validate docs/briefs/BRIEF-lifecycle-passing-state-validation.md \
                   docs/briefs/BRIEF-cascade-outline-ac-completeness.md
::error ... [R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
::error ... [R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
exit 2                              # R6 only fires on files passed positionally
```

(Side finding worth surfacing separately: the whole-tree ready-posture gate
exits 2 on the current shirabe tree over `PRD-koto-adoption.md`.)

**A sweep is at minimum six PRs, and they are not independent.** Cross-repo
prose references exist in both directions —
`private/dot-niwa-overlay/.niwa/CLAUDE.overlay.md` cites a niwa DESIGN;
`private/vision/projects/tsuku/**` cites tsuku DESIGNs;
`private/tools/plugin/tsukumogami/skills/**` cites DESIGNs across repos. Repair
of a broken reference frequently lands in a *different repo* from the deletion
that caused it, so the PRs must be sequenced or land with knowingly-broken
intermediate states. No CODEOWNERS in shirabe; tsuku has one. Nothing found
blocks bulk deletion mechanically — the problem is that nothing detects it
either.

### 6. The corpus is young, lightly amended, and demonstrably read.

From shirabe git history (125 docs with history):

| | DESIGN (48) | PRD (42) | BRIEF (35) |
|---|---|---|---|
| exactly 1 commit | 31 (64%) | 28 (66%) | 26 (74%) |
| touched >30d after creation | 10 (20%) | 8 (19%) | 3 (8%) |
| create→last-touch span, p90 (days) | 71 | 102 | 11 |
| days since last touch, median | 68 | 68 | 68 |
| oldest document | 146 days | 136 days | 82 days |

**Nothing here is ancient.** The entire shirabe doc corpus is under five months
old. One in five DESIGNs was amended more than a month after it was written,
with a maximum span of 127 days — so documents do get revisited after their
implementation merged.

Being *read* shows up more strongly in citations than in edits. **68 DESIGNs
(19%) are cited from outside `docs/` — from skill prose, code comments, CI
config, and scripts.** Concrete instances:
`DESIGN-needs-design-lifecycle.md` cited from CI and scripts;
`DESIGN-dashboard-observability.md` from CI, scripts, docs and elsewhere;
`DESIGN-execute-skill.md`, `DESIGN-shirabe-scope-skill.md`,
`DESIGN-tiered-validation.md`, `DESIGN-batch-recipe-generation.md` from
`skills/`; `DESIGN-install-state-abstraction.md`,
`DESIGN-transition-script-consolidation.md`,
`DESIGN-tsuku-homebrew-dylib-chaining.md` from code only. The most-cited
documents in the workspace are `PRD-roadmap-plan-standardization.md` and
`DESIGN-roadmap-plan-standardization.md` (16 referrers each), then
`DESIGN-batch-child-spawning.md` and `VISION-tsukumogami.md` (15).

At the same time, **141 DESIGNs (40%) are cited by literally nothing.** So the
corpus is genuinely bimodal: a working-reference population and a
never-referenced population — but citation count is a proxy for reach, not for
worth, and nothing measured here distinguishes "nobody needed it" from "nobody
needed it yet."

**Baseline damage already present.** The prose citation surface is *already*
partly broken: filtering out obvious placeholder names (`DESIGN-foo.md`,
`-test`, `cascade-test`, eval fixtures), roughly 374 distinct document names are
cited in prose that resolve to no file on disk, across ~467 mentions. The
deleted `PLAN-roadmap-plan-standardization.md` alone is still named in 13 places.
That is the pre-existing class the constraint says a sweep must not enlarge.

### 7. Cost: 2.72M input tokens to read the corpus once; ~11M to judge it.

Real corpus (fixtures excluded), measured with `/tmp/cost.py`:

| type | n | lines | chars | words | input tokens (words × 1.33) |
|---|---|---|---|---|---|
| DESIGN | 352 | 228,886 | 11,602,717 | 1,546,359 | 2,056,657 |
| PRD | 103 | 49,743 | 2,707,236 | 393,996 | 524,014 |
| BRIEF | 61 | 13,397 | 693,964 | 104,756 | 139,325 |
| **total** | **516** | **292,026** | **15,003,917** | **2,045,111** | **~2,720,000** |

Per repo (DESIGN+PRD+BRIEF): tsuku 156 docs / ~797k tokens, shirabe 125 /
~603k, niwa 107 / ~570k, koto 58 / ~320k, private/tools 49 / ~260k,
private/vision 21 / ~170k.

Size distribution (lines): DESIGN min 81, p50 544, p90 1,128, max 4,400;
PRD min 150, p50 349, max 1,916; BRIEF min 112, p50 190, max 697. Median DESIGN
is ~5,800 input tokens on its own. **The exploration's conclusion that length is
useless as a proxy is confirmed and is stronger than stated** — the real floor
is 81 lines, not 10, and the p50 is 544.

**Defensible judgment cost.** A per-document verdict cannot be made from the
document alone; the judgment is "does this hold anything beyond its contribution
that compression would lose," which needs the document, its chain neighbours,
and evidence about who cites it. Budget per document: body ~5.8k + chain context
~6k + referrer evidence ~2k + skill instructions ~5k ≈ **19k input tokens**, plus
~2k reasoning output.

- 516 documents × 19k ≈ **9.8M input tokens**, ~1M output.
- Read-once floor: 2.72M input. With chain context only: ~6.8M.
- Bounded to shirabe alone: 125 documents, ~603k read-once, ~2.4M with judgment
  overhead.

The token bill is not the binding constraint (single-digit-hundreds of dollars
at frontier pricing, less if the reading agent is a smaller model). The binding
constraint is **516 irreversible content judgments that a human has to be
willing to accept unreviewed, or review**. At even one minute of human review
per document that is 8.6 hours of undivided attention across six repositories,
and the review has no undo once the PRs merge.

**One more cost the estimate has to carry:** the absorb procedure has never
executed once in this workspace. A sweep would be its first production use, at
516-document scale, with no worked example to calibrate against.

---

## Assumptions made

1. **Fixtures are not corpus.** I excluded 44 files under
   `crates/shirabe/tests/fixtures/` (14 DESIGN, 4 PRD, 3 BRIEF among them), so I
   report 516 rather than 537. *If wrong:* every count rises by ~4%, no
   proportion changes materially, and the "smallest DESIGN is 10 lines" reading
   returns — which would only strengthen the case that a size proxy is
   meaningless, since those files are synthetic.

2. **`upstream:` frontmatter is the only machine-readable chain edge.** I treated
   a document as having a downstream only when another document names it in
   `upstream:`. *If wrong* — if some other convention encodes lineage — the 338
   no-downstream DESIGNs may be understated as orphans. I checked the full
   frontmatter key census (`status` 617, `problem` 517, `decision`/`rationale`
   366 each, `upstream` 215, `schema` 199, `spawned_from` 23,
   `superseded_by` 17) and found no second lineage field with meaningful
   coverage, so I consider this low-risk.

3. **Basename resolution within a repo is a valid fallback for `upstream:`.**
   Where a written path did not exist I matched by basename inside the same
   repo. This is *generous* — it treats the five stale
   `docs/designs/DESIGN-roadmap-plan-standardization.md` refs as resolving.
   *If wrong:* the dangling count rises from 11 to something larger, and the
   graph gets sparser, which pushes the "nothing to fold into" finding further
   in the same direction.

4. **Git history is only available for shirabe.** This session is worktree-
   isolated; `git -C <other repo>` is refused by the sandbox. All recency,
   commit-count, and amendment statistics in Finding 6 are shirabe-only (n=125).
   *If wrong* — if tsuku's 147 DESIGNs are much older or much more frequently
   amended — the read-after-ship picture could shift substantially in either
   direction for the largest single population in the corpus. **This is the
   biggest measurement gap in this report.** Someone with unrestricted git
   access should re-run `/tmp/gitdocs.sh` in tsuku, niwa, koto and
   private/tools before any sweep decision is finalized.

5. **Text-file citation scanning approximates the true reference surface.** I
   scanned 12,586 files across 14 extensions in ten repos. GitHub issue bodies,
   PR descriptions, commit messages, and any external system are outside it.
   *If wrong:* the 201-broken-files figure is a **floor**, not a ceiling; the
   real blast radius is larger.

6. **Token estimate uses words × 1.33.** Standard for English markdown; actual
   tokenization of code-dense docs runs higher. *If wrong:* the ~2.7M read-once
   figure moves by maybe ±20%, which does not change any conclusion.

7. **CI behaviour is inferred from workflow YAML, not from an executed run.**
   I read `--diff-filter=ACMR` and the "CLI never discovers files itself"
   comment; I did not push a deletion PR to observe it. *If wrong* — if a
   repo-level branch protection or an unlisted required check catches deletions
   — the "CI provides zero protection" claim weakens, though the whole-tree
   lifecycle check demonstrably does not run R6, which I verified by execution.

---

## Clean summary of the problem and remaining critical unknowns

The author's argument for retroactive scope is that the corpus accumulated
because nothing ever asked whether documents should be deleted. Three
measurements cut against it.

**First, the forward mechanism cannot be run backward.** Consolidation is a
fold: an upstream is distilled into a surviving downstream. For BRIEF and PRD
that target exists (98% and 91%). For DESIGN — 352 of the 516 documents, 68% of
the corpus — it exists for **8 documents**. 338 DESIGNs have nothing downstream
at all, because the PLAN is deleted at finalization *by design*. A retroactive
pass over them is not the fold this work is building; it is a bare discard
verdict, which the exploration's own constraint ("reduction stays a
content-preserving move; no discard verdict") forbids.

**Second, the premise is factually contested by a still-Accepted decision.**
`DECISION-orphan-doc-passing-state-rule-2026-06-06.md` explicitly considered
whether a DESIGN at `Current` with no downstream PLAN is drift, and ruled that
it is "the post-completion healthy case." Rule L02 encodes that. 307 of 352
DESIGNs sit at exactly that state. The workflow *did* ask; it answered yes.
Reversing that is a legitimate move, but it is reversing a recorded decision, not
filling a gap where none was ever made — and the sweep argument as currently
framed does not acknowledge the decision exists.

**Third, the redundancy the argument rests on isn't there.** 3.5 DESIGNs per PRD
is a counting artifact of two repos that predate the PRD-first workflow
(tsuku 21.0, private/tools 23.5). Among DESIGNs actually in a PRD chain, the
ratio is **1.03**; 94 of 103 PRDs have exactly one child DESIGN; only 12% of
DESIGNs share even a two-token topic prefix with a sibling. The corpus is a lot
of independent design work, not a pile of duplicates.

Against that, the sweep's cost is concrete and its safety net is absent.
Judging 516 documents on content is ~2.7M tokens to read and ~11M to judge,
producing 516 irreversible calls. **43% of the DESIGN candidates are cited by a
file that survives**, leaving 201 surviving files holding broken references —
111 of them in skills, code, CI and scripts, none of which any validator checks.
The one existing precedent is a *four-file* cascade commit (`a133581`) that
stranded five references and went undetected for 64 days; the diff-scoped
`validate-docs.yml` excludes deletions entirely (`--diff-filter=ACMR`), and the
whole-tree lifecycle gate does not run R6 — verified by execution.

A less destructive path already exists and is tested:
`shirabe transition <design> Superseded` git-mv's into `docs/designs/archive/`,
where 22 documents already live. It preserves the file, so no reference breaks.
It requires a `superseded_by:` pointer, which an orphan DESIGN cannot supply
without inventing one.

### Remaining critical unknowns

1. **Git history for the other five repos** (Assumption 4). tsuku's 147 DESIGNs
   are 42% of the corpus and entirely unmeasured for age, amendment rate, and
   post-merge revision. This is the one gap that could genuinely move the
   answer, and it is cheap to close from an unrestricted shell.

2. **Whether the author intends to reverse
   `DECISION-orphan-doc-passing-state-rule`.** If terminal orphans stop being
   healthy, L02 changes, and 307 DESIGNs at `Current` become failures the moment
   the rule flips — independently of any sweep. That is a much larger blast
   radius than the sweep itself and nobody has costed it.

3. **Whether a discard verdict is being introduced at all.** The exploration
   holds two positions simultaneously: "every fold is a distillation, so loss is
   by design" and "reduction stays a content-preserving move; no discard
   verdict." Retroactive DESIGN deletion is only coherent under the first. That
   contradiction has to be resolved before the retroactive question can be
   answered, because 96% of the retroactive population sits exactly on it.

4. **What a full referrer map would cost to build.** Nothing in
   `shirabe-validate` scans prose, code, skills, or CI for document citations;
   `build_referrer_map` sees only `upstream:` edges and would report near-zero
   inbound links for precisely the 338 documents whose deletion breaks 201
   files. A prose/code referrer scanner is new machinery, not a wiring change.
   `/tmp/refscan.py` is a working prototype if someone wants a starting point.
