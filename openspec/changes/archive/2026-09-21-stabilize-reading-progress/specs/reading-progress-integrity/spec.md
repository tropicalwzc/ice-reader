## ADDED Requirements

### Requirement: Single source of truth for reading position
The reader SHALL maintain exactly one state value that represents the persisted reading position, and SHALL derive the scroll viewport window and any scroll anchor from state that is independent of that value.

#### Scenario: Persisting the position does not move the viewport
- **WHEN** the reader persists the current reading position
- **THEN** the rendered list range and the scroll anchor remain unchanged

#### Scenario: Jumping does not redefine the persisted position
- **WHEN** the user jumps to a page through the jump dialog
- **THEN** the viewport moves to that page and the persisted position becomes that page, without the jump being treated as a new window boundary

#### Scenario: Window remains valid after a distant alignment
- **WHEN** an alignment or jump sets the reading position far from the current window's lower bound
- **THEN** the reader renders a non-empty, content-backed range around the new position and does not replace the reading area with a loading indicator

### Requirement: Position updates are user-driven
The reader SHALL update the persisted reading position only from explicit user actions or scroll-derived visibility, and SHALL NOT treat lazy-container row creation or recycling as a user scroll.

#### Scenario: Idle recomputation does not change progress
- **WHEN** the reader re-renders, recycles rows, or refreshes its list while the user is not scrolling
- **THEN** the persisted reading position is unchanged

#### Scenario: Scrolling forward updates progress
- **WHEN** the user scrolls forward and a new row becomes the first visible row
- **THEN** the persisted reading position becomes that row

#### Scenario: Fast fling does not record a skipped row
- **WHEN** the user performs a fast fling and intermediate rows are created and destroyed without becoming the first visible row
- **THEN** the persisted reading position reflects a row that was actually visible, not a row that merely appeared during recycling

#### Scenario: Incidental tap does not move progress
- **WHEN** the user taps the text to reveal or hide the navigation bar without changing the visible page
- **THEN** the persisted reading position is unchanged

### Requirement: External alignment does not perturb an active reader
The reader SHALL persist its current position before evaluating any external update, and SHALL NOT move the viewport for an external update when doing so would discard a position the user is actively reading.

#### Scenario: Cloud update arrives while the user is reading elsewhere
- **WHEN** an external iCloud change notification arrives while the reader's current position differs from the stored position
- **THEN** the reader persists its current position first and does not move the viewport to the external value during that interaction

#### Scenario: Cold start restores the stored position once
- **WHEN** the reader first appears for a book and the stored position is valid for the current content
- **THEN** the reader moves the viewport to that position exactly once

#### Scenario: Returning to the reader does not re-anchor
- **WHEN** the reader becomes visible again without a content reload, such as after returning from another screen
- **THEN** the reader does not move the viewport or rewrite progress

#### Scenario: Alignment cannot move progress backward
- **WHEN** the stored position differs from the current position only because the stored value is smaller
- **THEN** the reader keeps the larger current position and does not persist the smaller value as a result of the read

### Requirement: Saving is explicit, pure, and complete
Reading the stored position SHALL NOT write local storage or cloud storage, and the app SHALL persist the current position when reading is interrupted by suspension.

#### Scenario: Read has no side effects
- **WHEN** any caller reads the stored position for a book
- **THEN** local storage and cloud storage retain the values they held before the read, except for a deliberate cloud-override application performed by its dedicated path

#### Scenario: Suspension captures the last position
- **WHEN** the app enters the background while the reader is open
- **THEN** the current reading position is persisted before saving is suppressed

#### Scenario: Save gate cannot remain stuck
- **WHEN** the app resumes on a launch path that did not receive a background transition
- **THEN** progress saving is enabled and subsequent position updates persist normally

### Requirement: Restored positions are clamped and stable
The reader SHALL clamp a restored position into the valid range of the current content, persist the corrected value, and key progress by the book's stable identifier rather than its title or list position.

#### Scenario: Content became shorter
- **WHEN** the stored position exceeds the last valid index of the current content
- **THEN** the reader restores the last valid index and persists the corrected position

#### Scenario: Key survives a title change
- **WHEN** an imported book's title or source changes while its local identifier is preserved
- **THEN** the reader reads and writes progress under the same storage key as before

#### Scenario: Shelf percentage stays in range
- **WHEN** the reader persists a valid position for loaded content
- **THEN** the recorded shelf percentage is between zero and one inclusive
