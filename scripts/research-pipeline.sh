#!/usr/bin/env bash
# research-pipeline.sh — 자율 논문 연구 파이프라인 (Phase 1: S01-S05)
# 사용법: bash scripts/research-pipeline.sh "주제" [--skip-experiment]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ORCH="$SCRIPT_DIR/orchestrate.sh"

TOPIC=""
SLUG=""
VAULT="${HOME}/vault"
[ -d "$VAULT" ] || VAULT="/tmp/pipeline-test"
SKIP_EXPERIMENT="false"
PAPER_DIR=""
STATE_DIR=""
PIPELINE_FILE=""
CURRENT_STAGE=1

# ── 유틸 ───────────────────────────────────────────────────────────────

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-zA-Z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

stage_file() {
  local stage="$1"
  case "$stage" in
    S01) echo "$STATE_DIR/s01_scope.md" ;;
    S02) echo "$STATE_DIR/s02_literature.md" ;;
    S03) echo "$STATE_DIR/s03_screened.md" ;;
    S04) echo "$STATE_DIR/s04_extracted.md" ;;
    S05) echo "$STATE_DIR/s05_synthesis.md" ;;
    *) echo "" ;;
  esac
}

get_stage_status() {
  local stage="$1"
  [ -f "$PIPELINE_FILE" ] || { echo "pending"; return; }
  jq -r ".stages.${stage}.status // \"pending\"" "$PIPELINE_FILE"
}

# ── 체크포인트 ─────────────────────────────────────────────────────────

save_checkpoint() {
  local stage="$1"
  local status="$2"
  local now
  now="$(timestamp)"

  if [ ! -f "$PIPELINE_FILE" ]; then
    jq -n \
      --arg topic "$TOPIC" \
      --arg slug "$SLUG" \
      --argjson cs "$CURRENT_STAGE" \
      '{topic:$topic,slug:$slug,current_stage:$cs,skip_experiment:false,stages:{S01:{status:"pending",ts:""},S02:{status:"pending",ts:""},S03:{status:"pending",ts:""},S04:{status:"pending",ts:""},S05:{status:"pending",ts:""}}}' \
      > "$PIPELINE_FILE"
  fi

  local ts_val=""
  [ "$status" = "pending" ] || ts_val="$now"

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg s "$stage" \
    --arg st "$status" \
    --arg ts "$ts_val" \
    --argjson cs "$CURRENT_STAGE" \
    '.stages[$s] = {status:$st,ts:$ts} | .current_stage = $cs' \
    "$PIPELINE_FILE" > "$tmp"
  mv "$tmp" "$PIPELINE_FILE"
}

# ── 초기화 / 리줌 ──────────────────────────────────────────────────────

init_pipeline() {
  TOPIC="$1"
  SLUG="$(slugify "$TOPIC")"
  [ -n "$SLUG" ] || SLUG="paper-research"

  PAPER_DIR="$VAULT/30-projects/papers/$SLUG"
  STATE_DIR="$PAPER_DIR/state"
  PIPELINE_FILE="$PAPER_DIR/pipeline.json"

  mkdir -p "$STATE_DIR"

  if [ -f "$PIPELINE_FILE" ]; then
    echo "[pipeline] 기존 상태 감지 — 리줌합니다."
    CURRENT_STAGE="$(jq -r '.current_stage // 1' "$PIPELINE_FILE")"
  else
    echo "[pipeline] 새 파이프라인 시작: $TOPIC"
    CURRENT_STAGE=1
    save_checkpoint "S01" "pending"
  fi
}

# ── Gemini 위임 ────────────────────────────────────────────────────────

run_stage_gemini() {
  local stage="$1"
  local brief="$2"
  local name="$3"
  local out_file
  out_file="$(stage_file "$stage")"
  local tmp
  tmp="$(mktemp)"
  # NO_VAULT=true: vault 저장 건너뜀 / FORCE=true: vault 캐시 무시 (항상 신선한 실행)
  NO_VAULT=true FORCE=true bash "$ORCH" gemini "$brief" "$name" > "$tmp" 2>&1
  # "--- Gemini Result ---" 이후 내용만 추출 (메타 로그 제거)
  local result full_content
  full_content="$(cat "$tmp")"
  rm -f "$tmp"
  result="$(printf '%s\n' "$full_content" | awk '/^--- Gemini Result ---/{found=1; next} found')"
  # fallback: --- 없으면 전체 사용
  [ -z "$result" ] && result="$full_content"
  printf '%s\n' "$result" > "$out_file"
}

# 템플릿 변수 치환 (sed 기반)
render_template() {
  local tmpl="$1"
  local topic="$2"
  local payload="$3"
  local stage="$4"
  local out
  out="$(cat "$tmpl")"
  out="${out//\{TOPIC\}/$topic}"
  case "$stage" in
    S02) out="${out//\{RQ\}/$payload}" ;;
    S04) out="${out//\{LITERATURE\}/$payload}" ;;
    S05) out="${out//\{EXTRACTED\}/$payload}" ;;
  esac
  printf '%s' "$out"
}

# ── 직접 처리 단계 (S01, S03) ──────────────────────────────────────────

