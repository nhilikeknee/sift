import Foundation
import Testing

/// What the shipped bundle declares about itself.
///
/// `Info.plist` is not compiled, so nothing else in the suite reads it, and a
/// key that quietly goes missing is invisible until somebody hits the prompt it
/// was there to write. `NSNetworkVolumesUsageDescription` was missing for two
/// audits: D-260 added four of the five places photographs live and a NAS got
/// the bare system prompt (D-299).
@Suite struct BundleTests {
    private static let plist = Repo.at("Resources/Info.plist")

    private func declarations() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.plist)
        return try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }

    /// Every folder Sift asks macOS for says why, in Sift's own words. The
    /// prompt without one names the app and nothing else, which is the dialog
    /// people deny.
    @Test func everyProtectedPlaceAPhotographLivesHasItsOwnPrompt() throws {
        let plist = try declarations()
        for key in ["NSDesktopFolderUsageDescription",
                    "NSDocumentsFolderUsageDescription",
                    "NSDownloadsFolderUsageDescription",
                    "NSNetworkVolumesUsageDescription",
                    "NSRemovableVolumesUsageDescription"] {
            let text = plist[key] as? String
            #expect(text?.isEmpty == false,
                    "\(key) is missing, so that prompt arrives with no reason in it")
            // An empty string satisfies the key and says nothing, which is the
            // failure this test exists for rather than a missing key.
            #expect(text?.contains("Sift") == true,
                    "\(key) does not name the app: \(text ?? "nil")")
        }
    }

    /// The two that would be a finding if they appeared. Sift reads photo files
    /// off disk; it does not open the Photos library and it does not ask where
    /// the machine is, and a usage string is the first sign that something
    /// started to.
    @Test func theBundleAsksForNothingItHasNoBusinessWith() throws {
        let plist = try declarations()
        for key in ["NSPhotoLibraryUsageDescription",
                    "NSPhotoLibraryAddUsageDescription",
                    "NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription",
                    "NSCameraUsageDescription",
                    "NSMicrophoneUsageDescription",
                    "NSContactsUsageDescription"] {
            #expect(plist[key] == nil, "\(key) is declared, and nothing in Sift should need it")
        }
    }

    /// The version is three numbers, and the two keys agree.
    ///
    /// `dmg.sh` stamps both keys with the release tag, but only when it is
    /// given one: called with no argument it reads `CFBundleShortVersionString`
    /// for the disk image's filename instead. So a `0.1` here and a `v0.1.0`
    /// tag are two names for one build — `Sift-0.1.dmg` locally, `Sift-0.1.0.dmg`
    /// from the workflow — and the About box macOS builds out of this file
    /// disagrees with the release it came from. That is what this catches: the
    /// plist shipped `0.1` against a `CFBundleVersion` of `1` until the day
    /// before the repository went public.
    ///
    /// Three components rather than any non-empty string, because two is the
    /// shape that drifts: nothing about `0.1` looks wrong on its own.
    @Test func theVersionIsThreeNumbersAndBothKeysSayTheSameOne() throws {
        let plist = try declarations()
        let short = plist["CFBundleShortVersionString"] as? String ?? ""
        let build = plist["CFBundleVersion"] as? String ?? ""

        let parts = short.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) },
                "CFBundleShortVersionString is \(short.isEmpty ? "missing" : short), not three numbers")
        #expect(short == build,
                "the two version keys disagree: \(short) and \(build), so a local build and a release of the same commit name themselves differently")
    }

    /// No network code means no reason to soften the transport rules, and an
    /// `NSAppTransportSecurity` block would be the first thing a reader
    /// checking SECURITY.md's claim would find.
    @Test func theBundleDoesNotRelaxTransportSecurity() throws {
        #expect(try declarations()["NSAppTransportSecurity"] == nil,
                "an app with no network code is loosening its transport rules")
    }
}
