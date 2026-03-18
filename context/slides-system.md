# 슬라이드 생성 시스템

**상태**: 실사용 검증 완료. AP-01~09 누적.
**핵심 파일**: `~/projects/agent-orchestration/slides_config.yaml`
**렌더 파이프라인**: HTML → `render-slides.sh` → Playwright → PDF → ~/Desktop/

## Anti-Patterns (AP) 현황

| AP | 원인 | 수정 |
|---|---|---|
| AP-01 | flex column 자식 height:100% | flex:1; min-height:0 |
| AP-02 | 고정 height wrapper | flex:1; min-height:0 |
| AP-03 | justify-content:center + flex:1 공존 | Pattern B 전환 |
| AP-04 | min-height/height:100vh | height:720px 고정 |
| AP-05 | 좁은 컬럼 긴 텍스트 | font-size 11px 이하 |
| AP-06 | 바 차트 width 임의 설정 | value/max*100% 공식 |
| AP-07 | 컬러 오버라이드 시 파스텔 | 원색 유지 |
| AP-08 | Pattern C 패널 내부 flex centering 미적용 | justify-content:center 필수 |
| AP-09 | 사례박스 absolute bottom 고정 | flex 흐름 안에 margin-top:20px |

## 슬라이드 파이프라인
```
gen-brief.sh → orchestrate.sh gemini (리서치)
→ orchestrate.sh codex (HTML 생성)
→ render-slides.sh (Playwright → PDF)
→ scp (기기 전송)
→ telegram-send.sh
```

```bash
bash scripts/slides-bridge.sh "커피" 10 local      # 로컬 저장
bash scripts/slides-bridge.sh "커피" 10 telegram   # 텔레그램 전송
```

**검증된 주제**: 개vs고양이, 미쉐린서울, 치앙마이골프, 스포츠난이도, AI에이전트B2BSaaS
