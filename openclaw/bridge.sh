#!/usr/bin/env bash
# OpenClaw → orchestrate.sh 브리지

AGENT_TYPE="${1:-codex}"   # codex | gemini | codex-spark | gemini-pro
TASK="${2}"
TASK_NAME="${3:-openclaw-$(date +%s)}"

ORCH="$HOME/Desktop/agent-orchestration/scripts/orchestrate.sh"

if [ ! -f "$ORCH" ]; then
  echo "ERROR: orchestrate.sh not found at $ORCH" >&2
  exit 1
fi

bash "$ORCH" "$AGENT_TYPE" "$TASK" "$TASK_NAME"
