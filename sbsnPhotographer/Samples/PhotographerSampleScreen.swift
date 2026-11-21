import MapKit
import SBSNUI
import SwiftUI

/// 작가 앱 예시 화면 라우터: 메뉴 id로 예시 화면을 고른다(D032, 총괄 문서 `UI_WIREFRAME_PAGES.md` 2절).
/// 예시 화면은 화면 안 상태만 바꾸고 서버에 쓰지 않으며 앱 밖으로 나가지 않는다. 촬영 엔진과는 연결하지 않는다.
struct PhotographerSampleScreen: View {
    let feature: PlannedFeature

    init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    var body: some View {
        Group {
            switch feature.id {
            case PhotographerFeatures.activityArea.id: SampleActivityAreaScreen()
            case PhotographerFeatures.breakTime.id: SampleBreakScreen()
            case PhotographerFeatures.requestPolicy.id: SampleRequestPolicyScreen()
            case PhotographerFeatures.customerBrief.id: SampleCustomerBriefScreen()
            case PhotographerFeatures.safety.id:
                SampleSafetyView(reportTarget: "고객", showsStopRequest: true, tips: PhotographerSampleData.safetyTips)
            case PhotographerFeatures.timer.id: SampleTimerScreen()
            case PhotographerFeatures.cameraGuide.id: SampleCameraGuideScreen()
            case PhotographerFeatures.photoReview.id: SamplePhotoReviewScreen()
            case PhotographerFeatures.history.id: SampleHistoryScreen()
            case PhotographerFeatures.sales.id: SampleSalesScreen()
            case PhotographerFeatures.settlement.id: SampleSettlementScreen()
            case PhotographerFeatures.feedback.id: SampleFeedbackScreen()
            case PhotographerFeatures.disputes.id: SampleDisputesScreen()
            case PhotographerFeatures.portfolio.id: SamplePortfolioScreen()
            case PhotographerFeatures.registration.id: SampleRegistrationScreen()
            case PhotographerFeatures.originals.id: SampleOriginalsScreen()
            case PhotographerFeatures.support.id: SampleSupportScreen()
            case PhotographerFeatures.terms.id: SamplePhotographerTermsScreen()
            default: Text(feature.title)
            }
        }
        .sampleScreen(feature)
    }
}

/// 목록에서 작가 예시 화면으로 가는 행.
struct PhotographerSampleLink: View {
    let feature: PlannedFeature

    init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    var body: some View {
        PlannedFeatureLink(feature) { PhotographerSampleScreen(feature) }
    }
}

// MARK: - P1 활동 위치·반경

struct SampleActivityAreaScreen: View {
    private static let seochon = CLLocationCoordinate2D(latitude: 37.5796, longitude: 126.9707)

