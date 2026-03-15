# Law Automation — 법령 자동 업데이트 파이프라인

**상태**: 파이프라인 완성, M1 배포 및 법제처 API 승인 대기 중
**마지막 업데이트**: 2026-03-15

---

## 핵심 파일

| 파일 | 위치 (Windows) | 역할 |
|---|---|---|
| `pdf-to-vault.py` | `~/Desktop/` | PDF → Markdown 변환 + vault 저장 |
| `law-check.py` | `~/Desktop/` | 법제처 API 버전 비교 + 자동 다운로드 |
| `law_registry.yaml` | `~/Desktop/` | 36개 법령 추적 목록 (ls_id, current_no, current_date) |
| `com.luma2.law-check.plist` | `~/Desktop/` | M1 launchd 설정 (매주 일요일 09:00) |

M1 배포 경로: `~/Desktop/` (3파일) + `~/Library/LaunchAgents/` (plist)

---

## M1 배포 명령어 (API 승인 전 미리 가능)

```bash
scp "C:/Users/1/Desktop/law-check.py" m1:~/Desktop/
scp "C:/Users/1/Desktop/pdf-to-vault.py" m1:~/Desktop/
scp "C:/Users/1/Desktop/law_registry.yaml" m1:~/Desktop/
scp "C:/Users/1/Desktop/com.luma2.law-check.plist" "m1:~/Library/LaunchAgents/"
ssh m1 "launchctl load ~/Library/LaunchAgents/com.luma2.law-check.plist"
ssh m1 "launchctl list | grep law-check"
```

---

## 법제처 API 승인 후 작업

1. 승인 확인: https://open.law.go.kr/LSO/openApi/cuAskList.do
2. OC값을 M1 `.env`에 추가:
   ```bash
   ssh m1 "echo 'LAW_API_OC=<OC값>' >> ~/Desktop/content-automation/.env"
   ```
3. ls_id 자동 탐색 (최초 1회):
   ```bash
   ssh m1 "python3 ~/Desktop/law-check.py --discover"
   ```
4. `law_registry.yaml`을 M1 → Windows로 동기화 (ls_id 채워진 버전):
   ```bash
   scp m1:~/Desktop/law_registry.yaml "C:/Users/1/Desktop/law_registry.yaml"
   ```

---

## 자동 업데이트 흐름 (M1 기준)

```
launchd 매주 일요일 09:00
  → law-check.py (OS 자동감지 → M1 경로)
    → 법제처 API 조회 (36개 법령)
    → 개정 감지 시: PDF 다운로드 → ~/Desktop/pdf-input/
    → pdf-to-vault.py 호출 (LOCAL_VAULT_PATH 설정됨)
      → pymupdf 텍스트 추출
      → 법령 모드 (Gemini 스킵): 파일명에 (법률)/(대통령령) 포함
      → ~/vault/10-knowledge/{domain}/ 직접 저장
  → law_registry.yaml 버전 업데이트
```

---

## law_registry.yaml 구조 (36개 법령)

| 도메인 | 법령/시행령 수 |
|---|---|
| tax | 법인세·소득세·부가가치세·조세특례·국세기본·상속증여·국제조세 (각 법+령) = 14 |
| legal | 상법·민법·근로기준·공정거래·개인정보·최저임금·산업안전 (법+령) = 12 |
| finance | 자본시장법 (법+령) = 2 |
| medical | 의료법·응급의료·국민건강보험 (각 법+령) = 6 |
| accounting | 외부감사법 (법+령) = 2 |

- `ls_id`: null → API 승인 후 `--discover`로 자동 채워짐
- `.bak` 파일 자동 생성 (save 전 백업)

---

## pdf-to-vault.py 핵심 설계

- **법령 모드**: 파일명에 `(법률)`, `(대통령령)`, `(부령)`, `시행령`, `시행규칙` 포함 시 Gemini 스킵
- **도메인 분류기**: filename_rules 우선 → content_rules 폴백 (앞 5,000자)
- **LOCAL_VAULT_PATH 환경변수**: 설정 시 SCP 대신 로컬 vault에 직접 저장 (M1 네이티브)
- **Gemini CLI**: `gemini.cmd --yolo -m gemini-2.5-flash`, 입력 80,000자 제한

### 도메인 분류기 — 주의 패턴 (이전에 오분류된 케이스)
- `accounting` 먼저, `tax` 나중 (K-IFRS에 법인세 언급 많음)
- `investment`에 `기업가치_제고`, `공정가치`, `투자자산` 포함 (제고→accounting 오분류 방지)
- `strategy`에 `mna_` 포함 (M&A 가이드북 파일명 패턴)
- `finance`에서 `공시` 제거, `기업공시`만 유지 (특수관계자_공시 → finance 오분류 방지)
- `investment`에서 `벤처투자` → `벤처투자자산`으로 수정 (조인트벤처투자 오분류 방지)

---

## Knowledge Vault 현황 (2026-03-15 기준)

| 도메인 | 파일 수 | 상태 |
|---|---|---|
| accounting | ~60 | ✅ 충분 (K-IFRS 전 기준서 + K-GAAP 31챕터) |
| tax | ~21 | ✅ 충분 (7대 세법 법+령 완비) |
| legal | ~14 | ✅ 충분 (핵심 법령 완비) |
| finance | ~14 | ✅ 충분 |
| medical | 7 | 🔶 법령만, 임상 지식 없음 |
| strategy | 5 | 🔶 실무 가이드 추가 여지 있음 |
| economics | 2 | 🔴 BOK 용어집 1개뿐 |
| investment | **3** | 🔴 최우선 보강 대상 |

### investment 보강 후보 (미수집)
- KVCA 벤처투자 실무 가이드 (한국벤처캐피탈협회)
- 금융감독원 기업공개(IPO) 실무 안내
- 중소벤처기업부 투자심사 기준
- VC 투자계약서 표준 (KVenture)
- 비상장주식 가치평가 실무 (삼일PwC, EY한영)

---

## 20-experts 페르소나 현황 (20개)

페르소나 파일들이 이번에 추가된 법령 원문 파일을 명시적으로 참조하지 않음.
추후 페르소나 파일 내 `knowledge_refs` 또는 참조 링크 추가 필요.

| 분야 | 파일 |
|---|---|
| Tax (4) | tax_investigation, international_tax, wealth_tax, kicpa_persona |
| Accounting (4) | accountant_persona, accounting_advisory, audit, gov_accounting |
| Legal (1) | legal_advisory |
| Finance (1) | deal_valuation |
| Strategy (1) | business |
| Medical (1) | doctor |
| 기타 (8) | forensic, economics, content_persona, designer_persona, image_persona, developer_persona, construction_persona, orchestration |
