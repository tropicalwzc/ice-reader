## ADDED Requirements

### Requirement: Dedicated local-network library page
The iOS bookshelf SHALL provide a navigation entry to a dedicated management page for discovering servers, connecting, viewing remote books, importing or updating selected books, and deleting imported local copies.

#### Scenario: Open management page
- **WHEN** the user activates the local-network import control from the bookshelf
- **THEN** the app presents server connection controls and the imported/remote book management list without changing the current bookshelf

### Requirement: First-import guidance
The bookshelf SHALL show setup guidance beneath its book grid while the device has no valid imported novels and SHALL hide that guidance after the first successful import.

#### Scenario: No novel has been imported
- **WHEN** the imported catalog contains no valid books
- **THEN** the bookshelf explains how to share and run the computer server, join the same Wi-Fi, open LAN management, pair, and download novels

#### Scenario: First import succeeds
- **WHEN** the first LAN novel is installed and the bookshelf refreshes
- **THEN** the first-import guidance disappears while normal server-package access remains available

### Requirement: Share desktop server packages
The iOS app SHALL embed valid ZIP distributions for a universal macOS server and a Windows x86_64 server and SHALL expose both through the system share sheet from the bookshelf and LAN management page.

#### Scenario: Share macOS server
- **WHEN** the user selects the macOS package
- **THEN** the system share sheet receives a ZIP containing a universal arm64/x86_64 executable, setup instructions, and an adjacent `novels` directory

#### Scenario: Share Windows server
- **WHEN** the user selects the Windows package
- **THEN** the system share sheet receives a ZIP containing an x86_64 PE executable, setup instructions, and an adjacent `novels` directory

### Requirement: Automatic and manual server connection
The management page SHALL discover `_icereader._tcp` services through Bonjour, accept a manually entered host and port, and persist the last successfully connected normalized address for a later automatic reconnection attempt.

#### Scenario: Bonjour server found
- **WHEN** a compatible server advertises on the permitted local network
- **THEN** the management page presents it by name for connection

#### Scenario: Bonjour unavailable
- **WHEN** discovery finds no server but the user enters a reachable compatible address
- **THEN** the app can connect through that address

#### Scenario: Reopen after a successful connection
- **WHEN** the user reopens the management page after previously connecting successfully
- **THEN** the saved address is prefilled and the app attempts to reconnect without requiring the address to be entered again

#### Scenario: A new address fails validation or connection
- **WHEN** the user enters an invalid or unreachable address
- **THEN** the app reports the failure without replacing the last successfully connected address

#### Scenario: Local-network access denied
- **WHEN** iOS denies local-network permission
- **THEN** the page explains why discovery/connection failed and points the user to the relevant Settings permission

### Requirement: Pair and remember a server
The iOS app SHALL accept the server's pairing code, store the resulting device token in Keychain, and associate it with the stable server ID.

#### Scenario: First connection
- **WHEN** a user selects an unpaired server and enters a valid code
- **THEN** the app stores the returned credential and loads the remote catalog

#### Scenario: Stored token rejected
- **WHEN** a previously stored token is rejected by the server
- **THEN** the app clears that credential and asks the user to pair again

### Requirement: Communicate remote book state
For each server book, the management page SHALL show title, file size, and exactly one of the states not imported, imported/current, update available, or transfer in progress.

#### Scenario: Remote hash differs
- **WHEN** a remote book matches an imported `serverID` and `serverBookID` but has a different content hash
- **THEN** the row displays update available and offers an explicit update action

#### Scenario: Remote book is current
- **WHEN** the remote and stored content hashes match
- **THEN** the row displays that the book is already imported and current

### Requirement: Explicit per-book import and update
The page SHALL let the user initiate import for an unimported book and update for a changed imported book, display byte progress, and allow cancellation.

#### Scenario: Import succeeds
- **WHEN** the user imports a remote book and download validation succeeds
- **THEN** the row becomes imported/current and the book becomes available on the bookshelf

#### Scenario: Update succeeds
- **WHEN** the user updates an imported book and validation succeeds
- **THEN** the local content and hash change while the local book identity and reading progress are preserved

#### Scenario: Transfer fails or is cancelled
- **WHEN** a download fails validation, loses connectivity, or is cancelled
- **THEN** the page reports a retryable state and the previous valid book, if any, remains unchanged

### Requirement: Download all missing or updated books
The page SHALL provide a “全部下载” action that sequentially downloads every remote book that is not current on the device and reports aggregate completion.

#### Scenario: First-time user downloads the library
- **WHEN** the connected library contains multiple books that have not been imported and the user activates “全部下载”
- **THEN** the app downloads them one at a time, exposes per-book progress, refreshes the bookshelf after each success, and reports the final success/failure count

#### Scenario: Some books are already current
- **WHEN** “全部下载” is activated while some remote books already have matching local hashes
- **THEN** current books are skipped and only missing or updated books are queued

### Requirement: Delete imported local copy
The page SHALL let the user delete an imported book from the iOS device after confirmation and SHALL clearly label that this action does not delete the computer's source file.

#### Scenario: Confirm local deletion
- **WHEN** the user confirms “删除本机副本” for an imported book
- **THEN** the app removes its local file and imported catalog entry, removes it from the bookshelf, and leaves the server book unchanged

#### Scenario: Cancel local deletion
- **WHEN** the user cancels the confirmation
- **THEN** neither the local copy nor its catalog entry changes

#### Scenario: Delete active book
- **WHEN** the deleted local copy is the last-read or currently selected imported book
- **THEN** the app clears the invalid last-read selection and safely returns to or remains on the bookshelf

### Requirement: Offline management visibility
The page SHALL continue to list imported local books when no server is reachable and SHALL allow deletion of their local copies while disabling remote import/update actions.

#### Scenario: Server goes offline
- **WHEN** the management page cannot reach the previously paired server
- **THEN** imported local books remain visible and deletable, with their remote status shown as unavailable
