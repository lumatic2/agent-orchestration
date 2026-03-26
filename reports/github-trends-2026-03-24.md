# GitHub Trends — 2026-03-24

> 수집 기간: 2026-03-17 ~ 2026-03-24 | 즉시적용 29개 | 참고 9개

## 이번 주 동향
Registering notification handlers for server 'notion-personal'. Capabilities: { tools: {} } Server 'notion-personal' has tools but did not declare 'listChanged' capability. Listening anyway for robustness... Scheduling MCP context refresh... Executing MCP context refresh... MCP context refresh complete. 이번 주 오픈소스 트렌드는 범용 AI의 시대를 지나 ‘특화 에이전트 생태계’의 구축으로 무게 중심이 이동하고 있음을 명확히 보여줍니다. 더 이상 하나의 거대 모델에 의존하는 대신, 개발자들은 Claude Code나 Codex 같은 에이전트에 특정 도메인 지식을 주입하는 ‘스킬’을 제작하는 데 집중하고 있습니다. 비즈니스 진단, 앱 스토어 사전 검수, 심지어 족보 연구와 같은 전문 분야를 위한 스킬들이 등장하며 AI를 범용 조수에서 전문 동료로 바꾸고 있습니다. 이러한 특화는 자연스럽게 다중 에이전트 시스템의 부상으로 이어져, 에이전트 간의 통신과 협업을 조율하는 프레임워크가 주목받았습니다. 자율적으로 연구하고 학습하는 ‘Autoresearch’ 프로젝트들의 약진은 스스로 문제를 해결하는 AI를 향한 기대를 보여주며, 이를 관리하기 위한 통합 콘솔과 오케스트레이션 도구의 등장은 생태계의 성숙을 의미합니다. 또한, 로컬 LLM 최적화, 특정 플랫폼 연동, 자동화 봇 제작 등 구체적인 적용 사례들이 동시다발적으로 나타나고 있습니다. 이번 주의 흐름을 한 문장으로 요약하면, 우리는 더 이상 하나의 만능 AI를 만드는 것이 아니라, 각자의 전문성을 가지고 협력하는 ‘AI 작업팀’을 구성하는 시대로 접어들고 있습니다.

## 즉시적용 (29개)
- **danveloper/flash-moe** ★1665 this week
  로컬 LLM 실행 및 최적화
  → 적용 포인트: 온디바이스 AI 모델 성능 최적화 및 활용

- **dontbesilent2025/dbskill** ★1250 this week
  Claude Code용 상업 진단 스킬
  → 적용 포인트: 특정 도메인(비즈니스 진단)을 위한 Claude Code 스킬 개발

- **louislva/claude-peers-mcp** ★943 this week
  Claude Code 에이전트 간 ad-hoc 통신
  → 적용 포인트: 다중 Claude Code 에이전트 간 통신 및 협업 시스템 구축

- **mattprusak/autoresearch-genealogy** ★905 this week
  Claude Code 기반 AI 보조 족보 리서치
  → 적용 포인트: Claude Code를 활용한 전문 분야(족보) 리서치 자동화 및 프롬프트 구조화

- **truongduy2611/app-store-preflight-skills** ★896 this week
  앱 스토어 거부 패턴 스캔 AI 에이전트 스킬
  → 적용 포인트: 특정 배포 프로세스(앱 스토어)를 위한 AI 에이전트 스킬 개발 및 자동화

- **leo-lilinxiao/codex-autoresearch** ★757 this week
  Codex 자율 리서치 및 반복 학습 시스템
  → 적용 포인트: Codex 에이전트의 자율적인 연구 및 검증 워크플로우 구축

- **eze-is/web-access** ★744 this week
  Claude Code의 웹 접근성 스킬
  → 적용 포인트: Claude Code 에이전트의 웹 브라우징 및 데이터 수집 능력 강화

- **dou-jiang/codex-console** ★682 this week
  Codex를 위한 통합 콘솔 및 작업 관리
  → 적용 포인트: Codex 에이전트 작업 모니터링, 배치 처리, 데이터 파이프라인 자동화

- **win4r/ClawTeam-OpenClaw** ★606 this week
  OpenClaw 기반 다중 에이전트 스웜 코디네이션
  → 적용 포인트: OpenClaw를 활용한 다중 에이전트 시스템 및 협업 메커니즘 연구

- **olelehmann100kMRR/autoresearch-skill** ★519 this week
  자율 리서치 AI 에이전트 스킬
  → 적용 포인트: 에이전트의 자율적인 정보 탐색 및 리서치 스킬 개발

- **Shpigford/chops** ★516 this week
  다중 AI 에이전트 스킬 관리 macOS 앱
  → 적용 포인트: 여러 AI 에이전트(Claude Code, Codex 등)의 스킬 통합 및 관리 UI/UX 참고

- **griffinmartin/opencode-claude-auth** ★387 this week
  Claude Code 기존 인증을 활용하는 OpenCode 플러그인
  → 적용 포인트: Claude Code 연동 시 인증 간소화 및 플러그인 개발

