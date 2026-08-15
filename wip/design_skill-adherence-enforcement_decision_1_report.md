# Decision 1 — Evidence admissibility: what state does the conformance determination read?

Tier 3 (standard). Decision-researcher report for `/design` Phase 2,
`skill-adherence-enforcement`.

Everything marked **[confirmed]** was read from source or reproduced against live
state on this machine during this decision. **[inferred]** means reasoned from
confirmed facts without a direct test.

## Question

What state does the conformance determination read, and what makes that state
admissible under R1's rule that the determination be derived only from state no
tool call issued by the evaluated session produced?

Two sub-questions carry it: does the koto `/workflows` record satisfy that rule,
and what evidence bounds R2's every-issue delegation bar?

---

## Two terms have to be pinned before the evidence makes sense

### "Session" in R2 means koto session, not Claude Code session

R2 defines delegated as "every issue whose implementation the run produced was
implemented by a session other than the orchestrator." Read as *operating-system
or Claude Code session*, that requirement is unsatisfiable by the sanctioned
workflow, because the sanctioned workflow does not create one.

`references/parent-skill-pattern.md:396-403` states the dispatch mechanism
directly: "The parent invokes the child via the **Skill tool**, called inline
from the parent's own agent context... the child runs in the parent's agent
context." `skills/execute/SKILL.md:388` names the same binding for `/execute`'s
per-issue children. koto's own spawn primitive is a logging stub
(`public/koto/src/engine/respawn.rs:165-180`), so nothing launches a process
either. **[confirmed]**

Reproduced: for the live run `execute-calendar-cli-only`, the parent and its four
children all resolve to the single Claude Code session
`9dbd4bf0-a2d9-46f4-88c7-9d63484987d6`; that session's project directory holds
two `koto-*.json` records, neither of which is a child of the execute run.
**[confirmed]**

So delegation is realized as **one distinct koto session per issue, driven to
terminal**, and that is the unit the determination must count. This matches the
PRD's own language for the field incidents — incident 1's "no per-issue child
ran", incident 2's "implemented six issues inline" — both of which describe
missing koto child sessions, not missing processes.

### Two id namespaces, and why they are easy to conflate

There are two unrelated identifiers in play, and reading one as the other
produces a plausible but wrong conclusion in either direction. Both are confirmed
from `public/koto/src/workflows_surface/materialize.rs:262-292`:

- **Claude Code session id** — read from the `CLAUDE_CODE_SESSION_ID` environment
  variable and resolved to a project directory by locating `<sid>.jsonl`. It is
  the **directory** component of the path:
  `~/.claude/projects/<encoded-cwd>/<claude-sid>/workflows/`.
- **koto session id** — a UUID koto mints per koto session and stores in the state
  header's `session_id` field. It is the **filename** component:
  `koto-<koto-uuid>.json`.

Worked example from the live `execute-calendar-cli-only` run. **[confirmed]**

```
parent koto header  session_id = b78e9f2e-d9da-4193-9d9f-0d2458d1ac8d  template_name = execute
child  koto header  session_id = bb804b4e-81b0-4ea7-ba96-81a616a78b36  template_name = work-on
                                 parent_workflow = execute-calendar-cli-only

both records live under ONE Claude Code session directory:
  ~/.claude/projects/-home-...-options-sweep-cli-read/9dbd4bf0-a2d9-46f4-88c7-9d63484987d6/
```

`b78e9f2e` and `bb804b4e` differ because every koto session gets its own UUID;
that is true by construction and carries no information about Claude Code
sessions. The decisive test is whether either is a Claude Code session id, and
neither is: `find ~/.claude/projects -maxdepth 2 -name 'b78e9f2e*' -o -name
'bb804b4e*'` returns nothing, and no transcript exists under either name.
**[confirmed]** Consistent with this, no `<parent>.o-<slug>` workflow name appears
anywhere in the 67 workflow records on this machine — children never get their own
Claude Code session directory, because they never get their own Claude Code
session.

**Which mechanism `spawn_and_await` uses, stated plainly:** neither a separate
Claude Code session nor the Agent tool. koto materializes a child *record* and the
same agent, in the same Claude Code session, drives that child's `work-on` state
machine inline via the Skill tool. The consequence for this decision is that the
`/workflows` record — keyed by Claude Code session id — genuinely **cannot**
separate orchestrator work from child work, and the check below never asks it to.
It uses that record for registration only. Delegation is measured entirely from
the koto-session namespace, where parent and child are distinct by construction
and linked by `parent_workflow` (live) and by the `<parent>.` name prefix (durable).

