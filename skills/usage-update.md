# Usage Update

에이전트 사용량을 확인하고 모드를 조정한다.

## 실행 흐름

1. 사용자에게 질문해라:
   > 각 에이전트의 남은 사용량을 알려주세요.
   > (예: "클로드 60%, 코덱스 넉넉, 제미나이 거의 다 씀")
   >
   > 확인 방법:
   > - Claude: `/usage` 또는 https://claude.ai/settings/usage
   > - Codex: `/status` 또는 https://chatgpt.com/codex/settings/usage
   > - Gemini: `/stats session`

2. 사용자의 자연어 답변에서 각 에이전트별 잔여 비율을 판단해라:
   - 숫자가 있으면 그대로 사용 (예: "60%" → 60%)
   - "넉넉해", "여유 있어", "많이 남았어" → 80%+
   - "반 정도", "절반" → 50%
   - "좀 썼어", "얼마 안 남았어" → 20~30%
   - "거의 다 썼어", "바닥이야" → 5~10%
   - "다 썼어", "소진됨" → 0%
   - 언급 안 한 에이전트 → 변경 없음 (기존 캐시 유지)

3. `queue/.usage_cache`에 JSON으로 저장해라:
   ```bash
   cat > ~/projects/agent-orchestration/queue/.usage_cache << 'EOF'
   {
     "claude": {"remaining_pct": N, "updated": "YYYY-MM-DDTHH:MM:SS"},
     "codex": {"remaining_pct": N, "updated": "YYYY-MM-DDTHH:MM:SS"},
     "gemini": {"remaining_pct": N, "updated": "YYYY-MM-DDTHH:MM:SS"}
   }
   EOF
   ```

4. 임계값 판단 후 모드 제안:
   - gemini <= 20% → `bash ~/projects/agent-orchestration/scripts/orchestrate.sh --mode conserve-gemini`
   - codex <= 20% → `bash ~/projects/agent-orchestration/scripts/orchestrate.sh --mode conserve-codex`
   - gemini <= 20% AND codex <= 20% → `--mode solo`
   - claude <= 20% → 경고만 ("Claude 한도 주의 — 위임 작업 위주로 전환 권장")
   - 전부 50% 이상 → `--mode full` (conserve 모드였다면 해제)

5. 결과를 보여줘라:
   ```
   사용량 업데이트 완료:
   - Claude: N% 남음
   - Codex: N% 남음
   - Gemini: N% 남음
   → 모드: [현재 모드] (변경 있으면 이유 포함)
   ```
