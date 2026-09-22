import Testing
import Foundation
import AppKit
@testable import Sift

/// The guess must not queue in front of the ask (D-217).
///
/// An actor runs one call at a time. With one `ImageLoader`, a cursor move put
/// seven full-size decodes ahead of every thumbnail the grid then wanted, and a
/// thumbnail that takes 9ms took 482ms. Both halves of the fix are asserted
/// here, and neither assertion is a stopwatch: a timing test on a shared
/// machine fails for reasons that are nobody's bug.
@Suite struct DecodeQueueTests {
    /// A photograph big enough that decoding it is not free.
    private func jpeg(at url: URL, edge: Int = 4000) throws {
        let ctx = CGContext(data: nil, width: edge, height: edge * 2 / 3, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: edge, height: edge * 2 / 3))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: url)
    }

    /// The half that made the queue drainable.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` is one C call that runs to
    /// completion, so cancellation can only be honoured *before* it starts. It
    /// used to be checked after the `await` returned, which meant a cancelled
    /// prefetch decoded a 24MP frame and threw it away.
    @Test func aCancelledDecodeNeverReachesImageIO() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("big.jpg")
        try jpeg(at: url)

        // Cancelled before it ever runs, so the guard is the only thing that
        // can be under test: there is no race with a decode that started.
        let task = Task { await ImageLoader.ahead.decode(url, maxPixels: nil) }
        task.cancel()
        #expect(await task.value == nil,
                "a cancelled decode still went to ImageIO and came back with pixels")

        // And the same call without cancellation still works, so the guard is
        // not simply breaking the loader.
        #expect(await ImageLoader.ahead.decode(url, maxPixels: nil) != nil)
    }

    /// The half that separated the queues.
    ///
    /// A source scan, because what is being asserted is which loader a call
    /// site reaches for, and that is a fact about the file. The rule: the
    /// prefetcher is the only thing allowed to touch `ahead`, and it is not
    /// allowed to touch `shared` — one call site on the wrong one puts the
    /// guess back in front of the ask.
    @Test func onlyTheGuessUsesTheSpeculativeLoader() throws {
        let root = Repo.at("Sift")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []

        var aheadUsers: [String] = []
        var prefetcherUsesShared = false
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            if text.contains("ImageLoader.ahead") { aheadUsers.append(name) }
            if name == "Prefetcher.swift", text.contains("ImageLoader.shared") {
                prefetcherUsesShared = true
            }
        }
        #expect(aheadUsers == ["Prefetcher.swift"],
                "the speculative loader is for the prefetcher alone: \(aheadUsers)")
        #expect(!prefetcherUsesShared,
                "the prefetcher reaches the loader the reader is waiting on")
    }

    /// Both exist and are genuinely separate. Two `let`s that happened to be
    /// the same instance would pass the scan above and fix nothing.
    @Test func theTwoLoadersAreNotTheSameActor() {
        #expect(ImageLoader.shared !== ImageLoader.ahead)
    }
}
