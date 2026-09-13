# Validation status

CI runs on Windows Server 2022 using Windows PowerShell 5.1. It checks syntax,
translation consistency and measured text layout, file encoding, website checks,
headless imaging regressions, installer digest rejection and archive assembly.
It does not certify the interactive desktop, installed application, or other OSes.

The imaging helpers now live in `src/Jipeg-Imaging.ps1`, separate from the window.
This is a first extraction, not a portable complete conversion engine: orchestration
still lives in `Jipeg-Convert.ps1`, and several helpers require Windows imaging and
functions from `Jipeg-Common.ps1`.

## Device checks still required

See [the 2026-09-13 test report](testing-2026-09-13.md) for installation and local
screen-geometry results. HEIC/AVIF successful decoding and visual mixed-DPI tests
remain blocked by missing codecs and unavailable UI capture, respectively.

| Environment/input | Check | Status |
|---|---|---|
| Windows 10 and 11 on another person's PC | Install, convert, update, uninstall | Pending |
| Real screens at 125%, 150%, mixed DPI | Window placement, all controls, readable text | Pending |
| HEIC/HEIF and AVIF with installed codecs | Orientation, colour, alpha, output decode | Pending |
| Display P3/Adobe RGB and CMYK | Compare in a colour-managed viewer | Pending |
| Linux/macOS | Dependencies, shell menu, real conversions, orientation | Experimental; pending |
| JPEG/PNG/WebP/TIFF metadata | GPS, EXIF, ICC, thumbnails through each output path | Not exhaustively verified |

For each manual run record the commit, OS/build, codec versions, scaling, input
hashes, settings, observed output and logs. Synthetic regression tests do not
replace these runs. Never use private GPS-bearing photos as public fixtures.

## Compression measurements

Historical percentages in the engineering notes are examples, not guarantees.
To publish a reproducible benchmark, archive legally redistributable source files
(or stable source URLs and SHA-256), tool versions, exact commands, output sizes,
and quality measurements. Record unchanged and failed files as well as successes.
Do not describe lossy JPEG encoding as pixel-identical or promise a fixed saving.

Metadata removal and pixel fidelity are separate properties. The PNG path uses
`--strip safe`, retaining chunks needed for rendering. Files skipped because a
conversion would grow keep their original metadata. A privacy-sensitive export
needs explicit, tested guarantees beyond the current size optimization contract.