    @State private var area = PhotographerSampleData.areas[0]
    @State private var radius = 800.0
    @State private var days: Set<String> = ["토", "일"]
    @State private var start = Calendar.current.date(from: DateComponents(hour: 10)) ?? .now
    @State private var end = Calendar.current.date(from: DateComponents(hour: 17)) ?? .now
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                // 실제 내 위치는 쓰지 않는다. 서촌 중심에 반경 원만 그린다.
                Map(initialPosition: .region(MKCoordinateRegion(center: Self.seochon, latitudinalMeters: 4_500, longitudinalMeters: 4_500))) {
                    MapCircle(center: Self.seochon, radius: radius)
                        .foregroundStyle(.blue.opacity(0.2))
                        .stroke(.blue, lineWidth: 1)
                }
                .frame(height: 200)
            }
            Picker("활동 지역", selection: $area) {
                ForEach(PhotographerSampleData.areas, id: \.self) { Text($0).tag($0) }
            }
            Section("반경 \(radius >= 1_000 ? String(format: "%.1fkm", radius / 1_000) : "\(Int(radius))m")") {
                Slider(value: $radius, in: 300...2_000, step: 100)
            }
            Section("활동 요일") {
                ForEach(PhotographerSampleData.weekdays, id: \.self) { day in
                    Toggle(day, isOn: Binding(
                        get: { days.contains(day) },
                        set: { if $0 { days.insert(day) } else { days.remove(day) } }
                    ))
                }
            }
            Section("시간") {
                DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("끝", selection: $end, displayedComponents: .hourAndMinute)
            }
            Section {
                Button("저장") { status = "활동 위치를 저장했습니다(예시)" }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P2 휴게

struct SampleBreakScreen: View {
    @State private var startedAt: Date?

    private var total: Int { PhotographerSampleData.breakRecords.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        List {
            Section {
                if let startedAt {
                    LabeledContent("상태") {
                        Text("휴게 중 · \(startedAt, style: .relative)째")
                    }
                } else {
                    LabeledContent("상태", value: "대기 중")
                }
                Button {
                    startedAt = startedAt == nil ? .now : nil
                } label: {
                    Text(startedAt == nil ? "휴게 시작" : "휴게 끝")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sample.breakToggle")
            } footer: {
                Text("휴게 중에는 고객 지도에 보이지 않고 새 매칭을 받지 않습니다. 예시 화면이라 실제 \"촬영 가능\" 상태는 바뀌지 않습니다.")
            }
            Section("오늘 기록") {
                ForEach(PhotographerSampleData.breakRecords) { record in
                    LabeledContent(record.range, value: "휴게 \(record.minutes)분")
                }
                LabeledContent("합계", value: "\(total)분")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P3 수락·거절 설정

struct SampleRequestPolicyScreen: View {
    @State private var manual = false
    @State private var responseSeconds = 60
    @State private var reasons = PhotographerSampleData.rejectReasons
    @State private var newReason = ""
    @State private var status: String?

    var body: some View {
        Form {
            Picker("수락 방식", selection: $manual) {
                Text("자동 수락(지금 방식)").tag(false)
                Text("직접 수락").tag(true)
            }
            .pickerStyle(.segmented)
            Stepper("응답 시간 \(responseSeconds)초", value: $responseSeconds, in: 30...120, step: 10)
                .disabled(!manual)
            Section("거절 사유") {
                ForEach(reasons, id: \.self) { Text($0) }
                HStack {
                    TextField("새 사유", text: $newReason)
                    Button("추가") {
                        guard !newReason.isEmpty else { return }
                        reasons.append(newReason)
                        newReason = ""
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section("받은 요청 예시") {
                Text("고객 2명 · 한국어 · 약 120m · 자연스러운 미소")
                HStack {
                    Button("수락") { status = "요청을 수락했습니다(예시)" }
                        .buttonStyle(.borderedProminent)
                    Button("거절") { status = "요청을 거절했습니다(예시)" }
                        .buttonStyle(.bordered)
                }
                SampleStatus(status)
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P4 고객 브리프

struct SampleCustomerBriefScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(PhotographerSampleData.brief, id: \.0) { row in
                    LabeledContent(row.0, value: row.1)
                }
            }
            Section {
                Label("촬영료에 사진 미포함 안내 확인됨(예시)", systemImage: "checkmark.seal")
            }
            SampleNoticeSection()
        }
    }
}

// MARK: - P6 10분 타이머

struct SampleTimerScreen: View {
    @State private var total = 600
    @State private var remaining = 600
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 64, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("sample.timerValue")
                ProgressView(value: Double(total - remaining), total: Double(total))
                HStack {
                    Button(isRunning ? "멈춤" : "시작") { isRunning.toggle() }
                        .buttonStyle(.borderedProminent)
                    Button("+5분 연장") {
                        total += 300
                        remaining += 300
                    }
                    .buttonStyle(.bordered)
                }
            } footer: {
                Text("화면 안에서만 줄어듭니다. 실제 촬영 시작 시각과는 아직 연결하지 않았습니다.")
            }
            SampleNoticeSection()
        }
        .task(id: isRunning) {
            while isRunning, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if isRunning { remaining -= 1 }
            }
            if remaining == 0 { isRunning = false }
        }
    }
}

// MARK: - P7 카메라 연결 가이드

struct SampleCameraGuideScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(PhotographerSampleData.cameraGuides) { guide in
                    NavigationLink(guide.brand) { SampleCameraGuideDetailScreen(guide: guide) }
                }
            }
            SampleNoticeSection()
        }
    }
}

struct SampleCameraGuideDetailScreen: View {
    let guide: PhotographerSampleData.CameraGuide

    var body: some View {
        List {
            if let note = guide.note {
                Section {
                    Label(note, systemImage: "info.circle")
                }
            }
            Section("단계") {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
            }
            SampleNoticeSection()
        }
        .sampleScreen(title: guide.brand, id: "cameraGuideDetail")
    }
}

// MARK: - P8 사진 검수·공개

struct SamplePhotoReviewScreen: View {
    enum Filter: String, CaseIterable {
        case all = "전체"
        case recommended = "추천"
        case check = "검토 필요"
        case excluded = "제외"
    }

    @State private var filter = Filter.all
    @State private var published: Set<String> = Set(PhotographerSampleData.reviewPhotos.filter { $0.badge != .excluded }.prefix(6).map(\.fileName))
    @State private var status: String?

    private var photos: [PhotographerSampleData.ReviewPhoto] {
        switch filter {
        case .all: PhotographerSampleData.reviewPhotos
        case .recommended: PhotographerSampleData.reviewPhotos.filter { $0.badge == .recommended }
        case .check: PhotographerSampleData.reviewPhotos.filter { $0.badge == .check }
        case .excluded: PhotographerSampleData.reviewPhotos.filter { $0.badge == .excluded }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("보기", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("공개 \(published.count)장(최소 5 · 목표 6 · 최대 8)")
                    .font(.subheadline)
            }
            Section {
                SamplePhotoGrid(photos) { photo in
                    Button {
                        if published.contains(photo.fileName) { published.remove(photo.fileName) } else { published.insert(photo.fileName) }
                    } label: {
                        SamplePhoto(photo.fileName)
                            .overlay(alignment: .topLeading) {
                                if let badge = photo.badge {
                                    Text(badge.rawValue)
                                        .font(.caption2.bold())
                                        .padding(4)
                                        .background(.regularMaterial)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: published.contains(photo.fileName) ? "eye.fill" : "eye.slash")
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            Section {
                Button("고객에게 공개") { status = "\(published.count)장을 공개했습니다(예시)" }
                SampleStatus(status)
            } footer: {
                Text("지금은 받은 사진이 바로 고객에게 보입니다.")
            }
            SampleNoticeSection()
        }
    }
}
