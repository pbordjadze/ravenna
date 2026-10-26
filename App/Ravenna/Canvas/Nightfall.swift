#if UNRELEASED
import QuartzCore
import UIKit

/// Night falls over a painting the painter has just finished, about three seconds once its shine
/// has swept (Paul, October 18, 2026: "Build both please, then let me see"; the Lamplit Table's
/// round `pieces/intro-animation` chose the finished moment over any intro screen): dusk settles
/// on the painting, a gold crescent is inked into its top corner stroke by stroke, two stars come
/// out, and the night lifts again, leaving the painting as it was. By Sun (`Sky`) only a warm
/// evening light settles and lifts: no moon, no stars. It makes no sound. Under Reduce Motion
/// the whole night fades in as one still, the crescent already whole, and fades out.
///
/// Its layers sit over the painting in view space (the fill's sparkles' way); `follow` keeps them
/// on it while the camera moves. In SideStore and Debug builds only for now (`UNRELEASED`).
final class Nightfall {
    /// When the night is at its fullest (media time): demos wait for it.
    let peak: CFTimeInterval
    /// Seconds from the start to the night's lifting.
    let duration: Double
    /// What VoiceOver says as night falls.
    let announcement: String

    private let container = CALayer()
    /// The painting's frame in view space as night fell; `follow` maps it to where it is now.
    private let frame: CGRect

    /// `Theme.gold`, spelled out: the theme is SwiftUI, this file isn't.
    private static let gold = UIColor(red: 0.788, green: 0.635, blue: 0.290, alpha: 1).cgColor
    /// The dusk over the painting by Moon, and the evening light by Sun, with how much of each.
    private static let dusk = (color: UIColor(red: 0.10, green: 0.08, blue: 0.24, alpha: 1).cgColor, amount: 0.42)
    private static let evening = (color: UIColor(red: 0.86, green: 0.56, blue: 0.26, alpha: 1).cgColor, amount: 0.16)

    /// `pace` stretches every time (a canvas's `fillDurationScale`).
    init(over painting: CGRect, in host: CALayer, sky: Sky, reduceMotion: Bool, pace: Double) {
        frame = painting
        let night = sky == .moon
        // Seconds (before `pace`): dusk settles by `settled`, the night holds until `lifts`, and is
        // gone by `end`.
        let settled = reduceMotion ? 0.6 : 0.9
        let lifts = night ? 2.4 : 1.9
        let end = lifts + (reduceMotion ? 0.6 : 0.8)
        duration = end * pace
        let start = CACurrentMediaTime()
        peak = start + (reduceMotion ? settled : (night ? 2.0 : settled)) * pace
        announcement = night
            ? String(localized: "nightfall.moon", defaultValue: "The moon rises over your painting.",
                     comment: "VoiceOver announcement as a painting is finished by night: dusk falls over it and a crescent and two stars come out")
            : String(localized: "nightfall.evening", defaultValue: "Evening light falls over your painting.",
                     comment: "VoiceOver announcement as a painting is finished by day: a warm evening light settles over it")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(origin: .zero, size: painting.size)
        container.position = CGPoint(x: painting.midX, y: painting.midY)
        container.masksToBounds = true
        // Under the fill's sparkles (10), over the canvas.
        container.zPosition = 9
        host.addSublayer(container)

        /// Keyframes of `keyPath`: (second, value) pairs, eased between.
        func animate(_ layer: CALayer, _ keyPath: String, _ frames: [(Double, Double)]) {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = frames.map { NSNumber(value: $0.1) }
            animation.keyTimes = frames.map { NSNumber(value: min(1, max(0, $0.0 / end))) }
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(1, frames.count - 1))
            animation.duration = end * pace
            animation.beginTime = start
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: keyPath)
        }
        /// Shows from `appears` (seconds) until the night lifts.
        func shows(_ layer: CALayer, from appears: Double, amount: Double = 1) {
            let fade = reduceMotion ? (0.0, settled) : (appears, appears + 0.15)
            layer.opacity = 0
            animate(layer, "opacity", [(0, 0), (fade.0, 0), (fade.1, amount), (lifts, amount), (end, 0)])
        }

        let veil = CALayer()
        veil.frame = container.bounds
        let tone = night ? Self.dusk : Self.evening
        veil.backgroundColor = tone.color
        container.addSublayer(veil)
        veil.opacity = 0
        animate(veil, "opacity", [(0, 0), (settled, tone.amount), (lifts, tone.amount), (end, 0)])

        if night {
            let short = min(painting.width, painting.height)
            let side = min(72, max(28, short * 0.13))
            let margin = max(10, short * 0.07)
            let w = painting.width

            let moon = CAShapeLayer()
            moon.frame = CGRect(x: w - margin - side, y: margin, width: side, height: side)
            moon.path = Crescent.cgPath(in: moon.bounds)
            moon.fillColor = nil
            moon.strokeColor = Self.gold
            moon.lineWidth = min(3.5, max(2, side * 0.05))
            moon.lineCap = .round
            moon.lineJoin = .round
            container.addSublayer(moon)
            shows(moon, from: 0.3)
            // Inked stroke by stroke, the outer arc first.
            moon.strokeEnd = 1
            if !reduceMotion { animate(moon, "strokeEnd", [(0, 0), (0.3, 0), (1.3, 1), (end, 1)]) }

            // Two stars, few enough that the crescent stays the one thing to look at.
            let stars = [(centre: CGPoint(x: w - margin - side * 1.9, y: margin + side * 1.05), side: side * 0.34, appears: 1.2),
                         (centre: CGPoint(x: max(margin + side * 0.2, w * 0.24), y: margin + side * 0.35), side: side * 0.24, appears: 1.5)]
            for star in stars {
                let layer = CAShapeLayer()
                layer.bounds = CGRect(x: 0, y: 0, width: star.side, height: star.side)
                layer.position = star.centre
                layer.path = Sparkle.starPath(in: layer.bounds)
                layer.fillColor = Self.gold
                container.addSublayer(layer)
                shows(layer, from: star.appears)
                if !reduceMotion {
                    let t = star.appears
                    animate(layer, "transform.scale", [(0, 0.3), (t, 0.3), (t + 0.25, 1.12), (t + 0.5, 1), (end, 1)])
                }
            }
        }
        CATransaction.commit()
    }

    /// Keeps the night on the painting, now at `painting` in view space.
    func follow(_ painting: CGRect) {
        guard frame.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = CGPoint(x: painting.midX, y: painting.midY)
        let scale = painting.width / frame.width
        container.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    /// Lifts the night at once (the painting was undone, a replay began): a quick fade, then gone.
    func end() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = container.presentation()?.opacity ?? container.opacity
        fade.toValue = 0
        fade.duration = 0.25
        container.opacity = 0
        container.add(fade, forKey: "end")
        let container = container
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            container.removeFromSuperlayer()
        }
    }

    /// Takes its layers away once it has lifted.
    func remove() {
        container.removeFromSuperlayer()
    }
}
#endif
