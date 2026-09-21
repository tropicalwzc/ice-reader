# Verification

Status: implementation landed on branch `main` (uncommitted at the time of writing). Automated evidence below was produced by the commands shown; interactive simulator scenarios remain open and are listed at the end.

## Automated evidence

| Command | Result |
| --- | --- |
| `xcodebuild -workspace "ice reader.xcworkspace" -scheme "ice reader" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16 Pro" -derivedDataPath /tmp/ice-reader-dd test` | `** TEST SUCCEEDED **`, 32 tests, 0 failures |
| `xcodebuild -workspace "ice reader.xcworkspace" -scheme "ice reader" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/ice-reader-dd-generic build` | `** BUILD SUCCEEDED **` |

No compiler warnings are attributable to the changed files. The only warnings in the logs are the pre-existing `CombineCocoa` deployment-target warning and the AppIntents metadata notice.

New cases in `ice readerTests/BookVMProgressTests.swift`, all passing:

| Case | Demonstrates |
| --- | --- |
| `testStoredPageReadDoesNotMutateDefaults` | Local value, percentage, cloud key, and applied marker are identical before and after a read |
| `testStoredPageClampsToContentRange` | Clamp behavior for negative, zero, last-index, beyond-last-index, and empty content |
| `testStoredPageClampsRestoredValueBeyondContent` | A restored value past the end resolves to the last valid index |
| `testStoredPagePrefersNewerCloudRevision` | A strictly newer revision wins even when smaller; an older revision is ignored |
| `testStoredPageNeverMovesBackward` | A smaller cloud value never replaces a larger local position |
| `testRestartPathKeepsLocalPositionAndDoesNotCopyCloud` | Local 300 vs cloud 200 resolves to 300 and re-persists 300 with the correct percentage |
| `testDeliberateBackwardJumpPublishesNewRevision` | A deliberate backward jump publishes the value as a new revision |
| `testFreshOverrideRemainsPendingUntilConsumed` | Peeking at a fresh override does not consume it, so a deferred alignment is not dropped |
| `testConsumedExternalOverrideIsNotReplayed` | The same revision is applied at most once |
| `testProgressKeyIsStableAcrossTitleChange` | The storage key is `ImportedBook.<localID>` plus `ReadingProgress` |
| `testProgressPercentageIsBounded` | Percentage stays within `0...1`, including single-page and empty content |
| `testCloudProgressQueriesTolerateUnusableKeys` | Non-progress and empty keys do not raise; `NSInvalidArgumentException` regression covered |

The pre-existing `testCloudRestoredPagePersistsLocalPageAndProgress` was renamed to `testCloudRestoredPageIsResolvedWithoutWritingLocalStorage` and now asserts the new contract: the read reports the cloud value and writes nothing, while the explicit persistence path records both the page and the percentage.

## Simulator checks performed

- Installed the Debug build on a booted iPhone 16 Pro simulator and launched it repeatedly; the process stayed alive and no crash report was produced in `~/Library/Logs/DiagnosticReports`.
- Seeded the bundled placeholder's progress directly in the app container plist (`样例占位 = 300`, `syncIRA0 = 200`) with the applied-override marker set, then launched and terminated cleanly. After the run the local value was still `300`; the smaller cloud value was not copied over it. This exercises the restart path against the real store rather than a test suite.
- The same run also exercised a store that already contained real iCloud values (progress `12` plus an override revision). The observed behavior matched the documented policy: the newer cloud override wins and is merged into the preference keys by `MKiCloudSync`, while the app's own read path writes nothing.

## Interactive scenarios still required

These need a person driving the UI. Each row records the position before and after the event; a perturbation is any position change the user did not cause.

| Scenario | Pass condition | Result |
| --- | --- | --- |
| Cold start with saved progress | Viewport lands on the stored page once and stays there | pending |
| Jump dialog to an earlier and a later page | Viewport moves to the requested page; content stays visible throughout | pending |
| Manual scroll, slow and fast | Progress follows the first visible row; no jump during or after the scroll settles | pending |
| Idle for 30s after scrolling | Progress and viewport unchanged despite re-renders and window growth | pending |
| Rotate device while reading | Viewport keeps the same reading position; no extra re-anchor | pending |
| Background then foreground | The last read position is preserved and the shelf percentage matches it | pending |
| Tap text to reveal navigation bar | Progress unchanged | pending |
| Dismiss reader to shelf | Shelf percentage reflects the final position | pending |
| Switch to another app and back while scrolled away from the stored page | External alignment is deferred; the viewport is not moved mid-read | pending |

## Physical-device checks still required

- Two devices signed into the same iCloud account: confirm that a deliberate backward jump on one device propagates, and record whether a device that is behind is pulled forward (the monotonic merge is deliberately unchanged by this change).
- Low-memory interruption in the background followed by relaunch, to confirm the save gate is cleared and progress is not lost.

## Known limitations accepted by this change

- The cloud merge policy remains "larger value wins" unless a deliberate override revision is newer. A device that is behind another device is still pulled forward on alignment; changing that needs a separate change with device- or timestamp-scoped comparison.
- `MKiCloudSync.mergeLocalAndCloudProgress` runs on `NSUserDefaultsDidChangeNotification` and writes the winning value back into the app's preference keys. That behavior is outside this change; the reader no longer adds to it, but a stale newer override in the cloud can still be merged into preferences before the reader opens.
- Window growth is monotonic within a reading session; the `ForEach` range widens as the reader advances and is not compacted back down. `LazyVStack` still renders only visible rows.
- Isolation is per book and per session: if the writer switches to a different book without leaving the reader screen, an alignment is deferred while the position is off the stored value.
