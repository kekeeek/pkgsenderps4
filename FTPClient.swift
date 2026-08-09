import Foundation

enum FTPError: Error, LocalizedError {
    case connectionFailed(String)
    case authFailed
    case commandFailed(String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return msg
        case .authFailed: return "Login to the PS4's FTP server failed."
        case .commandFailed(let msg): return msg
        case .invalidResponse: return "Unexpected response from the PS4's FTP server."
        case .cancelled: return "Operation cancelled."
        }
    }
}

struct FTPFileEntry {
    let name: String
    let size: Int64
}

/// Minimal FTP client built directly on Foundation's Stream API, just
/// enough to talk to GoldHEN's FTP server: login, change directory,
/// list, upload, delete.
///
/// Runs its own background thread with a dedicated RunLoop so the
/// Stream delegate callbacks fire reliably, and exposes a simple
/// sequential/blocking-style API. Every method here is meant to be
/// called from a background thread (never the main thread/main actor) -
/// the UI layer is responsible for that.
final class FTPClient: NSObject, StreamDelegate {

    private var controlInput: InputStream?
    private var controlOutput: OutputStream?
    private var clientThread: Thread?
    private var clientRunLoop: RunLoop?

    private let responseSemaphore = DispatchSemaphore(value: 0)
    private var responseBuffer = Data()
    private var lastResponseLines: [String] = []
    private var streamError: Error?
    private let openSemaphore = DispatchSemaphore(value: 0)

    // MARK: - Connection lifecycle

    func connect(host: String, port: Int, timeout: TimeInterval = 15) throws {
        streamError = nil

        let thread = Thread { [weak self] in
            guard let self = self else { return }
            var input: InputStream?
            var output: OutputStream?
            Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
            guard let inp = input, let out = output else {
                self.streamError = FTPError.connectionFailed("Could not create a connection to \(host):\(port).")
                self.openSemaphore.signal()
                return
            }
            self.controlInput = inp
            self.controlOutput = out
            inp.delegate = self
            out.delegate = self
            let rl = RunLoop.current
            self.clientRunLoop = rl
            inp.schedule(in: rl, forMode: .default)
            out.schedule(in: rl, forMode: .default)
            inp.open()
            out.open()
            self.openSemaphore.signal()
            // Keep this thread's run loop alive for the life of the connection,
            // so Stream delegate callbacks keep firing.
            while !Thread.current.isCancelled {
                rl.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
            }
        }
        thread.name = "FTPClient"
        thread.start()
        self.clientThread = thread

        if openSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw FTPError.connectionFailed("Connection to \(host):\(port) timed out.")
        }
        if let err = streamError { throw err }

