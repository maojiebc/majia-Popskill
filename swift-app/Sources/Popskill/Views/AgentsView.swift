import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AgentsViewModel {
    var agents: [LocalAgent] = []
    var searchText = ""
    var selectedCategory = "All"
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()

    var filteredAgents: [LocalAgent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return agents.filter { agent in
            selectedCategory == "All" || agent.categoryLabel == selectedCategory
        }.filter { agent in
            query.isEmpty
                || agent.name.lowercased().contains(query)
                || agent.description.lowercased().contains(query)
                || agent.categoryLabel.lowercased().contains(query)
                || agent.fileName.lowercased().contains(query)
                || agent.tools.contains { $0.lowercased().contains(query) }
        }
    }

    var categories: [String] {
        ["All"] + Array(Set(agents.map(\.categoryLabel))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var categoryCount: Int {
        Set(agents.map(\.categoryLabel)).count
    }

    var toolCount: Int {
        Set(agents.flatMap(\.tools)).count
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            agents = try await client.listAgents()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !categories.contains(selectedCategory) {
                selectedCategory = "All"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AgentsView: View {
    @Bindable var viewModel: AgentsViewModel
    @State private var selectedAgentID: LocalAgent.ID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await viewModel.load() }
                }
                Divider()
            }

            HStack(spacing: 0) {
                agentList

                Divider()

                AgentDetailPane(agent: selectedAgent)
                    .frame(width: 320)
            }
            .onChange(of: viewModel.agents) { _, agents in
                if selectedAgentID == nil {
                    selectedAgentID = agents.first?.id
                }
            }
            .onChange(of: viewModel.filteredAgents) { _, agents in
                if let selectedAgentID, agents.contains(where: { $0.id == selectedAgentID }) {
                    return
                }
                selectedAgentID = agents.first?.id
            }
        }
        .popPageBackground()
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search Agents")
        .task {
            if !viewModel.hasLoadedOnce {
                await viewModel.load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("\(viewModel.agents.count) Claude Code agents · \(viewModel.categoryCount) categories")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 14) {
                    SummaryMetric(title: "Installed", value: viewModel.agents.count)
                    SummaryMetric(title: "Categories", value: viewModel.categoryCount)
                    SummaryMetric(title: "Tools", value: viewModel.toolCount)
                }

                Button {
                    Task { await viewModel.load() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }

            Picker("Category", selection: $viewModel.selectedCategory) {
                ForEach(viewModel.categories, id: \.self) { category in
                    Text(category == "All" ? "All Categories" : category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .popPageBackground()
    }

    private var agentList: some View {
        List(viewModel.filteredAgents, selection: $selectedAgentID) { agent in
            AgentRow(agent: agent)
                .tag(agent.id)
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading && viewModel.agents.isEmpty {
                ProgressView()
                    .controlSize(.large)
            } else if viewModel.filteredAgents.isEmpty {
                ContentUnavailableView(emptyStateTitle, systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    private var selectedAgent: LocalAgent? {
        guard let selectedAgentID else {
            return viewModel.filteredAgents.first
        }
        return viewModel.filteredAgents.first { $0.id == selectedAgentID } ?? viewModel.filteredAgents.first
    }

    private var emptyStateTitle: String {
        if viewModel.agents.isEmpty {
            return "No Agents"
        }
        return "No Matching Agents"
    }
}

struct AgentRow: View {
    let agent: LocalAgent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            InitialAvatarView(name: agent.name, identifier: agent.id)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(agent.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    StatusPill(title: agent.categoryLabel, color: .popSectionGreen)
                }

                Text(agent.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(agent.toolSummary)
                    .font(.caption)
                    .foregroundStyle(Color.popTertiaryLabel)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 78)
    }
}

struct AgentDetailPane: View {
    let agent: LocalAgent?

    var body: some View {
        Group {
            if let agent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            InitialAvatarView(name: agent.name, identifier: agent.id)
                                .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                Text(agent.categoryLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Text(agent.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        DetailSection(title: "Agent", accent: PopskillSectionAccent.color(for: 0)) {
                            DetailField(title: "Identifier", value: agent.id)
                            DetailField(title: "File", value: agent.fileName)
                            DetailField(title: "Modified", value: timestampText(agent.lastModifiedAt))
                        }

                        DetailSection(title: "Runtime", accent: PopskillSectionAccent.color(for: 1)) {
                            DetailField(title: "Model", value: agent.model ?? "Default")
                            DetailField(title: "Tools", value: agent.toolSummary)
                            DetailField(title: "Size", value: byteCountText(agent.sizeBytes))
                        }

                        Link(destination: agent.fileURL) {
                            Label("Open Agent File", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(22)
                }
            } else {
                ContentUnavailableView("No Agent Selected", systemImage: "person.crop.circle")
            }
        }
        .background(Color.popHeaderBackground.opacity(0.45))
    }

    private func timestampText(_ value: Int?) -> String {
        guard let value else {
            return "Unknown"
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func byteCountText(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
