#let bg = white
#let accent = rgb("#77c6fc")
#let text-main = rgb("#494949")

#let conf(title: "", abstract: [], doc) = {
  set document(title: title)
  set page(
    width: 25.4cm,
    height: 14.29cm,
    margin: (top: 1.4cm, bottom: 1.1cm, left: 1.9cm, right: 1.9cm),
    fill: bg,
    footer: context align(right,
      text(size: 9pt, fill: rgb("#7a7a7a"))[
        #counter(page).display() / #counter(page).final().first()
      ],
    ),
  )
  set text(
    font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"),
    size: 18pt,
    fill: text-main,
    lang: "ko",
  )
  set par(leading: 0.72em, spacing: 0.52em)

  align(center + horizon)[
    #v(1.0cm)
    #text(size: 40pt, weight: "bold", fill: text-main)[#title]
    #v(0.8cm)
    #if abstract != [] {
      text(size: 20pt, fill: accent)[#abstract]
      v(1.0cm)
    }
    #line(length: 38%, stroke: 2.2pt + accent)
    #v(4.2cm)
    #text(size: 14pt, fill: rgb("#8c8c8c"))[#datetime.today().display("[year]-[month]-[day]")]
  ]
  pagebreak()

  doc
}

#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  align(center + horizon)[
    #context {
      let sec = counter(heading.where(level: 1)).get().first()
      block(
        width: 76%,
        inset: (x: 1.4cm, y: 1.0cm),
        radius: 26pt,
        fill: accent.lighten(35%),
      )[
        #align(center)[
          #text(size: 50pt, weight: "bold", fill: rgb("#3e8ec1"))[#sec]
          #v(0.2cm)
          #text(size: 34pt, weight: "bold", fill: text-main)[#it.body]
        ]
      ]
    }
  ]
  v(0.4cm)
}

#show heading.where(level: 2): it => {
  v(0.15cm)
  text(size: 26pt, weight: "bold", fill: accent)[#it.body]
  v(0.12cm)
  line(length: 100%, stroke: 0.9pt + accent.lighten(25%))
  v(0.22cm)
}
