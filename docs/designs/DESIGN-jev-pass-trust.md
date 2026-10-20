---
schema: design/v1
status: Accepted
problem: |
  Every Jev criterion needs a slice contract a machine can hold to the
  templates, a bar that grants and removes pass trust only through reviewed
  registry changes, a way to withhold a trusted criterion's rule only for a
  user whose decider is active, and a review-shadow trial that reads koto
  decider events instead of its own local store. None of that exists, and the
  registry, its checker and the review-shadow script each assume it doesn't.
decision: |
  Each Jev criterion's contract is a `jev` object on its rule-registry entry,
  and koto decider checks get a `decider` check kind. A Python module,
  scripts/jev-criteria/jev_criteria.py, checks the contracts against the
  templates (read through a pinned yq), computes declaration hashes, measures
  slices, runs fixtures against Jev and computes live figures from koto
  session logs. A bash script, scripts/jev-withhold.sh, decides which copy of
  a rule file a state loads. review-shadow.py keeps only check and scan.
  `level_fits_facts` becomes the one untrusted criterion, with a completed
  slice and a fixture file; the eleven review-shadow Jev criteria are recorded
  as rejected or blocked and lose withhold eligibility.
rationale: |
  The registry is already the one definition of a rule, and a second contracts
  file would split it. Template frontmatter is YAML and the checks need
  hashing, dates and counts, which bash 3.2 and jq handle badly, so the
  contract logic lives in Python beside a pinned yq, as shirabe already reads
  templates elsewhere. The withhold script runs inside templates like the
  other gate scripts, so it is bash and reuses rule-registry.sh's line ranges
  and the canary's render step. Retiring the trial's store rather than porting
  it avoids a second grading path beside koto's own events.
upstream: docs/prds/PRD-jev-pass-trust.md
user_visible_surface: true
decision_provenance: inline-resolved
---

# DESIGN: Jev criteria and pass trust

## Status

Accepted

## Context and Problem Statement

The PRD (`docs/prds/PRD-jev-pass-trust.md`) settles what this feature does:
slice contracts for every Jev criterion, a fixture and live bar for pass trust,
promotion and demotion only through reviewed registry changes, withholding
only where the decider is active, and the review-shadow trial moved onto koto
decider events. This document settles how, against the code as it stands.

Five pieces of the repository shape the answer.

- **The rule registry.** `references/rule-registry.json` holds one entry per
  rule. `scripts/check-rule-registry.sh` (bash 3.2, jq) holds it to the
  repository with twelve numbered checks. Its check kinds are `script`,
  `review-shadow` and `none`; any other kind fails check 1. A `gate` entry
  needs a guard or a backstop (check 2). Nothing in it knows about koto
  decider checks.
- **The one decider check.** `/work-on`'s `review_level_check` declares
  `level_fits_facts`, veto mode, `max_bytes: 2048`, label `review_facts`, run
  by `review-level.sh slice`. The slice is a fixed jq projection of the
  `review_facts.json` key that the state's own `default_action`
  (`review-level.sh facts`) writes, plus a `level:` line. It has no registry
  entry.
- **Templates are YAML frontmatter in Markdown.** Shirabe reads them in CI
  with a pinned mikefarah yq (`scripts/check-decider-declarations.sh`, run by
  `check-templates.yml`). The registry workflow installs no koto and no yq.
- **The review-shadow trial.** `scripts/review-shadow/review-shadow.py`
  (2,676 lines) grades pull requests (`grade`), records panel outcomes
  (`outcome`), grades review sites (`site`, called from `panel-scope.sh` and
  three skill phase files) and reports (`report`), all against a local store
  under `$REVIEW_SHADOW_HOME`. It also holds the Jev client, the slicers the
  criteria were built on, and the six script criteria that `scan` runs.
