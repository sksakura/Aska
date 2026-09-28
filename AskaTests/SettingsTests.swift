import Foundation
import Testing
@testable import Aska

/// Mid-June birthdays in UTC, so the year never depends on the machine's time zone.
func birthday(_ year: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: 6, day: 15))!
}

struct UserSettingsValidationTests {
    let year = 2026
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let valid = UserSettings(birthDate: birthday(2000), menarcheYear: 2013, cycleLength: 28, periodLength: 5)

    func isValid(_ settings: UserSettings) -> Bool {
        settings.isValid(currentYear: year, calendar: utc)
    }

    @Test("V1: типичные значения валидны")
    func typicalIsValid() {
        #expect(isValid(valid))
    }

    enum Field: Sendable {
        case cycleLength, periodLength
        func set(_ value: Int, in settings: inout UserSettings) {
            switch self {
            case .cycleLength: settings.cycleLength = value
            case .periodLength: settings.periodLength = value
            }
        }
    }

    @Test("V2: границы длительностей включительно (цикл 15–45, менструация 1–12)", arguments: [
        (Field.cycleLength, 15, true), (.cycleLength, 45, true),
        (.cycleLength, 14, false), (.cycleLength, 46, false),
        (.periodLength, 1, true), (.periodLength, 12, true),
        (.periodLength, 0, false), (.periodLength, 13, false),
    ] as [(Field, Int, Bool)])
    func rangeBoundaries(field: Field, value: Int, expected: Bool) {
        var settings = valid
        field.set(value, in: &settings)
        #expect(isValid(settings) == expected)
    }

    @Test("V3: год начала менструаций — от 8 до 18 лет после рождения")
    func menarcheYearBoundaries() {
        var settings = valid
        for (menarcheYear, expected) in [(2008, true), (2007, false), (2018, true), (2019, false)] {
            settings.menarcheYear = menarcheYear
            #expect(isValid(settings) == expected, "menarcheYear \(menarcheYear)")
        }
    }

    @Test("V4: год рождения — не старше 80 и не младше 8 лет")
    func birthYearBoundaries() {
        for (birthYear, expected) in [(1946, true), (1945, false), (2018, true), (2019, false)] {
            let settings = UserSettings(birthDate: birthday(birthYear), menarcheYear: birthYear + 8,
                                        cycleLength: 28, periodLength: 5)
            #expect(isValid(settings) == expected, "birthYear \(birthYear)")
        }
    }

    @Test("V5: год начала менструаций не может быть в будущем")
    func menarcheNotInFuture() {
        var settings = UserSettings(birthDate: birthday(2014), menarcheYear: 2026, cycleLength: 28, periodLength: 5)
        #expect(isValid(settings))
        settings.menarcheYear = 2027
        #expect(!isValid(settings))
    }

    @Test("V6: допустимые годы начала менструаций для степпера")
    func menarcheYearRange() {
        #expect(UserSettings.menarcheYearRange(birthYear: 2000, currentYear: year) == 2008...2018)
        #expect(UserSettings.menarcheYearRange(birthYear: 2014, currentYear: year) == 2022...2026)
    }
}

@MainActor
struct SettingsStoreTests {
    let local: UserDefaults
    let cloud: UserDefaults
    let sample = UserSettings(birthDate: birthday(1995), menarcheYear: 2007, cycleLength: 30, periodLength: 6, remindersOn: false)

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
