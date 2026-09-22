import CoreGraphics
import Foundation
import Vision

/// One face Vision found, in normalized coordinates with the origin at the top
/// left, which is the convention every rect in this app uses and the opposite
/// of the one Vision returns.
struct Face: Identifiable, Hashable, Sendable {
    let id: Int
    /// The face itself.
    let bounds: CGRect
    /// The face with room around it, which is what you actually want to look
    /// at: an expression is the eyes, the mouth and the space between them.
    let framed: CGRect
    /// Nil when the landmarks were not readable. True is advisory and never
    /// written to the file (D-99).
    let eyesClosed: Bool?
}

/// Faces, and whether their eyes are open, from Apple's Vision framework
/// (D-99). Vision is part of the OS, so this adds no dependency and breaks no
/// rule; it is also the only thing in the app that can be wrong about a
/// photograph, which is why nothing it says is ever written to a file.
enum FaceReader {
    /// Up to this many faces are reported. A group shot's back row is not what
    /// anybody is checking for a blink.
    static let maxFaces = 6

    /// Below this ratio of eye height to eye width, the eye is called closed.
    /// Measured against open eyes across a range of faces; a blink collapses
    /// the ratio by roughly half, so the threshold sits well under both.
    private static let closedRatio: CGFloat = 0.17

    /// How much wider than the face itself a close-up is drawn.
    private static let framing: CGFloat = 1.45

    static func faces(in image: CGImage) -> [Face] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }
        let observations = (request.results ?? [])
            .sorted { $0.boundingBox.width > $1.boundingBox.width }
            .prefix(maxFaces)
        return observations.enumerated().map { i, face in
            Face(id: i,
                 bounds: flipped(face.boundingBox),
                 framed: framed(flipped(face.boundingBox)),
                 eyesClosed: closed(face))
        }
    }

    /// Vision's origin is bottom left; everything else here is top left.
    private static func flipped(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    private static func framed(_ r: CGRect) -> CGRect {
        let w = min(1, r.width * framing), h = min(1, r.height * framing)
        let x = min(max(0, r.midX - w / 2), 1 - w)
        let y = min(max(0, r.midY - h / 2), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Both eyes, or neither: one closed eye is a wink, which is a decision
    /// rather than a mistake, and calling it a mistake would be the app having
    /// an opinion it has not earned.
    private static func closed(_ face: VNFaceObservation) -> Bool? {
        guard let landmarks = face.landmarks,
              let left = landmarks.leftEye, let right = landmarks.rightEye else { return nil }
        guard let l = openness(left), let r = openness(right) else { return nil }
        return l < closedRatio && r < closedRatio
    }

    /// Height over width of the eye's own outline. An open eye is roughly a
    /// third as tall as it is wide; a closed one is a line.
    private static func openness(_ eye: VNFaceLandmarkRegion2D) -> CGFloat? {
        let points = eye.normalizedPoints
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let width = maxX - minX
        guard width > 0 else { return nil }
        return (maxY - minY) / width
    }
}
