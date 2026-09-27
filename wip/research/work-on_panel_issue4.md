# Review panel: Issue 4 (record read and rotation handoff for reconcile)

Subject: commit 466749b -- `skills/coordinate/scripts/reconcile-read.sh`,
`reconcile-read_test.sh`, and the two names added to `reconcile-deps.sh`.

Probes ran the script against the record feature's real `record-parse.sh`,
`record-render.sh` and `record-codec.jq` (copied from the F2 extraction), with
the test file's own keyed stub standing in for `gh` and `coord-log.sh`.
Probe scripts: `/home/dangazineu/.claude/jobs/d0fd18fd/tmp/panel4/probe{1,2,3}.sh`
(harness in `lib.sh`, `setup.sh`).

## Tests

- Linux bash 5, with `RECORD_FEATURE_SCRIPTS` set (real parser): 40 passed, 0 failed.
- Linux bash 5, without it: 35 passed, 0 failed (the 5 contract cases skip).
- bash 3.2.57 (the `shirabe-bash-floor:3.2` image): 40/0 with the real parser, 35/0 without.

## Blocking

### B1. A handoff with a missing or empty reasoning section refuses the whole reconcile

`reconcile-read.sh:152-157`. The AC (and DESIGN "Rotation handoff") says a
missing, empty or "not recorded" reasoning section yields "no reasoning
received" and no reasoning output. With the real parser both cases exit 4
instead:

- Section heading present, nothing under it (probe P1): the codec's
  `normalized` trims trailing newlines, so `## Reasoning for the next
  rotation` no longer starts with `...rotation\n\n` and `parse_handoff`
  refuses even under `--no-canonical`. Output:
  `{"status":"unreadable","reason":"the handoff file isn't a handoff for this discipline"}`, exit 4.
- Section absent (P2): `parse_handoff` refuses "expected four sections and
  the reasoning"; same exit 4.

The reader has no fallback for these, so a discipline start with a
reasoning-less handoff is blocked rather than reported with
`reasoning: "not_recorded"`. A whitespace-only section (P1b) does reach
`not_recorded`, which shows the intent; it's the codec's refusal path that
isn't handled. Fix: on a 65 from the handoff parse, detect the
missing/empty-reasoning shape (or ask F2 for a parse mode that tolerates it)
and map it to `not_recorded`; add real-parser tests for both.

### B2. The "not recorded" sentence is reported as present reasoning and written as the predecessor's

`reconcile-read.sh:162-168`. Only `has("predecessor_copy")` or a blank
string counts as not recorded. A handoff whose reasoning section is the fixed
sentence "The outgoing rotation's reasoning was not recorded." without the
"As written by the previous rotation at ..." line (a hand edit, or a
predecessor copy that lost that line) parses under `--no-canonical` as
`{reasoning: "<the sentence>"}`. Probe P3: `reasoning: "present"`, and
`--reasoning-out` receives the sentence as if it were the predecessor's
reasoning. The DESIGN says a section that "says the reasoning wasn't
recorded" is `not_recorded` with no key written. Fix: also treat
`.reasoning` equal to the codec's `predecessor_sentence` (after trimming) as
`not_recorded`.

### B3. The handoff's deferrals and side effects are merged unlabelled, and the handoff date never reaches the report

`reconcile-read.sh:184-189`.

- `deferrals` and `side_effects` are concatenated with the handoff's with no
  `source` and no date (only holdings are wrapped as `{row, source}`). The
  AC says the handoff's *tables* are labelled with its heading date. In the
  ordinary case, where the successor record carries the predecessor's
  deferrals forward, every such deferral appears twice. Probe P0 and probe
  3: the rendered report lists "flaky test (raised 2026-09-25T10:00Z)" twice
  under "Undisposed deferrals", neither marked as the handoff's.
- `record.source` is `"record and handoff"` (line 184), a value outside the
  facts contract `reconcile-report.sh` documents (`source: record|handoff`,
  reconcile-report.sh:30) and tests (`.header.source == "handoff"`,
  reconcile-report.sh:352). Probe 3: with the reader's value, the report's
  header omits "Rows as written by the previous rotation on 2026-09-23";
  with `"handoff"` it appears. So `handoff_date` is computed and then
  dropped from everything the agent reads, and handoff holdings are
  labelled "row as written by the previous rotation" with no date.

Fix: label handoff deferral and side-effect rows the same way holdings are
(or carry `source`/`date` per row), decide how a carried-forward duplicate
is reported, and emit a `record.source` value the report's contract knows
(or change that contract in the same PR).

### B4. Per-row "unparseable" doesn't exist: one malformed row refuses the record, and `raw` is a diagnostic, not the row

`reconcile-read.sh:118-137, 190-191`. AC 4: "A row the reader returns as
unparseable reaches the facts with its raw text for a fence and the
reader's reason" (and DESIGN, "The contract with the record feature": the
reader returns per-row unparseable results that go to `not_verified[]` with
the raw row fenced).

