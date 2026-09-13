## ADDED Requirements

### Requirement: Foreground browser-upload service
The iOS app SHALL provide a dedicated browser-upload page that starts a temporary HTTP listener while visible, displays its current receiving state, and stops accepting new connections when the page closes or the app leaves the foreground.

#### Scenario: Open receive page on Wi-Fi
- **WHEN** the user opens the browser-upload page while a usable private IPv4 interface is active
- **THEN** the app starts the listener, keeps the screen awake, and displays at least one browser URL and a short-lived six-digit code

#### Scenario: Leave receive page
- **WHEN** the user navigates away from the page or the scene enters the background
- **THEN** the app stops accepting new connections, invalidates the session credential, restores normal idle-timer behavior, and cleans abandoned partial files

#### Scenario: No usable private address
- **WHEN** no address in `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16` is available
- **THEN** the page does not display loopback, public, link-local, CGNAT, or unrelated addresses and explains how to connect both devices to the same non-isolated Wi-Fi

#### Scenario: Common and large-network addresses coexist
- **WHEN** the device has both a `10.*` address and a usable `192.168.*` or `172.16–31.*` address
- **THEN** the common home or enterprise address is shown directly and the `10.*` address remains available in a collapsed “其他地址” section

### Requirement: Embedded cross-platform upload page
The iOS listener SHALL serve a responsive same-origin page usable from current macOS and Windows browsers without installing desktop software.

#### Scenario: Open displayed URL
- **WHEN** a computer on the same reachable LAN opens a displayed URL
- **THEN** the browser receives the embedded upload page with code entry, drag-and-drop, multi-file selection, directory selection, status, and progress controls

#### Scenario: Select a directory
- **WHEN** the user selects or drags a directory containing nested supported and unsupported files
- **THEN** the page recursively queues supported novel files, retains safe relative names for display, skips unsupported files, and presents the total queued count and size

#### Scenario: Supported files become ready
- **WHEN** file or directory selection produces at least one supported novel and no upload is currently active
- **THEN** the browser starts uploading automatically and retains a prominent manual start control for resuming queued work after cancellation

### Requirement: Short-lived upload authorization
The service SHALL require a valid six-digit code exchange before upload, rate-limit failed attempts, issue an in-memory high-entropy session token, enforce same-origin requests, and invalidate authorization when the receive session ends.

#### Scenario: Correct code
- **WHEN** the browser submits the current code before expiry and within the attempt limit
- **THEN** it receives a session credential that authorizes upload-only requests for that receive session

#### Scenario: Invalid, expired, or throttled code
- **WHEN** a browser submits an incorrect or expired code or exceeds the failed-attempt limit
- **THEN** the service denies authorization without revealing existing books or creating a file

#### Scenario: Unauthorized upload
- **WHEN** an upload lacks the session token or has an invalid origin, host, method, transfer mode, or metadata
- **THEN** the service rejects it before committing content

### Requirement: Bounded streaming uploads
The browser SHALL upload files sequentially as individual raw request bodies with visible per-file and aggregate progress, and iOS SHALL stream each accepted body into a unique staged file with bounded memory.

#### Scenario: Upload a supported novel
- **WHEN** an authorized request supplies a supported filename, valid content length within 200 MB, and the complete advertised number of bytes
- **THEN** iOS streams the body to staging, validates completion, atomically installs it, commits catalog metadata, refreshes the bookshelf, and returns success

#### Scenario: Upload is interrupted
- **WHEN** the browser cancels, Wi-Fi disconnects, the body ends early, or the receive session stops
- **THEN** the partial file is removed, the browser receives or displays a retryable failure, and any prior valid same-title book remains unchanged

#### Scenario: Request exceeds limits
- **WHEN** request headers, metadata, content length, concurrent transfer count, or available-storage requirements exceed configured bounds
- **THEN** iOS rejects the request without reading unbounded data or publishing a catalog entry

### Requirement: Novel validation and safe naming
The upload boundary SHALL accept only configured text-novel extensions, normalize untrusted filenames and relative display paths, prevent traversal or absolute paths, and treat content bytes as opaque until the reader decodes them as UTF-8 or GB18030.

#### Scenario: Unsafe path or unsupported extension
- **WHEN** upload metadata contains traversal, an absolute path, control characters, an empty filename, or an unsupported extension
- **THEN** iOS rejects that file and continues to permit later valid files in the browser queue

#### Scenario: Chinese filename and legacy encoding
- **WHEN** a valid Chinese-named UTF-8 or GB18030 novel is uploaded
- **THEN** its title is preserved for the bookshelf and its bytes remain readable through the existing decoding fallback

### Requirement: Stable replacement and migration
Browser uploads SHALL integrate with the existing imported-book store, preserve all valid legacy imported files and local IDs, and replace a same-normalized-title book without losing its reading progress.

#### Scenario: Upgrade with legacy LAN imports
- **WHEN** an existing installation launches after this change with desktop-server import records
- **THEN** all valid local files remain on the bookshelf with the same stable IDs and progress keys without contacting the former server

#### Scenario: Upload same-title replacement
- **WHEN** a browser upload completes with the same normalized title as an existing imported book
- **THEN** the new bytes atomically replace the prior content while retaining the existing local ID and reading progress

#### Scenario: First successful browser upload
- **WHEN** the device previously had no imported books and the first upload commits
- **THEN** the bookshelf refreshes immediately and its first-use upload guidance disappears

### Requirement: Desktop-free shipped experience
The iOS application SHALL use browser upload as its LAN import entry and SHALL NOT ship desktop server archives or expose desktop-server sharing, discovery, pairing, remote-catalog, update, or bulk-download controls.

#### Scenario: Inspect bookshelf and import UI
- **WHEN** the updated app is launched
- **THEN** its onboarding and explicitly labeled “从局域网导入” toolbar action lead to browser upload and contain no server-package sharing or desktop-server connection actions

#### Scenario: Manage imported books on iOS
- **WHEN** the user opens the local-book management page from the bookshelf
- **THEN** the app lists imported novels and permits individually confirmed local deletion without deleting any computer source file

#### Scenario: Inspect clean application bundle
- **WHEN** the iOS target is built from a clean derived-data directory
- **THEN** the application bundle contains no macOS or Windows server ZIP or executable resources

### Requirement: Actionable receiving diagnostics
The receive page SHALL distinguish listener startup failure, local-network permission denial, missing private Wi-Fi, browser authorization failure, storage exhaustion, rejected files, interrupted transfers, and successful imports.

#### Scenario: Desktop browser cannot connect
- **WHEN** the listener is ready but no browser request arrives and the user requests help
- **THEN** the page explains same-Wi-Fi requirements, guest/AP isolation, VPN interference, keeping the page foreground, and trying each displayed private address
