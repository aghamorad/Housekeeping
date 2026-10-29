import SwiftUI

// MARK: - The housekeeper, drawn

// This is the app's own drawing of the housekeeper rather than a scaled bitmap,
// because she is needed from about 18 points in the menu bar up to a hundred and
// four in the sweep screen, and a bitmap that survives the top of that range is a
// smudge at the bottom of it.
//
// The path coordinates below are not invented. They are read off the artwork she
// was drawn from: the reference is 1408 x 1117 and the figure inside it sits in a
// box from x 200 to 1204 and y 88 to 1002, with her axis of symmetry at x 702.
// Every number here is a coordinate in that space, so a shape can be checked
// against the artwork by looking at it. `OctopusLayout` is what turns that space into
// whatever square the view has been given, and it scales both axes by the same
// factor so a non-square frame letterboxes her instead of stretching her.
//
// She is drawn twice from the same geometry. On a colour screen she is red, with a
// dark dress and cream linen. In the menu bar she is handed to macOS as a template
// image, which has exactly one tint to give — so there she is a single silhouette
// with the linen and the eyes cut out of it, and the cut-outs are what tell the
// eye where the cap and the apron are.
//
// Two shapes here are not outlines read off the artwork but relations between
// shapes: the headband is the head, lifted twenty-one units, with the head taken
// out of it, which is the only description that reproduces the way the band hugs
// her crown and thins to nothing at her temples; and both halves of her are drawn
// once and reflected, so the two sides cannot drift apart as the numbers are edited.

struct OctopusMark: View {
    /// How she is to be painted. The distinction cannot be inferred from `color`:
    /// the menu bar passes `.black` and the rail disc passes `.white`, and both of
    /// those are *solid* colours that a two-colour drawing could also use.
    enum Rendering {
        /// Red head, dark dress, cream linen. For anywhere with a real colour.
        case fullColour
        /// One ink, with the linen and the eyes cut away. For template images.
        case singleColour
    }

    var time: Double = 0
    var color: Color = OctopusMark.benignMonster
    var effort: Double = 0
    var rendering: Rendering = .fullColour

    /// Sampled from the artwork: the red of her head and tentacles.
    static let benignMonster = Color(red: 0.835, green: 0.169, blue: 0.149)
    /// Her dress and her headband. In the artwork this is a hair darker than the
    /// backdrop, which is why she reads as a bright figure on a dark ground.
    static let dress = Color(red: 0.165, green: 0.106, blue: 0.098)
    /// The cap, the collar, the cuffs, the buttons and the apron.
    static let linen = Color(red: 0.969, green: 0.941, blue: 0.910)

    /// The weight of her side tentacles and of her legs, in design units. The legs
    /// are the heavier of the two, which is what keeps her from looking as if she is
    /// standing on nothing.
    static let sideTentacleWidth: CGFloat = 48
    static let legWidth: CGFloat = 84

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // The tentacles are *stroked*, and a stroke width is the one thing a
            // `Shape` cannot scale for itself: its path comes back in view points, so
            // an unscaled 62 draws 62 points thick however small she is asked to be —
            // a quarter of her width at 260, and one solid blob in the menu bar.
            // `OctopusSilhouette` already does this arithmetic internally; this is the
            // same number for the full-colour path.
            let ink = OctopusLayout(CGRect(origin: .zero, size: CGSize(width: side, height: side))).scale
            // She breathes rather than merely being animated: a slow swell of a
            // couple of percent, deeper when she is working. A scale effect, not a
            // taller frame — `OctopusLayout` preserves her proportions and centres her, so
            // a taller frame would only add margin.
            let breath = 1 + (0.022 + 0.026 * effort) * sin(time * (1.25 + 1.5 * effort))