- Probe Q4c: one Holdings row with an extra cell (`| Feature 2 | extra | ...`)
  makes `record-parse.sh` exit 65 in both modes, and reconcile exits 4 for
  the whole record. Every other row, and the reason the row failed, is lost.
- Probe Q4: when the canonical check fails, `unparseable[0].raw` holds the
  parser's stderr ("record-parse: not canonical: refused: repo: not
  owner/repo"), not the row text, and the offending row still goes into
  `holdings` as a normal row sourced "record" (with `repo: "../../evil"`,
  `branch: "--upload-pack=..."`). reconcile-check.sh validates values before
  use (reconcile-check.sh:102-104), so this isn't an injection, but the
  report says "not verified: invalid repository", not "unparseable row" with
  the row fenced.
- Probe P8b: `raw` can also carry bash's warning with the absolute path of
  record-parse.sh ("…/record-parse.sh: line 112: warning: command
  substitution: ignored null byte in input"), against the DESIGN's rule that
  report paths are never absolute.

F2's `record-parse.sh` has no per-row mode, so this AC can't be met by
passing its output through. Either reconcile splits the body into rows
itself when the parse refuses (which the DESIGN rules out: "two readers of
one record drift"), or F2 grows a per-row result, or the AC and DESIGN are
amended to "a body the parser refuses is unreadable; a non-canonical body is
read and its first differing line reported". As shipped, the code, the AC
and the DESIGN disagree.

## Advisory

### A1. The handoff is fetched directly, against the AC's wording

`reconcile-read.sh:146-150`. The AC says the handoff is read "through the
record feature's `predecessor_handoff` read, never by fetching the file
directly". The script calls `gh api .../contents/docs/disciplines/<name>.md`
itself. I don't count this as blocking: F2's `predecessor-handoff.sh` renders
a handoff from the predecessor *pull request* (only when `record_find` said
`predecessor`), seals a koto capture and writes a session file, so it can't
serve a read-only reconcile read of the committed file. F2's own
`deferral-check.sh:216-218` reads the same file directly (via
`lib_file_at`). The PLAN outline and DESIGN "Rotation handoff" should be
amended to say what the code does, or the read should go through F2's
`lib_file_at` so there's one fetch path.

### A2. Refusal codes: ambiguous, undeclared and timed-out aren't distinct

AC 3 asks for distinct exits for no record, two candidates, an undeclared
candidate, an unreadable body and a timed-out read; DESIGN Decision 2 lists
exits for found, none, ambiguous, undeclared and unreadable. The script has
3 none / 4 unreadable / 5 failed (`reconcile-read.sh:31-36`). Ambiguous and
undeclared can't reach it (run-facts exits 1 unless `record_find` sealed
`found <n>`), so they'd surface as "none: the run has no found record",
which misnames the case to a human. Timeouts share 5 with other failures,
distinguished only by the reason text. Amend the AC, or add the codes.

### A3. The handoff heading date is taken unvalidated from a hand-edited file

`reconcile-read.sh:185`. Under `--no-canonical`, `parse_handoff` captures the
heading's date as `.*`. Probe Q5: `handoff_date: "see <script>alert(1)</script> and https://evil"`.
That value is rendered verbatim into the report markdown
(reconcile-report.sh:352) once B3 is fixed. Validate it as `YYYY-MM-DD` or
emit null and list it as unparseable.

### A4. The handoff's host and record aren't checked against the run

Probe Q6: a handoff whose rotation line names `evil/other` and
`https://github.com/evil/other/pull/1` is accepted with no note. Only the
discipline name is matched (`--expect-scope`). Consider checking
`rotation.host_repo == REPO`.

### A5. The handoff file carries no authority check, and its reasoning goes verbatim into the agent's context

The record is adopted only after `record_find`'s author/editor check; the
handoff on the default branch is trusted on the strength of being merged.
Its reasoning is written byte for byte to `--reasoning-out`, including ANSI
escapes, BEL (probe P8) and NUL (P8b), and ends up in
`reconcile/reasoning.md`, which the agent reads. Verbatim is the design's
intent, but the report should frame it as untrusted text, and stripping NUL
and terminal escapes (at least for display) is worth deciding explicitly.

### A6. A 404 for any reason is a first rotation

`reconcile-read.sh:170`. Any `HTTP 404` on the contents read becomes
`reasoning: "absent"` and the handoff is silently skipped, including a token
that can read repository metadata but not contents (GitHub answers 404, not
403). The repo read succeeding first narrows this, but a fine-grained token
without Contents access would pass it. A 404 whose text lacks "HTTP 404"
(probe P5, "gh: Not Found (404)") is reported as failed, which is the safe
direction.

### A7. A legitimate handoff over 64 KiB is unreadable

Probe P7b: a handoff F2's own `record-render.sh` produced for 300 holdings
(66,530 bytes) is refused by `record-parse.sh`'s 65,536-byte cap (a limit for
issue and PR bodies, not committed files), and reconcile exits 4. Inherited
from F2; worth raising there.