The Agent-tool caveat is real but does not bite here: if a future revision of
`/execute` delegated issues via the Agent tool instead of via koto child sessions,
those children would share the parent's Claude Code session id *and* leave no koto
child session, so they would be invisible to both halves of this check. That is a
constraint on future changes to `spawn_and_await`, not a limitation of the current
evidence.

### "Produced" in R1 means authored, not caused

Read strictly, R1 is unsatisfiable. Every artifact on the machine is downstream of
some tool call the session issued: the koto record exists because the agent ran
`koto init`; the git history exists because the agent ran `git commit`; the branch
exists because the agent created it. A causal reading admits nothing and the
requirement dissolves.

Read loosely — "anything the agent didn't literally hand-write" — the second
incident's task payload becomes admissible, because `plan-to-tasks.sh` computed
it from the PLAN rather than the agent inventing it. That reading defeats the
discriminator the PRD was written to protect (Decisions and Trade-offs,
"Invocation is not the unit of measurement").

The reading that survives both is **constitutive**: a piece of state is
admissible as evidence of an act when

1. its existence is entailed by the occurrence of that act — it cannot be
   produced by any cheaper route than performing the act, and
2. its content is determined by a process other than the evaluated agent, so the
   agent supplies inputs but does not choose what gets recorded.

Under this test the discriminator is not *who caused the write* but *what the
write is evidence of*.

- The koto `/workflows` record passes. It is written by `materialize.rs` from
  inside `LocalBackend::append_event`, "the single low-level commit funnel every
  state mutation passes through", so it exists if and only if a koto state commit
  occurred. Its fields are koto's, rendered from the compiled template. The
  cheapest way for an agent to produce one is to actually run `koto init` — which
  *is* registering. **[confirmed]**
- The `plan-to-tasks.sh` payload fails, and fails on clause 1, not clause 2. Its
  content is computed rather than invented, but the act it is constitutive of is
  "ran a script against the PLAN", which is not the act under determination. The
  script's own header states its whole interface: it "Reads a PLAN.md path and
  outputs a JSON array of koto task-entry objects on stdout", and it takes no
  session argument. It is structurally incapable of attesting to registration
  because it does not know what to register against. **[confirmed]**

The useful test to carry into the DESIGN: **an admissible record is one whose
cheapest forgery is compliance.**

A corollary worth stating explicitly, because it is easy to over-apply R1: the
rule constrains the *evaluated* session, not the checker. The checker may run
whatever scripts it likes — including `plan-to-tasks.sh` — because those are its
own tool calls, not the evaluated session's. And session-produced state may be
read *monotonically against* conformance: evidence that can only lower a verdict
never manufactures a false pass. Both moves are used below.

---

## Options

### Option A — `test -d ~/.koto/sessions/<name>`

Rejected on evidence, not taste. koto deletes the session directory on reaching a
terminal state. Verified: `execute-feature-23-google-cli-access` reached
`completed` on 2026-08-03 with eight completed children, and
`~/.koto/sessions/execute-feature-23-google-cli-access` does not exist.
**[confirmed]** The check is false for every successful run — it inverts the
signal.

### Option B — a git or CI marker on the PR

The `/execute` template's `pr_finalization` writes a title of `feat: $PLAN_SLUG`
and a body of prose plus a per-child outcome table; there is no session id,
template hash, koto marker, or commit trailer. The only in-repo artifact,
`wip/execute_<topic>_state.md`, is agent-authored prose and is `git rm`'d by the
finalization cascade before the PR flips ready. **[confirmed]** A CI check cannot
distinguish a koto-driven PR from a hand-rolled one, and adding a marker requires
widening `/execute`'s closed write-target set — which the PRD puts out of scope
("Making the conformance record travel off the machine").

### Option C — `~/.claude/projects/<encoded-cwd>/<sid>/workflows/koto-*.json` alone

The strongest single artifact, and the right primary signal, but insufficient on
its own for three reasons found empirically:

- **It carries no delegation ledger.** I dumped the full record for
  `execute-calendar-cli-only`: top-level keys are `id, name, status, startTime,
  phases, workflowProgress, koto`, and `workflowProgress` holds only the parent's
  own 12 phases and 3 agent entries. No child appears. **[confirmed]**
