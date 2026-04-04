# Lead: What do established product/strategy frameworks say about the artifacts between "idea" and "requirements"?

## Findings

### 1. Lean Canvas (Ash Maurya, adapted from Business Model Canvas)

**What it contains:** A single-page, 9-box framework: Problem, Customer Segments, Unique Value Proposition, Solution, Channels, Revenue Streams, Cost Structure, Key Metrics, Unfair Advantage.

**Purpose:** Force clarity on whether a business idea is viable before building anything. Originally designed for startups validating new ventures.

**How it differs from a PRD:** A Lean Canvas never mentions features, user stories, or acceptance criteria. It operates at the business model level -- why this thing should exist and how it makes money. A PRD assumes you already know the "why" and focuses on the "what" to build.

**Single doc or pipeline:** Single document. Meant to be filled in 20 minutes and iterated. Not a gateway artifact -- it's a thinking tool.

**Relevance to small dev tool orgs:** High. The constraint of one page forces prioritization. The "Problem" and "Unfair Advantage" boxes map directly to "why should this project exist" and "what's our edge."

---

### 2. Business Model Canvas (Alexander Osterwalder)

**What it contains:** 9 boxes: Key Partners, Key Activities, Key Resources, Value Propositions, Customer Relationships, Channels, Customer Segments, Cost Structure, Revenue Streams.

**Purpose:** Map an entire business model for an established or new venture. More operational than Lean Canvas -- includes partnerships, resources, and customer relationship management.

**How it differs from a PRD:** Even further from requirements than Lean Canvas. This is pure business strategy. No product detail at all.

**Relevance to small dev tool orgs:** Moderate. Useful for thinking about a tool's ecosystem (partners, channels, revenue), but the operational boxes (Key Resources, Key Partners) add overhead for a small team evaluating a project idea.

---

### 3. Amazon PR/FAQ (Working Backwards)

**What it contains:** Two parts: (1) A mock press release written as if the product already launched -- headline, customer problem, solution, quote from leadership, how to get started. (2) FAQ section answering anticipated customer and internal stakeholder questions.

**Purpose:** Force future-back thinking. By writing the press release first, you define the customer experience you want to deliver, then work backwards to figure out what to build.

**How it differs from a PRD:** The PR/FAQ is aspirational and customer-facing in tone. It doesn't list requirements -- it paints a picture of the end state. A PRD then decomposes that vision into buildable pieces. Amazon uses the PR/FAQ as the starting point for all other product documents and mockups.

**Single doc or pipeline:** Single document, but it's the first in a chain. The PR/FAQ feeds into more detailed specs. The FAQ section often surfaces scope questions that become PRD material.

**Relevance to small dev tool orgs:** High. Writing a press release for a dev tool forces you to articulate the value proposition in plain language. The FAQ section naturally captures "why not just use X?" questions that matter for competitive positioning.

---

### 4. Amazon 6-Pager

**What it contains:** A narrative memo with 6 sections: Introduction (challenge/opportunity), Goals, Tenets (guiding principles), State of the Business (data-driven current state), Lessons Learned, Strategic Priorities. Plus unlimited appendix pages.

**Purpose:** Present a strategic proposal or business case in narrative form, forcing rigorous thinking. Used for major initiatives, not individual features.

**How it differs from a PRD:** The 6-pager is about strategy and business justification. It explains why an initiative matters and what principles should guide it. A PRD is about what to build.

**Relevance to small dev tool orgs:** Medium. The 6-page constraint is arbitrary for a small team, but the section structure (especially Tenets and Lessons Learned) is valuable. Tenets in particular -- "principles that guide this project" -- is a section missing from most frameworks that would be useful in a project thesis.

---

### 5. Marty Cagan's Opportunity Assessment (SVPG)

**What it contains:** Answers to 10 questions: (1) What problem does this solve? (2) For whom? (3) How big is the opportunity? (4) What alternatives exist? (5) Why are we best suited? (6) Why now? (7) Go-to-market approach? (8) Success metrics? (9) Critical success factors? (10) Recommendation: go or no-go?

**Purpose:** Lightweight go/no-go filter. Determine whether a product opportunity is worth pursuing before investing in discovery or requirements.

**How it differs from a PRD:** The opportunity assessment is explicitly pre-requirements. It doesn't describe what to build -- it asks whether you should build anything at all. The 10-question format is designed to be answered in a page or two.

**Single doc or pipeline:** Single document. It's a decision gate, not a workflow.

