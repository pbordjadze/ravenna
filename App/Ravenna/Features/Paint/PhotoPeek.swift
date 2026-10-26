import Foundation
import SwiftUI

/// When the painting screen shows the source photo over the canvas. Holding the Photo
/// control peeks for as long as it is held; a quick tap keeps the photo shown (like the `p`
/// key and VoiceOver's activate) until the next tap on the control or on the canvas.
struct PhotoPeek {
    /// Presses shorter than this are taps.
    static let tapDuration: TimeInterval = 0.3

    private(set) var isLatched: Bool
    private(set) var isPressed = false
    private var pressStart: TimeInterval = 0
    private var latchedAtPress = false

    init(latched: Bool = false) {
        isLatched = latched
    }

    var isShown: Bool { isLatched || isPressed }

    mutating func pressBegan(at time: TimeInterval) {
        guard !isPressed else { return }
        isPressed = true
        pressStart = time
        latchedAtPress = isLatched
    }

    /// A press on a latched photo hides it however long it was; otherwise a tap latches and
    /// a hold leaves the latch as it is.
    mutating func pressEnded(at time: TimeInterval) {
        guard isPressed else { return }
        isPressed = false
        if latchedAtPress {
            isLatched = false
        } else if time - pressStart < Self.tapDuration {
            isLatched = true
        }
    }

    /// The system took the touch (a call, a multitasking gesture): the peek ends, but that was
    /// no deliberate tap, so it neither latches nor unlatches.
    mutating func pressCancelled() {
        isPressed = false
    }

    /// The menu or keyboard toggle, VoiceOver, or a canvas touch.
    mutating func setLatched(_ latched: Bool) {
        isLatched = latched
    }
}

/// The top bar's Photo control: touch and hold to compare the painting with its photo, tap
/// to keep the photo shown. Tinted glass while the photo shows.
struct PhotoPeekButton: View {
    @Binding var peek: PhotoPeek
    @GestureState private var isPressing = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.glassButtonDiameter) private var diameter
    /// Every accessibility value the control has had, under `DemoMode.tracesPhotoPeek`.
    @State private var valueTrace: [String] = []

    var body: some View {
        Image(systemName: peek.isShown ? "photo.fill" : "photo")
            .font(.system(size: 17, weight: .semibold))
            .imageScale(diameter > 44 ? .large : .medium)
            .foregroundStyle(peek.isShown ? Color.white : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: diameter, height: diameter)
            // Not interactive glass: it would take the touches this control handles itself.
            .glassEffect(peek.isShown ? Glass.regular.tint(Theme.signature) : Glass.regular, in: .circle)
            .scaleEffect(isPressing && isEnabled ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, pressing, _ in pressing = true }
                    .onChanged { press(down: true, at: $0.time) }
                    .onEnded { press(down: false, at: $0.time) })
            // Gesture state resets when the system cancels the touch, which never calls onEnded.
            // It also resets on a normal release, so the cancel waits for the current update:
            // by then a release's onEnded has run and the cancel finds nothing pressed.
            .onChange(of: isPressing) { _, pressing in
                if !pressing { Task { peek.pressCancelled() } }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Photo"))
            .accessibilityValue(peek.isShown ? Text("Showing") : Text("Hidden"))
            .accessibilityHint(Text("Touch and hold to compare with the photo. Tap to keep it shown."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { peek.setLatched(!peek.isLatched) }
            #if DEBUG
            .accessibilityIdentifier(DemoMode.tracesPhotoPeek ? valueTrace.joined(separator: ",") : "Photo")
            .onChange(of: peek.isShown, initial: true) { _, shown in
                if DemoMode.tracesPhotoPeek { valueTrace.append(shown ? "Showing" : "Hidden") }
            }
            #else
            .accessibilityIdentifier("Photo")
            #endif
    }

    /// `.disabled` doesn't stop a custom gesture, so a press is ignored here; a release
    /// always goes through so the photo can't stay stuck on.
    ///
    /// Times are the touches' own event times, not when these handlers run: a busy main thread
    /// (the photo loading as the press begins) must not stretch a quick tap into a hold.
    private func press(down: Bool, at date: Date) {
        let time = date.timeIntervalSinceReferenceDate
        if down {
            guard isEnabled else { return }
            peek.pressBegan(at: time)
        } else {
            peek.pressEnded(at: time)
        }
    }
}