            ZStack {
                if rendering == .singleColour {
                    OctopusSilhouette(time: time, effort: effort)
                        .fill(color)
                } else {
                    // Behind everything: the eight tentacles, which pass behind the
                    // dress and behind her arms.
                    SideTentacles().stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: OctopusMark.sideTentacleWidth * ink,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    LegTentacles().stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: OctopusMark.legWidth * ink,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    OctopusFeet().fill(color)

                    OctopusDress().fill(OctopusMark.dress)

                    // The arms go on after the dress and before the head, because the
                    // sleeve tucks under her chin and behind her cheeks.
                    Arm(side: 1, time: time, effort: effort)
                    Arm(side: -1, time: time, effort: effort)

                    // The cap goes on first and the headband over it, then the head
                    // over that. That order is what produces the headband: it is a
                    // crescent between the white and the red, and the head hides the
                    // middle of it, so what is left showing is the arc you see in the
                    // artwork.
                    CapPuffs().fill(OctopusMark.linen)
                    Headband().fill(OctopusMark.dress)
                    OctopusHead().fill(color)
                    OctopusEyes().fill(OctopusMark.dress)

                    OctopusCollar().fill(OctopusMark.linen)
                    OctopusStraps().fill(OctopusMark.linen)
                    OctopusApron().fill(OctopusMark.linen)
                    OctopusButtons().fill(OctopusMark.linen)
                }
            }
            .frame(width: side, height: side)
            .scaleEffect(x: 1, y: breath, anchor: .center)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

// MARK: - Her geometry

/// The space the artwork was measured in.
///
/// The box is the figure's bounding box with a little air on every side, and the
/// axis is the line she is symmetrical about. Nothing else in the file should carry
/// a bare 702 or a bare 1000: those numbers belong here, where they can be
/// compared with the artwork in one place.
enum OctopusDesign {
    static let box = CGRect(x: 200, y: 88, width: 1004, height: 924)
    static let axis: CGFloat = 702
}

/// Maps the design space onto a view's rectangle.
///
/// One scale factor for both axes, so a square frame is exact and a non-square one
/// letterboxes her rather than stretching her. She is centred in whatever she is
/// given, which is why nothing here has to know how big it is being drawn.
struct OctopusLayout {
    let scale: CGFloat
    let origin: CGPoint

    init(_ rect: CGRect) {
        scale = min(rect.width / OctopusDesign.box.width, rect.height / OctopusDesign.box.height)
        origin = CGPoint(
            x: rect.minX + (rect.width - OctopusDesign.box.width * scale) / 2
                - OctopusDesign.box.minX * scale,
            y: rect.minY + (rect.height - OctopusDesign.box.height * scale) / 2
                - OctopusDesign.box.minY * scale
        )
    }

    /// A design point, in the view's coordinates.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    /// A circle at a design point, as the rectangle an ellipse is drawn in.
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (x - r) * scale,
            y: origin.y + (y - r) * scale,
            width: r * 2 * scale,
            height: r * 2 * scale
        )
    }

    /// An upright oval at a design point.
    func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (x - rx) * scale,
            y: origin.y + (y - ry) * scale,
            width: rx * 2 * scale,
            height: ry * 2 * scale
        )
    }

    /// A design rectangle.
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + x * scale,
            y: origin.y + y * scale,
            width: w * scale,
            height: h * scale
        )
    }

    /// The line she is symmetrical about, once the design box has been placed.
    var axisX: CGFloat { p(OctopusDesign.axis, 0).x }

    /// Reflection in that line. Half of her is drawn once and reflected, so the two
    /// sides cannot drift apart as the numbers are edited.
    var mirror: CGAffineTransform {
        CGAffineTransform(translationX: 2 * axisX, y: 0).scaledBy(x: -1, y: 1)
    }

    /// The same reflection, in design units, for callers working in that space.
    var mirroredDesignPoint: (CGFloat, CGFloat) -> CGPoint {
        { x, y in self.p(2 * OctopusDesign.axis - x, y) }
    }
}

/// Rotate about a point. Named for the point rather than the angle so a call site
/// reads as what it does.
func rotationAbout(_ point: CGPoint, degrees: Double) -> CGAffineTransform {
    CGAffineTransform(translationX: point.x, y: point.y)
        .rotated(by: degrees * .pi / 180)
        .translatedBy(x: -point.x, y: -point.y)
}

