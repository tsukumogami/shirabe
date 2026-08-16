# Phase 4 Jury — BRIEF-work-on-retry-clearing.md

## Role 1: Content Quality — FAIL

### Blocking

**Problem Statement misstates the current content of `phase-4a-scrutiny.md`.**
The Problem Statement's central piece of supporting evidence reads:

> One phase does try: `phase-4a-scrutiny.md` instructs `koto context remove`,
> which koto did not have when that line was written, so it failed on every
> run — quietly, because koto's migration noise makes `2>/dev/null` the
> routine operator reflex and that filter swallows the error too. The same
> passage also states its own mechanics backwards...

This is false against the file as it currently exists in this worktree. I read
`skills/work-on/references/phases/phase-4a-scrutiny.md` in full: it does not
call `koto context remove` anywhere, and no `2>/dev/null` appears in it or in
any other `/work-on` phase file (grep confirms). The current text instead
reads:

> 2. Do not try to delete it. `koto context` advertises `add`, `get`,
>    `exists`, and `list` — koto has no verb that removes a key. A stale
>    value is cleared by being overwritten, not by being deleted.

`git show 8e07f07` (shirabe PR #292, "feat(preflight): declare and verify
each skill's host prerequisites at load", merged 2026-08-16T02:55:00Z) shows
the diff that produced this: the old text — which *did* call
`koto context remove <WF> scrutiny_results.json` at line 45, exactly as the
brief describes — was deleted and replaced with the current
ignore-and-overwrite workaround, specifically because `koto context remove`
did not exist at the time. koto PR #196 ("feat(context): add `koto context
remove`") merged later the same day, 2026-08-16T17:19:18Z, after #292. So by
the time this brief was scoped (`wip/scope_work-on-retry-clearing_state.md`
records `chain_started: 2026-08-16T18:30:00Z`, after both merges), the file
no longer attempted the removal call at all — the brief describes a state of
the file that had already been superseded roughly sixteen hours earlier.

This matters for content quality specifically because "stands alone" and
factual grounding are part of what makes a Problem Statement legible: a
reader who opens the cited file after reading the brief will find a
contradiction, not confirmation. It also means the "what needs to change"
framing in Problem Statement/Scope Boundary is subtly wrong for this one
file: `phase-4a-scrutiny.md` does not need its existing `koto context remove`
call restored — it needs a *new* removal call added on top of a workaround
that itself needs to be retired, and that workaround's own claim ("koto has
no verb that removes a key") is now the second stale claim in the same
passage. The underlying thesis of the brief (presence gates on six keys are
unsound; `koto context remove` now being available is the fix) still holds —
but the specific "one phase already tried and failed, quietly, via
`2>/dev/null`" narrative used to motivate it does not match the repository.

### Advisory

- Frontmatter `outcome` and Scope Boundary IN prose name the specific
  mechanism ("through one verb that koto now ships") rather than staying
  purely outcome-shaped. Not blocking — BRIEFs are allowed sub-structure and
  this doesn't turn into a feature list — but it leans closer to solution
  language than the rubric's example outcome sentence.

### What checks out

- Problem Statement's core structural claims (twelve `context-exists` gates,
  six unsound by key, deferral_approval's specific stale-read argument) are
  accurate — see fact_check below.
- User Outcome is outcome-shaped and names who benefits (the agent whose work
  is sent back; a maintainer reading the phase files).
- User Journeys: five journeys, each with a named user/role, a concrete
  trigger, and a distinct outcome shape (review-panel retry, plan-rewrite
  retry, finalization/deferral retry, clearing-step failure, maintainer edit
  regression-test). Genuinely distinct entry points, not one path retold.
- Scope Boundary has real IN items (six named keys, five named files, a
  failure-mode requirement, a test-coverage requirement, an evals-update
  requirement) and real OUT items, including two exclusions a downstream
  author could plausibly assume were in scope (changing gate types; the
  `context_assignments:` no-op) — verified the no-op claim structurally
  (see fact_check).
- No PRD-level requirements, DESIGN-level architecture, or implementation
  tasks — the document stays at framing altitude throughout.

## Role 2: Structural Format — PASS

Ran the validator:

```
./target/release/shirabe validate docs/briefs/BRIEF-work-on-retry-clearing.md --format json --visibility=Public
```

Result: `"outcome": "clean"`, 0 errors, 0 notices.

- FC01 (required frontmatter fields): `schema: brief/v1`, `status: Draft`,
  `problem:` and `outcome:` all present as literal block scalars.
- FC02 (valid status): `Draft` is a valid value.
- FC03 (frontmatter/body Status match): body `## Status` first non-blank line
  is the bare word `Draft`, matching frontmatter exactly; explanatory prose
  follows after a blank line, correctly deferred.
- FC04 / FC15 (required sections, canonical order): Status, Problem
  Statement, User Outcome, User Journeys, Scope Boundary all present in
  order, followed by optional References.
- Public-visibility clean: no `private/` paths, no private-repo issue
  numbers. The one citation, `tsukumogami/koto#196`, is a public repo.
- References resolves: `gh pr view 196 --repo tsukumogami/koto` returns a
  real, MERGED PR titled "feat(context): add `koto context remove`" —
  matches the brief's description exactly.
- No open-questions-in-Draft issue, no downstream-artifacts durability issue
  (section not present).

No structural defects found.

## Fact-check detail

Verified true:

1. **Twelve `context-exists` gates in `skills/work-on/koto-templates/work-on.md`.**
   Counted directly: `context_injection` (context.md), `setup_issue_backed`
   (baseline.md), `setup_free_form` (baseline.md), `plan_context_injection`
   (context.md), `setup_plan_backed` (baseline.md), `introspection`
   (introspection.md), `analysis` (plan.md), `scrutiny`
   (scrutiny_results.json), `review` (review_results.json), `qa_validation`
   (qa_results.json), `finalization` (summary.md), `deferral_approval`
   (summary.md). = 12.
2. **The six named-unsound keys** (`scrutiny_results.json`,
   `review_results.json`, `qa_results.json`, `plan.md`, `summary.md` ×2 at
   `finalization` and `deferral_approval`) match exactly.
3. **The six sound gates genuinely cannot be re-entered** — traced the
   transition graph: `context_injection` and `plan_context_injection` are
   targeted only from `entry`, no other transition targets either; the three
   `setup_*` states are targeted once each (from `context_injection`,
   `post_research_validation`, and `plan_context_injection`/`plan_validation`
   respectively) with no downstream loop-back; `introspection` is targeted
   only from `staleness_check` and nothing loops back to it. All six are
   reached at most once per run.
4. **`deferral_approval` argument**: exactly one transition targets it (from
   `finalization` on `deferral_requested`); `deferral_approval` itself has no
   self-loop and nothing else targets it, so it is entered at most once.
   But `finalization` sits on a real cycle (`issues_found` → `implementation`
   → panels/verification → `finalization` again), and both states gate on
   the same key `summary.md`. So a `deferral_approval` visit reached after a
   `finalization` round-trip can still be looking at a `summary.md` written
   during an earlier, stale `finalization` pass — the brief's claim is
   structurally accurate.
5. **`koto context remove` exists in the installed koto.** `koto context
   --help` lists `remove — Remove a key and its content (idempotent:
   succeeds if already absent)`.
6. **`tsukumogami/koto#196` resolves** and matches its description (see
   Role 2 above).
7. **`context_assignments:` is dropped at compile time.** Read
   `public/koto/src/template/types.rs:136-140`: `pub struct Transition { pub
   target: String, pub when: Option<...> }` — no `context_assignments`
   field. Confirms the Scope Boundary's OUT claim that every
   `failure_reason` assignment in `work-on.md`'s `context_assignments:`
   blocks is a no-op.

Verified false / stale:

1. **"`phase-4a-scrutiny.md` instructs `koto context remove`... failed on
   every run... `2>/dev/null` swallows the error... states its own mechanics
   backwards."** The current file does not call `koto context remove` and
   contains no `2>/dev/null`; it explicitly documents that koto has no
   remove verb and uses an overwrite-based workaround instead. This was true
   of the file before commit 8e07f07 (shirabe #292, merged
   2026-08-16T02:55:00Z), which deleted exactly that call and passage. koto
   #196 (merged 2026-08-16T17:19:18Z, later the same day) is what actually
   added `koto context remove`. The brief was scoped after both merges
   (18:30Z) but narrates the pre-#292 state as current.

## Content re-review

Re-read `docs/briefs/BRIEF-work-on-retry-clearing.md` after the rewrite and
diffed the Problem Statement against `skills/work-on/references/phases/`
directly. Both quoted passages are verbatim and in the context the brief
claims:

- `> Do not try to delete it. \`koto context\` advertises \`add\`, \`get\`,
  \`exists\`, and \`list\` — koto has no verb that removes a key.` matches
  `phase-4a-scrutiny.md` line 48 exactly (the brief truncates before "A
  stale value is cleared by being overwritten..." but that's a legitimate
  partial quote, not a misquote), and the brief's framing — "carries a Retry
  Loop section telling the agent to ignore the stale artifact, and then:"
  — matches the file's actual structure (step 1 is "Ignore whatever
  `scrutiny_results.json` is already in context," step 2 is the quoted
  sentence).
