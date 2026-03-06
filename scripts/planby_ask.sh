#!/bin/bash
# planby_ask.sh — AnythingLLM 플랜바이 문서 검색 (워크스페이스 자동 라우팅)
# 사용법: bash planby_ask.sh "질문" [N결과수] [--workspace <이름>]
#
# 워크스페이스 자동 선택 기준:
#   재무세무  — 재무제표, 세금, 회계, 결산, 감사 등
#   전략영업  — 전략, 영업, 고객, OKR, 가격 등
#   회의초안  — 회의록, 초안, 메모, 아이디어 등
#   기준문서  — 계약서, 정책, 운영기준, 공식 스펙 등
#   전체      — 분류 불명확 시 fallback (구 통합 워크스페이스)

QUERY="${1:-}"
N_RESULTS="${2:-6}"
FORCE_WS=""

shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) FORCE_WS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

API_KEY="planby-cb99f5222e56c3ed40d98c77e35bf001"
BASE_URL="http://localhost:3001/api/v1"

if [ -z "$QUERY" ]; then
  echo "사용법: bash planby_ask.sh \"질문\" [N] [--workspace 재무세무|전략영업|회의초안|기준문서|전체]"
  exit 1
fi

# ─── 워크스페이스 자동 선택 (키워드 기반) ─────────────────────
if [ -n "$FORCE_WS" ]; then
  SELECTED_WS="$FORCE_WS"
else
  SELECTED_WS="전체"

  if echo "$QUERY" | grep -qiE '재무제표|재무상태|손익|현금흐름|자본|세무|세금|법인세|부가세|소득세|회계|결산|감사|장부|계정|분개|원가|수익|비용|이익|손실|자산|부채|매출|영업이익|당기순이익|이월결손금|세액공제|세율|납세|환급|신고'; then
    SELECTED_WS="재무세무"
  elif echo "$QUERY" | grep -qiE '전략|사업계획|사업모델|로드맵|OKR|KPI|ROI|영업|고객|파이프라인|제안서|계약|가격|단가|요금제|경쟁사|시장|포지셔닝|마케팅|파트너|채널|세일즈'; then
    SELECTED_WS="전략영업"
  elif echo "$QUERY" | grep -qiE '회의|회의록|미팅|초안|draft|메모|아이디어|검토|리뷰|피드백|논의|결정사항|액션아이템'; then
    SELECTED_WS="회의초안"
  elif echo "$QUERY" | grep -qiE '계약서|정책|운영기준|가이드라인|SOP|규정|기준|공식|스펙|요구사항|프로세스|절차|매뉴얼'; then
    SELECTED_WS="기준문서"
  fi
fi

# ─── slug 매핑 ────────────────────────────────────────────────
case "$SELECTED_WS" in
  기준문서) SLUG="0fb026cf-455b-40b9-911e-33ba8c63dbaa" ;;
  재무세무) SLUG="51656bcc-e741-4e16-8094-4c813fe259bf" ;;
  전략영업) SLUG="0e6792e6-bc20-4e49-9d24-91af61bbf5fb" ;;
  회의초안) SLUG="497efbac-31d9-4864-8d53-98a49437d51e" ;;
  전체|*)   SLUG="4b7216ef-9bb1-4553-a2b0-0478a73d5b03"; SELECTED_WS="전체" ;;
esac

echo "📂 워크스페이스: $SELECTED_WS" >&2

# ─── 쿼리 실행 ────────────────────────────────────────────────
curl -s -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"${QUERY}\", \"mode\": \"query\"}" \
  "${BASE_URL}/workspace/${SLUG}/chat" | \
python3 -c "
import sys, json
d = json.load(sys.stdin)
sources = d.get('sources', [])
print(f'=== 플랜바이 문서 검색 결과: {len(sources)}개 청크 ===\n')
for i, s in enumerate(sources):
    print(f'[{i+1}] 출처: {s.get(\"title\",\"\")}')
    text = s.get('text','').replace('<document_metadata>', '').replace('</document_metadata>', '').strip()
    lines = [l for l in text.split('\n') if not l.startswith('sourceDocument:') and not l.startswith('published:')]
    print('\n'.join(lines).strip()[:800])
    print()
"