**Relevance to small dev tool orgs:** Very high. This is the closest framework to what the exploration is looking for. It's lightweight, question-driven, and explicitly positioned as the step before a PRD. Cagan's framing -- "most product failures can be traced back to the team not understanding the opportunity" -- is directly applicable.

---

### 6. Product Brief / One-Pager

**What it contains:** A concise document (1-2 pages) covering: problem statement, proposed solution (high level), target user, success metrics, key risks, and next steps. Sometimes includes competitive context.

**Purpose:** Align stakeholders on whether to pursue an initiative before investing in detailed requirements. Often used to get executive approval.

**How it differs from a PRD:** The product brief is the "should we do this?" document. The PRD is the "here's what we're doing" document. The brief intentionally avoids feature-level detail.

**Single doc or pipeline:** Single document. Feeds into PRD or design work if approved.

**Relevance to small dev tool orgs:** High. The one-pager format respects small-team time constraints. Lenny Rachitsky's "Initiative Strategy One-Pager" template is a well-known variant.

---

### 7. Product Thesis (Jason Evanish model)

**What it contains:** A 1-3 page document starting with the problem or opportunity statement, then covering target users, constraints, known risks, and open questions. Uses bullet points. Explicitly avoids detailing the solution.

**Purpose:** Clarify thinking and set up discussion with engineering and design partners about what's possible within constraints. Acts as the "why and what problem" doc that precedes the "what solution" doc.

**How it differs from a PRD:** The thesis focuses entirely on the problem space and constraints. It doesn't prescribe features. It's designed to be the starting point for collaborative solution exploration, not a hand-off spec.

**Single doc or pipeline:** Single document. Used for 10+ years as a pre-PRD artifact.

**Relevance to small dev tool orgs:** Very high. The thesis format matches the exploration's use case almost exactly -- "here's WHY this project should exist, WHAT problem it addresses, and what CONSTRAINTS we're working within."

---

### 8. Market Requirements Document (MRD)

**What it contains:** Market analysis, target personas, competitive landscape, business case, market sizing, and high-level problem definition. Does not include feature specifications.

**Purpose:** Establish the market justification for a product or initiative. Answers "is there a market for this?" before "what should we build?"

**How it differs from a PRD:** The MRD focuses on the "why" (market need), the PRD focuses on the "what" (product features). The MRD informs the PRD. Audience is executives and product leaders; PRD audience is designers and engineers.

**Single doc or pipeline:** Part of a formal pipeline: BRD -> MRD -> PRD -> SRD (Software Requirements Document). This hierarchy is traditional enterprise product management.

**Relevance to small dev tool orgs:** Low-medium. The formal BRD/MRD/PRD pipeline is heavyweight for a small team. But the core idea -- separate market justification from product specification -- is sound.

---

### 9. Project Charter (PMI/PMBOK)

**What it contains:** Project purpose, objectives, key deliverables, assumptions, constraints, risks, stakeholders, high-level timeline, and authority granted to the project manager.

**Purpose:** Formally authorize a project and grant resource allocation authority. It's a governance document.

**How it differs from a PRD:** The charter is about project governance (who, when, authority), not product definition (what to build). A PRD describes the product; a charter authorizes the effort to build it.

**Relevance to small dev tool orgs:** Low. The formal authorization aspect is unnecessary for a solo developer or small team. However, the "assumptions and constraints" section is universally useful.

---

### 10. Teresa Torres' Opportunity-Solution Tree

**What it contains:** A visual tree structure mapping: desired outcome -> opportunities (problems/needs) -> solution hypotheses -> experiments. Not a document per se but a structured thinking framework.

**Purpose:** Connect product discovery to business outcomes. Ensures solutions trace back to real user opportunities, not just ideas.

**How it differs from a PRD:** The OST is a discovery framework, not a specification. It maps the problem space before any requirements exist.

**Relevance to small dev tool orgs:** Medium. The visual structure is useful for thinking but is more of a facilitation tool than a document artifact.

---

### Cross-Framework Synthesis

**Common sections that appear across 3+ frameworks:**

| Section | Appears In |
|---------|-----------|
| Problem / Pain Point | Lean Canvas, Cagan OA, Product Brief, Product Thesis, PR/FAQ, MRD |
| Target User / Customer | All frameworks |
| Why Now / Market Timing | Cagan OA, Product Brief, PR/FAQ |
| Competitive Alternatives | Lean Canvas, Cagan OA, MRD, PR/FAQ (FAQ section) |
| Success Metrics | Lean Canvas, Cagan OA, Product Brief, 6-Pager |
| Unique Advantage / Differentiator | Lean Canvas, Cagan OA, PR/FAQ |
| Go/No-Go Recommendation | Cagan OA, Project Charter |
| Constraints / Assumptions | Product Thesis, Project Charter |
| Guiding Principles / Tenets | Amazon 6-Pager |
| Business Model / Revenue | Lean Canvas, BMC, MRD |

