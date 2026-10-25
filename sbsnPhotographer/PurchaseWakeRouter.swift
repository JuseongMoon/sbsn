//
//  PurchaseWakeRouter.swift
//  sbsnPhotographer
//

import Observation
import SBSNBackend

/// 원격 알림으로 받은 구매를 지금 열려 있는 실증 화면 모델에 넘기고, 알림 등록 상태를 화면에 보여 준다.
@Observable
final class PurchaseWakeRouter {
    enum Registration: Equatable {
        case pending
        case registered
        case failed(String)
    }

    static let shared = PurchaseWakeRouter()

    var registration = Registration.pending
    /// 배너·소리 권한. 꺼져 있어도 앱을 깨우는 알림은 받는다.
    var isAlertAuthorized: Bool?
    /// 실증 화면 모델이 서버를 열 때 등록한다. 구매를 처리했으면 true를 돌려준다.
    @ObservationIgnored var handler: ((PhotographerPush.Purchase) async -> Bool)?

    func handle(_ purchase: PhotographerPush.Purchase) async -> Bool {
        guard let handler else { return false }
        return await handler(purchase)
    }
}
