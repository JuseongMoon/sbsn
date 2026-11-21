import SBSNCore
import SBSNUI
import SwiftUI

/// "내 사진" 탭: 진행 중인 촬영으로 가는 길, 지난 촬영(갤러리, D040 ①), 아직 만들지 않은 앨범·주문·추가 서비스 메뉴.
struct MyPhotosTab: View {
    @Binding var selectedTab: CustomerTab
    @Binding var path: [String]

    @Environment(CustomerSession.self) private var session
    @Environment(GalleryStore.self) private var galleries

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("진행 중") {
                    if session.activeTicketId != nil {
                        Button("진행 중인 촬영 보기") { selectedTab = .shoot }
                            .accessibilityIdentifier("photos.activeTicket")
                    } else {
                        Text("진행 중인 촬영이 없습니다")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if galleries.galleries.isEmpty {
                        Text("끝난 촬영이 없습니다")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(galleries.galleries) { ticket in
                        NavigationLink(value: ticket.id) {
                            GalleryRow(ticket: ticket)
                        }
                        .accessibilityIdentifier("photos.gallery")
                    }
                    CustomerSampleLink(CustomerFeatures.album)
                    CustomerSampleLink(CustomerFeatures.orders)
                } header: {
                    Text("지난 촬영")
                }
                Section {
                    CustomerSampleLink(CustomerFeatures.retouch)
                    CustomerSampleLink(CustomerFeatures.shareAndPrint)
                } header: {
                    Text("추가 서비스")
                } footer: {
                    Text("구매한 사진은 받자마자 사진 앱에 저장됩니다. 구매는 공개 뒤 7일 안에 할 수 있고, 서버에 남은 고화질 사진은 30일 뒤 지워집니다.")
                }
            }
            .navigationTitle("내 사진")
            .navigationDestination(for: String.self) { ticketID in
                GalleryScreen(ticketID: ticketID)
                    .navigationTitle("지난 촬영")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// 지난 촬영 한 줄: 작가·종료 시각과 공개 상태
private struct GalleryRow: View {
    let ticket: TicketRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(ticket.photographerDisplayName.isEmpty ? "작가" : ticket.photographerDisplayName) · \(ticket.endedAt?.formatted(.dateTime.month().day().hour().minute()) ?? "")")
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        guard let closesAt = ticket.galleryPurchaseClosesAt else { return "작가가 사진을 고르는 중" }
        if closesAt < Date() { return "사진 \(ticket.galleryPhotoIds.count)장 · 구매 기한 지남" }
        return "사진 \(ticket.galleryPhotoIds.count)장 · 구매 기한 \(closesAt.formatted(.dateTime.month().day().hour().minute()))"
    }
}
