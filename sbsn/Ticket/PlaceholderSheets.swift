import SwiftUI

/// 촬영 시작 직전의 "촬영료 결제" 자리 화면. 결제는 만들지 않고(D003), "결제 없이 계속"이 지금의 시작 기록을 부른다.
struct PaymentPlaceholderSheet: View {
    let onContinue: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("10분 촬영", value: "15,000원")
                    LabeledContent("결제 수단", value: "준비 중")
                } footer: {
                    Text("결제 기능은 아직 없습니다. 계속하면 결제 없이 촬영을 시작합니다.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onContinue) {
                    Text("결제 없이 계속")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("customer.payment.continue")
                .padding()
                .background(.bar)
            }
            .navigationTitle("촬영료 결제")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
