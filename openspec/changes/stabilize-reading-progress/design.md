## Context

Commit `5d9054f` ("优化旋转自动页面归位") deleted `restorePageAfterRotation()` and the `quickJumpToIndexSig` receiver from `BookMainView`. Before that, every orientation change scheduled a second `scrollTo` 0.25s later, which fought with SwiftUI's own rotation-time layout and produced a visible snap. Removing it was correct.

The perturbation reports continue, because the deleted method was only the loudest instance of a general pattern. The current `BookMainView` derives its rendered range from the same state it persists as progress:

```swift
let total = (page + pageSize < vm.splitedContents.count ? page + pageSize : vm.splitedContents.count)
if self.loadFinished && smallHeadpage < total {
    LazyVStack { ForEach(smallHeadpage ..< total, id: \.self) { ... } }
```

with an auto-advance block inside the row:

```swift
if isUserScrolling && index == page + pageSize - 1 {
    page = index
    vm.saveLastPage(name: bookName, page: page)
}
```

`page` is therefore simultaneously (a) the persisted reading position, (b) the window upper bound, and (c) the anchor argument for `scrollTo` in `submit()`, `readLastPage()`, and `checkCloudUpdateIfNeed()`. Any write to (a) rebuilds the `ForEach` range and moves (c).

`readLastPage()` in `BookVM` is also not a pure read: it calls `persistLocalReadingState`, which writes `UserDefaults` and the shelf percentage, and every caller immediately re-anchors the viewport. It is called from `onAppear`, from the `MKiCloudSyncDidUpdateToLatest` notification, and from `recursiveCheck`, a foreground loop that polls up to 10 times at 0.6s intervals. So background work can move the reader's position at any moment.

Git history confirms the direction of past fixes: `229d7bf` ("屏蔽滚动") added the `isUserScrolling` gate precisely because the auto-advance block was firing without user scrolling. That commit treated the symptom (fire rate) while leaving the state coupling intact, and the 5-second `userScrollEnded` tail window is a second-order workaround for the same coupling.

## Goals / Non-Goals

**Goals:**

- Make the persisted reading position change only as a result of an explicit user action or an explicit, deliberate alignment.
- Decouple the viewport window from the persisted position so that persisting progress can never rebuild the list range or move the scroll anchor.
- Make progress reads side-effect free, and give persistence exactly one entry point.
- Guarantee the position is flushed before suspension, and that the save gate is balanced and cannot stick.
- Lock the underlying contracts with XCTest cases so future changes cannot silently reintroduce divergence.
- Preserve the existing on-disk and iCloud key/value formats; no migration.

**Non-Goals:**

- Changing the cloud merge policy. Monotonic "larger value wins" behavior in `MKiCloudSync` stays as-is; cross-device convergence is a separate decision with its own trade-off (see Open Questions).
- Adding percentage/bookmark sync, per-chapter progress, or a reading-position history.
- Replacing `ScrollViewReader`/`LazyVStack` with a `UIScrollView`/`UICollectionView` bridge or a page-curl container. Out of scope; the state-model fix is intended to be sufficient.
- Changing imported-book identity, storage keys, or the bookshelf layout.
- Touching the rotation behavior that `5d9054f` removed; that path must not come back.

## Decisions

### Split `page` into three explicit states

Introduce distinct state with one job each, and make the ownership rules explicit:

- `readingIndex: Int` — the single source of truth for persisted progress. Only ever written by the position-update paths below.
- `windowEnd: Int` — the exclusive upper bound of the rendered `ForEach` range. Updated by a monotonically growing rule (`max(windowEnd, readingIndex + pageSize)`) so scrolling forward extends the window and scrolling backward does not shrink content out from under the scroll view.
- `pendingJump: Int?` — an explicit request to move the viewport, consumed once and cleared.

`smallHeadpage` keeps its meaning as the window's lower bound and continues to be refreshed by `stripSmallPage()`.

Alternative considered: keep one `page` and add a `@State windowEnd` that mirrors it with `onChange`. Rejected because two sources of truth that must agree is exactly the bug being fixed.

### Derive the reading position from visible rows

Replace the `index == page + pageSize - 1` trigger with an observation of which rows are actually on screen. Each row publishes its frame (or appear/disappear transitions) into a small `@State` collection; the position becomes `visibleRows.min()`, throttled to UI-frame cadence and written only when the resolved row changes.

Rationale: `onAppear` inside a lazy container fires on creation and on recycling, not on "the user is looking at this". The current 5-second `isUserScrolling` window is a heuristic that suppresses most spurious fires but not all of them, and it also suppresses legitimate ones. A visible-rows source removes the need for the heuristic entirely.

Alternative considered: keep `onAppear`/`onDisappear` pairing only. Rejected as the primary mechanism because disappear ordering during fast flings is not guaranteed; frame reporting with a minimum-offset resolution is more robust and directly expresses "what is at the top of the screen".

Alternative considered: scroll-offset observation via `GeometryReader` + `PreferenceKey`. Acceptable as the implementation detail for the frame source; either mechanism satisfies the requirement as long as the resolved position is "first visible row".

### One explicit entry point for persistence, pure reads

Split `BookVM`'s current `readLastPage(name:)` into:

