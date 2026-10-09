---
schema: design/v1
status: Proposed
problem: |
  shirabe's gate scripts read their rules from a tab-separated table beside the scripts, the
  review-shadow trial reads its criteria from its own JSON file, and the rule text both point
  at lives in prose. A gate finding's rule_ref is a stored line range at a stored commit, so it
  goes stale on the next edit above the rule, and three of the four commits the table pins were
  squashed off main. Nothing records a rule's check, fixtures, enforcement, timing or whether
  it may ever be withheld, and no script can hand an agent a rule's text when the rule applies.
decision: |
  One JSON registry, references/rule-registry.json, holds an entry per rule: the 22 gate rule
  names and rs-001 to rs-017 under their existing ids, plus the takeover rule. Each entry finds
  its full text by two literal anchors (a substring of the first and of the last line), so
  scripts/rule-registry.sh computes rule_ref when a finding is printed, as
  <path>#L<a>-L<b>@<revision>, where the revision is the checkout's commit or, in an installed
  copy, the release tag. The gate scripts declare the ids they can print and read refs and
  short text through the helper, which refuses an unregistered or retired id; gate-rules.tsv
  goes away. The review-shadow criteria stay in their file and the registry references them.
  The same helper's release mode prints a rule's text on standard error, and /execute's owned-PR
  lookup calls it in the takeover case. A check script run by a new CI job enforces the fields,
  vocabularies, ids, pointers, withhold safety and baseline keys.
rationale: |
  Computing the reference from an anchor is the only form that is right after an edit without
  a re-pin, and it never names a commit a squash merge removed, because the revision is either
  what the running copy is or a release tag on main. Anchors in the existing prose leave every
  loaded file untouched, which a withholding experiment needs and the no-withholding rule
  demands. JSON is read by jq, already a dependency of every gate script, and by the
  review-shadow tool's standard library, so no reader is added. Referencing the criteria rather
  than moving them keeps the trial tool, its tests and its Python 3.8 floor exactly as they are.
  A declared id list per script makes the set of printable ids a static fact a check can read,
  instead of a guess from grepping strings.
upstream: docs/prds/PRD-rule-registry.md
decision_provenance: inline-resolved
user_visible_surface: false
---

# DESIGN: Rule registry

## Status

Proposed

## Context and Problem Statement

The requirements are in `docs/prds/PRD-rule-registry.md`. This design settles how they're
met. Five facts from the repository at `4dc0df0` shape it.

**Who reads rules today.** `skills/work-on/scripts/gate-rules.tsv` has one row per gate rule:
the name, `<path>#L<a>-L<b>`, a 12-character commit and an excerpt. Four scripts read it with
the same `awk` lookup (`check-branch-output.sh`, `check-pr-output.sh`, `check-verification.sh`
and `panel-scope.sh --verdict`), and `gate-rule-refs_test.sh` checks that each excerpt still
sits inside its range at `HEAD`. `scripts/review-shadow/criteria.json` has 17 criteria, each
with an opaque `rule_id` and a `rule_ref` that is only a path; `review-shadow.py` refuses a
criterion that lacks a field or names a path that doesn't exist, and `categories.json` lists
which criteria cover which finding category.

**Stored commits don't survive squash merges.** Of the four commits the table pins
(`246d366312dc`, `13682ab38dd3`, `e32bfc216e39`, `25e5ea426ff8`), only the first is an ancestor
of `origin/main`. The others were branch commits of pull requests that were squash-merged, so a
reader on `main` can't open the text those references name.

**Installed copies have no git metadata.** A plugin installed from a release is a copy of the
repository tree without `.git`. Its `.claude-plugin/plugin.json` carries the version, and every
release commit (`chore(release): set version to vX.Y.Z`) is on `main` with a `vX.Y.Z` tag.

**A real trigger exists.** `skills/execute/scripts/adopt-or-create-pr.sh` exits 6 when the one
pull request on a plan's shared branch carries another run's marker. `/execute`'s template
states the rule for that case at its `orchestrator_setup` state: don't take the pull request
over without a positive signal that the earlier run ended. The script already prints one line
on standard error in that case and nothing on standard output.

