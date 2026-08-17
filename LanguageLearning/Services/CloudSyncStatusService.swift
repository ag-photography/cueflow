import CloudKit
import SwiftUI

private struct CueFlowStorageModeKey: EnvironmentKey {
    static let defaultValue: CueFlowStorageMode = .local
}

extension EnvironmentValues {
    var cueFlowStorageMode: CueFlowStorageMode {
        get { self[CueFlowStorageModeKey.self] }
        set { self[CueFlowStorageModeKey.self] = newValue }
    }
}

@MainActor
final class CloudSyncStatusService: ObservableObject {
    enum Status: Equatable {
        case checking
        case available
        case noAccount
        case restricted
        case unavailable

        var label: String {
            switch self {
            case .checking: return "Wird geprüft …"
            case .available: return "Mit iCloud synchronisiert"
            case .noAccount: return "Kein iCloud-Account"
            case .restricted: return "iCloud eingeschränkt"
            case .unavailable: return "Nur auf diesem Gerät"
            }
        }

        var symbol: String {
            switch self {
            case .checking: return "arrow.triangle.2.circlepath.icloud"
            case .available: return "checkmark.icloud.fill"
            case .noAccount, .restricted, .unavailable: return "icloud.slash"
            }
        }
    }

    @Published private(set) var status: Status = .checking

    func refresh(storageMode: CueFlowStorageMode) async {
        guard storageMode == .iCloud else {
            status = .unavailable
            return
        }
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available: status = .available
            case .noAccount, .couldNotDetermine: status = .noAccount
            case .restricted: status = .restricted
            case .temporarilyUnavailable: status = .unavailable
            @unknown default: status = .unavailable
            }
        } catch {
            status = .unavailable
        }
    }
}
