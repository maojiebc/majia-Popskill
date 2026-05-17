import SwiftUI

/// 5-step onboarding wizard presented as a sheet over `RootView`. Triggered
/// on first launch (no skills + no prior onboardScan) and re-runnable from
/// Settings → Re-run onboarding.
///
/// Steps:
///   0. Welcome — value prop + Start.
///   1. Detect tools — show Claude / Codex / brew CLIs / npm globals.
///   2. Scan capabilities — show ~/.agents/skills + per-app skill dirs.
///   3. Storage + sync — confirm SSOT + pick provider (iCloud recommended on
///      Mac with iCloud Drive available, Git otherwise).
///   4. Done — open matrix.
struct OnboardingWizardView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var step: Int = 0
    @State private var scanInFlight: Bool = false
    @State private var scanError: String?
    @State private var pickedProvider: SyncProvider = .git

    private static let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                content
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 640, height: 540)
        .background(Color.popMainBackground)
        .onAppear {
            // If we already have a scan from settings/last-time, default to
            // the recommended provider; otherwise the picker shows .git.
            if let report = store.onboardScan,
               let provider = SyncProvider(rawValue: report.recommendedSyncProvider) {
                pickedProvider = provider
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(localization.string("onboarding.title"))
                .font(.headline)
                .foregroundStyle(Color.popLabel)
            Spacer()
            stepIndicator
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.stepCount, id: \.self) { idx in
                Circle()
                    .fill(idx <= step ? Color.accentColor : Color.popTertiaryLabel.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if step > 0 {
                Button(localization.string("onboarding.back")) {
                    step = max(0, step - 1)
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            if step < Self.stepCount - 1 {
                Button(localization.string("onboarding.skip")) {
                    close()
                }
                .controlSize(.regular)
                Button {
                    Task { await advance() }
                } label: {
                    HStack(spacing: 4) {
                        Text(localization.string("onboarding.next"))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(scanInFlight)
            } else {
                Button {
                    finish()
                } label: {
                    Text(localization.string("onboarding.finish"))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: detectStep
        case 2: scanStep
        case 3: storageStep
        default: doneStep
        }
    }

    // MARK: Step 0 — Welcome

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(14)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            LocalizedText("onboarding.welcome.title")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            LocalizedText("onboarding.welcome.body")
                .font(.callout)
                .foregroundStyle(Color.popSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack(alignment: .leading, spacing: 6) {
                bullet(symbol: "square.grid.3x3", key: "onboarding.welcome.bullet1")
                bullet(symbol: "stethoscope", key: "onboarding.welcome.bullet2")
                bullet(symbol: "icloud.and.arrow.down", key: "onboarding.welcome.bullet3")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func bullet(symbol: String, key: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            LocalizedText(key)
                .font(.callout)
                .foregroundStyle(Color.popLabel)
        }
    }

    // MARK: Step 1 — Detect tools

    private var detectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("onboarding.detect.title", subtitle: "onboarding.detect.subtitle")

            if let report = store.onboardScan {
                detectCard(
                    title: "Claude Code",
                    symbol: "sparkles",
                    paths: [report.claudeSkillsDir, report.claudeAgentsDir],
                    keyEmpty: "onboarding.detect.empty"
                )
                detectCard(
                    title: "Codex",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    paths: [report.codexSkillsDir],
                    keyEmpty: "onboarding.detect.empty"
                )
                cliCard(report)
                npmCard(report)
            } else {
                placeholderScan(
                    titleKey: "onboarding.detect.placeholderTitle",
                    bodyKey: "onboarding.detect.placeholderBody"
                )
            }
        }
    }

    private func detectCard(title: String, symbol: String, paths: [OnboardScanDir], keyEmpty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                statusBadge(found: paths.contains(where: { $0.exists }))
            }
            ForEach(paths.indices, id: \.self) { idx in
                let dir = paths[idx]
                HStack(spacing: 8) {
                    Image(systemName: dir.exists ? "checkmark.circle" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(dir.exists ? Color.popStatusOK : Color.popTertiaryLabel)
                    Text(dir.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.popSecondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if dir.exists {
                        Text("\(dir.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.popLabel)
                    }
                }
            }
        }
        .padding(12)
        .popCard(cornerRadius: PopskillRadius.smallCard)
    }

    private func cliCard(_ report: OnboardScanReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "terminal").font(.system(size: 13, weight: .semibold))
                Text("brew CLI")
                    .font(.callout.weight(.semibold))
                Spacer()
                statusBadge(found: !report.brewCli.isEmpty)
            }
            if report.brewCli.isEmpty {
                Text(localization.string("onboarding.detect.cliEmpty"))
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            } else {
                Text(report.brewCli.joined(separator: ", "))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .popCard(cornerRadius: PopskillRadius.smallCard)
    }

    private func npmCard(_ report: OnboardScanReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox").font(.system(size: 13, weight: .semibold))
                Text("npm globals")
                    .font(.callout.weight(.semibold))
                Spacer()
                statusBadge(found: !report.npmGlobalMcp.isEmpty)
            }
            if report.npmGlobalMcp.isEmpty {
                Text(localization.string("onboarding.detect.npmEmpty"))
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            } else {
                Text(report.npmGlobalMcp.joined(separator: ", "))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .popCard(cornerRadius: PopskillRadius.smallCard)
    }

    // MARK: Step 2 — Scan capabilities

    private var scanStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("onboarding.scan.title", subtitle: "onboarding.scan.subtitle")

            if let report = store.onboardScan {
                detectCard(
                    title: localization.string("onboarding.scan.agentsRoot"),
                    symbol: "folder",
                    paths: [report.agentsDir],
                    keyEmpty: "onboarding.scan.empty"
                )

                HStack(spacing: 12) {
                    metric(
                        label: localization.string("onboarding.scan.installed"),
                        value: report.popskillInstalledCount,
                        symbol: "square.grid.3x3.fill",
                        tint: .accentColor
                    )
                    metric(
                        label: localization.string("onboarding.scan.totalAgents"),
                        value: report.agentsDir.count,
                        symbol: "folder.fill",
                        tint: .orange
                    )
                }

                if let ssot = report.popskillSsot, !ssot.isEmpty {
                    Text(localization.string("onboarding.scan.ssotLabel"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.popSecondaryLabel)
                    Text(ssot)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.popLabel)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            } else {
                placeholderScan(
                    titleKey: "onboarding.scan.placeholderTitle",
                    bodyKey: "onboarding.scan.placeholderBody"
                )
            }
        }
    }

    // MARK: Step 3 — Storage + sync

    private var storageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("onboarding.storage.title", subtitle: "onboarding.storage.subtitle")

            ssotInfoCard

            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("onboarding.storage.providerLabel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
                ForEach(SyncProvider.allCases) { provider in
                    providerOption(provider)
                }
            }
        }
    }

    private var ssotInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                LocalizedText("onboarding.storage.ssotLabel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Text((NSHomeDirectory() as NSString).appendingPathComponent(".cc-switch/skills"))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.popLabel)
                .textSelection(.enabled)
            LocalizedText("onboarding.storage.ssotHint")
                .font(.caption2)
                .foregroundStyle(Color.popTertiaryLabel)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.smallCard)
    }

    private func providerOption(_ provider: SyncProvider) -> some View {
        let isRecommended = provider.rawValue == (store.onboardScan?.recommendedSyncProvider ?? "git")
        return Button {
            pickedProvider = provider
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pickedProvider == provider ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(pickedProvider == provider ? Color.accentColor : Color.popTertiaryLabel)
                Image(systemName: provider.symbol).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(localization.string(provider.titleKey))
                            .font(.callout.weight(.medium))
                        if isRecommended {
                            Text(localization.string("onboarding.storage.recommended"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(localization.string(provider.subtitleKey))
                        .font(.caption)
                        .foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer()
                if !provider.implemented {
                    Text(localization.string("settings.sync.soon"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.popStatusWarning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            pickedProvider == provider ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: Step 4 — Done

    private var doneStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Color.popStatusOK)
                .padding(14)
                .background(Color.popStatusOK.opacity(0.12), in: Circle())
            LocalizedText("onboarding.done.title")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            LocalizedText("onboarding.done.body")
                .font(.callout)
                .foregroundStyle(Color.popSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack(alignment: .leading, spacing: 6) {
                bullet(symbol: "command", key: "onboarding.done.tip1")
                bullet(symbol: "stethoscope", key: "onboarding.done.tip2")
                bullet(symbol: "arrow.down.circle", key: "onboarding.done.tip3")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private func sectionTitle(_ titleKey: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText(titleKey)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.popLabel)
            LocalizedText(subtitle)
                .font(.callout)
                .foregroundStyle(Color.popSecondaryLabel)
        }
    }

    private func placeholderScan(titleKey: String, bodyKey: String) -> some View {
        VStack(spacing: 10) {
            if scanInFlight {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.popTertiaryLabel)
            }
            LocalizedText(titleKey)
                .font(.callout.weight(.semibold))
            LocalizedText(bodyKey)
                .font(.caption)
                .foregroundStyle(Color.popSecondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let scanError {
                Text(scanError)
                    .font(.caption)
                    .foregroundStyle(Color.popStatusError)
            }
            Button {
                Task { await runScan() }
            } label: {
                Label(localization.string("onboarding.scan.now"), systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(scanInFlight)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func metric(label: String, value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popCard(cornerRadius: PopskillRadius.smallCard)
    }

    private func statusBadge(found: Bool) -> some View {
        Text(found ? localization.string("onboarding.detect.found") : localization.string("onboarding.detect.missing"))
            .font(.caption2.weight(.bold))
            .foregroundStyle(found ? Color.popStatusOK : Color.popStatusWarning)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                (found ? Color.popStatusOK : Color.popStatusWarning).opacity(0.14),
                in: Capsule()
            )
    }

    // MARK: Actions

    @MainActor
    private func advance() async {
        // Step 1 → 2 triggers the actual scan (kept eager so the user sees
        // something to confirm before committing to step 2). If the scan
        // failed in step 1, step 2 will offer a retry.
        if step == 0 && store.onboardScan == nil {
            await runScan()
        }
        step = min(Self.stepCount - 1, step + 1)
    }

    @MainActor
    private func runScan() async {
        guard !scanInFlight else { return }
        scanInFlight = true
        scanError = nil
        defer { scanInFlight = false }

        do {
            let report = try await store.client.onboardScan()
            store.onboardScan = report
            if let provider = SyncProvider(rawValue: report.recommendedSyncProvider) {
                pickedProvider = provider
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func finish() {
        store.lastSyncProvider = pickedProvider.rawValue
        OnboardingState.markFinished()
        close()
        // Drop the user on the matrix so the first thing they see is the row
        // grid they just configured.
        store.currentSelection = .matrix
        Task { await store.bootstrap() }
    }

    private func close() {
        store.onboardingOpen = false
        step = 0
    }
}

/// Tiny UserDefaults wrapper so the first-launch hook in `RootView` can tell
/// "fresh install" apart from "user manually re-opened onboarding".
enum OnboardingState {
    private static let key = "popskill.onboarding.finishedAtV03"

    static func hasFinished() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markFinished() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
