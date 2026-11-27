# The question commands

`shirabe question` raises, lists, renders and answers a question a session
can't settle on its own evidence, and records the attempt to decide that comes
before it. koto keeps the record: each question is an
`escalate` decision with a typed recipient, and its content is stored once
beside it. shirabe checks what a question contains and how it's shown. The
procedure a session follows around these commands is in
`references/question-procedure.md`.

The commands need koto 0.42.0 or later on `PATH`. Every subcommand prints one
JSON object on standard output and, on failure, a one-line message on
standard error.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | done |
| 1 | shirabe refused the input before any koto write |
| 2 | a usage error |
| 3 | koto is missing, or below the minimum (the message names both versions) |
| 4 | koto refused: its `code`, `field` and the `check` it names are passed through |
| 5 | a question that can't be presented, or an answer that doesn't read as verified |
| 6 | a koto call ran past its time bound and was stopped (`code: koto_timeout`) |
| 7 | `answer`: koto recorded the owner's answer, but reading it back failed |
| 8 | `render`: the question given is no longer open |

A failure prints `{"v":1,"error":{"exit","code","field","check","message",...}}`,
with `field` and `check` present only when known.

Every koto call is bounded at 10 seconds. A call still running then, most
likely blocked on a store lock, is stopped; the command exits 6 with a message
naming the koto command and writes nothing further. The one exception is
`raise`: once the `escalate` is recorded, a timeout on the content write or
its read-back withdraws the `escalate`, as a failed content write does, and
the error carries `withdrawn`.

A read that koto doesn't answer stops the whole command at the first one: the
command exits 6 on a timeout, or with the failure's own code (4) on any other
koto failure, and prints no listing. It never reads that as a question with
missing content, an unrecorded origin or an unheld dependency. Only koto's own
not-found answer (`decision_not_found`) puts a question under `incomplete`.

A session or anchor name given to any subcommand (`--in`, `--at`, the session
in `--attempt`) must have koto's session-name shape: a letter or digit first,
then letters, digits, `.`, `_` and `-`. Anything else exits 1 before any koto
call, so a value such as `--help` never reaches koto as an option. Every koto
call puts its options first, caller values as `--option=value`, and its
positionals after `--`.

## `shirabe question raise`

```text
shirabe question raise --in <session> --content <file|-> [--to <recipient>] [--attempt <id>] [--state <state>:<visit>]
```

- `--in`: the koto session raising the question.
- `--content`: the content file, or `-` for standard input.
- `--to`: `session:<name>`, `anchor:<name>` or `person:owner`; nothing else is
  taken. Without it the recipient comes from `koto session origin`: the
  dispatching session or anchor, `person:owner` for a session nothing
  dispatched, and `person:owner` with `unlinked: true` for a session whose
  origin reads unrecorded. A need always goes to `person:owner`.
- `--attempt`: the undecided attempt the question rests on, `<id>` or
  `<session>:<id>`. A decision question is refused without one, with one that
  names no attempt in the session's run, and with one whose `result` isn't
  `undecided`. The `escalate` names it in its `basis`. A need takes none.
- `--state`: stored as the question's `state`.

Output fields: `identity` (`<raiser session id>/<decision id>`), `session`,
`id`, `recipient`, `unlinked`, `need`, `label`, `packet` (`sha256:<hex>` of the
stored bytes), `bytes`, `prompt_header`, and `state`, `attempt` and
`depends_on` when given.

What's refused with exit 1, before koto is called to write: a missing or empty
part; fewer than two or more than four options; an option without a `label` or
`reason`; an unknown key; a file that isn't JSON; stored content over 16 KiB
(16,384 bytes); a label over 128 bytes; a control character in the context,
the problem, the question or an option label; anything over the prompt limits
in `references/decision-presentation.md`; a standing mark on content that
would need shortening; text shaped like a secret, from the list in
`scripts/lib/secret-shapes.ere`, the same list the public-content check
keeps (the matched text is never printed); a
`depends_on` naming no question, or one whose chain comes back round; both
`options` and a need.

The writes come in koto's order: the `escalate` first, then the content, then
a read-back. When the content write fails, `raise` withdraws the `escalate` it
just recorded, with a reason naming the failed write, and exits 4.

## `shirabe question pending`

```text
shirabe question pending --in <session> [--person owner | --at <session-or-anchor>]
```

With neither flag it lists both sets, each question once. It reads only: it
runs one `koto decisions open --person` and one `koto decisions open --at`, and
never `koto next`.

Output: `questions`, `held`, `incomplete` and `answered`. Each question
carries `identity`, `session` (the raiser), `id`, `question`, `label`, `need`,
`waiting` (the count of waiting work items), `raised` and `age_seconds`,
`recipient` (as raised), `addressee` (who it waits on now), `relation`,
`for_owner`, `other_person` (waits on a person other than `owner`), `standing`,
`unlinked`, `depends_on`, `held` and `stored`. The order is most waiting work
items first, then oldest, then identity compared as bytes. A question whose
`depends_on` names an open question is under `held`.

