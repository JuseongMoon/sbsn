import SBSNUI
import SwiftUI

/// "내 사진" 탭: 진행 중인 촬영으로 가는 길과, 아직 만들지 않은 앨범·주문·추가 서비스 메뉴.
struct MyPhotosTab: View {
    @Binding var selectedTab: CustomerTab

    @Environment(CustomerSession.self) private var session

    var body: some View {
        NavigationStack {
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
                Section("지난 촬영") {
                    PlannedFeatureLink(CustomerFeatures.album)
                    PlannedFeatureLink(CustomerFeatures.orders)
                }
                Section {
                    PlannedFeatureLink(CustomerFeatures.retouch)
                    PlannedFeatureLink(CustomerFeatures.shareAndPrint)
                } header: {
                    Text("추가 서비스")
                } footer: {
                    Text("구매한 사진은 받자마자 사진 앱에 저장됩니다. 서버에 남은 고화질 사진은 30일 뒤 지워집니다.")
                }
            }
            .navigationTitle("내 사진")
        }
    }
}
