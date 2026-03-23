## Quality Checklist — Test Automation

**Focus:**
- prioritizing high-risk behavior for durable regression coverage
- test architecture choices that keep suites deterministic and maintainable
- fixture and data setup that minimizes flakiness and hidden coupling
- assertion quality focused on behavior contracts, not implementation detail
- integration points where automated coverage prevents recurring defects
- test runtime cost and parallelization tradeoffs for CI stability
- clear mapping from bug/risk to added or updated automated tests

**Quality checks:**
- [ ] tests fail for the broken behavior and pass after the fix
- [ ] new tests are deterministic and avoid timing-dependent fragility
- [ ] test scope is minimal but sufficient for regression prevention
- [ ] CI/runtime impact is acceptable and documented if increased
- [ ] environment or mock assumptions limiting confidence are called out

**Return format:**
- exact scope analyzed (feature path, component, service, or diff area)
- key finding(s) with supporting evidence
- smallest recommended fix/mitigation and expected risk reduction
- what was validated vs what still needs runtime verification
- residual risk, priority, and concrete follow-up actions

> Do not introduce broad framework migration in test suites.
