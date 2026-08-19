import Foundation
import WidgetKit

enum WidgetSnapshotService {
    /// Fed from the precomputed Heute snapshot — the counts are identical, and
    /// deriving them here meant a second pass that faulted `phrase.topics` for
    /// every card.
    static func refresh(dueCount: Int, newCount: Int, languageCode: String) {
        let snapshot = CueFlowWidgetSnapshot(
            dueCount: dueCount,
            newCount: newCount,
            languageLabel: LanguagePack.configuration(for: languageCode)?.germanLabel
                ?? languageCode.uppercased(),
            updatedAt: .now
        )
        guard let defaults = UserDefaults(suiteName: CueFlowWidgetSnapshot.suiteName),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: CueFlowWidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