/// How far an arm has swung from hanging still, in degrees.
///
/// The two arms are half a cycle apart — one leads, one follows — which is the
/// difference between waving and marching. That falls out of the sign alone, so the
/// phase is deliberately absent: adding one on this side *and* a signed multiplier
/// cancels, and both arms then swim together. At rest she only drifts a couple of
/// degrees, enough to be alive on screen without looking agitated, and when she is
/// working it opens out.
func armSwing(_ side: CGFloat, time: Double, effort: Double) -> Double {
    let rate = 1.5 * (1 + 1.2 * effort)
    return side * sin(time * rate) * (2 + 13 * effort)
}

/// Where an arm is pinned to her body. Both arms share it, mirrored.
let shoulderPoint = CGPoint(x: 572, y: 508)

// MARK: - Her head

/// The head: an egg, not a circle. A circle through her crown and her widest point
/// bulges past her jaw, so the outline is two cubics down each side — one from the
/// crown to the cheekbone, one from there to the chin — with the control points on
/// the lower pair pulled in wide. She is broad from about a third of the way down,
/// which is why the second cubic is the short one.
struct OctopusHead: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.move(to: l.p(702, 186))
        p.addCurve(to: l.p(492, 470), control1: l.p(610, 188), control2: l.p(490, 300))
        p.addCurve(to: l.p(702, 548), control1: l.p(486, 512), control2: l.p(572, 548))
        p.addCurve(to: l.p(912, 470), control1: l.p(832, 548), control2: l.p(918, 512))
        p.addCurve(to: l.p(702, 186), control1: l.p(914, 300), control2: l.p(794, 188))
        p.closeSubpath()
        return p
    }
}

/// The two eyes. Solid dark ovals with no whites, which is what gives her the flat
/// illustration look rather than a cartoon one.
struct OctopusEyes: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.addEllipse(in: l.oval(625, 370, 32.5, 50))
        p.addEllipse(in: l.oval(779, 370, 32.5, 50))
        return p
    }
}

/// The dark crescent between her cap and her forehead.
///
/// Not a drawn band at all: it is the head, lifted twenty-one units, with the head
/// itself taken out of it. What survives is the sliver where the lifted outline
/// clears the real one — thickest at the crown, tapering to nothing at the temples,
/// which is exactly how a band sitting on top of a round head looks.
struct Headband: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        let head = OctopusHead().path(in: rect)
        let lifted = head.applying(
            CGAffineTransform(translationX: 0, y: -21 * l.scale)
        )
        return Path(lifted.cgPath.subtracting(head.cgPath, using: .winding))
    }
}

/// The frilled cap: seven overlapping puffs whose union is the scalloped bonnet.
///
/// Their centres lie on a circle of radius 138 about (702, 262), at thirty degrees
/// apart. That is not a guess — it is what puts the topmost puff's crown at y 94 and
/// the outermost puff's edge at x 534, which are the two extremes the artwork shows.
struct CapPuffs: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        for step in 0...6 {
            let theta = Double.pi * Double(step) / 6
            p.addEllipse(
                in: l.circle(
                    702 - 138 * CGFloat(cos(theta)),
                    262 - 138 * CGFloat(sin(theta)),
                    30
                )
            )
        }
        return p
    }
}

// MARK: - Her dress

/// The bodice and the skirt as one dark shape, from the shoulders to the hem.
///
/// There is no waist in it. The bodice is narrow at the top and the flare to the hem
/// is monotone; a pinch in the middle is what made an earlier version of this read as
/// a person in a suit rather than as an octopus in a maid's dress. The sleeves are not
/// part of it — they move with her arms.
struct OctopusDress: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.move(to: l.p(578, 496))
        p.addCurve(to: l.p(539, 632), control1: l.p(556, 540), control2: l.p(538, 580))
        p.addCurve(to: l.p(457, 752), control1: l.p(540, 680), control2: l.p(470, 700))
        p.addCurve(to: l.p(560, 820), control1: l.p(450, 790), control2: l.p(500, 820))
        p.addCurve(to: l.p(702, 828), control1: l.p(614, 828), control2: l.p(660, 830))
        p.addCurve(to: l.p(844, 820), control1: l.p(744, 830), control2: l.p(790, 828))
        p.addCurve(to: l.p(947, 752), control1: l.p(904, 820), control2: l.p(954, 790))
        p.addCurve(to: l.p(865, 632), control1: l.p(934, 700), control2: l.p(864, 680))
        p.addCurve(to: l.p(826, 496), control1: l.p(866, 580), control2: l.p(848, 540))
        p.closeSubpath()
        return p
    }
}