- **zarazhangrui/codebase-to-course** ★368 this week
  코드베이스를 HTML 교육 코스로 변환하는 Claude Code 스킬
  → 적용 포인트: Claude Code를 활용한 코드 분석 기반 교육 콘텐츠 자동 생성

- **creationix/rx** ★327 this week
  CLI 데이터 처리 및 인코딩/디코딩 도구
  → 적용 포인트: CLI 기반 데이터 유틸리티 개발 및 워크플로우 자동화

- **slavingia/skills** ★315 this week
  Sahil Lavingia의 철학 기반 Claude Code 스킬
  → 적용 포인트: 특정 원칙/철학을 AI 에이전트 스킬로 구현하는 방법론

- **EurekaClaw/EurekaClaw** ★306 this week
  새로운 에이전트 시스템의 공식 레포지토리
  → 적용 포인트: 에이전트 시스템 구조 및 작동 방식 연구

- **K-Dense-AI/k-dense-byok** ★295 this week
  Claude Scientific Skills 기반 AI 공동 과학자
  → 적용 포인트: Claude Scientific Skills를 활용한 전문 과학 분야 AI 에이전트 개발

- **joeseesun/markdown-proxy** ★274 this week
  URL 콘텐츠를 마크다운으로 추출하는 프록시 서비스
  → 적용 포인트: AI 에이전트의 웹 콘텐츠 수집 및 정제 자동화

- **ayush-that/jiang-clips** ★260 this week
  YouTube 영상의 자동 클립 생성 파이프라인
  → 적용 포인트: 동영상 콘텐츠 자동 편집 및 워크플로우 자동화 파이프라인 구축

- **lyddape595/wplace-bot-2026** ★255 this week
  Windows 자동화 봇 및 작업 완료 도구
  → 적용 포인트: Windows 환경 작업 자동화, 봇 개발, 캡차 해결 기술

- **5uNRiSEBr7059Oken/uniswap-arbitrage-bot-2026** ★255 this week
  Uniswap V3 아비트라지 거래 봇
  → 적용 포인트: 특정 시장(DeFi) 아비트라지 거래 자동화 봇 개발

- **alvinunreal/awesome-autoresearch** ★233 this week
  자율 개선 루프, 리서치 에이전트 목록
  → 적용 포인트: AI 에이전트의 자율 학습 및 리서치 시스템 개발 아이디어 참고

- **zengwenliang416/ppt-agent** ★231 this week
  프레젠테이션 자동 생성 에이전트
  → 적용 포인트: 프레젠테이션 콘텐츠 자동 생성 AI 에이전트 개발

- **SethGammon/Citadel** ★220 this week
  Claude Code 에이전트 오케스트레이션 프레임워크
  → 적용 포인트: Claude Code 기반 다중 에이전트 오케스트레이션 및 협업 시스템 아키텍처

- **seabra98/Polymarket-Kalshi-Arbitrage-Bot** ★216 this week
  예측 시장 아비트라지 거래 봇
  → 적용 포인트: 예측 시장(Polymarket, Kalshi) 아비트라지 거래 자동화 봇 개발

- **second-state/kitten_tts_rs** ★215 this week
  Rust 기반 TTS CLI 및 API 서버
  → 적용 포인트: CLI 기반 AI 음성 합성 도구 개발 및 통합

- **meodai/skill.color-expert** ★214 this week
  색채 과학 전문 AI 에이전트 스킬
  → 적용 포인트: 특정 전문 지식(색채 과학)을 AI 에이전트 스킬로 구현

- **mnfst/awesome-free-llm-apis** ★213 this week
  무료 LLM API 목록
  → 적용 포인트: LLM 활용을 위한 API 선택 및 연동 전략 수립

- **komunite/kalfa** ★211 this week
  Claude Code용 터키어 전문 운영 시스템 (다중 에이전트, 스킬)
  → 적용 포인트: Claude Code 기반 다중 에이전트 시스템, 스킬 및 명령어 체계 설계

## 참고 (9개)
- **lxf746/any-auto-register** ★1029
  일반적인 자동 등록 기능

- **wong2/weixin-agent-sdk** ★745
  WeChat 에이전트 개발 SDK

- **ghostty-org/ghostling** ★766
  최소한의 터미널 에뮬레이터

- **m1heng/claude-plugin-weixin** ★509
  Claude Code WeChat 플러그인

- **fastclaw-ai/weclaw** ★454
  WeChat ClawBot을 통한 에이전트 연결

- **vercel-labs/emulate** ★399
  CI를 위한 로컬 API 에뮬레이션

- **rohitg00/ai-engineering-from-scratch** ★393
  AI 엔지니어링 학습 자료

- **mshumer/unslop** ★324
  코드 품질 개선 및 리팩토링

- **0din-ai/ai-scanner** ★304
  AI 모델 안전성 스캐너

## 스킵
math-inc/OpenGauss, BryanLunduke/DoesItAgeVerify, openyak/desktop, ccbkkb/MicroWARP, gnekt/My-Brain-Is-Full-Crew, xiaolajiaoyyds/regplatformm, bramcohen/manyana, eggricesoy/filmkit, avinash201199/DSA-KIT, Gustavo1900/bevy-atmosphere, dashersw/gea, kulikov0/whitelist-bypass
