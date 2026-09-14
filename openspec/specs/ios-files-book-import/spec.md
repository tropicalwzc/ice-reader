# ios-files-book-import Specification

## Purpose
Define native multi-file novel import from iOS Files providers into app-owned storage, including validation, replacement, progress, and batch feedback.
## Requirements
### Requirement: Native Files import entry
The iOS app SHALL provide a clearly labeled action for importing novels from the system Files interface alongside the existing LAN import and local-book management actions.

#### Scenario: Open Files importer
- **WHEN** the user chooses “从文件 App 导入” from the bookshelf import controls
- **THEN** the app presents the system Files interface and permits selection of multiple files from available local, iCloud Drive, and document-provider locations

#### Scenario: Cancel selection
- **WHEN** the user dismisses the Files interface without selecting files
- **THEN** the app returns to the bookshelf without displaying an import failure or changing the library

### Requirement: Supported novel file selection
The Files importer SHALL advertise the configured text-novel content types and SHALL apply the existing filename, extension, regular-file, and 200 MB per-file validation rules after selection.

#### Scenario: Select supported novels
- **WHEN** the user selects regular files with supported `.txt`, `.text`, `.md`, `.markdown`, `.html`, or `.htm` extensions within the size limit
- **THEN** the app queues each selected file for import while preserving its safe user-visible filename

#### Scenario: Provider reports an imprecise content type
- **WHEN** a selected provider item has an imprecise or dynamic UTType but its filename and file properties satisfy the authoritative storage validation
- **THEN** the app imports it according to its supported filename extension

#### Scenario: Select an invalid item
- **WHEN** a selected item is a directory, has an unsupported or unsafe filename, exceeds the size limit, or is not a readable regular file
- **THEN** the app skips or fails that item without publishing a catalog record and continues processing the other selected items

### Requirement: Secure app-owned file copy
The app SHALL access each selected security-scoped URL only for the duration required to coordinate and copy it into a unique staged file under app-owned storage, SHALL balance granted security-scope access, and SHALL commit only a complete validated copy.

#### Scenario: Import provider-backed file
- **WHEN** the selected file is available through iCloud Drive or another document provider and security-scoped access succeeds
- **THEN** the app coordinates the read, copies the file off the main UI thread, validates its copied size and hash, atomically installs it, and releases provider access

#### Scenario: Provider access or copy fails
- **WHEN** security-scoped access, provider download, coordinated reading, storage-capacity validation, or copying fails
- **THEN** the app removes the partial staging file, releases any granted access, leaves any prior valid same-title book unchanged, and records a failure for that item

#### Scenario: Read imported book offline
- **WHEN** a Files-imported book has committed and its original provider item later becomes unavailable, moves, or is deleted
- **THEN** Ice Reader continues reading the app-owned imported copy without resolving the original provider URL

### Requirement: Bounded multi-file batch processing
The app SHALL process selected files sequentially with bounded memory, prevent overlapping Files import batches, and treat each selected item as an independent result.

#### Scenario: Mixed-result selection
- **WHEN** a selection contains both valid novels and items that cannot be imported
- **THEN** the app imports every valid novel, retains a result for every selected item, and does not abort the batch because one item fails

#### Scenario: Import is running
- **WHEN** the app is copying and validating a selected batch
- **THEN** the UI remains responsive, indicates import activity and progress, and prevents starting a second overlapping Files import batch

### Requirement: Stable same-title replacement
The app SHALL route Files imports through the shared imported-book commit behavior and SHALL replace a same-normalized-title imported book while retaining its stable local ID and reading-progress key.

#### Scenario: Replace a book imported by another source
- **WHEN** a valid Files selection has the same normalized title as a book previously imported through LAN or Files
- **THEN** the new bytes and source metadata atomically replace the prior content while the local book ID and reading progress remain unchanged

#### Scenario: New title commits
- **WHEN** a valid Files selection has no same-normalized-title imported record
- **THEN** the app creates a new imported-book record with Files source metadata and a new stable local ID

### Requirement: Bookshelf refresh and batch feedback
The app SHALL refresh the bookshelf after successful Files commits and SHALL summarize imported, replaced, skipped, and failed outcomes when the batch completes.

#### Scenario: Files import succeeds
- **WHEN** one or more selected novels commit successfully
- **THEN** those books appear on the bookshelf without an application restart and first-import guidance disappears when applicable

#### Scenario: Batch completes with failures
- **WHEN** a batch contains skipped or failed items
- **THEN** the app displays aggregate counts and actionable per-file reasons without exposing security-scoped provider paths or internal storage paths
