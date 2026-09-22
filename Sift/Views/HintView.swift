import SwiftUI

/// One sentence, the first time the thing it is about happens, and then never
/// again (D-66). The help overlay is a list you go and read; this is the one
/// line you needed at the moment you needed it.
///
/// Quieter than a toast on purpose: a toast reports something that happened and
/// carries the way back from it. A hint reports nothing. It is tertiary text on
/// the same pill, with no button on it but the one that makes it go away.
struct HintView: View {
    let hint: HintState
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            Text(hint.text)
                .textStyle(.readout)
            GlyphButton(shape: Glyph.Cross(),
                        label: "Dismiss", hint: "Dismiss", act: dismiss)
        }
        .padding(.leading, Tokens.Space.s16)
        .padding(.trailing, Tokens.Space.s8)
        .padding(.vertical, Tokens.Space.s8)
        .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .shadow(color: Tokens.Elevation.raised.color,
                radius: Tokens.Elevation.raised.radius,
                y: Tokens.Elevation.raised.y)
        .task(id: hint.id) {
            try? await Task.sleep(for: Tokens.Motion.hintDwell)
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hint.text)
    }
}
