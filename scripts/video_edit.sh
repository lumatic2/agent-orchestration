#!/bin/bash
# video_edit.sh — FFmpeg 기반 영상 편집 자동화
# 사용법: bash video_edit.sh [명령] [옵션]
#
# 명령:
#   trim    INPUT START END OUTPUT        # 구간 자르기 (예: 00:00:10 00:01:30)
#   merge   OUTPUT INPUT1 INPUT2 ...      # 영상 합치기
#   resize  INPUT OUTPUT [1080p|720p|4k]  # 해상도 변환
#   gif     INPUT OUTPUT [START] [END]    # GIF 변환
#   thumb   INPUT OUTPUT [TIME]           # 썸네일 추출 (기본: 00:00:03)
#   audio   INPUT OUTPUT AUDIO_FILE       # 배경음악 교체/추가
#   speed   INPUT OUTPUT [배속: 0.5|2.0]  # 배속 조절
#   caption "텍스트" INPUT OUTPUT         # 자막 오버레이 (간단)
#   ai      "요청"                        # 자연어로 편집 방법 물어보기

CMD="${1:-}"
FFMPEG=$(which ffmpeg 2>/dev/null)

if [ -z "$FFMPEG" ]; then
  echo "❌ FFmpeg 미설치"
  echo "   설치: brew install ffmpeg"
  echo ""
  echo "💡 FFmpeg 없이도 'ai' 명령으로 편집 방법 확인 가능:"
  echo "   bash video_edit.sh ai \"영상에 자막 넣는 법\""
  # Allow 'ai' command without ffmpeg
  [ "$CMD" != "ai" ] && exit 1
fi

case "$CMD" in
  trim)
    INPUT="$2" START="$3" END="$4" OUTPUT="$5"
    [ -z "$OUTPUT" ] && echo "사용법: trim INPUT START END OUTPUT" && exit 1
    echo "✂️  트리밍: $START → $END"
    ffmpeg -i "$INPUT" -ss "$START" -to "$END" -c copy "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  merge)
    OUTPUT="$2"; shift 2
    INPUTS=("$@")
    [ ${#INPUTS[@]} -lt 2 ] && echo "사용법: merge OUTPUT INPUT1 INPUT2 ..." && exit 1

    # Create concat list
    TMP=$(mktemp /tmp/ffmpeg_list_XXXX.txt)
    for f in "${INPUTS[@]}"; do echo "file '$f'" >> "$TMP"; done

    echo "🔗 합치기: ${#INPUTS[@]}개 파일"
    ffmpeg -f concat -safe 0 -i "$TMP" -c copy "$OUTPUT" -y
    rm "$TMP"
    echo "✅ 저장: $OUTPUT"
    ;;

  resize)
    INPUT="$2" OUTPUT="$3" SIZE="${4:-1080p}"
    case "$SIZE" in
      4k|2160p)  SCALE="3840:2160" ;;
      1080p)     SCALE="1920:1080" ;;
      720p)      SCALE="1280:720"  ;;
      480p)      SCALE="854:480"   ;;
      *)         SCALE="$SIZE"     ;;  # 직접 입력: 1280:720
    esac
    echo "📐 해상도 변환: $SIZE ($SCALE)"
    ffmpeg -i "$INPUT" -vf "scale=$SCALE" -c:a copy "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  gif)
    INPUT="$2" OUTPUT="$3" START="${4:-00:00:00}" END="${5:-00:00:05}"
    echo "🎞️  GIF 변환: $START → $END"
    ffmpeg -i "$INPUT" -ss "$START" -to "$END" \
      -vf "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
      "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  thumb)
    INPUT="$2" OUTPUT="$3" TIME="${4:-00:00:03}"
    echo "🖼️  썸네일 추출: $TIME"
    ffmpeg -i "$INPUT" -ss "$TIME" -frames:v 1 "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  audio)
    INPUT="$2" OUTPUT="$3" AUDIO="$4"
    [ -z "$AUDIO" ] && echo "사용법: audio INPUT OUTPUT AUDIO_FILE" && exit 1
    echo "🎵 배경음악 교체"
    DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT")
    ffmpeg -i "$INPUT" -i "$AUDIO" \
      -map 0:v -map 1:a \
      -c:v copy -c:a aac \
      -shortest "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  speed)
    INPUT="$2" OUTPUT="$3" RATE="${4:-2.0}"
    echo "⏩ 배속 조절: ${RATE}x"
    VRATE=$(python3 -c "print(f'{1/$RATE:.4f}')")
    # atempo supports 0.5~2.0 only — chain filters for values outside range
    ATEMPO=$(python3 -c "
r = float('$RATE')
filters = []
while r > 2.0:
    filters.append('atempo=2.0')
    r /= 2.0
while r < 0.5:
    filters.append('atempo=0.5')
    r /= 0.5
filters.append(f'atempo={r:.4f}')
print(','.join(filters))
")
    ffmpeg -i "$INPUT" \
      -filter:v "setpts=${VRATE}*PTS" \
      -filter:a "$ATEMPO" \
      "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  caption)
    TEXT="$2" INPUT="$3" OUTPUT="$4"
    [ -z "$OUTPUT" ] && echo "사용법: caption \"텍스트\" INPUT OUTPUT" && exit 1
    echo "📝 자막 추가"
    ffmpeg -i "$INPUT" \
      -vf "drawtext=text='$TEXT':fontsize=48:fontcolor=white:x=(w-tw)/2:y=h-th-40:box=1:boxcolor=black@0.6:boxborderw=10" \
      -c:a copy "$OUTPUT" -y
    echo "✅ 저장: $OUTPUT"
    ;;

  ai)
    QUESTION="${2:-}"
    [ -z "$QUESTION" ] && echo "사용법: bash video_edit.sh ai \"영상 편집 질문\"" && exit 1

    PROMPT="당신은 FFmpeg 전문가입니다. 다음 영상 편집 요청에 대해 정확한 FFmpeg 명령어와 설명을 제공하세요.

요청: $QUESTION

출력 형식:
## FFmpeg 명령어
\`\`\`bash
ffmpeg [명령어]
\`\`\`

## 설명
[각 옵션 설명]

## 주의사항
[주의할 점]"

    echo "🎬 영상 편집 AI..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    gemini --yolo -m gemini-2.5-flash -p "$PROMPT"
    ;;

  *)
    echo "video_edit.sh 사용법:"
    echo "  trim    INPUT START END OUTPUT        예: trim input.mp4 00:00:10 00:01:30 out.mp4"
    echo "  merge   OUTPUT INPUT1 INPUT2 ...      예: merge final.mp4 a.mp4 b.mp4 c.mp4"
    echo "  resize  INPUT OUTPUT [1080p|720p|4k]"
    echo "  gif     INPUT OUTPUT [START] [END]"
    echo "  thumb   INPUT OUTPUT [시간]"
    echo "  audio   INPUT OUTPUT AUDIO_FILE"
    echo "  speed   INPUT OUTPUT [배속]            예: speed in.mp4 out.mp4 2.0"
    echo "  caption \"텍스트\" INPUT OUTPUT"
    echo "  ai      \"자연어 질문\"                 FFmpeg 미설치시도 사용 가능"
    ;;
esac
