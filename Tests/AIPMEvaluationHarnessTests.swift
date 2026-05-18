import XCTest

@MainActor
final class AIPMEvaluationHarnessTests: XCTestCase {
    func testProjectIntelligenceSignalsCoverBlockedStaleHierarchyAndDependencies() throws {
        let fixture = AIPMFixture.complexRiskBoard()
        let server = BeadsHTTPServer(
            llmConfiguration: LLMServerConfigurationStore(persistenceURL: temporaryFile("llm.json")),
            aiPMState: AIPMStateStore(persistenceURL: temporaryFile("pm-state.json"))
        )
        let store = BoardStore(boards: [fixture.board], persistenceURL: temporaryFile("boards.json"))
        server.configure(store: store)

        let intelligence = try withExtendedLifetime(store) {
            try server.evaluateAIPMProjectIntelligence(request: AIPMRunRequest(boardID: fixture.board.id))
        }

        XCTAssertEqual(intelligence.totalActiveBeads, 5)
        XCTAssertEqual(intelligence.blockedBeads, 1)
        XCTAssertEqual(intelligence.staleBeads, 1)
        XCTAssertEqual(intelligence.urgentBeads, 2)
        XCTAssertEqual(intelligence.orphanedChildren, 1)
        XCTAssertEqual(intelligence.dependencyIssues, 1)
        XCTAssertTrue(intelligence.signals.contains { $0.category == .blocked && $0.severity == .critical })
        XCTAssertTrue(intelligence.signals.contains { $0.category == .stale })
        XCTAssertTrue(intelligence.signals.contains { $0.category == .hierarchy })
        XCTAssertTrue(intelligence.signals.contains { $0.category == .dependency })
    }

    func testHealthyProjectIntelligenceEmitsHealthySignal() throws {
        let fixture = AIPMFixture.healthyBoard()
        let server = BeadsHTTPServer(
            llmConfiguration: LLMServerConfigurationStore(persistenceURL: temporaryFile("llm.json")),
            aiPMState: AIPMStateStore(persistenceURL: temporaryFile("pm-state.json"))
        )
        let store = BoardStore(boards: [fixture.board], persistenceURL: temporaryFile("boards.json"))
        server.configure(store: store)

        let intelligence = try withExtendedLifetime(store) {
            try server.evaluateAIPMProjectIntelligence(request: AIPMRunRequest(boardID: fixture.board.id))
        }

        XCTAssertEqual(intelligence.totalActiveBeads, 2)
        XCTAssertEqual(intelligence.blockedBeads, 0)
        XCTAssertEqual(intelligence.staleBeads, 0)
        XCTAssertEqual(intelligence.orphanedChildren, 0)
        XCTAssertEqual(intelligence.dependencyIssues, 0)
        XCTAssertEqual(intelligence.signals.map(\.category), [.health])
        XCTAssertEqual(intelligence.signals.first?.title, "No deterministic PM risks detected")
    }

    func testProposalActionApplicationCreatesMovesAndFlagsBeads() {
        let fixture = AIPMFixture.healthyBoard()
        let store = BoardStore(boards: [fixture.board], persistenceURL: temporaryFile("boards.json"))

        let createResult = store.apply(BeadPlanReviewChange(
            kind: .createBead,
            targetBeadsID: nil,
            field: nil,
            value: "Ready",
            title: "Draft release checklist",
            summary: "Prepare release handoff.",
            notes: "Confirm owner, scope, and rollout steps.",
            labels: ["release", "pm"],
            priority: .high,
            issueType: "task",
            rationale: "The release needs explicit planning."
        ))

        XCTAssertEqual(createResult.status, .applied)
        let created = store.selectedBoardBeads.first { $0.title == "Draft release checklist" }
        XCTAssertEqual(created?.status, "Ready")
        XCTAssertEqual(created?.labels, ["release", "pm"])
        XCTAssertEqual(created?.priority, .high)
        XCTAssertTrue(store.selectedBoard?.columns.first { $0.name == "Ready" }?.beads.contains { $0.id == created?.id } == true)

        let setStatusResult = store.apply(BeadPlanReviewChange(
            kind: .setStatus,
            targetBeadsID: fixture.implementation.relationshipID,
            field: nil,
            value: "Blocked",
            title: nil,
            summary: nil,
            notes: nil,
            labels: nil,
            priority: nil,
            issueType: nil,
            rationale: "The implementation is waiting on a decision."
        ))

        XCTAssertEqual(setStatusResult.status, .applied)
        let moved = store.bead(beadsID: fixture.implementation.relationshipID)
        XCTAssertEqual(moved?.status, "Blocked")
        XCTAssertTrue(store.selectedBoard?.columns.first { $0.name == "Blocked" }?.beads.contains { $0.relationshipID == fixture.implementation.relationshipID } == true)

        let blockedResult = store.apply(BeadPlanReviewChange(
            kind: .setBlocked,
            targetBeadsID: fixture.implementation.relationshipID,
            field: nil,
            value: "true",
            title: nil,
            summary: nil,
            notes: nil,
            labels: nil,
            priority: nil,
            issueType: nil,
            rationale: "Mark blocked for PM follow-up."
        ))

        XCTAssertEqual(blockedResult.status, .applied)
        XCTAssertEqual(store.bead(beadsID: fixture.implementation.relationshipID)?.isBlocked, true)
    }

