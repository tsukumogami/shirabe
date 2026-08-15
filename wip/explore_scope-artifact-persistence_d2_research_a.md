# Research A: What actually happens to the bytes

Empirical study of artifact persistence across `/scope` -> `/execute` -> squash-merge
in `tsukumogami/shirabe`. All git and `gh` commands below were executed; output is
verbatim unless marked otherwise.

## Research conducted

- `gh auth status` — authenticated as `dangazineu`, scopes `admin:org, gist, repo`.
  Remote `git@github.com:tsukumogami/shirabe.git` reachable. **Nothing in this report
  is unverified for network reasons.**
- Repo merge settings via `gh api repos/tsukumogami/shirabe`.
- Fresh `git clone` into `/tmp/shirabe-clonetest` and `git clone --mirror` into
  `/tmp/shirabe-mirror.git`, used as the ground truth for "what survives in a clone".
- `git ls-remote origin 'refs/pull/*'`, `git fetch origin refs/pull/271/head`.
- Real merged `/scope` run: PR #271 (branch `docs/charter-scope-parity`, squash
  commit `9f45603`). Real in-flight `/scope` run: PR #278 (branch
  `impl/execute-single-pr-blockers`, the #270 run named in the brief).
- Read: `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-0-setup.md`,
  `phase-2-chain-orchestration.md`, `phase-3-exit-finalization.md`,
  `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`,
  `skills/execute/scripts/run-cascade.sh`, `references/pr-body-conformance.md`,
  `.github/workflows/pr-body.yml`, `.github/workflows/validate-pr-body.yml`,
  `docs/decisions/*`.

---

## Findings

### 0. The premise needs a correction first: fold-into-PLAN is not currently reachable

`skills/scope/references/phases/phase-2-chain-orchestration.md:424` carries the
absorbability mapping table. Verbatim:

| Hop | Absorbable |
|---|---|
| BRIEF to PRD | **Yes** |
| PRD to DESIGN | **No** |
| DESIGN to PLAN | **No** |

Stage 1 is a hard gate: "When the mapping is not total, the only available verdict
is `keep`." So today **the only absorb that can fire anywhere in `/scope` is
BRIEF -> PRD**, whose survivor (the PRD) is durable. No absorb into a DESIGN and no
absorb into a PLAN is reachable.

