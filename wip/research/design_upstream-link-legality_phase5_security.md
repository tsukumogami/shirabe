# Phase 5 security review — upstream link legality

Scope: PRD-upstream-link-legality R1-R25 as refined by decision reports 1-4.
Five areas, each closed with one of: **CONCERN** (real, with mitigation),
**ACCEPTED** (risk stated and reasoned), or **N/A** (self-contained
justification).

---

## 1. Path handling on the new `/plan --upstream` surface — **CONCERN**

### What the siblings do, and what `/plan` has

`/plan` has no value-consuming flag today. `SKILL.md:249-270` parses six flags,
all boolean, then "Remove flags from arguments before using the remainder as the
document path." So the residue rule, the bare-flag rejection, and the
at-most-once rule are all new parse states for this skill, not a re-use of an
existing one.

The five siblings that already carry `--upstream` run a validation set that has
converged. The canonical statement is
`skills/scope/references/phases/phase-0-setup.md:132-207`; `/brief`'s is
`skills/brief/references/phases/phase-0-setup.md:139-197`; `/prd`'s is
`skills/prd/references/phases/phase-3-draft.md:37-52`. Composited:

1. Flag parsed **before** the positional slot is classified; the token following
   `--upstream` is consumed as the flag's argument and is never tested against
   the topic/path classifier. Bare `--upstream` (last token, or followed by a
   token starting with `--`) is a Phase 0 rejection. A second occurrence is a
   rejection.
2. Cross-repo `owner/repo:path` values are discriminated **first** and exempted
   from filesystem resolution (`crate::upstream::is_cross_repo_reference` is the
   Rust-side equivalent, `upstream.rs:133-141`).
3. Otherwise: resolve against the repo root, **resolve symlinks fully**, reject
   if the canonical path falls outside the repo working tree.
4. Exists and is readable.
5. Basename enforcement, inbound only — `ROADMAP-` here.
6. Not under `wip/`.
7. Tracked by git.
8. Public repo naming a private upstream: stop recording, omit, announce.

### The minimum `/plan` must adopt

All eight. Two of them are load-bearing in a way the others are not, and both
follow from the same fact: **`/plan` records, and `/brief` (under R13) no longer
does.** Decision 4's argument for relaxing `/brief` — a read-only input needs
path-safety checks but not durability checks — inverts cleanly here. `/plan` is
the skill that turns the value into a committed frontmatter field, so it inherits
the whole record-time set, including checks 7 and 8, which decision 4 correctly
drops and subsumes for `/brief`.

Check 3 (symlink resolution + bounds) is the one that answers the question as
posed. Without it, `--upstream docs/roadmaps/ROADMAP-x.md` where that path is a
symlink to `../../private-repo/docs/roadmaps/ROADMAP-x.md` canonicalizes outside
the tree, and a `../`-shaped value literally resolves outside it. Either reaches
the PLAN's committed `upstream:` field in a public repo.

### Is Phase 7's 7.4b hygiene re-check sufficient on its own? **No — four ways**

`skills/plan/references/phases/phase-7-creation.md:277-315` runs two greps:

```bash
git grep -nE 'wip/' -- 'docs/plans/PLAN-<topic>.md'
head -20 'docs/plans/PLAN-<topic>.md' | grep -E '^upstream:'
```

a. **It is blind to the shape R14 produces.** Decision 3 verified this against
   the real script: the second grep is scalar-shaped, so against a block
   sequence it prints the bare key `upstream:` and the instruction that follows
   ("the `upstream:` value must resolve") has no value to resolve. The step
   passes without checking either entry. Decision 3's required rewrite —
   enumerate `- ` items and inline `[a, b]` items and run `git ls-files` on each
   — is therefore a **security control**, not only a correctness fix, and should
   be labelled as one in the design.

b. **It runs too late to be the only gate.** 7.4b sits under "Common Steps (Both
   Modes)", after `7.1 Create GitHub Issues Using Batch Script`
   (`phase-7-creation.md:64-68`). In multi-pr mode a bad `--upstream` value is
   caught only after issues have been filed on GitHub — an externally-visible,
   hard-to-reverse side effect. Every sibling rejects at Phase 0, before any
   state file is written.

