import CoreGraphics

/// The quiet painting screen (Paul, October 18, backlog row 37: "let all the other buttons kinda
/// fade away, so you're just seeing the painting and your colors and a back button"; shaped with
/// the Lamplit Table, `factory/pieces/quiet-painting`). Once an area is painted the top bar fades
/// to Back, the progress ring and Hint; a tap on the ring brings the rest back until the next
/// fill. Nothing the canvas sees changes, so the painting never moves. On regular widths the bar's
/// buttons and the swatches are a quarter bigger, always, so nothing changes size under a finger.
///
/// SideStore and Debug builds only for now (`UNRELEASED`, root `CLAUDE.md` › App rules).
nonisolated enum QuietPainting {
    #if UNRELEASED
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    /// The tips that hang from a button the quiet bar hides: while one has its turn, the bar
    /// shows, so the tip has its button to point at.
    static let barTips: Set<TipID> = [.benchShowPhoto, .benchZen, .benchFeedback]

    /// Whether the top bar is quiet now. `wanted`: a fill has landed since the ring last brought
    /// the bar back (`PaintChromeState.wantsQuiet`). A painting not begun or finished, feedback
    /// mode, a bar tip's turn and VoiceOver or Switch Control (which find controls by moving
    /// through them, so none may go) keep the whole bar.
    static func isQuiet(
        wanted: Bool, isStarted: Bool, isComplete: Bool, isGivingFeedback: Bool, assistiveTechnology: Bool,
        tipTurn: TipID?
    ) -> Bool {
        guard isAvailable, wanted, isStarted, !isComplete, !isGivingFeedback, !assistiveTechnology else { return false }
        return tipTurn.map { !barTips.contains($0) } ?? true
    }

    /// How much bigger the bar's buttons and the swatches are: a quarter on regular widths.
    static func scale(regularWidth: Bool) -> CGFloat {
        isAvailable && regularWidth ? 1.25 : 1
    }
}
