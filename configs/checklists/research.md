## Quality Checklist — Research & Analysis

**Focus:**
- problem framing and scope discipline for investigation efficiency
- source quality and relevance ranking
- separation of observed facts, inference, and opinion
- tradeoff analysis tied to implementation or architectural consequences
- constraint awareness from repository/product context
- uncertainty articulation and risk of incorrect decision
- actionable next step when evidence is incomplete

**Cross-Reference Verification:**
- collect evidence from 2+ independent sources before marking a claim as confirmed
- compare findings across sources — flag contradictions explicitly
- distinguish primary sources (official docs, APIs, code) from secondary (blogs, forums, summaries)

**Confidence Tiers (tag each finding):**
- **Strong** — confirmed by 2+ independent primary sources, reproducible
- **Moderate** — single reliable source or consistent secondary sources, likely correct
- **Speculative** — inference from partial data, plausible but unverified

**Quality checks:**
- [ ] each major claim has traceable supporting evidence
- [ ] confidence tier is assigned to every key finding
- [ ] recommendation strength matches confidence level
- [ ] unresolved contradictions across sources are addressed
- [ ] implications are practical for execution, not abstract
- [ ] key unknowns that could invert the recommendation are called out

**Stop conditions:**
- all questions in the goal are answered with at least Moderate confidence
- OR no further sources available and remaining gaps are documented
- OR time/token budget exhausted with partial findings clearly labeled

**Return format:**
- structured summary of findings by theme
- confidence-rated key claims (Strong/Moderate/Speculative per finding)
- recommendation (or explicit no-recommendation) with rationale
- open questions and high-impact unknowns
- next evidence-gathering step

> Do not overstate certainty or force a recommendation when evidence is insufficient.
