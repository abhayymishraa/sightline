# Building from source

## macOS

Requirements: macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is needed only for universal (Apple silicon + Intel) builds.

```sh
cd macos
scripts/make-signing-identity.sh   # once: a local signing identity, so permissions survive rebuilds
swift run selfcheck                # gaze math checks
scripts/build-app.sh               # builds build/Sightline.app
scripts/build-app.sh --install     # also copies it to /Applications and opens it
```

Options for `build-app.sh`:

| Variable | Meaning |
|---|---|
| `ARCHS="arm64 x86_64"` | Universal build (needs Xcode). Default: this Mac's architecture. |
| `VERSION=1.2.0` | App version. |
| `SIGN_ID="name"` | Code-signing identity. Default: `Sightline Local Signing` if it exists, else ad-hoc. |

> **Caution:** macOS ties Camera and Accessibility grants to the app's signature. With an ad-hoc signature every build has a new signature, and the Accessibility switch stays on but has no effect. Use `make-signing-identity.sh` to avoid this.

`Sightline --snapshot DIR` renders every window to PNG in light and dark mode for design review.

## Windows

Requirements: Windows 10 or 11 and Python 3.10 to 3.12.

```powershell
cd windows
python -m pip install -e .
python -m unittest sightline.selftest   # gaze math checks
python -m sightline                     # run from source
powershell -File build.ps1              # packaged app in dist\Sightline-Windows.zip
```

`build.ps1` downloads the MediaPipe face model, builds with PyInstaller, runs the packaged app's `--selfcheck`, and zips the result.

The Windows app also runs on a Mac for UI work (window control is disabled there). `python tools/snapshot.py OUT_DIR` renders its windows to PNG.

## Logo and banner

The icon and banner are React components rendered with [Remotion](https://www.remotion.dev).

```sh
cd logo
npm install
npx remotion studio --port 3123   # live editor; the Preview still shows every icon size
./export.sh                       # writes every icon size and the banner
```

`export.sh` also refreshes `windows/sightline/assets/icon.png`, `docs/assets/icon.png` and the banner. The source art is `public/icon.svg` and `public/icon-small.svg`; earlier concepts are in `concepts-v2/`.

## Releases

Push a version tag. GitHub Actions builds both apps, runs their self-checks, publishes the release, and then tests both one-line installers on clean runners.

```sh
git tag v1.2.0 && git push origin v1.2.0
```

For stable macOS permissions across updates, the release job signs with a self-signed identity from two repository secrets: `MACOS_SIGNING_P12` (base64 of a `.p12` file) and `MACOS_SIGNING_PASSWORD`.

## Documentation site

The site at https://abhayymishraa.github.io/sightline/ is built from `docs/` with [Zensical](https://zensical.org) and published by `.github/workflows/docs.yml` whenever `docs/` or `zensical.toml` changes on `main`.

```sh
pip install zensical
zensical serve      # live preview at http://localhost:8000
```
