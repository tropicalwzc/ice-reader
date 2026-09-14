## Context

The current in-progress LAN import implementation makes a macOS or Windows executable the HTTP server and iOS the client. That direction works on macOS but creates a poor Windows bootstrap path: an unsigned executable must be transferred and extracted, Windows may block inbound HTTP and mDNS, and the user must understand firewall profiles before importing a book. The iOS app already owns the imported catalog, atomic local file storage, content decoding, progress identity, and bookshelf refresh behavior.

This change reverses only the transfer direction. While a dedicated receive page is visible, iOS becomes a narrowly scoped upload server and a desktop browser becomes the client. The computer makes an outbound HTTP connection, so it needs no installed program or inbound firewall rule. iOS remains the authoritative destination and all reading stays offline after upload.

The target remains iOS 16.1. A normal iOS app cannot promise an indefinitely available background listener, so receiving is explicitly a foreground activity.

## Goals / Non-Goals

**Goals:**

- Let a macOS or Windows user open one displayed local URL and upload novels with a browser.
- Support drag-and-drop, multi-file selection, and recursive directory selection with per-file and aggregate progress.
- Stream uploads with bounded memory, validate them, and reuse the existing atomic imported-book installation and bookshelf refresh flow.
- Remove desktop executable distribution, server-package sharing, desktop discovery/pairing, and remote download concepts from the iOS user experience.
- Preserve all valid books already imported by the earlier implementation and their stable local progress IDs.
- Keep the receiving surface short-lived and safe enough for a trusted home or office LAN.

**Non-Goals:**

- Keeping the iOS server running indefinitely in the background or while the device is locked.
- Public-internet uploads, cloud synchronization, TLS certificate provisioning, or account-based authentication.
- Browser-side reading, downloading books from iOS, deleting iOS books from the browser, or general-purpose file management.
- Deleting the sibling Go project from the developer workspace; it simply ceases to be an application dependency or distributed resource.

## Decisions

### Run a foreground-only listener with Network.framework

Use `NWListener` with TCP on a dynamically allocated port and advertise `_icereader-upload._tcp` while receiving. The receive page derives and displays only RFC1918 IPv4 URLs, preferring the active Wi-Fi interface. Dynamic allocation avoids port conflicts; the chosen port remains stable for that page session.

Within the receive page, common `192.168.*` home-network and `172.16–31.*` enterprise-network URLs are shown directly. Valid `10.*` URLs remain available under a collapsed “其他地址” section so VPN, hotspot, or large private-network interfaces do not overwhelm the normal connection choice.

The listener starts when the receive view appears and stops when it disappears or the scene enters the background. The app disables the idle timer only while this page is active. If an upload is already committing when the app backgrounds, a finite `beginBackgroundTask` grace period may finish that file, but the app stops accepting new requests immediately. Pretending to be a permanent background server was rejected because iOS suspension would make that promise false.

### Implement a deliberately small HTTP/1.1 surface

Use Network.framework directly instead of adding a general-purpose embedded-server dependency. The server supports only the methods and routes required by its embedded page, requires `Content-Length`, rejects chunked transfer encoding, caps request headers, closes each response connection, and limits simultaneous uploads. Static HTML, CSS, and JavaScript ship as ordinary app resources.

The browser sends each file as the raw body of a separate authenticated `PUT`, rather than multipart form data. A `Blob` has a known byte count, raw streaming avoids a multipart parser, and one-file-per-request gives simple retry and progress semantics. Directory relative paths travel in encoded request metadata and are treated only as display/source metadata; local storage remains based on safe generated IDs.

### Use a code exchange and in-memory session token

Every receive-page session generates a random six-digit code with a short expiry. The browser first submits the code through a rate-limited endpoint and receives a high-entropy bearer token held only in browser memory. Upload requests require that token, an expected same-origin `Origin`/`Host`, a supported content type/extension, and bounded metadata. Tokens and partial uploads are invalidated when receiving stops.

The web surface cannot enumerate, download, rename, or delete existing books. A code-less open upload endpoint was rejected because any device on the same Wi-Fi could inject content while the page was open. TLS is not introduced because locally trusted, short-lived, IP-address sessions cannot obtain a frictionless broadly trusted certificate.

### Stream directly into staged imported storage

