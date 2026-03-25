#!/usr/bin/env bash
# research-pipeline.sh — 자율 논문 연구 파이프라인 (Phase 1: S01-S05)
# 사용법: bash scripts/research-pipeline.sh "주제" [--skip-experiment]

set -euo pipefail

# Mac Homebrew PATH 보장 (비대화형 SSH 세션에서 /opt/homebrew/bin 누락 방지)
if [[ "$(uname -s)" == "Darwin" ]]; then
  [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  [[ ":$PATH:" != *":/usr/local/bin:"* ]]    && export PATH="/usr/local/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ORCH="$SCRIPT_DIR/orchestrate.sh"

# ── lib 모듈 로드 (없으면 건너뜀) ─────────────────────────────────────
[ -f "$SCRIPT_DIR/lib/self_heal.sh" ]      && source "$SCRIPT_DIR/lib/self_heal.sh"
[ -f "$SCRIPT_DIR/lib/circuit_breaker.sh" ] && source "$SCRIPT_DIR/lib/circuit_breaker.sh"
[ -f "$SCRIPT_DIR/lib/gate.sh" ]            && source "$SCRIPT_DIR/lib/gate.sh"
[ -f "$SCRIPT_DIR/lib/verified_registry.sh" ] && source "$SCRIPT_DIR/lib/verified_registry.sh"
[ -f "$SCRIPT_DIR/lib/metaclaw.sh" ]        && source "$SCRIPT_DIR/lib/metaclaw.sh"

TOPIC=""
SLUG=""
VAULT="${HOME}/vault"
[ -d "$VAULT" ] || VAULT="/tmp/pipeline-test"
# Python-compatible temp directory (Windows Git Bash /tmp/ not recognized by Python)
PYTMPDIR="$(python3 -c "import tempfile; print(tempfile.gettempdir())" 2>/dev/null || echo "/tmp")"
SKIP_EXPERIMENT="false"
PAPER_DIR=""
STATE_DIR=""
PIPELINE_FILE=""
CURRENT_STAGE=1
GATE_ARG=""
DECISION_ARG=""
TEMPLATE="A"   # Typst 템플릿: A(학술) B(모던) C(미니멀) D(테크다크)

# ── 프로세스 트리 kill (크로스 플랫폼) ──────────────────────────────────
_kill_tree() {
  local pid="$1"
  # 방법 1: pkill -P (Linux/Mac)
  pkill -P "$pid" 2>/dev/null || true
  # 방법 2: ps --ppid (GNU)
  local children
  children="$(ps -o pid= --ppid "$pid" 2>/dev/null || true)"
  for child in $children; do
    kill "$child" 2>/dev/null || true
  done
  # 마지막: 부모 kill
  kill "$pid" 2>/dev/null || true
}

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
  local check_result="${2:-fail}"  # pass/fail/warn (기본: fail → 기존 동작 유지)

  # gate.sh가 로드되어 있으면 향상된 게이트 사용
  if type gate_check &>/dev/null; then
    gate_init 2>/dev/null || true
    local gate_rc=0
    gate_check "$stage" "$check_result" || gate_rc=$?
    if [[ $gate_rc -eq 0 ]]; then
      return 0  # auto-approve 또는 pass → 계속 진행
    fi
    # rollback 대상이 설정되었으면 로그
    if [[ -n "${GATE_ROLLBACK_TARGET:-}" ]]; then
      echo "[pipeline] GATE: $stage → rollback to $GATE_ROLLBACK_TARGET" >&2
    fi
  fi

  # 기존 동작: pipeline.json에 기록 + exit 42
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
  if [ -z "$SLUG" ]; then
    SLUG="research-$(printf '%s' "$TOPIC" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])")"
  fi

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

  # MetaClaw: 이전 실행 교훈 주입
  if type metaclaw_init &>/dev/null; then
    metaclaw_init 2>/dev/null || true
    metaclaw_inject 2>/dev/null || true
    [ -f "$STATE_DIR/metaclaw_skills.md" ] && echo "[pipeline] MetaClaw: 이전 실행 교훈 로드 완료" >&2
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
    _kill_tree "$bg_pid"; wait "$bg_pid" 2>/dev/null || true
    exit_code=124
  else
    wait "$bg_pid" || exit_code=$?
  fi

  local result full_content
  full_content="$(cat "$tmp")"
  rm -f "$tmp"

  # Gemini 실패/타임아웃 시 ChatGPT fallback 시도
  if [ "$exit_code" -eq 124 ] || [ "$exit_code" -ne 0 ]; then
    local fail_reason="exit $exit_code"
    [ "$exit_code" -eq 124 ] && fail_reason="timeout 180s"
    echo "[pipeline] WARN: $stage Gemini 실패 ($fail_reason) — ChatGPT fallback 시도" >&2

    local fb_tmp fb_exit=0
    fb_tmp="$(mktemp)"
    NO_VAULT=true FORCE=true bash "$ORCH" chatgpt "$brief" "${name}-fallback" > "$fb_tmp" 2>&1 &
    local fb_pid=$!
    local fb_elapsed=0
    while kill -0 "$fb_pid" 2>/dev/null && [ "$fb_elapsed" -lt 300 ]; do
      sleep 5; fb_elapsed=$((fb_elapsed + 5))
    done
    if kill -0 "$fb_pid" 2>/dev/null; then
      _kill_tree "$fb_pid"; wait "$fb_pid" 2>/dev/null || true; fb_exit=124
    else
      wait "$fb_pid" || fb_exit=$?
    fi

    if [ "$fb_exit" -eq 0 ]; then
      full_content="$(cat "$fb_tmp")"
      echo "[pipeline] $stage ChatGPT fallback 성공" >&2
    else
      echo "[pipeline] WARN: $stage ChatGPT fallback도 실패 (exit $fb_exit) — 빈 결과로 진행" >&2
      printf '# %s (실패)\nGemini: %s / ChatGPT fallback: exit %s\n' "$stage" "$fail_reason" "$fb_exit" > "$out_file"
      rm -f "$fb_tmp"
      save_checkpoint "$stage" "completed"
      return 0
    fi
    rm -f "$fb_tmp"
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
    _kill_tree "$bg_pid"; wait "$bg_pid" 2>/dev/null || true; exit_code=124
  else
    wait "$bg_pid" || exit_code=$?
  fi

  local full_content; full_content="$(cat "$tmp")"; rm -f "$tmp"
  if [ "$exit_code" -eq 124 ]; then
    echo "[pipeline] WARN: $stage Codex 호출 타임아웃 (300s) — 계속 진행" >&2
    printf '# %s (타임아웃)\nERROR: Codex 타임아웃\n' "$stage" > "$out_file"
    save_checkpoint "$stage" "completed"
    return 0
  elif [ "$exit_code" -ne 0 ]; then
    echo "[pipeline] WARN: $stage Codex 호출 실패 (exit $exit_code) — 계속 진행" >&2
    printf '# %s (실패)\nERROR: Codex exit %s\n' "$stage" "$exit_code" > "$out_file"
    save_checkpoint "$stage" "completed"
    return 0
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
        local fallback_brief
        fallback_brief="$(render_template "$tmpl" "$TOPIC" "$rq" "S02")"
        local skip_api_flow=0

        local arxiv_raw ss_raw arxiv_json ss_json merged_md
        arxiv_raw="$(mktemp "${PYTMPDIR}/arxiv_raw_XXXXXX" 2>/dev/null || mktemp)"
        ss_raw="$(mktemp "${PYTMPDIR}/ss_raw_XXXXXX" 2>/dev/null || mktemp)"
        arxiv_json="$(mktemp "${PYTMPDIR}/arxiv_parsed_XXXXXX" 2>/dev/null || mktemp)"
        ss_json="$(mktemp "${PYTMPDIR}/ss_parsed_XXXXXX" 2>/dev/null || mktemp)"
        merged_md="$(mktemp "${PYTMPDIR}/s02_lit_XXXXXX" 2>/dev/null || mktemp)"

        local search_terms en_keywords slug_query
        search_terms="$TOPIC"
        en_keywords=""

        # S01 scope 파일에서 영문 키워드 먼저 읽기
        if [ -f "$STATE_DIR/s01_scope.md" ]; then
          en_keywords="$(grep '^\- \*\*영문 검색 키워드\*\*:' "$STATE_DIR/s01_scope.md" | sed 's/.*: //' | head -1)"
        fi

        # S01에 없으면 TOPIC이 한글인 경우 Gemini→ChatGPT fallback으로 영문 키워드 생성
        if [ -z "$en_keywords" ]; then
          if echo "$TOPIC" | grep -qP '[\x{AC00}-\x{D7A3}]' 2>/dev/null || echo "$TOPIC" | python3 -c "import sys; s=sys.stdin.read(); exit(0 if any(ord(c)>127 for c in s) else 1)" 2>/dev/null; then
            local _kw_prompt="다음 한국어 연구 주제를 arXiv 검색에 적합한 영문 키워드 3~5개로 변환해줘. 키워드만 공백으로 구분해서 한 줄로 출력. 다른 설명 없이 키워드만.\n주제: $TOPIC"
            local _kw_tmp; _kw_tmp="$(mktemp)"
            local _kw_exit=0
            bash "$ORCH" gemini "$_kw_prompt" s02-en-keywords > "$_kw_tmp" 2>/dev/null &
            local _kw_pid=$!
            local _kw_elapsed=0
            while kill -0 "$_kw_pid" 2>/dev/null && [ "$_kw_elapsed" -lt 60 ]; do
              sleep 3; _kw_elapsed=$((_kw_elapsed + 3))
            done
            if kill -0 "$_kw_pid" 2>/dev/null; then
              _kill_tree "$_kw_pid"; wait "$_kw_pid" 2>/dev/null || true; _kw_exit=124
            else
              wait "$_kw_pid" || _kw_exit=$?
            fi
            if [ "$_kw_exit" -ne 0 ]; then
              echo "[pipeline] S02: Gemini 키워드 변환 실패 (${_kw_exit}) — ChatGPT fallback" >&2
              bash "$ORCH" chatgpt "$_kw_prompt" s02-en-keywords-fb > "$_kw_tmp" 2>/dev/null &
              _kw_pid=$!; _kw_elapsed=0
              while kill -0 "$_kw_pid" 2>/dev/null && [ "$_kw_elapsed" -lt 60 ]; do
                sleep 3; _kw_elapsed=$((_kw_elapsed + 3))
              done
              if kill -0 "$_kw_pid" 2>/dev/null; then
                kill -- -"$_kw_pid" 2>/dev/null || kill "$_kw_pid" 2>/dev/null || true
                wait "$_kw_pid" 2>/dev/null || true
              else
                wait "$_kw_pid" 2>/dev/null || true
              fi
            fi
            en_keywords="$(cat "$_kw_tmp" 2>/dev/null | grep -v '^\[' | grep -v '^---' | grep -v '^$' | tail -1 || true)"
            rm -f "$_kw_tmp"
            if [ -n "$en_keywords" ] && [ -f "$STATE_DIR/s01_scope.md" ] && ! grep -q '^\- \*\*영문 검색 키워드\*\*:' "$STATE_DIR/s01_scope.md"; then
              printf '\n- **영문 검색 키워드**: %s\n' "$en_keywords" >> "$STATE_DIR/s01_scope.md"
            fi
          fi
        fi

        [ -n "$en_keywords" ] && search_terms="$en_keywords"

        slug_query="$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "$search_terms" 2>/dev/null || true)"
        [ -z "$slug_query" ] && slug_query="$search_terms"

        # ── arXiv API (circuit breaker 적용) ──
        local arxiv_url
        arxiv_url="https://export.arxiv.org/api/query?search_query=all:${slug_query}&max_results=15&sortBy=relevance"
        if type _circuit_update_source &>/dev/null; then
          local _arxiv_open
          _arxiv_open="$(_circuit_is_open_and_recent "arxiv" 2>/dev/null || echo 0)"
          if [[ "$_arxiv_open" == "1" ]]; then
            echo "[pipeline] S02: arXiv circuit OPEN — skip" >&2
          else
            local _arxiv_rc=0
            curl -s --max-time 30 "$arxiv_url" -o "$arxiv_raw" 2>/dev/null || _arxiv_rc=$?
            if [[ $_arxiv_rc -ne 0 ]] || [[ ! -s "$arxiv_raw" ]]; then
              _circuit_update_source "arxiv" "failure" 2>/dev/null || true
              echo "[pipeline] S02: arXiv fetch 실패 (rc=$_arxiv_rc) — circuit 기록" >&2
            else
              _circuit_update_source "arxiv" "success" 2>/dev/null || true
            fi
          fi
        else
          curl -s --max-time 30 "$arxiv_url" -o "$arxiv_raw" 2>/dev/null || true
        fi

        local arxiv_count
        arxiv_count="$(python3 - "$arxiv_raw" "$arxiv_json" << 'PYEOF' 2>/dev/null || true
