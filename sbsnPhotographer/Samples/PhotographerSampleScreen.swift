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
            case PhotographerFeatures.customerBrief.id: SampleCustomerBriefScreen()
            case PhotographerFeatures.safety.id:
                SampleSafetyView(reportTarget: "고객", showsStopRequest: true, tips: PhotographerSampleData.safetyTips)
            case PhotographerFeatures.cameraGuide.id: SampleCameraGuideScreen()
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

// P1 활동 위치·반경, P2 휴게, P3 수락·거절 설정은 2단계 실제 화면이 돼 지웠다.

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

// MARK: - P7 사진 옮기기 가이드

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