/// The white collar: two lobes reaching in from the shoulders, pinched to a point at
/// the centre so the neck is not covered. It is a butterfly rather than a bib — the
/// middle of it is missing at the bottom as well as the top, which is why there are
/// two lobes and not one band.
struct OctopusCollar: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var lobe = Path()
        lobe.move(to: l.p(572, 512))
        lobe.addCurve(to: l.p(612, 582), control1: l.p(578, 536), control2: l.p(592, 566))
        lobe.addCurve(to: l.p(640, 576), control1: l.p(622, 584), control2: l.p(632, 580))
        lobe.addLine(to: l.p(702, 548))
        lobe.closeSubpath()

        var p = lobe
        p.addPath(lobe, transform: l.mirror)
        return p
    }
}

/// The two shoulder straps, running from under the collar down to the apron. Small,
/// but without them the bodice is a slab and the apron looks stuck on rather than
/// tied on.
struct OctopusStraps: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var strap = Path()
        strap.addRoundedRect(
            in: l.rect(587, 548, 22, 106),
            cornerSize: CGSize(width: 11 * l.scale, height: 11 * l.scale)
        )

        var p = strap
        p.addPath(strap, transform: l.mirror)
        return p
    }
}

/// The two buttons down the middle of the bodice.
struct OctopusButtons: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.addEllipse(in: l.circle(702, 592, 12))
        p.addEllipse(in: l.circle(702, 638, 12))
        return p
    }
}

/// The apron: a broad white shape over the front of the skirt, its top edge a shallow
/// dip under the bodice and its bottom edge a row of five scallops.
///
/// It is built right to left along the bottom, because `addScallops` always bulges to
/// one side of travel and an apron's frill hangs downward.
struct OctopusApron: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.move(to: l.p(556, 646))
        p.addCurve(to: l.p(702, 664), control1: l.p(610, 646), control2: l.p(652, 660))
        p.addCurve(to: l.p(840, 646), control1: l.p(752, 660), control2: l.p(794, 646))
        p.addCurve(to: l.p(838, 798), control1: l.p(852, 690), control2: l.p(852, 760))
        addScallops(&p, from: l.p(838, 798), to: l.p(566, 798), count: 5)
        p.addCurve(to: l.p(556, 646), control1: l.p(554, 760), control2: l.p(554, 690))
        p.closeSubpath()
        return p
    }
}

// MARK: - Her arms

/// An arm, complete: the puffed sleeve and the white cuff at its end, turned about
/// the shoulder as one piece so the cuff cannot slide off the sleeve while she moves.
///
/// There is no red forearm. In the artwork the sleeve meets the cuff and the cuff
/// meets tentacle; drawing a red length between them was an invention, and it is what
/// made her look like a person in a costume.
struct Arm: View {
    var side: CGFloat
    var time: Double = 0
    var effort: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let l = OctopusLayout(rect)
            let mirrored = side < 0
            let shoulder = l.p(
                mirrored ? 2 * OctopusDesign.axis - shoulderPoint.x : shoulderPoint.x,
                shoulderPoint.y
            )
            let flip = mirrored ? l.mirror : .identity

            ZStack {
                Sleeve().path(in: rect).applying(flip).fill(OctopusMark.dress)
                Cuff().path(in: rect).applying(flip).fill(OctopusMark.linen)
            }
            .rotationEffect(
                .degrees(armSwing(side, time: time, effort: effort)),
                anchor: UnitPoint(
                    x: shoulder.x / max(rect.width, 1),
                    y: shoulder.y / max(rect.height, 1)
                )
            )
        }
    }
}

