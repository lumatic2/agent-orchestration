#!/bin/bash
# content_pipeline.sh — 콘텐츠 파이프라인 (소설/책/논문)
#
# 사용법:
#   bash content_pipeline.sh init "프로젝트명" [소설|책|논문] "주제/설명"
#   bash content_pipeline.sh write "프로젝트명" [챕터번호]   # 번호 없으면 다음 챕터
#   bash content_pipeline.sh compile "프로젝트명"            # 전체 합치기
#   bash content_pipeline.sh status "프로젝트명"             # 진행 현황
#   bash content_pipeline.sh list                            # 프로젝트 목록

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PERSONA_FILE="$REPO_DIR/agents/content_persona.md"
PROJECTS_DIR="$HOME/Desktop/content-projects"
mkdir -p "$PROJECTS_DIR"

CMD="${1:-}"
PROJECT="${2:-}"
BACKEND="gemini"
SAVE_NOTION=false
for arg in "$@"; do
  [ "$arg" = "--codex" ] && BACKEND="codex"
  [ "$arg" = "--save"  ] && SAVE_NOTION=true
done

ai_call() {
  local prompt="$1"
  if [ "$BACKEND" = "codex" ]; then
    codex exec -c model="gpt-5.2" -c 'approval_policy="never"' "$prompt"
  else
    gemini --yolo -m gemini-2.5-flash -p "$prompt"
  fi
}

# ─── 유틸 ────────────────────────────────────────────────
die() { echo "❌ $1"; exit 1; }
project_dir() { echo "$PROJECTS_DIR/$1"; }
meta_file()   { echo "$(project_dir "$1")/meta.json"; }

load_meta() {
  local f; f=$(meta_file "$1")
  [ -f "$f" ] || die "프로젝트 없음: $1 (먼저 init)"
  cat "$f"
}

get_meta() { load_meta "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$2',''))" 2>/dev/null; }

