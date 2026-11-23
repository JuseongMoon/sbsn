import SBSNUI
import SwiftUI

/// 고객 앱 예시 화면 라우터: 메뉴 id로 예시 화면을 고른다(D032, 총괄 문서 `UI_WIREFRAME_PAGES.md` 1절).
/// 예시 화면은 화면 안 상태만 바꾸고 서버에 쓰지 않으며 앱 밖으로 나가지 않는다.
struct CustomerSampleScreen: View {
    let feature: PlannedFeature

    init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    var body: some View {
        Group {
            switch feature.id {
            case CustomerFeatures.photographerList.id: SamplePhotographerList()
            case CustomerFeatures.conditions.id: SampleConditionsScreen()
            case CustomerFeatures.photographerProfile.id:
                SampleProfileView(CustomerSampleData.profile, footerLine: "예시입니다. 실제 프로필은 지도에서 작가 핀을 눌러 [프로필]로 봅니다")
            case CustomerFeatures.briefing.id: SampleBriefingScreen()
            case CustomerFeatures.safety.id:
                SampleSafetyView(reportTarget: "작가", showsStopRequest: false, tips: CustomerSampleData.safetyTips)
            case CustomerFeatures.recommendation.id: SampleRecommendationScreen()
            case CustomerFeatures.basket.id: SampleBasketScreen()
            case CustomerFeatures.review.id: SampleReviewScreen()
            case CustomerFeatures.events.id: SampleEventsScreen()
            case CustomerFeatures.album.id: SampleAlbumScreen()
            case CustomerFeatures.orders.id: SampleOrdersScreen()
            case CustomerFeatures.retouch.id: SampleRetouchScreen()
            case CustomerFeatures.shareAndPrint.id: SampleShareScreen()
            case CustomerFeatures.profile.id: SampleProfileSettingsScreen()
            case CustomerFeatures.help.id: SampleHelpScreen()
            case CustomerFeatures.inquiry.id: SampleInquiryScreen()
            case CustomerFeatures.refund.id: SampleRefundScreen()
            case CustomerFeatures.terms.id: SampleTermsScreen()
            default: Text(feature.title)
            }
        }
        .sampleScreen(feature)
    }
}

/// 목록에서 고객 예시 화면으로 가는 행.
struct CustomerSampleLink: View {
    let feature: PlannedFeature

    init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    var body: some View {
        PlannedFeatureLink(feature) { CustomerSampleScreen(feature) }
    }
}

// MARK: - C1 작가 목록

/// 지도 화면의 [목록]. 행을 누르면 프로필(예시)로 간다.
struct SamplePhotographerList: View {
    enum Sort: String, CaseIterable {
        case distance = "가까운 순"
        case rating = "평점 순"
        case price = "가격 순"
    }

    @State private var sort = Sort.distance

    private var photographers: [CustomerSampleData.Photographer] {
        switch sort {
        case .distance: CustomerSampleData.photographers.sorted { $0.meters < $1.meters }
        case .rating: CustomerSampleData.photographers.sorted { $0.rating > $1.rating }
        case .price: CustomerSampleData.photographers
        }
    }

    var body: some View {
        List {
            Section {
                Picker("정렬", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(photographers) { photographer in
                    NavigationLink {
                        CustomerSampleScreen(CustomerFeatures.photographerProfile)
                    } label: {
                        row(photographer)
                    }
                    .opacity(photographer.isAvailable ? 1 : 0.45)
                }
            }
            SampleNoticeSection()
        }
    }

    private func row(_ photographer: CustomerSampleData.Photographer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SamplePhoto(systemImage: "person.fill", cornerRadius: 6)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(photographer.name)
                    .font(.headline)
                Text("약 \(photographer.meters)m · \(photographer.walk)")
                Text("\(photographer.languages) · ★ \(photographer.rating, specifier: "%.1f") (\(photographer.reviewCount))")
                Text(CustomerSampleData.priceLine)
                Text(photographer.status)
                    .foregroundStyle(photographer.isAvailable ? .green : .secondary)
            }
            .font(.caption)
        }
    }
}

