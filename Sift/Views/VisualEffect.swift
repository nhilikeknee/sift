import AppKit
import SwiftUI

/// The blur behind a panel.
///
/// SwiftUI's own `Material` blurs what is behind it *inside* the window, which
/// for a sidebar in a `VStack` is nothing at all — the desktop is behind the
/// window, not behind the view. `NSVisualEffectView` with `.behindWindow`
/// blending is the only thing that reaches it, and it is what every panel on
/// this platform is made of (D-117).
///
/// The material is the whole API on purpose: `.sidebar` and `.headerView` are
/// named for the two places they belong, and AppKit decides what they look like
/// in each theme, at each accent, and when the window is not key. A hand-mixed
/// translucency would be a fourth surface token that only matched the platform
/// on the day it was written.
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    /// Emphasized while the window is key, which is what makes an inactive
    /// window recede the way every other window on the desktop does.
    var emphasized = false
    /// What the blur reaches. `.behindWindow` is the desktop, which is what a
    /// panel at the window's edge wants. `.withinWindow` is whatever this view
    /// is drawn on top of inside the window, which is what a bar floating over
    /// a photograph wants (D-164).
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    /// Drawn dark whatever the app's theme is. For the one case where what is
    /// underneath is a photograph rather than app chrome: a material that
    /// follows the theme is a light bar over a bright frame in light mode and a
    /// mid-gray one in dark, and the text on it goes with it (D-58, D-120).
    var alwaysDark = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.isEmphasized = emphasized
        view.blendingMode = blending
        view.appearance = alwaysDark ? NSAppearance(named: .darkAqua) : nil
    }
}

extension View {
    /// A panel's ground: the blur, with the flat tone behind it for the moments
    /// the blur cannot be drawn.
    func panelBackground(_ material: NSVisualEffectView.Material) -> some View {
        background {
            Tokens.Surface.chrome
            VisualEffect(material: material)
        }
    }
}
