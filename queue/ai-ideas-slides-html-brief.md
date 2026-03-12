# Task: AI 아이디어 슬라이드 HTML 생성

## Goal
아래 콘텐츠를 `~/Desktop/agent-orchestration/slides_config.yaml`의 디자인 시스템에 맞게
HTML 슬라이드로 생성한다.
출력 파일: `C:/Users/1/Desktop/ai_ideas_slides.html`

## Design System 참조
- `~/Desktop/agent-orchestration/slides_config.yaml` 전체 반드시 숙독 후 생성
- 색상: slides_config.yaml `colors` 섹션 그대로 사용 (포트폴리오 블루 시스템)
- 폰트: Inter (Google Fonts CDN)
- 슬라이드 크기: 1280×720px, `height:720px` 고정 (min-height 금지)
- `@page { size: 1280px 720px; margin: 0; }` 반드시 head에 포함
- 이모지 금지, SVG 아이콘 사용 (Lucide stroke 기반)
- word-break: keep-all 전역 CSS 필수 (AP-13)

## 슬라이드 구성 (9장)

### S1: title_left_panel (Pattern C)
- 좌 패널(35%): accent blue (#2563EB) 배경
  - 상단 소배지: "TEAM DISCUSSION"
  - 메인 타이틀: "AI 기반\n창업 아이디어 3선"
  - 서브: "문제 명확성 · AI 필요성 · MVP 가능성 · 시장 설명"
- 우 패널(65%): 흰 배경
  - 아이콘 리스트 3개:
    - 📋 → SVG(문서 아이콘): "01 AI 회의 결정문서 생성기"
    - 💰 → SVG(차트 아이콘): "02 AI 개인 재무·투자 코파일럿"
    - 👤 → SVG(사람 아이콘): "03 AI 포트폴리오 생성기"
  - 하단 우: "2026"

### S2: icon_card_grid (Pattern A, 4카드 → 4열)
- 배지: "EVALUATION CRITERIA"
- 제목: "좋은 팀 토론 아이디어의 4가지 기준"
- 4개 카드:
  1. SVG(타겟) / 명확한 문제 / 누구나 공감하는 실제 페인 포인트
  2. SVG(CPU) / AI가 핵심 가치 / AI 없이는 불가능하거나 현저히 열등
  3. SVG(로켓) / MVP 가능성 / 1주 내 프로토타입 제작 가능한 구조
  4. SVG(말풍선) / 시장 설명 용이 / 누구에게나 30초 안에 설명 가능

### S3: magazine_split (Pattern C, 60/40 비대칭)
- 좌(60%): accent blue 배경
  - 오버라인: "IDEA 01"
  - 대제목: "AI 회의\n결정문서 생성기"
  - 설명: "대화는 많지만 결정이 남지 않는다"
- 우(40%): 흰 배경
  - 문제 항목들 (numbered list 스타일):
    - 01 / "그때 뭐 결정했지?" 반복
    - 02 / 책임자·마감기한 불명확
    - 03 / 논쟁 이유가 기록에 미기록
  - 하단 타겟 마켓: "대학 팀플 · 스타트업 · 기업"

### S4: flow_arrows (Pattern B, 4단계 흐름)
- 배지: "IDEA 01 — HOW IT WORKS"
- 제목: "음성 입력에서 결정문서까지"
- 4단계 flow:
  - 🎤→SVG(마이크): "음성 입력" / "회의 녹음\n파일 업로드"
  - 📝→SVG(파일): "STT 변환" / "Speech-to-Text\n텍스트화"
  - 🧠→SVG(뇌): "LLM 분석" / "핵심 추출\n구조화"
  - 📄→SVG(문서): "결정문서" / "Decision·Owner\nDeadline 자동 생성"

### S5: right_accent_panel (Pattern C)
- 좌 영역(72%): 흰 배경
  - 배지: "IDEA 02"
  - 제목: "AI 개인 재무·투자 코파일럿"
  - 부제: "데이터는 있다. 해석이 없을 뿐이다."
  - 기능 리스트 (아이콘 + 텍스트):
    - 소비 패턴 분석
    - 절세 전략 제안
    - 투자 포트폴리오 평가
    - 리스크 경고
- 우 패널(28%): accent blue 배경
  - 히어로 숫자: "2.3x"
  - 서브: "평균 대비\n식비 초과"
  - 구분선
  - 보조 수치: "48%" / "고정비 비율"
  - 보조 수치: "20%" / "저축률"

### S6: asymmetric_panel (Pattern B)
- 배지: "IDEA 03"
- 제목: "AI 포트폴리오 생성기"
- 부제: "대화하면 완성된다"
- 좌(40%): 입력 → 출력 2열 비교
  - 입력: "이력 & 경험 입력"
  - 출력: "완성된 포트폴리오 웹사이트"
- 우(60%): 번호 리스트
  - 01 / 개인 소개 / 핵심 강점 3줄 요약
  - 02 / 프로젝트 사례 / 문제→역할→결과 STAR 구조
  - 03 / 문제 해결 방식 / 사고 프로세스 시각화
  - 04 / 기술 스택
  - 05 / 정량적 결과 / 수치화된 성과

### S7: stat_trio (Pattern A)
- 배지: "MARKET OPPORTUNITY"
- 제목: "세 아이디어의 공통점"
- 3개 stat:
  - "1주" / "내 MVP 가능" / "프로토타입 제작 기간"
  - "4/4" / "평가 기준 충족" / "모든 창업 기준 통과"
  - "3개" / "타겟 시장" / "각 아이디어당 명확한 시장"

### S8: comparison_table (Pattern A)
- 배지: "COMPARISON"
- 제목: "3개 아이디어 팀 토론 적합성 비교"
- 테이블:
  - 헤더: 평가 기준 / 회의 결정문서 / 재무 코파일럿 / 포트폴리오 생성기
  - 행 1: 문제 명확성 / ★★★★★ / ★★★★★ / ★★★★☆
  - 행 2: AI 필요성 / ★★★★★ / ★★★★★ / ★★★★☆
  - 행 3: MVP 가능성 / ★★★★★ / ★★★☆☆ / ★★★★★
  - 행 4: 시장 설명 / ★★★★★ / ★★★★☆ / ★★★★★
  - 행 5: 추천 대상 / 팀플·기업 / 개인·투자자 / 학생·취준생
- 별점은 colored spans으로 표현 (accent blue for filled, light gray for empty)

### S9: three_split_verdict (Pattern C, 3분할)
- 좌(30%): accent blue 배경
  - 제목: "지금 바로\n시작하려면"
  - 리스트:
    - STT API (Whisper)
    - LLM API (Claude/GPT)
    - 템플릿 엔진
- 중앙(40%): 진한 navy (#1E3A8A) 배경
  - 대형 문구: "세 아이디어\n모두\n1주 MVP"
  - 서브: "기술 장벽 없음"
- 우(30%): 흰 배경
  - 제목: "팀 토론 체크리스트"
  - 체크리스트:
    - ✓ 문제 공감 여부
    - ✓ AI 없이 가능한가?
    - ✓ 데모 가능한가?
    - ✓ 누가 돈 내는가?

## 필수 CSS 규칙 (AP 체크리스트)
- AP-04: `.slide { width:1280px; height:720px; overflow:hidden; position:relative; }`
- AP-08: Pattern C 모든 패널에 `display:flex; flex-direction:column; justify-content:center`
- AP-11: card-grid에 `flex:1; min-height:0; align-content:stretch`
- AP-12: 배지에 `display:inline-block; width:fit-content`
- AP-13: h1~h3, p, li 전체에 `word-break:keep-all; overflow-wrap:break-word`

## 완료 기준
1. `C:/Users/1/Desktop/ai_ideas_slides.html` 생성
2. CHK-01~08 자가검증 통과
3. 슬라이드 9장 모두 포함
