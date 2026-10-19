//
//  ShootingModeView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SwiftUI

/// 촬영 중 화면. 검은 화면에 받은 장수만 어둡게 보여 주고, 종료 버튼을 길게 누르는 것 외의 터치는 받지 않는다.
/// 주머니에 넣으면 근접 센서가 화면을 끄고, 사진이 들어올 때마다 진동으로 알린다.
struct ShootingModeView: View {
    let model: CameraTransferTestModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("촬영 모드")
                    .font(.headline)

                Text("\(model.photos.count)장 받음")
                    .font(.system(size: 52, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())

                Text("서버 저장 \(model.uploadedCount)장")
                    .font(.title3.monospacedDigit())
                    .contentTransition(.numericText())

                if let last = model.photos.last {
                    VStack(spacing: 4) {
                        Text(last.relativePath)
                            .font(.subheadline.monospaced())
                        Text("\(last.receivedAt, style: .relative) 전")
                            .font(.footnote)
                    }
                }

                if let line = model.logLines.last {
                    Text(line.text)
                        .font(.caption2.monospaced())
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Text("주머니에 넣으면 화면이 꺼지고 전송은 계속됩니다.\n전원 버튼으로 잠그면 전송이 멈춥니다.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                Text("길게 눌러 종료")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .overlay(Capsule().stroke(.white.opacity(0.4)))
                    .contentShape(Capsule())
                    .onLongPressGesture(minimumDuration: 1.5) {
                        onExit()
                    }
            }
            .padding(.top, 60)
            .padding(.bottom, 30)
            .foregroundStyle(.white.opacity(0.55))
            .animation(.default, value: model.photos.count)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.success, trigger: model.photos.count)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
            model.note("proximity: \(UIDevice.current.proximityState ? "covered" : "uncovered")")
        }
    }
}
