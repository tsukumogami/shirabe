---
schema: design/v1
status: Planned
problem: |
  shirabe's gate scripts read their rules from a tab-separated table beside the scripts, the
  review-shadow trial reads its criteria from its own JSON file, and the rule text both point
  at lives in prose. A gate finding's rule_ref is a stored line range at a stored commit, so it
  goes stale on the next edit above the rule, and three of the four commits the table pins were
  squashed off main. Nothing records a rule's check, fixtures, enforcement, timing or whether
  it may ever be withheld, and no script can hand an agent a rule's text when the rule applies.
decision: |
  One JSON registry, references/rule-registry.json, holds an entry per rule: the 21 gate rule
  names and rs-001 to rs-017 under their existing ids, plus the takeover rule. Each entry finds
  its full text by two literal anchors (a substring of the first and of the last line), so
  scripts/rule-registry.sh computes rule_ref when a finding is printed, as
  <path>#L<a>-L<b>@<revision>, where the revision is the checkout's commit or, in an installed
  copy, the release tag (or the version and the file's blob hash for a development build). The
  gate scripts declare the ids they can print and read refs and
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

Planned

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

- in a git checkout, the 12-character commit of `HEAD` when the file's content equals its blob
  at `HEAD` (compared as `git hash-object --no-filters <file>` against
  `git rev-parse HEAD:<path>`, so no diff driver or filter runs); otherwise the literal
  `worktree`, so a dirty development copy never claims a commit whose lines differ;
- in an installed copy (no `.git` at the plugin root) whose `.claude-plugin/plugin.json`
  version is a plain `X.Y.Z`, `vX.Y.Z`, the release tag. Every release tag points at the
  release commit on `main`, so `git rev-parse vX.Y.Z^{commit}` in a clone of `main` turns it
  into a commit, and a reader can join a tagged reference to a commit-pinned one;
- in an installed copy with any other version, such as the `X.Y.Z-dev` that `main` carries
  between releases (the marketplace installs from the repository root, so a copy can come from
  `main` rather than a release), `<version>+<12-character git blob hash of the file>`. No tag
  names that tree, but the blob does: `git hash-object` needs no repository, and a reader finds
  the commits holding that exact text with `git log --all --find-object=<blob>`. When `git`
  itself is missing, the revision is `<version>` alone.

The revision is a pointer for a person to open, not an integrity claim: nothing signs it, and a
modified installed copy still prints its version.

The plugin root counts as a checkout only when `git rev-parse --show-toplevel` run there returns
the plugin root itself, so a copy that happens to sit inside some other repository isn't
mistaken for one. Every `git` call runs as `git -C <plugin root>` with repository hooks and
the filesystem monitor disabled and the system and global configuration ignored, and its output
must match the shape expected (`^[0-9a-f]{12}$` for a commit); any failure or mismatch falls
through to the installed-copy forms (Security Considerations).

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
For a one-line rule `last` is omitted. Anchors are plain substrings, matched as bytes with `awk`'s
`index()` under `LC_ALL=C` (not `jq`, whose string functions count code points), so they need no
escaping and survive any edit that doesn't touch the rule's own first or last line.

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
the finding's `message`, followed by `: ` and their existing detail.** The detail keeps its
current text, so the agent still reads what failed; the summary puts the rule's name in words
in front of it, the same words for every finding of that rule. Several details are already
sentences (the commit walk's, the validator's), so a message can read as two clauses saying
related things, for example `Pull request title isn't a Conventional Commits title: PR title
"update" is missing a type`. That redundancy is accepted for one stable prefix per rule. Tests
that compare a whole message change with the prefix; tests that match a substring of the
detail don't. The whole message passes through `jq --arg`, and control characters in the detail
(a commit subject or file name can carry them) are replaced before printing, so a finding is
always one line.

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
| `withhold` | `never`, `eligible` | Required, with no default. `never` is forced by any guard other than `none`, and by `check.kind: none`: a rule nothing checks can't be withheld on trust. |
| `check.kind` | `script`, `review-shadow`, `none` | `script` names `path` (and optionally `mode`); `review-shadow` names `criterion`; `none` names nothing. |

Two more pairings are enforced: `level: gate` requires a guard other than `none` (a gate that
guards nothing would be a routing gate, which prints no findings and has no entry), and
`level: prose` requires `check.kind: none`.

**How guards were classified.** A gate rule guards the action its gate stands in front of: the
commit and pull-request rules guard `pr-create` and `push` (the commit walk runs before the pull
request opens and before `/execute` pushes its settled branch), the branch and docs rules guard
`pr-create` and `publish`, the verification rules guard `pr-create`, the panel rule guards
`pr-create` and `merge`, and `branch/current-with-main` guards `push` and `merge`. All 21 are
therefore `never`. Of the criteria, `rs-001` (attribution), `rs-002` (private names) and `rs-003`
(scratch paths) guard `publish`: their violation is public the moment a commit or body is
pushed, and a later fix doesn't take it back. `rs-004` to `rs-017` judge quality a later commit
can fix before merge, guard `none`, and are `eligible`. The takeover rule is `level: prose`,
`check.kind: none`, `timing: ["execute:orchestrator_setup"]`, guards `push` and `publish`
(taking over rewrites another run's pull request), and is `never` on both counts.

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
trigger can never change its caller's result, and the template's prose stays the authority.
The template keeps its prose; this is a copy.

`release` prints only from files an agent already loads in normal runs (a path under
`skills/*/koto-templates/`, `skills/*/references/`, `skills/*/SKILL.md` or `references/`), at
most 60 lines, and the check rejects an entry whose range holds a marker line or a control
character, so released text can't end its own block early or add instructions from a file no
skill reads.

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
outside that list, or for one the registry marks retired or lacks. Each mode still resolves
every id it can report before it checks anything, as `require_rules` does today, so a broken
anchor holds the gate at once rather than at the first violation, and the resolved refs and
summaries are kept for the run. The check reads every `RULE_IDS=` line under `skills/` and
`scripts/` with `grep` (it never sources a script; each script has exactly one such line, at
the start of a line, in the form `RULE_IDS="<id> <id> ..."` on one line, and the check fails on
any other shape), and every literal id passed to
`rule-registry.sh release`, and requires each id to be an active registry entry.

The second half is a finding log. When `SHIRABE_FINDINGS_LOG` names a file, each gate script's
finding helper appends the line it printed there. Because an agent can also run a gate script
from its own shell, where the environment isn't cleared, the log is honored only when its path
lies under `${TMPDIR:-/tmp}`, is not a symlink, and either doesn't exist or is a regular file;
anything else is ignored. The four gate scripts' test suites set it, and at the end each
suite runs `rule-registry.sh verify-findings <log>`, which fails unless every logged
`rule_id` is an active entry and every `rule_ref` names that entry's path and the same range
`ref` computes for it.

*Alternative: grep the scripts for id-shaped strings.* No declaration needed, and `<area>/<rule>`
matches paths like `skills/work-on` as easily as rules. Rejected as unreliable.

*Alternative: rely on the test suites' output alone.* Precise for what the tests reach, and
blind to a branch no test exercises. Kept as a second check, not the only one.

### Decision 9: Baseline keys

**Chosen: each entry's `baseline_keys` lists the location of its text at the baseline's
pinned commit, found by resolving the same anchors in `git show 2a3719ed:<path>`, or is empty
when they don't resolve there.** The check reads the pinned commit from
`docs/measurement/offload-baseline/template-pin.json` (read only, and refused unless it is 40
hex characters) and confirms each key's range lies within its file at that commit. A key may
appear on several entries when their texts shared a range at the pin (the three visibility
rules point at one paragraph, as do the two attribution rules); each entry that shares a key
must say so in `notes`, naming the others. An empty list must also be explained in `notes`
(the text didn't exist at the pin, or was reworded there so the anchor doesn't match), so a
rule that existed at the pin is never dropped from the join silently.

*Alternative: compute keys on demand instead of storing them.* Possible, since the anchors and
the commit are fixed, but the reader joining baseline records wants a lookup, not a git
operation. Rejected; stored keys never go stale because the pinned commit never changes.

### Decision 10: What happens to the gate table

**Chosen: `gate-rules.tsv` and `gate-rule-refs_test.sh` are removed, and the gate scripts read
the registry through the helper.** A second table would be a second home. The table's test
becomes the registry check's pointer test, which is stricter: it resolves anchors rather than
checking an excerpt sits inside a stored range. Every mention of the table goes with it: the
four gate scripts' header comments, `check-pr-output_test.sh`, the workflow that lists the
removed test, and `DESIGN-output-gates.md` wherever it names the table (Decision 5, Decision 9,
its implementation steps and its mitigations), which now names the registry.

*Alternative: keep the table as a generated view.* Nobody reads it but the scripts, which now
read the registry. Rejected.

## Decision Outcome

The registry is `references/rule-registry.json`: `{"schema": "shirabe-rule-registry/v1",
"rules": [...]}`, one object per rule, sorted by id. 39 entries ship: the 21 gate rules, the 17
review-shadow criteria and `execute/pr-takeover-needs-signal`. Ids follow
`^[a-z0-9-]+/[a-z0-9-]+$` or `^rs-[0-9]{3}$`.

`scripts/rule-registry.sh` is the one reader. Gate scripts and the trigger call it; the check
script and the tests use it too. It computes every `rule_ref` from anchors when a finding is
printed, naming the checkout's commit, the installed release's tag, or an installed
development copy's version and blob.

`scripts/check-rule-registry.sh` enforces every standing property and runs in a new workflow,
`.github/workflows/check-rule-registry.yml`, triggered by `pull_request` with read-only
permissions. Its path filter is deliberately broad (`references/**`, `skills/**`, `scripts/**`,
`docs/guides/**`, `docs/designs/current/DESIGN-output-gates.md`, `CLAUDE.md`,
`.claude-plugin/plugin.json` and the workflow itself), and one of the checks reads that filter
from the workflow file and fails when an entry's `text.path` matches none of its globs, so a
rule can't live where an edit to it wouldn't run the check.

### The `rule_id` and `rule_ref` contract

Every `::koto-finding::` line a gate script prints carries:

- `rule_id`: an active registry id from the script's `RULE_IDS`;
- `rule_ref`: `<path>#L<first>-L<last>@<revision>`, computed at print time, where `<path>` is
  the entry's `text.path`, the range is the entry's first-to-last line in the running copy, and
  `<revision>` is one of: the 12-character `HEAD` commit of a checkout whose file matches
  `HEAD`; `worktree` for a checkout whose file doesn't; `vX.Y.Z` for an installed release;
  `<version>+<12-character blob hash>` for any other installed copy (`<version>` alone when
  `git` is missing); or `unknown` when `plugin.json`'s version doesn't have the expected shape;
- `message`: the entry's `summary`, then `: `, then the script's own detail with control
  characters replaced.

`level`, `path` and `line` are unchanged. A reader joins on `rule_id`; `rule_ref` is for opening
the text: `git show <revision>:<path>` and the line range for a commit or tag, and
`git log --all --find-object=<blob>` for the blob form.

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
| `notes` | yes; empty only when `baseline_keys` is non-empty and shares no key | Why a key list is empty, which entries share a key, and anything else a reviewer needs. |

`notes` and `aliases` are the two fields the PRD didn't ask for. `notes` keeps explanations out
of field values; `aliases` lets a reader who has a validator code find the gate rule that wraps
it without making codes into ids.

### Components

| Component | New or changed | Role |
|---|---|---|
| `references/rule-registry.json` | new | The registry. |
| `references/rule-registry.md` | new | Field reference, vocabularies, how to add or retire a rule, the routing-gate rule. Not loaded by any skill. |
| `scripts/rule-registry.sh` | new | `ref <id>`, `summary <id>`, `text <id>`, `release <id>`, `verify-findings <log>`. Finds the plugin root from its own location, never from the working directory (gate scripts run from the repository being gated). `--registry <file>` and `--root <dir>` exist for tests; no gate script passes them. Exit 0 found, 1 unknown or retired id, 2 unreadable registry, unsafe path or unresolvable text. |
| `scripts/check-rule-registry.sh` | new | The standing checks below; `--base <ref>` adds the id-removal check. Exit 0 clean, 1 problems listed, 2 could not run. |
| `scripts/check-rule-registry-adoption.sh` | new | The one-time *(this change)* comparison against the merge base, kept apart so the standing check stays standing. |
| `scripts/check-rule-registry_test.sh` | new | Shows each check failing on an altered copy, and passing on the real registry; pins the real registry's shape (exactly 21 `level: gate` entries, 17 `rs-` entries, 39 in all) and its never-withhold entries (the 21 gate rules, `rs-001` to `rs-003`, the takeover rule); runs the adoption script against a scratch repository with a base that has the table and one that doesn't. |
| `scripts/rule-registry_test.sh` | new | `ref` from a clean scratch repository, a dirty one, an installed-style copy with a release version and one with a `-dev` version, and one with no `git`; anchor movement after lines are inserted above; retired, unknown and unsafe-path entries; `release` output, its line cap, its path restriction and its failure line; `verify-findings`. |
| `check-branch-output.sh`, `check-pr-output.sh`, `check-verification.sh`, `panel-scope.sh` | changed | `RULE_IDS=`; each mode resolves its ids up front and keeps the refs and summaries; the finding helper builds the line with `jq --arg`, refuses other ids, and appends to `SHIRABE_FINDINGS_LOG` when set. |
| the four gate scripts' `_test.sh` suites | changed | Expected `rule_ref` and message forms; each sets `SHIRABE_FINDINGS_LOG` and ends with `rule-registry.sh verify-findings`, plus one case per suite asserting a literal expected range for one rule (independent of the resolver), and cases showing an id outside `RULE_IDS` and a retired id each exit 2. `panel-scope.sh --verdict` now requires the ref (today it omits `rule_ref` when the lookup fails); an unresolvable rule exits 2 like the other scripts. |
| `skills/work-on/scripts/gate-rules.tsv`, `gate-rule-refs_test.sh` | removed | Replaced by the registry and its check. |
| `skills/execute/scripts/adopt-or-create-pr.sh` | changed | Calls `rule-registry.sh release execute/pr-takeover-needs-signal </dev/null >&2 || true` in its exit-6 branch, after its existing line. |
| `adopt-or-create-pr_test.sh` | changed | Asserts the released text, unchanged stdout and exit codes, no text on other exits, and the failure line. |
| `.github/workflows/check-rule-registry.yml` | new | `pull_request`, read-only, full history (`fetch-depth: 0`, for the pinned commit and the merge base). Runs both suites, the check with `--base`, and the adoption script on Linux, and the suites on the macOS bash floor. |
| `.github/workflows/check-work-on-scripts.yml`, `check-execute-scripts.yml` | changed | Path filters gain the registry and helper; the removed test leaves the work-on suite list. |
| `scripts/check-bash-floor.sh` | changed | A `rule-registry` suite running both new test files. |
| `DESIGN-output-gates.md` | changed | Every mention of `gate-rules.tsv` names the registry instead, and Decision 9 defines a registered rule as one with a registry entry. |

### The checks

`check-rule-registry.sh` reads the registry and the repository at `HEAD` and reports every
problem it finds, one line each:

1. **Shape.** The file parses; every entry has every field; values come from Decision 6's
   vocabularies; `id` matches a pattern; no duplicate ids or aliases; no alias equals an id;
   `none` stands alone in `guards`; `timing` is non-empty and each `<skill>:<state>` names a
   `## <state>` section of that skill's template; `summary` is one line with no control
   character and no `::` marker.
2. **Withhold safety.** Any guard other than `none`, and `check.kind: none`, require
   `withhold: never`; `level: gate` requires a guard other than `none`; `level: prose` requires
   `check.kind: none`.
3. **Paths and references.** Every path (`text.path`, `check.path`, each fixture) matches
   `^[A-Za-z0-9._][A-Za-z0-9._/-]*$`, has no `..` segment, is not a symlink and resolves inside
   the repository; each `check.path` and fixture exists; each `review-shadow` criterion exists
   in `criteria.json`.
4. **Pointers.** For each active entry, `text.path` exists, `first` occurs on exactly one line,
   `last` (when given) occurs on a line at or after it, and the range holds no marker line and
   no control character other than a tab.
5. **Review-shadow agreement.** The `rs-` ids of the registry and `criteria.json` are the same
   set, and each such entry's `text.path` equals the criterion's `rule_ref`.
6. **Printable ids.** Every id in a `RULE_IDS=` line under `skills/` and `scripts/`, and every
   literal id passed to `rule-registry.sh release`, is an active entry.
7. **Baseline keys.** The pinned commit read from `template-pin.json` is 40 hex characters; each
   key matches `<path>#L<a>-L<b>` with `a <= b`, and its file exists at the pinned commit with at
   least `b` lines; an entry sharing a key with another names the other in `notes`; an empty
   list has a non-empty `notes`.
8. **Routing-gate rule.** `DESIGN-output-gates.md` names `references/rule-registry.json` in its
   Decision 9, `references/rule-registry.md` defines a registered rule as an id with a registry
   entry, and no file under `skills/`, `scripts/`, `references/` or `docs/guides/`, nor
   `CLAUDE.md` or `DESIGN-output-gates.md`, names `gate-rules.tsv`.
9. **Path filter.** Every active entry's `text.path` matches a glob in the `pull_request`
   `paths:` list of `check-rule-registry.yml`. The filter uses only literal paths and a
   trailing `/**`, so the check matches each glob as a literal path or a directory prefix rather
   than reimplementing GitHub's glob syntax.
10. **Releasable ids.** Every id passed to `rule-registry.sh release` has a `text.path` under
    one of the releasable directories and a range of at most 60 lines, so a release that would
    be refused at runtime fails CI first.
11. **Id removal (`--base <ref>`).** Every id in the registry at `<ref>` is in the registry at
    `HEAD`. When the base has no registry, the check passes; CI passes the pull request's merge
    base.

The two *(this change)* criteria in the PRD (every old id present; review-shadow files
unchanged; no line removed from manifest files or `/execute`'s template) are checked by
`scripts/check-rule-registry-adoption.sh <base>`, which the new workflow runs only while the
merge base still contains `gate-rules.tsv`; once the table is gone from `main` it has nothing
to compare and prints that it skipped.

### Data flow at a gate

```text
check-branch-output.sh --wip
  require_rules branch/no-wip-files               (every id this mode can report)
    -> in RULE_IDS?                                no -> exit 2
    -> rule-registry.sh ref / summary              unknown/retired/unsafe/unresolvable -> exit 2
         plugin root from the helper's own path; first/last found in references/wip-hygiene.md
         revision: HEAD commit (file matches HEAD) | worktree | vX.Y.Z | <version>+<blob>
    -> kept for this run
  ... the check runs ...
  finding branch/no-wip-files "<path under wip/>"
  ::koto-finding::{"rule_id":"branch/no-wip-files","level":"error",
                   "message":"The branch carries files under wip/: <path under wip/>",
                   "rule_ref":"references/wip-hygiene.md#L14-L16@v0.25.0"}
```

Resolving costs one `jq` read, one `awk` pass and at most three `git` calls per id, once per
run, well inside koto's 30-second command limit.

## Implementation Approach

One pull request, built in this order so each step's tests can run:

1. **Registry and helper.** Write `references/rule-registry.json` with all 39 entries, anchors
   resolved and baseline keys computed from the pinned commit; write `rule-registry.sh` and its
   tests; write `references/rule-registry.md`; register the `rule-registry` floor suite.
2. **Gate scripts.** Move the four scripts to `RULE_IDS` and the helper; update their tests'
   expected `rule_ref` and message forms and add the findings log; remove `gate-rules.tsv`, its
   test and every mention of it.
3. **Trigger.** The exit-6 release in `adopt-or-create-pr.sh` and its test cases.
4. **Check script and CI.** `check-rule-registry.sh` with every check and its failing-case
   tests, the adoption script, the new workflow, the path filters, and `DESIGN-output-gates.md`.
   It comes last because its fixture, timing and printable-id checks read what steps 2 and 3
   changed.

## Security Considerations

**Trust boundary.** The helper reads files inside the plugin root, the same directory the gate
scripts themselves are loaded from. Whoever can write there can already change what a gate
does, so the helper doesn't defend the plugin against its own files. It does make sure that
reading the registry can't widen what a modified or malformed entry reaches, and that `git`
config planted in the directory runs nothing.

**`git` runs with repository config disabled.** Every call is
`git -C <plugin root> -c core.fsmonitor=false -c core.hooksPath=/dev/null` with
`GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null`, with `GIT_DIR`, `GIT_WORK_TREE`,
`GIT_INDEX_FILE` and `GIT_CEILING_DIRECTORIES` unset so the caller's environment can't point it
at another repository, and only plumbing that runs no diff
driver or filter is used (`rev-parse`, `hash-object --no-filters`). Output is validated
(`^[0-9a-f]{12}$` for a commit, `^[0-9a-f]{40}$` for a blob). A refusal, such as git's
dubious-ownership check now that the user's `safe.directory` is ignored, or any other failure,
falls through to the installed-copy forms, which read only `plugin.json`, whose version must
match `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` or the revision is `unknown`.

**The registry is read, never executed.** Every value reaches `jq` as data or as `--arg`, and
anchors are compared as fixed strings with `awk`'s `index()`, so a rule text holding regex or
shell metacharacters can't change what runs. Every path in an entry must match
`^[A-Za-z0-9._][A-Za-z0-9._/-]*$` (so no absolute path and no leading `-`), contain no `..`
segment, and resolve, with symlinks followed by `cd -P`, to a location under the plugin root
that is not itself a symlink; the helper refuses anything else with exit 2, and the check
refuses it in CI. Paths reach commands after `--`.

**Lines stay lines.** Finding lines are built by `jq -cn --arg`, which escapes quotes and
newlines; control characters in a script's detail are replaced before that. The check rejects
a `summary` or a released range containing a control character or a `::` marker, so released
text can't close its own block or forge a finding line.

**Released text is quoted, not interpreted.** `release` prints at most 60 lines, only from files
under `skills/*/koto-templates/`, `skills/*/references/`, `skills/*/SKILL.md` or `references/`,
and refuses at runtime, as the check does in CI, a range holding a marker line or a control
character other than a tab. The agent reads the text as a rule, which is its purpose. The
directory allowlist bounds where text can come from to the plugin's own skill prose; for the
takeover rule it's the template the agent is already running, though a later trigger could
release a reference its skill hadn't loaded yet, which is the point of delivering on trigger.

**Ids are checked before use.** The helper refuses an id that doesn't match the two id patterns
before it reaches `jq` or any path.

**CI runs with read-only permissions.** The new workflow uses `pull_request`, never
`pull_request_target`, with `contents: read`, and reads scripts' `RULE_IDS=` lines with `grep`,
never by sourcing them.

**No private content.** The registry names repository paths, public ids and public rule text
only. The guard vocabulary and checks carry no list of private terms.

**Failure can't loosen a gate.** A gate whose rule can't be resolved exits 2, which holds the
state, rather than printing a finding with no reference or passing. In a development checkout
with a broken anchor that holds every gate run until the anchor is fixed, which is the intended
pressure. A failed release changes nothing about its caller's result, and its distinctive
`rule-registry: could not release` line says the copy was skipped; the template's prose is
still in the agent's context.

**Residual risk.** A modified installed copy can print any revision it likes, since the
revision is a pointer, not a signature. Nothing here needs a maintainer's sign-off beyond this
review: the helper runs `git` only on the plugin's own directory, with its config disabled.

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
