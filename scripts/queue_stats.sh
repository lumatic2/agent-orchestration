#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
QUEUE_DIR="$REPO_DIR/queue"

read_meta_field() {
  local meta_file="$1" field="$2"
  grep -o "\"$field\": *\"[^\"]*\"" "$meta_file" 2>/dev/null \
    | sed 's/.*: *"\([^"]*\)"/\1/' \
    | head -n 1 || true
}

total=0
completed=0
pending=0
queued=0
dispatched=0
failed=0
unknown=0

non_completed_tasks=()

shopt -s nullglob
for task_dir in "$QUEUE_DIR"/T[0-9][0-9][0-9]_*/; do
  meta_file="$task_dir/meta.json"
  [ -f "$meta_file" ] || continue

  total=$((total + 1))

  id="$(read_meta_field "$meta_file" id)"
  name="$(read_meta_field "$meta_file" name)"
  status="$(read_meta_field "$meta_file" status)"

  if [ -z "$id" ]; then
    id="$(basename "$task_dir" | cut -d_ -f1)"
  fi
  if [ -z "$name" ]; then
    name="$(basename "$task_dir" | cut -d_ -f2-)"
  fi

  case "$status" in
    completed)
      completed=$((completed + 1))
      ;;
    pending)
      pending=$((pending + 1))
      ;;
    queued)
      queued=$((queued + 1))
      ;;
    dispatched)
      dispatched=$((dispatched + 1))
      ;;
    failed)
      failed=$((failed + 1))
      ;;
    *)
      unknown=$((unknown + 1))
      status="unknown"
      ;;
  esac

  if [ "$status" != "completed" ]; then
    non_completed_tasks+=("$id|$name|$status")
  fi
done

echo "Queue summary for: $QUEUE_DIR"
echo "--------------------------------"
echo "Total tasks: $total"
echo "  completed : $completed"
echo "  pending   : $pending"
echo "  queued    : $queued"
echo "  dispatched: $dispatched"
echo "  failed    : $failed"
if [ "$unknown" -gt 0 ]; then
  echo "  unknown   : $unknown"
fi

echo
echo "Non-completed tasks (ID | Name | Status):"
if [ "${#non_completed_tasks[@]}" -gt 0 ]; then
  printf "%-8s %-30s %-12s\n" "ID" "NAME" "STATUS"
  for task in "${non_completed_tasks[@]}"; do
    IFS='|' read -r id name status <<< "$task"
    printf "%-8s %-30s %-12s\n" "$id" "$name" "$status"
  done
else
  echo "  (none)"
fi
