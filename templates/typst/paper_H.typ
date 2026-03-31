// Template H: Business (기획서/제안서)
// 표지 + 목차 + 본문, 고딕 기반, 번호 있는 섹션
#let accent = rgb("#1e3a5f")
#let subtle = rgb("#7f8c8d")

#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 2.5cm, bottom: 2.5cm, left: 2.5cm, right: 2.5cm),
    numbering: "1",
    number-align: center,
  )
  set text(font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"), size: 10pt, lang: "ko")
  set par(leading: 1.4em, justify: true, spacing: 1.6em)
  set heading(numbering: "1.1")

  // Cover page
  page(numbering: none, margin: (top: 0cm, bottom: 0cm, left: 0cm, right: 0cm))[
    #block(width: 100%, height: 40%, fill: accent)[
      #align(left + bottom)[
        #pad(x: 3cm, bottom: 2cm)[
          #text(size: 32pt, weight: "bold", fill: white)[#title]
          #v(0.6cm)
          #if abstract != [] {
            text(size: 14pt, fill: rgb("#a8c4e0"))[#abstract]
          }
        ]
      ]
    ]
    #align(left + bottom)[
      #pad(x: 3cm, bottom: 3cm)[
        #text(size: 11pt, fill: subtle)[
          #datetime.today().display("[year]년 [month]월 [day]일")
        ]
        #v(0.3cm)
        #text(size: 11pt, fill: rgb("#555555"))[luma]
      ]
    ]
  ]

  // TOC
  outline(title: "목차", depth: 2)
  pagebreak()

  doc
}

#show heading.where(level: 1): it => {
  v(1em)
  block(
    width: 100%,
    inset: (bottom: 0.4em),
    stroke: (bottom: 2pt + accent),
  )[
    #text(size: 14pt, weight: "bold", fill: accent)[
      #counter(heading).display("1.") #it.body
    ]
  ]
  v(0.4em)
}

#show heading.where(level: 2): it => {
  v(0.6em)
  text(size: 11pt, weight: "bold", fill: rgb("#333333"))[
    #counter(heading).display("1.1") #it.body
  ]
  v(0.2em)
}