    func testInvalidProposalActionsFailWithoutMutatingBoard() {
        let fixture = AIPMFixture.healthyBoard()
        let store = BoardStore(boards: [fixture.board], persistenceURL: temporaryFile("boards.json"))
        let beadCount = store.selectedBoardBeads.count

        let missingDependency = store.apply(BeadPlanReviewChange(
            kind: .addDependency,
            targetBeadsID: fixture.implementation.relationshipID,
            field: nil,
            value: "missing-id",
            title: nil,
            summary: nil,
            notes: nil,
            labels: nil,
            priority: nil,
            issueType: nil,
            rationale: "This should fail because the dependency does not exist."
        ))

        XCTAssertEqual(missingDependency.status, .failed)
        XCTAssertEqual(store.selectedBoardBeads.count, beadCount)
        XCTAssertEqual(store.bead(beadsID: fixture.implementation.relationshipID)?.dependencyBeadsIDs, [])

        let missingTarget = store.apply(BeadPlanReviewChange(
            kind: .setStatus,
            targetBeadsID: "missing-target",
            field: nil,
            value: "Done",
            title: nil,
            summary: nil,
            notes: nil,
            labels: nil,
            priority: nil,
            issueType: nil,
            rationale: "This should fail because the target does not exist."
        ))

        XCTAssertEqual(missingTarget.status, .failed)
        XCTAssertNil(store.bead(beadsID: "missing-target"))
    }

    func testPlanReviewJSONResponseDecodesExpandedActions() throws {
        let json = """
        {
          "message": "Review complete",
          "findings": [
            {
              "severity": "warning",
              "category": "sequencing",
              "title": "Blocked implementation",
              "detail": "The implementation should be marked blocked until scope is decided."
            }
          ],
          "changes": [
            {
              "kind": "createBead",
              "targetBeadsID": null,
              "field": null,
              "value": "Ready",
              "title": "Clarify launch scope",
              "summary": "Decide what ships in the launch.",
              "notes": "Acceptance: scope is explicit and reviewed.",
              "labels": ["planning", "launch"],
              "priority": "high",
              "issueType": "task",
              "rationale": "The team needs a planning bead before implementation continues."
            },
            {
              "kind": "setBlocked",
              "targetBeadsID": "task-1",
              "field": null,
              "value": "true",
              "title": null,
              "summary": null,
              "notes": null,
              "labels": null,
              "priority": null,
              "issueType": null,
              "rationale": "Implementation is blocked on launch scope."
            }
          ],
          "generatedAt": "2026-05-17T12:00:00Z"
        }
        """

        let response = try BeadsJSON.decoder.decode(BeadPlanReviewResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.message, "Review complete")
        XCTAssertEqual(response.findings.first?.category, .sequencing)
        XCTAssertEqual(response.changes.map(\.kind), [.createBead, .setBlocked])
        XCTAssertEqual(response.changes.first?.labels, ["planning", "launch"])
        XCTAssertEqual(response.changes.first?.priority, .high)
    }

