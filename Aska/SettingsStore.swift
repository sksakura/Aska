import Foundation
import Observation

protocol KeyValueStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStorage {}
extension NSUbiquitousKeyValueStore: KeyValueStorage {}

/// User settings kept locally (UserDefaults) and mirrored to iCloud key-value storage,
/// so they follow the user to a new device. The iCloud copy wins when it arrives.
@MainActor
@Observable
final class SettingsStore {
    static let key = "userSettings"

    private(set) var settings: UserSettings?

    private let local: KeyValueStorage
    private let cloud: KeyValueStorage?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(local: KeyValueStorage = UserDefaults.standard,
         cloud: KeyValueStorage? = NSUbiquitousKeyValueStore.default) {
        self.local = local
        self.cloud = cloud

        if let fromCloud = cloud.flatMap(Self.load) {
            settings = fromCloud
            local.set(try? JSONEncoder().encode(fromCloud), forKey: Self.key)
        } else {
            settings = Self.load(from: local)
        }

        if let kvs = cloud as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: kvs, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cloudDidChange() }
            }
            kvs.synchronize()
        }
    }

    func save(_ newSettings: UserSettings) {
        settings = newSettings
        let data = try? JSONEncoder().encode(newSettings)
        local.set(data, forKey: Self.key)
        cloud?.set(data, forKey: Self.key)
    }

    func cloudDidChange() {
        guard let fromCloud = cloud.flatMap(Self.load) else { return }
        settings = fromCloud
        local.set(try? JSONEncoder().encode(fromCloud), forKey: Self.key)
    }

    private static func load(from storage: KeyValueStorage) -> UserSettings? {
        storage.data(forKey: key).flatMap { try? JSONDecoder().decode(UserSettings.self, from: $0) }
    }
}
