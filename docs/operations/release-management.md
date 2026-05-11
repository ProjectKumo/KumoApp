# Release Management

Kumo publishes macOS app updates through GitHub Releases. The app checks a small
release manifest, downloads a DMG, verifies its SHA-256 checksum, then launches a
detached installer helper that replaces the current `Kumo.app` and relaunches it.

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

The app also accepts the same fields as JSON for local testing and backwards compatibility.

## Building Artifacts

Use the release helper to build the Release `.app`, create the DMG, and emit `latest.yml`:

```bash
make release-dmg VERSION=0.0.1 CHANNEL=stable
```

`VERSION` is passed through to Xcode as `MARKETING_VERSION`, so the built
`Kumo.app/Contents/Info.plist` and `latest.yml` use the same app version.
Override `BUILD_NUMBER` to set `CFBundleVersion`; it defaults to `1`.
The artifact script validates the built app version before creating the DMG.

The DMG is laid out as a Finder install window. `Assets/dmg-background.png`
provides the 660×420 paper background with handwritten labels and a
pencil-drawn small-loop arrow from `Kumo.app` toward the `/Applications` alias.

Outputs are written to `build/release/`:

- `Kumo-macos-0.0.1-arm64.dmg`
- `latest.yml`

Upload both files to the GitHub Release. For beta, set `CHANNEL=beta`; the manifest points at the `pre-release` tag.

## Runtime Update Flow

1. `AppUpdateManager` downloads the manifest for the selected channel.
2. Kumo compares the manifest version with `CFBundleShortVersionString`.
3. If an update exists, About and Settings show `Download and Install` when the manifest points to a DMG and includes `sha256`.
4. The DMG is downloaded into `~/Library/Application Support/Kumo/updates/downloads/`.
5. Kumo computes SHA-256 and deletes the download if it does not match the manifest.
6. Kumo disables system proxy, stops the core if running, and launches a detached install helper.
7. The helper waits for the current app process to exit, mounts the DMG, copies `Kumo.app` over the current app, detaches the DMG, and reopens Kumo.

Automatic replacement requires the current app's parent directory to be writable. If Kumo is in a protected location, the update flow reports a clear error and the user can install manually from the download page.

## Logs and Cache

- Downloads: `~/Library/Application Support/Kumo/updates/downloads/`
- Installer log: `~/Library/Application Support/Kumo/logs/app-update-installer.log`

The installer helper is intentionally external because an app cannot safely overwrite its own bundle while it is running.
