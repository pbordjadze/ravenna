import Foundation

/// How often the tips may speak (the design's §5), as a pure value TipKit's `displayFrequency` can't
/// stand in for: it knows neither what the painter has done meanwhile, nor sessions, nor the first
/// painting, nor what is happening on screen. `TipDesk` asks it before it gives a tip its turn and
/// tells it when the tip is shown and when it is over; its state lives in UserDefaults (`TipStore`),
/// so the limits hold across launches.
///
/// The limits:
/// - one tip at a time, and none while something keeps them away (`Quiet`);
/// - at least `minimumGap` between hints, and something done between them (a fill, a slider moved,
///   a screen changed: `noteActivity`);
/// - at most `hintsPerSession` in a session (a stretch of use that no break of `sessionBreak` cuts)
///   and `hintsPerDay` in a day;
/// - on the newcomer's first painting, `hintsOnFirstPainting` from the time it opens: Tap to Paint
///   and whichever two others come due first. They count apart from the session's, whose limit the
///   hint on the shelf before the painting would otherwise share.
///
/// Tap to Paint is the way into painting, shown the moment the first painting opens, often seconds
/// after the shelf's hint was used (opening the painting): it alone waits for neither the gap nor
/// something done.
///
/// A refused hint is not kept. `refusal(for:)` changes nothing and the pacing has no queue: the hint
/// comes up again only when its moment next comes, and is judged then, as the design says ("it is not
/// queued to appear right after").
nonisolated struct TipPacing: Codable, Equatable, Sendable {
    static let minimumGap: TimeInterval = 3 * 60
    static let hintsPerSession = 3
    static let hintsPerDay = 5
    static let hintsOnFirstPainting = 3
    /// A break this long between two moments of use ends the session.
    static let sessionBreak: TimeInterval = 30 * 60

    /// What is on screen that keeps the hints away. The painter's own: a finger or the Pencil on
    /// the page, a fill landing. The show's: The Making-of, Replay Painting, the shine, Zen Mode
    /// drifting to the next area, Give Feedback. `pageFinished` is not silence but a narrowing: once
    /// a page is finished, Replay Painting is the only hint.
    struct Quiet: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let handOnPage = Quiet(rawValue: 1 << 0)
        static let filling = Quiet(rawValue: 1 << 1)
        static let makingOf = Quiet(rawValue: 1 << 2)
        static let replay = Quiet(rawValue: 1 << 3)
        static let shine = Quiet(rawValue: 1 << 4)
        static let zenDrifting = Quiet(rawValue: 1 << 5)
        static let feedback = Quiet(rawValue: 1 << 6)
        static let pageFinished = Quiet(rawValue: 1 << 7)

        /// Everything that is silence.
        static let silence: Quiet = [.handOnPage, .filling, .makingOf, .replay, .shine, .zenDrifting, .feedback]
    }

    /// Why a hint may not appear now.
    enum Refusal: Equatable, Sendable {
        case anotherShowing
        case quiet
        /// The page is finished: only Replay Painting speaks.
        case replayOnly
        case dayFull
        case sessionFull
        case firstPaintingFull
        case tooSoon
        case nothingDone
    }

    /// When the last hint appeared, and whether anything was done since.
    private(set) var lastShown: Date?
    private(set) var didSomethingSince = true
    /// The last moment of use, which a session lasts through.
    private(set) var lastSeen: Date?
    private(set) var shownThisSession = 0
    /// The calendar day of `shownToday` (`dayKey`).
    private(set) var day: String?
    private(set) var shownToday = 0
    /// The hints left of the first painting's, from the time it opens; nil when it isn't open.
    private(set) var firstPaintingLeft: Int?
    /// The hint on screen. Not kept: nothing is showing when the app starts.
    private(set) var showing: TipID?

    private enum CodingKeys: String, CodingKey {
        case lastShown, didSomethingSince, lastSeen, shownThisSession, day, shownToday, firstPaintingLeft
    }

    init() {}

    /// Every field may be missing, so a field added later keeps what an earlier build stored.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastShown = try c.decodeIfPresent(Date.self, forKey: .lastShown)
        didSomethingSince = try c.decodeIfPresent(Bool.self, forKey: .didSomethingSince) ?? true
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        shownThisSession = try c.decodeIfPresent(Int.self, forKey: .shownThisSession) ?? 0
        day = try c.decodeIfPresent(String.self, forKey: .day)
        shownToday = try c.decodeIfPresent(Int.self, forKey: .shownToday) ?? 0
        firstPaintingLeft = try c.decodeIfPresent(Int.self, forKey: .firstPaintingLeft)
    }

    /// The calendar day of `date` as a key (`2026-10-17`).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Whether `now` still belongs to the session that `lastSeen` ended last.
    private func continuesSession(at now: Date) -> Bool {
        guard let lastSeen else { return false }
        let away = now.timeIntervalSince(lastSeen)
        return away >= 0 && away < Self.sessionBreak
    }

    /// Why `id` may not appear now (nil: it may). Changes nothing.
    func refusal(for id: TipID, quiet: Quiet, now: Date, calendar: Calendar = .current) -> Refusal? {
        if showing != nil { return .anotherShowing }
        if !quiet.isDisjoint(with: .silence) { return .quiet }
        if quiet.contains(.pageFinished) && id != .benchReplay { return .replayOnly }

        if day == Self.dayKey(now, calendar: calendar), shownToday >= Self.hintsPerDay { return .dayFull }
        if continuesSession(at: now) {
            if let left = firstPaintingLeft {
                if left <= 0 { return .firstPaintingFull }
            } else if shownThisSession >= Self.hintsPerSession {
                return .sessionFull
            }
        }
        if !id.isHowTo, let lastShown {
            // A clock set back is no reason to wait (`continuesSession` reads it so too).
            let gap = now.timeIntervalSince(lastShown)
            if gap >= 0, gap < Self.minimumGap { return .tooSoon }
            if !didSomethingSince { return .nothingDone }
        }
        return nil
    }

    /// `id` appears.
    mutating func show(_ id: TipID, now: Date, calendar: Calendar = .current) {
        rollSession(at: now)
        showing = id
        lastSeen = now
        let today = Self.dayKey(now, calendar: calendar)
        if day != today {
            day = today
            shownToday = 0
        }
        shownToday += 1
        shownThisSession += 1
        if let left = firstPaintingLeft { firstPaintingLeft = left - 1 }
        lastShown = now
        didSomethingSince = false
    }

    /// `id` is over: closed, used, or its moment passed. A later hint still waits for the gap.
    mutating func hide(_ id: TipID) {
        if showing == id { showing = nil }
    }

    /// The painter did something: filled, moved a slider, went to another screen.
    mutating func noteActivity(now: Date) {
        rollSession(at: now)
        didSomethingSince = true
        lastSeen = now
    }

    /// The app starts or comes to the front: a break of `sessionBreak` since the last moment of use
    /// has ended the session before it.
    mutating func beginSession(now: Date) {
        rollSession(at: now)
        lastSeen = now
    }

    /// The newcomer's first painting opens.
    mutating func firstPaintingOpened(now: Date) {
        beginSession(now: now)
        firstPaintingLeft = Self.hintsOnFirstPainting
    }

    /// The painting screen closes; the first painting's own limit with it.
    mutating func paintingClosed() {
        firstPaintingLeft = nil
    }

    /// Starts a new session when the break has passed.
    private mutating func rollSession(at now: Date) {
        guard !continuesSession(at: now) else { return }
        shownThisSession = 0
        firstPaintingLeft = nil
    }
}

