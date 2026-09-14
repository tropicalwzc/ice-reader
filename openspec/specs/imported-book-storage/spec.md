# imported-book-storage Specification

## Purpose
Define the durable on-device catalog, file safety, decoding, reading progress, and bookshelf behavior shared by every supported novel import source.
## Requirements
### Requirement: Persistent imported-book catalog
The app SHALL persist imported-book metadata independently from the hard-coded bundled list, including a stable local ID, title, extension, relative file path, source-specific metadata, content hash, size, and import date.

#### Scenario: App relaunch
- **WHEN** the application launches after one or more successful imports
- **THEN** it reconstructs the imported bookshelf entries from the persisted catalog without contacting a server

### Requirement: Minimal bundled placeholder
The app SHALL bundle only the readable `样例占位.txt` novel and SHALL obtain all other novels through the imported-book catalog without deleting their external source files.

#### Scenario: Inspect built application resources
- **WHEN** the iOS application target is built
- **THEN** `样例占位.txt` is the only bundled novel text resource

#### Scenario: Upgrade with a removed bundled title selected
- **WHEN** saved last-read state names a former bundled title that is neither bundled nor imported
- **THEN** the app clears that unavailable last-read reference safely

### Requirement: Atomic imported content storage
The app SHALL store imported content beneath its Application Support directory, copy or download into a temporary file, verify the completed byte count and SHA-256, and atomically install or replace the final file before committing catalog changes.

#### Scenario: New file passes validation
- **WHEN** a completed temporary download matches the advertised size and hash
- **THEN** the app atomically installs it and commits the corresponding catalog record

#### Scenario: File fails validation
- **WHEN** a completed download does not match advertised metadata
- **THEN** the app discards the temporary file and does not expose invalid content on the bookshelf

### Requirement: Read bundled and imported sources
The content loader SHALL resolve bundled books from the application bundle and imported books from their persisted local paths, decoding text as UTF-8 first and GB18030 second.

#### Scenario: Read imported GB18030 book
- **WHEN** a valid imported `.txt` file cannot be decoded as UTF-8 but can be decoded as GB18030
- **THEN** the reader loads and splits the decoded content using the existing reading flow

#### Scenario: Imported file is missing
- **WHEN** a catalog record points to a missing or unreadable local file
- **THEN** the app reports the book as unavailable and does not render placeholder text as book content

### Requirement: Stable imported reading progress
Imported-book reading progress SHALL be keyed by stable local book ID rather than title, filename, source list position, or server content hash, and SHALL remain device-local for this change.

#### Scenario: Source metadata changes
- **WHEN** an imported book is updated through a supported import source
- **THEN** the app updates its source metadata without losing its local reading progress

#### Scenario: Updated content is shorter
- **WHEN** preserved progress refers beyond the split count of updated content
- **THEN** the app clamps the restored position to a valid location and saves the corrected progress

#### Scenario: Same-title book is imported from another source
- **WHEN** a verified import has the same normalized title as an existing imported book but comes from a different supported source
- **THEN** the app atomically overwrites the existing local content, updates its source metadata, and retains the same local book ID and reading-progress key

### Requirement: Unified bookshelf presentation
The bookshelf SHALL present valid imported books after the bundled placeholder and refresh after import, update, or deletion.

#### Scenario: Import completes
- **WHEN** a book is committed to imported storage
- **THEN** it appears on the bookshelf without requiring application restart

#### Scenario: Local copy is deleted
- **WHEN** an imported catalog record and file are removed
- **THEN** its bookshelf entry disappears while the bundled placeholder remains
