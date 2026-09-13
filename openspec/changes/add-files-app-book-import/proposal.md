## Why

LAN browser upload is useful for transferring a desktop library, but importing novels already stored in iCloud Drive, Downloads, or another iOS Files provider should not require a second device or a network connection. Ice Reader needs a native, multi-file Files picker that copies selected novels into the existing imported-book library safely and gives users clear per-batch results.

## What Changes

- Add a system Files importer that lets users select multiple supported novel files in one operation.
- Present Files import alongside the existing LAN import entry without removing LAN browser upload or local-book management.
- Copy each selected security-scoped file into app-owned staged storage, validate it with the existing size, extension, naming, and atomic-install rules, and release external access promptly.
- Process files independently so one rejected or unavailable provider item does not cancel the rest of the selection.
- Preserve the existing local book ID and reading progress when an imported file replaces a same-normalized-title book.
- Refresh the bookshelf after successful imports and report imported, replaced, skipped, and failed counts with actionable failure details.
- Keep recursive folder import and Files share-sheet/Open-In integration outside this initial change.

## Capabilities

### New Capabilities

- `ios-files-book-import`: Native multi-file novel selection from the iOS Files interface, secure staged copying into the imported library, replacement behavior, bookshelf refresh, and batch result feedback.

### Modified Capabilities

None. The repository currently has no archived baseline capability requiring a delta; this change integrates with the imported-book behavior being established by the active LAN and browser-upload changes.

## Impact

- Affects the SwiftUI bookshelf/import UI, `BookVM`, imported-book source metadata, and `ImportedBookStore` staging and commit APIs.
- Adds use of SwiftUI `fileImporter`, Uniform Type Identifiers, and Foundation security-scoped file access; no third-party dependency is required.
- Uses the existing Application Support imported-library directory and 200 MB per-file limit.
- Requires manual verification with local Files storage, iCloud Drive/provider-backed files, mixed valid and invalid selections, cancellation, and same-title replacement.
