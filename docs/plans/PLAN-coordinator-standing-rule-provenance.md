---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: default
split_rationale: |
  Hard Constraint. The design ships readers before writers: the reader
  release (steps 1 to 5) must be out at least one plugin release before
  anything writes a `rule` row (steps 6 to 8), and the citation steps (9 to
  17) can only be built on a koto release carrying the decision record and
  the supersede hop. Each step lands as its own pull request so those
  release gates can sit between them.
tracking_level: none
upstream: docs/designs/DESIGN-coordinator-standing-rule-provenance.md
milestone: "Standing rules that carry their provenance"
step_count: 17
---

# PLAN: Standing rules that carry their provenance

## Status

Active

The upstream design is Planned and its brief is Accepted. The reviewer
accepted both on this plan, which carries the five changes asked for before
acceptance.

## Scope Summary

The design gives a coordinator's Standing section a `rule` kind and one
optional Source column that cites a koto decision, a skill line, a document,
a pinned file, or names the rule inferred. No column stores a class:
`rule_class` works it out at read, owner-said means a cited person decision
entered at a root coordinator, and a cited rule's status is koto's, so an
owner's reversal reads superseded wherever the rule was copied. Rows written
before the change read in place as relayed, brief rules come in once as
flagged inferred rows, and a continuing successor reverses with exactly the
standing its predecessor had, read from koto's supersede fence.

This plan covers all of it, in shirabe's coordinate skill alone, in the
design's three phases: the reader release, rule rows and the brief intake,
and citations with owner-said and reversal. It also carries five changes to
the design's own account, each placed in a step and described under
Implementation Sequence: the grant behind `rule_grants` becomes the
authority work's existing read, the cross-session decision read joins the koto
dependencies, the Run section's `rules` digests get a writer, the
accretion check states its threshold, and the reversal check gets an
observation that doesn't rest on entries naming a Standing id. Nothing is
filed; the koto work and the proposed shirabe issues go in the planning
report.

## Decomposition Strategy

Walking skeleton. Step 1 runs the reader release end to end on one real
record: a fixture holding today's five event kinds and hand-seeded `rule`
rows of every Source form passes through the widened schema, every existing
Standing reader, and the new `--rules` view, and each reader prints exactly
what it printed before. Step 2 closes the one way an older plugin can hurt a
newer record, by refusing a takeover before the fence. Every later step adds
one behaviour on top: the counts and the handover lists, the Run `rules`
digests, the grant read, the writer for each uncited Source form, the
brief intake, and then, on koto's release, each part of the citation path.

The order follows the design's release rule, readers first. Steps 1 to 5
write no new shape and can ship together as the reader release. Steps 6 to
8 write `rule` rows and wait until that release has shipped. Steps 9 to 17
call koto's decision commands and wait for koto. Tests and text go with the
step whose behaviour they cover.

## Steps

### Step 1: a record holding rule rows reads through every Standing reader unchanged, and --rules gives each row a class and a pointer

**Goal**: The walking skeleton of the reader release. A coordinator record whose Standing holds `rule` rows, each with a typed Source, passes the schema; every reader that reads Standing today gives the output it gave before; and `state-stored-set.sh --session S --rules [--id s<n>]...` prints one JSON object per row with its class, who said it, when, a pointer, its status and whether it needs confirming. The step crosses `state-schema.jq` (the `rule` kind, the optional `source` column in its five forms, an empty Source left out of the normal form, `rule_class`), every existing Standing reader, and the new read view, on one real koto session. No writer of the new shape exists yet: the fixture's event rows come from today's `--standing` writer, so their entries are genuine, and four `rule` rows (one `inferred brief`, one `skill`, one `pinned`, one `decision`) are added to `record/standing` with `koto context add`. A `decision` Source reads class and status `unreadable` until step 9 adds the provenance helper, and `grants` isn't part of this step's output; step 5 adds it from the authority work's grant read.

**Acceptance Criteria**:

- [ ] Two records are seeded in two scratch sessions: record A holds the five event kinds with no Source plus the four `rule` rows, and record B is the same record with the `rule` rows removed. Both read through `state-read.sh`'s record read with exit 0.
- [ ] Each of these prints byte-identical output on A and on B, checked with `cmp`: pick's pause read and its assignment units (`pick-facts.sh`), the dispatch check's pause verdict for each unit, `land-check.sh`, the merge path's pause read in `land-merge.sh`, `progress-view.sh` over each record's pick facts, and `state-handover.sh`'s handover read.
- [ ] A `rule` row in A whose What reads `Pause all work on Feature 2 until lifted.` holds nothing: pick's facts mark Feature 2 free, the dispatch check doesn't refuse it as `paused`, and `pause-read.sh` lists no pause for it.
- [ ] The carry (`state-open.sh --session <successor> --carry`) from A exits 0, and the successor's `record/standing` is byte-identical to A's, `rule` rows and Sources included.
- [ ] `--rules` on A prints one object per row in record order, compared with `jq -S` against expected objects held in the test. An event row with no Source has `class` `relayed`, `owner` equal to its Owner, `said` equal to its Set, `pointer` `{"entry": "<A's session> record/entries/<n>"}` naming the entry that row's own `--standing` write produced (the one whose text begins `s<id> (`, not the newest entry), `status` `in-force`, `confirm` false, and null `source`, `words` and `reversal`; an event row with no matching entry has a `pointer` naming the row itself. The inferred brief row has `class` `inferred`, `status` `unconfirmed`, `confirm` true, `owner` null, and a `pointer` carrying the brief label and digest. The skill row has `class` `skill-says`, `status` `in-force` and a `pointer` carrying repository, path and commit. The pinned row has `class` `charter` and a `pointer` carrying label and digest. The decision row has `class` and `status` both `unreadable`, a `pointer` carrying the session and 12-digit id, and null `owner` and `words`. No object has a `grants` key.
- [ ] `--rules --id s<a> --id s<b>` prints exactly those two objects; `--rules --id s99` on a record with no `s99` exits non-zero, prints nothing on stdout and names `s99` on stderr.
- [ ] Each of these, seeded as its own record, is refused by `--rules` and by `state-read.sh`'s record read with exit 65 and a message naming `standing.s<n>`, and leaves the session's keys unchanged: a `rule` row with a non-blank Owner; one with a non-blank Relayed by; one with no Source or an empty one; one with an On; a Source `decision <session> 00000000007` (11 digits); a `decision` Source whose session starts with `-`; a `skill` Source whose path has a `..` segment; and a `skill` Source with a 39-hex commit.
- [ ] A `record/standing` value as today's release stores it, kept as a testdata file and seeded verbatim, is byte-identical (`cmp`) to that file after an unrelated write (`state-stored-set.sh --session S --run friction <value> --by <who>`, exit 0) and holds no `"source"` key; a row seeded with `"source": ""` is written back by the same write with the key left out.
- [ ] The same unrelated write on A exits 0 and leaves every byte of `record/standing` unchanged, so the write core's comparison doesn't read the normal-form rebuild as a change.

