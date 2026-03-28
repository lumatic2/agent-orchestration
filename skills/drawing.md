시각 결과물 생성 세션을 시작한다.

대화를 통해 원하는 시각 결과물을 구체화한다.
- **이미지 프롬프트**: Midjourney / Firefly / Nanobanana에서 사용할 프롬프트 생성
- **직접 생성**: SVG 아이콘/로고, Mermaid 다이어그램을 코드로 바로 생성
- **UI 디자인**: Stitch MCP로 실제 UI 화면 생성

$ARGUMENTS 형식: [설명] [옵션]

옵션: --quick, --mj, --ff, --nb, --all, --svg, --mermaid, --icon, --dark, --mobile, --desktop, --tablet, --variants N

---

## 0. 인수 없이 호출 시 (인터랙티브 모드)

$ARGUMENTS가 비어 있으면:

**연계 컨텍스트 자동 감지**: 현재 세션에서 이전 크리에이티브 결과물(글·음악)이 있으면 AskUserQuestion을 호출해라:
- 질문: "[제목/주제] 작업이 이어지고 있네요. 이 컨텍스트를 이미지 방향에 반영할까요?"
- A) 반영 — 주제·분위기·키워드를 이미지 소재에 자동 연결
- B) 새로 시작 — 이전 작업과 독립적으로 진행

반영 로직:
- 글 반영: 주제·감정·핵심 이미지어 → 이미지 타입 자동 추천 + 프롬프트 소재 반영
- 음악 반영: 장르·분위기·악기 → 시네마틱/앨범아트 추천 + 시각 분위기 반영

컨텍스트 없거나 B 선택 시 → AskUserQuestion을 호출해라:
- 질문: "어떤 걸 만들까요?" (header: "출력 유형")
- A) 이미지 프롬프트 — Midjourney / Firefly / Nanobanana 외부 도구용
- B) 로컬 AI 생성 — ComfyUI (RTX 4070 Ti, 무료)
- C) SVG / 다이어그램 — 로고, 아이콘, Mermaid 플로우차트
- D) UI 화면 — Stitch MCP (모바일/웹/태블릿)

## 1. 라우팅

요청 내용에 따라 세 경로 중 하나로 자동 분기한다.

**UI 화면 경로** (Stitch MCP로 실제 화면 생성):
- 앱 화면, 대시보드, 랜딩페이지, 로그인, 피드 등 UI/UX 결과물
- `--mobile`, `--desktop`, `--tablet`, `--variants N` 옵션 시 강제 분기

**ComfyUI 로컬 생성 경로** (로컬 AI로 직접 이미지 생성):
- 치비·캐릭터·스티커·일러스트 등 AI 이미지 로컬 생성
- `--comfy` 옵션 또는 "로컬로", "ComfyUI로" 언급 시 강제 분기
- 자세한 설정 → Section 5 참조

**직접 생성 경로** (SVG/Mermaid로 즉시 출력):
- 로고, 아이콘, SVG 그래픽, 심볼, 다이어그램, 플로우차트, ER 다이어그램 등
- `--svg`, `--mermaid`, `--icon` 옵션 시 강제 분기

**프롬프트 생성 경로** (MJ/Firefly/Nanobanana 프롬프트):
- 사진풍 이미지, 일러스트, 컨셉아트, 캐릭터, 풍경 등
- `--mj`, `--ff`, `--nb`, `--all` 옵션 시 강제 분기
- 도구 미지정 시 → Step 1에서 도구 선택

---

## 2. 대화 흐름 — 이미지 프롬프트 경로

### Step 1 — 도구 선택

도구가 지정되지 않았으면 AskUserQuestion을 호출해라:
- 질문: "어떤 도구로 만들까요?" (header: "도구")
- A) Midjourney — 최고 퀄리티. 아트워크·사진풍·시네마틱 모두 강력 (Recommended)
- B) Adobe Firefly — 상업용 안전. 저작권 걱정 없음, Adobe 연동
- C) Nanobanana — 무료. Gemini 기반, 빠른 실험용

### Step 2 — 이미지 구체화 대화

도구 선택 후, 아래 요소를 **한 번에 2~3개씩** 자연스럽게 질문한다.
이미 언급된 항목은 건너뛴다. 절대 한꺼번에 묻지 않는다.

