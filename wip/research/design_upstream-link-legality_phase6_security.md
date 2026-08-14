# Phase 6 security review — DESIGN-upstream-link-legality

**Verdict:** FAIL

Three required changes, all inside the flag-path subsection and Security
Considerations, all specification-level rather than re-litigations of a settled
decision. Two of the five Phase 5 areas are carried faithfully and one is
carried more strongly than I asked for. The failures are concentrated in the
surface the design itself identifies as the one that records: `/plan`'s new
flag.

---

## What is carried faithfully

**Area 3 (visibility boundary)** — faithful. The rule is stated in the flag-path
enumeration and again in Security Considerations, and the reason given is the
standalone-versus-chain asymmetry with the correct consequence named (a public
plan naming a private roadmap, uncatchable because a cross-repo value resolves
to nothing). An implementer cannot satisfy this by pointing at `/scope`.

**Area 5 (validator I/O and basename spoofing)** — faithful, and correctly
separated: I/O is N/A by construction ("no path to canonicalize, no file to
open, and no syscall an attacker could steer"), spoofing is accepted with both
directions priced. The added observation that evading by renaming also costs the
document its required-sections detection is a better version of my argument than
the one I wrote.

**Area 1, one part — stronger than my report.** I offered "while
`validate-plan.sh` is being changed anyway, canonicalize and reject an
out-of-root or symlinked target" as an aside; the design commits to it in
Security Considerations and sequences the whole script fix as a hard dependency
of the flag rather than a follow-up. That is the right call and it is stated in
a way an implementer cannot defer.

---

## Required change 1 — the `/plan` validation set is missing cross-repo discrimination, and the omission makes the visibility check unreachable

The flag-path subsection enumerates six checks: canonicalization with symlink
resolution, bounds-check against the working tree, roadmap basename, not under
`wip/`, tracked by git, private-upstream omission. The seventh is missing, and
it is the one that has to run **first**.

Every sibling skill discriminates a cross-repo `owner/repo:path` value before
any filesystem check and exempts it from path resolution.
`skills/scope/references/phases/phase-0-setup.md:146-151`: such a value "is not a
working-tree path and is not resolved against the filesystem at all. It skips
this check and the tracked-by-git check." `/brief`'s
`phase-0-setup.md:189-194` says the same. The Rust side has the discriminator
public as `crate::upstream::is_cross_repo_reference` (`upstream.rs:133-141`).

Applied literally, the design's set rejects every cross-repo roadmap: it does not
canonicalize, it is not inside the working tree, and `git ls-files` returns
nothing for it. Two consequences, one functional and one security:

- **Functional.** `/scope` deliberately accepts cross-repo upstreams, and its own
  Phase 0 gives the reason: rejecting them "would also make the flag unable to
  express the case that motivates it, a tactical chain run in one repo underneath
  a roadmap that lives in another"
  (`skills/scope/references/phases/phase-0-setup.md:204-207`). Under R14 that
  value is now handed to `/plan`. A `/plan` that rejects what `/scope` accepts
  breaks the chain mid-flight — the same divergence class the design correctly
  guards against between `/scope` and `/brief`.
- **Security.** The private-upstream omission check only ever fires on a
  cross-repo value: a private upstream is by definition in another repository.
  If cross-repo values never survive canonicalization, the check the design
  calls out in its own Security Considerations is unreachable code. The ordering
  is what makes that control real, so the ordering has to be in the contract.

**Required:** state that a cross-repo `owner/repo:path` value is discriminated
first and exempted from canonicalization, the bounds check, and the tracked-by-git
check, retaining the roadmap-basename rule on its file component — and that the
private-upstream omission check runs on it, because that is the only value class
it can fire on.

**Also required, one sentence, same paragraph.** The design says `/plan`
canonicalizes the value and then "writes it into the produced plan's `upstream:`
as a second sequence entry", without saying which form is written. It must be
the repo-relative path, not the canonical absolute one: `validate-plan.sh:149`
builds `upstream_abs="${repo_root}/${upstream_val}"` by concatenation, so an
absolute recorded value produces a doubled path and fails the CI gate this
change is otherwise repairing. `finalize.rs` resolves relative to the process
working directory and would accept either, so the script is the binding
constraint and nothing else would catch the mistake.

---

## Required change 2 — the confinement is applied to the reader and not to the writer

This is the answer to the second question, and it is the reason for the FAIL
rather than a note.

The design confines the flag's canonical path to the roadmaps directory at
`/scope` and `/brief`. My at-both-or-neither caveat was written about those two
skills, before R14 made `/plan` a third holder of the same value. Re-priced with
`/plan` in the picture, confining two of the three is the wrong two.

**The chain direction is safe.** `/scope` is now stricter than `/plan`, so a
value that reaches `/plan` through the chain has already passed the confinement.
No mid-flight rejection.

**The standalone direction is not.** Standalone `/plan --upstream <path>` accepts
what standalone `/brief --upstream <path>` rejects — and `/plan` is the one that
commits the value. The design's own justification for the confinement is that
grounding a durable artifact in an unreproducible file makes its provenance
unrecoverable. Recording a committed frontmatter pointer to such a file is
strictly the worse case, and it is the case left open.

**What is actually reachable.** `/plan` keeps tracked-by-git, so the untracked
class decision 4 opened at `/brief` is closed at `/plan`. What remains is a
**tracked** file with a `ROADMAP-` basename outside `docs/roadmaps/`. This
repository has four:

- `skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md`
- `skills/work-on/evals/fixtures/roadmaps/ROADMAP-cascade-test.md`
- `crates/shirabe/tests/fixtures/golden/corpus/real/ROADMAP-strategic-pipeline.md`
- `crates/shirabe/tests/fixtures/golden/corpus/synthetic/ROADMAP-fc05-divergent-header.md`

A plan recording one of these is not merely mislabelled. `finalize.rs:687-691`
types a node as `Roadmap` from its basename with no directory rule, so the walk
hands it off; `run-cascade.sh:830-832` routes the handoff to `handle_roadmap`,
which greps and rewrites the file, and on the all-features-Done path
`handle_roadmap_deletion` reaches `git rm -f "$path"` at `:563`. The consume-side
guards I confirmed in Phase 5 (`validate_node_path`: root confinement, regular
file, symlink rejection) all pass for a tracked in-tree fixture — they were never
directory-aware, and were never meant to be. The Phase 0 confinement is the only
place this is decidable.

**Required:** apply the same confinement to `/plan`'s flag, and say in the
Security Considerations paragraph that it binds at all three skills that carry a
roadmap on the flag — `/scope`, `/brief`, `/plan` — with the writer being the one
that most needs it. While editing, state whether the confinement is a prefix
match on `docs/roadmaps/` or a match against the non-recursive glob `/brief`'s
positional mode uses (`skills/brief/SKILL.md:107-109`); the two differ for a
nested subdirectory and an implementer will otherwise pick one silently.

**Priced and not a problem** (checked, so the change can be made without a second
review round):

- No eval breaks. `/scope`'s `upstream-flag-consumed` uses
  `docs/roadmaps/ROADMAP-editor.md` (`skills/scope/evals/evals.json:344`), and
  `/prd`'s `wip/ROADMAP-staging.md` scenario (`skills/prd/evals/evals.json:125`)
  is a negative test for a check that is unchanged.
- Resume is covered for free and degrades gracefully.
  `upstream-flag-stale-on-resume` already specifies that the ladder "re-run[s]
  the whole Phase 0 battery against the worktree as it is now"; a
  `consumed_upstream:` recorded before this change that now fails the confinement
  routes to the already-specified Re-supply / Continue-without / Bail rather than
  to a hard stop.
- R23's hand-authored fixture chain is unaffected. The confinement binds the
  skill's input flag; the validator and the cascade stay directory-agnostic by
  design, which is exactly why the input flag has to carry it.

---

## Required change 3 — "one new interpolation site" undercounts by one

Security Considerations says "One new interpolation site, and it gets the
argument boundary... The value reaches a `git ls-files` invocation per entry in
the plan pre-flight path."

Two distinct commands take the value, in two different files, and only one of
them is new:

1. **New.** Step 7.4b's per-entry `git ls-files`, in
   `skills/plan/references/phases/phase-7-creation.md`. The step's prose today
   reads "If `git ls-files <path>` returns empty" (`:308`) — unquoted and with no
   `--`. This is the site the design is describing, and it is currently
   specified in the exact shape the stated discipline forbids.
2. **Pre-existing, in the script the design is already rewriting.**
   `validate-plan.sh:160` runs `git ls-files --error-unmatch "$upstream_val"` —
   quoted, but with no `--` terminator, so a value beginning with a dash is
   parsed as an option rather than a pathspec. The advice string at `:162` has
   the same shape.

An implementer reading "one new interpolation site" can satisfy the sentence by
fixing the script and leaving 7.4b's prose as written, or the reverse. Severity
is low on its own — the roadmap-basename rule makes a leading-dash value require
a directory literally named `-something` — but the cost of naming both sites is
one clause, and the design elsewhere insists correctly that the argument
boundary rather than the validation is the guarantee.

**Required:** name both commands and say both are quoted and passed after `--`.
The Rust side already models it exactly (`checks.rs:846`:
`.args(["ls-files", "--error-unmatch", "--", path])`) and is worth citing so the
shape is not re-derived.

---

## Secondary finding — outside my remit, visible from here

`/prd` still documents its `--upstream` as "Typically points to a Roadmap
document when the PRD is part of a multi-feature initiative" and writes it to
frontmatter — `skills/prd/SKILL.md:81-84` and
`skills/prd/references/phases/phase-3-draft.md:32-35`. Under R5 a PRD's only
legal parent is a BRIEF, and R11 says no skill records a value the definition
forbids, so `/prd` is a second skill that will keep producing exactly the edge
the new direction check errors on.

The design's Implementation Approach phase four lists `/brief`, `/plan`,
`/scope`, and `/explore` as the skill contracts to author, and does not list
`/prd`. The reference-sweep AC ("no file under `references/` or
`skills/*/references/` documents a ROADMAP as a legal upstream for a BRIEF, a
PRD, or a DESIGN") catches `phase-3-draft.md` but not `SKILL.md`, which is
neither. So half of it lands by accident of the AC's grep scope and half is
unowned. This is an R11 completeness gap rather than a security one; I raise it
because a reviewer finding it after the change ships will reasonably assume it
was missed rather than deferred.

---

## Summary

| Area | Carried as reported? |
|---|---|
| 1. `/plan --upstream` path handling | Partly — the six-check enumeration drops cross-repo discrimination-first, which breaks the motivating case and makes the visibility check unreachable; the recorded value's form is unstated. Otherwise carried, and the `validate-plan.sh` half is carried more strongly than reported |
| 2. Interpolation | Partly — discipline stated correctly, site count is one short; both commands need naming |
| 3. Visibility boundary | Yes, faithfully, with the right reason |
| 4. `/brief` tracked-by-git | Mitigation 1 taken correctly at `/scope` and `/brief`, but not at `/plan`, which is the skill that records. Breaks no legitimate invocation and no eval; the gap is the writer, not the reader |
| 5. Validator I/O and spoofing | Yes, faithfully, and better argued than reported |
