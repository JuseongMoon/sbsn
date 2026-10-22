import Foundation
import Network

/// FTP 제어 연결 하나. 서버의 `queue`에서만 동작한다.
final class FTPSession: @unchecked Sendable {
    private let control: NWConnection
    private unowned let server: FTPServer
    private var queue: DispatchQueue { server.queue }

    private var lineBuffer = Data()
    private var currentDirectory = "/"
    private var pendingUser: String?
    private var isAuthenticated = false
    private var renameSource: URL?
    private var isControlClosed = false

    private var passiveListener: NWListener?
    private var dataConnection: NWConnection?
    private var dataConnectionWaiter: ((NWConnection) -> Void)?

    init(control: NWConnection, server: FTPServer) {
        self.control = control
        self.server = server
    }

    func start() {
        control.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.server.log("control ready: \(self.control.endpoint)")
                self.reply(220, "sbsn FTP ready")
                self.receiveControl()
            case .failed(let error):
                self.server.log("control failed: \(error)")
                self.close()
            case .cancelled:
                self.server.sessionDidClose(self)
            default:
                break
            }
        }
        control.start(queue: queue)
    }

    /// 보내려고 쌓아 둔 응답을 모두 내보낸 뒤 제어 연결을 닫는다. 바로 cancel()하면 아직 안 나간 응답(QUIT의 221 등)이 버려진다.
    func close() {
        guard !isControlClosed else { return }
        isControlClosed = true
        closeData()
        control.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [control] _ in
            control.cancel()
        })
        // 상대가 받지 않아 보내기가 끝나지 않더라도 연결이 남지 않게 한다.
        queue.asyncAfter(deadline: .now() + 5) { [control] in
            control.cancel()
        }
    }

    // MARK: - Control channel

    private func receiveControl() {
        control.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.consume(data) }
            if isComplete || error != nil {
                self.server.log("control closed\(error.map { ": \($0)" } ?? "")")
                self.close()
                return
            }
            self.receiveControl()
        }
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            var lineData = lineBuffer[lineBuffer.startIndex..<newline]
            if lineData.last == UInt8(ascii: "\r") { lineData = lineData.dropLast() }
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            handle(String(decoding: lineData, as: UTF8.self))
        }
    }

    private func reply(_ code: Int, _ text: String) {
        server.log("<- \(code) \(text)")
        control.send(content: Data("\(code) \(text)\r\n".utf8), completion: .contentProcessed { _ in })
    }

    private func replyMultiline(_ code: Int, _ lines: [String], end: String) {
        let body = (["\(code)-\(lines.first ?? "")"] + lines.dropFirst().map { " \($0)" } + ["\(code) \(end)"])
            .joined(separator: "\r\n") + "\r\n"
        server.log("<- \(code) (multiline)")
        control.send(content: Data(body.utf8), completion: .contentProcessed { _ in })
    }

    private func handle(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let command = parts.first.map { $0.uppercased() } ?? ""
        let argument = parts.count > 1 ? String(parts[1]) : ""
        server.log("-> \(command == "PASS" ? "PASS ****" : line)")

        if !isAuthenticated, !["USER", "PASS", "QUIT", "FEAT", "SYST", "OPTS", "AUTH"].contains(command) {
            reply(530, "Please login with USER and PASS")
            return
        }

        switch command {
        case "USER":
            pendingUser = argument
            reply(331, "Password required")
        case "PASS":
            if let credentials = server.credentials,
               pendingUser != credentials.user || argument != credentials.password {
                reply(530, "Login incorrect")
            } else {
                isAuthenticated = true
                reply(230, "Logged in")
            }
        case "AUTH":
            reply(502, "TLS not supported")
        case "SYST":
            reply(215, "UNIX Type: L8")
        case "FEAT":
            replyMultiline(211, ["Features:", "UTF8", "EPSV", "PASV", "SIZE", "MDTM"], end: "End")
        case "OPTS":
            reply(200, "OK")
        case "NOOP":
            reply(200, "OK")
        case "TYPE", "MODE", "STRU":
            reply(200, "OK")
        case "PWD", "XPWD":
            reply(257, "\"\(currentDirectory)\" is current directory")
        case "CWD", "XCWD":
            changeDirectory(to: argument)
        case "CDUP":
            changeDirectory(to: "..")
        case "MKD", "XMKD":
            makeDirectory(argument)
        case "PASV":
            openPassive(extended: false)
        case "EPSV":
            openPassive(extended: true)
        case "PORT":
            openActive(portArgument: argument)
        case "STOR":
            store(argument, append: false)
        case "APPE":
            store(argument, append: true)
        case "LIST", "NLST":
            list(namesOnly: command == "NLST")
        case "SIZE":
            size(of: argument)
        case "MDTM":
            modificationTime(of: argument)
        case "DELE":
            delete(argument)
        case "RNFR":
            renameFrom(argument)
        case "RNTO":
            renameTo(argument)
        case "QUIT":
            reply(221, "Bye")
            close()
        default:
            reply(502, "Command not implemented")
        }
    }

    // MARK: - Paths

    /// 클라이언트 경로를 현재 디렉터리 기준으로 정규화한 가상 경로("/a/b"). 루트 밖으로 나가면 nil.
    private func virtualPath(for path: String) -> String? {
        let joined = path.hasPrefix("/") ? path : currentDirectory + "/" + path
        var components: [Substring] = []
        for component in joined.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": if components.popLast() == nil { return nil }
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private func fileURL(forVirtualPath virtual: String) -> URL {
        virtual.split(separator: "/").reduce(server.rootDirectory) { $0.appendingPathComponent(String($1)) }
    }

    /// 클라이언트 경로를 루트 아래의 실제 경로로 바꾼다. 루트 밖으로 나가면 nil.
    private func resolve(_ path: String) -> URL? {
        virtualPath(for: path).map(fileURL(forVirtualPath:))
    }

    private func changeDirectory(to path: String) {
        guard let virtual = virtualPath(for: path) else { return reply(550, "Invalid path") }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL(forVirtualPath: virtual).path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            currentDirectory = virtual
            reply(250, "Directory changed to \(virtual)")
        } else {
            reply(550, "No such directory")
        }
    }

    private func makeDirectory(_ path: String) {
        guard let virtual = virtualPath(for: path) else { return reply(550, "Invalid path") }
        do {
            try FileManager.default.createDirectory(at: fileURL(forVirtualPath: virtual), withIntermediateDirectories: true)
            reply(257, "\"\(virtual)\" created")
        } catch {
            reply(550, "Cannot create directory")
        }
    }

    private func size(of path: String) {
        guard let url = resolve(path),
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        else { return reply(550, "No such file") }
        reply(213, "\(size)")
    }

    private func modificationTime(of path: String) {
        guard let url = resolve(path),
              let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        else { return reply(550, "No such file") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        reply(213, formatter.string(from: date))
    }

    private func delete(_ path: String) {
        guard let url = resolve(path), (try? FileManager.default.removeItem(at: url)) != nil
        else { return reply(550, "Cannot delete") }
        reply(250, "Deleted")
    }

    private func renameFrom(_ path: String) {
        guard let url = resolve(path), FileManager.default.fileExists(atPath: url.path)
        else { return reply(550, "No such file") }
        renameSource = url
        reply(350, "Ready for RNTO")
    }

    private func renameTo(_ path: String) {
        guard let source = renameSource, let destination = resolve(path) else { return reply(503, "RNFR required") }
        renameSource = nil
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: source, to: destination)
            reply(250, "Renamed")
        } catch {
            reply(550, "Rename failed")
        }
    }

    // MARK: - Data channel

    private func openPassive(extended: Bool) {
        closeData()
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            return reply(425, "Cannot open passive port")
        }
        passiveListener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.server.log("data connected: \(connection.endpoint)")
            self.passiveListener?.cancel()
            self.passiveListener = nil
            self.dataConnection = connection
            connection.start(queue: self.queue)
            if let waiter = self.dataConnectionWaiter {
                self.dataConnectionWaiter = nil
                waiter(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, let port = listener.port?.rawValue else { return }
            if extended {
                self.reply(229, "Entering Extended Passive Mode (|||\(port)|)")
            } else if let address = self.localIPv4Address() {
                let host = address.replacingOccurrences(of: ".", with: ",")
                self.reply(227, "Entering Passive Mode (\(host),\(port >> 8),\(port & 0xff))")
            } else {
                self.reply(425, "No IPv4 address for passive mode")
            }
        }
        listener.start(queue: queue)
    }

    /// 액티브 모드: 클라이언트가 알려 준 주소(h1,h2,h3,h4,p1,p2)로 서버가 데이터 연결을 연다.
    private func openActive(portArgument: String) {
        closeData()
        let numbers = portArgument.split(separator: ",").compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 6, numbers.allSatisfy({ $0 <= 255 }),
              let port = NWEndpoint.Port(rawValue: numbers[4] << 8 | numbers[5])
        else { return reply(501, "Invalid PORT argument") }
        let host = NWEndpoint.Host(numbers[0..<4].map(String.init).joined(separator: "."))
        let connection = NWConnection(host: host, port: port, using: .tcp)
        dataConnection = connection
        connection.start(queue: queue)
        reply(200, "PORT command successful")
    }

    private func localIPv4Address() -> String? {
        guard case .hostPort(let host, _) = control.currentPath?.localEndpoint else { return nil }
        switch host {
        case .ipv4(let address):
            return address.rawValue.map(String.init).joined(separator: ".")
        case .ipv6(let address):
            // IPv4-mapped IPv6 (::ffff:a.b.c.d)
            let bytes = Array(address.rawValue)
            guard bytes.count == 16, bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff
            else { return nil }
            return bytes[12...].map(String.init).joined(separator: ".")
        default:
            return nil
        }
    }

    private func withDataConnection(_ body: @escaping (NWConnection) -> Void) {
        if let dataConnection {
            body(dataConnection)
        } else if passiveListener != nil {
            dataConnectionWaiter = body
        } else {
            reply(425, "Use PASV or EPSV first")
        }
    }

    private func closeData() {
        passiveListener?.cancel()
        passiveListener = nil
        dataConnection?.cancel()
        dataConnection = nil
        dataConnectionWaiter = nil
    }

    private func store(_ path: String, append: Bool) {
        guard let url = resolve(path) else { return reply(553, "Invalid file name") }
        // STOR는 숨김 임시 파일로 받고 끝까지 받은 뒤에만 원래 이름으로 바꾼다. 중단된 전송이 사진처럼 남지 않게 하기 위해서다.
        let partialURL = append ? nil : url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).part")
        let writeURL = partialURL ?? url
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !append || !FileManager.default.fileExists(atPath: writeURL.path) {
                FileManager.default.createFile(atPath: writeURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: writeURL)
            if append { try handle.seekToEnd() }
            reply(150, "Opening data connection for \(url.lastPathComponent)")
            let transfer = Transfer(handle: handle, destination: url, partial: partialURL, startedAt: Date())
            withDataConnection { [weak self] connection in
                self?.receiveFile(from: connection, transfer: transfer, byteCount: 0)
            }
        } catch {
            reply(550, "Cannot open file")
        }
    }

    private struct Transfer {
        let handle: FileHandle
        let destination: URL
        let partial: URL?
        let startedAt: Date

        var writtenURL: URL { partial ?? destination }
    }

    /// JPEG는 EOI 표식(FF D9)으로 끝난다. 끝 근처에 표식이 없으면 잘린 파일로 본다.
    /// 일부 카메라는 EOI 뒤에 부가 데이터를 붙이므로 마지막 4KB 안에서 찾는다.
    private static func isTruncatedJPEG(at url: URL, named name: String) -> Bool {
        guard ["jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 2 else { return true }
        let tailLength = min(size, 4096)
        try? handle.seek(toOffset: size - tailLength)
        guard let tail = try? handle.read(upToCount: Int(tailLength)) else { return true }
        return tail.range(of: Data([0xFF, 0xD9])) == nil
    }

    private func receiveFile(from connection: NWConnection, transfer: Transfer, byteCount: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var total = byteCount
            if let data, !data.isEmpty {
                do {
                    try transfer.handle.write(contentsOf: data)
                    total += data.count
                } catch {
                    self.discard(transfer)
                    return self.reply(451, "Write failed")
                }
            }
            if let error {
                self.server.log("data error: \(error)")
                self.discard(transfer)
                return self.reply(426, "Transfer aborted")
            }
            if isComplete {
                // FTP는 데이터 연결을 닫는 것으로 파일 끝을 알린다. 카메라가 전송을 취소하면 제어 연결을 먼저 끊고
                // 데이터 연결도 닫으므로, 그 경우는 완료가 아니라 중단으로 본다.
                if self.isControlClosed {
                    self.server.log("discarded \(transfer.destination.lastPathComponent): control closed before transfer finished")
                    return self.discard(transfer)
                }
                try? transfer.handle.close()
                if Self.isTruncatedJPEG(at: transfer.writtenURL, named: transfer.destination.lastPathComponent) {
                    self.server.log("discarded \(transfer.destination.lastPathComponent): JPEG has no end marker")
                    self.discard(transfer)
                    return self.reply(451, "Incomplete JPEG")
                }
                self.closeData()
                do {
                    if let partial = transfer.partial {
                        try? FileManager.default.removeItem(at: transfer.destination)
                        try FileManager.default.moveItem(at: partial, to: transfer.destination)
                    }
                } catch {
                    try? transfer.partial.map(FileManager.default.removeItem(at:))
                    return self.reply(451, "Cannot finalize file")
                }
                let file = FTPServer.ReceivedFile(url: transfer.destination, byteCount: total, duration: Date().timeIntervalSince(transfer.startedAt))
                self.server.didReceive(file)
                return self.reply(226, "Transfer complete (\(total) bytes)")
            }
            self.receiveFile(from: connection, transfer: transfer, byteCount: total)
        }
    }

    private func discard(_ transfer: Transfer) {
        try? transfer.handle.close()
        closeData()
        if let partial = transfer.partial {
            try? FileManager.default.removeItem(at: partial)
        }
    }

    private func list(namesOnly: Bool) {
        guard let directory = resolve(currentDirectory) else { return reply(550, "Invalid path") }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { !$0.hasPrefix(".") }
        let lines = names.sorted().map { name -> String in
            if namesOnly { return name }
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            let isDirectory = (attributes?[.type] as? FileAttributeType) == .typeDirectory
            let size = attributes?[.size] as? Int ?? 0
            return "\(isDirectory ? "d" : "-")rw-r--r-- 1 sbsn sbsn \(size) Jan 01 00:00 \(name)"
        }
        reply(150, "Opening data connection for listing")
        withDataConnection { [weak self] connection in
            let body = lines.map { $0 + "\r\n" }.joined()
            connection.send(content: Data(body.utf8), isComplete: true, completion: .contentProcessed { [weak self] _ in
                guard let self else { return }
                self.closeData()
                self.reply(226, "Listing complete")
            })
        }
    }
}
