# Exploration Decisions: release-process

## Round 1
- Approach B (commit-first, then tag) over Approach A (tag-first): Marketplace reads plugin.json at the tagged commit, so the version must be correct before tagging. Approach A creates a window where the tag exists with wrong manifests.
- Sentinel value (0.0.0-dev) on main over real versions: Prevents drift, simpler CI check, aligns with marketplace caching. Real versions only exist at release tags.
- Design doc is the right artifact: The problem is well-understood ("how to build"), not "what to build". Implementation decisions (workflow architecture, sentinel vs real, skill integration) are the focus.
- Adversarial demand acknowledged but not blocking: Version drift is a technical correctness problem (marketplace serves stale versions), not just a nice-to-have. Single-contributor project doesn't invalidate the need — it means demand evidence lives in the code state, not in issues.
