import Foundation

struct CueFlowWidgetSnapshot: Codable, Equatable, Sendable {
    static let suiteName = "group.com.alex.cueflow"
    static let storageKey = "cueflow.widget.snapshot"

    let dueCount: Int
    let newCount: Int
    let languageLabel: String
    let updatedAt: Date

    static let empty = CueFlowWidgetSnapshot(
        dueCount: 0,
        newCount: 0,
        languageLabel: "CueFlow",
        updatedAt: .distantPast
    )
}