// MARK: - C2 촬영 조건

struct SampleConditionsScreen: View {
    @State private var people = 2
    @State private var moods: Set<String> = ["자연스러운 미소"]
    @State private var language = "한국어"
    @State private var request = ""
    @State private var status: String?

    var body: some View {
        Form {
            Picker("인원", selection: $people) {
                Text("1명").tag(1)
                Text("2명").tag(2)
            }
            .pickerStyle(.segmented)
            Section("원하는 분위기") {
                ForEach(CustomerSampleData.moods, id: \.self) { mood in
                    Toggle(mood, isOn: Binding(
                        get: { moods.contains(mood) },
                        set: { if $0 { moods.insert(mood) } else { moods.remove(mood) } }
                    ))
                }
            }
            Picker("소통 언어", selection: $language) {
                ForEach(CustomerSampleData.languages, id: \.self) { Text($0).tag($0) }
            }
            Section("요청 사항") {
                TextField("예: 한복 입고 걸어가는 장면", text: $request)
            }
            Section {
                Button("조건 적용") { status = "조건을 적용했습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C4 촬영 안내

struct SampleBriefingScreen: View {
    var body: some View {
        List {
            Section("오늘 흐름") {
                ForEach(Array(CustomerSampleData.briefingSteps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
            }
            Section("촬영 브리프") {
                LabeledContent("인원", value: "2명")
                LabeledContent("분위기", value: "자연스러운 미소")
                LabeledContent("소통 언어", value: "한국어")
                LabeledContent("요청 사항", value: "돌담길에서 걸어가는 장면")
            }
            Section("약속") {
                ForEach(CustomerSampleData.briefingPromises, id: \.self) { Text($0) }
            }
            Section("취소·노쇼") {
                Text("촬영 시작 전에는 언제든 무료로 취소할 수 있습니다. 약속 장소에 오지 않으면 5분 뒤 매칭이 끝나고, 작가가 오지 않으면 운영팀이 다음 촬영을 도와드립니다.")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C6 추천 순서

struct SampleRecommendationScreen: View {
    @State private var byRecommendation = true

    private var photos: [CustomerSampleData.SamplePhotoItem] {
        byRecommendation ? CustomerSampleData.recommended : CustomerSampleData.recommended.sorted { $0.fileName < $1.fileName }
    }

    var body: some View {
        List {
            Section {
                Picker("정렬", selection: $byRecommendation) {
                    Text("추천 순서").tag(true)
                    Text("촬영 순서").tag(false)
                }
                .pickerStyle(.segmented)
            }
            Section {
                SamplePhotoGrid(photos) { photo in
                    VStack(alignment: .leading, spacing: 2) {
                        SamplePhoto(photo.fileName)
                            .overlay(alignment: .topLeading) {
                                if byRecommendation, let rank = photo.rank {
                                    Text("추천 \(rank)")
                                        .font(.caption2.bold())
                                        .padding(4)
                                        .background(.regularMaterial)
                                }
                            }
                        if byRecommendation, let reason = photo.reason {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("추천 순서는 후속 기능입니다(AI 선별).")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C7 선택 바구니

struct SampleBasketScreen: View {
    @State private var items = CustomerSampleData.basket
    @State private var status: String?

    var body: some View {
        List {
            Section("고른 사진") {
                ForEach(items, id: \.self) { fileName in
                    HStack {
                        SamplePhoto(cornerRadius: 4)
                            .frame(width: 48)
                        Text(fileName)
                        Spacer()
                        Button("빼기") { items.removeAll { $0 == fileName } }
                            .buttonStyle(.borderless)
                    }
                }
                NavigationLink("두 장 비교") { SampleCompareScreen() }
                    .accessibilityIdentifier("sample.compareLink")
            }
            Section("금액") {
                LabeledContent("사진 \(items.count)장 × 8,000원", value: "\((items.count * 8_000).formatted())원")
                LabeledContent("촬영료", value: "15,000원 · 결제 완료")
                LabeledContent("합계", value: "\((items.count * 8_000 + 15_000).formatted())원")
            }
            Section {
                Button("\(items.count)장 구매하기") { status = "구매했습니다(예시, 결제 없음)" }
                    .disabled(items.isEmpty)
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

struct SampleCompareScreen: View {
    @State private var status: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    SamplePhoto("DSC0101.JPG")
                    SamplePhoto("DSC0104.JPG")
                }
                HStack {
                    Button("왼쪽 고르기") { status = "DSC0101.JPG를 골랐습니다(예시)" }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("오른쪽 고르기") { status = "DSC0104.JPG를 골랐습니다(예시)" }
                        .buttonStyle(.bordered)
                }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: "두 장 비교", id: "compare")
    }
}

// MARK: - C8 리뷰 남기기

struct SampleReviewScreen: View {
    @State private var stars = 5
    @State private var liked: Set<String> = ["포즈 안내"]
    @State private var text = ""
    @State private var isPublic = true
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("하린 작가와의 촬영", value: "2026년 11월 21일")
                HStack {
                    ForEach(1...5, id: \.self) { index in
                        Button {
                            stars = index
                        } label: {
                            Image(systemName: index <= stars ? "star.fill" : "star")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("별 \(index)개")
                    }
                }
            }
            Section("좋았던 점") {
                ForEach(CustomerSampleData.reviewTags, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { liked.contains(tag) },
                        set: { if $0 { liked.insert(tag) } else { liked.remove(tag) } }
                    ))
                }
            }
            Section("한 줄 평") {
                TextEditor(text: $text)
                    .frame(minHeight: 80)
                Toggle("작가 포트폴리오에 내 리뷰 공개", isOn: $isPublic)
            }
            Section {
                Button("보내기") { status = "리뷰를 보냈습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - C9 제휴·이벤트

struct SampleEventsScreen: View {
    enum Tab: String, CaseIterable {
        case promotion = "프로모션"
        case coupon = "쿠폰"
        case guide = "촬영지 가이드"
    }

    @State private var tab = Tab.promotion
    @State private var status: String?

    var body: some View {
        List {
            Section {
                Picker("보기", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch tab {
            case .promotion:
                ForEach(CustomerSampleData.promotions) { promotion in
                    Section {
                        SamplePhoto(systemImage: "gift", cornerRadius: 6)
                            .frame(height: 100)
                        Text(promotion.title)
                            .font(.headline)
                        Text(promotion.period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .coupon:
                Section {
                    ForEach(CustomerSampleData.coupons) { coupon in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(coupon.name)
                                    .font(.headline)
                                Text("\(coupon.benefit) · \(coupon.expiry)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("사용하기") { status = "\(coupon.name)을 다음 촬영에 적용합니다(예시)" }
                                .buttonStyle(.bordered)
                        }
                    }
                    SampleStatus(status)
                }
            case .guide:
                Section {
                    ForEach(CustomerSampleData.guidePlaces) { place in
                        NavigationLink(place.name) { SampleGuidePlaceScreen(place: place) }
                    }
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleGuidePlaceScreen: View {
    let place: CustomerSampleData.GuidePlace

    var body: some View {
        List {
            Section {
                SamplePhoto(place.name, systemImage: "mappin.and.ellipse", cornerRadius: 6)
                    .frame(height: 160)
            }
            Section {
                LabeledContent("좋은 시간대", value: place.bestTime)
                LabeledContent("촬영 허용 범위", value: place.allowed)
                LabeledContent("주의 사항", value: place.caution)
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: place.name, id: "guidePlace")
    }
}
