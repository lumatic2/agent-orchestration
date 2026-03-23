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
GATE_ARG=""
DECISION_ARG=""
TEMPLATE="A"   # Typst 템플릿: A(학술) B(모던) C(미니멀) D(테크다크)

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
    S06) echo "$STATE_DIR/s06_experiment.md" ;;
    S07) echo "$STATE_DIR/s07_code" ;;
    S08) echo "$STATE_DIR/s08_results.md" ;;
    S09) echo "$STATE_DIR/s09_decision.md" ;;
    S10) echo "$STATE_DIR/s10_draft.md" ;;
    S11) echo "$STATE_DIR/s11_revised.md" ;;
    S12) echo "$STATE_DIR/s12_quality.md" ;;
    S13) echo "$STATE_DIR/s13_final.md" ;;
    S14) echo "$STATE_DIR/s14_citations.md" ;;
    S15) echo "$STATE_DIR/s15_validation.md" ;;
    S16) echo "$STATE_DIR/s16_pdf.md" ;;
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
      '{topic:$topic,slug:$slug,current_stage:$cs,skip_experiment:false,gate_pending_stage:null,decision_pending:false,refine_count:0,pivot_count:0,stages:{S01:{status:"pending",ts:""},S02:{status:"pending",ts:""},S03:{status:"pending",ts:""},S04:{status:"pending",ts:""},S05:{status:"pending",ts:""},S06:{status:"pending",ts:""},S07:{status:"pending",ts:""},S08:{status:"pending",ts:""},S09:{status:"pending",ts:""},S10:{status:"pending",ts:""},S11:{status:"pending",ts:""},S12:{status:"pending",ts:""},S13:{status:"pending",ts:""},S14:{status:"pending",ts:""},S15:{status:"pending",ts:""},S16:{status:"pending",ts:""}}}' \
      > "$PIPELINE_FILE"
  fi

  local ts_val=""
  [ "$status" = "pending" ] || ts_val="$now"

  # in_progress 시작 시 start_ts 기록 (watchdog용)
  local start_ts_val=""
  [ "$status" = "in_progress" ] && start_ts_val="$now"

  local tmp
  tmp="$(mktemp)"
  if [ "$status" = "in_progress" ]; then
    jq \
      --arg s "$stage" \
      --arg st "$status" \
      --arg ts "$ts_val" \
      --arg start_ts "$start_ts_val" \
      --argjson cs "$CURRENT_STAGE" \
      '.stages[$s] = {status:$st,ts:$ts,start_ts:$start_ts} | .current_stage = $cs' \
      "$PIPELINE_FILE" > "$tmp"
  else
    jq \
      --arg s "$stage" \
      --arg st "$status" \
      --arg ts "$ts_val" \
      --argjson cs "$CURRENT_STAGE" \
      '.stages[$s].status = $st | .stages[$s].ts = $ts | .current_stage = $cs' \
      "$PIPELINE_FILE" > "$tmp"
  fi
  mv "$tmp" "$PIPELINE_FILE"
}

# watchdog: in_progress 상태로 N분 이상 지속된 단계가 있으면 경고
watchdog_check() {
  [ -f "$PIPELINE_FILE" ] || return 0
  local stale_minutes=10
  local now_epoch
  now_epoch="$(date +%s)"

  local stages="S01 S02 S03 S04 S05 S06 S07 S08 S09 S10 S11 S12 S13 S14 S15 S16"
  for s in $stages; do
    local status start_ts
    status="$(jq -r ".stages.${s}.status // \"pending\"" "$PIPELINE_FILE")"
    start_ts="$(jq -r ".stages.${s}.start_ts // \"\"" "$PIPELINE_FILE")"
    if [ "$status" = "in_progress" ] && [ -n "$start_ts" ]; then
      local start_epoch elapsed_min
      start_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S' "$start_ts" +%s 2>/dev/null || date -d "$start_ts" +%s 2>/dev/null || echo 0)"
      if [ "$start_epoch" -gt 0 ]; then
        elapsed_min=$(( (now_epoch - start_epoch) / 60 ))
        if [ "$elapsed_min" -ge "$stale_minutes" ]; then
          echo "[pipeline] ⚠️  WATCHDOG: $s 이(가) ${elapsed_min}분째 in_progress — hang 가능성 있음" >&2
          echo "[pipeline] ⚠️  재실행하려면: bash $0 \"$TOPIC\" --skip-experiment (또는 해당 옵션 유지)" >&2
          save_checkpoint "$s" "failed"
          echo "[pipeline] $s → failed 로 강제 마킹됨" >&2
          exit 1
        fi
      fi
    fi
  done
}

wait_gate() {
  local stage="$1"
  local tmp
  tmp="$(mktemp)"
  jq --arg s "$stage" '.gate_pending_stage = $s' "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
  echo "[pipeline] GATE: $stage — 검토 후 --approve-gate $stage 로 재실행"
  exit 42
}

