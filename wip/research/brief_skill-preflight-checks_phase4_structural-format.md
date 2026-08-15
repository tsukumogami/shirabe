# Verdict: PASS

Reviewer: structural-format (Phase 4 two-reviewer jury, re-check after content revision)
Target: `docs/briefs/BRIEF-skill-preflight-checks.md` (275 lines, up from 247)
Prior verdict: PASS. Re-run is a full structural check, not a diff-only pass.

## Checks

1. **Frontmatter — PASS, and the `problem:` field is not stale.** `schema: brief/v1` on line 2. Required fields all present: `status` (L3), `problem` (L4-8), `outcome` (L9-13). Both are YAML literal block scalars (`|`) at 4 content lines, inside the 2-4 line window. Optional `motivating_context` (L14-18) is a well-formed `|` block scalar, 4 content lines, carrying situational-trigger content distinct from `problem` and `outcome`.

   Substance match against the revised body, checked field by field:
   - `problem:` asserts three things — skills call six named host tools; almost none of those calls declares what it needs or checks it is there; a missing or *surface-drifted* tool does not stop the run, it takes a wrong branch and continues. The rewritten first paragraph (L40-52) now says guards *do* exist for `shirabe`, `git`, and `jq` but live inside scripts several layers below the skill, and that a skill body never says what it needs. That is a sharpening of "almost none of those calls says what it needs or checks that it is there," not a contradiction of it: the field's claim is about the call site and the skill body, which is exactly what the new paragraph narrows to. The new final paragraph (L104-117) answers two recorded counter-positions and introduces no claim the frontmatter contradicts. The "surface has drifted" clause is if anything better supported after the revision than before, since L73-85 now states outright that not one of the five incidents is a plain missing tool.
   - `outcome:` — one declaration site, verified when the skill loads, host-resolved instruction, silence on a satisfied machine. All four map onto `## User Outcome` (L119-141) unchanged.
   - `motivating_context:` — five filed incidents, the silent koto-subcommand success, twelve children dispatched at a branch nobody created. Matches L80-85 and the rewritten Journey 2 (L156-167).

   `upstream:` remains correctly absent (no ROADMAP grounded this brief; the Status section records exploration provenance). `od -c` over L1-19 confirms clean `---` delimiters, no CRLF, no trailing whitespace.

2. **FC02 — PASS.** Frontmatter `status: Draft`, one of the three valid statuses.

3. **FC03 — PASS (verified byte-exactly).** `od -c` of L23-27 returns `#   #       S   t   a   t   u   s  \n  \n   D   r   a   f   t  \n  \n   T   h   e ...`. The first non-blank line under `## Status` is the bare word `Draft` alone — no trailing prose, no period, no trailing space. Matches frontmatter `status: Draft`. Explanatory prose resumes on L27 after a blank line.

4. **FC04 / FC15 — PASS.** Heading scan, in file order: L23 `## Status`, L38 `## Problem Statement`, L119 `## User Outcome`, L143 `## User Journeys`, L196 `## Scope Boundary`, L242 `## Open Questions`, L262 `## References`. Five required sections present in canonical order. Both optional sections trail `Scope Boundary` in Section Matrix order (Open Questions, then References; Downstream Artifacts absent). `Open Questions` is legal because status is `Draft`. `###` sub-headings appear only under `User Journeys` (five journeys, Journey 2 rewritten in place with its heading intact) and `Scope Boundary` (`### In`, `### Out`), which does not affect `##`-level matching.

5. **Public-visibility cleanliness — PASS.** Repo is public. Case-insensitive grep for `private/`, `vision`, `coding-tools`, `overlay`, `dot-niwa` returns zero matches across the whole file, including the six edited regions. Every issue reference is a public shirabe issue: `shirabe#80` (L69), `shirabe#270` (L78, L112), `shirabe#279` (L80, L167), plus `/work-on 214` (L148) as an illustrative public issue number. The revision added `shirabe#270` at L112 and `shirabe#279` at L167 — both public, both fine. Host paths (`~/.tsuku/tools/current/`, `~/.tsuku/env`) are user-machine paths for a publicly documented tool.

