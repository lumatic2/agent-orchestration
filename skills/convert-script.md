스크립트를 받아서 Remotion 슬라이드 컴포넌트를 생성하고, Studio를 열어라.

$ARGUMENTS 가 비어 있으면 사용자에게 스크립트를 붙여넣어달라고 요청해라.

## 환경 감지

Remotion 프로젝트 경로를 현재 기기에 맞게 결정한다:

- **Windows** (hostname에 `DESKTOP` 포함 또는 OS가 Windows): 로컬 `C:/Users/1/Desktop/유튜브영상`
- **Mac Air / M4 등 다른 기기**: SSH로 Windows에 원격 작업
  - 프로젝트 경로: `ssh windows "cd ~/Desktop/유튜브영상 && ..."`
  - 코드 생성은 로컬 `/tmp/remotion-{ep-id}/`에 먼저 작성 후 `scp`로 전송
  - Studio 실행/렌더링은 `ssh windows`로 실행
  - 브라우저 오픈: `ssh windows "start http://localhost:3002"`

## 시작 전 확인

스크립트를 받으면 AskUserQuestion을 호출해라:
- 질문: "어떤 형식으로 만들까요?" (header: "영상 형식")
- A) 가로 (1920×1080) — 유튜브 일반 영상 (Recommended)
- B) 세로 (1080×1920) — 쇼츠 / 릴스

## 디자인 레퍼런스 로드

형식 확인 후, Codex에 넘기기 전에 vault에서 레퍼런스를 읽어 디자인 컨텍스트를 구성한다.

1. obsidian-vault MCP로 `refs/remotion/index.md` 읽기
2. 읽기 성공하면: 레퍼런스 목록을 Codex 프롬프트의 "디자인 레퍼런스 컨텍스트" 섹션에 포함
3. 읽기 실패(파일 없음)하면: 레퍼런스 없이 진행 (사용자에게 별도 안내 불필요)

Codex 프롬프트에 포함할 형식:
```
## 디자인 레퍼런스 컨텍스트
아래는 Behance에서 수집한 모션 디자인 레퍼런스다.
슬라이드 디자인 시 이 레퍼런스들의 스타일, 구성, 타이포그래피 패턴을 참고해라.
단, 그대로 모방하지 말고 Remotion(CSS/spring 애니메이션)으로 구현 가능한 요소만 추출해 적용해라.

{index.md 내용}
```

사용자 답변에 따라:
- 가로: `width=1920, height=1080` (기본값, registry에 width/height 생략 가능)
- 세로: `width=1080, height=1920`, ep ID에 `-shorts` 접미사 추가

## 영상 ID 결정

스크립트 제목을 기반으로 영상 ID를 만든다:
- 가로 형식: `ep{번호}-{영문-슬러그}` (예: `ep02-morning-routine`)
- 세로 형식: `ep{번호}-{영문-슬러그}-shorts` (예: `ep02-morning-routine-shorts`)
- 번호: `src/videos/` 폴더 안 기존 ep 번호 중 최대값 + 1
- 슬러그: 제목을 영문 소문자 + 하이픈으로 변환

## 슬라이드 생성 규칙

스크립트를 분석해서 **내용에 맞는 슬라이드를 자유롭게 설계**한다.
고정 타입 없음 — 텍스트 강조, 키워드 나열, 대비 구조, 숫자 강조, 인용 등 내용에 최적화된 레이아웃을 직접 디자인한다.

### 공통 규칙
- 슬라이드당 핵심 1~2개만 표시 (나레이션 그대로 넣지 말 것)
- `theme.ts` 값 활용 (fontSize, color, fontFamily 등)
- `ThemeContext`에서 `accentColor` 사용
- `spring` + `interpolate`로 입장 애니메이션 필수
- `AbsoluteFill` 기반, `backgroundColor: theme.backgroundColor`
- `wordBreak: "keep-all"` 한국어 줄바꿈