Each accepted request writes chunks to a unique `.partial` file under Application Support without accumulating the novel in memory. It enforces a 200 MB per-file limit, available-storage checks, supported extensions, normalized filenames, and cancellation cleanup. On completion the store computes SHA-256, derives the title from the filename, and atomically installs the file before publishing catalog metadata.

The browser uploads sequentially. A same-normalized-title upload replaces the existing local bytes while preserving the local book ID and reading progress, matching the current server-download behavior. Unsupported files are skipped in the browser when possible and rejected again by iOS as the security boundary.

Once file or directory selection yields at least one supported novel, the browser starts the upload queue automatically. A larger explicit start button remains available after cancellation or for manually resuming queued work.

### Migrate source metadata without losing existing imports

Replace mandatory desktop `serverID`/`serverBookID` assumptions with a backward-compatible source representation that can describe either a legacy LAN download or a browser upload. Existing catalog JSON must decode without rewriting file paths or local IDs. Browser uploads have no remote update identity; later same-title uploads are explicit replacements.

The bookshelf continues to contain the bundled placeholder followed by valid imported records. Its first-use card now instructs the user to open “浏览器上传,” keep the page visible, type one of the displayed URLs on the computer, enter the six-digit code, and drag files or a directory.

The bookshelf toolbar uses an explicit “从局域网导入” label beside the Wi-Fi icon and provides a separate local-book management page. That page lists imported records and permits confirmed deletion from iOS without exposing any browser-side delete API.

### Remove the desktop-host workflow from the shipped app

Remove `LANLibraryView`, `LANLibraryClient`, Keychain server credentials, desktop Bonjour browsing declarations, server ZIP references, `ServerPackageShareView`, toolbar share menus, and package-resource tests. Add the new receive-page entry and advertised Bonjour service declaration. The sibling Go project remains untouched but no binary from it ships in the iOS bundle.

Keeping both directions was rejected because it leaves two overlapping import models, retains the Windows troubleshooting burden, and preserves approximately 15 MB of resources that the browser-upload path makes unnecessary.

## Risks / Trade-offs

- **iOS suspends the listener when the app backgrounds or locks** → Keep the receive page foreground-only, disable idle sleep during the session, stop accepting new requests on background, and show this constraint prominently on both screens.
- **A large upload is interrupted by Wi-Fi or lifecycle changes** → Stream to a disposable partial file, report retryable failure, and never replace a valid book until the new file completes.
- **Custom HTTP parsing can create security bugs** → Implement only a strict subset, bound every field/body, require known length, reject unsupported transfer modes/methods, fuzz malformed framing/path cases, and close each connection.
- **Another LAN device guesses the six-digit code** → Use short expiry, attempt throttling, high-entropy post-pairing tokens, and a server lifetime tied to the visible page.
- **Multiple RFC1918 interfaces produce confusing URLs** → Prefer Wi-Fi, label alternatives, omit non-RFC1918 addresses, and explain AP/guest-network isolation.
- **Legacy imported metadata no longer has a live remote source** → Preserve it as historical source metadata while treating its local file and ID as authoritative.
- **Removing remote update/all-download loses synchronization behavior** → Make browser batch upload and same-title replacement the explicit update path.

## Migration Plan

1. Add backward-compatible source metadata and browser-upload installation APIs while retaining current catalog decoding.
2. Implement and test the strict HTTP parser, session authorization, listener lifecycle, and embedded browser assets behind the new receive view.
3. Switch bookshelf onboarding and navigation to browser upload, then remove the desktop client, Keychain credentials, ZIP resources, share UI, and obsolete tests/configuration.
4. Verify a clean build contains no server ZIPs and preserves previously imported files/progress across launch.
5. Test macOS Safari/Chrome and Windows Edge/Chrome against a physical iPhone/iPad on the same Wi-Fi, including directory upload, replacement, interruption, screen lock, and denied local-network permission.

Rollback can restore the desktop-client UI and resources without changing imported local IDs or files. New browser-upload records remain readable because their local storage fields are independent of source metadata.

## Open Questions

- Whether a future release should expose a QR code for opening the receive URL from another mobile device; it is not needed for the primary desktop-browser flow.
- Whether Bonjour-discovered friendly links should be documented for macOS while retaining numeric URLs as the cross-platform baseline.