6. **wip/ hygiene — PASS.** `grep -n 'wip/'` over the brief returns no matches. No `wip/...` path in frontmatter, prose, Open Questions, or References. All four References entries are durable repo-relative paths; no Downstream Artifacts section.

7. **Writing style — PASS, checked fresh over the full revised text.** Rulebook read from `skills/writing-style/rules.yaml` (schema `writing-style-rules/v1`). Word-boundary, case-insensitive grep over every banned term in all five categories — with `tier`, `journey`, and `underscore` excluded as shirabe's declared vocabulary per CLAUDE.md — returns zero matches. Adverb-opener grep at sentence-start and after a period returns zero. Frequency rule `em-dash-density`: `grep -c '—'` returns 0; the author uses `--` throughout, which the pattern does not match, so the rule cannot fire. Judgment-only spot checks on the new prose: `landscape` absent; no forced rule-of-three; the two added paragraphs (L104-117 and the Journey 2 rewrite) both end on a load-bearing claim rather than a restatement, so the empty-conclusion rule does not bite. The longest new sentence chains at L112-117 are varied in length and every `that`/`which` in them has a local antecedent.

8. **Referenced-path existence — PASS.** Every repo-relative path in prose and References resolves on disk:

   References: `references/fixes/cli-version-preflight.md` (4003 bytes, 108 lines — the brief's "a hundred and eight lines" at L94-95 is still accurate), `skills/inflight/SKILL.md` (5633), `skills/execute/scripts/preflight.sh` (1542, mode 755), `docs/briefs/BRIEF-shirabe-check-absorption.md` (8029).

   Prose: `skills/work-on/SKILL.md` (L43, 17724), `.tsuku.toml` (L90, 190), `.tsuku-recipes/shirabe.toml` (L249, 684), `run-cascade.sh` (L50, L235 — bare filename, resolves uniquely to `skills/execute/scripts/run-cascade.sh`, 39988), `references/fixes/cli-version-preflight.md` again at L94 and L247.

   The path the revision turns on, checked exactly as specified: **`docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md` exists** (86976 bytes). The revised text cites it at L105 as the bare document name `DESIGN-shirabe-pattern-v1-ergonomics` in backticks, which resolves to that one file and nothing else in the repo — not a dangling reference.

   Corpus counts still check out: `ls skills | wc -l` returns 20, matching "shirabe's twenty skills" (L40, L193, L200) and the "nine of shirabe's twenty" denominator (L193).

## Validator output

Binary: `shirabe` on PATH -> `/Users/danielgazineu/.tsuku/tools/current/shirabe`, `shirabe v0.16.0`.

Command:

```
shirabe validate --format json --visibility=public docs/briefs/BRIEF-skill-preflight-checks.md
```

Output (verbatim), exit code 0:

```json
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
```

## Required changes (if FAIL)

None. All eight checks pass on the revised file and the validator reports `clean` with zero errors and zero notices under `--visibility=public`. The six content edits introduced no structural, visibility, hygiene, style, or path regression, and the frontmatter `problem` block did not go stale against the rewritten Problem Statement.

Three optional, non-blocking observations, none affecting the verdict:

1. `run-cascade.sh` (L50, L235) and `DESIGN-shirabe-pattern-v1-ergonomics` (L105) are cited by bare name rather than repo-relative path. Both resolve unambiguously today; full paths (`skills/execute/scripts/run-cascade.sh`, `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`) would survive a file move and match how References already cites. The design doc is now load-bearing in the argument, so it is the stronger candidate for promotion into the References section.
2. Journey 5 (L189-194) says the check is silent for the nine skills that need nothing but a checkout, while the revised Scope Boundary bullet (L200-203) says four of those nine declare `shirabe transition`. The arithmetic is consistent (five truly empty declarations), but a reader meeting the journey first may take "silent for nine" literally. Content-reviewer territory, not structural.
3. `Open Questions` is populated, correct for `Draft`; it must be emptied or removed before the Draft -> Accepted transition.
