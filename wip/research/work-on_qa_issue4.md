# QA: Issue 4, record read and rotation handoff for reconcile

Branch `docs/coordinate-reconcile` at 1bc8e29. Under test: `skills/coordinate/scripts/reconcile-read.sh` and `reconcile-salvage.jq`, run against the record feature's real `record-parse.sh`, `record-render.sh` and `record-codec.jq`. Every body and handoff below was produced by `record-render.sh` and then hand-edited where the scenario calls for it.

## Setup

A scratch tree held reconcile's scripts (`reconcile-read.sh`, `reconcile-deps.sh`, `reconcile-salvage.jq`, `reconcile-report.sh`, and `skills/execute/scripts/coord-common.sh`) beside the record feature's `record-parse.sh`, `record-render.sh` and `record-codec.jq`, the same layout `reconcile-read_test.sh` builds for its contract cases. `gh` was a stand-in on PATH that served per-case responses, exit codes, stderr and delays and logged every call. `coord-log.sh` was a stand-in for `run-facts` for the `--session` cases. The others used `--scope/--name/--repo/--ref`. Every run set TMPDIR inside the scratch area so path leaks would show up.

## Unit suite

| Run | Result | Evidence |
|---|---|---|
| `RECORD_FEATURE_SCRIPTS` set to the record feature's scripts | PASS | `passed: 53  failed: 0` (contract cases ran against the real parser) |
| without `RECORD_FEATURE_SCRIPTS` | PASS | `passed: 38  failed: 0`, "skip contract cases: the record feature's parser is not beside this script" |

## Summary

156 checks ran: 2 unit-suite runs and 154 scenario checks. 147 passed, 5 are observations (INFO) and 4 failed. The failures come from three defects.

The core of the issue holds up. Roadmap scope reads exactly the issue it was given and nothing else. Discipline scope reads the pull request, then the default branch, then `docs/disciplines/<name>.md` at that branch. A record that is closed or merged gets exit 4 before any handoff read. Wrong-scope, oversized, structurally broken and empty bodies get exit 4 and are not salvaged. Hand-edited rows (grammar breaks, extra or missing cells, unescaped pipes) are set aside one by one with their raw line and the codec's reason, and every other row is still read. Escaped pipes decode on both the canonical and the salvage paths. CRLF and mixed line endings read clean. Text that quotes the parser's refusal or not-canonical wording is treated as data, and the line reported is always the parser's own. Every handoff variant maps to the right reasoning status. The reasoning file is byte-for-byte verbatim and is never left stale. Deduplication uses the documented keys. Deadlines hold at 1 s plus the kill grace, including when `gh` leaves a grandchild holding stdout. No stdout, stderr or report output contained a path from the scratch tree, TMPDIR or the home directory.

### Failures

1. **Control characters reach the reader's JSON.** Three fields let them through.
   - `record.written` carries whatever follows `Written: ` when the salvage path runs. An ESC sequence on that line came out as `"2026-09-26T12:00:00Z\u001b[31m"` (case 801).
   - The handoff's bad heading date goes into `unparseable[].raw` unstripped: `"2026\u001b[31m-09-23\u007f"` (case 808).
   - A bare CR inside a free-text cell survives the salvage read. The deferral reason came out as `"not\rnow"` (case 214). The record codec's `check_cell` control-character class leaves out `\r` because its encoder writes CR as `&#13;`. The canonical parser therefore rejects the row as not canonical, and the salvage read then keeps it with the CR.

   Row raws, the not-canonical body echo and the parser-reason paths all strip control characters correctly. These three are the only gaps.
