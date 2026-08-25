# Tests

Everything the README claims about Jipeg was measured by something in this
folder. It is here so the claims can be replayed rather than believed.

Nothing runs on a schedule and there is no CI: these are scripts you point at a
working copy. The PowerShell ones need nothing beyond Windows. The four that
build or inspect images need **Python 3 with Pillow** (`pip install pillow`),
because they have to produce a transparent WebP, a 16-bit PNG and an animated
GIF, and Windows will not make those on its own.

Several of them convert files, which means they need Jipeg **installed**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\Install-Jipeg.ps1 -Silent
```

## The ones that need nothing but Windows

| | |
|---|---|
| `Test-Languages.ps1` | Every language file against the English one: same keys, no extras, and every `{0}` that English uses surviving into the translation. A missing placeholder leaves a hole in a formatted message. |
| `Test-Widths.ps1` | Every translated string measured against the box that has to hold it. Labels are fixed rectangles — text longer than one is simply cut off, and nothing on screen says so. Six strings had to be shortened before all ten languages fit. |
| `Test-InstallCycle.ps1` | Installs and uninstalls in a loop, comparing the whole registry footprint each time. `-Tours 20` for the full round. This is what found an install wiping the flag that says who turned the Windows 11 classic menu on. |
| `Invoke-Corpus.ps1` | Hands a folder to the converter and waits. `-Folder corpus` or `-Folder random`. Sets `closeWhenDone` for the run and puts it back afterwards. |

## The ones that need Python

| | |
|---|---|
| `check-encoding.py` | BOM, line endings and stray NUL bytes across the repo. A `.sh` with CRLF does not start on Unix at all; a `.ps1` without a BOM loses its accents. |
| `check-site.py` | The page: every `data-t` string present in all ten tables, no external resource loaded, tags balanced, images where the markup says they are. |
| `check-dead-code.py` | Functions defined and never called, variables assigned and never read. |

## The ones that need Python **and Pillow**

| | |
|---|---|
| `corpus-build.py` | Writes 48 files into `corpus/` together with `corpus-expected.json`, which says what each one should produce — decided before anything runs. |
| `corpus-check.py` | Compares what came out to what was written down. Also checks the transparent files came back byte for byte identical, and that all eight Exif orientations turned the pixels rather than the tag. |
| `fuzz-build.py` | 100 random images and 60 copies with bytes flipped at random, into `random/`. Takes a seed: `python fuzz-build.py 1337`. |
| `fuzz-check.py` | Not "did it produce the right file" but "did it break a rule": nothing heavier than its source, no unreadable output, no transparency lost, no temporary file left in the folder or in `%TEMP%`. |

## A full round

```powershell
python tests\check-encoding.py
python tests\check-site.py
python tests\check-dead-code.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Languages.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Widths.ps1
python tests\corpus-build.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-Corpus.ps1 -Folder corpus
python tests\corpus-check.py
```

and for the random one, a few seeds in a row:

```powershell
python tests\fuzz-build.py 7
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-Corpus.ps1 -Folder random
python tests\fuzz-check.py
```

`corpus/` and `random/` are not in the repository. They are rebuilt from a seed
each time, and there is no reason to carry several megabytes of generated images
through the history.

## Two things worth knowing before trusting a result

**A window left open is not a hang.** When a batch has a failure in it the
progress window deliberately stays on screen so the reason can be read — see the
`Failed -eq 0` on the auto-close. A harness that times how long the process
lives will call that a stall. Mine did, twice.

**A test can be wrong about the thing it is testing.** Three findings in these
scripts turned out to be faults in the scripts rather than in Jipeg: a wait
shorter than the delay the uninstaller hands to `cmd`, a registry key counted as
a leak when leaving it alone is deliberate, and two label strings measured
separately when they are displayed joined. Read a failure before believing it.
