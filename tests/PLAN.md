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
- **no** a PNG with an ICC profile that is not sRGB
- **no** a 12-bit or arithmetic-coded JPEG

### 1.2 Shape and size
- **done** 1×1, 2000×40, 37×1301, 1600×1200, and a few hundred random sizes
- **no** anything above about 4000 px on a side, or over 50 MB
- **no** a picture large enough to matter for memory — a 100 MP panorama

### 1.3 The file itself
- **done** empty, truncated, a JPEG named `.png`, a PNG named `.jpg`, plain text
  wearing an image extension, a PNG header with nothing behind it
- **done** 300 files with bytes flipped at random, five seeds
- **done** read-only source
- **no** a source that is **open in another program** while converting
- **no** a source on a **network share**, a USB stick, or a OneDrive folder that
  is online-only
- **no** a source whose folder cannot be written to
- **no** a **hidden** or **system** file

### 1.4 The name
- **done** spaces, accents, Japanese, 130 characters, already carrying `_jipeg`
- **no** a path near the **260-character limit**
- **no** a name with `[`, `]` or `#` in it — PowerShell wildcards, everywhere it
  matters `-LiteralPath` is used, but that has never been proven with a file
- **no** a name ending in a space or a dot

---

## 2. What the user asked for

### 2.1 Settings
- **done** quality 90, chroma `auto`, dark theme, Mica on, at 100% scaling
- **done** all nine quality values, and the sizes they produce ordered as they
  should be. This is the branch that found a photograph saved as RGBA coming out
  eight times heavier than the same photograph saved as RGB
- **done** chroma forced to `always` and to `never`
- **done** the **light theme**, both with Mica and without
- **no** `closeWhenDone` on with a batch that fails, off with one that does not
- **done** language: ten of them, in both windows and in the registry

### 2.2 How it is started
- **done** one file, a handful, 48 at once, 160 at once
- **done** the same file twice in one selection
- **no** **right-clicking a folder** — the `Directory` verb is registered and has
  never been exercised
- **no** several hundred files at once
- **done** two conversions started at the same time — twelve files across two
  folders, both finish, nothing lost, the lock is handed back
- **no** files **dropped into the selection while it is running** — the watcher
  runs every 400 ms and has never been made to pick anything up

### 2.3 During
- **done** pressing **Cancel** halfway — three files out of twenty-four came
  out, so it really did stop, and nothing was left behind
- **done** closing the window with the cross while an encoder is running
- **done** the source being **deleted** mid-batch — reported, batch finishes
- **no** the source being **renamed** rather than deleted
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
- **no** a machine where `%LOCALAPPDATA%` is redirected to a network profile
- **no** PowerShell **7** rather than Windows PowerShell 5.1
- **no** ExecutionPolicy set to `AllSigned`
- **can't** an antivirus other than Defender, or a corporate policy

---

## 4. Installing and removing

- **done** 26 install/uninstall cycles, registry compared each time
- **done** the archive installed from the zip, on a cleared machine
- **done** the archive missing `src\lang` — refused, as intended
- **once** the **classic menu** path, which restarts Explorer
- **no** installing **over a running conversion**
- **no** uninstalling **while a conversion is running**
- **no** installing when `%LOCALAPPDATA%\Jipeg` exists but is **read-only**
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
- **no** the **quality** of the result measured — ssimulacra2 or butteraugli
  against the source. Size is checked; fidelity is taken on trust
- **no** the result opened by something other than Pillow — a browser, Photos

---

## 6. Around the software

- **done** the page: every string in ten languages, no external resource
- **once** the page rendered in a browser and switched between languages
- **no** the page on a **phone**, or at a narrow window
- **no** the page with JavaScript **off**
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
