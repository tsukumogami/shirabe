---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-release-same-day-merges.md
problem: |
  `/release` derives what a release contains twice -- once as a commit range in
  Phase 3, once as a GitHub pull request search keyed on the undefined
  `$LAST_TAG_DATE` -- and the second derivation is consumed by two phases. Read
  as a calendar date, GitHub's `merged:>YYYY-MM-DD` excludes everything merged
  on the previous tag's own day, so the release notes and the
  security-labeled-PR precondition both silently lose those pull requests.
decision: |
  Compute the release's pull request set once, in Phase 1, from the commit range
  the phase already establishes, by parsing the `(#N)` suffix squash-merge
  writes into commit subjects. Phase 2's security precondition and Phase 3's
  notes gather both read that one set. `$LAST_TAG_DATE` and both GitHub
  pull-request searches are removed. Phase 1 also emits the commits in the range
  that carry no pull request reference, which is the residual the derived set
  cannot account for.
rationale: |
  The commit range is exact and has no boundary semantics to get wrong, and the
  skill already computes it one step before the truncating search runs. Deriving
  the set from it removes the second source rather than tightening it, so the
  two consumers cannot drift apart the way a redefined variable could -- there
  is one value, computed once, and repairing one call site without the other
  stops being possible. Defining `$LAST_TAG_DATE` as a full timestamp is the
  smaller edit and was rejected because it leaves two derivations and two places
  to keep correct.
---

# DESIGN: One PR set for a release, derived from its commits

## Status

Planned

Design for issue #321, written from
[PRD-release-same-day-merges](../prds/PRD-release-same-day-merges.md). The PRD
owns R1 through R7; this document owns which mechanism meets them.

## Context and Problem Statement

`skills/release/SKILL.md` establishes the previous release tag in Phase 1:

```bash
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
```

and counts commits by conventional-commit prefix since that tag to recommend a
version bump. The commit range is therefore already Phase 1's, and it is exact:
`$LAST_TAG..HEAD` is the set of commits the release contains, by construction.

Two later phases then ask a different question of a different source. Phase 2's
sixth precondition:

```
gh pr list --state merged --search "label:security merged:>$LAST_TAG_DATE"
```

and Phase 3's step 2:

```
gh pr list --state merged --base main --search "merged:>$LAST_TAG_DATE"
```

`$LAST_TAG_DATE` has no assignment anywhere in the skill. Whoever runs the
skill supplies it, and the name asks for a date. GitHub's search grammar
resolves `merged:>YYYY-MM-DD` as strictly after the end of that day, so a
date-shaped value drops every pull request merged between the tag's timestamp
and midnight.

Measured against the v0.17.0 to v0.18.0 range, with v0.17.0 tagged
`2026-08-15T19:43:30+00:00` and the release HEAD at `4859557`:

| Source | Pull requests |
|---|---|
| `merged:>2026-08-15` (date-shaped) | 292, 311, 316, 318 |
| `merged:>2026-08-15T19:43:30Z` (timestamp-shaped) | 292, 297, 311, 316, 318 |
| `git log v0.17.0..4859557`, parsing `(#N)` | 292, 297, 311, 316, 318 |

`#297` merged at `2026-08-15T23:52:38Z`. It is in the release and the
date-shaped search does not return it.

The technical problem is not that one search term is imprecise. It is that a
release's contents are derived twice, so there is a derivation that can be
wrong while the authoritative one sits three lines above it, and nothing
compares them. Fixing the search term leaves that shape intact and leaves two
call sites to keep correct.

## Decision Drivers

- **Both call sites, structurally.** A fix that can repair one call site and
  leave the other truncating has not addressed the defect (PRD R1 and R2). The
  strongest form of this is a shape where there is only one thing to repair.
- **No undefined values.** The skill is prose executed by a person or an agent.
  A command referencing a variable nobody assigned pushes a correctness
  decision onto whoever runs it (PRD R3).
- **Skill prose only.** `CLAUDE.md` section "CLI Surface" reserves artifact
  authoring for skills and the CLI for validation. No subcommand may render or
  compute release notes (PRD R5), and the workflows are out of scope (PRD R7).
- **Legible to the next reader.** Whichever mechanism ships has to be one a
  future editor keeps correct without knowing this history.
