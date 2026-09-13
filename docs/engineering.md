# Engineering notes

These are historical observations from the original development machine, not
universal compression guarantees. Some original inputs and measurement tools
are not archived; the figures are not independently reproduced by CI.

### Why the files are not smaller still

Every switch `cjpegli` has that changes the size of what it writes has been
measured, along with the two things that can be done to the file afterwards.

| Switch | Effect | Verdict |
|---|---|---|
| `-p 1` / `-p 0` instead of the default `-p 2` | **&minus;1 to &minus;7%** | **taken.** It is free, see below |
| `--std_quant` | +55% | the Annex K tables are far worse than jpegli's own |
| `--noadaptive_quantization` | +1.6% | adaptive quantisation earns its keep |
| `--xyb` | &minus;24% | rejected, see below |
| `--target_size` | hits a size exactly | up to 20× slower, and it targets bytes rather than quality |
| stripping the headers | nothing to strip | `cjpegli` writes no JFIF, no APP14, no comment. What is left is the quantisation and Huffman tables and the frame header: 0.65% of the file, all required |

**The progressive level is a free 1 to 7%.** It decides how the scan data is laid
out in the file and changes nothing whatever about the picture: decoded, `-p 0`,
`-p 1` and `-p 2` give bit-identical pixels, and `ssimulacra2` returns the same
score to eight decimal places. Yet the default of 2 was never the smallest of the
three on anything measured. `-p 1` wins on ordinary pictures; below roughly 20 000
pixels `-p 0` takes over, by 6.8% on a 64-pixel icon. The crossover sits between
120 and 200 pixels wide on both a photograph and a screenshot, so it is not a
property of the content.

**`--xyb` is the tempting one, and it is a trap.** It writes the image in a
different colour space and describes it with a 720-byte ICC profile called
`XYB_Per`. A viewer that applies the profile gets a good picture — average error
1.65 against the original, next to 0.88 for the normal encoding. A viewer that
ignores it gets an average error of **34.78**: visibly wrong colours. Jipeg
promises a plain JPEG that opens anywhere, so it stays off.

**All four chroma modes were measured**, not just the two Jipeg uses, with
`ssimulacra2` and `butteraugli` rather than by eye. On a photograph with a line of
coloured text over it: 4:4:4 scored 86.5 at 84 502 B, 4:4:0 scored 83.6 at
68 485 B, 4:2:2 scored 81.2 at 70 726 B, 4:2:0 scored 80.4 at 69 275 B. **4:2:2 is
dominated everywhere** — bigger than 4:4:0 and worse than it too — so it is never
worth choosing. On a plain photograph 4:2:0 keeps the best quality of the
subsampled three, which is what Jipeg picks.

**JPEG XL was considered and rejected.** `cjxl` repacks an existing JPEG's exact
coefficients losslessly and reversibly — measured at &minus;20.1% and &minus;21.0%
with the original restored byte for byte. But nothing on a stock Windows opens a
`.jxl`: neither GDI+ nor WIC. A file 20% lighter that nobody can open is not
lighter, it is lost.

### Multiple selection

Explorer starts one process per selected file. The first one holds a lock for its
whole life; the others drop their paths into a shared queue and quit. The live
instance picks them up, including after the batch has finished (it resumes), and
if something lands exactly as the window closes it hands those files to a fresh
instance instead of losing them.

A converter that is killed rather than closed leaves that lock file behind, so the
quiet update tests whether anything still *holds* it rather than whether it
exists. Testing for the file meant one crash switched automatic updates off
permanently and silently.

### Why it looks the way it does

Every window uses real Windows controls, so it inherits the system font and the
rounded corners Windows 11 draws itself. What needed doing by hand:

- **Three type sizes, not one.** Section headings, control labels and explanations
  used to share a single size, so everything shouted at the same volume and
  nothing led the eye. Headings are semibold at 11.25 pt, labels 10 pt,
  explanations 8.75 pt, all from the user's own dialog font.
- **Contrast.** Secondary text sits at roughly 7.8:1 against its background — WCAG
  AAA — where the usual dimmed grey lands nearer 5:1.
