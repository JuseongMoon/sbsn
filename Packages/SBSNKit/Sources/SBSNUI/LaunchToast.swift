#if os(iOS)
import SwiftUI

/// 몇 초 보이다 사라지는 알림 줄(두 앱 공통, 총괄 결정). 카드가 구독에서 빠져 사라져도 결과를 볼 수 있게 화면 뿌리에 붙인다.
/// 식별자는 Android와 같은 `request.notice`(교차 시험 드라이버가 두 앱에서 같은 이름으로 찾는다).
/// 예: "이미 만료된 신청이에요", "다른 신청을 이미 수락했어요", "1분이 지나 연장 요청이 만료됐어요".
public extension View {
    func launchToast(_ text: Binding<String?>, seconds: Double = 4) -> some View {
        overlay(alignment: .top) {
            if let message = text.wrappedValue {
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("request.notice")
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(seconds))
                        withAnimation { text.wrappedValue = nil }
                    }
            }
        }
        .animation(.default, value: text.wrappedValue)
    }
}
#endif
