#!/usr/bin/env bash

set -euo pipefail

[[ -n "${_VERIFIED_REGISTRY_LOADED:-}" ]] && return 0
_VERIFIED_REGISTRY_LOADED=1

STATE_DIR="${STATE_DIR:-${PWD}/state}"
_VERIFIED_REGISTRY_FILE_NAME="verified_registry.json"

_registry_python() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "python3"
    return 0
  fi
  printf '%s' "python"
}

_registry_now_iso() {
  "$(_registry_python)" - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).astimezone().isoformat())
PY
}

_registry_file_path() {
  printf '%s/%s' "$STATE_DIR" "$_VERIFIED_REGISTRY_FILE_NAME"
}

registry_init() {
  mkdir -p "$STATE_DIR"
  local registry_file
  registry_file="$(_registry_file_path)"

  if [[ -f "$registry_file" ]]; then
    return 0
  fi

  "$(_registry_python)" - "$registry_file" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
data = {
    "metrics": {},
    "citations": {},
    "metadata": {
        "created": datetime.now(timezone.utc).astimezone().isoformat(),
        "stage": "init",
    },
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
PY
}

registry_add_metric() {
  local key="${1:-}"
  local value="${2:-}"
  local source="${3:-}"
  local stage="${4:-}"

  if [[ -z "$key" || -z "$value" || -z "$source" || -z "$stage" ]]; then
    echo "registry_add_metric: requires key value source stage" >&2
    return 1
  fi

  registry_init
  local registry_file
  registry_file="$(_registry_file_path)"

  "$(_registry_python)" - "$registry_file" "$key" "$value" "$source" "$stage" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

path, key, raw_value, source, stage = sys.argv[1:6]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

metrics = data.setdefault("metrics", {})

value = raw_value
num_match = re.fullmatch(r"[+-]?\d+(?:\.\d+)?", raw_value.strip())
if num_match:
    try:
        if "." in raw_value:
            value = float(raw_value)
        else:
            value = int(raw_value)
    except Exception:
        value = raw_value

metrics[key] = {
    "value": value,
    "source": source,
    "stage": stage,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(),
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
PY
}

registry_add_citation() {
  local ref_key="${1:-}"
  local title="${2:-}"
  local doi_or_url="${3:-}"
  local verified="${4:-}"

  if [[ -z "$ref_key" || -z "$title" || -z "$doi_or_url" || -z "$verified" ]]; then
    echo "registry_add_citation: requires ref_key title doi_or_url verified" >&2
    return 1
  fi

  registry_init
  local registry_file
  registry_file="$(_registry_file_path)"

  "$(_registry_python)" - "$registry_file" "$ref_key" "$title" "$doi_or_url" "$verified" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, ref_key, title, doi_or_url, verified_raw = sys.argv[1:6]
verified = str(verified_raw).strip().lower() in {"true", "1", "yes", "y"}

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

citations = data.setdefault("citations", {})
citations[ref_key] = {
    "title": title,
    "doi_or_url": doi_or_url,
    "verified": verified,
    "ts": datetime.now(timezone.utc).astimezone().isoformat(),
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
PY
}

registry_extract_from_experiment() {
  local experiment_path="${1:-}"
  local stage="${2:-S08}"

  if [[ -z "$experiment_path" ]]; then
    echo "registry_extract_from_experiment: requires experiment path" >&2
    return 1
  fi
  if [[ ! -f "$experiment_path" ]]; then
    echo "registry_extract_from_experiment: file not found: $experiment_path" >&2
    return 1
  fi

  local pair
  while IFS=$'\t' read -r key value; do
    [[ -z "$key" || -z "$value" ]] && continue
    registry_add_metric "$key" "$value" "experiment" "$stage"
  done < <("$(_registry_python)" - "$experiment_path" <<'PY'
import json
import re
import sys
from collections import OrderedDict

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

pairs = OrderedDict()

name_pattern = r"[A-Za-z_][A-Za-z0-9_.-]*"
value_pattern = r"[+-]?\d+(?:\.\d+)?"

for m in re.finditer(rf"\b({name_pattern})\b\s*[:=]\s*({value_pattern})\b", text):
    pairs.setdefault(m.group(1), m.group(2))

for m in re.finditer(rf"\|\s*({name_pattern})\s*\|\s*({value_pattern})\s*\|", text):
    pairs.setdefault(m.group(1), m.group(2))

try:
    obj = json.loads(text)
except Exception:
    obj = None

if obj is not None:
    def walk(node, parent_key=""):
        if isinstance(node, dict):
            for k, v in node.items():
                walk(v, str(k))
        elif isinstance(node, list):
            for item in node:
                walk(item, parent_key)
        else:
            if parent_key and isinstance(node, (int, float)) and not isinstance(node, bool):
                pairs.setdefault(parent_key, str(node))

    walk(obj)

for k, v in pairs.items():
    print(f"{k}\t{v}")
PY
)
}

registry_verify_draft() {
  local draft_path="${1:-}"

  if [[ -z "$draft_path" ]]; then
    echo "registry_verify_draft: requires draft path" >&2
    return 1
  fi
  if [[ ! -f "$draft_path" ]]; then
    echo "registry_verify_draft: file not found: $draft_path" >&2
    return 1
  fi

  registry_init
  local registry_file
  registry_file="$(_registry_file_path)"

  "$(_registry_python)" - "$registry_file" "$draft_path" <<'PY'
import json
import math
import re
import sys

registry_path, draft_path = sys.argv[1:3]

with open(registry_path, "r", encoding="utf-8") as f:
    registry = json.load(f)
with open(draft_path, "r", encoding="utf-8", errors="ignore") as f:
    draft = f.read()

metrics = []
for key, node in (registry.get("metrics") or {}).items():
    if not isinstance(node, dict):
        continue
    raw = node.get("value")
    try:
        v = float(raw)
    except Exception:
        continue
    if not math.isfinite(v):
        continue
    metrics.append({
        "key": key,
        "value": v,
        "source": str(node.get("source", "unknown")),
        "stage": str(node.get("stage", "unknown")),
    })

number_re = re.compile(r"(?<![A-Za-z0-9_])([+-]?\d+(?:\.\d+)?)(%?)(?![A-Za-z0-9_])")

matches = list(number_re.finditer(draft))
if not matches:
    print("UNVERIFIED: no numbers found in draft")
    sys.exit(1)

verified = 0

for m in matches:
    raw_num = m.group(1)
    suffix = m.group(2)
    label = raw_num + suffix

    try:
        val = float(raw_num)
    except Exception:
        print(f"UNVERIFIED: {label} (parse error)")
        continue

    candidates = [val]
    if suffix == "%":
        candidates.append(val / 100.0)

    best = None
    best_rel = None
    for c in candidates:
        for metric in metrics:
            denom = max(abs(metric["value"]), 1e-12)
            rel = abs(c - metric["value"]) / denom
            if best_rel is None or rel < best_rel:
                best_rel = rel
                best = metric

    if best is None:
        print(f"UNVERIFIED: {label} (no registry metrics)")
        continue

    if best_rel is not None and best_rel <= 0.02:
        verified += 1
        print(
            f"VERIFIED: {label} -> {best['key']}={best['value']} "
            f"(source={best['source']}, stage={best['stage']}, rel_diff={best_rel:.4f})"
        )
    elif best_rel is not None and best_rel <= 0.10:
        print(
            f"MISMATCH: {label} ~ {best['key']}={best['value']} "
            f"(source={best['source']}, stage={best['stage']}, rel_diff={best_rel:.4f})"
        )
    else:
        print(f"UNVERIFIED: {label}")

total = len(matches)
ratio = verified / total if total > 0 else 0.0
print(f"SUMMARY: verified={verified}/{total} ratio={ratio:.2f}")
sys.exit(0 if ratio >= 0.80 else 1)
PY
}

registry_get_prompt_prefix() {
  registry_init
  local registry_file
  registry_file="$(_registry_file_path)"

  "$(_registry_python)" - "$registry_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

print("## 검증된 수치 (이 수치만 사용할 것)")
print("| 지표 | 값 | 출처 |")
print("| --- | --- | --- |")

metrics = data.get("metrics") or {}
for key in sorted(metrics.keys()):
    node = metrics.get(key) or {}
    value = node.get("value", "")
    source = node.get("source", "")
    print(f"| {key} | {value} | {source} |")
PY
}

_registry_self_test() {
  local failed=0
  local tmp_root
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/verified_registry_test.XXXXXX" 2>/dev/null || mktemp -d -t verified_registry_test)"

  local old_state_dir="${STATE_DIR:-}"
  STATE_DIR="$tmp_root/state"
  mkdir -p "$STATE_DIR"

  registry_init
  registry_add_metric "f1" "0.755" "experiment" "S08"
  registry_add_citation "smith2024" "Sample Study" "https://example.com/smith2024" "true"

  local persisted_ok
  persisted_ok="$("$(_registry_python)" - "$(_registry_file_path)" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    d = json.load(f)

ok = (
    "f1" in d.get("metrics", {})
    and d["metrics"]["f1"].get("value") in (0.755, "0.755")
    and "smith2024" in d.get("citations", {})
    and d["citations"]["smith2024"].get("verified") is True
)
print("1" if ok else "0")
PY
)"
  [[ "$persisted_ok" == "1" ]] || failed=1

  local exp_file
  exp_file="$tmp_root/experiment.txt"
  cat > "$exp_file" <<'EOF'
accuracy: 0.95
precision = 0.91
| recall | 0.88 |
{"auc": 0.93}
EOF

  registry_extract_from_experiment "$exp_file" "S08"

  local draft_good
  draft_good="$tmp_root/draft_good.md"
  cat > "$draft_good" <<'EOF'
Model results: accuracy reached 95.3%, precision was 0.911, recall stayed at 0.88, and f1 was 0.755. Baseline was 0.5.
EOF

  if ! registry_verify_draft "$draft_good" >/dev/null 2>&1; then
    failed=1
  fi

  local draft_bad
  draft_bad="$tmp_root/draft_bad.md"
  cat > "$draft_bad" <<'EOF'
Draft values: 0.83 and 0.12.
EOF

  if registry_verify_draft "$draft_bad" >/dev/null 2>&1; then
    failed=1
  fi

  local prefix
  prefix="$(registry_get_prompt_prefix)"
  if [[ -z "$prefix" || "$prefix" != *"|"* ]]; then
    failed=1
  fi

  rm -rf "$tmp_root"
  if [[ -n "$old_state_dir" ]]; then
    STATE_DIR="$old_state_dir"
  fi

  if [[ "$failed" -eq 0 ]]; then
    echo "PASS"
    return 0
  fi
  echo "FAIL"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--test" ]]; then
    _registry_self_test
  fi
fi
