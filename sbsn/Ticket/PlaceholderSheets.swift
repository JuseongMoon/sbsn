import SBSNCore
import SwiftUI

/// 확정 전 "가격·조건 확인" 자리 화면. 결제와 동의는 아직 없어 표시만 하고, 확정 버튼이 지금의 확정 트랜잭션을 부른다.
struct PriceReviewSheet: View {
    let photographer: PhotographerPresence
    let isConfirming: Bool
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("작가", value: photographer.displayName)
                    LabeledContent("촬영료", value: "15,000원 (사진 미포함)")
                    LabeledContent("사진", value: "장당 8,000원")
                    Text("예) 1장 23,000원 · 3장 39,000원")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("판매자", value: "준비 중")
                } header: {
                    Text("가격")
                }
                Section {
                    Toggle("촬영·사진 처리 동의 (준비 중)", isOn: .constant(false))
                        .disabled(true)
                    Toggle("위치정보 이용 동의 (준비 중)", isOn: .constant(false))
                        .disabled(true)
                } header: {
                    Text("동의")
                } footer: {
                    Text("지금은 결제 없이 진행됩니다.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onConfirm) {
                    Group {
                        if isConfirming {
                            ProgressView()
                        } else {
                            Text("이 작가와 촬영 확정")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfirming)
                .accessibilityIdentifier("customer.confirm")
                .padding()
                .background(.bar)
            }
            .navigationTitle("가격·조건 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}

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
