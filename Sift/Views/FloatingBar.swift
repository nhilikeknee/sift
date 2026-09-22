import SwiftUI

/// A bar that floats over the photograph: the preview window's controls, and
/// the crop bar that replaces them while a box is being dragged (D-238).
///
/// One definition, because there are two of them now and the ground is the
/// part that must not drift. A blur rather than a fill, because this is the one
/// piece of chrome that genuinely floats over something (D-164).
/// `.withinWindow`, so it takes the photograph behind it rather than the
/// desktop behind the window, and dark whatever the theme is, because a
/// photograph has no theme: a material that followed the app came out mid-gray
/// over a white sky in dark mode and put 1.6:1 text on it.
struct FloatingBar<Content: View>: View {
    /// What a screen reader lands on.
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, Tokens.Space.s16)
            .padding(.vertical, Tokens.Space.s8)
            .background {
                ZStack {
                    VisualEffect(material: .hudWindow, blending: .withinWindow, alwaysDark: true)
                    // The blur is what it looks like; this is what makes it
                    // legible. A material takes its tone from whatever is under
                    // it, so over a bright frame the bar came out light gray and
                    // the text on it went with it — the same failure the
                    // theme-following material had, one step further along. The
                    // scrim is the measured answer the cell controls already
                    // use: at 70% the worst ground in the fixture gives 6.0:1,
                    // and at 55% it gave 3.1:1 (D-120, D-164).
                    Tokens.Surface.overPhoto
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            }
            // The ground is dark, so everything on it reads its dark tone: one
            // line instead of an on-photo variant of every control in the bar.
            .environment(\.colorScheme, .dark)
            .shadow(color: Tokens.Elevation.overlay.color,
                    radius: Tokens.Elevation.overlay.radius,
                    y: Tokens.Elevation.overlay.y)
            .padding(.bottom, Tokens.Space.s32)
            .padding(.horizontal, Tokens.Space.s16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
