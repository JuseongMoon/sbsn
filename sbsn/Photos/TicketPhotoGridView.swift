import SBSNBackend
import SBSNCore
import SwiftUI

/// 촬영 중·촬영 뒤의 사진 그리드. 미리보기는 화면에 보이는 셀부터 받고, 셀을 누르면 상세 화면으로 간다.
struct TicketPhotoGridView: View {
    let ticket: TicketRecord
    let workspace: TicketWorkspace

    /// 목록은 전달 관리자가 티켓 동안 계속 듣는다. 이 화면의 task는 상세로 들어가면 취소되므로 여기서 듣지 않는다.
    private var photos: [PhotoRecord] { workspace.delivery.photos }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                if photos.isEmpty {
                    ContentUnavailableView(
                        "아직 사진이 없습니다",
                        systemImage: "photo.on.rectangle",
                        description: Text(ticket.phase == .ended ? "올라온 사진이 없습니다." : "작가가 찍은 사진이 올라오면 여기에 보입니다.")
                    )
                }
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink(value: photo.fileName) {
                            PhotoGridCell(photo: photo, workspace: workspace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photo.cell.\(photo.fileName)")
                    }
                }
            }
        }
        .navigationDestination(for: String.self) { fileName in
            PhotoDetailView(ticket: ticket, fileName: fileName, photos: photos, workspace: workspace)
        }
        .task { workspace.delivery.startListening() }
        .task { await workspace.delivery.watchForMissingDocuments() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ticket.phase == .ended {
                Label("촬영이 끝났습니다. 준비된 사진만 구매할 수 있습니다", systemImage: "checkmark.seal")
            } else {
                Label("촬영 중 · 사진 \(photos.count)장", systemImage: "camera")
            }
            if let listenError = workspace.delivery.listenError {
                HStack {
                    Text(listenError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("다시 시도") { workspace.delivery.startListening() }
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
    let workspace: TicketWorkspace

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbnail }
            .overlay(alignment: .bottom) { badges }
            .clipped()
            // 미리보기가 아직 안 올라온 사진은 요청하지 않는다(404). 올라오면 id가 바뀌어 다시 요청한다.
            .task(id: photo.hasPreview) {
                if photo.hasPreview {
                    workspace.previews.request(photo.fileName)
                }
            }
            .onDisappear { workspace.previews.cancelRequest(photo.fileName) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = workspace.previews.images[photo.fileName] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if workspace.previews.failures[photo.fileName] != nil {
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
