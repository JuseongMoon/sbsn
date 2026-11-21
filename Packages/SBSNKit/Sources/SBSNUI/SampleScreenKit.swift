import SwiftUI

// 예시 화면 공통 요소(D032). 두 앱의 예시 화면이 같이 쓴다. 서버에 쓰지 않고 앱 밖으로 나가지 않는다:
// 버튼은 화면 안 상태 줄(`SampleStatus`)로만 반응한다.

/// 예시 화면 맨 아래 표시 줄.
public struct SampleNotice: View {
    public init() {}

    public var body: some View {
        Text("예시 화면 · 실제 데이터와 연결되지 않았습니다")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("sample.notice")
    }
}

/// `List`·`Form` 맨 끝에 두는 예시 표시 섹션.
public struct SampleNoticeSection: View {
    public init() {}

    public var body: some View {
        Section {
        } footer: {
            SampleNotice()
        }
    }
}

/// 버튼을 누른 뒤의 화면 안 상태 줄. 알림 창 대신 쓴다(D028 편의성).
public struct SampleStatus: View {
    let text: String?

    public init(_ text: String?) {
        self.text = text
    }

    public var body: some View {
        if let text {
            Label(text, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sample.status")
        }
    }
}

/// 사진 자리: 회색 사각형 + SF Symbol + 짧은 캡션. 실제 이미지·저작물은 넣지 않는다.
public struct SamplePhoto: View {
    let caption: String?
    let systemImage: String
    let cornerRadius: CGFloat

    public init(_ caption: String? = nil, systemImage: String = "photo", cornerRadius: CGFloat = 0) {
        self.caption = caption
        self.systemImage = systemImage
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.25))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .bottom) {
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(4)
                }
            }
    }
}

/// 3열 사진 격자. 칸 내용은 호출하는 쪽이 정한다.
public struct SamplePhotoGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let cell: (Item) -> Cell

    public init(_ items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.cell = cell
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(items) { item in
                cell(item)
            }
        }
    }
}

/// 별점 표시(1~5).
public struct SampleStars: View {
    let rating: Int

    public init(_ rating: Int) {
        self.rating = rating
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
            }
        }
        .font(.caption)
        .accessibilityLabel("별점 \(rating)")
    }
}

// MARK: - 리뷰·프로필

public struct SampleReview: Hashable, Identifiable, Sendable {
    public var id: String { "\(date)-\(text)" }
    public let stars: Int
    public let tags: String
    public let text: String
    public let date: String

    public init(stars: Int, tags: String, text: String, date: String) {
        self.stars = stars
        self.tags = tags
        self.text = text
        self.date = date
    }
}

public struct SampleReviewRow: View {
    let review: SampleReview

    public init(_ review: SampleReview) {
        self.review = review
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SampleStars(review.stars)
                Spacer()
                Text(review.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(review.tags)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(review.text)
        }
    }
}

/// 고객에게 보이는 작가 프로필(고객 앱 C3, 작가 앱 P14의 "고객에게 보이는 모습").
public struct SampleProfile: Sendable {
    public let name: String
    public let stats: String
    public let intro: String
    public let equipment: String
    public let languages: String
    public let area: String
    public let portfolioCaptions: [String]
    public let priceLines: [(String, String)]
    public let priceExample: String
    public let reviews: [SampleReview]

    public init(name: String, stats: String, intro: String, equipment: String, languages: String, area: String,
                portfolioCaptions: [String], priceLines: [(String, String)], priceExample: String, reviews: [SampleReview]) {
        self.name = name
        self.stats = stats
        self.intro = intro
        self.equipment = equipment
        self.languages = languages
        self.area = area
        self.portfolioCaptions = portfolioCaptions
        self.priceLines = priceLines
        self.priceExample = priceExample
        self.reviews = reviews
    }
}

public struct SampleProfileView: View {
    let profile: SampleProfile
    let footerLine: String

    public init(_ profile: SampleProfile, footerLine: String) {
        self.profile = profile
        self.footerLine = footerLine
    }

