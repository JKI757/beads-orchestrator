# Beads-Orchestrator PRD

## Overview

Beads-Orchestrator is a native macOS, iOS, and iPadOS app for visually managing work in a software repository. The product presents repository activity as a Trello-like kanban board where each card is a "bead": a compact unit of work tied to issues, branches, pull requests, commits, files, tasks, or local notes.

The app is intended for solo developers and small teams who want a spatial, visual way to understand what is happening in a repo without living entirely inside terminal output, GitHub tabs, or project management tools.

## Problem

Modern repositories accumulate work across many surfaces: issues, PRs, branches, TODOs, commit history, local changes, design notes, and release tasks. Existing tools are good at showing each surface individually, but they often fail to answer simple operational questions quickly:

- What is actively being worked on?
- What is blocked?
- What needs review?
- What changed locally but has not been connected to an issue or PR?
- Which pieces of work are drifting or stale?
- What should I pick up next?

Developers often maintain this state mentally or across disconnected tools. Beads-Orchestrator creates a single visual workspace that maps repo activity into an editable kanban board.

## Goals

- Provide a clear kanban-style view of work happening in one or more repositories.
- Represent each unit of work as a bead with useful repo context.
- Support macOS, iPadOS, and iOS with platform-appropriate native interactions.
- Make repo state understandable at a glance through columns, grouping, filters, status indicators, and visual metadata.
- Allow manual planning while preserving links to source-of-truth systems such as GitHub, GitLab, local Git, and issue trackers.
- Work well for individual developers first, with a path toward lightweight team collaboration.

## Non-Goals

- Replace GitHub, GitLab, Linear, Jira, or a full issue tracker.
- Become a full Git GUI for every advanced Git operation.
- Require users to adopt a rigid workflow.
- Automatically make code changes or perform risky repository operations without explicit user action.
- Provide real-time multiplayer collaboration in the first release.

## Target Users

### Solo App Developer

A developer working across a few personal or client repositories who wants a calm board showing active tasks, local changes, PRs, and release prep.

### Small Product Team Engineer

An engineer who wants a repo-centered view that cuts across issue tracker tasks, PRs, branches, and code review status.

### Technical Lead

A lead who wants to scan work in progress, identify stale branches, blocked PRs, review load, and unplanned local changes.

## Core Concepts

### Bead

A bead is the primary card object. A bead can represent:

- Issue
- Pull request or merge request
- Branch
- Commit range
- Local working tree change
- TODO or code annotation
- Release task
- Manual note

Each bead may include title, status, source, assignee, labels, branch, PR number, modified files, timestamps, dependency links, checklist items, and comments.

### Board

A board is a visual workspace connected to a repository or repo group. Boards contain columns and beads. Boards can be manually configured or generated from templates.

### Column

A column represents a workflow state. Default columns:

- Backlog
- Ready
- In Progress
- Blocked
- Review
- Done

Users can rename, reorder, add, and archive columns.

### Source

A source is an integration that provides repo or work data:

- Local Git repository
- GitHub
- GitLab
- Linear
- Jira
- Manual entry

First release should prioritize local Git and GitHub.

## User Experience

### Product Feel

The interface should feel like a native productivity tool: dense enough for daily engineering work, visual enough to make state obvious, and calm enough to leave open all day.

The board should be visually related to Trello without copying it directly:

- Horizontal columns
- Draggable cards
- Compact metadata
- Quick filters
- Detail pane for selected card
- Clear empty states
- Low-friction card creation

The app should avoid a marketing-dashboard feel. It should prioritize scanning, triage, and repeated use.

### macOS Experience

macOS is the primary power-user platform.

Expected behaviors:

- Multi-window support
- Sidebar for repositories and saved boards
- Main kanban board
- Inspector/detail pane
- Keyboard shortcuts for navigation, moving beads, filtering, and creating beads
- Menu bar commands
- Drag and drop between columns
- Local repository picker
- Optional background refresh
- Deep links to files, PRs, issues, and terminal commands

### iPadOS Experience

iPadOS should support planning, review, and triage.

Expected behaviors:

- Adaptive split view layout
- Pencil-friendly card selection and drag interactions
- Touch-first column scrolling
- Detail sheet or side panel
- Stage Manager-friendly resizing
- External keyboard shortcuts where practical

### iOS Experience

iOS should focus on quick review and lightweight updates.

Expected behaviors:

- Compact board view
- Column-by-column navigation
- Quick filters
- Bead detail screen
- Status changes
- Comments and notes
- Notifications for review, blockers, and stale work

## Primary Workflows

### Connect a Repository

1. User selects "Add Repository."
2. User chooses a local Git repo or connects GitHub.
3. App scans branches, local changes, open PRs, and issues.
4. App suggests a default board.
5. User confirms columns and import rules.