handle_decision() {
  local decision="${DECISION_ARG:-}"
  local tmp

  if [ -z "$decision" ]; then
    tmp="$(mktemp)"
    jq '.decision_pending = true' "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
    echo "[pipeline] DECISION: s09_decision.md 검토 후 --decide PROCEED|REFINE|PIVOT"
    exit 42
  fi

  case "$decision" in
    PROCEED)
      CURRENT_STAGE=9
      ;;
    REFINE)
      local refine_count
      refine_count="$(jq -r '.refine_count // 0' "$PIPELINE_FILE")"
      if [ "$refine_count" -ge 3 ]; then
        echo "[pipeline] 최대 REFINE 횟수 초과 → PROCEED 강제"
        CURRENT_STAGE=9
      else
        tmp="$(mktemp)"
        jq ".refine_count = $((refine_count + 1)) | .stages.S08.status = \"pending\" | .stages.S09.status = \"pending\" | .current_stage = 8" "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
        CURRENT_STAGE=8
      fi
      ;;
    PIVOT)
      local pivot_count
      pivot_count="$(jq -r '.pivot_count // 0' "$PIPELINE_FILE")"
      if [ "$pivot_count" -ge 2 ]; then
        echo "[pipeline] 최대 PIVOT 횟수 초과 → PROCEED 강제"
        CURRENT_STAGE=9
      else
        tmp="$(mktemp)"
        jq ".pivot_count = $((pivot_count + 1)) | .stages.S05.status = \"pending\" | .stages.S06.status = \"pending\" | .stages.S07.status = \"pending\" | .stages.S08.status = \"pending\" | .stages.S09.status = \"pending\" | .current_stage = 5" "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
        CURRENT_STAGE=5
      fi
      ;;
    *)
      echo "[pipeline] 알 수 없는 결정값: $decision" >&2
      exit 1
      ;;
  esac

  tmp="$(mktemp)"
  jq '.decision_pending = false' "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
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

  # 타임아웃 180초 — 초과 시 실패로 처리 (macOS timeout 없으므로 bash 구현)
  local exit_code=0
  NO_VAULT=true FORCE=true bash "$ORCH" gemini "$brief" "$name" > "$tmp" 2>&1 &
  local bg_pid=$!
  local elapsed=0
  local timeout_sec=180
  while kill -0 "$bg_pid" 2>/dev/null && [ "$elapsed" -lt "$timeout_sec" ]; do
    sleep 5
    elapsed=$((elapsed + 5))
  done
  if kill -0 "$bg_pid" 2>/dev/null; then
    kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null
    exit_code=124
  else
    wait "$bg_pid" || exit_code=$?
  fi

  local result full_content
  full_content="$(cat "$tmp")"
  rm -f "$tmp"

  if [ "$exit_code" -eq 124 ]; then
    echo "[pipeline] ERROR: $stage Gemini 호출 타임아웃 (180s 초과)" >&2
    save_checkpoint "$stage" "failed"
    echo "# $stage 실패\nERROR: Gemini 호출 타임아웃 (180s)" > "$out_file"
    return 1
  elif [ "$exit_code" -ne 0 ]; then
    echo "[pipeline] ERROR: $stage Gemini 호출 실패 (exit $exit_code)" >&2
    save_checkpoint "$stage" "failed"
    echo "# $stage 실패\nERROR: Gemini exit $exit_code\n\n$full_content" > "$out_file"
    return 1
  fi

  # "--- Gemini Result ---" 이후 내용만 추출 (메타 로그 제거)
  result="$(printf '%s\n' "$full_content" | awk '/^--- Gemini Result ---/{found=1; next} found')"
  # fallback: --- 없으면 전체 사용
  [ -z "$result" ] && result="$full_content"
  # Node.js stacktrace / [LOG] / [QUEUE] 라인 제거
  result="$(printf '%s\n' "$result" | /usr/bin/grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]' || true)"
  # 앞부분 stacktrace 잔재 제거 (SECTION_ADDITION 또는 # 로 시작하는 실제 내용 이전 라인)
  local first_content_line
  first_content_line="$(printf '%s\n' "$result" | /usr/bin/grep -n '^#\|^## SECTION_ADDITION\|^---' | head -1 | cut -d: -f1)"
  if [ -n "$first_content_line" ] && [ "$first_content_line" -gt 1 ]; then
    result="$(printf '%s\n' "$result" | tail -n +"$first_content_line")"
  fi
  printf '%s\n' "$result" > "$out_file"
}

run_stage_codex() {
  local stage="$1" brief="$2" name="$3"
  local out_file; out_file="$(stage_file "$stage")"
  local tmp; tmp="$(mktemp)"
  local exit_code=0

  NO_VAULT=true FORCE=true bash "$ORCH" codex "$brief" "$name" > "$tmp" 2>&1 &
  local bg_pid=$!
  local elapsed=0; local timeout_sec=300
  while kill -0 "$bg_pid" 2>/dev/null && [ "$elapsed" -lt "$timeout_sec" ]; do
    sleep 5; elapsed=$((elapsed + 5))
  done
  if kill -0 "$bg_pid" 2>/dev/null; then
    kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null; exit_code=124
  else
    wait "$bg_pid" || exit_code=$?
  fi

  local full_content; full_content="$(cat "$tmp")"; rm -f "$tmp"
  if [ "$exit_code" -eq 124 ]; then
    echo "[pipeline] ERROR: $stage Codex 호출 타임아웃 (300s)" >&2
    save_checkpoint "$stage" "failed"
    printf '# %s 실패\nERROR: Codex 타임아웃\n' "$stage" > "$out_file"
    return 1
  elif [ "$exit_code" -ne 0 ]; then
    echo "[pipeline] ERROR: $stage Codex 호출 실패 (exit $exit_code)" >&2
    save_checkpoint "$stage" "failed"
    printf '# %s 실패\nERROR: Codex exit %d\n\n%s\n' "$stage" "$exit_code" "$full_content" > "$out_file"
    return 1
  fi

  # '--- Codex Result ---' 이후 추출, 없으면 전체
  local result
  result="$(printf '%s\n' "$full_content" | awk '/^--- Codex Result ---/{found=1; next} found')"
  [ -z "$result" ] && result="$full_content"
  # Node.js stacktrace / [LOG] / [QUEUE] 라인 제거
  result="$(printf '%s\n' "$result" | /usr/bin/grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]' || true)"
  printf '%s\n' "$result" > "$out_file"
}