import json, re, sys, xml.etree.ElementTree as ET
raw_path, out_path = sys.argv[1], sys.argv[2]
papers = []
try:
    root = ET.parse(raw_path).getroot()
except Exception:
    root = None
if root is not None:
    ns = {"a": "http://www.w3.org/2005/Atom"}
    for e in root.findall("a:entry", ns):
        title = re.sub(r"\s+", " ", (e.findtext("a:title", "", ns) or "")).strip()
        if not title:
            continue
        authors = e.findall("a:author", ns)
        author = "N/A"
        if authors:
            author = (authors[0].findtext("a:name", "", ns) or "").strip() or "N/A"
        year = (e.findtext("a:published", "", ns) or "")[:4] or "N/A"
        url = (e.findtext("a:id", "", ns) or "").strip() or "N/A"
        abstract = re.sub(r"\s+", " ", (e.findtext("a:summary", "", ns) or "")).strip()[:200] or "N/A"
        papers.append({
            "title": title,
            "author": author,
            "year": year,
            "url": url,
            "doi": "",
            "abstract": abstract
        })
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(papers, f, ensure_ascii=False)
print(len(papers))
PYEOF
)"
        [ -z "$arxiv_count" ] && arxiv_count="0"
        if [ "$arxiv_count" -eq 0 ] 2>/dev/null; then
          echo "[pipeline] WARN: arXiv API 결과 없음 (주제: ${SLUG})"
        fi

        if [ "$skip_api_flow" -eq 0 ]; then
          local ss_query
          ss_query="$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "$search_terms" 2>/dev/null || true)"
          local ss_url
          ss_url="https://api.semanticscholar.org/graph/v1/paper/search?query=${ss_query}&limit=10&fields=title,authors,year,externalIds,abstract,url"
          # SS API (circuit breaker 적용)
          if type _circuit_update_source &>/dev/null; then
            local _ss_open
            _ss_open="$(_circuit_is_open_and_recent "semantic_scholar" 2>/dev/null || echo 0)"
            if [[ "$_ss_open" == "1" ]]; then
              echo "[pipeline] S02: Semantic Scholar circuit OPEN — skip" >&2
            else
              local _ss_rc=0
              curl -s --max-time 30 "$ss_url" -o "$ss_raw" 2>/dev/null || _ss_rc=$?
              if [[ $_ss_rc -ne 0 ]] || [[ ! -s "$ss_raw" ]]; then
                _circuit_update_source "semantic_scholar" "failure" 2>/dev/null || true
                echo "[pipeline] S02: SS fetch 실패 (rc=$_ss_rc) — circuit 기록" >&2
              else
                _circuit_update_source "semantic_scholar" "success" 2>/dev/null || true
              fi
            fi
          else
            curl -s --max-time 30 "$ss_url" -o "$ss_raw" 2>/dev/null || true
          fi
          python3 - "$ss_raw" "$ss_json" << 'PYEOF' 2>/dev/null || true
