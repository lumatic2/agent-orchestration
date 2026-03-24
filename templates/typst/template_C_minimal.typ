// Template C: Minimal Elegant (미니멀 엘레강스)
// 넓은 여백, 세리프, 절제된 타이포그래피

#let paper(
  title: "",
  abstract: "",
  body
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 4cm, bottom: 4cm, left: 4cm, right: 4cm),
    numbering: "— 1 —",
    number-align: center,
    footer: context align(center,
      text(size: 8pt, fill: rgb("#999999"))[
        #counter(page).display("— 1 —")
      ]
    ),
  )
  set text(font: ("NanumMyeongjo", "Noto Serif", "Georgia"), size: 11pt, lang: "ko")
  set par(justify: true, leading: 0.9em, spacing: 1.4em, first-line-indent: 1.5em)
  set heading(numbering: none)

  // Minimal title
  v(1cm)
  align(center)[
    #text(size: 20pt, weight: "bold", tracking: -0.5pt)[#title]
    #v(0.8cm)
    #line(length: 3cm, stroke: 0.8pt)
    #v(0.5cm)
    #text(size: 9pt, fill: rgb("#777777"), tracking: 1pt)[
      #upper[Research · #datetime.today().display("[year]")]
    ]
  ]
  v(1.5cm)

  // Abstract
  if abstract != "" {
    align(center)[
      #block(width: 85%)[
        #set par(first-line-indent: 0em)
        #text(size: 9.5pt, style: "italic", fill: rgb("#444444"))[#abstract]
      ]
    ]
    v(1.5cm)
    line(length: 100%, stroke: 0.3pt + rgb("#cccccc"))
    v(1cm)
  }

  body
}

#show heading.where(level: 1): it => {
  v(1.5em)
  align(center)[
    #text(size: 12pt, weight: "bold", tracking: 0.5pt)[
      #upper[#it.body]
    ]
  ]
  v(0.8em)
}

#show heading.where(level: 2): it => {
  v(0.8em)
  text(size: 11pt, weight: "bold", style: "italic")[#it.body]
  v(0.3em)
}

// ── 미리보기용 샘플 콘텐츠 ──
#paper(
  title: "대규모 언어 모델의 교차 검증 기법에 관한 체계적 연구",
  abstract: "본 연구는 대규모 언어 모델(LLM)의 출력 신뢰성을 높이기 위한 다양한 교차 검증 기법을 체계적으로 분석한다. 문헌 조사, 실험 설계, 결과 종합을 통해 핵심 패턴을 도출하였으며, 실용적 적용 방안을 제시한다.",
)[

= 서론

인공지능 연구에서 언어 모델의 신뢰성 검증은 핵심 과제로 부상하고 있다. 특히 다중 모델 파이프라인 환경에서 출력 간의 일관성을 확보하는 방법론적 접근이 요구된다.

본 연구는 세 가지 핵심 질문을 중심으로 진행된다. 첫째, 현존하는 교차 검증 기법의 유형과 효과는 어떠한가. 둘째, 각 기법의 적용 조건과 한계는 무엇인가. 셋째, 실용적 구현 전략은 어떻게 설계할 수 있는가.

= 관련 연구

앙상블 기반 검증 연구들은 다수결 투표 방식을 중심으로 발전해왔다. Wang et al.(2023)은 자기일관성 기법을 통해 산술 추론 과제에서 정확도를 17% 향상시켰다. 이후 연구들은 이를 확장하여 다양한 도메인에 적용하였다.

Chain-of-Thought 프롬프팅은 중간 추론 단계를 명시화함으로써 검증 가능성을 높이는 접근법이다. 이 방법론은 복잡한 추론 과제에서 특히 효과적임이 입증되었다.

= 방법론

본 연구는 혼합 방법론 접근을 채택하였다. 정량적 벤치마크 분석과 정성적 사례 연구를 병행하여 종합적 관점을 확보하였다.

실험 설계는 세 단계로 구성된다. 1단계에서는 기존 검증 기법을 분류하고 평가 기준을 수립한다. 2단계에서는 통제된 환경에서 각 기법을 비교 실험한다. 3단계에서는 실제 파이프라인 환경에서 적용 가능성을 검증한다.

= 연구 결과

실험 결과, 앙상블 기반 접근법이 단일 모델 대비 평균 23%의 정확도 향상을 보였다. 특히 추론 집약적 과제에서 그 효과가 두드러졌으며, 단순 분류 과제에서는 개선 효과가 제한적이었다.

= 결론

본 연구는 LLM 교차 검증 기법의 체계적 비교 분석을 통해 실용적 지침을 제시하였다. 향후 연구는 계산 효율성 개선과 도메인 특화 검증 방법론 개발에 집중해야 한다.

]
