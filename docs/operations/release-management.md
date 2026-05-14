# Release Management

Kumo publishes macOS app updates through GitHub Releases. Release artifacts
include a signed app DMG and a small manifest consumed by the runtime update
system.

Runtime discovery, five-minute asynchronous polling, local update
notifications, checksum verification, and installer-helper behavior are
documented in [App Updates](app-updates/README.md).

## Release Channels

- Stable updates read `https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest.yml`.
- Beta updates read `https://github.com/ProjectKumo/KumoApp/releases/download/pre-release/latest.yml`.
- Settings may override the manifest URL for development or private feeds. Leave it blank for the default GitHub Releases feed.

## Manifest Format

`latest.yml` is uploaded as a release asset beside the DMG.

```yaml
version: 0.0.1
channel: stable
downloadURL: https://github.com/ProjectKumo/KumoApp/releases/download/0.0.1/Kumo-macos-0.0.1-arm64.dmg
assetName: Kumo-macos-0.0.1-arm64.dmg
sha256: <64-character-sha256>
releaseNotes: |
  See https://github.com/ProjectKumo/KumoApp/releases/tag/0.0.1
```

The app also accepts the same fields as JSON for local testing and backwards
compatibility. See [App Updates](app-updates/README.md) for the runtime
manifest contract and automatic-install requirements.

## Building Artifacts

Use the release helper to build the Release `.app`, create the DMG, and emit `latest.yml`:

```bash
make release-dmg VERSION=0.0.1 CHANNEL=stable
```

`VERSION` is passed through to Xcode as `MARKETING_VERSION`, so the built
`Kumo.app/Contents/Info.plist` and `latest.yml` use the same app version.
Override `BUILD_NUMBER` to set `CFBundleVersion`; it defaults to `1`.
The artifact script validates the built app version before creating the DMG.
Release builds must also include the bundled Sub-Store payload in
`KumoCoreKit` resources: Node sidecar, `sub-store.bundle.js`, and
`manifest.json`. The Sub-Store frontend is no longer bundled; Kumo's SwiftUI
UI talks to the backend directly. Kumo does not download Sub-Store at
runtime; app updates are the update channel for the bundled Sub-Store
resources. The Node sidecar is not tracked in Git; `make app-release` runs
`Scripts/prepare_substore_runtime.sh` before invoking Xcode so the generated
runtime is present in the resource bundle without committing the large binary.

The DMG is laid out as a Finder install window. `Assets/dmg-background.png`
provides the 660×420 paper background with handwritten labels and a
pencil-drawn small-loop arrow from `Kumo.app` toward the `/Applications` alias.

Outputs are written to `build/release/`:

- `Kumo-macos-0.0.1-arm64.dmg`
- `latest.yml`

Upload both files to the GitHub Release. For beta, set `CHANNEL=beta`; the manifest points at the `pre-release` tag.

## Runtime Update Flow

For runtime behavior, see [App Updates](app-updates/README.md). That document
owns the app-side polling, notification throttling, download cache, and
installer-helper details.

Automatic replacement requires the current app's parent directory to be
writable. If Kumo is in a protected location, the update flow reports a clear
error and the user can install manually from the download page.