# 템플릿 변수 치환 (sed 기반)
truncate_payload() {
  local text="$1"
  local limit="${2:-8000}"
  if [ "${#text}" -gt "$limit" ]; then
    printf '%s\n...(truncated: %d → %d chars)' "${text:0:$limit}" "${#text}" "$limit"
  else
    printf '%s' "$text"
  fi
}

render_template() {
  local tmpl="$1"
  local topic="$2"
  local payload
  payload="$(truncate_payload "$3")"
  local stage="$4"
  local out
  out="$(cat "$tmpl")"
  out="${out//\{TOPIC\}/$topic}"
  case "$stage" in
    S02) out="${out//\{RQ\}/$payload}" ;;
    S04) out="${out//\{LITERATURE\}/$payload}" ;;
    S05) out="${out//\{EXTRACTED\}/$payload}" ;;
    S06) out="${out//\{TOPIC\}/$topic}" ;;
    S07) out="${out//__TOPIC__/$topic}" ;;
    S10) out="${out//\{SYNTHESIS\}/$payload}" ;;
    S11|S14) out="${out//\{DRAFT\}/$payload}" ;;
  esac
  printf '%s' "$out"
}

# ── 직접 처리 단계 (S01, S03) ──────────────────────────────────────────

write_direct_stage() {
  local stage="$1"
  local file="$2"
  [ -f "$file" ] && return

  if [ "$stage" = "S01" ]; then
    cat > "$file" << S01_EOF
# S01 스코핑

- **주제**: ${TOPIC}
- **생성**: $(timestamp)

## 핵심 연구 질문 (RQ)
1. ${TOPIC}의 현재 접근 방법과 한계는 무엇인가?
2. 최신 연구 동향과 기존 방법과의 차이점은?
3. 실용적 적용 가능성과 기여 가능한 방향은?

## 연구 범위
- **포함**: ${TOPIC} 관련 최근 5년 이내 연구, 실증 데이터 포함 논문
- **제외**: 이론 추론만 있는 미검증 연구, 관련성 낮은 주변 주제
- **평가 기준**: 재현 가능성, 실용적 기여도, 인용 수
S01_EOF
  else
    if [ "$stage" = "S03" ]; then
    cat > "$file" << S03_EOF
# S03 스크리닝

- **주제**: ${TOPIC}
- **생성**: $(timestamp)

## 포함 기준
- S02에서 수집된 문헌 중 연구 질문에 직접 관련
- 방법론이 명확하고 결과가 검증 가능

## 제외 이유
- 중복 연구 (동일 저자 유사 논문)
- 방법론 불명확 / 주제 괴리

## 스크리닝 결과
S02 문헌 기반으로 Claude가 직접 선별. state/s02_literature.md 참조.
S03_EOF
    elif [ "$stage" = "S06" ]; then
      cat > "$file" << S06_EOF
# S06 실험 설계

- **주제**: ${TOPIC}
- **생성**: $(timestamp)

## 실험 가설
1. 실험 설계의 목적은 S05 합성 결과 기반의 핵심 가설 검증이다.
2. 주요 지표/종속변수는 재현 가능성을 기준으로 정의한다.

## 실험 프로토콜(초안)
- 데이터/입력: 기존 실험 자원 및 샘플 문헌 기반의 정량 지표를 활용한다.
- 반복 횟수: 최소 3회 반복
- 평가지표: 정확도, 비용/시간, 안정성

## 위험 요소
- 입력 형식 불일치
- 계산 자원 제한
S06_EOF
    fi
  fi
}

# ── 단계별 실행 ───────────────────────────────────────────────────────

