import PhotosUI
import SBSNBackend
import SBSNCore
import SwiftUI
import UniformTypeIdentifiers

/// 갤러리 화면 하나: 공개 전이면 고르기·공개(`PhotoSelectionView`), 공개 뒤면 찜·구매·전달 현황(`PublishedGalleryView`).
struct GalleryRouteView: View {
    let ticketID: String
    @Environment(PhotographerSession.self) private var session

    var body: some View {
        if let model = session.galleries[ticketID] {
            PhotoSelectionView(model: model)
                .onAppear { session.focusedGalleryID = ticketID }
                .onDisappear { if session.focusedGalleryID == ticketID { session.focusedGalleryID = nil } }
        } else {
            PublishedGalleryView(ticketID: ticketID)
        }
    }
}

/// 사진 고르기·공개(P8 "사진 검수·공개"의 실제화, 설계 문서 2.1~2.5절).
///
/// 촬영이 끝나면 작가가 카메라 사진을 폰으로 옮기고(소니 앱·카드 리더·라이트룸) 5~8장을 고른다.
/// 고르는 즉시 검사·렌더·업로드가 시작되고, 다 올라가면 한 번 공개한다(올리는 중이면 공개 예약).
struct PhotoSelectionView: View {
    let model: CuratedDeliveryModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var isImporting = false
    @State private var confirmsPublish = false
    @State private var editMode = EditMode.inactive