c. **A grep is not a canonicalization.** `git ls-files` on a tracked symlink
   under `docs/roadmaps/` succeeds; the symlink's target is never examined.
   Neither grep resolves symlinks or bounds-checks. The identical weakness is in
   the CI gate: `validate-plan.sh:149` builds `upstream_abs="${repo_root}/${upstream_val}"`
   by string concatenation with no canonicalization, and `[[ ! -f "$upstream_abs" ]]`
   follows symlinks. A `../`-escaping value is caught only incidentally, because
   `git ls-files --error-unmatch` refuses an out-of-tree pathspec.

d. **It has no basename rule and no visibility stop.** Line 312's "confirm
   visibility direction against cross-repo-references.md" is advisory prose
   addressed to an agent, not a check with a defined failure. See area 3.

### Mitigation

- Bind `/plan`'s Phase 0 to all eight checks above, worded from `/brief`'s
  `phase-0-setup.md:139-197` (decision 3 already recommends copying `/brief`'s
  residue-rule wording; extend that to the validation set).
- State in the design that decision 3's `validate-plan.sh` / 7.4b sequence
  enumeration is a security fix: without it, **every `/scope`-produced PLAN
  silently stops being upstream-validated by the one CI gate that does it**
  (`.github/workflows/check-plan-docs.yml:23`), and nothing says so.
- While `validate-plan.sh` is being changed anyway, canonicalize `upstream_abs`
  and reject an out-of-root or symlinked target rather than relying on
  `ls-files` to refuse it.

### What is *not* a concern here, and why it matters to say

A PLAN's `upstream:` value is the input to a `git rm -f`. The cascade walks it
(`skills/execute/scripts/run-cascade.sh:830-832` → `handle_roadmap` →
`handle_roadmap_deletion` → `git rm -f "$path"` at :563). That surface is
**already guarded at consume time**: `finalize.rs:680-685` calls
`validate_node_path` on every `upstream:` entry before any read or transition —
confinement to the repo root, regular file, and an explicit `symlink_metadata`
symlink rejection — and `run-cascade.sh:88-117` carries the same guard for the
PLAN doc itself. R14 moves the roadmap link from the BRIEF to the PLAN; it does
not create the delete surface, and it does not weaken it. The Phase 0 argument
above rests on the committed-field and fail-early grounds, not on a traversal
reaching `git rm`.

---

## 2. Interpolation — **CONCERN (small, but must be bound explicitly)**

### Where the value can reach a command

`/plan` emits shell in its phase prose. Tracing every site the flag's value can
reach:

- **7.4b, after decision 3's rewrite.** The step must run `git ls-files` per
  enumerated entry. The reference text today already says "If `git ls-files
  <path>` returns empty" (`phase-7-creation.md:308`) — unquoted, no `--`. That
  is the one new interpolation site, and it is currently specified in the exact
  shape the discipline forbids.
- **`validate-plan.sh:160`** — `git ls-files --error-unmatch "$upstream_val"`.
  Quoted, but **no `--` terminator**, so a value beginning with `-` is parsed as
  an option rather than a pathspec. Same at `:162`'s advice string.
- **7.5 status transition** — does *not* reach it. `shirabe transition <path>`
  runs only for `input_type: design|prd` on the positional source;
  `phase-7-creation.md:342-344` states roadmaps take no transition. Good.
- **`gh` issue bodies** — `create-issue.sh:244` uses `gh_args+=("--body" "$body")`,
  an argv array. No shell re-parse. Not a site.

### The discipline the design must bind

`/scope`'s Security Considerations states it in this repository's own terms and
the design should cite that sentence rather than re-derive it: the value is
"canonicalized to an absolute path and rejected if it resolves outside the
working tree, then **quoted and passed after `--`** in every command `/scope`
emits with it ... Validation alone is not the guarantee — the argument boundary
is." (`skills/scope/SKILL.md:738-748`.)

The Rust side already models this exactly: `checks.rs:846-847` runs
`.args(["ls-files", "--error-unmatch", "--", path])` — argv array, explicit
`--`. That is the shape to copy.

### Mitigation

- Every command `/plan` emits with the value: `git ls-files -- "<path>"`, quoted
  and after `--`. Write it that way in `phase-7-creation.md` step 7.4b rather
  than leaving `git ls-files <path>`.
- Add `--` to `validate-plan.sh:160`.
- State the `--` convention once in `/plan`'s own Security Considerations, as
  `/scope` does, since `--upstream` is the first author-supplied value `/plan`
  accepts that is not derived from a validated slug or a classified path.

---

## 3. The visibility boundary — **CONCERN**

### `/plan` has no private-upstream omission rule today

`grep -rn private skills/plan/` returns visibility *detection*
(`SKILL.md:280-292`), the governance-skill load, and two prose lines in Phase 7
(`:312`, `:412`, `:430`) about issue cross-references. There is no rule at the
frontmatter write site that says *omit `upstream:` when the target is private and
this repo is public*. `/brief`'s equivalent is explicit and at the write site
(`phase-2-draft.md:80-90`); `/scope`'s is check 3 at Phase 0.

The gap is not academic: `shirabe validate`'s resolution check returns nothing
for a cross-repo value (`checks.rs:834-836` `continue`s on `entry.cross_repo`),
so a public PLAN carrying `upstream: private-org/vision:docs/roadmaps/ROADMAP-x.md`
validates clean today and always will. Nothing downstream catches it either —
`finalize.rs:665-679` stops on a cross-repo node without reading it.

### Standalone `/plan` would skip a check the chain-driven path performs

Yes, and this is the sharpest form of the problem. Under `/scope`, check 3 runs
at `/scope`'s Phase 0: on a public repo with a private roadmap, `/scope` does not
write `consumed_upstream:` and does not pass the flag to any child
(`scope/phase-0-setup.md:183-188`). So the chain-driven `/plan` never sees the
value. Standalone `/plan --upstream private-org/repo:docs/roadmaps/ROADMAP-x.md`
in a public repo has no check anywhere and commits the path.

PRD R16 is the requirement that forbids this shape from the other direction: "A
skill records the same `upstream:` value when invoked standalone as it does when
a parent skill invoked it." A control that exists only in the parent makes the
standalone and chain-driven runs record *different* values for the same input —
which is exactly the asymmetry R16 rules out. The rule must live in the child.

### Mitigation

Restate the private-upstream omission rule in `/plan`'s own contract, as check 8
of area 1's set: on a public repo with a private upstream, omit the field, do not
pass it further, and announce the omission and its reason (this is R12's
announcement obligation, and R12 already binds every producing skill).
`/scope`'s check 3 stays where it is and stays load-bearing — it now protects
the `/plan` hand-off rather than the `/brief` write — so the two are
defense-in-depth, not a duplication to be collapsed.

### One consequence to state plainly, not a security finding

`/scope`'s check 3 omits and *continues*. Under R19/R14 that means a public
tactical chain run under a private roadmap produces a PLAN with no roadmap link,
so the cascade never finds the roadmap and the feature stays Planned after it
ships. That is the correct trade (do not leak the path), but it is a behaviour
the design should name, because before this change the same omission cost
nothing the cascade depended on.

---

## 4. Dropping the tracked-by-git check from `/brief`'s flag — **ACCEPTED, with one mitigation**

Reviewed adversarially, since this is the one place the change loosens a control.

### What an author can now feed `/brief` that they could not before

After decision 4's disposition, the flag's remaining checks are: canonicalize,
resolve symlinks, inside the working tree, exists and readable, basename starts
with `ROADMAP-`, not under `wip/`. Dropped: tracked by git.

The newly admissible input class is: **an untracked, gitignored, or
never-committed file anywhere in the working tree whose basename starts with
`ROADMAP-`.** Note the "anywhere": the flag has never carried a directory
constraint — `phase-0-setup.md:152-154` enforces the basename and nothing else —
whereas Input Mode 3 requires a match against `docs/roadmaps/ROADMAP-*.md`
(`skills/brief/SKILL.md:107-109`). So `--upstream target/ROADMAP-x.md`,
`--upstream node_modules/pkg/ROADMAP-x.md`, or a file another agent dropped in
the worktree all become admissible. The `wip/` rejection (kept, correctly) is now
the *only* directory bound on the flag.

### What reaches a committed artifact from that value

- **The frontmatter: nothing.** R13 removes the write. The concern the tracked
  check was written for is genuinely gone.
- **The file's contents: yes, and this is the real channel.** Phase 1's Upstream
  ROADMAP mode loads the file, reads the feature line item and the sequencing
  rationale around it, and drafts the problem and outcome candidates from it
  (`phase-1-discover.md:40-59`); Phase 2 re-reads it (`phase-2-draft.md:33`).
  Decision 4's own §1 says the input's whole value is this grounding. So
  arbitrary local file content becomes paraphrased prose in a committed,
  durable, public BRIEF — and, separately, becomes untrusted text in the agent's
  context, which is a prompt-injection channel independent of what gets
  committed.
- **The path string: transiently.** It lands in
  `wip/brief_<topic>_context.md`'s `## Grounding Path` and
  `wip/brief_<topic>_discover.md`'s `## Grounding Anchor`. Those are committed to
  the feature branch during the workflow and deleted by Phase 5's cleanup before
  merge; the workspace squash-merges, so they never reach the default branch.
  Low.