- **Honest about its residual.** Whatever the derived set cannot account for
  should be visible rather than assumed away (PRD R4).

## Considered Options

### Decision 1: Where the pull request set comes from

The skill needs a set of pull requests for two purposes: to credit changes in
the notes, and to find security-labeled changes that need a disclosure
decision. Two sources can supply it. The commit range is local, exact, and
already computed; the GitHub search is remote, has date-boundary semantics, and
is what is there today. The choice decides not only correctness but how many
derivations exist afterwards, which is what decides whether the two call sites
can drift.

#### Chosen: Derive from the commit range

Phase 1 already computes `LAST_TAG`. Extend it to name the release range once
and derive the pull request set from it, by parsing the `(#N)` suffix that
GitHub's squash merge writes into the commit subject:

```bash
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
RELEASE_RANGE="$LAST_TAG..HEAD"

RELEASE_PRS=$(git log --format='%s' "$RELEASE_RANGE" \
  | grep -oE '\(#[0-9]+\)$' \
  | tr -d '(#)' \
  | sort -n -u)
```

Phase 2's security precondition and Phase 3's notes gather both read
`$RELEASE_PRS`. Neither runs a `merged:>` search, and `$LAST_TAG_DATE` is
deleted.

The suffix is written by GitHub, not by authors: shirabe permits squash merges
only (`allow_merge_commit` and `allow_rebase_merge` are both false) with
`squash_merge_commit_title: PR_TITLE`, and GitHub appends `(#N)` to a
PR_TITLE-derived squash subject. The parse is anchored to the end of the
subject so a pull request whose own title contains a parenthesized number is
not misread.

Three properties follow, and they are the reason this option is chosen over a
narrower repair:

- The set is exactly the pull requests the release contains. A pull request
  merged into `main` after the release point is not in the range, and is
  correctly absent -- where a `merged:>` search would wrongly include it, since
  the search has an open upper bound.
- There is one derivation with two consumers, so the two call sites cannot
  disagree. Repairing one and not the other is not an available failure.
- The notes need no network access at all. The squash subject already carries
  the conventional-commit type, the description, and the number, which is
  everything Phase 3 groups and writes.

#### Alternatives Considered

**Define `$LAST_TAG_DATE` as a full ISO-8601 timestamp.** Assign
`LAST_TAG_DATE=$(git log -1 --format=%cI "$LAST_TAG")` in Phase 1 and leave
both searches otherwise as they are. This is the smaller edit and it does fix
the reproduced case: the timestamp-shaped search returns `#297`.

Rejected because it leaves two derivations of one fact and two call sites to
keep correct. The defect being fixed is not that a search term was imprecise;
it is that the imprecise derivation existed alongside an exact one and nothing
reconciled them. This option preserves that shape and depends on every future
editor of either line preserving the precision -- which is the assumption that
already failed once, since `$LAST_TAG_DATE` presumably had a definition in
someone's head when the line was written.

It has a second, narrower problem. `git describe --tags` returns a tag name,
and `git log -1 --format=%cI <tag>` reads the committer date of the commit the
tag points at, not the date the tag itself was created. shirabe's release tags
are annotated, so the two are distinct values: for `v0.17.0` the tagger date is
`2026-08-15T19:43:31Z` and the commit date is `2026-08-15T19:43:30Z`. One
second, because the workflow tags a commit it just made -- but a tag applied by
hand to an older commit opens the gap as wide as the delay, and every pull
request merged inside it gets counted into the wrong release. The direction is
safe in the sense that an earlier bound over-includes rather than drops, which
is why this is a secondary reason and not the main one. It still means the
window is not the one the variable's name claims, which is the same class of
quiet imprecision the fix exists to remove.

**Reconcile the two lists and report the difference.** Keep both derivations
and add a comparison step that stops or warns when they disagree. Rejected as a
resolution, though its useful residue is kept as Decision 3: a reconciliation
between an exact source and a wrong one is a way of noticing the wrong one,
not a reason to keep it. Once the search is gone there is nothing to
reconcile, and what is left worth reporting is the opposite gap -- commits with
no pull request at all.

### Decision 2: How the security precondition gets labels

The derived set is a list of numbers. Phase 2 needs to know which of them carry
the `security` label, and labels live only on GitHub. This is the one place the
network is still required, and where in the phase order the derivation has to
happen.

