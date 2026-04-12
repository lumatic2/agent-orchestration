#!/bin/bash
# vault 스케줄 관리 도구
# Usage: schedule.sh <command> [args...]

SCHEDULE="$HOME/vault/30-projects/schedule/SCHEDULE.md"
RECURRING="$HOME/vault/30-projects/schedule/RECURRING.md"
ARCHIVE="$HOME/vault/30-projects/schedule/SCHEDULE_ARCHIVE.md"

# 섹션 추출 헬퍼 (python3 — macOS sed UTF-8 호환 문제 회피)
read_section() {
  local file="$1" marker="$2"
  python3 -c "
import sys
marker = '$marker'
lines = open('$file').readlines()
capturing = False
for line in lines:
    if line.startswith('## ') and marker in line:
        capturing = True
        print(line, end='')
        continue
    if capturing:
        if line.startswith('## ') or line.strip() == '---':
            break
        print(line, end='')
"
}

case "$1" in
  read)
    section="${2:-오늘}"
    case "$section" in
      오늘|today)     read_section "$SCHEDULE" "오늘" ;;
      이번주|week)     read_section "$SCHEDULE" "이번 주" ;;
      진행중|progress) read_section "$SCHEDULE" "진행 중" ;;
      마감|deadline)   read_section "$SCHEDULE" "마감" ;;
      전체|all)       cat "$SCHEDULE" ;;
      반복|recurring) cat "$RECURRING" ;;
    esac
    ;;
  add)
    shift
    section="${1:-오늘}"; shift
    priority="${1:-중}"; shift
    item="$*"
    entry="- [ ] [${priority}] ${item}"
    case "$section" in
      오늘|today)     marker="오늘" ;;
      이번주|week)     marker="이번 주" ;;
      진행중|progress) marker="진행 중" ;;
      마감|deadline)   marker="마감" ;;
    esac
    python3 -c "
import sys
marker = '$marker'
entry = '$entry'
lines = open('$SCHEDULE').readlines()
insert_at = len(lines)
in_section = False
for i, line in enumerate(lines):
    if line.startswith('## ') and marker in line:
        in_section = True
        continue
    if in_section and (line.startswith('## ') or line.strip() == '---'):
        insert_at = i
        break
lines.insert(insert_at, entry + '\n')
open('$SCHEDULE', 'w').writelines(lines)
"
    echo "✅ 추가됨: ${entry}"
    ;;
  done)
    shift; keyword="$*"
    linenum=$(grep -n "$keyword" "$SCHEDULE" | head -1 | cut -d: -f1)
    if [ -n "$linenum" ]; then
      sed -i "" "${linenum}s/\[ \]/[x]/;${linenum}s/\[\/\]/[x]/" "$SCHEDULE"
      echo "✅ 완료: $(sed -n "${linenum}p" "$SCHEDULE")"
    else
      echo "❌ 찾을 수 없음: $keyword"
    fi
    ;;
  cancel)
    shift; keyword="$*"
    linenum=$(grep -n "$keyword" "$SCHEDULE" | head -1 | cut -d: -f1)
    if [ -n "$linenum" ]; then
      sed -i "" "${linenum}s/\[ \]/[~]/;${linenum}s/\[\/\]/[~]/" "$SCHEDULE"
      echo "✅ 취소: $(sed -n "${linenum}p" "$SCHEDULE")"
    else
      echo "❌ 찾을 수 없음: $keyword"
    fi
    ;;
  start)
    shift; keyword="$*"
    linenum=$(grep -n "$keyword" "$SCHEDULE" | head -1 | cut -d: -f1)
    if [ -n "$linenum" ]; then
      sed -i "" "${linenum}s/\[ \]/[\/]/" "$SCHEDULE"
      echo "✅ 진행중: $(sed -n "${linenum}p" "$SCHEDULE")"
    else
      echo "❌ 찾을 수 없음: $keyword"
    fi
    ;;
  archive)
    count=$(grep -c -E '\[x\]|\[~\]' "$SCHEDULE" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
      echo "" >> "$ARCHIVE"
      echo "## $(date +%Y-%m-%d) 아카이브" >> "$ARCHIVE"
      grep -E '\[x\]|\[~\]' "$SCHEDULE" >> "$ARCHIVE"
      grep -v -E '\[x\]|\[~\]' "$SCHEDULE" > "${SCHEDULE}.tmp"
      mv "${SCHEDULE}.tmp" "$SCHEDULE"
      echo "🗂 ${count}개 항목 아카이브 완료"
    else
      echo "아카이브할 항목 없음"
    fi
    ;;
  *)
    echo "사용법: schedule.sh <command> [args]"
    echo "  read [오늘|이번주|진행중|마감|전체|반복]"
    echo "  add [섹션] [우선순위] [내용]"
    echo "  done [키워드]"
    echo "  cancel [키워드]"
    echo "  start [키워드]"
    echo "  archive"
    ;;
esac