Success criteria:

- A useful board is generated within 30 seconds for a typical repo.
- User understands what data was imported and what remains manual.

### Create a Bead

1. User taps or clicks "New Bead."
2. User enters title.
3. User optionally links branch, issue, PR, file, or label.
4. Bead appears in selected column.

Success criteria:

- Manual bead creation takes less than 10 seconds.
- Linking repo context is optional and discoverable.

### Triage Repo State

1. User opens a board.
2. App highlights stale PRs, uncommitted changes, blocked items, and review requests.
3. User filters by source, assignee, label, branch, or age.
4. User moves beads between columns.

Success criteria:

- User can answer "what needs attention?" without opening another tool.

### Review a Bead

1. User selects a bead.
2. Detail pane opens with repo metadata, linked artifacts, checklist, activity, and notes.
3. User opens related PR, file, branch, or issue.
4. User updates status or adds notes.

Success criteria:

- Bead detail is useful without overwhelming the board.

### Sync with Source Systems

1. App refreshes local Git and integration data.
2. App updates linked beads.
3. Conflicts between manual board state and source state are shown clearly.

Success criteria:

- Sync never silently overwrites deliberate board organization.

### Connect Mobile Clients to a Mac Server

1. User opens Beads-Orchestrator on macOS.
2. The macOS app starts a local Beads server and exposes a pairing QR code for the local network or Tailscale.
3. User scans the QR code on iPhone or iPad.
4. The QR payload configures the Mac server URL and a bearer pairing token.
5. iPhone and iPad can test the pairing, cache the current board state, and send mutations to the Mac.

Success criteria:

- iPhone and iPad can connect to a Mac on the same local network or Tailscale without external cloud infrastructure.
- Connection status and failures are visible without disrupting the board UI.
- The macOS server is the canonical board state.
- Mobile clients are views with a local cache for offline launch and optimistic updates.
- Mobile mutations require a valid pairing token.

## Functional Requirements

### Board Management

- Create, rename, duplicate, archive, and delete boards.
- Create boards from templates.
- Support one repo per board in MVP.
- Future support for multi-repo boards.
- Persist column order and bead order.
- Support board-level filters and saved views.

### Bead Management

- Create, edit, archive, and delete beads.
- Drag beads between columns.
- Reorder beads within columns.
- Add title, description, labels, status, source link, branch, PR, issue, due date, priority, checklist, and notes.
- Show visual indicators for source type, stale age, blocked state, review state, local changes, and sync conflict.
- Support manual beads with no linked source.

### Repository Integration

- Add local Git repositories.
- Detect current branch, local changes, remote branches, recent commits, and stale branches.
- Link beads to branches and commits.
- Show uncommitted changes as suggested beads.
- Open files in the user’s preferred editor where feasible.
- Open terminal at repo path.

### GitHub Integration

- Authenticate with GitHub.
- Import open issues.
- Import open pull requests.
- Link beads to issues and PRs.
- Show PR status, review state, checks state, author, assignees, labels, and last updated time.
- Open GitHub links externally.

### Search and Filtering

- Search bead titles, descriptions, labels, branches, PRs, issues, and file paths.
- Filter by source, label, assignee, status, age, repository, branch, and blocked state.
- Save commonly used filters as views.

### Notifications

- Notify when a PR needs review.
- Notify when checks fail.
- Notify when a blocked bead changes state.
- Notify when a bead becomes stale.
- Notifications must be configurable per board and per source.

### Offline and Sync

- Mobile clients may cache board data for offline launch and read-only review.
- The macOS server owns canonical board state.
- Integration data should sync when connectivity returns.
- Manual edits on paired mobile clients should be sent to the Mac server and reflected back into the local cache.
- Offline mobile edits should either be disabled or queued explicitly until conflict-aware mutation replay exists.
- Sync conflicts should be visible and resolvable once queued offline mutations are supported.

### Mac-Hosted Server

- The macOS app must be able to run an HTTP server for iOS and iPadOS clients.
- The server must expose health/status information.
- The server must expose board read and mutation APIs.
- The server should be reachable over same-network local IPs, `.local` hostnames where available, and Tailscale addresses.
- The server should be controllable from the macOS toolbar or app settings.
- The macOS app should display a QR code containing the connection URL and pairing token.
- The macOS app should support regenerating the pairing token.
- iOS and iPadOS clients must scan the QR code and persist the configured Mac server URL and pairing token.
- iOS and iPadOS clients must support test pairing and refresh from Mac.
- Authenticated endpoints must require a bearer token derived from pairing.
- Production hardening should add token storage in Keychain, token revocation UI, per-device tokens, request signing, TLS where practical, and conflict-aware incremental sync.

