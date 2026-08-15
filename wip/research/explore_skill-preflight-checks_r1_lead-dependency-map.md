# Lead: What does each shirabe skill actually depend on at runtime, and where does it fail when the dependency is absent?

> Recorded by the orchestrator: the research agent ran read-only and returned
> its findings inline rather than writing this file. Content is verbatim.

## Findings

### 0. What the repo already declares (the partial answer)

- `/.tsuku.toml` declares exactly one tool: `"tsukumogami/koto" = "latest"`. `gh`
  is present but **commented out**: `# gh = "latest"  # disabled: segfaults on
  Linux (tsukumogami/tsuku#2245)`.
- `shirabe` itself is **not** in `.tsuku.toml`. `.tsuku-recipes/shirabe.toml` is
  a recipe *for other repos to install shirabe* (download from
  `github.com/tsukumogami/shirabe/releases`, `verify: shirabe --version`
  matching `{version}`).
- `jq`, `git`, `python3`, `curl` are declared nowhere.
- So the existing declaration covers 1 of ~7 runtime dependencies, states no
  version floor, and actively excludes the single most-used external binary
  (`gh`).
- `/references/fixes/cli-version-preflight.md` is the closest existing preflight
  artifact: a `shirabe --version` + `shirabe <sub> --help` grep probe,
  explicitly lazy-loaded and *reactive* ("dereferenced on-demand by chain skills
  (`/scope`, `/charter`) at the points where they invoke the CLI... only a
  pointer here when the failure surfaces"). It is prose, not a check, and only
  two skills point at it.

### 1. Per-skill dependency table

Legend: **U** = unconditional (every run hits it), **C** = conditional (named
branch).

| Skill | shirabe | koto | gh | jq (system) | git | network | other |
|---|---|---|---|---|---|---|---|
| **brief** | **U** `transition` on Approve -- `references/phases/phase-5-finalize.md:102`; **C** input-mode-2 lifecycle verb -- `SKILL.md:111` | -- | **C** PR at finalize, soft-worded "standard tooling (e.g. `gh pr create`)" -- `phase-5-finalize.md:190` | -- | **U** commit; **C** `git rm` on Reject -- `phase-5-finalize.md:~131` | **C** push/PR | -- |
| **charter** | **U** `validate --format json --visibility=<v>` before full-run success -- `references/phases/phase-finalization.md:165` (+ children's transitions) | -- | -- (children only) | -- | **U** tracked-by-git checks + commits -- `SKILL.md:136` | **C** via children | -- |
| **comp** | **U** `transition` at finalize -- `references/phases/phase-5-finalize.md:18`, `SKILL.md:113`; **C** `validate --visibility private <file>` -- `references/comp-format.md:152` | -- | **none** -- explicitly "do not open a PR" (`phase-5-finalize.md:81`) | -- | **U** commit | -- | -- |
| **decision** | **none** | -- | -- | -- | **C** commit of ADR | -- | -- |
| **design** | **U** `validate --lifecycle-chain <prd>` on PRD-entry -- `references/phases/phase-0-setup-prd.md:31`; **C** `transition <prd> "In Progress"` sentinel-gated -- `:51`; **C** `transition <design> <status>` -- `SKILL.md:277` | -- | -- | -- | **U** `git ls-files` upstream resolve -- `phase-6-final-review.md:152`; **U** `git commit -F`; **C** `git rm` on Reject -- `:303` | -- | -- |
| **execute** | **U** on finalize: `run-cascade.sh` -> `validate --lifecycle-chain` (`:296`), `finalize-chain` (`:716`), `transition` (`:557`,`:731`); **C** coordinated: `validate --merge-gate --mode=ready` -- `SKILL.md:109,315,323,473` | **U** single-pr: `koto init` -- `SKILL.md:150`; `koto next`/`context`/`workflows` throughout template. **C** coordinated mode has **no** koto session -- `SKILL.md:245`. **No version floor stated anywhere.** | **U** single-pr: `pr list`/`pr create` (`koto-templates/execute.md:341-342`), `pr edit` (`:456`), `pr ready` (`:506`), gates `:209`,`:212`; **U** coordinated: `gh api` merge-gate recompute | **U** `run-cascade.sh` -- 19 uses, **unguarded** (`:193,:347,:381,:761-768,:838`) | **U** `rev-parse --show-toplevel` (`run-cascade.sh:628`), `ls-files`, `add`, `rm -f`, `commit`, `push`; **U** `git fetch && git rebase` in worktree_discipline_check | **U** github.com + api.github.com; **U** origin fetch | **U** `python3` -- `run-cascade.sh:44` `_realpath_m`, **unguarded**; **C** `cargo` named only in the fallback error string `:646` |
| **explore** | -- (only prose references) | -- | **C** issue-number input only -- `SKILL.md:120`, `:181`; **C** spike + known issue -- `references/phases/phase-5-produce-deferred.md:96` | -- | **U** commit | **C** with gh | -- |
| **inflight** | **U at skill load** -- `SKILL.md:40` `` !`shirabe work-summary render` `` via `!` dynamic injection; `allowed-tools: Bash(shirabe:*)` (`:14`). **C** `work-summary track` -- `:77` | -- | **U indirectly** -- the binary calls `gh pr view` internally (`:29`, `:80`) | -- | -- | **U** (degrades: prints ledger-only block when unreachable -- `:31`) | -- |
| **plan** | **C** `transition <design> Planned` on design input -- `references/phases/phase-1-analysis.md:57`, `phase-7-creation.md:373`; documents `validate --lifecycle*` modes it does not itself run -- `SKILL.md:77,81` | -- | **C multi-pr only** -- `create-issues-batch.sh:273,280,290,412,438`; `create-issue.sh:257`; `apply-complexity-label.sh:82,87`; `SKILL.md:414`; `phase-7-creation.md:204,456,458` | **U for scripts**, guarded: `plan-to-tasks.sh:1146`, `create-issues-batch.sh:140`, `build-dependency-graph.sh:40`, `render-template.sh:41`. **Unguarded**: `create-issue.sh:184-187`. Contract: `references/plan-to-tasks-contract.md:25` "jq must be available in PATH. Exit 1 if not found." | **U** commit | **C** multi-pr | -- |
| **prd** | **C** `transition <brief-path> Accepted` brief-handoff -- `SKILL.md:157` | -- | -- | -- | **U** `git ls-files <path>` upstream check -- `references/phases/phase-3-draft.md:44`; **U** `git commit -F`; **C** `git rm` on Reject -- `phase-4-validate.md:295` | -- | -- |
| **private-content** | **none** | -- | -- | -- | -- | -- | -- |
| **public-content** | **none** | -- | -- | -- | -- | -- | -- |
| **release** | -- | -- | **U from Phase 2 on**: `gh api .../commits/{sha}/status` (`SKILL.md:54`), `gh run list` (`:57`), `gh release view` (`:61`), `gh issue list --label blocks-release` (`:62`), `gh pr list --search` (`:64,:88`), `gh release create` (`:122`), `gh workflow run` (`:140`), `gh run list/view` (`:159,:166`) | -- | **U** `git describe --tags` (`:31`), `git status --porcelain` (`:52`), `git tag -l` (`:59`) | **U** api.github.com | -- |
| **review-plan** | **none** | -- | -- | -- | -- | -- | -- |
| **roadmap** | **U** `roadmap populate --no-issues` in Phase 4 and again on activate -- `references/phases/phase-4-validate.md:226,276`, `SKILL.md:394,428`; **U** `transition <path> Active` -- `phase-4-validate.md:283`, `SKILL.md:280` | -- | **C** only `populate --issues` -- `SKILL.md:418`. Issueless mode is documented as "no `gh` call of any kind" -- `SKILL.md:369` | -- | **U** `git ls-files` -- `references/phases/phase-3-draft.md:57`; commit | **C** issue-creating mode | -- |
| **scope** | **U Phase 0** `slug-prefix-detect <slug> --docs-root docs` -- `references/phases/phase-0-setup.md:98`; **U per child** `validate --format json --visibility=<v>` step 7 -- `phase-2-chain-orchestration.md:58,397,528`; **C** coordinated `validate --coordination-body` / `--merge-gate` -- `SKILL.md:200,202` | -- | **C coordinated multi-repo only**: `gh pr create` (`SKILL.md:198,225`), `gh pr edit` (`:225`), `gh pr close` (`:710`) | -- | **U** `git commit -F` discipline -- `references/phases/phase-3-exit-finalization.md:243-268`; **U** `git fetch && git rebase` per child -- `phase-2-chain-orchestration.md:~78` -> `references/worktree-discipline.md:51-52` | **U** origin fetch; **C** github.com for coordination PR | -- |
| **strategy** | **U** `transition` on Accept -- `references/phases/phase-5-finalize.md:111`; **C** `transition ... Sunset --reason` -- `SKILL.md:112` | -- | **C** PR at finalize (soft) -- `phase-5-finalize.md:203` | -- | **U** commit; **C** `git rm` | **C** push | -- |
| **vision** | **U** `transition <path> Accepted` -- `SKILL.md:195`, `:85` | -- | -- | -- | **U** commit | -- | -- |
| **work-on** | **C** `validate --pr-body` named as a CI-side gate, not invoked -- `references/phases/phase-6-pr.md:31` | **U** -- `koto init` (`SKILL.md:188,195`), `koto next` loop (`:216-221`), `koto context add/get` throughout, `koto rewind` (`:227`), `koto workflows` (`:235`). **Version floor: `koto >= 0.3.3`, prose-only, `SKILL.md:178`** | **U** -- `gh issue view` (`SKILL.md:27,150,268`; `phase-1-setup.md:9`), `gh pr list` (`koto-templates/work-on.md:1090`), `ci_passing` gate (`:735`) | **C** -- only via `extract-context.sh` (guarded, `:133`); gates use `gh --jq` (gh's embedded jq, **not** system jq) | **U** `git rev-parse --abbrev-ref HEAD` in the CI gate (`work-on.md:735`); branch/commit/push | **U** github.com; `raw.githubusercontent.com` **C** only for the koto-install remediation -- `SKILL.md:181` | **C** `curl` -- same line `:181` |
| **writing-style** | **none at runtime** -- `rules.yaml:3` and `SKILL.md:23` note that `shirabe validate` reads the same file *at enforcement time*, i.e. in CI, not in the skill | -- | -- | -- | -- | -- | -- |

### 2. Repo-root `scripts/` (also runtime surface)

| Script | Deps | Guarded? |
|---|---|---|
| `scripts/run-evals.sh` | `claude` CLI (`:47`), `python3` (`:48`) | **Yes**, both `command -v` with exit 3 -- the only clean example in the repo |
| `scripts/check-evals-exist.sh` | `python3` (`:41`) | **No** -- `|| echo "0"` swallows a missing python3 and reports zero evals: **silent wrong answer** |
| `scripts/check-no-duplicate-rule-list.sh` | `python3` (`:26` `exec python3 -`) | **No** |
| `scripts/check-sentinel.sh` | `jq` (`:33`) | **No** |
| `scripts/validate-template-mermaid.sh` | sources `scripts/lib/koto-gates.sh`; `jq` in its `_test.sh` | **No** |
| `scripts/ci-gate-expression_test.sh` | `jq` (8 uses) | **No** |
| `skills/execute/scripts/preflight.sh` | none but filesystem | **Yes** -- checks the cross-skill child template path with a clear two-line error and `exit 1`. This is the model to generalize. |

### 3. Failure modes, ranked by how bad

**A. Silent-wrong-answer (worst)**

1. **`/inflight` with no `shirabe` on PATH.** `SKILL.md:40` is a `!`
   dynamic-injection line evaluated at skill load. The shell emits `command not
   found: shirabe` into the prompt context, and `render` never prints its
   empty-state line. The skill's own guardrail (`:85-103`, "No PR reference
   outside the block") then has nothing to anchor to -- the most likely model
   behavior is to narrate PRs from memory, which is exactly the failure the
   skill exists to prevent. This is the single strongest argument for a
   load-time check.
2. **koto command gates with `gh` or `git` missing.** `execute.md:209,212` and
   `work-on.md:735` embed `gh pr checks $(gh pr list ... ) --jq ... | grep -q
   true` inside a koto `command:` gate. The template itself documents the
   failure shape at `execute.md:353`: *"koto reports a failed command gate as an
   exit code with no message and discards the command's own output."* A missing
   `gh` is therefore indistinguishable from red CI -- the run stalls at
   `ci_passing` forever with no diagnostic.
3. **`check-evals-exist.sh:41`** returns `0` when `python3` is absent, so a CI
   gate passes on missing evals.

**B. Confusing error mid-workflow**

4. **`run-cascade.sh` with no `jq`.** 19 unguarded uses under `set -euo
   pipefail`. The first hit is `:193` inside `log_lifecycle_findings`
   (diagnostic), but `:347`/`:381` build the *output contract* JSON and
   `:761-768` parse the `finalize-chain` report. A failure at `:761` occurs
   **after** `shirabe finalize-chain` has already mutated docs and **before**
   the `git rm`/`git commit` at `:860`/`:872` -- leaving a half-cascaded,
   partly-staged tree. Compare: `shirabe` absence at the same script is handled
   beautifully (`:646`: `{"cascade_status":"skipped",...,"error":"shirabe binary
   not found (set SHIRABE_BIN, install shirabe, or build with cargo)"}`), and
   `git` absence too (`:628-629`, `"not a git repository"`). jq and python3 were
   simply missed.
5. **`run-cascade.sh` with no `python3`.** `:44` `_realpath_m` is used during
   path validation near the top; under `set -e` this exits 127 with a bare
   `python3: command not found` and no JSON envelope, violating the script's own
   documented "JSON to stdout (always, regardless of success or failure)"
   contract at `:19`.
6. **`/charter` and `/scope` validator pass-through with no `shirabe`.** Both
   branch on an explicit exit-code table -- `0 = clean`, `2 = violations`, `1 =
   tool-error` (`charter/references/phases/phase-finalization.md:165-198`). A
   missing binary yields **127**, which is not in the table. The prose gives the
   model no route, and `1 = tool-error` is the only "the validator could not
   run" bucket -- so the most likely outcome is 127 being misread as a content
   violation and the chain being blocked with a nonsense reason.
7. **`gh` unauthenticated.** Only
   `skills/work-on/references/scripts/extract-context.sh:137` runs `gh auth
   status`, emitting `json_failed "gh CLI not authenticated"` (`:138`). Every
   other gh call site -- `/release`'s eight, `/execute`'s PR lifecycle,
   `/plan`'s batch scripts, `/roadmap populate --issues`, `/scope`'s
   coordination PR -- hits `gh: To get started with GitHub CLI, please run: gh
   auth login` on stderr partway through. `/release/SKILL.md:186` mentions `gh
   auth status` only in a *post-failure* troubleshooting table row, not as a
   precondition, even though `SKILL.md:47` says "All must pass before
   proceeding".
8. **`create-issue.sh:257`** captures a missing-`gh` "command not found" into
   `$output` and treats it as a failed issue creation -- real error, wrong
   explanation.

**C. Detected with a good message (the working cases)**

9. `jq` in `plan-to-tasks.sh:1146` (`die_input "jq is required but not found in
   PATH"`, exit 1, matching the documented contract at
   `plan-to-tasks-contract.md:20,25`), `create-issues-batch.sh:140`,
   `build-dependency-graph.sh:40`, `render-template.sh:41` (structured
   `{"error": ...}` with exit 2).
10. `shirabe` and `git` in `run-cascade.sh:628-646`.
11. `koto` in `extract-context.sh:407-409` -- the only **graceful degradation**
    in the repo: warns and falls back to `wip/` storage.
12. `execute/scripts/preflight.sh` -- filesystem precondition, loud and early,
    with a why-this-matters second line.

**D. Version floors**

13. **koto >= 0.3.3** is asserted only in `/work-on` (`SKILL.md:178`: "Run `koto
    version` to verify koto >= 0.3.3 is installed"), as an instruction to the
    model rather than an executed check. `/execute` uses `koto
    init`/`next`/`context`/`workflows` just as heavily and states **no floor at
    all**. The `version: "1.0"` in both koto templates is the template schema
    version, not koto's.
14. **shirabe** has no floor stated by any skill.
    `references/fixes/cli-version-preflight.md:52-66` explicitly rejects
    version-based gating in favor of per-subcommand `--help` probing, because
    "shirabe releases sometimes ship partial surface changes". A composable
    check should therefore express *capability* (`shirabe transition --help |
    grep --superseded-by`) rather than semver -- but
    `.tsuku-recipes/shirabe.toml`'s `verify` block does the opposite (`shirabe
    --version` matching `{version}`).

**E. Network / sandbox**

15. `raw.githubusercontent.com` is needed only by `/work-on`'s koto-install
    remediation (`SKILL.md:181`, `curl -fsSL ... | bash`) -- i.e. only on the
    path that runs *because* a check already failed. In a sandboxed host that
    remediation is itself unavailable, which is the case a host-appropriate
    instruction has to cover.
16. `api.github.com` + `github.com` for every gh path and for
    `install.sh:26,57,71-79`.
17. `git fetch` / `git rebase origin/<branch>`
    (`references/worktree-discipline.md:51-52`) requires origin reachability and
    is unconditional in `/scope` (per child), `/execute`, and `/work-on`
    (`worktree_discipline_check`).

## Implications

1. **The check must be per-phase, not per-skill, for six skills.** `/plan`,
   `/roadmap`, `/scope`, `/execute`, `/explore`, `/work-on` all have a hard mode
   split where `gh` (and network) is required on one branch and provably unused
   on the other -- `/roadmap`'s issueless mode is documented as "no `gh` call of
   any kind" (`SKILL.md:369`), and `/execute`'s coordinated mode has no koto
   session (`SKILL.md:245`). A skill-level `requires: [gh]` would produce false
   alarms on the majority path. The declaration needs at minimum
   `{unconditional: [...], on_mode: {multi-pr: [...], coordinated: [...]}}`.
2. **Nine skills need nothing but `git`** (`decision`, `review-plan`,
   `private-content`, `public-content`, `writing-style`, plus
   `vision`/`prd`/`brief`/`strategy` which add only `shirabe transition` at
   their single finalize step). Composability pays off immediately: five skills
   declare an empty set, four declare `[shirabe, git]`.
3. **`shirabe` is genuinely unconditional in exactly one skill: `/inflight`** --
   and it is the one place where a `!`-injected command runs *at load*, before
   any model reasoning. Every other shirabe use is at a finalize/transition step
   reachable minutes into a session. That asymmetry argues for the check firing
   at skill load rather than at first use: `/inflight` needs it at load, and the
   others benefit from failing before the author has invested a whole drafting
   session.
4. **The three check categories map cleanly onto observed failures**: binary
   presence (jq/python3 in `run-cascade.sh` -- category-A silent corruption),
   auth state (`gh auth status` checked in 1 of ~30 call sites -- category-B),
   network posture (the koto-install remediation and `git fetch` -- the case
   where telling the user "run curl | bash" is itself wrong on a sandboxed
   host).
5. **`run-cascade.sh` is the single highest-value target.** It already contains
   the pattern (guarded `shirabe`, guarded `git`, JSON-envelope errors) and just
   needs `jq` and `python3` added to the same block at `:628-646`. That one edit
   closes the worst data-integrity failure in the repo.

## Surprises

- **`gh` is deliberately disabled in `.tsuku.toml`** ("segfaults on Linux,
  tsukumogami/tsuku#2245") while being the most-invoked external binary in the
  skill corpus (~90 call sites). The existing declaration is not merely
  incomplete, it is inverted on the most important entry.
- **`shirabe` is absent from its own `.tsuku.toml`.** The repo declares koto but
  not the binary its own skills call.
- **`gh --jq` does not need system `jq`.** gh embeds jq for `--jq`. So the koto
  gates at `execute.md:209` and `work-on.md:735` require `gh` + `git` but *not*
  jq -- while `run-cascade.sh` and the plan scripts need real jq. A naive "does
  this file mention jq" scan would get both wrong in opposite directions.
- **`run-cascade.sh` documents a total-JSON-output contract** (`:19` "Output:
  JSON to stdout (always, regardless of success or failure)") that a missing
  `python3` at `:44` breaks before the first line of JSON is emitted.
- **`/charter` and `/scope` already model exit codes precisely** (0/1/2 with
  distinct handling for tool-error vs violation) -- a level of rigor no other
  skill reaches -- and still have no route for 127.
- **`references/fixes/cli-version-preflight.md` is deliberately reactive**: "the
  chain skill body does not contain the preflight prose, only a pointer here
  when the failure surfaces" (`:9-11`). Someone already decided prose preflight
  was too expensive to inline. That is the design pressure this exploration is
  answering.
- **The best existing check is `extract-context.sh:407-409`** -- it *degrades*
  rather than fails, falling back to `wip/` when koto is absent. Worth
  preserving as a check outcome type ("degrade with a named fallback"), not just
  pass/fail.

## Open Questions

1. Should `/roadmap`'s `--issues` mode and `/plan`'s multi-pr mode declare `gh`
   as a *mode* dependency evaluated at mode selection, or should the check
   re-run at the branch point? Mode is chosen mid-run (`/plan` between Phases 3
   and 4), which a load-time check cannot see.
2. Does `shirabe work-summary render` degrade cleanly when `gh` is present but
   unauthenticated? `SKILL.md:31` promises a "best-effort, ledger-only block
   clearly marked as such" for unreachable live state -- unverified whether auth
   failure takes that path or errors.
3. Is `python3` a real dependency or an accident? `run-cascade.sh:43` justifies
   it as "macOS ships coreutils without realpath; python3 is available on both
   platforms" -- but macOS 12.3+ removed system python3. A pure-bash normalizer
   would delete the dependency entirely.
4. What is `/execute`'s actual koto floor? It uses `koto context`, `koto
   workflows`, `failure_policy: skip_dependents`, and `--with-data @file` --
   likely a *higher* floor than `/work-on`'s stated 0.3.3, but nothing records
   it.
5. Should the check express shirabe capability (`--help` grep, per
   `cli-version-preflight.md:63-66`) or semver (per
   `.tsuku-recipes/shirabe.toml`'s `verify`)? The two existing artifacts
   disagree.
6. Do the skills' `@.claude/shirabe-extensions/<name>.md` imports (every
   SKILL.md, e.g. `brief/SKILL.md:22-23`) belong in the same check surface? They
   are file-presence preconditions with the same silent-failure shape.
7. `/inflight` declares `allowed-tools: Bash(shirabe:*)` (`SKILL.md:14`) -- can
   a check be expressed in frontmatter alongside it, or does it need a separate
   declaration mechanism?

## Summary

Ten of twenty skills touch a binary at all: `shirabe` is unconditional only in
`/inflight` (a `!`-injected command at skill load) and at the single finalize
step of the document skills, while `gh`, `koto`, and `jq` are concentrated in
`/work-on`, `/execute`, `/plan`, `/release`, and `/scope`, where each is
unconditional on one mode and provably unused on another -- so a per-skill flat
requirement list would misfire on the majority path and the declaration must
carry the mode split. Failure handling is inconsistent rather than absent: `jq`
is guarded with good messages in four plan scripts and `shirabe`/`git` in
`run-cascade.sh`, but the same script leaves 19 `jq` uses and one `python3` use
unguarded on a path that mutates docs before committing, koto's command gates
swallow a missing `gh` as an unexplained red-CI stall, and `gh auth status` is
checked at exactly one of roughly thirty call sites. `.tsuku.toml` is a partial
and partly-inverted answer -- it declares `koto` but omits `shirabe`, `jq`,
`git`, and `python3`, and has `gh` commented out as broken on Linux despite `gh`
being the most-invoked external binary in the corpus.
