import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

/// Ten numbers that say how a photograph should look, and nothing else.
///
/// A recipe rather than an edit: it describes what to do to pixels, and nothing
/// on disk changes until somebody presses Return (D-161). An overwrite leaves
/// one of these on the photograph it wrote, so the panel can reopen where it
/// was left and develop the kept original again (D-165). That is the whole
/// extent of developing in this app, and the PRD's non-goal is still the
/// boundary: no curves, no masks, no presets, one recipe per photograph and
/// never a stack. The ten are Lightroom's Basic panel, which is the vocabulary
/// anybody arriving here already has, less the knobs that change how a kept
/// frame looks rather than whether it is kept (D-230).
///
/// Every knob rests at 0 and runs to ±100, because a slider whose neutral is
/// its middle can be read at a glance and reset by eye. What each one means in
/// the filter underneath is `render`'s business and nowhere else's.
struct Adjustments: Equatable, Sendable, Codable {
    var exposure: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var warmth: Double = 0
    var tint: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0

    static let neutral = Adjustments()

    /// Written out rather than synthesised, so a recipe stored by a version
    /// with fewer knobs still reads back. The synthesised decoder throws on a
    /// missing key even where the property has a default, and the recipe lives
    /// in an extended attribute on a photograph that may have been adjusted
    /// weeks ago: dropping it would put the sliders at zero over pixels that
    /// already carry the edit, which is the one thing D-165 exists to prevent.
    /// A knob added later is absent, which is the same as 0.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Knob.self)
        for knob in Knob.allCases {
            self[knob] = try c.decodeIfPresent(Double.self, forKey: knob) ?? 0
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Knob.self)
        for knob in Knob.allCases { try c.encode(self[knob], forKey: knob) }
    }

    init() {}

    /// A recipe from the knobs that are set, so a caller naming three of them
    /// does not have to name the other seven. It replaces the memberwise
    /// initializer, which the explicit `init(from:)` above takes away, and is
    /// the better shape anyway: an eleventh knob leaves every call site alone.
    init(_ values: [Knob: Double]) {
        for (knob, value) in values { self[knob] = value }
    }

    /// Nothing to do, which is both the empty state and the fast path: a
    /// neutral recipe hands the image straight back rather than running six
    /// filters that cancel out.
    var isNeutral: Bool { self == .neutral }

    /// One knob, as data, so the panel is built from this list rather than
    /// from ten hand-written rows. An eleventh slider is a case here and a line
    /// in the design document, not a view edit. It is also the recipe's `CodingKey`, so
    /// adding the case is what puts the number on the file as well.
    ///
    /// The order is the panel's and Lightroom's: light first, then color,
    /// each group running from the knob most often reached for to the knob
    /// least. It is not the order `render` applies them in, which is the
    /// darkroom's and is `render`'s own business.
    enum Knob: String, CaseIterable, Identifiable, Sendable, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks
        case warmth, tint, vibrance, saturation

        var id: String { rawValue }

        /// Which block of the panel it sits in. Ten sliders in one column is a
        /// wall; the two names are the ones Lightroom uses, so somebody who
        /// has used one knows where to look for the other nine (D-230).
        enum Group: String, CaseIterable, Identifiable, Sendable {
            case light = "Light", color = "Color"
            var id: String { rawValue }
            var knobs: [Knob] { Knob.allCases.filter { $0.group == self } }
        }

        var group: Group {
            switch self {
            case .exposure, .contrast, .highlights, .shadows, .whites, .blacks: .light
            case .warmth, .tint, .vibrance, .saturation: .color
            }
        }

        var label: String {
            switch self {
            case .exposure: "Exposure"
            case .contrast: "Contrast"
            case .highlights: "Highlights"
            case .shadows: "Shadows"
            case .whites: "Whites"
            case .blacks: "Blacks"
            case .warmth: "Warmth"
            case .tint: "Tint"
            case .vibrance: "Vibrance"
            case .saturation: "Saturation"
            }
        }

        /// What moving it does, in the words somebody judging a frame would
        /// use. It is the slider's tooltip and its accessibility label.
        ///
        /// The four pairs that sound alike each say what the other one is not:
        /// highlights and whites both act on the bright end, shadows and
        /// blacks both on the dark end, and warmth and tint are two axes of
        /// one white balance. A hint that only said "the bright end" twice
        /// would leave the reader to find out by dragging.
        var hint: String {
            switch self {
            case .exposure: "The whole frame brighter or darker, in stops"
            case .contrast: "Push the ends apart, or bring them together"
            case .highlights: "Recover a blown sky, or open the bright end up"
            case .shadows: "Lift what is buried, or let it go black"
            case .whites: "Where white starts. Blow the brightest out, or pull them back off the edge"
            case .blacks: "Where black starts. Crush the darkest to nothing, or lift them off it"
            case .warmth: "Warmer toward orange, cooler toward blue"
            case .tint: "The other half of the white balance: toward magenta, or toward green"
            case .vibrance: "Color, but only where there is little of it. Skin stays where it is"
            case .saturation: "Color, everywhere at once, up to twice as much or all the way out"
            }
        }

        /// The far ends of the slider. Symmetric on purpose: a control that
        /// can only go one way reads as broken when it is already at 0.
        static let range: ClosedRange<Double> = -100...100
    }

    subscript(knob: Knob) -> Double {
        get {
            switch knob {
            case .exposure: exposure
            case .contrast: contrast
            case .highlights: highlights
            case .shadows: shadows
            case .whites: whites
            case .blacks: blacks
            case .warmth: warmth
            case .tint: tint
            case .vibrance: vibrance
            case .saturation: saturation
            }
        }
        set {
            let v = min(max(newValue, Knob.range.lowerBound), Knob.range.upperBound)
            switch knob {
            case .exposure: exposure = v
            case .contrast: contrast = v
            case .highlights: highlights = v
            case .shadows: shadows = v
            case .whites: whites = v
            case .blacks: blacks = v
            case .warmth: warmth = v
            case .tint: tint = v
            case .vibrance: vibrance = v
            case .saturation: saturation = v
            }
        }
    }

    /// What is set, in the order the panel lists it. The readout over the
    /// photograph says this, so a frame being previewed says what is being done
    /// to it without the panel having to be read.
    var summary: String {
        let set = Knob.allCases.filter { self[$0] != 0 }
        guard !set.isEmpty else { return "No adjustment" }
        return set.map { "\($0.label) \(Self.readout(self[$0]))" }.joined(separator: "  ·  ")
    }

    /// A signed whole number. The sign is the point: it says which way this
    /// knob has been moved without anybody having to remember where its middle
    /// was.
    static func readout(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%+.0f", value)
    }

    /// Everything the render depends on, as a string, so a cached result is
    /// keyed by what made it rather than by which file it came from. Two
    /// photographs under the same recipe are two keys, and one photograph
    /// under two recipes is two keys as well.
    var key: String {
        Knob.allCases.map { String(format: "%.1f", self[$0]) }.joined(separator: ",")
    }

    // MARK: rendering

    /// One context for the whole app. `CIContext` is documented as safe to use
    /// from several threads and is expensive to build, so building one per
    /// slider tick would cost more than the render it is for.
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The recipe applied. Nil only when Core Image refuses the render, which
    /// the caller shows as the photograph it already had rather than as a blank
    /// frame.
    ///
    /// The order is the one a darkroom would use: set the exposure, shape the
    /// tones, then color. Doing saturation before exposure would be
    /// saturating a frame that is about to change brightness. It is not the
    /// panel's order and does not have to be — the panel lists the knobs the
    /// way somebody looks for them, and six filters run here in the order the
    /// pixels need.
    func render(_ image: CGImage) -> CGImage? {
        guard !isNeutral else { return image }
        var ci = CIImage(cgImage: image)

        if exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = ci
            // ±100 is ±2 stops, which is as far as a JPEG has anything left to
            // recover at either end.
            f.ev = Float(exposure / 50)
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        // Two curves rather than four knobs on one, which is the whole of
        // what keeps this monotone. A tone curve is a spline through its five
        // points, so a segment that is nearly flat next to one that is steep
        // dips below its own left-hand point on the way up: blacks all the way
        // up against shadows all the way down put (0, 0.10) beside (0.25,
        // 0.12) and cost eight levels of inversion at the bottom of the frame.
        // Clamping the two points apart does not fix it — the dip is inside
        // the segment, not at its ends — and no separation that leaves the
        // knobs their travel is wide enough.
        //
        // Composing two monotone functions is monotone, whatever each one is
        // doing, so each pair gets its own curve and neither has to know about
        // the other. Measured across every combination of the four at nine
        // positions each, over a 256-step ramp, the worst step backwards is
        // one level, which is the 8-bit quantization and not an inversion.
        // `noSettingOfTheFourToneKnobsInvertsTheFrame` is that measurement.

        if highlights != 0 || shadows != 0 {
            // The inside of the range. A tone curve rather than
            // `CIHighlightShadowAdjust`, because that filter's highlight input
            // only darkens: 1.0 is no change and 0 is full recovery, so there
            // is no way to open the bright end up. ±0.2 at the quarter tones
            // can never reach the middle point.
            let f = CIFilter.toneCurve()
            f.inputImage = ci
            f.point0 = CGPoint(x: 0, y: 0)
            f.point1 = CGPoint(x: 0.25, y: 0.25 + shadows / 100 * 0.2)
            f.point2 = CGPoint(x: 0.5, y: 0.5)
            f.point3 = CGPoint(x: 0.75, y: 0.75 + highlights / 100 * 0.2)
            f.point4 = CGPoint(x: 1, y: 1)
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        if whites != 0 || blacks != 0 {
            // The ends of the range. Only the endpoints move, and only in y:
            // past 1 or below 0 the render clips, which is what blowing a
            // highlight out or crushing a black to nothing means. The three
            // points between them stay put, so the midtone holds within two
            // levels at either extreme — sliding an endpoint sideways instead
            // was the first attempt and it dragged the midtone twenty levels
            // with it, because a spline re-bends through every knot when one
            // knot moves.
            //
            // ±0.15 at white and ±0.1 at black: black has less room above it
            // than white has below it, and a Blacks slider that lifted as far
            // as Whites drops would turn the bottom of every frame gray.
            let f = CIFilter.toneCurve()
            f.inputImage = ci
            f.point0 = CGPoint(x: 0, y: blacks / 100 * 0.1)
            f.point1 = CGPoint(x: 0.25, y: 0.25)
            f.point2 = CGPoint(x: 0.5, y: 0.5)
            f.point3 = CGPoint(x: 0.75, y: 0.75)
            f.point4 = CGPoint(x: 1, y: 1 + whites / 100 * 0.15)
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        if contrast != 0 || saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = ci
            // Contrast pivots on 1: ±100 is 0.5 to 1.5, which is the range
            // either side of neutral that a photograph survives.
            f.contrast = Float(1 + contrast / 200)
            // Saturation floors at 0 rather than at 0.5: -100 means gray, which
            // is a thing somebody asks a slider for. +100 is twice, which is as
            // far as it goes before skin stops being skin.
            f.saturation = Float(1 + saturation / 100)
            f.brightness = 0
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        if vibrance != 0 {
            // After `colorControls`, because it is the correction on top of
            // the flat one: saturation moves every pixel by the same factor
            // and this moves the ones that have least color to start with.
            // The two are separate knobs for the same reason Lightroom keeps
            // them separate — a frame pushed to +100 saturation has orange
            // faces, and the same frame at +100 vibrance does not.
            let f = CIFilter.vibrance()
            f.inputImage = ci
            f.amount = Float(vibrance / 100)
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        if warmth != 0 || tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = ci
            // The filter takes "the neutral this frame has" and "the neutral it
            // should have", and which of the two moves is not something the
            // documentation settles: rendering a gray patch both ways and
            // reading the bytes back is what settled it. Moving the *target*
            // down is what warms the pixels up. Doing it the other way round
            // came out at (120, 148, 193) — a blue patch under a slider
            // labeled Warmth. `AdjustTests` keeps the sign honest.
            //
            // Tint is the same filter's other axis and was settled the same
            // way: a negative target tint puts red and blue in and takes green
            // out, which is magenta, so +100 on a slider labeled Tint goes
            // toward magenta and -100 toward green. That is the direction
            // Lightroom's own Tint runs, which matters more than the sign of
            // the number underneath. 50 rather than 25 because tint moves a
            // gray patch about half as far per unit as temperature does.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: CGFloat(6500 - warmth * 25), y: CGFloat(-tint * 0.5))
            guard let out = f.outputImage else { return nil }
            ci = out
        }

        let frame = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // 16 bits out of a 16-bit source, for the reason D-21 reads the depth
        // at all: a depth-preserving decode followed by an 8-bit render is an
        // 8-bit file.
        let format: CIFormat = image.bitsPerComponent > 8 ? .RGBA16 : .RGBA8
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return Self.context.createCGImage(ci, from: frame, format: format, colorSpace: space)
    }
}
