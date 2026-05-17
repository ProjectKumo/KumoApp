# Release Management

Kumo publishes macOS app updates through GitHub Releases. Release artifacts
include a signed app DMG and a small manifest consumed by the runtime update
system.

Runtime discovery, five-minute asynchronous polling, local update
notifications, checksum verification, and installer-helper behavior are
documented in [App Updates](app-updates/README.md).

## Release SOP

The canonical release workflow for a new version (e.g. `0.0.10`). Follow these
steps in order. Do not skip the verification steps.

### 1. Pre-flight Checks

```bash
# Ensure working tree is clean and you are on main
git status
git branch

# Pull latest remote changes
git fetch origin
git pull origin main

# Verify the version you are about to release does not already exist
git tag -l | grep "^0\.0\.10$"
# Should print nothing. If it prints the tag, abort.
```

### 2. Build arm64 (Apple Silicon) DMG

```bash
# Clean previous build artifacts to avoid architecture contamination
make clean

# Build release DMG for arm64
make release-dmg VERSION=0.0.10
```

Outputs in `build/release/`:

- `Kumo-macos-0.0.10-arm64.dmg`
- `latest-arm64.yml`
- `latest.yml` (backward-compatible alias for arm64)

**Verify:**

```bash
ls -la build/release/
# Expect three files; note the arm64 DMG size and SHA-256 for later
```

### 3. Build amd64 (Intel) DMG

The amd64 build must not reuse the Release products directory from the arm64
build, otherwise Xcode may produce a mixed-architecture bundle.

```bash
# Remove only the Release products, keeping the arm64 DMG
rm -rf build/Build/Products/Release build/release/latest.yml

# Build release DMG for Intel
make release-dmg-amd64 VERSION=0.0.10
```

Outputs in `build/release/`:

- `Kumo-macos-0.0.10-amd64.dmg`
- `latest-amd64.yml`

The `latest.yml` alias is intentionally omitted here; it was already produced
by the arm64 build and must not be overwritten with amd64 URLs.

**Verify:**

```bash
ls -la build/release/
# Expect four files total (two DMGs + latest-arm64.yml + latest-amd64.yml)
```

### 4. Verify Architecture Isolation

Confirm each DMG contains a binary for exactly one architecture:

```bash
# Mount DMGs and inspect the binary (or use lipo on the extracted app)
# The arm64 DMG app should report: arm64
# The amd64 DMG app should report: x86_64
```

If either app reports both architectures, the build was contaminated. Start
over from `make clean`.

### 5. Create and Push Git Tag

```bash
git tag -a "0.0.10" -m "Kumo 0.0.10"
git push origin "0.0.10"
```

### 6. Create GitHub Release

Use `gh release create` with both DMGs. Write release notes covering all
commits since the previous tag.

```bash
gh release create "0.0.10" \
  --title "Kumo 0.0.10" \
  --notes "## What's New

- Summarize each commit since the last release.
- Call out user-facing changes first; internal refactors last.
- If a commit fixes a bug users reported, mention it.

## Downloads

- Apple Silicon (M1/M2/M3): \`Kumo-macos-0.0.10-arm64.dmg\`
- Intel: \`Kumo-macos-0.0.10-amd64.dmg\`" \
  --verify-tag \
  build/release/Kumo-macos-0.0.10-arm64.dmg \
  build/release/Kumo-macos-0.0.10-amd64.dmg
```

### 7. Upload Manifest Files

The DMG upload in step 6 does not include the manifest files. Upload them
separately. These are consumed by the in-app update checker.

```bash
gh release upload "0.0.10" \
  build/release/latest.yml \
  build/release/latest-amd64.yml \
  --clobber
```

**Verify:**

```bash
gh release view 0.0.10 --json assets
# Expect four assets: two DMGs + latest.yml + latest-amd64.yml
```

### 8. Verify Update URLs

```bash
# These must return 302 (redirect to the actual asset), not 404
curl -sI "https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest.yml"
curl -sI "https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest-amd64.yml"
```

### 9. Smoke Test In-App Update Check

Install the new DMG on a test machine (or the build machine), open the app,
navigate to **About Kumo** and click **Check for Updates**.