| # | 요소 | 예시 |
|---|---|---|
| ① | 주제/피사체 | 고양이, 도시 풍경, 우주비행사 |
| ② | 스타일/매체 | 수채화, 사이버펑크, 사진풍, 지브리 |
| ③ | 분위기/톤 | 몽환적, 어두운, 따뜻한, 긴장감 |
| ④ | 구도/앵글 | 클로즈업, 버드아이뷰, 와이드샷 |
| ⑤ | 조명 | 골든아워, 네온, 림라이트, 스튜디오 |
| ⑥ | 색감 | 파스텔, 모노크롬, 고채도, 어스톤 |
| ⑦ | 비율/용도 | 1:1 인스타, 16:9 배경화면, 9:16 스토리 |
| ⑧ | 레퍼런스 | "Moebius 느낌", "Wes Anderson 색감" |

**대화 가이드라인:**
- 감각적 표현("비 오는 날 카페 창가")을 프롬프트 요소로 변환
- 스타일 조합 제안 ("지브리 + 사이버펑크 → 코지펑크")
- 용도를 알면 비율 자동 추천
- 레퍼런스 언급 시 해당 아티스트/작품의 시각적 특징 분석해서 반영

**대화 예시:**
```
사용자: /drawing 고양이가 책 읽는 그림
→ "도구는 Midjourney로 갈까요? 그리고 어떤 스타일 — 사진풍, 일러스트, 수채화?"
사용자: 수채화, 미드저니
→ "어디에 쓸 이미지예요? 그리고 배경은 — 서재 창가, 아늑한 소파, 배경 없이?"
사용자: 인스타에 올릴거야, 창가
→ 프롬프트 생성
```

---

## 3. 대화 흐름 — 직접 생성 경로 (SVG/Mermaid)

### SVG 로고/아이콘

내용 구체화 후 즉시 생성 → 파일 저장 → VSCode 오픈

**구체화 질문 (한 번에 2~3개):**

| # | 요소 | 예시 |
|---|---|---|
| ① | 브랜드명/용도 | luma, 앱 아이콘, 파비콘 |
| ② | 타입 | 심볼형(아이콘+텍스트), 워드마크(텍스트만), 심볼 단독 |
| ③ | 색감/무드 | 밝은, 어두운, 특정 컬러, 브랜드 컬러 참조 |
| ④ | 스타일 | 미니멀, 기하학, 유기적, 볼드 |
| ⑤ | 아이콘 스타일 | Outline, Filled, Duotone, Bold |

**SVG 생성 원칙:**
- `viewBox="0 0 24 24"` 기준 (아이콘), 로고는 비율에 맞게
- `currentColor` 사용으로 CSS 색상 제어 가능하게
- 로고는 라이트/다크/심볼 단독 3버전 기본 제공
- 8px 그리드 기반 설계

### Mermaid 다이어그램

내용 구체화 후 코드블록으로 출력 (파일 저장 불필요 — 문서에 바로 붙여넣기 가능)

**다이어그램 타입 자동 선택:**
- 프로세스/의사결정 → `flowchart TD/LR`
- API 호출/서비스 통신 → `sequenceDiagram`
- DB 스키마 → `erDiagram`
- OOP 구조 → `classDiagram`
- 프로젝트 일정 → `gantt`
- 아이디어 정리 → `mindmap`
- 시스템 아키텍처 → `graph TB` + 서브그래프

**스타일링:**
```
%%{init: {'theme': 'dark'}}%%                                    ← --dark 옵션
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#6366f1'}}}%%  ← 커스텀 컬러
```

---

## 4. 대화 흐름 — UI 화면 경로 (Stitch MCP)

### Step 1 — 디바이스 선택

디바이스가 지정되지 않았으면:
```
어떤 디바이스용 UI예요?
📱 모바일 (기본)  🖥️ 데스크탑  📟 태블릿
```

### Step 2 — UI 구체화 대화

한 번에 2~3개씩 자연스럽게 질문. 이미 언급된 항목은 건너뛴다.

| # | 요소 | 예시 |
|---|---|---|
| ① | 화면 종류 | 랜딩페이지, 대시보드, 로그인, 피드 |
| ② | 서비스/앱 성격 | 피트니스 앱, SaaS 툴, 쇼핑몰, 포트폴리오 |
| ③ | 핵심 콘텐츠 | 표시할 데이터, 주요 액션, CTA 버튼 |
| ④ | 디자인 스타일 | 미니멀, 뉴모피즘, 글라스모피즘, 다크모드 |
| ⑤ | 색감/브랜드 | 브랜드 컬러, 무드 (차분한/활기찬/고급스러운) |
| ⑥ | 레퍼런스 | "Notion 느낌", "Linear 스타일", "Apple 감성" |
| ⑦ | 용도 | 클라이언트 제안용, 개인 프로젝트, 실제 개발 예정 |