/// What the painter has done, as far as the tips' moments are concerned: facts TipKit's rules can't
/// state (dates, which paintings) and the pacing doesn't hold. Counts that rules can state are
/// TipKit events (`TipEvents`).
nonisolated struct TipHistory: Codable, Equatable, Sendable {
    /// Paintings opened, distinct, as far as the third.
    static let openedKept = 3

    /// When tips were first turned on: day one.
    private(set) var tipsOnSince: Date?
    /// Whether anything has been filled: until then the bench says nothing but Tap to Paint.
    private(set) var hasFilled = false
    private(set) var firstFinishedAt: Date?
    private(set) var opened: [String] = []

    private enum CodingKeys: String, CodingKey {
        case tipsOnSince, hasFilled, firstFinishedAt, opened
    }

    init() {}

    /// Every field may be missing, so a field added later keeps what an earlier build stored.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tipsOnSince = try c.decodeIfPresent(Date.self, forKey: .tipsOnSince)
        hasFilled = try c.decodeIfPresent(Bool.self, forKey: .hasFilled) ?? false
        firstFinishedAt = try c.decodeIfPresent(Date.self, forKey: .firstFinishedAt)
        opened = try c.decodeIfPresent([String].self, forKey: .opened) ?? []
    }

    mutating func tipsTurnedOn(at date: Date) {
        if tipsOnSince == nil { tipsOnSince = date }
    }

    mutating func filled() { hasFilled = true }

    mutating func finished(at date: Date) {
        if firstFinishedAt == nil { firstFinishedAt = date }
    }

    /// A painting opens. True when no painting had opened before: the first painting.
    @discardableResult
    mutating func paintingOpened(_ painting: String) -> Bool {
        let first = opened.isEmpty
        if !opened.contains(painting), opened.count < Self.openedKept { opened.append(painting) }
        return first
    }

    var openedCount: Int { opened.count }

    /// From the day after tips were first turned on.
    func isDayTwoOrLater(now: Date, calendar: Calendar = .current) -> Bool {
        guard let tipsOnSince else { return false }
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: tipsOnSince)
    }

    /// At least a day (24 hours) since the first page was finished.
    func isADayAfterFirstFinish(now: Date) -> Bool {
        guard let firstFinishedAt else { return false }
        return now.timeIntervalSince(firstFinishedAt) >= 24 * 60 * 60
    }
}

/// The pacing and the history in UserDefaults, as JSON. Unreadable data is no data: the tips start
/// fresh, quieter than they would be (nothing was shown that day), never louder.
nonisolated struct TipStore {
    static let pacingKey = "tipsPacing"
    static let historyKey = "tipsHistory"

    var defaults: UserDefaults = .standard

    func pacing() -> TipPacing { read(Self.pacingKey) ?? TipPacing() }
    func history() -> TipHistory { read(Self.historyKey) ?? TipHistory() }
    func save(_ pacing: TipPacing) { write(pacing, Self.pacingKey) }
    func save(_ history: TipHistory) { write(history, Self.historyKey) }

    /// Back to the start (Show Tips Again; every demo and test launch).
    func reset() {
        defaults.removeObject(forKey: Self.pacingKey)
        defaults.removeObject(forKey: Self.historyKey)
    }

    private func read<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    private func write(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