- **It carries no PLAN binding.** `PLAN_DOC` does occur in execute-template
  records exactly once — as the *unsubstituted placeholder* `{{PLAN_DOC}}` inside
  a `promptPreview` string. The real plan path lives only in the state log's
  `workflow_initialized` event, which cleanup deletes. **[confirmed]** The plan
  binding survives only as the session-name convention `execute-<plan-slug>`
  (`skills/execute/SKILL.md:150`), and names are free-form — a record named
  `demo-before` runs the `execute` template. **[confirmed]**
- **Its absence does not prove non-registration.** See the version-rollout finding
  below.

### Option D — the koto terminal index as the delegation ledger

`~/.koto/_terminal_index.jsonl` is append-only, four fields, written by koto on
every terminal transition (`public/koto/src/engine/terminal_index.rs:65-97`).
133 entries on this machine, 51 of them children named `<parent>.o-<slug>`, going
back to 2026-06-07 — five weeks earlier than the oldest `/workflows` record.
**[confirmed]** For the completed 8-issue run, all eight children plus the parent
are present, with the parent's `terminal_at` following the last child's.

Critically, it distinguishes **materialized** from **driven**. koto materializes a
child at `spawn_and_await` — the child gets a session directory and a state log —
but that is not delegation. `execute-calendar-cli-only`'s four children each have
a three-line state log (header, `workflow_initialized`, `transitioned → entry`)
and no terminal-index entry, because the agent never drove them. **[confirmed]**
An agent that materialized children and then implemented the issues inline would
pass a "do child directories exist" check and fails this one.

### Option E — the conjunction (chosen)

Registration from Option C, delegation from Option D, denominator recomputed from
the PLAN by the checker, plus an arming witness (below) to make absence
affirmative.

---

## Chosen option

**Read three koto-authored surfaces plus the PLAN, and require all four to agree.**

| Element | Surface | Who writes it | Survives cleanup |
|---|---|---|---|
| Registered | `~/.claude/projects/<enc-cwd>/<sid>/workflows/koto-*.json`, `.name` prefix `execute `, `.koto.workflow == execute-<plan-slug>` | koto, from `append_event` | yes |
| Delegated (numerator) | `~/.koto/_terminal_index.jsonl`, entries with prefix `<parent>.` | koto, on terminal transition | yes |
| Run finished | same index, exact entry for `<parent>` | koto | yes |
| Expected issues (denominator) | the PLAN document, re-parsed by the checker | the planning session, not the evaluated one | n/a |
| Recorder was live | arming component's own log | the enforcement hook | yes |

Repo scoping comes from the encoded project directory. The encoding replaces every
non-alphanumeric character with `-`, so a worktree under `.claude/worktrees/`
encodes as `<repo-encoding>--claude-worktrees-<name>` and prefix-matches its
repo. **[inferred from four observed directory names; verified as a prefix match
for two independent repos.]** The freshest-by-mtime rule from the research lead is
preserved for the mid-session-cwd-change case, but scoped to project directories
matching the repo, which closes a false positive where a session drives an execute
loop in repo A and hand-implements a plan in repo B.

### The finding that forced a fifth element

Absence of a registration record is *not*, on its own, evidence of
non-registration — and the machine proves it. The completed 8-child run
`execute-feature-23-google-cli-access` has no `/workflows` record at all. I traced
why: koto defaulted `workflows.native` on in commit `6fe4902`, dated 2026-07-18,
but the record only started appearing in that workspace on 2026-08-04. Nine
Claude sessions in the commuter workspace dated 2026-08-02/03 have no `workflows`
directory; three dated 2026-08-04 have one. The run predates the binary upgrade on
that workspace. **[confirmed]**

A checker that treats absence as non-conformance would have reported a
fully-delegated run as `non-conforming`. That is the exact failure R9 exists to
prevent, and it means the determination needs a witness that *the recorder was
running while the session ran*.

