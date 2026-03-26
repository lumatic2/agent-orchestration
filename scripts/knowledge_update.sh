#!/bin/bash
# knowledge_update.sh — Knowledge 파일 최신성 검사 및 업데이트
#
# 사용법:
#   bash knowledge_update.sh --check              # 전체 파일 개정 탐지
#   bash knowledge_update.sh --check tax_core     # 특정 파일만
#   bash knowledge_update.sh --review             # 대기 중인 변경사항 출력
#   bash knowledge_update.sh --apply tax_core     # 특정 파일에 변경사항 적용
#   bash knowledge_update.sh --apply all          # 전체 적용
#   bash knowledge_update.sh --schedule           # weekly cron 등록
#   bash knowledge_update.sh --status             # 마지막 검사 날짜 확인
#
# 의존: gemini CLI (웹검색), PERSONAL_NOTION_TOKEN (선택, 결과 저장용)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KNOWLEDGE_DIR="$REPO_DIR/agents/knowledge"
PENDING_DIR="$KNOWLEDGE_DIR/pending"
STATUS_FILE="$KNOWLEDGE_DIR/.update_status"   # 마지막 검사 날짜 기록

mkdir -p "$PENDING_DIR"

# ─── Knowledge 파일 → 담당 법령/기준 매핑 ────────────────────
declare_sources() {
  local file="$1"
  case "$file" in
    tax_core)
      echo "법인세법, 국세기본법, 법인세법 시행령"
      ;;
    tax_incentives)
      echo "조세특례제한법, 조세특례제한법 시행령, R&D 세액공제, 통합고용세액공제"
      ;;
    valuation_formulas)
      echo "상속세 및 증여세법, 상증세법 시행령, 자본시장법, 비상장주식 평가"
      ;;
    audit_standards)
      echo "주식회사 등의 외부감사에 관한 법률(외감법), 회계감사기준, 내부회계관리제도 감사기준, 표준감사시간"
      ;;
    ifrs_key)
      echo "K-IFRS 한국채택국제회계기준, 한국회계기준원 고시, IFRS 15 16 9 3 10 2 17"
      ;;
    *)
      echo "관련 법령 및 회계기준"
      ;;
  esac
}

# ─── 단일 파일 개정 탐지 ─────────────────────────────────────
check_file() {
  local target="$1"   # 예: tax_core (확장자 없음)
  local kfile="$KNOWLEDGE_DIR/${target}.md"

  if [ ! -f "$kfile" ]; then
    echo "❌ 파일 없음: $kfile"
    return 1
  fi

  local sources
  sources=$(declare_sources "$target")
  local today
  today=$(date '+%Y-%m-%d')
  local pending_file="$PENDING_DIR/${today}_${target}_changes.md"

  echo "🔍 검사 중: $target.md ($sources)"

  local content
  content=$(cat "$kfile")

  # Gemini에 웹검색으로 개정사항 확인 요청
  local PROMPT="다음은 회계/세무 AI 시스템의 지식 파일 내용이다.

## 파일: ${target}.md
## 담당 법령: $sources

---
$content
---

위 내용을 기준으로, 최근 2년(2024~2025년) 이내에 발생한 **실제 법령/기준 개정사항**을 웹에서 검색해서 알려줘.

출력 형식 (반드시 이 형식 준수):

## 검사 결과: ${target}
검사일: $today
대상 법령: $sources

### 변경 없음 / 변경 있음 (둘 중 하나)

---
변경 있을 경우 각 항목마다:

### [변경] <변경된 항목명>
- **기존**: <기존 내용 한 줄>
- **변경**: <새 내용 한 줄>
- **시행일**: <시행일>
- **근거**: <법령명 조항>
- **출처**: <URL 또는 '국세청/금감원/한국회계기준원 공고'>

---
변경이 없거나 확인 불가인 경우:
### [변경 없음]
확인된 최근 개정 없음 (검색 기준: $today)"

  local _TMP
  _TMP=$(mktemp)

  # Gemini 웹검색 실행 (Flash: 비용 최소화)
  if ! gemini --yolo -m gemini-2.5-flash -p "$PROMPT" > "$_TMP" 2>&1; then
    echo "⚠️  Gemini 오류 발생 — 스킵: $target"
    rm -f "$_TMP"
    return 1
  fi

  local result
  result=$(cat "$_TMP"); rm -f "$_TMP"

  # 결과 저장
  {
    echo "<!-- AUTO-GENERATED: bash knowledge_update.sh --check $target -->"
    echo "<!-- Reviewed: false -->"
    echo ""
    echo "$result"
  } > "$pending_file"

  # 변경 있는지 간단 판별
  if echo "$result" | grep -q "\[변경\]"; then
    echo "  ⚠️  변경사항 발견 → $pending_file"
  else
    echo "  ✅ 변경 없음"
  fi
}

