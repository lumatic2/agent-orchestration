## Quality Checklist — Performance Engineering

**Focus:**
- latency and throughput bottleneck identification in critical paths
- CPU, memory, I/O, and allocation hotspots tied to real workload behavior
- database query efficiency and caching effectiveness in slow operations
- concurrency model limitations causing queueing, contention, or starvation
- frontend rendering and long-task regressions where UI is part of issue
- capacity headroom and scaling characteristics under burst scenarios
- tradeoffs between optimization impact, complexity, and maintainability

**Quality checks:**
- [ ] bottleneck claims include measurement source and confidence level
- [ ] proposed optimization targets dominant cost center, not minor noise
- [ ] regression risk and fallback strategy for performance changes noted
- [ ] before/after validation plan is concrete and reproducible
- [ ] benchmark/load-test steps requiring environment-specific execution are called out

**Return format:**
- exact scope analyzed (feature path, component, service, or diff area)
- key finding(s) with supporting evidence
- smallest recommended fix/mitigation and expected risk reduction
- what was validated vs what still needs runtime verification
- residual risk, priority, and concrete follow-up actions

> Do not propose broad rewrites for marginal gains.
