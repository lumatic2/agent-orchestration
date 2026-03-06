## Routing Analysis Report

This report analyzes the routing mechanisms implemented within the multi-agent orchestration system, based on the provided `ROUTING_TABLE.md`.

### Core Routing Principles

1.  **Queue-Based Prioritization**: All tasks are first routed through a persistent queue (`scripts/orchestrate.sh --boot`). This ensures continuity across sessions and prioritizes:
    *   Stale dispatched tasks (resumption).
    *   Previously rate-limited queued tasks (retries).
    *   Pending tasks.
    *   New tasks (only after queue is clear).

2.  **Orchestration Decision Flow**: A hierarchical decision-making process determines the initial agent assignment:
    *   **Research First**: Any task involving research is first delegated to Gemini. Claude Code explicitly "never researches."
    *   **Task Complexity/Size**:
        *   **Claude Alone**: For small tasks (under 5 mins, 1-3 files), data analysis, or Notion operations.
        *   **Gemini Alone**: Pure research, document analysis without code changes.
        *   **Codex Alone**: Heavy code work (5+ files, test loops, scaffolding) with no research.
        *   **Combined**: Specific combinations (Claude + Gemini, Claude + Codex) for research-then-code scenarios, or full orchestration for deep research + heavy implementation.
    *   **Usage Limits**: If Claude is near usage limits, tasks may be directed to Codex or Gemini alone.

3.  **Agent Specialization and Model Selection**:
    *   **Gemini**: Primary for research, web search, document analysis (especially large ones due to 1M context), and multimodal inputs. Defaults to `2.5 Flash`, with `2.5 Pro` reserved for deep analysis (sparingly, 100/day limit). Structured output (bullet points, Tactical Map for coding research) is enforced.
    *   **Codex**: Primary for code generation, refactoring, error fixing, and test execution. `gpt-5.3-codex` is the default/heavy model, while `codex-spark` is used for lighter tasks (e.g., boilerplate, quick edits) due to its speed. It's also used for document writing, summarization, and translation when web search is not required.
    *   **Claude Code (Opus)**: Acts as the orchestrator, responsible for task decomposition, final integration, and high-level judgment. It uses cheaper subagents (Haiku for codebase exploration/file classification, Sonnet for code review) to conserve Opus tokens.
    *   **Domain-Specific Scripts**: Specialized scripts (`tax_agent.sh`, `expert_agent.sh`, `content_pipeline.sh`, `image_agent.sh`, `video_edit.sh`) handle specific domains, often routing through Gemini Flash initially.

### Routing Criteria Summary

| Criterion           | Primary Agent(s)                   | Key Characteristics                                                                      |
| :------------------ | :--------------------------------- | :--------------------------------------------------------------------------------------- |
| Research Needed     | Gemini                             | Always first if research involved.                                                       |
| Code Changes        | Codex (sometimes Claude for small) | Large refactors, scaffolding, test loops go to Codex. Small edits to Claude.             |
| Complexity          | Claude (Orchestrator)              | Decomposes complex tasks, manages integration.                                           |
| Document Analysis   | Gemini                             | Handles large texts, multimodal inputs, provides summaries for Claude.                   |
| Specific Domains    | Specialized Scripts (e.g., tax_agent) | Leverage Gemini or Codex based on script logic.                                          |
| Cost/Rate Limits    | Claude, Gemini, Codex              | Fallback mechanisms, model selection (Flash vs. Pro, Spark vs. Codex) to manage costs.   |

### Workflow Patterns

*   **Interactive Workflow**: For brainstorming/research, Gemini collects data, Claude presents options, and the user makes decisions before implementation by Codex.
*   **Large Document Handling**: Claude delegates large document reading to Gemini, then processes Gemini's summary.

### Fallback and Safety

*   **Fallback Rules**: A defined chain ensures continuity if an agent hits rate limits (e.g., Codex → Claude Sonnet → Gemini Flash for code tasks).
*   **Scope Isolation**: Enforces non-overlapping work areas or sequential execution to prevent conflicts during parallel processing.

### Conclusion

The system employs a sophisticated, multi-layered routing strategy that prioritizes task type, complexity, agent specialization, and resource management (cost, rate limits). The orchestrator, Claude Code, intelligently delegates tasks to specialized worker agents (Gemini for research, Codex for code) and manages the overall workflow, including queue processing, model selection, and fallback mechanisms. This structure aims to maximize efficiency, leverage agent strengths, and ensure task completion even under constraints.