**The "universal core" of a pre-PRD artifact (appears in 5+ frameworks):**
1. Problem statement (what pain exists)
2. Target user (who has this pain)
3. Competitive landscape (what they do today)
4. Value proposition / differentiator (why us)
5. Success criteria (how we'd know it worked)

**The "useful additions" (appear in 2-4 frameworks):**
6. Why now / market timing
7. Constraints and assumptions
8. Guiding principles / tenets
9. Go/no-go recommendation
10. Revenue model / sustainability

## Implications

The industry has converged on a clear pattern: there is a distinct artifact layer between "idea" and "requirements" that every serious product framework acknowledges. The disagreement is only on format and formality, not on whether this layer should exist.

For a small dev tool org, the most applicable frameworks are Cagan's Opportunity Assessment, the Product Thesis, and the Amazon PR/FAQ. These three share key properties:
- Lightweight (1-3 pages)
- Question-driven or narrative (not checkbox-heavy)
- Focus on problem justification, not solution design
- Explicitly position themselves as pre-PRD

The formal enterprise pipeline (BRD -> MRD -> PRD) is too heavyweight, but its core insight -- separating market justification from product specification -- is exactly right.

A new artifact type for this workflow should probably combine elements from Cagan (the 10 questions as a skeleton), the Product Thesis (constraints and open questions), and the PR/FAQ (aspirational end-state narrative). The result would be a "Project Thesis" or "Opportunity Brief" that captures: why this should exist, who it's for, what makes us suited to build it, and what success looks like -- all without specifying features.

## Surprises

1. **Amazon uses two distinct pre-requirements docs, not one.** The PR/FAQ (aspirational, customer-facing) and the 6-pager (analytical, business-facing) serve different purposes. Most frameworks assume a single pre-PRD artifact, but Amazon's separation of "vision narrative" from "strategic analysis" is worth noting.

2. **"Why now?" is more common than expected.** Market timing appears in multiple frameworks as a first-class section, not just a nice-to-have. This makes sense for dev tools where ecosystem shifts (new language features, platform changes, competitor exits) create windows.

3. **Almost no framework includes "org fit" explicitly.** The question "does this project fit our organization's capabilities and direction?" is implicit in Cagan's "Why are we best suited?" but no framework gives it a dedicated section. For a small org where every project is a major commitment, org fit deserves more prominence than industry frameworks give it.

4. **The Product Thesis format is underappreciated.** Despite being used for 10+ years by experienced PMs, it's far less well-known than Lean Canvas or PR/FAQ. Its emphasis on constraints and open questions makes it arguably the most practical pre-PRD format for engineering-led teams.

## Open Questions

1. **Should vision narrative and strategic analysis be combined or separate?** Amazon splits them (PR/FAQ vs 6-pager). Most other frameworks combine them. For a small team, one document seems right, but having both a "here's the dream" section and a "here's the analysis" section within one doc could work.

2. **How does a pre-PRD artifact evolve over time?** Is it a snapshot (written once, then archived) or a living document that gets updated as the project matures? Most frameworks treat it as a decision gate artifact, but for longer-lived projects, the thesis may need revision.

3. **What's the right level of competitive analysis in a thesis vs. a separate artifact?** The current workflow already has a Competitive Analysis artifact type. Should the thesis just reference it, or should it include a lightweight competitive section?

4. **How should a thesis artifact interact with the existing PRD workflow?** Should creating a PRD require a thesis, or should the thesis be optional? What fields from the thesis should auto-populate into a PRD?

5. **Does the "go/no-go" framing (from Cagan) make sense for a small org?** In a small team, the person writing the thesis is often the person making the decision. The thesis might serve more as "clarify my own thinking" than "convince a decision-maker."

## Summary

Every major product framework acknowledges a distinct artifact layer between "idea" and "requirements" -- the industry consensus is that this layer should capture problem justification, target user, competitive context, and success criteria without specifying features, typically in 1-3 pages. For a small dev tool org, the most applicable models are Cagan's Opportunity Assessment (10 questions as skeleton), the Product Thesis (constraints and open questions), and Amazon's PR/FAQ (aspirational end-state narrative), which could be synthesized into a single "Project Thesis" artifact type. The biggest open question is whether the vision narrative ("here's the dream") and strategic analysis ("here's the justification") should live in one document or two, and how this new artifact should gate or feed into the existing PRD workflow.
