import Photos
import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI
import UIKit

/// 사진 한 장의 상세: 큰 미리보기, 찜, 구매, 고화질 전달 상태.
///
/// 구매는 확인을 받은 뒤 기록하고 되돌릴 수 없다. 사진 앱 추가 권한은 처음 구매할 때 한 번만 묻는다.
/// 미리보기(워터마크 저화질)는 사진 앱에 저장하지 않는다.
struct PhotoDetailView: View {
    let ticket: TicketRecord
    let photoID: String
    /// 갤러리 안 순서(0부터). 파일 이름이 없을 때 "사진 n"으로 쓴다.
    let index: Int
    let workspace: GalleryWorkspace

    @Environment(CustomerSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var showsPurchaseConfirm = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?

    private var photo: PhotoRecord? {
        workspace.delivery.photos.first { $0.id == photoID }
    }

    /// 구매 기한 확인에 쓰는 최신 티켓(갤러리 리스너 값)
    private var currentTicket: TicketRecord { workspace.ticket ?? ticket }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                if let photo {
                    controls(photo)
                } else {
                    Text("사진이 목록에서 사라졌습니다")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(photo?.displayName(index: index) ?? "사진 \(index + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photo?.hasPreview) {
            if photo?.hasPreview == true {
                workspace.previews.request(photoID)
            }
        }
        .confirmationDialog("구매하면 고화질 사진이 사진 앱에 자동 저장됩니다. 취소할 수 없습니다.",
                            isPresented: $showsPurchaseConfirm, titleVisibility: .visible) {
            Button("구매", action: purchase)
            Button("취소", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = workspace.previews.images[photoID] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let failure = workspace.previews.failures[photoID] {
            ContentUnavailableView("미리보기를 불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(failure))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    private func controls(_ photo: PhotoRecord) -> some View {
        let isFavorited = workspace.favorites.isFavorited(photo)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    workspace.favorites.toggle(photo)
                } label: {
                    Label(isFavorited ? "찜 해제" : "찜", systemImage: isFavorited ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .opacity(workspace.favorites.isPending(photo) ? 0.6 : 1)
                Spacer()
                if let capturedAt = photo.capturedAt {
                    Text(LaunchTime.clock(capturedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if photo.canPurchase(on: currentTicket) {
                Button {
                    showsPurchaseConfirm = true
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView()
                        } else {
                            Label("구매", systemImage: "cart")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
                .accessibilityIdentifier("photo.purchase")
            }
            if let purchaseError {
                Text(purchaseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            deliveryStatus(photo)
            Divider()
            HStack {
                NavigationLink(value: CustomerFeatures.retouch) {
                    Label(CustomerFeatures.retouch.title, systemImage: CustomerFeatures.retouch.systemImage)
                }
                .accessibilityIdentifier("planned.retouch")
                NavigationLink(value: CustomerFeatures.shareAndPrint) {
                    Label(CustomerFeatures.shareAndPrint.title, systemImage: CustomerFeatures.shareAndPrint.systemImage)
                }
                .accessibilityIdentifier("planned.shareAndPrint")
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func deliveryStatus(_ photo: PhotoRecord) -> some View {
        if let badge = workspace.delivery.badge(for: photo) {
            Label(badge.text, systemImage: badge.symbol)
                .font(.subheadline)
                .accessibilityIdentifier("photo.delivery")
        } else if !photo.isPurchased, !currentTicket.acceptsGalleryPurchase() {
            Text("구매 기한이 지났습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        GalleryDeadlineText(ticket: currentTicket)
        switch workspace.delivery.status(of: photo) {
        case .downloadedOnly(let url):
            VStack(alignment: .leading, spacing: 8) {
                Text("사진 앱 권한이 없어 저장하지 못했습니다. 설정에서 권한을 켜거나 파일을 직접 내보낼 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ShareLink(item: url) {
                        Label("파일 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    Button("설정 열기", action: openSettings)
                        .buttonStyle(.bordered)
                    Button("다시 저장") { workspace.delivery.retry(photoID) }
                        .buttonStyle(.bordered)
                }
            }
        case .failed:
            Button("다시 시도") { workspace.delivery.retry(photoID) }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func purchase() {
        guard !isPurchasing else { return }
        guard session.isOnline else {
            purchaseError = "인터넷 연결을 확인해 주세요."
            return
        }
        isPurchasing = true
        purchaseError = nil
        Task {
            defer { isPurchasing = false }
            // 구매를 먼저 기록한다. 권한 창에 답하는 동안 구매가 멈추면 안 된다(실기기에서 확인).
            do {
                try await TicketPhotoCatalog.purchase(ticketId: ticket.id, photoId: photoID)
            } catch {
                // 기한 경계에서 늦게 도착한 요청은 서버가 거부한다(공개 + 168시간).
                purchaseError = currentTicket.acceptsGalleryPurchase()
                    ? "구매를 기록하지 못했습니다: \(error.localizedDescription)"
                    : "구매 기한이 지나 구매하지 못했습니다."
                return
            }
            // 처음 구매할 때만 사진 앱 추가 권한을 묻는다. 거부해도 구매는 유지되고 파일 내보내기로 대신한다.
            if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
                _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
        }
    }
}
