import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 개발 메뉴: 고른 사진이 가져오는 경로마다 어떤 바이트로 오는지 확인한다(D037 실기기 확인, 설계 문서 4.3절).
///
/// 받은 파일을 손대지 않고 `Documents/MetaProbe/<경로>/`에 그대로 둔다. 맥으로 꺼내 ExifTool로 GPS·XMP·MakerNote·일련번호를 비교한다.
/// 경로: 선택기 `.current`, 선택기 `.compatible`, PHPicker item provider `loadFileRepresentation`, 파일 앱(`fileImporter`).
struct MetadataProbeView: View {
    @State private var currentItems: [PhotosPickerItem] = []
    @State private var compatibleItems: [PhotosPickerItem] = []
    @State private var showsProviderPicker = false
    @State private var showsImporter = false
    @State private var log: [String] = []

    var body: some View {
        List {
            Section {
                PhotosPicker("선택기 .current", selection: $currentItems, matching: .images, preferredItemEncoding: .current,
                             photoLibrary: .shared())
                    .accessibilityIdentifier("probe.current")
                PhotosPicker("선택기 .compatible", selection: $compatibleItems, matching: .images, preferredItemEncoding: .compatible,
                             photoLibrary: .shared())
                    .accessibilityIdentifier("probe.compatible")
                Button("item provider loadFileRepresentation") { showsProviderPicker = true }
                    .accessibilityIdentifier("probe.provider")
                Button("파일에서(fileImporter)") { showsImporter = true }
                    .accessibilityIdentifier("probe.files")
                Button("받은 파일 지우기", role: .destructive) {
                    try? FileManager.default.removeItem(at: MetadataProbeStore.root)
                    log.append("지움")
                }
            } footer: {
                Text("받은 파일은 앱 Documents/MetaProbe/에 그대로 둡니다. 시험 사진에는 위치가 있을 수 있으니 끝나면 지워 주세요.")
            }
            Section("기록") {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
            .accessibilityIdentifier("probe.log")
        }
        .navigationTitle("메타데이터 경로 시험")
        .onChange(of: currentItems) { _, items in load(items, route: "current") }
        .onChange(of: compatibleItems) { _, items in load(items, route: "compatible") }
        .sheet(isPresented: $showsProviderPicker) {
            ProviderPicker { lines in log.append(contentsOf: lines) }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for (index, url) in urls.enumerated() {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    log.append(MetadataProbeStore.keep(copyOf: url, route: "files", index: index, types: "file"))
                }
            case .failure(let error):
                log.append("files 실패: \(error.localizedDescription)")
            }
        }
    }

    private func load(_ items: [PhotosPickerItem], route: String) {
        guard !items.isEmpty else { return }
        Task {
            for (index, item) in items.enumerated() {
                let types = item.supportedContentTypes.map(\.identifier).joined(separator: ",")
                do {
                    if let file = try await item.loadTransferable(type: ProbeFile.self) {
                        log.append(MetadataProbeStore.keep(movingFrom: file.url, route: route, index: index, types: types))
                    } else {
                        log.append("\(route) #\(index): 없음 [\(types)]")
                    }
                } catch {
                    log.append("\(route) #\(index) 실패: \(error.localizedDescription) [\(types)]")
                }
            }
            if route == "current" { currentItems = [] } else { compatibleItems = [] }
        }
    }
}

/// 선택기가 넘긴 파일을 받자마자 앱 폴더로 복사한다(넘겨받은 임시 파일은 곧 지워진다).
private nonisolated struct ProbeFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            ProbeFile(url: try MetadataProbeStore.copyToIncoming(received.file))
        }
    }
}

nonisolated enum MetadataProbeStore {
    static var root: URL { URL.documentsDirectory.appending(path: "MetaProbe", directoryHint: .isDirectory) }

    static func copyToIncoming(_ source: URL) throws -> URL {
        let directory = root.appending(path: "incoming", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: UUID().uuidString + "-" + source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// 받은 파일을 경로 폴더로 옮기고 기록 한 줄을 돌려준다. 원래 이름 앞의 UUID는 뗀다.
    static func keep(movingFrom url: URL, route: String, index: Int, types: String) -> String {
        let name = url.lastPathComponent.split(separator: "-", maxSplits: 5).last.map(String.init) ?? url.lastPathComponent
        return place(url, route: route, name: "\(index)-\(name)", types: types, move: true)
    }

    static func keep(copyOf url: URL, route: String, index: Int, types: String) -> String {
        place(url, route: route, name: "\(index)-\(url.lastPathComponent)", types: types, move: false)
    }

    private static func place(_ url: URL, route: String, name: String, types: String, move: Bool) -> String {
        let directory = root.appending(path: route, directoryHint: .isDirectory)
        let destination = directory.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            if move {
                try FileManager.default.moveItem(at: url, to: destination)
            } else {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int) ?? 0
            return "\(route)/\(name) \(size)B [\(types)]"
        } catch {
            return "\(route)/\(name) 실패: \(error.localizedDescription)"
        }
    }
}

/// PHPicker를 직접 띄워 item provider의 `loadFileRepresentation`으로 받는다(SwiftUI 선택기와 다른 경로인지 비교용).
private struct ProviderPicker: UIViewControllerRepresentable {
    let onLog: @MainActor ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLog: onLog) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onLog: @MainActor ([String]) -> Void

        init(onLog: @escaping @MainActor ([String]) -> Void) {
            self.onLog = onLog
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let onLog = onLog
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let types = provider.registeredTypeIdentifiers
                guard let type = types.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                    onLog(["provider #\(index): 사진 표현 없음 [\(types.joined(separator: ","))]"])
                    continue
                }
                _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    let line: String
                    if let url, let copied = try? MetadataProbeStore.copyToIncoming(url) {
                        line = MetadataProbeStore.keep(movingFrom: copied, route: "provider", index: index,
                                                       types: types.joined(separator: ","))
                    } else {
                        line = "provider #\(index) 실패: \(error?.localizedDescription ?? "-")"
                    }
                    Task { @MainActor in onLog([line]) }
                }
            }
        }
    }
}
