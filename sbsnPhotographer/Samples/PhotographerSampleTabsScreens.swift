import SBSNUI
import SwiftUI

// 작가 앱 "내역"·"마이" 탭 예시 화면(P9~P18). 근거: 총괄 문서 `UI_WIREFRAME_PAGES.md` 2절.

// MARK: - P9 촬영 이력

struct SampleHistoryScreen: View {
    private var sections: [String] {
        PhotographerSampleData.shoots.map(\.section).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(PhotographerSampleData.shoots.filter { $0.section == section }) { shoot in
                        NavigationLink { SampleHistoryDetailScreen(shoot: shoot) } label: {
                            Text(shoot.title)
                                .font(.subheadline)
                        }
                    }
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleHistoryDetailScreen: View {
    let shoot: PhotographerSampleData.Shoot

    var body: some View {
        List {
            Section("시각표") {
                ForEach(shoot.timeline, id: \.0) { LabeledContent($0.0, value: $0.1) }
            }
            Section("사진") {
                LabeledContent("공개한 사진", value: "\(shoot.received)장")
                LabeledContent("판매", value: "\(shoot.sold)장")
                LabeledContent("고객 저장", value: "\(shoot.delivered)장")
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "촬영 상세", id: "historyDetail")
    }
}

// MARK: - P10 판매·전달 현황

struct SampleSalesScreen: View {
    @State private var isMonth = false

    var body: some View {
        List {
            Section {
                Picker("기간", selection: $isMonth) {
                    Text("이번 주").tag(false)
                    Text("이번 달").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section("요약") {
                LabeledContent("촬영", value: isMonth ? "12회" : "3회")
                LabeledContent("판매", value: isMonth ? "31장" : "9장")
                LabeledContent("판매 있는 촬영", value: isMonth ? "54%" : "67%")
            }
            Section("촬영별") {
                ForEach(PhotographerSampleData.shoots) { shoot in
                    LabeledContent("\(shoot.section) · 판매 \(shoot.sold)장", value: shoot.deliveryState)
                }
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P11 수익·정산

struct SampleSettlementScreen: View {
    var body: some View {
        List {
            Section {
                Text("예시: 정식 M2 · 작가 70%")
                    .font(.subheadline)
            }
            Section("이번 달 예상") {
                LabeledContent("촬영료 매출", value: "180,000원")
                LabeledContent("사진 매출", value: "248,000원")
                LabeledContent("작가 몫 70%", value: "299,600원")
                LabeledContent("환불 조정", value: "−5,600원")
                LabeledContent("지급 예정", value: "12월 15일")
            }
            Section("지난 지급") {
                ForEach(PhotographerSampleData.payouts) { payout in
                    NavigationLink { SamplePayoutDetailScreen(payout: payout) } label: {
                        LabeledContent(payout.month, value: payout.paidOn)
                    }
                }
            }
            Section {
                Text("첫 검증 기간(M1)에는 시급 15,000원과 정상 촬영 1건당 3,000원을 지급합니다. 정식 운영(M2)에서는 작가 70% · 회사 30%로 나누고, 월말에 확정해 다음 달 15일에 지급합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            SampleNoticeSection()
        }
    }
}

struct SamplePayoutDetailScreen: View {
    let payout: PhotographerSampleData.Payout

    var body: some View {
        List {
            Section(payout.paidOn) {
                ForEach(payout.lines, id: \.0) { line in
                    LabeledContent(line.0, value: "\(line.1.formatted())원")
                }
                LabeledContent("합계", value: "\(payout.total.formatted())원")
                    .bold()
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "\(payout.month) 명세", id: "payoutDetail")
    }
}

// MARK: - P12 품질 피드백

struct SampleFeedbackScreen: View {
    var body: some View {
        List {
            Section {
                Text("★ 4.8 · 리뷰 32")
                    .font(.headline)
            }
            Section("고객 리뷰") {
                ForEach(PhotographerSampleData.reviews) { SampleReviewRow($0) }
            }
            Section("운영팀 피드백") {
                ForEach(PhotographerSampleData.opsFeedback, id: \.0) { item in
                    LabeledContent(item.0, value: item.1)
                }
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P13 분쟁 대응

struct SampleDisputesScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink { SampleDisputeDetailScreen() } label: {
                    LabeledContent("환불 요청 · 사진 1장 초점", value: "답변 필요")
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleDisputeDetailScreen: View {
    @State private var action = PhotographerSampleData.disputeActions[0]
    @State private var reply = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section("고객 요청") {
                Text("DSC0207.JPG 초점이 맞지 않아 환불을 원합니다.")
                SamplePhoto("DSC0207.JPG")
                    .frame(height: 160)
            }
            Picker("처리 제안", selection: $action) {
                ForEach(PhotographerSampleData.disputeActions, id: \.self) { Text($0).tag($0) }
            }
            Section("답변") {
                TextEditor(text: $reply)
                    .frame(minHeight: 100)
            }
            Section {
                Button("보내기") { status = "\(action)을(를) 보냈습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "분쟁 상세", id: "disputeDetail")
    }
}

// MARK: - P14 프로필·포트폴리오

struct SamplePortfolioScreen: View {
    private struct Slot: Identifiable {
        let id: Int
    }

    @State private var intro = PhotographerSampleData.profile.intro
    @State private var years = 7
    @State private var equipment = PhotographerSampleData.equipment
    @State private var newEquipment = ""
    @State private var languages: Set<String> = ["한국어", "English"]
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 64, height: 64)
                        .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                    Text("고객에게 보일 이름은 촬영 탭에서 입력합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("소개") {
                TextEditor(text: $intro)
                    .frame(minHeight: 80)
                Stepper("경력 \(years)년", value: $years, in: 0...40)
            }
            Section("장비") {
                ForEach(equipment, id: \.self) { Text($0) }
                HStack {
                    TextField("장비 추가", text: $newEquipment)
                    Button("추가") {
                        guard !newEquipment.isEmpty else { return }
                        equipment.append(newEquipment)
                        newEquipment = ""
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section("소통 언어") {
                ForEach(PhotographerSampleData.languages, id: \.self) { language in
                    Toggle(language, isOn: Binding(
                        get: { languages.contains(language) },
                        set: { if $0 { languages.insert(language) } else { languages.remove(language) } }
                    ))
                }
            }
            Section("샘플 사진") {
                SamplePhotoGrid((0..<6).map(Slot.init)) { _ in SamplePhoto() }
                    .padding(.vertical, 4)
                Button("사진 추가") { status = "사진을 추가했습니다(예시)" }
                SampleStatus(status)
            }
            Section {
                NavigationLink("고객에게 보이는 모습") {
                    SampleProfileView(PhotographerSampleData.profile, footerLine: "고객 앱의 작가 프로필과 같은 모양입니다")
                        .sampleScreen(title: "고객에게 보이는 모습", id: "profilePreview")
                }
                .accessibilityIdentifier("sample.profilePreviewLink")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P15 등록·계약·장비

struct SampleRegistrationScreen: View {
    var body: some View {
        List {
            Section("등록") {
                LabeledContent("신원 확인", value: "완료 · 2026-11-01")
                LabeledContent("계약", value: "M1 지정 근로(예시)")
                NavigationLink("계약서 보기") { SampleDocumentView(PhotographerSampleData.contract) }
                LabeledContent("정산 계좌", value: PhotographerSampleData.maskedAccount)
            }
            Section {
                LabeledContent("Sony a7C II", value: "등록됨")
                LabeledContent("FE 35mm F1.8", value: "등록됨")
            } header: {
                Text("등록 장비")
            } footer: {
                Text("장비 일련번호는 프로필에 표시하지 않습니다. 사진 메타데이터의 일련번호는 구매한 고객에게 그대로 전달됩니다.")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P16 원본 보관·삭제

struct SampleOriginalsScreen: View {
    @State private var autoClean = "전달 끝나고 7일 뒤"
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Gauge(value: 3.2, in: 0...16) {
                    Text("이 폰의 원본")
                } currentValueLabel: {
                    Text("3.2GB")
                }
                Text("이 폰의 원본 3.2GB · 촬영 4건")
                    .font(.subheadline)
            }
            Section("촬영별") {
                ForEach(PhotographerSampleData.originals) { shoot in
                    LabeledContent(shoot.title, value: "\(shoot.size) · \(shoot.sold)")
                }
            }
            Picker("자동 정리", selection: $autoClean) {
                ForEach(["전달 끝나고 7일 뒤", "전달 끝나고 30일 뒤"], id: \.self) { Text($0).tag($0) }
            }
            Section {
                Button("구매되지 않은 원본 지우기", role: .destructive) { status = "지웠습니다(예시, 실제로 지우지 않음)" }
                SampleStatus(status)
            } footer: {
                Text("올린 사진의 메타데이터(촬영 위치, 일련번호 등)는 구매한 고객에게 그대로 전달됩니다. 빼고 싶은 항목은 편집 앱에서 내보낼 때 지워 주세요.")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P17 고객지원

struct SampleSupportScreen: View {
    @State private var type = PhotographerSampleData.supportTypes[0]
    @State private var detail = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section("문의") {
                Picker("유형", selection: $type) {
                    ForEach(PhotographerSampleData.supportTypes, id: \.self) { Text($0).tag($0) }
                }
                TextEditor(text: $detail)
                    .frame(minHeight: 80)
                Button("보내기") { status = "문의를 보냈습니다(예시)" }
                SampleStatus(status)
            }
            Section("작가용 도움말") {
                ForEach(PhotographerSampleData.supportFAQ, id: \.0) { item in
                    DisclosureGroup(item.0) {
                        Text(item.1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("문의 내역") {
                LabeledContent("11월 18일 · 카메라 연결", value: "답변 완료")
            }
            Section {
                NavigationLink("차단한 사용자") { SampleBlockedUsersView(users: PhotographerSampleData.blockedUsers) }
                    .accessibilityIdentifier("sample.blockedUsersLink")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P18 약관·정책

struct SamplePhotographerTermsScreen: View {
    var body: some View {
        List {
            Section {
                // 목록 순서: 작가 이용약관, 위치기반서비스 이용약관, 위치정보, 개인정보 처리방침, 동의 내역(계정 삭제는 마이 탭 계정 칸의 실제 기능)
                NavigationLink(PhotographerSampleData.documents[1].title) { SampleDocumentView(PhotographerSampleData.documents[1]) }
                NavigationLink(PhotographerSampleData.documents[0].title) { SampleDocumentView(PhotographerSampleData.documents[0]) }
                NavigationLink("위치정보") {
                    SampleLocationInfoView(consents: PhotographerSampleData.locationConsents, stopHints: PhotographerSampleData.locationStopHints,
                                           history: PhotographerSampleData.locationHistory, revokeAllTitle: nil) {
                        PhotographerSampleScreen(PhotographerFeatures.support)
                    }
                }
                .accessibilityIdentifier("sample.locationInfoLink")
                NavigationLink(PhotographerSampleData.documents[2].title) { SampleDocumentView(PhotographerSampleData.documents[2]) }
                NavigationLink("동의 내역") { SamplePhotographerConsentsScreen() }
            }
            SampleNoticeSection()
        }
    }
}

struct SamplePhotographerConsentsScreen: View {
    var body: some View {
        List {
            ForEach(PhotographerSampleData.consents, id: \.0) { consent in
                VStack(alignment: .leading, spacing: 2) {
                    Text(consent.0)
                    Text("\(consent.1) 동의 · \(consent.2)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "동의 내역", id: "consents")
    }
}
