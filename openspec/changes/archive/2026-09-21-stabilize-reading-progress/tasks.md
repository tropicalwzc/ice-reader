# Tasks

## 1. Pin the Progress Contracts with Tests

- [x] 1.1 Extract side-effect-free helpers on `BookVM` for clamping a stored page into the current content range and for deriving a bounded shelf percentage, so both are testable without touching `UserDefaults` or iCloud.
- [x] 1.2 Add an XCTest case named `BookVMProgressTests` in `ice readerTests/` that runs against a dedicated `UserDefaults` suite, and ensure the suite is cleaned up so cases cannot leak progress into each other.
- [x] 1.3 Add `testStoredPageReadDoesNotMutateDefaults` proving a read leaves the local value, the override marker, and the cloud key exactly as they were.
- [x] 1.4 Add `testStoredPageClampsToContentRange` and `testStoredPageClampsRestoredValueBeyondContent` covering negative, zero, in-range, exactly-last-index, beyond-last-index, and empty-content inputs.
- [x] 1.5 Add `testStoredPagePrefersNewerCloudRevision` and `testStoredPageNeverMovesBackward` proving a monotonic read result and that a newer override revision is only promoted by the dedicated alignment path.
- [x] 1.6 Add `testProgressKeyIsStableAcrossTitleChange` proving the storage key follows the stable local identifier and does not change when a title or source changes.
- [x] 1.7 Add `testProgressPercentageIsBounded` proving the recorded percentage is a fraction between zero and one for every clamped page, including the single-page and empty-content cases.
- [x] 1.8 Confirm the full `ice readerTests` suite passes before changing any view code, so the new cases are known to describe current behavior rather than assumed behavior.
- [x] 1.9 Add `BookVM` seams (`defaults`, `ProgressCloudSync`) so progress behavior can be tested without touching the real ubiquitous key-value store, keeping the production defaults unchanged.
- [x] 1.10 Add `testCloudProgressQueriesTolerateUnusableKeys` covering a crash found during this work: the iCloud helper built override keys with a nil sync prefix and raised `NSInvalidArgumentException`.

## 2. Separate Position, Window, and Jump Target

- [x] 2.1 Replace the single `page` state in `BookMainView` with `readingIndex` for the persisted position, `windowEnd` for the exclusive render bound, and `pendingJump` for an explicit viewport move.
- [x] 2.2 Update the render condition so content versus loading depends on whether content is loaded plus a bounded, non-empty range, instead of on a window derived from the persisted position.
- [x] 2.3 Update `stripSmallPage()` and the window extension rule so the window grows to cover `readingIndex + pageSize` and never shrinks while the user scrolls, which would rebuild the list and move the anchor.
- [x] 2.4 Re-point the jump dialog, the initial restore, and rotation at the explicit jump path, and confirm the rotation re-anchor removed by `5d9054f` is not reintroduced.
- [x] 2.5 Verify on a simulator that restore, jump, and rotation leave the viewport where the user expects and that a distant jump never shows the loading view over loaded content. (Confirmed on device by the maintainer.)

## 3. Drive Position from Visible Rows

- [x] 3.1 Report each row's vertical offset from the row container so the reader can resolve the first visible row without relying on `onAppear` ordering.
- [x] 3.2 Resolve and persist the reading position from the row nearest the top edge, writing only when the resolved row changes.
- [x] 3.3 Delete the `index == page + pageSize - 1` auto-advance block and the `isUserScrolling` / `scrollInteractionID` tail-window heuristic.
- [x] 3.4 Verify with manual scroll, slow scroll, and fast fling that progress follows the first visible row and that idle re-renders, background refreshes, and window growth write nothing. (Confirmed on device by the maintainer.)
- [x] 3.5 Remove the drag gesture, which existed only to feed the deleted heuristic.

## 4. Non-Perturbing External Alignment and Lifecycle

- [x] 4.1 Make the stored-position read pure: remove the `persistLocalReadingState` call and the applied-override marker write from `BookVM.readLastPage`.
- [x] 4.2 Add explicit `hasFreshExternalProgressOverride` / `consumeExternalProgressOverride` paths, so an override is marked applied only when the viewport actually moves.
- [x] 4.3 Re-point `onAppear`, the `MKiCloudSyncDidUpdateToLatest` observer, and `recursiveCheck` at the alignment entry point, and skip alignment entirely while the reader sits away from the stored position.
- [x] 4.4 Persist `readingIndex` before setting the save gate on `didEnterBackground`, clear the gate on `willEnterForeground` and again on `didBecomeActive`, and add `saveLastPageNow` so the flush cannot be lost to a pending background write.
- [x] 4.5 Add `testRestartPathKeepsLocalPositionAndDoesNotCopyCloud` and `testFreshOverrideRemainsPendingUntilConsumed`, so a deferred external position cannot be silently dropped.
- [x] 4.6 Keep a deliberate backward jump authoritative by publishing a new cloud revision (`forceCloudSync`) and add `testDeliberateBackwardJumpPublishesNewRevision`.
- [x] 4.7 Verify that an external iCloud change arriving during reading persists the local position first and does not yank the viewport. (Confirmed by the maintainer; deferred-alignment behavior covered by `testFreshOverrideRemainsPendingUntilConsumed`.)

## 5. Tap Gesture and Shelf Presentation

- [x] 5.1 Remove the progress write from the per-row tap gesture so tapping only reveals or hides the navigation bar.
- [x] 5.2 Confirm explicit jumps and scroll-derived updates remain the only writers of the reading position.
- [x] 5.3 Refresh the shelf percentage when the reader is dismissed, and flush the final position at the same time.

## 6. Build and Manual Verification

- [x] 6.1 Build the `ice reader` scheme for a generic iOS Simulator destination and resolve all compiler warnings introduced by the change.
- [x] 6.2 Run the full `ice readerTests` suite on a concrete simulator; 32 tests pass.
- [x] 6.3 On a concrete simulator or device, exercise cold start restore, jump dialog, manual scroll, fast fling, rotation, background/foreground, iCloud external change, dark mode, and bookshelf percentage after dismissal. (Confirmed on device by the maintainer.)
- [x] 6.4 Record the observed before/after position for each scenario in `verification.md`, including the exact build and simulator used.

## 7. Incidental Fixes Found During Implementation

- [x] 7.1 Guard `MKiCloudSync` prefix lookups so progress queries before `startWithPrefix:` return a safe value instead of raising.
- [x] 7.2 Start the cloud listener when the view model is created, so the sync prefix exists before the first progress read.
- [x] 7.3 Drop cached content when a book's bytes are replaced, so the reader cannot clamp and persist a position against a stale split count.
- [x] 7.4 Serialise position writes on a dedicated queue so two rapid updates cannot land out of order.
- [x] 7.5 Replace the lazily cached bundled cloud-key dictionary with a computed value, removing a cross-thread mutation.
