## Context

Ice Reader already has a persistent imported-book catalog and app-owned content under Application Support. Browser uploads stage bytes, validate them, atomically commit them, and replace a same-title record while preserving its stable local ID. The new path must reuse those invariants while accepting URLs returned by the iOS document picker.

Picker URLs can belong to iCloud Drive or third-party document providers and are outside the app sandbox. Access is temporary, may require the provider to download content, and must not be retained as the reader's permanent source. Importing several large novels must also avoid blocking SwiftUI's main actor or holding multiple provider resources open at once.

The deployment target is iOS 16.1, so SwiftUI `fileImporter`, multiple selection, `UniformTypeIdentifiers`, security-scoped URL access, and coordinated file reads are available without another dependency.

## Goals / Non-Goals

**Goals:**

- Offer an understandable native Files import action alongside LAN browser import.
- Import multiple selected novels safely, sequentially, and independently.
- Reuse one storage commit path and preserve existing replacement/progress behavior across every import source.
- Keep provider access short-lived and leave no partial book or catalog record after failure.
- Give a useful batch summary and refresh the bookshelf as valid books commit.

**Non-Goals:**

- Recursive directory selection and enumeration.
- Receiving files from the Files share sheet, Open In, or a Share Extension.
- Reading directly from external provider URLs or retaining security-scoped bookmarks.
- Adding formats beyond the extensions already accepted by imported-book storage.
- Changing LAN browser upload or exposing the app's internal Documents directory in Files.

## Decisions

### Present a multi-file SwiftUI system importer

The bookshelf import affordance will expose both “从文件 App 导入” and “从局域网导入”. The Files action presents `fileImporter` with `allowsMultipleSelection: true`. A single “导入小说” menu is preferred where toolbar space is limited, while local-book management remains a separate action.

Allowed picker types will be assembled from the configured supported extensions using `UTType(filenameExtension:conformingTo:)`, with appropriate system text types included. Selection filtering improves the picker experience, but the storage layer remains authoritative because document providers can report broad, dynamic, or inaccurate types.

Alternative considered: `UIDocumentPickerViewController` through `UIViewControllerRepresentable`. SwiftUI's importer supplies the required multi-selection and security-scoped URLs on the deployment target with less bridging and lifecycle code.

### Copy sequentially into app-owned staging

The importer will hand selected URLs to an asynchronous import coordinator. It will process one URL at a time off the main actor to bound memory and the number of active provider resources. For each URL it will:

1. Obtain security-scoped access and guarantee balanced release with `defer` when access was granted.
2. Read coordinated resource metadata, reject directories, unsupported names/extensions, files over 200 MB, and files that cannot fit available storage.
3. Copy or stream the source through `NSFileCoordinator` into a unique `.partial` staging file under the existing imported-library area.
4. Verify the actual copied byte count and compute the content hash before committing.
5. Invoke a source-neutral imported-file commit API and always remove an abandoned staged file.

The app stores its own final copy and does not retain bookmarks. This makes imported books available offline and independent of provider renames, deletion, or revoked access.

Alternative considered: retain the chosen URL and read it in place. That would require persistent bookmark lifecycle management and would make reading depend on network/provider availability, so it is rejected.

### Generalize storage commit without duplicating browser logic

`ImportedBookStore` will expose a source-neutral staged-file installation operation. Browser upload and Files import will both supply a validated staging URL, original filename/display name, expected size, and source metadata to the same atomic commit logic. A Files-origin source case will be persisted in a backward-compatible way; decoding older source cases remains unchanged.

Same-normalized-title installation replaces the existing bytes and updates source metadata while retaining the existing local ID. Therefore the progress key remains stable whether the previous copy came from LAN browser upload, legacy LAN download, or Files.

Alternative considered: call the browser-specific `installBrowserUpload` method from the picker. That would encode a false source and keep transport-specific naming in the storage boundary, so the API will instead be generalized.

### Model import as a batch with per-item outcomes

The coordinator returns ordered per-file outcomes categorized as imported, replaced, skipped, or failed. An unsupported or inaccessible item is recorded and processing continues. Cancellation of the system picker produces no error. Once copying has begun, the UI shows an importing state, prevents a second overlapping batch, and remains responsive.

Successful commits notify `BookVM` so the bookshelf can refresh without relaunching. At completion, the app presents aggregate counts and concise details for failed/skipped items; it does not expose provider paths or internal filesystem paths.

## Risks / Trade-offs

- [Some providers delay while downloading an iCloud placeholder] → Coordinate reads off the main actor, expose an importing state, and handle provider errors per item.
- [Provider content changes between metadata lookup and copy] → Treat copied byte count and hash as authoritative and commit only the completed staged copy.
- [UTType filtering hides a valid legacy text file] → Include extension-derived types and keep the supported-extension list centralized; validate selected names independently.
- [A large multi-selection takes time] → Process sequentially with bounded memory and show batch progress rather than opening all URLs concurrently.
- [App interruption leaves temporary content] → Use unique `.partial` files, clean them in `defer`, and reuse startup cleanup for abandoned staging files.
- [Two import paths create inconsistent overwrite behavior] → Route both paths through the same source-neutral commit function and add replacement regression tests.

## Migration Plan

1. Add backward-compatible Files source metadata and source-neutral staged installation while retaining decoding for existing catalog records.
2. Add the import coordinator and picker UI, then connect successful commits to the existing bookshelf refresh flow.
3. Build and manually test local, iCloud/provider-backed, mixed-result, large-file, and same-title cases.
4. Rollback can remove the picker UI and coordinator while leaving already imported app-owned files readable; the catalog decoder must continue accepting the Files source case if a released build has written it.

## Open Questions

- Whether a future change should add recursive folder selection, which needs separate provider and cancellation testing.
- Whether a future change should register document types or add a Share Extension so users can send books to Ice Reader directly from the Files app share sheet.
