#if os(macOS)
import Foundation
import Testing
@testable import SBSNCameraTransfer

/// 실제 FTP 클라이언트(curl)로 서버를 검증한다. 카메라처럼 패시브·확장 패시브·액티브 모드로 올려 본다.
@Suite(.serialized)
struct FTPServerTests {
    let root: URL
    let source: URL
    let server: FTPServer
    let port: UInt16

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "FTPServerTests-\(UUID().uuidString)")
        root = base.appending(path: "root")
        source = base.appending(path: "DSC00001.JPG")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 바이트 패턴(31씩 증가)에는 FF D9가 나오지 않으므로, 끝에 붙인 EOI 표식만 JPEG 끝으로 인식된다.
        let body = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try (body + [0xFF, 0xD9]).write(to: source)
        try body.write(to: base.appending(path: "TRUNCATED.JPG"))
        port = UInt16.random(in: 40_000...49_000)
        server = FTPServer(port: port, rootDirectory: root, credentials: ("camera", "sbsn"))
        try server.start()
        Thread.sleep(forTimeInterval: 0.2)
    }

    @Test func uploadsWithExtendedPassiveMode() throws {
        let result = try curl(["-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/"])
        #expect(result.status == 0)
        #expect(try Data(contentsOf: root.appending(path: "DSC00001.JPG")) == Data(contentsOf: source))
        server.stop()
    }

    @Test func leavesNoPartialFileAfterUpload() throws {
        let result = try curl(["-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/"])
        #expect(result.status == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)) == ["DSC00001.JPG"])
        server.stop()
    }

    @Test func rejectsJPEGWithoutEndMarker() throws {
        let truncated = source.deletingLastPathComponent().appending(path: "TRUNCATED.JPG")
        let result = try curl(["-T", truncated.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/"])
        #expect(result.status != 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
        server.stop()
    }

    @Test func uploadsIntoNewDirectoriesWithPassiveMode() throws {
        let result = try curl(["--disable-epsv", "--ftp-create-dirs", "-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/DCIM/100MSDCF/"])
        #expect(result.status == 0)
        #expect(try Data(contentsOf: root.appending(path: "DCIM/100MSDCF/DSC00001.JPG")) == Data(contentsOf: source))
        server.stop()
    }

    @Test func uploadsWithActiveMode() throws {
        let result = try curl(["--ftp-port", "127.0.0.1", "--disable-eprt", "-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/"])
        #expect(result.status == 0)
        #expect(try Data(contentsOf: root.appending(path: "DSC00001.JPG")) == Data(contentsOf: source))
        server.stop()
    }

    @Test func rejectsWrongPassword() throws {
        let result = try curl(["-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/"], password: "wrong")
        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "DSC00001.JPG").path(percentEncoded: false)))
        server.stop()
    }

    @Test func refusesPathsOutsideRoot() throws {
        let result = try curl(["-T", source.path(percentEncoded: false), "ftp://127.0.0.1:\(port)/%2E%2E/escape.jpg"])
        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "escape.jpg").path(percentEncoded: false)))
        server.stop()
    }

    /// 연결을 닫을 때 쌓인 응답을 버리지 않아야 한다. QUIT의 221을 못 받으면 클라이언트(맥 ftplib)가 오류로 본다.
    /// nc는 입력을 다 보내면 송신 쪽을 먼저 닫으므로(half-close), 그때도 앞선 명령의 응답이 모두 와야 한다.
    @Test func repliesToQuitBeforeClosing() throws {
        for _ in 0..<20 {
            let output = try netcat("USER camera\r\nPASS sbsn\r\nQUIT\r\n")
            #expect(output.contains("221 Bye"), "받은 응답: \(output)")
        }
        server.stop()
    }

    private func netcat(_ input: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/nc")
        process.arguments = ["-w", "5", "127.0.0.1", String(port)]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        try process.run()
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func curl(_ arguments: [String], password: String = "sbsn") throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/curl")
        process.arguments = ["-sS", "--max-time", "10", "--user", "camera:\(password)"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
#endif
