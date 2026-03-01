다음 질문에 대해 조사해줘:

1. 멀티 에이전트 오케스트레이션에서 '작업 특성 기반 에이전트 라우팅' 규칙의 베스트 프랙티스는 무엇인가?
   - 특히: Google 생태계 작업(YouTube, Drive, Docs 등)을 특정 에이전트에 우선 배정하는 패턴
   - 작업 도메인(코드/리서치/미디어/데이터)별로 에이전트를 매칭하는 프레임워크가 있는지

2. 다음 3개 오픈소스 프로젝트를 분석해줘:
   - ComposioHQ/agent-orchestrator: 메타데이터 기반 세션 관리 방식
   - bassimeledath/dispatch: 파일 IPC + 체크리스트 패턴
   - johannesjo/parallel-code: worktree 격리 패턴
   각각의 핵심 아이디어, 우리 시스템(Claude Code + Codex + Gemini 오케스트레이션)에 적용 가능한 부분, 한계점 정리

3. 우리 현재 ROUTING_TABLE.md의 라우팅 규칙에서 빠져있거나 약한 부분은?
   - Google 생태계 작업 라우팅
   - 미디어 처리(이미지/영상/오디오) 라우팅  
   - 데이터 분석 작업 라우팅
   - 외부 API 연동 작업 라우팅

결과는 한국어로, 표 형태 위주로 정리해줘.
