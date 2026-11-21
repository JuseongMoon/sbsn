import Photos
import SBSNCore
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
            Section {
                Button("구매 시험 저장본 지우기") { deleteSavedPurchases() }
                    .disabled(isRunning)
                    .accessibilityIdentifier("probe.deleteSaved")
            } footer: {
                Text("원본 파일 이름이 사진 ID(p + 12자).jpg인 사진만 지웁니다(구매 저장본). 지운 사진은 최근 삭제된 항목으로 갑니다.")
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

    /// 시험 정리: 구매 저장본은 `<사진 ID>.jpg`로 들어간다(`TicketPhotoDownloader`). 그 이름인 사진만 골라 지운다.
    private func deleteSavedPurchases() {
        isRunning = true
        Task {
            defer { isRunning = false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized else {
                log.append("사진 전체 접근 권한 없음(\(status.rawValue))")
                return
            }
            let started = Date()
            let found = Self.assets(named: { Self.isSavedPurchase($0) })
            let identifiers = found.map(\.asset.localIdentifier)
            log.append("찾음 \(identifiers.count)장(\(String(format: "%.1f", Date().timeIntervalSince(started)))초): \(found.map(\.name).sorted().joined(separator: ", "))")
            if !identifiers.isEmpty {
                do {
                    try await Self.deleteAssets(identifiers)
                    log.append("지움 \(identifiers.count)장")
                } catch {
                    log.append("지우지 못함: \(error.localizedDescription)")
                }
            }
            log.append("끝")
        }
    }

    /// 변경 블록은 Photos가 자기 큐에서 돌리므로 MainActor 밖에서 만든다(`PhotoDeliveryManager.saveToPhotoLibrary`와 같은 이유).
    nonisolated static func deleteAssets(_ identifiers: [String]) async throws {
        try await Task.detached {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil))
            }
        }.value
    }

    /// 원본 파일 이름이 조건에 맞는 사진을 모두 찾는다. iOS 27 실기기의 Photos는 정렬 키 "addedDate"를 받지 않고
    /// 예외를 던져 앱이 죽으므로(2026-11-22 iPhone 12), 공개 키로 전체를 훑는다. 개발 메뉴 전용이라 느려도 된다.
    static func assets(named matches: @escaping (String) -> Bool) -> [(asset: PHAsset, name: String)] {
        var found: [(asset: PHAsset, name: String)] = []
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            if let name = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo })?.originalFilename, matches(name) {
                found.append((asset, name))
            }
        }
        return found
    }

    nonisolated static func isSavedPurchase(_ fileName: String) -> Bool {
        let url = URL(fileURLWithPath: fileName)
        return url.pathExtension.lowercased() == "jpg" && PhotoCuration.isValidPhotoID(url.deletingPathExtension().lastPathComponent)
    }

    /// 저장 경로는 파일을 옮기므로 사본을 넘긴다. 저장 직후 가장 최근 사진을 원본 리소스로 꺼낸다.
    private func roundTrip(_ file: URL, into output: URL) async -> String {
        let name = file.lastPathComponent
        let copy = URL.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        do {
            try FileManager.default.copyItem(at: file, to: copy)
            try await PhotoDeliveryManager.saveToPhotoLibrary(fileURL: copy)
            // 저장한 사본의 이름(UUID.jpg)이 원본 파일 이름으로 남는다. creationDate는 촬영 시각이라 맨 위가 아닐 수 있다.
            guard let asset = Self.assets(named: { $0 == copy.lastPathComponent }).first?.asset,
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
