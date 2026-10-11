---
schema: prd/v1
status: In Progress
problem: |
  The resume convention moved the two chains onto koto session keys, but four
  shirabe skills still write the staging folder on main: /explore's own working
  files, /comp, /release and /work-on's no-koto fallback. While any of them does,
  the enforcement built around the folder (the node-push sweep, the leftover-files
  branch gate, /scope's untrack step and the wip_paths report field) has to stay,
  and a topic's sessions can't be moved to another host in one step.
goals: |
  Every shirabe skill keeps its state in its own session under the convention, so
  nothing writes the staging folder; the enforcement layer comes out because there
  is nothing left for it to guard; one shared subcommand imports a topic's
  sessions to another host; and the convention's references stop describing the
  file era.
absorbed:
  - docs/briefs/BRIEF-leaf-skills-off-folder.md
---

# PRD: Leaf skills off the staging folder

## Status

In Progress

Absorbed [BRIEF-leaf-skills-off-folder](docs/briefs/BRIEF-leaf-skills-off-folder.md); carried in Absorbed Brief.

## Absorbed Brief

Why this feature exists. The resume convention moved the two chains onto
koto sessions and stopped there on purpose, so four skills still write the
staging folder: /explore's own working files, /comp, /release and /work-on's
fallback for a missing koto. Each one keeps alive machinery that exists only
for the folder (a sweep commit on node branches, a branch gate, an untrack
step and a report field), and nobody can move a topic's chain to another host
in one step. Three people pay for that: the maintainer whose interrupted
/explore, /comp or /release resumes from files on the branch; the operator who
has to know every session name to move a chain; and the coordinator who reads
a report field that should always be empty.

The outcome a user should experience: a skill's state is in its own session
by name, an interrupted run picks up from it, a pull request carries only the
documents the work produced with no sweep or gate standing guard, and a topic
moves hosts with one subcommand. The boundary: the convention itself, the
workspace rule for the folder, the coordinate skill, koto, pruning, and the
guards that keep a staging path out of a committed document all stay as they
are.

## Problem Statement

shirabe skills used to keep intermediate state in `wip/`, a folder committed to
the feature branch and deleted before merge. The resume convention
(`references/skill-session-convention.md`,
`docs/designs/current/DESIGN-resume-convention.md`) moved the eleven skills a
chain runs onto koto session keys and named what it left for later work: /comp,
/release, /explore's own working files, /work-on's fallback file, and then the
enforcement layer. A read of main confirms that list and finds nothing else
writing the folder:

- **/explore** writes six kinds of working file (its scope, each research lead's
  output, the accumulated findings, its decision blocks, its crystallize verdict
  and the brief its /decision arm reads) and decides where to resume by testing
  which exist. Its handoff to /scope or /charter is already a key in
  `explore-<topic>`, so one run spans two stores, and the handoff body cites
  folder paths that cleanup deletes.
- **/comp** writes its scope file and three jury verdicts, and its setup reads a
  parent state file that no parent has written since /charter moved onto its
  session; /comp is in no parent's list of children.
- **/release** writes the release range, the pull requests the release contains,
  the commits no pull request names, and the drafted notes, because its phases
  run as separate shell invocations.
- **/work-on**'s `extract-context.sh` writes `IMPLEMENTATION_CONTEXT.md` under the
  folder when it's called without a session or koto isn't on the path. Nothing
  reads that file, and /work-on's own template, which needs koto to run, never
  takes that branch.

Because these writers remain, so does the machinery that exists only for the
folder: /execute's `node-push.sh` sweeps it from node branches in a commit of its
own and refuses a pushed head that still carries it; the `branch/no-wip-files`
rule gates /work-on's and /execute's pull requests; /scope's publish step
untracks its children's files and reports any it pushed as `wip_paths=`, which
/deliver relays. Each of these costs a gate, a commit or a report field on every
run, and shirabe's own CLAUDE.md still tells non-koto workflows to use the
folder.

Two smaller gaps belong to the same rollout. The convention fixed session names
so that importing a chain's sessions under their own names gives another host a
resumable chain, but nothing does the import for a topic: an operator has to know
every name and run `koto session import` once per session. And three of the
convention's references still describe the file era (tsukumogami/shirabe#747).

This matters now because the convention is merged and Done, so every remaining
writer is the last thing holding the enforcement layer in place, and the next
change to any of these skills would otherwise copy the stale examples.

## Goals

- Whoever runs /explore, /comp or /release finds its state in that skill's own
  session, `<skill>-<topic>`, by name, and an interrupted /explore or /comp
  resumes from it.
- No shirabe skill writes or reads the staging folder for its own state, and a
  pull request from any shirabe workflow carries only the documents the work
  produced, with no sweep commit and no leftover-files gate.
- The reports a coordinator reads carry no field about the folder.
- An operator moves every session a topic holds to another host with one
  subcommand.
- The convention's references describe the convention as it is.

## User Stories

- **As a maintainer resuming an interrupted /explore**, I want the run to
  continue from the keys in `explore-<topic>` (for example at convergence, with
  the research leads' outputs read back from the session), so that I lose no
  research and the branch never holds files I must remember to clean up.
- **As a maintainer whose /comp jury was interrupted**, I want the next run to
  find which verdicts came back from `comp-<topic>` and re-run the jury from
  there, so that a competitive analysis doesn't leave verdict files on the
  branch.
- **As a maintainer cutting a release with /release**, I want the range,
  membership and drafted notes kept in the release's session between phases,
  with the notes handed to `gh release create` from a private scratch copy, so
  that the release branch never carries a working file and a second release
  never reads the first one's membership.
- **As an operator moving work to another host mid-chain**, I want to run one
  subcommand naming the set, the topic and the source workspace and have every
  session the set holds arrive under its own name, with names the chain never
  opened skipped, so that the chain resumes where it stopped; and when I name the
  wrong source or have too old a koto, I want the subcommand to fail and say why
  rather than report success.
- **As a coordinator reading a /deliver result**, I want node pull requests with
  no sweep commit and a report with no `wip_paths=` line, so that I don't check a
  field that is always empty and the workspace rule for the folder can be
  retired.
- **As the author of the next skill move**, I want the convention's references
  to state the clean-cancel carve-out and show key-based handoffs, so that I
  copy the convention rather than the file era.

## Requirements

Terms used below. *The floor* is the koto version `scripts/assert-koto-floor.sh`
enforces. *The topic grammar* is the convention's `^[a-z0-9][a-z0-9-]*$`. *A
scratch directory* is one `skill-session.sh scratch` allocates: mode 0700,
outside the work tree, removed by `ingest` or by the step that made it once its
file is used.

### Moving the remaining skills

- **R1. /explore's working state is keys.** /explore runs `skill-session.sh open
  explore <topic>` at the end of its setup phase, after the branch step and
  before its first write, and keeps its files as keys by the convention's
  mapping: scope, findings, decisions, crystallize and the /decision brief as
  `work/scope.md`, `work/findings.md`, `work/decisions.md`,
  `work/crystallize.md` and `work/decision-brief.md`; each research lead's
  output as `research/r<N>_lead-<name>.md`. Lead agents write into a scratch
  directory that the orchestrator ingests with `skill-session.sh ingest`; no
  agent runs a koto command.
- **R2. /explore resumes from keys.** Each row of /explore's resume table, and
  each per-phase resume check, tests a key where it tested a file, one row for
  one. A row that tests a file's content (the crystallize marker in the
  findings) reads the key's content; an absent key and a key without the marker
  both fail that row, as an absent file and a file without it do today.
- **R3. /explore's handoff cites no staging path, and the session still closes.**
  The handoff body names the exploration's material by session key, not by
  folder path. In the handoff arm (/scope or /charter), after the handoff key is
  written, /explore removes every key under `work/` and `research/` in
  `explore-<topic>`, leaving the handoff key and `session/branch`, so the
  consumer's existing rule (close `explore-<topic>` once the handoff is removed
  and nothing else is left) still closes it. Every other arm of Phase 5 ends by
  closing `explore-<topic>` with `done`. A run that stops before Phase 5 closes
  nothing, so its keys stay for the resume.
- **R4. /comp's state is keys, and it reads no parent file.** /comp opens
  `comp-<topic>` at setup, keeps its scope as `work/scope.md` and each juror's
  verdict as `research/phase4_<role>.md` (written to a scratch directory and
  ingested), and decides its jury resume from those keys exactly as it decides
  from files today: all three present, aggregate; some, re-run all three. It
  closes its session with `done` when it finalizes. The read of a parent state
  file is removed: /comp is in no parent's list of children and always runs
  directly. /comp's topic check is the topic grammar.
- **R5. /release's state is keys, rewritten on every run.** /release opens
  `release-<topic>`. The topic is the repository's owner and name as `gh repo
  view --json owner,name` prints them, joined as `<owner>-<name>`, lowercased,
  with each run of characters outside `[a-z0-9]` replaced by one `-` and
  leading or trailing `-` removed (`tsukumogami-shirabe` for this repository). Phase 1 writes the range, the membership list and the
  unattributed commits as `work/` keys on every run, replacing any value an
  earlier run left, so a later release never reads an earlier one's membership;
  /release has no resume. Phases 2 and 3 read those keys; an empty membership is
  a key holding no lines, which reads back as an empty list, while an absent key
  stops the run as "Phase 1 did not run". Phase 4 writes the drafted notes as a
  `work/` key and passes `gh release create --notes-file` a copy materialized
  into a scratch directory with `skill-session.sh get`, removed once the command
  returns. /release closes the session with `done` after Phase 4 (or at the end
  of a dry run) and with `abandoned` when it stops earlier on a failed check or
  a declined version. /release declares koto in its requirements file.
- **R6. No fallback.** Each moved skill stops when koto is missing (exit 127 from
  `skill-session.sh open`) or below the floor (exit 69), with the script's
  message naming koto, and never writes the staging folder instead.
- **R7. /work-on's fallback file is gone.** `extract-context.sh` writes no file.
  Called without `--session`, or with `--session` when `koto` isn't on `PATH`, it
  prints `status: failed` and `context_available: false` with a warning naming
  koto, and its header, usage text and JSON schema drop the fallback and the
  `context_file` field. /work-on itself needs koto to run its template; its
  preflight already stops on a missing or too-old koto, and that is its whole
  behavior when koto is unreachable: it stops and names koto.

### Shared pieces

- **R8. One subcommand imports a topic's sessions.** `skill-session.sh import
  <set> <topic> --from <workspace-path>` runs `koto session import <name> --from
  <workspace-path>` once per name in the set, each under its own name, in the
  set's listed order:
  - `tactical`: `scope-`, `brief-`, `prd-`, `design-`, `plan-`, `explore-<topic>`;
  - `strategic`: `charter-`, `vision-`, `strategy-`, `roadmap-`,
    `explore-<topic>`;
  - `explore`, `comp`, `release`: that one session.

  It checks the set, the topic grammar and that the path is absolute before any
  koto call, and checks that the installed koto has `session import`. It prints
  one line per name: `imported=<name>`, `skipped=<name> reason=not-found` (koto's
  `import_source_not_found`), or `failed=<name> code=<koto's error code>`. It
  stops at the first `failed` line. Exit codes: 0 when nothing failed and at
  least one name was imported; 3 when every name was skipped (nothing in the set
  exists at that source, which is how a wrong path shows); 1 at a `failed` line;
  64 for a usage refusal; 127 or 69 when koto is missing or lacks `session
  import`. A name a previous run already imported from the same source is
  reported `imported`, since koto treats it as a retry, so a re-run after a
  partial import completes it. It never passes `--as` or `--trust-template` and
  rests on no parent-child lineage.
- **R9. The convention documents what it now covers.** The convention reference
  adds /explore's working keys and /comp's and /release's keys to its per-skill
  table, the leaf skills' sessions to its session sets, and the `import`
  subcommand to "Finding a session after an import".
- **R10. The stale references are corrected (tsukumogami/shirabe#747).** Three
  places: the convention reference's Closing section states the carve-out the
  design settled (the exits that record an `exit:` value close a parent and its
  children; a clean cancel, a refusal or an error terminal close nothing); the
  Slot 7 example in `references/parent-skill-security.md` shows a key-based
  handoff instead of a staging file; the `<<ISSUE:5>>` placeholders in
  `skills/charter/references/phases/phase-finalization.md` cite the state schema
  they stand for.

### Removing the enforcement layer

- **R11. The sweep goes.** `node-push.sh` neither removes the folder before a
  push nor refuses a pushed head that carries it. Exit 69's documented causes
  lose the two folder cases; no exit code is renumbered.
- **R12. The leftover-files rule goes.** Rule `branch/no-wip-files`, the `--wip`
  check in `check-branch-output.sh`, the gates that run it
  (`branch_wip_clean` in /work-on's template, `settled_wip_clean` in /execute's),
  and the coordinated-node instruction in `execute-coordinated.md` to check the
  pushed head for the folder are removed, with the tests and registry entries
  that name them.
- **R13. The publish step and the reports stop handling the folder.** /scope's
  publish step stops untracking staging files, listing them as `wip_paths=` and
  scanning them for private markers; `print-scope-exit.sh` prints no
  `wip_paths=`; /deliver's template carries no `wip_paths` and
  `deliver-report.sh` prints none.
- **R14. shirabe's own rule text follows.** CLAUDE.md's Intermediate Storage
  section states that every skill keeps intermediate state in koto sessions
  under the convention, and `references/wip-hygiene.md` keeps only the rule
  that no committed document cites a staging path, without the enforcement
  table rows R11 to R13 remove.
- **R15. The enforcement layer comes out last.** The pull request carrying R11
  to R14 declares a dependency on every pull request carrying R1 to R7, is
  built only once they are all pushed, and merges after them. R8 to R10 carry
  no ordering constraint.
- **R16. The workspace rule's retirement is proposed, not made.** The rule that
  governs the folder lives in workspace configuration outside this repository.
  This feature doesn't edit it; the final report quotes the rule's text as the
  workspace instructions present it and proposes removing it.

### Non-functional

- **R17. Tests run the real path.** Each move is shown by a test that drives the
  skill's real scripts and `skill-session.sh` calls against real koto, in a store
  isolated by `KOTO_SESSIONS_BASE`, then reads the state back from the session
  with `koto context get`; no test seeds the keys it then asserts. R8's import
  needs koto's cloud backend, which CI can't provide, so its test drives the real
  subcommand against a koto stand-in that returns the outputs and exit codes
  koto's `DESIGN-session-migration.md` documents for `session import`, and a
  second test runs against a real bucket only when one is configured.
- **R18. Nothing private is committed.** No committed line, pull request body or
  issue names a private repository, a local path, a session or instance name, a
  job id, or a staging file path, except lines in the code and prose that
  remove or describe the folder; `scripts/ablation/check-public-content.sh
  --diff origin/main` passes before every push, and a fixture that must hold an
  old staging path has a record in `scripts/ablation/check-public-content.allow`.
- **R19. Evals follow, narrowly.** An eval scenario whose expectations name a
  file a pull request moves is updated in that pull request, and only those
  scenarios run, once per pull request; the body names them or says none ran
  and why.

## Acceptance Criteria

Moves:

- [ ] `git grep -nE 'wip/[A-Za-z0-9_<]' -- skills/explore skills/comp
      skills/release skills/work-on ':!*/evals/*'` prints no line that a
      skill's instructions or scripts follow to read or write a file; the pull
      request body lists every remaining hit with its kind (folder-not-used
      prose, a durable-document guard, or a test fixture).
- [ ] A test runs /explore's setup and one research round through the real
      commands named in its phase files, then reads `work/scope.md` and
      `research/r1_lead-<name>.md` back from `explore-<topic>`; `git status
      --porcelain` shows no `wip/` entry.
- [ ] Resume tests for /explore: with only `work/scope.md` the resume selects
      Phase 2; with lead keys and no findings, Phase 3; with findings lacking
      the marker, Phase 3; with the marker, Phase 4; with `work/crystallize.md`,
      Phase 5.
- [ ] A test runs /explore's /scope handoff arm and shows `explore-<topic>` lists
      only `handoff/scope.md` and `session/branch`, and that after the consumer
      removes the handoff the session is finished; a test of the spike-report arm
      shows the session finished with its `work/` keys still readable.
- [ ] /comp's phase files contain no read of a parent state file; a test runs
      /comp's scope and jury steps and reads `work/scope.md` and the three
      `research/phase4_<role>.md` keys from `comp-<topic>`; with two verdict
      keys present the resume re-runs all three; after finalize the session is
      finished; a topic `-x` is refused.
- [ ] /release tests, in a repository with tagged history: the range,
      membership and unattributed keys read back from `release-<topic>`; a
      second run in the same repository replaces the first run's membership; a
      range with no pull requests reads back as an empty list and an absent key
      stops Phase 2; the notes reach a stubbed `gh release create --notes-file`
      through a scratch file that no longer exists afterwards; the session is
      finished after a dry run, and finished as `abandoned` after a run stopped
      by a failed Phase 2 check; `skills/release/requires.tsv` lists koto.
- [ ] /explore's /decision arm writes `work/decision-brief.md` and reads it back
      from `explore-<topic>`; no /explore research-lead prompt names a koto
      command.
- [ ] `extract-context.sh` run without `--session`, and with `--session` but no
      koto on `PATH`, prints `"status": "failed"` and `"context_available":
      false`, names koto, and creates no file; its output has no `context_file`.
- [ ] Each moved skill's open, run with no koto on `PATH`, exits 127, and with a
      stand-in koto below the floor exits 69; neither creates a `wip/` entry.

Shared:

- [ ] The import subcommand, against a koto stand-in: with two of six tactical
      names present it prints two `imported=` and four `skipped=` lines and
      exits 0; with none present it exits 3; with a third name refused as
      `import_name_taken` it prints that `failed=` line, stops, and exits 1;
      re-run after a partial import, it reports the already-imported names
      `imported` and exits 0; a relative `--from`, an unknown set and a topic
      `-x` exit 64 before any koto call; a koto without `session import` exits
      69; no stand-in invocation carries `--as` or `--trust-template`.
- [ ] `references/skill-session-convention.md` lists the leaf skills' keys and
      sessions and the `import` subcommand; its Closing section says a clean
      cancel, a refusal or an error terminal closes nothing.
- [ ] `references/parent-skill-security.md`'s Slot 7 example names a handoff key
      and no staging file; `git grep -n '<<ISSUE:' skills/charter` prints
      nothing.

Enforcement:

- [ ] `git grep -n 'wip' -- skills/execute/scripts/node-push.sh
      references/rule-registry.json skills/work-on/scripts/check-branch-output.sh
      skills/scope/scripts/publish-scoping-pr.sh
      skills/scope/scripts/print-scope-exit.sh skills/deliver
      ':!*/evals/*'` prints nothing, and the koto templates under
      `skills/work-on/koto-templates` and `skills/execute/koto-templates` have no
      gate or instruction checking the folder.
- [ ] `node-push_test.sh`, `check-branch-output_test.sh`,
      `check-rule-registry_test.sh`, `publish-scoping-pr_test.sh`,
      `print-scope-exit_test.sh`, `deliver-report_test.sh` and
      `deliver-engine_test.sh` pass, and each still has at least one case that
      exercises the changed script.
- [ ] CLAUDE.md's Intermediate Storage section has no rule telling a workflow to
      use the folder.
- [ ] The enforcement pull request's body names the move pull requests it
      depends on, and each of those is merged before it is.

Every pull request:

- [ ] Its body states which eval scenarios ran, or that none ran and why.
- [ ] `scripts/ablation/check-public-content.sh --diff origin/main` exits 0 at
      its head.

## Out of Scope

- **Changing the convention.** Naming, key areas, the dispatch key, the close
  rule and the reclaimable rule are settled; a gap found while moving a skill is
  raised as a question.
- **The workspace rule for the folder.** It lives outside this repository; its
  retirement is proposed (R16), not made. The same holds for other repositories'
  own CI checks for a leftover folder.
- **The coordinate skill.** Its own state and record scripts move under later
  coordinator work, and its hygiene test that forbids staging paths in its own
  files stays.
- **koto changes.** Listing a source workspace's sessions, or a local bucket for
  tests, would be koto features; they are proposed, not built.
- **Pruning finished sessions.** The reclaimable rule is only evaluated.
- **Guards over committed text.** The upstream checks that refuse a staging
  path, the finalize greps that keep one out of a committed document, the
  public-content check's staging-path class and the lint that refuses a /scope
  gate reading the folder protect committed text, not the folder, and stay.
- **Readers of `wip_paths=` outside this repository.** A consumer that parses
  the field gets no line; nothing here adapts it.

## Known Limitations

- A handoff arm discards /explore's research keys once the handoff is written;
  the handoff carries what the next skill needs, and the research isn't kept
  anywhere for later reading.
- The import subcommand can only try the fixed names in a set; koto has no
  listing of a source workspace's sessions.
- The import subcommand's CI test uses a koto stand-in; the real cloud path is
  tested only where a bucket is configured.
- /release now requires koto, as every moved skill does.
- Work in flight when this lands keeps its staging files: an interrupted
  /explore, /comp or /release with files and no session starts fresh, and a
  branch that already carries staging files is no longer refused by any gate.
  Committed text naming such a file is still refused by the public-content
  check.

## Decisions and Trade-offs

- **/explore's close at handoff.** Decided: the handoff arm removes /explore's
  own keys so the consumer's existing close rule holds. Alternatives: change the
  consumer rule to close regardless of other keys (rejected: it changes the
  settled convention), or keep the keys and never close (rejected: the next
  /explore of the topic would attach to stale resume keys).
- **/release's topic and its lack of resume.** Decided: the repository's owner and name,
  normalized, with Phase 1 rewriting its keys on every run, since a version
  carries dots the topic grammar refuses and the version isn't known until
  Phase 3. Alternative: the last tag rewritten to a slug (rejected: a first
  release has no tag, and the name would change between a release and its
  retry).
- **/release's close on a stop.** Decided: `abandoned` on an early stop. The
  carve-out that a cancel closes nothing protects children a resume needs;
  /release has no children and no resume.
- **An absent source in the import.** Decided: skipped, with exit 3 when nothing
  in the set exists. Alternative: every absent name is an error (rejected: a
  chain rarely opens every session in its set).
- **Testing the import.** Decided: a koto stand-in in CI plus a real-bucket test
  when one is configured, because koto ships no local bucket. Alternative:
  installing an S3-compatible server in CI (rejected as heavy for one
  subcommand; proposed instead as a koto feature).
- **/work-on's behavior with koto unreachable.** Decided: it stops and names
  koto, as its preflight already does; the script's dead fallback goes.
  Alternative: keep a file fallback outside the work tree (rejected: nothing
  reads it, and the convention forbids a fallback).
- **Guards that stay.** The scope-gate lint and the document guards stay as
  regression guards over committed text; they cost nothing per run.

## Downstream Artifacts

- `docs/designs/DESIGN-leaf-skills-off-folder.md` (to be written): the design.