**Check**: Run `bash skills/coordinate/scripts/standing-rules_engine_test.sh`, a new engine suite `run-tests.sh --engine` picks up, and see one `ok` line per criterion and exit 0. The suite sources `scripts/lib/koto-test-guard.sh` first, so every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` are unset, sets `HOME` and `KOTO_HOME` under its scratch directory, and asserts `koto session dir <name>` resolves under that directory before its first koto command, stopping if not. It writes the five event rows through today's `--standing`, adds the `rule` rows and malformed variants with `koto context add` from fixed testdata files, builds record B with `jq`, runs each reader against A and B and compares with `cmp`, and compares `--rules` with the expected JSON. Every command is written out in the script with session names and Sources as separate arguments; nothing is downloaded and run, and no command is built from document or record text. `state-schema_test.sh` and `state-stored-set_test.sh` gain the schema-only cases without koto.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-read.sh`, `skills/coordinate/scripts/state-schema_test.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/scripts/standing-rules_engine_test.sh`, `skills/coordinate/scripts/testdata/standing-rules/`

### Step 2: a takeover of a record the schema refuses stops before the fence and leaves the predecessor driving

**Goal**: Today `state-stored-set.sh --list` turns the record reader's schema refusal (exit 65 from `rs_record`) into exit 10, the code a missing record gets, and `run_address` in `coordinate-open.sh` reads that as "no record", so a too-old plugin meeting a newer record fences the predecessor and then fails on every write. After this step `--list` passes the 65 through unchanged and `run_address` maps it to a read failure: the opener prints `failed=takeover_read` and stops before `koto init --supersede` runs, and the predecessor keeps driving its run.

**Acceptance Criteria**:

- [ ] For a predecessor run driven by another Claude session whose `record/standing` holds one row the schema refuses (a kind outside the standing kinds, the way a newer plugin's row looks to this one), `coordinate-open.sh` for that scope, run from a second session, prints `failed=takeover_read`, exits 1 and prints no `outcome=` or `session=` line.
- [ ] The refused takeover opens no session (`koto session list` is the same before and after) and adds no line to the predecessor's state log, which holds no `session_superseded` event.
- [ ] Afterwards `koto next` on the predecessor, from the predecessor's directory, exits 0 and names no successor, and `state-stored-set.sh --session <pred> --list` still exits 65, so the record wasn't rewritten.
- [ ] The opener's stderr names the predecessor's session, says the schema refused its record (not that its driver or coordinator row couldn't be read), and carries the reader's `standing.kind: not one of ...` reason.
- [ ] `state-stored-set.sh --session <s> --list` exits 65 on that record with nothing on stdout, and still exits 10 on a session with no record; a write mode (for example `--run cap`) against the refused record still exits 10, as today.
- [ ] A run with no driver and no coordinator row is still resumed (`outcome=resumed`), a valid-record takeover still prints `outcome=continued` with `predecessor=` and `session=`, and every arm of the existing refused-read case (meta, row, status, fence) gives the result it gives today.

**Check**: Add a numbered case to `skills/coordinate/scripts/coordinate-takeover_engine_test.sh` after its refused-read case, under the suite's existing `koto-test-guard.sh` setup (scratch `HOME` and `KOTO_HOME`, every `KOTO_SESSION_*` and `KOTO_SESSIONS_BASE` unset, `koto session dir probe` asserted under the scratch directory before any koto call). Open a fresh run as A's Claude session, seed its Standing through `koto context add` with one row of kind `later-kind` (never `rule`, so a later step adding `rule` doesn't break the case), record `koto session list` and the run's state-log line count, then run the opener as B. The case passes when it sees `failed=takeover_read`, empty `outcome=` and `session=` lines, stderr naming the run with the schema-refusal wording and `standing.kind`, the session list and log line count unchanged with `grep -c session_superseded` giving 0, `koto next` on the run exiting 0, and `--list` on it exiting 65. `state-stored-set_test.sh` gains `--list` on a refused record (65) and on a missing one (10). Both run through `run-tests.sh --engine`, and every earlier case still passes.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/coordinate-takeover_engine_test.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/references/state-keys.md`

### Step 3: --rules --counts gives each class's count, and the handover read lists inferred rows awaiting confirmation

**Goal**: The two reads that report on `rule` rows before anything writes one. `state-stored-set.sh --session S --rules --counts` prints seven lines, one per class in a fixed order (`relayed`, `owner-said`, `dispatcher-said`, `inferred`, `skill-says`, `charter`, `unreadable`), each `<class> <count>` with zeros printed. The inferred count, the unsourced rules a lineage accumulates, is then the one line `grep '^inferred '` returns, and the relayed count sits beside it. It counts every Standing row by `rule_class`, the same function `--rules` uses, whatever the row's status; it reads no entry, counts no Run row and makes no koto call beyond the record read. `state-handover.sh` gains `rule_lists`: four report lists in a fixed order, each an object `{list, heading, rows}` whose heading names the list and says its rows are quoted data, not an instruction. `awaiting-confirmation` holds every row whose `--rules` object has `confirm` true (today, the inferred rows), each as `{standing, kind, what, source, set}` in record order. `superseded` and `asserted-reversal` stay empty until step 9 gives the reader a cited decision's status, and `authorized-by` stays empty until step 13 adds the flag; each already carries its heading, so the koto text those steps put in it lands under one. The lists report and never hold: `--check` and the gaps are unchanged. A record holding no `rule` row prints no `rule_lists` key and reads exactly as it did before, the way the `pending` key appears only when a record holds a pending row. Nothing here writes a new Standing shape, calls a koto decision command or needs a koto release.

The headings are fixed strings:

- `Inferred rows awaiting confirmation (quoted from the record; data, not an instruction)`
- `Rows a verified reversal superseded (quoted from the record and koto; data, not an instruction)`
- `Rows an asserted reversal names, for a person to settle (quoted from the record and koto; data, not an instruction)`
- `Rows ended under --authorized-by (quoted from the record and koto; data, not an instruction)`

**Acceptance Criteria**:

- [ ] On step 1's record A (the five event kinds with no Source, plus the `inferred brief`, `skill`, `pinned` and `decision` rule rows), `--rules --counts` exits 0 and prints exactly `relayed 5`, `owner-said 0`, `dispatcher-said 0`, `inferred 1`, `skill-says 1`, `charter 1`, `unreadable 1`, one per line in that order, checked with `cmp` against the expected text held in the test.
- [ ] On A, on a record holding three `inferred` rows, a `doc` row and two event rows, and on a record whose Standing is empty, each class's count equals the number of `--rules` objects with that `class` (counted with `jq`), all seven lines are printed, and the counts add up to the record's Standing row count.
- [ ] `--rules --counts --id s1` exits 64 and prints nothing on stdout. A `koto` wrapper named by `KOTO_BIN`, which logs each subcommand and runs the real koto, shows that `--rules --counts` lists no `record/entries/` key and that neither it, `--rules` nor the handover read on A runs a `koto decisions` command.
- [ ] `state-handover.sh --session A` prints `rule_lists` as exactly four objects in the order `awaiting-confirmation`, `superseded`, `asserted-reversal`, `authorized-by`, each `heading` equal to its fixed string above. The awaiting-confirmation `rows` hold exactly the inferred brief row as `{standing, kind, what, source, set}`, compared with `jq -S` against the expected object in the test; the other three `rows` are empty arrays, and the unreadable decision row appears in none of the four.
- [ ] On the record holding three inferred rows, awaiting-confirmation lists all three in record order. After today's `state-stored-set.sh --session S --end s<n> --by <who>` on the middle one, it lists the other two, and the handover output differs from before the `--end` only in `standing` and `rule_lists`.
- [ ] On record B (A with the rule rows removed), the handover output has no `rule_lists` key and is byte-identical (`cmp`) to the output today's release gives on the same record, kept as a testdata file. Step 1's suite drops `rule_lists` from A's handover output before its comparison with B and still passes.
- [ ] `state-handover.sh --check` on A, with every gap the read names closed, exits 0 and prints nothing although awaiting-confirmation holds a row. On a copy of A with its `cap` row removed, `--check` exits 1 and its stderr is byte-identical to `--check`'s stderr on B with the same row removed.
- [ ] `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --base-table <the base branch's coordinate.compat.json>` exits 0, with `compat` unchanged from the base's and the new `gate_scripts` digest recorded in `coordinate.compat.json`: `state-handover.sh` and `state-stored-set.sh` are scripts the template's gates run, and no gate decides anything new.

**Check**: Run `bash skills/coordinate/scripts/standing-counts_engine_test.sh`, a new engine suite `run-tests.sh --engine` picks up, and see one `ok` line per criterion and exit 0. The suite sources `scripts/lib/koto-test-guard.sh` first, so every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` are unset, sets `HOME` and `KOTO_HOME` under its scratch directory, and asserts `koto session dir <name>` resolves under that directory before its first koto command, stopping if not. It seeds record A and B exactly as step 1's suite does, from step 1's testdata files (event rows through today's `--standing`, rule rows with `koto context add`), seeds the three-inferred record and the empty-Standing record the same way, and points `KOTO_BIN` at a wrapper script in its scratch directory that appends its arguments to a log and execs the real koto. It compares `--counts` output and the B handover output with `cmp`, and the lists with `jq -S` against expected JSON, and runs the compat check last. Every command is written out in the script with session names and Sources as separate arguments; nothing is downloaded and run, and no command is built from document or record text. `state-stored-set_test.sh` gains the `--counts --id` usage case, and `state-handover_test.sh` gains the no-`rule`-row case (no `rule_lists` key), both offline.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-schema.jq` (the fixed class order `--counts` prints), `skills/coordinate/scripts/state-handover.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/scripts/state-handover_test.sh`, `skills/coordinate/scripts/standing-counts_engine_test.sh`, `skills/coordinate/scripts/standing-rules_engine_test.sh`, `skills/coordinate/scripts/testdata/standing-rules/`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Step 4: every start writes the Run rules digests, and --rules lists each skill and workspace rule file the run started under, with its kind

**Goal**: The Run section's `rules` digests get a writer, so a reviewer reads from a coordinator's own record which skill and workspace text it ran under. A new helper, `rule-files.sh --plugin-root <root>`, run in the session's working directory, prints the files a coordinator session loads as rules, one `{label, path, digest}` each. The coordinate skill's own files at the installed plugin (the root's `.claude-plugin/plugin.json` names the version) are `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md` and the six references SKILL.md's Reference Files table names (`loop.md`, `brief-template.md`, `verification-checklist.md`, `state-keys.md`, `landing-milestone-roadmap.md`, `landing-feature-roadmap.md`), each labelled `skill-<file name>`. The workspace's instruction files are every `CLAUDE.md`, `CLAUDE.local.md` and `.claude/rules/*.md` in the working directory and each directory above it, stopping below the home directory (or at the filesystem root when the working directory isn't under it), labelled `workspace-<depth>-<file name>` or `workspace-<depth>-rules-<file name>`, depth 0 being the working directory. Files in the home directory itself are the person's own, not the workspace's, and an `@` import inside a file isn't followed. Every label fits the Run label grammar (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`); a file whose label wouldn't is left out and named on stderr. A new write mode, `state-stored-set.sh --session S --rule-files FILE --by WHO`, takes that list. It sets `record/host`'s `rules:<label>` to each file's path and drops the `rules:` key of any `skill-` or `workspace-` label no longer listed. It replaces the Run `rules` rows whose labels carry either prefix with one `rules <label> sha256:<digest>` row per listed file, keeping a row whose digest didn't change as written, Set included, and keeping every other `rules` row and every `briefs` row. It writes one `run` entry naming each label added, changed (old and new digest) or removed, and only when a Run row changed; with nothing changed it writes nothing. The opener runs the pair, with `--by` its run's session name, on every start that leaves the run holding a record: a resume, a carry, a takeover and an import. A fresh start's record is seeded later, by the find, so `state-open.sh` runs the pair right after each seed it makes: a roadmap seed, a first rotation and a rotation's `--carry`. A failed digest write never fails a start: it prints `warning=rules-unrecorded` after `session=` (or `record=`), the reason on stderr, and the next start writes the rows. `--rules` then prints, after its Standing objects and without changing them, one object per Run `rules` row in record order, `{"run": "rules", "kind": "skill" | "workspace" | "other", "label", "digest"}`, `other` being a label with neither prefix. With `--id` it prints none. No new Standing shape is written and no koto decision command is called.

**Acceptance Criteria**:

- [ ] In a scratch workspace under the scratch `HOME`, whose working directory `$HOME/ws/inst/repo` holds `CLAUDE.md` and whose parent `$HOME/ws/inst` holds `CLAUDE.local.md` and `.claude/rules/imports.md`, with a `CLAUDE.md` in `$HOME` itself and in `$HOME/.claude`, a fresh roadmap start (`coordinate-open.sh`, then `state-open.sh --session <it>` as the find runs it) leaves the Run section holding exactly eleven `rules` rows: the eight `skill-` labels, `workspace-0-CLAUDE.md`, `workspace-1-CLAUDE.local.md` and `workspace-1-rules-imports.md`. Each row's digest equals `sha256sum` of its file, and neither home-directory file has a row.
- [ ] `record/host` holds `rules:<label>` for each of the eleven labels, its value that file's absolute path, and no other `rules:` key.
- [ ] A `.claude/rules` file named `two words.md`, and one whose label would pass 64 bytes, get no row and no `rules:` key and are each named on the opener's stderr; the start still prints `session=` and exits 0.
- [ ] A second start of the same run (a resume) with no file changed appends no entry (the entry count is the same before and after), leaves `record/meta`'s written time, the Run section and `record/host` byte-identical, and prints no `warning=` line.
- [ ] After `SKILL.md` in the plugin copy and the working directory's `CLAUDE.md` are edited and the copy's manifest version raised, the next start replaces exactly those two rows with their new digests, leaves the other nine byte-identical (Set included), and appends one `run` entry naming both labels with their old and new digests.
- [ ] After `.claude/rules/imports.md` is deleted, the next start removes its row and its `rules:` key, and its entry names the label as removed. A `rules notes sha256:<64 hex>` row written beforehand with today's `--run rules`, its `rules:notes` host key, and every `briefs` row stay byte-identical through all of these starts.
- [ ] A takeover (the opener run as a second Claude session, printing `outcome=continued`) leaves the successor's Run `rules` rows naming the files the successor loaded from its own plugin root and working directory, and the predecessor's `record/run` and `record/host` byte-identical to what they held before the takeover.
- [ ] `--rules` on that record prints its Standing objects first, byte-identical to its output on the same record before any `rules` row existed, then one object per Run `rules` row in record order, compared with `jq -S` against expected objects held in the test: kind `skill` for the eight `skill-` labels, `workspace` for the `workspace-` ones and `other` for `notes`, each digest the row's `sha256:<64 hex>`. `--rules --id s1` prints only s1's object.
- [ ] `--rule-files` exits 65, writing no key and posting no entry, on a list holding a label with neither prefix, a label outside the grammar, a relative path, a digest that isn't 64 hex, a path holding a control character or a token-shaped string, or one label twice.
- [ ] With a plugin root whose `SKILL.md` can't be read, the opener still prints `session=` and exits 0, then prints `warning=rules-unrecorded` with the reason on stderr, and the Run section holds no `skill-` row; the next start, with the file readable again, writes all eight.
- [ ] Offline, `rule-files.sh`'s skill list equals `SKILL.md`, `koto-templates/coordinate.md` and every path in SKILL.md's Reference Files table other than the template, read from the table itself, so a reference added to the table without being digested fails the suite.
- [ ] `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --base-table <the base branch's coordinate.compat.json>` exits 0, with `compat` unchanged from the base's and the new `gate_scripts` digest recorded in `coordinate.compat.json`: `state-stored-set.sh` is a script the template's gates run, and no gate decides anything new.

**Check**: Run `bash skills/coordinate/scripts/rule-files_engine_test.sh`, a new engine suite `run-tests.sh --engine` picks up, and see one `ok` line per criterion except the offline one, which `rule-files_test.sh` prints under `run-tests.sh`; both exit 0. The engine suite sources `scripts/lib/koto-test-guard.sh` first, so every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` are unset, sets `HOME` and `KOTO_HOME` under its scratch directory, and asserts `koto session dir <name>` resolves under that directory before its first koto command, stopping if not. It copies the plugin tree (`.claude-plugin/`, `skills/`, `scripts/`) into its scratch directory and opens every run with `--plugin-root` naming the copy, so editing a skill file never touches the checkout. It builds the workspace tree under the scratch `HOME`, runs the opener from `$HOME/ws/inst/repo`, takes the second Claude session for the takeover from `CLAUDE_CODE_SESSION_ID` the way `coordinate-takeover_engine_test.sh` does, reads the Run section, `record/host` and the entries with `koto context get`, and compares digests with `sha256sum` and objects with `jq -S`. The unreadable `SKILL.md` is made with `chmod 000` on the copy. Every command is written out in the script with session names and labels as separate arguments; nothing is downloaded and run, and no command is built from file or record text. `state-stored-set_test.sh` gains the `--rule-files` refusals without koto.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/rule-files.sh` (new), `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/state-open.sh`, `skills/coordinate/scripts/rule-files_test.sh`, `skills/coordinate/scripts/rule-files_engine_test.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/references/state-keys.md` (the crash set's `skill-` and `workspace-` labels and their writer), `skills/coordinate/SKILL.md` (the crash-set paragraph: the start writes these rows, a person never does)

### Step 5: --rules says for every row whether it grants, from the floor, the repository anchor and niwa authority check, and a row never widens the session's grant

**Goal**: `rule_grants` lands in `state-schema.jq`, and `--rules` prints `grants` and `allows` on every Standing object. shirabe keeps two expectations about row text and reads the allowance from the authority work's existing read; it builds no grant model of its own. The floor: a pause, an inferred row, a `pinned` row, an unreadable or superseded row, and a row whose cited decision has an `asserted` reversal never grant. The repository anchor: only a `skill` row citing the repository the installed plugin's manifest names as its source (the `repository` field of `.claude-plugin/plugin.json` under the plugin root, read as `https://github.com/<owner>/<repo>`; a manifest naming none anchors nothing), and a `doc` row citing the record's host repository, can carry a grant. The anchor stays shirabe's provenance rule about whose merged words a row may quote, not a grant model, and the authority read doesn't replace it. A row the floor or the anchor settles prints `grants` false and `allows` `[]` and never causes a read. For the rest, `--rules` makes at most one read per invocation, `niwa authority check -C <instance> --session <id> --json`, and only when at least one row among those it prints passes both; that one answer applies to every such row. The instance is the first directory at or above the working directory holding `.niwa/instance.json`, made canonical, the walk `posture-read.sh` makes for its own grant read. The session is `CLAUDE_CODE_SESSION_ID`, the coordinator's Claude session, which niwa ties to its dispatch. `record/host` stores neither, and the record's one session fact is `record/meta`'s driver, which a takeover writes, so when `record/meta` names a driver other than `CLAUDE_CODE_SESSION_ID` the caller isn't the session driving this record and no read is made. niwa is found on PATH, else as an executable `$NIWA_BIN`, and the read is bounded at `NIWA_LOOKUP_SECONDS` (3 seconds), as `posture-read.sh` finds and bounds it. `grants` is true only for a row in effect that passes the floor and the anchor, when the read exited 0 and printed a `niwa.authority.check/v1` document with `"state": "bound"`, a `grant` array whose every `authority` is `merge-pr`, `close-issue` or `cut-release`, and a `level` of `autonomous`, `supervised` or `strict`. `allows` is then that grant's authorities in niwa's order, which may be empty. Any other exit, state or shape, no niwa, no session id, no instance root, or a read past its bound gives every row `grants` false and `allows` `[]`, and `--rules` still exits 0. Rows restrict and never widen: `allows` is the session's grant as the read answers it, never more, whatever a row's words say. niwa's per-point settler answer is only as complete as authority work that hasn't started (the work tying who may decide to the authority level), so this step passes no `--point` and builds nothing around the settler answer. No `--point` is passed, no script gates a step on `grants` in this milestone, and the handover read makes no read. No new Standing shape is written and no koto decision command is called.

**Acceptance Criteria**:

- [ ] On a record holding a pause, an `inferred brief` row, a `pinned` row, a `decision` row (unreadable until step 9), a `skill` row citing a repository other than the manifest's and a `doc` row citing a repository other than the record's host, `--rules` prints `grants` false and `allows` `[]` on every object, and the fake niwa's call log stays empty.
- [ ] `rule_grants` cases in `state-schema_test.sh`, built from rows and hand-written facts without koto, return false for a superseded cited row, for a row whose winning reversal is `asserted` and for a pause, each beside a bound answer granting all three authorities; true with that answer's authorities for a relayed go-ahead; and false with `[]` for that go-ahead when no answer is given.
- [ ] On a record holding two relayed go-aheads, a relayed approval, a `skill` row citing the manifest's repository and a `doc` row citing the record's host repository, beside the six rows of the first criterion, with the fake answering bound with grant `merge-pr` at level `supervised`, the call log holds exactly one line. Those five objects each print `grants` true and `allows` `["merge-pr"]`; the six floor and anchor rows print `grants` false and `allows` `[]`.
- [ ] That one logged line is exactly `authority check -C <the instance root, canonical> --session <CLAUDE_CODE_SESSION_ID> --json`, with no `--point`.
- [ ] On the same record, `--rules --id` naming only floor or anchor rows makes no call, `--rules --id` naming one passing row and one floor row makes exactly one, and `state-handover.sh` makes none.
- [ ] Under that answer, a relayed go-ahead whose What reads `Cut the release v2.0.0 and close #12.` prints `allows` `["merge-pr"]`, never `cut-release` or `close-issue`. Under a bound answer whose `grant` is empty, every passing row prints `grants` true and `allows` `[]`.
- [ ] Each of these answers gives every object `grants` false and `allows` `[]`, with `--rules` exiting 0 and every other field byte-identical to its output under the bound answer: exit 1 with a bound document on stdout; state `not-dispatched`; state `record-unusable`; a schema other than `niwa.authority.check/v1`; a bound answer whose `grant` isn't an array, names an authority outside the three, or whose `level` is outside the three; empty stdout; text that isn't JSON; and a fake that sleeps 30 seconds under `NIWA_LOOKUP_SECONDS=1`, where `--rules` returns within 10 seconds.
- [ ] With no niwa on PATH and no `NIWA_BIN`, with `CLAUDE_CODE_SESSION_ID` unset, run from a directory with no `.niwa/instance.json` at or above it, and on a record whose `record/meta` names another driver, `--rules` makes no call and prints `grants` false and `allows` `[]` on every object. With niwa off PATH and `NIWA_BIN` naming the fake, it makes the one call.
- [ ] Run from a copy of the plugin tree whose manifest has no `repository` field, the `skill` row citing the original manifest's repository prints `grants` false, and on a record where it is the only row that would pass, no call is made.
- [ ] Apart from `grants` and `allows`, every `--rules` object on step 1's record A is byte-identical (`jq 'del(.grants, .allows)'`, then `cmp`) to step 1's expected object. Step 1's suite, run with a fake niwa answering `not-dispatched`, now expects `grants` false and `allows` `[]` on every object where it expected no `grants` key.
- [ ] `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --base-table <the base branch's coordinate.compat.json>` exits 0, with `compat` unchanged from the base's and the new `gate_scripts` digest recorded in `coordinate.compat.json`: `state-stored-set.sh` is a script the template's gates run, and no gate reads `grants`.

**Check**: Run `bash skills/coordinate/scripts/rule-grants_engine_test.sh`, a new engine suite `run-tests.sh --engine` picks up, and see one `ok` line per criterion except the `rule_grants` unit cases, which `state-schema_test.sh` prints under `run-tests.sh`; both exit 0. The engine suite sources `scripts/lib/koto-test-guard.sh` first, so every `KOTO_SESSION_*` variable and `KOTO_SESSIONS_BASE` are unset, sets `HOME` and `KOTO_HOME` under its scratch directory, and asserts `koto session dir <name>` resolves under that directory before its first koto command, stopping if not. The real niwa is never reached. A fake `niwa` in the scratch directory, first on PATH, appends its arguments to a call log and answers from an answer file, or as a mode file says (exit 1 still printing the answer, print nothing, sleep), the way `posture-read_test.sh`'s stub does. The no-niwa case runs under a PATH in which every directory holding a `niwa` is replaced by a copy without it, built as that suite builds it. The suite builds `$HOME/ws/inst/.niwa/instance.json`, runs `--rules` from `$HOME/ws/inst/repo` with `CLAUDE_CODE_SESSION_ID` set to a fixed lowercase UUID, seeds the rows with `koto context add` from testdata files as step 1 does, and makes the other-driver record by adding a copy of `record/meta` naming another driver. It counts reads by the call log's lines, comparing the log with `cmp` against the expected line. Step 1's suite, and any other suite that runs `--rules`, puts the same fake first on PATH. Every command is written out in the script with session names and Sources as separate arguments; nothing is downloaded and run, and no command is built from document or record text.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/state-schema.jq` (`rule_grants`), `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-schema_test.sh`, `skills/coordinate/scripts/state-stored-set_test.sh`, `skills/coordinate/scripts/rule-grants_engine_test.sh`, `skills/coordinate/scripts/standing-rules_engine_test.sh`, `skills/coordinate/scripts/testdata/standing-rules/`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/check-skill.tsv`

### Step 6: --standing rule writes a skill, doc, pinned or inferred rule row and refuses one that cites words its source doesn't hold

shirabe, after the reader release has shipped: the writer takes `rule` and `--source` in the four uncited forms with the grammar, the private-repository checks on Source and What, the default-branch and quoted-sentence checks (three forge reads on a public host, two elsewhere, any failure refusing the row), one refusal for a missing and an unreadable repository, and the 120-rule and 60-inferred caps that leave room for every event kind.

### Step 7: a start whose brief has no briefs row names brief-unread, and the intake brings each brief rule in once as an inferred row

shirabe, after step 6: `record/host` names the brief, the handover read raises `brief-unread <label>`, the intake writes one `inferred brief` rule row per unmatched brief sentence by the normalized match plus the `briefs` row, is idempotent on one digest, brings a pause-shaped line in as a restrict-only `rule` row, ends the earlier digest's inferred rows the new brief no longer states, and leaves the gap open naming the count when a cap would be passed.

### Step 8: state-keys.md and SKILL.md describe rule rows, Source forms, classes and the two read modes

shirabe, with step 7: the reference text for the uncited forms, the intake and `--rules`, with "yourself as relayer" kept until step 16; this touches the same passages of `SKILL.md` and `references/state-keys.md` as the coordinate skill's reviewer-wording change in tsukumogami/shirabe#1449, so whichever lands second rebases on the first.

### Step 9: standing-provenance.sh prints a cited decision's facts, and anything it can't read in 5 seconds reads unreadable

shirabe, gated on a koto release with the decision record and the reads listed below: the read-only helper runs `koto decisions show <session> <id>` with the two passed as separate arguments, prints decider, surface, link, entering session, time, subject, status, the bound test's inputs and the winning reversal's standing path and fence, cuts koto text to 200 characters with control characters stripped, and fails closed on any error, parse failure or timeout.

### Step 10: a decision row reads owner-said, dispatcher-said or inferred by the root and leg tests, and the writer refuses a citation that wouldn't

shirabe, gated as step 9 plus the supersede hop, with only its dispatcher-said criterion also waiting on koto's cross-session decision read (with the read failing, a citation of the dispatcher's decision reads unreadable and the writer records the ruling as an `inferred` rule row quoting it, flagged for confirmation, and its tests cover both paths): the `decision` form, `rule_class`'s fixed-order tests (unreadable, person to the root test, own run, then a leg to a coordinator outside the writer's run created before the writer), the writer's refusals (What not equal to the decision's whole reason, Owner not koto's decider, a person in Owner uncited once the koto floor is met), and the koto version-floor check that turns citations on; it ships in the same plugin release as step 14, because that refusal covers the carry acknowledgement every handover writes.

### Step 11: a manager's row citing its director's person decision reads owner-said, and reads as a flagged inferred quote while the cross-session read fails

shirabe, gated as step 10, with only its owner-said criterion also waiting on koto's cross-session decision read on one host: a manager on the same host as its director cites the decision the director recorded and reads owner-said one level down; with the read failing, the citation reads unreadable and the manager writes an `inferred` rule row quoting the ruling, flagged for confirmation, and its tests cover both paths.

### Step 12: a reversed cited pause holds nothing and a reversed cited go-ahead lets nothing through, inside the pause read's bounds

shirabe, gated as step 10: `pause-read.sh` reads uncited pauses first, consults at most 16 cited rows within 20 seconds, treats an unreached, unreadable or timed-out row as unreadable (a pause holds, a go-ahead grants nothing), keeps a row whose only reversal is asserted holding and restricting, and names the session koto couldn't read.

### Step 13: --confirm cites a row in place, --end follows the cited-row rules, and a superseded row's place against the rule cap is settled

shirabe, gated as step 10: `--confirm` keeps id, kind, On, Until, What and Set and sets an event row's Owner to koto's decider, `--end` refuses a cited row in effect naming `koto decisions reverse` and accepts it only after a verified reversal older than this member whose words the brief no longer states, `--authorized-by` ends an unreadable or asserted row, the intake matches superseded rows, and a superseded row counts against the 120-rule cap but not the 60-inferred one, with the start report naming each superseded row `--end` would now accept.

### Step 14: each kind of successor writes a carry acknowledgement that satisfies the handover gate, and only a director's taken-over successor reads owner-said

shirabe, gated on the supersede hop: a director's taken-over successor cites a person decision it records and reads owner-said; a carried run cites one in its own session, reads inferred with `confirm` true, satisfies the gate and nothing else, and is listed for its next fenced member; a manager's successor, never a root and never entering a person decision, cites a session decision its director records acknowledging the carry, which reads dispatcher-said through a leg, and otherwise, including while koto's cross-session decision read is missing, writes today's uncited event row naming the director's session as Owner, which reads relayed.

### Step 15: every tick's gate output lists the rule ids in force, and after a reversal no tick lists the reversed rule as in force

shirabe, gated as step 12: the coordinate template's tick runs `--rules --in-force` as a gate whose output koto records in the session log, so the reversal check reads ticks from koto's log rather than from entries naming a Standing id; the template's compat number moves with it.

### Step 16: SKILL.md tells a root to record the owner's word before writing the row and a manager to cite its director's

shirabe, after steps 5, 8, 11 and 14: the owner-said procedure, the manager rule, the replacement for "record a person's word found on the record's thread or anywhere else", the dropped "yourself as relayer", and the restrict-only rule for rows `rule_grants` refuses, on the same passages tsukumogami/shirabe#1449 changes.

### Step 17: on a fixture lineage, the five outcome checks each hold, and the unsourced count rises within its threshold

shirabe, after steps 3, 4, 11, 13, 14 and 15: an end-to-end walkthrough a reviewer can rerun, over a fixture lineage of at least six successions whose every handover writes its carry acknowledgement in one of step 14's forms, that runs the design's five checks with the observations described below for the old lineage, the reversed rule and the accretion threshold.

## Implementation Sequence

The steps run in order where they depend on each other and side by side
where they don't. Each step is one pull request in tsukumogami/shirabe. A
step marked gated waits on something outside this plan; the others can
start now that the design is accepted.

| Step | Phase | Depends on | Gated on |
|---|---|---|---|
| 1 | reader release | none | nothing |
| 2 | reader release | none | nothing |
| 3 | reader release | 1 | nothing |
| 4 | reader release | 1 | nothing |
| 5 | reader release | 1 | the authority work's agreement to the grant interface, which is reached; niwa already ships the read |
| 6 | writer release | 1 | the reader release (steps 1 to 5) shipped in a plugin release |
| 7 | writer release | 6 | as step 6 |
| 8 | writer release | 7 | as step 6 |
| 9 | citations | 1 | a koto release with the decision record and the reads below |
| 10 | citations | 6, 9 | as step 9, plus the supersede hop; its dispatcher-said criterion also waits on the cross-session decision read |
| 11 | citations | 10 | as step 10; its owner-said criterion also waits on the cross-session decision read |
| 12 | citations | 9 | as step 10 |
| 13 | citations | 7, 10 | as step 10 |
| 14 | citations | 10 | as step 10; its dispatcher-said criterion also waits on the cross-session decision read |
| 15 | citations | 12 | as step 10 |
| 16 | citations | 5, 8, 11, 14 | as step 11 |
| 17 | citations | 3, 4, 11, 13, 14, 15 | as step 11 |

Steps 1 to 5 need no koto change and can be built first. Step 5 reads
only `niwa authority check`, which niwa already ships, and nothing in
steps 6 to 8 reads `grants`. Steps 6 to 8 wait for the reader release to
ship, by the design's release rule: the writer release goes out at least
one plugin release after the reader release. Steps 9 to 17 wait for koto.

Steps 10 and 14 ship in one plugin release. Once koto is at the floor,
step 10's writer refuses an uncited event row naming a person in Owner,
and the carry acknowledgement the handover gate asks every successor to
write is such a row. Only step 14 gives a successor a form the gate then
accepts, so a plugin carrying step 10 without step 14 would leave every
coordinator on that koto unable to hand over.

### The koto dependencies

Every one of these is koto's to build. Steps 9 to 17 check for them through
the version floor step 10 adds, and none of them lands on a koto that lacks
what it needs.

| koto dependency | Gates |
|---|---|
| The decision record's session-addressed commands, released: `koto decisions record <session> --kind judgment --by person:<handle> --surface terminal\|forge\|relay [--link]`, `koto decisions show <session> <id>`, `koto decisions reverse`, and the listing below a session | steps 9 to 17 |
| The supersede hop with Decision 4's six conditions: a fenced predecessor records no decision, a write-once supersede marker readable at listing cost, the chain walk following the marker with id checks, refusal on a hop it can't confirm, the hop recorded in the reversal's standing path, and person-reverses-person unchanged | steps 10 to 17 |
| The reads koto's decision design doesn't name yet: a decision's status, the entering session of a person decision, the frozen chain with each link's kind, the winning reversal's standing path, the supersede marker, and ideally one read of the chain walk so shirabe keeps none of its own | steps 9 to 17 |
| A cross-session decision read: `koto decisions show` on a decision held in another session on the same host, which the design states as an assumption with a fallback | step 11, the dispatcher-said half of step 10, and the manager successor's dispatcher-said citation in step 14 |

The cross-session read is the one the design assumes rather than requires.
Without it a manager's citation of its director's decision reads unreadable,
and the manager writes the ruling as an `inferred` rule row quoting it,
flagged for confirmation, until the read works. Step 11 builds and tests
that fallback, so it can land on a koto whose cross-session read is still
missing, provided the other three rows are met; it is gated on the read
only for its owner-said criterion.

The four open items the design carries back to koto (a verified identity
for a person decider, dispatch links and requesters koto observes itself, a
carry that rides the fence, and a rule for who may fence a session) gate no
step. They close residual risks the design accepts.

### The grant read behind rule_grants (step 5)

This plan builds no grant model. Who may settle a step and what a grant
allows belong to the authority work, which already has the one read a gate,
a coordinator and the session itself all make: `niwa authority check -C
<instance> --session <id> --json`. Its answer says whether the session is
bound to its dispatch, its grant (`merge-pr`, `close-issue`, `cut-release`
or none) and its level. That read is the grant behind `rule_grants`. An
allowance is configurable per workspace and host while an expectation is
hardcoded in the skill, so shirabe keeps two expectations and reads the
allowance:

- **The floor.** A row the design says can only restrict never grants: a
  pause, an inferred row, a `pinned` row, an unreadable or superseded row,
  and a row whose cited decision has an `asserted` reversal. The root test
  in `rule_class` stays where it is.
- **The repository anchor.** Only a `skill` row citing the installed
  plugin's own source repository, and a `doc` row citing the record's host
  repository, can carry a grant; a row citing any other repository restricts
  only. This is shirabe's provenance rule for row text, about whose merged
  words a row may quote, not a grant model, and the authority read doesn't
  replace it.

What the interface is:

- **What calls it.** The coordinator, through `rule_grants`, before a rule
  permits a step. In this milestone `state-stored-set.sh --rules` makes
  at most one read per `--rules` call, made only when a row passes the floor
  and the anchor, its one answer applied to every row that passes both, and no
  script gates a step on the answer: the pause read enforces pauses and
  go-aheads by kind and status, as the design says.
- **What it returns.** The session's grant as the authority read answers
  it. `--rules` prints it on each such row as `allows`, and `grants` is true
  only when the row is in effect, passes the floor and the anchor, and the
  read printed a `niwa.authority.check/v1` document with `"state": "bound"`
  and exit 0. Any other exit, state or shape gives `grants` false and an
  empty `allows`.
- **Restrict, never widen.** A row can narrow what the session's grant
  allows and never add to it, so a granting row never permits anything the
  workspace doesn't already grant that session. That matches the design's
  rule that a `doc` grant never widens what the workspace allows.

This plan uses no per-point settler answer (`--point`). Any later use of it
depends on the authority work that ties who may decide to the authority
level, which hasn't started. Successor reversal standing stays with koto, in
the koto dependencies below. The design's Key Interfaces example shows
`"grants": true` on an owner-said row, which is what this read gives for a
bound session.

### The Run rules digests (step 4)

The design leans on the Run section's `rules` digests to say which skill
and workspace text a coordinator ran under, so that text isn't copied into
rows, but nothing writes those digests today. Step 4 gives them a writer:
the opener, at every start, digests each file the session loads as rules
and writes one `rules <label> sha256:<digest>` row for it, with the file's
path in `record/host`, replacing the label's earlier row and writing an
entry when the digest changed. The label carries the kind: `skill-` for the
coordinate skill's own files at the installed plugin version, `workspace-`
for the workspace's instruction files. `--rules` prints one object per Run
`rules` row with its kind, label and digest.

The reviewer's first check then reads two lists from the predecessor's own
record: its `--rules` Standing objects, each with a class, and its Run
`rules` objects, each skill and workspace rule file with its kind.

### The accretion threshold (step 17)

The check for "unsourced rules stop accreting" runs `--rules --counts` on
each member of a lineage, oldest to newest, and passes when the inferred
count rises by no more than one per three successions, against the baseline
the reviewer measures on the same lineage before the change. The fixture in
step 17 has at least six successions, so there a rise of three or more over
its starting count fails.

What keeps the rise that low in this design:

- The intake runs once per brief digest, and its duplicate test is the
  mechanical normalized match against every row, superseded ones included,
  so a successor's brief that re-copies its predecessor's sentences adds
  nothing.
- A new digest of the same brief label ends the earlier digest's inferred
  rows that the new brief no longer states, so a reworded sentence replaces
  a row rather than adding one.
- A rule the owner reversed doesn't come back as inferred, since the
  intake matches superseded rows, and step 13 keeps a superseded row until
  no brief states its words.
- `--confirm` turns an inferred row into a cited one, and the writer never
  creates a new `decision` row that reads inferred, save the carried run's
  carry acknowledgement.

The gap: nothing in this milestone stops a predecessor writing new prose
rules into its successor's brief, and each new sentence comes in as one
inferred row. The 60-row cap bounds that and the start report lists every
unconfirmed row, but neither holds the rate. Stopping briefs from carrying
prose at all is the compiled-brief work that follows this milestone. Step
17's fixture includes one succession that adds a new brief sentence, so the
check shows the rise that gap allows.

### The reversal check (step 15)

The design's third check says no entry written after a reversal names the
reversed Standing id as the reason for an action. That rests on the
coordinator naming Standing ids in its own entries, which it may not do. Step
15 adds an observation that doesn't: the coordinate template's tick runs
`--rules --in-force` as a gate, and koto records each gate's output in the
session's log. A reviewer reads, from koto's log of each run member, every
tick after the reversal's time and sees the reversed id absent from the
in-force list (or present only as superseded), in the director's record and
in each lane's. For a cited pause or go-ahead the pause read's output, which
steps 12 and 15 both expose, shows it holding or granting nothing. The
entry-naming check stays as a second signal.

### Notes from the design's last review

- **A manager successor's carry acknowledgement.** Decision 2 makes a
  taken-over successor a root, which holds only for a director: a manager's
  successor stays bound and never enters a person decision. Step 14
  settles the form: the manager's successor cites a session decision its
  director records acknowledging the carry, which reads dispatcher-said
  through a leg; with no leg it writes today's uncited event row naming the
  director's session as Owner, which names no person and reads relayed.
- **Owner and Relayed by stay blank on rule rows.** Step 1's schema
  refuses a `rule` row with either filled, and step 6's writer gives the
  same refusal.
- **How many forge reads a cited file costs.** Components counts two
  (ancestry and the file) and Security three (adding visibility). Step 6
  makes it three on a public host, where the visibility read runs, and two
  elsewhere.
- **A superseded row against the rule cap.** Step 13 counts a superseded
  row against the 120-rule cap and not the 60-inferred cap, and the start
  report names each superseded row `--end` would now accept, so the cap
  can't fill with rows nobody can see are ready to go.

### What each outcome rests on

| Outcome | Steps |
|---|---|
| An old lineage keeps its rules, and every skill and workspace rule file is listed with a kind | 1, 4, 7, 17 |
| Three sources on request, each with a class, a date and a pointer | 1, 6, 9, 10 |
| A reversed rule is never acted on, read from koto's log rather than from entries | 12, 13, 15, 17 |
| Unsourced rules stop accreting, within the stated threshold | 3, 7, 13, 17 |
| One home, one reversal | 1, 10, 13 |