- `storedPage(name:) -> Int` — pure. Reads local and cloud values, applies the clamp, returns. Performs no `UserDefaults` write and no cloud write. It may still consult `MKiCloudSync.overrideRevision(forKey:)` for the applied-override comparison, but must not persist the result of that comparison.
- an explicit persist operation used by `saveLastPage(name:page:forceCloudSync:)`, and a separate one-shot `applyCloudOverrideIfNeeded(name:)` for the case where an override revision genuinely advanced.

`BookMainView` then has two clearly named paths: `persistPosition()` (writes `readingIndex`) and `alignToStoredPosition()` (reads, then requests a jump if and only if the resulting index differs from `readingIndex`). Restoring on first appear uses the align path once; `onAppear` on subsequent appearances does not re-anchor.

Rationale: the current code hides a write inside a getter, so callers cannot tell whether reading is safe. `checkCloudUpdateIfNeed()` calling `readLastPage()` mutates local storage on every check, which is how the view's `page` and the stored value diverge.

### Keep the window guard from ever collapsing to the loader

The condition that currently decides between content and `LoadingView` mixes "content is loaded" with "the window is non-empty":

```swift
if self.loadFinished && smallHeadpage < total { ... } else { LoadingView() }
```

These become independent: content versus loader depends only on whether content is loaded; the window is always derived as a valid, non-empty range when content is loaded (`windowEnd = clamp(max(windowEnd, readingIndex + pageSize), 1, count)`, lower bound `min(smallHeadpage, readingIndex)`). This removes the mechanism by which a distant alignment empties the reading area.

### Align to cloud without perturbing an active reader

The alignment entry point flushes `readingIndex` first, then reads the stored position, then jumps only if the user is not actively positioned elsewhere. Concretely: an alignment that would move the position while the reader is scrolled away from the persisted value is deferred rather than applied immediately, and an alignment is never allowed to rebuild the window from scratch.

The cloud merge policy itself is unchanged in this change. `readLastPage` continues to take `max(local, cloud)`, so cross-device "one device read further" behavior is preserved and documented rather than silently altered.

### Taps no longer write progress

The per-row `.onTapGesture` currently both reveals the navigation bar and assigns `page = index` plus a save. Only the navigation-bar reveal stays. Explicit jumps (the jump dialog) and scroll-derived position updates remain the only writers.

Rationale: the hit area is the `Text`, not the row container, so an incidental tap or the start of a drag can land on a neighbouring row and silently rewrite progress.

### Balanced save gate and flush before suspension

`blockSaveAction` is set on `didEnterBackground` and cleared on `willEnterForeground`. It has no other reset, and the background transition never records the current position. Replace this with: flush `readingIndex` on the way into the background, then set the gate; clear the gate on the way out; and make the gate's lifetime owned by a single helper so it cannot remain stuck `true` across a launch that skipped the foreground notification.

## Risks / Trade-offs

- [Rewriting `BookMainView`'s state model regresses the cold-start restore that `f59bbbd` fixed] → Keep the restore sequence's ordering (content loaded, then clamp, then jump) and cover it with the existing simulator scenario; the align path is a rename of the current first-appear behavior, not a redesign.
- [Visible-row observation adds per-frame work and could jank large books] → Throttle writes to position changes only, resolve the top row arithmetically from reported frames, and keep the per-row payload to a row index plus offset.
- [Removing the `isUserScrolling` gate re-exposes the phantom auto-advance that `229d7bf` suppressed] → The visible-rows source is strictly more accurate than the gate; if a regression appears, keep the gate as a secondary guard rather than the primary trigger.
- [Window growth never shrinking increases memory on long sessions] → The window is bounded by `readingIndex + pageSize` and `LazyVStack` still virtualizes rendering; only the `ForEach` range widens. Acceptable, and separate from progress correctness.
- [Pure reads change when the applied-override marker advances] → Move the marker write into the explicit alignment path and cover it with a test; the marker exists to suppress repeated cloud overrides, not to be a read side effect.
- [Removing the tap-to-save changes existing behavior users may rely on] → Explicit jumps and scrolling still update progress; the jump dialog remains the precise tool. Note the change in the commit message as user-visible.

## Migration Plan

1. Add the pure progress-read and clamping contracts plus XCTest cases, so the contracts are pinned before the view changes.
2. Split `page` into `readingIndex` / `windowEnd` / `pendingJump` and update the render condition, keeping behavior otherwise identical; build and verify restore, jump, and rotation manually.
3. Replace the auto-advance trigger with visible-row observation and delete the `isUserScrolling` tail-window heuristic; verify manual scrolling and fast flings.
4. Make reads pure, add the explicit persist/align entry points, and re-point `onAppear`, the cloud notification, and `recursiveCheck` at them.
5. Remove progress writes from the tap gesture; rebalance the save gate and add the flush-before-suspend.
6. Execute the simulator scenarios in `verification.md` and the command-line build.

Rollback is per-step: steps 1–2 and 5 are independent of steps 3–4, and no step changes the on-disk format, so any subset can be reverted without data migration.

## Open Questions

- Should cross-device convergence stop being "larger value wins"? A reader on device B who is behind device A is currently pulled forward on foreground. Fixing that needs a device-scoped or timestamp-scoped comparison in `MKiCloudSync`, which is deliberately excluded here.
- Should the persisted position be the top visible row or the row that occupies the largest share of the screen? The top-row rule is chosen for predictability and to match the existing `anchor: .top` restore behavior.
- Should the shelf percentage continue to be written on every position update, or batched to reduce `UserDefaults` traffic during long scrolls? Deferred until the position pipeline is stable.
