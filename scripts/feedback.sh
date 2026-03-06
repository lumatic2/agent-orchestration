#!/bin/bash
# feedback.sh — 에이전트 응답 품질 피드백 루프
#
# 사용법:
#   bash feedback.sh --log <agent> <expert> "<question>" <rating> ["note"]
#   bash feedback.sh --stats           # 전체 통계
#   bash feedback.sh --stats week      # 최근 7일
#   bash feedback.sh --list [--low]    # 최근 기록 목록 (--low: 낮은 평점만)
#   bash feedback.sh --export          # CSV 내보내기

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$REPO_DIR/logs/feedback.jsonl"

mkdir -p "$REPO_DIR/logs"

# ─── 기록 ────────────────────────────────────────────────────
do_log() {
  local agent="${1:-unknown}"
  local expert="${2:-}"
  local question="${3:-}"
  local rating="${4:-}"
  local note="${5:-}"

  if ! [[ "$rating" =~ ^[1-5]$ ]]; then
    echo "❌ 유효하지 않은 평점: $rating (1-5 사이 입력)" >&2
    return 1
  fi

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # JSON 이스케이프 (간단 처리)
  local q_escaped
  q_escaped=$(echo "$question" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)
  local n_escaped
  n_escaped=$(echo "$note" | sed 's/\\/\\\\/g; s/"/\\"/g')

  echo "{\"ts\":\"$ts\",\"agent\":\"$agent\",\"expert\":\"$expert\",\"question\":\"$q_escaped\",\"rating\":$rating,\"note\":\"$n_escaped\"}" >> "$LOG_FILE"

  echo "   [FEEDBACK] 기록됨 (${rating}점) ✓"
}

# ─── 통계 ─────────────────────────────────────────────────────
do_stats() {
  local period="${1:-all}"

  if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    echo "피드백 기록 없음. 에이전트 실행 후 평점을 남겨보세요."
    return 0
  fi

  python3 - "$LOG_FILE" "$period" << 'PYEOF'
import json, sys
from datetime import date, timedelta
from collections import defaultdict

log_file = sys.argv[1]
period   = sys.argv[2] if len(sys.argv) > 2 else "all"

today = date.today()
if period == "week":
    cutoff = str(today - timedelta(days=7))
    label = f"최근 7일 ({cutoff} ~ {today})"
elif period == "month":
    cutoff = str(today - timedelta(days=30))
    label = f"최근 30일"
else:
    cutoff = "2000-01-01"
    label = "전체 기간"

records = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
            if d.get("ts", "")[:10] >= cutoff:
                records.append(d)
        except Exception:
            continue

if not records:
    print(f"해당 기간({label}) 피드백 없음.")
    sys.exit(0)

# 전체 통계
ratings = [r["rating"] for r in records]
avg = sum(ratings) / len(ratings)
dist = {i: ratings.count(i) for i in range(1, 6)}

print(f"\n=== 응답 품질 통계 ({label}) ===\n")
print(f"  총 {len(records)}개  |  평균 {avg:.2f}점  |  최저 {min(ratings)}  최고 {max(ratings)}")
print()

# 분포 바
print("  [평점 분포]")
for score in range(5, 0, -1):
    count = dist.get(score, 0)
    bar = "█" * count + "░" * max(0, 10 - count)
    pct = count / len(ratings) * 100
    stars = "★" * score + "☆" * (5 - score)
    print(f"  {stars}  {bar}  {count:3}건  {pct:.0f}%")
print()

# 에이전트 유형별
by_agent = defaultdict(list)
for r in records:
    key = r.get("expert") or r.get("agent") or "unknown"
    by_agent[key].append(r["rating"])

print("  [전문가/에이전트별 평균]")
sorted_agents = sorted(by_agent.items(), key=lambda x: -sum(x[1])/len(x[1]))
for agent, rlist in sorted_agents:
    a = sum(rlist) / len(rlist)
    bar_len = int(a * 4)
    bar = "█" * bar_len + "░" * (20 - bar_len)
    warn = " ⚠️ 개선 필요" if a < 3.0 else ""
    print(f"  {agent:<22}  {bar}  {a:.1f}점  ({len(rlist)}건){warn}")
print()

# 낮은 평점 (1-2점) 항목
low = [r for r in records if r["rating"] <= 2]
if low:
    print(f"  [낮은 평점 ({len(low)}건) — 개선 필요]")
    for r in sorted(low, key=lambda x: x["ts"], reverse=True)[:5]:
        q = r.get("question", "")[:60]
        note = f"  메모: {r['note']}" if r.get("note") else ""
        print(f"  ★{'☆'*4}  [{r.get('expert') or r.get('agent')}]  {q}{note}")
    print()

# 최고 평점 항목
top = [r for r in records if r["rating"] == 5]
if top:
    print(f"  [최고 평점 ({len(top)}건) — 잘 되는 유형]")
    for r in sorted(top, key=lambda x: x["ts"], reverse=True)[:3]:
        q = r.get("question", "")[:60]
        print(f"  ★★★★★  [{r.get('expert') or r.get('agent')}]  {q}")
PYEOF
}

# ─── 목록 ─────────────────────────────────────────────────────
do_list() {
  local filter="${1:-}"

  if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    echo "피드백 기록 없음."
    return 0
  fi

  python3 - "$LOG_FILE" "$filter" << 'PYEOF'
import json, sys

log_file = sys.argv[1]
filt     = sys.argv[2] if len(sys.argv) > 2 else ""

records = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except Exception:
            continue

if filt == "--low":
    records = [r for r in records if r["rating"] <= 2]
    print(f"\n낮은 평점 항목 ({len(records)}건):\n")
else:
    print(f"\n최근 피드백 ({len(records)}건):\n")
    records = records[-20:]  # 최근 20개

for r in reversed(records):
    stars = "★" * r["rating"] + "☆" * (5 - r["rating"])
    agent = r.get("expert") or r.get("agent") or "?"
    q = r.get("question", "")[:70]
    note = f"  → {r['note']}" if r.get("note") else ""
    ts = r.get("ts", "")[:16].replace("T", " ")
    print(f"  {stars}  [{agent}]  {q}{note}  ({ts})")
PYEOF
}

# ─── CSV 내보내기 ──────────────────────────────────────────────
do_export() {
  if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    echo "피드백 기록 없음."
    return 0
  fi

  local out="$REPO_DIR/logs/feedback_export_$(date '+%Y%m%d').csv"
  python3 - "$LOG_FILE" "$out" << 'PYEOF'
import json, sys, csv

log_file = sys.argv[1]
out_file = sys.argv[2]

records = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                records.append(json.loads(line))
            except Exception:
                pass

with open(out_file, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.DictWriter(f, fieldnames=["ts", "agent", "expert", "rating", "question", "note"])
    w.writeheader()
    w.writerows(records)

print(f"내보내기 완료: {out_file} ({len(records)}건)")
PYEOF
}

# ─── 진입점 ─────────────────────────────────────────────────
CMD="${1:-}"
case "$CMD" in
  --log)    do_log "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
  --stats)  do_stats "${2:-all}" ;;
  --list)   do_list "${2:-}" ;;
  --export) do_export ;;
  *)
    echo "사용법: bash feedback.sh <명령>"
    echo ""
    echo "명령:"
    echo "  --log <agent> <expert> \"질문\" <1-5> [\"메모\"]"
    echo "  --stats [week|month|all]"
    echo "  --list [--low]"
    echo "  --export"
    ;;
esac
