## 1. Imported Storage Migration

- [x] 1.1 Introduce backward-compatible imported-book source metadata that decodes existing server IDs while supporting browser-upload records without a remote server identity
- [x] 1.2 Add a staged browser-upload installation path that computes size/SHA-256 locally, atomically installs new content, and preserves stable ID/progress on same-title replacement
- [x] 1.3 Add storage tests for legacy catalog migration, new browser records, same-title replacement, interrupted staging cleanup, supported extensions, Chinese names, and UTF-8/GB18030 bytes

## 2. Foreground HTTP Service

- [x] 2.1 Implement an `NWListener` lifecycle that selects a dynamic TCP port, advertises `_icereader-upload._tcp`, and stops on view dismissal or non-foreground scene state
- [x] 2.2 Enumerate and prioritize usable RFC1918 IPv4 interfaces for display while excluding loopback, link-local, CGNAT, public, IPv6, and out-of-range `172.*` addresses
- [x] 2.3 Implement the bounded HTTP/1.1 request parser and response writer for embedded assets, status, code exchange, and raw file upload routes
- [x] 2.4 Reject unsupported methods, chunked bodies, missing/invalid content lengths, oversized headers/bodies, unsafe encoded metadata, invalid origins/hosts, and excess concurrent transfers
- [x] 2.5 Implement six-digit code expiry, failed-attempt throttling, high-entropy in-memory bearer sessions, session invalidation, and an upload-only authorization boundary
- [x] 2.6 Stream request bodies into unique partial files, handle disconnect/cancellation/short bodies, enforce the 200 MB and available-storage limits, commit through `ImportedBookStore`, and emit bookshelf refresh events
- [x] 2.7 Add deterministic unit/integration tests for HTTP framing, fragmented reads, authorization, rate limiting, path attacks, streaming success/failure, lifecycle shutdown, and private-address filtering

## 3. Embedded Browser Experience

- [x] 3.1 Add embedded responsive HTML/CSS/JavaScript with connection/code states, a drag-and-drop zone, multi-file input, directory input, queue summary, and accessible Chinese copy
- [x] 3.2 Recursively enumerate dropped/selected directories, filter supported novel extensions, preserve safe relative display paths, and report skipped files before upload
- [x] 3.3 Upload one raw file request at a time with bearer authorization, per-file and aggregate byte progress, cancellation, retry, success/failure summaries, and no full-file JavaScript buffering
- [x] 3.4 Add browser-asset syntax checks and HTTP integration coverage for code exchange, Chinese filenames, nested directories, sequential uploads, cancellation, and actionable errors

## 4. iOS Receiving UI

- [x] 4.1 Build the SwiftUI “浏览器上传” page with listener state, prominent URLs, copy controls, pairing code/expiry, received-file results, stop/restart controls, and troubleshooting guidance
- [x] 4.2 Keep the screen awake only while receiving, stop new requests when the app backgrounds, use finite background time only to finish or cancel an active commit, and restore lifecycle state on every exit path
- [x] 4.3 Replace bookshelf onboarding and toolbar navigation with browser-upload instructions and hide first-use guidance immediately after the first successful import
- [x] 4.4 Update local-network and Bonjour declarations for advertising the iOS upload service and cover permission-denied, no-private-address, listener-failure, storage-full, and interrupted-upload states
- [x] 4.5 Add view-model tests for startup/shutdown, scene transitions, idle-timer restoration, address/code presentation, result aggregation, and bookshelf refresh

## 5. Retire Desktop-Server Distribution and Client Flow

- [x] 5.1 Remove the server-package share menu/buttons, `ServerPackageShareView`, both embedded ZIPs, their Xcode references, and bundle-resource tests
- [x] 5.2 Remove the desktop-server discovery, manual connection, pairing, remote catalog/update/delete-local-copy, and “全部下载” UI plus obsolete `LANLibraryClient`/Keychain code and tests
- [x] 5.3 Remove `_icereader._tcp` browsing declarations, add only the declarations needed to advertise `_icereader-upload._tcp`, and verify no desktop binary/archive remains in a clean app bundle
- [x] 5.4 Preserve already imported local books and deletion/reading behavior after removing their former remote-management UI, adding any necessary local bookshelf management fallback

## 6. Verification

- [x] 6.1 Run the complete XCTest suite and the documented clean generic iOS Simulator build with `git diff --check` and plist/project validation
- [ ] 6.2 Verify from macOS Safari and Chrome that code entry, file drag, directory selection, progress, replacement, cancellation, retry, and immediate bookshelf refresh work against a physical iOS device
- [ ] 6.3 Verify the same browser flows from Windows Edge and Chrome without installing software or adding Windows inbound firewall rules
- [ ] 6.4 Verify denied local-network permission, guest/AP isolation guidance, VPN/multiple-interface addresses, screen lock, app backgrounding, Wi-Fi loss, near-200 MB upload, and low-storage behavior on a physical device
- [ ] 6.5 Record bundle-size reduction, migration results for legacy imported records, supported browser notes, foreground-only limitations, and final manual verification evidence
