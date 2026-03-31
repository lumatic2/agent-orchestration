// Template A: Academic (학술 표준)
// 2단 컬럼, 회색 초록 박스, IEEE/학술지 스타일
#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 2.5cm, bottom: 2.5cm, left: 2cm, right: 2cm),
    numbering: "1",
    number-align: center,
  )
  set text(font: ("NanumMyeongjo", "Batang", "AppleMyungjo", "Noto Serif CJK KR", "Georgia"), size: 10pt, lang: "ko")
  set par(justify: true, leading: 0.85em, spacing: 2.2em, first-line-indent: 1em)
  set heading(numbering: "1.1")

  // Title block
  align(center)[
    #block(width: 100%)[
      #text(size: 18pt, weight: "bold", font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"))[#title]
      #v(0.3cm)
      #text(size: 9pt, fill: rgb("#555555"))[자율 연구 파이프라인 · #datetime.today().display("[year]년 [month]월 [day]일")]
      #v(0.2cm)
      #line(length: 100%, stroke: 0.5pt + rgb("#333333"))
    ]
  ]

  // Abstract
  v(0.4cm)
  block(
    width: 100%,
    fill: rgb("#f5f5f5"),
    inset: (x: 1cm, y: 0.6cm),
    radius: 2pt,
  )[
    #text(weight: "bold", size: 9pt)[초록 — ]
    #text(size: 9pt)[#abstract]
  ]
  v(0.5cm)

  // Two-column body
  columns(2, gutter: 0.8cm)[
    #doc
  ]
}

#show heading.where(level: 1): it => {
  v(0.5em)
  text(size: 11pt, weight: "bold", font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"))[
    #counter(heading).display("1.") #it.body
  ]
  v(0.2em)
}
#show heading.where(level: 2): it => {
  v(0.3em)
  text(size: 10pt, weight: "bold", style: "italic")[
    #counter(heading).display("1.1") #it.body
  ]
  v(0.1em)
}
