# Lead: What does the niwa CLI offer today for cross-repo worktrees and coordination that a capstone workflow could lean on?

## Findings

### MAJOR CORRECTION: the mesh is gone

The workspace docs (`CLAUDE.overlay.md`) describe a niwa "mesh" with delegation
tools (`niwa_delegate`, `niwa_await_task`, `niwa_ask`, etc.) and a coordinator
role. **That subsystem has been deleted.** It is stale context.

Evidence:
- `public/niwa/docs/briefs/BRIEF-niwa-mesh-removal.md` (status: **Done**) —
  "niwa carries a pre-pivot agent-facing mesh (an MCP server, a task-delegation
  substrate, a per-worktree daemon...) that is non-functional in practice. The
  only capability that actually works is git worktree creation."
- `public/niwa/cmd/niwa/main.go` registers no MCP server — it only calls
  `cli.Execute()` and imports a vault backend.
- `grep` for `mesh`/`delegate` across `internal/` and `cmd/` returns only
  incidental English uses of the word "delegate" in code comments. There is no
  task-delegation code, no MCP tools, no coordinator role.

So a shirabe capstone workflow **cannot** lean on niwa for agent-to-agent task
dispatch, merge ordering, or cross-session coordination. None of that exists.
What niwa offers is a **single-machine git-worktree lifecycle manager** plus
**workspace state files**. Any "merge order" / "capstone tracking" semantics must
be built in shirabe (skill logic + its own artifacts), using niwa only to
create/destroy/list worktrees.

### 1. Worktree primitives (the live, load-bearing capability)

Canonical command group: **`niwa worktree`** (legacy alias `niwa session`, which
still works and prints a one-line deprecation notice to stderr).
- Source: `public/niwa/internal/cli/session.go` (parent cmd, `list`),
  `public/niwa/internal/cli/session_lifecycle_cmd.go` (create/apply/destroy),
  plus `internal/cli/sessionattach/` (attach/detach).
- Core engine (leaf package, no workspace/mcp imports):
  `public/niwa/internal/worktree/worktree.go`
  (`CreateSession`, `DestroySession`).
- Guide: `public/niwa/docs/guides/worktree.md` (authoritative, 332 lines).

Commands:
| Command | Behavior |
|---|---|
| `niwa worktree create <repo> <purpose>` | Creates branch `session/<id>` from repo HEAD, adds a git worktree at `<instance>/.niwa/worktrees/<repo>-<id>/`, installs the repo's CLAUDE content + a `worktree-imports.md` rule + a purpose/branch layer, runs `worktree-hooks/`, writes state file. Prints `session: created <id> at <path>`. With shell integration, cd's into it. |
| `niwa worktree apply <id>` | Idempotent re-sync of CLAUDE content into an existing active worktree. |
| `niwa worktree destroy <id> [--force]` | Marks state `ended`, removes the working dir, deletes branch with `git branch -d` (merged-only) or `-D` (with `--force`). Guards: refuses on uncommitted changes or live attach lock unless `--force`. |
| `niwa worktree list [--repo <name>] [--status active\|ended\|abandoned] [--attached\|--available] [--json]` | Lists lifecycle states with attach availability. `--json` emits one object per worktree. |
| `niwa worktree attach <id>` | Acquires exclusive lock, launches `claude --resume` on the worktree's transcript; auto-releases on exit. Typed exit codes 0-4. |
| `niwa worktree detach <id> [--force]` | Operator escape hatch for stale/live attach locks. |

Naming / per-repo notion:
- **Worktree dir**: `<instance>/.niwa/worktrees/<repo>-<id>/` — `<repo>` is the
  per-repo prefix (`worktree.go:199`: `wtPath := worktreesDir + repo + "-" + sid`).
- **Branch**: default `session/<id>`; the engine supports a `BranchPrefix` param
  (`CreateSessionParams.BranchPrefix`, e.g. `niwa-bootstrap/` used by the
  bootstrap path) — but the CLI `create` command does NOT expose a flag for it
  (it always passes the default). Branch name is persisted in state.
