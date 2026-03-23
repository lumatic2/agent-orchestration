## Quality Checklist — Data Research

**Focus:**
- evidence relevance to the stated business/engineering question
- source quality (freshness, coverage, methodology, and bias)
- metric definition consistency across compared sources
- assumptions required to bridge incomplete or mismatched datasets
- uncertainty quantification and confidence communication
- implications for product, architecture, or operational decisions
- smallest next data slice that would reduce uncertainty most

**Quality checks:**
- [ ] key claims trace to concrete source evidence
- [ ] metric/definition mismatches are called out explicitly
- [ ] survivorship, selection, or reporting bias risks are checked
- [ ] conclusions are proportional to evidence strength
- [ ] missing data that blocks high-confidence recommendation is noted

**Return format:**
- sourced summary tied to the original question
- strongest evidence points and confidence level
- assumptions and caveats affecting interpretation
- practical decision implication
- prioritized next data/research step

> Do not present inferred numbers as measured facts.