    func testLLMSettingsAllowUnauthenticatedEndpointAndDecodeModels() throws {
        let modelsJSON = """
        {
          "object": "list",
          "data": [
            { "id": "qwen2.5-coder:7b", "object": "model" },
            { "id": "llama3.2:latest", "object": "model" }
          ]
        }
        """
        let models = try BeadsJSON.decoder.decode(OpenAIModelsResponse.self, from: Data(modelsJSON.utf8))
        let configuration = LLMServerConfiguration(
            provider: .remoteOpenAICompatible,
            endpointURLString: " http://127.0.0.1:11434/v1 ",
            modelName: " llama3.2:latest ",
            apiKey: " ",
            timeoutSeconds: 1,
            maximumResponseBytes: 10,
            retryLimit: 99
        )
        let store = LLMServerConfigurationStore(persistenceURL: temporaryFile("llm.json"))

        store.save(configuration)

        XCTAssertEqual(models.data.map(\.id), ["qwen2.5-coder:7b", "llama3.2:latest"])
        XCTAssertTrue(store.status.isAvailable)
        XCTAssertEqual(store.status.model, "llama3.2:latest")
        XCTAssertEqual(store.configuration.trimmedAPIKey, "")
        XCTAssertEqual(store.configuration.timeoutSeconds, 5)
        XCTAssertEqual(store.configuration.maximumResponseBytes, 65_536)
        XCTAssertEqual(store.configuration.retryLimit, 5)
    }

    func testLLMConfigurationDecodesLegacySettingsWithSafeguardDefaults() throws {
        let json = """
        {
          "provider": "localOpenAICompatible",
          "endpointURLString": "http://127.0.0.1:11434/v1",
          "modelName": "qwen2.5-coder:7b",
          "apiKey": ""
        }
        """

        let configuration = try BeadsJSON.decoder.decode(LLMServerConfiguration.self, from: Data(json.utf8))

        XCTAssertEqual(configuration.timeoutSeconds, 60)
        XCTAssertEqual(configuration.maximumResponseBytes, 1_000_000)
        XCTAssertEqual(configuration.retryLimit, 1)
    }

    func testAIPMStatePersistenceRecordsRunsFailuresAndAuditEvents() {
        let stateURL = temporaryFile("pm-state.json")
        let store = AIPMStateStore(persistenceURL: stateURL)
        let proposal = AIPMDecisionProposal(
            title: "Clarify release scope",
            summary: "Decide what ships.",
            category: .planning,
            risk: .medium,
            rationale: "Scope is unclear.",
            changes: []
        )

        store.saveSettings(AIPMAutomationSettings(isEnabled: true, cadence: .daily))
        store.recordRun(
            summary: "Found one planning decision.",
            proposals: [proposal],
            report: AIPMReportSnapshot(title: "Daily PM Report", summary: "One decision pending.", sections: []),
            intelligence: AIPMProjectIntelligenceSummary(
                boardID: UUID(),
                boardName: "Harness",
                totalActiveBeads: 1,
                blockedBeads: 0,
                staleBeads: 0,
                urgentBeads: 0,
                orphanedChildren: 0,
                dependencyIssues: 0,
                signals: [],
                generatedAt: Date()
            )
        )
        store.updateProposal(proposal.id, status: .accepted)
        store.recordRunFailure("Provider unavailable")

        let reloaded = AIPMStateStore(persistenceURL: stateURL)

        XCTAssertEqual(reloaded.state.proposals.count, 1)
        XCTAssertEqual(reloaded.state.reports.count, 1)
        XCTAssertEqual(reloaded.state.lastRunError, "Provider unavailable")
        XCTAssertTrue(reloaded.state.settings.isEnabled)
        XCTAssertTrue(reloaded.state.auditEvents.contains { $0.kind == .runCompleted })
        XCTAssertTrue(reloaded.state.auditEvents.contains { $0.kind == .proposalStatusChanged && $0.resultStatus == "accepted" })
        XCTAssertEqual(reloaded.state.auditEvents.first?.kind, .runFailed)
    }

    func testAIPMSettingsDecodeLegacyNotificationDefaultsAndAttentionState() throws {
        let json = """
        {
          "isEnabled": true,
          "cadence": "daily",
          "autonomyLevel": "surfaceDecisions",
          "reviewsBacklog": true,
          "generatesReports": true,
          "maximumProposals": 8
        }
        """

        let settings = try BeadsJSON.decoder.decode(AIPMAutomationSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.sendsNotifications)
        XCTAssertTrue(settings.notifiesHighRiskProposals)
        XCTAssertTrue(settings.notifiesRunFailures)
        XCTAssertEqual(settings.maximumActionsPerProposal, 5)
        XCTAssertEqual(settings.maximumConsecutiveFailures, 3)
        XCTAssertTrue(settings.requiresHighRiskApproval)

        let state = AIPMState(proposals: [
            AIPMDecisionProposal(
                title: "Resolve launch risk",
                summary: "Needs a decision.",
                category: .decision,
                risk: .high,
                rationale: "The next milestone is blocked."
            )
        ])
        XCTAssertEqual(state.unreadDecisionCount, 1)
        XCTAssertEqual(state.highRiskPendingProposals.count, 1)
        XCTAssertTrue(state.needsAttention)
    }

