# Jipeg on Linux and macOS

**Experimental, and never run by its author.** Everything here was written on a
Windows machine and has not been executed once on Linux or on macOS. The shell
parses and the two property lists are valid XML — that is the whole of what has
been checked. Treat it as a starting point, not as a release.

The Windows version is the tested one.

## What it does

The same idea: right-click an image, get a lighter file, never a heavier one.
The originals are never touched and the result is written next to them with a
`_jipeg` suffix.

It follows the same rules as the Windows version:

- a **PNG with transparent pixels** is never turned into a JPEG — JPEG has no
  alpha channel, so the only way to make one is to paint something behind the
  picture. It is shrunk losslessly as a PNG instead;
- a **PNG that would grow as a JPEG** — a screenshot, a diagram, an icon — is
  shrunk as a PNG too, rather than producing nothing;
- **nothing heavier than the original is ever written**;
- the result **keeps the original's date**, so a converted folder still sorts by
  when the pictures were taken;
- failures and batch summaries go to a log.

## The one thing it does worse

Choosing between 4:4:4 and 4:2:0. The Windows version measures the density of
hard colour transitions across the actual pixels, which is what 4:2:0 destroys.
A shell script cannot do that, so this one asks ImageMagick how many distinct
colours the picture holds and treats "few" as artwork. Without ImageMagick it
falls back to 4:4:4, which is safe and slightly wasteful.

## What it needs

`cjpegli` is the only one it cannot work without. `oxipng` handles the PNG side
and `dwebp` reads WebP.

| | |
|---|---|
| Debian, Ubuntu | `sudo apt install libjxl-tools oxipng webp` |
| Fedora | `sudo dnf install libjxl-utils oxipng libwebp-tools` |
| Arch | `sudo pacman -S libjxl oxipng libwebp` |
| macOS | `brew install jpeg-xl oxipng webp` |

## Installing

One line, on either system — it works out which one it landed on:

```bash
curl -fsSL https://raw.githubusercontent.com/da0t-exe/Jipeg/main/platform/install.sh | bash
```

And to take it back out:

```bash
curl -fsSL https://raw.githubusercontent.com/da0t-exe/Jipeg/main/platform/uninstall.sh | bash
```

Everything goes into your home folder and nothing needs root. From a clone, the
per-system scripts do the same thing directly:

```bash
./install-linux.sh      # GNOME Files, KDE Dolphin, XFCE Thunar
./install-macos.sh      # Finder Quick Action
```

There is also a plain command, if the right-click entry does not appear:

```bash
jipeg photo.png            # one file
jipeg ~/Pictures/holiday   # every image directly inside a folder
```

## Where it is most likely to break

- **Thunar** keeps every custom action in one XML file. The installer writes it
  only when there is nothing there to overwrite, because merging into somebody
  else's actions blind is a good way to lose them. Otherwise it prints the
  command to paste in by hand.
- **The macOS Quick Action.** An Automator workflow is a bundle of two property
  lists, written here by hand rather than by Automator. The shell command inside
  reads its input both as arguments and from standard input, because which one
  Automator uses depends on how the action was built and an action that silently
  does nothing is the worst outcome.
- **Nautilus** passes the selection through an environment variable with one
  path per line, which breaks on a filename containing a newline. Rare, but real.
- **Orientation.** The Windows version rotates the pixels of a photograph that
  asks to be shown rotated, and writes no metadata. This one does not do it at
  all yet, so a phone photograph may come out on its side.

If you run this and something breaks, the log is the place to look:
`~/.local/state/jipeg/jipeg.log` on Linux, `~/Library/Logs/Jipeg/jipeg.log` on
macOS.
