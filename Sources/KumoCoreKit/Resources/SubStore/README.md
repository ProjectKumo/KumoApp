Sub-Store bundled resources live in this directory.

Expected release payload:

- `node/bin/node`
- `backend/sub-store.bundle.js`
- `manifest.json`

The Node runtime is generated locally by `Scripts/prepare_substore_runtime.sh`
and is intentionally ignored by Git. Run `make app`, `make app-release`, or
`make prepare-substore-runtime` to download it before building or packaging.

Kumo copies these files into Application Support before launching the local
Sub-Store backend. The frontend is no longer bundled: the SwiftUI app talks to
the backend directly over HTTP, so only the JS runtime and Sub-Store backend
bundle ship with Kumo. Update `manifest.json` whenever replacing the bundled
payload so users can see which resource version is installed.
