import SwiftUI

/// 기획에는 있지만 아직 만들지 않은 메뉴 하나. 두 앱이 같은 빈 페이지(`PlannedFeaturePage`)로 보여 준다.
///
/// `id`는 시험 스크립트가 찾는 식별자(`planned.<id>`, 빈 페이지는 `placeholder.<id>`)에 쓴다.
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

/// 준비 중인 메뉴의 빈 페이지.
public struct PlannedFeaturePage: View {
    let feature: PlannedFeature

    public init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    public var body: some View {
        ContentUnavailableView {
            Label("준비 중", systemImage: feature.systemImage)
        } description: {
            VStack(spacing: 12) {
                Text(feature.summary)
                if !feature.plannedItems.isEmpty {
                    Text("기획: " + feature.plannedItems.joined(separator: " · "))
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(feature.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("placeholder.\(feature.id)")
    }
}

/// 목록에서 빈 페이지로 가는 행. 오른쪽에 "준비 중"을 붙여 동작하는 메뉴와 구분한다.
public struct PlannedFeatureLink: View {
    let feature: PlannedFeature

    public init(_ feature: PlannedFeature) {
        self.feature = feature
    }

    public var body: some View {
        NavigationLink {
            PlannedFeaturePage(feature)
        } label: {
            LabeledContent(feature.title) {
                Text("준비 중")
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("planned.\(feature.id)")
    }
}
