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

**Output rules (CRITICAL):**
- Write the full report content directly to stdout — do NOT summarize as "I completed the task" or "analysis is done"
- Do not use todo tools, file write tools, or any side-channel to store results — output everything inline
- Minimum output: 500 characters of substantive findings; if under this threshold the response is considered invalid
- Always respond in the same language as the task prompt (if the prompt is in Korean, respond in Korean)
- Do NOT write results to any file — do not use file write tools or save to paths like C:\Users\... — output everything to stdout only