**가이드라인:** "깔끔하게" → "여백 많고 텍스트 중심의 미니멀 스타일"로 구체화. 용도가 개발 예정이면 코드 추출 안내.

### Step 3 — 생성 실행

```
# 1. 프로젝트 생성
mcp__stitch-mcp__create_project(title="{서비스명} UI")

# 2. 화면 생성 (영어 프롬프트, 위→아래 구조 서술)
mcp__stitch-mcp__generate_screen_from_text(
  projectId="{ID}",
  prompt="{UI 설명}",
  deviceType="MOBILE"  # MOBILE / DESKTOP / TABLET
)
```

**프롬프트 원칙:** 영어로 작성. "Header with... → Hero section... → Cards showing..." 순서. 색상 구체적으로 ("indigo accent"). 컴포넌트명 명시 ("floating action button").

### Step 4 — 후속 작업 옵션

생성 완료 후:
```
① 수정 — mcp__stitch-mcp__edit_screens (selectedScreenIds, prompt)
② 변형 생성 — mcp__stitch-mcp__generate_variants
   variantOptions: { variantCount: N, creativeRange: "EXPLORE" }
   creativeRange: REFINE(미세조정) / EXPLORE(탐색, 기본) / REIMAGINE(재해석)
③ 다른 화면 추가 — 같은 projectId로 generate_screen_from_text 재호출
④ 코드 추출 — stitch.withgoogle.com → 프로젝트 선택 → "Get code" / 또는 mcp__stitch-mcp__fetch_screen_code
⑤ 완료
```

---

## 5. 대화 흐름 — ComfyUI 로컬 생성 경로

> 🖥️ RTX 4070 Ti 로컬 실행. 무료. MCP로 Claude Code에서 직접 제어.
> 출력 폴더: `C:\Users\1\Desktop\Drawing\comfy\`
> ComfyUI 포트: `127.0.0.1:8000` (Windows Electron 앱)

### 설치된 체크포인트

| 모델 파일 | 특징 | 최적 스타일 |
|---|---|---|
| `illustriousXL_v01.safetensors` | 클린 애니 라인아트 | 치비·스티커·캐릭터 **추천** |
| `ponyDiffusionV6XL_v6StartWithThisOne.safetensors` | 애니/furry 특화 | 붓터치 질감 |
| `noobaiXLNAIXL_vPred10Version.safetensors` | V-Pred, 단일 캐릭터 제어 약함 | 실험용 |

### 설치된 LoRA

| LoRA 파일 | 용도 | 권장 weight |
|---|---|---|
| `minimalist_flat_2d.safetensors` | 플랫 채색 강제 (Illustrious) | 0.6~0.8 |
| `dual_vector_flat_2d.safetensors` | 벡터 2D 스타일 (SDXL) | 0.5~0.7 |
| `cartoon_style_illustrious.safetensors` | 카툰 스타일 (Illustrious) | 0.6~0.8 |
| `sdxl_sticker_sheet_norod78.safetensors` | 스티커 질감 (Pony 전용) | 0.5 |

### 프롬프트 구조 (Illustrious XL 기준)

```
긍정: solo, 1{동물}, chibi, front view, facing viewer, looking at viewer,
      big round eyes, {복장}, thick bold black outline, flat color fill,
      no shading, no gradient, clean lineart, white background, kawaii, cute

부정: multiple characters, back view, shading, gradient, texture,
      3D, realistic, complex background, repeated pattern, collage
