import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 공개된 갤러리의 사진 그리드(작가가 정한 순서). 미리보기는 화면에 보이는 셀부터 받고, 셀을 누르면 상세 화면으로 간다.
struct TicketPhotoGridView: View {
    let ticket: TicketRecord
    let workspace: GalleryWorkspace

    /// 목록은 전달 관리자가 갤러리가 살아 있는 동안 계속 듣는다. 이 화면의 task는 상세로 들어가면 취소되므로 여기서 듣지 않는다.
    private var photos: [PhotoRecord] { workspace.delivery.photos }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                plannedTools
                if photos.isEmpty {
                    ProgressView("사진을 불러오는 중…")
                        .padding(.top, 40)
                }
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        NavigationLink(value: GalleryPhotoRoute(ticketID: ticket.id, photoID: photo.id, index: index)) {
                            PhotoGridCell(photo: photo, workspace: workspace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photo.cell.\(index)")
                    }
                }
            }
        }
        .navigationDestination(for: GalleryPhotoRoute.self) { route in
            PhotoDetailView(ticket: ticket, photoID: route.photoID, index: route.index, workspace: workspace)
        }
        .navigationDestination(for: PlannedFeature.self) { CustomerSampleScreen($0) }
        .task { workspace.delivery.startListening(photoIds: ticket.galleryPhotoIds) }
        .task { await workspace.delivery.watchForStalled() }
    }

    /// 아직 만들지 않은 정렬·바구니(빈 페이지)
    private var plannedTools: some View {
        HStack {
            NavigationLink(value: CustomerFeatures.recommendation) {
                Label(CustomerFeatures.recommendation.title, systemImage: CustomerFeatures.recommendation.systemImage)
            }
            .accessibilityIdentifier("planned.recommendation")
            NavigationLink(value: CustomerFeatures.basket) {
                Label(CustomerFeatures.basket.title, systemImage: CustomerFeatures.basket.systemImage)
            }
            .accessibilityIdentifier("planned.basket")
            Spacer()
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .padding(.horizontal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("사진 \(ticket.galleryPhotoIds.count)장", systemImage: "photo.stack")
                .font(.headline)
            GalleryDeadlineText(ticket: ticket)
            Text("산 사진은 사진 앱에 바로 저장됩니다. 서버의 고화질 사진은 30일 뒤 지워집니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let listenError = workspace.delivery.listenError {
                HStack {
                    Text(listenError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("다시 시도") { workspace.delivery.startListening(photoIds: ticket.galleryPhotoIds) }
                        .font(.caption)
                }
            }
            if let message = workspace.favorites.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

}

/// 그리드 한 칸: 정사각형 미리보기, 찜 하트, 구매·전달 상태 배지.
struct PhotoGridCell: View {
    let photo: PhotoRecord
    let workspace: GalleryWorkspace

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbnail }
            .overlay(alignment: .bottom) { badges }
            .clipped()
            // 미리보기가 아직 안 올라온 사진은 요청하지 않는다(404). 올라오면 id가 바뀌어 다시 요청한다.
            .task(id: photo.hasPreview) {
                if photo.hasPreview {
                    workspace.previews.request(photo.id)
                }
            }
            .onDisappear { workspace.previews.cancelRequest(photo.id) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = workspace.previews.images[photo.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if workspace.previews.failures[photo.id] != nil {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else if photo.hasPreview {
            ProgressView()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private var badges: some View {
        let isFavorited = workspace.favorites.isFavorited(photo)
        return HStack(spacing: 4) {
            Button {
                workspace.favorites.toggle(photo)
            } label: {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorited ? Color.red : Color.white)
                    .opacity(workspace.favorites.isPending(photo) ? 0.6 : 1)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            Spacer()
            if let badge = workspace.delivery.badge(for: photo) {
                Image(systemName: badge.symbol)
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .font(.callout)
        .shadow(radius: 2)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
    }
}

/// 갤러리 안 사진 한 장으로 가는 경로
struct GalleryPhotoRoute: Hashable {
    let ticketID: String
    let photoID: String
    let index: Int
}

/// 구매 기한 표시. 하루 남으면 강조하고, 지나면 "기한이 지났습니다"(서버 규칙이 공개 + 168시간을 강제한다).
struct GalleryDeadlineText: View {
    let ticket: TicketRecord

    var body: some View {
        if let closesAt = ticket.galleryPurchaseClosesAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let left = closesAt.timeIntervalSince(context.date)
                if left <= 0 {
                    Label("구매 기한이 지났습니다(\(closesAt.formatted(.dateTime.month().day().hour().minute())))", systemImage: "clock.badge.xmark")
                        .foregroundStyle(.secondary)
                } else {
                    Label("구매 기한 \(closesAt.formatted(.dateTime.month().day().hour().minute()))까지", systemImage: "clock")
                        .foregroundStyle(left < 86_400 ? Color.orange : Color.primary)
                        .fontWeight(left < 86_400 ? .semibold : .regular)
                }
            }
            .font(.subheadline)
            .accessibilityIdentifier("gallery.deadline")
        }
    }
}
