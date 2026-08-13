# Explore Scope: vale-adoption

## Visibility

Public

## Core Question

Should this workspace adopt Vale, the syntax-aware prose linter, and if so
where? Two candidate uses are on the table: a tool authors run when writing or
updating skills and agent instructions, and a step shirabe skills invoke at
document drafting time. The author has never used Vale and is unsure whether it
earns its keep, so the exploration has to establish what Vale can actually
mechanize before it can recommend anything.

## Context

shirabe already owns a `writing-style` skill: a 73-line SKILL.md listing banned
words, phrases, structural patterns, formatting tells, and cognitive tells. It
is applied entirely by model judgment — nothing checks the output. The
workspace CLAUDE.md carries a second, shorter copy of the same rules plus a
pointer to `.claude/helpers/writing-style.md`, and a Communication Style section
that bans bullet-heavy structured reports in chat.

shirabe's existing correctness engine is `shirabe validate`, a Rust CLI whose
stated job is to "tell the agent what to fix and why." The repo has an explicit
anti-pattern rule: authoring belongs in skills, deterministic checking belongs
in `validate`. Any Vale proposal has to land on one side of that line.

tsuku already ships a `vale` recipe (`recipes/v/vale.toml`, homebrew-backed,
tier 0), so installation is a solved problem and not a reason to reject.

The author wants Vale evaluated against four content targets: skills and agent
instructions, shirabe-generated artifacts at draft time, user-facing docs and
READMEs, and the ephemeral prose stream of commits, issues, and PR bodies. Both
the "what job does it do" and "where does it run" questions are open and are
themselves part of what the exploration should answer.

## In Scope

- Vale's actual rule-engine capabilities and their hard limits
- Translating shirabe's existing writing-style rules into Vale rules, and what
  fraction survives that translation
- Evidence about whether prose linters improve LLM-authored prose specifically
- Fit with `shirabe validate`, koto workflows, and existing CI
- Operational cost: config distribution across repos, false positives on
  markdown with frontmatter/tables/code, agent-loop latency
- All four content targets named above

## Out of Scope

- Rewriting the `writing-style` skill's rule content itself (only its
  mechanizability is in question)
- Spelling/grammar checkers that are not Vale (ltex-ls, textlint, etc.) except
  as comparison points for the capability boundary
- Recipe or packaging work in tsuku (the vale recipe already exists)
- Style-guide authorship for tsuku's user-facing website copy

## Research Leads

1. **What is Vale actually good at, and what can it fundamentally not check?** (lead-capability-boundary)
   The author has never used it. Establish the real capability surface — rule
   types, scoping, markup awareness, packages — and just as importantly the
   hard boundary where regex-and-token matching stops. This determines the
   ceiling on everything else.

2. **How much of shirabe's writing-style rulebook survives translation into Vale rules?** (lead-rule-translation)
   Take `skills/writing-style/SKILL.md` rule by rule and classify each as
   fully mechanizable, partially mechanizable, or out of reach. The banned-word
   tables look trivially mechanizable; the cognitive tells and "burstiness"
   guidance look impossible. The ratio between those is the strongest single
   signal on whether adoption is worth it.

3. **Who uses Vale, and is there evidence it improves LLM-authored prose?** (lead-ecosystem-evidence)
   Vale is well established in human docs teams, but this workspace's prose is
   overwhelmingly agent-authored. Find out whether anyone runs a prose linter
   in an agent feedback loop, what the reported false-positive burden is, and
   whether existing style packages cover AI writing tells at all.

4. **Where would Vale fit shirabe's existing enforcement machinery without duplicating it?** (lead-integration-fit)
   shirabe has `shirabe validate` as its correctness engine, koto for workflow
   orchestration, per-skill jury reviews, and CI workflows. Map the candidate
   insertion points and test each against the repo's authoring-vs-validation
   anti-pattern rule.

5. **What does Vale cost to run across four very different content types?** (lead-operational-cost)
   Config distribution across a multi-repo workspace, behavior on SKILL.md
   files that are instructions rather than prose, handling of frontmatter,
   tables, and code blocks, network dependence of `vale sync`, and latency if
   it runs inside an agent loop. Cost is what decides the deployment model.

6. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)

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
      references — not paraphrases.
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