**The baseline has keys but no key list.** `docs/measurement/offload-baseline/README.md` keys a
rule by `<path>#L<start>-L<end>` at the pinned commit `2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10`
and expects a registry to re-key those records. No file in the repository lists the keys; the
records are produced by measurement outside it. Neither `gate-rules.tsv` nor `criteria.json`
existed at the pinned commit, though most of the prose they point at did.

## Decision Drivers

- **D1. One home.** Every id a gate, gate script, criterion or trigger uses is defined in
  exactly one file, and that file links to the text, the check and the tests.
- **D2. Ids never move.** Existing ids keep working, ids are never deleted or reused, and an id
  can't be a location.
- **D3. References stay right.** A `rule_ref` opens the rule's text at a revision the reader
  can reach, after edits elsewhere in the file, without anyone re-pinning it.
- **D4. Nothing loaded changes.** No file the baseline's load manifest lists and no skill
  template loses a line (the PRD's R9). Adding to them is also avoided, so the registry doesn't
  move token counts.
- **D5. No new dependency or koto feature.** Shell readers use `jq`, which every gate script
  already needs; the review-shadow tool stays standard-library Python 3.8 and unchanged; koto
  0.15.0 stays the floor.
- **D6. Checks, not conventions.** Every property the PRD names as standing is enforced by a
  script in CI, with a test that shows it failing.
- **D7. Callers don't notice.** Gate exit codes, finding shapes and the owned-PR lookup's
  standard output and exit codes stay as they are.

## Considered Options

Each question below was resolved inline, within this design's own evaluation, because each is
a standard-level choice under `/scope`'s sentinel; none was delegated to a separate decision
record.

### Decision 1: Where the registry lives and in what format

**Chosen: one JSON file, `references/rule-registry.json`, with a companion
`references/rule-registry.md` that documents its fields.** `references/` is the plugin-root
directory every skill reaches through `PLUGIN_ROOT`, and it's where the texts most gate rules
point at already live (`pr-body-conformance.md`, `wip-hygiene.md`). Shell reads the file with
`jq`; the review-shadow tool, or any later Python reader, uses `json` from the standard library.

*Alternative: keep and widen `gate-rules.tsv`.* The table already exists and four scripts read
it with `awk`. It can't hold a list of fixtures, a list of timings or a nested check without
inventing an escape scheme, and it lives inside `/work-on`'s scripts directory, where the
review-shadow criteria and `/execute`'s trigger don't belong. Rejected on shape and location.

*Alternative: TOML or YAML, like `skills/writing-style/rules.yaml`.* Friendlier to edit by
hand, but no shell reader for either is a declared dependency, and the review-shadow tool's
Python 3.8 floor predates `tomllib`. Rejected on D5.

*Alternative: `scripts/rule-registry.json`, beside `decider-declarations.tsv`.* Equally
reachable. Rejected because the registry is about rules and their text, which live under
`references/`, and readers looking for "what does rule X say" look there first.

### Decision 2: Whether the review-shadow criteria move into the registry

**Chosen: they stay in `criteria.json`, and each `rs-` entry references its criterion.** The
entry's check is `{"kind": "review-shadow", "criterion": "rs-002"}`. A check holds the two
files together: the `rs-` id sets are equal in both directions, and each entry's full-text path
equals the criterion's `rule_ref`. `criteria.json`, `review-shadow.py` and its tests don't
change.

*Alternative: move the criteria's grading fields (question, values, escape, threshold) into
the registry and have the tool read them from there.* One file instead of two, which is what
the trial's own design anticipated ("opaque ids make that a copy"). It changes the trial tool,
its loader's refusal rules and its fixtures in the same pull request that introduces the
registry, during a trial whose records must stay comparable. Rejected for now; the opaque ids
mean it stays a copy whenever the trial settles.

### Decision 3: Whether `rule_ref` is computed or stored, and what revision it names

**Chosen: computed when the finding is printed.** `rule-registry.sh ref <id>` reads the entry,
finds its first and last line in the copy of the file the script runs from (Decision 4), and
prints `<path>#L<first>-L<last>@<revision>`. The revision is:

- in a git checkout, the 12-character commit of `HEAD`, when the file has no uncommitted
  changes; with uncommitted changes, the literal `worktree`, so a dirty development copy never
  claims a commit whose lines differ;
- in an installed copy (no `.git` at the plugin root), `v<version>` from
  `.claude-plugin/plugin.json`, which is the release tag. Every release tag points at the
  release commit on `main`, so `git rev-parse v<version>^{commit}` in a clone of `main` turns it
  into a commit, and a reader can join a tagged reference to a commit-pinned one; it names
  exactly the tree that was installed.

The plugin root counts as a checkout only when `git rev-parse --show-toplevel` from it returns
the plugin root itself, so a copy that happens to sit inside some other repository isn't
mistaken for one.

*Alternative: store the range and commit, and fail CI until a contributor re-pins it.* What the
gate table does today, made strict. Every edit above a rule becomes a CI failure and a re-pin,
and the commit a pull request pins is a branch commit that its own squash merge removes from
`main`, which is the problem this feature exists to fix. Rejected on D3.

*Alternative: store the range, compute nothing, and name the release tag.* Stable for
installed copies, but the stored range is wrong at the first release after an edit. Rejected on
D3.

*Alternative: a content hash instead of a revision.* Unambiguous, but nobody can open a hash in
a browser or with `git show`. Rejected because `rule_ref` exists to be opened.

### Decision 4: How an entry finds its text

**Chosen: two literal anchors.** `text` is `{"path": ..., "first": ..., "last": ...}`. `first`
is a substring that occurs on exactly one line of the file; that line starts the rule. `last`
is a substring of the line that ends it: the first line at or after the start that contains it.
For a one-line rule `last` is omitted. Anchors are plain substrings, compared as bytes, so they
need no escaping and survive any edit that doesn't touch the rule's own first or last line.

*Alternative: marker comments in the prose (`<!-- rule: x -->`).* Exact and self-describing,
and it adds lines to files the baseline loads, which moves the token baseline and edits every
template a rule lives in. Rejected on D4.

*Alternative: heading anchors.* Markdown headings are stable and linkable, but most rules
aren't sections: the verification rules are table rows, the PB checks are list items, and one
rule is a comment inside a template. Rejected because it fits a minority of rules.

*Alternative: one excerpt and a fixed line count.* Simpler, and a reworded rule that gains a
line would silently lose its last line. Rejected.

### Decision 5: The short text and the finding message

**Chosen: an entry's `summary` is the short text, and the gate scripts print it as the start of
the finding's `message`, followed by `: ` and their existing detail.** A finding that read
`conventional-subject: abc123 "update stuff"` now reads `Commit subject is not a Conventional
Commits subject: abc123 "update stuff"`. The detail is unchanged, so every test that matches a
substring of it keeps passing; the summary gives the agent the rule in words before the detail.

*Alternative: a separate `summary` field on the finding.* It would keep the message exactly as
it is. koto's finding shape names `rule_id`, `level`, `message`, `rule_ref`, `path` and `line`,
and an extra field isn't part of that contract, so whether it reaches the event and the
blocking condition depends on koto's parser rather than on anything shirabe controls. Rejected
on D5; the message is the field every koto release shows.

*Alternative: leave the message alone.* The registry would hold a short text nobody sees on
failure, which is the one thing the PRD says the short text is for. Rejected.

### Decision 6: The closed vocabularies

**Chosen:**

| Field | Values | Meaning |
|---|---|---|
| `status` | `active`, `retired` | A retired entry keeps its id; its text needn't resolve, and no script may print it. |
| `level` | `gate`, `shadow`, `prose` | `gate`: a koto gate holds or reroutes the run on it. `shadow`: graded and recorded beside a panel, never blocking. `prose`: stated in a skill or template, checked by nothing. |
| `timing` | `<skill>:<state>`, or `pre-merge` | Each `<skill>:<state>` must name a `## <state>` section of `skills/<skill>/koto-templates/<skill>.md`; `pre-merge` is the review-shadow trial's point, after a pull request is ready and before its panel. A list, never empty. |
| `guards` | `pr-create`, `push`, `force-push`, `merge`, `close-issue`, `release`, `delete-branch`, `publish`, `destroy-record`, `none` | What the rule exists to keep from doing harm that can't be taken back once it happens. A list, never empty; `none` stands alone. |
| `withhold` | `never`, `eligible` | Required, with no default. Any guard other than `none` requires `never`. |
| `check.kind` | `script`, `review-shadow`, `none` | `script` names `path` (and optionally `mode`); `review-shadow` names `criterion`; `none` names nothing. |

**How guards were classified.** A gate rule guards the action its gate stands in front of: the
commit and pull-request rules guard `pr-create` and `push` (the commit walk runs before the pull
request opens and before `/execute` pushes its settled branch), the branch and docs rules guard
`pr-create` and `publish`, the verification rules guard `pr-create`, the panel rule guards
`pr-create` and `merge`, and `branch/current-with-main` guards `push` and `merge`. All 22 are
therefore `never`. Of the criteria, `rs-001` (attribution), `rs-002` (private names) and `rs-003`
(scratch paths) guard `publish`: their violation is public the moment a commit or body is
pushed, and a later fix doesn't take it back. `rs-004` to `rs-017` judge quality a later commit
can fix before merge, guard `none`, and are `eligible`. The takeover rule guards `push` and
`publish` (taking over rewrites another run's pull request) and is `never`.

*Alternative: let `withhold` stand alone, reviewed per entry.* Simpler, and a mismarked rule is
the mistake a reviewer misses. Rejected; the PRD settled this.

*Alternative: a numeric enforcement level.* Orderable, but the three cases differ in kind, not
degree. Rejected.

### Decision 7: The deliver-on-trigger shape

**Chosen: `rule-registry.sh release <id>` prints the rule's text on standard error, between two
marker lines, and `adopt-or-create-pr.sh` calls it in its exit-6 branch.**

```text
::shirabe-rule::{"rule_id":"execute/pr-takeover-needs-signal","rule_ref":"skills/execute/koto-templates/execute.md#L1382-L1387@v0.25.0"}
**Another run's PR (exit 6 on `impl/{{PLAN_SLUG}}`, step 2).** The one PR on this PLAN's ...
...
::shirabe-rule-end::
```

The lines between the markers are the file's lines from the entry's first to its last line,
byte for byte, so the agent reads exactly what the template says. The marker lines make a
delivery countable by anything that later reads tool output. `release` always exits 0: when the
registry, the entry or the text can't be read, it prints one line,
`rule-registry: could not release <id>: <reason>`, on standard error and nothing else, so a
trigger can never change its caller's result. The template keeps its prose; this is a copy.

It needs nothing from koto: the agent runs the lookup script with its Bash tool, and both
streams come back in the same tool result.

*Alternative: a `::koto-finding::` line on a gate.* koto shows findings in a blocking
condition, which is the right channel for a violation and the wrong one here: the takeover case
isn't a violation, and the lookup runs as an agent command, not a gate. Rejected.

*Alternative: print on standard output.* The agent sees it either way, but standard output is
the script's result channel, which its tests pin case by case, and D7 forbids changing it.
Standard error already carries the script's human-readable lines. Rejected.

*Alternative: cascade recovery as the trigger.* `run-cascade.sh`'s `partial` verdict also
reaches a rarely used rule, but it runs as a gate-adjacent script whose JSON output is parsed
whole. The takeover branch already writes free text on standard error. Deferred to later work,
which reuses the helper.

### Decision 8: How CI knows every id a script can print

**Chosen: each emitting script declares its ids, and its finding helper refuses any other.**
Each gate script gets one line, `RULE_IDS="..."`, listing every id it can print, and the
script's finding function exits with the script's could-not-decide code (2) when asked for an id
outside that list, or for one the registry marks retired or lacks. The check reads every
`RULE_IDS=` line under `skills/` and `scripts/`, and every `rule-registry.sh release <id>` call,
and requires each id to be an active registry entry. A gate test also collects every finding
its suite prints and checks each `rule_id` and `rule_ref`.

*Alternative: grep the scripts for id-shaped strings.* No declaration needed, and `<area>/<rule>`
matches paths like `skills/work-on` as easily as rules. Rejected as unreliable.

*Alternative: rely on the test suites' output alone.* Precise for what the tests reach, and
blind to a branch no test exercises. Kept as a second check, not the only one.

### Decision 9: Baseline keys

**Chosen: each entry's `baseline_keys` lists the location of its text at the baseline's
pinned commit, found by resolving the same anchors in `git show 2a3719ed:<path>`, or is empty
when they don't resolve there.** The check reads the pinned commit from
`docs/measurement/offload-baseline/template-pin.json` (read only), confirms each key's range
lies within its file at that commit, and that no key appears in two entries. Two entries whose
texts share a range at the pin (the three visibility rules point at one paragraph) list it once,
on the first, and the others carry an empty list with that noted in `notes`.

*Alternative: compute keys on demand instead of storing them.* Possible, since the anchors and
the commit are fixed, but the reader joining baseline records wants a lookup, not a git
operation. Rejected; stored keys never go stale because the pinned commit never changes.

### Decision 10: What happens to the gate table

**Chosen: `gate-rules.tsv` and `gate-rule-refs_test.sh` are removed, and the gate scripts read
the registry through the helper.** A second table would be a second home. The table's test
becomes the registry check's pointer test, which is stricter: it resolves anchors rather than
checking an excerpt sits inside a stored range.

*Alternative: keep the table as a generated view.* Nobody reads it but the scripts, which now
read the registry. Rejected.

## Decision Outcome

The registry is `references/rule-registry.json`: `{"schema": "shirabe-rule-registry/v1",
"rules": [...]}`, one object per rule, sorted by id. 40 entries ship: the 22 gate rules, the 17
review-shadow criteria and `execute/pr-takeover-needs-signal`. Ids follow
`^[a-z0-9-]+/[a-z0-9-]+$` or `^rs-[0-9]{3}$`.

`scripts/rule-registry.sh` is the one reader. Gate scripts and the trigger call it; the check
script and the tests use it too. It computes every `rule_ref` from anchors when a finding is
printed, naming the checkout's commit or the installed release's tag.

`scripts/check-rule-registry.sh` enforces every standing property and runs in a new workflow,
`.github/workflows/check-rule-registry.yml`, on every pull request that touches the registry,
the helper, the gate scripts, the criteria file or any file an entry's text lives in.

### The `rule_id` and `rule_ref` contract

Every `::koto-finding::` line a gate script prints carries:

- `rule_id`: an active registry id from the script's `RULE_IDS`;
- `rule_ref`: `<path>#L<first>-L<last>@<revision>`, computed at print time, where `<path>` is
  the entry's `text.path`, the range is the entry's first-to-last line in the running copy, and
  `<revision>` is the 12-character `HEAD` commit of a clean checkout, `worktree` for a checkout
  whose file has uncommitted changes, or `v<version>` for an installed copy;
- `message`: the entry's `summary`, then `: `, then the script's own detail.

`level`, `path` and `line` are unchanged. A reader joins on `rule_id`; `rule_ref` is for opening
the text, and a reader resolves it with `git show <revision>:<path>` and the line range.

A koto fallback finding (a failed gate that printed none) carries the gate's name as its
`rule_id`. Gate names aren't registry ids, so under the interim rule of
`DESIGN-output-gates.md` Decision 9 such a finding isn't a violation: "registered" means "has a
registry entry".

## Solution Architecture

### Registry entry

```json
{
  "id": "branch/no-wip-files",
  "status": "active",
  "summary": "The branch carries files under wip/",
  "text": {"path": "references/wip-hygiene.md",
           "first": "`wip/` is committed to feature branches",
           "last": "squash-merge keeps the cleanup out of the main branch trail"},
  "check": {"kind": "script", "path": "skills/work-on/scripts/check-branch-output.sh",
            "mode": "--wip"},
  "fixtures": ["skills/work-on/scripts/check-branch-output_test.sh"],
  "level": "gate",
  "timing": ["work-on:pr_precheck", "execute:pr_finalization"],
  "guards": ["pr-create", "publish"],
  "withhold": "never",
  "baseline_keys": ["references/wip-hygiene.md#L14-L16"],
  "aliases": [],
  "notes": ""
}
```

| Field | Required | Why it's there |
|---|---|---|
| `id` | yes | The join key; never changes (D2). |
| `status` | yes | Retiring instead of deleting keeps old records joinable. |
| `summary` | yes | The short text an agent sees on failure (Decision 5). |
| `text` | yes | The full-text pointer (Decision 4). |
| `check` | yes | What enforces it, or `none`. |
| `fixtures` | yes, may be empty | Tests that exercise the check, so a reader finds them from the rule. |
| `level`, `timing` | yes | How hard and when, for later work deciding where to deliver a rule. |
| `guards`, `withhold` | yes | The withhold safety (Decision 6). |
| `baseline_keys` | yes, may be empty | The join to baseline records (Decision 9). |
| `aliases` | yes, may be empty | Codes the rule is also known by (`PB3`, `R7`); never a `rule_id`, unique across the registry. |
| `notes` | yes, may be empty | Free text for anything a reviewer needs, such as why a key list is empty. |

`notes` and `aliases` are the two fields the PRD didn't ask for. `notes` keeps explanations out
of field values; `aliases` lets a reader who has a validator code find the gate rule that wraps
it without making codes into ids.

### Components

| Component | New or changed | Role |
|---|---|---|
| `references/rule-registry.json` | new | The registry. |
| `references/rule-registry.md` | new | Field reference, vocabularies, how to add or retire a rule, the routing-gate rule. Not loaded by any skill. |
| `scripts/rule-registry.sh` | new | `ref <id>`, `summary <id>`, `text <id>`, `release <id>`; `--registry <file>` and `--root <dir>` for tests. Exit 0 found, 1 unknown or retired id, 2 unreadable registry or unresolvable text. |
| `scripts/check-rule-registry.sh` | new | The standing checks below; `--base <ref>` adds the id-removal check. Exit 0 clean, 1 problems listed, 2 could not run. |
| `scripts/check-rule-registry_test.sh` | new | Shows each check failing on an altered copy, and passing on the real registry. |
| `scripts/rule-registry_test.sh` | new | `ref` from a checkout, a dirty checkout and an installed-style copy; anchor movement; retired and unknown ids; `release` output and its failure line. |
| `check-branch-output.sh`, `check-pr-output.sh`, `check-verification.sh`, `panel-scope.sh` | changed | `RULE_IDS=`, finding helper reads ref and summary through `rule-registry.sh`, refusing other ids. |
| `skills/work-on/scripts/gate-rules.tsv`, `gate-rule-refs_test.sh` | removed | Replaced by the registry and its check. |
| `skills/execute/scripts/adopt-or-create-pr.sh` | changed | Calls `rule-registry.sh release execute/pr-takeover-needs-signal` in its exit-6 branch, after its existing line. |
| `adopt-or-create-pr_test.sh` | changed | Asserts the released text, unchanged stdout and exit codes, no text on other exits, and the failure line. |
| `.github/workflows/check-rule-registry.yml` | new | Runs both suites and the check on Linux, and the suites on the macOS bash floor. |
| `.github/workflows/check-work-on-scripts.yml`, `check-execute-scripts.yml` | changed | Path filters gain the registry and helper; the removed test leaves the work-on suite list. |
| `scripts/check-bash-floor.sh` | changed | A `rule-registry` suite. |
| `DESIGN-output-gates.md` | changed | Decision 9 and the rule-id section name the registry as the set of registered rules. |

### The checks

`check-rule-registry.sh` reads the registry and the repository at `HEAD` and reports every
problem it finds, one line each:

1. **Shape.** The file parses; every entry has every field; values come from Decision 6's
   vocabularies; `id` matches a pattern; no duplicate ids or aliases; no alias equals an id;
   `none` stands alone in `guards`; `timing` is non-empty and each `<skill>:<state>` names a
   `## <state>` section of that skill's template.
2. **Withhold safety.** Any guard other than `none` requires `withhold: never`.
3. **References.** Each `check.path` and each fixture exists at `HEAD`; each `review-shadow`
   criterion exists in `criteria.json`.
4. **Pointers.** For each active entry, `text.path` exists, `first` occurs on exactly one line,
   and `last` (when given) occurs on a line at or after it.
5. **Review-shadow agreement.** The `rs-` ids of the registry and `criteria.json` are the same
   set, and each such entry's `text.path` equals the criterion's `rule_ref`.
6. **Printable ids.** Every id in a `RULE_IDS=` line under `skills/` and `scripts/`, and every
   literal id passed to `rule-registry.sh release`, is an active entry.
7. **Baseline keys.** Each key matches `<path>#L<a>-L<b>` with `a <= b`, its file exists at the
   pinned commit with at least `b` lines, and no key appears twice.
8. **Routing-gate rule.** `DESIGN-output-gates.md` names `references/rule-registry.json` in its
   Decision 9 and no longer says "rule tables".
9. **Id removal (`--base <ref>`).** Every id in the registry at `<ref>` is in the registry at
   `HEAD`. When the base has no registry, the check passes; CI passes the pull request's merge
   base.

The two *(this change)* criteria in the PRD (old ids all present; review-shadow files, manifest
files and `/execute`'s template not shortened) are checked by
`scripts/check-rule-registry.sh --adoption <base>`, which the new workflow runs on this pull
request only, gated on the base still containing `gate-rules.tsv`; once the table is gone from
`main` the step has nothing to compare and skips with a notice.

### Data flow at a gate

```text
check-branch-output.sh --wip
  finding branch/no-wip-files "wip/notes.md"
    -> is it in RULE_IDS?                         no -> exit 2
    -> rule-registry.sh summary branch/no-wip-files
    -> rule-registry.sh ref branch/no-wip-files   unknown/retired/unresolvable -> exit 2
         read entry, find first/last in $PLUGIN_ROOT/references/wip-hygiene.md
         revision: git HEAD (clean) | worktree | v<version>
  ::koto-finding::{"rule_id":"branch/no-wip-files","level":"error",
                   "message":"The branch carries files under wip/: wip/notes.md",
                   "rule_ref":"references/wip-hygiene.md#L14-L16@v0.25.0"}
```

A gate script calls the helper once per finding, not once per run, so a run with no violation
pays nothing; a violation costs one `jq` read and one `git` call, well inside koto's 30-second
command limit.

## Implementation Approach

One pull request, built in this order so each step's tests can run:

1. **Registry and helper.** Write `references/rule-registry.json` with all 40 entries, anchors
   resolved and baseline keys computed from the pinned commit; write `rule-registry.sh` and its
   tests; write `references/rule-registry.md`.
2. **Check script.** `check-rule-registry.sh` with every check and its failing-case tests, and
   the adoption mode.
3. **Gate scripts.** Move the four scripts to `RULE_IDS` and the helper; update their tests'
   expected `rule_ref` and message forms; remove `gate-rules.tsv` and its test.
4. **Trigger.** The exit-6 release in `adopt-or-create-pr.sh` and its test cases.
5. **CI and docs.** The new workflow, path filters, the floor suite, and Decision 9 in
   `DESIGN-output-gates.md`.

## Security Considerations

**The registry is read, never executed.** Every value reaches `jq` as data or as `--arg`, and
anchors are compared as fixed strings (`grep -F`, or `index()` in `jq`), so a rule text holding
regex or shell metacharacters can't change what runs. `text.path` is joined to the plugin root
only after the check confirms it's a relative path with no `..` component, and the helper
refuses one that isn't, so an entry can't make a gate read outside the plugin.

**Released text is quoted, not interpreted.** `release` prints file lines between markers. The
agent reads them as a rule, which is their purpose; they come from the plugin's own files, the
same text the template already put in its context, so no new source of instructions is added.

**No private content.** The registry names repository paths, public ids and public rule text
only. The guard vocabulary and checks carry no list of private terms.

**Failure can't loosen a gate.** A gate whose rule can't be resolved exits 2, which holds the
state, rather than printing a finding with no reference or passing. A failed release changes
nothing about its caller's result.

## Consequences

**Positive.** Every id a gate or criterion uses is defined once, with its text, check and tests.
A `rule_ref` from a real run opens the right lines at a tag on `main`, after any edit, with no
re-pin. A rule can't be marked withholdable while it guards a push, merge or publish, and the
first deliver-on-trigger path is in place for later work to reuse.

**Negative.** Finding messages gain a prefix, which changes what agents and logs see. An edit
that rewrites a rule's first or last line must update the anchor in the same pull request, or
the pointer check fails. Findings from a development checkout carry a branch commit or
`worktree`, which can't be opened after a squash merge. The review-shadow criteria live in two
files until the trial settles.

**Mitigations.** The detail after the prefix is unchanged, so existing matching keeps working.
The pointer check's message names the entry and the anchor that stopped matching, so the fix
is one line. Real runs use installed releases, whose tag is on `main`. The agreement check
keeps the two criteria files from drifting.
