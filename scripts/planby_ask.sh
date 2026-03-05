#!/bin/bash
# planby_ask.sh — AnythingLLM에서 플랜바이 문서 청크 검색
# 사용법: bash planby_ask.sh "질문"

QUERY="$1"
API_KEY="planby-cb99f5222e56c3ed40d98c77e35bf001"
WORKSPACE_SLUG="4b7216ef-9bb1-4553-a2b0-0478a73d5b03"
N_RESULTS="${2:-6}"

if [ -z "$QUERY" ]; then
  echo "사용법: planby_ask.sh \"질문\""
  exit 1
fi

curl -s -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"${QUERY}\", \"mode\": \"query\"}" \
  "http://localhost:3001/api/v1/workspace/${WORKSPACE_SLUG}/chat" | \
python3 -c "
import sys, json
d = json.load(sys.stdin)
sources = d.get('sources', [])
print(f'=== 플랜바이 문서 검색 결과: {len(sources)}개 청크 ===\n')
for i, s in enumerate(sources):
    print(f'[{i+1}] 출처: {s.get(\"title\",\"\")}')
    text = s.get('text','').replace('<document_metadata>', '').replace('</document_metadata>', '').strip()
    # 메타데이터 헤더 제거
    lines = [l for l in text.split('\n') if not l.startswith('sourceDocument:') and not l.startswith('published:')]
    print('\n'.join(lines).strip()[:800])
    print()
"
