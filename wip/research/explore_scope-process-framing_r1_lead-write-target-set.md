# Lead: Can `/scope` state its closed write-target set without publishing every artifact address in the chain — and if so, how?

## Findings

### 1. What the shared contract actually binds

`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` (plugin cache
`/home/dgazineu/.claude/plugins/cache/shirabe/shirabe/0.18.1-dev/references/parent-skill-security.md`),
section `## Closed Write-Target Set`, lines 47-73. The binding language, verbatim:

> A parent's filesystem writes are confined to an enumerated set
> declared in the parent's SKILL.md. Writes outside this set fail the
> R9 hard-finalization check.

and, closing the section:

> The per-parent SKILL.md names the concrete paths against the parent's
> chain shape; the pattern-level rule is that the set SHALL be
> enumerable and the R9 check SHALL enforce membership.

Three things follow, and they matter for every option below.

- **SKILL.md specifically is named, twice.** "declared in the parent's
  SKILL.md" and "The per-parent SKILL.md names the concrete paths". This is
  not a generic "must exist somewhere and be authoritative" requirement.
  Relocating `/scope`'s enumeration into a reference file would put `/scope`
  out of conformance with a pattern-level reference shared with `/charter` —
  and amending that reference is outside the stated blast radius (`/scope`
  only).