import json, re, sys
raw_path, out_path = sys.argv[1], sys.argv[2]
papers = []
try:
    data = json.load(open(raw_path, encoding="utf-8"))
except Exception:
    data = {}
for p in data.get("data", []) if isinstance(data, dict) else []:
    title = re.sub(r"\s+", " ", (p.get("title") or "")).strip()
    if not title:
        continue
    authors = p.get("authors") or []
    author = "N/A"
    if isinstance(authors, list) and authors:
        author = ((authors[0] or {}).get("name") or "N/A").strip() or "N/A"
    year = str(p.get("year") or "N/A")
    ext = p.get("externalIds") or {}
    doi = (ext.get("DOI") or "").strip()
    arxiv_id = (ext.get("ArXiv") or "").strip()
    if arxiv_id:
        url = f"https://arxiv.org/abs/{arxiv_id}"
    elif p.get("url"):
        url = (p.get("url") or "").strip()
    else:
        url = "N/A"
    abstract = re.sub(r"\s+", " ", (p.get("abstract") or "")).strip()[:200] or "N/A"
    papers.append({
        "title": title,
        "author": author,
        "year": year,
        "url": url,
        "doi": doi,
        "abstract": abstract
    })
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(papers, f, ensure_ascii=False)
PYEOF

          # ── OpenAlex API (3번째 소스, circuit breaker 적용) ──
          local oa_json
          oa_json="$(mktemp "${PYTMPDIR}/oa_parsed_XXXXXX" 2>/dev/null || mktemp)"
          local oa_raw
          oa_raw="$(mktemp "${PYTMPDIR}/oa_raw_XXXXXX" 2>/dev/null || mktemp)"
          local oa_url
          oa_url="https://api.openalex.org/works?search=${slug_query}&per_page=10&select=id,title,authorships,publication_year,doi,primary_location"

          local _do_oa=1
          if type _circuit_update_source &>/dev/null; then
            local _oa_open
            _oa_open="$(_circuit_is_open_and_recent "openalex" 2>/dev/null || echo 0)"
            [[ "$_oa_open" == "1" ]] && _do_oa=0 && echo "[pipeline] S02: OpenAlex circuit OPEN — skip" >&2
          fi
          if [[ $_do_oa -eq 1 ]]; then
            local _oa_rc=0
            curl -s --max-time 20 "$oa_url" -o "$oa_raw" 2>/dev/null || _oa_rc=$?
            if [[ $_oa_rc -ne 0 ]] || [[ ! -s "$oa_raw" ]]; then
              type _circuit_update_source &>/dev/null && _circuit_update_source "openalex" "failure" 2>/dev/null || true
              echo "[pipeline] S02: OpenAlex fetch 실패" >&2
            else
              type _circuit_update_source &>/dev/null && _circuit_update_source "openalex" "success" 2>/dev/null || true
            fi
          fi
          python3 - "$oa_raw" "$oa_json" << 'PYEOF' 2>/dev/null || true
import json, re, sys
raw_path, out_path = sys.argv[1], sys.argv[2]
papers = []
try:
    data = json.load(open(raw_path, encoding="utf-8"))
except Exception:
    data = {}
for w in data.get("results", []) if isinstance(data, dict) else []:
    title = re.sub(r"\s+", " ", (w.get("title") or "")).strip()
    if not title:
        continue
    auths = w.get("authorships") or []
    author = "N/A"
    if auths and isinstance(auths, list):
        author = ((auths[0].get("author") or {}).get("display_name") or "N/A").strip()
    year = str(w.get("publication_year") or "N/A")
    doi = (w.get("doi") or "").replace("https://doi.org/", "").strip()
    loc = w.get("primary_location") or {}
    url = (loc.get("landing_page_url") or w.get("id") or "N/A").strip()
    papers.append({"title": title, "author": author, "year": year, "url": url, "doi": doi, "abstract": "N/A"})
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(papers, f, ensure_ascii=False)
PYEOF

          local total_api
          total_api="$(python3 - "$arxiv_json" "$ss_json" "$oa_json" "$merged_md" << 'PYEOF' 2>/dev/null || true