# ─── INIT ────────────────────────────────────────────────
cmd_init() {
  local project="$1" type="${2:-책}" topic="$3"
  [ -z "$project" ] && die "사용법: init \"프로젝트명\" [소설|책|논문] \"주제\""
  [ -z "$topic"   ] && die "주제를 입력하세요"

  local dir; dir=$(project_dir "$project")
  [ -d "$dir" ] && die "이미 존재하는 프로젝트: $project"
  mkdir -p "$dir/chapters"

  local PERSONA; PERSONA=$(cat "$PERSONA_FILE" 2>/dev/null || echo "전문 작가로서 답변하세요.")

  echo "📋 목차 생성 중 ($type: $topic)..."

  local outline_prompt="$PERSONA

## 임무: 목차 생성

다음 프로젝트의 상세 목차를 작성하세요.

- 프로젝트명: $project
- 유형: $type
- 주제/설명: $topic

### 출력 형식 (반드시 아래 마크다운 형식 준수)

\`\`\`markdown
# $project

## 개요
[2-3문장 프로젝트 설명]

## 독자 대상
[타겟 독자]

## 챕터 목록
| 번호 | 제목 | 핵심 내용 |
|---|---|---|
| 1 | [챕터 제목] | [한 줄 요약] |
| 2 | ... | ... |
[총 5-10개 챕터]

## 전체 메시지
[이 작품이 전달하는 핵심 메시지]
\`\`\`"

  local outline
  outline=$(ai_call "$outline_prompt" 2>/dev/null)

  # Extract chapter count
  local chapter_count
  chapter_count=$(echo "$outline" | grep -c "^| [0-9]" 2>/dev/null || echo "8")

  # Save files
  echo "$outline" > "$dir/outline.md"
  cat > "$(meta_file "$project")" << EOF
{
  "project": "$project",
  "type": "$type",
  "topic": "$topic",
  "chapter_count": $chapter_count,
  "chapters_written": [],
  "created": "$(date +%Y-%m-%d)"
}
EOF

  echo ""
  echo "✅ 프로젝트 초기화 완료: $dir"
  echo ""
  cat "$dir/outline.md"
  echo ""
  echo "📝 다음 단계: bash content_pipeline.sh write \"$project\""
}

# ─── WRITE ───────────────────────────────────────────────
cmd_write() {
  local project="$1" ch_num="${2:-}"
  load_meta "$project" > /dev/null

  local dir; dir=$(project_dir "$project")
  local type; type=$(get_meta "$project" type)
  local topic; topic=$(get_meta "$project" topic)

  # Determine next chapter number
  if [ -z "$ch_num" ]; then
    ch_num=1
    while [ -f "$dir/chapters/ch$(printf '%02d' "$ch_num").md" ]; do
      ch_num=$((ch_num + 1))
    done
  fi

  local ch_file="$dir/chapters/ch$(printf '%02d' "$ch_num").md"
  [ -f "$ch_file" ] && echo "⚠️  챕터 $ch_num 이미 존재. 덮어씁니까? (y/N)" && read -r ans && [ "$ans" != "y" ] && exit 0

  local outline; outline=$(cat "$dir/outline.md" 2>/dev/null || echo "")
  local PERSONA; PERSONA=$(cat "$PERSONA_FILE" 2>/dev/null || echo "전문 작가로서 글을 쓰세요.")

  # Collect previous chapter summaries
  local prev_summaries=""
  for prev in "$dir/chapters"/ch*.md; do
    [ -f "$prev" ] || continue
    local summary; summary=$(grep "<!-- SUMMARY:" "$prev" | sed 's/<!-- SUMMARY: //;s/ -->//')
    [ -n "$summary" ] && prev_summaries="$prev_summaries\n- $(basename "$prev"): $summary"
  done

  echo "✍️  챕터 $ch_num 작성 중..."

  local write_prompt="$PERSONA

## 프로젝트 정보
- 유형: $type
- 주제: $topic

## 전체 목차
$outline

## 이전 챕터 요약
${prev_summaries:-없음 (첫 챕터)}

## 임무
챕터 $ch_num 을 작성하세요. 목차의 해당 챕터 설명을 충실히 반영하고,
이전 챕터와 자연스럽게 이어지게 하세요.

맨 첫 줄에 \`<!-- SUMMARY: [1-2줄 요약] -->\` 포함
마지막 줄에 \`<!-- CHAPTER_END -->\` 포함"

  local chapter_content
  chapter_content=$(ai_call "$write_prompt" 2>/dev/null)

  echo "# 챕터 $ch_num" > "$ch_file"
  echo "" >> "$ch_file"
  echo "$chapter_content" >> "$ch_file"

  echo ""
  echo "✅ 챕터 $ch_num 저장: $ch_file"
  echo ""
  echo "--- 미리보기 (처음 20줄) ---"
  head -20 "$ch_file"
  echo "..."
  echo ""
  echo "📝 다음: bash content_pipeline.sh write \"$project\" $((ch_num + 1))"
}

# ─── COMPILE ─────────────────────────────────────────────
cmd_compile() {
  local project="$1"
  load_meta "$project" > /dev/null
  local dir; dir=$(project_dir "$project")

  local out="$dir/compiled.md"
  echo "# $(get_meta "$project" project)" > "$out"
  echo "" >> "$out"
  echo "*유형: $(get_meta "$project" type) | 생성: $(date +%Y-%m-%d)*" >> "$out"
  echo "" >> "$out"
  echo "---" >> "$out"
  echo "" >> "$out"

  local count=0
  for ch in "$dir/chapters"/ch*.md; do
    [ -f "$ch" ] || continue
    # Strip comments, append content
    grep -v "<!-- SUMMARY:" "$ch" | grep -v "<!-- CHAPTER_END -->" >> "$out"
    echo "" >> "$out"
    echo "---" >> "$out"
    echo "" >> "$out"
    count=$((count + 1))
  done

  local words; words=$(wc -w < "$out" | tr -d ' ')
  echo "✅ 컴파일 완료: $out"
  echo "   챕터 $count개 / 약 ${words}단어"
  echo ""
  echo "📄 PDF 변환 (pandoc 설치 후):"
  echo "   brew install pandoc"
  echo "   pandoc $out -o $dir/compiled.pdf"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "💡 다음 단계:"
  echo "   Notion 저장:  bash content_pipeline.sh compile \"$project\" --save"
  echo "   메모리 기록:  bash memory_update.sh \"active_projects\" \"$project 컴파일 완료 (${count}챕터)\""

  if [ "$SAVE_NOTION" = true ]; then
    local compiled_content; compiled_content=$(cat "$out" 2>/dev/null)
    bash "$SCRIPT_DIR/save_to_notion.sh" \
      --agent content \
      --title "$project 컴파일 (${count}챕터 / ${words}단어)" \
      --content "$compiled_content"
  fi
}

# ─── STATUS ──────────────────────────────────────────────
cmd_status() {
  local project="$1"
  load_meta "$project" > /dev/null
  local dir; dir=$(project_dir "$project")

  echo "📊 [$project] 진행 현황"
  echo "유형: $(get_meta "$project" type) | 주제: $(get_meta "$project" topic)"
  echo ""

  local written=0 total; total=$(get_meta "$project" chapter_count)
  for ch in "$dir/chapters"/ch*.md; do
    [ -f "$ch" ] || continue
    local num; num=$(basename "$ch" .md | sed 's/ch0*//')
    local summary; summary=$(grep "<!-- SUMMARY:" "$ch" | sed 's/<!-- SUMMARY: //;s/ -->//')
    printf "  ✅ Ch%02d: %s\n" "$num" "${summary:-작성 완료}"
    written=$((written + 1))
  done

  local remaining=$((total - written))
  [ "$remaining" -gt 0 ] && echo "  ⬜ 미작성: ${remaining}개 챕터 남음"
  echo ""
  echo "진행률: $written / $total 챕터"
  [ -f "$dir/compiled.md" ] && echo "컴파일본: $dir/compiled.md ($(wc -w < "$dir/compiled.md" | tr -d ' ')단어)"
}

# ─── LIST ────────────────────────────────────────────────
cmd_list() {
  echo "📚 콘텐츠 프로젝트 목록"
  echo ""
  for meta in "$PROJECTS_DIR"/*/meta.json; do
    [ -f "$meta" ] || continue
    local name type topic created
    name=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('project',''))" 2>/dev/null)
    type=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('type',''))" 2>/dev/null)
    topic=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('topic','')[:40])" 2>/dev/null)
    created=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('created',''))" 2>/dev/null)
    local dir; dir=$(dirname "$meta")
    local ch_count; ch_count=$(ls "$dir/chapters/"ch*.md 2>/dev/null | wc -l | tr -d ' ')
    echo "  [$name] $type | $topic | 챕터 ${ch_count}개 | $created"
  done
}

# ─── DISPATCH ────────────────────────────────────────────
case "$CMD" in
  init)    cmd_init "$PROJECT" "${3:-책}" "${4:-}" ;;
  write)   cmd_write "$PROJECT" "${3:-}" ;;
  compile) cmd_compile "$PROJECT" ;;
  status)  cmd_status "$PROJECT" ;;
  list)    cmd_list ;;
  *)
    echo "콘텐츠 파이프라인 사용법:"
    echo "  init    \"프로젝트명\" [소설|책|논문] \"주제\""
    echo "  write   \"프로젝트명\" [챕터번호]"
    echo "  compile \"프로젝트명\""
    echo "  status  \"프로젝트명\""
    echo "  list"
    ;;
esac
