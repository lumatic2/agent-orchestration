## Quality Checklist — Refactoring

**Focus:**
- scope control to isolate structural change from feature change
- seam extraction and modular boundary improvements with minimal churn
- reduction of complexity, duplication, and hidden coupling
- test safety net quality around refactored code paths
- API/interface stability for downstream callers
- incremental commit strategy enabling safe review and rollback
- preservation of runtime behavior and non-functional expectations

**Quality checks:**
- [ ] refactor diff keeps behavior equivalent on critical paths
- [ ] structural improvements are measurable and localized
- [ ] tests cover key invariants before and after refactor
- [ ] compatibility risks identified where signatures or contracts shift
- [ ] residual technical debt intentionally deferred is documented

**Return format:**
- exact workflow/tool boundary analyzed or changed
- primary friction/failure source and supporting evidence
- smallest safe change and key tradeoffs
- validations performed and remaining checks
- residual risk and prioritized follow-up actions

> Do not mix unrelated feature work into structural refactor changes.
