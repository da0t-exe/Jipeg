# Jipeg

Convert an image to JPEG from the **right-click menu**, using Google's
[jpegli](https://github.com/google/jpegli) encoder: same visual quality as an ordinary JPEG,
noticeably smaller file, and the result is still a plain `.jpg` that opens anywhere.

No application to launch and nothing to configure on the way: one context menu entry, a small
progress window in your Windows theme, done.

![The Jipeg progress window](docs/preview.png)

## Install

One line in PowerShell:

```powershell
irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/install.ps1 | iex
```

It fetches the latest release, checks it against the SHA-256 GitHub publishes for
that file, and installs it in the console — no setup window. On Windows 11 it asks
one question, because the answer restarts Explorer:

```
  Show Jipeg directly in the right-click menu? [y/n] (Enter = yes, 10s)
```

The seconds tick down as you watch. Type your answer and confirm with Enter — a
single key press does nothing on its own, and typing restarts the countdown.
Press Enter alone, or leave it be, and the default applies after 10 seconds.
Run the file directly with `-ClassicMenu` or `-NoClassicMenu` to answer up front,
or `-Gui` for the setup window.

Or by hand:

1. Download the ZIP from [Releases](https://github.com/da0t-exe/Jipeg/releases/latest) and unpack it.
2. Double-click **`Install.bat`**.
3. Click **Install**.

No administrator rights. Everything stays inside your user profile.

On Windows 11, say yes: otherwise the entry only shows up under **Show more options**
(or Shift + F10). Saying yes restores the classic context menu, which needs Explorer to
restart — the taskbar goes away for a few seconds and any open File Explorer windows are
closed. Say no and Jipeg still installs; it just stays in the second menu.

## Use

Right-click an image → **Convert to JPEG (Jipeg)**.

- Works on a **multiple selection**: one window handles the whole batch.
- Right-click a **folder** to take every image inside it.
- The original is **never** modified or deleted. The result is written next to it with a
  `_jipeg` suffix (`photo.png` → `photo_jipeg.jpg`).
- The window shows progress in your Windows accent colour, then the result
  (`697 KB → 214 KB (−69%)`), and waits for you to click **OK**. **Cancel** stops the batch
  after the current file.

## Settings

**Start menu → Jipeg Settings.** A small window, opened only when you want it:

![The Jipeg settings window](docs/settings.png)

| Setting | What it does |
|---|---|
| **JPEG quality** | libjpeg scale. 90 is the default; 75 is light enough for the web, 96 is close to lossless. |
| **Colour detail** | *Follow the source* (default) reads what the original actually has and matches it: a lossless source keeps full colour, and a JPEG is re-encoded with the sampling stated in its own frame header. *Always full (4:4:4)* and *Smaller files (4:2:0)* force one or the other. |
| **Theme** | Follow Windows, or force Light or Dark. |
| **Translucent window background (Mica)** | The Windows 11 Mica material behind the windows, on by default. It shows only in the space between the cards; the surfaces on top of it are opaque and measure exactly the colours they were given. Ignored when the theme is forced to the opposite of the Windows one. |
| **Close the window automatically** | Off by default, so the result stays until you dismiss it. |
| **Install new versions quietly** | Once a day, after a conversion and never during one, Jipeg looks for a newer release and installs it without showing anything. Only from this repository, only a strictly higher version, and only if the archive matches the SHA-256 GitHub publishes for it. Turn it off and nothing is fetched. |
| **Check for updates** | The settings window also checks when it opens, without blocking. If a newer release exists the button becomes *Update* and installs it on the spot — the same download, checksum and silent install the daily check uses, just without waiting for tomorrow. |

## Supported formats

PNG, APNG, JPEG, GIF, JXL, PPM/PNM/PGM/PAM/PFM directly;
BMP, TIFF and ICO through an automatic intermediate conversion.

WebP is not supported — `cjpegli` cannot read it.

## Worth knowing

- **Re-encoding an already compressed JPEG can make it bigger.** jpegli shines on
  uncompressed sources (PNG, TIFF) or high-quality JPEGs. When the result grows, the summary
  says so with a `+`: the number shown is always the real one.
- Metadata (EXIF, ICC profile) is not carried over by `cjpegli`. For a photograph taken on a
  phone this includes the orientation tag, so a picture that was stored rotated comes back the
  way it was actually captured.
- `cjpegli` encodes 4:4:4 unless told otherwise, so **Colour detail** now names the sampling in
  both directions. Until 1.9.0 it only ever passed the flag to ask for 4:4:4, which is the
  default anyway — the setting produced the same image whichever way it was set.
- Files are encoded one at a time; the window stays responsive throughout.

## Uninstall

**`Uninstall.bat`**, or *Settings → Installed apps → Jipeg*.

Removes the context menu entry, the Start menu shortcut, the install folder and — only if the
installer turned it on — the classic context menu tweak. Converted images are left alone.

## Under the hood

| | |
|---|---|
| Installed in | `%LOCALAPPDATA%\Jipeg` |
| Registry keys | `HKCU\Software\Classes\SystemFileAssociations\<ext>\shell\JipegConvert` and `HKCU\Software\Classes\Directory\shell\JipegConvert` |
| Encoder | `cjpegli.exe` from **libjxl v0.11.1** — the last release to ship that binary (v0.12 dropped it, and `google/jpegli` publishes none) |
| Binary SHA-256 | `db564007b69b8f038eb4703fc72278c15a992aad9865fa59166735d6fd41b740` |
| UI | PowerShell 5.1 + WinForms, standard Windows controls, light/dark theme followed automatically |

The binary is committed so the ZIP is installable as-is. If it is missing, the installer
downloads the official libjxl v0.11.1 archive from GitHub and **verifies its SHA-256** before
extracting `cjpegli.exe`.

### Multiple selection

Explorer starts one process per selected file. The first one holds a lock for its whole life;
the others drop their paths into a shared queue and quit. The live instance picks them up,
including after the batch has finished (it resumes), and if something lands exactly as the
window closes it hands those files to a fresh instance instead of losing them.

### Why it looks the way it does

Every window uses real Windows controls, so it inherits the system font and the rounded
corners Windows 11 draws itself. What needed doing by hand:

- **Three type sizes, not one.** Section headings, control labels and explanations used to
  share a single size, so everything shouted at the same volume and nothing led the eye.
  Headings are now semibold at 11.25 pt, labels 10 pt, explanations 8.75 pt. All three come
  from the user's own dialog font, so they still follow their typeface and DPI.
- **Contrast.** Secondary text sits at roughly 7.8:1 against its background — WCAG AAA —
  where the usual dimmed grey lands nearer 5:1.
- **Mica.** The window background is the translucent Mica material, applied through
  `DWMWA_SYSTEMBACKDROP_TYPE` with the client area extended into the frame. DWM keys the
  glass on black pixels, so the form background is black and labels are transparent. Buttons
  must be `FlatStyle` with their own background, or the themed renderer leaves an opaque halo
  around them. Mica is only used when the chosen theme matches the Windows one, because its
  tint comes from the system setting rather than ours.
- **The progress bar is drawn, not native.** The stock `ProgressBar` animates its own fill,
  cannot be recoloured reliably and has a white trough in dark mode. This one is a rounded
  rectangle in a single flat colour that eases toward each new value instead of snapping to
  it. It never invents progress: only real values are ever targets.
- **The colour is yours.** It comes from the Windows accent palette in the registry — a light
  shade on dark backgrounds, a deeper one on light, the same way Windows picks.
- **Drop-downs are painted, not clipped.** A `ComboBox` draws a pale system border and a grey
  arrow button, and ignores the height you give it — it is always `ItemHeight + 6`, here 32
  against the 26 the field is drawn at. Clipping the control to a rounded region was the first
  attempt and it looked wrong: a region clip is all-or-nothing per pixel, so the corners came
  out as a hard staircase. What shows now is a painted face over the real control, which stays
  underneath only to provide the system list. The face covers it completely — when it did not,
  the bottom six rows of the untouched control showed through as a `#F0F0F0` strip under a
  white line, the pale bar that used to appear below every drop-down — and the control is
  lifted by that difference so its bottom edge, where Windows hangs the list, lands exactly on
  the bottom of the painted field. The list items are owner-drawn so they follow the theme.
- **Check boxes are painted here.** No built-in style is presentable in dark mode: `Standard`
  draws a white box when unticked, `Flat` an unreadable light one when ticked, and
  `SetWindowTheme` breaks the control outright. The glyph is drawn instead — a rounded square,
  accent-filled with a white tick when on. It is still a real `CheckBox`, so focus, Space and
  accessibility keep working. Its background must stay opaque: left transparent, the control's
  own caption shows through underneath the painted one and the text renders twice.
  `NumericUpDown` cannot be darkened at all, which is why quality is a drop-down.
- **Mica costs nothing, once everything on top of it is opaque.** What DWM lifts is the window
  background, which WinForms erases with no alpha: painted black, it comes back as `#202020`,
  or a tinted `#1C2127` over a blue wallpaper — that lift *is* the material showing through,
  and it is the point. Every surface above it is filled with a GDI+ brush, which writes opaque
  pixels: with the backdrop on, a card given `#2B2B2B` measures `#2B2B2B` and a field given
  `#383838` measures `#383838`. Two things had to be true for that. Surfaces are filled with a
  brush rather than left to `BackColor`, or the backdrop shows straight through them. And a
  background is written with `Clear` *before* antialiasing is switched on — an antialiased
  `FillRectangle` leaves its outermost column only partly covered, and the backdrop came
  through that one-pixel gap as a faint blue line, `#383B40` where the surface should have been
  flat `#2B2B2B`, down the left edge of every field.
- **Surfaces are filled with a GDI+ brush** rather than left to `BackColor`, and the labels on
  them are transparent so the surface's own fill shows through — otherwise every line of text
  wears a slightly different rectangle behind it.
- **The same radius on all four corners.** GDI+ samples the right and bottom edges of a path
  differently from the left and top, so a rounded rectangle drawn the obvious way is not
  symmetric: measured across the antialiasing ramps, the four corners of a field differed by up
  to 21 levels out of 255, and the curve visibly ran tighter on two of them. Drawing on integer
  bounds one pixel short of the control, with the pen laid inside the path rather than centred
  on it, brings the worst difference between corners down to 6 while the shape still occupies
  exactly the size it was given — a field measures 280 x 26 pixels on the nose. Supersampling
  the whole field at 8x and scaling it down was tried and reached 3, which is not worth a
  bitmap on every repaint.
- **Focus is drawn, not borrowed.** `ControlPaint.DrawFocusRectangle` paints a hard black
  dotted box whatever the theme, which on a dark surface reads as stray pixels. Focus is a thin
  rounded outline in the accent colour instead.
- **The drop-down list is a separate system window** of class `ComboLBox`. Windows 11 will
  round it and give it a border, but only once it exists, so it is asked just after the list
  opens.

## Layout

```
install.ps1              one-line installer, fetches the latest release
Install.bat              runs the installer
Uninstall.bat            runs the uninstaller
bin/cjpegli.exe          the jpegli encoder (+ component licences)
src/Jipeg-Common.ps1     settings, theming and Win32 helpers
src/Jipeg-Convert.ps1    the converter and its progress window
src/Jipeg-Settings.ps1   the settings window
src/Jipeg-Update.ps1     the quiet update check
src/Install-Jipeg.ps1    installer (window, or -Silent for deployment)
src/Uninstall-Jipeg.ps1
src/launch.vbs           starts the converter without a console window
src/settings.vbs         starts the settings window without a console window
```

## Credits and licences

- The encoding is done by **[jpegli](https://github.com/google/jpegli)**, a Google project,
  shipped here as the `cjpegli.exe` binary built by
  **[libjxl](https://github.com/libjxl/libjxl)**. Jipeg is not affiliated with Google or the
  libjxl project and does not modify their code.
- The icon is drawn from the **JPEG format mark** — a square with its corner taken out and the
  removed piece set beside it. Jipeg is not affiliated with or endorsed by the JPEG committee.
- Third-party licences: `bin/LICENSE.*` (BSD-3-Clause, Apache-2.0, zlib and others).
- Jipeg itself is MIT licensed — see [LICENSE](LICENSE).
