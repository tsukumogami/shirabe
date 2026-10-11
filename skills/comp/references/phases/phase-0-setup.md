# Phase 0: Setup

Detect the input mode, run the private-only visibility check, validate
the topic slug, and open the `comp-<topic>` session. Phase 0 runs before
any content work, and the session is opened last, so a visibility warning
reaches the author before anything is created.

## 0.1 Detect Input Mode

Parse `$ARGUMENTS`:

- **Empty** — ask the user which competitive question to survey, then
  derive a topic slug from their answer.
- **Existing COMP path + lifecycle verb** (`accept`, `done`) — this is a
  transition invocation; run `shirabe transition <path>
  Accepted|Done` and exit. No new authoring.
- **`--upstream <path>`** — record the upstream artifact path for Phase 1.
- **Anything else** — treat the first token as the topic slug.

## 0.2 Visibility Check (Private Only) — Warning

Detect repo visibility from CLAUDE.md (`## Repo Visibility:
Public|Private`). If the header is absent, infer from the repo path
(`private/` -> Private, `public/` -> Public; default to Private).

COMP is private-only. If visibility is anything other than `private`,
**warn before doing anything else** — before opening the session,
creating anything, or starting the scoping conversation. Emit this
exact line to stdout so the condition can be detected by shell
parsing:

```
[/comp] WARNING <topic>: visibility=public
```

Then present the decision using AskUserQuestion, following the pattern in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`, and wait for
the author's answer. Recommend stopping — the detected visibility is
what grounds that recommendation, and nothing the skill can do here
changes the validator's answer downstream:

> *"This repo is public. A COMP is competitive content and belongs in a
> private repo: `shirabe validate` rejects a COMP under public
> visibility (R9), so an analysis written here can't be finalized in
> place — and CI's guardrail fails the PR. If you want the competitive
> question on the record in this repo, a BRIEF or PRD can reference it
> without carrying the analysis."*

**Options:**
1. "Stop here (Recommended)" — take the analysis to a private repo, or
   write a public BRIEF/PRD that references the competitive question
2. "Continue anyway" — draft the COMP here knowing it cannot be
   finalized in place

**Description field:** Name how visibility was resolved — the CLAUDE.md
`## Repo Visibility:` header, the inferred repo path, or the absent
header that defaulted the check — so the author can spot a mis-set
header and override on an informed basis.

Recommending "Stop here" is not the same as stopping: `/comp` does
**not** exit on its own, and "Continue anyway" proceeds normally. The
author decides. The check is fail-closed in what it treats as
public — any non-`private` value,
including an unset or unrecognized visibility, warrants the warning —
but fail-closed here means "warn", not "terminate".

Warn rather than refuse because the author is the one who knows why they
invoked `/comp` here: they may be about to move the analysis, may have a
mis-set `## Repo Visibility:` header, or may want the draft in hand
before deciding where it lives. What a flat refusal actually protected
was the artifact never landing in a public repo, and that protection is
not the skill's to give up — it lives in the validator's R9 gate and the
CI guardrail, both of which still reject a COMP under public visibility.
The skill's job is to make sure the author knows that before they spend
the session, which is what the warning does.

If the author continues, carry the resolved visibility forward: Phase 5
states the same consequence again at the approval gate, and finalization
stops at the validator rather than landing a COMP in a public repo.

## 0.3 Validate Topic Slug

The `<topic>` slug must match `^[a-z0-9][a-z0-9-]*$` (lowercase alphanumeric
and hyphens only, starting with a letter or digit). Reject any topic
containing `.`, `/`, `_`, whitespace or other characters, or starting with
`-`, and ask the user for a conforming slug. This constraint is
load-bearing: `<topic>` is placed in the session name `comp-<topic>` and on
`skill-session.sh` command lines, so a topic like `-x` must never get as far
as being read as a flag.

## 0.4 Open the Session

With the visibility decision made and the topic valid, open the session:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open comp <topic>
```

`open` attaches to a live `comp-<topic>` (an interrupted run), replaces a
finished one (a fresh run), or creates it. A non-zero exit stops the run
with the script's message: 127 or 69 means koto is missing or too old, 6
means HEAD is detached, and the skill never falls back to files. See
"Session and Keys" in SKILL.md.

`/comp` keeps two kinds of working key in this session, neither written
yet:

- `work/scope.md` — Phase 1 scoping notes.
- `research/phase4_<role>.md` — Phase 4 verdicts (written later, by the
  jury through a scratch directory).

These are non-durable intermediates. Phase 5 closes the session, and no
committed COMP artifact may reference a staging path.

## Output

Phase 0 produces: the validated topic slug, the resolved visibility, the
optional upstream path, and an open `comp-<topic>` session. On a
non-private repo it also produces the `[/comp] WARNING` stdout signal and
the author's decision about whether to continue.
