# What there is to test

Written down as a tree so that what is *not* covered is as visible as what is.
Every branch is marked:

- **done** — a script in this folder covers it, and it has been run
- **once** — checked by hand at some point, nothing replays it
- **no** — never checked
- **can't** — needs a machine, a licence or a person that is not here

The point of the tree is the **no** rows. A list of what passes tells you
nothing about what was never asked.

---

## 1. The picture that goes in

### 1.1 Format
- **done** PNG: truecolour, palette, palette + tRNS, greyscale, 16-bit, interlaced
- **done** JPEG: baseline, progressive, greyscale, 4:4:4, CMYK, all eight Exif orientations
- **done** WebP: lossy, lossless, with alpha, animated
- **done** GIF still and animated, BMP, TIFF, ICO, PPM, APNG
- **can't** HEIC, HEIF, AVIF, JPEG XR — the codecs are not installed, so only the
  message naming the missing one has ever run
- **no** JPEG XL as a *source*, though Windows now ships a decoder for it
- **done** a PNG and a JPEG carrying an AdobeRGB profile, built by rewriting
  the primaries of the sRGB profile Windows ships so the structure stays
  valid. Both converted. Two earlier attempts embedded a Lab and a CMYK
  profile, which libpng rejects outright and rightly so - a PNG iCCP chunk
  must carry an RGB or grey profile - so those measured a malformed file
  rather than a colour space. They are kept as exactly that: the software
  refuses them cleanly
- **no** a 12-bit or arithmetic-coded JPEG

### 1.2 Shape and size
- **done** 1×1, 2000×40, 37×1301, 1600×1200, and a few hundred random sizes
- **done** 4200 x 2800, converted in 7 s, 1.1 MB down to 76 KB
- **done** 12000 x 8400, 100.8 megapixels, converted in 15 s

### 1.3 The file itself
- **done** empty, truncated, a JPEG named `.png`, a PNG named `.jpg`, plain text
  wearing an image extension, a PNG header with nothing behind it
- **done** 300 files with bytes flipped at random, five seeds
- **done** read-only source
- **done** held under an exclusive lock for the whole conversion: refused,
  which is the only honest answer when the bytes cannot be read
- **done**, and it was broken. A file reached through a UNC path failed every
  time. `Resolve-Path ... .Path` returns the provider-qualified form on UNC -
  `Microsoft.PowerShell.Core\FileSystem::\server\share\...` - which no
  native executable can open, so the encoder was handed a path that could not
  exist. `.ProviderPath` gives the bare one. Checked over `\localhost\C$`,
  which puts the real SMB redirector in the loop: a file converts, and so does a
  folder. A USB stick and an online-only OneDrive folder are still untried -
  neither is here
- **done** write and append denied on the folder by ACL: refused in 3 s
- **done**, and it was broken. A hidden file failed with "Could not find
  item" for a path `Test-Path` had just confirmed, because `Get-Item`
  without `-Force` skips Hidden and System. Fixing that moved the failure
  one step along, onto Jipeg's own temporary file: `Copy-Item` carries the
  attributes across, so a hidden original made a hidden temporary. The
  temporary is ours and now has its attributes cleared. Both convert

### 1.4 The name
- **done** spaces, accents, Japanese, 130 characters, already carrying `_jipeg`
- **partial** a 258-character path converted on two runs out of three; the
  third produced nothing in 5 s with no line in the log. Recorded as
  unstable rather than dressed up as either result. A 264-character path -
  the output name of that same file - fails to be read back
- **done** `crochets [1] et #diese.png` converted. The first run reported it
  broken, and the harness was at fault: it looked for the output with `-like`,
  which read `[1]` as a character class. The wildcard test defeated by a
  wildcard. `-LiteralPath` in the software held throughout
