// Template F3: Project / Proposal (Block Layout, Structured)
// Reference: Slidesgo "Engineering Project Proposal Blue variant"
#let primary = rgb("#556d96")
#let charcoal = rgb("#434343")
#let light-bg = rgb("#c8d2df")

#let conf(title: "", abstract: [], doc) = {
  set document(title: title)
  set page(
    width: 25.4cm,
    height: 14.29cm,
    margin: (top: 0cm, bottom: 0cm, left: 0cm, right: 0cm),
    fill: white,
    footer: context {
      h(2cm)
      text(size: 8pt, fill: rgb("#999999"))[
        #counter(page).display() / #context counter(page).final().first()
      ]
      h(1fr)
      h(2cm)
    },
  )
  set text(
    font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"),
    size: 16pt,
    fill: charcoal,
    lang: "ko",
  )
  set par(leading: 0.7em, spacing: 0.5em)

  // Title slide — left block + right white
  grid(
    columns: (55%, 45%),
    rows: (100%,),
    block(width: 100%, height: 14.29cm, fill: primary, inset: (x: 2.5cm, y: 2cm))[
      #align(left + bottom)[
        #text(size: 36pt, weight: "bold", fill: white)[#title]
        #v(0.6cm)
        #if abstract != [] {
          text(size: 16pt, fill: light-bg)[#abstract]
          v(0.8cm)
        }
        #text(size: 11pt, fill: rgb("#a0b0c8"))[#datetime.today().display("[year]-[month]-[day]")]
      ]
    ],
    block(width: 100%, height: 14.29cm, fill: white)[],
  )
  pagebreak()

  // Body with proper margins
  set page(margin: (top: 1.5cm, bottom: 1.5cm, left: 2.2cm, right: 2.2cm))
  doc
}

// Section divider — left dusty blue block + right area
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  set page(margin: (top: 0cm, bottom: 0cm, left: 0cm, right: 0cm))
  grid(
    columns: (45%, 55%),
    rows: (14.29cm,),
    block(width: 100%, height: 14.29cm, fill: primary, inset: (x: 2cm, y: 2cm))[
      #align(left + horizon)[
        #context {
          let sec = counter(heading).get().first()
          text(size: 72pt, weight: "bold", fill: white.transparentize(60%))[#numbering("01", sec)]
        }
        #v(0.5cm)
        #text(size: 30pt, weight: "bold", fill: white)[#it.body]
      ]
    ],
    block(width: 100%, height: 14.29cm, fill: white)[],
  )
}

// Content heading
#show heading.where(level: 2): it => {
  v(0.4cm)
  text(size: 20pt, weight: "bold", fill: charcoal)[#it.body]
  v(0.15cm)
  line(length: 100%, stroke: 0.5pt + rgb("#cccccc"))
  v(0.25cm)
}
