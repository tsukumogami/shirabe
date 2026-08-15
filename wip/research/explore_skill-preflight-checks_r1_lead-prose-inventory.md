# Lead: How much prerequisite prose actually exists across shirabe's skills, and what does it cost?

> Recorded by the orchestrator: the research agent ran read-only and returned
> its findings inline rather than writing this file. Content is verbatim.

## Findings

### Inventory

Categories: **A** names a required external tool - **B** states a version floor -
**C** tells the agent to run a presence/version check - **D** gives an install
command - **E** describes missing-tool handling.

**EAGER -- sits in a SKILL.md body, loads on every invocation of that skill**

| # | File : lines | Lines | Words / chars | ~Tokens | Cat |
|---|---|---|---|---|---|
| P1 | `skills/work-on/SKILL.md` : 176-183 | 8 | 21 / 187 | ~47 | **A B C D E** |
| P2 | `skills/execute/SKILL.md` : 123-137 | 15 | 56 / 556 | ~139 | C (file-path, not a tool) |
| P3 | `skills/execute/SKILL.md` : 269-282 | 14 | 75 / 512 | ~128 | A (`gh`), C |
| P4 | `skills/release/SKILL.md` : 186 | 1 | 12 / 54 | ~14 | C, E |

**LAZY -- sits in `references/`, loads only when that phase is reached**

| # | File : lines | Lines | Words / chars | ~Tokens | Cat |
|---|---|---|---|---|---|
| P5 | `skills/plan/references/plan-to-tasks-contract.md` : 20, 25 | 2 | 27 / 147 | ~37 | A (`jq`), E |
| P6 | `skills/charter/references/phases/phase-2-chain-orchestration.md` : 91-130 | 40 | 314 / 2,227 | ~557 | E-analogue (probes a *skill*, not a tool) |

**ORPHANED -- outside `skills/`, zero inbound references from any skill**

| # | File : lines | Lines | Words / chars | ~Tokens | Cat |
|---|---|---|---|---|---|
| P7 | `references/fixes/cli-version-preflight.md` : 1-108 | 108 | 559 / 4,003 | ~1,000 | **A B C E** for the `shirabe` binary |

P1 verbatim is the entire canonical case:

```
### Prerequisites

Run `koto version` to verify koto >= 0.3.3 is installed. If missing:

curl -fsSL https://raw.githubusercontent.com/tsukumogami/koto/main/install.sh | bash
```

### The numbers

- **Distinct passages: 7.** Across **5 distinct skills** (work-on, execute,
  release, plan, charter) out of **20**. **15 of 20 skills contain zero
  prerequisite prose of any kind.**
- **Total prose: ~1,922 tokens** counting everything including the orphaned
  file; **~922 tokens** counting only what a skill can actually reach.
- **Eager cost: ~327 tokens total, spread over 3 skills.** Per skill: work-on
  ~47, execute ~267, release ~14.
- **Denominator:** the 20 SKILL.md bodies total 302,022 chars ~ **75,500
  tokens** (avg 3,775/skill). `skills/**/*.md` excluding evals is 1,456,669
  chars ~ **364,000 tokens**.
- **Eager prereq prose is 0.43% of the SKILL.md corpus.** Restricted to genuine
  external-tool prose (dropping P2, which checks a file path not a tool):
  **~188 tokens, 0.25%**.
- Per-skill share of its own body: work-on **1.1%**, execute **2.4%**, release
  **0.8%**.
- **Always-on cost (frontmatter descriptions, loaded before any invocation): 0
  tokens.** All 20 `description:` fields total 187 words and **not one mentions
  a tool, version, or install step.**

### The reachability gap is the real story

`references/fixes/cli-version-preflight.md` is a purpose-built, 108-line
lazy-load preflight reference for the `shirabe` binary -- `--version` detection,
per-subcommand `--help` capability probe, documented sed-edit fallback. Its own
header claims it "is dereferenced on-demand by chain skills (`/scope`,
`/charter`)". A repo-wide grep for `cli-version-preflight` returns hits **only**
in `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`. No skill
cites it. The design's R30 ("Each child SKILL that prescribes a `shirabe`
subcommand emits a structured pointer to this file") never landed in the skills.

Meanwhile the skills call the binary bare and unguarded: `shirabe
slug-prefix-detect` (`skills/scope/references/phases/phase-0-setup.md:98`),
`shirabe validate --format json` (scope, charter, ~8 call sites), `shirabe
transition` (`skills/strategy/SKILL.md:111`), `shirabe work-summary render`
(`skills/inflight/SKILL.md:40`, a dynamic-command `!` invocation that fires at
load). None of these has a presence check, a version floor, or a missing-binary
path.

