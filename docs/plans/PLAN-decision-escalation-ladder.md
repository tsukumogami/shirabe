---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: flag
split_rationale: |
  Hard Constraint. Steps 1 to 6 land in the koto repository and must be merged
  and shipped in a koto release before steps 8 to 13, in shirabe, can pass
  their checks against that release; koto and shirabe each release on their
  own cadence, and the dogfooding step can only run on released versions of
  both. Each step lands as its own pull request so those release gates can sit
  between them.
tracking_level: none
upstream: docs/designs/DESIGN-decision-escalation-ladder.md
milestone: "Decision Escalation Ladder"
step_count: 14
---

# PLAN: Decision Escalation Ladder

## Status

Active

## Scope Summary

A record-first escalation procedure. koto holds each question from the moment
it is raised to its answer, with a typed addressee, owner answers it has
verified, and reads that list what is open. shirabe gains a family of question
commands, a decide-first state in the worker templates, coordinator
enforcement in scripts, an undecided result from the decision skills, an
on-demand command and a guard on the question prompt. The work is dogfooded in
the tsukumogami organization before it is called done.

Steps 1 to 6 land in `tsukumogami/koto`. Steps 7 to 13 land in
`tsukumogami/shirabe`. Step 14 runs on released versions of both.

## Decomposition Strategy

Walking skeleton. Step 1 runs the whole life of a question inside koto on one
real input: one session raises a question addressed to `owner`, a read lists
it as open for `owner`, a second session records an answer aimed at it, the
open read no longer lists it, and the first session's next `koto next` reports
the answer. Every later step adds one behaviour on top of that path. First
come the rest of koto's rules: verification of the owner's answer, passing a
question up, precedence, precedent, retention. After a koto release comes what
shirabe builds on them: the question commands, the undecided decision, the
decide-first state, the coordinator's enforcement, the on-demand command. The
prompt guard needs nothing from koto and sits beside the koto steps. The last
step is the dogfooding run.

## Steps

### Step 1: A question raised in one session is listed as open for the owner, answered from another, and reported back to the asker

**Goal**: In the koto repository, cross the whole question path on one input: an `escalate` decision with the typed recipient `person:owner` recorded in session A is returned by a new open-by-person read, is answered by an `answer` entry recorded in an unrelated session B and aimed at A's question, stops reading as open, and is reported in a `questions` array on A's `koto next` until A records a decision citing the answer. koto's decision-record requirements and design are amended in the same pull request to say so.

The skeleton is deliberately thin. The answer is recorded by a session decider, because a person's answer needs the verification that step 2 adds. In this step any `answer` entry with outcome `answered` aimed at a question closes it; which answers count and which one governs are narrowed in steps 2 and 4. The `settled` and `withdrawn` outcomes, `readdress`, the new subject fields other than the typed recipient, the content area, the read by position, the precedent read, the wake ring and the retention changes are not part of this step.

Command names: this step uses `koto decisions record` as it exists, and proposes `koto decisions open --person <handle>` for the read and `koto decisions answer <raiser-session> <decision-id> --in <session> --text <text>` for the answer, modelled on `koto decisions reverse`. If the amended design settles on other names, the criteria and the check apply to those names and the worker's report says which were used.

**Acceptance Criteria**:

