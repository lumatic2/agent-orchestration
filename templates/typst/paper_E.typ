// Template E: Essay (에세이/브런치)
// 명조체, 넓은 행간, 문학적 타이포그래피, heading 숨김
#let conf(
  title: "",
  abstract: [],
  doc,
) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 25mm, bottom: 25mm, left: 35mm, right: 35mm),
    numbering: "1",
    number-align: center,
  )
  set text(font: ("NanumMyeongjo", "Batang", "AppleMyungjo", "Noto Serif CJK KR", "Georgia"), size: 11pt, lang: "ko")
  set par(leading: 1.8em, first-line-indent: 0em, spacing: 0.8em, justify: true)
  show heading: none

  // Title
  align(center)[
    #text(size: 20pt, weight: "bold")[#title]
    #v(0.6em)
  ]

  // Subtitle (abstract as subtitle)
  if abstract != [] {
    align(center)[
      #text(size: 13pt, style: "italic", fill: rgb("#555555"))[#abstract]
    ]
  }

  v(1.2em)
  align(right)[
    #text(size: 10pt, fill: rgb("#666666"))[luma]
    #linebreak()
    #text(size: 10pt, fill: rgb("#666666"))[#datetime.today().display("[year]-[month]-[day]")]
  ]
  v(1.4em)

  doc
}
