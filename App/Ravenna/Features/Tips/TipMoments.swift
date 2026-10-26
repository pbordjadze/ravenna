import Foundation

/// Whether tips are on: Settings › Tips' switch, `SettingsKey.tipsEnabled`. Tips are on for everyone
/// until they switch them off there (the only way to), so unset means on: whoever updates from an
/// earlier build has them too.
nonisolated enum TipPreference {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.tipsEnabled) as? Bool ?? SettingsDefault.tipsEnabled
    }

    static func record(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: SettingsKey.tipsEnabled)
    }

    /// Back to the default, on: what a demo or test launch starts from.
    static func forget(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: SettingsKey.tipsEnabled)
    }
}

/// Which tips a moment may offer, in the order the design meets them. A pure choice from what the
/// screen and the painter's history say; the desk (`TipDesk`) then asks TipKit which of them is
/// eligible (its events and parameters) and the pacing whether it may appear now.
nonisolated enum TipMoments {
    /// The shelf (the gallery) as the tips see it.
    struct Shelf: Equatable, Sendable {
        var artworks = 0
        var started = 0
        var ready = 0
        var finished = 0
        /// Pages still being prepared: the starters of the first launch.
        var preparing = false
    }

    /// What the shelf may say on this visit. Nothing before its pages are in view; then, to a
    /// newcomer, the page that waits and, as the painter reaches them, the rest. At most one of them
    /// is given its turn per visit (`TipDesk`).
    static func shelf(_ facts: Shelf, history: TipHistory, now: Date, calendar: Calendar = .current) -> [TipID] {
        guard !facts.preparing, facts.artworks > 0 else { return [] }
        var due: [TipID] = []
        // Nobody has painted: the starters wait, and no painting has been opened.
        if facts.started == 0, facts.finished == 0, facts.ready > 0, history.openedCount == 0 {
            due.append(.shelfStarter)
        }
        if facts.started + facts.finished > 0 { due.append(.shelfNewPainting) }
        if facts.artworks >= 2, history.isDayTwoOrLater(now: now, calendar: calendar) { due.append(.shelfHold) }
        if facts.finished > 0 { due += [.shelfSettings, .shelfTimeLapse] }
        return due
    }

    /// What the bench may say as a painting opens: a fresh page, how to paint; the third painting
    /// opened a day after the first page was finished, Give Feedback (whether its page is fresh or
    /// not: the third painting is often a new one); a page past a quarter, the photo.
    static func benchOpened(fresh: Bool, feedbackIsDue: Bool, pastQuarter: Bool) -> [TipID] {
        var due: [TipID] = []
        if fresh { due.append(.benchTap) }
        if feedbackIsDue { due.append(.benchFeedback) }
        if pastQuarter { due.append(.benchShowPhoto) }
        return due
    }

    /// What the preview may say once its template is final, given whether the divider's tip is
    /// over (Already Chosen for You waits for it) and where the settings came from.
    static func preview(dividerIsOver: Bool, isSuggested: Bool) -> [TipID] {
        var due: [TipID] = [.newPaintingDivider]
        if dividerIsOver, isSuggested { due.append(.newPaintingSuggested) }
        due.append(.newPaintingSliders)
        return due
    }
}
