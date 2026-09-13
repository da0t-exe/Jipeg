# Jipeg

Right-click an image, get a lighter one. Jipeg adds a single entry to the Windows
context menu and encodes with Google's [jpegli](https://github.com/google/jpegli):
the same visual quality as an ordinary JPEG, a noticeably smaller file, and a
result that is still a plain `.jpg` opening anywhere.

No application to launch, nothing to configure on the way. One menu entry, a small
progress window in your Windows theme, done.

![The Jipeg progress window](docs/preview.png)

Compression savings depend on the source and settings. JPEG encoding is lossy:
the default aims for high visual quality, not identical pixels. Already optimized
images may offer no useful saving. PNG optimization preserves pixels.

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
- **Metadata handling depends on the output path.** JPEG encoding aims to omit
  source metadata, and supported orientation tags are applied to the pixels.
  PNG optimization uses `oxipng --strip safe`, which may retain rendering-related
  metadata. An unchanged original retains all its metadata. Do not treat Jipeg as
  a verified anonymization tool. Removing a colour profile without a suitable
  colour conversion can also change appearance; non-sRGB inputs need more tests.
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
| **JPEG quality** | libjpeg scale. 90 is the default, targeting high visual quality. JPEG remains lossy; inspect important images before discarding originals. |
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

See [engineering notes](docs/engineering.md) for historical codec measurements,
batch coordination and UI design details. See the [validation matrix](docs/validation.md)
for remaining device tests.

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
src/Jipeg-Imaging.ps1    decoding and image inspection helpers
src/Jipeg-Convert.ps1    conversion orchestration and its progress window
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

**The character in the footer of [the page](https://da0t-exe.github.io/Jipeg/) is
Anthropic's.** It is Clawd, the Claude Code mascot, and it appears there with no
affiliation to Anthropic of any kind — they have not endorsed, reviewed or had
anything to do with Jipeg. `docs/clawd.gif` is three frames lifted from their own
animation and is **not covered by this project's MIT licence**; every other file
here is. If Anthropic would rather it were not there, say so and it goes.


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