My first attempt used a weaker corroborator — "does a koto session for this plan
exist anywhere" — and it failed under test: with an unrelated `execute-demo`
session present, an inline session that never registered got `indeterminate`
instead of the `non-conforming` AC2 and AC3 demand. The correct witness is the
arming component itself (Decision 2's territory): it observes the session's tool
calls in-band, so its entry proves the enforcement stack — and therefore koto's
recording path — was live at the time. This is an **interface requirement the
determination places on the arming design**: the armer must append a durable,
per-session record (`claude_session_id`, `armed_at`, `contract_version`,
`repo_root`). Without it, an unregistered session is only reportable as
`indeterminate`, which fails AC2 and AC3.

The arming record is admissible on the same constitutive test as koto's: it is
written by the hook process, not by the agent; the agent's tool call triggers it
but does not author it; and it cannot exist without the arming condition holding.

### Detecting partial delegation

`spawned_count >= 1` bounds nothing, and neither does the count of child
directories, because materialization is not delegation. The bound that works is a
**set comparison**: recompute the expected task-name set from the PLAN using the
same derivation `/execute` would have used, and require it to be a subset of the
child names that reached terminal.

Name derivation is deterministic and reproducible: `slugify` at
`skills/plan/scripts/plan-to-tasks.sh:221-230` lowercases, maps non-alphanumerics
to `-`, collapses runs, and strips edges; names are prefixed `o-` and truncated to
`KOTO_NAME_MAX=64` with collision suffixes. In `multi-pr` mode names are
`issue-<n>` instead. Child koto sessions are `<parent>.<task-name>`, so the prefix
`<parent>.` covers both shapes. **[confirmed]**

Running the real script against the real PLAN in this worktree surfaced a parser
bug worth flagging: `plan-to-tasks.sh docs/plans/PLAN-work-on-friction-fixes.md`
emits **7 entries for `issue_count: 6`**, with `issue-84` duplicated — it picks up
`#84` from prose in a table row at line 73 whose issue-number cells are empty.
**[confirmed]** Deduplicating the expected set absorbs this particular bug (the
phantom collides with a real name), which is why the check compares sets rather
than counts. `issue_count` from the PLAN frontmatter is retained only as a
fallback bound when the script cannot run.

Reporting `non-conforming` for partial delegation requires the run to have
finished, established by the parent's own terminal-index entry. An in-flight run
reports `indeterminate` — more children may yet be driven.

#### Does the denominator hold when a plan legitimately has fewer children?

Mostly yes, and for a reason that is easy to miss: **a legitimately dropped issue
still produces a child koto session.** `work-on`'s template declares five terminal
states — `done`, `done_already_complete`, `done_blocked`,
`skipped_due_to_dep_failure` (`skills/work-on/koto-templates/work-on.md:763-780`)
and `validation_exit` (`:122-123`). **[confirmed]** Every one of them is a terminal
transition, so every one lands a terminal-index entry. An issue closed as a no-op
exits through `done_already_complete`; an issue whose dependency failed exits
through `skipped_due_to_dep_failure`. Both remain in the ledger, both satisfy the
subset test, and neither reduces the count. The check measures *conformance*, not
*completeness* — a run where three of six children reached `done_blocked` is
`conforming` and separately unfinished, which is what `batch_outcome:
needs_attention` is for.

The one case that does reduce the ledger is an issue the orchestrator drops
without materializing a child at all — a merged outline, a scope cut taken
mid-run. That reports `non-conforming`, and on reflection that is the right
answer rather than a false positive: R10 obliges a session to record a conflict
before departing from the workflow, and AC22 makes an unrecorded departure
`non-conforming` on its own terms. The conflict record is the sanctioned route to
legitimize a dropped issue, so a silent drop is non-conforming by R10 whether or
not R2 binds. The reason string names the missing child, which is precisely the
information a reviewer needs to go look for the conflict record.

Note also what the check must *not* do here. Reading git to discover that a
missing issue was never implemented would be using session-produced state to
*raise* a verdict from `non-conforming` to `conforming`, which is the direction
R1's admissibility rule exists to block. Session-produced state stays
monotonically against conformance.

#### What this evidence does not bound

Stated plainly, because it matters more to the DESIGN than the parts that work.

The delegation ledger establishes that every issue in the PLAN got a koto child
session that ran to a terminal state. It does **not** establish that the
orchestrator refrained from writing implementation code itself. A run that
delegates all six issues correctly and *also* has its orchestrator edit source
files inline produces an identical ledger to a clean run. Nothing in the post-hoc
file evidence distinguishes them, because the distinguishing fact — which agent
role issued a given write — exists only at the tool-call layer and is not recorded
anywhere durable.

That gap is R3's, not R1's. The in-band write refusal is the mechanism that keeps
the orchestrator out of the source tree, and the team lead's probe supplies the
discriminator it needs: a subagent's hook invocation carries `agent_id` and
`agent_type` while the parent's carries neither. The read-only determination
inherits the guarantee rather than establishing it, and the DESIGN should say so
rather than implying the check proves orchestrator abstention. This is the same
shape as the PRD's own Known Limitations, which already disclaim that a conforming
record means the delegated work was good.

### Outcome mapping

| Situation | Outcome |
|---|---|
| PLAN `execution_mode: coordinated` | `coordinated` (R7) |
| Registered, run terminal, expected ⊆ terminal children | `conforming` |
| Registered, run terminal, some expected child never reached terminal | `non-conforming` |
| Registered, run terminal, zero terminal children | `non-conforming` |
| Armed, session known, no registration record | `non-conforming` (AC2, AC3) |
| No arming witness, no registration record | `indeterminate` (AC7) |
| Session id unknown, PLAN unreadable, index unreadable, `jq` absent | `indeterminate` |
| Registered, run still in flight | `indeterminate` |

---

## The recommended check

Verified against seven cases: four synthetic fixtures and three real sessions on
this machine. Written to
`/home/dgazineu/.claude/jobs/4d06ff3a/tmp/shirabe-conformance.sh` during this
decision; it is a working reference implementation, not a shipped artifact.

```bash
#!/usr/bin/env bash
#
# shirabe-conformance.sh - Report whether a session ran plan-scale execution
#                          under the sanctioned workflow.
#
# Usage:
#   shirabe-conformance.sh --plan <PLAN.md> --session <claude-code-session-id>
#     [--repo-root <dir>] [--tasks-script <path>]
#     [--koto-root <dir>] [--projects-root <dir>] [--arm-log <file>]
#
# Output: one line, "<outcome>\t<reason>"
# Outcomes / exit codes: conforming 0, non-conforming 1, indeterminate 2,
#                        coordinated 3
#
# Every input is either (a) written by koto or by the arming component as a
# byproduct of its own operation, or (b) the PLAN document, which is the input
# under execution rather than an output of the evaluated session.

set -uo pipefail

PLAN=""; SID=""; REPO_ROOT=""; TASKS_SCRIPT=""
KOTO_ROOT="${KOTO_ROOT:-$HOME/.koto}"
PROJECTS="${CLAUDE_PROJECTS_ROOT:-$HOME/.claude/projects}"
ARM_LOG="${SHIRABE_ARM_LOG:-$HOME/.shirabe/armed.jsonl}"
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --session) SID="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --tasks-script) TASKS_SCRIPT="$2"; shift 2 ;;
    --koto-root) KOTO_ROOT="$2"; shift 2 ;;
    --projects-root) PROJECTS="$2"; shift 2 ;;
    --arm-log) ARM_LOG="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

verdict() {
  printf '%s\t%s\n' "$1" "$2"
  case "$1" in
    conforming) exit 0 ;;
    non-conforming) exit 1 ;;
    coordinated) exit 3 ;;
    *) exit 2 ;;
  esac
}

[ -n "$PLAN" ] && [ -n "$SID" ] || { echo "usage: $0 --plan <PLAN.md> --session <sid>" >&2; exit 64; }
[ -n "$REPO_ROOT" ] || REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
command -v jq >/dev/null 2>&1 || verdict indeterminate "jq-missing"

# ---------------------------------------------------------------- PLAN inputs
[ -r "$PLAN" ] || verdict indeterminate "plan-unreadable:$PLAN"
MODE=$(awk -F': *' '/^execution_mode:/{print $2; exit}' "$PLAN")
[ -n "$MODE" ] || verdict indeterminate "plan-missing-execution_mode"

SLUG=$(basename "$PLAN" .md); SLUG=${SLUG#PLAN-}
WANT="execute-$SLUG"

# R7: the coordinated path runs without a single orchestration session by design.
[ "$MODE" = "coordinated" ] && verdict coordinated "execution_mode=coordinated plan=$SLUG"

INDEX="$KOTO_ROOT/_terminal_index.jsonl"

koto_session_seen() {
  [ -d "$KOTO_ROOT/sessions/$WANT" ] && return 0
  [ -r "$INDEX" ] && grep -qF "\"session_id\":\"$WANT\"," "$INDEX" && return 0
  return 1
}

# ------------------------------------------------------ was it REGISTERED (R2)
[ -d "$PROJECTS" ] || verdict indeterminate "claude-projects-unreadable"

ENC=$(printf '%s' "$REPO_ROOT" | sed 's/[^A-Za-z0-9]/-/g')
REG_FILE=""; REG_MTIME=0; REG_STATE=""

while IFS= read -r wfdir; do
  projdir=$(basename "$(dirname "$(dirname "$wfdir")")")
  case "$projdir" in "$ENC"*) : ;; *) continue ;; esac
  for f in "$wfdir"/koto-*.json; do
    [ -e "$f" ] || continue
    # IFS=$'\t' is load-bearing: .name is "execute · <state>" and contains spaces.
    IFS=$'\t' read -r nm wf st < <(jq -r '[(.name//""),(.koto.workflow//""),(.koto.currentState//"")]|@tsv' "$f" 2>/dev/null)
    case "$nm" in "execute "*) : ;; *) continue ;; esac
    [ "$wf" = "$WANT" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$m" -gt "$REG_MTIME" ]; then REG_MTIME=$m; REG_FILE=$f; REG_STATE=$st; fi
  done
done < <(find "$PROJECTS" -mindepth 3 -maxdepth 3 -type d -path "*/$SID/workflows" 2>/dev/null)

if [ -z "$REG_FILE" ]; then
  # Absence of a registration record is affirmative evidence of non-conformance
  # ONLY when something independently witnesses that the recorder was running
  # while this session ran. The arming component is that witness.
  if ! find "$PROJECTS" -mindepth 2 -maxdepth 2 -name "$SID.jsonl" 2>/dev/null | grep -q .; then
    verdict indeterminate "unknown-session:$SID"
  fi
  if [ -r "$ARM_LOG" ] && grep -qF "\"claude_session_id\":\"$SID\"" "$ARM_LOG"; then
    verdict non-conforming "not-registered:armed-but-no-execute-workflow-for-$SLUG-in-session-$SID"
  fi
  if koto_session_seen; then
    verdict indeterminate "koto-session-$WANT-exists-but-no-session-binding-for-$SID"
  fi
  verdict indeterminate "no-arming-witness-for-$SID:cannot-distinguish-unregistered-from-unrecorded"
fi

# ------------------------------------------------------- was it DELEGATED (R2)
[ -r "$INDEX" ] || verdict indeterminate "terminal-index-unreadable"

# Partial delegation is only concludable once the run has finished.
grep -qF "\"session_id\":\"$WANT\"," "$INDEX" \
  || verdict indeterminate "run-in-flight:$WANT-at-$REG_STATE"

# Delegation ledger: child koto sessions that reached a terminal state.
# Materialization alone is NOT delegation -- a materialized child that never
# advanced past `entry` has no terminal-index entry.
OBSERVED=$(grep -oE "\"session_id\":\"$WANT\.[^\"]+\"" "$INDEX" \
           | sed 's/.*"\(.*\)"/\1/' | sed "s/^$WANT\.//" | sort -u)

if [ -z "$OBSERVED" ]; then
  verdict non-conforming "registered-but-never-delegated:0-terminal-children-for-$WANT"
fi

# Expected task set, recomputed from the PLAN by the CHECKER (not by the
# evaluated session), using the same derivation /execute would have used.
[ -n "$TASKS_SCRIPT" ] || TASKS_SCRIPT="$(dirname "$0")/../plan/scripts/plan-to-tasks.sh"
EXPECTED=""
if [ -r "$TASKS_SCRIPT" ]; then
  EXPECTED=$(bash "$TASKS_SCRIPT" "$PLAN" 2>/dev/null | jq -r '.[].name' 2>/dev/null | sort -u)
fi

if [ -n "$EXPECTED" ]; then
  MISSING=$(comm -23 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$OBSERVED") | paste -sd, -)
  [ -z "$MISSING" ] || verdict non-conforming "partial-delegation:no-child-session-for:$MISSING"
  verdict conforming "registered=$WANT delegated=$(printf '%s\n' "$OBSERVED" | grep -c .)/$(printf '%s\n' "$EXPECTED" | grep -c .)"
fi

# Fallback bound when the task set cannot be recomputed: the PLAN's own count.
COUNT=$(awk -F': *' '/^issue_count:/{print $2; exit}' "$PLAN")
[ -n "$COUNT" ] || verdict indeterminate "cannot-derive-expected-task-set-and-no-issue_count"
HAVE=$(printf '%s\n' "$OBSERVED" | grep -c .)
[ "$HAVE" -ge "$COUNT" ] \
  || verdict non-conforming "partial-delegation:$HAVE-terminal-children-for-$COUNT-issues"
verdict conforming "registered=$WANT delegated=$HAVE/$COUNT (count-bound)"
```

### Verified results

Synthetic fixtures (`/tmp/demo-repo`, three-issue `multi-pr` PLAN):

```
AC1  fully delegated            -> conforming    registered=execute-demo delegated=3/3
AC4  2 of 3 delegated           -> non-conforming partial-delegation:no-child-session-for:issue-13
AC2/3 armed, never registered   -> non-conforming not-registered:armed-but-no-execute-workflow-for-demo...
AC6  execution_mode=coordinated -> coordinated    execution_mode=coordinated plan=demo-coord
     registered, 0 driven kids  -> non-conforming registered-but-never-delegated:0-terminal-children-for-execute-demo
```

Real sessions on this machine:

```
9dbd4bf0 (execute-calendar-cli-only, blocked at spawn_and_await, 4 materialized
          but undriven children)
  -> indeterminate  run-in-flight:execute-calendar-cli-only-at-spawn_and_await

f1b86b09 (execute-feature-23-google-cli-access, completed with 8 delegated
          children, predates the /workflows surface in that workspace)
  -> indeterminate  koto-session-...-exists-but-no-session-binding-for-f1b86b09
     (correctly refuses to call a conforming run non-conforming)

4d06ff3a-0000-... (nonexistent session id)
  -> indeterminate  unknown-session:...
```

The second field incident is also confirmed forensically by the registration half
alone, reproducing the research lead's result: `find
~/.claude/projects/-home-dgazineu-dev-niwaw-tsuku-tsuku-execute-and-work-on-trigger-d36b0bbf
-maxdepth 3 -type d -name workflows` returns **0** directories. No koto loop was
ever driven from any Claude Code session in the incident workspace. **[confirmed]**

---

## Rationale

The constitutive reading of R1 is the only one that is both satisfiable and
faithful to the PRD's stated purpose. The PRD's own justification for the
admissibility clause is that "that incident's payload was produced by a script the
agent ran, so evidence traceable to the session's own tool calls cannot count, or
the discriminator is defeated by the artifact the failure produced." The operative
word is *defeated*: the concern is a record that can be produced without doing the
thing. The constitutive test names that property directly, where a causal test
over-reaches and a forgery test under-reaches.

The forgery test under-reaches because nothing local is forgery-resistant against
an agent holding a Write tool — the agent could hand-write a
`workflows/koto-x.json`. But the PRD's threat model is drift, not fraud: both
field incidents were agents doing what they thought reasonable, and one of them
volunteered the departure when asked. Requiring corroboration across three
independent koto-owned files (workflows record, session directory, terminal index)
raises the bar well past that threat model without pretending to cryptographic
integrity.

Delegation is measured on terminal children rather than materialized children
because materialization is a bookkeeping act koto performs on the parent's behalf,
while reaching terminal requires the agent to have driven a full `work-on` state
machine through every gate. `execute-calendar-cli-only` is the live proof that the
two differ: four children exist on disk with three log lines each and no work done.

The denominator comes from the PLAN because the PLAN is the input under execution
rather than an output of the run, and because the checker recomputing it is the
checker's own act. Comparing sets rather than counts survives the duplicate-name
bug found in `plan-to-tasks.sh`.

The arming witness is the piece that lets absence mean something. Without it the
check can report `conforming` and `coordinated` correctly but collapses AC2, AC3,
and AC7 into a single `indeterminate`, which is precisely the outcome the PRD says
is unacceptable for the never-invoked journey.

---

## Rejected options

**`~/.koto/sessions/<name>` existence.** False for every successful run; inverts
the signal. Retained only as a live-detail lookup and a weak corroborator.

**A PR trailer or CI gate.** Requires widening `/execute`'s closed write-target
set, which the PRD explicitly puts out of scope. It is the only route to off-machine
verification, and should stay on the table as a separate amendment.

**Counting `scheduler_ran.spawned_count`.** Evaluated directly, since it was
proposed as the fallback if the workflows record could not separate parent from
child work. It fails twice over. It records materialization rather than execution
— `execute-calendar-cli-only` fanned out four children that each sit at `entry`
with a three-line log and no work done, so a non-zero `spawned_count` there proves
only that koto wrote four directories. And the event lives in the parent's
`koto-<name>.state.jsonl`, which cleanup deletes on terminal: the directory for the
completed `execute-feature-23-google-cli-access` no longer exists. **[confirmed]**
An event that over-counts and then disappears cannot bound R2's every-issue bar.
The terminal-index prefix scan carries the same per-child identity, is written on
actual terminal transitions rather than on materialization, and survives cleanup.

**Comparing counts instead of task-name sets.** A phantom node from the parser bug
plus one skipped issue would sum back to the expected count and pass. Set subset
does not have that failure mode.

**Deriving the denominator from git.** Enumerating which issues were actually
implemented means reading commits, which the evaluated session produced. Admitting
it would breach R1 for no gain, since the PLAN already supplies the denominator.

**Using "does any koto session for this plan exist" as the liveness corroborator.**
Tested and rejected: an unrelated same-named session makes an unregistered
session report `indeterminate` instead of `non-conforming`.

---

## Assumptions

1. The threat model is drift, not deliberate forgery. An agent that hand-writes a
   consistent set of koto records across three files defeats this check, and no
   local mechanism closes that.
2. `~/.claude/projects/<encoded-cwd>/` encodes cwd by replacing every
   non-alphanumeric with `-`. Consistent with four observed directory names and
   verified as a prefix match for two repos, but read from directory names rather
   than from Claude Code source. **[inferred]**
3. A conforming run names its koto session `execute-<plan-slug>` per
   `skills/execute/SKILL.md:150`. A run that deviates reports `non-conforming`,
   which is conservative but could surprise.
4. The arming component (Decision 2) will emit a durable per-session record. If it
   does not, AC2, AC3, and AC7 are not separable and this decision needs revisiting.
5. `has_result: true` in the terminal index is not relied on. Every entry on this
   machine has `terminal_state: "completed"` — the schema's only other value is
   `"abandoned"` — so the index proves a child terminated, not that it succeeded.
   That matches the PRD's Known Limitations, which disclaim any assertion about
   the quality of delegated work.

---

## Open questions

1. **Does `koto init` reliably run with `CLAUDE_CODE_SESSION_ID` set in
   niwa-dispatched background sessions?** The whole registration half depends on
   it, and koto's own source contemplates the failure: `resolve_from_claude_env`
   "Returns `None` when the env var is unset/empty or no matching transcript
   exists (e.g. a fully headless run) -- in which case nothing renders"
   (`materialize.rs:262-267`). **[confirmed]** A headless run therefore leaves no
   registration record while genuinely conforming. The arming witness converts
   that into `indeterminate` rather than a false `non-conforming`, but every
   dispatched run reporting `indeterminate` would gut R12 coverage. This is the
   highest-value thing to test next, and it is a different question from the team
   lead's probe — that probe established that Agent-tool subagents *share* the
   parent's session id, which is a fact about one session, not about whether a
   dispatched session has one at all.
2. **Should the plan binding be strengthened beyond the session-name convention?**
   Today the PLAN path survives only in the state log that cleanup deletes.
   Persisting `PLAN_DOC` into the `/workflows` record is a small koto change
   (`materialize.rs` already reads the header) and would remove assumption 3
   entirely. Worth raising with koto.
3. **The `plan-to-tasks.sh` phantom-issue bug.** `PLAN-work-on-friction-fixes.md`
   yields 7 tasks for 6 issues, with `issue-84` extracted from prose. Set
   deduplication absorbs it here, but a phantom that does *not* collide with a
   real name would produce a spurious `partial-delegation` finding. This should be
   filed independently of this design.
4. **What is the check's arming-side latency budget?** R16 caps the in-band refusal
   at 100ms p95. This determination is post-hoc and not on that path, but if D2
   invokes any part of it during arming, the `find` over `~/.claude/projects` (67
   records, 1210 koto session dirs on this machine) needs measuring.
5. **Where does the arming log live, and does it need rotation?** One line per
   armed session is small, but it is a new durable surface and D2 should own its
   path, schema, and lifecycle rather than inheriting the placeholder
   `~/.shirabe/armed.jsonl` used above.
6. **Should "delegation goes through koto child sessions, never the Agent tool"
   become a recorded design invariant?** The determination depends on it. Agent-tool
   children share the parent's Claude Code session id and create no koto session,
   so a future `spawn_and_await` that delegated that way would be invisible to both
   halves of the check while looking, from the outside, like a well-behaved run.
   The invariant costs nothing to state now and is expensive to discover later.
