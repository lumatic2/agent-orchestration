다음을 조사하고 한국어로 답변해줘. 표 형태 위주로.

## 질문 1: 오픈소스 프로젝트 분석
다음 3개 GitHub 프로젝트의 핵심 아이디어, 장단점을 정리해줘:
- ComposioHQ/agent-orchestrator: 메타데이터 기반 세션 관리
- bassimeledath/dispatch: 파일 IPC + 체크리스트 패턴
- johannesjo/parallel-code: worktree 격리 패턴

## 질문 2: 작업 특성 기반 에이전트 라우팅 베스트 프랙티스
멀티 에이전트 시스템에서 작업 도메인별로 에이전트를 매칭하는 규칙:
- Google 생태계(YouTube, Drive, Docs) → 어떤 에이전트가 적합한가
- 미디어 처리(이미지/영상/오디오)
- 데이터 분석
- 외부 API 연동

## 질문 3: 현재 우리 시스템의 라우팅 규칙에서 빠진 부분
현재 규칙: 코드→Codex, 리서치→Gemini, 소규모→Claude
빠진 것: Google 생태계, 미디어, 데이터 파이프라인, 외부 서비스 연동 등

각 빠진 영역에 대해 추천 라우팅 규칙을 제안해줘.