run_pipeline_stages() {
  # 리줌 시: 이전 세션에서 hang으로 죽은 단계가 있으면 감지
  watchdog_check

  while [ "$CURRENT_STAGE" -le 16 ]; do
    local stage="S$(printf '%02d' "$CURRENT_STAGE")"
    local status
    status="$(get_stage_status "$stage")"
    local out_file
    out_file="$(stage_file "$stage")"

    if [ "$status" = "completed" ] || [ "$status" = "skipped" ]; then
      echo "[pipeline] $stage — 이미 완료/스킵, 건너뜀"
      CURRENT_STAGE=$((CURRENT_STAGE + 1))
      continue
    fi

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
      S10)
        local synthesis
        synthesis="$([ -f "$STATE_DIR/s05_synthesis.md" ] && cat "$STATE_DIR/s05_synthesis.md" || echo "(S05 결과 없음)")"
        local tmpl10="$REPO_DIR/templates/prompts/s10_paper_draft.md"
        local brief10
        brief10="$(render_template "$tmpl10" "$TOPIC" "$synthesis" "S10")"
        run_stage_gemini "$stage" "$brief10" "s10-paper-draft-${SLUG}"
        ;;
      S11)
        local draft
        draft="$([ -f "$STATE_DIR/s10_draft.md" ] && cat "$STATE_DIR/s10_draft.md" || echo "(S10 초안 없음)")"
        local tmpl11="$REPO_DIR/templates/prompts/s11_peer_review.md"
        local brief11
        brief11="$(render_template "$tmpl11" "$TOPIC" "$draft" "S11")"
        run_stage_gemini "$stage" "$brief11" "s11-peer-review-${SLUG}"
        ;;
      S12)
        if [ ! -f "$STATE_DIR/s11_revised.md" ]; then
          echo "[pipeline] ERROR: S11 수정본이 없습니다: $STATE_DIR/s11_revised.md" >&2
          save_checkpoint "$stage" "failed"
          exit 1
        fi

        cat > "$out_file" << S12_EOF
# S12 품질 게이트

## 핵심 초안

$(cat "$STATE_DIR/s11_revised.md")

## 품질 체크리스트

- 핵심 주장과 근거의 정합성
- 실험/분석 절차의 한계 명시
- 근거·논리 전개와 결론의 일관성
- 재현성 및 오류 처리 경로 점검
- 오해 가능성이 있는 문장/과장 표현 제거
- 표기 형식의 일관성(단위/약어/참고문헌)
S12_EOF

        local gate_arg_upper
        gate_arg_upper="$(echo "$GATE_ARG" | tr '[:lower:]' '[:upper:]')"
        if [ "$gate_arg_upper" = "S12" ]; then
          local tmp
          tmp="$(mktemp)"
          jq '.gate_pending_stage = null' "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
          GATE_ARG=""
        else
          wait_gate "S12"
        fi
        ;;
      S13)
        if [ ! -f "$STATE_DIR/s11_revised.md" ]; then
          echo "[pipeline] ERROR: S11 수정본 파일이 없습니다: $STATE_DIR/s11_revised.md" >&2
          save_checkpoint "$stage" "failed"
          exit 1
        fi

        mkdir -p "$PAPER_DIR"
        # S10 base + S11 additions 병합 (python3) → draft.md
        local base_file="$STATE_DIR/s10_draft.md"
        local additions_file="$STATE_DIR/s11_revised.md"
        python3 - "$base_file" "$additions_file" > "$PAPER_DIR/draft.md" << 'PYEOF'
import sys, re

base_path, add_path = sys.argv[1], sys.argv[2]
with open(base_path) as f:
    base = f.read()
try:
    with open(add_path) as f:
        additions_raw = f.read()
except Exception:
    additions_raw = ""

# SECTION_ADDITION 블록 파싱
blocks = re.findall(
    r'^## SECTION_ADDITION:\s*(.+?)\n(.*?)(?=^## SECTION_ADDITION:|\Z)',
    additions_raw, re.MULTILINE | re.DOTALL
)

result = base
for heading, content in blocks:
    heading = heading.strip()
    content = content.strip()
    if not content:
        continue
    # 섹션 다음에 삽입 (## 로 시작하는 다음 헤더 바로 앞)
    pattern = r'(## ' + re.escape(heading) + r'(?:\n.+?)*?)(\n(?=## )|\Z)'
    replacement = r'\1\n\n' + content + r'\2'
    new_result = re.sub(pattern, replacement, result, count=1, flags=re.DOTALL)
    if new_result != result:
        result = new_result
    else:
        # 섹션 못 찾으면 References 앞에 추가
        result = re.sub(r'(\n## References|\Z)', '\n\n' + content + r'\1', result, count=1)

# [LOG]/[QUEUE] 메타라인 제거
lines = [l for l in result.splitlines() if not l.startswith('[LOG]') and not l.startswith('[QUEUE]')]
print('\n'.join(lines))
PYEOF

        # notes.md — 합성 + 가설 요약
        {
          echo "# Research Notes: ${TOPIC}"
          echo ""
          echo "- date: $(timestamp)"
          echo "- pipeline: ${PIPELINE_FILE}"
          echo ""
          echo "## Synthesis"
          cat "$STATE_DIR/s05_synthesis.md" 2>/dev/null || echo "(없음)"
        } > "$PAPER_DIR/notes.md"

        # references.md — draft의 References 섹션 추출
        {
          echo "# References: ${TOPIC}"
          echo ""
          grep -A 9999 '^## References\|^## [0-9]\+\. References' "$PAPER_DIR/draft.md" 2>/dev/null || echo "(References 섹션 없음)"
        } > "$PAPER_DIR/references.md"

        # vault에 저장 (draft + notes + references)
        local vault_ok=0
        if ssh -o ConnectTimeout=10 m4 "mkdir -p ~/vault/30-projects/papers/$SLUG" 2>/dev/null; then
          ssh -o ConnectTimeout=10 m4 "cat > ~/vault/30-projects/papers/$SLUG/draft.md" < "$PAPER_DIR/draft.md" 2>/dev/null && \
          ssh -o ConnectTimeout=10 m4 "cat > ~/vault/30-projects/papers/$SLUG/notes.md" < "$PAPER_DIR/notes.md" 2>/dev/null && \
          ssh -o ConnectTimeout=10 m4 "cat > ~/vault/30-projects/papers/$SLUG/references.md" < "$PAPER_DIR/references.md" 2>/dev/null && \
          vault_ok=1
        fi

        local vault_status="❌ 실패 (m4 연결 불가)"
        [ "$vault_ok" -eq 1 ] && vault_status="✅ ~/vault/30-projects/papers/$SLUG/"

        cat > "$out_file" << S13_EOF
