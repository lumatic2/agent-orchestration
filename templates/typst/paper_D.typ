// Template D: Tech Dark (테크 다크)
// 다크 헤더, 라이트 바디, 파란 액센트
#let dark = rgb("#1e1e2e")
#let accent = rgb("#89b4fa")
#let subtext = rgb("#6c7086")

#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 0cm, bottom: 2.5cm, left: 0cm, right: 0cm),
    footer: context {
      h(2.5cm)
      text(size: 8pt, fill: subtext)[
        #title #h(1fr) #counter(page).display() #h(2.5cm)
      ]
    },
  )
  set text(font: ("Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR"), size: 10.5pt, lang: "ko")
  set par(justify: true, leading: 0.75em, spacing: 1.1em)

  // Dark header
  block(width: 100%, fill: dark, inset: (x: 2.5cm, y: 1.5cm))[
    #text(size: 8pt, fill: accent, tracking: 2pt)[RESEARCH PAPER]
    #v(0.5cm)
    #text(size: 21pt, weight: "bold", fill: white)[#title]
    #v(0.6cm)
    #text(size: 9pt, fill: subtext)[
      Auto-generated · #datetime.today().display("[year]-[month]-[day]")
    ]
  ]
  // Abstract stripe
  block(width: 100%, fill: rgb("#f8f9fd"), inset: (x: 2.5cm, y: 0.8cm))[
    #set par(first-line-indent: 0em)
    #text(size: 8.5pt, weight: "bold", fill: accent)[▶ ABSTRACT  ]
    #text(size: 9.5pt)[#abstract]
  ]
  // Body with padding
  block(inset: (x: 2.5cm, y: 0.5cm))[
    #doc
  ]
}

#show heading.where(level: 1): it => {
  v(1em)
  box(fill: rgb("#f0f4ff"), inset: (x: 0.6em, y: 0.4em), radius: 3pt)[
    #text(size: 12pt, weight: "bold", fill: dark)[#it.body]
  ]
  v(0.5em)
}
#show heading.where(level: 2): it => {
  v(0.6em)
  text(size: 10.5pt, weight: "bold", fill: rgb("#334155"))[
    #text(fill: accent)[›] #it.body
  ]
  v(0.2em)
}
