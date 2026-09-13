# Verification

## Automated evidence

- `xcodebuild ... test` passed on the booted iOS 26.5 iPhone 14 Plus simulator.
- A clean generic iOS Simulator build passed with isolated DerivedData at `/private/tmp/ice-reader-browser-upload-derived`.
- `node --check "ice reader/BrowserUploadWeb/app.js"` passed.
- `plutil -lint` passed for the app plist and Xcode project, and `git diff --check` passed.
- The clean app bundle contains `BrowserUploadWeb/index.html`, `style.css`, and `app.js`; no `.zip` or `ice-reader-server` resource is present.
- Legacy catalog tests confirm old `serverID`/`serverBookID` records retain their local IDs. Replacement tests confirm same-title browser uploads retain the local ID and replace only bytes/metadata.
- Browser asset syntax validation covers the automatic-start queue update, and the simulator suite verifies that deleting an imported current book removes its file, bookshelf entry, and last-read state.

## Supported browser and lifecycle notes

- Baseline targets: current Safari and Chrome on macOS; current Edge and Chrome on Windows.
- Directory selection uses `webkitdirectory`; directory drag/drop uses the File System Entries API when available. Multi-file selection remains the fallback.
- Receiving is foreground-only. Leaving the receive page, backgrounding, or locking the iOS device stops the listener, invalidates authorization, and removes partial uploads.
- Only numeric RFC1918 IPv4 URLs are displayed. Bonjour advertises `_icereader-upload._tcp`, but numeric URLs remain the cross-platform baseline.
- The two embedded desktop server archives (previously approximately 15 MB combined) and all corresponding client/share code are removed. The current unstripped Debug simulator app bundle is 32 MB; release/App Store sizing is expected to differ.

## Physical-device checks still required

- macOS Safari and Chrome: code exchange, drag/drop, directory picker, progress, cancel/retry, same-title replacement, and immediate bookshelf refresh.
- Windows Edge and Chrome: the same flow without installing software or opening an inbound firewall port.
- iPhone/iPad: denied local-network permission, guest/AP isolation, VPN/multiple interfaces, Wi-Fi loss, background/lock, near-200 MB input, and low-storage behavior.