# ─── 전체 또는 특정 파일 검사 ─────────────────────────────────
do_check() {
  local target="${1:-all}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔄 Knowledge 파일 최신성 검사"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local files=()
  if [ "$target" = "all" ]; then
    for f in "$KNOWLEDGE_DIR"/*.md; do
      [ -f "$f" ] || continue
      files+=("$(basename "$f" .md)")
    done
  else
    files=("$target")
  fi

  local changed=0
  for file in "${files[@]+"${files[@]}"}" ; do
    check_file "$file" && true
    echo ""
    sleep 2   # API rate limit 방지
  done

  # 검사 날짜 기록
  date '+%Y-%m-%d %H:%M' > "$STATUS_FILE"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "완료. 결과 확인: bash knowledge_update.sh --review"
  echo ""

  # Notion에도 요약 저장 (PERSONAL_NOTION_TOKEN 있으면)
  if [ -n "${PERSONAL_NOTION_TOKEN:-}" ]; then
    local summary
    summary=$(cat "$PENDING_DIR"/$(date '+%Y-%m-%d')_*.md 2>/dev/null | grep -E "^### \[변경\]" | head -20 || echo "변경사항 없음")
    bash "$SCRIPT_DIR/save_to_notion.sh" \
      --agent expert \
      --title "Knowledge 업데이트 검사 $(date '+%Y-%m-%d')" \
      --content "## 검사 결과 요약\n\n$summary" 2>/dev/null || true
  fi
}

# ─── 대기 중인 변경사항 리뷰 ─────────────────────────────────
do_review() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 대기 중인 변경사항"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local count=0
  for f in "$PENDING_DIR"/*.md; do
    [ -f "$f" ] || continue
    local fname
    fname=$(basename "$f")

    # 미검토만 표시
    if grep -q "Reviewed: false" "$f" 2>/dev/null; then
      echo "📄 $fname"
      # 변경된 항목만 추출해서 요약 출력
      grep -E "^### \[변경\]|^- \*\*(기존|변경|시행일|근거)\*\*" "$f" | head -20 || true
      echo ""
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    echo "  검토할 변경사항 없음."
    echo ""
    if [ -f "$STATUS_FILE" ]; then
      echo "  마지막 검사: $(cat "$STATUS_FILE")"
    else
      echo "  아직 검사를 실행하지 않았습니다."
      echo "  실행: bash knowledge_update.sh --check"
    fi
  else
    echo "총 ${count}개 파일 대기 중."
    echo ""
    echo "적용: bash knowledge_update.sh --apply <파일명>  (예: tax_core)"
    echo "전체: bash knowledge_update.sh --apply all"
    echo ""
    echo "전체 내용 보기:"
    echo "  cat $PENDING_DIR/<파일명>"
  fi
}

# ─── 변경사항 적용 (knowledge 파일 업데이트) ─────────────────
do_apply() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "사용법: bash knowledge_update.sh --apply <파일명|all>"
    exit 1
  fi

  # 적용할 pending 파일 목록
  local pending_files=()
  if [ "$target" = "all" ]; then
    for f in "$PENDING_DIR"/*.md; do
      [ -f "$f" ] && grep -q "Reviewed: false" "$f" 2>/dev/null && pending_files+=("$f")
    done
  else
    # 가장 최근 것 선택
    local latest
    latest=$(ls -t "$PENDING_DIR"/*_${target}_changes.md 2>/dev/null | head -1 || true)
    if [ -z "$latest" ]; then
      echo "❌ 대기 중인 변경사항 없음: $target"
      exit 1
    fi
    pending_files=("$latest")
  fi

  if [ ${#pending_files[@]} -eq 0 ]; then
    echo "적용할 변경사항 없음."
    exit 0
  fi

  for pfile in "${pending_files[@]}"; do
    local fname
    fname=$(basename "$pfile")
    # 파일명에서 target 추출: YYYY-MM-DD_<target>_changes.md
    local file_target
    file_target=$(echo "$fname" | sed 's/^[0-9-]*_//' | sed 's/_changes\.md$//')
    local kfile="$KNOWLEDGE_DIR/${file_target}.md"

    echo "🔧 적용 중: $file_target"

    if [ ! -f "$kfile" ]; then
      echo "  ❌ Knowledge 파일 없음: $kfile"
      continue
    fi

    # 변경사항 있는지 확인
    if ! grep -q "^\### \[변경\]" "$pfile" 2>/dev/null; then
      echo "  ✅ 변경사항 없음 — 스킵"
      # 검토 완료 표시
      sed -i '' 's/Reviewed: false/Reviewed: true (no changes)/' "$pfile" 2>/dev/null || true
      continue
    fi

    local changes
    changes=$(cat "$pfile")
    local current
    current=$(cat "$kfile")

    # Gemini에게 변경사항 반영해서 파일 전체 재작성 요청
    local PROMPT="다음은 현재 knowledge 파일 내용과 검사된 변경사항이다.

## 현재 파일 내용
$current

## 검사된 변경사항
$changes

위 변경사항을 반영해서 현재 파일 내용을 업데이트해줘.

규칙:
1. 파일 형식(Markdown, 섹션 구조, 표, 코드블록)을 그대로 유지
2. 변경사항에 명시된 항목만 수정 — 나머지는 그대로
3. 변경된 수치/내용 옆에 '(개정 YYYY-MM)' 표기 추가
4. 파일 맨 위에 '<!-- 마지막 업데이트: $(date '+%Y-%m-%d') -->' 주석 추가
5. 다른 설명 없이 업데이트된 파일 내용만 출력"

    echo "  🤖 Gemini로 파일 업데이트 중..."
    local _TMP
    _TMP=$(mktemp)

    if ! gemini --yolo -m gemini-2.5-flash -p "$PROMPT" > "$_TMP" 2>&1; then
      echo "  ⚠️  Gemini 오류 — 수동 업데이트 필요"
      rm -f "$_TMP"
      continue
    fi

    # 백업 후 덮어쓰기
    cp "$kfile" "${kfile}.bak"
    mv "$_TMP" "$kfile"

    # 검토 완료 표시
    sed -i '' "s/Reviewed: false/Reviewed: true (applied $(date '+%Y-%m-%d'))/" "$pfile" 2>/dev/null || true

    echo "  ✅ 업데이트 완료 (백업: ${kfile}.bak)"
  done

  echo ""
  echo "완료. git diff 로 변경 내용 확인 권장."
}

# ─── Cron 등록 ───────────────────────────────────────────────
do_schedule() {
  echo "📅 Weekly cron 등록 (매주 월요일 오전 9시)"
  local cmd="bash $SCRIPT_DIR/knowledge_update.sh --check >> $REPO_DIR/logs/knowledge_update.log 2>&1"
  local cron_line="0 9 * * 1 $cmd"

  # 이미 등록됐는지 확인
  if crontab -l 2>/dev/null | grep -q "knowledge_update.sh"; then
    echo "이미 등록됨:"
    crontab -l 2>/dev/null | grep "knowledge_update.sh"
  else
    mkdir -p "$REPO_DIR/logs"
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    echo "✅ 등록 완료:"
    echo "  $cron_line"
  fi
  echo ""
  echo "제거: crontab -e 에서 해당 줄 삭제"
}

# ─── 상태 확인 ───────────────────────────────────────────────
do_status() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Knowledge 업데이트 상태"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📁 Knowledge 파일:"
  for f in "$KNOWLEDGE_DIR"/*.md; do
    [ -f "$f" ] || continue
    local fname
    fname=$(basename "$f")
    local updated
    # 파일 내 업데이트 날짜 추출
    updated=$(grep "마지막 업데이트" "$f" 2>/dev/null | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "초기 버전")
    printf "  %-30s %s\n" "$fname" "$updated"
  done
  echo ""
  echo "🔄 마지막 검사:"
  if [ -f "$STATUS_FILE" ]; then
    echo "  $(cat "$STATUS_FILE")"
  else
    echo "  미실행"
  fi
  echo ""
  echo "📋 대기 중인 변경사항:"
  local pending_count=0
  for f in "$PENDING_DIR"/*.md; do
    [ -f "$f" ] && grep -q "Reviewed: false" "$f" 2>/dev/null && pending_count=$((pending_count + 1)) || true
  done
  echo "  ${pending_count}개"
  echo ""
  echo "⏰ Cron 스케줄:"
  if crontab -l 2>/dev/null | grep -q "knowledge_update.sh"; then
    crontab -l 2>/dev/null | grep "knowledge_update.sh"
  else
    echo "  미등록 (bash knowledge_update.sh --schedule 로 등록)"
  fi
}

# ─── 진입점 ─────────────────────────────────────────────────
CMD="${1:-}"
case "$CMD" in
  --check)    do_check "${2:-all}" ;;
  --review)   do_review ;;
  --apply)    do_apply "${2:-}" ;;
  --schedule) do_schedule ;;
  --status)   do_status ;;
  *)
    echo "사용법: bash knowledge_update.sh <명령>"
    echo ""
    echo "명령:"
    echo "  --check [파일명]   Gemini 웹검색으로 개정사항 탐지"
    echo "  --review           대기 중인 변경사항 확인"
    echo "  --apply <파일명>   변경사항 knowledge 파일에 반영"
    echo "  --apply all        전체 적용"
    echo "  --schedule         weekly cron 등록 (매주 월요일 오전 9시)"
    echo "  --status           마지막 검사 날짜, 대기 현황"
    echo ""
    echo "파일명: tax_core | tax_incentives | valuation_formulas | audit_standards | ifrs_key"
    echo ""
    echo "권장 워크플로:"
    echo "  1. bash knowledge_update.sh --check        (또는 자동: cron)"
    echo "  2. bash knowledge_update.sh --review       (변경사항 검토)"
    echo "  3. bash knowledge_update.sh --apply all    (적용)"
    ;;
esac
