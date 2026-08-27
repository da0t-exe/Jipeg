# The page, detail by detail

The same idea as [`PLAN.md`](PLAN.md), turned on the site: a tree of every small
thing, so that what is still wrong is as visible as what is right. Marked:

- **ok** — measured, and it holds
- **fixed** — was wrong, corrected, and the measurement now holds
- **no** — still wrong, or never looked at
- **choice** — deliberate, and here is why

`check-design.py` produces the numbers. It reads the colours out of the
stylesheet and computes contrast the way WCAG does, counts the type sizes and
the spacing values, and looks for classes that no longer belong to anything. It
does not have opinions; it has a ruler.

---

## 1. Colour

- **fixed** `--mute` failed the contrast floor on both themes — 3.85:1 on the
  dark page, 3.31:1 on the light one, against 4.5:1 for body text. It is the
  colour of every hint, caption and footer line on the page, which is to say
  most of the small print. Now #7c7c82 and #73737d: 4.77 and 4.54
- **ok** `--ink` 17.4:1, `--dim` 7.6:1, `--accent` 5.0:1 dark and 5.5:1 light
- **ok** every colour is a token on `:root`, redefined once under
  `prefers-color-scheme`, so nothing is hard-coded mid-page
- **choice** the page is dark first and light second, which is the opposite of
  the usual order. It reads better against a screenshot of a dark window
- **no** contrast of the accent against the *panel* rather than the page
- **no** what any of this looks like to someone who cannot separate red from green

## 2. Type

- **fixed** seven sizes, in half-pixel steps: 11, 11.5, 12, 12.5, 13, 13.5,
  14.5. Nobody perceives a half pixel as a decision. Four now — 11, 12, 13,
  14.5 — and each one means something: labels, hints, body of a table or note,
  and the lede
- **ok** one family, the system monospace stack, with real fallbacks
- **ok** prose held to 64 characters; the table and the picture keep the width
- **choice** the headline scales with the viewport (`clamp`) while everything
  else is fixed — it is the only line where size is the point
- **no** line-height is set once on `body` and never revisited for the headline

## 3. Rhythm

- **fixed** spacing ran on 28 different values including 3, 5, 7, 9, 11, 13 and
  15 px, which is not a grid, it is whatever looked right that afternoon. Twenty-two
  now, none of them odd
- **ok** sections all breathe the same: 56 px above and below
- **no** the gap under a heading (28 px) and the gap under a paragraph (16 px)
  were never chosen against each other

## 4. What moves

- **ok** sections rise fourteen pixels and fade in as they arrive, their children
  staggered 70 ms apart, so a section is read top to bottom rather than landing
  as a block
- **ok** the reduction figures count up to their value while the gauge beside
  them stretches — the two say the same thing and arrive together
- **ok** the install command fades out and back when the OS tab changes, so the
  swap is visible instead of the text jumping
- **ok** the copy button pulses once and turns accent-coloured on success
- **ok** the note blocks grow their left border on hover
- **choice** the page opens behind a curtain: the mark, a 160 px track, and a
  percentage in tabular figures. The reference has no loader — it renders
  nothing until it has mounted, then everything arrives at once — so this is a
  deliberate addition rather than a copy. It is also, honestly, a cost: this
  page is one 63 KB file and is ready in about 190 ms, so a curtain adds time
  rather than covering it. What makes it defensible is that it is bounded and
  tells the truth
- **ok** the progress bar advances at the **slower** of two measures: never past
  what has actually loaded, and never past the time elapsed toward the floor.
  The first version took the faster of the two and read 95% at 60 ms, then sat
  there — a bar that is full before it is shown is a decoration pretending to be
  an instrument. Replayed outside the browser on both cases: a fast page gives
  15 steps from 6% to 95% across 450 ms, a slow one is held at 75% at 900 ms by
  the network
- **ok** the curtain cannot stick. It is `hidden` in the markup and only script
  removes that, so no-JS never sees it; reduced motion never unhides it; and a
  hard 2.2 s cap lifts it whatever happens to the network or the events
- **ok** the load is a written sequence rather than a loop. The reference holds
  half a second before moving anything, then walks its elements at 100 ms
  intervals; here the beats are a table read top to bottom — bar 420, status
  600, headline 720, lede 900, tabs 1020, command 1120, note 1240. Measured from
  real page load: 451, 625, 751, 925, 1050, 1151, 1276, every one within about
  30 ms of its mark
- **ok** the overture waits for the curtain instead of running behind it, and
  takes 300 ms off every beat when one has been shown — otherwise the page holds
  twice in a row. Measured end to end: curtain up at 48 ms, gone at 881 ms,
  status 1201, headline 1320, last note 1841
- **ok** `.rev` is applied while the document is still parsing, before first
  paint at 192 ms, so nothing flashes visible and then hides
- **ok** the status dot pulses, 3.2 s, the slowest thing on the page
- **ok** the rail dot grows to 1.6× when its section is in view
- **ok** the bars draw themselves to the length of the reduction they sit under
- **ok** buttons lift 1 px under the cursor and settle on click
- **ok** the headline scrambles once on load and once per language change. The
  reference applies that effect to exactly two elements, both in its own
  headline; here it also runs on the status line and on each section heading as
  the section arrives, 150 ms behind the rise so the two do not compete. Verified
  on Japanese as well as Latin text — the remainder is drawn from the same
  symbol set the reference uses