    func testAIPMSafetyPolicyRejectsUnsafeAutonomousApplication() {
        let server = BeadsHTTPServer(
            llmConfiguration: LLMServerConfigurationStore(persistenceURL: temporaryFile("llm.json")),
            aiPMState: AIPMStateStore(persistenceURL: temporaryFile("pm-state.json"))
        )
        let proposal = AIPMDecisionProposal(
            title: "Resolve launch risk",
            summary: "Move risky work forward.",
            category: .risk,
            risk: .high,
            rationale: "Launch scope is blocked.",
            changes: [
                BeadPlanReviewChange(kind: .setBlocked, targetBeadsID: "task-1", field: nil, value: "true", title: nil, summary: nil, notes: nil, labels: nil, priority: nil, issueType: nil, rationale: "Mark blocked."),
                BeadPlanReviewChange(kind: .setStatus, targetBeadsID: "task-1", field: nil, value: "Blocked", title: nil, summary: nil, notes: nil, labels: nil, priority: nil, issueType: nil, rationale: "Move to blocked.")
            ]
        )

        server.saveAIPMSettings(AIPMAutomationSettings(
            autonomyLevel: .surfaceDecisions,
            maximumActionsPerProposal: 1,
            requiresHighRiskApproval: true
        ))
        XCTAssertNotNil(server.aipmSafetyRejection(
            proposal: proposal,
            selectedChangeCount: 1,
            hasExplicitApproval: true
        ))

        server.saveAIPMSettings(AIPMAutomationSettings(
            autonomyLevel: .autonomousProposals,
            maximumActionsPerProposal: 1,
            requiresHighRiskApproval: true
        ))
        XCTAssertNotNil(server.aipmSafetyRejection(
            proposal: proposal,
            selectedChangeCount: 2,
            hasExplicitApproval: true
        ))
        XCTAssertNotNil(server.aipmSafetyRejection(
            proposal: proposal,
            selectedChangeCount: 1,
            hasExplicitApproval: false
        ))
        XCTAssertNil(server.aipmSafetyRejection(
            proposal: proposal,
            selectedChangeCount: 1,
            hasExplicitApproval: true
        ))
    }

    func testAIPMSchedulerPausesAfterBoundedFailuresAndResumesAfterSuccess() {
        let stateURL = temporaryFile("pm-state.json")
        let store = AIPMStateStore(persistenceURL: stateURL)
        store.saveSettings(AIPMAutomationSettings(
            isEnabled: true,
            cadence: .hourly,
            maximumConsecutiveFailures: 2
        ))

        XCTAssertNotNil(store.state.nextRunAt)

        store.recordRunFailure("Provider offline")
        XCTAssertEqual(store.state.consecutiveRunFailures, 1)
        XCTAssertNotNil(store.state.nextRunAt)

        store.recordRunFailure("Provider still offline")
        XCTAssertEqual(store.state.consecutiveRunFailures, 2)
        XCTAssertNil(store.state.nextRunAt)

        store.recordRun(
            summary: "Recovered.",
            proposals: [],
            report: nil,
            intelligence: nil
        )

        XCTAssertEqual(store.state.consecutiveRunFailures, 0)
        XCTAssertNotNil(store.state.nextRunAt)
    }