- **Session logs.** koto writes `<session dir>/koto-<name>.state.jsonl`: a
  header line with `session_id`, then events `{seq, timestamp, type,
  payload}`. A decider check writes `decider_checked` (payload `gate`,
  `rule_id`, `visit_seq`, `mode`, `outcome`, `reason`, `input_bytes`, ...),
  `decider_fallback` (`gate`, `rule_id`, `visit_seq`, `mode`, `reason`,
  `input_bytes`) and, after `koto decider answer`, `decider_check_answered`.
  The exported run journal carries the same as `koto.check`, `koto.rule.id`,
  `koto.visit.seq`, `koto.session.id`, `koto.decider.outcome`,
  `koto.decider.reason`, `koto.decider.mode` and `koto.decider.input_bytes`.

Measured on 2026-10-20, only `level_fits_facts` fits a koto budget on nearly
every real run; the PRD's Problem Statement has the table.

## Decision Drivers

- The registry stays the one definition of a rule (PRD R1).
- CI must check contracts against templates without koto and without spending
  a decider key, since a fork's pull request runs it (R20).
- Gate scripts must run on the bash 3.2 floor shirabe holds every template
  script to.
- No template's states, gates, directives or routes change (R16), and the koto
  floor stays 0.20.0 (R19).
- A promotion or demotion is a reviewed registry change that CI can hold to
  the bar (R12, R13).
- The trial's local store is retired, not ported (R18).
- The feature's own figures must be reproducible by a shipped command (R4).

## Considered Options

Each question below was resolved inline under `/scope`, as a standard-tier
question (`decision_provenance: inline-resolved`).

### Decision 1: Where a criterion's contract lives

Resolved inline.

**Chosen: a `jev` object on the registry entry, and a `decider` check kind.**
A koto decider check's entry carries
`check: {kind: decider, template, state, gate, criterion}`; every Jev entry,
whatever its kind, carries `jev`. The registry checker learns the new kind
and field; everything about the contract is checked by Decision 2's module.

*Alternative: a separate `references/jev-criteria.json`.* Rejected: it would
define each criterion twice (id, text, check in the registry; contract in the
second file), and the two would need a sync check of their own.

*Alternative: extend `scripts/review-shadow/criteria.json`.* Rejected: it holds
only review-shadow criteria, and `level_fits_facts` lives in a koto template,
not there.

### Decision 2: What checks the contracts

Resolved inline.

**Chosen: `scripts/jev-criteria/jev_criteria.py check`, reading the registry as
JSON and template frontmatter through a pinned yq, run by a new workflow.**
`check-rule-registry.sh` changes only to admit the `decider` kind and the
`jev` field, and to exempt a `decider` entry from check 2's guard rule, since
its withholding is governed by its contract.

*Alternative: a thirteenth numbered check inside `check-rule-registry.sh`.*
Rejected: the checks need YAML, SHA-256, dates, percentages and fixture
files; bash 3.2 with jq would need a second tool for each, and the script is
already the longest checker in the repository.

*Alternative: `koto template compile` to read gates.* Rejected: the registry
workflow has no koto, and adding one couples a registry change to a koto
release.

### Decision 3: Where the runner, measurement and reader live

Resolved inline.

**Chosen: the same module, with subcommands `declared-hash`, `measure`,
`fixtures` and `figures`, and the Jev client moved out of `review-shadow.py`
into it.** After the trial's grading is retired, the fixture runner is the
client's only caller.

*Alternative: keep the client in `review-shadow.py` and load that script by
path.* Rejected: it keeps a retired tool's file as a library for a new one,
and a hyphenated script can only be imported by path. `measure prs` still
loads `review-shadow.py` by path for its slicers, because those slicers are
the definition the rejected contracts name; moving them would change the
file each contract points at for no gain.

*Alternative: a `shirabe` CLI subcommand.* Rejected: the CLI is for
validation and gh-backed checks (CLAUDE.md), and nothing here needs compiled
code.

### Decision 4: How the withhold script decides and renders

Resolved inline.

**Chosen: bash `scripts/jev-withhold.sh`, reading the registry with jq and
`rule-registry.sh` (`range`, `text`), koto's configuration through
`koto config get`, and the session log with jq; it renders the withheld copy
the way `offload-canary.sh` does.** It is the shape a template's
`default_action` calls with `capture_stdout_as`, so a promotion wires it with
one variable, like the live canary's `PR_BODY_RULES`.