# S13 아카이브 완료

- 논문: $PAPER_DIR/draft.md
- 노트: $PAPER_DIR/notes.md
- 참고문헌: $PAPER_DIR/references.md
- Vault: ${vault_status}
S13_EOF
        ;;
      S14)
        # Layer 1: bash curl로 References 섹션 URL 실제 존재 확인
        local draft14
        draft14="$([ -f "$PAPER_DIR/draft.md" ] && cat "$PAPER_DIR/draft.md" || cat "$STATE_DIR/s11_revised.md" 2>/dev/null || echo "")"

        local curl_report=""
        # draft에서 http/https URL 추출 후 curl HEAD 확인
        local urls
        urls="$(printf '%s\n' "$draft14" | /usr/bin/grep -oE 'https?://[^) >"\`]+' | sort -u || true)"
        if [ -n "$urls" ]; then
          while IFS= read -r url; do
            [ -z "$url" ] && continue
            local http_code
            http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --location "$url" 2>/dev/null || echo "ERR")"
            local status="✅"
            [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || status="❌ ($http_code)"
            curl_report="${curl_report}- ${status} ${url}\n"
          done <<< "$urls"
        else
          curl_report="(draft에서 URL 없음 — References 섹션에 URL 추가 필요)\n"
        fi

        # Layer 2: Gemini로 인용 서지 정보 일관성 검증
        local url_summary
        url_summary="$(printf '%b' "$curl_report")"
        local ref_section
        ref_section="$(printf '%s\n' "$draft14" | awk '/^## References|^## 8\. References/{found=1} found')"
        [ -z "$ref_section" ] && ref_section="(References 섹션 없음)"

        local brief14
        brief14="You are running S14 citation verification.

Topic: ${TOPIC}

## URL Audit Results (curl HEAD check)
${url_summary}

## References Section
$(truncate_payload "$ref_section" 4000)

## Task
Based on the URL audit results above and the references section:
1. List each citation with its verification status (verified/partial/unverified)
2. Flag citations with broken URLs (marked ❌), missing URLs, or incomplete bibliographic info
3. Suggest specific fixes for each problematic citation

## Output Format
# S14 Citation Verification

## Citation Status
| Citation | URL Status | Bib Status | Verdict |
|----------|-----------|-----------|---------|

## Issues & Fixes
- ...

## Summary
- Total citations: N
- Verified: N | Partial: N | Unverified: N"

        run_stage_gemini "$stage" "$brief14" "s14-citation-verify-${SLUG}"
        ;;
      S15)
        local final_draft
        final_draft="$([ -f "$PAPER_DIR/draft.md" ] && cat "$PAPER_DIR/draft.md" || cat "$STATE_DIR/s11_revised.md" 2>/dev/null || echo '(draft 없음)')"
        final_draft="$(truncate_payload "$final_draft" 6000)"

        # 1) Gemini 독립 리뷰
        local gemini_brief="## Multi-Agent Validation: Gemini Review\n\n주제: ${TOPIC}\n\n아래 논문 초안을 독립적으로 평가해라.\n평가 항목: 논리적 일관성, 근거 품질, 구조 완성도, 인용 신뢰도, 한계 명시 여부.\n각 항목을 Strong/Moderate/Weak로 평가하고 근거 1-2줄을 제시해라.\n마지막에 Overall verdict(Accept/Minor Revision/Major Revision)를 내려라.\n\n## Draft\n${final_draft}"
        local gemini_out="${STATE_DIR}/s15_gemini_review.md"
        local tmp_g; tmp_g="$(mktemp)"
        local eg=0
        NO_VAULT=true FORCE=true bash "$ORCH" gemini "$gemini_brief" "s15-gemini-${SLUG}" > "$tmp_g" 2>&1 &
        local gp=$!; local ge=0
        while kill -0 "$gp" 2>/dev/null && [ "$ge" -lt 180 ]; do sleep 5; ge=$((ge+5)); done
        if kill -0 "$gp" 2>/dev/null; then kill "$gp"; wait "$gp" 2>/dev/null; eg=124; else wait "$gp" || eg=$?; fi
        local g_full; g_full="$(cat "$tmp_g")"; rm -f "$tmp_g"
        local gr; gr="$(printf '%s\n' "$g_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
        [ -z "$gr" ] && gr="$g_full"
        gr="$(printf '%s\n' "$gr" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
        [ -z "$gr" ] && gr="(Gemini 리뷰 실패 exit=$eg)"
        printf '%s\n' "$gr" > "$gemini_out"

        # 2) Codex 독립 리뷰
        local codex_brief="Multi-Agent Validation: Codex Review\n\nTopic: ${TOPIC}\n\nReview the paper draft below independently.\nEvaluate: logical consistency, evidence quality, structure, citation reliability, limitations.\nRate each Strong/Moderate/Weak with 1-2 sentence rationale.\nGive an Overall verdict: Accept / Minor Revision / Major Revision.\n\nDraft:\n${final_draft}"
        local codex_out="${STATE_DIR}/s15_codex_review.md"
        local tmp_c; tmp_c="$(mktemp)"
        local eck=0
        NO_VAULT=true FORCE=true bash "$ORCH" codex "$codex_brief" "s15-codex-${SLUG}" > "$tmp_c" 2>&1 &
        local cp2=$!; local ce=0
        while kill -0 "$cp2" 2>/dev/null && [ "$ce" -lt 300 ]; do sleep 5; ce=$((ce+5)); done
        if kill -0 "$cp2" 2>/dev/null; then kill "$cp2"; wait "$cp2" 2>/dev/null; eck=124; else wait "$cp2" || eck=$?; fi
        local c_full; c_full="$(cat "$tmp_c")"; rm -f "$tmp_c"
        local cr; cr="$(printf '%s\n' "$c_full" | awk '/^--- Codex Summary ---/{found=1;next}found')"
        [ -z "$cr" ] && cr="$c_full"   # fallback: 전체 출력 사용
        # node.js 스택트레이스 및 메타라인 제거
        cr="$(printf '%s\n' "$cr" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
        [ -z "$cr" ] && cr="(Codex 리뷰 실패 exit=$eck)"
        printf '%s\n' "$cr" > "$codex_out"

        # 3) Claude 합성 — 두 리뷰를 orchestrate.sh gemini로 합성 (Claude 오케스트레이터 역할)
        local synth_brief="## Multi-Agent Review Synthesis\n\n주제: ${TOPIC}\n\n아래는 동일한 논문 초안에 대한 두 AI 에이전트의 독립 리뷰다. 두 리뷰를 비교·분석해서 합의된 사항, 의견 차이, 최종 권고를 한국어로 정리해라.\n\n### Gemini 리뷰\n${gr}\n\n---\n\n### Codex 리뷰\n${cr}\n\n---\n\n## 출력 형식\n\n### 합의된 사항 (두 에이전트가 공통으로 지적한 문제)\n- ...\n\n### 의견 차이 (에이전트 간 평가가 다른 영역)\n- ...\n\n### 최종 권고\n- Overall verdict 비교 결과: ...\n- 우선 수정 사항: ..."
        local synth_out="${STATE_DIR}/s15_synthesis.md"
        local tmp_s; tmp_s="$(mktemp)"
        local es=0
        NO_VAULT=true FORCE=true bash "$ORCH" gemini "$synth_brief" "s15-synthesis-${SLUG}" > "$tmp_s" 2>&1 &
        local sp=$!; local se=0
        while kill -0 "$sp" 2>/dev/null && [ "$se" -lt 180 ]; do sleep 5; se=$((se+5)); done
        if kill -0 "$sp" 2>/dev/null; then kill "$sp"; wait "$sp" 2>/dev/null; es=124; else wait "$sp" || es=$?; fi
        local s_full; s_full="$(cat "$tmp_s")"; rm -f "$tmp_s"
        local sr; sr="$(printf '%s\n' "$s_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
        [ -z "$sr" ] && sr="$s_full"
        sr="$(printf '%s\n' "$sr" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
        [ -z "$sr" ] && sr="(합성 실패 exit=$es)"
        printf '%s\n' "$sr" > "$synth_out"

        cat > "$out_file" << S15_EOF
# S15 멀티에이전트 검증 보고서

- **주제**: ${TOPIC}
- **생성**: $(timestamp)
- **검증 에이전트**: Gemini CLI, Codex CLI, Gemini(합성)

---

## Gemini 리뷰

$(cat "$gemini_out")

---

## Codex 리뷰

$(cat "$codex_out")

---

## 합성 의견 (Gemini가 두 리뷰 비교)

$(cat "$synth_out")

---

## 검증 파일
- Gemini 리뷰: state/s15_gemini_review.md
- Codex 리뷰: state/s15_codex_review.md
- 합성: state/s15_synthesis.md
S15_EOF
        ;;
      S16)
        # markdown → Typst → PDF (typst compile)
        # 파일명: 논문 첫 줄 제목 기반 (한국어면 SLUG+날짜 fallback)
        local paper_title
        paper_title="$(head -1 "$PAPER_DIR/draft.md" | sed 's/^#* *//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g; s/__*/_/g; s/^_//; s/_$//')"
        if [ "${#paper_title}" -lt 5 ]; then
          paper_title="${SLUG}_$(date +%Y%m%d)"
        fi
        paper_title="${paper_title:0:60}"
        local pdf_path="$PAPER_DIR/${paper_title}.pdf"
        local typ_path="$PAPER_DIR/${paper_title}.typ"

        if ! command -v typst >/dev/null 2>&1; then
          echo "[pipeline] WARN: typst 미설치 — brew install typst" >&2
          printf '# S16 PDF 변환\n\nWARN: typst 미설치\n' > "$out_file"
        elif ! command -v pandoc >/dev/null 2>&1; then
          echo "[pipeline] WARN: pandoc 미설치 — brew install pandoc" >&2
          printf '# S16 PDF 변환\n\nWARN: pandoc 미설치\n' > "$out_file"
        else
          # 0) 논문 제목 + 초록 추출
          local raw_title abstract_text
          raw_title="$(head -1 "$PAPER_DIR/draft.md" | sed 's/^#* *//')"
          abstract_text="$(python3 - "$PAPER_DIR/draft.md" << 'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().split('\n')
in_abstract = False
buf = []
for line in lines:
    if re.match(r'^#{1,2}\s*(초록|Abstract)', line, re.IGNORECASE):
        in_abstract = True
        continue
    if in_abstract:
        if re.match(r'^#{1,2}\s+', line):
            break
        buf.append(line)
print('\n'.join(buf).strip())
PYEOF
)"

          # 1) 초록 제외한 본문을 Typst 형식으로 변환
          local body_md="$PAPER_DIR/draft_body.md"
          python3 - "$PAPER_DIR/draft.md" "$body_md" << 'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().split('\n')
out = []
skip_abstract = False
i = 0
while i < len(lines):
    line = lines[i]
    # 첫 번째 H1(제목)은 건너뜀
    if i == 0 and re.match(r'^#\s+', line):
        i += 1
        continue
    # 초록 섹션 건너뜀
    if re.match(r'^#{1,2}\s*(초록|Abstract)', line, re.IGNORECASE):
        skip_abstract = True
        i += 1
        continue
    if skip_abstract:
        if re.match(r'^#{1,2}\s+', line) and not re.match(r'^#{1,2}\s*(초록|Abstract)', line, re.IGNORECASE):
            skip_abstract = False
        else:
            i += 1
            continue
    out.append(line)
    i += 1
open(sys.argv[2], 'w').write('\n'.join(out))
PYEOF

          # 2) pandoc: markdown body → typst
          local body_typ="$PAPER_DIR/draft_body.typ"
          pandoc "$body_md" --from markdown --to typst -o "$body_typ" 2>/dev/null || true
          rm -f "$body_md"

          # 3) 템플릿 선택 및 .typ 파일 조합
          local tmpl_file="$REPO_DIR/templates/typst/paper_${TEMPLATE}.typ"
          if [ ! -f "$tmpl_file" ]; then
            echo "[pipeline] WARN: 템플릿 없음 $tmpl_file — A로 대체" >&2
            tmpl_file="$REPO_DIR/templates/typst/paper_A.typ"
          fi

          # abstract 특수문자 이스케이프 (Typst 문자열용)
          local abs_escaped
          abs_escaped="$(printf '%s' "$abstract_text" | sed 's/\\/\\\\/g; s/"/\\"/g')"
          local title_escaped
          title_escaped="$(printf '%s' "$raw_title" | sed 's/\\/\\\\/g; s/"/\\"/g')"

          # 최종 .typ 파일 생성
          {
            cat "$tmpl_file"
            echo ""
            echo "#show: conf.with("
            echo "  title: \"${title_escaped}\","
            echo "  abstract: ["
            echo "${abstract_text}"
            echo "  ],"
            echo ")"
            echo ""
            cat "$body_typ"
          } > "$typ_path"
          rm -f "$body_typ"

          # 4) typst compile
          typst compile "$typ_path" "$pdf_path" 2>/dev/null || true

          local pdf_status="❌ Typst PDF 실패"
          local vault_pdf_status="❌ Vault 저장 실패 (m4 연결 불가)"
          local desktop_pdf_status="❌ 바탕화면 복사 실패"
          if [ -f "$pdf_path" ] && [ -s "$pdf_path" ]; then
            pdf_status="✅ $pdf_path (템플릿: ${TEMPLATE})"
            if ssh -o ConnectTimeout=10 m4 "cat > ~/vault/30-projects/papers/$SLUG/${paper_title}.pdf" < "$pdf_path" 2>/dev/null; then
              vault_pdf_status="✅ ~/vault/30-projects/papers/$SLUG/${paper_title}.pdf"
            fi
            local desktop_pdf="$HOME/Desktop/${paper_title}.pdf"
            if cp "$pdf_path" "$desktop_pdf" 2>/dev/null; then
              desktop_pdf_status="✅ $desktop_pdf"
            fi
          fi

          cat > "$out_file" << S16_EOF
# S16 PDF 변환 (Typst 템플릿 ${TEMPLATE})

- PDF: ${pdf_status}
- Vault PDF: ${vault_pdf_status}
- 바탕화면: ${desktop_pdf_status}
S16_EOF
        fi
        ;;
      S06)
        if [ "$SKIP_EXPERIMENT" = "true" ]; then
          CURRENT_STAGE=6; save_checkpoint "S06" "skipped"
          CURRENT_STAGE=7; save_checkpoint "S07" "skipped"
          CURRENT_STAGE=8; save_checkpoint "S08" "skipped"
          CURRENT_STAGE=9; save_checkpoint "S09" "skipped"
          CURRENT_STAGE=10
          continue
        fi

        local synth
        synth="$([ -f "$STATE_DIR/s05_synthesis.md" ] && cat "$STATE_DIR/s05_synthesis.md" || echo "(S05 결과 없음)")"
        local exp
        exp="$([ -f "$STATE_DIR/s06_experiment.md" ] && cat "$STATE_DIR/s06_experiment.md" || echo "(S06 실험 설계 없음)")"
        local prompt
        prompt="$(cat "$REPO_DIR/templates/prompts/s07_code_gen.md")"
        prompt="${prompt//__TOPIC__/$TOPIC}"
        prompt="${prompt//__SYNTHESIS__/$synth}"
        prompt="${prompt//__EXPERIMENT__/$exp}"
        write_direct_stage "$stage" "$out_file"

        local gate_arg_upper
        gate_arg_upper="$(echo "$GATE_ARG" | tr '[:lower:]' '[:upper:]')"
        if [ "$gate_arg_upper" = "S06" ]; then
          local tmp
          tmp="$(mktemp)"
          jq '.gate_pending_stage = null' "$PIPELINE_FILE" > "$tmp" && mv "$tmp" "$PIPELINE_FILE"
          GATE_ARG=""
        else
          wait_gate "S06"
        fi
        ;;
      S07)
        if [ "$SKIP_EXPERIMENT" = "true" ]; then
          CURRENT_STAGE=10
          save_checkpoint "$stage" "skipped"
          continue
        fi

        mkdir -p "$STATE_DIR/s07_code"
        local code_tmp
        code_tmp="$(mktemp)"
        local s05
        s05="$([ -f "$STATE_DIR/s05_synthesis.md" ] && cat "$STATE_DIR/s05_synthesis.md" || echo "(S05 결과 없음)")"
        local s06
        s06="$([ -f "$STATE_DIR/s06_experiment.md" ] && cat "$STATE_DIR/s06_experiment.md" || echo "(S06 실험 설계 없음)")"
        local brief
        brief="$(cat "$REPO_DIR/templates/prompts/s07_code_gen.md")"
        brief="${brief//__TOPIC__/$TOPIC}"
        brief="${brief//__SYNTHESIS__/$s05}"
        brief="${brief//__EXPERIMENT__/$s06}"
        NO_VAULT=true FORCE=true bash "$ORCH" codex-spark "$brief" "s07-code-${SLUG}" > "$code_tmp" 2>&1
        cp "$code_tmp" "$STATE_DIR/s07_code/experiment.py"
        rm -f "$code_tmp"
        ;;
      S08)
        if [ "$SKIP_EXPERIMENT" = "true" ]; then
          CURRENT_STAGE=10
          save_checkpoint "$stage" "skipped"
          continue
        fi

        if [ ! -f "$STATE_DIR/s07_code/experiment.py" ]; then
          echo "[pipeline] ERROR: S07 결과가 없습니다: $STATE_DIR/s07_code/experiment.py" >&2
          save_checkpoint "$stage" "failed"
          exit 1
        fi

        printf '실행 결과: [수동 입력 필요]\n' > "$out_file"
        ;;
      S09)
        if [ "$SKIP_EXPERIMENT" = "true" ]; then
          CURRENT_STAGE=10
          save_checkpoint "$stage" "skipped"
          continue
        fi

        if [ ! -f "$STATE_DIR/s08_results.md" ]; then
          echo "[pipeline] ERROR: S08 결과 파일이 없습니다: $STATE_DIR/s08_results.md" >&2
          save_checkpoint "$stage" "failed"
          exit 1
        fi

        cat > "$out_file" << S09_EOF
# S09 분석 및 결정

- **주제**: ${TOPIC}
- **생성**: $(timestamp)

## 실험 결과
$(cat "$STATE_DIR/s08_results.md")

## 제안
- PROCEED / REFINE / PIVOT 중 하나를 선택해야 함
S09_EOF
        handle_decision
        ;;
    esac

    if [ "$stage" = "S07" ]; then
      if [ ! -f "$STATE_DIR/s07_code/experiment.py" ]; then
        echo "[pipeline] ERROR: $stage 출력 없음" >&2
        save_checkpoint "$stage" "failed"
        exit 1
      fi
    elif [ ! -s "$out_file" ]; then
      echo "[pipeline] ERROR: $stage 출력 없음" >&2
      save_checkpoint "$stage" "failed"
      exit 1
    fi

    if [ "$CURRENT_STAGE" -lt 17 ]; then
      CURRENT_STAGE=$((CURRENT_STAGE + 1))
    fi
    save_checkpoint "$stage" "completed"
    echo "[pipeline] $stage 완료 → $(stage_file "$stage")"
  done

  echo ""
  echo "[pipeline] 파이프라인 완료!"
  echo "  논문(MD): $PAPER_DIR/draft.md"
  echo "  논문(PDF): $PAPER_DIR/draft.pdf"
  echo "  검증: $STATE_DIR/s15_validation.md"
  echo "  상태: $PIPELINE_FILE"
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
      --approve-gate)
        GATE_ARG="$2"
        shift
        ;;
      --decide)
        DECISION_ARG="$2"
        shift
        ;;
      --template)
        TEMPLATE="${2^^}"   # 대문자 변환
        shift
        ;;
      --help|-h)
        echo "사용법: bash scripts/research-pipeline.sh \"주제\" [--skip-experiment] [--approve-gate S06] [--decide PROCEED|REFINE|PIVOT] [--template A|B|C|D]"
        exit 0 ;;
      --*)
        echo "알 수 없는 옵션: $1" >&2
        exit 1
        ;;
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