import difflib, json, re, sys
arxiv_path, ss_path, oa_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
def read(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return []
items = list(read(arxiv_path)) + list(read(ss_path)) + list(read(oa_path))
final = []
seen = []
for p in items:
    title = re.sub(r"\s+", " ", (p.get("title") or "")).strip()
    if not title:
        continue
    low = title.lower()
    dup = False
    for prev in seen:
        if low == prev or difflib.SequenceMatcher(None, low, prev).ratio() >= 0.8:
            dup = True
            break
    if dup:
        continue
    seen.append(low)
    final.append(p)
with open(out_path, "w", encoding="utf-8") as f:
    f.write(f"<!-- VERIFIED_PAPERS: {len(final)} -->\n\n")
    for idx, p in enumerate(final, 1):
        f.write(f"## 논문 {idx}: {(p.get('title') or 'N/A').strip()}\n")
        f.write(f"- 저자: {(p.get('author') or 'N/A').strip()}\n")
        f.write(f"- 연도: {(str(p.get('year') or 'N/A')).strip()}\n")
        f.write(f"- URL: {(p.get('url') or 'N/A').strip()}\n")
        doi = (p.get('doi') or '').strip()
        f.write(f"- DOI: {doi if doi else 'N/A'}\n")
        f.write(f"- Abstract: {(p.get('abstract') or 'N/A').strip()}\n\n")
print(len(final))
PYEOF
)"
          [ -z "$total_api" ] && total_api="0"

          if [ "$total_api" -eq 0 ] 2>/dev/null; then
            # API에서 논문 0편: Gemini 논문 생성(할루시네이션) 대신 게이트로 차단
            rm -f "$arxiv_raw" "$ss_raw" "$oa_raw" "$arxiv_json" "$ss_json" "$oa_json" "$merged_md" || true
            cat > "$out_file" << S02_WARN_EOF
<!-- VERIFIED_PAPERS: 0 -->
<!-- WARNING: API_NO_RESULTS -->

# S02 문헌 수집 — API 결과 없음

- **주제**: ${TOPIC}
- **arXiv 결과**: 0편
- **Semantic Scholar 결과**: 0편
- **생성**: $(timestamp)

## 원인 분석

arXiv 및 Semantic Scholar API에서 이 주제에 해당하는 논문을 찾지 못했습니다.

가능한 원인:
1. 주제가 너무 구체적이거나 신조어 포함
2. 학술 논문 데이터베이스에 미등재 주제 (실무/산업 주제)
3. 검색 키워드가 논문 제목/초록과 불일치

## 권장 조치

- 주제를 더 일반적인 학술 용어로 재범위화
- 예: "openclaw" → "AI agent skill marketplace security"
- 또는 --skip-experiment 없이 Gemini 웹 검색 기반 접근 사용

## 상태

이 단계에서 검증된 논문이 없으므로 파이프라인이 중단됩니다.
후속 단계(S04, S10)에서 인용할 실제 논문이 없어 할루시네이션 위험이 매우 높습니다.
S02_WARN_EOF
            save_checkpoint "$stage" "completed"
            echo "[pipeline] S02 API 결과 없음 → 재범위화 게이트 진입"
            jq --arg gs "S02_NO_RESULTS" '.gate_pending_stage = $gs' "$PIPELINE_FILE" > "${PIPELINE_FILE}.tmp" && mv "${PIPELINE_FILE}.tmp" "$PIPELINE_FILE"
            exit 42
          else

            cp "$merged_md" "$out_file" 2>/dev/null || true
            local collected
            collected="$(cat "$out_file" 2>/dev/null || true)"
            local analyze_brief
            analyze_brief="아래 실제 수집된 논문들을 분석하고, 각 논문의 핵심 주장과 연구 주제와의 관련성을 한국어로 정리하라.

연구 주제: ${TOPIC}

${collected}"
            local tmp_g
            tmp_g="$(mktemp)"
            local eg=0
            NO_VAULT=true FORCE=true bash "$ORCH" gemini "$analyze_brief" "s02-literature-analysis-${SLUG}" > "$tmp_g" 2>&1 &
            local bg_pid=$!
            local elapsed=0
            while kill -0 "$bg_pid" 2>/dev/null && [ "$elapsed" -lt 180 ]; do
              sleep 5
              elapsed=$((elapsed + 5))
            done
            if kill -0 "$bg_pid" 2>/dev/null; then
              _kill_tree "$bg_pid"; wait "$bg_pid" 2>/dev/null || true
              eg=124
            else
              wait "$bg_pid" || eg=$?
            fi
            local g_full gr
            g_full="$(cat "$tmp_g" 2>/dev/null || true)"
            rm -f "$tmp_g" || true
            gr="$(printf '%s\n' "$g_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
            [ -z "$gr" ] && gr="$g_full"
            gr="$(printf '%s\n' "$gr" | /usr/bin/grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]' || true)"
            {
              echo ""
              echo "## API 수집 논문 보강 분석 (Gemini)"
              echo ""
              if [ -n "$gr" ] && [ "$eg" -eq 0 ]; then
                printf '%s\n' "$gr"
              else
                printf '(Gemini 분석 실패 exit=%d)\n' "$eg"
              fi
            } >> "$out_file"
            rm -f "$arxiv_raw" "$ss_raw" "$oa_raw" "$arxiv_json" "$ss_json" "$oa_json" "$merged_md" || true
          fi
        fi
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
        brief="${brief}

주의: 위 문헌 목록에 포함된 논문만을 근거로 사용할 것. 목록에 없는 논문을 인용하거나 생성하지 말 것."
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
        # S11은 논문 전체를 검토해야 하므로 truncation 한도를 20000으로 확대
        local tmpl11_content; tmpl11_content="$(cat "$tmpl11")"
        local draft_truncated; draft_truncated="$(truncate_payload "$draft" 20000)"
        local brief11
        brief11="${tmpl11_content//\{TOPIC\}/$TOPIC}"
        brief11="${brief11//\{DRAFT\}/$draft_truncated}"
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
        python3 - "$base_file" "$additions_file" "$PAPER_DIR/draft.md" << 'PYEOF'
import sys, re

base_path, add_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(base_path, encoding="utf-8") as f:
    base = f.read()
