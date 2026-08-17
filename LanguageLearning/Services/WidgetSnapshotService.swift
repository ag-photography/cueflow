import Foundation
import WidgetKit

enum WidgetSnapshotService {
    static func refresh(cards: [StudyCard], settings: [AppSettings]) {
        let code = settings.first?.activeLanguageCode ?? "ru"
        let active = cards.filter { $0.phrase?.language?.code == code }
        let due = active.filter { $0.state != .new && $0.dueDate <= .now }.count
        let new = active.filter {
            $0.state == .new
                && (($0.phrase?.topics?.contains(where: { $0.isActive }) ?? false)
                    || ($0.phrase?.isTutorPriorityActive ?? false))
        }.count
        let snapshot = CueFlowWidgetSnapshot(
            dueCount: due,
            newCount: new,
            languageLabel: LanguagePack.configuration(for: code)?.germanLabel ?? code.uppercased(),
            updatedAt: .now
        )
        guard let defaults = UserDefaults(suiteName: CueFlowWidgetSnapshot.suiteName),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: CueFlowWidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