#### Chosen: Per-pull-request label lookup, over a set derived in Phase 1

Phase 2 iterates the derived set and reads each pull request's labels:

```bash
for pr in $RELEASE_PRS; do
  gh pr view "$pr" --json number,title,labels \
    --jq 'select(.labels[]?.name == "security") | "\(.number) \(.title)"'
done
```

This forces the placement question, and the answer is what makes the whole
design hold together. Phase 2 runs before Phase 3, so the derivation cannot
live in Phase 3 where the search does today. It moves to Phase 1, which already
computes `LAST_TAG` and already walks the commit range to count prefixes. Phase
1 becomes the single site that answers "what is in this release"; Phase 2 and
Phase 3 are consumers.

The cost is one API call per pull request in the release. Recent shirabe
releases carry five to fifteen, so a release spends five to fifteen calls
against a 5000-per-hour authenticated limit. The precondition already makes
several `gh` calls of its own.

#### Alternatives Considered

**One `gh pr list --search` restricted to the derived numbers.** Combine
`label:security` with the pull request numbers in a single search, trading N
calls for one. Rejected because it does not work: GitHub's search treats bare
numbers as full-text terms rather than as a number filter, so
`--search "label:security 292 297 311 316 318"` returns an empty set even when
a matching pull request exists. Verified against this repository.

**Keep a `merged:>` search for the security check alone, with a timestamp.**
Leave Phase 2 querying GitHub directly and only change Phase 3. Rejected
because it reintroduces exactly the split the design removes, at the call site
whose failure mode is worse -- and it is the specific partial fix the issue's
follow-up comment calls out as unacceptable.

### Decision 3: What is reported about commits with no pull request

Deriving pull requests from commits leaves a residual the other direction: a
commit in the range that carries no `(#N)` suffix is in the release and in no
pull request. Release chore commits are the routine case; a direct push to
`main` is the interesting one. PRD R4 requires this be visible.

#### Chosen: Phase 1 computes it, Phase 3 surfaces it with the notes

Phase 1 emits it alongside the derived set:

```bash
git log --format='%h %s' "$RELEASE_RANGE" | grep -vE '\(#[0-9]+\)$'
```

and Phase 3 prints it under the drafted notes, where the author is already
reading and can decide whether an entry deserves a line. Against the v0.17.0 to
v0.18.0 range this reports exactly one commit,
`chore(release): advance to 0.17.1-dev`, which is the expected shape.

The report is informational and does not stop the release. Every release
contains at least one such commit, so a blocking check would fire on every run
and be trained away within two releases.

It also carries the design's own assumption check, which is why it is worth
more than its size. The derived set depends on GitHub writing `(#N)` into
squash subjects. If that assumption ever breaks -- the repository enables merge
commits, or someone lands work by pushing to `main` -- the symptom is a sudden
crowd of unattributed commits in this report, in front of the author, at the
moment it matters.

#### Alternatives Considered

**Report nothing.** Accept that a commit outside a pull request is not
creditable and stay silent. Rejected because it hides the failure of the
assumption the derived set rests on, and because a direct push to `main` is
precisely the change an author would want to notice in release notes.

**Fail the release on any unattributed commit.** Rejected: release chore
commits make this fire on every release, so the check would be routinely
overridden and stop meaning anything.

## Decision Outcome

**Chosen: 1-commit-range + 2-per-PR-labels + 3-informational-residual**

### Summary

Phase 1 becomes the single place that answers what a release contains. It
already resolves `LAST_TAG`; it gains a named release range, a derived set of
pull request numbers parsed from the `(#N)` suffix on squash-merge subjects,
and a list of the commits in the range that carry no such suffix. Nothing else
in the skill derives a release's membership.

Phase 2's sixth precondition stops searching GitHub for merged pull requests
and instead reads labels for the numbers Phase 1 produced, one `gh pr view` per
pull request, keeping the ones labelled `security`. Everything downstream of
that -- reading the pull request before asking, the recommend-one-treatment
AskUserQuestion, the standard/redacted/excluded vocabulary -- is unchanged;
only the set it operates on changes.

