import Foundation
import Testing
@testable import Aska

struct UserSettingsValidationTests {
    let year = 2026
    let valid = UserSettings(birthYear: 2000, menarcheAge: 13, cycleLength: 28, periodLength: 5)

    @Test("V1: типичные значения валидны")
    func typicalIsValid() {
        #expect(valid.isValid(currentYear: year))
    }

    enum Field: Sendable {
        case menarcheAge, cycleLength, periodLength
        func set(_ value: Int, in settings: inout UserSettings) {
            switch self {
            case .menarcheAge: settings.menarcheAge = value
            case .cycleLength: settings.cycleLength = value
            case .periodLength: settings.periodLength = value
            }
        }
    }

    @Test("V2: границы диапазонов включительно", arguments: [
        (Field.menarcheAge, 8, true), (.menarcheAge, 18, true),
        (.menarcheAge, 7, false), (.menarcheAge, 19, false),
        (.cycleLength, 20, true), (.cycleLength, 45, true),
        (.cycleLength, 19, false), (.cycleLength, 46, false),
        (.periodLength, 1, true), (.periodLength, 10, true),
        (.periodLength, 0, false), (.periodLength, 11, false),
    ] as [(Field, Int, Bool)])
    func rangeBoundaries(field: Field, value: Int, expected: Bool) {
        var settings = valid
        field.set(value, in: &settings)
        #expect(settings.isValid(currentYear: year) == expected)
    }

    @Test("V3: границы года рождения: не старше 80 и не младше 8 лет")
    func birthYearBoundaries() {
        var settings = valid
        settings.menarcheAge = 8
        for (birthYear, expected) in [(1946, true), (1945, false), (2018, true), (2019, false)] {
            settings.birthYear = birthYear
            #expect(settings.isValid(currentYear: year) == expected, "birthYear \(birthYear)")
        }
    }

    @Test("V4: первая менструация не может быть в будущем")
    func menarcheNotInFuture() {
        var settings = valid
        settings.birthYear = 2014
        settings.menarcheAge = 12
        #expect(settings.isValid(currentYear: year))
        settings.menarcheAge = 13
        #expect(!settings.isValid(currentYear: year))
    }
}

@MainActor
struct SettingsStoreTests {
    let local: UserDefaults
    let cloud: UserDefaults
    let sample = UserSettings(birthYear: 1995, menarcheAge: 12, cycleLength: 30, periodLength: 6)

    init() {
        local = UserDefaults(suiteName: "test.local.\(UUID())")!
        cloud = UserDefaults(suiteName: "test.cloud.\(UUID())")!
    }

    func encoded(_ settings: UserSettings) -> Data { try! JSONEncoder().encode(settings) }

    /// JSON key order is not stable, so compare decoded values rather than bytes.
    func stored(in storage: UserDefaults) -> UserSettings? {
        storage.data(forKey: SettingsStore.key).flatMap { try? JSONDecoder().decode(UserSettings.self, from: $0) }
    }

    @Test("K1: первый запуск — настроек нет, нужен онбординг")
    func emptyOnFirstLaunch() {
        #expect(SettingsStore(local: local, cloud: cloud).settings == nil)
    }

    @Test("K2: сохранение пишет и локально, и в iCloud")
    func saveWritesBoth() {
        SettingsStore(local: local, cloud: cloud).save(sample)
        #expect(stored(in: local) == sample)
        #expect(stored(in: cloud) == sample)
    }

    @Test("K3: новое устройство — настройки есть только в iCloud, восстанавливаются и копируются локально")
    func restoreFromCloud() {
        cloud.set(encoded(sample), forKey: SettingsStore.key)
        #expect(SettingsStore(local: local, cloud: cloud).settings == sample)
        #expect(stored(in: local) == sample)
    }

    @Test("K4: iCloud недоступен — работает на локальных настройках")
    func localOnly() {
        local.set(encoded(sample), forKey: SettingsStore.key)
        let store = SettingsStore(local: local, cloud: nil)
        #expect(store.settings == sample)
        store.save(UserSettings.default)
        #expect(store.settings == UserSettings.default)
    }

    @Test("K5: локальные и облачные различаются — побеждает iCloud")
    func cloudWinsOnConflict() {
        local.set(encoded(UserSettings.default), forKey: SettingsStore.key)
        cloud.set(encoded(sample), forKey: SettingsStore.key)
        #expect(SettingsStore(local: local, cloud: cloud).settings == sample)
    }

    @Test("K6: изменение пришло с другого устройства — настройки обновляются")
    func externalChange() {
        let store = SettingsStore(local: local, cloud: cloud)
        cloud.set(encoded(sample), forKey: SettingsStore.key)
        store.cloudDidChange()
        #expect(store.settings == sample)
        #expect(stored(in: local) == sample)
    }

    @Test("K7: повреждённые данные считаются отсутствующими, не падаем")
    func corruptedData() {
        local.set(Data("garbage".utf8), forKey: SettingsStore.key)
        cloud.set(Data("garbage".utf8), forKey: SettingsStore.key)
        #expect(SettingsStore(local: local, cloud: cloud).settings == nil)
    }

    @Test("K8: повреждённые данные в iCloud не затирают рабочие локальные")
    func corruptedCloudKeepsLocal() {
        local.set(encoded(sample), forKey: SettingsStore.key)
        cloud.set(Data("garbage".utf8), forKey: SettingsStore.key)
        let store = SettingsStore(local: local, cloud: cloud)
        #expect(store.settings == sample)
        store.cloudDidChange()
        #expect(store.settings == sample)
    }
}