*Alternative: generalize `offload-canary.sh`.* Rejected: the canary draws a
random group per run for one rule; the withhold decision is deterministic and
per rule, and mixing them would make each harder to read.

*Alternative: Python.* Rejected: the scripts templates call are bash on the
3.2 floor, and the decision needs nothing bash can't do with jq.

### Decision 5: How much of review-shadow.py goes

Resolved inline.

**Chosen: remove `grade`, `outcome`, `site`, `report`, the store and the Jev
client; keep `check`, `scan`, the loaders, the six script criteria and the
slicers the rejected and blocked contracts name.** Remove the callers in
`panel-scope.sh` and the `/brief`, `/prd` and `/review-plan` phase files.

*Alternative: port `grade` and `site` to write koto events.* Rejected: it
would keep a grading path beside koto's decider checks, and every criterion it
grades is rejected or blocked.

*Alternative: delete the script.* Rejected: `scan` still runs `rs-001` to
`rs-006`, and the contracts point at the slicers.

## Decision Outcome

The five choices fit together around one record. A Jev criterion's whole
story is its registry entry: the `check` says where it runs (a koto gate, or
nowhere for a review-shadow criterion now), and the `jev` object says what its
slice holds, how big it is, what proves it, and whether it is trusted. One
module checks that record against the templates and fixtures, computes every
figure the record holds, and is the only code that talks to Jev. One bash
script reads the record at run time to decide what a session loads. The
trial's own store and grading paths go, so the only Jev evidence left is what
koto writes.

## Solution Architecture

### Registry entry

A Jev entry gains `jev`; a koto decider check's entry also uses the new check
kind. The new entry for `level_fits_facts`:

```json
{
  "id": "work-on/review-level-fits-facts",
  "status": "active",
  "summary": "The chosen review level is lighter than the change's facts call for",
  "text": {"path": "skills/work-on/references/review-levels.md",
           "first": "The rules:", "last": "- `light` otherwise."},
  "check": {"kind": "decider", "template": "skills/work-on/koto-templates/work-on.md",
            "state": "review_level_check", "gate": "level_fits_facts",
            "criterion": "level_fits_facts"},
  "fixtures": ["scripts/jev-criteria/fixtures/work-on-review-level-fits-facts.jsonl"],
  "level": "gate",
  "timing": ["work-on:review_level_check"],
  "guards": ["none"],
  "withhold": "never",
  "baseline_keys": [],
  "aliases": [],
  "notes": "Registered after the baseline pin, so it has no baseline key.",
  "jev": {
    "state": "untrusted",
    "sources": [
      {"what": "review_facts.json", "writer": "gate-script",
       "script": "skills/work-on/scripts/review-level.sh"},
      {"what": "REVIEW_LEVEL", "writer": "graded-artifact"}
    ],
    "slice_script": "skills/work-on/scripts/review-level.sh",
    "budget": 2048,
    "completeness": {"path": "references/jev-criteria.md",
                     "heading": "work-on/review-level-fits-facts",
                     "verdict": "sufficient"},
    "measured": {"population": "koto-sessions", "runs": 0, "max": 0, "p90": 0,
                 "over_budget": 0, "on": "2026-10-20",
                 "command": "python3 scripts/jev-criteria/jev_criteria.py measure sessions ..."},
    "fixtures": "scripts/jev-criteria/fixtures/work-on-review-level-fits-facts.jsonl",
    "declared": {"sha256": "<declared-hash output>", "since": "2026-10-20"},
    "false_passes": []
  }
}
```

The `measured` figures are filled from the shipped command run over the new
slice, so they differ from the PRD's pre-change figures by the order line.
The entry's top-level `fixtures` keeps its existing meaning (the tests and
files that exercise the check); `jev.fixtures` names the one fixture-profile
file R8 describes. The registry's existing checks apply to a `decider`
entry as to any other: its template path must exist (check 3), its text
anchors must resolve (check 4) and its text path must be in the workflow's
filter (check 9).

