import SBSNUI
import SwiftUI

// 고객 앱 "마이" 탭 예시 화면(C14~C19). 근거: 총괄 문서 `UI_WIREFRAME_PAGES.md` 1절, 위치정보 화면은 정책 문서 02 5절.

// MARK: - C14 프로필·언어

struct SampleProfileSettingsScreen: View {
    @State private var name = "고객"
    @State private var language = "한국어"
    @State private var notificationLanguage = "한국어"
    @State private var status: String?

    var body: some View {
        Form {
            TextField("표시 이름", text: $name)
            Picker("사용 언어", selection: $language) {
                ForEach(["한국어", "English"], id: \.self) { Text($0).tag($0) }
            }
            Picker("알림 언어", selection: $notificationLanguage) {
                ForEach(["한국어", "English"], id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("나이", value: "만 14세 이상 확인됨(예시)")
            Section {
                Button("저장") { status = "저장했습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C15 계정 연결

struct SampleAccountLinkScreen: View {
    @State private var status: String?

    var body: some View {
        List {
            Section("현재 상태") {
                Label("익명 계정 · 이 기기에만 연결", systemImage: "person.crop.circle.badge.questionmark")
            }
            Section {
                Text("계정을 연결하면 기기를 바꿔도 지난 촬영과 구매한 사진을 이어서 볼 수 있습니다.")
                Button {
                    status = "예시 화면에서는 로그인하지 않습니다"
                } label: {
                    Label("Apple로 계속하기", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C16 도움말

struct SampleHelpScreen: View {
    @State private var query = ""

    private var groups: [CustomerSampleData.FAQGroup] {
        guard !query.isEmpty else { return CustomerSampleData.faq }
        return CustomerSampleData.faq.compactMap { group in
            let items = group.items.filter { $0.question.contains(query) || $0.answer.contains(query) }
            return items.isEmpty ? nil : CustomerSampleData.FAQGroup(title: group.title, items: items)
        }
    }

    var body: some View {
        List {
            Section {
                TextField("검색", text: $query)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.question) { item in
                        DisclosureGroup(item.question) {
                            Text(item.answer)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C17 문의·신고

struct SampleInquiryScreen: View {
    @State private var isReport = false
    @State private var type = CustomerSampleData.inquiryTypes[0]
    @State private var shoot = CustomerSampleData.shoots[0].title
    @State private var target = CustomerSampleData.reportTargets[0]
    @State private var reason = SampleReportReasons.all[0]
    @State private var detail = ""
    @State private var status: String?

    var body: some View {
        Form {
            Picker("종류", selection: $isReport) {
                Text("문의").tag(false)
                Text("신고").tag(true)
            }
            .pickerStyle(.segmented)
            if isReport {
                Picker("대상", selection: $target) {
                    ForEach(CustomerSampleData.reportTargets, id: \.self) { Text($0).tag($0) }
                }
                Picker("사유", selection: $reason) {
                    ForEach(SampleReportReasons.all, id: \.self) { Text($0).tag($0) }
                }
            } else {
                Picker("유형", selection: $type) {
                    ForEach(CustomerSampleData.inquiryTypes, id: \.self) { Text($0).tag($0) }
                }
                Picker("관련 촬영", selection: $shoot) {
                    ForEach(CustomerSampleData.shoots) { Text($0.title).tag($0.title) }
                }
            }
            Section("내용") {
                TextEditor(text: $detail)
                    .frame(minHeight: 100)
                if !isReport {
                    Button("사진 첨부") { status = "사진을 첨부했습니다(예시)" }
                }
            }
            Section {
                Button("보내기") { status = isReport ? "신고를 보냈습니다(예시)" : "문의를 보냈습니다(예시)" }
                SampleStatus(status)
            }
            Section("내 문의 내역") {
                ForEach(CustomerSampleData.inquiries) { inquiry in
                    NavigationLink {
                        SampleInquiryDetailScreen(inquiry: inquiry)
                    } label: {
                        LabeledContent(inquiry.title, value: inquiry.state)
                    }
                }
            }
            Section {
                NavigationLink("차단한 사용자") { SampleBlockedUsersView(users: CustomerSampleData.blockedUsers) }
                    .accessibilityIdentifier("sample.blockedUsersLink")
            }
            SampleNoticeSection()
        }
    }
}

struct SampleInquiryDetailScreen: View {
    let inquiry: CustomerSampleData.Inquiry

    var body: some View {
        List {
            Section("질문") {
                Text(inquiry.question)
            }
            Section("답변") {
                Text(inquiry.answer ?? "아직 답변이 없습니다. 보통 하루 안에 답합니다.")
                    .foregroundStyle(inquiry.answer == nil ? .secondary : .primary)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: inquiry.title, id: "inquiryDetail")
    }
}

// MARK: - C18 환불·분쟁 요청

struct SampleRefundScreen: View {
    private struct FileItem: Identifiable {
        var id: String { name }
        let name: String
    }

    @State private var shoot = CustomerSampleData.shoots[0].title
    @State private var reason = CustomerSampleData.refundReasons[0]
    @State private var selected: Set<String> = []
    @State private var resolution = "환불"
    @State private var detail = ""
    @State private var status: String?

    var body: some View {
        Form {
            Picker("대상 촬영", selection: $shoot) {
                ForEach(CustomerSampleData.shoots) { Text($0.title).tag($0.title) }
            }
            Picker("사유", selection: $reason) {
                ForEach(CustomerSampleData.refundReasons, id: \.self) { Text($0).tag($0) }
            }
            Section("대상 사진") {
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
            Picker("원하는 처리", selection: $resolution) {
                ForEach(["환불", "재촬영", "24시간 안 복구"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Section("설명") {
                TextEditor(text: $detail)
                    .frame(minHeight: 80)
            }
            Section {
                Button("요청하기") { status = "\(resolution) 요청을 보냈습니다(예시)" }
                SampleStatus(status)
            }
            Section("정책 요약(가안)") {
                ForEach(CustomerSampleData.refundPolicy, id: \.self) { Text($0) }
            }
            Section("요청 내역") {
                LabeledContent("11월 9일 · 사진 1장 초점", value: "환불 완료")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C19 약관·정책

struct SampleTermsScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(CustomerSampleData.documents) { document in
                    NavigationLink(document.title) { SampleDocumentView(document) }
                }
            }
            Section {
                NavigationLink("위치정보") {
                    SampleLocationInfoView(consents: CustomerSampleData.locationConsents, stopHints: [],
                                           history: CustomerSampleData.locationHistory, revokeAllTitle: "위치정보 동의 전부 철회") {
                        CustomerSampleScreen(CustomerFeatures.inquiry)
                    }
                }
                .accessibilityIdentifier("sample.locationInfoLink")
                NavigationLink("동의 내역") { SampleConsentHistoryScreen() }
                NavigationLink("사진·계정 삭제") { SampleDeletionScreen() }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleConsentHistoryScreen: View {
    var body: some View {
        List {
            ForEach(CustomerSampleData.consents) { consent in
                VStack(alignment: .leading, spacing: 2) {
                    Text(consent.item)
                    Text("\(consent.date) 동의 · \(consent.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "동의 내역", id: "consents")
    }
}

struct SampleDeletionScreen: View {
    @State private var status: String?

    var body: some View {
        List {
            Section("지워지는 것") {
                Text("익명 계정과 촬영·주문 기록")
                Text("서버에 남은 구매 사진(사진 앱에 저장한 사진은 그대로 남습니다)")
                Text("위치 제공 기록은 법이 정한 기간이 지나면 지웁니다")
            }
            Section {
                Button("삭제 요청", role: .destructive) { status = "삭제를 요청했습니다(예시, 실제로 지우지 않음)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "사진·계정 삭제", id: "deletion")
    }
}