- [ ] `koto decisions record A --kind escalate --outcome escalated --subject question=q1 --subject text=... --subject recipient=person:owner --by session` exits 0, and `koto decisions show A <id>` returns the recipient as separate kind and handle values (`person`, `owner`), so a caller selects a person's questions with a field comparison and never splits or pattern-matches a string. `session:<name>` and `anchor:<name>` recipients read back the same way with their own kind.
- [ ] An `escalate` whose recipient has no type prefix, written before this change (for example `recipient=coord`), still appears in `koto decisions list <session> --format v1` and `koto decisions show` with the value it was stored with, marked as untyped, and is never returned by the open read for any person.
- [ ] `koto decisions open --person owner` exits 0 and prints JSON whose `questions` array holds A's question with its identity `<A's session id>/<decision id>`, the raising session's name, the question identifier and text, and the typed recipient. It takes no session argument, and it returns the question when A has no parent, no anchor, no `continues` relation and no other recorded link to any session.
- [ ] `koto decisions open --person someone-else` exits 0 with an empty `questions` array while A's question is open for `owner`.
- [ ] `koto decisions answer A <id> --in B --text "..." --by session` exits 0 and prints the new entry with kind `answer`, outcome `answered`, the question's session id and decision id as its target, the answer text, the decider and the run mode. Afterward exactly one new file exists under B's `ctx/koto/aimed/<A's session id>/`, and every file under A's session directory is byte-identical to what it was before the command (lock files aside).
- [ ] `koto decisions answer` aimed at a decision that does not exist, or at one whose kind is not `escalate`, exits 2 with a decision error naming the reason, and writes nothing in either session.
- [ ] With two questions q1 and q2 raised in A to `person:owner` and a third, q3, raised to `person:someone-else`, an answer aimed at q1 alone leaves `koto decisions open --person owner` returning exactly q2 and `koto decisions open --person someone-else` returning exactly q3. `koto next A` then reports q1 as answered with its own answer text and does not report q2 as answered, and a decision in A citing q1's answer leaves q2 as it was.
- [ ] An answer's target is the question's identity, the raiser's session id with the decision id, never the session's name: an answer that pairs A's session id with a decision id that exists only in another session exits 2 and writes nothing, and after A is removed and a new session named `A` is created, the earlier answer is not reported on the new A's `koto next` and closes none of its questions.
- [ ] `koto decisions answer ... --by person:owner` exits 2 with a message saying a person's answer cannot be recorded yet, and writes nothing. No binary built from this step can store a person's answer that was never verified.
- [ ] After the answer is recorded, `koto decisions open --person owner` exits 0 with an empty `questions` array. Open is computed when the read runs: no file in A or B records the question as closed other than the `answer` entry itself.
- [ ] `koto decisions list B --format v1` lists the `answer` entry as a readable decision, and `koto decisions reverse` aimed at it is refused with exit 2. A reversal recorded in the aimed area before this change still lists, shows and takes effect as it did.
- [ ] `koto next A`, run after the answer is recorded, exits with the code it would have had without the question, and its response carries a `questions` array with one element: the question's identity, its state (`answered`), and the answer in effect with its text, its decider and the session it was given in. The same array is present when A's workflow has already reached a terminal state, and on every repeat of `koto next A`.
- [ ] `koto next A` reports the answer without writing: A's and B's session directories are byte-identical before and after the call that only reports (no transition submitted), and the call makes no network request under the cloud backend.
- [ ] A session that continues A through koto's existing succession (`koto init <succ> --template work.md --continues A --supersede`, the form `tests/decisions_succession_test.rs` uses) gets the answer to A's question in the `questions` array of its own first `koto next`.
- [ ] Once A records a decision whose basis names the answer (`koto decisions record A --kind judgment --outcome settled --subject what=... --by session --basis B:<answer id>`), the next `koto next A` carries no `questions` key. A decision in A that does not cite the answer leaves the array in place.
- [ ] `koto next` on a session that holds no question prints a response byte-identical to the one the previous binary printed: `cargo test --test next_response_baseline` passes with its fixtures unchanged.
- [ ] Entries written by an older binary still read: `cargo test --test decisions_record_test --test decisions_reverse_test --test decisions_chain_test --test decisions_succession_test --test decisions_gate_pass_test --test decisions_cloud_test` passes with no expected value edited, and a session directory holding decisions written before this change lists the same entries with the same statuses under the new binary.
- [ ] A reader of `docs/prds/PRD-decision-record.md` finds, numbered after the existing requirements: the recipient of an `escalate` typed as a session, an anchor or a person, with an untyped recipient on an existing entry still readable; the `answer` kind with its `answered` outcome and its subject; that an answer is stored in the session it is given in and never in the asker's; the read of open questions for a person, which makes no chain test; open as something computed at read time; and the report on `koto next`, repeated until the asker cites the answer and present on an ended workflow. The statements that kinds, outcomes and subject fields are closed name `answer` and the typed recipient among what is allowed.
- [ ] A reader of `docs/designs/DESIGN-decision-record.md` finds the aimed area described as holding reversals and answers, the read-time rule this step builds for open, the command surface for the open read and the answer, the `questions` array of `koto next` with its fields and its no-write, no-network, never-blocking contract, and a note that a binary older than this change reads an `answer` entry as unreadable. Both documents say that a person's answer, precedence between answers, passing a question up and retention are not yet covered, so nobody reads the interim closing rule as final.
- [ ] `docs/guides/cli-usage.md` describes `koto decisions open`, `koto decisions answer` and the `questions` array with the same names and fields the binary prints.

