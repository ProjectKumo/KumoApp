import Foundation

public struct AppUpdateInstaller: Sendable {
    private let paths: KumoPaths

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
    }

    public func installDMG(
        dmgURL: URL,
        currentAppURL: URL,
        processID: Int32
    ) throws {
        guard currentAppURL.pathExtension == "app" else {
            throw KumoError.invalidArguments("Automatic installation requires Kumo to run from a .app bundle.")
        }
        guard FileManager.default.fileExists(atPath: dmgURL.path) else {
            throw KumoError.invalidArguments("Downloaded update was not found at \(dmgURL.path).")
        }

        let parentDirectory = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw KumoError.invalidArguments(
                "Kumo cannot replace itself in \(parentDirectory.path). Move Kumo.app to a writable location or install the update manually."
            )
        }

        try paths.prepare()
        let scriptURL = paths.appUpdatesDirectory.appendingPathComponent("install-update.sh")
        try installScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            dmgURL.path,
            currentAppURL.path,
            String(processID),
            paths.appUpdateInstallerLogFile.path
        ]
        try process.run()
    }

    private var installScript: String {
        #"""
        #!/bin/zsh
        set -euo pipefail

        DMG_PATH="$1"
        TARGET_APP="$2"
        TARGET_PID="$3"
        LOG_PATH="$4"
        APP_NAME="Kumo.app"

        mkdir -p "$(dirname "$LOG_PATH")"
        exec >> "$LOG_PATH" 2>&1

        echo "[$(date)] Starting Kumo update install"
        echo "DMG: $DMG_PATH"
        echo "Target: $TARGET_APP"
        echo "PID: $TARGET_PID"

        while kill -0 "$TARGET_PID" 2>/dev/null; do
          sleep 0.2
        done

        PLIST_PATH="$(mktemp /tmp/kumo-update-attach.XXXXXX.plist)"
        /usr/bin/hdiutil attach "$DMG_PATH" -nobrowse -readonly -plist > "$PLIST_PATH"

        MOUNT_POINT=""
        for index in {0..10}; do
          candidate="$(/usr/libexec/PlistBuddy -c "Print :system-entities:${index}:mount-point" "$PLIST_PATH" 2>/dev/null || true)"
          if [[ -n "$candidate" ]]; then
            MOUNT_POINT="$candidate"
            break
          fi
        done

        if [[ -z "$MOUNT_POINT" ]]; then
          echo "Unable to find DMG mount point"
          exit 1
        fi

        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
          rm -f "$PLIST_PATH"
        }
        trap cleanup EXIT

        SOURCE_APP="$(/usr/bin/find "$MOUNT_POINT" -maxdepth 2 -name "$APP_NAME" -type d | /usr/bin/head -n 1)"
        if [[ -z "$SOURCE_APP" ]]; then
          echo "Unable to find $APP_NAME in $MOUNT_POINT"
          exit 1
        fi

        echo "Copying $SOURCE_APP to $TARGET_APP"
        /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

        echo "Relaunching $TARGET_APP"
        /usr/bin/open "$TARGET_APP"
        echo "[$(date)] Kumo update install finished"
        """#
    }
}
