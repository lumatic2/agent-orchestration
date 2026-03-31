// Template G: Resume (이력서/CV)
// 2단 느낌, 컴팩트, 깔끔한 구분선
#let accent = rgb("#2c3e50")
#let subtle = rgb("#7f8c8d")

#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 2cm, bottom: 2cm, left: 2.5cm, right: 2.5cm),
  )
  set text(font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"), size: 10pt, lang: "ko")
  set par(leading: 0.7em, spacing: 0.8em, justify: false)

  // Header: name + contact
  block(width: 100%, inset: (bottom: 0.6cm))[
    #text(size: 24pt, weight: "bold", fill: accent)[#title]
    #v(0.3cm)
    #if abstract != [] {
      text(size: 9pt, fill: subtle)[#abstract]
    }
  ]
  line(length: 100%, stroke: 1.5pt + accent)
  v(0.5cm)

  doc
}

// Section heading = bold line
#show heading.where(level: 1): it => {
  v(0.8em)
  text(size: 12pt, weight: "bold", fill: accent, tracking: 0.5pt)[#upper[#it.body]]
  v(0.2em)
  line(length: 100%, stroke: 0.5pt + rgb("#bdc3c7"))
  v(0.3em)
}

// Subsection = role/company
#show heading.where(level: 2): it => {
  v(0.4em)
  text(size: 10.5pt, weight: "bold")[#it.body]
  v(0.1em)
}