        // Read the server's welcome banner (220 ...)
        _ = try readResponse(timeout: timeout)
    }

    func disconnect() {
        _ = try? sendCommand("QUIT", timeout: 3)
        controlInput?.close()
        controlOutput?.close()
        clientThread?.cancel()
        controlInput = nil
        controlOutput = nil
    }

    // MARK: - StreamDelegate (control connection only)

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream, input === controlInput else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let read = input.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                responseBuffer.append(contentsOf: buffer[0..<read])
                processBufferedLines()
            }
        case .errorOccurred:
            guard aStream === controlInput || aStream === controlOutput else { return }
            streamError = aStream.streamError ?? FTPError.connectionFailed("Connection error.")
            responseSemaphore.signal()
        default:
            break
        }
    }

    private func processBufferedLines() {
        guard let text = String(data: responseBuffer, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let last = lines.last, last.count >= 4 else { return }
        // A final reply line looks like "226 Transfer complete", a
        // continuation line looks like "150-About to send data".
        let code = last.prefix(3)
        let sep = last[last.index(last.startIndex, offsetBy: 3)]
        if Int(code) != nil && sep == " " {
            lastResponseLines = lines
            responseBuffer.removeAll()
            responseSemaphore.signal()
        }
    }

    // MARK: - Low-level command/response

    @discardableResult
    private func sendCommand(_ command: String, timeout: TimeInterval = 15) throws -> (code: Int, lines: [String]) {
        guard let output = controlOutput else { throw FTPError.connectionFailed("Not connected.") }
        let line = command + "\r\n"
        guard let data = line.data(using: .utf8) else {
            throw FTPError.commandFailed("Could not encode command.")
        }
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            _ = output.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }
        return try readResponse(timeout: timeout)
    }

    @discardableResult
    private func readResponse(timeout: TimeInterval) throws -> (code: Int, lines: [String]) {
        if responseSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw FTPError.commandFailed("The PS4 did not respond in time.")
        }
        if let err = streamError {
            streamError = nil
            throw err
        }
        guard let last = lastResponseLines.last, last.count >= 3, let code = Int(last.prefix(3)) else {
            throw FTPError.invalidResponse
        }
        return (code, lastResponseLines)
    }

    // MARK: - High-level FTP operations

    func login(user: String = "anonymous", password: String = "") throws {
        let userResp = try sendCommand("USER \(user)")
        if userResp.code == 230 { return } // some servers skip the password step entirely
        guard userResp.code == 331 else { throw FTPError.authFailed }
        let passResp = try sendCommand("PASS \(password)")
        guard passResp.code == 230 else { throw FTPError.authFailed }
    }

    func setBinaryMode() throws {
        let resp = try sendCommand("TYPE I")
        guard resp.code == 200 else { throw FTPError.commandFailed("Could not switch to binary mode.") }
    }

    private func changeDirectory(_ path: String) throws {
        let resp = try sendCommand("CWD \(path)")
        guard resp.code == 250 else { throw FTPError.commandFailed("Could not open \(path) on the PS4.") }
    }

    private func makeDirectory(_ path: String) {
        _ = try? sendCommand("MKD \(path)")
    }

    /// Creates each path component if needed, then changes into it - mirrors
    /// the desktop/Android apps' "ensure /data/pkg exists" behavior.
    func ensureAndEnterDirectory(_ path: String) throws {
        let parts = path.split(separator: "/").map(String.init)
        var current = ""
        for part in parts {
            current += "/\(part)"
            do {
                try changeDirectory(current)
            } catch {
                makeDirectory(current)
                try changeDirectory(current)
            }
        }
    }

    private func enterPassiveMode() throws -> (host: String, port: Int) {
        let resp = try sendCommand("PASV")
        guard resp.code == 227, let line = resp.lines.last else {
            throw FTPError.commandFailed("The PS4 refused passive mode.")
        }
        // Line looks like: 227 Entering Passive Mode (192,168,1,50,200,15).
        guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")") else {
            throw FTPError.invalidResponse
        }
        let numbers = line[line.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Int($0) }
        guard numbers.count == 6 else { throw FTPError.invalidResponse }
        let dataHost = "\(numbers[0]).\(numbers[1]).\(numbers[2]).\(numbers[3])"
        let dataPort = numbers[4] * 256 + numbers[5]
        return (dataHost, dataPort)
    }

    private func openDataStreams(host: String, port: Int) throws -> (InputStream, OutputStream) {
        guard let rl = clientRunLoop else { throw FTPError.connectionFailed("Not connected.") }
        var input: InputStream?
        var output: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
        guard let dIn = input, let dOut = output else {
            throw FTPError.connectionFailed("Could not open a data connection to the PS4.")
        }
        dIn.schedule(in: rl, forMode: .default)
        dOut.schedule(in: rl, forMode: .default)
        dIn.open()
        dOut.open()
        return (dIn, dOut)
    }

    /// Lists files in the current directory. Parses standard Unix-style
    /// LIST output, which is what GoldHEN's FTP server returns.
    func listFiles() throws -> [FTPFileEntry] {
        let (dataHost, dataPort) = try enterPassiveMode()
        let (dIn, dOut) = try openDataStreams(host: dataHost, port: dataPort)
        defer { dIn.close(); dOut.close() }

        let listResp = try sendCommand("LIST")
        guard listResp.code == 150 || listResp.code == 125 else {
            throw FTPError.commandFailed("The PS4 refused to list files.")
        }

        var collected = Data()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if dIn.hasBytesAvailable {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let read = dIn.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    collected.append(contentsOf: buffer[0..<read])
                } else if read == 0 {
                    break
                }
            } else if dIn.streamStatus == .atEnd || dIn.streamStatus == .closed {
                break
            } else {
                usleep(20_000)
            }
        }

        _ = try? readResponse(timeout: 10) // final 226 Transfer complete

        let text = String(data: collected, encoding: .utf8) ?? ""
        var entries: [FTPFileEntry] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9, !parts[0].hasPrefix("d") else { continue } // skip directories
            guard let size = Int64(parts[4]) else { continue }
            let name = parts[8...].joined(separator: " ")
            if name.lowercased().hasSuffix(".pkg") {
                entries.append(FTPFileEntry(name: name, size: size))
            }
        }
        return entries
    }

    func deleteFile(_ name: String) throws {
        let resp = try sendCommand("DELE \(name)")
        guard resp.code == 250 else {
            throw FTPError.commandFailed("Could not delete \(name) on the PS4.")
        }
    }

    /// Uploads a file's contents, calling `onProgress` periodically with
    /// bytes sent so far.
    func uploadFile(fileURL: URL, remoteName: String, onProgress: @escaping (Int64) -> Void) throws {
        let (dataHost, dataPort) = try enterPassiveMode()
        let (dIn, dOut) = try openDataStreams(host: dataHost, port: dataPort)
        defer { dIn.close(); dOut.close() }

        let storResp = try sendCommand("STOR \(remoteName)")
        guard storResp.code == 150 || storResp.code == 125 else {
            throw FTPError.commandFailed("The PS4 refused the upload.")
        }

        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
            throw FTPError.commandFailed("Could not open the file to send.")
        }
        defer { fileHandle.closeFile() }

        let chunkSize = 256 * 1024
        var sent: Int64 = 0
        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            var offset = 0
            chunk.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let base = ptr.bindMemory(to: UInt8.self).baseAddress!
                while offset < chunk.count {
                    var waited = 0.0
                    while !dOut.hasSpaceAvailable && waited < 15 {
                        usleep(5_000)
                        waited += 0.005
                    }
                    let written = dOut.write(base + offset, maxLength: chunk.count - offset)
                    if written <= 0 { return }
                    offset += written
                }
            }
            sent += Int64(chunk.count)
            onProgress(sent)
        }

        _ = try? readResponse(timeout: 30) // final 226 Transfer complete
    }
}