    private struct Caption: Identifiable {
        let id: Int
        let text: String
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 64, height: 64)
                        .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.headline)
                        Text(profile.stats)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(profile.intro)
            }
            Section("정보") {
                LabeledContent("장비", value: profile.equipment)
                LabeledContent("소통 언어", value: profile.languages)
                LabeledContent("주 활동", value: profile.area)
            }
            Section("포트폴리오") {
                SamplePhotoGrid(profile.portfolioCaptions.enumerated().map { Caption(id: $0.offset, text: $0.element) }) { caption in
                    SamplePhoto(caption.text)
                }
                .padding(.vertical, 4)
            }
            Section("가격") {
                ForEach(profile.priceLines, id: \.0) { line in
                    LabeledContent(line.0, value: line.1)
                }
                Text(profile.priceExample)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("리뷰") {
                ForEach(profile.reviews) { review in
                    SampleReviewRow(review)
                }
            }
            Section {
                Text(footerLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - 약관 문서

public struct SampleDocument: Hashable, Identifiable, Sendable {
    public struct Clause: Hashable, Sendable {
        public let heading: String
        public let body: String

        public init(_ heading: String, _ body: String) {
            self.heading = heading
            self.body = body
        }
    }

    public var id: String { title }
    public let title: String
    public let version: String
    public let clauses: [Clause]

    public init(title: String, version: String = "초안 · 2026-11-21", clauses: [Clause]) {
        self.title = title
        self.version = version
        self.clauses = clauses
    }
}

/// 약관·정책 문서 화면: 제목, 판, 조항 머리와 예시 문장.
public struct SampleDocumentView: View {
    let document: SampleDocument

    public init(_ document: SampleDocument) {
        self.document = document
    }

    public var body: some View {
        List {
            Section {
                Text(document.version)
                    .foregroundStyle(.secondary)
            }
            ForEach(document.clauses, id: \.heading) { clause in
                Section(clause.heading) {
                    Text(clause.body)
                }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: document.title, id: "document")
    }
}

// MARK: - 위치정보 한 화면(정책 02 5절)

/// 위치정보 동의 항목 하나: 스위치 = 동의 상태(끄는 것이 곧 철회).
public struct SampleLocationConsent: Hashable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let consentedAt: String
    /// 끄기 전에 보여 줄 결과 한 줄
    public let offResult: String

    public init(title: String, consentedAt: String, offResult: String) {
        self.title = title
        self.consentedAt = consentedAt
        self.offResult = offResult
    }
}

/// 마이 > 약관·정책 > 위치정보. 동의 항목별 스위치, 멈추는 법, 최근 제공 내역(구간·끝난 이유), 문의 링크를 한 화면에 둔다.
/// `inquiry`는 "내역이 틀렸나요? 문의하기"의 목적지(고객 C17, 작가 P17).
public struct SampleLocationInfoView<Inquiry: View>: View {
    let consents: [SampleLocationConsent]
    let stopHints: [String]
    let history: [String]
    let revokeAllTitle: String?
    let inquiry: () -> Inquiry
    @State private var enabled: Set<String>
    @State private var status: String?

    public init(consents: [SampleLocationConsent], stopHints: [String], history: [String], revokeAllTitle: String?,
                @ViewBuilder inquiry: @escaping () -> Inquiry) {
        self.consents = consents
        self.stopHints = stopHints
        self.history = history
        self.revokeAllTitle = revokeAllTitle
        self.inquiry = inquiry
        _enabled = State(initialValue: Set(consents.map(\.title)))
    }

    public var body: some View {
        List {
            Section {
                ForEach(consents) { consent in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(consent.title, isOn: Binding(
                            get: { enabled.contains(consent.title) },
                            set: { isOn in
                                if isOn { enabled.insert(consent.title) } else { enabled.remove(consent.title) }
                                status = isOn ? "\(consent.title)을 다시 켰습니다(예시)" : "\(consent.title) 동의를 철회했습니다(예시)"
                            }
                        ))
                        Text(enabled.contains(consent.title) ? "동의 \(consent.consentedAt) · 끄면: \(consent.offResult)" : "꺼짐 · \(consent.offResult)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SampleStatus(status)
            } header: {
                Text("동의")
            } footer: {
                Text("스위치를 끄는 것이 곧 동의 철회입니다.")
            }
            if !stopHints.isEmpty {
                Section("멈추는 법") {
                    ForEach(stopHints, id: \.self) { Text($0) }
                }
            }
            Section("최근 위치 제공 내역") {
                ForEach(history, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
                NavigationLink("내역이 틀렸나요? 문의하기") { inquiry() }
                    .accessibilityIdentifier("sample.locationInquiryLink")
            }
            if let revokeAllTitle {
                Section {
                    Button(revokeAllTitle, role: .destructive) {
                        enabled.removeAll()
                        status = "위치정보 동의를 모두 철회했습니다(예시, 실제로 바뀌지 않음)"
                    }
                } footer: {
                    Text("모든 위치 기능(작가 찾기 지도의 내 위치, 만남 위치 공유)을 끄는 뜻입니다.")
                }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "위치정보", id: "locationInfo")
    }
}

// MARK: - 신고·차단(정책 03)

/// 두 앱이 같이 쓰는 신고 사유 목록(안전·긴급, 문의·신고, 채팅 메뉴).
public enum SampleReportReasons {
    public static let all = ["욕설·괴롭힘", "성적 내용", "위협·안전", "사기·금전 요구", "개인정보 노출", "약속 위반", "기타"]
}

/// 채팅 "…" 메뉴의 [신고]: 사유 → 보내기, 같은 시트에 "이 사용자 차단" 스위치. 실제 채팅은 바뀌지 않는다.
public struct SampleChatReportSheet: View {
    let target: String
    let onClose: () -> Void
    @State private var reason = SampleReportReasons.all[0]
    @State private var detail = ""
    @State private var alsoBlock = false
    @State private var status: String?

    public init(target: String, onClose: @escaping () -> Void) {
        self.target = target
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Form {
                Picker("사유", selection: $reason) {
                    ForEach(SampleReportReasons.all, id: \.self) { Text($0).tag($0) }
                }
                Section("내용") {
                    TextEditor(text: $detail)
                        .frame(minHeight: 100)
                }
                Toggle("이 사용자 차단", isOn: $alsoBlock)
                Section {
                    Button("보내기") {
                        status = alsoBlock ? "\(target)을(를) 신고하고 차단했습니다(예시)" : "\(target)을(를) 신고했습니다(예시)"
                    }
                    SampleStatus(status)
                }
                SampleNoticeSection()
            }
            .sampleScreen(title: "\(target) 신고", id: "chatReport")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}

/// 채팅 "…" 메뉴의 [차단]: 확인 1번(이 시트의 [차단하기]). 시작 전 티켓이면 촬영도 함께 취소된다고 알린다.
public struct SampleChatBlockSheet: View {
    let target: String
    let cancelsShoot: Bool
    let onClose: () -> Void
    @State private var status: String?

    public init(target: String, cancelsShoot: Bool, onClose: @escaping () -> Void) {
        self.target = target
        self.cancelsShoot = cancelsShoot
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("차단하면 \(target)의 메시지를 받지 않고 다시 매칭되지 않습니다.")
                    if cancelsShoot {
                        Label("촬영도 함께 취소됩니다", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("차단하기", role: .destructive) {
                        status = "\(target)을(를) 차단했습니다(예시, 실제로 차단·취소하지 않음)"
                    }
                    SampleStatus(status)
                }
                SampleNoticeSection()
            }
            .sampleScreen(title: "\(target) 차단", id: "chatBlock")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}

/// 마이 > 고객지원 > 차단한 사용자.
public struct SampleBlockedUsersView: View {
    let users: [String]
    @State private var unblocked: Set<String> = []
    @State private var status: String?

    public init(users: [String]) {
        self.users = users
    }

    public var body: some View {
        List {
            Section {
                ForEach(users, id: \.self) { user in
                    HStack {
                        Text(user)
                            .foregroundStyle(unblocked.contains(user) ? .secondary : .primary)
                        Spacer()
                        Button(unblocked.contains(user) ? "해제됨" : "차단 해제") {
                            unblocked.insert(user)
                            status = "\(user) 차단을 해제했습니다(예시)"
                        }
                        .buttonStyle(.borderless)
                        .disabled(unblocked.contains(user))
                    }
                }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "차단한 사용자", id: "blockedUsers")
    }
}

/// 채팅 "…" 메뉴에 붙이는 [신고]·[차단] 시트. 메뉴 항목은 `SampleChatSafetyMenuItems`.
public extension View {
    func sampleChatSafetySheets(target: String, cancelsShoot: Bool, showsReport: Binding<Bool>, showsBlock: Binding<Bool>) -> some View {
        sheet(isPresented: showsReport) {
            SampleChatReportSheet(target: target) { showsReport.wrappedValue = false }
        }
        .sheet(isPresented: showsBlock) {
            SampleChatBlockSheet(target: target, cancelsShoot: cancelsShoot) { showsBlock.wrappedValue = false }
        }
    }
}

public struct SampleChatSafetyMenuItems: View {
    let showsReport: Binding<Bool>
    let showsBlock: Binding<Bool>

    public init(showsReport: Binding<Bool>, showsBlock: Binding<Bool>) {
        self.showsReport = showsReport
        self.showsBlock = showsBlock
    }

    public var body: some View {
        Button("신고", systemImage: "exclamationmark.bubble") { showsReport.wrappedValue = true }
        Button("차단", systemImage: "hand.raised") { showsBlock.wrappedValue = true }
    }
}

// MARK: - 안전·긴급 지원

/// 안전·긴급 지원(고객 C5, 작가 P5). 전화는 걸지 않고 상태 줄로만 반응한다.
public struct SampleSafetyView: View {
    let reportTarget: String
    let reportReasons: [String]
    let showsStopRequest: Bool
    let tips: [String]
    @State private var status: String?

    public init(reportTarget: String, reportReasons: [String] = SampleReportReasons.all, showsStopRequest: Bool, tips: [String]) {
        self.reportTarget = reportTarget
        self.reportReasons = reportReasons
        self.showsStopRequest = showsStopRequest
        self.tips = tips
    }

    public var body: some View {
        List {
            Section("긴급") {
                HStack {
                    Button("112 신고") { status = "예시 화면에서는 전화하지 않습니다" }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    Button("119 신고") { status = "예시 화면에서는 전화하지 않습니다" }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                SampleStatus(status)
            }
            Section("운영팀") {
                LabeledContent("긴급 연락", value: "02-000-0000(예시)")
                Button("운영팀에 알리기") { status = "운영팀에 알렸습니다(예시)" }
                if showsStopRequest {
                    NavigationLink("촬영 중단 요청") {
                        SampleReportForm(title: "촬영 중단 요청", reasons: ["안전 위협", "고객 연락 두절", "장비 고장", "기타"], id: "stopRequest")
                    }
                }
            }
            Section("신고") {
                NavigationLink("\(reportTarget) 신고") {
                    SampleReportForm(title: "\(reportTarget) 신고", reasons: reportReasons, id: "report")
                }
                .accessibilityIdentifier("sample.reportLink")
            }
            Section("안전 수칙") {
                ForEach(tips, id: \.self) { tip in
                    Text(tip)
                }
            }
            SampleNoticeSection()
        }
    }
}

/// 신고·요청 양식: 사유, 내용, 보내기(상태 줄).
public struct SampleReportForm: View {
    let title: String
    let reasons: [String]
    let id: String
    @State private var reason: String
    @State private var detail = ""
    @State private var status: String?

    public init(title: String, reasons: [String], id: String) {
        self.title = title
        self.reasons = reasons
        self.id = id
        _reason = State(initialValue: reasons.first ?? "")
    }

    public var body: some View {
        Form {
            Picker("사유", selection: $reason) {
                ForEach(reasons, id: \.self) { Text($0).tag($0) }
            }
            Section("내용") {
                TextEditor(text: $detail)
                    .frame(minHeight: 120)
            }
            Section {
                Button("보내기") { status = "보냈습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: title, id: id)
    }
}
