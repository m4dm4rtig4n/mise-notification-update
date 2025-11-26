import SwiftUI
import AppKit

// MARK: - Model

struct PackageUpdate: Identifiable {
    let id = UUID()
    let name: String
    let currentVersion: String
    let newVersion: String
}

enum AppState {
    case loading
    case updates([PackageUpdate])
    case installing(progress: Double, log: [String])
    case done(log: [String])
    case upToDate
}

// MARK: - ViewModel

@MainActor
class MiseUpdaterViewModel: ObservableObject {
    @Published var state: AppState = .loading

    private let miseBin: String

    init() {
        self.miseBin = ProcessInfo.processInfo.environment["MISE_BIN"]
            ?? "\(NSHomeDirectory())/.local/bin/mise"
    }

    func checkForUpdates() async {
        let outdated = await runCommand("\(miseBin) outdated")
        let lines = outdated.split(separator: "\n").map(String.init)

        if lines.isEmpty {
            state = .upToDate
            return
        }

        var packages: [PackageUpdate] = []
        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 4 else { continue }
            let name = parts[0]
            let current = parts[2]
            let new = parts[3]
            packages.append(PackageUpdate(name: name, currentVersion: current, newVersion: new))
        }

        state = .updates(packages)
    }

    func installUpdates() async {
        state = .installing(progress: 0, log: ["▸ Démarrage de la mise à jour..."])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: miseBin)
        process.arguments = ["upgrade"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            state = .done(log: ["Erreur: \(error.localizedDescription)"])
            return
        }

        var logLines: [String] = []
        let handle = pipe.fileHandleForReading

        // Read output line by line
        while process.isRunning || handle.availableData.count > 0 {
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                let newLines = line.split(separator: "\n").map { "▸ \($0)" }
                logLines.append(contentsOf: newLines)

                // Keep last 10 lines
                if logLines.count > 10 {
                    logLines = Array(logLines.suffix(10))
                }

                let checkmarks = logLines.filter { $0.contains("✓") }.count
                let progress = min(Double(checkmarks) / 5.0, 1.0) // Estimate

                state = .installing(progress: progress, log: logLines)
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        process.waitUntilExit()
        state = .done(log: logLines)
    }

    private func runCommand(_ command: String) async -> String {
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
                    Task { await viewModel.installUpdates() }
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
    @Environment(\.dismiss) var dismiss

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
                            Text("⬆️")
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
