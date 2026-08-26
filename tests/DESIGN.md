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

- **ok** the status dot pulses, 3.2 s, the slowest thing on the page
- **ok** the rail dot grows to 1.6× when its section is in view
- **ok** the bars draw themselves to the length of the reduction they sit under
- **ok** buttons lift 1 px under the cursor and settle on click
- **ok** the headline scrambles once on load and once per language change
- **ok** every one of those is inside `prefers-reduced-motion`
- **fixed** the bar observer watched an element of zero width, which can never
  meet an intersection threshold — it watches the container now
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
