## 1. Server Project and Configuration

- [x] 1.1 Scaffold the Go module under `/Users/wangzicheng/iceWorkSpace/ice-reader-server` with command, internal packages, embedded web assets, and documented macOS/Windows build commands
- [x] 1.2 Implement library-directory resolution from `--library`, saved user configuration, executable-adjacent `novels`, and the development sibling fallback
- [x] 1.3 Implement configurable port startup, clear bind failures, graceful shutdown, reachable-address reporting, and cross-platform default-browser opening
- [x] 1.4 Add unit tests for configuration precedence, supported-file filtering, and startup error reporting

## 2. Server Catalog and Download API

- [x] 2.1 Implement persistent server identity and `.ice-reader/catalog.json` book identity storage with startup/request rescanning and safe reconciliation of external changes
- [x] 2.2 Implement `/api/v1/server`, book list, and book detail responses with the specified metadata and stable IDs
- [x] 2.3 Implement authenticated streamed content, HEAD, Range, SHA-256/ETag behavior, and filesystem-safe book ID lookup
- [x] 2.4 Add API and filesystem tests covering metadata, rename identity, direct file additions, ranges, removed files, traversal, symlinks, and concurrent catalog access

## 3. Server Pairing, Discovery, and Web Management

- [x] 3.1 Implement expiring six-digit pairing codes, persistent revocable device bearer tokens, and read-only API authentication middleware
- [x] 3.2 Advertise `_icereader._tcp` with stable server ID/API version and withdraw the service on shutdown
- [x] 3.3 Build the embedded responsive management page with library status, connection addresses, pairing code, listing, upload, rename, download, and delete confirmation
- [x] 3.4 Implement atomic size-limited text-novel uploads, managed renames, and recoverable deletion with traversal/symlink protection
- [x] 3.5 Restrict mutations to host-local requests by default and enforce bounded request formats, same-origin, browser session, and CSRF checks
- [x] 3.6 Add integration tests for pairing expiry/rejection, local versus remote mutation access, CSRF failures, upload rollback, rename, and recovery-area deletion
- [x] 3.7 Produce and smoke-test macOS and Windows binaries, including paths and filenames containing Chinese characters
- [x] 3.8 Replace buffered browser uploads with bounded streaming multipart handling and visible byte progress
- [x] 3.9 Add recursive catalog scanning plus browser directory import for supported text-novel formats while preserving safe relative paths
- [x] 3.10 Register through system Bonjour on macOS so discovery covers every eligible network interface, retaining the portable Windows fallback
- [x] 3.11 Restrict displayed server URLs and portable mDNS A records to RFC1918 IPv4 ranges, keep loopback only for the host browser, and test accepted/rejected ranges

## 4. iOS Book Model and Local Storage

- [x] 4.1 Refactor book descriptors to use stable identity and explicit bundled/imported locations
- [x] 4.2 Implement a Codable imported-book catalog with atomic persistence and fields for local ID, source server/book IDs, title, path, content hash, size, and import date
- [x] 4.3 Implement Application Support book paths, staged `.partial` files, streaming writes, size/SHA-256 validation, atomic install/update, cancellation cleanup, and local-copy deletion
- [x] 4.4 Extend content loading to resolve bundle or imported URLs, retain UTF-8 then GB18030 decoding, and report missing/unreadable files without placeholder content
- [x] 4.5 Key imported progress by stable local book ID, keep it device-local, preserve progress through update/rename, and clamp positions after shorter-content updates
- [x] 4.6 Add an XCTest target and unit tests for catalog round trips, atomic failure behavior, stable progress, placeholder bundling, decoding fallback, missing files, and progress clamping
- [x] 4.7 Replace a same-title imported book atomically while preserving its local identity/progress and test replacement across different source IDs
- [x] 4.8 Remove legacy novel references/resources from the iOS target, retain only `样例占位.txt`, and clear unavailable last-read state without deleting server-library source files

## 5. iOS Local-Network Client

- [x] 5.1 Add Codable v1 API models and a URLSession client for server metadata, pairing, authenticated catalog retrieval, and progress-reporting downloads
- [x] 5.2 Implement Bonjour discovery for `_icereader._tcp`, deduplicate results by server ID, and support manual host/port validation and connection
- [x] 5.3 Store device tokens in Keychain by stable server ID and clear/re-prompt when authentication is rejected
- [x] 5.4 Add `NSLocalNetworkUsageDescription`, `NSBonjourServices`, and the narrow ATS local-network configuration to the target
- [x] 5.5 Add client tests with a stub HTTP server for compatible/incompatible API versions, authentication expiry, metadata decoding, download progress, cancellation, and hash mismatch
- [x] 5.6 Persist the last successfully connected server address, prefill and auto-reconnect on page entry, and cover address persistence with a unit test

## 6. iOS Local-Network Book Management Page

- [x] 6.1 Add a bookshelf toolbar/navigation entry and build the server discovery, manual address, connection, pairing, loading, empty, permission-denied, and offline states
- [x] 6.2 Build book rows that show title, size, not-imported/current/update-available/transfer state, byte progress, retry, and cancellation
- [x] 6.3 Wire explicit per-book import and update actions to staged storage and refresh both the management list and bookshelf on success
- [x] 6.4 Implement confirmed “删除本机副本” actions that never invoke server deletion and remain available while the server is offline
- [x] 6.5 Handle deletion of the last-read/current imported book by clearing invalid navigation and safely returning to the bookshelf
- [x] 6.6 Merge valid imported entries after the fixed bundled entries and refresh the bookshelf immediately after catalog changes
- [x] 6.7 Add accessibility labels and Chinese user-facing copy that distinguishes server sources from on-device copies
- [x] 6.8 Add a sequential “全部下载” queue for missing and updated books with per-book and aggregate progress/results
- [x] 6.9 Show first-import setup guidance beneath the bookshelf until the imported catalog contains a valid novel
- [x] 6.10 Build and embed shareable universal-macOS and Windows-x86_64 server ZIPs, with persistent share-sheet entry points and bundle-resource tests

## 7. End-to-End Verification

- [ ] 7.1 Verify discovery, manual connection, pairing, import, offline reading, update, cancellation/retry, and local deletion against the macOS server on a physical iOS device
- [x] 7.2 Verify an iOS local deletion leaves the server file unchanged and a browser recoverable deletion removes it from subsequent remote listings
- [x] 7.3 Verify the single bundled placeholder mapping remains isolated from imported-book identity and progress
- [ ] 7.4 Verify UTF-8 and GB18030 novels, Chinese filenames, a near-limit upload, server restart, app relaunch, denied local-network permission, and unavailable Bonjour
- [x] 7.5 Run Go unit/integration tests, the macOS and Windows cross-builds, and the documented `xcodebuild` simulator build; record manual simulator/device scenarios and any distribution/firewall notes