```

**Pony 전용 필수 태그 (앞에 붙일 것):** `score_9, score_8_up, score_7_up, source_anime`

### 워크플로우 핵심 설정

| 파라미터 | Illustrious XL | Pony |
|---|---|---|
| Steps | 28~30 | 30 |
| CFG | 7 | 9 |
| Sampler | dpmpp_2m | dpmpp_2m |
| Scheduler | karras | karras |
| batch_size | **반드시 1** | 1 |

### LoRA 2개 사용 시

```
CheckpointLoaderSimple → LoraLoader(LoRA_A) → LoraLoader(LoRA_B) → KSampler
```
각 LoRA weight 합이 1.4 이하가 되도록 조정.

### 알려진 문제 & 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| 뒷모습만 나옴 | 색상 조합이 특정 뒷면 캐릭터와 연결 | 색상 변경 또는 시드 교체 |
| 여러 캐릭터 콜라주 | `solo` 태그 누락 또는 batch_size > 1 | `solo` 필수, batch_size=1 |
| 회색 배경 | 모델 기본 배경 | Flat Color LoRA 추가, `white background` 강조 |
| NoobAI 흰 화면 | V-Pred 미설정 | `ModelSamplingDiscrete(v_prediction)` 노드 추가 |

---

## 5-B. SVG 파일 저장 파이프라인

SVG 결과물은 **항상** 파일로 저장하고 VSCode에서 자동 오픈한다.

```
# 1. 폴더 확인 (없으면 생성)
mkdir -p ~/Desktop/Drawing

# 2. 파일 저장
Write(file_path="C:/Users/1/Desktop/Drawing/{filename}.svg", content="{svg코드}")

# 3. VSCode 오픈
Bash("cmd /c code C:\\Users\\1\\Desktop\\Drawing\\{filename}.svg")
```

**파일명 규칙:**
- 로고: `{브랜드명}-logo.svg`, `{브랜드명}-logo-dark.svg`, `{브랜드명}-symbol.svg`
- 아이콘 단독: `{설명}-icon.svg`
- 아이콘 세트: `{세트명}-icons.svg`
- HTML 다이어그램: `{설명}-diagram.html`

---

## 5. Midjourney 프롬프트 체계 (v7/v8)

### 현재 모델 상태 (2026-03)
- **V7**: 메인 사이트 + Discord 기본 모델
- **V8 Alpha**: 2026-03-17 출시. alpha.midjourney.com 전용. 5배 빠름, `--hd` 지원
- **Niji 7**: 2026-01-09 출시. 일본 애니 스타일 특화

### 프롬프트 구조 (v7/v8 공통)

v7부터 자연어 이해 대폭 향상. **태그 나열보다 서술형 문장이 효과적.**

```
[주제 서술], [환경/배경], [스타일/매체], [조명], [분위기], [카메라/구도] --ar {비율} --v 7 --s {값}
```

**좋은 예:**
```
a golden retriever puppy sitting on autumn leaves in a sunlit park, soft dappled light filtering through the trees, painterly illustration style with warm earthy tones, low angle shot looking up slightly --ar 4:5 --v 7 --s 300
```

### 핵심 파라미터

| 파라미터 | 범위 | 설명 | 권장값 |
|---|---|---|---|
| `--v 7` | — | 모델 버전 (기본) | 항상 명시 |
| `--v 8` | — | V8 Alpha | 실험적 |
| `--niji 7` | — | 애니/일러스트 특화 | 일본풍 |
| `--ar` | 자유 비율 | 가로:세로 | 용도에 맞게 |
| `--s` (stylize) | 0~1000 | 미학적 개입도 | 기본 100 |
| `--c` (chaos) | 0~100 | 결과 다양성 | 탐색=25~50 |
| `--w` (weird) | 0~3000 | 실험적 변형 | 일반=0 |
| `--q` (quality) | .25/.5/1/4 | 품질/시간 | 테스트=.5, 최종=1 |
| `--no` | 텍스트 | 제외 요소 | |
| `--style raw` | — | AI 미화 최소화 | 사진풍 |

### 레퍼런스 파라미터

| 파라미터 | 설명 |
|---|---|
| `--sref {URL}` | 스타일 레퍼런스 (`--sw` 0~1000으로 강도 조절) |
| `--oref {URL}` | 오브젝트/캐릭터 레퍼런스 (v7+) |
| `--cref {URL}` | 캐릭터 레퍼런스 (`--cw` 0=얼굴만, 100=전체) |
| `--p` | 개인화 (좋아요 기반 취향 반영) |

### V8 전용

| 파라미터 | 설명 | 주의 |
|---|---|---|
| `--hd` | 네이티브 2K 해상도 | GPU 4배 |
| `--q 4` | 최고 품질 | GPU 4배 |
| `--hd --q 4` | 2K + 최고품질 | GPU 16배, Relax 불가 |

### Stylize 가이드

| 용도 | --s 값 |
|---|---|
| 프롬프트 충실 | 0~100 |
| 균형 (기본) | 100~250 |
| 아트워크 | 250~500 |
| MJ 자체 미학 | 500~1000 |

### 비율 가이드

| 용도 | --ar |
|---|---|
| 인스타 피드 | 4:5 |
| 인스타 스퀘어 | 1:1 |
| 스토리/릴스 | 9:16 |
| 유튜브 썸네일 | 16:9 |
| 포스터/인쇄 | 2:3 또는 3:4 |
| 시네마틱 | 21:9 |

### 스타일별 키워드 팔레트

**사진풍** — 35mm, 85mm f/1.4, Kodak Portra 400, shallow depth of field, `--style raw`

**디지털 아트** — digital painting, concept art, cel-shaded, "Studio Ghibli aesthetic"

**수채화** — watercolor on cold-pressed paper, visible brush strokes, ink wash, paper texture

**시네마틱** — anamorphic lens, teal and orange, volumetric god rays, rain-slicked streets

**미니멀/디자인** — negative space, geometric composition, limited 2-color palette

---

## 6. Adobe Firefly 프롬프트 체계 (Image Model 4, 2026-03)

### 현재 모델
- **Firefly Image 4**: 기본. 포토리얼리즘, 텍스트 렌더링 강화
- **Firefly Image 4 Ultra**: 최고 품질, 복잡한 장면
- **FLUX.2 통합**: 최대 4개 레퍼런스 이미지 지원

### 프롬프트 구조
```
{주제 + 행동}. {배경/환경}. {스타일/기법}. {조명}. {색감/분위기}.
```

### 핵심 설정 (UI 패널)

| 설정 | 권장 |
|---|---|
| Content Type | Photo/Graphic/Art 용도에 맞게 |
| Visual Intensity | 사진=낮게, 아트=높게 |
| Prompt Enhancement | 짧은 프롬프트 시 켜기 |

### 작성 원칙
1. 최소 3단어, "generate"/"create" 금지
2. 생존 아티스트명 직접 사용 금지 → 기법으로 대체
3. 네거티브: "bad hands, extra fingers, low res, watermark"

---

## 7. Nanobanana 프롬프트 체계 (Gemini 3 Pro Image, 2026-03)

### 현재 모델
- **Nano Banana 2**: Gemini 3.1 Flash Image. 빠름, 무료
- **Nano Banana Pro**: Gemini 3 Pro Image. Thinking 지원, 최대 14개 레퍼런스, 텍스트 렌더링 완벽

### 프롬프트 구조
```
{피사체와 구체적 특징}. {행동/상황}. {배경과 환경}. {스타일과 분위기}. {조명과 색감}. {카메라 앵글}.
```

### 레퍼런스 이미지 (Pro)
최대 14개. `[레퍼런스 이미지] + [관계 설명] + [새 시나리오]` 형식

### 작성 원칙
1. 서술형 문장 — 태그 스팸 불필요
2. 긍정형 서술 — "not dark" → "bright and airy"
3. Pro Thinking — 복잡한 장면은 상세히 설명할수록 좋음

---

## 8. 출력 형식

**이미지 프롬프트:**
```
## 이미지 프롬프트