**Check**: Build the binary from the branch (`cargo build`, then use `target/debug/koto`), and run the walkthrough below on the local backend in a scratch koto home, the way `tests/decisions_reverse_test.rs` sets one up: a temporary directory holding `home/`, `ws/` and `sessions/`, with `HOME` and `KOTO_HOME` set to `home/`, `KOTO_SESSIONS_BASE` set to `sessions/`, `KOTO_ANCHOR` and the `KOTO_SESSION_*` variables unset, and `ws/` as the working directory. Use the two-state template from that test file (state `work` accepting `go`, terminal state `done`), saved as `work.md`.

1. `koto init A --template work.md` and `koto init B --template work.md`. Both exit 0. The two sessions have no link to each other.
2. `koto decisions record A --kind escalate --outcome escalated --subject question=q1 --subject text="Postgres or SQLite for the cache?" --subject recipient=person:owner --by session`. Exit 0. Note the printed `id` and the session id at `decision.session.id`; together they are the question's identity.
3. `koto decisions open --person owner`. Exit 0, and `questions` has one element carrying that identity, session `A`, question `q1` and a recipient of kind `person` with handle `owner`.
4. Record a listing of every file under `sessions/A` with its SHA-256 (lock files aside).
5. `koto decisions answer A <id> --in B --text "SQLite" --by session`. Exit 0, kind `answer`, outcome `answered`. `ls sessions/B/ctx/koto/aimed/<A's session id>/` shows one file. Repeat the listing from point 4 and see it unchanged.
6. `koto decisions open --person owner`. Exit 0, `questions` is empty.
7. `koto next A`. The response carries `questions` with one element: the identity from point 2, state `answered`, and an answer with text `SQLite`, a session decider and session `B`. Run it a second time and see the same array.
8. `koto next A --with-data '{"go":"go"}'` to end the workflow, then `koto next A` again. The terminal response still carries the same `questions` array.
9. `koto decisions record A --kind judgment --outcome settled --subject what="use SQLite for the cache" --by session --basis B:<answer id>`. Exit 0.
10. `koto next A`. The response has no `questions` key.

11. In a fresh scratch home, repeat points 1 and 2 with two questions `q1` and `q2` to `person:owner` in A and a third, `q3`, to `person:someone-else` in B, then answer `q1` only. `koto decisions open --person owner` lists `q2` alone, `koto decisions open --person someone-else` lists `q3` alone, and `koto next A` shows `q1` answered and no answer for `q2`.

The same scenario runs as an integration test in the repository (`cargo test --test decisions_question_test`, or the name the pull request gives it), alongside `cargo test --test next_response_baseline` and the existing `decisions_*` tests, all passing. The worker's report quotes the output of points 3, 6, 7, 8, 10 and 11.

**Dependencies**: None

**Files**: `docs/prds/PRD-decision-record.md`, `docs/designs/DESIGN-decision-record.md`, `docs/guides/cli-usage.md`, `src/decisions/body.rs`, `src/decisions/read.rs`, `src/decisions/store.rs`, `src/decisions/mod.rs`, `src/cli/decisions.rs`, `src/cli/mod.rs`, `src/cli/next_types.rs`, `tests/decisions_question_test.rs`

### Step 2: An owner's answer is accepted only when a question-prompt call in that session showed the stored question and returned that answer

**Goal**: In the koto repository, a question's content is stored once in a write-once area capped at 16 KiB and hashed, and an `answer` by a person decider is recorded only after koto has checked it against the harness's record of the question-tool call in the session it is recorded in. koto takes the answer text from that call's result, marks the entry verified, and reads the mark as verified only in a session this machine created.

