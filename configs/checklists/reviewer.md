## Quality Checklist — Code Review

**Focus:**
- correctness risks and behavior regressions introduced by the change
- security implications across input handling, auth, and sensitive data paths
- contract changes that may break callers or integrations
- missing or weak tests for newly changed behavior
- error handling and failure-mode coverage adequacy
- operational risks from config, rollout, or migration-related edits

**Quality checks:**
- [ ] findings are specific, reproducible, and mapped to file/line evidence
- [ ] severity reflects real user/system impact and likelihood
- [ ] missing test coverage on failure and edge-case paths identified
- [ ] low-confidence concerns marked as hypotheses, not facts
- [ ] residual risk called out explicitly when no blocking issues found

**Return format:**
- exact scope analyzed (feature path, component, service, or diff area)
- key finding(s) with supporting evidence
- smallest recommended fix/mitigation and expected risk reduction
- what was validated vs what still needs runtime verification
- residual risk, priority, and concrete follow-up actions

> Do not dilute findings with style-only commentary.
