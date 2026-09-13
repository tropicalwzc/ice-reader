## 1. Shared Import Storage

- [x] 1.1 Add backward-compatible Files-origin metadata to imported-book records while preserving decoding of legacy LAN and browser-upload records.
- [x] 1.2 Refactor `ImportedBookStore` to expose a source-neutral staged-file install API and migrate browser upload to it without changing existing behavior.
- [x] 1.3 Return whether a staged install created or replaced a record, preserve the stable local ID for same-normalized-title replacement, and keep catalog/file commits atomic.

## 2. Files Import Coordinator

- [x] 2.1 Centralize the supported novel extensions, picker `UTType` values, safe-name rules, and 200 MB file limit used by Files import and storage validation.
- [x] 2.2 Implement ordered per-item and aggregate batch result models for imported, replaced, skipped, and failed outcomes.
- [x] 2.3 Implement sequential off-main-actor processing that validates each selected URL independently and continues after individual failures.
- [x] 2.4 Balance security-scoped access and use `NSFileCoordinator` to copy each provider item into a unique `.partial` staging file with size and storage-capacity checks.
- [x] 2.5 Ensure every failure and interruption removes partial content, releases provider access, and leaves an existing same-title book unchanged.

## 3. SwiftUI Import Experience

- [x] 3.1 Add an import affordance that clearly exposes both “从文件 App 导入” and the existing “从局域网导入” while keeping local-book management accessible.
- [x] 3.2 Present SwiftUI `fileImporter` with multiple selection and supported novel content types, treating picker cancellation as a no-op.
- [x] 3.3 Show responsive batch activity/progress, prevent overlapping Files import batches, and connect successful commits to immediate `BookVM` bookshelf refresh.
- [x] 3.4 Present completion counts and safe actionable details for skipped or failed files, and ensure first-import guidance disappears after the first success.

## 4. Automated Verification

- [x] 4.1 Add or configure an XCTest target and cover supported/unsupported names, size limits, batch continuation, and abandoned staging cleanup.
- [x] 4.2 Add regression tests proving Files import creates a new stable record and same-title replacement across import sources preserves local ID and progress while replacing bytes and source metadata.
- [x] 4.3 Add compatibility tests proving existing catalog source cases still decode and Files-imported records remain readable from app-owned storage without the original URL.

## 5. Build and Manual Verification

- [x] 5.1 Build the `ice reader` scheme for a generic iOS Simulator destination and resolve all compiler or project-file issues.
- [ ] 5.2 On a concrete simulator or device, verify cancellation, multi-selection, mixed valid/invalid files, Chinese filenames, UTF-8 and GB18030 content, large-file rejection, and bookshelf refresh.
- [ ] 5.3 On a physical device, verify imports from local Files, iCloud Drive, and an available third-party provider, including a cloud placeholder and same-title replacement with progress retention.