**Acceptance Criteria**:

Content

- [ ] Writing content of exactly 16,384 bytes for a question succeeds, and writing 16,385 bytes exits non-zero with a message that names the 16 KiB cap and leaves nothing stored.
- [ ] A second content write for the same question exits non-zero, whether the bytes are the same or different, and the content read returns the first write's bytes afterward. A write through the context store to a key under `koto/packets/` is refused the same way writes under the other decision areas are.
- [ ] The content read, run from a session other than the raiser's and given the question's identity `<raiser-session-id>/<decision-id>`, prints bytes identical to those written (compared with `cmp`, including any trailing newline or its absence).
- [ ] The `packet` value shown on the question's `escalate` entry equals the hash of the stored bytes, and an `escalate` whose `packet` does not match the content written for it is refused.

Verification of a person's answer

- [ ] With a fixture in which the call exists in the session, is the question tool, shows the stored `question` text and every option `label` at the named position, carries the question's identity at that position and has a result from the user, an `answer` by `person:owner` that hands in the pointer (harness session id, call id, position) exits 0, and the stored entry shows the pointer.
- [ ] The recorded answer text equals the text the call's result holds for that position when the caller passes different answer text, and when the caller passes none. A free-text reply in the result is stored verbatim.
- [ ] A fixture whose call asked three questions backs one accepted answer for each of positions 1, 2 and 3, each against its own stored question, and each entry holds the result text for its own position.
- [ ] A second `answer` citing a call and position that an earlier answer already cites exits non-zero and writes nothing, and the first entry is unchanged.
- [ ] Each of these exits non-zero, writes no entry, and prints a message naming the one check that failed: the pointer names no call in that session's record; the call named is not the question tool; the question at that position does not carry the identity of the question being answered; the result did not come from the user (a denied or errored call, or a result supplied by something other than the user's reply); the position is outside the questions the call asked.
- [ ] The comparison is of exact bytes, shown by one refusal case each, every one naming the question-text or the option check: the `question` text with one byte changed; with trailing whitespace added; with a difference in Unicode normalization only; one option `label` with one byte changed; with only its letter case changed; one option dropped; one option added; two options swapped. The fixture that differs from these in nothing is accepted.
- [ ] The record read is the one for the harness session the answer is recorded in, and no other: with a matching call that exists only in harness session X's record, an `answer` recorded in a koto session bound to harness session Y exits non-zero and writes nothing, whether the pointer names X or names Y with X's call id. No caller input chooses where koto looks for the record.
- [ ] A pointer is accepted only with a person decider: an `answer --by session` handing in a pointer that would pass every check exits non-zero and writes nothing, so a session's answer never carries the mark. The mark verifies the prompt and its reply; the person handle stays the caller's claim, and an entry recorded for a handle other than `owner` reads as that handle's answer, never the owner's.
- [ ] Two `answer` commands started together for the same call and position leave exactly one entry, and the other exits non-zero naming the reused call position; the test runs the pair at least 20 times.
- [ ] At least one accepted fixture and one result-not-from-the-user fixture (a denied call) are structural copies of real harness records captured in this workspace: every field name and nesting kept, every text value replaced by a marker string. The pull request names how they were captured, and a test fails when koto reads a field the captured structure does not have.
- [ ] An `answer` by a person decider with no pointer exits non-zero with a message saying a person's answer needs the question-prompt evidence. An `answer` by a session decider with no pointer is still accepted as step 1 left it.
- [ ] A harness record in a shape koto does not recognize (a missing or renamed field in the call or its result, a result with no per-question answer, a line that is not valid JSON where the call should be) is refused with a message saying the record's shape is not recognized, and nothing is written.
- [ ] No refusal message contains text from the harness's record. Each refusal fixture carries a distinctive marker string in its question text, option labels and result, and the marker appears in none of koto's output or error text; the message holds the check's name and the pointer the caller handed in, nothing more from the record.

The verified mark

