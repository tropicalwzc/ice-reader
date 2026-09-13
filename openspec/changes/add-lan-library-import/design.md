## Context

The iOS application currently defines every book in `BookVM.bookNames`, loads content only from `Bundle.main`, and derives legacy iCloud progress keys from each book's array position. The sibling `novels` directory contains the source `.txt` files, while the requested `ice-reader-server` directory is currently empty. The change crosses a new Go process, a browser administration UI, a local-network API, iOS network/privacy configuration, SwiftUI management UI, file persistence, and the existing reader.

The intended environment is a trusted home or office LAN. The computer is the authoritative source for remote files; an iOS device explicitly downloads local copies and can continue reading when the server is offline.

## Goals / Non-Goals

**Goals:**

- Ship a click-to-run Go server for macOS and Windows with its web assets embedded in one executable.
- Expose a versioned, bounded HTTP API for discovery, pairing, book metadata, and content downloads.
- Give the computer's browser a safe management UI for the configured novels directory.
- Give iOS a dedicated management page that clearly distinguishes remote availability from on-device storage.
- Keep only one bundled placeholder book while giving LAN-imported books stable identities and device-local progress.
- Make downloads and catalog updates atomic and recoverable.

**Non-Goals:**

- Public-internet access, account-based multi-user hosting, or protection against a malicious LAN capable of sniffing unencrypted HTTP.
- EPUB/PDF parsing, server-side reading, automatic background synchronization, or iCloud synchronization of imported content/progress.
- Deleting or renaming server source files from iOS.
- Replacing the existing text splitting and reading presentation in this change.

## Decisions

### Separate the server library from the iOS offline library

The Go server treats the configured computer directory as its library. iOS always downloads a selected book into `Application Support/Books` before exposing it on the bookshelf. Reading never streams directly from the server.

This keeps reading reliable when Wi-Fi changes or the executable stops. Direct streaming was rejected because it would couple navigation, progress restoration, and content availability to a transient LAN connection.

### Use a stable catalog identity instead of titles or array positions

The server assigns each file a persistent opaque book ID and stores filename-to-ID metadata in a private `.ice-reader/catalog.json` sidecar. Renames performed through the web UI retain the ID. A persistent server ID distinguishes two servers that happen to expose books with the same filename.

The iOS catalog stores a local stable ID plus optional `serverID`, `serverBookID`, content hash, title, extension, and relative local path. A remote update replaces bytes atomically while retaining the local ID and reading-progress keys. Titles are display metadata, not identity.

The distributable app intentionally contains only `样例占位.txt`, mapped to `syncIRA0`. The former bundled novel source files remain in the sibling computer library but are no longer Xcode resources. Imported books are appended in catalog order and use stable local progress keys only, so deleting or reordering imports cannot corrupt progress.

### Use a versioned pull-oriented JSON/HTTP contract

The initial contract uses `/api/v1` and includes server metadata, pairing, a book listing, per-book metadata, and content download. Book metadata includes ID, title, filename, byte count, modification timestamp, SHA-256 hash, and download path. Content responses expose ETag and support HEAD and byte ranges.

The web administration endpoints support upload, rename, download, and recoverable delete. Uploads have a configurable limit with a 200 MB default and accept common text-novel extensions (`txt`, `text`, `novel`, `md`, `markdown`, and `log`). The catalog scans nested directories. Browser directory selection recursively filters supported files, preserves relative paths, and uploads them sequentially with aggregate progress so a single large transfer cannot make the page appear stalled. The server treats contents as opaque bytes so existing UTF-8 and GB18030-compatible files are not silently rewritten.

### Make the iOS management page the explicit import authority

The bookshelf toolbar opens a local-network library page. It discovers `_icereader._tcp` services and also accepts a manual `host:port`. Once connected, rows present one of three states: not imported, imported/current, or update available. The user can import an individual book, update an imported book, or delete its on-device copy.

Deleting from this page removes only the iOS catalog entry and local file after confirmation. It does not call a server delete API. Removing a currently active book clears `LastReadBookName` safely and returns to the bookshelf if necessary.

The page also offers “全部下载” for the common first-use flow. It builds a queue of books that are not imported or have updates and transfers them sequentially, skipping current copies to avoid unnecessary traffic and avoiding a burst of concurrent large downloads.

When installing a download, the store first matches the stable server/book identity and then falls back to a normalized title match. A same-title local import is atomically overwritten while retaining its local ID and progress key; its source identity and metadata are updated to the newly downloaded server book. This deliberately treats a same-name import as a replacement instead of creating a duplicate shelf entry.

### Use staged downloads and hash verification

iOS downloads into a temporary `.partial` file, validates size and SHA-256, then atomically replaces the destination and persists the catalog. Cancellation or failure removes the partial file and leaves the previous valid copy/catalog entry intact. The management row shows progress and actionable failure state.

The content loader resolves either a bundle URL or imported local URL, then attempts UTF-8 followed by the existing GB18030 fallback. Missing imported files are reported as unavailable and reconciled out of the visible catalog rather than returning placeholder book content.

### Combine Bonjour discovery with manual addressing

