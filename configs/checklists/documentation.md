## Quality Checklist — Documentation

**Focus:**
- faithful mapping between docs and actual code/tool behavior
- task-oriented guidance that supports setup, operation, and recovery workflows
- prerequisite clarity: versions, permissions, and environment assumptions
- example quality with copy-paste safety and realistic defaults
- change impact communication for upgraded workflows or breaking behavior
- cross-reference structure that reduces documentation drift
- documentation maintainability with clear ownership boundaries

**Quality checks:**
- [ ] instructions match current repository commands and file paths
- [ ] error-prone steps include safety notes and rollback guidance
- [ ] examples are accurate, minimal, and show expected outputs
- [ ] version/environment-specific behavior is called out
- [ ] areas requiring runtime validation are flagged

**Return format:**
- exact workflow/tool boundary documented
- primary friction/failure source and supporting evidence
- smallest safe change and key tradeoffs
- validations performed and remaining checks
- residual risk and prioritized follow-up actions

> Do not invent undocumented behavior or operational guarantees.
