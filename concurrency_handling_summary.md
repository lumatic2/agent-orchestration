## Research Findings: How the Multi-Agent Orchestration System Handles Concurrent Tasks

The multi-agent orchestration system manages concurrent tasks primarily through a centralized orchestration model, task queuing, and clear delineation of agent responsibilities, rather than employing complex, low-level concurrency control mechanisms like distributed locks or semaphores for simultaneous execution of a single task.

### Key Mechanisms:

1.  **Centralized Orchestration (Claude Code)**:
    *   Claude Code acts as the primary orchestrator, responsible for planning, judgment, and delegation of tasks.
    *   It uses the `orchestrate.sh` script for managing the task lifecycle.

2.  **Task Queuing System**:
    *   Tasks are managed within a dedicated `queue/` directory, with each task having a unique ID (`TXXX_*`) and a `meta.json` file to track its status (e.g., `pending`, `queued`, `dispatched`, `completed`).
    *   The system includes helper functions for managing the queue, such as `next_task_id`, `create_queue_entry`, and `update_meta_status`.

3.  **Sequential Task Dispatch with Requeuing**:
    *   Tasks are typically dispatched sequentially from the queue. The `--resume` functionality in `orchestrate.sh` specifically targets the "oldest pending/queued task."
    *   Tasks can be re-queued with a `queued_reason` (e.g., `rate_limited`, `all_agents_rate_limited`), indicating that the system manages load and agent availability by delaying tasks rather than executing them in parallel when resources are constrained. This acts as a form of flow control.

4.  **Clear Agent Scoping and Constraints**:
    *   Worker agents (Codex, Gemini, Claude subagents) are instructed to "Stay in scope," "Follow constraints exactly," and "Do not modify files outside your assigned scope."
    *   This design principle minimizes potential conflicts by ensuring agents work on distinct parts of a project, reducing the need for dynamic, fine-grained concurrency control.

5.  **User Discipline for Multi-Terminal Parallelism**:
    *   The system supports parallel work across multiple terminals, but explicitly warns against simultaneously modifying the same files from different terminals.
    *   This implies that file-level concurrency management in such scenarios is largely a user responsibility, not an automated system feature.

6.  **Sequential Pipelines for Complex Workflows**:
    *   Evidence from E2E tests (e.g., "Gemini researched → Codex generated code → Claude verified") suggests that complex tasks are often broken down into sequential steps, where the output of one agent serves as the input for the next.

### Conclusion:

The orchestration system's approach to concurrency is pragmatic, prioritizing robust task management, conflict prevention through design and clear rules, and controlled flow of tasks over simultaneous execution of a single task across multiple agents. The primary method of handling what might appear as concurrent needs is through intelligent task decomposition and sequential processing, with rate-limiting and re-queuing as key mechanisms for managing resource contention.

### Relevant Files:

*   `ORCHESTRATION_SETUP.md`: Provides context on multi-terminal parallel operation and the architecture with Claude Code as orchestrator.
*   `SHARED_PRINCIPLES.md`: Defines behavioral rules for worker agents that help prevent conflicts (e.g., scoping, constraints).
*   `SHARED_MEMORY.md`: Contains project-specific mentions of "P_parallel" data and hints at a task queue system.
*   `scripts/orchestrate.sh`: The core script implementing the task queuing, dispatch, and status management logic, including rate-limiting handling.
*   `tests/e2e/test_dispatch_cycle.sh`: Likely contains tests for the task dispatch cycle, which would implicitly test aspects of task handling and queuing.