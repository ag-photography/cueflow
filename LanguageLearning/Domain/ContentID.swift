import Foundation
import SwiftData

/// A cheap, `Sendable` identity token for a SwiftData model.
///
/// The domain layer needs to group and intersect model identities without
/// holding on to `@Model` instances — those are main-actor bound and can't
/// cross into the detached tasks that build the dashboard snapshots. The
/// obvious shortcut, `String(describing: persistentModelID)`, routes through
/// reflection: profiling the Heute tab showed it accounting for ~72 % of the
/// time spent building the learning-event list, and tens of thousands of calls
/// per tab switch once it landed inside a sort comparator.
///
/// `PersistentIdentifier` is already `Hashable` and `Sendable`, so wrapping it
/// keeps identity comparisons to a plain hash. The string case exists so tests
/// and previews can build fixtures without a live store.
enum ContentID: Hashable, Sendable {
    case model(PersistentIdentifier)
    case token(String)

    init(_ id: PersistentIdentifier) { self = .model(id) }
    init(_ token: String) { self = .token(token) }
}

extension ContentID: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .token(value) }
}

extension ContentID: CustomStringConvertible {
    /// Only for diagnostics — never use this to build a key.
    var description: String {
        switch self {
        case .model(let id): return String(describing: id)
        case .token(let value): return value
        }
    }
}

extension PersistentModel {
    /// The identity token for this model, cheap enough to call in a loop.
    var contentID: ContentID { .model(persistentModelID) }
}