### 파일 구조 (새 영상마다 독립 폴더)
```
src/videos/{ep-id}/
  Slide1.tsx
  Slide2.tsx
  ...
  slides.ts       ← slides 배열
  Component.tsx   ← YoutubeVideo 래퍼
```

### import 경로 (videos 하위 파일 기준)
```tsx
import { theme } from "../../theme";
import { ThemeContext } from "../../YoutubeVideo";
```

### 각 슬라이드 컴포넌트 형식
```tsx
import React, { useContext } from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../../theme";
import { ThemeContext } from "../../YoutubeVideo";

export const Slide1: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { accentColor } = useContext(ThemeContext);
  // spring 애니메이션 + 레이아웃
  // 텍스트에 반드시 fontVariationSettings: "'wght' 900" 적용 (fontWeight만으로는 굵기 미적용)
};
```

### slides.ts 형식
```ts
import { Slide1 } from "./Slide1";
import { Slide2 } from "./Slide2";

export const slides = [
  { key: "{ep-id}-slide-1", Component: Slide1 },
  { key: "{ep-id}-slide-2", Component: Slide2 },
];
```

### Component.tsx 형식
```tsx
import React from "react";
import { YoutubeVideo } from "../../YoutubeVideo";
import { slides } from "./slides";

export const {ComponentName}: React.FC = () => <YoutubeVideo slides={slides} />;
```
ComponentName: EpXX + 제목 카멜케이스 (예: `Ep02MorningRoutine`)

## registry.ts 업데이트

새 영상을 `src/registry.ts`에 추가한다.
기존 항목은 절대 수정하지 말고, 배열 마지막에 추가:

```ts
import { {ComponentName} } from "./videos/{ep-id}/Component";
import { slides as {epId}Slides } from "./videos/{ep-id}/slides";

// videoRegistry 배열에 추가 (세로 영상이면 width/height 명시):
{
  id: "{ep-id}",
  title: "{영상 제목}",
  component: {ComponentName},
  durationInFrames: getTotalDurationInFrames({epId}Slides.length),
  // 세로 영상일 때만 추가:
  width: 1080,
  height: 1920,
},
```

## 실행 순서

1. `src/videos/` 폴더에서 기존 ep 번호 확인 → 새 ep ID 결정
2. 스크립트 분석 → 슬라이드 수/내용 결정
3. `src/videos/{ep-id}/Slide1.tsx`, `Slide2.tsx` ... 생성
4. `src/videos/{ep-id}/slides.ts` 생성
5. `src/videos/{ep-id}/Component.tsx` 생성
6. `src/registry.ts` 업데이트 (기존 항목 유지, 새 항목 추가)
7. `npx tsc --noEmit` 타입 체크
8. Remotion Studio 백그라운드 실행 (포트 충돌 방지를 위해 항상 kill 후 재실행):

**Windows 로컬:**
```bash
npx kill-port 3002 2>/dev/null; sleep 1 && cd "C:/Users/1/Desktop/유튜브영상" && npx remotion studio --port 3002 &
```

**Mac에서 원격:**
```bash
ssh windows "cd ~/Desktop/유튜브영상 && npx kill-port 3002 2>/dev/null; sleep 1 && npx remotion studio --port 3002 &"
```

9. 브라우저 오픈:

**Windows 로컬:** `start http://localhost:3002`
**Mac에서 원격:** `ssh windows "start http://localhost:3002"`

## 사용자 안내

Studio 사이드바에서 `{ep-id}` Composition 선택 후 미리보기 확인.
렌더링:

**Windows 로컬:**
```bash
cd "C:/Users/1/Desktop/유튜브영상" && npx remotion render {ep-id} "1차영상/{ep-id}.mp4" --color-space=bt709
```

**Mac에서 원격:**
```bash
ssh windows "cd ~/Desktop/유튜브영상 && npx remotion render {ep-id} '1차영상/{ep-id}.mp4' --color-space=bt709"
```