### 컨셉
{한 줄 요약}

### {도구명} 프롬프트 (복사용)
​```
{프롬프트}
​```

### 설정
- 비율: {--ar 값} ({용도})
- Stylize: {--s 값}
- 모델: --v 7
--no {제외 목록}
```

**SVG 직접 생성:**
```
## {제목} 완성

- 파일: Desktop/Drawing/{filename}.svg
- VSCode에서 열림

수정하거나 다른 버전이 필요하면 말씀해주세요.
```

`--all`이면 세 도구 모두 출력.

---

## 9. --quick 모드

질문 없이 즉시 생성.
- 이미지: 부족한 요소 자동 결정 + 근거 한 줄 표기, 도구 미지정 시 Midjourney
- SVG/다이어그램: 내용 맥락으로 스타일 자동 결정

---

## 10. 개선 루프

출력 후 수정 요청 반영:
- "더 어둡게" / "색감 따뜻하게" → 조명/색상 조정
- "stylize 올려줘" → --s 값 조정
- "V8으로" → `--v 8 --hd` 적용
- "다른 도구용으로도" → 추가 도구 변환
- SVG: "색상 바꿔줘" / "더 두껍게" / "다크모드로" → 즉시 재생성 + 파일 덮어쓰기

---

## 11. 자기검증 (내부용, 출력 안 함)

**이미지 프롬프트:**
- [ ] 주제가 구체적 (모호한 형용사 없음)
- [ ] 스타일/분위기 키워드 충돌 없음
- [ ] 도구별 규칙 준수
- [ ] 비율이 용도에 적합
- [ ] 프롬프트 길이 40~120단어 (MJ 기준)

**SVG:**
- [ ] viewBox 기준 맞음
- [ ] 라이트/다크 대비 충분
- [ ] 파일 저장 + VSCode 오픈 실행했는가

---

## 12. --update 모드 (스킬 자동 패치)

`/drawing --update` 호출 시 실행. 이미지 생성 없이 스킬 자체를 업데이트한다.

### Step 1 — 최신 리서치 파일 읽기

```
mcp__obsidian-vault__search_notes(query="drawing-skill-update", limit=5)
```

날짜 기준 가장 최신 파일을 선택 후 전체 내용 읽기:
```
mcp__obsidian-vault__read_note(path="10-knowledge/research/drawing-skill-update_YYYY-MM-DD.md")
```

### Step 2 — 자동 패치 (확인 없이 즉시 적용)

아래 항목은 리서치 내용 기준으로 **즉시 자동 수정**:

| 자동 패치 대상 | 예시 |
|---|---|
| 모델 버전 문자열 | `V7` → `V8`, `Niji 7` → `Niji 8` |
| 파라미터 범위/기본값 | `--s 0~1000` 범위 변경 |
| 파라미터 추가 | 새 파라미터 행을 테이블에 삽입 |
| 파라미터 삭제/deprecated | 테이블에서 제거 또는 ~~취소선~~ 표기 |
| 날짜 표기 | `(2026-03)` → 최신 날짜로 갱신 |
| 출시 날짜 | "2026-03-17 출시" 등 날짜 업데이트 |

### Step 3 — 검토 제안 (수동 확인 필요)

구조 변경이 필요한 항목은 자동 적용하지 않고 제안만:

```
## --update 완료