## Platform Requirements

- Native app built with Swift and SwiftUI.
- The app must be delivered as a single Xcode project.
- Code reuse across macOS, iOS, and iPadOS is critical. Shared domain models, repository services, view models, board UI, bead detail UI, filtering logic, and persistence should live in shared source groups and be compiled into each platform target.
- Platform-specific code should be limited to app entry points, platform affordances, window commands, menu commands, navigation presentation, and OS-specific integrations.
- iOS and iPadOS should ship from the same iOS target using adaptive SwiftUI layout and device-family support for both iPhone and iPad.
- macOS should ship as a separate target in the same Xcode project, consuming the same shared SwiftUI and domain modules.
- Use SwiftData or Core Data for local persistence.
- Use async/await for integration refresh.
- Use secure storage for tokens via Keychain.
- Support iCloud sync for board metadata if feasible after MVP validation.

## Data Model

### Board

- id
- name
- repositoryId
- columns
- savedViews
- createdAt
- updatedAt

### Column

- id
- boardId
- name
- order
- archivedAt

### Bead

- id
- boardId
- columnId
- title
- description
- order
- sourceType
- sourceId
- sourceUrl
- branchName
- issueNumber
- pullRequestNumber
- labels
- priority
- blocked
- stale
- checklistItems
- notes
- createdAt
- updatedAt
- archivedAt

### Repository

- id
- name
- localPath
- remoteUrl
- provider
- defaultBranch
- createdAt
- updatedAt

### Integration Account

- id
- provider
- accountName
- tokenReference
- scopes
- createdAt
- updatedAt

## MVP Scope

### Included

- macOS app as primary launch platform.
- Universal SwiftUI architecture prepared for iOS and iPadOS.
- Mac-hosted local HTTP server for iPhone and iPad clients.
- iPhone and iPad connection configuration for local network or Tailscale use.
- Local Git repository connection.
- Manual boards, columns, and beads.
- Kanban drag and drop.
- Bead detail inspector.
- GitHub authentication.
- Import GitHub issues and pull requests.
- Basic search and filters.
- Local persistence.
- Configurable stale indicators.

### Deferred

- Real-time collaboration.
- Production-grade pairing, authentication, and incremental conflict resolution for the Mac server.
- Jira and Linear integrations.
- GitLab integration.
- iCloud sync.
- Advanced Git operations.
- Automation rules.
- AI-generated planning suggestions.
- Multi-repo boards.
- Custom dashboard analytics.

## Success Metrics

- User can connect a repo and get a useful board in under 5 minutes.
- 80% of manually created beads are created in under 10 seconds.
- Users can identify blocked, stale, and review-needed work within 30 seconds of opening a board.
- Daily active users open the app at least once per active coding day.
- At least 50% of connected repos have recurring board edits after initial setup.

## Risks and Mitigations

### Risk: Source-of-truth confusion

Users may be unsure whether the board or GitHub owns status.

Mitigation:

- Clearly label linked source state versus board state.
- Never silently overwrite manual movement.
- Provide sync history and conflict resolution.

### Risk: Too much imported noise

Repos may generate too many beads.

Mitigation:

- Use import rules.
- Default to open PRs, assigned issues, local changes, and recent branches.
- Offer suggested beads before adding everything.

### Risk: Cross-platform complexity

macOS, iPadOS, and iOS have different interaction models.

Mitigation:

- Build shared model and sync engine first.
- Make macOS the complete power-user experience.
- Scope iPhone to review and lightweight updates.

### Risk: Git integration edge cases

Local repositories can have unusual remotes, worktrees, submodules, or detached HEAD states.

Mitigation:

- Start with read-only Git inspection.
- Surface unsupported states clearly.
- Avoid destructive Git operations in MVP.

## Open Questions

- Should "bead" be the user-facing term, or should the UI use "card" while the product keeps bead as the brand concept?
- Should the first release be macOS-only with iOS and iPadOS following, or should it ship as a universal app from the beginning?
- Should local Git inspection use command-line Git, a Swift Git library, or a hybrid approach?
- Which GitHub scopes are required for the desired MVP import and notification behavior?
- Should board metadata sync through iCloud in MVP or remain local-only?
- Should the board support one repository per board only, or allow repo groups from day one?

## Launch Criteria

- User can create a board from a local Git repo.
- User can create, edit, drag, reorder, archive, and delete beads.
- User can connect GitHub and import issues and PRs.
- User can search and filter the board.
- User can open linked repo artifacts from a bead.
- App works offline for existing boards.
- App handles sync errors without data loss.
- macOS UI is stable with hundreds of beads across multiple columns.
