## Why

ice-reader currently bundles a fixed set of novels into the application, so adding or removing a book requires changing the Xcode project and rebuilding the app. A local-network library service and an in-app management page will let users manage novels on a nearby macOS or Windows computer and explicitly choose which books are stored on the iOS device.

## What Changes

- Add a cross-platform Go executable that serves a configured `novels` directory over a versioned local-network HTTP API.
- Add an embedded browser-based management page for listing, streaming uploads with progress, recursively importing directories, renaming, downloading, and recoverably deleting common text-novel files on the server computer.
- Advertise the server with system Bonjour on macOS (and a portable Windows mDNS fallback) while retaining manual host and port entry as a fallback.
- Publish and display only RFC1918 IPv4 addresses (`10/8`, `172.16/12`, and `192.168/16`) so VPN, public, loopback, and link-local interfaces do not lead iOS to unreachable endpoints.
- Add an iOS local-network book management page that discovers/connects to servers, remembers and retries the last successful address, and shows remote books as not imported, imported, or update available.
- Let users explicitly import selected remote books, download all missing/updated books sequentially, update previously imported books, and delete imported local copies without deleting the server source.
- Persist imported book metadata and files in the app container and merge them into the existing bookshelf.
- Give imported books stable identities so title changes, same-name replacement, and content updates do not lose local reading progress.
- Reduce the iOS bundled catalog to the single readable `样例占位.txt`; real novels are imported from the LAN server and imported-book progress remains device-local in this change.
- Show first-import guidance below the bookshelf until at least one LAN novel has been installed successfully.
- Bundle shareable ZIP packages for a universal macOS server and Windows x86_64 server inside the iOS app.
- Add local-network privacy, Bonjour service, and local HTTP transport declarations to the iOS target.

## Capabilities

### New Capabilities

- `lan-library-server`: Cross-platform startup, library discovery, web file management, local-network API, service discovery, and access controls for the Go server.
- `ios-lan-library-management`: Server discovery/connection and an iOS management page for importing, updating, and deleting local copies of remote books.
- `imported-book-storage`: Stable imported-book identity, atomic on-device storage, bookshelf integration, decoding, and reading-progress preservation.

### Modified Capabilities

None. This repository has no existing OpenSpec capabilities.

## Impact

- Adds a sibling Go project at `/Users/wangzicheng/iceWorkSpace/ice-reader-server` and reads/manages the sibling `/Users/wangzicheng/iceWorkSpace/novels` directory by configuration.
- Changes the SwiftUI bookshelf and `BookVM` content-loading model from bundled-only resources to bundled and imported sources.
- Adds iOS networking, discovery, download, catalog persistence, and imported-book management components.
- Increases the application bundle by roughly 15 MB for the two compressed server distributions and exposes them through the system share sheet.
- Changes the iOS information property list settings for local-network privacy, Bonjour, and local HTTP access.
- Introduces a versioned JSON/HTTP contract shared by the Go server and iOS client.
- Removes legacy novel references from the iOS target without deleting their source files in the sibling `novels` directory; it does not synchronize imported contents through iCloud or delete server files from iOS.
