# Jipeg

Right-click an image, get a lighter one. Jipeg adds a single entry to the Windows
context menu and encodes with Google's [jpegli](https://github.com/google/jpegli):
the same visual quality as an ordinary JPEG, a noticeably smaller file, and a
result that is still a plain `.jpg` opening anywhere.

No application to launch, nothing to configure on the way. One menu entry, a small
progress window in your Windows theme, done.

![The Jipeg progress window](docs/preview.png)

| | |
|---|---|
| a photograph | **&minus;90%** |
| a scanned document | **&minus;68%** |
| a transparent logo | **&minus;62%**, and nothing lost at all |
| a JPEG that is already small | left exactly as it was |

**Website:** [da0t-exe.github.io/Jipeg](https://da0t-exe.github.io/Jipeg/)

---

## Install

One line in PowerShell:

```powershell
irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/install.ps1 | iex
```

It fetches the latest release, checks it against the SHA-256 GitHub publishes for
that file, and installs it in the console. On Windows 11 it asks one question,
because the answer restarts Explorer:

```
  Show Jipeg directly in the right-click menu? [y/n] (Enter = yes, 10s)
```

The seconds tick down as you watch. Type your answer and confirm with Enter — a
single key press does nothing on its own, and typing restarts the countdown.
Press Enter alone, or leave it be, and the default applies after ten seconds.

Say yes: otherwise the entry only shows up under **Show more options** (or
Shift + F10). Saying yes restores the classic context menu, which needs Explorer
to restart — the taskbar goes away for a few seconds and any open File Explorer
windows are closed. Say no and Jipeg still installs; it just stays in the second
menu.

Run the file directly with `-ClassicMenu` or `-NoClassicMenu` to answer up front,
or `-Gui` for the setup window. By hand: download the ZIP from
[Releases](https://github.com/da0t-exe/Jipeg/releases/latest), unpack it and run
`src\Install-Jipeg.ps1`.

No administrator rights. Everything stays inside your user profile.

## Uninstall

```powershell
irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/uninstall.ps1 | iex
```

Same question, same countdown, and it answers itself when nobody is at the
keyboard. To skip it entirely:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/uninstall.ps1))) -Yes
```

*Settings → Installed apps → Jipeg* does the same thing. Either way it removes the
context menu entry, the Start menu shortcut, the install folder and — only if the
installer turned it on — the classic context menu tweak. **Converted images are
never touched.**

## Use

Right-click an image → **Convert to JPEG (Jipeg)**.

- Works on a **multiple selection**: one window handles the whole batch.
- Right-click a **folder** to take every image directly inside it.
- The original is **never** modified or deleted. The result is written next to it
  with a `_jipeg` suffix (`photo.png` → `photo_jipeg.jpg`).
- The window shows progress in your Windows accent colour, then the result
  (`697 KB → 214 KB (−69%)`), and waits for you to click **OK**. **Cancel** stops
  the batch after the current file.

## What it refuses to do

This is most of what separates Jipeg from any other converter.

- **It never writes a heavier file.** JPEG is very good at photographs and very
  bad at flat colour and text. Measured on real files, a screenshot grew 88%, a
  diagram 325%, a 64-pixel icon 448%. Those JPEGs are never written: the picture
  is shrunk losslessly instead, and where even that would come out bigger it is
  handed back untouched, with the summary saying how many were left alone.
- **It never flattens transparency onto a background.** A picture with
  see-through pixels is not turned into a JPEG, because JPEG has no alpha channel
  and the only way to make one is to paint something behind the picture. Those
  files are shrunk as PNGs instead, losslessly: the pixels and the alpha channel
  come back byte for byte identical. This holds whichever format the transparency
  arrived in — PNG, WebP, GIF, TIFF, ICO — and the question is asked of the pixels
  rather than the header, so a GIF that declares a transparent palette entry it
  never uses is still encoded as the opaque picture it actually is. Where the
  lossless result would be heavier than the original, the original is kept. A PNG
  that would merely have grown as a JPEG takes the same route rather than
  producing nothing — and so does anything else the chroma measurement calls
  flat colour. A GIF of flat colour used to be handed straight back untouched;
  measured, one of them was giving up 70% by being left alone. A photograph is
  refused that second attempt on purpose: a lossless PNG of one is many times
  the size, and the try would be pure waste.
- **It carries nothing over.** No Exif, no GPS, no camera model, no colour
  profile, no embedded thumbnail. That is the single biggest saving on a phone
  photograph, and it means the file cannot tell anyone where it was taken. The
  rotation a phone asks for is read, applied to the pixels, and then thrown away
  with the rest — upright everywhere, and not one byte heavier.
- **It keeps the original's date**, so a converted folder still sorts by when the
  pictures were taken rather than by when they went through Jipeg.

### The codecs Windows does not come with

Windows reads neither an iPhone photo (`.heic`) nor an `.avif` on its own, and
Jipeg cannot carry what it takes: these are Microsoft Store packages, and the
one a `.heic` needs comes with a patent licence paid per machine.

The console installer asks once, and prints the links rather than opening them:

| | | |
|---|---|---|
| [HEIF Image Extensions](https://apps.microsoft.com/detail/9PMMSR1CGPWG) | `9PMMSR1CGPWG` | free |
| [HEVC Video Extensions from Device Manufacturer](https://apps.microsoft.com/detail/9N4WGH0Z6VHQ) | `9N4WGH0Z6VHQ` | free where the PC maker paid for it |
| [AV1 Video Extension](https://apps.microsoft.com/detail/9MVZQVXJBQ9V) | `9MVZQVXJBQ9V` | free |

**A `.heic` needs the first two together** — the HEIF package reads the
container, and the picture inside it is HEVC-coded. An `.avif` needs only the
third.

Answer up front with `-Codecs` or `-NoCodecs`, the same way `-ClassicMenu` and
`-NoClassicMenu` work. Opening the three pages was tried first and dropped: the
Store navigates a single window, so three in a row leave only the last one
showing, whatever pause sits between them — measured, not assumed.

## Settings

**Start menu → Jipeg Settings.** A small window, opened only when you want it.

![The Jipeg settings window](docs/settings.png)

| Setting | What it does |
|---|---|
| **JPEG quality** | libjpeg scale. 90 is the default and is exactly distance 1.0, jpegli's own definition of visually lossless. |
| **Colour detail** | *Follow the source* asks two questions rather than guessing from the file type. Does the content need full colour — measured from the density of hard colour transitions, which is what 4:2:0 destroys: photographs score 0.00%, a photograph with a line of coloured text over it 0.10%, a screenshot 3.48%. And can the source even have it — a JPEG states its sampling in its own frame header, and a lossy WebP is 4:2:0 inside whatever it looks like. |
| **Language** | Ten of them: English, Français, Español, Deutsch, Português, Italiano, Polski, Русский, 日本語, 中文. *Automatic* follows the Windows display language and falls back to English. The right-click entry is renamed too — the shell keeps its own copy of that wording in the registry, so changing the language goes back and rewrites all twenty-three keys. |
| **Theme** | Follow Windows, or force Light or Dark. |
| **Translucent window background (Mica)** | The Windows 11 material, on by default. It shows only in the space between the cards; the surfaces on top of it are opaque and measure exactly the colours they were given. |
| **Close the window automatically** | Off by default, so the result stays until you dismiss it. |
| **Install new versions quietly** | Once a day, after a conversion and never during one, Jipeg looks for a newer release and installs it without showing anything. Only from this repository, only a strictly higher version, and only if the archive matches the SHA-256 GitHub publishes for it. Turn it off and nothing is fetched. |
| **Check for updates** | The window also checks when it opens, without blocking. If a newer release exists the button becomes *Update* and installs it on the spot. |

## Formats

| | |
|---|---|
| **Read by the encoder itself** | PNG, JPEG, JXL, PPM/PNM/PGM/PAM/PFM |
| **Decoded first, then encoded** | BMP, TIFF, ICO, EMF, WMF, GIF, APNG — through Windows' own imaging. Animated files keep their first frame. |
| **WebP** | Decoded by `dwebp.exe`, libwebp's own tool, shipped with Jipeg. Nothing already on a Windows machine reads WebP: `cjpegli` refuses it, GDI+ never knew it, and Windows only decodes it if someone installed the Store extension. An **animated** WebP goes through `webpmux.exe` first, which lifts out the first frame. |
| **CMYK JPEG** | Four-component JPEGs, the kind print workflows produce, are decoded by Windows. `cjpegli` answers *"Failed to decode input image"* and stops. |
| **HEIC, HEIF, AVIF, JPEG XR** | Handed to Windows, which reads them when the matching codec is installed. Without it you get the name of the one to install rather than a bare failure. The console installer offers to print the links; see below. |

## Linux and macOS

There is an experimental port in [`platform/`](platform/) — the same right-click
entry for GNOME Files, KDE Dolphin, XFCE Thunar and the macOS Finder, following
the same rules. One line on either system:

```bash
curl -fsSL https://raw.githubusercontent.com/da0t-exe/Jipeg/main/platform/install.sh | bash
```

**It has never been run by its author**, who works on Windows: the shell parses
and the property lists are valid XML, and that is the whole of what has been
checked. See [`platform/README.md`](platform/README.md) for where it is most
likely to break.

## Tested, and not tested

Twenty behaviours are checked against a corpus on every change — the formats
above, a transparent PNG, a grey one, a rotated photograph, a file that would
grow, an empty file, a truncated one, a JPEG saved under a `.png` name, a
read-only source and a name full of accents and spaces. A wider run of 48 adds
the eight Exif orientations one at a time, a 16-bit PNG, an interlaced one,
2000×40 and 37×1301, transparency arriving as WebP, GIF, TIFF and ICO, a name
in Japanese, one 130 characters long, and a file already carrying the
`_jipeg` suffix. Alongside them:
the settings migration (7 cases), the Exif orientation reader (7), the JPEG
frame-header reader (5), the timeout guard, the stale-lock rule, the update
round trip and a full uninstall-reinstall cycle. The window's geometry is
measured rather than looked at: all four corners of every rounded shape come out
identical to the byte.

**All of it on one machine**: Windows 11 build 26100, one screen at 100%
scaling, dark theme, one accent colour, French as the system language.

What that leaves untested, in plain terms:

| | |
|---|---|
| **HEIC, HEIF, AVIF, JPEG XR** | Never actually decoded. The codecs are not installed here, so only the message naming the missing one is verified. |
| **Display scaling** | Only simulated, with `JIPEG_SCALE`. The layout has never been seen on a real 125% or 150% screen. |
| **Linux and macOS** | Never executed at all. See [`platform/README.md`](platform/README.md). |
| **Other Windows** | No other build, no other system language, no other accent colour, no touch. |
| **A second screen at a different scale** | Known limitation rather than an untested guess: the scale and the height it has to fit into are both read from the *primary* screen, once, before any window exists. On a laptop at 150% beside an external screen at 100%, a window opening on the second one is sized for the first. Two screens were on hand to find this; both were at the same scale, so the consequence has never been seen. |
| **Somebody else's machine** | No antivirus, no managed or corporate policy, no SmartScreen prompt as a stranger would see it. |
| **The nine translations** | Every string was measured against the box it has to fit in, so nothing is cut off. None of them has been read by a native speaker. |

The two bugs that mattered most — PNGs coming out heavier, and WebP — were found
by somebody else running it, not by any of the above. That is the honest measure
of what this covers.

## When something goes wrong

Jipeg keeps a log at `%LOCALAPPDATA%\Jipeg\jipeg.log`. One line per event: what
the machine was (Windows build, display scaling, theme, the settings in force),
every file that failed and why, and a summary of every batch. It is capped at
128 KB and trimmed back to its last 200 lines.

It exists for one situation, which has already happened: somebody else runs
Jipeg, something goes wrong, and there is otherwise nothing at all to look at.
If you are reporting a problem, send that file.

## Worth knowing

- **Re-encoding an already compressed JPEG usually makes it bigger.** jpegli
  shines on uncompressed sources (PNG, TIFF) or high-quality JPEGs. When it would
  grow a file, Jipeg writes nothing and says so.
- **GIF and APNG never actually worked before 2.1.** `cjpegli` lists them as input
  formats and does read them, then fails at the encode step — measured on a plain
  100×100 static GIF and on a two-frame APNG, both answered *"jpegli encoding
  failed"*. They are decoded by Windows now. An animated PNG usually calls itself
  `.png`, so the file's own header is checked for an `acTL` chunk rather than
  trusting the extension.
- **A grey picture is encoded as one channel, not three.** A scanned page, a
  diagram or a black and white photograph is often stored in RGB with all three
  channels identical. Encoding those as greyscale takes 8% off, and loses nothing
  that was ever there.
- Files are encoded one at a time; the window stays responsive throughout.

---

## Under the hood

| | |
|---|---|
| Installed in | `%LOCALAPPDATA%\Jipeg` |
| Registry keys | `HKCU\Software\Classes\SystemFileAssociations\<ext>\shell\JipegConvert` and `HKCU\Software\Classes\Directory\shell\JipegConvert` |
| Encoder | `cjpegli.exe` from **libjxl v0.11.1** — the last release to ship that binary (v0.12 dropped it, and `google/jpegli` publishes none) |
| Its SHA-256 | `db564007b69b8f038eb4703fc72278c15a992aad9865fa59166735d6fd41b740` |
| WebP | `dwebp.exe` and `webpmux.exe` from **libwebp 1.5.0**, the WebM project's own Windows build |
| PNG shrinker | `oxipng.exe` **10.2.0**, its own Windows build, MIT |
| UI | PowerShell 5.1 + WinForms, standard Windows controls, light and dark followed automatically |

The binaries are committed so the ZIP is installable as-is. If one is missing, the
installer downloads the official archive and **verifies its SHA-256** before
extracting.

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

## Layout

```
install.ps1              one-line installer, fetches the latest release
uninstall.ps1            one-line uninstaller
bin/cjpegli.exe          the jpegli encoder (+ component licences)
bin/dwebp.exe            libwebp's WebP decoder
bin/webpmux.exe          pulls the first frame out of an animated WebP
bin/oxipng.exe           shrinks a PNG without changing a pixel
docs/index.html          the website
src/Jipeg-Common.ps1     settings, theming, scaling and Win32 helpers
src/Jipeg-Convert.ps1    the converter and its progress window
src/Jipeg-Settings.ps1   the settings window
src/Jipeg-Update.ps1     the quiet update check
src/Install-Jipeg.ps1    installer (window, or -Silent for deployment)
src/Uninstall-Jipeg.ps1
src/launch.vbs           starts the converter without a console window
src/settings.vbs         starts the settings window without a console window
platform/                Linux and macOS, experimental and untested
```

## Tests

Everything claimed above was measured by something in [`tests/`](tests) — 48
files with their outcome written down before anything runs, a few hundred random
and byte-flipped ones checked against rules rather than expected answers, and
the install run in a loop with the registry compared each time. [`tests/README.md`](tests/README.md)
says what each one does and what it needs.

## Contributing a translation

Jipeg speaks English, Français, Español, Deutsch, Português, Italiano, Polski,
Русский, 日本語 and 中文. Nine of those were written without a native speaker
ever reading them back, so some lines are almost certainly stiff, stilted, or
plain wrong.

One line is worth reporting. [Open a translation
issue](https://github.com/da0t-exe/Jipeg/issues/new?template=translation.yml) —
it asks what the line says, what it should say, and nothing else. A pull request
against [`src/lang/`](src/lang) is just as welcome; each language is one file,
and the English one is the reference every other falls back to.

Two things worth knowing before editing one:

- **Never use a curly apostrophe.** PowerShell treats `‘` and `’` as string
  delimiters, so a single one inside a value stops the whole file parsing. Plain
  `'` doubled — `''` — is how an apostrophe is written.
- **Every string is measured against the box it sits in.** A label column is 176
  design units wide, a hint 442 to 468, the update button 152. Six strings had to
  be shortened before all ten languages fit. If a line is cut off on screen, that
  is a bug on this side and worth a screenshot.

## Credits and licences

- The encoding is done by **[jpegli](https://github.com/google/jpegli)**, a Google
  project, shipped here as the `cjpegli.exe` binary built by
  **[libjxl](https://github.com/libjxl/libjxl)**. Jipeg is not affiliated with
  Google or the libjxl project and does not modify their code.
- WebP input is decoded by **[libwebp](https://github.com/webmproject/libwebp)**'s
  `dwebp` and `webpmux`, taken from the WebM project's own Windows release.
- PNGs are shrunk by **[oxipng](https://github.com/oxipng/oxipng)**, MIT licensed,
  taken from its own Windows release.
- The icon is drawn from the **JPEG format mark** — a square with its corner taken
  out and the removed piece set beside it. Jipeg is not affiliated with or
  endorsed by the JPEG committee.
- Third-party licences: `bin/LICENSE.*` (BSD-3-Clause, Apache-2.0, MIT, zlib and
  others).
- Jipeg itself is MIT licensed — see [LICENSE](LICENSE).