- **id**: 8-char lowercase hex from `crypto/rand`, validated `^[0-9a-f]{8}$`.
- **Per repo**: `create` takes a `<repo>` arg and validates that repo is a cloned
  git repo two levels deep in the instance (`findRepoInWorkspace`). Multiple
  worktrees for the same repo coexist (each its own id/branch/dir). There is no
  built-in "≤1 worktree per repo" enforcement — that's a policy shirabe would add
  (e.g. via `niwa worktree list --repo <name> --status active --json`).

### 2. Worktree lifecycle state (the per-worktree state files)

Schema: `SessionLifecycleState` in
`public/niwa/internal/worktree/session_lifecycle.go` (v=1, branch_name added
v1.1). One JSON file per worktree at
**`<instance>/.niwa/sessions/<id>.json`**. Fields:
- `v`, `session_id`, `repo`, `purpose`, `status` (`active`/`ended`/`abandoned`),
  `creation_time` (RFC3339), `worktree_path` (absolute), `branch_name`,
  `creator_pid`, `creator_start_time`.
- **`parent_session_id`** (`omitempty`) — *already exists in the schema.* This is
  the single most relevant field for a capstone: it can link a per-repo
  implementation worktree to a parent (capstone) worktree. The engine accepts it
  via `CreateSessionParams.ParentSessionID`, BUT the CLI `create` command does NOT
  expose a flag to set it (only the in-process bootstrap caller can). See Open
  Questions.
- `claude_conversation_id` (`omitempty`), `attach` (computed, not persisted).

Read/write helpers (exported, usable as a Go API if shirabe ever vendored, but
realistically the seam for a skill is the CLI + reading the JSON):
`ReadSessionLifecycleState`, `WriteSessionLifecycleState`,
`ListSessionLifecycleStates`. The state file is the documented source of truth
for status; `--json` on `list` is the supported read path for scripts.

### 3. Workspace-level state: `instance.json`

Schema: `InstanceState` in `public/niwa/internal/workspace/state.go`, file at
**`<instance>/.niwa/instance.json`** (current `SchemaVersion = 4`). Fields:
`schema_version`, `config_name`, `instance_name`, `instance_number`, `root`,
`overlay_url`/`overlay_commit`/`no_overlay`, `config_name_override`, `created`,
`last_applied`, `managed_files[]`, `repos` (map name→{url, cloned}),
`shadows[]`, `disclosed_notices[]`, `config_source`, `auth_sources`.

Extensibility assessment for "active capstone / merge order":
- instance.json is **niwa-owned and apply-rewritten**. `SaveState` marshals the
  struct; any unknown JSON keys a third party added would be **silently dropped**
  on the next `niwa apply` (Go `json.Unmarshal` ignores unknown fields, then
  `SaveState` re-marshals only the known struct). So **shirabe must NOT write its
  own keys into instance.json** — they won't survive. It's safe to *read*
  (e.g. `root`, `repos`, `instance_name`).
- There is **no** existing niwa field for "active capstone," "merge order," or
  cross-repo PR sequencing. niwa tracks worktrees individually; it has no concept
  of a worktree group, an ordering, or a PR.
- `disclosed_notices[]` is the only "append a string list" extension point, and
  it's semantically owned by the one-time-notices feature — not a place for
  capstone state.

### 4. Cleanest seams for a shirabe capstone skill

niwa gives three usable seams; everything orchestration-level lives in shirabe.

a) **Create the capstone worktree**: `niwa worktree create <repo> "<purpose>"`
   for whichever repo should host the overarching plan + artifacts. niwa returns
   `session: created <id> at <path>` on stdout (parseable) and writes
   `.niwa/sessions/<id>.json`. Note: niwa has no "capstone" type — it's just a
   worktree whose purpose string and shirabe-side bookkeeping mark it as the
   capstone.

b) **Create ≤1 per-repo implementation worktree**: loop
   `niwa worktree create <repo> "<purpose>"` per target repo. Enforce the
   one-per-repo rule in shirabe by first calling
   `niwa worktree list --repo <repo> --status active --json` and skipping/erroring
   if one exists. niwa itself won't stop a second.

