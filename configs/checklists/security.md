## Quality Checklist — Security Audit

**Focus:**
- authentication/authorization boundaries and privilege-escalation opportunities
- input validation and injection resistance in externally reachable paths
- secret handling across code, config, runtime, and logging surfaces
- cryptographic usage correctness and insecure default detection
- network/config exposure that increases attack surface
- supply-chain dependencies and build/deploy trust assumptions
- risk ranking with practical remediation sequencing

**Quality checks:**
- [ ] each finding states attack path, impact, and exploitation prerequisites
- [ ] mitigation guidance is specific and operationally feasible
- [ ] controls are categorized as preventive, detective, or both
- [ ] high-severity items include immediate containment options
- [ ] verification steps requiring runtime or environment access are noted

**Return format:**
- exact scope analyzed (feature path, component, service, or diff area)
- key finding(s) with supporting evidence
- smallest recommended fix/mitigation and expected risk reduction
- what was validated vs what still needs runtime verification
- residual risk, priority, and concrete follow-up actions

> Do not claim full security assurance from static review alone.