Phase 3 step 2 stops searching GitHub and reads the same derived set. Its step
1 commit gather stays as it is, since the notes are written from commit
subjects and the subject already carries the type prefix, the description, and
the number. Phase 3 also prints Phase 1's unattributed-commit list beneath
the drafted notes.

`$LAST_TAG_DATE` is deleted. After the change the string appears nowhere in the
skill, which is the mechanically checkable form of PRD R3.

The evals gain two scenarios, one per call site, each asserting the same-day
case specifically: that the gathered set includes a pull request merged after
the previous tag's timestamp but before the end of its calendar day, and that
the security precondition evaluates that same pull request rather than
skipping it.

### Rationale

The three decisions reinforce each other around one property: after the change
there is exactly one derivation of a release's membership, so there is exactly
one thing to keep correct. Decision 1 removes the second source rather than
repairing it. Decision 2's placement is what makes that literal -- because the
security check runs first, the derivation has to move to Phase 1, and once it
is there both consumers necessarily read the same value. Decision 3 keeps the
remaining assumption honest by putting its failure mode in front of the author
rather than in a comment.

The trade-off accepted is a dependency on squash-merge subject formatting,
which is a repository setting rather than a guarantee. That is a real
narrowing compared to a GitHub search, which would keep working under any merge
strategy. It is accepted because the setting is enforced by the repository
(merge commits and rebase merges are both disabled), because the failure is
loud rather than silent under Decision 3, and because the alternative buys its
generality by keeping a second derivation -- which is the thing that broke.

## Solution Architecture

There are no components to build. The artifact is `skills/release/SKILL.md`,
and the change is to its prose and the commands that prose prescribes, plus
`skills/release/evals/evals.json`.

Data flow after the change:

```
Phase 1  git describe --tags       -> LAST_TAG
         "$LAST_TAG..HEAD"         -> RELEASE_RANGE
         git log --format='%s'     -> RELEASE_PRS          (parsed (#N) suffixes)
         git log --format='%h %s'  -> unattributed commits (subjects with no suffix)
             |                             |
Phase 2  RELEASE_PRS -> gh pr view --json labels -> security-labeled subset
                                           -> AskUserQuestion per PR (unchanged)
             |                             |
Phase 3  RELEASE_PRS -> notes gather       |
         git log $LAST_TAG..HEAD -> commits (unchanged, step 1)
                                           -> unattributed commits printed with notes
```

Interfaces: `RELEASE_RANGE`, `RELEASE_PRS`, and the unattributed-commit list
are the skill's own shell variables, established in Phase 1 and referenced by
name in Phases 2 and 3. They are internal to one skill invocation; nothing
outside the skill reads them, and no file format changes.

Two existing paths through the skill constrain how the range is written.
`--dry-run` runs Phases 1 through 3 normally, so the derivation runs on that
path unchanged and needs no special case. The first release does: Phase 1
already branches on `LAST_TAG` being empty, and `"$LAST_TAG..HEAD"` with an
empty tag is not a range git accepts. The range is therefore `HEAD` when no tag
exists and `"$LAST_TAG..HEAD"` otherwise, which makes the first release's set
every pull request in the repository's history -- the correct answer for a
release that contains all of it.

Sections of `skills/release/SKILL.md` that change:

| Section | Change |
|---|---|
| Phase 1: Version Analysis | Add the release-range naming, the `RELEASE_PRS` derivation, the unattributed-commit derivation, and a sentence stating the squash-merge assumption they rest on |
| Phase 2 precondition 6 | Replace the `gh pr list --search` line with the per-pull-request label read over `$RELEASE_PRS`; leave the treatment guidance untouched |
| Phase 3 step 2 | Replace the `gh pr list --search` line with a read of `$RELEASE_PRS` |
| Phase 3 step 5 | Print the unattributed-commit list beneath the notes |

`skills/release/requires.tsv` needs no change: it already declares `gh` and
`git` as always-required tool-only records, and the change adds no new binary.

## Implementation Approach

One unit of work, landing in one pull request. The change is small, it is all
in one file plus its evals, and splitting it would produce an intermediate
state where one call site is fixed and the other is not -- the exact shape the
PRD rejects.

