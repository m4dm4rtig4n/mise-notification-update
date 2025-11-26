import SwiftUI
import AppKit

// MARK: - Model

enum PackageSource: String {
    case mise = "mise"
    case brew = "brew"

    var icon: String {
        switch self {
        case .mise: return "🔧"
        case .brew: return "🍺"
        }
    }
}

struct PackageUpdate: Identifiable {
    let id = UUID()
    let name: String
    let currentVersion: String
    let newVersion: String
    let source: PackageSource
}

enum AppState {
    case loading
    case updates([PackageUpdate])
    case installing(progress: Double, log: [String])
    case done(log: [String])
    case upToDate
}

// MARK: - Update Checker

class UpdateChecker {
    static let shared = UpdateChecker()

    let miseBin: String
    let brewBin: String

    init() {
        self.miseBin = ProcessInfo.processInfo.environment["MISE_BIN"]
            ?? "\(NSHomeDirectory())/.local/bin/mise"
        self.brewBin = ProcessInfo.processInfo.environment["BREW_BIN"]
            ?? "/opt/homebrew/bin/brew"
    }

    func checkForUpdates() async -> [PackageUpdate] {
        var packages: [PackageUpdate] = []

        let miseOutdated = await runCommand("\(miseBin) outdated")
        packages.append(contentsOf: parseMiseOutput(miseOutdated))

        let brewOutdated = await runCommand("\(brewBin) outdated --verbose")
        packages.append(contentsOf: parseBrewOutput(brewOutdated))

        return packages
    }

    private func parseMiseOutput(_ output: String) -> [PackageUpdate] {
        let lines = output.split(separator: "\n").map(String.init)
        var packages: [PackageUpdate] = []

        for line in lines {
            if line.hasPrefix("mise ") || line.contains("up to date") {
                continue
            }

            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4 else { continue }

            let name = parts[0]
            let current = parts[2]
            let new = parts[3]

            guard current.contains(where: { $0.isNumber }) || current == "[MISSING]",
                  new.contains(where: { $0.isNumber }) else {
                continue
            }

            packages.append(PackageUpdate(name: name, currentVersion: current, newVersion: new, source: .mise))
        }

        return packages
    }

    private func parseBrewOutput(_ output: String) -> [PackageUpdate] {
        let lines = output.split(separator: "\n").map(String.init)
        var packages: [PackageUpdate] = []

        for line in lines {
            let pattern = #"^([^\s]+)\s+\(([^)]+)\)\s+[<!]=?\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let nameRange = Range(match.range(at: 1), in: line)!
                let currentRange = Range(match.range(at: 2), in: line)!
                let newRange = Range(match.range(at: 3), in: line)!

                packages.append(PackageUpdate(
                    name: String(line[nameRange]),
                    currentVersion: String(line[currentRange]),
                    newVersion: String(line[newRange]),
                    source: .brew
                ))
            }
        }

        return packages
    }

    func runCommand(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

// MARK: - ViewModel

@MainActor
class MiseUpdaterViewModel: ObservableObject {
    @Published var state: AppState = .loading

    func checkForUpdates() async {
        let packages = await UpdateChecker.shared.checkForUpdates()

        if packages.isEmpty {
            state = .upToDate
            return
        }

        state = .updates(packages)
    }

    func installUpdates(packages: [PackageUpdate]) async {
        var logLines: [String] = ["▸ Démarrage de la mise à jour..."]
        state = .installing(progress: 0, log: logLines)

        let checker = UpdateChecker.shared
        let misePackages = packages.filter { $0.source == .mise }
        let brewPackages = packages.filter { $0.source == .brew }

        let totalSteps = (misePackages.isEmpty ? 0 : 1) + (brewPackages.isEmpty ? 0 : 1)
        var completedSteps = 0

        if !misePackages.isEmpty {
            logLines.append("▸ 🔧 Mise à jour des packages mise...")
            state = .installing(progress: Double(completedSteps) / Double(totalSteps), log: logLines)

            let miseLog = await checker.runCommand("\(checker.miseBin) upgrade")
            logLines.append(contentsOf: miseLog.split(separator: "\n").map { "  \($0)" })
            completedSteps += 1
            state = .installing(progress: Double(completedSteps) / Double(totalSteps), log: Array(logLines.suffix(10)))
        }

        if !brewPackages.isEmpty {
            logLines.append("▸ 🍺 Mise à jour des packages Homebrew...")
            state = .installing(progress: Double(completedSteps) / Double(totalSteps), log: Array(logLines.suffix(10)))

            let brewLog = await checker.runCommand("\(checker.brewBin) upgrade")
            logLines.append(contentsOf: brewLog.split(separator: "\n").map { "  \($0)" })
            completedSteps += 1
            state = .installing(progress: Double(completedSteps) / Double(totalSteps), log: Array(logLines.suffix(10)))
        }

        logLines.append("▸ ✅ Terminé!")
        state = .done(log: Array(logLines.suffix(10)))
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = MiseUpdaterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .loading:
                LoadingView()
            case .upToDate:
                UpToDateView()
            case .updates(let packages):
                UpdatesListView(packages: packages) {
                    Task { await viewModel.installUpdates(packages: packages) }
                }
            case .installing(let progress, let log):
                InstallingView(progress: progress, log: log)
            case .done(let log):
                DoneView(log: log)
            }
        }
        .frame(width: 450, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.checkForUpdates()
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Vérification des mises à jour...")
                .foregroundColor(.secondary)
        }
    }
}

struct UpToDateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("✅")
                .font(.system(size: 48))
            Text("Tout est à jour")
                .font(.title2.bold())
            Button("OK") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct UpdatesListView: View {
    let packages: [PackageUpdate]
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🚀")
                    .font(.system(size: 32))
                Text("Mises à jour")
                    .font(.title.bold())
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(packages) { pkg in
                        HStack {
                            Text(pkg.source.icon)
                            Text(pkg.name)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(pkg.currentVersion)
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(pkg.newVersion)
                                .foregroundColor(.green)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Plus tard") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Installer") {
                    onInstall()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

struct InstallingView: View {
    let progress: Double
    let log: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("⏳")
                    .font(.system(size: 24))
                Text("Installation...")
                    .font(.title2.bold())
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 150)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            ProgressView(value: progress)
                .padding(.horizontal, 24)

            HStack {
                Spacer()
                Button("Fermer") { }
                    .disabled(true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

struct DoneView: View {
    let log: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("✅")
                    .font(.system(size: 24))
                Text("Terminé !")
                    .font(.title2.bold())
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 150)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            ProgressView(value: 1.0)
                .tint(.green)
                .padding(.horizontal, 24)

            HStack {
                Spacer()
                Button("OK") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - App

@main
struct MiseUpdaterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
