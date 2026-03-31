// Template B: Modern Report (모던 리포트)
// 1단, 파란 헤더 배너, 사이드 액센트 라인
#let accent = rgb("#1a56db")
#let lightbg = rgb("#f0f4ff")

#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 3cm, bottom: 3cm, left: 3cm, right: 3cm),
    numbering: "1",
    header: context {
      if counter(page).get().first() > 1 {
        text(size: 8pt, fill: rgb("#888888"))[
          #title #h(1fr) #counter(page).display()
        ]
        line(length: 100%, stroke: 0.3pt + rgb("#cccccc"))
      }
    },
  )
  set text(font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"), size: 10.5pt, lang: "ko")
  set par(justify: true, leading: 0.8em, spacing: 1.1em)

  // Title banner
  block(width: 100%, fill: accent, inset: (x: 1.5cm, y: 1.2cm), radius: (top: 4pt))[
    #text(size: 22pt, weight: "bold", fill: white)[#title]
    #v(0.3cm)
    #text(size: 9pt, fill: rgb("#c8d8ff"))[
      Research Report · #datetime.today().display("[year].[month].[day]")
    ]
  ]
  // Abstract stripe
  block(width: 100%, fill: lightbg, inset: (x: 1.5cm, y: 0.8cm), radius: (bottom: 4pt))[
    #text(size: 8.5pt, weight: "bold", fill: accent)[ABSTRACT  ]
    #text(size: 9.5pt)[#abstract]
  ]
  v(0.8cm)
  doc
}

#show heading.where(level: 1): it => {
  v(1em)
  stack(dir: ltr, spacing: 0.5em,
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
