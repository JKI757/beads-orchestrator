import SwiftUI

enum BeadCardDensity {
    case compact
    case regular
    case dense

    var titleFont: Font {
        switch self {
        case .compact: .headline
        case .regular: .subheadline.weight(.semibold)
        case .dense: .callout.weight(.semibold)
        }
    }

    var summaryFont: Font {
        switch self {
        case .compact: .subheadline
        case .regular: .caption
        case .dense: .caption
        }
    }

    var padding: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 10
        case .dense: 8
        }
    }

    var summaryLineLimit: Int {
        switch self {
        case .compact: 3
        case .regular: 3
        case .dense: 2
        }
    }
}

struct BeadCardView: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    var density: BeadCardDensity = .regular

    var isSelected: Bool {
        store.selectedBeadID == bead.id
    }

    var body: some View {
        Button {
            store.select(bead)
        } label: {
            BeadCardContent(bead: bead, density: density, showsSourceBadge: true)
                .padding(density.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                #else
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .contextMenu {
            if let board = store.selectedBoard {
                Menu("Move To") {
                    ForEach(board.columns) { column in
                        Button(column.name) {
                            store.moveBead(bead.id, to: column.id)
                        }
                    }
                }
            }

            Button("Archive", role: .destructive) {
                store.archiveBead(bead.id)
            }
        }
    }
}

struct BeadCardContent: View {
    let bead: Bead
    var density: BeadCardDensity = .regular
    var showsSourceBadge = true

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 6 : 8) {
            HStack(alignment: .top) {
                Text(bead.title)
                    .font(density.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(density == .compact ? 2 : 1)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if showsSourceBadge {
                    SourceBadge(sourceType: bead.sourceType)
                }
            }

            if !bead.summary.isEmpty {
                Text(bead.summary)
                    .font(density.summaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(density.summaryLineLimit)
                    .multilineTextAlignment(.leading)
            }

            if !bead.labels.isEmpty || bead.isBlocked || bead.isStale {
                FlowTags(bead: bead)
            }

            HStack {
                if let branchName = bead.branchName {
                    Label(branchName, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(bead.updatedAt, style: .relative)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SourceBadge: View {
    let sourceType: BeadSourceType

    var body: some View {
        Image(systemName: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(sourceType.displayName)
    }

    private var symbolName: String {
        switch sourceType {
        case .manual: "note.text"
        case .localGit: "point.3.connected.trianglepath.dotted"
        case .githubIssue: "smallcircle.filled.circle"
        case .githubPullRequest: "arrow.triangle.pull"
        }
    }
}

private struct FlowTags: View {
    let bead: Bead

    var body: some View {
        HStack(spacing: 5) {
            if bead.isBlocked {
                Tag(text: "Blocked", color: .red)
            }
            if bead.isStale {
                Tag(text: "Stale", color: .orange)
            }
            ForEach(bead.labels.prefix(3), id: \.self) { label in
                Tag(text: label, color: .blue)
            }
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
