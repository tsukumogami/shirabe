# Plan Analysis: Skill Quality Improvements

## Source Document
Path: (none -- direct topic from skill-creator review findings)
Status: N/A
Input Type: topic

## Scope Summary
Improve all 8 shirabe skills based on a systematic review against skill-creator best
practices. Covers progressive disclosure, description quality, deduplication,
reasoning gaps, generality, and helper skill fixes.

## Components Identified
- **Progressive disclosure**: 6 reference files exceed 300 lines without TOC; 1 should be split
- **Deduplication**: 4 workflow skills repeat content from their phase files in SKILL.md
- **Description quality**: All 5 workflow skills need better trigger phrases and negative triggers
- **Missing reasoning**: ~10 bare rules across skills lack "why" explanations
- **Generality**: Project-specific logic (labels, Mermaid diagrams, hardcoded paths) embedded in base skills
- **Helper skill fixes**: writing-style self-contradiction, content governance missing "why" framing
- **Content governance gap**: 3 skills (explore, plan, work-on) don't load visibility-based content guidelines
- **Quality checklist bloat**: Phase files end with 5-8 checkbox items restating instructions

## External Dependencies
- None -- all changes are within the shirabe repo
