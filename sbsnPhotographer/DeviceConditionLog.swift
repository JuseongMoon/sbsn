//
//  DeviceConditionLog.swift
//  sbsnPhotographer
//

import Foundation
import UIKit

/// 작가 폰의 배터리·충전·저전력 모드·발열 단계를 기록한다. 핫스팟·위치·업로드를 함께 켠 폰이
/// 한 촬영(약 1시간)을 버티는지 현장 실증에서 보려고 둔다.
///
/// `Application Support/device-log.csv`에 5분마다, 그리고 충전 상태·저전력 모드·발열 단계가 바뀔 때 한 줄씩 남긴다.
/// 앱이 살아 있는 동안만 기록된다("촬영 가능" 중에는 백그라운드 위치로 살아 있다). 멈춰 있던 동안은 줄이 비어 있다.
@MainActor
final class DeviceConditionLog {
    struct Context {
        let isAvailable: Bool
        let phase: String
    }

    static let fileURL = URL.applicationSupportDirectory.appending(path: "device-log.csv")
    private static let header = "time,battery,charging,lowPower,thermal,app,available,phase,trigger"
    /// 넘으면 이전 파일로 돌리고 새로 쓴다(5분 간격이면 몇 달 치).
    private static let maximumBytes = 1_000_000
    private static let interval: Duration = .seconds(5 * 60)

    private let context: @MainActor () -> Context
    private var observers: [any NSObjectProtocol] = []
    private var sampling: Task<Void, Never>?

    init(context: @escaping @MainActor () -> Context) {
        self.context = context
    }

    func start() {
        guard sampling == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let triggers: [(Notification.Name, String)] = [
            (UIDevice.batteryStateDidChangeNotification, "charging"),
            (.NSProcessInfoPowerStateDidChange, "lowPower"),
            (ProcessInfo.thermalStateDidChangeNotification, "thermal"),
        ]
        observers = triggers.map { name, trigger in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(trigger: trigger) }
            }
        }
        sampling = Task { [weak self] in
            self?.record(trigger: "launch")
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.record(trigger: "timer")
            }
        }
    }

    private func record(trigger: String) {
        let device = UIDevice.current
        let context = context()
        let battery = device.batteryLevel < 0 ? "" : String(Int((device.batteryLevel * 100).rounded()))
        let charging = switch device.batteryState {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
        let thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        let app = switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
        let fields = [
            Date().ISO8601Format(),
            battery, charging, ProcessInfo.processInfo.isLowPowerModeEnabled ? "1" : "0", thermal, app,
            context.isAvailable ? "1" : "0", context.phase, trigger,
        ]
        append(fields.joined(separator: ","))
    }

    private func append(_ line: String) {
        let url = Self.fileURL
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? Int, size > Self.maximumBytes {
            let previous = url.deletingLastPathComponent().appending(path: "device-log-previous.csv")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        if !manager.fileExists(atPath: url.path(percentEncoded: false)) {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: url.path(percentEncoded: false), contents: Data((Self.header + "\n").utf8))
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