`incomplete` lists a question whose `escalate` carries a `packet` with no
content behind it, or content that doesn't hash to it, with the `koto` command
that withdraws it. `answered` lists, with koto's answer entry unchanged
(`text`, `decider`, `session`, `reading`), each answer to a question this
session raised and each owner answer given at or below it, until a decision in
its run cites the answer.

## `shirabe question render`

```text
shirabe question render <identity>... [--in <session>]
shirabe question render --person owner
```

Output: `prompts`, `requests` and `held`. Each prompt holds `questions`, the
question tool's input as it stands, `identities`, and `text`, a plain rendering
for a session that can't open a prompt. In `questions`, `header` is koto's
`prompt_header`, `question` is the stored composed text (context, problem and
question as three paragraphs), and the option labels are the stored labels in
stored order. Each `description` carries the option's reason, the first opening
with `Recommended.` and every marked option with `This answer sets a standing
rule.` A prompt holds at most four questions; a need is never in one and comes
under `requests`.

With `--person owner` the output also has `incomplete`: each open question
for the owner that can't be presented (raised with no stored content, content
missing, or content that doesn't hash to its `packet`), with its `identity`
and `reason`, as `pending` lists them.

The output depends on the stored bytes and the header only, so it's the same
across runs, sessions, directories and environments, and after the raising
session has ended, and the tests check each of those. Rendering after a
compaction, or after a successor replaces the raising session, rests on the
same inputs, but no automated case covers it; the plan's dogfooding step
exercises both.

A question given by identity that is no longer open (answered, settled or
withdrawn) exits 8 with `state` naming how it closed, since presenting it
would ask the owner again. A question whose content is missing or doesn't
hash to its `packet` exits 5 and prints nothing from the content.

## `shirabe question answer`

```text
shirabe question answer <identity> --in <session> [--call <call-id> --position <n>]
```

It takes no answer text: the answer is what the owner chose in the prompt.
`--text`, `--answer` and text on standard input are usage errors. The handle
is `owner`, with no flag to change it. Without `--call`, it looks in the
record of the harness session running the command (`CLAUDE_CODE_SESSION_ID`,
under `.claude/projects/` in the account's home) for the latest question-tool
call whose question at some position carries the question's `prompt_header`.
It reads structured fields only and prints nothing from the record.

It runs `koto decisions answer <raiser> <id> --in <session> --by person:owner
--prompt <harness session>/<call>/<position>` and reads the entry back. The
answer is recorded in the session the owner answered in, so `--in` names
that session; koto refuses `--in` naming the session that raised the
question.
Output: `identity`, `session`, `id`, `prompt`, `reading` (as koto prints it)
and `text`.

Refusals:

- exit 3 first, whatever else is wrong, when koto is missing or below the
  minimum; a pre-release of the minimum (`0.42.0-rc1`) doesn't meet it;
- exit 1 before any other koto call in an unattended run
  (`KOTO_RUN_MODE=unattended` or `CLAUDE_CODE_SESSION_ATTENDED=0`). It reads
  those two environment variables only: it doesn't read koto's recorded run
  mode, and a skill started with `--auto` sets neither, so this check can't see
  it. koto's own reading of the run mode still applies;
- exit 4 with `check: call` when no call carries the header, and with
  `check: record` when `CLAUDE_CONFIG_DIR` is set, since koto reads the record
  only from the default place. Either message says the question is still open
  and how a relayed claim is recorded instead;
- exit 4 with koto's `prompt_unverified` and the check that failed:
  `call`, `question-text`, `options`, `result`, `call-position-reused`, `time`,
  `session`, `sidechain`, `identity` and the others koto names;
- exit 5 when the entry doesn't read `verified`, printing koto's `reading`;
- exit 7 when koto recorded the answer but reading the entry back failed. The
  error names the `entry`; don't answer again, since the same call and
  position would fail koto's `call-position-reused` check. Read the entry with
  `koto decisions show`.

### What koto verifies, and its limits

koto marks a person's answer `verified` only on the host that recorded it,
from the session that recorded it. Read anywhere else (another host, a copied
session directory, an import) it reads `a remote session's answer` and carries
no authority of the owner there. The check covers what the harness record
shows: the call, its question text and labels, the reply and that a person
gave it in that session. It can't show that the person at the keyboard was the
owner.

The harness session in the pointer comes from the environment
(`CLAUDE_CODE_SESSION_ID`), and `answer` takes it as given. It doesn't check
that the variable names the session it runs in; koto's own `session` check is
what catches a pointer into another session's record.

The 8,192-byte bound on a question's text is an estimate. The length the
question tool accepts hasn't been measured yet (see
`references/decision-presentation.md`).

## `shirabe question attempt`

```text
shirabe question attempt --in <session> --what <text> --result <decided|undecided|provisional> [--state <state>:<visit>] [--chosen <text>] [--undo <cheap|costly> --undo-reason <text>] [--ground <ground>] [--basis <session>:<id>]...
```