/// The dark puff over the shoulder.
struct Sleeve: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.addEllipse(in: l.oval(548, 590, 58, 66))
        return p
    }
}

/// The white cuff: a short thick band across the outer end of the sleeve, set on the
/// slant. Square-ended, because a cuff is a hem and not a limb.
struct Cuff: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.move(to: l.p(472, 555))
        p.addLine(to: l.p(517, 605))
        p.addLine(to: l.p(483, 635))
        p.addLine(to: l.p(438, 585))
        p.closeSubpath()
        return p
    }
}

// MARK: - Her tentacles

/// One curl: the near-circle a tentacle ends in.
///
/// The arc is Core Graphics' own. An earlier pass walked it in forty-five degree steps
/// and set each cubic's handles from the unit tangent — but the walk ran *backwards*,
/// against the tangent it was reading, so every segment's control points landed on the
/// wrong side of its own chord. Each one looped instead of bowing, and the coil came
/// out as a three-lobed trefoil: invisible in the bare path, and unmissable once a
/// forty-eight wide stroke followed it. The joins were still exactly tangent-continuous
/// throughout, which is what made it read as plausible for so long. Handing CG the arc
/// leaves nothing to get backwards.
///
/// Angles are in the design space's own orientation, which is the screen's: 0° is to
/// the right and 90° is downwards. `from: 0` is the rightmost point of the coil, which
/// is where an arm arriving from the body meets it, so a negative sweep curls the
/// tentacle away from her rather than back across her.
func addCurl(_ path: inout Path, in l: OctopusLayout,
             centre: CGPoint, radius: CGFloat, from: Double, sweep: Double) {
    path.addArc(center: l.p(centre.x, centre.y),
                radius: radius * l.scale,
                startAngle: .degrees(from),
                endAngle: .degrees(from + sweep),
                clockwise: sweep < 0)
}

/// The three tentacles that curl to each side of her. Each comes out from behind the
/// dress, sweeps away and hooks back on itself; the gap the hook leaves is what tells
/// the eye it is a curl rather than a lump.
struct SideTentacles: Shape {
    /// Where each curl's centre sits, and how tightly it coils.
    ///
    /// A radius of forty-two against a stroke of forty-eight puts the coil's outer edge
    /// at sixty-six and its hole eighteen across, which is what a row-by-row scan of
    /// the artwork measures: the middle curl runs a hundred and thirty from top to
    /// bottom, its leftmost red sits sixty-six out from the centre, and the slit in the
    /// middle is thirty-four wide where it is narrowest. An earlier pass used a radius
    /// of thirty with a stroke of sixty-two — outer sixty-one, hole *negative* — and
    /// the coils came out as solid bulbs, because there was nothing for the eye to see
    /// through and the arm had nowhere to sit but on top of the tip.
    private static let curls: [(centre: CGPoint, radius: CGFloat, sweep: Double)] = [
        (CGPoint(x: 356, y: 503), 42, -235),
        (CGPoint(x: 276, y: 685), 42, -235),
        (CGPoint(x: 383, y: 876), 42, -235)
    ]

    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var half = Path()

        // The three arms, top to bottom. Each rises from behind her dress and arrives
        // at its curl travelling straight up, which is the tangent a zero-degree
        // entry takes when the sweep runs backwards. That is the whole reason the
        // sweep is negative: it is what makes the arm hang off the outside of the
        // coil instead of lying across it.
        half.move(to: l.p(520, 640))
        half.addCurve(to: l.p(398, 503), control1: l.p(466, 600), control2: l.p(410, 559))
        addCurl(&half, in: l, centre: Self.curls[0].centre, radius: Self.curls[0].radius,
                from: 0, sweep: Self.curls[0].sweep)