### 자동 패치됨
- V8 Alpha → V8 (정식 출시)
- --q 파라미터 최대값 4 → 8로 변경
- --sw 기본값 100 → 250으로 변경

### 검토 필요 (직접 반영 여부 결정)
① Firefly Image 5 출시 — 섹션 전면 개편 필요
   → "반영해줘" 하면 즉시 적용

② Nanobanana Pro 프롬프트 구조 변경
   → 기존 예시가 구버전. 새 예시로 교체 필요
   → "반영해줘" 하면 즉시 적용

리서치 원본: vault/10-knowledge/research/drawing-skill-update_YYYY-MM-DD.md
```

### 리서치 파일 없을 때

```
아직 리서치 파일이 없어요.
크론은 매월 1일 09:30에 실행돼요. (다음 실행: {다음 날짜})
지금 바로 리서치하려면: bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini "Midjourney, Firefly, Nanobanana 최신 업데이트 조사" "drawing-skill-update-manual"
```

---

## 13. 세션 종료 & 연계 제안

결과물 출력 후 아래 형식으로 연계 제안을 반드시 표시한다.
결과물 성격에 따라 관련 높은 항목을 1~2개 강조 (모두 나열하지 않음).

```
완성! {이미지: 도구에서 붙여넣어 사용 / SVG: Desktop/Drawing/ 폴더 확인}

이어서 진행할까요?
{결과물 성격에 맞는 제안 1~2개 선택해서 표시}
```

**결과물별 연계 제안 선택 기준:**

| 결과물 | 우선 제안 | 보조 제안 |
|---|---|---|
| 일러스트 / 컨셉아트 | ✏️ `/writing` — 이 이미지를 소재로 에세이·단편 써보기 | 🎵 `/music` — 이 분위기로 음악 프롬프트 만들기 |
| 사진풍 / 인물 | ✏️ `/writing` — 이 장면을 묘사하는 짧은 글 써보기 | — |
| 로고 / 아이콘 | 📱 `/drawing --mobile` — 이 브랜드로 UI 목업 만들기 | ✏️ `/writing` — 브랜드 카피 써보기 |
| UI 화면 (Stitch) | ✏️ `/writing` — 이 화면의 카피·설명 텍스트 써보기 | — |
| 다이어그램 / 플로우차트 | ✏️ `/writing` — 이 구조를 설명하는 기술문서 써보기 | — |
| 시네마틱 / 분위기 이미지 | 🎵 `/music` — 이 장면에 어울리는 OST 프롬프트 만들기 | ✏️ `/writing` — 이 장면을 소설 도입부로 써보기 |