- [ ] Reading an accepted entry (the single-entry read and the listing) shows the evidence with a verified mark whose source label is `observed`, while the person handle on the same entry stays labelled `handed`.
- [ ] No flag or field a caller can pass produces the mark: an `answer` whose input claims the entry is verified, with a pointer that fails a check, is refused, and one with no pointer is refused as above.
- [ ] Reading the same entry from a copy of the session that arrived through `koto session import` shows it as a remote session's answer and does not show it as verified, though the stored bytes of the entry are identical to the original's.
- [ ] Reading the entry from a session this machine obtained by a pull from shared storage shows the same remote reading, and reading it in the session on the machine that recorded it still shows verified after that session has synced to shared storage.
- [ ] Reading a verified entry does not open the harness's record: with the fixture record removed after the answer is accepted, the entry still reads verified in the session that recorded it.

Documents

- [ ] A reader of `docs/prds/PRD-decision-record.md` finds new requirements, numbered after R48, stating the content area with its cap and write-once rule, each check koto applies to a person's `answer`, that the answer text comes from the call's result, the verified mark with its `observed` label, and the remote reading for a session that arrived by import or by a pull, each with an acceptance criterion.
- [ ] A reader of `docs/designs/DESIGN-decision-record.md` finds `koto/packets/` named as a fourth write-once area, each field of the harness's record koto reads for the call and for its result, with that field's path in the captured record, where in a prompt position the question's identity is carried, how koto finds the record for a harness session, that an unrecognized shape is refused, and that the trust in the mark rests on the harness's record, whose format is observed and not a documented contract.

**Check**: Run from a checkout of the koto repository, with fixtures committed under `tests/fixtures/` and no live prompt at any point. The fixtures are small harness records built for the tests: one line holding a question-tool call with its `questions`, and one line holding that call's result. The accepted fixture and the denied-call fixture copy the structure of records captured from a real session, with every text value replaced by a marker string; the others are edits of those two. None holds text from a real session.

1. `cargo test --test decisions_packets_test` passes. Its cases cover the 16,384-byte accept, the 16,385-byte refusal, the second-write refusal with unchanged bytes, and the read from another session.
2. `cargo test --test decisions_person_answer_test` passes. Its cases are named for what they show: a matching call accepted; answer text taken from the result when the caller passed other text; three positions of one call each accepted once; and one refusal case each for a missing call, a call that is not the question tool, a call for another question, each of the eight byte-comparison cases, a call in another harness session's record, a session decider handing in a pointer, two answers racing on one call position, a result not from the user, a reused call position, an unrecognized record shape, and a person answer with no evidence. Each refusal case asserts the exit code, that the entry count in the answering session did not change, that the message names the check, and that the fixture's marker string is absent from the output.
3. `cargo test --test decisions_person_answer_remote_test` passes. It records an accepted answer, asserts the entry reads verified with the `observed` label, imports the session into a second workspace directory with `koto session import`, and asserts the same entry read there shows a remote session's answer and no verified reading. A second case does the same through the cloud test backend's pull.
4. By hand, in a temporary koto home, using the same fixture files: raise a question to `person:owner` as step 1 allows, write its content, and run the content read from a second session, piping it to `cmp` against the file written; `cmp` prints nothing and exits 0. Record the answer with the matching fixture's pointer while passing an answer text of `something else`; the command exits 0, and the entry read back shows the fixture result's text, not `something else`, with the verified mark labelled `observed`. Record the answer again with the same pointer; it exits non-zero and the message names the reused call position.
5. Still by hand, point the same command at the fixture whose question text differs by one byte; it exits non-zero, the message names the question-text check, and `koto decisions list` for the session shows no new entry.
6. `cargo test` and `go test ./...` in `test/functional` pass, so the existing decision record behaviour is unchanged.
7. Open `docs/prds/PRD-decision-record.md` and `docs/designs/DESIGN-decision-record.md` and find the passages the two document criteria name.

This step's amended design settles three things the upstream design leaves to koto: where in a prompt position the question's identity is carried, how koto finds the harness's record for a session id, and how a session obtained by a pull from shared storage is told apart from one created here (koto marks an imported session today and has no equivalent mark for a pulled one).

**Dependencies**: Step 1