- Expected: "Kumo is up to date." (no error, no 404).
- If it returns HTTP 404, the manifest files were not uploaded correctly.

### 10. Update Release Notes (Optional)

If the initial release notes were minimal, edit them on the GitHub release page
with a fuller summary. The release notes are what users read; the manifest
`releaseNotes` field only needs to point back to the release page.

---

## Release Channels

- Stable updates read `https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest.yml` (arm64) or `latest-amd64.yml` (Intel).
- Beta updates read `https://github.com/ProjectKumo/KumoApp/releases/download/pre-release/latest.yml` (arm64) or `latest-amd64.yml` (Intel).
- Settings may override the manifest URL for development or private feeds. Leave it blank for the default GitHub Releases feed.

## Manifest Format

Kumo's updater consumes one manifest per architecture. The default stable feed
uses the Apple Silicon manifest:

- `latest.yml` — arm64 / Apple Silicon
- `latest-amd64.yml` — amd64 / Intel x86_64

Each manifest keeps the single-asset shape expected by
`AppUpdateManager`: `downloadURL`, `assetName`, and `sha256`. Do not replace
these files with a combined `assets:` list unless the app-side parser is
changed in the same release.

```yaml
version: 0.0.1
channel: stable
downloadURL: https://github.com/ProjectKumo/KumoApp/releases/download/v0.0.1/Kumo-macos-0.0.1-arm64.dmg
assetName: Kumo-macos-0.0.1-arm64.dmg
sha256: <64-character-sha256>
releaseNotes: |
  See https://github.com/ProjectKumo/KumoApp/releases/tag/v0.0.1
```

The app also accepts the same fields as JSON for local testing and backwards
compatibility. See [App Updates](app-updates/README.md) for the runtime
manifest contract and automatic-install requirements.

## Building Artifacts

Use the release helper to build the Release `.app`, create the DMG, and emit
the architecture-specific manifest:

```bash
make release-dmg VERSION=0.0.1 CHANNEL=stable ARCH=arm64
make release-dmg VERSION=0.0.1 CHANNEL=stable ARCH=amd64
# shorthand for Intel: make release-dmg-amd64 VERSION=0.0.1 CHANNEL=stable
```

`VERSION` is passed through to Xcode as `MARKETING_VERSION`, so the built
`Kumo.app/Contents/Info.plist` and manifests use the same app version.
Override `BUILD_NUMBER` to set `CFBundleVersion`; it defaults to `1`.
The artifact script validates the built app version before creating the DMG.

When publishing a `v`-prefixed Git tag, pass the exact release tag into the
helper so manifest URLs match the GitHub release path:

```bash
RELEASE_TAG=v0.0.1 make release-dmg VERSION=0.0.1 CHANNEL=stable ARCH=arm64
RELEASE_TAG=v0.0.1 make release-dmg VERSION=0.0.1 CHANNEL=stable ARCH=amd64
```

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
If Finder automation cannot address the mounted volume, the script logs a
warning and still emits a usable DMG with the default Finder layout.

Outputs are written to `build/release/` for the selected architecture:

- `Kumo-macos-0.0.1-arm64.dmg` or `Kumo-macos-0.0.1-amd64.dmg`
- `latest.yml` for that architecture

For a dual-architecture GitHub release, collect and upload these four assets:

- `Kumo-macos-0.0.1-arm64.dmg`
- `Kumo-macos-0.0.1-amd64.dmg`
- `latest-arm64.yml` and `latest-amd64.yml` (per-architecture manifests)
- `latest.yml` (backward-compatible arm64 alias)

Upload both DMGs, `latest.yml`, and `latest-amd64.yml` to the GitHub Release.
The `.github/workflows/build-release.yml` workflow automates this collection,
validates that each manifest points at the matching architecture and tag, and
uploads all four assets. For beta, set `CHANNEL=beta`; the manifest points at
the `pre-release` tag unless `RELEASE_TAG` is explicitly provided.

## Runtime Update Flow

For runtime behavior, see [App Updates](app-updates/README.md). That document
owns the app-side polling, notification throttling, download cache, and
installer-helper details.

Automatic replacement requires the current app's parent directory to be
writable. If Kumo is in a protected location, the update flow reports a clear
error and the user can install manually from the download page.
