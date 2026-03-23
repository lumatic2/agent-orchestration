// Template B: Modern Report (모던 리포트 스타일)
// 1단, 컬러 헤딩, 사이드바 라인, 깔끔한 산세리프

#let accent = rgb("#1a56db")
#let lightbg = rgb("#f0f4ff")

#let paper(
  title: "",
  abstract: "",
  body
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 3cm, bottom: 3cm, left: 3cm, right: 3cm),
    numbering: "1",
    header: context {
      if counter(page).get().first() > 1 {
        text(size: 8pt, fill: rgb("#888888"))[
          #title
          #h(1fr)
          #counter(page).display()
        ]
        line(length: 100%, stroke: 0.3pt + rgb("#cccccc"))
      }
    },
  )
  set text(font: ("Apple SD Gothic Neo", "Helvetica", "Helvetica"), size: 10.5pt, lang: "ko")
  set par(justify: true, leading: 0.8em, spacing: 1.2em)

  // Title section
  block(
    width: 100%,
    fill: accent,
    inset: (x: 2cm, y: 1.2cm),
    radius: (top-left: 4pt, top-right: 4pt),
  )[
    #text(size: 22pt, weight: "bold", fill: white)[#title]
    #v(0.3cm)
    #text(size: 9pt, fill: rgb("#c8d8ff"))[
      Research Report · #datetime.today().display("[year].[month].[day]")
    ]
  ]

  // Abstract
  if abstract != "" {
    block(
      width: 100%,
      fill: lightbg,
      inset: (x: 2cm, y: 0.8cm),
      radius: (bottom-left: 4pt, bottom-right: 4pt),
    )[
      #text(size: 9pt, fill: accent, weight: "bold")[ABSTRACT]
      #v(0.2cm)
      #text(size: 10pt)[#abstract]
    ]
  }

  v(1cm)
  body
}

#show heading.where(level: 1): it => {
  v(1em)
  stack(
    dir: ltr,
    spacing: 0.5em,
    rect(width: 4pt, height: 1.2em, fill: accent, radius: 2pt),
    text(size: 13pt, weight: "bold", fill: accent)[#it.body],
  )
  v(0.4em)
}

#show heading.where(level: 2): it => {
  v(0.6em)
  text(size: 11pt, weight: "bold", fill: rgb("#333333"))[#it.body]
  line(length: 100%, stroke: 0.5pt + rgb("#dddddd"))
  v(0.2em)
}

// ── 미리보기용 샘플 콘텐츠 ──
#paper(
  title: "대규모 언어 모델의 교차 검증 기법에 관한 체계적 연구",
  abstract: "본 연구는 대규모 언어 모델(LLM)의 출력 신뢰성을 높이기 위한 다양한 교차 검증 기법을 체계적으로 분석한다. 문헌 조사, 실험 설계, 결과 종합을 통해 핵심 패턴을 도출하였으며, 실용적 적용 방안을 제시한다.",
)[

= 서론

인공지능 연구에서 언어 모델의 신뢰성 검증은 핵심 과제로 부상하고 있다. 특히 다중 모델 파이프라인 환경에서 출력 간의 일관성을 확보하는 방법론적 접근이 요구된다.

본 연구는 세 가지 핵심 질문을 중심으로 진행된다. 첫째, 현존하는 교차 검증 기법의 유형과 효과는 어떠한가. 둘째, 각 기법의 적용 조건과 한계는 무엇인가. 셋째, 실용적 구현 전략은 어떻게 설계할 수 있는가.

== 연구 배경

최근 GPT-4, Claude, Gemini 등 대형 언어 모델이 다양한 산업에 도입되면서 출력 품질 보증의 중요성이 부각되고 있다. 단일 모델 의존도를 낮추고 복수 모델의 출력을 비교·검증하는 체계가 필요하다.

= 관련 연구

앙상블 기반 검증 연구들은 다수결 투표 방식을 중심으로 발전해왔다. Wang et al.(2023)은 자기일관성 기법을 통해 산술 추론 과제에서 정확도를 17% 향상시켰다.

Chain-of-Thought 프롬프팅은 중간 추론 단계를 명시화함으로써 검증 가능성을 높이는 접근법이다. 이 방법론은 복잡한 추론 과제에서 특히 효과적임이 입증되었다.

= 방법론

본 연구는 혼합 방법론 접근을 채택하였다. 정량적 벤치마크 분석과 정성적 사례 연구를 병행하여 종합적 관점을 확보하였다.

== 실험 설계

실험은 세 단계로 구성된다. 1단계에서는 기존 검증 기법을 분류하고 평가 기준을 수립한다. 2단계에서는 통제된 환경에서 각 기법을 비교 실험한다. 3단계에서는 실제 파이프라인 환경에서 적용 가능성을 검증한다.

= 연구 결과

실험 결과, 앙상블 기반 접근법이 단일 모델 대비 평균 23%의 정확도 향상을 보였다. 특히 추론 집약적 과제에서 그 효과가 두드러졌으며, 단순 분류 과제에서는 개선 효과가 제한적이었다.

= 결론

본 연구는 LLM 교차 검증 기법의 체계적 비교 분석을 통해 실용적 지침을 제시하였다. 향후 연구는 계산 효율성 개선과 도메인 특화 검증 방법론 개발에 집중해야 한다.

]