**Files**: `src/decisions/mod.rs`, `src/decisions/store.rs`, `src/decisions/body.rs`, `src/decisions/decider.rs`, `src/decisions/read.rs`, a new module under `src/decisions/` for the harness-record check, `src/cli/decisions.rs`, `src/session/links.rs`, `src/session/import_links.rs`, `tests/decisions_packets_test.rs`, `tests/decisions_person_answer_test.rs`, `tests/decisions_person_answer_remote_test.rs`, `tests/fixtures/`, `test/functional/features/decisions.feature`, `docs/prds/PRD-decision-record.md`, `docs/designs/DESIGN-decision-record.md`

### Step 3: A passed-up question is listed once under every coordinator above its raiser, with who it now waits on

In koto: the `readdress` kind, the addressee history, and the open read by position return a passed-up question once, naming its current addressee.

### Step 4: The owner's answer outranks a session's, and a raiser can only withdraw its question or settle it from an answer of the owner's

In koto, on step 3's addressee history: precedence among answers, the settle and withdraw rules, needs that their raiser cannot settle, and the limit of twenty open questions addressed to a person.

### Step 5: A session finds the owner's earlier answers by subject, and attempts and provisional decisions can be listed

In koto: the precedent read by subject label, one question's whole history, and the `state` and `result` fields on `judgment` with their listings.

### Step 6: A session holding an open question survives cleanup, and recording an answer wakes the asker

In koto: the two retention rules with the amendment to koto's retention design, the cleanup refusal without force, the wake-file ring, and the five-second bound on every open read at 1,000 sessions, followed by a koto release carrying steps 1 to 6.

### Step 7: A question prompt opened in a turn no person typed is denied

In shirabe: the pre-tool guard on the question tool, starting with a capture of what the hooks and the harness record report for each way a turn can start.

### Step 8: A question raised with shirabe is shown identically after the session restarts, and answered through the prompt as the owner

In shirabe, on the released koto: the `shirabe question` commands for raising, listing, rendering and answering, the shared procedure reference, and the raised koto floor.

### Step 9: A structured decision hands a question back undecided instead of assuming an answer

In shirabe: the undecided result of `/decision`, the lightweight protocol's third outcome, the cheap-or-costly test for an unattended run, `/design` and `/explore` raising the question handed back, and the decision record superseding the earlier one on who owns an intent change.

### Step 10: A `/work-on` run about to stop at a covered exit must record an attempt, and ends waiting on the question it raised

In shirabe: the decide-first state, its gate and the waiting terminal in the `/work-on` template, with a run that reaches no covered exit unchanged.

### Step 11: `/execute` parks an issue on a question and takes the next one, and a `/scope` hop waits on the question it raised

In shirabe: the decide-first state in the `/execute` and `/scope` templates, and resuming a waiting run from the answer.

### Step 12: A coordinator cannot pass a question up without an attempt, presents four at a time, and reads a rule as the owner's only from a verified standing answer

In shirabe: the coordinator's script enforcement, entries held by identity, release by impact, the brief's reporting text, the standing-rule classifier's evidence test with the amendments to the standing-rule provenance design and its plan, and the superseded passages.

### Step 13: `/shirabe:pending` lists and resolves what is pending in any session, including one no workflow drives

In shirabe: the on-demand command and the unseen-answers listing, followed by a shirabe release carrying steps 7 to 13.

### Step 14: The dogfooding run shows the five events on released versions

In the tsukumogami organization, on real work: one chain with a worker under a manager and a director plus a solo unattended worker, with the record of each event attached and every finding fixed or filed.

## Implementation Sequence

The steps run in number order, with three places where two can run beside each
other: step 7 beside any of steps 1 to 6, since the prompt guard needs nothing
from koto; steps 2 and 3 once step 1 has landed; and steps 10 and 12 once
step 9 has landed.

Two releases gate the sequence. Step 6 ends with a koto release that carries
steps 1 to 6, and step 8 starts on that release. Step 13 ends with a shirabe
release that carries steps 7 to 13, and step 14 runs on both releases.

Step 4 builds on both step 2 and step 3. Step 13 comes after steps 7, 11 and
12, so the shirabe release holds the guard and the worker templates as well as
the coordinator's changes.
