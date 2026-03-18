#!/bin/bash
# image_agent.sh — 이미지 생성 프롬프트 에이전트
# 사용법: bash image_agent.sh "요청" [--type 로고|캐릭터|마케팅|콘셉트] [--ratio 1:1|16:9|3:4]
#
# Ollama에 SD 모델이 설치되면 자동으로 직접 생성으로 전환

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PERSONA_FILE="$REPO_DIR/agents/image_persona.md"

REQUEST=""
TYPE="일반"
RATIO="1:1"

ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  case "${ARGS[$i]}" in
    --type)  i=$((i+1)); TYPE="${ARGS[$i]:-일반}" ;;
    --ratio) i=$((i+1)); RATIO="${ARGS[$i]:-1:1}" ;;
    --*)     ;;
    *)       [ -z "$REQUEST" ] && REQUEST="${ARGS[$i]}" ;;
  esac
  i=$((i+1))
done

if [ -z "$REQUEST" ]; then
  echo "사용법: bash image_agent.sh \"요청\" [--type 로고|캐릭터|마케팅|콘셉트] [--ratio 1:1|16:9|3:4]"
  echo ""
  echo "예시:"
  echo "  bash image_agent.sh \"AI 스타트업 로고, 파란색 계열\" --type 로고"
  echo "  bash image_agent.sh \"미래 도시 콘셉트 아트\" --type 콘셉트 --ratio 16:9"
  exit 1
fi

PERSONA=$(cat "$PERSONA_FILE" 2>/dev/null || echo "이미지 프롬프트 전문가로서 답변하세요.")

PROMPT="$PERSONA

## 요청
- 내용: $REQUEST
- 유형: $TYPE
- 비율: $RATIO

위 형식에 맞게 최적화된 프롬프트를 생성해주세요."

# Check if Ollama SD model available
SD_MODEL=$(ollama list 2>/dev/null | grep -iE "sdxl|stable|flux" | awk '{print $1}' | head -1)

echo "🎨 이미지 프롬프트 생성 중..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

gemini --yolo -m gemini-2.5-flash -p "$PROMPT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$SD_MODEL" ]; then
  echo "✅ Ollama SD 모델 감지: $SD_MODEL — 직접 생성 가능"
  echo "   bash image_agent.sh \"$REQUEST\" --generate"
else
  echo "📋 사용법: DALL-E 3 프롬프트를 ChatGPT (chatgpt.com)에 복붙하세요"
  echo "💡 Stable Diffusion 설치: ollama pull stable-diffusion (모델 ~4GB)"
fi
