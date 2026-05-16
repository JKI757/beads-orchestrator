# Beads-Orchestrator Implementation Plan

## Project Shape

Beads-Orchestrator is a single Xcode project with two app targets:

- `Beads-Orchestrator iOS`: iPhone and iPad from one adaptive SwiftUI target.
- `Beads-Orchestrator macOS`: native macOS app target.

Most code lives in shared source folders and is compiled into both targets:

- `BeadsOrchestratorShared/Models`
- `BeadsOrchestratorShared/ViewModels`
- `BeadsOrchestratorShared/Views`
- `BeadsOrchestratorShared/Services`

Platform-specific code should stay small:

- `Apps/iOS`
- `Apps/macOS`

## Buildable MVP Slices

### Slice 1: Static Board

- Shared board, column, and bead models.
- Shared sample data.
- Shared SwiftUI kanban board.
- Shared bead detail inspector.
- iOS/iPadOS adaptive navigation.
- macOS window with sidebar, board, and inspector.

### Slice 2: Local Board Editing

- Create, rename, archive, and delete boards.
- Create, edit, move, reorder, and archive beads.
- Persist local state.
- Add search and basic filters.

### Slice 3: Local Git Read-Only Integration

- Add repository picker.
- Read current branch, local changes, remotes, and recent commits.
- Suggest beads for uncommitted changes and stale branches.
- Link beads to branches and file paths.

### Slice 4: GitHub Integration

- Authenticate with GitHub.
- Import open issues and pull requests.
- Show PR status, labels, checks, review state, and last update time.
- Open GitHub source links.

### Slice 5: Platform Polish

- macOS menu commands, keyboard shortcuts, and multi-window behavior.
- iPadOS split layout and pointer/keyboard support.
- iOS compact column navigation and notification settings.

## Reuse Rules

- Do not fork board behavior by platform unless the interaction model truly requires it.
- Add platform branches inside shared views only for presentation differences.
- Keep source integrations UI-independent.
- Keep persistence UI-independent.
- Treat macOS, iOS, and iPadOS as clients of the same product model.