        half.move(to: l.p(540, 790))
        half.addCurve(to: l.p(318, 685), control1: l.p(470, 775), control2: l.p(330, 743))
        addCurl(&half, in: l, centre: Self.curls[1].centre, radius: Self.curls[1].radius,
                from: 0, sweep: Self.curls[1].sweep)

        half.move(to: l.p(566, 950))
        half.addCurve(to: l.p(425, 876), control1: l.p(500, 940), control2: l.p(437, 932))
        addCurl(&half, in: l, centre: Self.curls[2].centre, radius: Self.curls[2].radius,
                from: 0, sweep: Self.curls[2].sweep)

        var p = half
        p.addPath(half, transform: l.mirror)
        return p
    }
}

/// Her two front legs. They converge as they descend rather than splaying apart, which
/// is what the artwork does and what stops the pair reading as a pair of table legs.
struct LegTentacles: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var half = Path()

        half.move(to: l.p(594, 792))
        half.addCurve(to: l.p(604, 920), control1: l.p(596, 848), control2: l.p(601, 888))

        var p = half
        p.addPath(half, transform: l.mirror)
        return p
    }
}

/// The feet, as separate solid ovals.
///
/// They are not the leg stroke's own round cap. A cap is exactly as wide as the leg,
/// and the artwork's feet are a third wider again — flared, the way a weight-bearing
/// foot is. They are filled shapes rather than strokes, which is also why they cannot
/// live inside `LegTentacles`: that path is stroked, and stroking an ellipse draws a
/// ring.
struct OctopusFeet: Shape {
    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)
        var p = Path()
        p.addEllipse(in: l.oval(616, 950, 58, 54))
        p.addEllipse(in: l.oval(2 * OctopusDesign.axis - 616, 950, 58, 54))
        return p
    }
}

// MARK: - One colour

/// What the menu bar gets: the whole figure in one ink, with the linen and the eyes
/// cut out. Built by adding the solid pieces and subtracting the rest, rather than
/// by painting them in the background colour, because a template image has one tint
/// to give and anything painted over it would come back as more of the same tint.
struct OctopusSilhouette: Shape {
    var time: Double = 0
    var effort: Double = 0

    func path(in rect: CGRect) -> Path {
        let l = OctopusLayout(rect)

        // The combining is done on `CGPath`, not on `Path`. SwiftUI's own
        // `Path.union` and `Path.subtracting` are macOS 14 and this app runs on 13,
        // and the other 13-safe route — one combined path filled even-odd — is wrong
        // here: the eyes cross the headband, and a point inside two holes counts as
        // outside and would come back solid. CoreGraphics has known how to do this
        // since long before either. Non-zero winding, because none of these outlines
        // cross themselves.
        func union(_ a: CGPath, _ b: CGPath) -> CGPath {
            a.union(b, using: .winding)
        }
        func filled(_ shape: some Shape, _ transform: CGAffineTransform = .identity) -> CGPath {
            shape.path(in: rect).applying(transform).cgPath
        }

        let swing = rotationAbout(
            l.p(shoulderPoint.x, shoulderPoint.y),
            degrees: armSwing(1, time: time, effort: effort)
        )
        // The far arm is the near one reflected whole, swing included, which is why
        // the reflection is concatenated *after* the rotation rather than before.
        let turn = swing.concatenating(l.mirror)

        // The tentacles are *stroked*, not filled. They are open paths: filling one
        // closes it with a straight line from its last point back to its first, which
        // turns every arm into a thin sliver. `Path.strokedPath` is macOS 13, unlike
        // `Path.union`, and it has to be applied after the transform rather than
        // before — safe here only because the only transforms in play are the mirror
        // and the arm swing, and both are isometries.
        func stroked(_ shape: some Shape, width: CGFloat,
                     _ transform: CGAffineTransform = .identity) -> CGPath {
            shape.path(in: rect)
                .applying(transform)
                .strokedPath(StrokeStyle(lineWidth: width * l.scale,
                                         lineCap: .round, lineJoin: .round))
                .cgPath
        }

        var solid = stroked(SideTentacles(), width: OctopusMark.sideTentacleWidth)
        solid = union(solid, stroked(SideTentacles(), width: OctopusMark.sideTentacleWidth, l.mirror))
        solid = union(solid, stroked(LegTentacles(), width: OctopusMark.legWidth))
        solid = union(solid, filled(OctopusFeet()))

        solid = union(solid, filled(OctopusDress()))
        solid = union(solid, filled(OctopusHead()))
        solid = union(solid, filled(Headband()))
        solid = union(solid, filled(CapPuffs()))

        for transform in [swing, turn] {
            solid = union(solid, filled(Sleeve(), transform))
        }

        var holes = filled(OctopusEyes())
        holes = union(holes, filled(OctopusCollar()))
        holes = union(holes, filled(OctopusStraps()))
        holes = union(holes, filled(OctopusApron()))
        holes = union(holes, filled(OctopusButtons()))
        for transform in [swing, turn] {
            holes = union(holes, filled(Cuff(), transform))
        }

        return Path(solid.subtracting(holes, using: .winding))
    }
}

