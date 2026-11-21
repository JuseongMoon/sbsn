import Photos
import SwiftUI

/// 개발 메뉴: 고화질본을 사진 앱에 저장한 뒤에도 메타데이터가 남는지 확인한다(D037, 설계 문서 4.4절).
///
/// `Documents/MetaProbeIn/`의 JPEG를 실제 저장 경로(`PhotoDeliveryManager.saveToPhotoLibrary`)로 사진 앱에 넣고,
/// 만들어진 사진의 원본 리소스를 `Documents/MetaProbeOut/`으로 다시 꺼낸다. 맥으로 꺼내 ExifTool로 비교한다.
/// 원본 리소스를 읽으려면 사진 읽기 권한이 필요하다(이 시험에서만 묻는다).
struct SavedPhotoProbeView: View {
    @State private var log: [String] = []
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Button("MetaProbeIn 파일 저장하고 다시 꺼내기") { run() }
                    .disabled(isRunning)
                    .accessibilityIdentifier("probe.saveRoundTrip")
            } footer: {
                Text("시험 사진은 끝나면 사진 앱과 이 앱 폴더에서 지워 주세요.")
            }
            Section("기록") {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("사진 앱 저장 시험")
    }

    private func run() {
        isRunning = true
        Task {
            defer { isRunning = false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                log.append("사진 읽기 권한 없음(\(status.rawValue))")
                return
            }
            let input = URL.documentsDirectory.appending(path: "MetaProbeIn", directoryHint: .isDirectory)
            let output = URL.documentsDirectory.appending(path: "MetaProbeOut", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let files = ((try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if files.isEmpty { log.append("MetaProbeIn에 JPEG 없음") }
            for file in files {
                log.append(await roundTrip(file, into: output))
            }
            log.append("끝")
        }
    }

    /// 저장 경로는 파일을 옮기므로 사본을 넘긴다. 저장 직후 가장 최근 사진을 원본 리소스로 꺼낸다.
    private func roundTrip(_ file: URL, into output: URL) async -> String {
        let name = file.lastPathComponent
        let copy = URL.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        do {
            try FileManager.default.copyItem(at: file, to: copy)
            try await PhotoDeliveryManager.saveToPhotoLibrary(fileURL: copy)
            let options = PHFetchOptions()
            options.fetchLimit = 1
            // creationDate는 촬영 시각이라 방금 넣은 사진이 맨 위가 아닐 수 있어, 추가된 순서로 찾는다.
            options.sortDescriptors = [NSSortDescriptor(key: "addedDate", ascending: false)]
            guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject,
                  let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo })
            else { return "\(name): 저장한 사진을 찾지 못함" }
            let destination = output.appending(path: "saved-" + name)
            try? FileManager.default.removeItem(at: destination)
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: nil)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int) ?? 0
            return "\(name) → saved-\(name) \(size)B, 사진 앱 위치 \(asset.location == nil ? "없음" : "있음")"
        } catch {
            return "\(name) 실패: \(error.localizedDescription)"
        }
    }
}
