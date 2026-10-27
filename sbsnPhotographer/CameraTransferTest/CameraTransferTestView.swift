//
//  CameraTransferTestView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SwiftUI

/// 촬영 중 화면: 카메라 FTP 설정값, 받은 사진과 업로드 상태. 측정 항목(전송 방식·처리량·로그)은 `showsMeasurements`일 때만 보인다.
/// 모델은 `PhotographerSession`이 소유한다. 이 화면을 닫아도 수신과 업로드는 계속된다.
struct CameraTransferTestView: View {
    @Bindable var model: CameraTransferTestModel
    var showsMeasurements = false

    var body: some View {
        List {
            Section {
                LabeledContent("상태", value: model.isRunning ? "수신 대기 중" : "중지됨")
                if showsMeasurements {
                    LabeledContent("촬영 티켓", value: model.ticketID)
                }
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

            if showsMeasurements {
            Section {
                Stepper("미리 올리기 \(model.prefetchMinutes)분", value: $model.prefetchMinutes, in: 1...240)
                LabeledContent("미리 올리기") {
                    if let deadline = model.prefetchDeadline {
                        Text("\(deadline, style: .time)까지")
                    } else {
                        Text("첫 사진을 받으면 시작")
                    }
                }
                Toggle("구매 원본을 셀룰러로도 올리기", isOn: $model.uploadsOriginalsOnCellular)
                LabeledContent("인터넷", value: model.isOnExpensiveNetwork ? "셀룰러(원본 보류)" : "와이파이")
                LabeledContent("구매 알림", value: pushStatus)
            } header: {
                Text("전달 순서")
            } footer: {
                Text("구매 고화질본 → 찜 고화질본 → 구매 원본 → 나머지 고화질본 순서로 올립니다. 마지막 사진을 받고 정한 시간이 지나면 찜·구매하지 않은 사진은 올리지 않습니다. 앱이 백그라운드에 있을 때 들어온 구매는 구매 알림으로 앱을 깨워 올립니다.")
            }

            Section {
                Picker("전송 방식", selection: $model.uploadMethod) {
                    ForEach(CameraTransferTestModel.UploadMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                Stepper("큰 파일 동시 업로드 \(model.largeUploadConcurrency)개", value: $model.largeUploadConcurrency, in: 1...4)
                LabeledContent("큰 파일 처리량") {
                    if let throughput = model.largeUploadThroughput {
                        Text("\(throughput / 1_000_000, format: .number.precision(.fractionLength(2))) MB/s · \(throughput * 8 / 1_000_000, format: .number.precision(.fractionLength(1))) Mbps")
                            .monospacedDigit()
                    } else {
                        Text("-")
                    }
                }
            } header: {
                Text("업로드 측정")
            } footer: {
                Text("자동: 화면에 있을 때 putData, 백그라운드에서 시작하는 업로드는 putFile. 방식과 관계없이 백그라운드에서 시작하는 구매 고화질본은 putData로 보냅니다. 바꾼 값은 다음에 시작하는 업로드부터 적용됩니다. 처리량은 고화질본·원본을 올리고 있던 시간만으로 계산합니다.")
            }
            }

            Section("받은 \(model.photos.count) · 미리보기 \(model.previewUploadedCount) · 고화질 \(model.fullResolutionUploadedCount) · 원본 \(model.originalUploadedCount)") {
                if model.failedUploadCount > 0 {
                    Button("업로드 실패 \(model.failedUploadCount)장 다시 올리기", systemImage: "arrow.clockwise.icloud") {
                        model.retryFailedUploads()
                    }
                }
                ForEach(model.photos.reversed()) { photo in
                    ReceivedPhotoRow(photo: photo)
                }
            }

            if showsMeasurements {
                Section("FTP 로그") {
                    ForEach(model.logLines.suffix(80).reversed()) { line in
                        Text(line.text)
                            .font(.caption2.monospaced())
                    }
                }
            }
        }
        .navigationTitle(showsMeasurements ? "카메라 전송 측정" : "촬영")
        .toolbar {
            ToolbarItem {
                Toggle("화면 켜두기", systemImage: "sun.max", isOn: $model.keepsScreenAwake)
            }
        }
        .task {
            while !Task.isCancelled {
                model.refreshAddresses()
                try? await Task.sleep(for: .seconds(3))
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
    }

    private var pushStatus: String {
        let session = PhotographerSession.shared
        let registration = switch session.registration {
        case .pending: "등록 중"
        case .registered: "등록됨"
        case .failed(let message): "등록 실패: \(message)"
        }
        return session.isAlertAuthorized == false ? "\(registration) · 배너 꺼짐" : registration
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
                HStack(spacing: 6) {
                    Text(photo.relativePath)
                        .font(.subheadline.monospaced())
                    if photo.isPurchased {
                        Label("구매", systemImage: "cart.fill")
                            .foregroundStyle(.orange)
                    } else if photo.isFavorited {
                        Label("찜", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }
                .font(.caption.bold())
                Text("\(Int64(photo.byteCount), format: .byteCount(style: .file)) · 전송 \(photo.transferDuration, format: .number.precision(.fractionLength(2)))초")
                    .font(.caption)
                if let latency = photo.shotToReceiveLatency {
                    Text("촬영 → 수신 \(latency, format: .number.precision(.fractionLength(1)))초")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UploadStateLabel(title: "미리보기", state: photo.preview)
                UploadStateLabel(title: "고화질", state: photo.fullResolution)
                UploadStateLabel(title: "원본", state: photo.original, waitingText: photo.isPurchased ? nil : "원본 구매 시 올림")
            }
        }
    }
}

private struct UploadStateLabel: View {
    let title: String
    let state: CameraTransferTestModel.ReceivedPhoto.UploadState
    var waitingText: String?

    var body: some View {
        Group {
            switch state {
            case .waiting:
                Label(waitingText ?? "\(title) 대기", systemImage: "clock")
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
        CameraTransferTestView(model: CameraTransferTestModel(ticketID: "preview", customerUID: "preview"), showsMeasurements: true)
    }
}