- **ok** links in the footer and in note blocks draw their underline from the
  left rather than switching it on. Targeted by selector, not by class: those
  links live inside translated strings injected as `innerHTML`, so a class would
  have to be repeated in all ten languages
- **ok** a screenshot lifts three pixels under the cursor
- **ok** every one of those is inside `prefers-reduced-motion`
- **fixed** the bar observer watched an element of zero width, which can never
  meet an intersection threshold — it watches the container now
- **fixed** four ways the new arrival animation could leave the page blank, all
  found by rendering it rather than reading it. `IntersectionObserver` does not
  run in a tab that is not compositing, so eleven elements sat at `opacity:0`
  for good; both observers are one scroll-checked registry now. The check for
  "is it visible" also required `bottom > 0`, so a section already scrolled past
  — arrived at by anchor, or by scrolling fast — was skipped and stayed
  invisible forever. The number counter froze on its first frame in a background
  tab and displayed **−0%** for a 90% reduction. And the hero waited on
  `requestAnimationFrame`, which a background tab never runs
- **fixed** the headline appeared in clear for 250 ms and only then scrambled,
  which is the effect backwards. The decrypt was starting 220 ms after the
  reveal; it starts with it now, so the line materialises already scrambled and
  resolves as it rises. Noise now begins one 25 ms sample after the beat fires
- **fixed** the language applied at load called `scramble()` on its own, so the
  headline started a second time outside the sequence. A flag hands the text to
  the overture and releases it 400 ms after the last beat — checked that a
  language change after that still decrypts
- **ok** the decrypt effect cannot strand text on noise: it refuses to start
  while the document is hidden, a timer rewrites the true string regardless, and
  a run in progress is cancelled before the text is read — otherwise a language
  change mid-animation would take the noise for the truth. Checked by chaining
  three languages inside 380 ms: the headline still landed on the exact Japanese
  string
- **fixed** the first OS tab click did not fade: the flag that suppresses the
  animation during setup was only cleared inside `showOS`, which is never called
  at load on Windows
- **fixed** the rail had no dot lit before the first scroll, which reads as
  broken rather than as waiting

## 5. Behaviour

- **ok** ten languages, the choice remembered, the rail labels following along
- **ok** the OS tabs, and the copy button
- **fixed** a stray line left by an editing script broke the whole page script —
  languages, tabs, copy, all of it — and it shipped twice. `check-site.py` runs
  `node --check` over the script now
- **ok** with JavaScript off: checked, and the claim above was wrong. The
  headline is real text in the markup and the scrambler animates *from* it, so
  nothing is garbled; the install block shows the Windows command and the tabs
  simply do not switch, which is the right thing to degrade to
- **fixed** the whole title bar vanished — logo, language selector, github link.
  I had named the table gauges `.bar`, which the header was already using. Two
  rules, same name, mine second: the header went from `flex; height:56px` to
  `block; height:2px; overflow:hidden` and swallowed everything inside it. The
  gauges are `.meter` now, and the check learned to count a class defined twice
- **fixed** the rail said nothing to a screen reader — a dot growing to 1.6× is
  not information. The current one carries `aria-current` now

## 6. The page as an object

- **ok** one file, no external request of any kind, 57 KB
- **ok** two images, 5.4 KB and 1.2 KB, both at their natural size
- **ok** `alt` on every image, `lang` on `<html>`, `:focus-visible` present
- **fixed** at 360 px the copy button sat at x=609 on a 360 px screen — the
  command refused to shrink and pushed the only useful control in that block off
  the side. The command scrolls now; the button stays put
- **ok** at 360 px: nothing overflows the viewport, no text is clipped, the
  table folds to 159/44/44/65 px and its rows grow from 40 to 56 px to take the
  wrap. Measured, not looked at — the preview pane would not compose a frame
- **no** printed

---

## What the ruler caught that the eye did not

Three of the five things above were invisible to look at and obvious to measure:
the muted grey that fails a contrast floor, seven type sizes where four would
do, and 28 spacing values pretending to be a grid. None of them would have come
up by staring at the page, which is the argument for the file.

The two that the eye did catch — the ghosted GIF and the broken script — were
both found by *rendering* the page rather than reading it, which is the other
half of the argument.

Two near-misses in the curtain work, both caught by asking one more question
instead of writing them up. Twelve elements sat at `opacity:0` after load, which
looked exactly like the reveal bug from earlier — they were the sections below
the fold, which are supposed to wait for a scroll, and scrolling revealed all
21. And a run that showed the curtain lifting at 3.6 s, well past its own 2.2 s
cap, was a throttled background tab rather than a broken timer; the honest way
to settle the progress rule turned out to be replaying it outside the browser.

One near-miss worth recording: the status line and headline appeared not to
animate at all, and the reason was that I was querying the wrong browser tab —
the real page, under reduced motion, where not animating is the correct
behaviour. The reading was right; the question was aimed at the wrong document.

And one that neither caught. Adding the gauges reused a class name the header
already had, and the header collapsed to a two-pixel line. The ruler said the
page was fine, because it only ever asked whether a class was *unused* — never
whether one was defined twice. The user saw it in a second by looking at the
page. Three tries were needed to make the check see it: the first regex wanted a
`}` before the selector and the offending rule followed a comment, so it
reported "none"; the second counted `@media` overrides and accused `.rail`,
which is not a collision but the entire point of a media query. It is checked
both ways now — reintroduce the bug and it exits 1 naming `bar`.