    func testAIPMReportSnapshotDecodesLegacyReportAndPersistsDeltas() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Daily PM Report",
          "summary": "One decision pending.",
          "sections": [
            { "title": "Decisions", "items": ["Pick launch scope"] }
          ],
          "generatedAt": "2026-05-17T16:00:00Z"
        }
        """

        let legacyReport = try BeadsJSON.decoder.decode(AIPMReportSnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(legacyReport.deltas.isEmpty)
        XCTAssertNil(legacyReport.boardSnapshot)

        let report = AIPMReportSnapshot(
            title: "Recurring PM Report",
            summary: "Progress and risks changed since the last run.",
            deltas: AIPMReportDeltas(
                progress: ["BO-1 moved from Backlog to In Progress"],
                risks: ["BO-2 became stale"],
                blockers: ["BO-3 is newly blocked"],
                decisions: ["High: Pick release scope"]
            ),
            sections: [
                BeadStatusReportSection(title: "Progress", items: ["BO-1 moved from Backlog to In Progress"])
            ],
            boardSnapshot: AIPMBoardSnapshot(
                boardID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                boardName: "Harness",
                beads: [
                    AIPMBoardSnapshotBead(
                        relationshipID: "BO-1",
                        title: "Build feature",
                        status: "In Progress",
                        priority: .normal,
                        isBlocked: false,
                        isStale: false
                    )
                ]
            )
        )

        let data = try BeadsJSON.encoder.encode(report)
        let decoded = try BeadsJSON.decoder.decode(AIPMReportSnapshot.self, from: data)
        XCTAssertEqual(decoded.deltas.progress, ["BO-1 moved from Backlog to In Progress"])
        XCTAssertEqual(decoded.deltas.risks, ["BO-2 became stale"])
        XCTAssertEqual(decoded.deltas.blockers, ["BO-3 is newly blocked"])
        XCTAssertEqual(decoded.deltas.decisions, ["High: Pick release scope"])
        XCTAssertEqual(decoded.boardSnapshot?.beads.first?.relationshipID, "BO-1")
    }

    private func temporaryFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BeadsOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}

private enum AIPMFixture {
    struct Fixture {
        var board: Board
        var epic: Bead
        var implementation: Bead
    }

    static func healthyBoard() -> Fixture {
        let epic = Bead(
            beadsID: "epic-1",
            issueType: "epic",
            status: "Ready",
            childBeadsIDs: ["task-1"],
            title: "Ship AI PM foundation",
            summary: "Build a useful AI PM foundation."
        )
        let implementation = Bead(
            beadsID: "task-1",
            issueType: "task",
            status: "In Progress",
            parentBeadsID: "epic-1",
            title: "Implement proposal workflow",
            summary: "Create and apply PM proposals."
        )
        return Fixture(board: board(named: "Healthy", beads: [epic, implementation]), epic: epic, implementation: implementation)
    }

    static func complexRiskBoard() -> Fixture {
        let epic = Bead(
            beadsID: "epic-1",
            issueType: "epic",
            status: "Ready",
            childBeadsIDs: ["task-1"],
            title: "Ship AI PM foundation",
            summary: "Build a useful AI PM foundation."
        )
        let implementation = Bead(
            beadsID: "task-1",
            issueType: "task",
            status: "In Progress",
            parentBeadsID: "epic-1",
            title: "Implement proposal workflow",
            summary: "Create and apply PM proposals.",
            priority: .urgent,
            isBlocked: true
        )
        let stale = Bead(
            beadsID: "task-2",
            issueType: "task",
            status: "Review",
            title: "Review reporting",
            summary: "Check PM report quality.",
            isStale: true
        )
        let orphaned = Bead(
            beadsID: "task-3",
            issueType: "task",
            status: "Ready",
            parentBeadsID: "missing-epic",
            title: "Orphaned child",
            summary: "This should flag missing hierarchy."
        )
        let dependencyIssue = Bead(
            beadsID: "task-4",
            issueType: "task",
            status: "Ready",
            dependencyBeadsIDs: ["missing-dependency", "task-4"],
            title: "Invalid dependency",
            summary: "This should flag dependency issues.",
            priority: .urgent
        )
        return Fixture(
            board: board(named: "Complex Risks", beads: [epic, implementation, stale, orphaned, dependencyIssue]),
            epic: epic,
            implementation: implementation
        )
    }

    private static func board(named name: String, beads: [Bead]) -> Board {
        Board(
            name: name,
            repositoryName: "Harness",
            columns: [
                BoardColumn(name: "Backlog"),
                BoardColumn(name: "Ready", beads: beads.filter { $0.status == "Ready" }),
                BoardColumn(name: "In Progress", beads: beads.filter { $0.status == "In Progress" }),
                BoardColumn(name: "Blocked", beads: beads.filter { $0.status == "Blocked" }),
                BoardColumn(name: "Review", beads: beads.filter { $0.status == "Review" }),
                BoardColumn(name: "Done", beads: beads.filter { $0.status == "Done" })
            ]
        )
    }
}
