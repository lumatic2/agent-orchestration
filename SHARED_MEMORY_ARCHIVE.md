# SHARED_MEMORY Archive

> 2026-03-11 정리 시 제거된 섹션 보관
> 원본 위치: `~/projects/agent-orchestration/SHARED_MEMORY.md`

---

## Active Projects (archived 2026-03-11)

- **MOD**: 54-card thinking framework deck. v1=thought frameworks, v2=knowledge/memory, v3=agents/physical AI.
- **Planby Pilot**: Business Strategy & Finance. OKR-ROI-Decision structures.
  - **현재 상태**: 4주 계획 전체 완료. Architecture v1.0 + 4개 운영 매뉴얼 + 대표용 보고서 생성됨.
  - **세션 인수인계 페이지**: https://www.notion.so/31a85046ff5581b58b6cf4a171319da1
  - **Architecture v1.0**: 31a85046-ff55-816e-8414-f25e60cbdaed
  - **대표용 보고서**: 31a85046-ff55-81bb-a57c-cb77428be930
  - **핵심 발견**:
    - P_parallel 실데이터: 최대 5건 (2025-09~11). Base 3건은 보수적으로 합리적.
    - 계약금 실데이터: Won 평균 ~4,900만 (PoC 포함). 대형 커스텀 1억+은 2건.
    - 재발주율: **9건 중 6건(66.7%)이 기존 고객** ✅ (DIPS 신청서 직접 명시, 2026-02-13)
    - 재발주 사례: 루시드프로모 2,080만 → 1.52억 (7.3x). PoC First 구조 증거.
    - **특허 4건 등록 확인** ✅: 10-2759071, 10-2776139, 10-2776140, 10-2797720 (모두 2025년 AI 이미지 생성 관련)
    - TIPS 협약: 정부지원금 15억 (2024~2027). 2026년 5억 입금 예정 (2026-03-31).
    - 투자: 500 Global 1.5억 + 카이스트창투 3.5억 = VC 5억. Series A 50~100억 미체결.
    - 현금: ~1.97억 (2026-03-01 재무제표 기준). TIPS 5억 후 ~6.97억. 런웨이 약 8개월.
    - 자본잠식 96%. Series A 즉시 착수 필요.
    - 기술기여도 의무: 2026년 45.76% (TIPS R&D 매출 기술료 납부 의무).
    - **⚠️ 매출 수정**: 공식 재무제표(세무사 2026-03-04) 기준 2025 서비스매출=2.89억. 이전 "7.8억"은 출처 불명으로 폐기.
    - 실적 트래킹 (공식): 2023=2,510만 / 2024=4,412만 / 2025=2.89억 (서비스매출). 국고보조금 별도(2025: 3.32억)
  - **미완성 항목**: Series A 타임라인, TIPS R&D 마일스톤 상세
  - **🟡 Win Rate 추정**: 55~65% (Won ~12건 / Active ~7건 / Lost ~7건 추정). B2B SaaS 평균 25~35% 상회 — 니치 특화. ⚠️ Lost 정확 건수는 고객사 DB Archived 뷰 확인 필요.
  - **🟡 장기차입금 만기 추정**: IBK 4.5억 (연 4.2%, 연 5천만 상환). 운전자금=매년 갱신(2026년 시점 주의), 시설자금=2027~2030년. 완전상환 12년. ⚠️ 대출계약서 원본 확인 필요.
  - **🟡 MRR 추정**: 현재 200~350만원/월. 연간 SaaS 2,000~3,000만원 = 서비스매출의 7~10%. 나머지 B2B 커스텀.
  - **N_maint 실수 (2026-03-05 조회)**: 최소 3곳 확인 — HK건축(Pro Yearly 288만/년), 지안건축설계(서면계약완료), 한국공항공사(Pro Monthly ~33만/월, 3개월 결제 완료). 5건 가정 → 3건으로 하향 조정 고려. 삼성E&A 유지보수 계약 별도 확인 필요.
  - **현재 활성 파이프라인 (2026-03-04 월간 전체 회의 기준)**: 넷폼알앤디 7,000만(계약직전), 위미코 PoC 1,500만+본계약 1.02억, 현대일렉트릭(BIM), 삼성전자(공장AI), 삼성물산(리모델링), LG전자(OI)
  - **PLAD 가격 모델**: Starter 9.9만/월(마진 60%), Pro 29.9만/월(마진 47%)
  - **⚠️ notion_db.py 주의**: replace-content를 자식 페이지 있는 페이지에 쓰면 자식 페이지 아카이브됨.

---

## Recent Decisions (archived 2026-03-11)

- **2026-03-06**: Notion 라우팅 재설계. Gemini에 Notion MCP 연결 완료. 조사+저장 원스톱 파이프라인 활성화. 규칙: 조사+콘텐츠→Notion=Gemini, DB설계·판단=Claude, AI없는 저장=notion_db.py. ROUTING_TABLE + adapters/gemini.md 업데이트.
- **2026-03-05**: knowledge 8개 파일 완성: tax_core, tax_incentives, vat, inheritance_gift_tax, valuation_formulas, audit_standards, ifrs_key, commercial_law_company. 15개 에이전트 전원 knowledge 매핑 완료
- **2026-03-05**: chain.sh 실전 검증 완료: expert:ifrs_advisory→tax 2단계 체인, K-IFRS 1020/1012 + 조특법10조 복합 분석.
- **2026-03-05**: 전문가 에이전트 실무 직무 기반 재편: audit/deal_advisory/valuation/wealth_tax/tax_investigation/ifrs_advisory/international_tax/forensic 8개 추가.
- **2026-03-05**: orchestration upgrade: --cost/--clean 추가, kicpa_agent.sh + law_agent.sh 신규, sync.sh notion_pages.conf 배포, 큐 52개 아카이브
- **2026-03-05**: connection layer 구현 완료: save_to_notion.sh + memory_update.sh 추가
- **2026-02-27**: E2E orchestration test passed. Gemini researched → Codex generated code → Claude verified. Full pipeline working. Note: Gemini `--sandbox` removed (requires Docker).

---

## 실전 사례: POSCO 제안서 (archived 2026-03-11, 원본 2026-03-06)

### MCP 작업은 위임 불가 — 직접 실행 원칙
Notion/Slack 등 MCP 도구가 필요한 작업은 Codex/Gemini에 위임 불가 (MCP 접근 권한 없음).
위임 결정 전 체크: "이 작업에 MCP가 필요한가?" → YES면 Claude 직접 실행.

### Notion API 실전 한계
- 블록 100개/요청 한도 → 초과 시 400 에러 → `append_paragraphs`에 chunk_size=100 청킹 적용
- `notion_db.py` 버그 수정 완료: `_looks_like_markdown` 루프 내 early return 오류

### 제안서 AI 지원 패턴 (비즈니스)
1. **익명화**: 고객사명 → "도메인 전문사"
2. **현학적 표현 3계층**: 제목(추상 개념어) / 도표(기술 용어 RAG·Embedding) / 본문(평이한 언어)
3. **수혜자 중심 리프레이밍**: "타사 납품 사례" 뉘앙스 → "귀사 전용 구조" 프레이밍

### 긴 세션 컨텍스트 관리
- `/tmp/` 파일을 버전별 중간 저장소로 활용
- 컨텍스트 압축 발동 전 SHARED_MEMORY 업데이트가 연속성 핵심