// MARK: - Scallops

/// One round scallop, from `start` to `end`, as a half-circle.
///
/// The bulge is always on the same side of travel — above the line when walked left
/// to right, below it when walked right to left — which is why the apron is built
/// right to left and the collar left to right. Getting that backwards is the whole
/// of the difference between a frill and a row of teeth.
func addBump(_ path: inout Path, from start: CGPoint, to end: CGPoint) {
    let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let radius = hypot(end.x - start.x, end.y - start.y) / 2
    guard radius > 0.01 else {
        path.addLine(to: end)
        return
    }
    let theta = atan2(start.y - midpoint.y, start.x - midpoint.x)
    // 4/3 is the handle length that makes one cubic match a quarter circle; the
    // scallop is a half circle, so one cubic spans it and both handles point the
    // same way round.
    let handle = CGPoint(x: -sin(theta) * radius * 4 / 3, y: cos(theta) * radius * 4 / 3)
    path.addCurve(
        to: end,
        control1: CGPoint(x: start.x + handle.x, y: start.y + handle.y),
        control2: CGPoint(x: end.x + handle.x, y: end.y + handle.y)
    )
}

/// A row of equal scallops along a straight line.
func addScallops(_ path: inout Path, from start: CGPoint, to end: CGPoint, count: Int) {
    guard count > 0 else {
        path.addLine(to: end)
        return
    }
    for step in 1...count {
        let t = CGFloat(step) / CGFloat(count)
        let previous = CGFloat(step - 1) / CGFloat(count)
        addBump(
            &path,
            from: CGPoint(
                x: start.x + (end.x - start.x) * previous,
                y: start.y + (end.y - start.y) * previous
            ),
            to: CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        )
    }
}

// MARK: - The moving one

/// Her, alive — when someone is there to see it.
///
/// The mark breathes, and a breathing mark means a `TimelineView`, which means the
/// whole body is evaluated and laid out twenty times a second. On a window nobody
/// is looking at that is not atmosphere, it is a fan. So the breathing is spent
/// from `MotionBudget`: while the app is active or the menu bar panel is open she
/// moves as before, and the rest of the time she is one still frame — the same
/// drawing at rest, with no clock behind it and no work in it.
///
/// This is also why she is still while `working == false` on a screen nobody is
/// looking at: the effort only changes how hard she breathes, never whether the
/// drawing is correct.
struct WorkingOctopus: View {
    var size: CGFloat
    var working: Bool = true

    @ObservedObject private var budget = MotionBudget.shared
    @State private var onScreen = false

    var body: some View {
        Group {
            if budget.isTicking && onScreen {
                TimelineView(.periodic(from: .now, by: working ? 1.0 / 12 : 1.0 / 8)) { context in
                    mark(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mark(at: 0)
            }
        }
        .frame(width: size, height: size)
        .tracksOnScreen($onScreen)
        .accessibilityLabel("The housekeeper, looking around")
    }

    private func mark(at time: Double) -> some View {
        OctopusMark(time: time, effort: working ? 1 : 0)
            .frame(width: size, height: size)
    }
}
