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
      '{topic:$topic,slug:$slug,current_stage:$cs,skip_experiment:false,gate_pending_stage:null,decision_pending:false,refine_count:0,pivot_count:0,stages:{S01:{status:"pending",ts:""},S02:{status:"pending",ts:""},S03:{status:"pending",ts:""},S04:{status:"pending",ts:""},S05:{status:"pending",ts:""},S06:{status:"pending",ts:""},S07:{status:"pending",ts:""},S08:{status:"pending",ts:""},S09:{status:"pending",ts:""},S10:{status:"pending",ts:""},S11:{status:"pending",ts:""},S12:{status:"pending",ts:""},S13:{status:"pending",ts:""},S14:{status:"pending",ts:""}}}' \
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
  while [ "$CURRENT_STAGE" -le 14 ]; do
    local stage="S$(printf '%02d' "$CURRENT_STAGE")"
    local status
    status="$(get_stage_status "$stage")"
    local out_file
    out_file="$(stage_file "$stage")"

    if [ "$status" = "completed" ]; then
      echo "[pipeline] $stage — 이미 완료, 건너뜀"
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
        cp "$STATE_DIR/s11_revised.md" "$PAPER_DIR/draft.md"
        if ! ssh -o ConnectTimeout=10 m4 "mkdir -p ~/vault/30-projects/papers/$SLUG && cat > ~/vault/30-projects/papers/$SLUG/draft.md" <<VEOF
$(cat "$STATE_DIR/s11_revised.md")
VEOF
        then
          : 
        fi
        cat > "$out_file" << S13_EOF
# S13 아카이브 완료

- 논문 저장 경로: ~/vault/30-projects/papers/$SLUG/draft.md
- 로컬 경로: $PAPER_DIR/draft.md
S13_EOF
        ;;
      S14)
        local draft14
        draft14="$([ -f "$STATE_DIR/s11_revised.md" ] && cat "$STATE_DIR/s11_revised.md" || echo "(S11 수정본 없음)")"
        local tmpl14="$REPO_DIR/templates/prompts/s14_citation_verify.md"
        local brief14
        brief14="$(render_template "$tmpl14" "$TOPIC" "$draft14" "S14")"
        run_stage_gemini "$stage" "$brief14" "s14-citation-verify-${SLUG}"
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

    if [ "$CURRENT_STAGE" -lt 15 ]; then
      CURRENT_STAGE=$((CURRENT_STAGE + 1))
    fi
    save_checkpoint "$stage" "completed"
    echo "[pipeline] $stage 완료 → $(stage_file "$stage")"
  done

  echo ""
  echo "[pipeline] 파이프라인 완료!"
  echo "  논문: $PAPER_DIR/draft.md"
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
      --help|-h)
        echo "사용법: bash scripts/research-pipeline.sh \"주제\" [--skip-experiment] [--approve-gate S06] [--decide PROCEED|REFINE|PIVOT]"
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
