# macOS AI PM Current-State Audit

Date: 2026-05-17

## Summary

The macOS AI PM is partially implemented. It has a first-class workspace entry, server-canonical state, LLM-backed runs, deterministic project intelligence, proposal application, reports, notifications, and audit history. It is not finished as a product surface because the workflow is still split across duplicated views, proposal review is shallow, safety/autonomy rules are mostly prompt-level, scheduler behavior is minimal, rollback is audit-only, report history is basic, and screenshot/HIG validation is still missing.

## Complete Enough For Now

- AI PM appears as a workspace mode beside Board and Hierarchy.
- The macOS workspace shows metrics, run status, automation controls, pending decisions, project intelligence, recent reports, and audit history.
- Manual AI PM runs call the Mac server and persist state in `AIPMStateStore`.
- LLM configuration includes provider, model, endpoint discovery/test, timeout, response-size, retry, latency, and failure status.
- Project intelligence is deterministic and available before LLM output.
- Reports persist with timestamps, board snapshots, and since-last-run deltas.
- Proposal actions can create/update/link/move supported bead fields through `BoardStore.apply`.
- Audit events are recorded for runs, failures, proposal status changes, and individual action applications.
- Mac local notifications can fire for high-risk proposals and run failures when enabled.
- Offline XCTest coverage exists for project intelligence, proposal decoding/application, invalid actions, state persistence, LLM config defaults, and report snapshot compatibility.

## Partial Or Risky

- The AI PM workspace and the older AI PM sheet duplicate substantial UI and logic inside `RootView.swift`.
- The proposal review surface is modal, narrow, and action-list oriented; it does not provide strong before/after comparisons or a persistent detail pane.
- Applying proposal changes records action metadata but does not capture full rollback state.
- The scheduler loop sleeps and runs, but has weak pause/resume visibility, weak retry semantics, and no dedicated scheduler tests.
- Safety is mostly expressed in prompt text and basic proposal limits; the server does not yet enforce risk thresholds, mutation budgets, or broad-change approval gates.
- Notification copy points to the dashboard conceptually, but notification response routing back to the workspace is not implemented.
- Provider health appears in text only; the workspace does not yet present model, latency, limits, and last failure as first-class diagnostics.
- Empty states are generic. First-run/provider-missing/board-missing/no-report/no-proposal states need guided actions.
- Report history is a compact disclosure list, not a real reporting history/detail experience.
- There is no visual screenshot QA pass for the macOS AI PM workspace at multiple window sizes.
- Documentation does not yet describe the macOS AI PM workflow, autonomy model, or known limitations.

## Missing Product Work Mapped To Beads

- `Beads-Orchestrator-12p.3` Refactor AI PM workspace into dedicated components.
- `Beads-Orchestrator-12p.4` Complete macOS AI PM overview workspace.
- `Beads-Orchestrator-12p.10` Add AI PM safety and autonomy controls.
- `Beads-Orchestrator-12p.1` Build AI PM proposal review workflow.
- `Beads-Orchestrator-12p.8` Add rollback for applied AI PM changes.
- `Beads-Orchestrator-12p.5` Harden AI PM autonomous scheduler.
- `Beads-Orchestrator-12p.6` Improve AI PM report history and exports.
- `Beads-Orchestrator-12p.7` Add AI PM notification routing to workspace.
- `Beads-Orchestrator-12p.12` Improve AI PM LLM/provider observability.
- `Beads-Orchestrator-12p.9` Add macOS AI PM empty and onboarding states.
- `Beads-Orchestrator-12p.13` Add AI PM workspace regression tests.
- `Beads-Orchestrator-12p.11` Verify macOS AI PM UX with screenshots.
- `Beads-Orchestrator-12p.14` Document macOS AI PM workflow.

## Recommended Execution Order

1. Refactor the AI PM UI into dedicated components so follow-on work is not trapped in `RootView.swift`.
2. Finish the overview workspace and empty/provider states as the main user surface.
3. Add safety/autonomy enforcement before deepening proposal application.
4. Improve proposal review, then add rollback on top of richer action metadata.
5. Harden scheduler behavior and observability.
6. Improve report history/export and notification routing.
7. Add regression coverage, screenshot QA, and documentation.

## Done Line For The Epic

The macOS AI PM should be considered complete only when routine PM work can happen from the AI PM workspace without opening hidden modal tools: users can configure the provider, understand server health, run or schedule AI PM work, review and safely apply proposals, undo supported mutations, read report history, see actionable notifications, and verify behavior through tests and screenshots.
