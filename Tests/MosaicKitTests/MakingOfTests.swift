import Foundation
import Testing
@testable import MosaicKit

/// The making-of's plan against its reference, `prototype/making_of_plan.py`, on a part of the Met's
/// Young Woman in Red (public domain) as the prototype lays it, with each tile's stage. The fixture's
/// two shows are the default options and every other option at once (indigo, the hand, the continuous
/// build, the named makers). Regenerate both files with the reference, from the repository root:
///
///     python3 prototype/making_of_plan.py Tests/Fixtures/making-of/making-of-mosaic.json \
///       --fixture Tests/Fixtures/making-of/making-of-plan.json
@Suite("MakingOf")
struct MakingOfTests {
    /// Outside the test target's folder, so SwiftPM doesn't take them for its resources.
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/making-of")

    static func mosaic() throws -> Mosaic {
        try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: fixtures.appendingPathComponent("making-of-mosaic.json")))
    }

    static func reference() throws -> [String: Any] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("making-of-plan.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func close(_ a: Double, _ b: Any?, _ what: String) {
        let b = (b as? NSNumber)?.doubleValue ?? .nan
        #expect(abs(a - b) <= 1e-9 * max(1, abs(b)), "\(what): \(a) against the reference's \(b)")
    }

    static let options: [String: MakingOf.Options] = [
        "scenes": MakingOf.Options(names: false),
        "continuous": MakingOf.Options(sinopia: .indigo, hand: true, flow: .continuous, names: true),
    ]

    @Test(arguments: ["scenes", "continuous"])
    func matchesTheReference(_ key: String) throws {
        let ref = try #require(try Self.reference()[key] as? [String: Any])
        let options = try #require(Self.options[key])
        let show = MakingOf.Show(try Self.mosaic(), options: options)
        Self.close(show.duration, ref["duration"], "duration")
        Self.close(show.pitch, ref["pitch"], "pitch")
        let times = try #require(ref["times"] as? [String: [Double]])
        for s in MakingOf.Scene.allCases {
            Self.close(show.times[s]!.start, times[s.rawValue]?[0], "\(s) start")
            Self.close(show.times[s]!.length, times[s.rawValue]?[1], "\(s) length")
        }
        let start = try #require(ref["start"] as? [Any])
        #expect(start.count == show.start.count)
        for (i, s) in start.enumerated() {
            if s is NSNull { #expect(show.start[i] == .infinity) } else { Self.close(show.start[i], s, "tile \(i)'s start") }
        }
        let strokes = try #require(ref["strokes"] as? [[[Double]]])
        #expect(strokes.count == show.strokes.count)
        for (s, r) in zip(show.strokes, strokes) {
            #expect(s.count == r.count)
            for (p, q) in zip(s, r) { Self.close(p.x, q[0], "stroke x"); Self.close(p.y, q[1], "stroke y") }
        }
        let spans = try #require(ref["strokeSpan"] as? [[Double]])
        for (s, r) in zip(show.strokeSpans, spans) { Self.close(s.from, r[0], "span"); Self.close(s.to, r[1], "span") }
        #expect(show.cakeOrder == ref["cakeRank"] as? [Int])

        let mosaic = try Self.mosaic()
        for case let f as [String: Any] in try #require(ref["frames"] as? [Any]) {
            let t = try #require(f["t"] as? Double)
            let (scene, u) = show.scene(at: t)
            #expect(scene.rawValue == f["scene"] as? String, "the scene at \(t)")
            Self.close(u, f["u"], "progress at \(t)")
            if let c = f["card"] as? [String: Any] {
                let card = try #require(show.card(at: t), "a card at \(t)")
                #expect(card.scene.rawValue == c["scene"] as? String)
                Self.close(card.opacity, c["opacity"], "card opacity at \(t)")
                let text = MakingOf.Card(card.scene, options: options, modelTitle: "Test", modelCredit: "Credit")
                #expect([text.title, text.line, text.credit, text.method] == c["text"] as? [String])
            } else {
                #expect(show.card(at: t) == nil, "no card at \(t)")
            }
            Self.close(show.sinopia(at: t), f["sinopia"], "drawing at \(t)")
            Self.close(show.bed(at: t), f["bed"], "bed at \(t)")
            if let h = f["hand"] as? [Double] {
                let hand = try #require(show.hand(at: t), "the hand at \(t)")
                Self.close(hand.x, h[0], "hand x"); Self.close(hand.y, h[1], "hand y")
            } else {
                #expect(show.hand(at: t) == nil, "no hand at \(t)")
            }
            let tiles = try #require(f["tiles"] as? [Any]), light = try #require(f["light"] as? [Any])
            for (k, i) in stride(from: 0, to: mosaic.tiles.count, by: 19).enumerated() {
                switch (show.tile(i, at: t), tiles[k]) {
                case (.waiting, is NSNull), (.set, "set" as String): break
                case (.flying(let fl), let r as [String: Double]):
                    Self.close(fl.lift, r["lift"], "lift"); Self.close(fl.scale, r["scale"], "scale")
                    Self.close(fl.shadow, r["shadow"], "shadow"); Self.close(fl.glow, r["glow"], "glow")
                case (let s, let r): Issue.record("tile \(i) at \(t): \(s) against the reference's \(r)")
                }
                Self.close(show.light(i, at: t), light[k], "tile \(i)'s light at \(t)")
            }
            let cakes = try #require(f["cakes"] as? [[Double]])
            for (p, c) in cakes.enumerated() {
                let cake = show.cake(p, at: u)
                Self.close(cake.shown, c[0], "cake"); Self.close(cake.cool, c[1], "cake"); Self.close(cake.cut, c[2], "cake")
            }
        }
    }

    @Test func setsEveryTileOnceInStageOrder() throws {
        let m = try Self.mosaic(), show = MakingOf.Show(m)
        #expect(show.start.allSatisfy { $0.isFinite })
        let lightStart = show.times[.light]!.start
        #expect(show.start.allSatisfy { $0 + MakingOf.setTime <= lightStart }, "every tile is set before the light")
        // The face before the outlines before the andamento; within the face, the features, then the eyes.
        let last = { (s: MakingOf.Scene) in m.tiles.indices.filter { show.sceneOf[$0] == s }.map { show.start[$0] }.max()! }
        let first = { (s: MakingOf.Scene) in m.tiles.indices.filter { show.sceneOf[$0] == s }.map { show.start[$0] }.min()! }
        #expect(last(.face) < first(.outlines) && last(.outlines) < first(.andamento))
        let features = m.tiles.indices.filter { m.tiles[$0].stage == .feature }.map { show.start[$0] }
        let eyes = m.tiles.indices.filter { m.tiles[$0].stage == .eye }.map { show.start[$0] }
        #expect(features.max()! < eyes.min()!)
        #expect(show.tile(0, at: show.duration) == .set)
    }

    @Test func aMosaicWithoutStagesStillPlays() throws {
        var m = try Self.mosaic()
        for i in m.tiles.indices { m.tiles[i].stage = nil; m.tiles[i].stone = false }
        let show = MakingOf.Show(m)
        #expect(show.times[.face]!.length == 0 && show.times[.outlines]!.length == 0, "no face, no strands: their scenes are skipped")
        #expect(show.times[.sinopia]!.length == 0, "nothing to draw: the drawing's scene is skipped")
        // Typed apart: Swift 6.3 (Xcode 26.6) can't type-check the literals inside #expect in time.
        let skipped: Double = 48 - 6.5 - 5 - 5
        #expect(show.duration == skipped)
        #expect(show.strokes.isEmpty)
        #expect(show.sceneOf.allSatisfy { $0 == .andamento } && show.start.allSatisfy { $0.isFinite })
    }

    @Test func everyCardInTheContinuousBuildStaysLongEnoughToRead() throws {
        // The fixture's face holds all but 4 of its strands: their stage still gets its time.
        let show = MakingOf.Show(try Self.mosaic(), options: MakingOf.Options(flow: .continuous))
        var seen: [MakingOf.Scene: Double] = [:]
        for k in 0..<Int(show.duration * 100) {
            if let c = show.card(at: Double(k) / 100) { seen[c.scene, default: 0] += 0.01 }
        }
        let shown = MakingOf.Scene.build.compactMap { seen[$0] }
        #expect(shown.count == 3, "every stage has its card")
        let least = MakingOf.minStage * 0.9
        #expect(shown.allSatisfy { $0 >= least }, "none flashes by")
    }

    @Test func eachBundledMosaicPlaysItsStages() throws {
        let dir = Self.fixtures.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Ravenna/Resources/Mosaics")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix("-standard.json") }
        #expect(files.count == 9)
        for f in files {
            let m = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: dir.appendingPathComponent(f)))
            let show = MakingOf.Show(m)
            #expect(!show.strokes.isEmpty && show.times[.sinopia]!.length > 0, "\(f): a drawing to draw")
            #expect(show.times[.outlines]!.length > 0, "\(f): its strands")
            #expect(show.times[.face]!.length > 0 || f.hasPrefix("william"), "\(f): a face, but for the hippopotamus")
            #expect(show.start.allSatisfy { $0 + MakingOf.setTime <= show.times[.light]!.start }, "\(f): set before the light")
        }
    }

    @Test func theCardsNameTheMakersUnlessAskedNotTo() {
        let named = MakingOf.Card(.hold), plain = MakingOf.Card(.hold, options: MakingOf.Options(names: false))
        #expect(named.line.contains("Sosus at Pergamon") && named.line.contains("Ephraim at Bethlehem"), "Paul: \"Name them!\"")
        #expect(plain.line == "Most mosaicists are anonymous; a few names survive." && !plain.line.contains("Sosus"))
        #expect(MakingOf.Card(.face).credit.contains("Dioskourides of Samos"))
        #expect(!MakingOf.Card(.face, options: MakingOf.Options(names: false)).credit.contains("Dioskourides"))
    }
}
