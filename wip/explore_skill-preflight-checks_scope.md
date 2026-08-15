# Explore Scope: skill-preflight-checks

## Visibility

Public

## Core Question

Can shirabe replace the prose in its skills that describes required CLI tools,
version floors, and install commands with a check that runs deterministically
when a skill loads -- silent and free on a correctly configured machine, and
emitting host-appropriate install instructions when something is missing? The
load-bearing unknown is whether Claude Code offers any mechanism that runs a
script at skill-load time, and what the fallback shape looks like if it doesn't.

## Context

Today `skills/work-on/SKILL.md` carries a Prerequisites section telling the
agent to run `koto version`, check for >= 0.3.3, and pipe an install script to
bash if it's absent. Other skills reference `shirabe validate`, `gh`, and `jq`
throughout their phase files without a single place that says what's required.
Every load pays for that prose whether or not the machine needs it.

The shirabe binary already hosts hook entry points (`pr-body-hook`,
`work-summary`), so there's precedent for the CLI serving the harness. There's
also a bootstrapping wrinkle: the shirabe binary is itself one of the
prerequisites, so a check implemented only in that binary can't report its own
absence.

Constraints established during scoping:

- Checks must be composable. Each skill declares which apply to it; there is no
  single monolithic check every skill pays for.
- Three check categories are in play: binary presence and version, auth and
  config state (`gh auth status`, convention headers), and network or sandbox
  posture.
- A failed check prints and lets the agent decide. Nothing hard-blocks a skill
  from running.
- Audience is shirabe's own skills. This is not a capability adopting repos
  configure for their own skills.
- Where install knowledge lives, and how it adapts to the host, is open --
  research shapes it rather than a pre-committed answer.

## In Scope

- Mechanisms Claude Code offers for running something at or around skill load
- The actual inventory of runtime dependencies across shirabe's skills
- How much prerequisite prose exists today and what it costs
- Declaration format for per-skill composable checks
- Resolving install instructions to commands known to work on the host
  (tsuku on PATH, package managers, OS differences)
- Where the check implementation lives, given the shirabe-binary bootstrap problem

## Out of Scope

- A prerequisite-declaration contract that adopting repos use for their own skills
- Hard-blocking or gating skill execution on a failed check
- Installing anything automatically without the agent or user deciding to
- Replacing `shirabe validate`'s existing checks, which validate documents, not hosts

## Research Leads

1. **What mechanism, if any, lets Claude Code deterministically run a script when a skill loads?**
   This decides the shape of everything else. Map what exists today -- plugin
   hooks, `SessionStart`, `PreToolUse` on the Skill tool, anything skill-scoped --
   and for each: can it be scoped to one skill, does its output reach the agent's
   context, does the exit code mean anything, and does it fire before the skill
   body is read. Report what does not exist as clearly as what does.

2. **How much prerequisite prose actually exists across shirabe's skills, and what does it cost?**
   The premise is that this prose is a recurring tax. Test it. Inventory every
   passage in `skills/` that names a tool, a version floor, a presence check, or
   an install command. Count tokens. Say plainly whether the tax is large,
   small, or concentrated in one or two skills.

3. **What does each shirabe skill actually depend on at runtime, and where does it fail when the dependency is absent?**
   Build the real dependency map: the `shirabe` binary, `koto`, `gh`, `jq`,
   `git`, network reachability. For each skill, which phases touch which tool,
   whether the dependency is unconditional or reached only on one branch, and
   what the failure looks like today when it's missing.

4. **How do comparable tools declare prerequisites and check them?**
   Look at Claude Code plugins and skills in the wild, devcontainer features,
   `mise`/`asdf`, `pre-commit`, `direnv`, `brew doctor`, and any tool that ships
   a "doctor" command. What declaration formats exist, how are checks composed,
   and how do they report a failure without becoming noise.

5. **How can install instructions be resolved to commands known to work on the host?**
   The user's example: `tsuku install tsukumogami/shirabe` when tsuku is on
   PATH, something else when it isn't; different commands for macOS and Linux.
   What signals are cheaply detectable, what precedence order makes sense, and
   what does the matrix cost to maintain as install routes change.

6. **Where should the check live -- shell, the shirabe Rust binary, or split?**
   The binary already hosts `pr-body-hook` and `work-summary`, so it's a
   natural home. But the binary is itself a prerequisite, so it can't report its
   own absence. Weigh a POSIX shell script in the plugin, a binary subcommand, and
   a shell shim that defers to the binary once it's confirmed present.

7. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)

   ```
   You are a demand-validation researcher. Investigate whether evidence supports
   pursuing this topic. Report what you found. Cite only what you found in durable
   artifacts. The verdict belongs to convergence and the user.

   ## Visibility

   Public

   Respect this visibility level. Do not include private-repo content in output
   that will appear in public-repo artifacts.

   ## Six Demand-Validation Questions

   Investigate each question. For each, report what you found and assign a
   confidence level.

   Confidence vocabulary:
   - **High**: multiple independent sources confirm (distinct issue reporters,
     maintainer-assigned labels, linked merged PRs, explicit acceptance criteria
     authored by maintainers)
   - **Medium**: one source type confirms without corroboration
   - **Low**: evidence exists but is weak (single comment, proposed solution
     cited as the problem)
   - **Absent**: searched relevant sources; found nothing

   Questions:
   1. Is demand real? Look for distinct issue reporters, explicit requests,
      maintainer acknowledgment.
   2. What do people do today instead? Look for workarounds in issues, docs,
      or code comments.
   3. Who specifically asked? Cite issue numbers, comment authors, PR
      references -- not paraphrases.
   4. What behavior change counts as success? Look for acceptance criteria,
      stated outcomes, measurable goals in issues or linked docs.
   5. Is it already built? Search the codebase and existing docs for prior
      implementations or partial work.
   6. Is it already planned? Check open issues, linked design docs, roadmap
      items, or project board entries.

   ## Calibration

   Produce a Calibration section that explicitly distinguishes:

   - **Demand not validated**: majority of questions returned absent or low
     confidence, with no positive rejection evidence. Flag the gap. Another
     round or user clarification may surface what the repo couldn't.
   - **Demand validated as absent**: positive evidence that demand doesn't exist
     or was evaluated and rejected. Examples: closed PRs with explicit maintainer
     rejection reasoning, design docs that de-scoped the feature, maintainer
     comments declining the request. This finding warrants a "don't pursue"
     crystallize outcome.

   Do not conflate these two states. "I found no evidence" is not the same as
   "I found evidence it was rejected."
   ```