- **Mica costs nothing, once everything on top of it is opaque.** What DWM lifts
  is the window background, which WinForms erases with no alpha: painted black it
  comes back as `#202020`, or a tinted `#1C2127` over a blue wallpaper, and that
  lift *is* the material showing through. Every surface above it is filled with a
  GDI+ brush, which writes opaque pixels. Two things had to be true: surfaces are
  filled with a brush rather than left to `BackColor`, and a background is written
  with `Clear` *before* antialiasing is switched on — an antialiased
  `FillRectangle` leaves its outermost column only partly covered, and the
  backdrop came through that one-pixel gap as a faint blue line down the left edge
  of every field.
- **The same radius on all four corners, to the byte.** Buttons and cards were
  rounded with a `Region`, which is all-or-nothing per pixel: their four corners
  differed by up to 45 levels out of 255 and the diagonal held two distinct values
  — a staircase, not a curve. Painting the shape fixes that but not GDI+, which
  rasterises right and bottom edges differently from left and top and left a
  residual 14. No geometry helps: rebuilding the shape from a mirrored point set
  gives the same 14 at every point count tried, and supersampling at 8× only
  reached 3. So every rounded shape is drawn into a buffer and its top-left
  quarter mirrored over the other three. Buttons, cards, fields, check boxes and
  the progress bar all measure **0**. Text and glyphs are drawn afterwards,
  straight onto the control, so they keep subpixel rendering — a check mark is not
  symmetric and mirroring would fold it in half.
- **What sits in the corners outside a rounded shape.** Painting them black — the
  colour the material is keyed on — does not work: Windows composites a child
  control opaquely, so each button wore four `#000000` notches against a backdrop
  measuring `#1D2025`. They are filled with the theme's own background instead,
  which lands 5 levels from what the material renders.
- **Display scaling.** The process was DPI-unaware, so on a laptop at 150% Windows
  took the whole window, rendered at 96 DPI, and stretched it. It now asks for
  per-monitor awareness. One factor settles the fonts, every control and every
  radius, and it is settled before a single font exists — deciding it later was a
  bug in itself, with the fonts built at one scale and the layout shrunk to
  another, so at 150% the text overflowed its box and the drop-down below wrote
  over the line above it. The factor is capped by what the screen can hold: the
  settings window is 760 points tall, which is 1140 at 150%, more than a 1080p
  laptop has room for, and OK and Cancel fell off the bottom. Set `JIPEG_SCALE=1.5`
  to see any of this on an ordinary display.
- **Drop-downs are painted, not clipped.** A `ComboBox` draws a pale system border
  and a grey arrow, and ignores the height you give it — always `ItemHeight + 6`,
  here 32 against the 26 the field is drawn at. Clipping it to a rounded region
  came out as a hard staircase, so what shows is a painted face over the real
  control. The face covers it completely: when it did not, the bottom six rows
  showed through as a `#F0F0F0` strip under a white line. The control is lifted by
  that difference so its bottom edge, where Windows hangs the list, lands on the
  bottom of the painted field — and re-aligned after scaling, because its height
  does not grow by the layout's factor and at 150% it stood 21 pixels above its
  field instead of 6.
- **Check boxes are painted here.** No built-in style is presentable in dark mode:
  `Standard` draws a white box when unticked, `Flat` an unreadable light one when
  ticked, and `SetWindowTheme` breaks the control outright. The glyph is drawn
  instead. Its background must stay opaque: left transparent, the control's own
  caption shows through underneath the painted one and the text renders twice.
- **Focus is drawn, not borrowed — and only when Windows would draw it.**
  `ControlPaint.DrawFocusRectangle` paints a hard black dotted box whatever the
  theme. Focus is a thin rounded outline in the accent colour instead, but it asks
  `WM_QUERYUISTATE` first, the same flag every native control obeys: hidden after
  a click, shown after Tab.
- **The progress bar is drawn, not native.** The stock control animates its own
  fill, cannot be recoloured reliably and has a white trough in dark mode. This one
  is a rounded rectangle in a single flat colour that eases toward each new value.
  It never invents progress: only real values are ever targets.
- **The colour is yours.** It comes from the Windows accent palette in the
  registry — a light shade on dark backgrounds, a deeper one on light.

