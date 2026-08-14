# Phase 6 security review — DESIGN-upstream-link-legality (re-review)

**Verdict:** PASS

All three required changes are applied and none of them is satisfiable without
closing the hole it names. One drafting correction must land with the
implementation — it is a clause, not a decision, and the correct behaviour is
already written down in `/scope`'s own Phase 0, so it needs no further review.
One residual is carried forward as a note because its failure mode is loud.

---

## The three required changes, judged

### 1. Cross-repo discrimination — applied, and not hollow

The flag path is now an ordered list with cross-repo discrimination as step 1,
and the ordering is stated as load-bearing rather than as presentation: "Run in
any other order, the checks below would reject every cross-repo roadmap and the
visibility check would become unreachable, which is the check that matters most
for exactly those values." Security Considerations repeats it with the reason
sharpened — "getting that order wrong is a security failure rather than a
functional one."

What would have made this hollow is listing cross-repo as an item without fixing
its position, leaving an implementer free to run canonicalization first and
discover the exemption as a special case afterwards. The numbering plus the
consequence sentence closes that: an implementer who reorders has been told in
advance what they broke.

### 2. The confinement extends to the writer — applied, and not hollow

Both the flag path and Security Considerations say it binds `/scope`, `/brief`
and `/plan`. The reason survives the trip: the chain direction is identified as
already safe (parent stricter than child), so the justification rests where it
should, on standalone `/plan` accepting what standalone `/brief` refuses. The
concrete input class is named — a tracked file with a roadmap basename outside
the roadmaps directory — along with the fact that this repository holds four of
them. That is the sentence that makes the control checkable rather than
aspirational: an implementer can test it.

The design also does something I did not ask for and should have: it flags in
the flag-path subsection that two of `/brief`'s five checks are *changes* to a
skill R13 elsewhere describes as unchanged, so the diff does not arrive as a
surprise to a reviewer reading "unchanged as inputs" literally.

### 3. Both interpolation sites — applied, and not hollow

The sites are distinguished by which one is new and by what each lacks today:
the Phase 7 per-entry invocation is "specified unquoted and without a
terminator", the pre-flight script "quotes the value but passes no `--`". The
sentence "the script does not have that boundary today and gains it here"
forecloses the reading that the script already complies. Both are named as
getting the boundary when the change lands.

---

## Must fix with the implementation — step 5's bundling drops a check `/scope` performs

This is the interaction the re-review question points at, and it arrives from
the bundling rather than from the confinement itself.

Step 5 bundles two checks into one item: "Reject a path under `wip/`, and reject
an untracked path." Step 1 then says a cross-repo value "skips checks 2, 3 and
5" — both halves. Between the two steps the `wip/` rejection has no live domain
at `/plan` at all:

- **For a local value it is unreachable**, because step 3's confinement to the
  roadmaps directory already excludes everything under `wip/`. The two
  directories are disjoint, so the confinement subsumes the `wip/` half. That is
  fine, and worth a clause so a future maintainer relaxing the confinement knows
  what else they are relaxing.
- **For a cross-repo value it is skipped**, and that is the drift.
  `skills/scope/references/phases/phase-0-setup.md:146-151` exempts a cross-repo
  value from the canonicalize/bounds check and from the tracked-by-git check —
  and from those two only. Its three ordered checks then run, and check 1 is the
  `wip/` rejection, so `/scope` applies `wip/` to a cross-repo value today.
  `/brief`'s equivalent at `phase-0-setup.md:189-194` reads the same way.

So `owner/repo:wip/ROADMAP-x.md` would be accepted by `/plan` and committed to a
public plan's `upstream:`, where `/scope` rejects it. Nothing downstream catches
it: the resolution check `continue`s on a cross-repo entry, and the finalization
walk stops on one. The result is a committed pointer into another repository's
non-durable directory — the exact defect the workspace's wip-hygiene rule
declares out of bounds "workspace-wide, to every repo regardless of visibility."
And it reproduces the divergence class the design otherwise guards against: the
chain path is protected because `/scope` checks first, and standalone `/plan` is
where it opens.

