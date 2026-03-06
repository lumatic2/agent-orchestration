## Research Findings

The routing in this multi-agent orchestration system is governed by a two-tiered approach: a strategic decision-making process outlined in `ROUTING_TABLE.md`, and a tactical implementation layer handled by `scripts/orchestrate.sh`.

### Strategic Routing (`ROUTING_TABLE.md`)
- **Decision Flow**: A hierarchical set of questions guides the orchestrator (Claude Code) in selecting the most appropriate agent. This prioritizes Gemini for any research component and Claude Code alone for small, quick tasks.
- **Agent Specialization**:
    - **Claude Code**: Primarily for orchestration, task decomposition, final integration, small code reviews, and Notion/data operations (due to MCP access). It *never researches* directly.
    - **Gemini**: Dedicated to research, document analysis, summarization, web searches, and multimedia analysis (due to multimodal capabilities and 1M context). Flash is the default, Pro is used sparingly for deep analysis.
    - **Codex**: Handles heavy coding tasks like large refactors, scaffolding, bug-fixing loops, and bulk text processing (translation, document writing). Different models (gpt-5.3-codex, codex-spark) are chosen based on risk and scale.
- **Domain-Specific Routing**: Specific shell scripts (`tax_agent.sh`, `expert_agent.sh`, `image_agent.sh`, etc.) are provided for specialized tasks, often utilizing Gemini for core intelligence and Codex for code generation where applicable.
- **Interactive Workflow**: For brainstorming and reference research, a user-centric iterative process (gather, present, select, refine) is defined.
- **Large Document Handling**: For documents over 50 pages, Claude delegates summarization to Gemini, then processes Gemini's summary.

### Tactical Implementation (`orchestrate.sh`)
- **Queue Management**: The script maintains a persistent queue (`queue/`) for all tasks, managing their lifecycle (pending, dispatched, completed, queued).
- **Agent Invocation**: It directly calls the `codex` and `gemini` CLI tools, passing the task brief and selected model.
- **Rate Limit Detection & Fallback**:
    - The `is_rate_limited` function detects common rate limit indicators in agent output.
    - `run_codex` and `run_gemini` functions handle dispatch.
    - `run_with_fallback_code` and `run_with_fallback_research` provide a robust fallback mechanism:
        - For code tasks: Codex (gpt-5.3-codex) → Gemini (gemini-2.5-flash).
        - For research tasks: Gemini (gemini-2.5-flash) → Codex (gpt-5.3-codex).
    - If all agents are rate-limited, the task is re-queued.
- **Inter-dispatch Guard**: `dispatch_guard` enforces a minimum 3-second gap between consecutive dispatches to the same agent family to prevent rapid rate limiting.
- **Logging and Metadata**: Each task receives a dedicated directory in `queue/` containing a `meta.json` (status, agent, model, timestamps) and `brief.md`. Detailed agent outputs are logged in `logs/`.
- **Utility Commands**: `--boot`, `--status`, `--resume`, `--complete`, `--cost`, `--clean` enable comprehensive management and reporting of the task queue.

## Conclusion
The routing system is well-defined, with clear strategic guidelines and a resilient implementation. The separation of concerns between the orchestrator's decision-making and the script's execution, coupled with robust queue management and fallback mechanisms, ensures tasks are efficiently delegated and processed even under challenging conditions like rate limits.