### A8. An empty handoff file is "unreadable", not a first rotation

Probe P4: a 0-byte `docs/disciplines/<name>.md` exits 4. Arguably right; the
AC covers only a missing file. Say which it should be.

### A9. A stale reasoning file survives

`reconcile-read.sh:166-168`. When reasoning is absent or not recorded the
script leaves `--reasoning-out` untouched; probe P10 shows a previous file's
contents survive. If the pass reuses a path across passes, a stale
predecessor's reasoning could be written to `reconcile/reasoning.md`.
Truncate or remove the file in those branches, or document that the caller
must.

### A10. Deadlines add up past the pass's budget

Up to four sequential reads (facts, body, default branch, handoff), each
with its own 8 s deadline (`reconcile-read.sh:50`), so about 32 s in the
worst case. Probe Q7c: 10 s with a 3 s deadline. The DESIGN has the pass
stop launching reads at 20 s and clip each deadline to the time left, but
this script offers no flag to pass a remaining budget, only the
`RECONCILE_READ_DEADLINE` environment variable (which the agent's
environment can set; the same pattern reconcile-check.sh already uses).
Add a `--deadline` or total-budget flag for Issue 5.

### A11. Holdings duplicated between record and handoff

A carried-forward holding appears once from the record and once from the
handoff (probe 3: "Feature 2" listed twice), and each is re-checked. That
may be what's wanted for a first pass, but it doubles reads and report
lines in the common case.

### A12. Reversals are dropped

The parser returns `reversals`; the reader's output omits them for both
record and handoff (`reconcile-read.sh:179-192`). The report doesn't use
them today, so this is fine, but a comment would save the next reader from
wondering.

### A13. AC 2 (reader-refused holdings) isn't addressed here

No `refused` marking reaches the output; the report's facts contract
(reconcile-report.sh:38-40) expects `refused` per holding. If that belongs
to Issue 5 or to reconcile-check, the PLAN should say so. The F2 parser has
no such per-row fact to pass through.

### A14. A merged or closed record exits 4 "unreadable"

`reconcile-read.sh:113`. Probe P6: a merged discipline PR exits 4 with
"the record is no longer open" and the handoff isn't read. Reasonable, but
it's a different situation from a body that isn't a record, and it shares a
code with it. A distinct case would help the escalation message.

### A15. The contract cases skip silently in CI

`reconcile-read_test.sh:252-257`. Until F2 is on the default branch the
real-parser cases print a skip and the suite passes on stubs alone, which is
how B1 and B2 got through: the stubbed `parse-handoff` never refuses those
shapes. Once F2 lands, make a missing parser a failure rather than a skip,
and add real-parser cases for the empty and missing reasoning section, the
fixed sentence without the predecessor-copy line, and a malformed row.

### A16. Small maintainability notes

- `parse` communicates through the global `NOTE` (`reconcile-read.sh:118-130`);
  fine, but the header comment should say so.
- The handoff parse passes `--container "$CONTAINER"`, which record-parse
  ignores for `--format handoff`.
- A timeout on the default-branch read reports "could not be read"
  (line 146-147), unlike the other reads, which say "timed out".
- `rd_deadline` makes its temp file outside `$T`, so a killed run leaves it
  behind. Minor.

## Checked and fine

- Read-only: every call in the log is `gh issue|pr view`, `gh api` GET, or
  `coord-log.sh run-facts` (probe Q9). Reconcile never acts.
- Rows keep the parser's keys: row objects pass through unchanged (contract
  case "reads back row for row"). Handoff holdings carry `source: "handoff"`.
- Injection through facts: a ref with `--jq`, names with newlines, `/`,
  `%2F` or arrays, repos with a leading `-` or a newline, and a zero-padded
  ref are all refused before any GitHub call (probe Q1). Names are held to
  `^[A-Za-z0-9._-]+$`, so `docs/disciplines/<name>.md` can't traverse (`..`
  becomes `...md`), and default branches with `&`, `#`, `?` or `..` are
  refused before they're spliced into `?ref=` (probe Q3).
- `--reasoning-out` to a missing directory or `/dev/full` exits 5 with a
  refusal line (probe P9).
- Deadlines: a facts read past a 1 s deadline returns in about 1 s with
  "timed out" (Q7); an out-of-range deadline falls back to 8 (Q7b).
- stdout is exactly one JSON line for success and for refusals (Q8).
- AC 7: the reader and seal helper are named only in `reconcile-deps.sh:43-46`.
- Portability: the suite passes on bash 3.2.57 in the floor image; no
  `case` inside `$(...)`, no GNU-only flags (`head -c`, `tr` ranges, `mktemp -d`
  templates, `awk`, `sed` without `-i`), no empty-array expansions.
