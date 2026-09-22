import Foundation
@testable import Sift

/// Runs `body` over a private pair of image caches (D-149).
///
/// `ImageCache.thumbnails` and `.fulls` are global, and swift-testing runs
/// suites in parallel in an order that changes between runs. A test that
/// asserts an entry is still there was really asserting that no other test
/// happened to be decoding at that moment. Bound here, the pair lives and dies
/// with this call's task tree, so the only writes it sees are this test's.
func withIsolatedCaches<T>(isolation: isolated (any Actor)? = #isolation,
                           _ body: () async throws -> T) async rethrows -> T {
    try await ImageCache.$caches.withValue(ImageCache.Pair(), operation: body, isolation: isolation)
}