A review-shadow Jev entry (`rs-007` to `rs-017`) keeps its `review-shadow`
check and gains a `jev` object whose `state` is `rejected` or `blocked`,
`slice_script` `scripts/review-shadow/review-shadow.py`, `budget` 2,560, and
`measured` from `merged-prs` (`rs-007`, `rs-008`, `rs-009`) or
`review-shadow-records` (the rest), or `not_measured: no-real-run-record`
(`rs-014`). Its `withhold` becomes `never`.

A promotion adds `jev.promotion`:

```json
"promotion": {
  "trusted_since": "YYYY-MM-DD",
  "slice_script_blob": "<git blob hash>",
  "fixture_run": {"on": "YYYY-MM-DD", "model": "<reported model>",
                  "fixtures_blob": "<git blob hash>",
                  "counts": {"good": {"pass": 0, "fail": 0, "unclear": 0, "error": 0},
                             "seeded-bad": {"...": 0}, "adversarial": {"...": 0}}},
  "live": {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "evaluations": 0,
           "sessions": 0, "answered": 0, "over_budget_fallbacks": 0,
           "max_input_bytes": 0}
}
```

and sets `state: trusted`, `withhold: eligible`. A false pass appends
`{"evaluated": "YYYY-MM-DD", "recorded": "YYYY-MM-DD", "oracle":
"review|ci|human", "evidence": "<url>"}` to `false_passes`.

`references/jev-criteria.md` holds one `## <rule id>` section per criterion:
its sources, slice, completeness case, measured figures and the reason for its
state. `references/rule-registry.md` documents the `decider` kind and the
`jev` object.

### `jev_criteria.py`

Standard-library Python 3.8, one file, with `test_jev_criteria.py` beside it
and fixtures under `scripts/jev-criteria/fixtures/`. It shells out to `yq`
(template frontmatter to JSON), `git` (blob hashes) and
`scripts/rule-registry.sh` (release checks), and to nothing else.

| Subcommand | Does |
|---|---|
| `check [--root DIR] [--base REF]` | holds every Jev entry to the contract rules below, and with `--base` to the history rules; prints one line per problem; exit 0, 1 problems, 2 couldn't run |
| `declared-hash RULE_ID` | prints the declaration's canonical JSON and its SHA-256 |
| `measure sessions --dir DIR` | runs the slice projection over every `review_facts.json` key under a koto sessions directory and prints the figures |
| `measure prs --repo OWNER/REPO --limit N --kind KIND` | builds one whole-run slice per merged pull request through `gh` and prints the figures |
| `measure records --dir DIR --kind KIND` | sums each review-shadow record's slices of a kind and prints the figures |
| `fixtures RULE_ID [--endpoint URL]` | sends each fixture case to Jev and prints counts by kind and answer, and the exact `fixture_run` JSON to paste into the promotion |
| `figures RULE_ID --sessions DIR [--from D] [--to D] [--bar]` | computes R10's figures from koto session logs and prints the exact `live` JSON; with `--bar`, exits 0 when they meet it and 1 when not |

**Contract rules (`check`).** For every entry whose check is `decider`, and
every `review-shadow` entry whose criterion's observer in `criteria.json` is
`jev`:

1. `jev` is present with the fields R1 lists for its state; `sources` is
   non-empty, each `writer` is `git`, `gate-script`, `graded-artifact` or
   `slice-script`, and a `gate-script` names an existing `script`;
   `slice_script`, `completeness.path` and `fixtures` exist, and
   `completeness.heading` is a `## ` heading in its file.
2. `measured` has integer runs, max, p90 and over-budget figures with
   `over_budget <= runs`, a population from the closed set, or instead
   `not_measured: no-real-run-record`.
3. The recorded state is the one R2's table gives: rejected when
   `over_budget * 100 > runs * 5` or the verdict is `insufficient`; blocked
   when no template declares the criterion; untrusted or trusted otherwise.
4. `budget <= 2560`; for a decider entry, `budget` equals the gate's
   `max_bytes` and the gate's command contains `slice_script`.
