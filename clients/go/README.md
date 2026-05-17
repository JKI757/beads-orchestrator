# Beads-Orchestrator Go Clients

This subtree contains cross-platform Go clients for the Beads-Orchestrator Mac server. It is intentionally outside the Xcode project, so Xcode ignores it unless it is manually added later.

## Clients

- `beads-ui`: Fyne desktop UI for macOS, Windows, and Linux.
- `beadsctl`: CLI for scripting, inspection, and simple mutations.

Both clients talk to the existing Mac server API:

- `GET /health`
- `GET /auth/verify`
- `GET /boards`
- `PUT /boards`

## Build

```sh
make all
```

Outputs:

```text
bin/beads-ui
bin/beadsctl
```

Useful targets:

```sh
make cli
make ui
make test
make fmt
make tidy
make cross
make clean
```

`make cross` currently cross-compiles the CLI. Fyne UI distribution usually needs platform-specific packaging and native graphics dependencies, so build the UI on each target platform when preparing release artifacts.

## Configuration

Both clients accept the same server settings:

```sh
export BEADS_SERVER_URL=http://beads-mac.local:8787
export BEADS_TOKEN=your-pairing-token
```

The CLI also accepts explicit flags:

```sh
bin/beadsctl --server http://beads-mac.local:8787 --token "$BEADS_TOKEN" boards
```

## CLI Examples

```sh
bin/beadsctl health
bin/beadsctl verify
bin/beadsctl boards
bin/beadsctl beads --board "Beads-Orchestrator"
bin/beadsctl create-bead --board "Beads-Orchestrator" --column Backlog --title "Wire Go client packaging"
bin/beadsctl move-bead --board "Beads-Orchestrator" --bead "Wire Go client packaging" --column Ready
bin/beadsctl archive-bead --board "Beads-Orchestrator" --bead "Wire Go client packaging"
bin/beadsctl pull --out boards.json
bin/beadsctl push --in boards.json
```

## UI Workflow

1. Start the macOS Beads-Orchestrator app and server.
2. Copy the server URL and pairing token from the Mac app.
3. Run `bin/beads-ui`.
4. Enter the URL and token.
5. Connect, refresh boards, create beads, move beads, or archive beads.

## Notes

The Mac app remains canonical. The Go clients read the full board snapshot, apply local mutations in memory, and write the full snapshot back with `PUT /boards`, matching the current mobile-client sync model.
