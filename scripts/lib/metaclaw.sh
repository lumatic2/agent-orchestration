#!/usr/bin/env bash

if [[ -n "${_METACLAW_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_METACLAW_LOADED=1

set -euo pipefail

: "${VAULT:=${HOME}/vault}"
: "${STATE_DIR:=.state}"
: "${SLUG:=unknown-run}"

_metaclaw_python_bin() {
  if [[ -n "${_METACLAW_PYTHON_BIN:-}" ]]; then
    printf '%s\n' "$_METACLAW_PYTHON_BIN"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    _METACLAW_PYTHON_BIN="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    _METACLAW_PYTHON_BIN="$(command -v python)"
  else
    echo "metaclaw.sh: python3/python is required" >&2
    return 1
  fi

  printf '%s\n' "$_METACLAW_PYTHON_BIN"
}

_metaclaw_base_dir() {
  printf '%s\n' "$VAULT/30-projects/papers/.metaclaw"
}

_metaclaw_runs_dir() {
  printf '%s\n' "$(_metaclaw_base_dir)/runs"
}

_metaclaw_shared_skills_file() {
  printf '%s\n' "$(_metaclaw_base_dir)/skills.md"
}

_metaclaw_state_skills_file() {
  printf '%s\n' "$STATE_DIR/metaclaw_skills.md"
}

metaclaw_init() {
  local base runs
  base="$(_metaclaw_base_dir)"
  runs="$(_metaclaw_runs_dir)"
  mkdir -p "$base" "$runs"
}

metaclaw_collect() {
  metaclaw_init
  mkdir -p "$STATE_DIR"

  local runs_dir ts_compact out_path
  runs_dir="$(_metaclaw_runs_dir)"
  ts_compact="$(date +%Y%m%d_%H%M%S)"
  out_path="$runs_dir/${SLUG}_${ts_compact}.json"

  RETRY_LOG="$STATE_DIR/retry_log.jsonl" \
  GATE_LOG="$STATE_DIR/gate_log.jsonl" \
  PIPELINE_JSON="$STATE_DIR/pipeline.json" \
  RUN_SLUG="$SLUG" \
  OUT_PATH="$out_path" \
  "$( _metaclaw_python_bin )" - <<'PY'
import json
import os
from collections import Counter
from datetime import datetime, timezone


def parse_iso_maybe(value):
    if not value:
        return None
    if isinstance(value, str):
        v = value.strip()
        if not v:
            return None
        try:
            if v.endswith("Z"):
                return datetime.fromisoformat(v.replace("Z", "+00:00"))
            return datetime.fromisoformat(v)
        except Exception:
            pass
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
            try:
                return datetime.strptime(v, fmt).replace(tzinfo=timezone.utc)
            except Exception:
                continue
    return None


def load_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def load_jsonl(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows

retry_log = os.environ["RETRY_LOG"]
gate_log = os.environ["GATE_LOG"]
pipeline_json = os.environ["PIPELINE_JSON"]
run_slug = os.environ["RUN_SLUG"]
out_path = os.environ["OUT_PATH"]

retries = load_jsonl(retry_log)
gates_raw = load_jsonl(gate_log)
pipeline = load_json(pipeline_json)

error_counts = Counter()
fix_strategy_counts = Counter()
for row in retries:
    err = str(row.get("error", "UNKNOWN") or "UNKNOWN")
    error_counts[err] += 1
    strategy = row.get("fix_strategy") or row.get("strategy") or row.get("action")
    if strategy:
        fix_strategy_counts[str(strategy)] += 1

latest_gate_result = {}
for row in gates_raw:
    stage = str(row.get("stage", "") or "").strip()
    if not stage:
        continue
    result = row.get("result") or row.get("action") or "unknown"
    latest_gate_result[stage] = str(result)

stages = pipeline.get("stages") if isinstance(pipeline, dict) else {}
if not isinstance(stages, dict):
    stages = {}

total_stages = len(stages)
completed_stages = 0
stage_times = []
for _, info in stages.items():
    if not isinstance(info, dict):
        continue
    if info.get("status") == "completed":
        completed_stages += 1
    ts = parse_iso_maybe(info.get("ts"))
    if ts is not None:
        stage_times.append(ts)

if stage_times:
    duration_min = int(max(0, (max(stage_times) - min(stage_times)).total_seconds() / 60))
else:
    duration_min = int(pipeline.get("duration_min", 0) or 0)

raw_decisions = []
if isinstance(pipeline, dict):
    if isinstance(pipeline.get("decisions"), list):
        raw_decisions.extend(str(x) for x in pipeline.get("decisions") if x)
    for key in ("decision", "final_decision"):
        val = pipeline.get(key)
        if val:
            raw_decisions.append(str(val))

decisions = []
seen = set()
for d in raw_decisions:
    if d not in seen:
        seen.add(d)
        decisions.append(d)

summary = {
    "slug": run_slug,
    "ts": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "total_stages": int(total_stages),
    "completed_stages": int(completed_stages),
    "errors": dict(error_counts),
    "retries": int(sum(error_counts.values())),
    "gates": latest_gate_result,
    "decisions": decisions,
    "duration_min": int(duration_min),
}
if fix_strategy_counts:
    summary["fix_strategies"] = dict(fix_strategy_counts)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
PY

  printf '%s\n' "$out_path"
}

metaclaw_inject() {
  metaclaw_init
  mkdir -p "$STATE_DIR"

  local runs_dir shared_skills state_skills
  runs_dir="$(_metaclaw_runs_dir)"
  shared_skills="$(_metaclaw_shared_skills_file)"
  state_skills="$(_metaclaw_state_skills_file)"

  RUNS_DIR="$runs_dir" \
  SHARED_SKILLS="$shared_skills" \
  STATE_SKILLS="$state_skills" \
  "$( _metaclaw_python_bin )" - <<'PY'
import glob
import json
import os
from collections import Counter, defaultdict
from datetime import datetime, timezone

runs_dir = os.environ["RUNS_DIR"]
shared_skills_path = os.environ["SHARED_SKILLS"]
state_skills_path = os.environ["STATE_SKILLS"]


def parse_ts(value):
    if not value or not isinstance(value, str):
        return None
    v = value.strip()
    if not v:
        return None
    try:
        if v.endswith("Z"):
            return datetime.fromisoformat(v.replace("Z", "+00:00"))
        return datetime.fromisoformat(v)
    except Exception:
        return None


def write_skills(text):
    os.makedirs(os.path.dirname(state_skills_path), exist_ok=True)
    os.makedirs(os.path.dirname(shared_skills_path), exist_ok=True)
    with open(state_skills_path, "w", encoding="utf-8") as f:
        f.write(text)
    with open(shared_skills_path, "w", encoding="utf-8") as f:
        f.write(text)

files = sorted(glob.glob(os.path.join(runs_dir, "*.json")))
if not files:
    write_skills("")
    raise SystemExit(0)

now = datetime.now(timezone.utc)
recent = []
for path in files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            row = json.load(f)
    except Exception:
        continue
    ts = parse_ts(row.get("ts"))
    if ts is None:
        continue
    age_days = max(0.0, (now - ts).total_seconds() / 86400.0)
    if age_days > 30.0:
        continue
    weight = max(0.1, 1.0 - (age_days / 30.0))
    row["_meta_weight"] = weight
    row["_meta_age_days"] = age_days
    recent.append(row)

if not recent:
    write_skills("")
    raise SystemExit(0)

total_weight = sum(r["_meta_weight"] for r in recent) or 1.0
run_count = len(recent)

error_weight = defaultdict(float)
error_run_presence = Counter()
stage_fail_weight = defaultdict(float)
stage_fail_presence = Counter()
strategy_weight = defaultdict(float)

for r in recent:
    w = r["_meta_weight"]
    errors = r.get("errors") or {}
    if isinstance(errors, dict):
        for err, cnt in errors.items():
            try:
                c = float(cnt)
            except Exception:
                c = 0.0
            if c <= 0:
                continue
            k = str(err)
            error_weight[k] += c * w
            error_run_presence[k] += 1

    gates = r.get("gates") or {}
    if isinstance(gates, dict):
        for stage, result in gates.items():
            res = str(result).strip().lower()
            if res != "fail":
                continue
            st = str(stage)
            stage_fail_weight[st] += w
            stage_fail_presence[st] += 1

    strategies = r.get("fix_strategies") or r.get("retry_strategies") or {}
    if isinstance(strategies, dict):
        for name, cnt in strategies.items():
            try:
                c = float(cnt)
            except Exception:
                c = 0.0
            if c <= 0:
                continue
            strategy_weight[str(name)] += c * w

fix_hint = {
    "API_FAIL": "fallback 전략 우선 적용",
    "TIMEOUT": "작업 범위 축소 후 재시도",
    "PARSE_FAIL": "출력 포맷 검증 선행",
    "MISSING_DEPS": "의존성 확인 후 실행",
    "OOM": "배치 처리로 메모리 절감",
    "NaN_INF": "수치 안정성 검증 강화",
    "EMPTY_OUTPUT": "명시적 출력 형식 강제",
    "UNKNOWN": "에러 로그 요약 후 단계 재실행",
}

lines = ["## 이전 실행 교훈 (자동 생성)"]

strong_errors = []
for err, wv in sorted(error_weight.items(), key=lambda x: x[1], reverse=True):
    weighted_freq = wv / total_weight
    if weighted_freq < 0.3:
        continue
    strong_errors.append((err, wv, weighted_freq))

if strong_errors and len(lines) < 5:
    err, _, _ = strong_errors[0]
    presence = error_run_presence.get(err, 0)
    hint = fix_hint.get(err, "재시도 전 입력/출력 조건 점검")
    lines.append(f"- {err} 에러 빈번 (최근 {run_count}회 중 {presence}회) — {hint}")

if stage_fail_weight and len(lines) < 5:
    stage, _ = sorted(stage_fail_weight.items(), key=lambda x: x[1], reverse=True)[0]
    presence = stage_fail_presence.get(stage, 0)
    lines.append(f"- {stage} 단계 실패율 높음 (최근 {run_count}회 중 {presence}회) — 출력 품질 사전 점검")

if strategy_weight and len(lines) < 5:
    strategy, _ = sorted(strategy_weight.items(), key=lambda x: x[1], reverse=True)[0]
    lines.append(f"- 재시도 전략 '{strategy}'가 반복적으로 유효 — 동일 유형 장애 시 우선 적용")
elif strong_errors and len(lines) < 5:
    err, _, _ = strong_errors[0]
    if err == "API_FAIL":
        lines.append("- API_FAIL 발생 시 대체 접근법이 상대적으로 안정적 — 초기 시도에 포함 권장")

if len(lines) == 1:
    lines.append("- 최근 실행에서 강한 반복 실패 패턴 없음 — 기본 절차 유지")

text = "\n".join(lines[:5]) + "\n"
write_skills(text)
PY
}

metaclaw_get_prefix() {
  local state_skills
  state_skills="$(_metaclaw_state_skills_file)"
  if [[ -f "$state_skills" ]]; then
    cat "$state_skills"
  else
    printf ''
  fi
}

metaclaw_stats() {
  metaclaw_init

  local runs_dir
  runs_dir="$(_metaclaw_runs_dir)"

  RUNS_DIR="$runs_dir" "$( _metaclaw_python_bin )" - <<'PY'
import glob
import json
import os
from collections import Counter

runs_dir = os.environ["RUNS_DIR"]
files = sorted(glob.glob(os.path.join(runs_dir, "*.json")))

rows = []
for path in files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            rows.append(json.load(f))
    except Exception:
        continue

total = len(rows)
if total == 0:
    print("+----------------------+----------------+")
    print("| Metric               | Value          |")
    print("+----------------------+----------------+")
    print("| Total Runs           | 0              |")
    print("| Success Rate         | 0.00%          |")
    print("| Avg Duration (min)   | 0.00           |")
    print("| Common Errors        | -              |")
    print("+----------------------+----------------+")
    raise SystemExit(0)

success = 0
durations = []
errors = Counter()
for r in rows:
    total_stages = int(r.get("total_stages", 0) or 0)
    completed_stages = int(r.get("completed_stages", 0) or 0)
    if total_stages > 0 and completed_stages >= total_stages:
        success += 1
    try:
        durations.append(float(r.get("duration_min", 0) or 0))
    except Exception:
        pass
    err_map = r.get("errors") or {}
    if isinstance(err_map, dict):
        for k, v in err_map.items():
            try:
                errors[str(k)] += int(v)
            except Exception:
                continue

success_rate = (success / total) * 100.0
avg_duration = (sum(durations) / len(durations)) if durations else 0.0
common_errors = ", ".join(f"{k}:{v}" for k, v in errors.most_common(3)) if errors else "-"

print("+----------------------+----------------+")
print("| Metric               | Value          |")
print("+----------------------+----------------+")
print(f"| Total Runs           | {str(total):<14}|")
print(f"| Success Rate         | {success_rate:>6.2f}%       |")
print(f"| Avg Duration (min)   | {avg_duration:>10.2f}     |")
print(f"| Common Errors        | {common_errors[:14]:<14}|")
print("+----------------------+----------------+")
if len(common_errors) > 14:
    print(f"  Errors(detail): {common_errors}")
PY
}

metaclaw_prune() {
  metaclaw_init

  local runs_dir
  runs_dir="$(_metaclaw_runs_dir)"

  local pruned
  pruned="$(RUNS_DIR="$runs_dir" "$( _metaclaw_python_bin )" - <<'PY'
import glob
import json
import os
from datetime import datetime, timezone

runs_dir = os.environ["RUNS_DIR"]
now = datetime.now(timezone.utc)
count = 0

for path in glob.glob(os.path.join(runs_dir, "*.json")):
    ts = None
    try:
        with open(path, "r", encoding="utf-8") as f:
            row = json.load(f)
        raw_ts = row.get("ts")
        if isinstance(raw_ts, str) and raw_ts.strip():
            v = raw_ts.strip()
            if v.endswith("Z"):
                ts = datetime.fromisoformat(v.replace("Z", "+00:00"))
            else:
                ts = datetime.fromisoformat(v)
    except Exception:
        ts = None

    if ts is None:
        try:
            mtime = os.path.getmtime(path)
            ts = datetime.fromtimestamp(mtime, tz=timezone.utc)
        except Exception:
            continue

    age_days = max(0.0, (now - ts).total_seconds() / 86400.0)
    if age_days > 30.0:
        try:
            os.remove(path)
            count += 1
        except Exception:
            continue

print(count)
PY
)"

  printf 'Pruned %s files\n' "$pruned"
}

metaclaw_self_test() {
  local base_tmp
  base_tmp="$(mktemp -d "${PYTMPDIR:-${TMPDIR:-/tmp}}/metaclaw-test.XXXXXX" 2>/dev/null || mktemp -d)"

  local failures=0
  local total=0

  _test_pass() {
    printf 'PASS %s\n' "$1"
  }

  _test_fail() {
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
  }

  _run_check() {
    local name="$1"
    total=$((total + 1))
    if "$@" >/dev/null 2>&1; then
      _test_pass "$name"
    else
      _test_fail "$name"
    fi
  }

  local old_vault old_state old_slug
  old_vault="${VAULT:-}"
  old_state="${STATE_DIR:-}"
  old_slug="${SLUG:-}"

  VAULT="$base_tmp/vault"
  STATE_DIR="$base_tmp/state"
  SLUG="metaclaw-test"
  export VAULT STATE_DIR SLUG

  mkdir -p "$STATE_DIR"
  metaclaw_init

  RUNS_DIR="$(_metaclaw_runs_dir)" "$( _metaclaw_python_bin )" - <<'PY'
import json
import os
from datetime import datetime, timedelta, timezone

runs_dir = os.environ["RUNS_DIR"]
os.makedirs(runs_dir, exist_ok=True)

now = datetime.now(timezone.utc)

def write(name, days_ago, payload):
    payload = dict(payload)
    payload["ts"] = (now - timedelta(days=days_ago)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    with open(os.path.join(runs_dir, name), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

write("recent1.json", 2, {
    "slug": "a",
    "total_stages": 16,
    "completed_stages": 14,
    "errors": {"API_FAIL": 2},
    "retries": 2,
    "gates": {"S14": "fail"},
    "decisions": ["PROCEED"],
    "duration_min": 40,
    "fix_strategies": {"fallback_api": 1}
})
write("recent2.json", 10, {
    "slug": "b",
    "total_stages": 16,
    "completed_stages": 16,
    "errors": {"TIMEOUT": 1},
    "retries": 1,
    "gates": {"S14": "pass"},
    "decisions": ["PROCEED"],
    "duration_min": 50
})
write("old1.json", 45, {
    "slug": "c",
    "total_stages": 16,
    "completed_stages": 8,
    "errors": {"OOM": 3},
    "retries": 3,
    "gates": {"S15": "fail"},
    "decisions": ["REFINE"],
    "duration_min": 60
})
PY

  test_inject_recent_only() {
    metaclaw_inject
    local file
    file="$STATE_DIR/metaclaw_skills.md"
    [[ -f "$file" ]] || return 1
    grep -q "API_FAIL" "$file" || return 1
    if grep -q "OOM" "$file"; then
      return 1
    fi
    return 0
  }

  test_prune_old() {
    local before after
    before="$(find "$(_metaclaw_runs_dir)" -type f -name '*.json' | wc -l | tr -d ' ')"
    metaclaw_prune >/dev/null
    after="$(find "$(_metaclaw_runs_dir)" -type f -name '*.json' | wc -l | tr -d ' ')"
    [[ "$before" -gt "$after" ]]
  }

  test_stats_output() {
    local out
    out="$(metaclaw_stats)"
    printf '%s' "$out" | grep -q "Total Runs"
  }

  test_collect_output() {
    cat > "$STATE_DIR/retry_log.jsonl" <<'EOF_RETRY'
{"stage":"S08","attempt":1,"error":"API_FAIL","ts":"2026-03-25T00:00:00Z"}
{"stage":"S08","attempt":2,"error":"API_FAIL","ts":"2026-03-25T00:01:00Z"}
EOF_RETRY

    cat > "$STATE_DIR/gate_log.jsonl" <<'EOF_GATE'
{"stage":"S14","result":"fail","action":"blocked","ts":"2026-03-25T00:02:00Z"}
EOF_GATE

    cat > "$STATE_DIR/pipeline.json" <<'EOF_PIPE'
{
  "stages": {
    "S01": {"status":"completed","ts":"2026-03-25 00:00:00"},
    "S02": {"status":"completed","ts":"2026-03-25 00:10:00"},
    "S03": {"status":"pending","ts":""}
  },
  "decision": "PROCEED"
}
EOF_PIPE

    local out_file
    out_file="$(metaclaw_collect)"
    [[ -f "$out_file" ]] || return 1
    grep -q '"retries": 2' "$out_file" || return 1
    grep -q '"API_FAIL": 2' "$out_file" || return 1
    return 0
  }

  _run_check test_inject_recent_only
  _run_check test_prune_old
  _run_check test_stats_output
  _run_check test_collect_output

  echo "Summary: $((total - failures))/$total passed"

  rm -rf "$base_tmp"

  VAULT="$old_vault"
  STATE_DIR="$old_state"
  SLUG="$old_slug"
  export VAULT STATE_DIR SLUG

  if (( failures > 0 )); then
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--test" ]]; then
    metaclaw_self_test
    exit $?
  fi
  echo "metaclaw.sh is a library. Use: source scripts/lib/metaclaw.sh" >&2
  exit 1
fi