try:
    with open(add_path, encoding="utf-8") as f:
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
    # Fix: content가 동일 헤딩으로 시작하면 제거 (중복 헤딩 방지)
    content = re.sub(r'^##\s+' + re.escape(heading) + r'\s*\n?', '', content, count=1).strip()
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
with open(out_path, "w", encoding="utf-8") as f:
    f.write('\n'.join(lines))
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

        # Layer 2: Semantic Scholar DOI 검증
        local dois
        dois="$(printf '%s\n' "$draft14" | /usr/bin/grep -oE '10\.[0-9]{4,}/[^ )>"`]+' | sort -u || true)"
        local doi_report=""
        if [ -n "$dois" ]; then
          while IFS= read -r doi; do
            [ -z "$doi" ] && continue
            local ss_result
            ss_result="$(curl -s --max-time 8 "https://api.semanticscholar.org/graph/v1/paper/DOI:${doi}?fields=title,year" 2>/dev/null || echo "")"
            if printf '%s' "$ss_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null | grep -q .; then
              local ss_title
              ss_title="$(printf '%s' "$ss_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null || true)"
              doi_report="${doi_report}- ✅ DOI:${doi} → \"${ss_title}\"\n"
            else
              doi_report="${doi_report}- ❌ DOI:${doi} → Semantic Scholar에서 확인 불가\n"
            fi
          done <<< "$dois"
        else
          doi_report="(draft에서 DOI 없음)\n"
        fi

        # Layer 3: Gemini로 인용 서지 정보 일관성 검증
        local url_summary
        url_summary="$(printf '%b' "$curl_report")"
        local ref_section
        ref_section="$(printf '%s\n' "$draft14" | awk '/^## References|^## 8\. References/{found=1} found')"
        [ -z "$ref_section" ] && ref_section="(References 섹션 없음)"

        local doi_summary
        doi_summary="$(printf '%b' "$doi_report")"
        local brief14
        brief14="You are running S14 citation verification.

Topic: ${TOPIC}

## URL Audit Results (curl HEAD check)
${url_summary}

## DOI Verification (Semantic Scholar)
${doi_summary}

## References Section
$(truncate_payload "$ref_section" 4000)

## Task
Based on the URL audit and DOI verification results above:
1. List each citation with its verification status (verified/partial/unverified)
2. Flag citations with broken URLs (❌), unconfirmed DOIs (❌), missing URLs, or incomplete bibliographic info
3. Suggest specific fixes for each problematic citation

## Output Format
# S14 Citation Verification

## Citation Status
| Citation | URL Status | DOI Status | Verdict |
|----------|-----------|-----------|---------|

## Issues & Fixes
- ...

## Summary
- Total citations: N
- Verified: N | Partial: N | Unverified: N"

        run_stage_gemini "$stage" "$brief14" "s14-citation-verify-${SLUG}"

        # Layer 4: VerifiedRegistry 수치 검증 (registry가 있는 경우만)
        if type registry_verify_draft &>/dev/null && [ -f "$STATE_DIR/verified_registry.json" ]; then
          echo "[pipeline] S14 Layer 4: VerifiedRegistry 수치 검증" >&2
          local reg_report
          reg_report="$(registry_verify_draft "$PAPER_DIR/draft.md" 2>/dev/null || true)"
          if [ -n "$reg_report" ]; then
            {
              printf '\n\n---\n\n## Layer 4: 수치 검증 (VerifiedRegistry)\n\n'
              printf '%s\n' "$reg_report"
            } >> "$out_file"
            echo "[pipeline] S14 Layer 4 완료 — 수치 검증 보고서 추가" >&2
          fi
        fi

        # S14 하드 스톱: 미검증 비율 50% 초과 시 게이트 진입
        # grep 대신 python3 사용 (grep→rg alias 충돌 방지)
        local s14_total s14_verified s14_unverified s14_unverified_rate
        read -r s14_total s14_verified s14_unverified < <(python3 - "$out_file" <<'PYPARSE'
import re, sys
text = open(sys.argv[1]).read()
def extract(pattern):
    m = re.search(pattern, text)
    return m.group(1) if m else "0"
print(extract(r'Total citations:\s*(\d+)'),
      extract(r'(?<![Un])Verified:\s*(\d+)'),
      extract(r'Unverified:\s*(\d+)'))
PYPARSE
) 2>/dev/null || { s14_total=0; s14_verified=0; s14_unverified=0; }
        s14_total="${s14_total:-0}"; s14_verified="${s14_verified:-0}"; s14_unverified="${s14_unverified:-0}"
        if [ "$s14_total" -gt 0 ] 2>/dev/null; then
          s14_unverified_rate=$(( s14_unverified * 100 / s14_total ))
          if [ "$s14_unverified_rate" -ge 50 ] 2>/dev/null; then
            echo "[pipeline] S14 경고: 미검증 인용 ${s14_unverified_rate}% (${s14_unverified}/${s14_total}) — 게이트 진입"
            {
              printf '\n\n---\n\n## ⚠️ 인용 품질 경고\n\n'
              printf '- 전체: %d | 검증: %d | 미검증: %d\n' "$s14_total" "$s14_verified" "$s14_unverified"
              printf '- 미검증 비율: **%d%%** (임계값 50%%)\n' "$s14_unverified_rate"
              printf '\n파이프라인이 인용 품질 문제로 일시 중단되었습니다.\n'
              printf '`--approve-gate S14` 로 강제 진행하거나, 논문 초안을 수정 후 재실행하세요.\n'
            } >> "$out_file"
            save_checkpoint "$stage" "completed"
            jq --arg gs "S14" '.gate_pending_stage = $gs' "$PIPELINE_FILE" > "${PIPELINE_FILE}.tmp" && mv "${PIPELINE_FILE}.tmp" "$PIPELINE_FILE"
            exit 42
          fi
        fi
        ;;
      S15)
        # 0) 구조 검사 (Python) — 중복 헤딩·필수 섹션 누락 탐지
        local struct_warn=""
        local draft_path
        draft_path="$([ -f "$PAPER_DIR/draft.md" ] && echo "$PAPER_DIR/draft.md" || echo "$STATE_DIR/s11_revised.md")"
        local struct_issues
        struct_issues="$(python3 - "$draft_path" << 'PYEOF'
import sys, re
from collections import Counter
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        content = f.read()
except Exception:
    content = ''
headings = re.findall(r'^## .+', content, re.MULTILINE)
dup = [h for h, c in Counter(headings).items() if c > 1]
issues = []
if dup:
    issues.append('중복 헤딩: ' + ', '.join(dup))
for req in ['서론', '결론', '참고문헌']:
    if not re.search(r'^## .*' + req, content, re.MULTILINE):
        issues.append('필수 섹션 누락: ' + req)
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
print('\n'.join(issues))
PYEOF
)" || true
        if [ -n "$struct_issues" ]; then
          struct_warn="$(printf '[구조 검사 경고]\n%s\n\n' "$struct_issues")"
          echo "[pipeline] WARN S15 구조 문제 발견: $struct_issues" >&2
        fi

        # 1) 전체 draft 로드 (truncation 없음 — 모든 리뷰어가 동일한 전체 문서를 검토)
        local draft_content
        draft_content="$(cat "$draft_path" 2>/dev/null || echo '(draft 없음)')"

        # 2) 공통 리뷰 프롬프트 (섹션별 평가 형식)
        local review_ko_header="## 논문 피어리뷰

주제: ${TOPIC}

논문 초안을 읽고 각 섹션(## 헤딩 기준)을 순서대로 독립적으로 평가해라.

각 섹션에 대해:
### [섹션 제목]: [Strong / Moderate / Weak]
- 논리 일관성: ...
- 근거 품질: ...
- 문제점 (있다면): ...

모든 섹션 평가 후 최종 판정:
## 최종 판정
- Overall verdict: Accept / Minor Revision / Major Revision
- 핵심 수정 요청 (상위 3개):
- 강점 (상위 2개):

---

## 논문 초안
"
        local full_prompt_ko="${review_ko_header}${draft_content}"

        local full_prompt_en="## Paper Peer Review

Topic: ${TOPIC}

Read the paper draft and evaluate each section (## headings) in order, independently.

For each section:
### [Section Title]: [Strong / Moderate / Weak]
- Logical consistency: ...
- Evidence quality: ...
- Issues (if any): ...

After all sections, conclude:
## Final Verdict
- Overall verdict: Accept / Minor Revision / Major Revision
- Top revision requests (top 3):
- Strengths (top 2):

---

## Paper Draft
${draft_content}"

        # 3) 3 리뷰어 병렬 실행 — Gemini, Codex, Claude (모두 동일한 전체 문서)
        local gemini_out="${STATE_DIR}/s15_gemini_review.md"
        local codex_out="${STATE_DIR}/s15_codex_review.md"
        local claude_out="${STATE_DIR}/s15_claude_review.md"
        local tmp_g tmp_c tmp_cl
        tmp_g="$(mktemp)"; tmp_c="$(mktemp)"; tmp_cl="$(mktemp)"

        NO_VAULT=true FORCE=true bash "$ORCH" gemini "$full_prompt_ko" "s15-gemini-${SLUG}" > "$tmp_g" 2>&1 &
        local gp=$!

        NO_VAULT=true FORCE=true bash "$ORCH" codex "$full_prompt_en" "s15-codex-${SLUG}" > "$tmp_c" 2>&1 &
        local cp2=$!

        # Claude 리뷰: claude -p (Max plan 커버, 별도 API 과금 없음)
        {
          claude -p "$full_prompt_ko" --output-format text 2>/dev/null \
            || claude --print "$full_prompt_ko" 2>/dev/null \
            || echo "(Claude 리뷰 실패: claude CLI 호출 불가)"
        } > "$tmp_cl" &
        local clp=$!

        # 타임아웃: Gemini 180s, Codex 300s, Claude 180s (각 독립 추적)
        local g_elapsed=0 c_elapsed=0 cl_elapsed=0
        local g_done=false c_done=false cl_done=false
        local eg=0 eck=0 ecl=0
        while true; do
          sleep 5
          if ! $g_done; then
            g_elapsed=$((g_elapsed+5))
            if ! kill -0 "$gp" 2>/dev/null; then
              wait "$gp" || eg=$?; g_done=true
            elif [ "$g_elapsed" -ge 180 ]; then
              kill "$gp" 2>/dev/null; wait "$gp" 2>/dev/null; eg=124; g_done=true
            fi
          fi
          if ! $c_done; then
            c_elapsed=$((c_elapsed+5))
            if ! kill -0 "$cp2" 2>/dev/null; then
              wait "$cp2" || eck=$?; c_done=true
            elif [ "$c_elapsed" -ge 300 ]; then
              kill "$cp2" 2>/dev/null; wait "$cp2" 2>/dev/null; eck=124; c_done=true
            fi
          fi
          if ! $cl_done; then
            cl_elapsed=$((cl_elapsed+5))
            if ! kill -0 "$clp" 2>/dev/null; then
              wait "$clp" || ecl=$?; cl_done=true
            elif [ "$cl_elapsed" -ge 180 ]; then
              kill "$clp" 2>/dev/null; wait "$clp" 2>/dev/null; ecl=124; cl_done=true
            fi
          fi
          $g_done && $c_done && $cl_done && break
        done

        # 결과 추출 + 정제
        local g_full; g_full="$(cat "$tmp_g")"; rm -f "$tmp_g"
        local gr; gr="$(printf '%s\n' "$g_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
        [ -z "$gr" ] && gr="$g_full"
        gr="$(printf '%s\n' "$gr" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
        [ -z "$gr" ] && gr="(Gemini 리뷰 실패 exit=$eg)"
        printf '%s\n' "$gr" > "$gemini_out"

        local c_full; c_full="$(cat "$tmp_c")"; rm -f "$tmp_c"
        local cr; cr="$(printf '%s\n' "$c_full" | awk '/^--- Codex Summary ---/{found=1;next}found')"
        [ -z "$cr" ] && cr="$c_full"
        cr="$(printf '%s\n' "$cr" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
        [ -z "$cr" ] && cr="(Codex 리뷰 실패 exit=$eck)"
        printf '%s\n' "$cr" > "$codex_out"

        local clr; clr="$(cat "$tmp_cl" 2>/dev/null || echo "(Claude 리뷰 실패 exit=$ecl)")"
        rm -f "$tmp_cl"
        [ -z "$clr" ] && clr="(Claude 리뷰 실패 exit=$ecl)"
        printf '%s\n' "$clr" > "$claude_out"

        # 4) 합성 — 3 리뷰어 섹션별 평가 + 최종 판정 비교
        local synth_brief="## 3-Agent 피어리뷰 합성

주제: ${TOPIC}

${struct_warn}아래는 세 AI 리뷰어의 섹션별 독립 리뷰다 (모두 동일한 전체 논문 초안을 검토).
각 리뷰어의 섹션별 평가와 최종 판정(## 최종 판정)을 비교·분석하고 합의 결과를 도출해라.

### Gemini 리뷰
${gr}

---

### Codex 리뷰
${cr}

---

### Claude 리뷰
${clr}

---

## 출력 형식

### 섹션별 합의 요약
(2개 이상 리뷰어가 공통으로 지적한 섹션별 문제 — 섹션명과 문제 서술)

### 리뷰어 간 의견 차이
(평가가 갈린 섹션 + 이유 분석)

### 최종 판정 비교

| 리뷰어 | Overall Verdict |
|---|---|
| Gemini | ... |
| Codex | ... |
| Claude | ... |
| **합의** | ... |

### 최우선 수정 권고
(2개 이상 리뷰어가 공통 지적한 문제, 우선순위 순 — 최대 5개)"
        # 합성: Claude (Max plan) — Gemini 호출 절감 (Gemini: 리뷰 1회로 축소)
        local synth_out="${STATE_DIR}/s15_synthesis.md"
        local tmp_s; tmp_s="$(mktemp)"
        local es=0
        {
          claude -p "$synth_brief" --output-format text 2>/dev/null \
            || claude --print "$synth_brief" 2>/dev/null \
            || echo "(합성 실패: claude CLI 호출 불가)"
        } > "$tmp_s" &
        local sp=$!; local se=0
        while kill -0 "$sp" 2>/dev/null && [ "$se" -lt 180 ]; do sleep 5; se=$((se+5)); done
        if kill -0 "$sp" 2>/dev/null; then kill "$sp"; wait "$sp" 2>/dev/null; es=124; else wait "$sp" || es=$?; fi
        local sr; sr="$(cat "$tmp_s")"; rm -f "$tmp_s"
        [ -z "$sr" ] && sr="(합성 실패 exit=$es)"
        printf '%s\n' "$sr" > "$synth_out"

        cat > "$out_file" << S15_EOF
# S15 멀티에이전트 검증 보고서

- **주제**: ${TOPIC}
- **생성**: $(timestamp)
- **검증 에이전트**: Gemini CLI (섹션별 리뷰), Codex CLI (섹션별 리뷰), Claude CLI (섹션별 리뷰 + 합성)

---

## Gemini 리뷰 (섹션별)

$(cat "$gemini_out")

---

## Codex 리뷰 (섹션별)

$(cat "$codex_out")

---

## Claude 리뷰 (섹션별)

$(cat "$claude_out")

---

## 합성 의견 (Claude — 3-Agent 최종 판정 비교)

$(cat "$synth_out")

---

## 검증 파일
- Gemini 리뷰: state/s15_gemini_review.md
- Codex 리뷰: state/s15_codex_review.md
- Claude 리뷰: state/s15_claude_review.md
- 합성: state/s15_synthesis.md
S15_EOF

        # S15 Auto-Revision: 합성 테이블의 합의 verdict 추출
        local s15_verdict
        # 1차: 합의 테이블 행에서 추출 (| **합의** | Minor Revision |)
        s15_verdict="$(grep -iE '^\|[[:space:]]*\*\*합의\*\*' "$synth_out" | grep -oiE 'Accept|Minor Revision|Major Revision' | head -1 || true)"
        # 2차: 최종 판정 비교 섹션 범위 내에서 추출
        [ -z "$s15_verdict" ] && s15_verdict="$(awk '/최종 판정 비교|Final Verdict Comparison/,/^###/' "$synth_out" | grep -oiE 'Accept|Minor Revision|Major Revision' | tail -1 || true)"
        # 3차: 파일 전체에서 마지막 verdict (가장 늦게 등장 = 합성 결론)
        [ -z "$s15_verdict" ] && s15_verdict="$(grep -oiE 'Accept|Minor Revision|Major Revision' "$synth_out" | tail -1 || true)"
        if [[ "$s15_verdict" == *"Revision"* ]]; then
          echo "[pipeline] S15 verdict: $s15_verdict — 자동 수정 시작..."
          local current_draft
          current_draft="$(cat "$PAPER_DIR/draft.md" 2>/dev/null || cat "$STATE_DIR/s11_revised.md" 2>/dev/null || echo '')"
          local synth_report
          synth_report="$(cat "$synth_out")"
          local rev_brief
          rev_brief="## 논문 자동 수정 요청

주제: ${TOPIC}

아래는 멀티에이전트 검증(S15) 결과 합성 보고서다. Overall verdict는 '${s15_verdict}'였다.
보고서에서 지적된 문제들을 반영하여 논문 초안을 수정해라.

**수정 규칙:**
- 검증 보고서의 '섹션별 합의 요약(공통 지적 문제)'을 우선 수정
- 논리적 일관성, 근거 품질, 구조 완성도 문제를 고쳐라
- 원문의 핵심 주장과 인용은 유지하되, 약한 부분만 강화해라
- 출력: 수정된 완전한 논문 마크다운 전체 (섹션 헤딩, 초록, 본문, 참고문헌 포함)

## 검증 보고서 (S15 Synthesis)
$(printf '%s' "$synth_report" | head -200)

## 현재 논문 초안
$(printf '%s' "$current_draft" | head -300)"

          local rev_tmp; rev_tmp="$(mktemp)"
          local er=0
          NO_VAULT=true FORCE=true bash "$ORCH" gemini "$rev_brief" "s15-revision-${SLUG}" > "$rev_tmp" 2>&1 &
          local rp=$!; local re=0
          while kill -0 "$rp" 2>/dev/null && [ "$re" -lt 300 ]; do sleep 5; re=$((re+5)); done
          if kill -0 "$rp" 2>/dev/null; then kill "$rp"; wait "$rp" 2>/dev/null; er=124; else wait "$rp" || er=$?; fi
          local r_full; r_full="$(cat "$rev_tmp")"; rm -f "$rev_tmp"
          local revised; revised="$(printf '%s\n' "$r_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
          [ -z "$revised" ] && revised="$r_full"
          revised="$(printf '%s\n' "$revised" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]')"
          # Gemini 서두 제거: 첫 번째 마크다운 헤딩(#) 이전 줄 제거 (heading 없으면 원본 유지)
          local revised_stripped; revised_stripped="$(printf '%s\n' "$revised" | awk '/^#/{found=1} found')"
          [ -n "$revised_stripped" ] && revised="$revised_stripped"
          if [ -n "$revised" ] && [ "$er" -eq 0 ]; then
            cp "$PAPER_DIR/draft.md" "$PAPER_DIR/draft_pre_s15_revision.md" 2>/dev/null || true
            printf '%s\n' "$revised" > "$PAPER_DIR/draft.md"
            echo "[pipeline] S15 자동 수정 완료 → draft.md 업데이트 (백업: draft_pre_s15_revision.md)"
            printf '\n\n---\n\n## S15 자동 수정\n\n- verdict: %s\n- 수정 완료: %s\n- 백업: draft_pre_s15_revision.md\n' \
              "$s15_verdict" "$(timestamp)" >> "$out_file"

            # 경량 재검증: 수정 후 주요 문제가 해결됐는지 확인
            echo "[pipeline] S15 수정 후 경량 재검증 시작..."
            local recheck_draft; recheck_draft="$(head -c 12000 "$PAPER_DIR/draft.md")"
            local recheck_brief
            recheck_brief="## S15 수정 후 경량 재검증

이전 검토에서 지적된 핵심 문제가 수정된 논문 초안에서 해결되었는지만 확인하라.

### 이전 주요 지적사항 (합성 보고서 요약)
$(printf '%s\n' "$sr" | head -60)

### 수정된 초안 (앞부분)
${recheck_draft}

### 확인 항목 (각 항목 Yes/No/Partial)
1. 근거 품질 개선 여부
2. 인용 신뢰도 개선 여부
3. 논리적 일관성 유지 여부

### 결론: 수정이 충분한가? (Sufficient / Insufficient)"

            local rck_tmp; rck_tmp="$(mktemp)"
            local rck_e=0
            NO_VAULT=true FORCE=true bash "$ORCH" gemini "$recheck_brief" "s15-recheck-${SLUG}" > "$rck_tmp" 2>&1 &
            local rck_pid=$!; local rck_t=0
            while kill -0 "$rck_pid" 2>/dev/null && [ "$rck_t" -lt 120 ]; do sleep 5; rck_t=$((rck_t+5)); done
            if kill -0 "$rck_pid" 2>/dev/null; then kill "$rck_pid"; wait "$rck_pid" 2>/dev/null; rck_e=124; else wait "$rck_pid" || rck_e=$?; fi
            local rck_full; rck_full="$(cat "$rck_tmp")"; rm -f "$rck_tmp"
            local rck_result; rck_result="$(printf '%s\n' "$rck_full" | awk '/^--- Gemini Result ---/{found=1;next}found')"
            [ -z "$rck_result" ] && rck_result="$rck_full"
            rck_result="$(printf '%s\n' "$rck_result" | grep -v '^\s*at async\|^\s*at Object\|node:internal\|node_modules\|^\[LOG\]\|^\[QUEUE\]' || true)"
            local rck_verdict; rck_verdict="$(printf '%s\n' "$rck_result" | grep -oiE 'Sufficient|Insufficient' | head -1 || true)"
            printf '\n\n---\n\n## S15 재검증 결과\n\n%s\n\n- 판정: **%s**\n' \
              "$rck_result" "${rck_verdict:-확인불가}" >> "$out_file"
            if [ "${rck_verdict}" = "Insufficient" ]; then
              echo "[pipeline] WARN: S15 재검증 결과 Insufficient — S15 게이트 진입"
              jq --arg gs "S15" '.gate_pending_stage = $gs' "$PIPELINE_FILE" > "${PIPELINE_FILE}.tmp" && mv "${PIPELINE_FILE}.tmp" "$PIPELINE_FILE"
              exit 42
            fi
          else
            echo "[pipeline] WARN: S15 자동 수정 실패 (exit=$er) — 원본 초안 유지"
          fi
        else
          echo "[pipeline] S15 verdict: ${s15_verdict:-확인불가} — 수정 불필요, S16으로 진행"
        fi
        ;;
      S16)
        # markdown → Typst → PDF (typst compile)
        # 파일명: 논문 첫 줄 제목 기반 (한국어 포함, 파일명 불가 문자만 제거)
        local paper_title
        # H1만 제목으로 사용, H2(초록 등) 제외
        paper_title="$(grep -m1 '^# [^#]' "$PAPER_DIR/draft.md" 2>/dev/null | sed 's/^#* *//' || true)"
        # H1 없으면 SLUG 사용
        [ -z "$paper_title" ] && paper_title="${SLUG}"
        # 파일명 불가 문자(/ \ : * ? " < > |)와 공백 → 언더스코어, 연속 언더스코어 정리
        paper_title="$(printf '%s' "$paper_title" | sed 's|[/\\:*?"<>|]|_|g; s/[[:space:]]/_/g; s/__*/_/g; s/^_//; s/_$//')"
        if [ "${#paper_title}" -lt 2 ]; then
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
          raw_title="$(grep -m1 '^# [^#]' "$PAPER_DIR/draft.md" 2>/dev/null | sed 's/^#* *//' || true)"
          [ -z "$raw_title" ] && raw_title="${TOPIC}"
          abstract_text="$(python3 - "$PAPER_DIR/draft.md" << 'PYEOF'
import sys, re
lines = open(sys.argv[1], encoding="utf-8").read().split('\n')
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
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
print('\n'.join(buf).strip())
PYEOF
)"

          # 1) 초록 제외한 본문 추출 + 헤딩 전후 빈 줄 보장
          local body_md="$PAPER_DIR/draft_body.md"
          python3 - "$PAPER_DIR/draft.md" "$body_md" << 'PYEOF'
import sys, re
lines = open(sys.argv[1], encoding="utf-8").read().split('\n')
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

content = '\n'.join(out)
# 헤딩 전 빈 줄 보장 (pandoc이 헤딩으로 인식하도록)
content = re.sub(r'([^\n])\n(#{1,6} )', r'\1\n\n\2', content)
# 헤딩 후 빈 줄 보장
content = re.sub(r'(#{1,6} [^\n]+)\n([^\n#\s])', r'\1\n\n\2', content)
# 3줄 이상 연속 빈 줄 → 2줄로
content = re.sub(r'\n{3,}', '\n\n', content)
open(sys.argv[2], 'w', encoding="utf-8").write(content)
PYEOF

          # 2) pandoc: markdown body → typst
          #    --shift-heading-level-by=-1: ##(H2) → level1(=), ###(H3) → level2(==)
          local body_typ="$PAPER_DIR/draft_body.typ"
          pandoc "$body_md" --from markdown --to typst \
            --shift-heading-level-by=-1 \
            -o "$body_typ" 2>/dev/null || true
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

        # S08 자동 실행 + self-healing retry
        if type run_with_retry &>/dev/null; then
          echo "[pipeline] S08: 실험 자동 실행 (self-heal max 3회)" >&2
          local exp_dir="$STATE_DIR/s07_code"
          local exp_out exp_exit
          local s08_attempt=0 s08_max=3 s08_success=0

          while (( s08_attempt < s08_max )); do
            s08_attempt=$((s08_attempt + 1))
            echo "[pipeline] S08: 시도 ${s08_attempt}/${s08_max}" >&2

            set +e
            exp_out="$(cd "$exp_dir" && python3 experiment.py 2>&1)"
            exp_exit=$?
            set -e

            if [[ $exp_exit -eq 0 && "$exp_out" =~ [^[:space:]] ]]; then
              s08_success=1
              break
            fi

            local err_cat
            err_cat="$(classify_error "$exp_exit" "$exp_out")"
            log_retry "$s08_attempt" "$err_cat"
            echo "[pipeline] S08: 에러 분류=$err_cat, 자동 수정 시도" >&2

            if (( s08_attempt >= s08_max )); then break; fi

            # Codex에게 코드 수정 요청
            local fix_prompt
            fix_prompt="$(generate_fix_prompt "$err_cat" "$(cat "$exp_dir/experiment.py")" "$exp_out")"
            local fixed_code
            fixed_code="$(bash "$ORCH" codex "$fix_prompt" s08-fix-${s08_attempt} 2>/dev/null || true)"
            if [[ -n "$fixed_code" ]]; then
              # 코드 블록 추출 후 덮어쓰기
              printf '%s\n' "$fixed_code" | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'\`\`\`python\n(.*?)\`\`\`', text, re.DOTALL)
if m: print(m.group(1))
else: print(text)
" > "$exp_dir/experiment.py"
            fi
          done

          if [[ $s08_success -eq 1 ]]; then
            printf '# S08 실험 결과 (자동 실행)\n\n%s\n' "$exp_out" > "$out_file"
            # VerifiedRegistry: 실험 결과에서 수치 자동 추출
            if type registry_init &>/dev/null; then
              registry_init 2>/dev/null || true
              registry_extract_from_experiment "$out_file" 2>/dev/null || true
              echo "[pipeline] S08: VerifiedRegistry에 실험 수치 등록 완료" >&2
            fi
          else
            printf '# S08 실험 결과\n\n실행 실패 (%s회 시도). 수동 개입 필요.\n\n## 마지막 에러\n%s\n' "$s08_max" "$exp_out" > "$out_file"
            echo "[pipeline] WARN: S08 자동 실행 실패, 수동 개입 필요" >&2
          fi
        else
          # self_heal.sh 미로드 시 기존 동작
          printf '실행 결과: [수동 입력 필요]\n' > "$out_file"
        fi
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
        TEMPLATE="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
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

  # MetaClaw: 실행 이력 수집 (정상 종료 시)
  if type metaclaw_collect &>/dev/null; then
    metaclaw_collect 2>/dev/null || true
    echo "[pipeline] MetaClaw: 실행 이력 수집 완료" >&2
  fi
}

main "$@"
