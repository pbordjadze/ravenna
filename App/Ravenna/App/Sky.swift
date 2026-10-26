import Foundation

/// The two skies the app keeps, a gentle nod to astrology (Paul, October 17, 2026; decided with
/// the Lamplit Table, the Lamp's jury for the app's screens and controls): by Sun painting plays a
/// brighter kalimba, by Moon a celesta-like bell on the same five notes, lower and minor
/// (Ravenna: the tune in major or minor, `TileSound`), and the fill's two sparkles become stars (`CanvasView.popSparkles`). Only
/// the sun and the moon keeping the hours: nothing here tells the painter anything about
/// themselves.
nonisolated enum Sky: String, Sendable {
    case sun, moon

    /// Sun from 6 a.m. to 7 p.m. by the painter's own clock, all year, and Moon the rest: first
    /// light, and the lamps after supper. The device keeps its local time zone, so this needs
    /// no location.
    static let sunrise = 6
    static let nightfall = 19

    /// The sky at `date` in `calendar`'s time zone (the device's, following it as it travels).
    static func at(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Sky {
        (sunrise..<nightfall).contains(calendar.component(.hour, from: date)) ? .sun : .moon
    }

    /// The sky painting plays in at `date`: what a sound or a sparkle asks for.
    static func current(at date: Date = .now, in defaults: UserDefaults = .standard) -> Sky {
        SkySetting.stored(in: defaults).sky(at: date)
    }

    /// `hour` o'clock as the painter's locale writes it ("7 PM", "19 Uhr"), for Settings.
    static func clockText(_ hour: Int, calendar: Calendar = .autoupdatingCurrent) -> String {
        (calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now).formatted(.dateTime.hour())
    }
}

/// Settings › Music, a theme and nothing to do with the light or dark appearance (an
/// accessibility choice, the system's) or the paper (Settings › Paper): Sun and Moon keep their
/// music at every hour, and Auto, the default, takes the sky of the hour. Paul, October 17, 2026,
/// on the first version (a Sky menu of Moon, Sun and Follow the Sky): "could be confusing—maybe
/// this should just be a list of two music options, and those can be “Sun” and “Moon” or
/// “Auto”—and then auto can be default".
nonisolated enum SkySetting: String, CaseIterable, Identifiable, Sendable {
    case sun, moon, auto

    static let `default` = SkySetting.auto

    var id: String { rawValue }

    var name: String {
        switch self {
        // Ravenna: the Sun's and the Moon's tune in major and minor (`TileSound`).
        case .sun: String(localized: "sky.sun", defaultValue: "Major",
                          comment: "Choice of Settings › Music: the tune in a major key, at every hour")
        case .moon: String(localized: "sky.moon", defaultValue: "Minor",
                           comment: "Choice of Settings › Music: the tune in a minor key, at every hour")
        case .auto: String(localized: "sky.auto", defaultValue: "Auto",
                           comment: "Choice of Settings › Music: major by day and minor by night, by the painter's own clock")
        }
    }

    func sky(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Sky {
        switch self {
        case .sun: .sun
        case .moon: .moon
        case .auto: Sky.at(date, calendar: calendar)
        }
    }

    /// The stored setting (`SettingsKey.sky`), or the default. A value this build doesn't know
    /// (the first version's `followTheSky`, in SideStore builds only) is the default, Auto, which
    /// is what it meant.
    static func stored(in defaults: UserDefaults = .standard) -> SkySetting {
        defaults.string(forKey: SettingsKey.sky).flatMap(SkySetting.init(rawValue:)) ?? .default
    }
}
