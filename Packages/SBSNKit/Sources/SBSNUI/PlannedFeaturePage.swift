import SwiftUI

/// 기획에는 있지만 아직 실제 데이터와 연결하지 않은 메뉴 하나. 두 앱이 예시(더미) 데이터로 채운 화면으로 보여 준다(D032).
///
/// `id`는 시험 스크립트가 찾는 식별자에 쓴다: 목록 링크는 `planned.<id>`, 예시 화면 뿌리는 `sample.<id>`.
public struct PlannedFeature: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 이 자리에 들어갈 화면을 한두 문장으로
    public let summary: String
    /// 기획 문서에 적힌 하위 항목
    public let plannedItems: [String]
    public let systemImage: String

    public init(id: String, title: String, summary: String, plannedItems: [String] = [], systemImage: String = "hammer") {
        self.id = id
        self.title = title
        self.summary = summary
        self.plannedItems = plannedItems
        self.systemImage = systemImage
    }
}

/// 목록에서 예시 화면으로 가는 행. 오른쪽에 "예시"를 붙여 실제로 동작하는 메뉴와 구분한다.
public struct PlannedFeatureLink<Destination: View>: View {
    let feature: PlannedFeature
    let destination: () -> Destination

    public init(_ feature: PlannedFeature, @ViewBuilder destination: @escaping () -> Destination) {
        self.feature = feature
        self.destination = destination
    }

    public var body: some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent(feature.title) {
                Text("예시")
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("planned.\(feature.id)")
    }
}

public extension View {
    /// 예시 화면의 뿌리: 제목과 식별자 `sample.<id>`. 뿌리는 `List`·`Form`·`ScrollView`여야 식별자가 하위 요소로 번지지 않는다.
    func sampleScreen(_ feature: PlannedFeature) -> some View {
        sampleScreen(title: feature.title, id: feature.id)
    }

    /// 하위 예시 화면(문서, 상세 등)
    func sampleScreen(title: String, id: String) -> some View {
        navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .accessibilityIdentifier("sample.\(id)")
    }
}
