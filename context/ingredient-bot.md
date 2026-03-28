# 냉장고를 부탁해 (ingredient-bot)

**경로**: `~/ingredient-bot/`
**스택**: Python, Telegram Bot API, SQLite, FastAPI+Jinja2 웹 UI, Gemini Flash
**핵심 목표**: "사람들이 식재료 낭비 없이 살 수 있게 돕는 서비스" — 스마트 냉장고가 없는 99% 가정 대상

## 로드맵
```
지금 (개인용)     →   6개월 (가족)      →   1~2년 (확장)      →   그 이후
텔레그램 봇           어머니 가구 실사용      멀티유저 구조           SmartThings API 연동
+ 웹 UI               → 가족 공유            카카오톡 채널 검토       또는 B2B/인수 기회
(싱글유저)             → 진짜 피드백 수집      앱 설치 불필요 강화
```
**다음 즉각 행동**: 어머니 가구에 봇 연결 (설정 대신 해드리고 텔레그램으로만 사용)

## 현재 구현 기능 (2026-03-28 기준, M4 운영 중)

### 텔레그램 봇
- 재고 CRUD, 영수증/바코드 OCR, 자연어 입력 ("달걀 5개 추가")
- `/count` 실지재고조사법 (배치 입력), `/minstock` 품목별 기준, `/low` 즉시 액션 버튼
- alias 자동 통합 (Gemini + difflib 선처리), 레시피 추천, 유통기한 자동 추정
- 하단 메뉴 키보드 (📦재고 / 🛒쇼핑 / 🍳레시피 / 📊현황 / 📸사진등록)
- 아침 알림: 긴급/주의 섹션 분리, 이모지, 날짜/요일, 웹 링크 포함

### 웹 UI (`~/ingredient-bot/web.py`, FastAPI)
- `/` 대시보드, `/inventory` 재고목록(인라인 편집·취향토글), `/shopping` 쇼핑리스트
- `/analytics` ABC분류 + EOQ 권장주문량 차트, `/barcode` 카메라 스캔
- PWA 설정, 다크모드, ngrok 외부 접근

### 비용 최적화
- suggest_canonical: difflib 선처리 → 불확실한 경우만 단일 배치 Gemini 호출
- 모델: gemini-1.5-flash (suggest_canonical, recipe) / gemini-2.5-flash (OCR 비전만)

## 차별화 포인트
- 앱 설치 불필요 (텔레그램 + 웹)
- 정밀 수량 관리 + 소진 예측 (타 앱 없음)
- EOQ/ABC 물류이론 적용 (개인용 앱 중 유일)
- 한국어 영수증 OCR + alias 자동 통합
- 자연어 입력 (무비용 regex)