- `> what keeps an earlier pass from advancing the workflow is the
  \`scrutiny_outcome\` you submit, which must always describe the round
  that just ran.` matches line 52 verbatim, and it genuinely is the last
  sentence of the Retry Loop section before `## Escalation`, so "The section
  closes by naming what actually holds the line today" is accurate.

Grepped the whole `skills/work-on/` tree for `koto context remove` and
`2>/dev/null`: zero hits tied to koto context calls anywhere (the only
`2>/dev/null` occurrences are unrelated `grep`/`find`/`go test`
suppressions in `extract-context.sh` and the template). The brief no longer
claims either exists in the current file — the earlier blocking narrative
is gone.

**Current-defect characterization**: the brief now correctly describes an
agent-discipline guarantee, not a structural one — "The guarantee is the
agent's submitted outcome — prose an agent can skip." and "Nothing
structural stops a `passed` submission from advancing on last round's
artifact, because the gate cannot tell the rounds apart." Both are true of
the gate as implemented (`context-exists` on `scrutiny_results.json`,
verified in the prior pass's fact-check). It also correctly flags the
now-false "koto has no verb that removes a key" claim as stale, immediately
noting "koto has had one since v0.11.5" — verified: `git log
v0.11.4..v0.11.5 --oneline` in the koto repo shows `feat(context): add
\`koto context remove\` (#196)` landed exactly in that release range.

**"Other five gates have no clearing prose" claim**: read
`phase-4b-review.md`, `phase-4c-qa.md`, `phase-3-analysis.md`, and
`phase-5-finalization.md` in full. None contains a Retry Loop section or
any prose about what happens to `review_results.json`, `qa_results.json`,
`plan.md`, or `summary.md` on re-entry — confirmed accurate. The brief
names only four files for five gates (review, qa_validation, analysis,
finalization, deferral_approval) because `finalization` and
`deferral_approval` are both documented in the single file
`phase-5-finalization.md` — grepped the skill tree for `deferral_approval`
and confirmed no separate phase file exists for it. `review-panel-
orchestration.md`, also cited in Scope Boundary IN, exists at
`skills/work-on/references/review-panel-orchestration.md`.

**"Not a re-fix of the filed issue" framing**: the brief now says plainly
that the issue's literal complaint (a phase file instructing a subcommand
koto didn't have) "is resolved" and "that instruction is gone from the
tree," and frames the brief's actual scope as the surviving defect the
instruction was aimed at. This matches the repository state and no longer
claims to be fixing the filed issue's literal text.

**No new factual errors found.** Checked the frontmatter `problem:` block,
the "why this brief is being written a second time" paragraph, the
`koto v0.11.5` citation, and the `review-panel-orchestration.md` and
`tsukumogami/koto#196` references — all verified against the tree and the
koto repo's git history.

**Earlier advisory (User Outcome naming a mechanism verb): resolved.**
Grepped the document for `verb`, `koto context remove`, and `removal`: none
of the hits fall inside the frontmatter `outcome:` block (lines 11-15) or
the `## User Outcome` section (lines 89-104) — both are now purely
outcome-shaped, with no mechanism named. The remaining "verb"/"removal"
mentions are in the Problem Statement (describing the stale claim to be
corrected), Scope Boundary IN/OUT (legitimate scope-defining detail: which
file gets corrected, why six keys instead of three, and an explicit OUT
item that adding to koto is not in scope), and References (a citation) —
none of which the rubric treats as solution-smuggling for a BRIEF, which is
allowed sub-structure in Scope Boundary.

**Content rubric on changed sections**: Problem Statement stands alone —
it states the mechanism defect, quotes the current file accurately, and
explains why the brief exists a second time without requiring the reader to
chase git history to follow it. No solution is smuggled into Problem
Statement itself (the "correcting the claim" language lives in Scope
Boundary, where it belongs).

Verdict: PASS. The blocking finding from the prior pass is resolved and no
new blocking issue was introduced by the rewrite.
