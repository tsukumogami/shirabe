# Phase 4 Jury — Testability Review

**Artifact:** `docs/prds/PRD-scope-chain-mandatory-steps.md`
**Rubric:** `skills/prd/references/prd-format.md`, Acceptance Criteria quality guidance
**Reviewer role:** testability

## Verdict

**FAIL**

The criteria are unusually strong for a prose-refactor PRD — most name a file
and a determinate condition, and most correctly fail today. But five are not
binary, one passes trivially in its literal form, one is over-broad enough to
be unsatisfiable, two conflict with each other, one contradicts the requirement
it verifies, and four requirements (R5, R13, R15, R19) carry no criterion at
all. R19 is the one that matters most: it is the clause that keeps a handoff
artifact from pre-supplying filesystem state a parent must re-read, and nothing
verifies it.

## Per-Criterion Verification Table

Criteria numbered in document order (AC1 = first checkbox at line 346).

| # | Criterion (abbrev) | How to verify | Well-formed? | Passes trivially today? |
|---|---|---|---|---|
| AC1 | pattern contains mandatory/post-hoc statement, findable without opening a skill dir | Read `references/parent-skill-pattern.md` Gate Vocabulary head | Partly — "a reader can find it" is subjective; R1 pins the location, the AC does not | No |
| AC2 | searching pattern + state schema for "the model's vocabulary" returns the new statement rather than nothing | `grep -E 'consolidat\|absorb\|fold\|worth\|earn' references/parent-skill-*.md` | **No** — vocabulary unnamed, and the pre-state is not "nothing" (see Commands Run) | No, but the stated premise is false |
| AC3 | ALWAYS declination clause names three properties, each verifiable against `/charter`'s roadmap prompt | Read the clause; check property 3 against `skills/charter/references/phases/phase-finalization.md:85` | Partly — property 1 (non-interactive invokes the child) is a runtime behavior, not checkable against a prompt | No |
| AC4 | pattern states Adjust's chain-membership reach is per-parent; both parents state which they have | grep `Adjust` in pattern + both parents' chain-proposal sections | Yes | No |
| AC5 | `chain_skipped[].reason` closed vocabulary; every reason either parent writes maps to a member; no member expresses a worth judgment | Read the enum (finite), grep reason strings in `skills/scope/`, `skills/charter/` | Yes — the negative universal is over a finite enum, so it is readable | No |
| AC6 | both parents write the same `chain_skipped` entry key; eval strings match | `grep -rn 'chain_skipped' skills/scope skills/charter references` | Yes | No — `/scope` writes `name:`, `/charter` writes `child:` |
| AC7 | `/execute` in the pattern's parent roster | `grep -n execute references/parent-skill-pattern.md` | Yes | No |
| AC8 | `/charter` names `/comp` in exactly one way across state schema and Phase 2 | Read both | **No** — "in exactly one way" is not a condition; R8 states the checkable form | No |
| AC9 | `/charter` Phase 1 Adjust cannot drop a child without a recorded ground | Read `skills/charter/references/phases/phase-1-discovery.md` Adjust wording | Yes (reading, not grep) | No |
| AC10 | `/explore` names no chain-internal child as a routing destination; grep returns "only references that are not routing destinations" | The stated grep | **No** — see below; 80 hits, judgment per hit | No |
| AC11 | `/explore` names `/scope`, `/charter`, `/execute` | `grep -rEo '/scope\b\|/charter\b\|/execute\b' skills/explore/` | Yes | No — all three are 0 today |
| AC12 | `/explore` writes no file under `docs/designs/` | `grep -rn 'docs/designs' skills/explore/` | Yes | No — 2 hits in `phase-5-produce-design.md` |
| AC13 | every skill destination in `skills/explore/` resolves to a directory under `skills/` | Enumerate `/token`s, check `skills/<token>/` | **No** — over-broad; catches `/triage`, `/issue`, `/cleanup`, which R16 does not target | No, but unsatisfiable as written |
| AC14 | competitive-analysis handler routes to `/comp`, writes no `docs/competitive/` file | Read `crystallize-framework.md:134` + the handler | Yes | No |
| AC15 | handoff path matches no Slot 5/6 condition in `/scope`, no row-8 condition in `/charter` | Read both ladders against the chosen path | Yes, but narrower than R17 (which says *no* existing ladder condition in either parent) | No |
| AC16 | `/scope` Slot 7 and `/charter`'s handoff clause enter Phase 1, not a child; each exercised by a new eval scenario | Read both; grep the new scenario names | Yes — and better-worded than R18 (see Required Changes #7) | No |
| AC17 | placing `wip/prd_<topic>_scope.md` + `/scope <topic>` no longer re-invokes `/prd` | Read `phase-resume.md:71` glob; or run the eval | Yes | No — Slot 6.3 globs `wip/prd_<topic>_*` today |
| AC18 | placing `wip/vision_<topic>_scope.md` + `/charter <topic>` no longer jumps into `/vision` | Read `skills/charter/.../phase-resume.md:58` | Yes | No — row 8 matches that exact filename |
| AC19 | slug re-validation rule enumerates Slot 7 | `grep -n 'Slot 5 or Slot 6' skills/scope/references/phases/phase-resume.md` | Yes for `/scope`; silent on `/charter` | No — line 141 says "any Slot 5 or Slot 6" |
| AC20 | chain proposal still has three option tokens; justification drops the "cannot produce a smaller set" claim | grep the tokens; read the justification | Yes | Half — the three tokens are already there |
| AC21 | Bail at Phase 1 reaches a defined terminal state; an eval scenario exercises it | Read Phase 1 bail branches; grep evals for the scenario | Yes | No |
| AC22 | `phase-1-discovery.md` contains no passage offering direct invocation as the route to a smaller set, and no self-contradicting passage | Read the file | Partly — first clause is checkable; "no passage contradicting another passage in the same file" is an unbounded judgment | No |
| AC23 | `chain_revised:` absent everywhere, or defined in `/scope`'s state schema with a stated reader | `grep -rn chain_revised skills/` | Yes | No — 2 hits in `phase-1-discovery.md`, 0 in `state-schema.md` |
| AC24 | post-`/prd` gate confirmation has an options block and a recorded answer, or is gone | Read `phase-2-chain-orchestration.md` | Yes (reading) | No |
| AC25 | `/scope`'s state schema enumerates every `chain_skipped` reason the skill writes | Set-compare grep output against the schema list | Yes, mechanical enough | No |
| AC26 | no `/scope` scenario asserts a floor, names `absorbable:`, or reasons from a required-section list | grep for `absorbable`, `durable-artifact floor`; third clause by reading | **Partly** — clauses 1-2 greppable, clause 3 is judgment and implicates a scenario AC27 wants preserved | No |
| AC27 | consolidation scenario count in `skills/scope/evals/evals.json` not lower than before | Count `"name": "consolidation-*"` | **No** — "consolidation family" undefined and the baseline number is not recorded | Yes, vacuously — no baseline to compare against |
| AC28 | `/scope` and `/charter` assert the chain-proposal triad the same way | Read both eval suites | **No** — "the same way" is not a condition; R29 states the checkable form (per-token) | No |
| AC29 | no scenario in `/explore`, `/roadmap`, `/vision`, `/decision` asserts `/explore` hands off to a chain-internal child | grep `/explore` in the four suites | Yes | No |
| AC30 | the two `explore-handoff-detection` scenarios still pass unchanged | Run `claude plugin eval` on roadmap + vision suites | **No** — "still pass" needs a graded LLM run; and it conflicts with AC29 (see #5) | Cannot be run determinately |
| AC31 | `chain-shape-is-constant` retains its 1st, 2nd, 4th expectations verbatim | `git diff` on `skills/scope/evals/evals.json` | Yes — and correct against the file; R31 is the one that is wrong | Yes if nothing is changed |
| AC32 | `/charter`'s four roadmap-declination scenarios byte-identical to pre-change | `git diff` | Yes | Yes if nothing is changed |
| AC33 | every re-targeted scenario carries an assertion array | Inspect the diff's touched scenarios | Yes | Yes, vacuously, if nothing is re-targeted |
| AC34 | `references/pipeline-model.md` describes no `/explore`→chain-interior route and no classification-driven Skip | Read the file | Yes (reading) | No |
| AC35 | `shirabe validate` reports zero errors across `docs/` | The literal command | **No** — `shirabe validate` with no FILES validates nothing and exits 0 | **Yes, trivially, right now** |

## Commands Run

### 1. The fragile `/explore` grep (AC10)

```
$ grep -rEc '/(brief|prd|design|plan|vision|strategy|roadmap)\b' skills/explore/ | sort -t: -k2 -rn
skills/explore/SKILL.md:12
skills/explore/references/phases/phase-5-produce.md:8
skills/explore/evals/evals.json:8
skills/explore/references/phases/phase-5-produce-vision.md:7
skills/explore/references/phases/phase-5-produce-roadmap.md:7
skills/explore/references/phases/phase-5-produce-plan.md:7
skills/explore/references/phases/phase-5-produce-prd.md:6
skills/explore/references/quality/crystallize-framework.md:5
skills/explore/references/phases/phase-5-produce-design.md:3
skills/explore/references/label-reference.md:3
skills/explore/references/phases/phase-5-produce-deferred.md:1
(all other files: 0)

$ grep -rEo '/(brief|prd|design|plan|vision|strategy|roadmap)\b' skills/explore/ | wc -l
80
```

**80 hits across 11 files.** The command runs and is deterministic, but the
stated pass condition — "returns only references that are not routing
destinations" — is not checkable. It asks a reader to classify 80 strings by
intent, one at a time, and it does not say what "not a routing destination"
looks like. Four distinct kinds of hit are in the output and only one is the
thing the criterion is hunting:

- **Real routing destinations** — `crystallize-framework.md:26` "Routes to
  /prd.", `phase-5-produce.md:40` "Auto-continues into /design".
- **Prose about a child's file format** — `phase-5-produce-prd.md:3` "matching
  /prd Phase 1's output format". Not a routing destination; survives R10.
- **Negative assertions in graded evals** — `evals.json:140` `"Transcript does
  NOT recommend /prd or /design as the first step"`. These are the scenarios
  that *guard* the model. The criterion would flag them as violations.
- **Commit-message templates** — `phase-5-produce-vision.md:41` "Commit:
  `docs(explore): hand off <topic> to /vision`".

The pattern also **under-matches**. `skills/explore/evals/evals.json:114` reads
`"Transcript describes invoking or handing off to /roadmap or /shirabe:roadmap
after the scope artifact is written"` — the `/shirabe:roadmap` form has no `/`
immediately before `roadmap`, so the grep misses it. Any plugin-qualified
destination escapes the check entirely.

The criterion needs restating. See Required Changes #1.

### 2. `shirabe validate` (AC35)

```
$ shirabe validate; echo "exit=$?"
exit=0
```

No output, exit 0. `shirabe validate --help` confirms `[FILES]...` is a
positional argument; with none supplied the tool validates nothing. **AC35 as
written passes today, before any work is done.** It verifies nothing.

Validating the actual chain does work and passes:

```
$ shirabe validate --format human docs/prds/PRD-scope-chain-mandatory-steps.md docs/briefs/BRIEF-scope-chain-mandatory-steps.md
All checks passed.
Advisory: Draft posture: no draft-tolerable findings to flag.
```

### 3. Pattern vocabulary (AC2)

```
$ grep -rEn 'consolidat|absorb|fold|worth|earn|mandator|post-hoc' references/parent-skill-pattern.md references/parent-skill-state-schema.md
references/parent-skill-state-schema.md:221:exit is a violation surface, not silently absorbed.
references/parent-skill-pattern.md:191:had no examples left and was folded into Mandatory-with-auto-skip's
references/parent-skill-pattern.md:254:prompt without learning about the parent that invoked it.
references/parent-skill-pattern.md:476:   `status:` value to learn the child's terminal exit (Accepted,
references/parent-skill-pattern.md:764:  `triggering_teammate:` field; the parent learns about it via the
```

The Problem Statement claims this search "returns nothing." It returns five
hits — `earn` inside "learn/learning", `absorb` inside "absorbed", `fold`
inside "folded". The *substance* of the claim holds (none of these state the
model), but AC2's pass condition ("returns the new statement rather than
nothing") is therefore not a mechanical check: a grep that already returns five
irrelevant hits cannot discriminate the new statement from the noise. The
criterion also never says which vocabulary to search.

### 4. `/explore` parent-skill mentions (AC11)

```
$ grep -rEo '/scope\b'   skills/explore/ | wc -l   -> 0
$ grep -rEno '/charter\b|/execute\b' skills/explore/  -> (no output)
```

Well-formed, deterministic, correctly fails today. A good criterion.

### 5. `/explore` writes under `docs/designs/` (AC12)

```
$ grep -rn 'docs/designs' skills/explore/
skills/explore/references/phases/phase-5-produce-design.md:5:**1. Design doc skeleton** at `docs/designs/DESIGN-<topic>.md`:
skills/explore/references/phases/phase-5-produce-design.md:67:- `docs/designs/DESIGN-<topic>.md` (new)
```

Well-formed, correctly fails today. A good criterion.

### 6. `chain_skipped` entry key divergence (AC6)

```
skills/scope/evals/evals.json:111    ... chain_skipped contains { name: prd, reason: ... }
skills/charter/evals/evals.json:188  ... chain_skipped carries a { child: roadmap, reason: ... } entry
skills/charter/references/phases/phase-finalization.md:85: `chain_skipped:` carries a `{child: roadmap, ...`
```

Confirms the divergence R6 names. Well-formed, correctly fails today.

### 7. Skill destinations that resolve to nothing (AC13)

```
$ grep -rn '/triage|/issue\b|/cleanup|/spike\b|/competitive-analysis' skills/explore/ --include=*.md
skills/explore/references/phases/phase-5-produce.md:58:            the user runs `/cleanup`.
skills/explore/references/phases/phase-5-produce-no-artifact.md:33: Create a focused issue with `/issue` ...
skills/explore/references/label-reference.md:20:  1. `/triage` or `/plan` (roadmap decomposition) assigns a `needs-*` label
skills/explore/references/quality/crystallize-framework.md:112: Routes to /spike.
skills/explore/references/quality/crystallize-framework.md:134: Routes to /competitive-analysis. Private repos only.
```

`skills/` contains: brief, charter, comp, decision, design, execute, explore,
inflight, plan, prd, private-content, public-content, release, review-plan,
roadmap, scope, strategy, vision, work-on, writing-style.

So `/cleanup`, `/issue`, and `/triage` also fail AC13 — they are tsukumogami
plugin skills living outside this repo, and R16 does not ask for them to be
removed. AC13 is unsatisfiable as written.

### 8. `chain-shape-is-constant` expectation ordinals (AC31 vs R31)

```
skills/scope/evals/evals.json:268  1. "Plan runs the whole chain and does not offer a shortened one"
                          :269  2. "Plan explains that skipping the BRIEF here would be a judgment about an unwritten document"
                          :270  3. "Plan points the author at invoking /design directly if they want to start above /brief"
                          :271  4. "Plan notes a redundant BRIEF is removed by the Phase 2 consolidation judgment, after both documents exist"
```

The contested redirect expectation is **third**, not fourth. AC31 ("retains its
first, second, and fourth expectations verbatim") is correct against the file.
**R31 is wrong** — it says "its fourth expectation SHALL be updated to match
R24's narrowed redirect." An implementer following R31 will rewrite the
consolidation expectation and preserve the stale redirect, which is the exact
inversion of the intent.

### 9. The two `explore-handoff-detection` scenarios (AC29 vs AC30)

```
$ grep -rn '/explore' skills/roadmap/evals/evals.json skills/vision/evals/evals.json skills/decision/evals/evals.json
skills/vision/evals/evals.json:25: "... Does not re-ask scoping questions that were already answered during /explore."
skills/vision/evals/evals.json:108: "prompt": "/explore --auto --strategic should we build a developer analytics dashboard"
skills/decision/evals/evals.json:66: "prompt": "/explore should we use WebSockets or Server-Sent Events ..."
skills/decision/evals/evals.json:93: "prompt": "/explore --auto --max-rounds=2 feasibility of WASM plugins"
skills/roadmap/evals/evals.json:92: "prompt": "/explore --auto --strategic improve CI pipeline reliability ..."
skills/roadmap/evals/evals.json:96: "Transcript recognizes this as an /explore command, not /roadmap directly"
```

`skills/vision/evals/evals.json:25` is the `explore-handoff-detection`
scenario's `expected_output`, and it names `/explore` as the origin of a handoff
consumed by `/vision` — a chain-internal child. AC29 forbids exactly that
sentence; AC30 requires the scenario to be "unchanged." They cannot both hold.

### 10. `/charter` has no Slot 7 (R18 / AC16)

```
$ grep -rn 'Slot [0-9]' skills/charter/references/phases/phase-resume.md
(no output)

$ grep -rn 'Slot 7' references/parent-skill-resume-ladder-template.md
references/parent-skill-resume-ladder-template.md:154:### Slot 7 — feeder-doc-detected

$ sed -n '48,62p' skills/charter/references/phases/phase-resume.md
7.  wip/strategy_<topic>_discover.md exists   -> Resume into /strategy
8.  wip/vision_<topic>_scope.md exists        -> Resume into /vision
```

`/charter`'s ladder uses no "Slot" vocabulary and its **row 7 is occupied**.
R18's claim that Slot 7 is a slot "which both name and leave empty today" is
false for `/charter`. AC16 hedges correctly ("`/charter`'s handoff clause"), so
the criterion is fine and the requirement is what needs fixing.

### 11. `/comp` membership contradiction (AC8 / R8)

```
skills/charter/references/phases/phase-state-management.md:255:planned_chain: [vision?, comp?, strategy, roadmap]
skills/charter/references/phases/phase-2-chain-orchestration.md:164: neither "skipping competitive analysis" nor the word /comp reaches a ...
```

The contradiction is real and the target site is `/charter`'s own
`phase-state-management.md:255`, not the shared
`references/parent-skill-state-schema.md` (which never mentions `/comp`).

### 12. Consolidation scenario count (AC27)

```
$ grep -n '"name":' skills/scope/evals/evals.json | grep -i consolidat
289:  "name": "consolidation-absorb-brief-into-prd",
304:  "name": "consolidation-keep-at-unmapped-hop",
317:  "name": "consolidation-carry-check-failure-aborts-absorb",
```

Three scenarios carry the `consolidation-` prefix. But the floor scenario R28
targets is `durable-artifact-floor-is-structural` (line 276), which does *not*
carry the prefix — so "the consolidation family" is undefined. And the criterion
compares against a "before this change" number the PRD never records. There are
also no `tags`/`category` fields in the file to group by.

Separately, `consolidation-absorb-brief-into-prd` (line 291) reasons explicitly
from a section mapping — "Problem Statement to Problem Statement, User Outcome
to Goals, User Journeys to User Stories, Scope Boundary to Requirements and Out
of Scope." AC26's third clause ("reasons from either type's required-section
list") arguably condemns it, while AC27 wants the count preserved.

## Required Changes

1. **Restate AC10.** The grep is not a test — it returns 80 hits and the pass
   condition asks for a per-hit intent judgment. Replace it with checks that
   have a determinate answer. Suggested: (a) `grep -rEn 'Routes to
   /(brief|prd|design|plan|vision|strategy|roadmap)\b'
   skills/explore/references/quality/crystallize-framework.md` returns nothing;
   (b) the `Auto-continues into` column of `phase-5-produce.md`'s handler table
   names no chain-internal child; (c) `skills/explore/SKILL.md`'s routing table
   and complexity table name no chain-internal child in their destination
   column. Scope each check to a named file and a named construct, not to the
   whole directory. If the directory-wide sweep is kept, exempt
   `skills/explore/evals/` explicitly (negative assertions there are the guard,
   not the defect) and make the pattern plugin-qualified-aware
   (`(/|shirabe:)(brief|prd|...)`) so `/shirabe:roadmap` cannot slip through.

2. **Fix AC35.** `shirabe validate` with no positional arguments validates
   nothing and exits 0 — the criterion passes right now. Give it the
   invocation: `shirabe validate --format human $(find docs -name '*.md')`
   reports zero errors, or use the lifecycle form
   `shirabe validate --lifecycle docs --mode ready`.

3. **Fix AC13's over-breadth.** As written it fails on `/cleanup`
   (`phase-5-produce.md:58`), `/issue` (`phase-5-produce-no-artifact.md:33`),
   and `/triage` (`label-reference.md:20`) — tsukumogami plugin skills that R16
   does not target. Narrow to R16's actual scope: "`skills/explore/` names
   neither `/spike` nor `/competitive-analysis`," or qualify as "every
   *shirabe* skill destination resolves to a directory under `skills/`."

4. **Resolve the R31 / AC31 ordinal contradiction.** In
   `skills/scope/evals/evals.json`, the contested redirect expectation is the
   **third** (line 270) and the consolidation expectation is the **fourth**
   (line 271). AC31 is correct; R31's "its fourth expectation SHALL be updated"
   is wrong and will produce the inverse edit. Fix R31 to say "third," or drop
   the ordinal from both and identify the expectation by its content.

5. **Resolve the AC29 / AC30 conflict.** `skills/vision/evals/evals.json:25`
   (the `explore-handoff-detection` scenario's `expected_output`) contains
   "already answered during `/explore`" — a claim that `/explore` hands a
   scoping artifact to `/vision`, a chain-internal child. AC29 forbids it; AC30
   requires the scenario unchanged. Either carve the receiving-side scenarios
   out of AC29 explicitly, or amend AC30 to "unchanged apart from removing the
   `/explore` attribution from `expected_output`."

6. **Replace AC30's "still pass" with a diff check.** Every other
   scenario-preservation criterion in this PRD uses a textual standard
   (AC31 "verbatim", AC32 "byte-identical"), which `git diff` settles. "Still
   pass" requires a graded LLM eval run, which is neither cheap nor
   deterministic, so the criterion has no reliable binary answer. Make it
   "byte-identical to their pre-change form" (or, given #5, "identical apart
   from the `/explore` attribution").

7. **Fix R18's factual claim about `/charter`'s Slot 7.** `/charter`'s
   `phase-resume.md` uses no "Slot" vocabulary at all, and its **row 7 is
   occupied** by `wip/strategy_<topic>_discover.md -> Resume into /strategy`.
   R18 says the clause "SHALL live in each parent's reserved Slot 7, which both
   name and leave empty today" — true of `/scope` (line 80, "vacuous in v1"),
   false of `/charter`. AC16 already hedges correctly; bring R18 to it.

8. **Give AC27 a number and a definition.** "The consolidation scenario count
   is not lower than before this change" has no baseline recorded anywhere and
   "the consolidation family" is undefined — three scenarios carry a
   `consolidation-` name prefix, but the floor scenario R28 targets
   (`durable-artifact-floor-is-structural`) does not, and the file has no tag
   or category field. State the number: "`skills/scope/evals/evals.json`
   contains at least 4 scenarios covering the consolidation judgment and the
   durable-artifact floor (3 named `consolidation-*` plus the rewritten floor
   scenario)."

9. **Disambiguate AC26's third clause.** "reasons from either type's
   required-section list" is the only clause of the three that is not
   greppable, and as written it appears to condemn
   `consolidation-absorb-brief-into-prd` (line 291), which maps BRIEF sections
   onto PRD sections to describe where content landed — the carry check, not an
   absorbability derivation. Distinguish the two: forbid *deriving the absorb
   verdict* from section lists, and say explicitly that describing where content
   landed is not what is forbidden.

10. **Make AC8 a condition.** "names `/comp` in exactly one way" cannot be
    checked. R8 already states the checkable form: replace with "`/comp`
    appears in no `planned_chain` example and no `chain_skipped` example under
    `skills/charter/`." Today
    `skills/charter/references/phases/phase-state-management.md:255` has
    `planned_chain: [vision?, comp?, strategy, roadmap]`, so the criterion
    correctly fails.

11. **Make AC28 a condition.** "assert the chain-proposal triad the same way"
    is not testable. R29 names the form: "no `/scope` or `/charter` scenario
    requires a contiguous `Proceed / Adjust / Bail` string; both assert the
    three tokens individually." Today `skills/scope/evals/evals.json:383` pins
    `"Proceed / Adjust / Bail?" byte-for-byte` while
    `skills/charter/evals/evals.json:247` explicitly tolerates a re-labelled
    option — so the criterion correctly fails.

12. **Add criteria for four uncovered requirements.**
    - **R5** (per-parent `planned_chain` constancy; the never-planned category)
      has no criterion at all. Suggested: "the triad contract names the
      never-planned category and states that a conditional feeder whose gate
      never opened appears in neither `planned_chain` nor `chain_skipped`;
      `/comp` is the worked example."
    - **R13** (the fourth arm) has no criterion. AC11 only checks that
      `/execute` is *named*, not that it is reached only with an existing PLAN
      and that the file-an-issue arm points at `/work-on`. Suggested:
      "`skills/explore/` routes a filed issue to `/work-on` and names
      `/execute` only in a branch conditioned on an existing PLAN path."
    - **R15** (Phase 0 artifact-type triage removal) has no criterion.
      Suggested: "`skills/explore/references/phases/phase-0-setup.md` assigns no
      `needs-*` label and contains no artifact-type triage."
    - **R19** (the handoff carries conversation, never filesystem state) has no
      criterion, and it is the load-bearing safety clause of the whole handoff
      design — a handoff that pre-supplies status or visibility lets a stale
      wip file drive a parent's gate. Suggested: "the handoff artifact's
      documented schema contains no field for artifact existence, frontmatter
      status, content hash, visibility, or upstream validation, and each
      parent's Slot 7 / handoff clause states that these are re-read."

13. **Add an `--auto` criterion for R2.** R2's first declination property is
    "author-supplied, so no predicate the parent evaluates can produce the skip
    and a non-interactive run invokes the child." `--auto` auto-proceeds at the
    chain proposal (`skills/scope/references/phases/phase-1-discovery.md:391`),
    so this is a real, reachable path with no criterion behind it. AC3 only
    checks that the clause *names* three properties, which a prose read
    satisfies without the behavior being true. Suggested: "an eval scenario
    exercises `/charter --auto` and asserts `/roadmap` is invoked with no
    `chain_skipped` declination entry."

## Optional Improvements

- **AC1** should inherit R1's location pin. "A reader can find it without
  opening a skill directory" is satisfied by the statement being anywhere in
  `references/`; R1 says "at the head of its Gate Vocabulary section," which is
  checkable. Use R1's wording.

- **AC15 is narrower than R17.** R17 says the handoff path must collide with
  "no existing resume-ladder match condition in either parent"; AC15 checks
  only `/scope` Slots 5-6 and `/charter` row 8. Restate as "the handoff path
  matches no ladder row in either parent other than `/scope`'s Slot 7 and
  `/charter`'s new handoff clause" — same check, and it does not go stale when
  a row is added. (I checked `/charter` row 7: it matches
  `wip/strategy_<topic>_discover.md`, a different filename, so it is not a live
  collision today.)

- **AC19 covers `/scope` only.** R21 says slug re-validation "SHALL cover Slot
  7"; `skills/scope/references/phases/phase-resume.md:141` reads "any Slot 5 or
  Slot 6 ladder match." If `/charter` has an equivalent rule it should be named
  too; if it does not, say so, so an implementer does not go looking.

- **AC22's second clause** ("no passage contradicting another passage in the
  same file") is an unbounded judgment over a 500-line file. The first clause
  is the testable one and is sufficient — the specific contradiction R24
  targets is already named.

- **AC31/AC32/AC33 pass vacuously if nothing is touched.** That is the correct
  shape for a no-regression criterion, but it means they contribute nothing to
  deciding "done." Not a defect; noted so the jury does not read them as
  coverage.

- **On restatement (rubric item 5):** the criteria do *not* duplicate the
  requirements. Almost every one names a file, a construct, and a condition
  that the corresponding requirement states in normative prose — AC12 versus
  R11 is the model: R11 says "the DESIGN skeleton SHALL be removed," AC12 says
  "`/explore` writes no file under `docs/designs/`," which is a check rather
  than a restatement. The closest to a restatement is AC9 ("`/charter`'s Phase
  1 Adjust cannot drop a child without a recorded ground"), which is R9 with
  the SHALL removed; it earns its place because the condition is directly
  readable off the Adjust wording. No changes needed on this axis.

- **On the edge cases raised in the brief:** "a parent that defines no
  reduction mechanism" is handled — R1's last sentence forbids requiring one,
  because `/charter` and `/execute` define none — but nothing verifies it; a
  criterion reading "the statement is true of `/scope`, `/charter`, and
  `/execute` as they exist, and requires no parent to define a reduction
  mechanism" would close it. "A repo with no `docs/roadmaps/`" is not a live
  case: `/charter`'s roadmap gate is unconditional
  (`skills/charter/evals/evals.json:242` — "both gates are unconditional"), so
  the absence of the directory changes nothing; the general shape is R5's
  never-planned category, covered by Required Change #12. "A handoff for a
  topic with no matching `docs/` artifacts" is the cold-start case and AC16
  already covers it, since entering Phase 1 with pre-loaded discovery input is
  the same behavior whether or not artifacts exist. "`--auto` where no author
  answers" is a real gap — Required Change #13.