2. **The salvaged `Written:` value is not validated.** A doubled space after `Written:` reads the rows and lists a not-canonical note, but `record.written` becomes `" 2026-09-26T12:00:00Z"`. A trailing space and a non-time value (`whenever <b>x</b>`) also pass straight through. The report then prints `Record written  2026-...`. This has the same root as the `written` control-character leak in failure 1.
3. **At the seam with `reconcile-report.sh`, a bad handoff date renders as "on null."** When the heading date is bad, the reader emits `source: "record and handoff"` with `handoff_date: null`, as its header documents. The report's text header then reads "Rows marked as the previous rotation's are as it wrote them on null." Either the report should drop the date clause when it is null, or the reader should fall back to a value the report can print.

### Observations (not counted as failures)

- A default-branch read that times out gets the reason "the host's default branch could not be read" rather than "timed out". The body, handoff and run-facts reads all say "timed out", and the script header promises that "the reason says which".
- A body refused for size gets the generic reason "the body isn't a coordinator record for this scope". The exit code (4) is correct.
- In a stub-only case, `gh --jq .default_branch` printed the string `null`. That passes the branch validator, and the handoff read went to `?ref=null`. GitHub doesn't return a null default branch for a readable repository.
- The reasoning file keeps ESC bytes from the handoff. That's verbatim by design, and it goes to the file, not stdout. Whoever consumes `reconcile/reasoning.md` should treat it as untrusted text.
- A missing reasoning section is noted as "not canonical: the body does not render back as written", though the parser actually refused it for a missing section. The wording is slightly off, but the handling is correct.

## Results by area

### 1 body read

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | roadmap scope (flags): rendered record reads back row for row, all rows sourced record | 101-rm-override | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 2 | PASS | roadmap scope: exactly one gh call, issue view of the found number; no handoff/default-branch read | 101-rm-override | `log: gh issue view 40 --repo acme/widgets --json state,body` |
| 3 | PASS | roadmap scope (--session via coord-log.sh run-facts stub): same read | 102-rm-session | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 4 | PASS | session mode asks coord-log.sh run-facts for the session, then reads the issue it names | 102-rm-session | `coord-log run-facts --session coordinate-plugin-system-20260926T120000Z;gh issue view 40 --repo acme/widgets --json state,body;` |
| 5 | PASS | roadmap scope: a body for ROADMAP-plugin-system-v2 read as plugin-system is refused, not taken | 103-rm-longer-title | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 6 | PASS | discipline scope: PR body with Part 1 prefix reads back; handoff rows appended | 104-ds-override | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 7 | PASS | discipline scope reads gh pr view 77, then default branch, then docs/disciplines/ci-health.md at that branch | 104-ds-override | `gh pr view 77 --repo acme/widgets --json state,body;gh api repos/acme/widgets --jq .default_branch;gh api -H Accept: application/vnd.github.raw repos/acme/widgets/contents/docs/disciplines/ci-health.md?ref=main;` |
| 8 | PASS | discipline record rendered for an issue container (no Part 1 prefix) served as the PR body: still read (non-canonical noted) or refused, never silently clean | 105-ds-issue-container | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 9 | PASS | roadmap scope served a discipline body: refused as another scope | 106-rm-disc-body | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |

### 2 not open

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | roadmap record in state CLOSED is 'no longer open' (exit 4) | 107-state-CLOSED | `exit 4: {"status":"unreadable","reason":"the record is no longer open"}` |
| 2 | PASS | roadmap record in state MERGED is 'no longer open' (exit 4) | 108-state-MERGED | `exit 4: {"status":"unreadable","reason":"the record is no longer open"}` |
| 3 | PASS | discipline record PR CLOSED is refused before any handoff read | 109-ds-closed | `exit 4: {"status":"unreadable","reason":"the record is no longer open"}` |
| 4 | PASS | no handoff read for a closed record | 109-ds-closed | `gh pr view 77 --repo acme/widgets --json state,body;` |