write_direct_stage() {
  local stage="$1"
  local file="$2"
  [ -f "$file" ] && return

  if [ "$stage" = "S01" ]; then
    cat > "$file" << EOF
# S01 스코핑

- **주제**: $TOPIC
- **생성**: $(timestamp)

## 핵심 연구 질문 (RQ)
1. ${TOPIC}의 현재 접근 방법과 한계는 무엇인가?
2. 최신 연구 동향과 기존 방법과의 차이점은?
3. 실용적 적용 가능성과 기여 가능한 방향은?

## 연구 범위
- **포함**: ${TOPIC} 관련 최근 5년 이내 연구, 실증 데이터 포함 논문
- **제외**: 이론 추론만 있는 미검증 연구, 관련성 낮은 주변 주제
- **평가 기준**: 재현 가능성, 실용적 기여도, 인용 수
EOF
  else
    cat > "$file" << EOF
# S03 스크리닝

- **주제**: $TOPIC
- **생성**: $(timestamp)

## 포함 기준
- S02에서 수집된 문헌 중 연구 질문에 직접 관련
- 방법론이 명확하고 결과가 검증 가능

## 제외 이유
- 중복 연구 (동일 저자 유사 논문)
- 방법론 불명확 / 주제 괴리

## 스크리닝 결과
S02 문헌 기반으로 Claude가 직접 선별. state/s02_literature.md 참조.
EOF
  fi
}

# ── 단계별 실행 ───────────────────────────────────────────────────────

run_pipeline_stages() {
  local n
  for n in 1 2 3 4 5; do
    local stage="S0${n}"
    local status
    status="$(get_stage_status "$stage")"
    local out_file
    out_file="$(stage_file "$stage")"

    if [ "$status" = "completed" ]; then
      echo "[pipeline] $stage — 이미 완료, 건너뜀"
      CURRENT_STAGE=$((n + 1))
      continue
    fi

    CURRENT_STAGE=$n
    echo "[pipeline] $stage 시작..."
    save_checkpoint "$stage" "in_progress"

    case "$stage" in
      S01)
        write_direct_stage "$stage" "$out_file"
        ;;
      S02)
        local rq
        rq="$([ -f "$STATE_DIR/s01_scope.md" ] && head -20 "$STATE_DIR/s01_scope.md" || echo "$TOPIC")"
        local tmpl="$REPO_DIR/templates/prompts/s02_literature_search.md"
        local brief
        brief="$(render_template "$tmpl" "$TOPIC" "$rq" "S02")"
        run_stage_gemini "$stage" "$brief" "s02-literature-${SLUG}"
        ;;
      S03)
        write_direct_stage "$stage" "$out_file"
        ;;
      S04)
        local lit
        lit="$([ -f "$STATE_DIR/s02_literature.md" ] && cat "$STATE_DIR/s02_literature.md" || echo "(S02 결과 없음)")"
        local tmpl="$REPO_DIR/templates/prompts/s04_knowledge_extract.md"
        local brief
        brief="$(render_template "$tmpl" "$TOPIC" "$lit" "S04")"
        run_stage_gemini "$stage" "$brief" "s04-extract-${SLUG}"
        ;;
      S05)
        local ext
        ext="$([ -f "$STATE_DIR/s04_extracted.md" ] && cat "$STATE_DIR/s04_extracted.md" || echo "(S04 결과 없음)")"
        local tmpl="$REPO_DIR/templates/prompts/s05_synthesis.md"
        local brief
        brief="$(render_template "$tmpl" "$TOPIC" "$ext" "S05")"
        run_stage_gemini "$stage" "$brief" "s05-synthesis-${SLUG}"
        ;;
    esac

    if [ ! -s "$out_file" ]; then
      echo "[pipeline] ERROR: $stage 출력 없음" >&2
      save_checkpoint "$stage" "failed"
      exit 1
    fi

    CURRENT_STAGE=$((n + 1))
    save_checkpoint "$stage" "completed"
    echo "[pipeline] $stage 완료 → $(stage_file "$stage")"
  done

  echo ""
  echo "[pipeline] Phase 1 완료!"
  echo "  논문 디렉토리: $PAPER_DIR"
  echo "  다음 단계: /research --paper --deep 로 Phase 2 계속"
}

# ── 진입점 ────────────────────────────────────────────────────────────

main() {
  command -v jq >/dev/null 2>&1 || { echo "jq 필요: brew install jq" >&2; exit 1; }
  [ -x "$ORCH" ] || { echo "orchestrate.sh 없음: $ORCH" >&2; exit 1; }

  [ "$#" -ge 1 ] || { echo "사용법: bash scripts/research-pipeline.sh \"주제\" [--skip-experiment]" >&2; exit 1; }

  local topic=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-experiment) SKIP_EXPERIMENT="true" ;;
      --help|-h)
        echo "사용법: bash scripts/research-pipeline.sh \"주제\" [--skip-experiment]"
        exit 0 ;;
      --*) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
      *)
        [ -z "$topic" ] && topic="$1" || topic="$topic $1"
        ;;
    esac
    shift
  done

  [ -n "$topic" ] || { echo "주제가 필요합니다." >&2; exit 1; }

  init_pipeline "$topic"
  run_pipeline_stages
}

main "$@"
