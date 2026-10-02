// Housekeeping — The Benign Monster octopus
//
// The mark is drawn rather than scaled down from the artwork on purpose. The original
// is a dark red octopus on black at very low contrast, and at the eighteen points a
// menu bar gives you it fills in to a smudge. Geometry solves both sizes at once: at
// eighteen points it is a crisp silhouette, and at forty the eyes open up into holes
// that read as a face.
//
// Everything is one colour, and the eyes are cut out of the head rather than painted
// on top, so the whole thing can be handed to macOS as a template image and tinted to
// match the menu bar in either appearance.

import SwiftUI

struct OctopusMark: View {
    /// Seconds. Tentacles drift on their own phases, so the octopus looks like it is
    /// breathing rather than like a picture being shaken.
    var time: Double = 0
    var color: Color = OctopusMark.benignMonster
    /// How hard the octopus is working. Zero is the resting mark the menu bar wears;
    /// one is the octopus at work, arms reaching wider and quicker. The drawing is the
    /// same either way, so the mark never turns into a different animal when it starts
    /// searching — the same octopus, moving more.
    var effort: Double = 0

    /// The Benign Monster's own red. Used as-is in the app; ignored in the menu bar,
    /// where the mark becomes a template and the system supplies the colour.
    static let benignMonster = Color(red: 0.78, green: 0.16, blue: 0.16)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // A slow rise and fall. Small enough that it registers as alive rather
            // than as movement — and quicker and deeper when there is work on.
            let breath = 1 + (0.028 + 0.030 * effort) * sin(time * (1.25 + 1.5 * effort))

            ZStack {
                OctopusTentacles(time: time, effort: effort)
                    .stroke(color, style: StrokeStyle(lineWidth: side * 0.105, lineCap: .round, lineJoin: .round))
                OctopusHead()
                    .fill(color, style: FillStyle(eoFill: true))
            }
            .frame(width: side, height: side * breath)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// The octopus at work, on its own clock.
///
/// The menu bar draws `OctopusMark` from a timer the app already runs. This is the
/// same mark on the sweep screen, where there is no such timer and the whole point
/// is that it should look busy while three readings are running underneath it. The
/// frame rate is the one the housekeeper's own octopus uses, so the two are the same
/// creature at the same speed.
struct WorkingOctopus: View {
    var size: CGFloat = 104

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
            OctopusMark(time: context.date.timeIntervalSinceReferenceDate, effort: 1)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("The housekeeper, looking around")
    }
}

/// The mantle: a dome from the waterline up over the top, with the eyes cut out.
struct OctopusHead: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(0.22, 0.62))
        path.addCurve(
            to: point(0.50, 0.07),
            control1: point(0.22, 0.28),
            control2: point(0.31, 0.07)
        )
        path.addCurve(
            to: point(0.78, 0.62),
            control1: point(0.69, 0.07),
            control2: point(0.78, 0.28)
        )
        path.closeSubpath()

        // Tall rather than round, the way an octopus's eye reads, and cut out of the
        // head so the mark stays a single colour.
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.360 * rect.width,
            y: rect.minY + 0.230 * rect.height,
            width: 0.082 * rect.width,
            height: 0.125 * rect.height
        ))
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.558 * rect.width,
            y: rect.minY + 0.230 * rect.height,
            width: 0.082 * rect.width,
            height: 0.125 * rect.height
        ))
        return path
    }
}

/// Four arms. The two outer ones reach out and curl back up; the two inner ones hang.
struct OctopusTentacles: Shape {
    var time: Double = 0
    /// How hard the arms are working. It scales how far they reach and how quickly,
    /// and lifts the tips, so the arms feel around rather than only sliding sideways.
    /// At zero every offset below is exactly zero and the drawing is the resting mark.
    var effort: Double = 0

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        /// How much faster the arms move when there is work on. Kept here so the sway
        /// and the lift stay in the same rhythm instead of drifting apart.
        let rate = 1.6 * (1 + 1.15 * effort)

        /// A horizontal nudge, in the same 0–1 space as the rest of the drawing, so an
        /// arm can drift without the tip losing its place on the grid.
        func sway(_ index: Int, _ amount: CGFloat, at x: CGFloat) -> CGFloat {
            let reach = amount * CGFloat(1 + 2.6 * effort)
            return x + CGFloat(sin(time * rate + Double(index) * 0.9 + effort * 0.7)) * reach
        }

        /// The vertical half of working: a tip lifts and settles. Up is a smaller y, so
        /// this subtracts, and it only ever subtracts when `effort` is above zero.
        func lift(_ index: Int, _ amount: CGFloat, at y: CGFloat) -> CGFloat {
            let rise = sin(time * rate + Double(index) * 1.3) * 0.5 + 0.5
            return y - amount * CGFloat(effort) * CGFloat(rise)
        }

        var path = Path()

        path.move(to: point(0.29, 0.56))
        path.addCurve(
            to: point(sway(0, 0.014, at: 0.17), lift(0, 0.05, at: 0.83)),
            control1: point(0.18, 0.67),
            control2: point(0.09, 0.76)
        )
        path.addCurve(
            to: point(sway(0, 0.012, at: 0.27), lift(0, 0.03, at: 0.82)),
            control1: point(0.23, 0.92),
            control2: point(0.29, 0.90)
        )

        path.move(to: point(0.44, 0.58))
        path.addCurve(
            to: point(sway(1, 0.010, at: 0.42), lift(1, 0.06, at: 0.93)),
            control1: point(0.38, 0.74),
            control2: point(0.39, 0.86)
        )

        path.move(to: point(0.56, 0.58))
        path.addCurve(
            to: point(sway(2, 0.010, at: 0.58), lift(2, 0.06, at: 0.93)),
            control1: point(0.62, 0.74),
            control2: point(0.61, 0.86)
        )

        path.move(to: point(0.71, 0.56))
        path.addCurve(
            to: point(sway(3, 0.014, at: 0.83), lift(3, 0.05, at: 0.83)),
            control1: point(0.82, 0.67),
            control2: point(0.91, 0.76)
        )
        path.addCurve(
            to: point(sway(3, 0.012, at: 0.73), lift(3, 0.03, at: 0.82)),
            control1: point(0.77, 0.92),
            control2: point(0.71, 0.90)
        )

        return path
    }
}