### 3 parser refusal

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | record for plugin-system read as roadmap 'plugin': refused (exit 4), not salvaged | 110-wrong-scope-name | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 2 | PASS | roadmap body read at discipline scope with the same name: refused | 111-wrong-scope-kind | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 3 | PASS | another scope's body with a bad row: still refused as another scope (salvage checks scope too) | 112-wrong-scope-edited | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 4 | PASS | a well-formed 71098-byte body is refused for size (exit 4), not read row by row | 113-too-large | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 5 | PASS | a body of exactly 65536 bytes (65536) is read (the limit is inclusive) | 114-size-boundary | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 6 | PASS | prose body: refused as not a record (exit 4) | 115-no-structure | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 7 | PASS | body without the declaration line: refused (exit 4) | 116-no-declaration | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 8 | PASS | body missing a section: refused (exit 4), no rows salvaged | 117-missing-section | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 9 | PASS | a table header renamed by hand: refused (structure, no row to salvage) | 118-bad-header | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 10 | PASS | empty body: refused (exit 4) | 119-empty-body | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |

### 4 hand-edited body

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | grammar-breaking row (short verified_head): that holding set aside with raw line and codec reason; the other holding, deferral, side effect still read | 201-grammar-sha | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 3...` |
| 2 | PASS | grammar-breaking deferral (raised=yesterday): deferral unparseable, both holdings read | 202-grammar-date | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 3 | PASS | a worker cell in the shape of a session id is set aside (worker grammar) | 203-grammar-worker | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 3...` |
| 4 | PASS | two bad rows in two sections: both listed, in section order, rest read | 204-two-bad | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 3...` |
| 5 | PASS | row with an extra cell: set aside with reason '5 cells, not 4'; everything else read | 205-extra-cell | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 6 | PASS | row with a missing cell: set aside, rest read | 206-missing-cell | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 7 | PASS | an unescaped pipe typed into a cell: that row is an extra-cell row, set aside | 207-unescaped-pipe | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 8 | PASS | an escaped pipe (renderer-encoded a\\|b with &lt; &amp;) decodes to 'a\|b <c> & d', no unparseable | 208-escaped-pipe | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 9 | PASS | a hand-typed escaped pipe 'not \\| now' is one cell and decodes to 'not \| now', canonical | 209-escaped-pipe-hand | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 10 | PASS | escaped pipe in one row and a bad row elsewhere (salvage path): the escaped pipe still decodes in the salvaged read | 210-escaped-pipe-plus-bad | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 3...` |
| 11 | PASS | whole body CRLF: read clean, no unparseable, same rows | 211-crlf | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 12 | PASS | CRLF body with a bad row: salvaged, raw has no CR | 212-crlf-bad-row | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 13 | PASS | mixed CRLF/LF line endings: read clean | 213-crlf-mixed | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 14 | FAIL | a bare CR inside a cell: row set aside (control character) or kept, never a CR in output | 214-bare-cr | `deferrals[0].row.reason is "not\rnow" (raw CR decoded in the JSON); the codec check_cell control-character class omits \r, so the salvage path keeps it` |
| 15 | PASS | Written line with two spaces: rows all read, a not-canonical entry listed | 215-written-spacing | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":" 2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature ...` |
| 16 | FAIL | Written-line spacing: record.written carries the stray space into the facts | 215-written-spacing | `record.written=[ 2026-09-26T12:00:00Z]; unparseable=[{"raw":"","reason":"not canonical: written: not YYYY-MM-DDTHH:MM:SSZ; the rest was read row by row"}]` |
| 17 | PASS | Written line with a trailing space: read, not-canonical noted | 216-written-trailing | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z ","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature ...` |
| 18 | PASS | Written: line with a non-time value: rows read, not-canonical listed | 217-written-garbage | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"whenever <b>x</b>","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2","...` |
| 19 | INFO | a non-time Written value is passed through unvalidated as record.written (same root as the spacing case) | 217-written-garbage | `record.written=[whenever <b>x</b>]` |
| 20 | PASS | Written line deleted: refused (no Written line is structure) | 218-written-missing | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 21 | PASS | a blank line inserted inside the Deferrals table: listed, other sections still read, or refused -- never silently clean | 219-blank-line-in-table | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 22 | PASS | a note typed between tables: read with the note set aside, or refused -- never silently clean | 220-note-between | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 23 | PASS | a cell quoting refusal words ('the record is for', 'bytes, over') in an extra-cell row: still read row by row | 221-refusal-phrase | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 24 | PASS | a valid cell whose text is the parser's whole refusal line: read as data, no refusal | 222-refusal-phrase-full | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 25 | PASS | a hand-added line reading 'record-parse: refused: body is 99999 bytes, over': not mistaken for a size refusal | 223-refusal-phrase-line | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 26 | PASS | refusal-words line in the head of the body is read (not a size refusal) | 223-refusal-phrase-line | `{"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2","entry...` |
| 27 | PASS | a hand-added 'record-parse: not canonical at line 1' line (at body line 4): the line reported is the parser's own (4), the spoofed text only appears as raw | 224-refusal-not-canonical | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |

