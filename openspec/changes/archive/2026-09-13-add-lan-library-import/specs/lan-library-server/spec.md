## ADDED Requirements

### Requirement: Cross-platform local library startup
The server SHALL run from macOS and Windows executables, resolve a configured novels directory, listen on a configurable local-network TCP port defaulting to 8090, and open its embedded management page in the default browser after successful startup.

#### Scenario: Start beside a novels directory
- **WHEN** the executable starts without an explicit library argument and a readable `novels` directory exists beside it
- **THEN** the server uses that directory, listens on the configured port, and opens the management page

#### Scenario: Port is unavailable
- **WHEN** the configured port cannot be bound
- **THEN** the server reports an actionable error and does not claim to be available

### Requirement: Versioned book catalog API
The server SHALL expose an `/api/v1` JSON API that returns server identity/capabilities and recursively lists supported text-novel files with stable book ID, title, relative filename, size, modification time, SHA-256 hash, and content URL.

#### Scenario: Paired client lists books
- **WHEN** an authenticated client requests the v1 book catalog
- **THEN** the server returns only regular supported files within the configured library and complete metadata for each result

#### Scenario: Unsupported file exists
- **WHEN** the library contains a non-text file or internal server metadata
- **THEN** the file is excluded from the public book catalog

#### Scenario: Nested novel directories exist
- **WHEN** supported files exist in nested directories below the configured library
- **THEN** the server recursively catalogs them and returns safe relative filenames

### Requirement: Stable server and book identities
The server SHALL persist a stable server ID and stable opaque IDs for cataloged books, retaining a book ID when the book is renamed through the management API.

#### Scenario: Managed rename
- **WHEN** the browser management page renames a cataloged book successfully
- **THEN** later catalog responses contain the new filename and title under the same book ID

#### Scenario: External file addition
- **WHEN** a new supported file is placed directly into the library directory
- **THEN** a subsequent rescan assigns it a new stable book ID and includes it in the catalog

### Requirement: Streamed and verifiable content download
The server SHALL stream book contents without loading the entire file into memory, support HEAD and byte-range requests, and return an ETag consistent with the advertised content hash.

#### Scenario: Download a book
- **WHEN** an authenticated client requests a cataloged book's content
- **THEN** the response bytes, length, and ETag match the catalog metadata

#### Scenario: Request unknown book
- **WHEN** a client requests content for an unknown or removed book ID
- **THEN** the server returns a not-found response without exposing filesystem paths

### Requirement: Browser file management
The embedded management page SHALL let the computer user list, upload, rename, download, and recoverably delete supported text-novel files in the configured library.

#### Scenario: Upload valid novel
- **WHEN** the local user uploads a `.txt` file within the configured size limit
- **THEN** the server writes it atomically, assigns it a book ID, and shows it in the refreshed catalog

#### Scenario: Import a novel directory
- **WHEN** the local user selects a directory containing supported and unsupported files
- **THEN** the page recursively uploads supported text-novel files, preserves their relative directories, skips unsupported files, and reports aggregate progress and per-file failures

#### Scenario: Upload a large novel
- **WHEN** a supported file is uploaded within the configured size limit
- **THEN** the request is streamed to a temporary file and the page continuously displays upload progress instead of appearing stalled

#### Scenario: Recoverably delete novel
- **WHEN** the local user confirms deletion of a cataloged novel
- **THEN** the server moves it out of the active library into a server-managed recovery area and removes it from listings

#### Scenario: Reject unsafe path
- **WHEN** any management request attempts path traversal, an absolute path, or escape through a symbolic link
- **THEN** the server rejects the request without reading or modifying the escaped target

### Requirement: Local administration boundary
The server SHALL permit mutation APIs only from the host machine by default and SHALL require same-origin requests with a valid browser-session CSRF token. Metadata mutations SHALL use JSON and file uploads SHALL use bounded streaming multipart requests.

#### Scenario: iOS attempts source deletion
- **WHEN** a paired iOS client calls a mutation endpoint while remote administration is disabled
- **THEN** the server refuses the operation and leaves the source library unchanged

#### Scenario: Cross-origin mutation attempt
- **WHEN** a browser request lacks the expected origin or CSRF token
- **THEN** the server rejects the mutation

### Requirement: Device pairing
The server SHALL issue a short-lived six-digit pairing code and exchange a valid code for a revocable device bearer token required by catalog and content endpoints.

#### Scenario: Successful pairing
- **WHEN** an iOS client submits the current pairing code before it expires
- **THEN** the server returns a device token usable for read-only catalog and content requests

#### Scenario: Invalid pairing code
- **WHEN** a client submits an incorrect or expired pairing code
- **THEN** the server denies pairing without issuing a token

### Requirement: Local service discovery
The server SHALL advertise `_icereader._tcp` over Bonjour with its stable server ID and API version and SHALL display only usable RFC1918 IPv4 manual connection addresses in the management page.

#### Scenario: Server becomes ready
- **WHEN** the HTTP listener has started successfully
- **THEN** the server publishes the Bonjour service and displays its reachable addresses and port

#### Scenario: Server stops
- **WHEN** the server shuts down
- **THEN** it withdraws the advertised service and closes the listener cleanly

#### Scenario: Computer has public, link-local, loopback, VPN, or unrelated virtual addresses
- **WHEN** the server builds its displayed address list and portable mDNS A records
- **THEN** it includes only addresses in `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16`
