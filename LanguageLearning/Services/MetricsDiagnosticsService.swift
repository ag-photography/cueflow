import Foundation
import MetricKit
import UIKit

final class MetricsDiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsDiagnosticsService()

    private let metricsCountKey = "metricKitPayloadCount"
    private let diagnosticsCountKey = "metricKitDiagnosticCount"
    private let lastDeliveryKey = "metricKitLastDelivery"
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        recordDelivery(count: payloads.count, key: metricsCountKey)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        recordDelivery(count: payloads.count, key: diagnosticsCountKey)
    }

    private func recordDelivery(count: Int, key: String) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
        defaults.set(Date.now, forKey: lastDeliveryKey)
    }

    func feedbackReport(storageMode: CueFlowStorageMode) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let defaults = UserDefaults.standard
        let deliveredMetrics = defaults.integer(forKey: metricsCountKey)
        let deliveredDiagnostics = defaults.integer(forKey: diagnosticsCountKey)
        let delivery = (defaults.object(forKey: lastDeliveryKey) as? Date)?.formatted() ?? "keine"
        return """
        CueFlow Problembericht

        Bitte beschreibe kurz, was passiert ist:


        App: \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Gerät: \(UIDevice.current.model)
        Speicher: \(storageMode.rawValue)
        MetricKit-Lieferungen: \(deliveredMetrics)
        Diagnosen: \(deliveredDiagnostics)
        Letzte Lieferung: \(delivery)

        Der Bericht enthält keine Lerninhalte, Antworten oder Aufnahmen.
        """
    }
}
