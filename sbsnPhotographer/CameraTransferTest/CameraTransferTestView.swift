//
//  CameraTransferTestView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SwiftUI

/// 카메라 → 작가 앱 FTP 자동 전송 실증 화면.
struct CameraTransferTestView: View {
    @State private var model = CameraTransferTestModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                LabeledContent("상태", value: model.isRunning ? "수신 대기 중" : "중지됨")
                LabeledContent("촬영 티켓", value: model.ticketID)
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
                Button("촬영 모드 시작", systemImage: "camera.aperture") {
                    model.enterShootingMode()
                }
                .disabled(!model.isRunning)
            }

            Section {
                if model.addresses.isEmpty {
                    Text("IPv4 주소가 없습니다. 개인용 핫스팟을 켜 주세요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.addresses) { address in
                    LabeledContent(address.isLikelyHotspot ? "호스트 (핫스팟)" : "호스트 (\(address.name))", value: address.address)
                }
                LabeledContent("포트", value: String(CameraTransferTestModel.port))
                LabeledContent("사용자", value: CameraTransferTestModel.user)
                LabeledContent("비밀번호", value: CameraTransferTestModel.password)
            } header: {
                Text("카메라 FTP 서버 설정값")
            } footer: {
                Text("보안 프로토콜은 끄고, 패시브 모드 항목이 있으면 켜 주세요.")
            }

            Section("받은 \(model.photos.count) · 미리보기 \(model.previewUploadedCount) · 원본 \(model.originalUploadedCount)") {
                if model.failedUploadCount > 0 {
                    Button("업로드 실패 \(model.failedUploadCount)장 다시 올리기", systemImage: "arrow.clockwise.icloud") {
                        model.retryFailedUploads()
                    }
                }
                ForEach(model.photos.reversed()) { photo in
                    ReceivedPhotoRow(photo: photo)
                }
            }

            Section("FTP 로그") {
                ForEach(model.logLines.suffix(80).reversed()) { line in
                    Text(line.text)
                        .font(.caption2.monospaced())
                }
            }
        }
        .navigationTitle("카메라 전송 실증")
        .toolbar {
            ToolbarItem {
                Toggle("화면 켜두기", systemImage: "sun.max", isOn: $model.keepsScreenAwake)
            }
        }
        .task {
            model.start()
            while !Task.isCancelled {
                model.refreshAddresses()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            model.note("scenePhase: \(phase)")
            switch phase {
            case .background:
                model.suspendForBackground()
            case .active:
                model.resumeFromBackground()
            default:
                break
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.isShootingMode },
            set: { if !$0 { model.exitShootingMode() } }
        )) {
            ShootingModeView(model: model) {
                model.exitShootingMode()
            }
        }
        .onDisappear {
            // 촬영 모드 화면이 덮을 때도 이 화면의 onDisappear가 불릴 수 있으므로 그때는 서버를 멈추지 않는다.
            if !model.isShootingMode {
                model.stop()
            }
        }
    }
}

private struct ReceivedPhotoRow: View {
    let photo: CameraTransferTestModel.ReceivedPhoto

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = photo.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(photo.relativePath)
                    .font(.subheadline.monospaced())
                Text("\(Int64(photo.byteCount), format: .byteCount(style: .file)) · 전송 \(photo.transferDuration, format: .number.precision(.fractionLength(2)))초")
                    .font(.caption)
                if let latency = photo.shotToReceiveLatency {
                    Text("촬영 → 수신 \(latency, format: .number.precision(.fractionLength(1)))초")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UploadStateLabel(title: "미리보기", state: photo.preview)
                UploadStateLabel(title: "원본", state: photo.original)
            }
        }
    }
}

private struct UploadStateLabel: View {
    let title: String
    let state: CameraTransferTestModel.ReceivedPhoto.UploadState

    var body: some View {
        Group {
            switch state {
            case .waiting:
                Label("\(title) 대기", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .uploading:
                Label("\(title) 업로드 중", systemImage: "arrow.up.circle")
                    .foregroundStyle(.secondary)
            case .uploaded(let duration):
                Label("\(title) 저장 \(duration, format: .number.precision(.fractionLength(1)))초", systemImage: "checkmark.icloud")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label("\(title) 실패: \(message)", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        CameraTransferTestView()
    }
}