- **"Concrete paths" is explicit.** A derivation rule ("whatever path the
  child at this hop writes") does not satisfy the text as written. The
  pattern-level shape the reference itself lists is already path-shaped:
  "Durable artifact paths under `docs/<type>/<TYPE>-<topic>.md` for the
  chain's terminal artifact and any force-materialized partial"
  (parent-skill-security.md:57-59). The generic pattern in the *shared*
  reference already discloses that the terminal artifact lives at
  `docs/<type>/<TYPE>-<topic>.md`.
- **The only enforcement named is R9**, a hard-finalization check performed
  by the skill itself in prose. Nothing mechanical reads the set (see §4).

### 2. `/charter` is not a counterexample — it discloses its terminal address too

`skills/charter/SKILL.md:334-352`, `**Closed write-target set.**`:

> `/charter` writes to exactly six places: the state file at
> `wip/charter_<topic>_state.md`, the `/roadmap` handoff at
> `wip/roadmap_<topic>_scope.md`, Decision Records under `docs/decisions/`,
> the force-materialized partial artifact its abandonment path produces
> under `docs/strategies/` (plus the `git rm` of a rejected Draft at the same
> path), the removal of the `/explore` handoff at
> `wip/charter_<topic>_handoff.md` once a run has consumed it, and the `wip/`
> cleanup its finalization performs.

and, in the same paragraph, the sentence that rules out any "rule instead of
paths" reading:

> the set is a closed list of concrete paths, so a path `/charter` touches
> and the list omits is outside the set.

So `/charter` states directory-level `docs/strategies/` rather than a
brace-expanded filename pattern. But `/charter` discloses the full terminal
address anyway, 175 lines earlier, in `## Topic-Slug Constraint`
(`skills/charter/SKILL.md:163-166`):

> The topic slug appears in the state-file path
> (`wip/charter_<topic>_state.md`), the terminal artifact filename
> (`docs/strategies/STRATEGY-<topic>.md`), and downstream child wip/ paths.

`docs/strategies/` also appears at `skills/charter/SKILL.md:34` in the
Overview. **The difference between the two skills' security sections is
cosmetic on the disclosure axis.** `/scope` prints the brace expansion in the
security section; `/charter` prints the same information in the slug section.
Both parents publish their chain's terminal address in SKILL.md, and both do
it outside the security section as well as inside it.

The one substantive difference is that `/charter`'s security section names
`docs/strategies/` only in the *abandonment* role (force-materialized
partial + `git rm` of a rejected Draft), because on a normal `/charter` run
the parent doesn't mutate the STRATEGY — `/scope`'s Phase 2 absorb does
mutate the survivor, which is why `/scope` has a Mutations entry at all
(`skills/scope/SKILL.md:845-855`).

### 3. The terminal address is disclosed in SKILL.md 818 lines before the security section

This is the finding that decides the lead.

`skills/scope/SKILL.md:29`, second paragraph of the Overview, in the sentence
that introduces the skill:

> ... lands at one of three terminal exits: a `full-run` that produces a PLAN
> at `docs/plans/PLAN-<topic>.md`, a `re-evaluation` exit that writes a
> Decision Record ...

Every other artifact address in the chain is likewise disclosed in SKILL.md
outside Security Considerations:

| Location | What it discloses |
|---|---|
| `skills/scope/SKILL.md:29` | `docs/plans/PLAN-<topic>.md` — Overview, paragraph 2 |
| `skills/scope/SKILL.md:94` | `docs/prds/PRD-foo.md` as a rejected input example |
| `skills/scope/SKILL.md:588` | `docs/plans/PLAN-<topic>.md` — Three Exit Paths, `full-run` binding |
| `skills/scope/SKILL.md:762-766` | all four: `docs/{briefs,prds,designs/current,designs,plans}/<TYPE>-<topic>.md`, then each spelled out |
| `skills/scope/SKILL.md:837-839, 847` | the Security Considerations enumeration (the address cited in #331) |

And in material `/scope` loads during a run:

| File | Lines | What it discloses |
|---|---|---|
| `skills/scope/references/phases/phase-1-discovery.md` | 62-65, 156-159, 519-522 | all four paths, twice as a table keyed by child |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | 185-187, 271-275 | the per-child input table *and* per-child output paths |
| `skills/scope/references/phases/phase-3-exit-finalization.md` | 45, 55, 145-147, 369-374 | the restatement of the write-target set |
| `skills/scope/references/phases/phase-4-cleanup.md` | 51-56, 133-135 | `exit: full-run → docs/plans/PLAN-<topic>.md`, plus a worked example |
| `skills/scope/references/phases/phase-resume.md` | 18, 26, 37, 48 | all four, as resume-ladder glob targets |
| `skills/scope/references/state-schema.md` | 133-134 | `absorbed:`/`into:` example paths |

And outside `/scope` entirely, in material an agent very plausibly already holds:

- `skills/plan/SKILL.md:44` — "Plans live at `docs/plans/PLAN-<topic>.md`."
  Also 456, 510, 527, 537, 542.
- `skills/design/SKILL.md:121, 209`; `skills/prd/SKILL.md:41, 186`;
  `skills/brief/SKILL.md:62, 320` — each child publishes its own address in
  its own SKILL.md.
- `skills/explore/references/phases/phase-4-crystallize.md:73-79` and
  `phase-5-produce-execute.md:4, 21-22` — the routing tables glob
  `docs/plans/PLAN-*.md` and print `/execute docs/plans/PLAN-<name>.md`.
- Repo `CLAUDE.md` — only one such path
  (`docs/designs/current/DESIGN-decision-framework.md`, line 15), so CLAUDE.md
  is *not* a disclosure channel here. That is the one place the lead expected
  a hit and didn't get one.

**Conclusion: removing or relocating `skills/scope/SKILL.md:847` changes
nothing about what an agent knows.** The identical information is at line 29
of the same file, in the paragraph that defines what the skill is. An agent
that reads SKILL.md at all reads line 29.

### 4. Nothing mechanical reads the set — so no validator cost to any option

`grep -rn "SKILL.md" crates/ --include=*.rs` returns exactly one hit,
`crates/shirabe/src/populate.rs:13`, and it is a doc comment pointing at
`skills/roadmap/SKILL.md` for where logic lives — not a read.

The `"Security Considerations"` string does appear in `crates/`
(`crates/shirabe-validate/src/formats.rs:311`,
`crates/shirabe-validate/src/validate.rs:717`), but in both cases it is an
entry in the **required-sections list for `design/v1` documents** — i.e.
DESIGN docs authored by `/design`, not skill SKILL.md files. Confirmed by
reading the surrounding `FormatSpec` (`formats.rs:300-316`) and the
`required_sections` table (`validate.rs:705-719`).

So: R9 hard-finalization is a prose check the skill performs on itself. No
CI job, no Rust check, and no test parses the write-target enumeration.
**Any of the options below costs zero validator work.** The only "breakage"
available is conformance against the shared prose reference.

### 5. The sentence that actually sanctioned the shortcut is not in the security section

`skills/scope/SKILL.md:442-445`, in `## Chain-Proposal Output`, immediately
after the paragraph explaining that the proposal never offers a shorter chain:

> An author who wants to start above `/brief` still invokes `/design` or
> `/plan` directly. That buys a shorter conversation, not a smaller artifact
> set: inside `/scope`, the set is settled per hop after the artifacts land.

That sentence tells the reader, in SKILL.md, before Phase 2, that invoking
`/plan` directly is a sanctioned move. Combined with line 29's disclosure of
the PLAN's address and the `## Why the Artifact Set Shrinks` argument at
472-531, an agent has the address, the licence, and the motive — none of
which come from the security section.

### 6. And `/plan` itself advertises the direct entry, in its skill description

`skills/plan/SKILL.md` frontmatter `description:`:

> Also use for direct topic planning without a source document.

Skill descriptions are loaded into every session's skill listing. So the
sink-and-source property the issue proposes ("an agent holding no DESIGN
should have nothing to give `/plan`") is contradicted by `/plan`'s own
advertised contract, in material that is loaded *before* `/scope` is even
invoked. Closing that would mean editing `/plan`, which is outside the stated
blast radius.

## Implications

- The issue's claim that "the security enumeration hands over every address
  in the chain up front, and it wins by default because it is stated early
  and unconditionally" is true about *disclosure* but false about
  *attribution*. The enumeration at line 847 is the last of at least five
  disclosures in SKILL.md and the 818th line after the first one. It is not
  where the address leaks; it is where the address is *bounded*.
- Progressive-disclosure-as-correctness (the issue's framing) cannot be
  achieved for the PLAN's path within the `/scope`-only blast radius. The
  path is in `/plan`'s SKILL.md, in `/explore`'s routing tables, and in
  `/scope`'s own Overview sentence. Treating one enumeration as the leak and
  fixing it there would leave the property unmet and the issue closed.
- What *is* achievable in-scope, and what the evidence points at, is changing
  the **status** of the disclosure rather than its **presence**: a path can be
  named as a bound on writing without being named as an available
  destination. Nothing in the shared reference requires the enumeration to
  read as an invitation, and nothing forbids the enumeration from carrying a
  sentence saying what membership in the set does and does not license.
- The `/charter` control cuts the other way from how #331 uses it. #331 is
  right that `/charter` lacks the `## Why the Artifact Set Shrinks` and
  `## Consolidation Judgment` sections, and right that removing them restores
  parity. But `/charter` is *not* a control for write-target disclosure: it
  discloses `docs/strategies/STRATEGY-<topic>.md` in SKILL.md too, and it
  states plainly that its set "is a closed list of concrete paths". If
  disclosure-of-terminal-address were the defect, `/charter` would have it.

## Surprises

- **A real divergence inside the self-declared authoritative set.**
  `skills/scope/SKILL.md:822-832` declares itself "the authoritative
  declaration of the closed write-target set". Its abandonment entry
  (`skills/scope/SKILL.md:857-860`) reads "force-materialized partials under
  `docs/{briefs,prds,designs}/` on `abandonment-forced`". But
  `skills/scope/SKILL.md:762-766` — same file, 90 lines earlier — says the
  force-materialization target is
  `docs/{briefs,prds,designs/current,designs,plans}/<TYPE>-<topic>.md`, and
  `skills/scope/references/phases/phase-4-cleanup.md:55-56` agrees
  (`docs/{briefs|prds|designs|plans}/<TYPE>-<topic>.md`). So the authoritative
  set **omits `docs/designs/current/` and `docs/plans/`** from the
  abandonment entry, and an `abandonment-forced` exit triggered inside
  `/plan`, or against a Current-lifecycle DESIGN, writes outside the declared
  set and fails R9 for a reason unrelated to safety. This is exactly the class
  of defect the section's own "Three corrections are folded into that
  enumeration" paragraph (`skills/scope/SKILL.md:868-880`) says it was fixing
  — a fourth instance of the same bug survived. Out of this lead's scope to
  fix, but it should be filed.
- Repo `CLAUDE.md` is clean. It carries one artifact path and it is a
  citation, not a template. The "addresses are everywhere" finding comes
  entirely from skills, not from workspace context.
- `skills/scope/scripts/check-citations_test.sh` contains ~15 literal
  artifact paths, but as shell-test fixtures — no agent-facing disclosure.

## Open Questions

- Does R9's hard-finalization check, as `/scope` actually performs it, compare
  against the SKILL.md enumeration or against the Phase 3 restatement? If the
  latter, the "authoritative" claim at `skills/scope/SKILL.md:829-832` is
  aspirational and the abandonment-entry divergence above is live at runtime.
  Not resolvable from prose alone.
- Is the `docs/designs/current/` + `docs/plans/` omission from the
  abandonment entry in scope for this exploration's PR, or does it want its
  own issue? It is a security-contract defect, not a framing one.
- `/charter`'s security section names `docs/strategies/` at directory level
  and lets the slug section carry the filename. Is that split accidental or
  deliberate? If deliberate, it is a precedent for Option C below; if
  accidental, Option C has no precedent to lean on.

## Proposed Resolutions

All three keep the enumeration authoritative and stay inside prose-and-
placement, `/scope`-only.

**Option A — keep the enumeration; add one sentence that changes its status,
and fix the two sentences that actually license the shortcut.**

Three prose edits:

1. In `## Security Considerations`, immediately after the Mutations block
   (`skills/scope/SKILL.md:847-855`), add a bounding clause. Something in the
   register of: *"This set bounds what `/scope` may write. It does not
   license a write, and it is not a list of destinations a run may address.
   A path in this set becomes writable only at the hop that produces it,
   from the input that hop consumes; an agent holding no DESIGN has nothing
   to give `/plan`, and `docs/plans/` appearing here does not change that."*
2. Rewrite `skills/scope/SKILL.md:29` so the first disclosure of the PLAN's
   address carries the sink-and-source framing rather than presenting the
   path as the skill's deliverable — "a `full-run` in which `/plan` consumes
   the DESIGN and deposits `docs/plans/PLAN-<topic>.md`" rather than "a
   `full-run` that produces a PLAN at `docs/plans/PLAN-<topic>.md`".
3. Rewrite `skills/scope/SKILL.md:442-445`. As written it tells the reader
   that invoking `/plan` directly is a sanctioned alternative. It should say
   what such an invocation actually gives up: a `/plan` invoked with no
   DESIGN plans against a topic string, not against a design, and that is a
   different and weaker thing than the chain's terminal hop.

Cost: zero validator work; zero conformance risk (the enumeration stays in
SKILL.md, still concrete, still closed); the shared reference is untouched.
It does not remove any disclosure — see the recommendation for why that is
correct rather than a shortfall.

**Option B — relocate the enumeration out of SKILL.md into
`skills/scope/references/security-write-targets.md`, leaving a pointer.**

Cost: breaks conformance with parent-skill-security.md's "declared in the
parent's SKILL.md" and "The per-parent SKILL.md names the concrete paths",
which would have to be amended — and that reference is shared with `/charter`
and any future parent, so the edit leaves the stated blast radius. Zero
validator work (nothing parses it). **And it buys nothing**: the PLAN's
address remains at `skills/scope/SKILL.md:29`, `:588`, `:764-766`, in every
child's SKILL.md, and in `/explore`'s routing tables. This is the option the
issue implies, and on the evidence it is theatre — it would close #331's
fourth bullet without changing what any agent knows.

**Option C — restate `/scope`'s set `/charter`-style: directory-level places
in prose, composed from the validated slug, instead of the brace-expanded
glob.**

Replaces `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md` with prose
naming the three survivor directories. Cost: zero validator work; conformance
holds only if "the survivor artifact of the hop, under `docs/prds/`,
`docs/designs/`, or `docs/plans/`" still counts as "concrete paths" — it
matches what `/charter` does, so precedent says yes. Buys the removal of one
copy-pasteable literal string. Given §3, that is close to zero real gain, and
it costs precision in a section whose value is precision.

**Recommendation: Option A.**

The lead asked whether `/scope` can state its set without publishing the
chain's addresses. The answer is no — and it does not matter, because
`/scope` publishes those addresses five other times in the same file and
every child publishes its own. The write-target enumeration is not the
disclosure channel; it is one of six, and the last one a reader reaches.

What the enumeration *does* uniquely contribute is the impression that the
set is a menu. That is fixable in one sentence without touching the contract,
and fixing it there is honest: the security section keeps doing its job, and
the reader is told what membership in the set means. Pair it with the two
sentences that actually gave the shortcut its licence — the Overview's framing
of the PLAN as a product rather than a deposit (`:29`), and the explicit
"still invokes `/design` or `/plan` directly" (`:442-445`) — and the fix lands
where the causation is.

Option B should be explicitly rejected in the write-up, with the §3 table as
the reason, so the issue's fourth bullet is answered rather than dropped.

## Summary

The write-target enumeration at `skills/scope/SKILL.md:847` is not where the chain's addresses leak: `docs/plans/PLAN-<topic>.md` appears at `skills/scope/SKILL.md:29` in the Overview's second paragraph, again at `:588` and `:764-766`, in all six `/scope` phase references, in `/plan`'s own SKILL.md (`:44`), and in `/explore`'s routing tables — so relocating that one enumeration changes nothing an agent knows and would be theatre.
`parent-skill-security.md:49-73` binds the set to SKILL.md by name twice ("declared in the parent's SKILL.md", "The per-parent SKILL.md names the concrete paths") and requires concrete paths, so relocation also breaks a shared reference outside the blast radius; `/charter` is no control, since it discloses `docs/strategies/STRATEGY-<topic>.md` at `skills/charter/SKILL.md:166` and states its set "is a closed list of concrete paths" — nothing in `crates/` parses either set, so every option costs zero validator work.
Recommend keeping the enumeration and adding one clause that it bounds writes rather than licensing them, plus rewriting the two sentences that actually sanctioned the skip (`:29`'s framing of the PLAN as the product, and `:442-445`'s "An author who wants to start above `/brief` still invokes `/design` or `/plan` directly"); separately, the self-declared authoritative set omits `docs/designs/current/` and `docs/plans/` from its `abandonment-forced` entry (`:857-860`) while `:762-766` and `phase-4-cleanup.md:55-56` include both — a live R9 defect worth its own issue.