**Required clause:** split step 5, so cross-repo skips checks 2, 3 and the
untracked half of 5 while retaining the `wip/` rejection on its path component;
and say in step 3 that the confinement subsumes the `wip/` rejection for
working-tree values. Two sentences. It changes no decision, contradicts nothing
already written, and restores parity with the sibling whose text the flag path
is otherwise reproducing — which is why it is a drafting correction rather than
a second failure.

---

## Residual carried forward — the recorded value's form is still unstated

My first-round change 1 had a second half that has not landed: the design says
`/plan` canonicalizes the value and then "writes the value into the produced
plan's `upstream:` as a second sequence entry after the design", without saying
which form is written. It must be the repo-relative path;
`validate-plan.sh:149` builds `upstream_abs="${repo_root}/${upstream_val}"` by
concatenation, so a canonical absolute value produces a doubled path.

I am not failing on it, and the reason is the failure mode: an absolute recorded
value makes the pre-flight script report `upstream file does not exist` and exit
3 on the first plan produced through the flag. That is loud, immediate, and in
CI — it cannot ship silently, which is the property that separates it from
everything above. Worth the clause when the flag's contract is authored;
not worth a review round.

---

## Answering the interaction question directly

**Does step 1's exemption conflict with step 3's confinement?** No, and the
exemption is the correct resolution rather than a papering-over. A cross-repo
value's path component describes the *other* repository's layout, and this
repository has no standing to require `docs/roadmaps/` of it — the cross-repo
reference convention deliberately does not export local placement rules across
the boundary. Exempting the confinement is therefore the only coherent
behaviour, and step 1 already states it.

**Did extending the confinement to `/plan` create anything unpriced?** One
thing, and it is the finding above: the confinement makes step 5's `wip/` half
redundant for local values, which is harmless, and step 1's exemption removes it
for cross-repo values, which is not. The two are individually correct and
jointly leave the check with nowhere to fire. Neither would have been visible
before the confinement landed, which is why it surfaces now rather than in the
first round.

**Anything else the confinement touches?** Re-checked and clear, as reported
last round: no eval breaks (`/scope`'s `upstream-flag-consumed` uses
`docs/roadmaps/ROADMAP-editor.md`), the resume ladder picks the confinement up
through its existing whole-battery re-validation and degrades to Re-supply /
Continue-without / Bail, and the hand-authored fixture chain is unaffected
because the confinement binds the input flag while the validator and the cascade
stay directory-agnostic by design.

---

## Summary

| Area | Status |
|---|---|
| 1. `/plan --upstream` path handling | Applied, ordered, and the ordering's consequence stated. One clause outstanding on the recorded value's form — loud failure, not a blocker |
| 2. Interpolation | Applied; both sites named and distinguished by what each lacks today |
| 3. Visibility boundary | Applied, with the standalone-versus-chain reason intact |
| 4. `/brief` tracked-by-git and the confinement | Applied at all three holders, with the concrete input class and its four instances named. Must-fix clause: step 5's bundling drops the `wip/` rejection for cross-repo values, where `/scope` applies it |
| 5. Validator I/O and spoofing | Unchanged and faithful |

---

## Secondary finding, unchanged and still unowned

Raised last round and not addressed, restated once so it is a decision rather
than an oversight: `/prd` still documents its `--upstream` as "Typically points
to a Roadmap document" and writes it to frontmatter
(`skills/prd/SKILL.md:81-84`, `skills/prd/references/phases/phase-3-draft.md:32-35`).
R5 gives a PRD one legal parent and it is not a roadmap, and R11 says no skill
records a forbidden value. The reference sweep's own acceptance criterion covers
`phase-3-draft.md` because it lives under `skills/*/references/`; `SKILL.md`
does not, and `/prd` is absent from the skill-contract phase. This is an R11
completeness gap rather than a security one, and it does not affect the verdict.