### 5 handoff

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | absent handoff (HTTP 404): first rotation -- reasoning absent, source record, no handoff date, record rows only | 301-absent-404 | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2"...` |
| 2 | PASS | 404: no reasoning file written (stale one removed) | 301-absent-404 | `no file at --reasoning-out` |
| 3 | PASS | a default branch other than main (trunk) is the ref the handoff is read at | 302-other-default-branch | `gh pr view 77 --repo acme/widgets --json state,body;gh api repos/acme/widgets --jq .default_branch;gh api -H Accept: application/vnd.github.raw repos/acme/widgets/contents/docs/disciplines/ci-health.md?ref=trunk;` |
| 4 | PASS | reasoning present: status present, source 'record and handoff', date 2026-09-23, handoff rows labelled | 303-present | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 5 | PASS | reasoning file is the section text verbatim (no trailing newline added) | 303-present | `0000000   T   h   e       f   l   a   k   y       j   o   b       i   s 0000020       t   i   m   i   n   g   . 0000030 ` |
| 6 | PASS | multi-paragraph reasoning with a '## ' sub-heading, a pipe and code: present | 304-multi | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 7 | PASS | multi-paragraph reasoning written byte for byte, including the '## ' line | 304-multi | `cmp equal (72 bytes)` |
| 8 | PASS | reasoning present without --reasoning-out: still reported present, nothing written | 305-present-no-out | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 9 | PASS | a predecessor copy (As written by the previous rotation ... + fixed sentence): not_recorded, rows still read | 306-copy | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 10 | PASS | predecessor copy: no reasoning file written (stale one removed) | 306-copy | `no file at --reasoning-out` |
| 11 | PASS | copy line present but real reasoning text (not the fixed sentence): read, with a not-canonical note or as present -- never silently a copy | 308-copy-line-with-own-reasoning | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 12 | PASS | missing reasoning section: tables read, not_recorded | 309-missing-section | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 13 | PASS | missing section: no reasoning file written (stale one removed) | 309-missing-section | `no file at --reasoning-out` |
| 14 | PASS | missing section is also listed as a handoff not-canonical note | 309-missing-section | `[{"raw":"","reason":"handoff: not canonical: the body does not render back as written; the rest was read row by row"}]` |
| 15 | PASS | empty reasoning section (heading only): not_recorded | 310-heading-only | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 16 | PASS | empty section: no reasoning file written (stale one removed) | 310-heading-only | `no file at --reasoning-out` |
| 17 | PASS | reasoning section holding only whitespace: not_recorded | 311-whitespace-only | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 18 | PASS | whitespace-only: no reasoning file written (stale one removed) | 311-whitespace-only | `no file at --reasoning-out` |
| 19 | PASS | only the fixed sentence (no copy line): not_recorded | 312-sentence | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 20 | PASS | fixed sentence: no reasoning file written (stale one removed) | 312-sentence | `no file at --reasoning-out` |
| 21 | PASS | the fixed sentence with surrounding spaces: not_recorded | 313-sentence-padded | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 22 | PASS | the fixed sentence followed by real text: present (it is the rotation's own words) | 314-sentence-plus | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 23 | PASS | a bad handoff row: set aside labelled 'handoff: Deferrals ...', the other handoff rows and the record's rows read | 315-bad-row | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 24 | PASS | bad handoff row: reasoning still written verbatim | 315-bad-row | `ok` |
| 25 | PASS | a handoff holding with an instance-shaped worker: set aside, labelled handoff | 316-bad-row-grammar | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 26 | PASS | a handoff naming another host repository: refused (exit 4) | 317-other-host | `exit 4: {"status":"unreadable","reason":"the handoff names another host repository"}` |
| 27 | PASS | another host: no reasoning file written (stale one removed) | 317-other-host | `no file at --reasoning-out` |
| 28 | PASS | host named in different case (Acme/Widgets): accepted as the same host | 318-host-case | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 29 | PASS | a handoff for another discipline at this path: refused (exit 4) | 319-other-discipline | `exit 4: {"status":"unreadable","reason":"the handoff file isn't a handoff for this discipline"}` |
| 30 | PASS | a handoff with its heading removed: refused (exit 4) | 320-no-heading | `exit 4: {"status":"unreadable","reason":"the handoff file isn't a handoff for this discipline"}` |
| 31 | PASS | a bad heading date: handoff_date null, the date listed as unparseable, rows still read | 321-bad-date | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":null},"holdings":[{"row":{"unit"...` |
| 32 | PASS | a prose heading date: handoff_date null, listed | 322-bad-date-2 | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":null},"holdings":[{"row":{"unit"...` |
| 33 | PASS | rows the record already carries (same worker; same deferral+raised; same side effect+target+attempted) are not repeated; the new side effect is | 323-dup | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 34 | PASS | same worker, different unit in the handoff: kept (the dedupe key is worker+unit) | 324-dup-same-worker-other-unit | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 35 | PASS | same deferral raised at another time: kept as the handoff's | 325-dup-deferral-other-time | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 36 | PASS | a handoff over 65536 bytes: refused as not a handoff (exit 4), not salvaged | 326-handoff-too-large | `exit 4: {"status":"unreadable","reason":"the handoff file isn't a handoff for this discipline"}` |
| 37 | PASS | an empty handoff file (200, zero bytes): refused (exit 4), not a first rotation | 327-handoff-empty-file | `exit 4: {"status":"unreadable","reason":"the handoff file isn't a handoff for this discipline"}` |
| 38 | PASS | a CRLF handoff: read clean, reasoning present | 328-handoff-crlf | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 39 | PASS | CRLF handoff: reasoning file has no CR | 328-handoff-crlf | `0000000   T   h   e       f   l   a   k   y       j   o   b       i   s 0000020       t   i   m   i   n   g   . ` |
| 40 | PASS | roadmap scope with --reasoning-out: reasoning null, no handoff read | 329-roadmap-no-handoff | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 41 | PASS | roadmap scope makes no api call; no reasoning file | 329-roadmap-no-handoff | `gh issue view 40 --repo acme/widgets --json state,body; file=no` |

### 6 failures and deadlines

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | body read past RECONCILE_READ_DEADLINE=1 (gh sleeps 6s): failed, 'reading the record timed out', exit 5 | 401-body-late | `exit 5: {"status":"failed","reason":"reading the record timed out"}` |
| 2 | PASS | body timeout returns within the deadline plus the 1s kill grace | 401-body-late | `elapsed 2.013020310s` |
| 3 | PASS | a 2s body read under a 3s deadline completes | 402-body-late-dl3 | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 4 | PASS | body read fails (gh exit 1, HTTP 502): failed, 'the record could not be read', exit 5 | 403-body-fail | `exit 5: {"status":"failed","reason":"the record could not be read"}` |
| 5 | PASS | record number that no longer exists (gh 404): failed read, exit 5 (not a first rotation, not none) | 404-body-404 | `exit 5: {"status":"failed","reason":"the record could not be read"}` |
| 6 | PASS | body response not JSON: failed, 'the record's response is unreadable' | 405-body-garbled | `exit 5: {"status":"failed","reason":"the record's response is unreadable"}` |
| 7 | PASS | body null in the response: failed read | 406-body-null | `exit 5: {"status":"failed","reason":"the record's response is unreadable"}` |
| 8 | PASS | handoff read past the deadline: failed, 'reading the handoff timed out', exit 5 | 407-handoff-late | `exit 5: {"status":"failed","reason":"reading the handoff timed out"}` |
| 9 | PASS | handoff timeout returns within the deadline plus grace | 407-handoff-late | `elapsed 1.181939755s` |
| 10 | PASS | handoff timed out: never read as a first rotation | 408-handoff-late-404 | `exit 5: {"status":"failed","reason":"reading the handoff timed out"}` |
| 11 | PASS | handoff read fails with 502: failed, not a first rotation | 409-handoff-fail-502 | `exit 5: {"status":"failed","reason":"the handoff could not be read"}` |
| 12 | PASS | handoff read rate-limited (403): failed, not a first rotation | 410-handoff-fail-403 | `exit 5: {"status":"failed","reason":"the handoff could not be read"}` |
| 13 | PASS | default-branch read fails: failed, 'the host's default branch could not be read', exit 5 | 411-default-branch-fail | `exit 5: {"status":"failed","reason":"the host's default branch could not be read"}` |
| 14 | PASS | no handoff read without a default branch | 411-default-branch-fail | `gh pr view 77 --repo acme/widgets --json state,body;gh api repos/acme/widgets --jq .default_branch;` |
| 15 | PASS | default-branch read 404 (host repo gone): failed, not a first rotation | 412-default-branch-404 | `exit 5: {"status":"failed","reason":"the host's default branch could not be read"}` |
| 16 | PASS | default-branch read past the deadline: failed, exit 5 | 413-default-branch-late | `exit 5: {"status":"failed","reason":"the host's default branch could not be read"}` |
| 17 | INFO | default-branch timeout reason does not say it timed out (header promises 'the reason says which') | 413-default-branch-late | `{"status":"failed","reason":"the host's default branch could not be read"}; elapsed 1.244323651s` |
| 18 | PASS | an invalid default-branch name: failed before any contents read | 414-default-branch-bad | `exit 5: {"status":"failed","reason":"the host's default branch is unreadable"}` |
| 19 | PASS | no contents read with an invalid branch | 414-default-branch-bad | `gh pr view 77 --repo acme/widgets --json state,body;gh api repos/acme/widgets --jq .default_branch;` |
| 20 | INFO | a null default branch: failed | 415-default-branch-empty | `stub-only: gh --jq printed the string null, which passes the branch validator; the read then went to ?ref=null. GitHub never returns a null default_branch for a readable repo` |
| 21 | PASS | run-facts read past the deadline: failed, 'reading the run's facts timed out' | 416-facts-late | `exit 5: {"status":"failed","reason":"reading the run's facts timed out"}` |
| 22 | PASS | run-facts exit 1 (no found record): none, exit 3 | 417-facts-none | `exit 3: {"status":"none","reason":"the run has no found record"}` |
| 23 | PASS | run-facts exit 2: failed, exit 5 | 418-facts-fail | `exit 5: {"status":"failed","reason":"the run's facts could not be read"}` |
| 24 | PASS | a record number the facts carry badly: failed, no gh call | 419-facts-bad-ref | `exit 5: {"status":"failed","reason":"the run's record number is unreadable"}` |
| 25 | PASS | no gh call on a bad record number | 419-facts-bad-ref | `coord-log run-facts --session s1;` |
| 26 | PASS | a scope name with a path in it: failed, no gh call | 420-facts-bad-name | `exit 5: {"status":"failed","reason":"the run's scope name is unreadable"}` |
| 27 | PASS | RECONCILE_READ_DEADLINE='0' falls back to 8s: a 2s read completes | 421-deadline-invalid-0 | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 28 | PASS | RECONCILE_READ_DEADLINE='61' falls back to 8s: a 2s read completes | 422-deadline-invalid-61 | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 29 | PASS | RECONCILE_READ_DEADLINE='abc' falls back to 8s: a 2s read completes | 423-deadline-invalid-abc | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 30 | PASS | RECONCILE_READ_DEADLINE='-1' falls back to 8s: a 2s read completes | 424-deadline-invalid--1 | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 31 | PASS | RECONCILE_READ_DEADLINE='' falls back to 8s: a 2s read completes | 425-deadline-invalid-empty | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 32 | PASS | RECONCILE_READ_DEADLINE=60 (upper bound) accepted | 426-deadline-60 | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 33 | PASS | gh leaves a grandchild holding stdout: reader still returns the record | 427-grandchild-holds-stdout | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 34 | PASS | grandchild holding stdout does not stall the reader past the deadline | 427-grandchild-holds-stdout | `elapsed .144144191s` |

### 7 report feed

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | discipline + handoff: header renders 'record and handoff' with the handoff date 2026-09-23 | 303-present | `Scope: discipline ci-health. Record written 2026-09-26T12:00:00Z; reconciled 2026-09-27T09:00:00Z. Rows marked as the previous rotation's are as it wrote them on 2026-09-23.` |
| 2 | PASS | report JSON: header.source 'record and handoff', per-holding source record/handoff | 303-present | `{"h":{"scope":"discipline ci-health","written":"2026-09-26T12:00:00Z","reconciled_at":"2026-09-27T09:00:00Z","source":"record and handoff","handoff_date":"2026-09-23","plugin_root":null},"s":["record","handoff"]}` |
| 3 | PASS | the handoff holding is marked 'row as written by the previous rotation'; the record's is not | 303-present | `- flaky-fix (Feature 2): executing; pull request not verified (not verified). Next: read again, then decide (inferred). Read not read; row as written by the previous rotation.` |
| 4 | PASS | the record's own holding carries no previous-rotation marker | 303-present | `- plugin-registry (Feature 2): executing; pull request not verified (not verified). Next: read again, then decide (inferred). Read not read.` |
| 5 | PASS | reasoning 'present' renders the reconcile/reasoning.md pointer | 303-present | `found` |
| 6 | PASS | deferrals from record and handoff both reach Undisposed deferrals | 303-present | `## Undisposed deferrals - flaky test (raised 2026-09-25T10:00Z): not now (verified by reading). - old gap (raised 2026-09-25T10:00Z): not now (verified by reading).  ` |
| 7 | PASS | an unparseable handoff row reaches Not verified with its reason and its raw text fenced | 315-bad-row | `- unparseable record row: handoff: Deferrals: a row with 5 cells, not 4~~  ~  \| old gap \| x \| not now \| 2026-09-25T10:00Z \|  \|~  ~` |
| 8 | PASS | roadmap: plain 'record' header, no predecessor section, the unparseable holding fenced with its reason | 201-grammar-sha | `Scope: roadmap plugin-system. Record written 2026-09-26T12:00:00Z; reconciled 2026-09-27T09:00:00Z.` |
| 9 | FAIL | a bad heading date: the report header renders the null handoff_date as the literal 'null' ("...as it wrote them on null.") | 321-bad-date | `Scope: discipline ci-health. Record written 2026-09-26T12:00:00Z; reconciled 2026-09-27T09:00:00Z. Rows marked as the previous rotation's are as it wrote them on null.` |
| 10 | PASS | bad heading date is listed under Not verified with its raw value fenced | 321-bad-date | `- unparseable record row: handoff: its heading date is not YYYY-MM-DD~~  ~  <b>soon</b>~` |
| 11 | PASS | first rotation: 'No reasoning was received', no handoff date clause | 301-absent-404 | `## Predecessor's reasoning~No reasoning was received from the previous rotation.~` |
| 12 | PASS | predecessor copy: reasoning not_recorded, no key, 'No reasoning was received' | 306-copy | `{"status":"not_recorded","key":null}` |
| 13 | INFO | Written-line spacing: the stray space reaches the report header | 215-written-spacing | `Scope: roadmap plugin-system. Record written  2026-09-26T12:00:00Z; reconciled 2026-09-27T09:00:00Z.` |

### 8 output hygiene

| # | Result | Scenario | Case | Evidence |
|---|---|---|---|---|
| 1 | PASS | ESC sequence appended to the Written line: read | 801-esc-in-written | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z\u001b[31m","source":"record","handoff_date":null},"holdings":[{"row":{"unit":...` |
| 2 | PASS | ESC inside a cell: that row set aside | 802-esc-in-cell | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 3 | PASS | DEL in a stray head line: read or refused | 803-del-in-head | `exit 4: {"status":"unreadable","reason":"the body isn't a coordinator record for this scope"}` |
| 4 | PASS | DEL inside a cell: row set aside | 804-del-in-row | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 5 | PASS | DEL in a non-row line between tables | 805-del-noncanon | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 6 | PASS | BEL/ESC in an added head line (not-canonical body echo path) | 806-bel-noncanon | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 7 | PASS | a cell that itself holds an absolute path (body content, not the tree's) is data | 807-path-in-cell | `exit 0: {"status":"found","scope":{"kind":"roadmap","name":"plugin-system","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record","handoff_date":null},"holdings":[{"row":{"unit":"Feature 2...` |
| 8 | PASS | ESC/DEL in the handoff heading date: handoff_date null, listed | 808-handoff-esc-heading | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":null},"holdings":[{"row":{"unit"...` |
| 9 | PASS | ESC in the reasoning: stdout JSON still found/present | 809-handoff-esc-reasoning | `exit 0: {"status":"found","scope":{"kind":"discipline","name":"ci-health","repo":"acme/widgets"},"record":{"written":"2026-09-26T12:00:00Z","source":"record and handoff","handoff_date":"2026-09-23"},"holdings":[{"row"...` |
| 10 | INFO | reasoning file keeps ESC bytes (verbatim by design; the file, not stdout) | 809-handoff-esc-reasoning | `0000000   T   h   e       f   l   a   k   y     033   [   1   m   j   o 0000020   b 033   [   0   m       i   s       t   i   m   i   n   g   . ` |
| 11 | PASS | parser internal failure (stderr with a path): failed read, exit 5, path not surfaced | 810-parser-internal-fail | `exit 5: {"status":"failed","reason":"the record could not be parsed"}` |
| 12 | PASS | record codec missing beside the script: a failed read (exit 5), not an unreadable record | 811-codec-missing | `exit 5: {"status":"failed","reason":"the record could not be parsed"}` |
| 13 | PASS | usage error exits 64 with the usage text | 812-usage-out | `Usage:   reconcile-read.sh --session S [--reasoning-out FILE] ` |
| 14 | PASS | no output (stdout, stderr, report) contains the tree, scratch or TMPDIR path, across all cases | 812-usage-out | `path hits 2, all 2 from the case that typed that path into a cell` |
| 15 | PASS | no output contains the home directory outside the deliberate cell | 812-usage-out | `ok` |
| 16 | FAIL | control characters reach the reader's JSON output | 812-usage-out | `raw=0 decoded=3: decoded:214-bare-cr decoded:801-esc-in-written decoded:808-handoff-esc-heading` |