- **A shell command: no.** Nothing in `/brief` interpolates the grounding path
  into an emitted command; Phase 5's hygiene grep is over the BRIEF, not the
  path.

### Why this is accepted rather than a concern

The content channel is **not created by this change**. It is reachable today by
three routes that never ran a tracked check:

1. Input Mode 3's positional path — decision 4 documents that the two further
   checks apply "to a `--upstream` value," so the positional roadmap route has
   never run either of them. An untracked `docs/roadmaps/ROADMAP-x.md` is
   already accepted today.
2. Phase 1's Freeform Topic mode, step 3: "if a relevant ROADMAP clearly exists
   but no path was given, **find it yourself by searching `docs/roadmaps/`**"
   (`phase-1-discover.md:78-81`) — a glob that finds untracked files.
3. `/strategy`'s grounding PRD, the corpus's existing read-only-input precedent,
   which runs the five canonicalization steps and neither durability check.

So the tracked check was never a content-provenance control. It was a
link-durability control, on one of two routes, and decision 4's reasoning that it
has "no independent reason underneath it" is correct as far as recording goes.

### The residual, and the mitigation

What genuinely widens is **directory scope**: the untracked input class moves
from "untracked file under `docs/roadmaps/`" to "untracked file anywhere in the
worktree except `wip/`". And decision 4 supplies the argument against its own
disposition without applying it — in defending check 1 it writes that "grounding
a durable brief's problem statement in a scratch draft that will not exist by
review time makes the framing's provenance unreproducible." That is exactly as
true of `target/ROADMAP-x.md` as of `wip/ROADMAP-x.md`.

Two mitigations, in preference order:

1. **Confine the flag's canonical path to `docs/roadmaps/`**, matching Input Mode
   3's own constraint. This completes the convergence decision 4 wants ("makes
   `/brief`'s two routes validate identically") rather than converging them
   halfway, and it rejects no legitimate input — every roadmap in the corpus and
   every `/roadmap`-produced artifact lands there, and cross-repo values skip
   path resolution entirely. **Caveat:** apply it at `/scope`'s Phase 0 too, or
   at neither — `/scope` enforces basename only, and a divergence would break a
   chain mid-flight after `/scope` accepted a path `/brief` then rejects.
2. **If the confinement is judged out of scope**, widen Phase 2 step 2.2's
   sanitization warning trigger from "upstream in a private repo" to "grounding
   file is untracked **or** in a private repo," with the same wording: the
   framing is being derived from content no reviewer can see, so review the
   Problem Statement and User Outcome before the draft lands. Decision 4 already
   requires step 2.2 be retained verbatim; this is a one-clause trigger change on
   a warning that already exists.

Either way, the design should state the residual explicitly rather than let
"drop check 2" read as costless: **the public BRIEF's prose now carries the whole
load of a grounding whose source may not be reproducible from the repository.**

---

## 5. The validator changes — **N/A on I/O; ACCEPTED on basename spoofing**

### Does the check do any I/O that could be pointed somewhere unexpected? **N/A**

