## Why

Commit `5d9054f` removed the extra post-rotation re-anchor (`restorePageAfterRotation` + `quickJumpToIndexSig`) that teleported the viewport after every orientation change. That was one perturbation path, but the mechanism that generates perturbations is still in place, so users continue to see the reading position move on its own.

The root cause is a state-model problem, not a single bad line. `BookMainView` uses one `@State var page` for three different jobs at once:

- the reading position that is persisted as progress,
- the upper bound of the `LazyVStack` window (`total = page + pageSize`),
- the anchor for `scrollTo` in jump/restore/cloud-align paths.

Because the first job changes value while the second is derived from it, every progress write rebuilds the list range and shifts the scroll anchor. On top of that, `readLastPage()` is a read-with-side-effects (it writes local storage, updates the shelf percentage, and callers immediately send a jump), and it is invoked from paths the user does not control: `onAppear`, iCloud external-change notifications, and a 10-round foreground polling loop. The result is a reader whose position is dragged around by background work rather than by the user's scrolling.

## What Changes

- Separate the three responsibilities that `page` currently holds: a persisted reading position, a viewport window bound, and an explicit jump target.
- Drive progress updates from the rows that are actually visible instead of from "`page + pageSize - 1` appeared", which fires during lazy-container recycling rather than during real user scrolling and is only loosely gated by a 5-second `isUserScrolling` window.
- Remove the window/anchor coupling that lets a jump rebuild the list range and move the viewport, and remove the path where the reading area collapses to `LoadingView` because the window condition became false.
- Make progress reads pure. Add an explicit, single entry point for "persist and move the viewport" instead of hiding a write inside a getter.
- Make the save gate (`blockSaveAction`) balanced and flush the current position before the app suspends, so the last stretch of reading is not lost and the gate cannot stick.
- Stop ordinary taps from rewriting progress; navigation-bar reveal and progress update should not be the same gesture.
- Keep the existing cloud merge semantics (monotonic, larger-value-wins) unchanged in this change; cross-device convergence is documented as a deliberate, separate decision.
- Add XCTest coverage for progress reading, clamping, and storage-key behavior to lock the contracts that these fixes depend on.

## Capabilities

### New Capabilities

- `reading-progress-integrity`: The reader's position, its persistence, and its relationship to the scroll viewport. Defines single-source-of-truth progress, user-driven position updates, non-perturbing external alignment, and the persistence/read contracts that protect progress.

### Modified Capabilities

None. `imported-book-storage` already owns catalog identity, atomic storage, and stable per-book progress keys; this change only adds the reader-side behavior layered on top of those keys and does not alter imported-book storage requirements.

## Impact

- Primary code: `ice reader/App/BookMainView.swift` (state model, scroll observation, jump/restore/align paths, lifecycle handling) and `ice reader/App/BookVM.swift` (`readLastPage`, `saveLastPage`, progress clamping and percentage writes).
- Secondary: `ice reader/App/BookShelfView.swift` (percentage refresh timing) and `ice reader/App/OC/MKiCloudSync.m` only if the alignment path needs a pure revision read; no change to the merge policy in this change.
- Tests: `ice readerTests/` (existing XCTest target). New cases cover progress reading, clamping, storage-key stability, and the percentage contract.
- No new dependency, no persistence-key migration, no bundled-resource change. Existing `UserDefaults`/iCloud keys and values remain readable and writable.
- Verification requires simulator scenarios for rotation, background/foreground, iCloud-external-change during reading, jump dialog, and manual scroll, plus a command-line build.