5. An untrusted or trusted contract has `runs >= 100` and a fixture file
   meeting R8, each case `{id, kind, technique?, expected, input, slice}`.
6. A decider entry's `declared.sha256` equals the hash `declared-hash`
   computes now.
7. A trusted entry has `promotion` with every field, fixture counts that add
   up to the file's cases, both bars met, blob hashes equal to the
   repository's, a `fixture_run.declared_sha256` equal to `declared.sha256`
   (so a fixture run under an older declaration doesn't count), `live.from`
   no earlier than `declared.since` and later than every false pass's
   `evaluated` date, `trusted_since` equal to `live.to`, template mode
   `veto`, and `withhold: eligible`. An untrusted entry has no `promotion`.
8. Every false pass has `evaluated`, `recorded`, an `oracle` from the closed
   set and an `evidence` link to `https://github.com/`; `measured.command`
   and every evidence link hold no home-directory or absolute local path.
9. An entry that isn't trusted is `withhold: never`.
10. An untrusted or trusted entry's text is releasable: `rule-registry.sh
    release` prints its marker lines, not a refusal.
11. Every criterion of every `decider-check` gate in `skills/*/koto-templates/`
    has an entry, and none of them is rejected or blocked.
12. A template state whose `default_action` or gate command runs
    `jev-withhold.sh` passes, as the command's first quoted argument after
    the script, only a rule id whose entry is `trusted` and whose `check`
    names a decider check of that same template, and its `## <state>`
    directive has `rule-registry.sh` and `release <rule id>`. A command
    naming the script whose first argument isn't a literal rule id is a
    problem. A test also greps every file under `skills/`, `koto-templates/`
    and `hooks/` and fails when anything other than a template's command
    calls the script, so a wrapper script can't hide a call. With no trusted
    entry, as when this ships, nothing may call it.

Every rule that names a template, state, gate or criterion reports a problem
when one doesn't resolve. Rule 11 covers templates under
`skills/*/koto-templates/` and `koto-templates/`.

With `--base REF` (the workflow passes the merge base), two history rules
hold too, as `check-rule-registry.sh`'s check 11 does for ids:

13. Every Jev entry at the base still has its `jev` object, and every false
    pass it held there is still there, unchanged and in order: the history
    only grows.
14. When an entry's `declared.sha256` differs from the base's,
    `declared.since` is no earlier than the date of the merge-base commit,
    so a changed declaration restarts its live window and can't reach back
    over events recorded under the old one.

The PRD's acceptance criteria say "the registry check" for these rules; it
means this module's `check` together with `check-rule-registry.sh`, the two
checks the workflows run over the registry.

**The declaration hash.** `declared-hash` reads the gate with yq and builds
`{"command", "label", "max_bytes", "question", "pass", "fail", "escape",
"threshold"}`, with `label` defaulting to `artifact`, `max_bytes` to 2,560
(an integer) and `threshold` to 0.9 (a float), the defaults koto's authoring
guide states, serialized as `json.dumps(obj, sort_keys=True,
separators=(",", ":"), ensure_ascii=False)` encoded as UTF-8, and hashed with
SHA-256. `threshold` is converted to a float before serializing, and the
criterion is selected by its id inside the gate's `criteria` map, so a gate
with several criteria hashes each one apart. A test pins one declaration's
exact hash. It differs from koto's own
`declaration_hash` on purpose: it includes the threshold, which changes what
counts as a pass, and it is computable without koto.

**The fixture runner.** It reads the declaration with `declared-hash`'s
reader, the key from `KOTO_DECIDER_API_KEY` and the endpoint from
`KOTO_DECIDER_ENDPOINT` or koto's default, and refuses a non-https endpoint
other than loopback. Each case sends
`{"model": "jev-latest", "state": {<label>: <slice>}, "questions":
{<criterion>: {"type": "choice", "instructions": <question>, "criteria":
{"pass": <pass>, "fail": <fail>, "unclear": <escape>}}}}`, retried once on a
transport error, a 5xx or an unreadable answer, as koto does, and maps the
answer with koto's threshold rule to `pass`, `fail`, `unclear` or `error`.
Exit codes follow R9. The key is never printed, logged or put in an error.
The `fixture_run` it prints records the `model` field of Jev's answers (the
one koto records as `koto.decider.model`) and the declaration hash it ran
under. The endpoint must be `https`, or `http` only to a host that parses as
`localhost`, `127.0.0.1` or `::1`, and a URL carrying user information is
refused.

**The reference reader.** For each `*/koto-*.state.jsonl` under the sessions
directory it reads the header's `session_id`, then each event whose type is
`decider_checked` or `decider_fallback` and whose payload `gate` and `rule_id`
match the entry's gate and criterion id (koto's `rule_id` is the criterion id
the template declares, not the registry id), within the window by
`timestamp`. It keys evaluations by
(session id, `visit_seq`, gate, rule id), marks one answered when any of its
`decider_checked` events has outcome `pass` or `fail`, and counts sessions,
`over_budget` fallbacks, the largest `input_bytes` and the lines it couldn't
parse. `decider_check_answered` events are read only to be ignored. Without
`--from`, the window starts on the later of `declared.since` and the day
after the latest false pass; without `--to`, it ends today (UTC).

`measure records` parses each record's JSON itself (`slices[].kind` and
`.bytes`) and needs no review-shadow code. `measure prs` uses the slicers
Decision 5 keeps (`slice_pr_summary`, `slice_code_hunks`, `slice_doc_pairs`
and the helpers they call), none of which touches the store or the Jev
client.

### `review-level.sh`

`cmd_slice` and a new `project <facts-file> <level>` subcommand share one
function that prints the projection, a new line `levels: light < standard <
full`, and the `level:` line. The projection also becomes strictly typed:
`lines` and `files` are kept only when they are non-negative integers and are
0 otherwise, and `classes` keeps at most 16 names matching `[a-z0-9_]`, so no
free text from a hand-edited facts key reaches Jev. `project` is what the fixture test and
`measure sessions` call, so a fixture's slice is the script's output by
construction. The gate's command is unchanged, so its declaration hash and
koto's are unchanged too.

### `jev-withhold.sh`

```text
jev-withhold.sh <rule-id> <rule-file> <session-name> <session-dir> <plugin-root>
```

`<rule-file>` is the plugin-relative path of the file the state loads, which
the template writes as it writes any other reference path, so the script
always has a full file to fall back on even when it can't read the registry.
A template passes `{{SESSION_NAME}}` and `{{SESSION_DIR}}`, as the gate
scripts' escalation ladder does. The script always exits 0 and prints one
path, set up front to `<plugin-root>/<rule-file>` and printed by an `EXIT`
trap, so a crash anywhere prints the full file. It prints the withheld copy
only when every check passes, in order, stopping at the first that fails:

0. The rule id matches the registry's id shape, the session name matches
   koto's, `<rule-file>` is a safe relative path, and the session directory
   exists and is not a symlink.
1. jq reads the entry: `jev.state` is `trusted`, `withhold` is `eligible`,
   and `text.path` equals `<rule-file>`.
2. `koto config get decider.mode` prints `auto`.
3. `koto config get decider.api_key`, with its output discarded, exits 0.
4. `.koto/config.toml` in the working directory, which is where koto reads
   the project's configuration, is absent, or no line of it outside a comment
   mentions `decider` at all. Any mention, in any TOML form, counts as a
   project setting.
5. jq over `<session-dir>/koto-<session-name>.state.jsonl` finds no
   `decider_checked` with `mode` other than `veto`, no `decider_fallback` and
   no `decider_check_answered` whose payload `gate` and `rule_id` are the
   entry's gate and criterion id. A missing or malformed log fails this
   check.

When all hold, it writes the rule file without the lines `rule-registry.sh
range` gives to a temporary file in `<session-dir>/jev-rules/`, refusing a
symlinked directory or target as `offload-canary.sh` does, checks that the
first removed line is the one `rule-registry.sh text` prints, moves it into
place as `<session-dir>/jev-rules/<rule-id with / as ->-<file name>`, and
prints that path; any failure there prints the full file instead.
koto's `capture_stdout_as` puts the path in a variable a directive names, as
the canary does. Because condition 5 reads the log on every call, a fallback
or an agent answer makes every later call in the session print the full file.

### Review-shadow

`review-shadow.py` drops `grade`, `outcome`, `site`, `report`, the store
(`store_home`, `write_private`, the record and outcome writers and readers),
the site assembly and seat readers, and the Jev section, which moves to
`jev_criteria.py`. `test_review_shadow.py` drops the matching tests and keeps
a test that no remaining code names `REVIEW_SHADOW_HOME`. `panel-scope.sh`
loses `shadow_site()` and its call; `panel-scope_test.sh` loses its tests.
The `/brief` and `/prd` phase 4 files and the `/review-plan` phase 5 file lose
their call. `docs/guides/review-shadow.md` says the store is retired and
points at the Jev criteria guide. `check-review-shadow.yml` keeps its
per-criterion jobs and its suite.

### CI

A new workflow, `check-jev-criteria.yml`, runs on pull requests touching the
registry, `references/jev-criteria.md`, `scripts/jev-criteria/**`,
`scripts/jev-withhold*`, `scripts/rule-registry.sh`, templates,
`review-level.sh`, `scripts/review-shadow/**`, the guide or itself. It runs on
`pull_request` (never `pull_request_target`) with `contents: read`, uses no
secret, and installs yq with the same version and checksum-verified step as
`check-templates.yml`, copied verbatim. On Linux it runs
`test_jev_criteria.py`, `jev_criteria.py check --base <merge base>` and
`jev-withhold_test.sh`; on macOS it runs `jev-withhold_test.sh` on the bash
3.2 floor. No job has a decider key or runs `fixtures`, `measure` or
`figures` outside their tests, and the tests replace the module's network
opener with one that refuses every call.

### Guide

`docs/guides/jev-criteria.md` has three sections the doc test looks for:
"Reading the live figures" (the R10 definitions as queries over exported
records, filtered by `koto.check` and `koto.rule.id`, grouped by
`koto.session.id` and `koto.visit.seq`, and the `figures` command that
computes the same from session logs), "Promoting a criterion" and "Demoting a
criterion" (the commands to run, the fields to record, what CI checks).

## Implementation Approach

One pull request. The order keeps every intermediate commit consistent, so
the checker never lands before the entries it checks:

1. **Registry vocabulary.** `check-rule-registry.sh` admits the `decider` kind
   and the `jev` field and exempts a decider entry from the guard rule; its
   test suite covers both. `rule-registry.md` documents them.
2. **The slice.** `review-level.sh` gains the typed projection, the order line
   and `project`, with tests pinning the output and the worst-case size.
3. **Contracts and checker together.** `jev_criteria.py` (`check`,
   `declared-hash`, `measure`), its tests, `references/jev-criteria.md`, the
   `level_fits_facts` entry with its fixture file and measured figures, the
   `jev` objects and `withhold: never` for `rs-007` to `rs-017`, and the
   workflow (without its withhold-script steps), in one commit, so `check`
   first runs against a complete registry.
4. **Runner and reader.** `fixtures` and `figures` with stub-endpoint and
   fixture-log tests; the Jev client is copied in, since `grade` still uses
   the original until step 6.
5. **Withhold script.** `jev-withhold.sh`, `jev-withhold_test.sh`, the
   checker's template rule (12) and the workflow's withhold-script steps.
6. **Trial retirement.** The review-shadow subcommands, store, callers and
   the original Jev client go, with their tests; the review-shadow guide
   changes.
7. **Guide.** `docs/guides/jev-criteria.md` and its doc test.

## Security Considerations

**The decider key.** The fixture runner reads the key from the environment
only, sends it in an unredirected `Authorization` header with redirects
refused (the review-shadow client's behaviour, moved unchanged), never
prints it, drops error bodies that could echo it, and refuses an endpoint
that is neither https nor a parsed loopback host, or that carries user
information. CI never has a key, and the workflow runs on `pull_request`
with read-only permissions and no secrets.

**What reaches Jev.** R3 keeps the agent from choosing what Jev sees, not from
shaping the work Jev judges: the agent writes the diff whose facts the slice
counts, and chooses the level the slice names, and those are exactly what
the criterion grades. What it can't do is add free text. The
`level_fits_facts` projection is typed (integers, at most 16 class names from
`[a-z0-9_]`, booleans, a floor and a level from closed sets, and the fixed
order line), so a hand-edited facts key can't smuggle an instruction through.
The adversarial fixtures test what remains.

**Fixtures are synthetic.** The `level_fits_facts` fixtures are facts files
written for the purpose, not copied from sessions; no fixture holds text from
a real session, pull request or record. Reviewers check this for any new
fixture file, since the checker can't tell a real input from a written one.

**Withholding fails closed.** The script validates its arguments, sets the
full file as its answer before doing anything, prints it from an `EXIT`
trap, and treats any project decider mention, any unreadable input and any
fallback or agent answer in the session as a reason to load the rule. It
writes only inside the session's own directory, through a temporary file
moved into place, refuses symlinks, and discards a copy whose removed first
line doesn't match the registry. No template calls it in this feature, and
the checker refuses one that calls it for a rule that isn't trusted.

**Promotion evidence.** CI checks that a promotion record is complete, adds
up, meets the bar, matches the repository's hashes and keeps false passes
append-only. It can't check that the figures are true: it has no key and no
session logs. Provenance rests on review: the guide has the reviewer of a
promotion re-run `figures --bar` over the exported events and `fixtures`
with their own key before merging, and a promotion pull request is never
merged by its author.

**Public repository.** Measured figures are aggregate counts and sizes from
closed populations. The checker refuses a `measured.command` or evidence
link holding a local path, and evidence links must point at GitHub.
`measure records` reads a directory its caller names and prints only figures.

**Residual risks, accepted.** These hold until the first promotion and are
recorded so that promotion's review weighs them:

- *First-call outage.* A session whose rule was withheld can meet a decider
  that is down at the check. The check then falls back, and R15's release
  step gives the agent the full rule before it answers, so no verdict is
  lost, but the agent works from the rule only at the check, not before it.
- *A writable session log.* An agent could edit its own session log to hide
  a fallback from the withhold script. koto's own gate still evaluates, so
  the check is not skipped; only the reload is.
- *No automatic demotion.* A criterion that starts failing keeps its trust
  until a reviewer merges a demotion. The guide asks the owner of each
  trusted criterion to re-read its figures when the model koto reports
  changes, since trust was earned against one model build.
- *Self-reported evidence.* As above, CI checks shape and arithmetic; the
  reviewer checks truth.
- *Trust not bound to everything the slice reads.* The promotion hashes the
  declaration, the slice script and the fixture file, but not
  `review-level-rules.tsv`, which sets the floor the slice prints, or the
  rule's text. A change to either doesn't revoke trust on its own; the
  guide asks a pull request that changes one to re-read the criterion's
  figures.

## Consequences

**Positive.** Every Jev criterion has one checked record, and the eleven that
can't run inside a koto gate say so with their measurements instead of
sitting in a trial nobody can read. Trust has a mechanical bar and a reviewed
path both ways. A future promotion wires a withheld rule with one script call
and one variable. The review-shadow script loses about two thirds of its code.

**Negative.** No criterion can be trusted until a host opts its decider in and
thirty evaluations accumulate. The checker adds a Python dependency and a
pinned yq to a third workflow. Retiring the trial throws away its grading
paths, so reviving a criterion means building it as a koto gate. The
in-flight check-lifecycle work also edits `check-rule-registry.sh`, so
whichever lands second rebases.

**Mitigations.** The guide states how to opt in and read the figures. The yq
pin is the one `check-templates.yml` already uses. The removed code stays in
history, and the slicers that define the rejected criteria stay in the
script.