This is confirmed independently by the author's own commit message on
`6e1a22d` (branch `impl/execute-single-pr-blockers`, "docs(chain): drop the scoping
artifacts and move their reasoning into the code"):

> This is a stopgap for tsukumogami/shirabe#280: /scope currently cannot end a run
> below a permanent PRD and DESIGN, because only BRIEF->PRD passes the absorbability
> test and the PLAN is deleted at finalization. For a two-defect bug fix that floor
> is wrong, so the artifacts are removed by hand here rather than left as an example
> of the problem.

**Decision-relevant consequence:** "a fold into the PLAN is irreversible" describes a
*prospective* capability the decision would be creating, not a live loss path. There
is no accumulated damage to remediate; the question is purely what to build alongside
the new hop. Also note the author's hand-rolled workaround was *not* a fold into the
PLAN — it was moving the reasoning into **code comments**, a durable surface.

### 1. Branch and PR topology: SAME branch, SAME PR is the designed shape

**`/scope` never pushes and never opens a PR** (non-coordinated case). `grep -rc
'git push' skills/scope/` returns zero occurrences. The only `gh pr create` in
`skills/scope/` is `SKILL.md:214`, and it is scoped to the **coordination PR** for
`execution_mode: coordinated`. `/scope` commits to whatever branch HEAD is on and
stops. `phase-0-setup.md:281` refers to "the pushed feature branch" as an assumption
about the environment, not an action `/scope` performs.

**`/execute` adopts the branch it finds.** `skills/execute/koto-templates/execute.md:297`,
verbatim:

> On the `override` path, the branch you stay on (the author's or `/scope` branch —
> NOT `impl/<slug>`) is the **settled branch**, and the open PR on it (including a
> `docs/<topic>` scoping PR) is **ADOPTED** as the home PR: `/execute` does not open
> a second PR and does not link a distinct one.

`skills/execute/SKILL.md:174` says the same. So one branch, one PR is designed, not
accidental. Empirically confirmed on **two independent runs**:

```
$ git log --oneline origin/impl/execute-single-pr-blockers --not origin/main
6e1a22d docs(chain): drop the scoping artifacts and move their reasoning into the code
d869c66 docs(chain): finalize the execute-single-pr-blockers chain
dba94dc feat(ci): reject shell-style interpolation in koto-executed template fields
a9b59ca chore(ci): stop installing bash 5 on the macOS plan-scripts runner
f131d8c fix(execute): resolve the worktree-discipline gate's plan slug through koto
3612edd fix(plan): run plan-to-tasks.sh under bash 3.2
54f546c chore(wip): clean up scope state for execute-single-pr-blockers
0655335 docs(plan): decompose the /execute single-pr blocker fixes into four issues
cb7bc76 docs(design): choose mechanisms for the /execute single-pr blocker fixes
3266780 docs(prd): scope the interpolation rule to koto-executed fields ...
fce1626 docs(prd): specify the /execute single-pr blocker fixes
594cc35 docs(brief): frame the /execute single-pr blockers
```

That is the #270 run: 5 chain-doc commits, 4 implementation commits, the finalization
commit, the wip cleanup, and the hand-fold — all one branch, all PR #278. PR #271
(branch `docs/charter-scope-parity`) has the identical shape and merged that way.

**Can `/scope` end with no branch/PR at all? Yes.** `/scope` makes local commits and
stops. If the author never pushes, nothing exists off the machine. And `/execute` days
later on a fresh branch is a supported entry: `skills/execute/SKILL.md:432` describes a
topic-keyed **home-PR lookup via `gh`** (invariant I-6) that finds an open PR by topic
and resumes on its branch. But that lookup only finds a **pushed, open** PR. If
`/scope`'s branch was never pushed, `/execute` on a fresh branch falls through to
"fresh chain" and the two runs are unrelated.

Note the asymmetry in the two skills' resume guarantees: `/scope` explicitly does
**not** satisfy I-6 (`SKILL.md:778`: "The substrate does NOT satisfy invariant I-6
(cross-branch resume); resume on a different branch starts a fresh chain"), while
`/execute` does. `/scope`'s state is branch-local `wip/` only.

### 2. Where the deleted bytes end up — THE DECISIVE TEST

`/execute`'s cascade deletes the PLAN at `skills/execute/scripts/run-cascade.sh:860`:

```bash
if git rm -f "$PLAN_DOC" > /dev/null 2>&1; then
```

Repo settings, verified:

```
$ gh api repos/tsukumogami/shirabe --jq '{...}'
{"archived":false,"delete_branch":true,"fork":false,"merge":false,"rebase":false,
 "squash":true,"squash_message":"PR_BODY","squash_title":"PR_TITLE"}
```

Squash-only, `PR_BODY` as the message source, `delete_branch_on_merge: true`. All
three brief claims confirmed.

#### 2a. A fresh clone: the deleted document is COMPLETELY GONE

PR #271 is a real merged `/scope`+`/execute` run whose finalization deleted
`docs/plans/PLAN-chain-cardinality.md` in commit `6b68712`. Fresh clone:

```
$ git clone git@github.com:tsukumogami/shirabe.git /tmp/shirabe-clonetest
$ git for-each-ref --format='%(refname)' | wc -l
38
$ git cat-file -e origin/main:docs/plans/PLAN-chain-cardinality.md
fatal: path 'docs/plans/PLAN-chain-cardinality.md' does not exist in 'origin/main'
ABSENT on main
$ git cat-file -e bd2495b            # PR271 branch tip
fatal: Not a valid object name bd2495b
ABSENT in fresh clone
$ git cat-file -e 6b68712            # the deleting commit
fatal: Not a valid object name 6b68712
ABSENT in fresh clone
$ git log --all --oneline --diff-filter=AD -- docs/plans/PLAN-chain-cardinality.md
(no output)
```

`--all` across every ref in the clone finds no trace. The squash commit `9f45603` has
one parent on `main` and does not reference the branch's commits; the branch was
deleted at merge. **From a normal clone the content is unrecoverable.**

#### 2b. GitHub's `refs/pull/<N>/head` DOES survive branch deletion — full recovery

```
$ git ls-remote origin 'refs/pull/271/*'
bd2495b462eb42655f6e21ca263b67c6be4aac81	refs/pull/271/head

$ git ls-remote origin 'refs/pull/260/*'
d7aa62604f9719a870d40133f830c12a17e26a36	refs/pull/260/head

$ git ls-remote origin 'refs/pull/270/*'
(empty)
```

(#270 is empty because 270 is an **issue**, not a PR — `gh pr view 270` returns
"Could not resolve to a PullRequest". The brief's "#270 run" is the issue; its PR is
#278.)

Recovery from the fresh clone, which had none of these objects:

```
$ cd /tmp/shirabe-clonetest
$ git fetch origin refs/pull/271/head
From github.com:tsukumogami/shirabe
 * branch            refs/pull/271/head -> FETCH_HEAD

$ git show 6b68712^:docs/plans/PLAN-chain-cardinality.md | head -12
---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: Chain Cardinality
issue_count: 12
upstream: docs/designs/DESIGN-chain-cardinality.md
---

# PLAN: Chain Cardinality

## Status
...
$ git show 6b68712^:docs/plans/PLAN-chain-cardinality.md | wc -l
288
```

**The full 288-line PLAN, deleted at finalization and absent from every clone, is
recovered byte-exact by one `git fetch`.** This is the single most decision-relevant
fact: recovery cost is one command, given the PR number.

#### 2c. But `refs/pull` is NOT durable in the senses that matter

Three separate limits, all verified or structural:

- **Mirrors do not carry it.**
  ```
  $ git clone --mirror git@github.com:tsukumogami/shirabe.git /tmp/shirabe-mirror.git
  $ git --git-dir=/tmp/shirabe-mirror.git for-each-ref 'refs/pull/*' | wc -l
  0
  ```
  A `--mirror` clone — the standard "take everything" backup — captures **zero**
  `refs/pull` refs. So the surface survives neither a mirror, a fork (a fork gets its
  own PR namespace), nor a migration off GitHub.
- **It is GitHub-server-side only.** It exists because GitHub keeps the objects
  reachable in its internal repo network. It is not part of the git object model the
  repo owns, it is not in the archive tarball, and GitHub documents no retention
  guarantee for it. It can be garbage-collected; there is no contract that it will not.
- **Discoverability is actually fine, though.** Bulk enumeration works:
  ```
  $ git ls-remote origin 'refs/pull/*' | wc -l
  142
  ```
  Someone who does not know the PR number can list all 142 heads and grep them. So
  discoverability is not the weak link — **portability and retention are.**

**Summary of 2:** the content is recoverable at near-zero cost *right now, from
GitHub, by anyone with repo access*, and irrecoverable from any clone, mirror, fork,
or post-GitHub copy of the repo. It is best described as a **convenience escrow, not
an archive.**

### 3. The PR body as a durable surface — both halves of the prior research confirmed

#### 3a. Part 1 lands on main verbatim; Part 2 is trimmed

```
$ gh pr view 271 --json body --jq '.body' | wc -l
115
$ gh pr view 271 --json body --jq '.body' | grep -n '^---$'
30:---
$ git log -1 --format=%B 9f45603 | wc -l
51
```

The body is 115 lines with its single `---` at line 30. The squash commit body on
main is exactly Part 1 (lines 1-29), verbatim in content — the 51 vs 29 line count is
GitHub's dialog re-wrapping at a narrower width, not different text. I compared the
two texts directly: identical prose, four paragraphs, character for character modulo
wrapping. Part 2 ("## What shipped, in dependency order" and everything below) does
not appear in the commit.

#### 3b. The trim is a human, not automation — confirmed

```
$ grep -rn 'gh pr merge' --include='*.md' --include='*.sh' --include='*.yml' .
(no output outside wip/)

$ git log -1 --format='%an|%ae|%cn|%ce' 9f45603
Dan Gazineu|danielgazineu@gmail.com|GitHub|noreply@github.com
```

No merge automation exists anywhere in the repo. Committer is `GitHub
<noreply@github.com>` — the web merge button. With `squash_merge_commit_message:
PR_BODY`, GitHub pre-fills the **entire** body including Part 2; the fact that the
landed message contains only Part 1 means a human deleted Part 2 in the dialog.
**There is no mechanism enforcing the trim.** If the human forgets, Part 2 lands on
main too (which incidentally makes Part 2 a *sometimes*-durable surface, i.e. one you
cannot rely on either way).

#### 3c. Size and shape limits on Part 1

**No length limit exists.** `grep -iE 'length|max|limit|chars|lines|wc -c|wc -l'`
across `.github/workflows/pr-body.yml` and `references/pr-body-conformance.md` matched
only one line, and it was about co-author lines. The four gated checks are PB1-PB4
(`references/pr-body-conformance.md:38-76`), all structural:

- **PB1** — Conventional Commits title.
- **PB2** — exactly one top-level bare `---`, non-empty Part 1.
- **PB3** — no AI-attribution footer (`Co-Authored-By:` to Claude/Anthropic,
  "Generated with").
- **PB4** — **no markdown ATX heading in Part 1.** This is the binding constraint for
  the idea. Part 1 must be *prose*: no `## Decision Drivers`, no `### Rejected
  Alternatives`. The stated rationale (line 64-67): "A clean commit message is
  [prose]... heading structure lands permanently on `main`."

Also relevant: `pr-body-conformance.md:49` requires issue references (`Fixes #N`) to
live in **Part 2**, so Part 1 cannot carry a pointer back to the issue.

**Could a distilled DESIGN contribution of 40-120 lines live in Part 1?** Mechanically
yes — nothing checks length, and there is precedent at roughly that scale: PR #271's
Part 1 is 29 lines of dense four-paragraph prose that reads well as a commit message.
Scaling to 40-60 lines of prose is plausible. **120 lines is not** — that is a
commit message a reader must scroll several screens of, and PB4 forbids the headings
that would make it navigable, so it degrades into an undifferentiated wall. The
practical ceiling is where prose-without-headings stops being readable: call it
**40-60 lines, hard-capped by structure rather than by any check.**

The deeper problem: Part 1 is *append-only history*. Once merged it cannot be edited,
corrected, superseded, or linked-to-from-a-later-document by path. A DESIGN's
rejected-alternatives reasoning put there is durable but frozen and unaddressable.

### 4. Other durable surfaces already in the tree

| Surface | In every clone? | Survives squash-merge? | Written automatically today? |
|---|---|---|---|
| A surviving chain doc (`docs/{briefs,prds,designs}/`) | Yes | Yes (it is in the final tree) | Yes — this is what an absorb produces |
| Squash commit message Part 1 | Yes | Yes, by definition | Yes, but human-trimmed |
| **Code/config comments** | Yes | Yes | **No — but the author did it by hand on `6e1a22d`** |
| `docs/decisions/DECISION-*.md` | Yes | Yes | **Yes, but only on rejection/re-evaluation exits** |
| `docs/decisions/REJECTED-*.md` | Yes | Yes | Yes, by `/explore` Phase 5 |
| Git notes | n/a | n/a | **Not used at all** |
| Commit trailers | Yes | Only if in Part 1 | No convention beyond PB3's prohibition |
| `koto decisions record` | **No** | n/a | Yes, by `/work-on` |
| GitHub issue bodies | No | n/a | No (`/plan` creates issues in multi-pr mode) |
| GitHub releases | No | n/a | Yes, by `/release` — but version notes only |
| `refs/pull/<N>/head` | **No** | n/a (it *is* the escape hatch) | Automatic, by GitHub |

Details worth having:

- **`docs/decisions/`** — 6 files on disk, all `DECISION-<topic>-<date>.md` with
  `status:`/`decision:`/`rationale:` frontmatter (see
  `DECISION-populate-issueless-default-2026-08-10.md`). `/scope` Phase 3 writes them
  **automatically**, but only at the canonical path
  `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  (`phase-3-exit-finalization.md:84`) and only on the `re-evaluation` /
  `rejection` exits. None of the 6 on-disk files match that naming, so the
  `/scope`-automatic path has apparently **never fired in production**. `/charter`,
  `/explore` Phase 5, `/plan`, and `/roadmap` also reference the directory.
  **This is the closest existing thing to a home for a folded artifact's contribution:
  same directory, same frontmatter shape, same skill already writes there, in every
  clone, survives squash-merge, editable and linkable by path afterward.**
- **Git notes** — `git ls-remote origin 'refs/notes/*'` returns empty; `git notes
  list` empty. Zero use. Also: notes are not fetched by default clones, so they would
  inherit the same portability problem as `refs/pull`.
- **Trailers** — the only convention in the repo is PB3's *prohibition* on
  AI-attribution trailers. No `Refs:`, no `Signed-off-by`, no positive trailer
  convention exists to extend.
- **`koto decisions record`** — confirmed off-repo. `~/.koto/sessions` holds **1207**
  session directories on this machine. Machine-local, not in any clone, not pushed,
  not shared. Useless as a durable surface for repo content.

### 5. Is the durable-survivor fold actually reversible? No — and that reframes the whole asymmetry

The absorbed BRIEF's **original full text is not recoverable from a normal clone
either.** Same mechanism as section 2a: the BRIEF is created and `git rm`-ed on the
same branch, that branch squash-merges to a single commit whose tree contains no
BRIEF, and the branch is deleted. `git log --all` on a fresh clone finds nothing.

I checked whether the "created in an earlier PR, deleted in a later one" case (which
*would* leave the full text on main's history) actually happens:

```
$ git log --diff-filter=D --format='%h %ci %s' --name-only origin/main \
    -- docs/prds/ docs/briefs/ docs/designs/
2ebd974 2026-06-21 fix(execute): remove stray cascade DESIGN files ... (#210)
docs/designs/current/DESIGN-cascade-outline-ac-completeness.md
docs/designs/current/DESIGN-cascade-test-short.md
```

One occurrence in the repo's history, and it is a stray-file cleanup, not a fold. So
in practice **every chain document a `/scope` run absorbs is born and buried inside a
single PR branch and never touches `main` at all.** The distinction between "durable
survivor" and "ephemeral survivor" makes **no difference whatsoever** to whether the
absorbed document's original bytes are recoverable from a clone. Both are equally
gone. "Reversible" is the wrong word for both cases.

**The real asymmetry is not about the absorbed document. It is about where the
distillate lands.** In every fold, the original is equally unrecoverable; what differs
is the fate of the *carry-check output* — the compact section the absorb writes into
the survivor:

- **BRIEF -> PRD (durable survivor).** The distillate lands in
  `docs/prds/PRD-<topic>.md`, which merges to `main`, is in every clone, has a stable
  path, is addressable by `upstream:` frontmatter, is editable and correctable later,
  and can be found by someone who does not know the PR number. The carry check's
  itemized `carried: true` map has a live referent.
- **X -> PLAN (ephemeral survivor).** The distillate lands in a file
  `run-cascade.sh:860` deletes in the same PR. Nothing on `main` ever holds it. The
  carry check certifies a transfer into a container that is destroyed before the
  container itself reaches durable storage.

So the correct framing is: **a fold into a durable survivor converts an artifact into
a section of another artifact; a fold into the PLAN converts an artifact into
nothing.** The first is lossy-but-retained; the second is total. That is a difference
in *what the repository ends up holding*, not a difference in reversibility — nothing
here is reversible.

Two corollaries that bear on the decision:

1. Because the difference is *where the distillate lands* and not *what happens to the
   original*, a recoverability mechanism aimed at the deleted original (a git-notes
   archive, a `refs/pull` bookmark, a "recover this DESIGN" command) addresses the
   wrong half. What is actually missing in the PLAN case is a **durable destination**.
2. A gate on the PLAN fold and a durable destination for it are not the only two
   options. The absorbability table (section 0) already refuses PRD->DESIGN and
   DESIGN->PLAN for exactly the reason a gate would exist: no home for the content.
   The existing mechanism is *refusal by structural mapping*, evaluated per-section,
   and it is already stricter than a gate.

---

## Assumptions made

- **Assumed:** PR #271 and PR #278 are representative of how `/scope` and `/execute`
  runs are actually shaped. **If wrong:** the "same branch, same PR" topology finding
  weakens to "the two most recent runs happened to do this", though the two skill
  files independently state the adopt-don't-create rule, so the design intent stands
  regardless.
- **Assumed:** `refs/pull/<N>/head` retention on GitHub is best-effort with no
  documented guarantee, and can be garbage-collected. **If wrong** (i.e. GitHub
  guarantees it indefinitely): the surface becomes more attractive, but the mirror
  test still shows it is unportable, so it still cannot be the primary answer.
- **Assumed:** Part 1 of PR #271's body is character-identical to the squash commit
  body modulo line wrapping — I compared them by eye across four paragraphs rather
  than by a normalized diff. **If wrong:** only the precision of "verbatim" changes;
  the structural claim (Part 1 lands, Part 2 does not) is independently confirmed by
  the presence/absence of the "## What shipped" section.
- **Assumed:** the absence of `gh pr merge` anywhere in the repo, plus the `GitHub
  <noreply@github.com>` committer, means merges go through the web UI. **If wrong**
  (e.g. merges happen from a personal script outside the repo): the "human trims"
  conclusion could become "an untracked script trims", which is worse for
  reliability, not better.
- **Assumed:** the 6 files in `docs/decisions/` are all hand-authored or
  `/roadmap`-authored, inferred from none matching the `/scope` canonical naming.
  **If wrong:** the `/scope` Decision Record path has fired at least once and the
  precedent is stronger than reported, which only strengthens the case for
  `docs/decisions/` as the destination.

---

## Critical unknowns that remain

- **GitHub's actual retention policy for `refs/pull/<N>/head`.** I confirmed it
  survives branch deletion for PRs #260 and #271 (months old). I could not establish
  whether GitHub ever prunes these, or what happens on repo transfer between orgs.
  Any design that leans on this surface is leaning on undocumented behavior.
- **Whether `/execute` is ever run on a branch other than the `/scope` branch in
  practice.** The I-6 home-PR lookup exists precisely to handle that case, but I found
  no run in this repo where it fired. If cross-branch `/execute` is real and common,
  the "one PR holds everything" recovery story gets more complicated.
- **What the prospective PLAN-fold would actually distill.** The DESIGN->PLAN row is
  marked `No` because six required DESIGN sections have no home in a PLAN. Whether a
  "compact contribution section" can honestly represent Decision Drivers, Considered
  Options, Decision Outcome, Solution Architecture, Security Considerations and
  Consequences is a content question I cannot settle from the file system. The carry
  check's own rule — "Any `carried: false` aborts the absorb" — suggests it cannot.
- **Whether Part 2 has ever accidentally landed on `main`.** I did not audit every
  squash commit for a stray `## ` section. If it has happened, it would show that the
  human trim is unreliable in both directions, which matters if Part 1 is proposed as
  a load-bearing surface.
