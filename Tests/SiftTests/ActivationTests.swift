import AppKit
import Foundation
import Testing
@testable import Sift

/// A button is pressed as well as clicked, and the two arrive carrying
/// different things (A-7, D-367).
///
/// The first assertion here would not have failed before the fix, it would
/// have *crashed the test process*: `NSEvent.clickCount` raises an
/// Objective-C exception on a key event, and one raised under Swift cannot be
/// caught. That is the whole finding, and it is why this file reads the
/// event's type first.
@Suite struct ActivationTests {
    private func key() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: " ", charactersIgnoringModifiers: " ",
                         isARepeat: false, keyCode: 49)!
    }

    private func mouse(clicks: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil,
                           eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    @Test func aKeyEventIsAPressAndIsNeverAskedForACount() {
        #expect(Activation.of(key()) == .press)
    }

    @Test func noEventAtAllIsAPressToo() {
        #expect(Activation.of(nil) == .press)
    }

    @Test func aClickCarriesTheCountAppKitWorkedOut() {
        #expect(Activation.of(mouse(clicks: 1)) == .click(count: 1))
        #expect(Activation.of(mouse(clicks: 2)) == .click(count: 2))
    }

    /// The rule the folder tile branches on. A press asks for the control's
    /// own verb, because somebody who reached it with a screen reader has
    /// already done the part a first click is for. The photo cell reads the
    /// count directly instead, a press there meaning what one click means.
    @Test func aPressAndASecondClickBothAskForTheVerb() {
        #expect(Activation.press.wantsThePrimaryAction)
        #expect(Activation.click(count: 2).wantsThePrimaryAction)
        #expect(!Activation.click(count: 1).wantsThePrimaryAction)
    }

    /// ⌘ held on the click that opens asks for the folder somewhere else,
    /// which is a new tab (D-370). Asked of the event the click carried, so a
    /// modifier pressed or let go between the click and the action changes
    /// nothing.
    @Test func commandHeldOnTheClickAsksForASecondPlace() {
        #expect(Activation.wantsASecondPlace(mouse(clicks: 2, flags: .command)))
        #expect(!Activation.wantsASecondPlace(mouse(clicks: 2)))
    }

    /// A key event is never asked, for the reason the whole file exists: only
    /// `type` is answerable on every event, and a press has no pointer behind
    /// it to have held anything.
    @Test func aPressNeverAsksForASecondPlace() {
        #expect(!Activation.wantsASecondPlace(key()))
        #expect(!Activation.wantsASecondPlace(nil))
    }

    /// The durable half. A view that asks an event how many clicks it carries
    /// has the bug again, wherever it is written, so the question belongs in
    /// one file and the test says which.
    @Test func nothingOutsideActivationReadsAClickCount() {
        let sift = Repo.at("Sift")
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sift, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent != "Activation.swift",
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (i, raw) in text.components(separatedBy: "\n").enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                // `.clickCount` is the read. `clickCount:` is the argument
                // label on `NSEvent.mouseEvent`, which builds one rather than
                // interrogating one.
                guard line.contains(".clickCount"), !line.hasPrefix("//"), !line.hasPrefix("///") else { continue }
                offenders.append("\(url.lastPathComponent):\(i + 1) \(line)")
            }
        }
        #expect(offenders.isEmpty, """
            `NSEvent.clickCount` raises on anything that is not a mouse event, and a \
            button's action runs for a press as well as a click. Ask `Activation` instead:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
