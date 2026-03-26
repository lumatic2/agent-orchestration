<!--
music.md — Suno Music Prompt Design Skill for Claude Code
Author: luma (https://github.com/Mod41529)
License: MIT
Vault dependency: None (standalone version)
Install: cp music.md ~/.claude/commands/music.md
Repo: https://github.com/Mod41529/music-skill-ko
-->

# /music — Suno 음악 프롬프트 설계 세션

대화를 통해 원하는 음악을 구체화하고, Suno에서 바로 사용할 수 있는 프롬프트와 설정을 생성한다.

$ARGUMENTS 형식: [장르/분위기 설명] [옵션]

옵션: --quick (질문 없이 바로 생성), --lyrics (가사 포함), --instrumental, --style [아티스트명], --album [컨셉]

---

# Part 1: Flow (실행 흐름)

## 0. 진입

$ARGUMENTS가 비어 있으면 인터랙티브 모드:

```
🔗 다른 크리에이티브 작업에서 이어왔나요?
✏️ 글 → 제목·핵심 문단·분위기 붙여넣기
🎨 그림 → 이미지 설명·프롬프트 붙여넣기
(없으면 Enter로 건너뛰기)
```

**연계 컨텍스트가 있으면:**
- 글에서 이어온 경우: 주제·감정·리듬감 추출 → 장르/분위기 자동 추천 + 가사 소재 반영
- 그림에서 이어온 경우: 시각 분위기·색감·스타일 추출 → 어울리는 사운드스케이프/장르 추천
- 컨텍스트 없으면: 아래 메뉴로 진행

```
어떤 음악을 만들고 싶으세요?

🎤 힙합
   └ 트랩 / 드릴 / 붐뱁 / 재즈힙합 / 로파이힙합

🎷 재즈
   └ 재즈힙합 / 퓨전재즈 / 스무스재즈 / 보사노바

🎸 록
   └ 인디 / 얼터너티브 / 팝록 / 포스트록

🎹 R&B · 소울
   └ 트랩소울 / 네오소울 / 펑크 / 컨템포러리 R&B

🎧 일렉트로닉
   └ EDM / 하우스 / 테크노 / 드럼앤베이스

🎻 클래식 · 오케스트라
   └ 미니멀 / 앰비언트 / 신포닉

🎵 K-POP · 팝
   └ 발라드 / 댄스팝 / 트로트

🌍 월드뮤직
   └ 라틴 / 아프로비트 / 레게

자유롭게 설명해주세요. 이런 것들을 알려주시면 좋아요:
- 장르/분위기, BPM, 메인 악기, 보컬 성별·톤, 음역대, 리듬
- 가사 스타일 (빈지노 / Drake / SZA 등)

💿 앨범/EP로 만들고 싶으면 "앨범"이라고 말해주세요.
```

`--quick`이면 Step 1의 "바로 만들기" 경로로 즉시. `--album`이거나 대화 중 "앨범"을 언급하면 Step 1-A로.

## 1. 설계 대화

사용자의 초기 설명을 받으면 **먼저 두 가지 경로를 제시한다**:

```
{장르/분위기 요약}군요!

① 바로 만들기 — 지금 정보로 즉시 프롬프트 생성 (빠르게)
② 더 구체화하기 — BPM·악기·보컬·가사 등 추가 설정

어떻게 할까요?
```

**① 바로 만들기** 선택 시:
- Ref D 템플릿 중 가장 유사한 장르 기준점 참고
- 빠진 요소(악기·BPM·보컬·프로덕션)를 장르 관습에 맞게 자동 결정
- 결정 근거를 간단히 표시 후 Step 2로 바로 출력

**② 더 구체화하기** 선택 시:
아래 요소를 이미 명시된 건 건너뛰고, 빠진 것만 2~3개씩 자연어로 질문.

| 요소 | 예시 |
|---|---|
| 장르 + 서브장르 | Jazz Hop, Trap Soul, Indie Rock |
| 분위기/감정 | melancholic, euphoric, chill, dark |
| BPM | 70 (chill) ~ 140+ (energetic) |
| 악기 구성 | piano, 808 bass, lo-fi guitar, synth pad |
| 보컬 스타일 | male rap, female R&B, no vocal |
| 레퍼런스 | "Nujabes 느낌", "The Weeknd 같은" |
| 곡 구조 | intro→verse→chorus→bridge→outro |
| 언어 · 가사 스타일 | 한국어, 영어, 혼합 / --style 아티스트명 |
| 길이 | 2분, 3분 30초 |

가이드라인:
- 감각적 표현("비 오는 날 카페")을 음악 요소로 변환
- 장르 조합 적극 제안 ("재즈 + 힙합 + lo-fi = jazz hop")
- 레퍼런스 아티스트 → 음악적 특징 분석 후 반영
- 가사 있으면 → Ref B 아티스트 프로필 + Ref C 가사 원칙 + Ref F 레퍼런스 참고

### 1-A. 앨범/EP 모드 (`--album`)

**컨셉 정의**: 앨범 제목(가제), 전체 무드/테마, 곡 수(EP 3~5 / 미니 5~7 / 정규 8~12), 통일 요소

**트랙 역할 구조**:
| 위치 | 역할 | 특징 |
|---|---|---|
| Track 1 | 인트로/오프닝 | 앨범 세계관 진입. 짧거나 인스트루멘탈 |
| Track 2~3 | 리드 싱글급 | 가장 캐치한 곡. 앨범의 얼굴 |
| 중반 | 분위기 전환 | 템포/장르 변화로 리스너 지루함 방지 |
| 후반 | 딥컷 | 실험적이거나 개인적인 곡 |
| 마지막 | 클로징 | 여운. 앨범 메시지 정리 |

**통일할 것**: 코어 태그 2~3개, BPM 범위, Weirdness/Style Influence 범위, Persona 동일 보컬

각 곡마다 Step 2 프롬프트 생성. 앨범 전체 컨셉 + 곡별 프롬프트를 한 번에 출력.

## 2. Suno v5 프롬프트 생성 (최종 출력)

설계 완료 후 아래 형식으로 출력:

```
## 🎵 Suno 프롬프트 (v5)

### Style of Music
{Suno Style of Music 필드에 그대로 붙여넣을 프롬프트}

### Title
{곡 제목 2~3개 후보}

### 설정
- Mode: Custom / Instrumental: {Yes/No} / Version: v5
- Vocal Gender: {Male/Female/미지정}
- Exclude Style: {제외 스타일}
- Weirdness: {0~100} / Style Influence: {Loose~Strong}
- Persona: {사용 여부} / Inspo: {사용 여부} / Audio: {사용 여부}

### Lyrics (가사 있을 경우)
[Intro]
{가사}
[Verse 1]
{가사}
...
```

앨범 모드는 공통 설정 + 곡별 프롬프트를 순서대로 출력.

## 3. 개선 루프

출력 후 수정 요청 시 재생성:
- "더 어둡게" → 분위기/악기 조정
- "BPM 올려줘" → 템포 변경
- "보컬 빼줘" → instrumental 전환
- "가사 써줘" / "가사 다시" → 가사 추가/재작성

세션은 사용자가 만족할 때까지 유지. 확정 시:
```
✅ 프롬프트 완성! Suno에서 Custom 모드로 생성하세요.
스타일 태그와 가사(있으면)를 각각 복사해서 붙여넣으면 됩니다.
```

---

# Part 2: Reference (내부 참조, 출력 안 함)

## Ref A. Suno v5 프롬프트 규칙

**Style of Music 작성**:
- 최대 1,000자 (v4 이전은 200자)
- 태그 우선순위: Genre → Mood → Instruments → Vocals → Production
- 쉼표 구분 태그 나열 + 자연어 혼용 가능
- 핵심 5~8개 태그 권장 (너무 많으면 "협상"됨)
- BPM 숫자 명시 가능: "140 BPM"
- 네거티브 프롬프트: "no autotune, no heavy reverb" (Exclude Style 필드와 별개)
- 레퍼런스 아티스트는 Style Influences 필드에 넣는 게 v5에서 더 효과적

**가사 태그**:
- 구조: [Intro], [Verse], [Chorus], [Pre-Chorus], [Bridge], [Outro], [Drop], [Hook], [Build]
- 보컬: [Male Vocal], [Female Vocal], [Whisper], [Spoken], [Belted], [Harmonies], [Ad-lib]
- 악기: [Instrumental], [Instrumental Break], [Guitar Solo], [Piano Solo]
- v5 최대 4분 (Extend로 연장). 가사 라인 짧게. 발음 어려운 고유명사는 발음 표기.

**Weirdness 장르별 권장값**:
| 장르 | Weirdness | Style Influence |
|---|---|---|
| Radio Pop / K-POP | 35~50 | 65~80 |
| Hip-hop / Trap | 40~55 | 60~75 |
| Worship / Gospel | 25~40 | 70~85 |
| Orchestral / Cinematic | 55~70 | 55~70 |
| Ambient / Experimental | 70~85 | 40~60 |
| 코러스 보호 (hook lock) | 25~40 | 70~85 |
| 브릿지 실험 | 55~70 | 45~65 |

**슬라이더 원칙**: 품질이 아닌 "행동" 제어 / 한 번에 하나만 변경 / 코러스는 보호 / 실험은 브릿지에서 / Audio Influence는 업로드 시만 (60~75)

## Ref B. 아티스트 가사 프로필

`--style [아티스트명]` 또는 대화 중 요청 시 참조. 미지정 시 장르·분위기에 맞게 자율 판단.

### 한국
| 아티스트 | 특징 | 문체 | 주제 |
|---|---|---|---|
| **빈지노** | 철학적·감성적 | 시적 이미지 + 일상어 혼합, 영한 혼용 유려 | 자아성찰, 도시, 자유 |
| **재키와이** | 직설적·날것의 에너지 | 짧고 임팩트, 감정을 날것으로 | 자기 확신, 관계, 분노 |
| **타블로** | 문학적·깊은 은유 | 복잡한 스토리텔링, 긴 호흡 시 구조 | 삶과 죽음, 가족, 시간 |
| **블랙넛** | 자조적·아이러니 | 예상 못 한 펀치라인, 도발적 유머 | 사회 비판, 자기 비하 |
| **던말릭** | 에너지·직관적 | 짧고 강렬한 반복, 리듬 우선 | 자신감, 바이브 |
| **키드밀리** | 냉소적·스웨거 | 건조한 위트, 의외의 비유 | 힙합 씬 비판, 아이러니 |
| **pH-1** | 감성·멜로디컬 | 부드러운 한영 전환, 감정선 뚜렷 | 관계, 그리움, 성장 |
| **lil boi** | 그루비·세련됨 | 여유 있는 플로우, 감각적 묘사 | 여유, 도시의 밤, 자기표현 |

### 해외
| 아티스트 | 특징 | 문체 | 주제 |
|---|---|---|---|
| **Drake** | 감성+플렉스 이중성 | 소프트 훅, 대화체, 자기연민 | 관계, 성공의 허무, 신뢰 |
| **The Weeknd** | 다크 R&B, 시네마틱 | 관능적·몽환적, 반복 후렴 | 쾌락과 공허, 중독, 밤 |
| **Frank Ocean** | 실험적, 내성적 | 의식의 흐름, 섬세한 감각 묘사 | 사랑과 상실, 향수, 시간 |
| **Kendrick Lamar** | 사회적·문학적 | 다층적 은유, 관점 전환 | 인종, 정체성, 내면 갈등 |
| **Tyler, the Creator** | 다채로운, 장르 블렌딩 | 화려한 색채 이미지, 유머+진심 | 외로움, 사랑, 창작 |
| **SZA** | 취약한·솔직한 | 날것의 감정, 구어체, 의외의 비유 | 관계, 자존감, 성장통 |
| **J. Cole** | 서사적·교훈적 | 긴 호흡 이야기, 담백 | 가족, 사회 관찰, 겸손 |
| **Billie Eilish** | 미니멀·속삭임 | ASMR 같은 톤, 짧은 문장 | 악몽, 자기 파괴, 10대 감성 |

## Ref C. 가사 작성 원칙

1. **Show Don't Tell** — "슬프다" → "창문에 빗소리만 들려". 감정의 이름 대신 장면/감각 묘사.
2. **구체적 이미지** — "좋은 하루" → "단골 빵집 아저씨 미소". 작고 구체적인 디테일이 보편적 감동.
3. **일상어 + 시적 표현 혼합** — 평범한 말 3줄 → 갑자기 한 줄 시. 이 리듬이 감성을 만듦.
4. **라임은 자연스럽게** — 억지 라임 금지. 라임 없으면 리듬감/반복으로 대체. 흐름이 우선.
5. **한 구절에 아이디어 하나** — Verse 1=상황 설정, Verse 2=심화, Bridge=클라이맥스 전 여백.
6. **후렴은 단순 반복** — 바로 따라 부를 수 있는 한 문장. 한영 혼합 시 영어는 punch word로.

## Ref D. 프롬프트 템플릿

장르별 기준점. "바로 만들기" 선택 시 가장 유사한 템플릿을 기준으로 빈 요소를 채운다.

### 힙합 — 레이지 트랩 (감성)
```
melodic rage hip-hop, dark atmospheric trap, emotional, introspective,
distorted synth leads, heavy 808 bass, trap hi-hats, autotuned male rap,
reverb-drenched vocals, 140 BPM, cinematic, brooding
```
Weirdness: 50 / Style Influence: 65

### 힙합 — 재즈힙합 (그루비)
```
jazz hop, groovy, upbeat, live jazz instruments, upright bass, jazz piano,
brushed drums, swing rhythm, male rap with jazz vocal hooks,
smooth lo-fi texture, 90 BPM, laid-back
```
Weirdness: 45 / Style Influence: 70

### K-POP — 감성 발라드
```
Korean ballad, slow emotional piano ballad, sorrowful, heartfelt male vocal
with breathy tone, piano-driven, string arrangement, melancholic,
bittersweet love, 65 BPM
```
Weirdness: 35 / Style Influence: 75

### 월드뮤직 — 레게 팝 (축제 앤썸)
```
reggae pop, world music, festive anthem, tropical groove, upbeat, euphoric,
male vocal, punchy brass horns, ska rhythm guitar, bouncy bass, steel drums,
handclaps, 100 BPM, stadium energy, catchy hook, sunny
```
Weirdness: 40 / Style Influence: 70

## Ref E. 가사 레퍼런스

분위기별 좋은 라인 패턴. 가사 작성 시 톤·이미지 참고.

**감성 / 그리움**
- 시각적 장면으로 감정 표현: "새벽 세 시, 꺼지지 않는 네 방의 불빛"
- 단순 질문이 깊이를 만듦: "넌 아직 거기 있을까, 같은 자리에"

**자기 확신 / 스웨거**
- 짧고 리듬감 있는 선언: "내 길을 가 — 빛이 나"
- 한영 대비로 아이러니: "They don't know me, 근데 다 알아보더라"

**일상 / 여유**
- 일상어가 가장 깊은 위로: "오늘도 별일 없이 괜찮았어"
- 감각적 미니멀리즘: "커피 한 잔에 노을 하나면 충분해"

**후렴 패턴**
- 반복형: 같은 문장 2회 + 변주 1회
- 콜앤리스폰스: 질문 → 대답 ("어디로 가?" / "어디든")
- 한영 스위치: 한국어 감정 → 영어 punch word ("괜찮아 I'm fine")

---

## 세션 종료 & 연계 제안

프롬프트 완성 후 아래 형식으로 연계 제안 표시:

```
이어서 진행할까요?
```

| 곡 성격 | 🎨 /drawing | ✏️ /writing |
|---|---|---|
| 가사 있는 곡 | 앨범 커버 or 뮤직비디오 컨셉아트 | 가사를 에세이·시로 확장 |
| 인스트루멘탈 | 이 분위기의 시네마틱 이미지 | 이 곡에 어울리는 짧은 산문 |
| 앨범 컨셉 | 앨범 커버 or 브랜드 비주얼 | 앨범 소개글 / 아티스트 노트 |
