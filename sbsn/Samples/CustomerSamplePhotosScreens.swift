import SBSNUI
import SwiftUI

// 고객 앱 "내 사진" 탭 예시 화면(C10~C13). 근거: 총괄 문서 `UI_WIREFRAME_PAGES.md` 1절.

private struct FileItem: Identifiable {
    var id: String { name }
    let name: String
}

// MARK: - C10 지난 촬영(앨범)

struct SampleAlbumScreen: View {
    var body: some View {
        List {
            ForEach(CustomerSampleData.shoots) { shoot in
                Section(shoot.section) {
                    NavigationLink(shoot.title) { SampleAlbumDetailScreen(shoot: shoot) }
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleAlbumDetailScreen: View {
    let shoot: CustomerSampleData.Shoot
    @State private var status: String?

    var body: some View {
        List {
            Section {
                LabeledContent("다시 받을 수 있는 기간", value: "\(shoot.daysLeft)일 남음")
                Button("모두 다시 받기") { status = "사진 앱에 다시 저장했습니다(예시, 실제 저장 안 함)" }
                SampleStatus(status)
            }
            Section("구매한 사진") {
                SamplePhotoGrid(shoot.photos.map(FileItem.init)) { SamplePhoto($0.name) }
                    .padding(.vertical, 4)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: shoot.section, id: "albumDetail")
    }
}

// MARK: - C11 주문 내역

struct SampleOrdersScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(CustomerSampleData.orders) { order in
                    NavigationLink {
                        SampleOrderDetailScreen(order: order)
                    } label: {
                        LabeledContent(order.title, value: order.state)
                    }
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleOrderDetailScreen: View {
    let order: CustomerSampleData.Order

    var body: some View {
        List {
            Section {
                LabeledContent("주문 번호", value: order.number)
                LabeledContent("일시", value: order.date)
                LabeledContent("판매자", value: "십분스냅")
                LabeledContent("결제 수단", value: CustomerSampleData.maskedCard)
                LabeledContent("상태", value: order.state)
            }
            Section("품목") {
                ForEach(order.items, id: \.self) { Text($0) }
            }
            Section {
                NavigationLink("영수증 보기") { SampleReceiptScreen(order: order) }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "주문 상세", id: "orderDetail")
    }
}

struct SampleReceiptScreen: View {
    let order: CustomerSampleData.Order

    var body: some View {
        List {
            Section("십분스냅 영수증(예시)") {
                ForEach(order.items, id: \.self) { item in
                    LabeledContent(item, value: "\((order.amount / max(order.items.count, 1)).formatted())원")
                }
                LabeledContent("합계", value: "\(order.amount.formatted())원")
                    .bold()
                LabeledContent("결제 수단", value: CustomerSampleData.maskedCard)
                LabeledContent("일시", value: order.date)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "영수증", id: "receipt")
    }
}

// MARK: - C12 전문 보정

struct SampleRetouchScreen: View {
    var body: some View {
        List {
            Section("진행 중 요청") {
                LabeledContent("DSC0104.JPG · 2인", value: "예정 2일 안(가안)")
                ForEach(Array(CustomerSampleData.retouchSteps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: index < 1 ? "checkmark.circle.fill" : index == 1 ? "circle.dotted" : "circle")
                        .foregroundStyle(index == 1 ? .primary : .secondary)
                }
            }
            Section {
                NavigationLink("새 요청") { SampleRetouchRequestScreen() }
                    .accessibilityIdentifier("sample.retouchRequestLink")
            }
            Section("완료 예시") {
                HStack(spacing: 8) {
                    SamplePhoto("기본본(v1)")
                    SamplePhoto("전문본(v2)")
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleRetouchRequestScreen: View {
    @State private var selected: Set<String> = ["DSC0104.JPG"]
    @State private var twoPeople = false
    @State private var scopes: Set<String> = ["피부 정리"]
    @State private var memo = ""
    @State private var status: String?

    private var price: Int { selected.count * (twoPeople ? 15_000 : 10_000) }

    var body: some View {
        Form {
            Section("사진 고르기") {
                SamplePhotoGrid(CustomerSampleData.basket.map(FileItem.init)) { item in
                    Button {
                        if selected.contains(item.name) { selected.remove(item.name) } else { selected.insert(item.name) }
                    } label: {
                        SamplePhoto(item.name)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: selected.contains(item.name) ? "checkmark.circle.fill" : "circle")
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            Picker("인원", selection: $twoPeople) {
                Text("1인 10,000원").tag(false)
                Text("2인 15,000원").tag(true)
            }
            .pickerStyle(.segmented)
            Section("요청 범위") {
                ForEach(CustomerSampleData.retouchScopes, id: \.self) { scope in
                    Toggle(scope, isOn: Binding(
                        get: { scopes.contains(scope) },
                        set: { if $0 { scopes.insert(scope) } else { scopes.remove(scope) } }
                    ))
                }
            }
            Section {
                TextField("메모", text: $memo)
            } footer: {
                Text("수정 1회 포함 · 기본본은 그대로 보관합니다.")
            }
            Section {
                LabeledContent("예상 금액", value: "\(price.formatted())원")
                Button("요청하기") { status = "보정을 요청했습니다(예시, 결제 없음)" }
                    .disabled(selected.isEmpty)
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "새 보정 요청", id: "retouchRequest")
    }
}

// MARK: - C13 공유·인화

struct SampleShareScreen: View {
    enum Ratio: String, CaseIterable {
        case square = "1:1"
        case portrait = "4:5"
        case story = "9:16"
    }

    @State private var linkPhoto = "DSC0104.JPG"
    @State private var link: String?
    @State private var ratio = Ratio.portrait
    @State private var printSize = "4×6"
    @State private var quantity = 1
    @State private var address = ""
    @State private var status: String?

    private var printPrice: Int {
        let unit = ["4×6": 1_000, "5×7": 2_000, "8×10": 4_000][printSize] ?? 1_000
        return unit * quantity + 3_000
    }

    var body: some View {
        Form {
            Section("공유 링크") {
                Picker("사진", selection: $linkPhoto) {
                    ForEach(CustomerSampleData.basket, id: \.self) { Text($0).tag($0) }
                }
                Button("링크 만들기") { link = "10minsnap.com/s/XXXX(예시)" }
                if let link {
                    LabeledContent("링크", value: link)
                    Text("7일 뒤 만료")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("SNS 규격 저장") {
                Picker("비율", selection: $ratio) {
                    ForEach(Ratio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("사진 앱에 저장") { status = "\(ratio.rawValue)로 저장했습니다(예시, 실제 저장 안 함)" }
            }
            Section("인화") {
                Picker("크기", selection: $printSize) {
                    ForEach(["4×6", "5×7", "8×10"], id: \.self) { Text($0).tag($0) }
                }
                Stepper("수량 \(quantity)장", value: $quantity, in: 1...20)
                TextField("받을 곳", text: $address)
                LabeledContent("예상 금액(예시)", value: "\(printPrice.formatted())원")
                Button("주문하기") { status = "인화를 주문했습니다(예시, 결제 없음)" }
            }
            Section {
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}