The server advertises `_icereader._tcp` with API version and stable server ID in its TXT record. On macOS it delegates registration to the operating system Bonjour daemon so the service is published on every eligible interface; the portable mDNS implementation remains the Windows fallback. iOS uses Bonjour discovery and provides manual address entry for networks where multicast discovery is unavailable. Subnet scanning was rejected because it is slow, noisy, and difficult to bound.

The iOS target declares `NSLocalNetworkUsageDescription`, `_icereader._tcp` in `NSBonjourServices`, and the narrow local-network ATS allowance required for HTTP hosts and IP addresses.

The app stores only the normalized address of the last server that completed the metadata handshake, then prefills and attempts it when the management page reopens. A failed address never replaces the saved value. Bonjour-selected addresses generally use the computer's `.local` hostname, providing an mDNS alias that remains valid across ordinary DHCP address changes.

Both the browser connection list and portable Windows mDNS A records are limited to RFC1918 IPv4 ranges: `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`. Loopback remains available only for opening the management page on the server computer. This avoids advertising public, link-local, VPN, and unrelated virtual-interface addresses that an iOS device cannot reach.

### Limit administration and require lightweight pairing

Mutation endpoints are host-local by default, so the automatically opened browser can manage the computer library but iOS cannot delete source files. Remote administration requires an explicit server option and is outside the required iOS flow.

The server displays a short-lived six-digit pairing code. Pairing returns a device bearer token that iOS stores in Keychain and sends when listing or downloading books. Tokens prevent accidental access by unrelated LAN devices, but the UI and documentation state that plain HTTP is intended only for trusted networks. Local browser mutations additionally require same-origin requests and a per-session CSRF token; metadata mutations use JSON while uploads use streaming multipart requests.

### Keep the executable configurable and portable

Library resolution uses `--library`, then saved user configuration, then a `novels` directory beside the executable, with a development convenience fallback to sibling `../novels`. Port configuration defaults to 8090 and detects/report conflicts rather than silently choosing an undiscoverable endpoint. Web assets are embedded with `go:embed`; builds target macOS and Windows from the same source.

### Bootstrap the computer server from the iOS app

Until the imported catalog contains a valid book, the bookshelf shows a compact setup guide beneath the bundled placeholder. It links directly to LAN management and offers the server packages through the native share sheet. A persistent toolbar menu and a section on the LAN management page retain package access after the first import.

The app embeds two ZIP resources: a universal macOS executable containing arm64 and x86_64 slices, and a Windows x86_64 executable. Each archive includes an empty adjacent `novels` directory and Chinese setup instructions. Shipping archives instead of naked executables preserves executable permissions and lets AirDrop, Files, mail, and messaging destinations handle a single transferable item.

## Risks / Trade-offs

- **Plain HTTP exposes data to a capable LAN attacker** → Document the trusted-LAN boundary, use pairing tokens for accidental-access control, and leave TLS as a future capability.
- **Bonjour can be blocked by router isolation or user denial** → Retain manual host/port entry and show all usable addresses in the server page.
- **Windows Firewall can silently drop HTTP or mDNS traffic** → Clearly instruct users to allow only Private-network access; automatic firewall mutation requires explicit consent because it changes persistent host security policy.
- **External filesystem changes can invalidate catalog metadata** → Rescan on startup and before listings; reconcile exact paths first and content hashes second, assigning a new ID when identity cannot be proven.
- **Large novels can increase memory and download pressure** → Stream HTTP and file writes, enforce the upload limit, expose byte progress, and retain the existing reader behavior only after the file is local.
- **Removing the former bundled catalog can leave stale last-read state** → Clear `LastReadBookName` when its referenced book is unavailable and keep imported progress independent of list position.
- **Deleting a local copy can surprise the reader** → Label the action as “删除本机副本”, confirm it, preserve the server source, and handle the active-book case explicitly.
- **A server content change may invalidate a numeric paragraph position** → Preserve the prior progress but clamp it to the new split count when the updated book is first opened.
- **Bundled server packages increase App Store download size and can become stale** → Keep only the two requested desktop targets, build them from the current source, verify archive integrity and bundle hashes, and refresh them whenever server behavior changes.

## Migration Plan

1. Replace the bundled catalog and Xcode novel resources with the single readable `样例占位.txt`, leaving all sibling `novels` source files untouched for server import.
2. Add imported catalog/file storage and verify the existing bookshelf and reading behavior before enabling networking.
3. Add the Go server and validate its contract independently on macOS and Windows.
4. Add iOS discovery, pairing, management UI, import/update/delete-local-copy operations, and privacy declarations.
5. Verify stale references to removed bundled titles are cleared safely and imported books survive app relaunch and server unavailability.

Rollback removes the management entry point and network declarations. Imported files/catalog can remain inert in the app container so a rollback does not destroy user data; the former bundled resources can be restored from the unchanged sibling source library if needed.

## Open Questions

- Whether a later release should provide iCloud progress for imported book IDs without uploading book contents.
- Whether Windows and macOS distributions should add tray/menu-bar wrappers after the single executable baseline is proven.
- Whether bulk import/delete controls should ship in the first UI iteration or follow the required per-book actions.
