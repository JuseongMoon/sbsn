import Foundation
import Network

/// 카메라의 FTP 자동 전송을 받기 위한 최소 FTP 서버.
///
/// 상태는 전부 `queue` 하나에서만 읽고 쓴다. 콜백(`onLog`, `onFileReceived`)은 `start()` 전에 설정하고,
/// 호출은 `queue`에서 일어나므로 UI 갱신은 받는 쪽에서 메인 액터로 넘긴다.
public final class FTPServer: @unchecked Sendable {
    public struct ReceivedFile: Sendable {
        public let url: URL
        public let byteCount: Int
        public let duration: TimeInterval

        public init(url: URL, byteCount: Int, duration: TimeInterval) {
            self.url = url
            self.byteCount = byteCount
            self.duration = duration
        }
    }

    public let port: UInt16
    public var onLog: (@Sendable (String) -> Void)?
    public var onFileReceived: (@Sendable (ReceivedFile) -> Void)?

    let rootDirectory: URL
    let credentials: (user: String, password: String)?
    let queue = DispatchQueue(label: "SBSNCameraTransfer.FTPServer")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: FTPSession] = [:]

    public init(port: UInt16, rootDirectory: URL, credentials: (user: String, password: String)? = nil) {
        self.port = port
        self.rootDirectory = rootDirectory
        self.credentials = credentials
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw FTPServerError.invalidPort }
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            self?.log("listener: \(state)")
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            sessions.values.forEach { $0.close() }
            sessions.removeAll()
        }
    }

    func log(_ message: String) {
        onLog?(message)
    }

    func didReceive(_ file: ReceivedFile) {
        onFileReceived?(file)
    }

    func sessionDidClose(_ session: FTPSession) {
        sessions[ObjectIdentifier(session)] = nil
    }

    private func accept(_ connection: NWConnection) {
        let session = FTPSession(control: connection, server: self)
        sessions[ObjectIdentifier(session)] = session
        session.start()
    }
}

public enum FTPServerError: Error {
    case invalidPort
}
