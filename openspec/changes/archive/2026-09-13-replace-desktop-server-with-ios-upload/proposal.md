## Why

The desktop-hosted server flow is unreliable on Windows because it depends on inbound firewall and mDNS behavior, and distributing executables from the iOS app adds setup friction and bundle size. Making the iPhone or iPad a temporary foreground upload node lets any nearby macOS or Windows computer contribute novels through an ordinary outbound browser connection with no desktop installation.

## What Changes

- Add an iOS “浏览器上传” page that starts a temporary local HTTP listener while the page remains open and displays usable RFC1918 URLs.
- Serve an embedded responsive browser page for dragging files, selecting multiple files, and recursively selecting directories.
- Stream supported text-novel files from the browser into staged local storage, validate limits and paths, atomically install them, and refresh the bookshelf after each success.
- Protect each receiving session with a short-lived six-digit code, same-origin checks, bounded requests, and automatic invalidation when the page closes.
- Keep the screen awake while receiving and explain that iOS cannot reliably keep the listener alive after the app backgrounds or locks.
- Preserve existing imported books and reading progress while adapting imported metadata to distinguish browser uploads from legacy desktop-server imports.
- **BREAKING** Remove the desktop-server discovery, pairing, remote-catalog, update, and “全部下载” workflow from the iOS user interface.
- **BREAKING** Remove the embedded macOS/Windows server ZIP resources and every server-package sharing entry point and setup instruction.
- Retain the sibling Go server project as an unshipped development artifact; it is no longer required for the iOS import experience.

## Capabilities

### New Capabilities

- `ios-browser-upload-server`: Foreground iOS HTTP service, authenticated browser upload UI, streamed file/directory ingestion, lifecycle behavior, and bookshelf integration.

### Modified Capabilities

None. The capabilities being replaced currently exist only in the still-active `add-lan-library-import` change and have not been archived into baseline specs.

## Impact

- Replaces `LANLibraryView` and `LANLibraryClient` as the primary import path with an iOS listener and browser-facing web assets.
- Extends `ImportedBookStore` with browser-upload installation and backward-compatible source metadata migration.
- Updates the bookshelf onboarding and toolbar entry from “connect to computer server” to “receive from computer browser”.
- Changes Bonjour declarations from browsing the desktop `_icereader._tcp` service to advertising an iOS upload service.
- Removes `ServerPackageShareView.swift` and approximately 15 MB of bundled ZIP resources from the application target.
- Requires focused HTTP parsing, upload/path validation, listener lifecycle, storage, and browser integration tests plus physical-device verification on the same Wi-Fi.