1. **Rewrite the three sections of `skills/release/SKILL.md`.** Phase 1 gains
   the derivation; Phases 2 and 3 become consumers; `$LAST_TAG_DATE` is
   deleted. Confirm with `grep -c 'LAST_TAG_DATE' skills/release/SKILL.md`
   returning zero.

2. **Add the two eval scenarios** to `skills/release/evals/evals.json`, one per
   call site, each naming the same-day condition explicitly in its prompt and
   asserting the derived-set behavior rather than the phase in general.

3. **Demonstrate the fix against the real case.** Execute the rewritten Phase 1
   derivation against `v0.17.0..4859557` and confirm the set contains `#297`;
   execute the rewritten Phase 2 label read over that set and confirm `#297` is
   among the pull requests whose labels are inspected. Record the commands and
   their output in the pull request body rather than asserting the outcome.

4. **Run the evals.** Per `CLAUDE.md` section "Skill Evals", delegate to an
   agent with `/skill-creator` loaded running `scripts/run-evals.sh release`,
   and fix any failing assertion before the pull request is marked ready.

## Security Considerations

**External artifact handling.** Applies, weakly, and the change reduces the
surface. The pull request numbers the skill interpolates into `gh pr view` come
from `grep -oE '\(#[0-9]+\)$'` over commit subjects, so every value is a run of
digits by construction -- a commit subject crafted to carry shell
metacharacters cannot produce one, because a value containing a metacharacter
does not match the pattern that produces values. The removed `gh pr list
--search` lines interpolated `$LAST_TAG_DATE`, an undefined and therefore
unconstrained value, into a search string; deleting them removes an
interpolation site rather than adding one. `$LAST_TAG` comes from `git describe
--tags`, which returns a ref name, and is quoted at every use.

**Permission scope.** Unchanged in kind and narrowed in one place. The skill
already requires `gh` and `git`, declared in `skills/release/requires.tsv`. The
label read is a read-only `gh pr view`; it needs no scope the removed `gh pr
list` did not.

**Supply chain and dependency trust.** Not applicable. The change adds no
dependency, downloads nothing, and executes nothing it did not already execute.
It moves work from a remote query to a local `git log` read, which if anything
reduces the trust placed in a remote response.

**Data exposure.** Applies and is unchanged. Phase 2 reads pull request labels
and, for security-labeled pull requests, the pull request body -- as it does
today. The set it reads them from is derived differently; the data read is the
same, and all of it is already public in a public repository. The change writes
nothing new to the release notes.

**Residual risk.** The security precondition's correctness now depends on the
derived set being complete, which depends on GitHub writing `(#N)` into squash
subjects. If the repository ever enabled merge commits, a pull request could
land without a suffix and be invisible to the precondition -- the same class of
silent, permissive failure being fixed, reached by a different route. Two
things bound it: merge commits and rebase merges are both disabled on the
repository, and Decision 3's unattributed-commit report surfaces the symptom in
front of the author at release time. The skill states the assumption where the
derivation is written, so an editor who changes the merge strategy meets it.

## Consequences

**Positive.**

- A pull request merged on the previous tag's calendar day is credited in the
  notes and reaches the security decision. Verified against the real v0.17.0 to
  v0.18.0 case.
- One derivation, two consumers. The two call sites cannot disagree, and a fix
  to one that misses the other is no longer expressible.
- No undefined value remains in the skill.
- The notes can be drafted with no network access; the only remaining `gh` call
  in this path is the label read.
- A pull request merged after the release point is correctly excluded, which
  the open-ended `merged:>` search got wrong in the other direction.

**Negative.**

- The derivation depends on a repository setting (squash-only merges) rather
  than on a property of git. A repository adopting this skill with merge
  commits enabled would derive an incomplete set.
- The security precondition costs one API call per pull request in the release
  instead of one call total.
- Phase 1 grows: it now answers a question Phase 3 used to answer, which makes
  it the phase a reader must understand before either consumer makes sense.

**Mitigations.**

- The unattributed-commit report is the detector for the merge-strategy
  assumption failing, and the skill states the assumption at the point of use
  so an editor meets it before changing the strategy.
- Five to fifteen calls per release against a 5000-per-hour limit is not a
  practical cost; the precondition already makes several `gh` calls.
- Phase 1's growth is the price of the property that makes the fix hold: the
  security check runs before the notes, so the shared derivation has to live
  above both.
