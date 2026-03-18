#!/bin/bash
# ask_history.sh — ask.sh 응답 히스토리 조회
#
# 사용법:
#   bash ask_history.sh               # 최근 10개 요약
#   bash ask_history.sh "키워드"      # 질문에서 키워드 검색
#   bash ask_history.sh --last        # 마지막 응답 전체 출력
#   bash ask_history.sh --stats       # 에이전트별 사용 통계
#   bash ask_history.sh --last N      # 최근 N개 요약 (기본 10)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$(dirname "$SCRIPT_DIR")/logs/ask_history.jsonl"

if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
  echo "히스토리 없음. bash ask.sh 로 질문하면 자동 저장됩니다."
  exit 0
fi

MODE="recent"
KEYWORD=""
LAST_N=10

case "${1:-}" in
  --last)
    if [[ "${2:-}" =~ ^[0-9]+$ ]]; then MODE="recent"; LAST_N="$2"
    else MODE="last"; fi ;;
  --stats) MODE="stats" ;;
  "") MODE="recent" ;;
  *) MODE="search"; KEYWORD="$1" ;;
esac

python3 - "$LOG_FILE" "$MODE" "$KEYWORD" "$LAST_N" << 'PYEOF'
import sys, json
from datetime import datetime, timezone

logfile, mode, keyword, last_n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

entries = []
with open(logfile, encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            entries.append(json.loads(line))
        except Exception:
            pass

if not entries:
    print("히스토리 없음")
    sys.exit(0)

def fmt_ts(ts):
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        local = dt.astimezone()
        return local.strftime('%m/%d %H:%M')
    except:
        return ts[:10]

if mode == "stats":
    from collections import Counter
    agents = Counter(e.get('agent','?') for e in entries)
    reviews = Counter(e.get('review','?') for e in entries)
    print(f"=== 히스토리 통계 (총 {len(entries)}건) ===\n")
    print("에이전트별 사용:")
    for agent, cnt in agents.most_common():
        print(f"  {agent:<25} {cnt}회")
    print(f"\n검토 비율:")
    print(f"  REVIEW_NEEDED : {reviews.get('REVIEW_NEEDED', 0)}회")
    print(f"  DIRECT        : {reviews.get('DIRECT', 0)}회")

elif mode == "search":
    matches = [e for e in entries if keyword.lower() in e.get('question','').lower()]
    print(f"=== 검색: \"{keyword}\" ({len(matches)}건) ===\n")
    for i, e in enumerate(reversed(matches[-20:]), 1):
        review_mark = "🔍" if e.get('review') == 'REVIEW_NEEDED' else "·"
        print(f"{review_mark} [{fmt_ts(e['ts'])}] [{e.get('agent','?')}] {e.get('question','')[:60]}")

elif mode == "last":
    e = entries[-1]
    print(f"=== 마지막 응답 ===")
    print(f"시각: {fmt_ts(e['ts'])} | 에이전트: {e.get('agent','?')} | {e.get('review','?')}")
    print(f"질문: {e.get('question','')}")
    print(f"{'─'*40}")
    print(e.get('response',''))

else:  # recent
    recent = entries[-last_n:]
    print(f"=== 최근 {len(recent)}건 ===\n")
    for e in reversed(recent):
        review_mark = "🔍" if e.get('review') == 'REVIEW_NEEDED' else "·"
        q = e.get('question', '')[:55]
        print(f"{review_mark} [{fmt_ts(e['ts'])}] [{e.get('agent','?')}] {q}")
    print(f"\n🔍 = REVIEW_NEEDED (Claude 검토)  · = DIRECT")
    print(f"\n전체 응답 보기: bash ask_history.sh --last")
    print(f"키워드 검색:    bash ask_history.sh \"IFRS\"")
    print(f"통계:           bash ask_history.sh --stats")
PYEOF