    var body: some View {
        List {
            header
            if model.canEditSelection {
                addSection
            }
            if !model.notices.isEmpty {
                Section {
                    ForEach(Array(model.notices.enumerated()), id: \.offset) { _, notice in
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button("확인") { model.dismissNotices() }
                }
            }
            photosSection
            publishSection
        }
        .accessibilityIdentifier("gallery.selection")
        .environment(\.editMode, $editMode)
        .navigationTitle("사진 고르기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canEditSelection, model.photos.count > 1 {
                EditButton()
            }
        }
        .onChange(of: pickerItems) { _, items in importPicked(items) }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.jpeg, .heic, .heif], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls.prefix(model.remainingSlots) {
                guard let picked = try? PickedPhotoFile.fromFileImporter(url) else { continue }
                model.add(fileAt: picked.url, fileName: picked.fileName, assetIdentifier: nil)
                try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
            }
        }
        .confirmationDialog("\(model.photos.count)장을 고객에게 공개할까요?", isPresented: $confirmsPublish, titleVisibility: .visible) {
            Button(model.allUploaded ? "공개" : "다 올라가면 공개") { model.requestPublish() }
        } message: {
            Text("공개한 뒤에는 사진을 더하거나 빼거나 순서를 바꿀 수 없습니다.")
        }
    }

    // MARK: - 머리

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                if let start = model.shootStartedAt, let end = model.ticket.endedAt {
                    Text("촬영 \(LaunchTime.clock(start))~\(LaunchTime.clock(end))")
                        .font(.headline)
                    Text("종료 \(end, style: .relative) 지남")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("끝난 촬영").font(.headline)
                }
            }
        } footer: {
            Text("① 카메라 사진을 폰으로 옮기세요(소니 앱·카드 리더·라이트룸). ② 고객에게 보일 사진 \(PhotoCuration.publishableCount.lowerBound)~\(PhotoCuration.publishableCount.upperBound)장을 고르세요(목표 \(PhotoCuration.targetCount)장).")
        }
    }

    private var addSection: some View {
        Section {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, model.remainingSlots), selectionBehavior: .ordered,
                         matching: .all(of: [.images, .not(.screenshots)]), preferredItemEncoding: .current, photoLibrary: .shared()) {
                Label("사진 앱에서 추가", systemImage: "photo.on.rectangle")
            }
            .disabled(model.remainingSlots == 0 || isImporting)
            .accessibilityIdentifier("gallery.addFromPhotos")
            Button("파일에서 추가", systemImage: "folder") { showsFileImporter = true }
                .disabled(model.remainingSlots == 0 || isImporting)
                .accessibilityIdentifier("gallery.addFromFiles")
            #if DEBUG
            Button("시험 사진 가져오기(Documents/TestPhotos)", systemImage: "hammer") { importTestPhotos() }
                .disabled(model.remainingSlots == 0)
                .accessibilityIdentifier("gallery.addTestPhotos")
            #endif
            if isImporting {
                ProgressView("가져오는 중…")
            }
        } footer: {
            Text("JPEG·HEIC만 받습니다. 긴 변 4,000px 미만과 RAW는 받지 않습니다.")
        }
    }

    // MARK: - 사진

    private var photosSection: some View {
        Section {
            if model.photos.isEmpty {
                Text("아직 고른 사진이 없습니다.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                PhotoRow(index: index, photo: photo, isPublished: model.isPublished) {
                    model.retryFailedUploads()
                }
                .deleteDisabled(!model.canEditSelection)
                .moveDisabled(!model.canEditSelection)
            }
            .onDelete { offsets in
                for index in offsets { model.remove(model.photos[index].id) }
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("고른 사진 \(model.photos.count)장 · 올라감 \(model.uploadedCount)장")
        } footer: {
            if model.canEditSelection, model.photos.count > 1 {
                Text("고객에게 이 순서대로 보입니다. 오른쪽 위 \"편집\"으로 순서를 바꾸거나 뺄 수 있습니다.")
            }
        }
    }

    // MARK: - 공개

    @ViewBuilder
    private var publishSection: some View {
        Section {
            Label("올린 사진의 메타데이터(촬영 위치, 카메라·렌즈 일련번호, 소유자 이름, 저작권 표시 등)는 구매한 고객에게 그대로 전달됩니다. 빼고 싶은 항목은 편집 앱에서 내보낼 때 지워 주세요.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("gallery.metadataNotice")
            if model.locationRemovedCount > 0 {
                // I008(Android 먼저, 같은 문구). 원인(선택 창 옵션인지, 편집 앱이 지웠는지)은 파일로 가릴 수 없어 단정하지 않는다.
                Label("위치 정보가 지워진 채 들어온 사진 \(model.locationRemovedCount)장: 고객 사진에 촬영 위치가 남지 않습니다(나머지 정보는 그대로).",
                      systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("gallery.locationRemoved")
            }
            switch model.publishState {
            case .draft, .failed:
                if case .failed(let message) = model.publishState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    confirmsPublish = true
                } label: {
                    Text(model.allUploaded ? "고객에게 공개(\(model.photos.count)장)" : "다 올라가면 공개(\(model.uploadedCount)/\(model.photos.count))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.countProblem != nil)
                .accessibilityIdentifier("gallery.publish")
                if let problem = model.countProblem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .reserved:
                Label("다 올라가면 바로 공개합니다(\(model.uploadedCount)/\(model.photos.count))", systemImage: "clock.arrow.circlepath")
                    .accessibilityIdentifier("gallery.reserved")
                Button("공개 예약 취소") { model.cancelReservation() }
            case .publishing:
                ProgressView("공개하는 중…")
            case .published(let date):
                Label("공개했습니다\(date.map { " · \(LaunchTime.clock($0))" } ?? "")", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("gallery.published")
            }
            if model.hasUnfinishedUploads {
                Text(uploadProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var uploadProgressText: String {
        var text = "고화질 \(model.photos.filter(\.fullres.isDone).count)/\(model.photos.count)"
        if let seconds = model.estimatedSecondsLeft {
            text += " · 약 \(max(1, Int((seconds / 60).rounded(.up))))분 남음"
        }
        if !model.isNetworkAvailable {
            text += " · 인터넷 연결을 기다리는 중"
        }
        return text
    }

    // MARK: - 가져오기

    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            for item in items {
                do {
                    if let picked = try await item.loadTransferable(type: PickedPhotoFile.self) {
                        model.add(fileAt: picked.url, fileName: picked.fileName, assetIdentifier: item.itemIdentifier)
                        try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
                    }
                } catch {
                    model.appendLog("picker load failed: \(error)")
                }
            }
            pickerItems = []
            isImporting = false
        }
    }

    #if DEBUG
    /// 자동 시험용: 앱 `Documents/TestPhotos/`의 JPEG·HEIC를 고른 것처럼 넣는다(선택기는 다른 프로세스라 UI 테스트로 누르기 어렵다).
    private func importTestPhotos() {
        let folder = URL.documentsDirectory.appending(path: "TestPhotos", directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "heic", "heif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files.prefix(model.remainingSlots) {
            guard let picked = try? PickedPhotoFile(copying: file) else { continue }
            model.add(fileAt: picked.url, fileName: picked.fileName, assetIdentifier: nil)
            try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent())
        }
    }
    #endif
}

/// 고른 사진 한 줄: 순서, 썸네일, 이름, 업로드 상태(실패면 눌러서 다시), 경고, 공개 뒤 찜·구매·전달
private struct PhotoRow: View {
    let index: Int
    let photo: CuratedDeliveryModel.Photo
    let isPublished: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .frame(width: 22)
            Group {
                if let thumbnail = photo.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.displayName(index: index))
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(photo.width)×\(photo.height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let error = photo.renderError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if photo.isOutsideShootWindow {
                    Text("이 촬영 시간대 밖에서 찍은 사진입니다").font(.caption).foregroundStyle(.orange)
                }
                if isPublished, let record = photo.record {
                    Text(recordText(record)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusIcon
        }
        .accessibilityIdentifier("gallery.photo.\(index)")
    }

    @ViewBuilder
    private var statusIcon: some View {
        if photo.isUploaded {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if photo.preview.isFailed || photo.fullres.isFailed {
            Button(action: onRetry) {
                Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("다시 올리기")
        } else if photo.renderError != nil {
            Image(systemName: "xmark.octagon").foregroundStyle(.red)
        } else {
            ProgressView()
        }
    }

    private func recordText(_ record: PhotoRecord) -> String {
        var parts: [String] = []
        if record.isFavorited { parts.append("찜") }
        if record.isPurchased { parts.append(record.isDelivered ? "구매·전달 완료" : "구매") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// 공개한 촬영의 현황(읽기 전용). 로컬 사본은 공개 뒤 지웠으므로 서버의 미리보기와 사진 문서로 보여 준다.
struct PublishedGalleryView: View {
    let ticketID: String
    @Environment(PhotographerSession.self) private var session
    @State private var ticket: TicketRecord?
    @State private var records: [String: PhotoRecord] = [:]
    @State private var previews: [String: UIImage] = [:]
    @State private var loadError: String?

    var body: some View {
        List {
            if let ticket, let publishedAt = ticket.galleryPublishedAt, let closesAt = ticket.galleryPurchaseClosesAt {
                Section {
                    LabeledContent("공개", value: LaunchTime.dayClock(publishedAt))
                    LabeledContent("구매 기한", value: LaunchTime.dayClock(closesAt))
                }
                Section("사진 \(ticket.galleryPhotoIds.count)장") {
                    ForEach(Array(ticket.galleryPhotoIds.enumerated()), id: \.element) { index, photoID in
                        let record = records[photoID] ?? PhotoRecord(id: photoID)
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).frame(width: 22)
                            Group {
                                if let image = previews[photoID] {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(record.displayName(index: index)).font(.subheadline).lineLimit(1)
                                Text(status(record)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("published.photo.\(index)")
                    }
                }
            } else if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("공개한 촬영")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ticketID) { await listen() }
    }

    private func status(_ record: PhotoRecord) -> String {
        var parts: [String] = []
        if record.isFavorited { parts.append("찜") }
        if record.isPurchased { parts.append(record.isDelivered ? "구매 · 사진 앱 저장됨" : "구매") }
        return parts.isEmpty ? "아직 없음" : parts.joined(separator: " · ")
    }

    private func listen() async {
        do {
            guard let fetched = try await TicketService.fetchTicket(ticketID) else {
                loadError = "촬영 정보를 찾을 수 없습니다."
                return
            }
            ticket = fetched
            if let publishedAt = fetched.galleryPublishedAt {
                session.applyServerPublishedAt(publishedAt, for: ticketID)
            }
            let downloader = TicketPhotoDownloader(ticketID: ticketID)
            for photoID in fetched.galleryPhotoIds {
                if let data = try? await downloader.preview(photoId: photoID) {
                    previews[photoID] = UIImage(data: data)
                }
            }
            let uploader = TicketPhotoUploader(ticketID: ticketID, customerUID: fetched.customerUid)
            for try await update in uploader.photoRecords() {
                records = update
            }
        } catch {
            loadError = "불러오지 못했습니다: \(error.localizedDescription)"
        }
    }
}
