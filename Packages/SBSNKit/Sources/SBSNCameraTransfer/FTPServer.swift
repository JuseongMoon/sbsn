import Foundation
import Network

/// 카메라의 FTP 자동 전송을 받기 위한 최소 FTP 서버.
///
/// 상태는 전부 `queue` 하나에서만 읽고 쓴다. 콜백(`onLog`, `onEvent`, `onFileReceived`)은 `start()` 전에 설정하고,
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

    /// 카메라 연결 상태를 화면에 보여 주기 위한 사건. 받은 파일은 `onFileReceived`로 따로 온다.
    public enum Event: Sendable, Equatable {
        /// 열려 있는 제어 연결 수가 바뀌었다(카메라가 접속하거나 연결을 닫았다).
        case connections(Int)
        case loggedIn
        /// 사용자 이름이나 비밀번호가 틀렸다.
        case loginRejected
        /// 파일을 받기 시작했다(파일 이름).
        case receiving(String)
        /// 받던 파일을 버렸다. 전송이 중단됐거나 JPEG가 잘렸다(파일 이름).
        case discarded(String)
    }

    public let port: UInt16
    public var onLog: (@Sendable (String) -> Void)?
    public var onEvent: (@Sendable (Event) -> Void)?
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

    func notify(_ event: Event) {
        onEvent?(event)
    }

    func didReceive(_ file: ReceivedFile) {
        onFileReceived?(file)
    }

    func sessionDidClose(_ session: FTPSession) {
        guard sessions.removeValue(forKey: ObjectIdentifier(session)) != nil else { return }
        notify(.connections(sessions.count))
    }

    private func accept(_ connection: NWConnection) {
        let session = FTPSession(control: connection, server: self)
        sessions[ObjectIdentifier(session)] = session
        notify(.connections(sessions.count))
        session.start()
    }
}

public enum FTPServerError: Error {
    case invalidPort
}
