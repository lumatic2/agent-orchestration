# agent-orchestration ROADMAP

## proj 런처 공개 준비

### 독립 레포 분리
- [ ] `proj` 관련 코드만 추출 (proj.zsh, powershell_profile.ps1의 proj 함수)
- [ ] 원클릭 설치 스크립트 작성 (setup.sh / setup.ps1)
- [ ] README 작성: 기능 설명, 스크린샷/GIF, 설치 방법
- [ ] GitHub 레포 생성 및 푸시

### 블로그 글
- [ ] "비개발자가 Claude Code로 20개 프로젝트를 관리하며 만든 런처" 초안
- [ ] 스크린샷 캡처 (proj 메뉴, status, archive, agent 선택 등)
- [ ] 브런치 또는 포트폴리오 블로그에 발행
- [ ] GitHub 레포 링크 연결

## proj 기능 개선
- [x] Windows(PowerShell) / Mac(zsh) 코드 통일
- [x] fzf 기반 메뉴 + 단축키 (ctrl+N/E/R/D)
- [x] 관리 액션 후 메뉴 복귀 (while 루프)
- [x] pin/archive 필드 (ctrl+P, ctrl+X, ctrl+A)
- [x] Esc 단계별 뒤로가기 (agent→worktree→project)
- [x] ctrl+S status 화면 (git/branch/worktree/ROADMAP)
- [x] Windows Terminal proj 프로필 추가
- [x] fzf 후 claude stdin 격리 (Start-Process)
- [ ] Mac에서 테스트 및 호환성 확인
