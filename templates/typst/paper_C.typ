// Template C: Minimal Elegant (미니멀 엘레강스)
// 넓은 여백, 명조체, 절제된 타이포그래피
#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 4cm, bottom: 4cm, left: 4cm, right: 4cm),
    footer: context align(center,
      text(size: 8pt, fill: rgb("#999999"))[#counter(page).display("— 1 —")]
    ),
  )
  set text(font: ("AppleMyungjo", "Batang", "Noto Serif CJK KR", "Palatino Linotype"), size: 11pt, lang: "ko")
  set par(justify: true, leading: 0.9em, spacing: 2.0em, first-line-indent: 0.8em)
  set heading(numbering: none)

  // Title
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
  align(center)[
    #block(width: 85%)[
      #set par(first-line-indent: 0em)
      #text(size: 9.5pt, style: "italic", fill: rgb("#444444"))[#abstract]
    ]
  ]
  v(1.5cm)
  line(length: 100%, stroke: 0.3pt + rgb("#cccccc"))
  v(1cm)
  doc
}

#show heading.where(level: 1): it => {
  v(1.5em)
  align(center)[
    #text(size: 12pt, weight: "bold", tracking: 0.5pt)[#upper[#it.body]]
  ]
  v(0.8em)
}
#show heading.where(level: 2): it => {
  v(0.8em)
  text(size: 11pt, weight: "bold", style: "italic")[#it.body]
  v(0.3em)
}
