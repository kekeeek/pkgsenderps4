import Foundation
import SwiftUI

struct RemoteFile: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
}

enum StatusKind {
    case info, success, error
}

@MainActor
final class SenderViewModel: ObservableObject {

    // Standard path used by GoldHEN's Package Installer, identical to
    // the one scanned when installing from a USB drive.
    nonisolated static let remotePath = "/data/pkg"

    @Published var ps4ip: String = ""
    @Published var ps4port: String = "2121"

    @Published var selectedFileURL: URL?
    @Published var selectedFileName: String?
    @Published var selectedFileSize: Int64 = 0

    @Published var isSending = false
    @Published var progressPercent: Double = 0
    @Published var progressSpeedMBs: Double = 0
    @Published var showProgress = false

    @Published var statusMessage: String?
    @Published var statusKind: StatusKind = .info

    @Published var remoteFiles: [RemoteFile] = []
    @Published var isRefreshing = false
    @Published var deletingFileName: String?

    private var securityScopedURL: URL?

    func selectFile(url: URL) {
        guard url.pathExtension.lowercased() == "pkg" else {
            showStatus(.error, "The file must be a .pkg")
            return
        }

        // Stop accessing any previously-picked file's security scope.
        securityScopedURL?.stopAccessingSecurityScopedResource()

        let didStart = url.startAccessingSecurityScopedResource()
        securityScopedURL = didStart ? url : nil

        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        selectedFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        statusMessage = nil
    }

    func send() {
        guard let fileURL = selectedFileURL, let fileName = selectedFileName else {
            showStatus(.error, "Choose a .pkg file first.")
            return
        }
        let ip = ps4ip.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else {
            showStatus(.error, "Enter your PS4's IP address.")
            return
        }
        let port = Int(ps4port.trimmingCharacters(in: .whitespaces)) ?? 2121

        isSending = true
        showProgress = true
        progressPercent = 0
        progressSpeedMBs = 0
        showStatus(.info, "Connecting to \(ip)...")

        let totalSize = selectedFileSize

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let client = FTPClient()
            var lastBytes: Int64 = 0
            var lastTime = Date()

            do {
                try client.connect(host: ip, port: port)
                try client.login()
                try client.setBinaryMode()
                try client.ensureAndEnterDirectory(Self.remotePath)

                try client.uploadFile(fileURL: fileURL, remoteName: fileName) { sent in
                    let now = Date()
                    let elapsed = now.timeIntervalSince(lastTime)
                    if elapsed >= 0.3 {
                        let bytesSinceLast = sent - lastBytes
                        let speedMBs = elapsed > 0 ? (Double(bytesSinceLast) / elapsed) / (1024 * 1024) : 0
                        let percent = totalSize > 0 ? min(100, (Double(sent) / Double(totalSize)) * 100) : 0
                        lastBytes = sent
                        lastTime = now
                        Task { @MainActor in
                            self.progressPercent = percent
                            self.progressSpeedMBs = speedMBs
                        }
                    }
                }
                client.disconnect()

                await MainActor.run {
                    self.progressPercent = 100
                    self.showStatus(.success, "✅ Sent! Open Package Installer on your PS4 to install it.")
                    self.isSending = false
                    self.refreshFiles()
                }
            } catch {
                client.disconnect()
                await MainActor.run {
                    self.showStatus(.error, "❌ \(error.localizedDescription)")
                    self.isSending = false
                }
            }
        }
    }

    func refreshFiles() {
        let ip = ps4ip.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else {
            remoteFiles = []
            return
        }
        let port = Int(ps4port.trimmingCharacters(in: .whitespaces)) ?? 2121

        isRefreshing = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let client = FTPClient()
            do {
                try client.connect(host: ip, port: port)
                try client.login()
                try client.ensureAndEnterDirectory(Self.remotePath)
                let files = try client.listFiles()
                client.disconnect()

                await MainActor.run {
                    self.remoteFiles = files.map { RemoteFile(name: $0.name, size: $0.size) }
                    self.isRefreshing = false
                }
            } catch {
                client.disconnect()
                await MainActor.run {
                    self.remoteFiles = []
                    self.isRefreshing = false
                    self.showStatus(.error, "❌ \(error.localizedDescription)")
                }
            }
        }
    }

    func deleteFile(_ file: RemoteFile) {
        let ip = ps4ip.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        let port = Int(ps4port.trimmingCharacters(in: .whitespaces)) ?? 2121

        deletingFileName = file.name

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let client = FTPClient()
            do {
                try client.connect(host: ip, port: port)
                try client.login()
                try client.ensureAndEnterDirectory(Self.remotePath)
                try client.deleteFile(file.name)
                client.disconnect()

                await MainActor.run {
                    self.remoteFiles.removeAll { $0.id == file.id }
                    self.deletingFileName = nil
                }
            } catch {
                client.disconnect()
                await MainActor.run {
                    self.deletingFileName = nil
                    self.showStatus(.error, "❌ Delete failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func showStatus(_ kind: StatusKind, _ message: String) {
        statusKind = kind
        statusMessage = message
    }

    static func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}