- **done** refused, both of them. Creating the files needed `CreateFileW`
  with the `\?\` prefix: Python's `open()` goes through the CRT, which
  strips the trailing character, so the first two attempts tested perfectly
  ordinary files without either of us noticing

---

## 2. What the user asked for

### 2.1 Settings
- **done** quality 90, chroma `auto`, dark theme, Mica on, at 100% scaling
- **done** all nine quality values, and the sizes they produce ordered as they
  should be. This is the branch that found a photograph saved as RGBA coming out
  eight times heavier than the same photograph saved as RGB
- **done** chroma forced to `always` and to `never`
- **done** the **light theme**, both with Mica and without
- **done** all three ways round: on with a failing batch, the window stays,
  which is the point of it; off with a batch that succeeds, it also stays;
  on with one that succeeds, it closes. The middle one first reported as
  closing on its own, and that was the harness: the previous case's window
  had just been killed and the two runs overlapped. Run on its own it holds
  for thirty seconds
- **done** language: ten of them, in both windows and in the registry

### 2.2 How it is started
- **done** one file, a handful, 48 at once, 160 at once
- **done** the same file twice in one selection
- **done** a folder handed straight to the converter, the way the `Directory`
  verb passes `%V`: 300 files in, 300 out, 43 s
- **done** 300 in one batch, all converted, no failure
- **done** two conversions started at the same time — twelve files across two
  folders, both finish, nothing lost, the lock is handed back
- **done** four slow files started, three more handed to fresh processes 1.8 s
  in, exactly as Explorer does it: seven converted in one batch, the three extra
  processes queued their paths and exited on their own. The log shows the run
  beginning with four files and ending with seven

### 2.3 During
- **done** pressing **Cancel** halfway — three files out of twenty-four came
  out, so it really did stop, and nothing was left behind
- **done** closing the window with the cross while an encoder is running
- **done** the source being **deleted** mid-batch — reported, batch finishes
- **done** three of six sources renamed 2.5 s into a batch: three outputs,
  and no original lost - which is the property that matters
- **no** the disk filling up
- **done** an encoder that never returns — the timeout guard, 2.1 s, no process left

---

## 3. The machine

- **done** Windows 11 build 26100, one screen at 100%, dark, French locale
- **can't** any other Windows build
- **can't** 125% or 150% **for real** — only simulated with `JIPEG_SCALE`
- **can't** two screens at **different** scales — known limitation, written down
- **can't** another system language or accent colour
- **no** a **standard user** account rather than an administrator one
- **done** and to a network path, not merely another folder: the whole
  installation copied under `\localhost\C$\...`, `LOCALAPPDATA` pointed at
  it, the converter run from there. It converts, and it writes its log into
  the redirected profile
- **can't** PowerShell 7 is not installed on this machine
- **done** AllSigned set for real on the user scope, then launched through
  `launch.vbs` as Explorer does: it converts, because the launcher passes
  `-ExecutionPolicy Bypass` on the command line. Testing it by running the
  script directly, as the first attempt did, only proved that nobody starts
  Jipeg that way. A policy pushed by Group Policy would still block it, and
  that needs a domain to try
- **can't** an antivirus other than Defender, or a corporate policy

---

## 4. Installing and removing

- **done** 26 install/uninstall cycles, registry compared each time
- **done** the archive installed from the zip, on a cleared machine
- **done** the archive missing `src\lang` — refused, as intended
- **once** the **classic menu** path, which restarts Explorer
- **done** the installer run 1.5 s into a four-file batch: it exits 0, the
  batch finishes all four, and the installation is intact afterwards - 36
  files and the folder verb still registered
- **no** uninstalling **while a conversion is running**
- **done** write, append and attribute-write denied by ACL on the whole tree:
  the installer exits 1 and changes nothing. 36 files before, 36 after, and a
  control reinstall right after succeeds - it fails without leaving half an
  installation behind, which is the part that matters
- **no** the console installer's **timed question** answered by hand — only the
  timeout and the switches have run
- **done** the quiet update: nothing to do, and the trace in ten languages
- **no** the quiet update actually **installing** a newer release end to end

---

## 5. What comes out

- **done** never heavier than its source
- **done** transparency never lost, whichever format it arrived in
- **done** pixels and alpha byte-identical where the result is lossless
- **done** no Exif, no orientation tag left behind
- **done** no temporary file left in the folder or in `%TEMP%`
- **done** dimensions preserved, or swapped where the Exif said to
- **partial** fidelity is measured now, though not with the tools named here.
  ssimulacra2 and butteraugli are not installed and bringing them in means a
  build chain, so `quality-check.py` computes SSIM, PSNR and the largest
  per-channel error itself. On photographic sources: SSIM 0.991, PSNR 34.1 dB,
  worst channel error 37, for 57% off. On the lossless path, across 300 files:
  SSIM 1.0000, PSNR infinite, error 0 — bit-exact, which is the stronger result
  of the two and was never checked before. SSIM is not ssimulacra2; it does not
  model vision the same way, and this line says so
- **done** ten outputs reopened by GDI+ and by WIC, two decoders that share
  no code with Pillow: all ten read back at their right dimensions

---

## 6. Around the software

- **done** the page: every string in ten languages, no external resource
- **once** the page rendered in a browser and switched between languages
- **done** at 360 px: nothing overflows the viewport, no text is clipped, the
  table folds to 159/44/44/65 px. It also found the copy button sitting at
  x=609 on a 360 px screen, since fixed
- **done** the headline is real text in the markup and the reveal classes are
  added by script, so nothing is hidden and nothing is scrambled. The install
  block shows the Windows command and the tabs simply do not switch
- **done** Windows Defender on the scripts, the console installer and the
  published archive — clean. The installed folder cannot be scanned from here:
  `%LOCALAPPDATA%` is excluded on this machine, and reading the exclusion list
  needs an administrator
- **no** any engine other than Defender. VirusTotal would say little about the
  four `.exe` — they are unmodified libjxl, libwebp and oxipng releases, known
  everywhere. The part nobody has looked at is the PowerShell, and heuristics
  are tuned for exactly its shape: a script that writes to the registry and
  fetches a zip
- **can't** SmartScreen as a stranger meets it — needs a signed installer, or
  publishing and waiting for reputation to build
- **can't** the site live — GitHub Pages is not switched on

---

## What the tree cost, and what it caught

Nine scenarios were run out of it so far. **One defect in Jipeg** — the alpha
channel taken for transparency, which had a photograph coming back eight times
heavier — and **three faults in these scripts**: a batch that finished before
the Cancel click landed, and a default setting that makes a finished window wait
for OK, counted twice as a hang and a leaked lock.

That ratio is the reason for the warning at the bottom of the README here. It
has held all day: the harness is wrong more often than the thing it measures.

## Where the gaps actually are

Counted: **24 rows never checked at all**, and they are not spread evenly. Three
clusters carry most of the risk:

1. ~~Everything that happens *while* it runs.~~ **Mostly done.** Cancel, the
   cross, two at once, a source deleted under it: the process always ends,
   nothing is left in the folder or in `%TEMP%`, the lock always comes back and
   every partial output opens. What is left of this cluster is the watcher —
   files dropped into a selection that is already running.
2. ~~Every setting except the default one.~~ **Done**, and it paid: the very
   first run of it found the alpha-channel-without-transparency bug. Which is
   the argument for the whole tree — the branch was not written because anything
   looked wrong there.
3. **The file that is not a plain local file** — network, removable, in use,
   unwritable folder.

None of these needs a second machine. All of them are reachable from here.
