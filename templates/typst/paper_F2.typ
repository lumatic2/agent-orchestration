// Template F2: Corporate / Pro (Dark+Light Alternating)
// Reference: Slidesgo "Elegant Blue" — premium, high-contrast
#let dark = rgb("#252525")
#let accent = rgb("#0043c1")
#let light-accent = rgb("#90ccfa")

#let conf(title: "", abstract: [], doc) = {
  set document(title: title)
  set page(
    width: 25.4cm,
    height: 14.29cm,
    margin: (top: 2cm, bottom: 1.5cm, left: 2.5cm, right: 2.5cm),
    fill: white,
    footer: context align(right,
      text(size: 8pt, fill: rgb("#999999"))[
        #counter(page).display() / #context counter(page).final().first()
      ]
    ),
  )
  set text(
    font: ("Malgun Gothic", "NanumBarunGothic", "Apple SD Gothic Neo", "Noto Sans CJK KR"),
    size: 16pt,
    fill: dark,
    lang: "ko",
  )
  set par(leading: 0.75em, spacing: 0.5em)

  // Title slide — dark background
  page(fill: dark, margin: (top: 0cm, bottom: 0cm, left: 0cm, right: 0cm))[
    #block(width: 100%, height: 100%, inset: (left: 3cm, right: 3cm))[
      #align(left + horizon)[
        #stack(dir: ltr, spacing: 1.2cm,
          rect(width: 5pt, height: 5cm, fill: accent, radius: 2pt),
          [
            #text(size: 44pt, weight: "bold", fill: white)[#title]
            #v(0.6cm)
            #if abstract != [] {
              text(size: 18pt, fill: light-accent)[#abstract]
              v(1cm)
            }
            #text(size: 12pt, fill: rgb("#777777"))[#datetime.today().display("[year]-[month]-[day]")]
          ],
        )
      ]
    ]
  ]

  doc
}

// Section divider — dark slide
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  page(fill: dark, margin: (top: 0cm, bottom: 0cm, left: 0cm, right: 0cm))[
    #block(width: 100%, height: 100%, inset: (left: 3cm, right: 3cm))[
      #align(left + horizon)[
        #stack(dir: ltr, spacing: 1cm,
          rect(width: 5pt, height: 3.5cm, fill: accent, radius: 2pt),
          [
            #context {
              let sec = counter(heading).get().first()
              text(size: 18pt, weight: "bold", fill: light-accent)[#sec.]
            }
            #v(0.3cm)
            #text(size: 36pt, weight: "bold", fill: white)[#it.body]
          ],
        )
      ]
    ]
  ]
}

// Content heading — blue left bar
#show heading.where(level: 2): it => {
  v(0.5cm)
  stack(dir: ltr, spacing: 0.6em,
    rect(width: 3pt, height: 1.1em, fill: accent, radius: 1pt),
    text(size: 22pt, weight: "bold", fill: dark)[#it.body],
  )
  v(0.3cm)
}
