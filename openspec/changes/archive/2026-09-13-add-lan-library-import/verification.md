## Automated verification

- `go test ./...` passes in `/Users/wangzicheng/iceWorkSpace/ice-reader-server`.
- macOS arm64, Windows amd64, and Windows arm64 server executables build successfully; `file` identifies the expected Mach-O and PE32+ formats.
- A macOS server smoke test on port 18090 served the embedded management page and a Chinese-named `.txt` catalog entry with matching size and SHA-256 metadata.
- A real streaming multipart request uploaded `测试目录/说明.md`, preserved its relative directory, and returned matching catalog metadata.
- System `dns-sd` browsing found `Ice Reader Library` on three macOS interfaces, including both active LAN interfaces.
- RFC1918 filtering tests accept `10/8`, `172.16/12`, and `192.168/16` while rejecting loopback, link-local, CGNAT, public, out-of-range `172.*`, and IPv6 addresses; a live server session displayed only its two `192.168.*` interfaces.
- `node --check web/app.js` passes for the directory picker and XHR progress implementation.
- `plutil -lint` passes for the Xcode project and application Info.plist.
- The documented generic iOS Simulator workspace build succeeds.
- A clean build using a fresh DerivedData directory contains exactly one root-level bundled novel resource: `样例占位.txt`; the sibling `novels` directory still contains all 33 `.txt` source files.
- The clean application bundle contains both server ZIPs with hashes matching their project resources. Archive integrity checks pass; the macOS executable is universal arm64/x86_64 and the Windows executable is PE32+ x86_64.
- The embedded server ZIPs were rebuilt after the RFC1918 filtering change, archive integrity checks pass, and the iOS bundle-resource test succeeds.
- The `ice readerTests` XCTest suite passes all 12 tests on the iPhone 16 / iOS 18.3.1 simulator, including persistence of a `.local` server address, same-title atomic replacement across different server IDs, the single-placeholder catalog, stale last-read cleanup, and readable ZIP bundle resources.
- The Debug application installs and cold-launches on the iPhone 16 simulator; the bookshelf and local-network library toolbar entry render successfully.

## Covered scenarios

- Configuration precedence and invalid ports.
- Stable server/book IDs, managed rename, recursive direct additions, supported text-novel filtering, nested-path safety, symlink exclusion, concurrent rescans, streaming upload rollback, directory-path upload, and recoverable deletion.
- Pairing success, persistence, expiry, invalid pairing, bearer authorization, CSRF, origin, and host-local administration.
- Catalog metadata, streamed content range responses, ETag, embedded web assets, and Chinese filenames.
- Imported catalog relaunch, stable ID across update/title change or same-title source replacement, atomic hash/size validation failure, UTF-8/GB18030 decoding, progress clamping, and single-placeholder bundled mapping.
- Client address parsing, last-successful-address persistence, compatible/incompatible API versions, expired authentication, metadata decoding, download progress, and cancellation.

## Manual verification still required

- Install on a physical iPhone/iPad, grant/deny local-network privacy, and verify Bonjour discovery across a real Wi-Fi LAN.
- Exercise import, offline reading, server-side update, retry/cancel, and “删除本机副本” on that physical device.
- Run the generated Windows executable on Windows and accept the private-network firewall prompt.
- Exercise a near-200 MB upload and a mixed large directory through a real browser and confirm progress/performance/storage behavior.

Physical-device installation was not performed automatically because it could replace an existing installed build and its app-container data.