No, by construction. Decision 2's Option B is a single loop over
`field_entries(field)` calling `detect_format(basename(&entry.value))`.
`detect_format` (`formats.rs:248-260`) is a pure longest-prefix string matcher
over the static `formats()` table; `basename` is a string split. No `Path::exists`,
no `fs::read`, no `Command`. There is no file handle, no subprocess, and no
path-derived syscall for an attacker-controlled value to steer — so symlink
following, TOCTOU, and out-of-tree reads are all absent rather than mitigated.
This is what makes PRD R8 and its AC ("a document whose `upstream:` names a
`VISION-` or `STRATEGY-` basename is judged **without that file being read from
disk**") true by construction rather than by discipline.

Decision 2's rejection of Option C (folding into `check_upstream_resolves`)
preserves this property, and the design should keep that as its stated reason
alongside the golden-bytes one: `check_upstream_resolves` *does* touch disk
(`checks.rs:840` `Path::new(path).exists()`, `:846` `git ls-files`), and merging
would put the pure check behind a subprocess. Both of those existing I/O sites
are unchanged by this work, and the `git ls-files` call is already correctly
shaped — argv array with an explicit `--`.

### Does typing a target from its basename introduce a spoofing surface? **ACCEPTED**

Two directions, both benign:

**A file named `ROADMAP-x.md` that is not a roadmap.** The check types it as
ROADMAP and a durable document naming it takes a lifetime finding. That is a
false positive, error-severity, author-visible at authoring time, and fixed by
renaming the file to its conventional prefix. It cannot be induced by anyone who
does not already control the repository, and the naming document's own type does
*not* come from the same weak signal — `main.rs:604` types the document under
validation by basename **and then** `validate_file:185-187` gates on
`doc.schema == spec.schema_version`, so a mis-named document under validation
gets a SCHEMA notice and an early return rather than being judged as the wrong
type.

**The reverse — renaming a roadmap to dodge the check.** `detect_format` returns
`None` for an unrecognized prefix and R9 leaves the entry unchecked, so
`docs/roadmaps/RM-x.md` would evade the lifetime finding. The evasion costs the
author the entire roadmap toolchain: `shirabe validate` types documents by the
same prefix table, so the renamed file stops being validated as a roadmap at all;
`finalize.rs:687-700` returns `NodeAction::Error` for an unrecognized prefix and
stops the chain walk, so the cascade stops finding it; and `/plan`'s and
`/brief`'s input modes glob on `ROADMAP-*.md`. It is a self-inflicted evasion by
an actor who already controls the frontmatter, which is the same actor who could
simply write any value they like. No control is lost that was ever holding.

The PRD already states this limitation in its own words ("The check reasons from
basenames ... This is the same assumption the format detection already makes
everywhere else"), which is the correct disposition. Two smaller items worth
carrying into the design text:

- The degenerate cross-repo shape `owner/repo:ROADMAP-x.md` (no path after the
  colon) basenames to `repo:ROADMAP-x.md` and falls through unchecked. Decision 2
  flags it and PRD R9's stated tolerance covers it. Splitting on the cross-repo
  colon first (`upstream::is_cross_repo_reference`, `upstream.rs:133-141`) closes
  it for the cost of one call; it is a completeness fix, not a security one.
- The schema gate is a bypass for the legality check the same way it is for every
  other per-file check: `real/PRD-roadmap-skill.md` in the golden corpus is
  illegal on both properties and escapes because it carries no `schema:` field.
  That is pre-existing, it is what preserves the frozen fixture bytes decision 2
  depends on, and it emits a visible notice. Accepted unchanged.

---

## Summary

| Area | Outcome |
|---|---|
| `/plan --upstream` path handling | CONCERN — bind all eight sibling checks at Phase 0; 7.4b alone is insufficient (sequence-blind, post-issue-creation, no canonicalization, no visibility stop); label the `validate-plan.sh` sequence fix as a security fix |
| Interpolation | CONCERN (small) — one new site (7.4b's per-entry `git ls-files`), currently specified unquoted and without `--`; add `--` to `validate-plan.sh:160`; state the argument-boundary convention in `/plan`'s own contract |
| Visibility boundary | CONCERN — `/plan` has no private-upstream omission rule; standalone `/plan` would skip a check the `/scope` path performs, which R16 forbids. Restate the rule in `/plan`'s contract |
| Dropping tracked-by-git from `/brief` | ACCEPTED — the content channel predates the change (positional mode and Phase 1's own glob never ran the check); residual is directory scope. Mitigate by confining the flag to `docs/roadmaps/` (at `/scope` too) or by widening step 2.2's warning trigger to untracked grounding |
| Validator changes | N/A on I/O (pure basename matching, no syscall to steer); ACCEPTED on basename spoofing (false positives are author-visible; evasion costs the whole roadmap toolchain) |