c) **Record/drive merge order**: niwa has nothing for this. shirabe must own it
   in its **own** artifact (a capstone plan doc / state file under the capstone
   worktree, or `wip/`). The natural keys to record are the worktree `session_id`,
   `repo`, and `branch_name` (read from each `.niwa/sessions/<id>.json` or from
   `list --json`). The `parent_session_id` field *could* model capstone→child
   linkage on disk — but only if niwa exposes a `--parent` flag on
   `worktree create` (it currently does not; see Open Questions).

d) **Discovery / instance root**: shirabe resolves the instance via
   `NIWA_INSTANCE_ROOT` env var or by walking up for `.niwa/instance.json`
   (`resolveInstanceRoot` / `DiscoverInstance`). The repos live two levels deep
   (`<instance>/<group>/<repo>`), groups e.g. `public/`, `private/`.

## Implications

- The capstone/merge-order orchestration the author wants is **net-new logic that
  belongs in shirabe**, not a thin wrapper over niwa primitives. niwa contributes
  exactly one verb family (worktree CRUD) and a per-worktree JSON state file.
- shirabe can shell out to `niwa worktree create/list/destroy` and parse stdout /
  `--json`. This is the clean, supported seam. It should NOT poke niwa's
  instance.json (writes get clobbered) and should NOT depend on the removed mesh.
- "Merged last" / "explicit merge order across per-repo PRs" maps to **PRs**,
  which niwa knows nothing about. That's a GitHub/gh-CLI concern shirabe already
  handles elsewhere (pr-creation skill). niwa worktrees just provide the isolated
  branches the PRs come from.
- `parent_session_id` is a promising on-disk hook for capstone→child linkage and
  is *already in the schema* — the gap is purely a missing CLI flag, a small,
  plausible niwa change shirabe could request.

## Surprises

- The biggest surprise: the entire mesh/delegation system referenced in the
  workspace overlay context is **deleted** (BRIEF-niwa-mesh-removal, status Done).
  Any plan built on `niwa_delegate`/coordinator roles is built on sand.
- The user-facing noun is "worktree," but the on-disk schema, state dir
  (`.niwa/sessions/`), and JSON keys still say "session" — `niwa session` is a
  deprecation alias for `niwa worktree`.
- `CreateSession` already supports `ParentSessionID` and a custom `BranchPrefix`,
  but neither is reachable from the `niwa worktree create` CLI — only the
  in-process bootstrap orchestrator uses them.

## Open Questions

- Will niwa expose `--parent <id>` (and/or `--branch-prefix`) on
  `niwa worktree create`? The engine already accepts both; exposing them would let
  shirabe record capstone→child linkage in niwa's own state rather than a
  shirabe-side file. (Currently it must use a shirabe-owned artifact.)
- Is there any appetite in niwa for a first-class "worktree group" / capstone
  concept, or should shirabe own that entirely? Today instance.json has no group
  notion and silently drops foreign keys.
- Does shirabe already have a worktree-creation path (e.g. superpowers
  using-git-worktrees) that competes with `niwa worktree`? If so, which is
  canonical inside a niwa workspace? (Out of scope for this niwa-focused lead, but
  needed before designing.)

## Summary

niwa's mesh/delegation system has been deleted (BRIEF-niwa-mesh-removal, Done); the only live coordination primitive is a single-machine git-worktree lifecycle manager exposed as `niwa worktree create/apply/destroy/list/attach`, with per-worktree state at `.niwa/sessions/<id>.json` and workspace state at `.niwa/instance.json`. niwa has no concept of a capstone, a worktree group, merge order, or PRs, and its instance.json silently drops foreign keys — so all capstone/ordering orchestration must live in shirabe, using niwa only to create/list/destroy per-repo worktrees (the supported seam is the CLI plus `list --json`). The one promising on-disk hook is the existing `parent_session_id` field in the worktree schema, which could link children to a capstone but is not yet settable from the `niwa worktree create` CLI.
