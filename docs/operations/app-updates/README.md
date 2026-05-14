# App Updates

Kumo updates itself from a GitHub Releases manifest while the app is running.
The update system has two separate concerns:

- **Discovery** — periodically check whether a newer manifest version exists.
- **Installation** — download the DMG, verify its SHA-256 checksum, and hand
  replacement work to an external installer helper.

## Release Feeds

Kumo reads one manifest URL for the selected update channel:

- Stable: `https://github.com/ProjectKumo/KumoApp/releases/latest/download/latest.yml`
- Beta: `https://github.com/ProjectKumo/KumoApp/releases/download/pre-release/latest.yml`
- Custom: Settings may override the manifest URL for development or private feeds.

The selected channel is stored in `UserPreferences.updateChannel`. A blank
custom URL means Kumo uses the default feed for that channel.

## Manifest Contract

`latest.yml` is uploaded as a release asset beside the DMG:

```yaml
version: 0.0.1
channel: stable
downloadURL: https://github.com/ProjectKumo/KumoApp/releases/download/0.0.1/Kumo-macos-0.0.1-arm64.dmg
assetName: Kumo-macos-0.0.1-arm64.dmg
sha256: <64-character-sha256>
releaseNotes: |
  See https://github.com/ProjectKumo/KumoApp/releases/tag/0.0.1
```

The same fields are accepted as JSON for local testing. `AppUpdateManager`
ignores a manifest when its `channel` does not match the selected channel or
when `version` is not greater than `CFBundleShortVersionString`.

Automatic installation requires:

- `downloadURL` points to a `.dmg`;
- `sha256` is present and non-empty.

If either condition is missing, the UI opens the download URL instead of trying
to install automatically.

## Asynchronous Polling

`KumoAppStore.startUpdatePolling()` owns the runtime polling task. It is called
after `KumoRootView` attaches the live store to `KumoAppContext`, and
`KumoAppDelegate.applicationWillTerminate(_:)` cancels the task through
`stopUpdatePolling()`.

The task is intentionally app-local. Kumo does not require APNs or a push token
for update discovery.

Polling behavior:

1. Wait five minutes.
2. Read the selected release manifest.
3. Compare the manifest version with the app bundle version.
4. If a newer version exists, update `lastUpdateCheckResult` and post the
   update-available notification when allowed by notification throttling.
5. Loop until the task is cancelled.

Manual checks in About and Settings call the same update-checking path, but
they keep the user-facing status behavior:

- manual success with no update sets `Kumo is up to date.`;
- manual failure writes `errorMessage`;
- background polling avoids both, so transient network failures do not disturb
  the main UI.

## Notification Behavior

`AppNotificationCoordinator` registers three update categories:

- `UPDATE_AVAILABLE` with `Install Now` and `Remind Me Later`;
- `UPDATE_PROGRESS` with replacement-style stage text;
- `RESTART_READY` with `Restart Now`.

The five-minute poll can repeatedly discover the same release, so update
notifications are gated per version:

- a version is notified once by default;
- `Remind Me Later` removes the visible update notification and suppresses that
  version for six hours;
- once the snooze expires, the same version may notify again;
- a newer version is treated as a new notification candidate.

Notification actions route back through
`KumoAppStore.handleNotificationAction(actionIdentifier:manifest:version:)`.
`Install Now` uses the current checked update when available, or the manifest
embedded in the notification payload.

## Installation Flow

When the user installs an update:

1. Kumo downloads the DMG into
   `~/Library/Application Support/Kumo/updates/downloads/`.
2. Kumo computes SHA-256 and deletes the file if it does not match the
   manifest.
3. Kumo posts coarse download/install notification updates.
4. If system proxy is enabled, Kumo disables it before replacement.
5. If the core is running, Kumo stops it before replacement.
6. Kumo launches the detached installer helper.
7. The helper waits for the current app process to exit, mounts the DMG, copies
   `Kumo.app` over the current app, detaches the DMG, and reopens Kumo.

The helper is external because an app cannot safely overwrite its own bundle
while it is running.

## Logs and Cache

- Downloads: `~/Library/Application Support/Kumo/updates/downloads/`
- Installer log: `~/Library/Application Support/Kumo/logs/app-update-installer.log`

macOS notifications do not provide a continuously updating native progress bar
for this update flow. Kumo uses in-app `ProgressView` for precise progress and
coarse notification stage text for background awareness.