It records what came of an attempt to decide, as one koto `judgment` by the
session: `koto decisions record --kind judgment --outcome settled` with the
subject `what`, `result` and, when given, `state`. An undecided attempt is
what `raise --attempt` rests a question on; `raise` refuses a decided or a
provisional one.

- `--in`: the session the attempt is recorded in, the one that will raise the
  question if there is one.
- `--what`: what was being decided.
- `--result`: `decided`, `undecided` or `provisional`. Missing, it's a usage
  error (exit 2).
- `--state`: the workflow state and its visit, such as `implement:1`. A
  session with no workflow state leaves it out, and the attempt reads back
  with a null `state`.
- `--chosen`: the option chosen. Required with `decided` and `provisional`,
  refused with `undecided`.
- `--undo` and `--undo-reason`: the cheap-or-costly test
  (`references/question-procedure.md`) and what undoing the choice would take.
  Each needs the other.
- `--ground`: why the session may not settle a question it could undo
  cheaply. One of `contradicts-answer`, `changes-scope`, `outward-facing` or
  `reserved-step`, and only with `undecided`.
- `--basis`: an earlier decision this one rests on, such as the answer it
  follows. Repeatable.

The chosen option, the undo judgment with its reason, and the ground go into
the entry's reason, in that order: `chosen: <text>; undo: <cheap|costly>:
<reason>; ground: <ground>`. koto's judgment subject has no field for them, so
`koto decisions show` prints them in `reason`, not in `subject`. A `;` in
`--chosen` or `--undo-reason` is refused, so a value can't read as a second
part (`--chosen "A; ground: reserved-step"`).

The run mode decides what's taken. It's read from the environment, as `answer`
reads it: `KOTO_RUN_MODE=unattended` or `CLAUDE_CODE_SESSION_ATTENDED=0` reads
as unattended, `KOTO_RUN_MODE=attended` or `CLAUDE_CODE_SESSION_ATTENDED=1` as
attended, and anything else as unknown. koto 0.42.0 records a run mode per
entry but keeps none per session for a command to read, and a skill started
with `--auto` sets neither variable, so this check can't see that flag.

- `provisional` is taken only in a session that reads as unattended, with
  `--undo cheap`, an `--undo-reason` and `--chosen`. `--undo costly` is refused
  (a costly choice is raised, not decided), as is an attended or unknown run
  mode (an attended run asks the person), and so is a session whose two
  variables name opposite modes (`KOTO_RUN_MODE=unattended` with
  `CLAUDE_CODE_SESSION_ATTENDED=1`, or `attended` with `0`); the refusal
  names both values.
- `undecided` in a session that reads as unattended needs `--undo`. With
  `--undo cheap` it also needs a `--ground`; without one it's refused, since a
  cheap choice is decided provisionally. In an attended session `--undo` is
  optional.
- A definite run mode is passed to koto with `--run-mode`, so the entry
  carries it.

What this doesn't enforce: the run mode and the cheap-or-costly judgment are
the session's own declarations, and a caller can set either variable for a
single call. The command checks that they're consistent with the result, not
that they're true. Nothing but the procedure in
`references/question-procedure.md` stops a session recording `decided` for a
matter it should have raised.

Output: `v`, `id`, `session`, `attempt` (`<session>:<id>`, the form
`raise --attempt` and `--basis` take), `what`, `result`, `state`, `run_mode`
(`attended`, `unattended` or `unknown`), `chosen`, `undo`, `undo_reason`,
`ground`, `basis` and `reason`, each null or empty when not given.

Refusals:

- exit 3 when koto is missing or below the minimum;
- exit 1, naming the field, before any koto call: an empty or multi-line
  `--what`, `--chosen` or `--undo-reason`; a `;` in `--chosen` or
  `--undo-reason`; a `--result`, `--state`, `--undo`,
  `--ground` or `--basis` outside its form; and each rule above, with `field`
  `chosen`, `undo`, `undo_reason`, `ground` or `run_mode`;
- exit 4 when koto refuses the record, with its `code` passed through.

A provisional attempt is listed for review and isn't a question:
`koto decisions attempts --in <session> --result provisional --awaiting-review`
reads it with review `awaiting`, and `koto decisions open` doesn't list it.

## The stored content

One JSON document, compact, keys in this order:

```text
context, problem, ask, question, standing?,
options[{label, reason, standing?}]   (a decision question)
  | need, needed                      (a need)
ground, waiting, label, depends_on?
```

`ask` is the question as the raiser wrote it; `question` is the composed
prompt text, `context`, `problem` and `ask` joined by one blank line. koto
compares the composed text and the labels with the prompt when it records the
owner's answer. The input takes the same keys, with `question` holding the
bare question and no `ask`, in any order and indentation; the same content
always stores the same bytes.

The committed golden fixtures under `crates/shirabe/tests/fixtures/question/`
(`golden-input.json`, `golden-stored.json`, `golden-packet.txt`,
`golden-render.json`) pin the format. A change to any of them is a format
change that breaks restoring every question already stored.