### A claimed check that does not exist

`skills/execute/SKILL.md:271-273` states the preflight will "confirm `gh` auth
is live -- it is a precondition." `skills/execute/scripts/preflight.sh` does no
such thing: it resolves `$CLAUDE_PLUGIN_ROOT` and tests `[[ -f "$CHILD" ]]` on
the work-on child template. That is the whole script. The `gh` auth precondition
is asserted in prose and enforced nowhere.

### What is not a hit

Every other `## Prerequisites` heading in the corpus
(`plan/references/phases/phase-2-milestone.md:9`, `phase-3-decomposition.md:35`,
`phase-4-agent-generation.md:32`, `phase-7-creation.md:48`) is about **wip/
artifacts from prior phases**, not tools. All `install` matches in
`review-plan/references/templates/ac-discriminability-taxonomy.md`,
`plan/references/quality/plan-doc-examples.md`, and
`vision/references/vision-format.md` are illustrative tsuku-recipe examples
inside teaching content. All 9,593 words of `koto-templates/**` contain zero
prerequisite prose.

## Implications

- **The stated premise -- "a recurring context tax paid on every skill load" --
  is not supported.** The always-on cost is exactly zero, and the per-invocation
  cost is 0.43% of the body it sits in. No token-budget argument justifies this
  work.
- **The defensible argument is correctness and coverage, not cost.** Four of the
  five tools shirabe depends on (`shirabe` itself, `gh`, `jq`, `git`) have no
  eager guard anywhere. Only `koto` does, in only one skill. A load-time check
  would take coverage from 1-of-5 to 5-of-5 -- that is a reliability win, and
  framing it as a context win would be dishonest.
- **The lazy-load architecture already works.** P6 and P7 show the team knows
  how to push resolution prose out of the eager path. P7 shows the failure mode
  of that architecture: prose that costs nothing also gets read by no one. A
  deterministic check does not have this failure mode.
- **The prose that exists is thin, not verbose.** P1 is 47 tokens covering all
  five categories. Replacing it saves ~47 tokens and adds a runtime dependency
  on the check firing correctly. The trade is only favorable if the check also
  covers the four unguarded tools.

## Surprises

- The one file explicitly engineered as a preflight reference is unreachable
  from every skill. It cost 108 lines to write and delivers zero tokens of value
  at runtime.
- `skills/execute/SKILL.md` documents a `gh` auth precondition that
  `preflight.sh` does not check -- prose and implementation have already
  drifted, which is the exact failure mode a deterministic check would prevent.
- `/inflight` declares `allowed-tools: Bash(shirabe:*)` and fires
  `` !`shirabe work-summary render` `` at load with no guard. It is the one
  skill that already runs a binary eagerly, and it is the one skill with no
  prose about that binary existing.
- The koto version floor is pinned at `>= 0.3.3` in exactly one place in the
  entire repo. Nothing enforces or cross-checks it.

## Open Questions

- Was R30's per-skill pointer row deliberately dropped, or lost in Batch 3 of
  the pattern-v1 rollout?
  `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md:462` lists the
  SKILL.md edits that were supposed to carry it.
- Should a load-time check cover the `shirabe` binary's *subcommand surface*
  (P7's actual concern -- version skew, not absence), or only presence? Those
  are different checks with very different cost profiles.
- Does the `koto >= 0.3.3` floor still hold at plugin version 0.16.1-dev, and
  who updates it?
- `.claude-plugin/plugin.json` declares no hooks. Where would a load-time check
  attach, and does the harness give a skill a pre-body execution point at all?

## Summary

Shirabe's skills contain seven prerequisite passages across five of twenty
skills, totalling roughly 1,900 tokens, of which only ~327 tokens sit in eagerly
-loaded SKILL.md bodies -- 0.43% of the 75,500-token SKILL.md corpus, with zero
cost in the always-loaded descriptions. The tax is SMALL and CONCENTRATED:
work-on carries the single complete passage (koto version floor, check, and
curl-pipe-bash install, 47 tokens), execute carries a preflight that claims a
`gh` auth check its script does not perform, and fifteen skills carry nothing at
all. The premise that prerequisite prose is a recurring context tax is thin --
the real defect is the inverse, that `shirabe`, `gh`, `jq`, and `git` are
invoked unguarded everywhere while the one purpose-built preflight reference
(`references/fixes/cli-version-preflight.md`, 108 lines) is cited by no skill
and therefore never loads.
