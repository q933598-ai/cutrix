# Packaging Cutrix

## Arch Linux / CachyOS

The Arch recipe currently builds the development branch `test/ui-prototype`:

```bash
cd packaging/arch
makepkg -si
```

This produces an installable `.pkg.tar.zst` package; it is not a file with a `.pacman` extension. To build from a release branch, change the source branch in `PKGBUILD` and update the version accordingly. For repeatable releases, prefer a tagged source tarball over a moving branch.

Cutrix uses the external `ffmpeg` and `ffprobe` commands for previews and export. Automatic subtitles additionally need `whisper-cli` and a Whisper model.

The project does not yet declare a license. The recipe uses `license=('unknown')` as an explicit packaging placeholder, not as a release-ready license declaration. Pick and add a project license before publishing packages for redistribution or submitting to AUR/Flathub.

## Flatpak

`flatpak/io.github.q933598_ai.Cutrix.yml` is a local development manifest. It builds FFmpeg with x264 and whisper.cpp inside the sandbox so the editing pipeline does not depend on executables from the host OS.

Build and install locally (requires Flatpak and flatpak-builder):

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.kde.Platform//6.11 org.kde.Sdk//6.11
flatpak-builder --user --install --force-clean build-flatpak \
  packaging/flatpak/io.github.q933598_ai.Cutrix.yml
```

The manifest is for local testing, not a ready-to-submit Flathub package. A public release needs a project license, AppStream metainfo, runtime/permission review, and a clean build test. Flathub also requires human-maintained submission manifests, so do not submit this development manifest unchanged.
